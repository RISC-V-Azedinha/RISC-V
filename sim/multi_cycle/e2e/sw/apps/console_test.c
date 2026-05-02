// Aponta para o nosso endereço de console mapeado em memória (MMIO)
#define console_output (*((volatile char*)0x10000000))

void print_start() {

    // Imprime apenas um caractere
    console_output = 'S'; 
    console_output = 'T';
    console_output = 'A';
    console_output = 'R';
    console_output = 'T';
    console_output = '\n';
    
}

int main() {

    // Imprime "START\n" iterativamente
    for(int n = 1; n <= 5; n++) {
        print_start();
    }

    // Finaliza o código
    return 0;

}