// Endereço para saída de NÚMEROS (formato int)
#define INT_OUTPUT (*((volatile int*)0x10000004))

int main() {

    volatile int n = 47;
    volatile int a = 0;
    volatile int b = 1;
    volatile int temp;

    for (volatile int i = 0; i < n; i++) {

        // Envia o NÚMERO diretamente para a saída de inteiros
        INT_OUTPUT = a;      

        // Calcula o próximo termo
        temp = a + b;
        a = b;
        b = temp;
    
    }

    return 0;

}