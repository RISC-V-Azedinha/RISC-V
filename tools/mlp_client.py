import numpy as np
import torch
import torch.nn as nn
import torch.optim as optim
from torchvision import datasets, transforms
from torch.utils.data import DataLoader
import tkinter as tk
from PIL import Image, ImageDraw
import serial
import struct
import time
import sys

# ==============================================================================
# CONFIGURAÇÃO DE HARDWARE
# ==============================================================================
SERIAL_PORT = '/dev/ttyUSB1'  # Verifique sua porta
BAUD_RATE   = 921600

# ==============================================================================
# PYTORCH MODEL & QUANTIZAÇÃO
# ==============================================================================
class MLP_Model(nn.Module):
    def __init__(self):
        super(MLP_Model, self).__init__()
        self.flatten = nn.Flatten()
        self.hidden_layer = nn.Linear(28 * 28, 128)
        self.relu = nn.ReLU()
        self.output_layer = nn.Linear(128, 10)

    def forward(self, x):
        x = self.flatten(x)
        x = self.hidden_layer(x)
        x = self.relu(x)
        return self.output_layer(x)

def quantize_tensor(tensor_float, target_dtype, max_val_int):
    max_abs = np.max(np.abs(tensor_float))
    scale = max_val_int / max_abs if max_abs > 0 else 1.0
    tensor_quant = np.round(tensor_float * scale)
    return np.clip(tensor_quant, -max_val_int, max_val_int).astype(target_dtype), scale

def treinar_e_extrair():
    print("--- FASE 1: TREINO RÁPIDO DO MODELO (PYTORCH) ---")
    transform = transforms.Compose([transforms.ToTensor()])
    train_dataset = datasets.MNIST(root='./data', train=True, download=True, transform=transform)
    train_loader = DataLoader(train_dataset, batch_size=32, shuffle=True)
    
    model = MLP_Model()
    criterion = nn.CrossEntropyLoss()
    optimizer = optim.Adam(model.parameters(), lr=0.002) # LR inicial levemente maior
    scheduler = optim.lr_scheduler.StepLR(optimizer, step_size=5, gamma=0.5) # Reduz o LR pela metade a cada 5 épocas

    epochs = 15 # Aumentado de 3 para 15
    for epoch in range(epochs):
        model.train()
        running_loss = 0.0
        for images, labels in train_loader:
            optimizer.zero_grad()
            loss = criterion(model(images), labels)
            loss.backward()
            optimizer.step()
            running_loss += loss.item()
            
        scheduler.step() # Atualiza o learning rate
        print(f"Época {epoch+1}/{epochs} - Loss: {running_loss/len(train_loader):.4f} - LR: {scheduler.get_last_lr()[0]:.5f}")

    print("\n--- FASE 2: QUANTIZAÇÃO INT8/INT32 ---")
    model.eval()
    with torch.no_grad():
        w1_float, b1_float = model.hidden_layer.weight.numpy(), model.hidden_layer.bias.numpy()
        w2_float, b2_float = model.output_layer.weight.numpy(), model.output_layer.bias.numpy()

    w1_int8, scale_w1 = quantize_tensor(w1_float, np.int8, 127)
    w2_int8, scale_w2 = quantize_tensor(w2_float, np.int8, 127)
    b1_int32 = np.round(b1_float * scale_w1 * 255.0).astype(np.int32)
    b2_int32 = np.round(b2_float * scale_w2 * 127.0).astype(np.int32)
    
    return w1_int8, b1_int32, w2_int8, b2_int32

