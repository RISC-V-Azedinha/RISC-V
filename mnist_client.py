import serial
import time
import struct
import numpy as np
import sys
from datetime import datetime
from sklearn.datasets import fetch_openml
from sklearn.linear_model import LogisticRegression
from sklearn.model_selection import train_test_split

# ==============================================================================
# CONFIGURAÇÃO DE USUÁRIO
# ==============================================================================
SERIAL_PORT = 'COM6' 
BAUD_RATE   = 115200

# ==============================================================================
# SISTEMA DE CORES & LOG
# ==============================================================================
class Colors:
    RESET   = "\033[0m"
    BOLD    = "\033[1m"
    DIM     = "\033[2m"
    RED     = "\033[91m"
    GREEN   = "\033[92m"
    YELLOW  = "\033[93m"
    BLUE    = "\033[94m"
    CYAN    = "\033[96m"
    WHITE   = "\033[97m"

def get_time(): return datetime.now().strftime('%H:%M:%S')
def log_info(msg):    print(f"{Colors.DIM}[{get_time()}]{Colors.RESET} {Colors.BLUE}[INFO]{Colors.RESET}    {msg}")
def log_success(msg): print(f"{Colors.DIM}[{get_time()}]{Colors.RESET} {Colors.GREEN}[PASS]{Colors.RESET}    {msg}")
def log_warn(msg):    print(f"{Colors.DIM}[{get_time()}]{Colors.RESET} {Colors.YELLOW}[WARN]{Colors.RESET}    {msg}")
def log_error(msg):   print(f"{Colors.DIM}[{get_time()}]{Colors.RESET} {Colors.RED}[FAIL]{Colors.RESET}    {msg}")

# ==============================================================================
# DRIVER NPU (ROBUSTO & FINAL)
# ==============================================================================
class NPUDriver:
    def __init__(self, port, baud):
        try:
            self.ser = serial.Serial(port, baud, timeout=3)
            self.ser.reset_input_buffer()
            self.ser.reset_output_buffer()
            log_success(f"Porta Serial aberta: {Colors.BOLD}{port}{Colors.RESET}")
            time.sleep(2) # Estabilização elétrica
        except Exception as e:
            log_error(f"Não foi possível abrir a porta: {e}")
            sys.exit(1)

    def close(self): 
        if self.ser.is_open: self.ser.close()

    def sync(self):
        self.ser.reset_input_buffer()
        for i in range(10):
            self.ser.write(b'P')
            time.sleep(0.05)
            if self.ser.in_waiting > 0:
                ack = self.ser.read(1)
                if ack == b'P': 
                    return True
            time.sleep(0.1)
        return False

    def configure(self, mult=1, shift=8, relu=0):
        self.ser.write(b'C')
        self.ser.write(struct.pack('<I', mult))
        self.ser.write(struct.pack('<I', shift))
        self.ser.write(struct.pack('<I', relu))
        if self.ser.read(1) != b'K': raise Exception("Handshake de Configuração Falhou")

    def send_input_only(self, inputs):
        # Broadcast (784,) -> (784, 4) & Pack
        inputs_broadcast = np.repeat(inputs[:, np.newaxis], 4, axis=1)
        flat_in = inputs_broadcast.flatten().astype(np.uint8)
        packed_in = flat_in.view(np.uint32)
        
        self.ser.write(b'I')
        self.ser.write(struct.pack('<I', len(packed_in)))
        self.ser.write(packed_in.tobytes())
        if self.ser.read(1) != b'K': raise Exception("Erro Transmissão Input (I)")

    def run_benchmark_weights_only(self, weights):
        # Weights (10, 784) -> Transpose & Pack
        weights_t = weights.T 
        flat_w = weights_t.flatten().astype(np.uint8)
        packed_w = flat_w.view(np.uint32)

        self.ser.write(b'W')
        self.ser.write(struct.pack('<I', len(packed_w)))
        self.ser.write(packed_w.tobytes())
        if self.ser.read(1) != b'K': raise Exception("Erro Transmissão Pesos (W)")

        # BENCHMARK COMMAND (Flags: 1 = REUSE INPUT)
        self.ser.write(b'B')
        self.ser.write(struct.pack('<I', 1)) 
        
        data = self.ser.read(28)
        if len(data) != 28: raise Exception("Timeout recebendo Benchmark")
        
        res_raw = data[0:4]
        cyc_cpu = struct.unpack('<Q', data[4:12])[0]
        cyc_pio = struct.unpack('<Q', data[12:20])[0]
        cyc_dma = struct.unpack('<Q', data[20:28])[0]
        
        return struct.unpack('<bbbb', res_raw), cyc_cpu, cyc_pio, cyc_dma

