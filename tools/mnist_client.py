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
BAUD_RATE   = 921600

# ==============================================================================
# SISTEMA DE CORES & LOG (VISUAL CLÁSSICO)
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
# DRIVER NPU V3.3 (MOTOR OTIMIZADO)
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

    def configure_quant(self, mult, shift, relu):
        self.ser.write(b'C')
        self.ser.write(struct.pack('<III', mult, shift, relu))
        if self.ser.read(1) != b'K': raise Exception("Handshake de Configuração Falhou")

    def upload_weights_ram(self, weights_blob):
        """ V3: Upload único para o Armazém RAM """
        flat_w = weights_blob.flatten().astype(np.uint8).view(np.uint32)
        self.ser.write(b'L')
        self.ser.write(struct.pack('<I', len(flat_w) * 4)) # Bytes
        self.ser.write(flat_w.tobytes())
        if self.ser.read(1) != b'K': raise Exception("Erro Upload RAM")
        log_success(f"Upload Pesos para RAM: {Colors.BOLD}{len(flat_w)*4} bytes{Colors.RESET}")

    def configure_tiling(self, num_tiles, k_dim_words, stride_bytes):
        """ V3: Configura a automação de tiles """
        self.ser.write(b'T')
        self.ser.write(struct.pack('<III', num_tiles, k_dim_words, stride_bytes))
        if self.ser.read(1) != b'K': raise Exception("Erro Config Tiling")
        log_info(f"Tiling Configurado: {num_tiles}x Tiles (Stride={stride_bytes})")

    def run_inference_atomic(self, input_vec, num_tiles_expected, enable_cpu=True):
        """ V3: Execução Atômica (Envia Input -> Recebe Tudo) """
        # 1. Input Broadcast & Pack
        bc = np.repeat(input_vec[:, np.newaxis], 4, axis=1)
        flat = bc.flatten().astype(np.uint8).view(np.uint32)
        
        self.ser.write(b'I')
        self.ser.write(struct.pack('<I', len(flat)))
        self.ser.write(flat.tobytes())
        if self.ser.read(1) != b'K': raise Exception("Erro Transmissão Input")

        # 2. Executa (Bit 1 = CPU Flag)
        flag = 2 if enable_cpu else 0
        self.ser.write(b'B')
        self.ser.write(struct.pack('<I', flag))

        # Payload: Resultados + Timings
        payload_size = (4 * num_tiles_expected) + 24
        data = self.ser.read(payload_size)
        if len(data) != payload_size: raise Exception("Timeout recebendo Benchmark")

        fmt = '<' + ('I' * num_tiles_expected) + 'QQQ'
        unpacked = struct.unpack(fmt, data)
        return unpacked[:num_tiles_expected], unpacked[num_tiles_expected:]

