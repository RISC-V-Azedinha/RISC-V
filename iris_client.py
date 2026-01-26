import serial
import time
import struct
import numpy as np
import sys
from datetime import datetime
from sklearn.datasets import load_iris
from sklearn.linear_model import LogisticRegression
from sklearn.model_selection import train_test_split

# ==============================================================================
# CONFIGURAÇÃO DE USUÁRIO
# ==============================================================================
SERIAL_PORT = 'COM6'   
BAUD_RATE   = 921600
HW_SHIFT    = 6        
BIAS_CONST  = 10       

# ==============================================================================
# SISTEMA DE CORES
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
# DRIVER NPU 
# ==============================================================================
class NPUDriver:
    def __init__(self, port, baud):
        try:
            self.ser = serial.Serial(port, baud, timeout=3)
            self.ser.reset_input_buffer()
            self.ser.reset_output_buffer()
            log_success(f"Porta Serial aberta: {Colors.BOLD}{port}{Colors.RESET}")
            time.sleep(2)
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
                if self.ser.read(1) == b'P': 
                    return True
            time.sleep(0.1)
        return False

    def configure(self, mult=1, shift=8, relu=0):
        self.ser.write(b'C')
        self.ser.write(struct.pack('<III', mult, shift, relu))
        if self.ser.read(1) != b'K': raise Exception("Erro Config")

    def upload_weights_ram(self, weights_blob):
        flat_w = weights_blob.flatten().astype(np.uint8).view(np.uint32)
        self.ser.write(b'L')
        self.ser.write(struct.pack('<I', len(flat_w) * 4)) # Bytes
        self.ser.write(flat_w.tobytes())
        if self.ser.read(1) != b'K': raise Exception("Erro Upload RAM")

    def configure_tiling(self, num_tiles, k_dim, stride_bytes):
        self.ser.write(b'T')
        self.ser.write(struct.pack('<III', num_tiles, k_dim, stride_bytes))
        if self.ser.read(1) != b'K': raise Exception("Erro Config Tiling")

    def run_inference_atomic(self, inputs, num_tiles=1, enable_cpu=False):
        # 1. Input
        inputs_broadcast = np.repeat(inputs[:, np.newaxis], 4, axis=1)
        flat_in = inputs_broadcast.flatten().astype(np.uint8)
        packed_in = flat_in.view(np.uint32)
        
        self.ser.write(b'I')
        self.ser.write(struct.pack('<I', len(packed_in)))
        self.ser.write(packed_in.tobytes())
        if self.ser.read(1) != b'K': raise Exception("Erro I")

        # 2. Executa
        flag = 2 if enable_cpu else 0
        self.ser.write(b'B')
        self.ser.write(struct.pack('<I', flag)) 
        
        # 3. Recebe
        payload_size = (4 * num_tiles) + 24
        data = self.ser.read(payload_size)
        if len(data) != payload_size: raise Exception("Timeout")
        
        fmt = '<' + ('I' * num_tiles) + 'QQQ'
        unpacked = struct.unpack(fmt, data)
        return unpacked[:num_tiles], unpacked[num_tiles:]

# ==============================================================================
# SIMULAÇÃO SW
# ==============================================================================
def sw_simulate_npu(input_vec, weights, mult, shift):
    sw_scores = []
    rounding = (1 << (shift - 1)) if shift > 0 else 0
    inp_32 = input_vec.astype(np.int32)
    for i in range(len(weights)):
        w_32 = weights[i].astype(np.int32)
        acc = np.dot(inp_32, w_32)
        val = ((acc * mult) + rounding) >> shift
        val = max(-128, min(127, val)) 
        sw_scores.append(int(val))
    return sw_scores

