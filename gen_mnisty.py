import numpy as np
import urllib.request
import os
from sklearn.neural_network import MLPClassifier
from sklearn.model_selection import train_test_split

def load_mnist_robust():
    """
    Baixa o MNIST diretamente de um mirror estável (Google Storage) em formato .npz.
    Evita os erros constantes da API do OpenML.
    """
    path = "mnist.npz"
    url = "https://storage.googleapis.com/tensorflow/tf-keras-datasets/mnist.npz"
    
    # 1. Baixa se não existir
    if not os.path.exists(path):
        print(f">>> Baixando MNIST de {url}...")
        urllib.request.urlretrieve(url, path)
        print(">>> Download concluído.")
    
    # 2. Carrega com Numpy
    print(">>> Carregando dados do arquivo local...")
    with np.load(path, allow_pickle=True) as f:
        x_train, y_train = f['x_train'], f['y_train']
        x_test, y_test = f['x_test'], f['y_test']
    
    # 3. Concatena tudo 
    X = np.concatenate([x_train, x_test])
    y = np.concatenate([y_train, y_test])
    
    # 4. Flatten (28x28 -> 784) e Normalização (0-255 -> 0-1)
    X = X.reshape(-1, 784).astype(np.float32) / 255.0
    
    return X, y

def hard_sim_layer(input_i8, w_i8, b_i32, shift, relu=False):
    acc = np.dot(input_i8, w_i8.T) + b_i32
    output = np.floor(acc / (2**shift)).astype(int)
    if relu: output = np.maximum(output, 0)
    return np.clip(output, -128, 127)

def export_mnist_header(clf, X_test, y_test, scale, shift):
    print(">>> Exportando fpga/sw/apps/weights_mnist.h ...")
    
    w1 = clf.coefs_[0].T; b1 = clf.intercepts_[0]
    w2 = clf.coefs_[1].T; b2 = clf.intercepts_[1]
    
    # Quantização
    w1_i8 = np.clip(np.round(w1 * scale), -128, 127).astype(int)
    b1_i32 = np.round(b1 * scale * scale).astype(int)
    w2_i8 = np.clip(np.round(w2 * scale), -128, 127).astype(int)
    b2_i32 = np.round(b2 * scale * scale).astype(int)
    
    print(f"   [Info] Tamanho dos Pesos L1: {w1_i8.nbytes / 1024:.1f} KB")
    
    # Garante que a pasta existe
    os.makedirs("fpga/sw/apps", exist_ok=True)

    with open("fpga/sw/apps/weights_mnist.h", "w") as f:
        f.write("#ifndef WEIGHTS_MNIST_H\n#define WEIGHTS_MNIST_H\n#include <stdint.h>\n\n")
        f.write(f"#define MNIST_SHIFT {shift}\n\n")
        
        # Layer 1: 784 -> 64
        f.write("const int8_t W1_DATA[] = {\n")
        for row in w1_i8: f.write("    " + ", ".join(map(str, row)) + ",\n")
        f.write("};\nconst int32_t B1_DATA[] = {\n")
        f.write("    " + ", ".join(map(str, b1_i32)) + "\n};\n")
        
        # Layer 2: 64 -> 10
        f.write("const int8_t W2_DATA[] = {\n")
        for row in w2_i8: f.write("    " + ", ".join(map(str, row)) + ",\n")
        f.write("};\nconst int32_t B2_DATA[] = {\n")
        f.write("    " + ", ".join(map(str, b2_i32)) + "\n};\n")
        f.write("#endif\n")
    print(">>> Arquivo de cabeçalho gerado com sucesso!")

def main():

    X, y = load_mnist_robust()
    
    # Split 
    print(">>> Separando dados de treino/teste...")
    X_train, X_test, y_train, y_test = train_test_split(X, y, train_size=5000, test_size=1000, random_state=42)
    
    # Labels precisam ser inteiros (às vezes vêm como string do npz dependendo da versão)
    y_train = y_train.astype(int)
    y_test = y_test.astype(int)
    
    # Configuração de Quantização
    SCALE = 4.0
    SHIFT = 2
    
    print(">>> Treinando MLP (784->64->10)...")
    clf = MLPClassifier(hidden_layer_sizes=(64,), 
                        solver='adam', 
                        alpha=0.01, 
                        max_iter=100,
                        random_state=42, 
                        activation='relu')
    
    clf.fit(X_train, y_train)
    
    # Validação Rápida da Quantização
    print(">>> Validando precisão quantizada no PC...")
    correct = 0
    X_test_int = np.clip(np.round(X_test * SCALE), -128, 127).astype(int)
    
    # Extrai pesos para teste local
    w1_i8 = np.clip(np.round(clf.coefs_[0].T * SCALE), -128, 127).astype(int)
    b1_i32 = np.round(clf.intercepts_[0] * SCALE * SCALE).astype(int)
    w2_i8 = np.clip(np.round(clf.coefs_[1].T * SCALE), -128, 127).astype(int)
    b2_i32 = np.round(clf.intercepts_[1] * SCALE * SCALE).astype(int)
    
    # Teste em subconjunto para ser rápido
    test_limit = 1000
    for i in range(min(len(y_test), test_limit)):
        h = hard_sim_layer([X_test_int[i]], w1_i8, b1_i32, SHIFT, relu=True)[0]
        out = hard_sim_layer([h], w2_i8, b2_i32, SHIFT, relu=False)[0]
        if np.argmax(out) == int(y_test[i]): correct += 1
            
    acc = correct / min(len(y_test), test_limit)
    print(f"   Acurácia Simulada (Int8): {acc*100:.2f}%")
    
    export_mnist_header(clf, X_test, y_test, SCALE, SHIFT)

if __name__ == "__main__":
    main()