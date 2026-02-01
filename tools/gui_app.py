import tkinter as tk
from tkinter import ttk
import threading
import numpy as np
import serial
import struct
import time
from PIL import Image, ImageDraw, ImageOps, ImageFilter, ImageTk 
from sklearn.datasets import fetch_openml
from sklearn.linear_model import LogisticRegression
from sklearn.model_selection import train_test_split

# ==============================================================================
# CONFIGURAÇÃO
# ==============================================================================
SERIAL_PORT = 'COM6'
BAUD_RATE   = 921600
CANVAS_SIZE = 400
PEN_WIDTH   = 40  

# Cores
C_BG        = "#1e1e1e"
C_CANVAS    = "#000000"
C_PEN       = "#FFFFFF"
C_ACCENT    = "#00ff99" 
C_TEXT      = "#e0e0e0"
C_PANEL     = "#2d2d2d"

# ==============================================================================
# DRIVER NPU V3
# ==============================================================================
class NPUDriver:
    def __init__(self, port, baud):
        self.ser = serial.Serial(port, baud, timeout=1)
        time.sleep(2)
        self.ser.reset_input_buffer()

    def sync(self):
        self.ser.reset_input_buffer()
        for _ in range(5):
            self.ser.write(b'P')
            time.sleep(0.05)
            if self.ser.in_waiting and self.ser.read(1) == b'P': return True
        return False

    def configure(self, mult, shift, relu):
        self.ser.write(b'C')
        self.ser.write(struct.pack('<III', mult, shift, relu))
        self.ser.read(1)

    def upload_weights(self, weights_blob):
        flat_w = weights_blob.flatten().astype(np.uint8).view(np.uint32)
        self.ser.write(b'L')
        self.ser.write(struct.pack('<I', len(flat_w) * 4))
        self.ser.write(flat_w.tobytes())
        self.ser.read(1)

    def configure_tiling(self, num_tiles, k_dim, stride):
        self.ser.write(b'T')
        self.ser.write(struct.pack('<III', num_tiles, k_dim, stride))
        self.ser.read(1)

    def predict(self, input_vec, num_tiles):
        bc = np.repeat(input_vec[:, np.newaxis], 4, axis=1)
        packed = bc.flatten().astype(np.uint8).view(np.uint32)
        self.ser.write(b'I')
        self.ser.write(struct.pack('<I', len(packed)))
        self.ser.write(packed.tobytes())
        if self.ser.read(1) != b'K': return None

        self.ser.write(b'B')
        self.ser.write(struct.pack('<I', 0))

        payload_size = (4 * num_tiles) + 24
        data = self.ser.read(payload_size)
        if len(data) != payload_size: return None

        results = struct.unpack('<' + ('I' * num_tiles) + 'QQQ', data)[:num_tiles]
        scores = []
        for pack in results:
            for b in range(4):
                val = (pack >> (b*8)) & 0xFF
                if val > 127: val -= 256
                scores.append(val)
        return scores[:10]

    def close(self): self.ser.close()

# ==============================================================================
# PROCESSAMENTO VISUAL (A CHAVE DA ACURÁCIA)
# ==============================================================================
def smart_preprocess(pil_image):
    """
    Simula pipeline MNIST: Bbox Crop -> Resize -> Blur -> Center
    """
    # 1. Pega Bbox (Remove espaço vazio)
    bbox = pil_image.getbbox()
    if bbox is None: return None

    # 2. Recorta
    crop = pil_image.crop(bbox)
    
    # 3. Resize para 20x20 preservando aspecto
    w, h = crop.size
    target_size = 20
    
    if w > h:
        new_w = target_size
        new_h = int(h * (target_size / w))
    else:
        new_h = target_size
        new_w = int(w * (target_size / h))
        
    crop_resized = crop.resize((new_w, new_h), Image.Resampling.BILINEAR)
    
    # 4. Cola no centro de 28x28
    final_img = Image.new("L", (28, 28), 0)
    paste_x = (28 - new_w) // 2
    paste_y = (28 - new_h) // 2
    final_img.paste(crop_resized, (paste_x, paste_y))
    
    # 5. BLUR: Suaviza o traço duro digital para parecer lápis/tinta
    # Isso ajuda o modelo linear a generalizar melhor
    final_img = final_img.filter(ImageFilter.GaussianBlur(radius=1))
    
    return final_img

