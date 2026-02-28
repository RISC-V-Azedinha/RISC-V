import serial
import time
import sys
import os
import threading

# ==========================================
# CONFIGURAÇÕES DA PORTA
# ==========================================
PORTA = '/dev/ttyUSB1' 
BAUD_RATE = 921600

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
                    # Lê TUDO o que está na fila de uma vez só (Desentope o buffer)
                    chunk = self.ser.read(self.ser.in_waiting)
                    
                    if b'\xBB' in chunk:
                        self.ser.rts = False
                        time.sleep(0.05)
                        self.ser.write(b'\xCA\xFE\xBA\xBE')
                        time.sleep(0.05)
                        self.halted = True
                        
                        # Auto-redesenha a tela instantaneamente
                        draw_dashboard(self, f"{C.RED}🚨 HARDWARE BREAKPOINT ATINGIDO!{C.RESET}")
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
        return f"{C.CYAN}[>] Step: 1 instrução executada.{C.RESET}"

    def reset(self):
        if not self.halted: return f"{C.YELLOW}[!] Pause a CPU ('h') antes de dar reset.{C.RESET}"
        self.ser.write(b'\x04')
        time.sleep(0.05)
        return f"{C.GREEN}[*] Target Resetado. PC = 0x00000000.{C.RESET}"

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
    print(f" 🛠️  {C.BOLD}RISC-V BARE-METAL DEBUGGER {C.GRAY}(RV32I_Zicsr SoC){C.RESET}")
    print(f"{C.GRAY}=" * 58 + f"{C.RESET}")
    print(f" {C.CYAN}[h]{C.RESET} Halt   │ {C.CYAN}[r]{C.RESET} Resume │ {C.CYAN}[s]{C.RESET} Step     │ {C.CYAN}[rst]{C.RESET} Reset")
    print(f" {C.CYAN}[b]{C.RESET} Set BKP│ {C.CYAN}[c]{C.RESET} Clr BKP│ {C.CYAN}[q]{C.RESET} Quit")
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
            elif cmd in ['b', 'bkp']:
                if len(raw_input) > 1:
                    try:
                        addr = int(raw_input[1], 16)
                        status_msg = dbg.set_bkp(addr)
                    except ValueError:
                        status_msg = f"{C.RED}[!] Endereço inválido. Use formato Hex (ex: b 0x800){C.RESET}"
                else:
                    status_msg = f"{C.RED}[!] Faltou o endereço. Ex: b 0x800{C.RESET}"
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