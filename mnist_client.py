import serial
import time
import struct
import numpy as np
import sys
import matplotlib.pyplot as plt
from sklearn.datasets import fetch_openml
from sklearn.linear_model import LogisticRegression
from sklearn.model_selection import train_test_split
from sklearn.preprocessing import StandardScaler

# ==============================================================================
# CONFIGURAÇÃO
# ==============================================================================
SERIAL_PORT = 'COM6'  # Atualizado com sua porta
BAUD_RATE   = 115200
TIMEOUT     = 2

# MNIST Specs
IMG_H, IMG_W = 28, 28
INPUT_DIM    = IMG_H * IMG_W  # 784
NUM_CLASSES  = 10

# ==============================================================================
# DRIVER DA FPGA (Reutilizado e Simplificado)
# ==============================================================================
class NPUDriver:
    def __init__(self, port, baud):
        self.ser = serial.Serial(port, baud, timeout=TIMEOUT)
        self.ser.reset_input_buffer()
        print(f"[HW] Conectado a {port}")

    def close(self):
        self.ser.close()

    def sync(self):
        for _ in range(5):
            self.ser.write(b'P')
            if self.ser.read(1) == b'P': return True
            time.sleep(0.1)
        return False

    def send_layer(self, inputs, weights):
        """
        Envia Inputs e Pesos para a FPGA e retorna 4 resultados.
        Inputs: Array (K,)
        Weights: Array (4, K) - 4 filtros de tamanho K
        """
        # 1. Input Broadcasting (Fundamental para Outer Product)
        # Transforma (784,) -> (784, 4) repetindo as colunas
        inputs_broadcast = np.repeat(inputs[:, np.newaxis], 4, axis=1)
        
        flat_in = inputs_broadcast.flatten().astype(np.uint8)
        packed_in = flat_in.view(np.uint32)
        
        # 2. Pesos
        weights_t = weights.T 
        flat_w = weights_t.flatten().astype(np.uint8)
        packed_w = flat_w.view(np.uint32)

        # Envia Pesos
        self.ser.write(b'W')
        self.ser.write(struct.pack('<I', len(packed_w)))
        self.ser.write(packed_w.tobytes())
        if self.ser.read(1) != b'K': raise Exception("Erro envio Pesos")

        # Envia Input
        self.ser.write(b'I')
        self.ser.write(struct.pack('<I', len(packed_in)))
        self.ser.write(packed_in.tobytes())
        if self.ser.read(1) != b'K': raise Exception("Erro envio Input")

        # Executa
        self.ser.write(b'R')
        
        # --- FIX CRÍTICO ---
        # Lê apenas 4 bytes (1 uint32 packed) em vez de 16
        res_bytes = self.ser.read(4) 
        cyc_bytes = self.ser.read(8)
        
        if len(res_bytes) != 4:
            print("Erro de leitura serial (Timeout?)")
            return [0,0,0,0], 0

        # Desempacota: 'bbbb' = 4 signed bytes (int8)
        # Isso vai transformar 0xFF em -1 corretamente.
        results = struct.unpack('<bbbb', res_bytes) 
        
        cycles = struct.unpack('<Q', cyc_bytes)[0]
        
        return results, cycles

# ==============================================================================
# TREINAMENTO E QUANTIZAÇÃO
# ==============================================================================
def load_and_train_mnist():
    print("[AI] Baixando MNIST (pode demorar um pouco)...")
    X, y = fetch_openml('mnist_784', version=1, return_X_y=True, as_frame=False)
    
    # Normalização simples para treino (0-1)
    X = X / 255.0
    
    # Treino rápido (Usamos apenas 5000 amostras para ser rápido)
    print("[AI] Treinando Regressão Logística...")
    X_train, X_test, y_train, y_test = train_test_split(X, y, train_size=5000, test_size=100)
    
    clf = LogisticRegression(solver='lbfgs', max_iter=100)
    clf.fit(X_train, y_train)
    
    print(f"[AI] Acurácia no PC (Float): {clf.score(X_test, y_test)*100:.2f}%")
    return clf, X_test, y_test