# ==============================================================================
# GUI APP
# ==============================================================================
class MagicBoardApp:
    def __init__(self, root):
        self.root = root
        self.root.title("RISC-V NPU | Digit Recognizer V3")
        self.root.geometry("850x600")
        self.root.configure(bg=C_BG)
        self.root.resizable(False, False)

        self.drawing = False
        self.needs_inference = False 
        self.last_x, self.last_y = None, None
        self.running = True
        self.hw_fps = 0
        self.top3_data = []
        self.debug_photo = None # Segura referencia da imagem tk

        self.status_var = tk.StringVar(value="Inicializando IA & FPGA...")
        self.setup_ui()
        threading.Thread(target=self.hw_init_thread, daemon=True).start()

    def setup_ui(self):
        main_frame = tk.Frame(self.root, bg=C_BG)
        main_frame.pack(fill=tk.BOTH, expand=True, padx=20, pady=20)

        # --- ESQUERDA: DESENHO ---
        left_panel = tk.Frame(main_frame, bg=C_BG)
        left_panel.pack(side=tk.LEFT, padx=10, fill=tk.Y)

        tk.Label(left_panel, text="Desenhe um dígito (0-9)", font=("Segoe UI", 12), bg=C_BG, fg=C_TEXT).pack(pady=(0, 5))

        self.canvas = tk.Canvas(left_panel, width=CANVAS_SIZE, height=CANVAS_SIZE, bg=C_CANVAS, 
                                highlightthickness=2, highlightbackground=C_ACCENT)
        self.canvas.pack()
        
        self.image = Image.new("L", (CANVAS_SIZE, CANVAS_SIZE), 0)
        self.draw = ImageDraw.Draw(self.image)

        btn_frame = tk.Frame(left_panel, bg=C_BG)
        btn_frame.pack(fill=tk.X, pady=15)
        
        self.btn_clear = tk.Button(btn_frame, text="LIMPAR LOUSA", command=self.clear_canvas, 
                        bg=C_PANEL, fg=C_ACCENT, font=("Segoe UI", 11, "bold"), 
                        relief=tk.FLAT, activebackground=C_ACCENT, activeforeground=C_BG)
        self.btn_clear.pack(fill=tk.X, ipady=5)

        self.canvas.bind("<Button-1>", self.start_draw)
        self.canvas.bind("<B1-Motion>", self.paint)
        self.canvas.bind("<ButtonRelease-1>", self.stop_draw)

        # --- DIREITA: RESULTADOS ---
        right_panel = tk.Frame(main_frame, bg=C_PANEL, width=300)
        right_panel.pack(side=tk.RIGHT, fill=tk.BOTH, expand=True, padx=10)
        right_panel.pack_propagate(False)

        # DEBUG VIEW (O QUE A NPU VÊ)
        tk.Label(right_panel, text="Visão da NPU (Input)", font=("Segoe UI", 9), bg=C_PANEL, fg="#888").pack(pady=(15, 2))
        self.lbl_debug_img = tk.Label(right_panel, bg="black", width=100, height=100, relief=tk.SUNKEN, borderwidth=1)
        self.lbl_debug_img.pack()

        # Score Principal
        tk.Label(right_panel, text="PREVISÃO", font=("Segoe UI", 10), bg=C_PANEL, fg="#888").pack(pady=(15, 0))
        self.lbl_pred = tk.Label(right_panel, text="-", font=("Segoe UI", 80, "bold"), bg=C_PANEL, fg=C_ACCENT)
        self.lbl_pred.pack()

        # Top 3
        tk.Label(right_panel, text="Confiança", font=("Segoe UI", 10, "bold"), bg=C_PANEL, fg=C_TEXT).pack(pady=(10, 5))
        self.top3_frame = tk.Frame(right_panel, bg=C_PANEL)
        self.top3_frame.pack(fill=tk.X, padx=20)
        
        self.bars = []
        for i in range(3):
            f = tk.Frame(self.top3_frame, bg=C_PANEL)
            f.pack(fill=tk.X, pady=4)
            lbl_digit = tk.Label(f, text=f"#", font=("Consolas", 14, "bold"), bg=C_PANEL, fg=C_TEXT, width=2)
            lbl_digit.pack(side=tk.LEFT)
            bar = ttk.Progressbar(f, orient=tk.HORIZONTAL, length=100, mode='determinate')
            bar.pack(side=tk.LEFT, fill=tk.X, expand=True, padx=10)
            self.bars.append({'digit': lbl_digit, 'bar': bar})

        self.lbl_status = tk.Label(right_panel, textvariable=self.status_var, font=("Consolas", 8), bg=C_PANEL, fg="#666")
        self.lbl_status.pack(side=tk.BOTTOM, pady=10)

    # --- DESENHO ---
    def start_draw(self, event):
        self.drawing = True
        self.last_x, self.last_y = event.x, event.y

    def paint(self, event):
        if self.drawing:
            x, y = event.x, event.y
            self.canvas.create_line((self.last_x, self.last_y, x, y), width=PEN_WIDTH, fill=C_PEN, capstyle=tk.ROUND, smooth=True)
            self.draw.line((self.last_x, self.last_y, x, y), fill=255, width=PEN_WIDTH)
            self.last_x, self.last_y = x, y
            self.needs_inference = True

    def stop_draw(self, event):
        self.drawing = False
        self.needs_inference = True

    def clear_canvas(self):
        self.canvas.delete("all")
        self.draw.rectangle((0, 0, CANVAS_SIZE, CANVAS_SIZE), fill=0)
        self.lbl_pred.config(text="-")
        self.lbl_debug_img.config(image='', bg='black') # Limpa debug
        self.status_var.set("Aguardando desenho...")
        self.needs_inference = False
        for b in self.bars:
            b['digit'].config(text="-")
            b['bar']['value'] = 0

    # --- HARDWARE THREAD ---
    def hw_init_thread(self):
        try:
            self.status_var.set("Treinando ML...")
            X, y = fetch_openml('mnist_784', version=1, return_X_y=True, as_frame=False)
            X = X / 255.0
            # Aumentando Dataset de treino para generalizar melhor
            X_train, _, y_train, _ = train_test_split(X, y, train_size=5000, stratify=y)
            
            clf = LogisticRegression(solver='lbfgs', max_iter=150)
            clf.fit(X_train, y_train)
            
            max_val = np.max(np.abs(clf.coef_))
            self.scale = 127.0 / max_val
            q_weights = np.round(clf.coef_ * self.scale).astype(np.int8)
            
            w_padded = np.vstack([q_weights, np.zeros((2, 784), dtype=np.int8)])
            batches_data = [w_padded[0:4], w_padded[4:8], w_padded[8:12]]
            blob = []
            for b in batches_data: blob.append(b.T.flatten())
            full_blob = np.concatenate(blob).astype(np.int8)

            self.status_var.set(f"Conectando {SERIAL_PORT}...")
            self.npu = NPUDriver(SERIAL_PORT, BAUD_RATE)
            if not self.npu.sync():
                self.status_var.set("Erro FPGA (Sync Fail)")
                return

            self.npu.configure(1, 12, 0)
            self.status_var.set("Enviando Pesos...")
            self.npu.upload_weights(full_blob)
            self.npu.configure_tiling(3, 784, 3136)

            self.status_var.set("PRONTO")
            self.hw_ready = True
            
            threading.Thread(target=self.inference_loop, daemon=True).start()

        except Exception as e:
            self.status_var.set(f"Erro: {str(e)[:20]}")
            print(e)

    def inference_loop(self):
        while self.running:
            if not getattr(self, 'hw_ready', False):
                time.sleep(0.5)
                continue

            if self.needs_inference:
                # 1. Processamento Inteligente (Blur + Crop)
                final_img = smart_preprocess(self.image)
                
                if final_img is None: 
                    self.needs_inference = False
                    continue

                # Prepara para display de debug (Zoom 4x para ver na GUI)
                debug_view = final_img.resize((100, 100), resample=Image.NEAREST)
                self.debug_photo_raw = ImageTk.PhotoImage(debug_view)

                # Prepara para NPU
                img_data = np.array(final_img, dtype=np.float32) / 255.0
                q_input = np.round(img_data.flatten() * 127).astype(np.int8)

                start = time.time()
                scores = self.npu.predict(q_input, 3)
                dt = time.time() - start

                if scores:
                    scored_list = []
                    for i, s in enumerate(scores):
                        scored_list.append((i, s))
                    scored_list.sort(key=lambda x: x[1], reverse=True)
                    
                    self.top3_data = scored_list[:3]
                    self.hw_time = dt * 1000
                    
                    self.root.after(0, self.update_display)
                
                self.needs_inference = False
            
            time.sleep(0.06) 

    def update_display(self):
        if not self.top3_data: return

        # Atualiza Imagem de Debug (Visão da NPU)
        self.lbl_debug_img.config(image=self.debug_photo_raw)
        self.lbl_debug_img.image = self.debug_photo_raw

        winner_digit, winner_score = self.top3_data[0]
        self.lbl_pred.config(text=str(winner_digit))
        
        max_ref = max(1, winner_score)
        
        for i, (digit, score) in enumerate(self.top3_data):
            ui = self.bars[i]
            ui['digit'].config(text=str(digit))
            pct = max(0, (score / max_ref) * 100)
            ui['bar']['value'] = pct
            
            if i == 0: ui['digit'].config(fg=C_ACCENT)
            else:      ui['digit'].config(fg=C_TEXT)

        self.lbl_status.config(text=f"NPU Latency: {self.hw_time:.1f}ms")

    def on_closing(self):
        self.running = False
        if getattr(self, 'npu', None): self.npu.close()
        self.root.destroy()

if __name__ == "__main__":
    root = tk.Tk()
    app = MagicBoardApp(root)
    root.protocol("WM_DELETE_WINDOW", app.on_closing)
    root.mainloop()