# ==============================================================================
# MAIN
# ==============================================================================
if __name__ == "__main__":
    
    print(f"\n{Colors.CYAN}")
    print(f"         ██╗██████╗ ██╗███████╗           ")
    print(f"         ██║██╔══██╗██║██╔════╝           ")
    print(f"         ██║██████╔╝██║███████╗           ")
    print(f"         ██║██╔══██╗██║╚════██║           ")
    print(f"         ██║██║  ██║██║███████║           ")
    print(f"         ╚═╝╚═╝  ╚═╝╚═╝╚══════╝           ")
    print(f"   SYSTOLIC NEURAL PROCESSING UNIT (NPU)  ")
    print(f"{Colors.RESET}")

    log_info("Carregando Iris Dataset...")
    iris = load_iris()
    X, y = iris.data, iris.target
    
    log_info("Treinando Modelo (Logistic Regression)...")
    X_train, X_test, y_train, y_test = train_test_split(X, y, test_size=15, random_state=42)
    clf = LogisticRegression(max_iter=500)
    clf.fit(X_train, y_train)
    
    acc_pc = clf.score(X_test, y_test)*100
    log_success(f"Modelo PC Pronto. Acurácia Float: {Colors.BOLD}{acc_pc:.1f}%{Colors.RESET}")

    log_info("Calculando escalas de quantização...")
    INPUT_SCALE = 10.0
    max_w = np.max(np.abs(clf.coef_))
    max_b = np.max(np.abs(clf.intercept_))
    global_max = max(max_w, max_b)
    WEIGHT_SCALE = 127.0 / global_max
    log_info(f"Escalas: Input={INPUT_SCALE:.1f}, Weight={WEIGHT_SCALE:.2f}")

    K_DIM_BYTES = 16 
    
    q_weights = np.zeros((4, K_DIM_BYTES), dtype=np.int8) 
    for c in range(3):
        q_weights[c, :4] = np.round(clf.coef_[c] * WEIGHT_SCALE).astype(np.int8)
        q_weights[c, 4]  = np.round(clf.intercept_[c] * WEIGHT_SCALE).astype(np.int8)
    
    blob_list = []
    blob_list.append(q_weights.T.flatten()) 
    full_blob = np.concatenate(blob_list).astype(np.int8)

    fpga = NPUDriver(SERIAL_PORT, BAUD_RATE)
    while not fpga.sync():
        log_warn("Pressione RESET na placa...")
        input(f"      {Colors.DIM}[Pressione Enter]{Colors.RESET}")
        fpga.ser.reset_input_buffer()

    fpga.configure(mult=1, shift=HW_SHIFT, relu=0)
    log_info(f"NPU Configurada: Shift={HW_SHIFT}, Mult=1")
    
    fpga.upload_weights_ram(full_blob)
    
    # K_DIM deve ser 16 (Bytes), não 4 (Words). 
    # O firmware espera o tamanho do vetor em elementos.
    fpga.configure_tiling(1, K_DIM_BYTES, K_DIM_BYTES * 4) 
    
    try:
        print(f"\n{Colors.WHITE}Configurações de Execução:{Colors.RESET}")
        run_cpu = input(f"{Colors.YELLOW}  Benchmark CPU (Lento)? [Y/n] {Colors.RESET}").lower() != 'n'
        val = input(f"{Colors.YELLOW}  Quantas amostras processar? [Default=15]: {Colors.RESET}")
        num_samples = int(val) if val else 15
        
        print(f"\n{Colors.YELLOW}  Iniciando Loop de Inferência...{Colors.RESET}")

        col_id = 4; col_name = 12; col_hw = 14; col_sw = 14; col_exact = 10; col_pred = 7; col_cpu = 10; col_npu = 10; col_speed = 10

        header = (f" {'ID':<{col_id}}| {'FLOR REAL':<{col_name}}| {'HW':<{col_hw}}| {'SW':<{col_sw}}| "
                  f"{'BIT-EXACT':^{col_exact}} | {'PRED?':^{col_pred}} | {'CPU(cyc)':>{col_cpu}} | {'NPU(cyc)':>{col_npu}} | {'SPEEDUP':>{col_speed}}")
        
        width = len(header)
        print(f"\n{Colors.WHITE}{'='*width}")
        print(header)
        print(f"{'='*width}{Colors.RESET}")

        stats = {'bit_exact': 0, 'correct': 0}
        total_dma_cyc = 0; total_cpu_cyc = 0
        valid_speedups = 0

        for i in range(num_samples):
            idx = i % len(X_test)
            
            q_in = np.zeros(K_DIM_BYTES, dtype=np.int8)
            q_in[:4] = np.round(X_test[idx] * INPUT_SCALE).astype(np.int8)
            q_in[4]  = BIAS_CONST 

            res_packed, timings = fpga.run_inference_atomic(q_in, num_tiles=1, enable_cpu=run_cpu)
            
            c_cpu, _, c_dma = timings

            pack = res_packed[0]
            scores_hw = []
            for b in range(3): 
                val = (pack >> (b*8)) & 0xFF
                if val > 127: val -= 256
                scores_hw.append(val)
            
            pred_hw = np.argmax(scores_hw)
            scores_sw = sw_simulate_npu(q_in, q_weights[:3], 1, HW_SHIFT)
            
            is_exact = (scores_hw == scores_sw)
            is_ok    = (pred_hw == y_test[idx])
            
            if is_exact: stats['bit_exact'] += 1
            if is_ok:    stats['correct'] += 1
            
            total_cpu_cyc += c_cpu
            total_dma_cyc += c_dma
            
            speedup_str = "-"
            if run_cpu and c_dma > 0:
                speedup_val = c_cpu / c_dma
                speedup_str = f"{speedup_val:.1f}x"
                valid_speedups += 1

            exact_txt = "YES" if is_exact else "NO"
            exact_clr = Colors.GREEN if is_exact else Colors.RED
            match_txt = "YES" if is_ok else "NO"
            match_clr = Colors.GREEN if is_ok else Colors.RED
            
            s_hw = str(scores_hw).replace(" ", "")
            s_sw = str(scores_sw).replace(" ", "")
            c_cpu_str = str(c_cpu) if c_cpu > 0 else "-"

            row = (f" {i:<{col_id}}| {iris.target_names[y_test[idx]]:<{col_name}}| {s_hw:<{col_hw}}| {s_sw:<{col_sw}}| "
                   f"{exact_clr}{exact_txt:^{col_exact}}{Colors.RESET} | "
                   f"{match_clr}{match_txt:^{col_pred}}{Colors.RESET} | "
                   f"{c_cpu_str:>{col_cpu}} | {c_dma:>{col_npu}} | "
                   f"{Colors.CYAN}{speedup_str:>{col_speed}}{Colors.RESET}")
            
            print(row)
            time.sleep(0.05)

        acc_pct = (stats['correct'] / num_samples) * 100
        hw_pct  = (stats['bit_exact'] / num_samples) * 100
        
        avg_speedup = 0
        if valid_speedups > 0:
            avg_speedup = total_cpu_cyc / total_dma_cyc

        print(f"{Colors.WHITE}{'='*width}{Colors.RESET}")
        print(f" {Colors.BOLD}RELATÓRIO IRIS:{Colors.RESET}")
        print(f"  • Acurácia HW           : {Colors.BOLD}{acc_pct:.1f}%{Colors.RESET}")
        print(f"  • Consistência SW/HW    : {Colors.BOLD}{hw_pct:.1f}%{Colors.RESET}")
        if run_cpu:
            print(f"  • Speedup (Small Data)  : {Colors.CYAN}{avg_speedup:.1f}x{Colors.RESET}")
        print(f"{Colors.WHITE}{'='*width}{Colors.RESET}")

    except KeyboardInterrupt:
        print("\nCancelado.")
    except Exception as e:
        log_error(f"{e}")
    finally:
        fpga.close()