def quantize_weights(coefs):
    """
    Converte pesos Float (sklearn) para Int8 (FPGA).
    Escala: -1.0..1.0 -> -127..127
    """
    # Encontra o valor máximo absoluto para escalar
    max_val = np.max(np.abs(coefs))
    scale = 127.0 / max_val
    
    # Quantiza
    q_coefs = np.round(coefs * scale).astype(np.int8)
    return q_coefs, scale

def quantize_input(image):
    """0.0..1.0 -> 0..127 (Assumindo unsigned input no hw, ou ajustamos para int8)"""
    # Se sua NPU usa input como int8 (com sinal), 0..127 é seguro.
    return np.round(image * 127).astype(np.int8) # Usando apenas parte positiva do int8

# ==============================================================================
# MAIN
# ==============================================================================
if __name__ == "__main__":
    # 1. Preparação da IA
    model, X_test, y_test = load_and_train_mnist()
    
    # Extrai pesos (10 classes x 784 features)
    weights_float = model.coef_ 
    q_weights, w_scale = quantize_weights(weights_float)
    
    print(f"[AI] Pesos Quantizados. Escala: {w_scale:.2f}")

    # 2. Conexão Hardware
    fpga = NPUDriver(SERIAL_PORT, BAUD_RATE)
    if not fpga.sync():
        print("[ERRO] Falha no Sync")
        sys.exit(1)

    # 3. Loop de Inferência Interativa
    print("\n=== Pressione ENTER para testar uma imagem (Ctrl+C para sair) ===")
    
    try:
        for i in range(len(X_test)):
            input("\nPróxima Imagem > ")
            
            # Pega uma imagem real
            img_float = X_test[i]
            label_real = y_test[i]
            
            # Prepara Input para FPGA
            img_q = quantize_input(img_float)
            
            # --- Execução Fatiada (Tiling) ---
            # A FPGA só processa 4 neurônios por vez. Precisamos de 3 passadas.
            # Passada 1: Classes 0, 1, 2, 3
            # Passada 2: Classes 4, 5, 6, 7
            # Passada 3: Classes 8, 9, (lixo), (lixo)
            
            final_scores = []
            total_cycles = 0
            
            # Agrupa pesos em blocos de 4
            weight_batches = [
                q_weights[0:4],  # 0-3
                q_weights[4:8],  # 4-7
                q_weights[8:10]  # 8-9 (precisa padding)
            ]
            
            # Padding no último batch para ter 4 filtros
            w_last = weight_batches[2]
            padding = np.zeros((2, 784), dtype=np.int8)
            w_last_padded = np.vstack([w_last, padding])
            weight_batches[2] = w_last_padded

            print(f"[FPGA] Processando...", end='')
            for batch_w in weight_batches:
                res, cyc = fpga.send_layer(img_q, batch_w)
                # O resultado da FPGA é Int32 acumulado. 
                # Precisamos converter para com sinal (se vier como uint32 do struct)
                # Mas nosso pack foi 'I' (unsigned). Se o acc for negativo, cuidado.
                # Para simplificar, assumimos ReLU ou valores positivos por enquanto,
                # ou convertemos manualmente:
                res_signed = [x if x < 0x80000000 else x - 0x100000000 for x in res]
                
                final_scores.extend(res_signed)
                total_cycles += cyc
                print(".", end='')
            
            # Remove o padding do último batch e pega só os 10 scores
            scores = final_scores[:10]
            prediction = np.argmax(scores)
            
            print(" Done!")
            print(f"      Real: {label_real} | Predito: {prediction}")
            print(f"      Ciclos Totais: {total_cycles} (~{total_cycles/100:.1f} us)")
            print(f"      Scores: {scores}")
            
            # Mostra a imagem
            plt.imshow(img_float.reshape(28,28), cmap='gray')
            plt.title(f"Real: {label_real} | FPGA: {prediction}\n({total_cycles} cycles)")
            plt.show(block=False)
            plt.pause(0.1)

    except KeyboardInterrupt:
        print("\nEncerrando...")
        fpga.close()