def empacotar_pesos_dma(W_int8):
    """ Agrupa pesos das colunas do Array Sistólico em palavras de 32 bits """
    out_features, in_features = W_int8.shape
    packed_array = []
    
    for chunk_start in range(0, out_features, 4):
        chunk_size = min(4, out_features - chunk_start)
        for k in range(in_features):
            w0 = int(W_int8[chunk_start + 0, k]) & 0xFF if chunk_size > 0 else 0
            w1 = int(W_int8[chunk_start + 1, k]) & 0xFF if chunk_size > 1 else 0
            w2 = int(W_int8[chunk_start + 2, k]) & 0xFF if chunk_size > 2 else 0
            w3 = int(W_int8[chunk_start + 3, k]) & 0xFF if chunk_size > 3 else 0
            
            # FIX: Invertemos o empacotamento para w0 ficar no LSB [7:0]
            val = (w3 << 24) | (w2 << 16) | (w1 << 8) | w0
            packed_array.append(val)
    return packed_array

# ==============================================================================
# DRIVER UART (UPLOAD E COMUNICAÇÃO)
# ==============================================================================
class NPUDriverEdge:
    def __init__(self, port, baud):
        try:
            self.ser = serial.Serial(port, baud, timeout=2.0)
            self.ser.reset_input_buffer()
            print(f"[INFO] FPGA Conectada: {port} @ {baud} bps")
        except Exception as e:
            print(f"[ERRO CRÍTICO] Falha na Serial: {e}")
            sys.exit(1)

    def upload_modelo(self, w1, b1, w2, b2):
        print("\n--- FASE 3: UPLOAD DO MODELO PARA A RAM DO SOC (DMA) ---")
        
        # 1. Empacota
        w1_packed = empacotar_pesos_dma(w1)
        w2_packed = empacotar_pesos_dma(w2)
        
        # 2. Upload W1 (0xAA)
        print("Enviando W1 (100 KB)... ", end="", flush=True)
        self.ser.write(struct.pack('>B', 0xAA))
        for val in w1_packed: self.ser.write(struct.pack('>I', val & 0xFFFFFFFF))
        assert self.ser.read(1) == b'A'
        print("OK")

        # 3. Upload B1 (0xBB)
        print("Enviando B1 (512 Bytes)... ", end="", flush=True)
        self.ser.write(struct.pack('>B', 0xBB))
        for val in b1: self.ser.write(struct.pack('>i', val))
        assert self.ser.read(1) == b'B'
        print("OK")

        # 4. Upload W2 (0xCC)
        print("Enviando W2 (1.5 KB)... ", end="", flush=True)
        self.ser.write(struct.pack('>B', 0xCC))
        for val in w2_packed: self.ser.write(struct.pack('>I', val & 0xFFFFFFFF))
        assert self.ser.read(1) == b'C'
        print("OK")

        # 5. Upload B2 (0xDD) - Preenchido até múltiplos de 4 (12 posições)
        print("Enviando B2... ", end="", flush=True)
        b2_padded = np.pad(b2, (0, 12 - len(b2)), mode='constant')
        self.ser.write(struct.pack('>B', 0xDD))
        for val in b2_padded: self.ser.write(struct.pack('>i', val))
        assert self.ser.read(1) == b'D'
        print("OK")
        
    def inferir(self, image_int8):
        self.ser.write(struct.pack('>B', 0xFF))
        self.ser.write(image_int8.tobytes())
        res = self.ser.read(10)
        return struct.unpack('>10b', res) # 10 signed bytes

    def close(self): 
        self.ser.close()

