#include <stdint.h>

#define GPIO_BASE 0x20000000
#define REG_LEDS  (*(volatile uint32_t *)(GPIO_BASE + 0x00))

void main() {
    // Variáveis locais (O GCC vai tentar colocá-las direto nos registradores)
    uint32_t t1, t2, nextTerm;

    // Pisca inicial para confirmar o boot
    REG_LEDS = 0xFFFF;
    REG_LEDS = 0x0000;

    while (1) {
        t1 = 0;
        t2 = 1;

        // Mostra o primeiro termo
        REG_LEDS = t2;

        // Loop principal (Gera cerca de 6 a 8 instruções Assembly)
        // Limitado a 23 repetições, pois Fib(24) = 46.368, que é o limite
        // máximo que cabe nos 16 LEDs da placa antes de estourar visualmente.
        for (int i = 0; i < 23; i++) {
            
            // Lógica do Fibonacci
            nextTerm = t1 + t2;
            t1 = t2;
            t2 = nextTerm;

            // Escreve fisicamente nos pinos da FPGA
            REG_LEDS = nextTerm; 
        }
    }
}