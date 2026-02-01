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
BAUD_RATE   = 921600

# ==============================================================================
# ESTÉTICA
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
    print(f"             SYSTOLIC NPU (Functional Connectivity)             ")
    print(f"{Colors.RESET}")

# ==============================================================================
# DRIVER
# ==============================================================================
class NPUDriver:
    def __init__(self, port, baud):
        try:
            self.ser = serial.Serial(port, baud, timeout=20) 
            self.ser.reset_input_buffer()
            log_pass(f"Porta Serial aberta: {Colors.BOLD}{port}{Colors.RESET}")
            time.sleep(2)
        except Exception as e:
            log_fail(f"Erro Serial: {e}")
            sys.exit(1)

    def close(self): self.ser.close()

    def sync(self):
        self.ser.reset_input_buffer()
        for _ in range(5):
            self.ser.write(b'P')
            time.sleep(0.1)
            if self.ser.in_waiting and self.ser.read(1) == b'P': return True
        return False

    def configure(self, mult, shift, relu):
        self.ser.write(b'C')
        self.ser.write(struct.pack('<III', mult, shift, relu))
        if self.ser.read(1) != b'K': raise Exception("Erro Config")

    def upload_weights(self, weights_blob):
        flat_w = weights_blob.flatten().astype(np.uint8).view(np.uint32)
        size_kb = (len(flat_w) * 4) / 1024
        
        if size_kb > 180: 
            log_fail(f"PESOS MUITO GRANDES ({size_kb:.1f} KB). Max ~180KB.")
            sys.exit(1)

        self.ser.write(b'L')
        self.ser.write(struct.pack('<I', len(flat_w) * 4))
        self.ser.write(flat_w.tobytes())
        if self.ser.read(1) != b'K': raise Exception("Erro Upload RAM")
        log_pass(f"Pesos carregados na RAM: {Colors.BOLD}{len(flat_w)*4} bytes ({size_kb:.1f} KB){Colors.RESET}")

    def configure_tiling(self, num_tiles, k_dim, stride):
        self.ser.write(b'T')
        self.ser.write(struct.pack('<III', num_tiles, k_dim, stride))
        if self.ser.read(1) != b'K': raise Exception("Erro Tiling")
        log_info(f"Tiling Configurado: {num_tiles} Tiles")

    def run_sample(self, input_vec, num_tiles, cpu=False):
        # 1. Input
        bc = np.repeat(input_vec[:, np.newaxis], 4, axis=1)
        packed = bc.flatten().astype(np.uint8).view(np.uint32)
        
        self.ser.write(b'I')
        self.ser.write(struct.pack('<I', len(packed)))
        self.ser.write(packed.tobytes())
        if self.ser.read(1) != b'K': raise Exception("Erro Input")

        # 2. Executa
        flag = 2 if cpu else 0
        self.ser.write(b'B')
        self.ser.write(struct.pack('<I', flag))

        # 3. Resultado
        payload = (4 * num_tiles) + 24
        data = self.ser.read(payload)
        if len(data) != payload: raise Exception("Timeout NPU")

        fmt = '<' + ('I' * num_tiles) + 'QQQ'
        unpacked = struct.unpack(fmt, data)
        return unpacked[:num_tiles], unpacked[num_tiles:]

# ==============================================================================
# REFERENCE
# ==============================================================================
def sw_ref(inp, w_mat, mult, shift, relu):
    res = []
    i32 = inp.astype(np.int32)
    rd = (1<<(shift-1)) if shift>0 else 0
    for w in w_mat:
        acc = np.dot(i32, w.astype(np.int32))
        val = ((acc*mult)+rd)>>shift
        if relu and val<0: val=0
        res.append(max(-128, min(127, val)))
    return np.array(res, dtype=np.int8)

