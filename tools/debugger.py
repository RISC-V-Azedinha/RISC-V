import serial
import time
import struct
import sys
import os
import threading

# ==========================================
# CONFIGURAÇÕES DA PORTA E MEMÓRIA
# ==========================================
PORTA = '/dev/ttyUSB1' 
BAUD_RATE = 921600

# Ajuste para o endereço real onde o seu bootloader escreve a RAM
RAM_START_ADDR = 0x80000800  

# ==========================================
# PALETA DE CORES (ANSI)
# ==========================================
class C:
    CYAN    = '\033[96m'
    GREEN   = '\033[92m'
    YELLOW  = '\033[93m'
    RED     = '\033[91m'
    GRAY    = '\033[90m'
    RESET   = '\033[0m'
    BOLD    = '\033[1m'

# ==========================================
# CLASSE DO DEBUGGER
# ==========================================
class Debugger:
    def __init__(self, port, baud):
        try:
            self.ser = serial.Serial(port, baud, rtscts=False, dsrdtr=False, timeout=0.1)
            self.ser.rts = True 
            self.halted = False
            self.is_running = True
            time.sleep(0.1)
            
            self.listener_thread = threading.Thread(target=self._bkp_listener, daemon=True)
            self.listener_thread.start()
            
        except Exception as e:
            print(f"\n{C.RED}[ERRO FATAL] Não foi possível abrir {port}: {e}{C.RESET}")
            sys.exit(1)
            
    def _bkp_listener(self):
        while self.is_running:
            if not self.halted and self.ser.is_open and self.ser.in_waiting:
                try:
                    chunk = self.ser.read(self.ser.in_waiting)
                    
                    if b'\xBB' in chunk:
                        self.ser.rts = False
                        time.sleep(0.05)
                        self.ser.write(b'\xCA\xFE\xBA\xBE')
                        time.sleep(0.05)
                        self.halted = True
                        
                        draw_dashboard(self, f"{C.RED}🚨 HARDWARE BREAKPOINT ATINGIDO! CPU INTERCEPTADA.{C.RESET}")
                        print(f"{C.CYAN}(-DBG) > {C.RESET}", end="", flush=True)
                except:
                    pass
            time.sleep(0.01)

    def halt(self):
        if self.halted: return f"{C.YELLOW}[!] CPU já está pausada.{C.RESET}"
        self.ser.rts = False
        time.sleep(0.05) 
        self.ser.write(b'\xCA\xFE\xBA\xBE')
        time.sleep(0.05)
        self.halted = True
        return f"{C.CYAN}[+] CPU Interceptada (Modo DEBUG ATIVO){C.RESET}"

    def resume(self):
        if not self.halted: return f"{C.YELLOW}[!] CPU já está rodando.{C.RESET}"
        self.ser.write(b'\x02')
        time.sleep(0.05)
        self.ser.rts = True
        self.halted = False
        return f"{C.GREEN}[-] CPU Liberada (Execução retomada){C.RESET}"

    def step(self):
        if not self.halted: return f"{C.YELLOW}[!] Pause a CPU ('h') antes de dar step.{C.RESET}"
        self.ser.write(b'\x03')
        time.sleep(0.02)
        return f"{C.CYAN}[>] Step: 1 instrução executada.{C.RESET}"

    def reset(self):
        if not self.halted: return f"{C.YELLOW}[!] Pause a CPU ('h') antes de dar reset.{C.RESET}"
        self.ser.write(b'\x04')
        time.sleep(0.05)
        self.ser.rts = True
        self.halted = False
        return f"{C.GREEN}[*] Target Resetado. Executando BootROM...{C.RESET}"

    def set_bkp(self, addr_int):
        if not self.halted: return f"{C.YELLOW}[!] Pause a CPU antes de configurar um Breakpoint.{C.RESET}"
        addr_bytes = addr_int.to_bytes(4, byteorder='little')
        self.ser.write(b'\x05')
        time.sleep(0.01)
        self.ser.write(addr_bytes)
        return f"{C.RED}[*] Hardware Breakpoint armado em 0x{addr_int:08X}{C.RESET}"

    def clr_bkp(self):
        if not self.halted: return f"{C.YELLOW}[!] Pause a CPU antes de limpar o Breakpoint.{C.RESET}"
        self.ser.write(b'\x06')
        return f"{C.GREEN}[*] Hardware Breakpoint desativado.{C.RESET}"

    def inject_fibo(self):
        if not self.halted:
            self.halt()
            time.sleep(0.1)

        # 1. Arma a armadilha no início da RAM
        self.set_bkp(RAM_START_ADDR)
        
        # Limpa o buffer de entrada para não ler lixo antigo
        self.ser.reset_input_buffer()
        
        # 2. Reseta o SoC (Acorda o Bootloader) e libera a UART (RTS = True)
        # O reset() interno envia o 0x04 e coloca self.ser.rts = True
        self.reset()
        
        # Dá um pequeno tempo para o Bootloader da ROM inicializar e mandar o "BOOT"
        time.sleep(0.2) 
        self.ser.reset_input_buffer() # Limpa o "BOOT\r\n" do buffer para ler o ACK limpo
        
        # 3. Envia a Magic Word do protocolo do Bootloader
        self.ser.write(b'\xCA\xFE\xBA\xBE')
        
        # 4. Aguarda o ACK (!)
        start_time = time.time()
        ack = b''
        while time.time() - start_time < 2.0:
            if self.ser.in_waiting:
                ack = self.ser.read(1)
                if ack == b'!':
                    break
                    
        if ack != b'!':
            # Se falhar, retoma o controle pro debugger não travar a porta
            self.halt()
            return f"{C.RED}[ERRO] Sem resposta do Bootloader (ACK='!'). Recebido: {ack}{C.RESET}"

        # 5. Payload Fibonacci (RV32I Machine Code - Otimizado e Sem Delay)
        payload = bytearray([
            0x37, 0x04, 0x00, 0x20,  # 00: lui  s0, 0x20000      (s0 = 0x20000000)
            0x93, 0x04, 0xe0, 0x02,  # 04: li   s1, 46
            0x93, 0x02, 0x00, 0x00,  # 08: li   t0, 0            <-- main_loop
            0x13, 0x03, 0x10, 0x00,  # 0C: li   t1, 1
            0x93, 0x03, 0x10, 0x00,  # 10: li   t2, 1
            0x23, 0x20, 0x54, 0x00,  # 14: sw   t0, 0(s0)        <-- fib_loop (CORRIGIDO: rs1 = x8)
            0xb3, 0x8e, 0x62, 0x00,  # 18: add  t4, t0, t1
            0x93, 0x02, 0x03, 0x00,  # 1C: mv   t0, t1
            0x13, 0x83, 0x0e, 0x00,  # 20: mv   t1, t4
            0x93, 0x83, 0x13, 0x00,  # 24: addi t2, t2, 1
            0xe3, 0x96, 0x93, 0xfe,  # 28: bne  t2, s1, fib_loop (salta -20 bytes)
            0x6f, 0xf0, 0xdf, 0xfd   # 2C: j    main_loop        (salta -36 bytes, CORRIGIDO)
        ])

        # 6. Envia o tamanho do payload (UInt32 Little Endian)
        self.ser.write(struct.pack('<I', len(payload)))
        time.sleep(0.05)

        # 7. Envia o código de máquina
        self.ser.write(payload)

        # Agora o Bootloader vai receber os bytes, gravar na RAM e executar o "jr".
        # Quando o PC bater em 0x10000, o Hardware Breakpoint vai disparar sozinho, 
        # a thread do _bkp_listener vai pegar o 0xBB e a tela vai atualizar!
        
        return f"{C.GREEN}[*] Handshake OK! Fibonacci injetado. Aguardando a armadilha do Breakpoint...{C.RESET}"

    def get_regs_display(self):
        if not self.halted: return ""
            
        self.ser.reset_input_buffer() 
        self.ser.write(b'\x10')
        dados = self.ser.read(132)
        
        if len(dados) != 132:
            return f"{C.RED}[ERRO] Falha de leitura. Recebeu {len(dados)}/132 bytes.{C.RESET}"
            
        abi = ["zero", "ra", "sp", "gp", "tp", "t0", "t1", "t2", 
               "s0", "s1", "a0", "a1", "a2", "a3", "a4", "a5", 
               "a6", "a7", "s2", "s3", "s4", "s5", "s6", "s7", 
               "s8", "s9", "s10","s11","t3", "t4", "t5", "t6"]
               
        linhas = [f" {C.BOLD}BANCO DE REGISTRADORES (RV32I){C.RESET}", f"{C.GRAY}" + "-" * 56 + f"{C.RESET}"]
        
        for i in range(0, 32, 2):
            v1 = int.from_bytes(dados[i*4 : i*4+4], byteorder='little')
            v2 = int.from_bytes(dados[(i+1)*4 : (i+1)*4+4], byteorder='little')
            
            str1 = f" {C.CYAN}x{i:02d}{C.RESET} ({C.GRAY}{abi[i]:>4}{C.RESET}) : 0x{v1:08X}"
            str2 = f" {C.CYAN}x{i+1:02d}{C.RESET} ({C.GRAY}{abi[i+1]:>4}{C.RESET}) : 0x{v2:08X}"
            linhas.append(f"{str1: <38} │ {str2}")
            
        pc_val = int.from_bytes(dados[128:132], byteorder='little')
        linhas.append(f"{C.GRAY}" + "-" * 56 + f"{C.RESET}")
        linhas.append(f" {C.GREEN}► PC Atual{C.RESET}       : {C.BOLD}0x{pc_val:08X}{C.RESET}")
        
        return "\n".join(linhas)

    def close(self):
        self.is_running = False
        if self.halted: self.resume()
        if self.ser.is_open: self.ser.close()

