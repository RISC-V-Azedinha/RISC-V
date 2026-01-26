import serial, struct, time
import numpy as np

SERIAL_PORT = 'COM6'   
BAUD_RATE   = 921600   
NETWORK_SHAPE = [64, 32, 16] 
Q_MULT, Q_SHIFT, Q_ZP, Q_RELU = 1, 0, 10, 1

def npu_layer_lane0(inputs_vec, weights_mat, biases_vec, mult, shift, zp, relu):
    n_out = weights_mat.shape[0]
    res_vec = np.zeros(n_out, dtype=np.uint32)
    for o in range(n_out):
        acc = 0
        row_w = weights_mat[o]
        for i in range(len(inputs_vec)):
            ival = int(inputs_vec[i]) & 0xFF
            wval = int(row_w[i]) & 0xFF
            if ival > 127: ival -= 256
            if wval > 127: wval -= 256
            acc += ival * wval
        
        bias = int(biases_vec[o])
        val = (acc + bias) * mult >> shift
        val += zp
        if relu and val < 0: val = 0
        if val > 127: val = 127
        if val < -128: val = -128
        res_vec[o] = (val & 0xFF)
    return res_vec

def main():
    print(f"🚀 Finale Debug V2 (Com Flow Control)")
    try: ser = serial.Serial(SERIAL_PORT, BAUD_RATE, timeout=10.0)
    except Exception as e: print(f"❌ {e}"); return

    # Handshake
    print("📡 Conectando...", end='')
    while True:
        ser.write(b'P')
        if ser.read(1) == b'O': break
    print(" ✅ OK!")

    # --- Geração de Dados ---
    print("🎲 Gerando Dados...")
    curr_in = np.random.randint(0, 0xFFFFFFFF, size=NETWORK_SHAPE[0], dtype=np.uint32)
    
    w_blob = bytearray()
    b_blob = bytearray()
    configs = []
    
    w_off, b_off = 0, 0
    
    # Recalcula expected
    input_bkp = curr_in.copy()

    for i in range(len(NETWORK_SHAPE)-1):
        ni, no = NETWORK_SHAPE[i], NETWORK_SHAPE[i+1]
        w = np.random.randint(0, 0xFFFFFFFF, size=(no, ni), dtype=np.uint32)
        b = np.random.randint(-100, 100, size=no, dtype=np.int32)
        
        exp = npu_layer_lane0(curr_in, w, b, Q_MULT, Q_SHIFT, Q_ZP, Q_RELU)
        
        configs.append((ni, no, w_off, b_off, Q_MULT, Q_SHIFT, Q_ZP, Q_RELU))
        w_blob.extend(w.tobytes()); b_blob.extend(b.tobytes())
        w_off += len(w.tobytes()); b_off += len(b)
        curr_in = exp

    final_exp = curr_in
    curr_in = input_bkp # Restaura input para envio

    # --- Carga de Dados Pesados (Safe para mandar em burst pois o FPGA só lê isso no inicio) ---
    print("📤 Enviando Blobs (Pesos/Bias/Input)...")
    ser.write(b'L'); ser.write(struct.pack('<I', len(w_blob))); ser.write(w_blob); ser.read(1)
    ser.write(b'B'); ser.write(struct.pack('<I', len(b_blob))); ser.write(b_blob); ser.read(1)
    
    # Reenvia Input Inicial Real
    ser.write(b'I'); ser.write(struct.pack('<I', curr_in.nbytes)); ser.write(curr_in.tobytes()); ser.read(1)

    # --- Execução Sincronizada ---
    print("⚡ Iniciando Execução Camada a Camada...")
    ser.write(b'R')
    ser.write(struct.pack('<I', len(configs)))

    for i, c in enumerate(configs):
        n_out = c[1]
        print(f"   ➡️  Enviando Config Layer {i}...", end='')
        
        # 1. Envia Config da Camada Atual
        ser.write(struct.pack('<IIIIIIII', *c))
        
        # 2. Espera FPGA processar (Lê 'L' e depois 'n_out' pontos)
        # Isso garante que não mandamos a próx config enquanto FPGA está ocupado
        print(f" Processando {n_out} neurônios...", end='', flush=True)
        
        # Lê até achar 'L'
        while True:
            ch = ser.read(1).decode('latin-1', errors='ignore')
            if ch == 'L': break
            if ch == '': print("❌ Timeout esperando 'L'"); return
        
        # Conta pontos '.'
        dots = 0
        while dots < n_out:
            ch = ser.read(1).decode('latin-1', errors='ignore')
            if ch == '.': dots += 1
            if ch == '': print(f"❌ Timeout nos dots ({dots}/{n_out})"); return
            
        print(" ✅ Done.")

    # Espera marcador final '!'
    print("   ⏳ Aguardando finalização...", end='')
    while True:
        ch = ser.read(1).decode('latin-1', errors='ignore')
        if ch == '!': break
    print(" OK!")

    # --- Resultados ---
    ser.read(8) # Ciclos
    out_len = struct.unpack('<I', ser.read(4))[0]
    fpga_out = np.frombuffer(ser.read(out_len*4), dtype=np.uint32)
    
    print(f"\n📦 Resultado Final ({len(fpga_out)}): {fpga_out[:10]}...")

    # Check Lane 0
    errs = 0
    if len(fpga_out) != len(final_exp): print("Erro tamanho"); return
    
    for i in range(len(final_exp)):
        if (fpga_out[i] & 0xFF) != (final_exp[i] & 0xFF):
            print(f"❌ Erro {i}: Exp 0x{final_exp[i]:02X} != Rec 0x{fpga_out[i]:02X}")
            errs += 1
            if errs > 5: break
            
    if errs == 0: print("\n🏆 SUCESSO! A sincronia funcionou.")
    else: print(f"\n💀 {errs} erros.")

    ser.close()

if __name__ == "__main__": main()