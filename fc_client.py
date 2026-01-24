import serial
import time
import struct
import numpy as np
import sys
from datetime import datetime

# ==============================================================================
# CONFIGURAÇÃO DE USUÁRIO
# ==============================================================================
SERIAL_PORT = 'COM6'      
BAUD_RATE   = 115200

# ==============================================================================
# ESTÉTICA & LOGGING
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

def log_print(tag, color, msg):
    print(f"[{get_time()}] {color}[{tag}]{Colors.RESET}    {msg}")

def log_info(msg):    log_print("INFO", Colors.BLUE, msg)
def log_pass(msg):    log_print("PASS", Colors.GREEN, msg)
def log_warn(msg):    log_print("WARN", Colors.YELLOW, msg)
def log_fail(msg):    log_print("FAIL", Colors.RED, msg)

def print_banner():
    print(f"\n{Colors.CYAN}")
    print(f"         ███████╗ ██████╗    ███████╗██╗   ██╗███╗   ██╗████████╗██╗  ██╗")
    print(f"         ██╔════╝██╔════╝    ██╔════╝╚██╗ ██╔╝████╗  ██║╚══██╔══╝██║  ██║")
    print(f"         █████╗  ██║         ███████╗ ╚████╔╝ ██╔██╗ ██║   ██║   ███████║")
    print(f"         ██╔══╝  ██║         ╚════██║  ╚██╔╝  ██║╚██╗██║   ██║   ██╔══██║")
    print(f"         ██║     ╚██████╗    ███████║   ██║   ██║ ╚████║   ██║   ██║  ██║")
    print(f"         ╚═╝      ╚═════╝    ╚══════╝   ╚═╝   ╚═╝  ╚═══╝   ╚═╝   ╚═╝  ╚═╝")
    print(f"                    SYSTOLIC NEURAL PROCESSING UNIT (NPU)                ")
    print(f"{Colors.RESET}")

# ==============================================================================
# DRIVER NPU
# ==============================================================================
class NPUDriver:
    def __init__(self, port, baud):
        try:
            self.ser = serial.Serial(port, baud, timeout=5)
            self.ser.reset_input_buffer()
            log_pass(f"Porta Serial aberta: {Colors.BOLD}{port}{Colors.RESET}")
            time.sleep(2)
        except Exception as e:
            log_fail(f"Erro ao abrir serial: {e}")
            sys.exit(1)

    def close(self): self.ser.close()

    def sync(self):
        self.ser.reset_input_buffer()
        for _ in range(5):
            self.ser.write(b'P')
            time.sleep(0.1)
            if self.ser.in_waiting:
                if self.ser.read(1) == b'P': return True
        return False

    def configure(self, mult, shift, relu):
        self.ser.write(b'C')
        self.ser.write(struct.pack('<III', mult, shift, relu))
        if self.ser.read(1) != b'K': raise Exception("Config ACK falhou")

    def load_input(self, inputs):
        # Broadcast para preencher 4 MACs (SIMD 4-way)
        inputs_broadcast = np.repeat(inputs[:, np.newaxis], 4, axis=1)
        flat = inputs_broadcast.flatten().astype(np.uint8)
        packed = flat.view(np.uint32)
        
        self.ser.write(b'I')
        self.ser.write(struct.pack('<I', len(packed)))
        self.ser.write(packed.tobytes())
        if self.ser.read(1) != b'K': raise Exception("Input ACK falhou")

    def run_layer_chunk(self, weights_chunk):
        # Transpõe e empacota pesos
        flat = weights_chunk.T.flatten().astype(np.uint8)
        packed = flat.view(np.uint32)

        self.ser.write(b'W')
        self.ser.write(struct.pack('<I', len(packed)))
        self.ser.write(packed.tobytes())
        if self.ser.read(1) != b'K': raise Exception("Weight ACK falhou")

        # Executa Benchmark (Reuse Input = 1)
        self.ser.write(b'B')
        self.ser.write(struct.pack('<I', 1))
        
        resp = self.ser.read(28)
        if len(resp) != 28: raise Exception("Timeout Benchmark response")
        
        # Unpack: [Res(4B) | CPU(8B) | PIO(8B) | DMA(8B)]
        res_vals = struct.unpack('<bbbb', resp[0:4])
        cycles   = struct.unpack('<QQQ', resp[4:28]) # (cpu, pio, dma)
        return res_vals, cycles

# ==============================================================================
# GOLDEN MODEL
# ==============================================================================
def sw_reference(input_vec, weight_matrix, mult, shift, relu):
    res = []
    inp32 = input_vec.astype(np.int32)
    rounding = (1 << (shift - 1)) if shift > 0 else 0

    for w_row in weight_matrix:
        w32 = w_row.astype(np.int32)
        acc = np.dot(inp32, w32)
        val = ((acc * mult) + rounding) >> shift
        if relu and val < 0: val = 0
        val = max(-128, min(127, val)) 
        res.append(val)
    return np.array(res, dtype=np.int8)

