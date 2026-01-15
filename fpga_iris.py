import serial
import time
import struct
import numpy as np
from sklearn import datasets
from sklearn.model_selection import train_test_split
from sklearn.preprocessing import StandardScaler

# Cores
RESET = "\033[0m"
GREEN = "\033[32m"
RED   = "\033[31m"
CYAN  = "\033[36m"

def main():
    print(f"{CYAN}>>> Iris NPU Validator (Basic Mode){RESET}")
    
    # 1. Prepara Dados (Mesma seed do treinamento Golden)
    iris = datasets.load_iris()
    X = iris.data; y = iris.target
    
    # Split
    X_train, X_test, y_train, y_test = train_test_split(X, y, test_size=0.3, random_state=42, stratify=y)
    
    # Normalização
    scaler = StandardScaler()
    scaler.fit(X_train) # Fit no treino
    X_test = scaler.transform(X_test) # Transform no teste
    
    # Quantização (Scale 4.0)
    SCALE = 4.0
    X_test_int = np.clip(np.round(X_test * SCALE), -128, 127).astype(int)

    # 2. Conexão
    try:
        ser = serial.Serial('COM6', 115200, timeout=2)
        time.sleep(2)
        ser.reset_input_buffer()
        print("Conectado na COM6")
    except Exception as e:
        print(f"{RED}Erro Serial: {e}{RESET}"); return

    correct = 0
    total = len(y_test)
    
    print("-" * 60)
    print(f"{'ID':<4} | {'REAL':<6} | {'PRED':<6} | {'SCORES':<15} | STATUS")
    print("-" * 60)

    for i, (vec, real) in enumerate(zip(X_test_int, y_test)):
        # Envia Header + Dados
        payload = struct.pack('Bbbbb', 0xA5, vec[0], vec[1], vec[2], vec[3])
        ser.write(payload)
        
        # Lê Resposta (5 bytes)
        resp = ser.read(5)
        
        if len(resp) != 5 or resp[0] != 0x5A:
            print(f"{i:<4} | {RED}SYNC ERROR{RESET}")
            ser.reset_input_buffer()
            continue
            
        scores = struct.unpack('bbbb', resp[1:])
        class_scores = scores[:3]
        pred = np.argmax(class_scores)
        
        if pred == real:
            correct += 1
            status = f"{GREEN}OK{RESET}"
        else:
            status = f"{RED}FAIL{RESET}"
            
        scores_str = f"[{class_scores[0]:>3}, {class_scores[1]:>3}, {class_scores[2]:>3}]"
        print(f"{i+1:<4} | {real:<6} | {pred:<6} | {scores_str:<15} | {status}")

    acc = (correct / total) * 100
    print("-" * 60)
    if acc > 95.0:
        color = GREEN
    elif acc > 90.0:
        color = CYAN
    else:
        color = RED
    print(f"Acurácia Final: {color}{acc:.2f}%{RESET}")
    ser.close()

if __name__ == "__main__":
    main()