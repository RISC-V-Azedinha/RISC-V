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
class Conv2D_Model(nn.Module):
    def __init__(self):
        super(Conv2D_Model, self).__init__()
        self.conv = nn.Conv2d(1, 4, kernel_size=3, stride=2, padding=0) 
        self.relu = nn.ReLU()
        self.flatten = nn.Flatten()
        self.fc = nn.Linear(13 * 13 * 4, 10)

    def forward(self, x):
        x = self.conv(x)  
        x = self.relu(x)
        x = x.permute(0, 2, 3, 1) # Formato da NPU (Channels-Last)
        x = self.flatten(x)
        return self.fc(x)

def treinar_e_extrair():
    print("--- FASE 1: TREINAMENTO (CONV2D AFINADA) ---")
    transform = transforms.Compose([
        transforms.RandomAffine(degrees=0, translate=(0.05, 0.05), shear=15),
        transforms.ToTensor()
    ])
    train_dataset = datasets.MNIST(root='./data', train=True, download=True, transform=transform)
    # Reduzimos o batch_size de 64 para 32. Isso faz a rede atualizar os pesos mais vezes por época!
    train_loader = DataLoader(train_dataset, batch_size=32, shuffle=True)
    
    model = Conv2D_Model()
    criterion = nn.CrossEntropyLoss()
    
    # Começamos com um LR levemente menor
    optimizer = optim.Adam(model.parameters(), lr=0.003)
    
    # O segredo: A cada 3 épocas, corta o tamanho do "passo" pela metade!
    scheduler = optim.lr_scheduler.StepLR(optimizer, step_size=3, gamma=0.5)

    epochs = 12 # Damos mais 7 épocas de fôlego para ela assentar os pesos
    for epoch in range(epochs):
        model.train()
        running_loss = 0.0
        for images, labels in train_loader:
            optimizer.zero_grad()
            loss = criterion(model(images), labels)
            loss.backward()
            optimizer.step()
            running_loss += loss.item()
            
        scheduler.step() # Atualiza o LR
        current_lr = scheduler.get_last_lr()[0]
        print(f"Época {epoch+1}/{epochs} - Loss: {running_loss/len(train_loader):.4f} - LR: {current_lr:.6f}")

    print("\n--- FASE 2: CALIBRAÇÃO INT8 (EVITANDO OVERFLOW NA FPGA) ---")
    model.eval()
    
    max_y1 = 0.0
    max_y2 = 0.0
    with torch.no_grad():
        images, _ = next(iter(train_loader))
        y1 = model.relu(model.conv(images))
        logits = model(images)
        max_y1 = y1.max().item()          
        max_y2 = logits.abs().max().item() 

    w_conv_f = model.conv.weight.detach().numpy().reshape(4, 9)
    b_conv_f = model.conv.bias.detach().numpy()
    w_fc_f = model.fc.weight.detach().numpy()
    b_fc_f = model.fc.bias.detach().numpy()

    print(f"[Calibração] Max Conv: {max_y1:.2f} | Max FC: {max_y2:.2f}")

    # MATEMÁTICA DE QUANTIZAÇÃO SEGURA
    scale_w1_max = 127.0 / np.max(np.abs(w_conv_f))
    scale_w1_safe = (120.0 * 256.0) / (max_y1 * 127.0) if max_y1 > 0 else scale_w1_max
    scale_w1 = min(scale_w1_max, scale_w1_safe)

    w_conv_i = np.round(w_conv_f * scale_w1).astype(np.int8)
    b_conv_i = np.round(b_conv_f * 127.0 * scale_w1).astype(np.int32)

    scale_y1 = (127.0 * scale_w1) / 256.0 

    scale_w2_max = 127.0 / np.max(np.abs(w_fc_f))
    scale_w2_safe = (120.0 * 256.0) / (max_y2 * scale_y1) if max_y2 > 0 else scale_w2_max
    scale_w2 = min(scale_w2_max, scale_w2_safe)

    w_fc_i = np.round(w_fc_f * scale_w2).astype(np.int8)
    b_fc_i = np.round(b_fc_f * scale_y1 * scale_w2).astype(np.int32)
    
    return w_conv_i, b_conv_i, w_fc_i, b_fc_i