# ==============================================================================
# MAIN
# ==============================================================================
if __name__ == "__main__":
    print_banner()

    # 1. Definição do Problema
    K_DIM = 2048  
    N_OUT = 256   
    
    log_info(f"Gerando dados sintéticos (FC {K_DIM} -> {N_OUT})...")
    np.random.seed(42)
    input_vec = np.random.randint(-128, 127, K_DIM, dtype=np.int8)
    weights   = np.random.randint(-128, 127, (N_OUT, K_DIM), dtype=np.int8)
    
    # 2. Setup Hardware
    npu = NPUDriver(SERIAL_PORT, BAUD_RATE)
    if not npu.sync():
        log_warn("Placa não respondeu. Reset e tente novamente.")
        sys.exit(1)

    # Configuração
    mult, shift, relu = 1, 10, 1
    npu.configure(mult, shift, relu)
    log_info(f"NPU Configurada: Shift={shift}, Mult={mult}, ReLU={relu}")

    # 3. Tabela
    print(f"\n{Colors.WHITE}{'='*105}")
    print(f" {'BATCH':<5} | {'SAMPLE':<8} | {'HW OUT (Partial)':<18} | {'BIT-EXACT':<10} | {'CPU (cyc)':<10} | {'NPU (cyc)':<10} | {'SPEEDUP'}")
    print(f"{'='*105}{Colors.RESET}")

    # 4. Execução
    npu.load_input(input_vec) 

    total_hw_res = []
    stats = {'cpu': 0, 'pio': 0, 'dma': 0, 'errors': 0}
    
    batch_id = 0
    for i in range(0, N_OUT, 4):
        w_chunk = weights[i:i+4]
        
        # Hardware Run
        res, cyc = npu.run_layer_chunk(w_chunk) 
        total_hw_res.extend(res)
        
        # Software Validation
        sw_chunk_res = sw_reference(input_vec, w_chunk, mult, shift, relu)
        
        # Stats Update
        stats['cpu'] += cyc[0]
        stats['pio'] += cyc[1]
        stats['dma'] += cyc[2]
        
        # Check Integrity
        match = (list(res) == list(sw_chunk_res))
        if not match: stats['errors'] += 1
        
        match_str = f"{Colors.GREEN}YES{Colors.RESET}" if match else f"{Colors.RED}NO{Colors.RESET}"
        speedup   = cyc[0] / cyc[2] if cyc[2] > 0 else 0
        
        # Formatação Visual do Vetor
        # Mostra algo como "[-12, 5, 0...]" para caber na tabela
        vec_str = str(list(res))[:15].replace(" ","") + "..." 

        # Mostra logs esporádicos para não poluir
        if N_OUT <= 64 or batch_id % 4 == 0:
             print(f" {batch_id:<5} | {i:<8} | {vec_str:<18} | {match_str:<19} | {cyc[0]:<10} | {cyc[2]:<10} | {Colors.CYAN}{speedup:.1f}x{Colors.RESET}")
        
        batch_id += 1

    # 5. Relatório Final
    hw_res_arr = np.array(total_hw_res, dtype=np.int8)
    sw_full_res = sw_reference(input_vec, weights, mult, shift, relu)
    total_diffs = np.sum(hw_res_arr != sw_full_res)

    print(f"{Colors.WHITE}{'='*105}{Colors.RESET}")
    print(f" {Colors.BOLD}RELATÓRIO DE PERFORMANCE:{Colors.RESET}")
    
    if total_diffs == 0:
        print(f"  • Integridade de Dados      : {Colors.GREEN}100.0% (Bit-Exact){Colors.RESET}")
    else:
        print(f"  • Integridade de Dados      : {Colors.RED}FALHA ({total_diffs} erros){Colors.RESET}")

    avg_speedup_dma = stats['cpu'] / stats['dma'] if stats['dma'] > 0 else 0
    ops = 2 * K_DIM * N_OUT
    fpga_time = stats['dma'] / 100_000_000.0
    gops = (ops / fpga_time) / 1e9 if fpga_time > 0 else 0

    print(f"  • Speedup Global (vs CPU)   : {Colors.CYAN}{avg_speedup_dma:.1f}x{Colors.RESET}")
    print(f"  • Throughput Efetivo        : {Colors.BOLD}{gops:.4f} GOPS{Colors.RESET}")
    print(f"  • Total Ciclos CPU          : {stats['cpu']:,}")
    print(f"  • Total Ciclos NPU (DMA)    : {stats['dma']:,}")
    print(f"{Colors.WHITE}{'='*105}{Colors.RESET}")
    
    npu.close()