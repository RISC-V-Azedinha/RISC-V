import serial
import time
import struct
import numpy as np
import sys
import argparse
from datetime import datetime
import torch
import torch.nn as nn
import torch.optim as optim
from torchvision import datasets, transforms
from torch.utils.data import DataLoader

# ==============================================================================
# CONFIGURAÇÃO DE USUÁRIO
# ==============================================================================
parser = argparse.ArgumentParser(description='SoC Edge AI Benchmark')
parser.add_argument('-p', '--port', default='/dev/ttyUSB1', help='Porta Serial (Ex: /dev/ttyUSB1)')
parser.add_argument('-b', '--baud', type=int, default=921600, help='Baud Rate')
args = parser.parse_args()

SERIAL_PORT = args.port
BAUD_RATE   = args.baud

# ==============================================================================
# PYTORCH MODEL, TREINAMENTO E QUANTIZAÇÃO
# ==============================================================================
class MLP_Model(nn.Module):
    def __init__(self):
        super(MLP_Model, self).__init__()
        self.flatten = nn.Flatten()
        self.hidden_layer = nn.Linear(28 * 28, 128)
        self.relu = nn.ReLU()
        self.output_layer = nn.Linear(128, 10)

    def forward(self, x):
        return self.output_layer(self.relu(self.hidden_layer(self.flatten(x))))

def quantize_tensor(tensor_float, target_dtype, max_val_int):
    max_abs = np.max(np.abs(tensor_float))
    scale = max_val_int / max_abs if max_abs > 0 else 1.0
    tensor_quant = np.round(tensor_float * scale)
    return np.clip(tensor_quant, -max_val_int, max_val_int).astype(target_dtype), scale

def treinar_e_extrair():
    print(f"{Colors.CYAN}\n--- FASE 1: TREINAMENTO ROBUSTO (PYTORCH) ---{Colors.RESET}")
    transform = transforms.Compose([transforms.ToTensor()])
    train_dataset = datasets.MNIST(root='./data', train=True, download=True, transform=transform)
    test_dataset  = datasets.MNIST(root='./data', train=False, download=True, transform=transform)
    
    train_loader = DataLoader(train_dataset, batch_size=64, shuffle=True)
    test_loader  = DataLoader(test_dataset, batch_size=1, shuffle=False)
    
    model = MLP_Model()
    criterion = nn.CrossEntropyLoss()
    optimizer = optim.Adam(model.parameters(), lr=0.002)
    scheduler = optim.lr_scheduler.StepLR(optimizer, step_size=5, gamma=0.5)

    epochs = 15 # O treinamento criterioso está de volta!
    for epoch in range(epochs):
        model.train()
        running_loss = 0.0
        for images, labels in train_loader:
            optimizer.zero_grad()
            loss = criterion(model(images), labels)
            loss.backward()
            optimizer.step()
            running_loss += loss.item()
            
        scheduler.step()
        print(f"Época {epoch+1}/{epochs} - Loss: {running_loss/len(train_loader):.4f} - LR: {scheduler.get_last_lr()[0]:.5f}")

    print(f"{Colors.CYAN}\n--- FASE 2: QUANTIZAÇÃO DO MODELO (INT8) ---{Colors.RESET}")
    model.eval()
    with torch.no_grad():
        w1_float, b1_float = model.hidden_layer.weight.numpy(), model.hidden_layer.bias.numpy()
        w2_float, b2_float = model.output_layer.weight.numpy(), model.output_layer.bias.numpy()

    w1_int8, scale_w1 = quantize_tensor(w1_float, np.int8, 127)
    w2_int8, scale_w2 = quantize_tensor(w2_float, np.int8, 127)
    b1_int32 = np.round(b1_float * scale_w1 * 255.0).astype(np.int32)
    b2_int32 = np.round(b2_float * scale_w2 * 127.0).astype(np.int32)
    
    return w1_int8, b1_int32, w2_int8, b2_int32, test_loader

