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
        # Retorna bytes
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
        # Lê 1 byte do stdin
        return sys.stdin.read(1).encode('utf-8')

    class TerminalContext:
        def __enter__(self):
            self.fd = sys.stdin.fileno()
            self.old_settings = termios.tcgetattr(self.fd)
            try:
                tty.setraw(self.fd) # setraw é melhor para monitor serial que setcbreak
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

def wait_for_bootloader(ser):
    Log.info("Aguardando sinal 'BOOT' da FPGA...")
    Log.warn("Por favor, reinicie a placa agora (Reset Button).")
    
    buffer = ""
    while True:
        # Checa saída de emergência
        if kb_hit():
            if get_char() == b'\x1b': raise KeyboardInterrupt("Abortado pelo usuário.")

        if ser.in_waiting:
            try:
                char = ser.read(1).decode('utf-8', errors='ignore')
                buffer += char
                if "BOOT" in buffer:
                    Log.success("Bootloader detectado!")
                    return
                # Limpa buffer se ficar muito grande para evitar falso positivo antigo
                if len(buffer) > 50: buffer = buffer[-20:] 
            except Exception:
                pass

def perform_handshake(ser, file_size):

    time.sleep(0.1) 
    ser.reset_input_buffer()

    # 1. Magic Word
    Log.info("Enviando Magic Word (0xCAFEBABE)...")
    ser.write(b'\xCA\xFE\xBA\xBE')
    
    # Aguarda ACK ('!') com timeout manual curto
    start_time = time.time()
    ack = b''
    while time.time() - start_time < 2.0:
        if ser.in_waiting:
            ack = ser.read(1)
            break
    
    if ack != b'!':
        raise Exception(f"Sem resposta da Magic Word. Recebido: {ack}")
    
    # 2. Tamanho do Arquivo
    Log.info(f"Enviando tamanho do arquivo: {file_size} bytes")
    ser.write(struct.pack('<I', file_size))
    # Pequeno delay para a FPGA processar
    time.sleep(0.05)

def upload_file(ser, filename):
    file_size = os.path.getsize(filename)
    CHUNK_SIZE = 64 
    
    Log.info(f"Iniciando upload de '{filename}' ({file_size} bytes)...\n")
    
    with open(filename, "rb") as f:
        payload = f.read()
        total_sent = 0
        BAR_WIDTH = 40 # Tamanho visual da barra (caracteres)
        
        # Garante que começa vazio
        sys.stdout.write(f"\r{Log.CYAN}Progresso: [{' ' * BAR_WIDTH}] 0%{Log.RESET}")
        sys.stdout.flush()
        
        for i in range(0, len(payload), CHUNK_SIZE):
            # 1. Verifica cancelamento
            if kb_hit() and get_char() == b'\x1b': 
                print("\n") # Pula linha para não estragar o log
                raise KeyboardInterrupt("Cancelado durante upload.")
            
            # 2. Envia dados
            chunk = payload[i : i + CHUNK_SIZE]
            ser.write(chunk)
            ser.flush()
            total_sent += len(chunk)
            
            # 3. Calcula Barra de Progresso
            # Porcentagem (0 a 100)
            percent = min(100, int((total_sent / file_size) * 100))
            # Quantos caracteres '=' desenhar
            filled_len = int(BAR_WIDTH * total_sent // file_size)
            # Cria a string da barra: Parte cheia '=' + Parte vazia ' '
            bar = '=' * filled_len + ' ' * (BAR_WIDTH - filled_len)
            
            # 4. Desenha na tela usando \r para voltar ao início
            sys.stdout.write(f"\r{Log.CYAN}Progresso: [{bar}] {percent}%{Log.RESET}")
            sys.stdout.flush()
            
            # Throttle (evita saturar a FPGA e o visual)
            time.sleep(0.002) 
            
        print("\n") # Pula para a próxima linha ao terminar
    
    Log.success("Upload concluído. Aguardando verificação...")
    
    # Espera confirmação final ('R')
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
            # 1. RECEPÇÃO (RX): FPGA -> PC
            if ser.in_waiting:
                data = ser.read(ser.in_waiting)
                # Tenta decodificar para printar bonito, senão printa raw
                try:
                    text = data.decode('utf-8', errors='replace')
                    sys.stdout.write(text)
                    sys.stdout.flush()
                except:
                    pass

            # 2. TRANSMISSÃO (TX): PC -> FPGA
            if kb_hit():
                char_bytes = get_char()
                
                # Checa saída
                if char_bytes == b'\x1b' or char_bytes == b'\x03': # ESC ou Ctrl+C
                    print(f"\n{Log.YELLOW}Encerrando monitor.{Log.RESET}")
                    break
                
                # No Linux/Mac em modo RAW, Enter vem como \r. 
                # Dependendo da FPGA, pode precisar converter \r para \n ou \r\n
                if char_bytes == b'\r':
                    char_bytes = b'\r\n' # Ajuste comum para terminais
                    sys.stdout.write('\n') # Echo local de nova linha
                else:
                    # Echo local opcional (se a FPGA não fizer echo)
                    # sys.stdout.write(char_bytes.decode('utf-8', errors='ignore'))
                    pass

                ser.write(char_bytes)
                sys.stdout.flush()

            time.sleep(0.005) # Evita uso de 100% CPU

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

    # Contexto do Terminal (crucial para Linux/Mac)
    with TerminalContext():
        ser = None
        try:
            ser = serial.Serial(args.port, args.baud, timeout=2)
            
            # 1. Bootloader
            wait_for_bootloader(ser)
            
            # 2. Handshake
            file_size = os.path.getsize(args.file)
            perform_handshake(ser, file_size)
            
            # 3. Upload
            upload_file(ser, args.file)
            
            # 4. Monitor
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