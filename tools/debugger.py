import serial
import time
import sys
import os

# ==========================================
# CONFIGURAÇÕES DA PORTA
# ==========================================
PORTA = '/dev/ttyUSB1' 
BAUD_RATE = 921600

# ==========================================
# CLASSE DO DEBUGGER (Driver de Hardware)
# ==========================================
class Debugger:
    def __init__(self, port, baud):
        try:
            self.ser = serial.Serial(port, baud, rtscts=False, dsrdtr=False, timeout=1)
            self.ser.rts = True 
            self.halted = False
            time.sleep(0.1)
        except Exception as e:
            print(f"\n[ERRO FATAL] Não foi possível abrir {port}: {e}")
            sys.exit(1)
            
    def halt(self):
        if self.halted: return "[!] CPU já está pausada."
        self.ser.rts = False
        time.sleep(0.05) 
        self.ser.write(b'\xCA\xFE\xBA\xBE')
        time.sleep(0.05)
        self.halted = True
        return "[+] CPU Interceptada (Modo DEBUG ATIVO)"

    def resume(self):
        if not self.halted: return "[!] CPU já está rodando."
        self.ser.write(b'\x02')
        time.sleep(0.05)
        self.ser.rts = True
        self.halted = False
        return "[-] CPU Liberada (Execução retomada)"

    def step(self):
        if not self.halted: return "[!] Pause a CPU ('h') antes de dar step."
        self.ser.write(b'\x03')
        return "[>] Step: 1 instrução executada."

    def reset(self):
        if not self.halted: return "[!] Pause a CPU ('h') antes de dar reset."
        self.ser.write(b'\x04')
        time.sleep(0.05)
        return "[*] Target Resetado. PC = 0x00000000."

    def set_bkp(self, addr_int):
        if not self.halted: return "[!] Pause a CPU antes de configurar um Breakpoint."
        addr_bytes = addr_int.to_bytes(4, byteorder='little')
        self.ser.write(b'\x05')
        time.sleep(0.01)
        self.ser.write(addr_bytes)
        return f"[*] Hardware Breakpoint armado em 0x{addr_int:08X}"

    def clr_bkp(self):
        if not self.halted: return "[!] Pause a CPU antes de limpar o Breakpoint."
        self.ser.write(b'\x06')
        return "[*] Hardware Breakpoint desativado."

    def get_regs_display(self):
        if not self.halted: return ""
            
        self.ser.reset_input_buffer() 
        self.ser.write(b'\x10')
        dados = self.ser.read(132)
        
        if len(dados) != 132:
            return f"[ERRO] Falha de leitura. Recebeu {len(dados)}/132 bytes."
            
        abi = ["zero", "ra", "sp", "gp", "tp", "t0", "t1", "t2", 
               "s0", "s1", "a0", "a1", "a2", "a3", "a4", "a5", 
               "a6", "a7", "s2", "s3", "s4", "s5", "s6", "s7", 
               "s8", "s9", "s10","s11","t3", "t4", "t5", "t6"]
               
        linhas = [" BANCO DE REGISTRADORES (RV32I)", "-" * 55]
        for i in range(0, 32, 2):
            v1 = int.from_bytes(dados[i*4 : i*4+4], byteorder='little')
            v2 = int.from_bytes(dados[(i+1)*4 : (i+1)*4+4], byteorder='little')
            str1 = f" x{i:02d} ({abi[i]:>4}) : 0x{v1:08X}"
            str2 = f" x{i+1:02d} ({abi[i+1]:>4}) : 0x{v2:08X}"
            linhas.append(f"{str1: <26} | {str2}")
            
        pc_val = int.from_bytes(dados[128:132], byteorder='little')
        linhas.append("-" * 55)
        linhas.append(f" ► PC Atual       : 0x{pc_val:08X}")
        
        return "\n".join(linhas)

    def close(self):
        if self.halted: self.resume()
        if self.ser.is_open: self.ser.close()

# ==========================================
# FUNÇÃO DE DESENHO DA TELA (DASHBOARD)
# ==========================================
def draw_dashboard(dbg, status_msg):
    os.system('clear' if os.name == 'posix' else 'cls')
    print("=" * 55)
    print(" 🛠️  AXON RTOS - Hardware Debugger CLI")
    print("=" * 55)
    print(" [h] Halt   | [r] Resume | [s] Step     | [rst] Reset")
    print(" [b] Set BKP| [c] Clr BKP| [q] Quit")
    print("=" * 55)
    
    if dbg.halted:
        print(dbg.get_regs_display())
    else:
        print("\n" * 7)
        print("          [ CPU EXECUTANDO LIVREMENTE ]")
        print("     [ Digite 'h' para pausar e inspecionar ]")
        print("\n" * 8)
        
    print("=" * 55)
    if status_msg:
        print(f" >> Status: {status_msg}")
    else:
        print(" >> Status: Aguardando comando...")
    print("=" * 55)

# ==========================================
# LOOP PRINCIPAL
# ==========================================
def main():
    dbg = Debugger(PORTA, BAUD_RATE)
    status_msg = f"Conectado na porta {PORTA}"

    try:
        while True:
            draw_dashboard(dbg, status_msg)
            
            raw_input = input("(-DBG) > ").strip().lower().split()
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
                        # Aceita formato "b 0x800" ou "b 800"
                        addr = int(raw_input[1], 16)
                        status_msg = dbg.set_bkp(addr)
                    except ValueError:
                        status_msg = "[!] Endereço inválido. Use formato Hex (ex: b 0x800)"
                else:
                    status_msg = "[!] Faltou o endereço. Ex: b 0x800"
            elif cmd in ['c', 'cb', 'clr']:
                status_msg = dbg.clr_bkp()
            elif cmd in ['q', 'exit', 'quit']:
                break
            elif cmd in ['p', 'regs']:
                status_msg = "Registradores atualizados."
            else:
                status_msg = f"Comando desconhecido: {cmd}"
                
    except KeyboardInterrupt:
        print("\nSaindo via Ctrl+C...")
    finally:
        dbg.close()
        print("Conexão serial encerrada. Hardware liberado!")

if __name__ == '__main__':
    main()