# ==============================================================================
# ESTÉTICA DO TERMINAL
# ==============================================================================
class Colors:
    RESET   = "\033[0m"
    BOLD    = "\033[1m"
    RED     = "\033[91m"
    GREEN   = "\033[92m"
    YELLOW  = "\033[93m"
    BLUE    = "\033[94m"
    CYAN    = "\033[96m"
    WHITE   = "\033[97m"

def get_time(): return datetime.now().strftime('%H:%M:%S')
def log_print(tag, c, msg): print(f"[{get_time()}] {c}[{tag}]{Colors.RESET}    {msg}")
def log_info(msg):    log_print("INFO", Colors.BLUE, msg)
def log_pass(msg):    log_print("PASS", Colors.GREEN, msg)
def log_fail(msg):    log_print("FAIL", Colors.RED, msg)

def print_banner():
    print(f"\n{Colors.CYAN}")
    print(f"        ███████╗ ██████╗    ███████╗██╗   ██╗███╗   ██╗████████╗")
    print(f"        ██╔════╝██╔════╝    ██╔════╝╚██╗ ██╔╝████╗  ██║╚══██╔══╝")
    print(f"        █████╗  ██║         ███████╗ ╚████╔╝ ██╔██╗ ██║   ██║   ")
    print(f"        ██╔══╝  ██║         ╚════██║  ╚██╔╝  ██║╚██╗██║   ██║   ")
    print(f"        ██║     ╚██████╗    ███████║   ██║   ██║ ╚████║   ██║   ")
    print(f"        ╚═╝      ╚═════╝    ╚══════╝   ╚═╝   ╚═╝  ╚═══╝   ╚═╝   ")
    print(f"             SYSTOLIC NPU (Edge AI SoC Benchmark)               ")
    print(f"{Colors.RESET}")

# ==============================================================================
# DRIVER UART (HIL)
# ==============================================================================
class NPUDriverEdge:
    def __init__(self, port, baud):
        try:
            self.ser = serial.Serial(port, baud, timeout=15.0) # Timeout longo para a CPU
            self.ser.reset_input_buffer()
            log_pass(f"Porta Serial aberta: {Colors.BOLD}{port}{Colors.RESET}")
            time.sleep(1)
        except Exception as e:
            log_fail(f"Erro Serial: {e}")
            sys.exit(1)

    def close(self): 
        self.ser.close()

    def empacotar_pesos_dma(self, W_int8):
        out_f, in_f = W_int8.shape
        packed = []
        for chunk_start in range(0, out_f, 4):
            c_size = min(4, out_f - chunk_start)
            for k in range(in_f):
                w0 = int(W_int8[chunk_start + 0, k]) & 0xFF if c_size > 0 else 0
                w1 = int(W_int8[chunk_start + 1, k]) & 0xFF if c_size > 1 else 0
                w2 = int(W_int8[chunk_start + 2, k]) & 0xFF if c_size > 2 else 0
                w3 = int(W_int8[chunk_start + 3, k]) & 0xFF if c_size > 3 else 0
                packed.append((w3 << 24) | (w2 << 16) | (w1 << 8) | w0)
        return packed

    def upload_modelo(self, w1, b1, w2, b2):
        w1_packed = self.empacotar_pesos_dma(w1)
        w2_packed = self.empacotar_pesos_dma(w2)
        
        self.ser.write(struct.pack('>B', 0xAA))
        for v in w1_packed: self.ser.write(struct.pack('>I', v & 0xFFFFFFFF))
        if self.ser.read(1) != b'A': raise Exception("Falha W1")
        log_pass("Pesos Camada 1 (W1) transferidos para a RAM.")

        self.ser.write(struct.pack('>B', 0xBB))
        for v in b1: self.ser.write(struct.pack('>i', v))
        if self.ser.read(1) != b'B': raise Exception("Falha B1")

        self.ser.write(struct.pack('>B', 0xCC))
        for v in w2_packed: self.ser.write(struct.pack('>I', v & 0xFFFFFFFF))
        if self.ser.read(1) != b'C': raise Exception("Falha W2")
        log_pass("Pesos Camada 2 (W2) transferidos para a RAM.")

        b2_padded = np.pad(b2, (0, 12 - len(b2)), mode='constant')
        self.ser.write(struct.pack('>B', 0xDD))
        for v in b2_padded: self.ser.write(struct.pack('>i', v))
        if self.ser.read(1) != b'D': raise Exception("Falha B2")

    def inferir(self, image_int8):
        self.ser.write(struct.pack('>B', 0xFF))
        self.ser.write(image_int8.tobytes())
        res = self.ser.read(10)
        if len(res) < 10: raise Exception("Timeout de Inferência!")
        return struct.unpack('>10b', res) 

    def rodar_benchmark(self):
        self.ser.write(struct.pack('>B', 0xEE))
        linha = self.ser.readline().decode('utf-8', errors='ignore').strip()
        if not linha: raise Exception("Timeout Severo da CPU RISC-V!")
        
        partes = linha.split(',')
        cpu_cyc = int(partes[0].split(':')[1])
        npu_cyc = int(partes[1].split(':')[1])
        return cpu_cyc, npu_cyc

