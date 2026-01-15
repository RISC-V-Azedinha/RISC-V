import serial
import time
import struct
import numpy as np
import os
import urllib.request
from sklearn.model_selection import train_test_split

# Cores
RESET = "\033[0m"
GREEN = "\033[32m"
RED   = "\033[31m"
CYAN  = "\033[36m"

def load_mnist_robust():
    """
    Carrega o MNIST do arquivo local mnist.npz.
    Se não existir, baixa do Google Storage.
    """
    path = "mnist.npz"
    url = "https://storage.googleapis.com/tensorflow/tf-keras-datasets/mnist.npz"
    
    if not os.path.exists(path):
        print(f">>> Baixando MNIST de {url}...")
        try:
            urllib.request.urlretrieve(url, path)
            print(">>> Download concluído.")
        except Exception as e:
            print(f"Erro ao baixar: {e}")
            return None, None
    
    print(">>> Carregando MNIST do disco...")
    with np.load(path, allow_pickle=True) as f:
        x_train, y_train = f['x_train'], f['y_train']
        x_test, y_test = f['x_test'], f['y_test']
    
    X = np.concatenate([x_train, x_test])
    y = np.concatenate([y_train, y_test])
    
    # Flatten e Normalização
    X = X.reshape(-1, 784).astype(np.float32) / 255.0
    
    return X, y

def main():
    print(f"{CYAN}>>> MNIST NPU Validator (Offline Mode){RESET}")
    
    # 1. Carrega MNIST Robusto
    X, y = load_mnist_robust()
    if X is None: return

    # Split (Mesma semente do treino para garantir que o teste seja justo)
    # Usamos apenas 1000 amostras de teste para economizar tempo
    _, X_test, _, y_test = train_test_split(X, y, train_size=5000, test_size=1000, random_state=42)
    
    # Labels para int
    y_test = y_test.astype(int)
    
    # Quantização (Scale 4.0 - Tem que ser igual ao treino)
    SCALE = 4.0
    X_test_int = np.clip(np.round(X_test * SCALE), -128, 127).astype(int)

    # 2. Conexão
    try:
        ser = serial.Serial('COM6', 115200, timeout=5) 
        time.sleep(2)
        ser.reset_input_buffer()
        print("Conectado na COM6")
    except Exception as e:
        print(f"{RED}Erro Serial: {e}{RESET}"); return

    correct = 0
    total = 50 # Quantidade de imagens para testar
    
    print("-" * 50)
    print(f"{'ID':<4} | {'REAL':<6} | {'PRED':<6} | {'CONF'}")
    print("-" * 50)

    for i in range(total):
        img = X_test_int[i]
        label = y_test[i]
        
        # Envia Header + 784 bytes
        ser.write(struct.pack('B', 0xA5))
        ser.write(struct.pack(f'{784}b', *img))
        
        # Lê Resposta (Header + 10 scores)
        resp = ser.read(11)
        
        if len(resp) != 11 or resp[0] != 0x5A:
            print(f"{i:<4} | {RED}TIMEOUT/SYNC{RESET}")
            # Tenta recuperar sincronia
            ser.reset_input_buffer()
            continue
            
        scores = struct.unpack('10b', resp[1:])
        pred = np.argmax(scores)
        conf = scores[pred]
        
        if pred == label:
            correct += 1
            status_color = GREEN
        else:
            status_color = RED
            
        print(f"{status_color}{i+1:<4}{RESET} | {label:<6} | {pred:<6} | {conf}")

    acc = (correct / total) * 100
    print("-" * 50)
    print(f"Acurácia Final: {acc:.2f}%")
    ser.close()

if __name__ == "__main__":
    main()