# ==========================================
# FUNÇÃO DE DESENHO DA TELA (DASHBOARD)
# ==========================================
def draw_dashboard(dbg, status_msg):
    os.system('clear' if os.name == 'posix' else 'cls')
    print(f"{C.GRAY}=" * 58 + f"{C.RESET}")
    print(f" 🛠️  {C.BOLD}RISC-V EDU DEBUGGER {C.GRAY}(RV32I_Zicsr SoC){C.RESET}")
    print(f"{C.GRAY}=" * 58 + f"{C.RESET}")
    print(f" {C.CYAN}[h]{C.RESET} Halt   │ {C.CYAN}[r]{C.RESET} Resume │ {C.CYAN}[s]{C.RESET} Step     │ {C.CYAN}[rst]{C.RESET} Reset")
    print(f" {C.CYAN}[b]{C.RESET} Set BKP│ {C.CYAN}[c]{C.RESET} Clr BKP│ {C.CYAN}[fibo]{C.RESET} Test Fibo│ {C.CYAN}[q]{C.RESET} Quit")
    print(f"{C.GRAY}=" * 58 + f"{C.RESET}")
    
    if dbg.halted:
        print(dbg.get_regs_display())
    else:
        print("\n" * 6)
        print(f"                 {C.GREEN}[ CPU EXECUTANDO LIVREMENTE ]{C.RESET}")
        print(f"             {C.GRAY}Digite 'h' para pausar e inspecionar{C.RESET}")
        print("\n" * 7)
        
    print(f"{C.GRAY}=" * 58 + f"{C.RESET}")
    if status_msg:
        print(f" >> Status: {status_msg}")
    else:
        print(f" >> Status: {C.GRAY}Aguardando comando...{C.RESET}")
    print(f"{C.GRAY}=" * 58 + f"{C.RESET}")