# ==============================================================================
# MAIN
# ==============================================================================
if __name__ == "__main__":
    print_banner()

    # --- SETUP ---
    K_DIM = 2048   
    N_OUT = 64     
    
    log_info(f"Setup FC Layer: {K_DIM} Inputs -> {N_OUT} Outputs")
    log_info(f"Memória de Pesos: {(K_DIM*N_OUT)/1024:.1f} KB")

    np.random.seed(42)
    weights = np.random.randint(-128, 127, (N_OUT, K_DIM), dtype=np.int8)
    
    npu = NPUDriver(SERIAL_PORT, BAUD_RATE)
    if not npu.sync(): sys.exit(1)

    m, s, r = 1, 10, 1
    npu.configure(m, s, r)
    log_info(f"Config: M={m}, S={s}, R={r}")

    blob = []
    for i in range(0, N_OUT, 4):
        blob.append(weights[i:i+4].T.flatten())
    blob_np = np.concatenate(blob).astype(np.int8)

    npu.upload_weights(blob_np)
    
    n_tiles = N_OUT // 4
    npu.configure_tiling(n_tiles, K_DIM, K_DIM * 4)

    # --- EXECUÇÃO ---
    try:
        print(f"\n{Colors.WHITE}Configurações:{Colors.RESET}")
        run_cpu = input(f"{Colors.YELLOW}  Benchmark CPU (Lento)? [Y/n] {Colors.RESET}").lower() != 'n'
        val = input(f"{Colors.YELLOW}  Amostras? [Default=20]: {Colors.RESET}")
        num = int(val) if val else 20
        
        print(f"\n{Colors.YELLOW}  Iniciando Loop de Inferência...{Colors.RESET}")
        print(f"\n{Colors.WHITE}{'='*80}")
        print(f" {'SAMPLE':<6} | {'STATUS':<15} | {'CPU (cyc)':<12} | {'NPU (cyc)':<12} | {'SPEEDUP'}")
        print(f"{'='*80}{Colors.RESET}")

        tot_cpu, tot_npu = 0, 0
        total_errors = 0
        
        for i in range(num):
            inp = np.random.randint(-128, 127, K_DIM, dtype=np.int8)
            
            raw_res, times = npu.run_sample(inp, n_tiles, run_cpu)
            
            hw_vals = []
            for p in raw_res:
                for b in range(4): 
                    v = (p>>(b*8))&0xFF
                    hw_vals.append(v if v<128 else v-256)
            
            sw_vals = sw_ref(inp, weights, m, s, r)
            match = (list(hw_vals) == list(sw_vals))
            
            if not match: total_errors += 1
            status = f"{Colors.GREEN}OK{Colors.RESET}" if match else f"{Colors.RED}ERR{Colors.RESET}"
            
            c_cpu, c_npu = times[0], times[2]
            sp_str = f"{c_cpu/c_npu:.1f}x" if c_npu > 0 and c_cpu > 0 else "-"
            
            tot_cpu += c_cpu
            tot_npu += c_npu
            
            c_cpu_s = f"{c_cpu}" if c_cpu > 0 else "-"
            print(f" {i:<6} | {status:<24} | {c_cpu_s:<12} | {c_npu:<12} | {Colors.CYAN}{sp_str}{Colors.RESET}")

        # --- RELATÓRIO FINAL ---
        print(f"{Colors.WHITE}{'='*80}{Colors.RESET}")
        print(f" {Colors.BOLD}RELATÓRIO FINAL:{Colors.RESET}")

        # 1. Integridade
        if total_errors == 0:
            print(f"  • Integridade      : {Colors.GREEN}100% (Bit-Exact){Colors.RESET}")
        else:
            print(f"  • Integridade      : {Colors.RED}FALHA ({total_errors} erros){Colors.RESET}")

        # 2. Speedup Médio
        if tot_npu > 0 and run_cpu:
            avg_sp = tot_cpu / tot_npu
            print(f"  • Speedup Médio    : {Colors.CYAN}{avg_sp:.1f}x{Colors.RESET}")

        # 3. Throughput (GOPS)
        # Ops por amostra: 2 (MAC) * K * N
        ops_per_sample = 2 * K_DIM * N_OUT
        total_ops = ops_per_sample * num
        
        # Tempo Total NPU (em segundos, clock 100MHz)
        # Nota: Usamos o tempo acumulado da NPU para calcular o throughput efetivo dela
        npu_seconds = tot_npu / 100_000_000.0
        
        if npu_seconds > 0:
            gops = (total_ops / npu_seconds) / 1e9
            print(f"  • Throughput       : {Colors.BOLD}{gops:.4f} GOPS{Colors.RESET}")
        
        print(f"{Colors.WHITE}{'='*80}{Colors.RESET}")
            
    except Exception as e:
        log_fail(f"{e}")
    finally:
        npu.close()