# ==============================================================================
# SOFTWARE REFERENCE (BIT-EXACT MODEL)
# ==============================================================================
def sw_ref(inp, w1, b1, w2, b2):
    shift = 9
    # O bit de arredondamento é 2^(shift-1) conforme post_process.vhd
    round_bit = (1 << (shift - 1)) if shift > 0 else 0
    
    # Camada 1
    # Estágio 1 & 2: (Acc + Bias) * Mult
    acc1 = np.dot(w1.astype(np.int32), inp.astype(np.int32)) + b1
    # Estágio 3: Round & Shift
    acc1 = np.right_shift(acc1 + round_bit, shift)
    # Estágio 4: Zero Point (assumindo 0) + ReLU + Clamp
    acc1 = np.clip(acc1, 0, 127) 
    
    # Camada 2
    acc2 = np.dot(w2.astype(np.int32), acc1.astype(np.int32)) + b2
    acc2 = np.right_shift(acc2 + round_bit, shift)
    acc2 = np.clip(acc2, -128, 127) # Sem ReLU na saída
    
    return acc2.astype(np.int8)

# ==============================================================================
# MAIN
# ==============================================================================
if __name__ == "__main__":
    print_banner()

    # Treina o modelo real e recupera os DataLoaders para validação
    w1, b1, w2, b2, test_loader = treinar_e_extrair()
    
    print(f"{Colors.CYAN}\n--- FASE 3: AVALIAÇÃO DE HARDWARE (EDGE NPU) ---{Colors.RESET}")
    npu = NPUDriverEdge(SERIAL_PORT, BAUD_RATE)
    
    try:
        npu.upload_modelo(w1, b1, w2, b2)
        
        print(f"\n{Colors.WHITE}Configurações:{Colors.RESET}")
        run_cpu = input(f"{Colors.YELLOW}  Benchmark CPU RISC-V (Muito Lento)? [Y/n] {Colors.RESET}").lower() != 'n'
        val = input(f"{Colors.YELLOW}  Quantas amostras do MNIST avaliar? [Default=20]: {Colors.RESET}")
        num = int(val) if val else 20
        
        print(f"\n{Colors.YELLOW}  Iniciando Loop de Inferência HIL...{Colors.RESET}")
        print(f"\n{Colors.WHITE}{'='*95}")
        print(f" {'ID':<4} | {'LBL':<3} | {'NPU':<3} | {'SW':<3} | {'INTEGRITY':<11} | {'CPU (cyc)':<12} | {'NPU (cyc)':<10} | {'SPEEDUP'}")
        print(f"{'='*95}{Colors.RESET}")

        tot_cpu, tot_npu = 0, 0
        total_errors_bit = 0
        total_acertos_npu = 0
        
        test_iter = iter(test_loader)
        
        for i in range(num):
            image_tensor, label_tensor = next(test_iter)
            lbl = label_tensor.item()
            
            img_npu = np.clip(image_tensor.numpy().flatten() * 127.0, 0, 127).astype(np.int8)
            
            npu_logits = npu.inferir(img_npu)
            npu_pred = np.argmax(npu_logits)
            
            c_cpu, c_npu = 0, 0
            if run_cpu: c_cpu, c_npu = npu.rodar_benchmark()
            
            sw_logits = sw_ref(img_npu, w1, b1, w2, b2)
            sw_pred = np.argmax(sw_logits)
            
            match_bit = (list(npu_logits) == list(sw_logits))
            if not match_bit: total_errors_bit += 1
            if npu_pred == lbl: total_acertos_npu += 1
            
            status = f"{Colors.GREEN}BIT-EXACT{Colors.RESET}" if match_bit else f"{Colors.RED}MISMATCH{Colors.RESET}"
            npu_color = Colors.GREEN if npu_pred == lbl else Colors.RED
            npu_str = f"{npu_color}{npu_pred}{Colors.RESET}"
            sp_str = f"{c_cpu/c_npu:.1f}x" if c_npu > 0 and c_cpu > 0 else "-"
            c_cpu_s = f"{c_cpu}" if c_cpu > 0 else "-"
            
            tot_cpu += c_cpu
            tot_npu += c_npu
            
            print(f" {i:<4} | {lbl:<3} | {npu_str:<12} | {sw_pred:<3} | {status:<20} | {c_cpu_s:<12} | {c_npu:<10} | {Colors.CYAN}{sp_str}{Colors.RESET}")
            
            # ================================================================
            # BLOCO DE DEBUG (Dispara apenas quando há falha de Bit-Exact)
            # ================================================================
            if not match_bit:
                print(f"{Colors.YELLOW}      ↳ [DEBUG] LBL {lbl}{Colors.RESET}")
                
                # Imprime os Logits
                print(f"{Colors.YELLOW}      ↳ NPU Logits : {list(npu_logits)}{Colors.RESET}")
                print(f"{Colors.YELLOW}      ↳ SW  Logits : {list(sw_logits)}{Colors.RESET}")
                
                # Calcula a diferença exata para vermos o padrão do erro
                diff = [n - s for n, s in zip(npu_logits, sw_logits)]
                print(f"{Colors.YELLOW}      ↳ Diferença  : {diff}{Colors.RESET}")
                print(f"{Colors.WHITE}{'-'*95}{Colors.RESET}")
                
                # Opcional: Descomente o 'break' abaixo se quiser que o script 
                # pare logo no primeiro erro para você analisar.
                # break

        # --- RELATÓRIO FINAL ---
        print(f"{Colors.WHITE}{'='*95}{Colors.RESET}")
        print(f" {Colors.BOLD}RELATÓRIO DE DESEMPENHO E ACURÁCIA:{Colors.RESET}")

        # Acurácia da Rede
        acc = (total_acertos_npu / num) * 100.0
        print(f"  • Acurácia MNIST     : {Colors.YELLOW}{acc:.1f}%{Colors.RESET} (Label Oficial vs Predição NPU)")

        # Integridade Hardware
        if total_errors_bit == 0:
            print(f"  • Verificação Lógica : {Colors.GREEN}100% (Bit-Exact com o Host Python){Colors.RESET}")
        else:
            print(f"  • Verificação Lógica : {Colors.RED}FALHA ({total_errors_bit} erros na saída){Colors.RESET}")

        # Speedup Médio
        if tot_npu > 0 and run_cpu:
            avg_sp = tot_cpu / tot_npu
            print(f"  • Speedup Físico     : {Colors.CYAN}{avg_sp:.2f}x mais rápido{Colors.RESET}")
        
        print(f"{Colors.WHITE}{'='*95}{Colors.RESET}")
            
    except KeyboardInterrupt:
        log_info("Benchmark Abortado pelo usuário.")
    except Exception as e:
        log_fail(f"Exceção durante execução: {e}")
    finally:
        npu.close()