# ==============================================================================
# INTERFACE GRÁFICA TKINTER
# ==============================================================================
# ==============================================================================
# INTERFACE GRÁFICA TKINTER (Real-Time Inference)
# ==============================================================================
class EdgeAI_App:
    def __init__(self, driver):
        self.driver = driver
        self.janela = tk.Tk()
        self.janela.title("Edge AI: Inferência SoC RISC-V + NPU")
        
        self.canvas_size = 280
        self.imagem_virtual = Image.new("L", (self.canvas_size, self.canvas_size), color=0)
        self.draw = ImageDraw.Draw(self.imagem_virtual)

        # Flag para controlar se a tela foi alterada desde a última inferência
        self.modificado = False

        tk.Label(self.janela, text="Desenhe o dígito (O SoC adivinha em tempo real!):", font=("Consolas", 12)).pack(pady=5)

        self.cv = tk.Canvas(self.janela, width=self.canvas_size, height=self.canvas_size, bg="black")
        self.cv.pack(pady=10)
        self.cv.bind("<B1-Motion>", self.pintar)

        frame_botoes = tk.Frame(self.janela)
        frame_botoes.pack(pady=5)
        
        # O botão de inferir manual foi removido para focar na experiência em tempo real,
        # mas mantivemos o botão de limpar.
        tk.Button(frame_botoes, text="Limpar Tela", command=self.limpar, font=("Consolas", 12), bg="#E53935", fg="white").pack(padx=10)

        self.lbl_resultado = tk.Label(self.janela, text="Aguardando desenho...", font=("Consolas", 14))
        self.lbl_resultado.pack(pady=10)

        # Inicia o loop de adivinhação em tempo real
        self.loop_inferencia()

    def pintar(self, event):
        x1, y1, x2, y2 = (event.x - 12), (event.y - 12), (event.x + 12), (event.y + 12)
        self.cv.create_oval(x1, y1, x2, y2, fill="white", outline="white")
        self.draw.ellipse([x1, y1, x2, y2], fill=255)
        
        # Sinaliza que há pixels novos para serem analisados
        self.modificado = True

    def limpar(self):
        self.cv.delete("all")
        self.draw.rectangle([0, 0, self.canvas_size, self.canvas_size], fill=0)
        self.lbl_resultado.config(text="Aguardando desenho...", fg="black")
        self.modificado = False

    def executar(self):
        bbox = self.imagem_virtual.getbbox()
        if not bbox: return

        # Pre-processamento Local
        img_cropped = self.imagem_virtual.crop(bbox)
        width, height = img_cropped.size
        ratio = 20.0 / max(width, height)
        new_width, new_height = int(width * ratio), int(height * ratio)

        img_resized = img_cropped.resize((new_width, new_height), Image.Resampling.LANCZOS)
        img_28x28 = Image.new("L", (28, 28), color=0)
        img_28x28.paste(img_resized, ((28 - new_width) // 2, (28 - new_height) // 2))

        img_npu = np.clip(np.array(img_28x28).flatten() // 2, 0, 127).astype(np.int8)

        # Envia apenas Entradas -> Recebe Saídas
        try:
            start_t = time.time()
            logits = self.driver.inferir(img_npu)
            latencia = (time.time() - start_t) * 1000
            predicao = np.argmax(logits)

            self.lbl_resultado.config(text=f"Predição SoC: {predicao}\nLatência (HIL): {latencia:.1f} ms", fg="green")
        except Exception as e:
            self.lbl_resultado.config(text=f"Erro de Conexão: {e}", fg="red")

    def loop_inferencia(self):
        """ Loop rodando em background usando o event loop do Tkinter """
        if self.modificado:
            # Reseta a flag ANTES de executar, para capturar desenhos feitos durante a latência
            self.modificado = False 
            self.executar()
            
        # Agenda a si mesmo para rodar novamente em 250 milissegundos (4 FPS)
        self.janela.after(250, self.loop_inferencia)

    def iniciar(self):
        self.janela.protocol("WM_DELETE_WINDOW", self.on_fechar)
        self.janela.mainloop()
        
    def on_fechar(self):
        self.driver.close()
        self.janela.destroy()

if __name__ == "__main__":
    w1, b1, w2, b2 = treinar_e_extrair()
    driver = NPUDriverEdge(SERIAL_PORT, BAUD_RATE)
    driver.upload_modelo(w1, b1, w2, b2)
    
    print("\n[INFO] Rede armazenada no SoC com Sucesso. Abrindo Interface...")
    app = EdgeAI_App(driver)
    app.iniciar()