# ==============================================================================
# GOLDEN MODEL
# ==============================================================================
def sw_simulate_npu(input_vec, weights, mult, shift, relu):
    inp_32 = input_vec.astype(np.int32)
    scores = []
    rd = (1 << (shift - 1)) if shift > 0 else 0
    for w in weights:
        acc = np.dot(inp_32, w.astype(np.int32))
        val = ((acc * mult) + rd) >> shift
        if relu and val < 0: val = 0
        scores.append(max(-128, min(127, val)))
    return scores

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
    print(f"    SYSTOLIC NPU (DMA + AUTO-TILING)   ")
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
    w_padded = np.vstack([q_weights, np.zeros((2, 784), dtype=np.int8)])
    batches_data = [w_padded[0:4], w_padded[4:8], w_padded[8:12]]
    final_blob = []
    for b in batches_data: final_blob.append(b.T.flatten())
    final_blob_np = np.concatenate(final_blob).astype(np.int8)

    # 2. Hardware Setup
    fpga = NPUDriver(SERIAL_PORT, BAUD_RATE)
    
    while not fpga.sync():
        log_warn("Falha no Sync. Pressione RESET na placa...")
        input(f"      {Colors.DIM}[Pressione Enter para tentar novamente]{Colors.RESET}")
        fpga.ser.reset_input_buffer()

    # Configuração
    CFG_MULT, CFG_SHIFT, CFG_RELU = 1, 12, 0
    fpga.configure_quant(CFG_MULT, CFG_SHIFT, CFG_RELU)
    log_info(f"NPU Configurada: Shift={CFG_SHIFT}, Mult={CFG_MULT}")

    # Upload & Tiling Config
    fpga.upload_weights_ram(final_blob_np)
    fpga.configure_tiling(3, 784, 3136) # 3 Tiles, K=784, Stride=3136

    # 3. Execution UI
    try:
        print(f"\n{Colors.WHITE}Configurações de Execução:{Colors.RESET}")
        
        # Pergunta 1: Benchmark CPU (Amarelo e Indentado)
        run_cpu = input(f"{Colors.YELLOW}  Executar Benchmark de CPU (Lento)? [Y/n]: {Colors.RESET}").strip().lower() != 'n'

        # Pergunta 2: Amostras (Amarelo e Indentado igual)
        val = input(f"{Colors.YELLOW}  Quantas amostras processar? [Default=20]: {Colors.RESET}")
        num = int(val) if val else 20

        # Tabela
        print(f"\n{Colors.WHITE}{'='*100}")
        print(f" {'ID':<3} | {'REAL':<4} | {'HW':<4} | {'SW':<4} | {'BIT-EXACT':<10} | {'PRED OK?':<8} | {'CPU (cyc)':<10} | {'NPU (cyc)':<10} | {'SPEEDUP'}")
        print(f"{'='*100}{Colors.RESET}")

        stats = {'bit_exact': 0, 'correct': 0}
        total_npu_cyc = 0
        total_speedup = 0
        valid_speedups = 0

        for i in range(num):
            img_q = np.round(X_test[i] * 127).astype(np.int8)
            
            raw_res, timings = fpga.run_inference_atomic(img_q, 3, enable_cpu=run_cpu)
            
            # Decodifica Tiles (3x4 -> 12 Scores)
            hw_scores = []
            for pack in raw_res:
                for b in range(4):
                    val = (pack >> (b*8)) & 0xFF
                    if val > 127: val -= 256
                    hw_scores.append(val)
            
            hw_scores = hw_scores[:10] # Remove padding
            hw_pred = np.argmax(hw_scores)
            
            # --- SW VALIDATION ---
            sw_scores = sw_simulate_npu(img_q, q_weights, CFG_MULT, CFG_SHIFT, CFG_RELU)
            sw_pred = np.argmax(sw_scores)
            
            # --- CHECKS ---
            is_exact = (list(hw_scores) == list(sw_scores))
            is_ok    = (str(hw_pred) == str(y_test[i]))
            
            if is_exact: stats['bit_exact'] += 1
            if is_ok:    stats['correct'] += 1
            
            # Métricas
            cyc_cpu = timings[0]
            cyc_npu = timings[2] # System Total (DMA + NPU)
            
            speedup_str = "-"
            if cyc_cpu > 0:
                speedup = cyc_cpu / cyc_npu if cyc_npu > 0 else 0
                speedup_str = f"{speedup:.1f}x"
                total_speedup += speedup
                valid_speedups += 1
            
            total_npu_cyc += cyc_npu

            # --- PRINT ROW ---
            exact_str = f"{Colors.GREEN}YES{Colors.RESET}" if is_exact else f"{Colors.RED}NO{Colors.RESET}"
            match_str = f"{Colors.GREEN}YES{Colors.RESET}" if is_ok else f"{Colors.RED}NO{Colors.RESET}"
            hw_color  = Colors.GREEN if is_ok else Colors.RED
            cpu_disp  = f"{cyc_cpu}" if cyc_cpu > 0 else "-"
            
            print(f" {i:<3} | {y_test[i]:<4} | {hw_color}{hw_pred:<4}{Colors.RESET} | {sw_pred:<4} | {exact_str:<19} | {match_str:<17} | {cpu_disp:<10} | {cyc_npu:<10} | {Colors.CYAN}{speedup_str}{Colors.RESET}")
            time.sleep(0.01)

        # --- SUMMARY ---
        acc_pct = (stats['correct'] / num) * 100
        hw_pct  = (stats['bit_exact'] / num) * 100
        avg_speedup = total_speedup / valid_speedups if valid_speedups > 0 else 0

        print(f"{Colors.WHITE}{'='*100}{Colors.RESET}")
        print(f" {Colors.BOLD}RELATÓRIO DE EXECUÇÃO:{Colors.RESET}")
        print(f"  • Acurácia de Classificação : {Colors.BOLD}{acc_pct:.1f}%{Colors.RESET}")
        print(f"  • Consistência de Hardware  : {Colors.BOLD}{hw_pct:.1f}%{Colors.RESET} (Bit-Exact)")
        if valid_speedups > 0:
            print(f"  • Speedup Médio Global      : {Colors.CYAN}{avg_speedup:.1f}x{Colors.RESET}")
        print(f"{Colors.WHITE}{'='*100}{Colors.RESET}")

    except KeyboardInterrupt:
        print("\nCancelado pelo usuário.")
    except Exception as e:
        log_error(f"Erro durante benchmark: {e}")
    finally:
        fpga.close()