# ==========================================
# LOOP PRINCIPAL
# ==========================================
def main():
    dbg = Debugger(PORTA, BAUD_RATE)
    status_msg = f"{C.GREEN}Conectado na porta {PORTA}{C.RESET}"

    try:
        while True:
            draw_dashboard(dbg, status_msg)
            
            try:
                raw_input = input(f"{C.CYAN}(-DBG) > {C.RESET}").strip().lower().split()
            except EOFError:
                break
                
            if not raw_input: 
                status_msg = ""
                continue
                
            cmd = raw_input[0]
            
            if cmd in ['h', 'halt']:
                status_msg = dbg.halt()
            elif cmd in ['r', 'resume']:
                status_msg = dbg.resume()
            elif cmd in ['s', 'step']:
                status_msg = dbg.step()
            elif cmd in ['rst', 'reset']:
                status_msg = dbg.reset()
            elif cmd in ['fibo']:
                status_msg = dbg.inject_fibo()
            elif cmd in ['b', 'bkp']:
                if len(raw_input) > 1:
                    try:
                        addr = int(raw_input[1], 16)
                        status_msg = dbg.set_bkp(addr)
                    except ValueError:
                        status_msg = f"{C.RED}[!] Endereço inválido. Use formato Hex (ex: b 0x10000){C.RESET}"
                else:
                    status_msg = f"{C.RED}[!] Faltou o endereço. Ex: b 0x10000{C.RESET}"
            elif cmd in ['c', 'cb', 'clr']:
                status_msg = dbg.clr_bkp()
            elif cmd in ['q', 'exit', 'quit']:
                break
            elif cmd in ['p', 'regs']:
                status_msg = f"{C.GREEN}Registradores atualizados.{C.RESET}"
            else:
                status_msg = f"{C.RED}Comando desconhecido: {cmd}{C.RESET}"
                
    except KeyboardInterrupt:
        print(f"\n{C.YELLOW}Saindo via Ctrl+C...{C.RESET}")
    finally:
        dbg.close()
        print(f"{C.GRAY}Conexão serial encerrada. Hardware liberado!{C.RESET}")

if __name__ == '__main__':
    main()