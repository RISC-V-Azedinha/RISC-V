// Aponta para o endereço de console mapeado em memória (MMIO)
#define console_output (*((volatile char*)0x10000000))

// Função para impressão de uma cadeia de caracteres
void print_string(const char* s) {
    while (*s) console_output = *s++;
}

// Ponto de entrada do programa (chamado pelo start.s)
int main() {

    // Imprime "Hello, World!\n" iterativamente
    print_string("Hello, World!\n");

    // Finaliza o código (retorna para o start.s)
    return 0;

}