import serial
import struct
import sys
import time
import os
import argparse
from datetime import datetime

# ==============================================================================
# CONFIGURAÇÕES PADRÃO
# ==============================================================================
DEFAULT_PORT      = "COM6" 
DEFAULT_BAUD      = 921600
DEFAULT_FILENAME  = "app.bin"

# ==============================================================================
# UTILITÁRIOS DE LOG E CORES
# ==============================================================================
class Log:
    RESET   = "\033[0m"
    RED     = "\033[91m"
    GREEN   = "\033[92m"
    YELLOW  = "\033[93m"
    BLUE    = "\033[94m"
    CYAN    = "\033[96m"
    GREY    = "\033[90m"

    @staticmethod
    def _timestamp():
        return datetime.now().strftime("%H:%M:%S")

    @staticmethod
    def info(msg):
        print(f"{Log.GREY}[{Log._timestamp()}] {Log.BLUE}INFO  {Log.RESET} {msg}")

    @staticmethod
    def success(msg):
        print(f"{Log.GREY}[{Log._timestamp()}] {Log.GREEN}OK    {Log.RESET} {msg}")

    @staticmethod
    def warn(msg):
        print(f"{Log.GREY}[{Log._timestamp()}] {Log.YELLOW}WARN  {Log.RESET} {msg}")

    @staticmethod
    def error(msg):
        print(f"{Log.GREY}[{Log._timestamp()}] {Log.RED}ERROR {Log.RESET} {msg}")
    
    @staticmethod
    def raw(msg):
        print(msg)

# ==============================================================================
# ABSTRAÇÃO DE TECLADO (CROSS-PLATFORM)
# ==============================================================================
if os.name == 'nt':
    import msvcrt
    
    def kb_hit():
        return msvcrt.kbhit()
    
    def get_char():
        return msvcrt.getch()
        
    class TerminalContext:
        def __enter__(self): return self
        def __exit__(self, exc_type, exc_val, exc_tb): pass

else:
    import tty
    import termios
    import select
    
    def kb_hit():
        dr, dw, de = select.select([sys.stdin], [], [], 0)
        return dr != []
    
    def get_char():
        return sys.stdin.read(1).encode('utf-8')

    class TerminalContext:
        def __enter__(self):
            self.fd = sys.stdin.fileno()
            self.old_settings = termios.tcgetattr(self.fd)
            try:
                tty.setcbreak(self.fd) 
            except termios.error:
                pass
            return self
        def __exit__(self, exc_type, exc_val, exc_tb):
            try:
                termios.tcsetattr(self.fd, termios.TCSADRAIN, self.old_settings)
            except termios.error:
                pass

# ==============================================================================
# LÓGICA DO PROTOCOLO
# ==============================================================================

def auto_reset(ser):
    Log.info("Acionando Reset de Hardware via Debug Controller...")
    
    # 1. Arma o Debugger (RTS Ativo em Baixo -> False envia 3.3V)
    ser.rts = False
    time.sleep(0.05)
    
    # 2. Envia Magic Word para assumir o controle
    ser.write(b'\xCA\xFE\xBA\xBE')
    time.sleep(0.05)
    
    # 3. Envia o comando de Soft-Reset (0x04)
    ser.write(b'\x04')
    time.sleep(0.05)
    
    # Limpa o buffer ANTES de soltar o processador!
    ser.reset_input_buffer()
    
    # 4. Devolve a UART para o SoC e dá "Play" no processador
    ser.rts = True
    
    Log.success("Placa resetada remotamente!")

def wait_for_bootloader(ser):
    Log.info("Aguardando sinal 'BOOT' da FPGA...")
    
    buffer = ""
    while True:
        if kb_hit():
            if get_char() == b'\x1b': raise KeyboardInterrupt("Abortado pelo usuário.")

        if ser.in_waiting:
            try:
                char = ser.read(1).decode('utf-8', errors='ignore')
                buffer += char
                if "BOOT" in buffer:
                    Log.success("Bootloader detectado!")
                    return
                if len(buffer) > 50: buffer = buffer[-20:] 
            except Exception:
                pass

def perform_handshake(ser, file_size):
    time.sleep(0.1) 
    ser.reset_input_buffer()

    # O Bootloader recebe a Magic Word (RTS já está True aqui)
    Log.info("Enviando Magic Word para o Bootloader (0xCAFEBABE)...")
    ser.write(b'\xCA\xFE\xBA\xBE')
    
    start_time = time.time()
    ack = b''
    while time.time() - start_time < 2.0:
        if ser.in_waiting:
            ack = ser.read(1)
            break
    
    if ack != b'!':
        raise Exception(f"Sem resposta do Bootloader. Recebido: {ack}")
    
    Log.info(f"Enviando tamanho do arquivo: {file_size} bytes")
    ser.write(struct.pack('<I', file_size))
    time.sleep(0.05)

