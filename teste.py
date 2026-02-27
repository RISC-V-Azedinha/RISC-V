import serial
import time
import sys
import os

# ==========================================
# CONFIGURAÇÕES DA PORTA (Ajuste se necessário)
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
            # RTS Ativo em Baixo: True envia 0V (Roda o SoC), False envia 3.3V (Arma Debugger)
            self.ser.rts = True 
            self.halted = False
            time.sleep(0.1)
        except Exception as e:
            print(f"\n[ERRO FATAL] Não foi possível abrir {port}: {e}")
            sys.exit(1)
            
    def halt(self):
        if self.halted: return
            
        self.ser.rts = False # 3.3V -> Vira a chave do hardware para o Debug Controller
        time.sleep(0.05) 
        self.ser.write(b'\xCA\xFE\xBA\xBE') # Envia a Magic Word
        time.sleep(0.05)
        
        self.halted = True
        print("[+] CPU Interceptada (Modo DEBUG ATIVO)")

    def resume(self):
        if not self.halted: return
            
        self.ser.write(b'\x02') # CMD_RESUME
        time.sleep(0.05)
        self.ser.rts = True    # 0V -> Devolve o controle da UART para o Bare-Metal/RTOS
        self.halted = False
        print("[-] CPU Liberada (Execução retomada)")

    def step(self):
        if not self.halted:
            print("[!] Pause a CPU ('halt') antes de dar step.")
            return
            
        self.ser.write(b'\x03') # CMD_STEP
        print("[>] Step: 1 instrução executada.")

    # =========================================================================
    # NOVA FUNÇÃO: RESET SOFT
    # =========================================================================
    def reset(self):
        if not self.halted:
            print("[!] Pause a CPU ('halt') antes de dar reset.")
            return
            
        self.ser.write(b'\x04') # CMD_RESET
        time.sleep(0.05)
        print("[*] Target Resetado. CPU aguardando no endereço 0x00000000.")

    def regs(self):
        if not self.halted:
            print("[!] Pause a CPU ('halt') antes de ler os registradores.")
            return
            
        self.ser.reset_input_buffer() 
        self.ser.write(b'\x10') # CMD_READ_REG
        
        # =========================================================================
        # Lê exatamente 132 bytes (32 registradores + 1 PC) * 4 bytes
        # =========================================================================
        dados = self.ser.read(132)
        
        if len(dados) == 132:
            print("\n" + "="*35)
            print(" BANCO DE REGISTRADORES (RV32I)")
            print("="*35)
            
            # Formatação em duas colunas para facilitar a leitura na tela
            for i in range(0, 32, 2):
                v1 = int.from_bytes(dados[i*4 : i*4+4], byteorder='little')
                v2 = int.from_bytes(dados[(i+1)*4 : (i+1)*4+4], byteorder='little')
                
                # Identifica a ABI comum (opcional, mas ajuda muito no debug do C)
                abi = ["zero", "ra", "sp", "gp", "tp", "t0", "t1", "t2", 
                       "s0", "s1", "a0", "a1", "a2", "a3", "a4", "a5", 
                       "a6", "a7", "s2", "s3", "s4", "s5", "s6", "s7", 
                       "s8", "s9", "s10","s11","t3", "t4", "t5", "t6"]
                
                str1 = f" x{i:02d} ({abi[i]:>4}) : 0x{v1:08X}"
                str2 = f" x{i+1:02d} ({abi[i+1]:>4}) : 0x{v2:08X}"
                print(f"{str1: <25} | {str2}")
            
            # =========================================================================
            # Extração e formatação do Program Counter (PC)
            # =========================================================================
            pc_val = int.from_bytes(dados[128:132], byteorder='little')
            print("-" * 35)
            print(f" ► PC Atual       : 0x{pc_val:08X}")
            print("="*35 + "\n")
            
        else:
            print(f"[ERRO] Falha de comunicação. Recebeu apenas {len(dados)}/132 bytes.")
            print("Verifique o roteamento do TX interno no debug_controller.vhd")

    def close(self):
        if self.halted:
            self.resume()
        if self.ser.is_open:
            self.ser.close()

# ==========================================
# LOOP PRINCIPAL (Interface de Linha de Comando)
# ==========================================
def main():
    # Limpa a tela do terminal para ficar mais elegante
    os.system('clear') 
    
    print("="*55)
    print(" 🛠️  RISC-V Hardware Debugger CLI - V1.1")
    print("="*55)
    
    dbg = Debugger(PORTA, BAUD_RATE)
    print(f"[*] Conectado na porta {PORTA} a {BAUD_RATE} bps\n")

    print("Comandos disponíveis:")
    print("  h, halt   -> Pausa a execução do processador")
    print("  r, resume -> Retoma a execução do programa")
    print("  s, step   -> Executa 1 instrução (precisa estar em halt)")
    print("  p, regs   -> Exibe o valor de todos os registradores + PC")
    print("  rst, reset-> Reinicia o processador via Hardware")
    print("  q, exit   -> Fecha o debugger e libera a placa\n")

    try:
        while True:
            cmd = input("(-DBG) > ").strip().lower()
            
            if cmd in ['h', 'halt']:
                dbg.halt()
            elif cmd in ['r', 'resume']:
                dbg.resume()
            elif cmd in ['s', 'step']:
                dbg.step()
            elif cmd in ['p', 'regs']:
                dbg.regs()
            elif cmd in ['rst', 'reset']:
                dbg.reset()
            elif cmd in ['q', 'exit', 'quit']:
                break
            elif cmd == '':
                continue
            else:
                print("Comando inválido. Tente: halt, resume, step, regs, reset, exit")
                
    except KeyboardInterrupt:
        print("\nSaindo via Ctrl+C...")
        
    finally:
        dbg.close()
        print("Conexão serial encerrada. Hardware liberado!")

if __name__ == '__main__':
    main()