# ==============================================================================
# GOLDEN MODEL (SIMULAÇÃO BIT-EXACT)
# ==============================================================================
def sw_simulate_npu(input_vec, weights, mult, shift, relu):
    """Recria a matemática da NPU bit-a-bit para validação."""
    sw_scores = []
    
    # Arredondamento 'Round to Nearest' do Hardware
    rounding = (1 << (shift - 1)) if shift > 0 else 0
    
    inp_32 = input_vec.astype(np.int32)
    
    for i in range(len(weights)):
        w_32 = weights[i].astype(np.int32)
        acc = np.dot(inp_32, w_32)
        val = ((acc * mult) + rounding) >> shift
        
        if relu and val < 0: val = 0
        val = max(-128, min(127, val)) # Clamp Int8
        
        sw_scores.append(int(val))
    return sw_scores

# ==============================================================================
# MAIN
# ==============================================================================
if __name__ == "__main__":

    print(f"\n{Colors.CYAN}")

    print(f"  ██████╗ ██╗███████╗ ██████╗ ██╗   ██╗")
    print(f"  ██╔══██╗██║██╔════╝██╔════╝ ██║   ██║")
    print(f"  ██████╔╝██║███████╗██║█████╗██║   ██║")
    print(f"  ██╔══██╗██║╚════██║██║╚════╝╚██╗ ██╔╝")
    print(f"  ██║  ██║██║███████║╚██████╗  ╚████╔╝ ")
    print(f"  ╚═╝  ╚═╝╚═╝╚══════╝ ╚═════╝   ╚═══╝  ")                   
    print(f"    SYSTOLIC NEURAL PROCESSING UNIT (NPU)     ")

    print(f"{Colors.RESET}")

    # 1. AI Setup
    log_info("Carregando MNIST Dataset...")
    try:
        X, y = fetch_openml('mnist_784', version=1, return_X_y=True, as_frame=False, cache=True)
    except:
        X, y = fetch_openml('mnist_784', version=1, return_X_y=True, as_frame=False)
    X = X / 255.0
    
    log_info("Treinando Modelo de Referência (Sklearn)...")
    X_train, X_test, y_train, y_test = train_test_split(X, y, train_size=5000, test_size=100)
    clf = LogisticRegression(solver='lbfgs', max_iter=200)
    clf.fit(X_train, y_train)
    
    acc_pc = clf.score(X_test, y_test)*100
    log_success(f"Modelo PC Pronto. Acurácia Float: {Colors.BOLD}{acc_pc:.1f}%{Colors.RESET}")

    # Quantização
    max_val = np.max(np.abs(clf.coef_))
    scale = 127.0 / max_val
    q_weights = np.round(clf.coef_ * scale).astype(np.int8)

    # 2. Hardware Setup
    fpga = NPUDriver(SERIAL_PORT, BAUD_RATE)
    
    while not fpga.sync():
        log_warn("Falha no Sync. Pressione RESET na placa...")
        input(f"      {Colors.DIM}[Pressione Enter para tentar novamente]{Colors.RESET}")
        fpga.ser.reset_input_buffer()

    # Configuração
    CFG_MULT, CFG_SHIFT, CFG_RELU = 1, 12, 0
    fpga.configure(CFG_MULT, CFG_SHIFT, CFG_RELU)
    log_info(f"NPU Configurada: Shift={CFG_SHIFT}, Mult={CFG_MULT}")

    # 3. Execution UI
    try:
        print(f"\n{Colors.YELLOW}", end='')
        val = input(f"Quantas amostras processar? [Default=20]: ")
        print(f"{Colors.RESET}", end='')
        num = int(val) if val else 20
    except: num = 20

    # Tabela
    print(f"\n{Colors.WHITE}{'='*100}")
    print(f" {'ID':<3} | {'REAL':<4} | {'HW':<4} | {'SW':<4} | {'BIT-EXACT':<10} | {'PRED OK?':<8} | {'CPU (cyc)':<10} | {'NPU (cyc)':<10} | {'SPEEDUP'}")
    print(f"{'='*100}{Colors.RESET}")

    stats = {'bit_exact': 0, 'correct': 0}
    total_dma_cyc = 0
    total_cpu_cyc = 0

    try:
        for i in range(num):
            img_q = np.round(X_test[i] * 127).astype(np.int8)
            
            # --- HW EXECUTION ---
            # Step A: Input Stationary (Carrega 1x)
            fpga.send_input_only(img_q)
            
            hw_scores = []
            cpu_c, dma_c = 0, 0
            
            # Step B: Weight Streaming (Troca pesos 3x)
            batches = [q_weights[0:4], q_weights[4:8], q_weights[8:10]]
            batches[2] = np.vstack([batches[2], np.zeros((2, 784), dtype=np.int8)])

            for w in batches:
                res, c_cpu, _, c_dma = fpga.run_benchmark_weights_only(w)
                hw_scores.extend(res)
                cpu_c += c_cpu
                dma_c += c_dma
                
            hw_scores = hw_scores[:10]
            hw_pred = np.argmax(hw_scores)
            
            # --- SW VALIDATION ---
            sw_scores = sw_simulate_npu(img_q, q_weights, CFG_MULT, CFG_SHIFT, CFG_RELU)
            sw_pred = np.argmax(sw_scores)
            
            # --- CHECKS ---
            is_exact = (list(hw_scores) == list(sw_scores))
            is_ok    = (str(hw_pred) == str(y_test[i]))
            
            if is_exact: stats['bit_exact'] += 1
            if is_ok:    stats['correct'] += 1
            
            total_cpu_cyc += cpu_c
            total_dma_cyc += dma_c
            
            speedup = cpu_c / dma_c if dma_c > 0 else 0

            # --- PRINT ROW ---
            exact_str = f"{Colors.GREEN}YES{Colors.RESET}" if is_exact else f"{Colors.RED}NO{Colors.RESET}"
            match_str = f"{Colors.GREEN}YES{Colors.RESET}" if is_ok else f"{Colors.RED}NO{Colors.RESET}"
            hw_color  = Colors.GREEN if is_ok else Colors.RED
            
            print(f" {i:<3} | {y_test[i]:<4} | {hw_color}{hw_pred:<4}{Colors.RESET} | {sw_pred:<4} | {exact_str:<19} | {match_str:<17} | {cpu_c:<10} | {dma_c:<10} | {Colors.CYAN}{speedup:.1f}x{Colors.RESET}")
            time.sleep(0.01) # Pequeno delay pra visualização fluida

        # --- SUMMARY ---
        acc_pct = (stats['correct'] / num) * 100
        hw_pct  = (stats['bit_exact'] / num) * 100
        avg_speedup = total_cpu_cyc / total_dma_cyc if total_dma_cyc > 0 else 0

        print(f"{Colors.WHITE}{'='*100}{Colors.RESET}")
        print(f" {Colors.BOLD}RELATÓRIO DE EXECUÇÃO:{Colors.RESET}")
        print(f"  • Acurácia de Classificação : {Colors.BOLD}{acc_pct:.1f}%{Colors.RESET}")
        print(f"  • Consistência de Hardware  : {Colors.BOLD}{hw_pct:.1f}%{Colors.RESET} (Bit-Exact)")
        print(f"  • Speedup Médio Global      : {Colors.CYAN}{avg_speedup:.1f}x{Colors.RESET}")
        print(f"{Colors.WHITE}{'='*100}{Colors.RESET}")

    except KeyboardInterrupt:
        print("\nCancelado pelo usuário.")
    except Exception as e:
        log_error(f"Erro durante benchmark: {e}")
    finally:
        fpga.close()