def upload_file(ser, filename):
    file_size = os.path.getsize(filename)
    CHUNK_SIZE = 64 
    
    Log.info(f"Iniciando upload de '{filename}' ({file_size} bytes)...\n")
    
    with open(filename, "rb") as f:
        payload = f.read()
        total_sent = 0
        BAR_WIDTH = 40 
        
        sys.stdout.write(f"\r{Log.CYAN}Progresso: [{' ' * BAR_WIDTH}] 0%{Log.RESET}")
        sys.stdout.flush()
        
        for i in range(0, len(payload), CHUNK_SIZE):
            if kb_hit() and get_char() == b'\x1b': 
                print("\n") 
                raise KeyboardInterrupt("Cancelado durante upload.")
            
            chunk = payload[i : i + CHUNK_SIZE]
            ser.write(chunk)
            ser.flush()
            total_sent += len(chunk)
            
            percent = min(100, int((total_sent / file_size) * 100))
            filled_len = int(BAR_WIDTH * total_sent // file_size)
            bar = '=' * filled_len + ' ' * (BAR_WIDTH - filled_len)
            
            sys.stdout.write(f"\r{Log.CYAN}Progresso: [{bar}] {percent}%{Log.RESET}")
            sys.stdout.flush()
            
            time.sleep(0.002) 
            
        print("\n")
    
    Log.success("Upload concluído. Aguardando verificação...")
    
    while True:
        if ser.in_waiting:
            c = ser.read(1).decode('utf-8', errors='ignore')
            if c == '.': continue 
            if c == '>':
                Log.success("FPGA confirmou: Executando App!")
                break

def serial_monitor(ser):
    print("\n" + "="*60)
    print(f"{Log.YELLOW}   MONITOR SERIAL ATIVO (Tx/Rx) {Log.RESET}")
    print(f"{Log.GREY}   - Digite para enviar.")
    print(f"   - [ESC] ou [Ctrl+C] para sair.{Log.RESET}")
    print("="*60 + "\n")

    try:
        while True:
            if ser.in_waiting:
                data = ser.read(ser.in_waiting)
                try:
                    text = data.decode('utf-8', errors='replace')
                    sys.stdout.write(text)
                    sys.stdout.flush()
                except:
                    pass

            if kb_hit():
                char_bytes = get_char()
                
                if char_bytes == b'\x1b' or char_bytes == b'\x03': 
                    print(f"\n{Log.YELLOW}Encerrando monitor.{Log.RESET}")
                    break
                
                if char_bytes == b'\r':
                    char_bytes = b'\r\n' 
                    sys.stdout.write('\n') 
                else:
                    pass

                ser.write(char_bytes)
                sys.stdout.flush()

            time.sleep(0.005)

    except KeyboardInterrupt:
        print(f"\n{Log.YELLOW}Encerrando monitor.{Log.RESET}")

# ==============================================================================
# MAIN
# ==============================================================================
def main():
    parser = argparse.ArgumentParser(description='FPGA Uploader & Serial Monitor')
    parser.add_argument('-p', '--port', default=DEFAULT_PORT, help=f'Porta Serial (Padrão: {DEFAULT_PORT})')
    parser.add_argument('-b', '--baud', type=int, default=DEFAULT_BAUD, help=f'Baud Rate (Padrão: {DEFAULT_BAUD})')
    parser.add_argument('-f', '--file', default=DEFAULT_FILENAME, help=f'Arquivo Binário (Padrão: {DEFAULT_FILENAME})')
    args = parser.parse_args()

    if not os.path.exists(args.file):
        Log.error(f"Arquivo '{args.file}' não encontrado.")
        sys.exit(1)

    Log.raw(f"\n{Log.CYAN}--- FPGA LOADER  ----------------------------------------------------------------{Log.RESET}\n")
    Log.info(f"Porta: {args.port} | Baud: {args.baud} | Arq: {args.file}")

    with TerminalContext():
        ser = None
        try:
            # IMPORTANTE: Desabilitar o controle de fluxo por hardware na porta serial
            ser = serial.Serial(args.port, args.baud, rtscts=False, dsrdtr=False, timeout=2)
            ser.rts = True # Garante que iniciamos no modo SoC
            
            # --- O NOVO FLUXO 100% AUTOMATIZADO ---
            auto_reset(ser)
            wait_for_bootloader(ser)
            
            file_size = os.path.getsize(args.file)
            perform_handshake(ser, file_size)
            upload_file(ser, args.file)
            serial_monitor(ser)

        except serial.SerialException as e:
            Log.error(f"Erro de conexão serial: {e}")
            if os.name != 'nt':
                Log.info("Dica Linux/WSL: Verifique permissões (sudo chmod 666 /dev/ttySx)")
        except KeyboardInterrupt:
            print("\n")
            Log.warn("Operação cancelada pelo usuário.")
        except Exception as e:
            Log.error(f"Ocorreu um erro: {e}")
        finally:
            if ser and ser.is_open:
                ser.close()
                Log.info("Conexão fechada.")

if __name__ == "__main__":
    main()