def empacotar_pesos_dma(W_int8):
    out_features, in_features = W_int8.shape
    packed_array = []
    for chunk_start in range(0, out_features, 4):
        chunk_size = min(4, out_features - chunk_start)
        for k in range(in_features):
            w0 = int(W_int8[chunk_start + 0, k]) & 0xFF if chunk_size > 0 else 0
            w1 = int(W_int8[chunk_start + 1, k]) & 0xFF if chunk_size > 1 else 0
            w2 = int(W_int8[chunk_start + 2, k]) & 0xFF if chunk_size > 2 else 0
            w3 = int(W_int8[chunk_start + 3, k]) & 0xFF if chunk_size > 3 else 0
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

    def upload_modelo(self, w_conv, b_conv, w_fc, b_fc):
        print("\n--- FASE 3: UPLOAD DO MODELO (DMA) ---")
        w_conv_packed = empacotar_pesos_dma(w_conv)
        w_fc_packed = empacotar_pesos_dma(w_fc)
        
        self.ser.write(struct.pack('>B', 0xAA))
        for val in w_conv_packed: self.ser.write(struct.pack('>I', val & 0xFFFFFFFF))
        assert self.ser.read(1) == b'A'

        self.ser.write(struct.pack('>B', 0xBB))
        for val in b_conv: self.ser.write(struct.pack('>i', val))
        assert self.ser.read(1) == b'B'

        self.ser.write(struct.pack('>B', 0xCC))
        for val in w_fc_packed: self.ser.write(struct.pack('>I', val & 0xFFFFFFFF))
        assert self.ser.read(1) == b'C'

        b_fc_padded = np.pad(b_fc, (0, 12 - len(b_fc)), mode='constant')
        self.ser.write(struct.pack('>B', 0xDD))
        for val in b_fc_padded: self.ser.write(struct.pack('>i', val))
        assert self.ser.read(1) == b'D'
        print("Upload OK!")
        
    def inferir(self, image_int8):
        self.ser.write(struct.pack('>B', 0xFF))
        self.ser.write(image_int8.tobytes())
        res = self.ser.read(10)
        return struct.unpack('>10b', res)

    def inferir_lote_serial(self, imagens_int8):
        """ Classifica uma lista de imagens uma de cada vez (comando 0xFF,
        repetido): manda, espera a resposta, só então manda a próxima. Serve de
        baseline pra comparar com o modo pipelined (double buffering). """
        t0 = time.time()
        preds = [int(np.argmax(self.inferir(img))) for img in imagens_int8]
        return preds, time.time() - t0

    def inferir_lote_pipelined(self, imagens_int8):
        """ Comando 0xEE: envia todas as imagens em sequência, sem esperar a
        resposta de uma antes de mandar a próxima. O SoC sobrepõe a recepção
        da PRÓXIMA imagem (via UART) com a classificação da ATUAL na NPU —
        double buffering em nível de imagem, espelhando o ping-pong que já
        existe dentro da NPU para pesos/inputs. """
        n = len(imagens_int8)
        t0 = time.time()
        self.ser.write(struct.pack('>B H', 0xEE, n))
        for img in imagens_int8:
            self.ser.write(img.tobytes())

        preds = []
        for _ in range(n):
            res = self.ser.read(10)
            preds.append(int(np.argmax(struct.unpack('>10b', res))))
        return preds, time.time() - t0

    def close(self):
        self.ser.close()

def rodar_benchmark_lote(driver, n_imagens=30):
    """ Gera `n_imagens` imagens sintéticas (mesma faixa de valores que a GUI
    envia) e compara o tempo total do modo serial (0xFF repetido) contra o
    modo pipelined/double-buffered (0xEE), pra mostrar o ganho de sobrepor a
    recepção da próxima imagem com o cômputo da atual. """
    rng = np.random.default_rng(42)
    imagens = [np.clip(rng.integers(0, 128, size=784), 0, 127).astype(np.int8) for _ in range(n_imagens)]

    print(f"\n--- BENCHMARK DE LOTE ({n_imagens} imagens) ---")

    preds_serial, t_serial = driver.inferir_lote_serial(imagens)
    print(f"Serial (0xFF x{n_imagens})     : {t_serial*1000:8.1f} ms  ({t_serial*1000/n_imagens:.2f} ms/imagem)")

    preds_pipe, t_pipe = driver.inferir_lote_pipelined(imagens)
    print(f"Pipelined (0xEE, Double Buf) : {t_pipe*1000:8.1f} ms  ({t_pipe*1000/n_imagens:.2f} ms/imagem)")

    if preds_serial != preds_pipe:
        print("[AVISO] Predições divergiram entre o modo serial e o pipelined — verifique o firmware.")

    speedup = t_serial / t_pipe if t_pipe > 0 else 0
    print(f"Speedup: {speedup:.2f}x")
    print("-" * 48)

# ==============================================================================
# INTERFACE GRÁFICA TKINTER (Real-Time Inference)
# ==============================================================================
class EdgeAI_App:
    def __init__(self, driver):
        self.driver = driver
        self.janela = tk.Tk()
        self.janela.title("Edge AI: Conv2D no SoC RISC-V")
        
        self.canvas_size = 280
        self.imagem_virtual = Image.new("L", (self.canvas_size, self.canvas_size), color=0)
        self.draw = ImageDraw.Draw(self.imagem_virtual)
        self.modificado = False

        tk.Label(self.janela, text="Desenhe o dígito (O SoC usa Conv2D!):", font=("Consolas", 12)).pack(pady=5)

        self.cv = tk.Canvas(self.janela, width=self.canvas_size, height=self.canvas_size, bg="black")
        self.cv.pack(pady=10)
        self.cv.bind("<B1-Motion>", self.pintar)

        frame_botoes = tk.Frame(self.janela)
        frame_botoes.pack(pady=5)
        
        tk.Button(frame_botoes, text="Limpar Tela", command=self.limpar, font=("Consolas", 12), bg="#E53935", fg="white").pack(padx=10)

        self.lbl_resultado = tk.Label(self.janela, text="Aguardando desenho...", font=("Consolas", 14))
        self.lbl_resultado.pack(pady=10)

        self.loop_inferencia()

    def pintar(self, event):
        x1, y1, x2, y2 = (event.x - 12), (event.y - 12), (event.x + 12), (event.y + 12)
        self.cv.create_oval(x1, y1, x2, y2, fill="white", outline="white")
        self.draw.ellipse([x1, y1, x2, y2], fill=255)
        self.modificado = True

    def limpar(self):
        self.cv.delete("all")
        self.draw.rectangle([0, 0, self.canvas_size, self.canvas_size], fill=0)
        self.lbl_resultado.config(text="Aguardando desenho...", fg="black")
        self.modificado = False

    def executar(self):
        bbox = self.imagem_virtual.getbbox()
        if not bbox: return

        img_cropped = self.imagem_virtual.crop(bbox)
        width, height = img_cropped.size
        ratio = 20.0 / max(width, height)
        new_width, new_height = int(width * ratio), int(height * ratio)

        img_resized = img_cropped.resize((new_width, new_height), Image.Resampling.LANCZOS)
        img_28x28 = Image.new("L", (28, 28), color=0)
        img_28x28.paste(img_resized, ((28 - new_width) // 2, (28 - new_height) // 2))

        img_npu = np.clip(np.array(img_28x28).flatten() // 2, 0, 127).astype(np.int8)

        try:
            start_t = time.time()
            logits = self.driver.inferir(img_npu)
            latencia = (time.time() - start_t) * 1000
            predicao = np.argmax(logits)

            self.lbl_resultado.config(text=f"Predição SoC: {predicao}\nLatência (Conv2D): {latencia:.1f} ms", fg="green")
        except Exception as e:
            self.lbl_resultado.config(text=f"Erro de Conexão: {e}", fg="red")

    def loop_inferencia(self):
        if self.modificado:
            self.modificado = False 
            self.executar()
        self.janela.after(250, self.loop_inferencia)

    def iniciar(self):
        self.janela.protocol("WM_DELETE_WINDOW", self.on_fechar)
        self.janela.mainloop()
        
    def on_fechar(self):
        self.driver.close()
        self.janela.destroy()

if __name__ == "__main__":
    w_conv, b_conv, w_fc, b_fc = treinar_e_extrair()
    driver = NPUDriverEdge(SERIAL_PORT, BAUD_RATE)
    driver.upload_modelo(w_conv, b_conv, w_fc, b_fc)

    if "--benchmark" in sys.argv:
        rodar_benchmark_lote(driver)

    print("\n[INFO] Rede Conv2D armazenada no SoC com Sucesso. Abrindo Interface...")
    app = EdgeAI_App(driver)
    app.iniciar()