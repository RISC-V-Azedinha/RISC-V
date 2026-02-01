/**
 * @file npu_irq_test.c
 * @brief Teste de Validação da NPU via Interrupção (IRQ)
 * 
 * * Este teste verifica a integração completa do hardware:
 * 1. Processador (CPU) envia dados e comandos.
 * 2. NPU processa em background.
 * 3. NPU sinaliza conclusão via interrupção.
 * 4. PLIC encaminha o sinal para a CPU.
 * 5. CPU trata o evento e verifica o resultado matemático.
 * 
 */

#include <stdint.h>
#include <stdbool.h>
#include "hal/hal_npu.h"
#include "hal/hal_uart.h"
#include "hal/hal_plic.h"
#include "hal/hal_irq.h"

// =========================================================
// CONFIGURAÇÕES E GLOBAIS
// =========================================================

// Profundidade da Acumulação (4 elementos)
#define K_DIM 4   

// Número de linhas do Array Sistólico
#define NUM_ROWS 4   

// Flag para avisar a conclusão da NPU
volatile bool g_npu_done = false;

// =========================================================
// INTERRUPT SERVICE ROUTINE (ISR)
// =========================================================

void my_npu_handler(void) {

    // Sinaliza para a aplicação principal que o trabalho terminou
    g_npu_done = true;

}

// =========================================================
// FUNÇÕES AUXILIARES
// =========================================================

// Imprime inteiros na UART (suporte a negativos)
void print_int(int val) {
    char buffer[16];
    int i = 0;
    
    if (val == 0) { 
        hal_uart_putc('0'); 
        return; 
    }
    
    if (val < 0) { 
        hal_uart_putc('-'); 
        val = -val; 
    }
    
    while (val > 0) {
        buffer[i++] = (val % 10) + '0';
        val /= 10;
    }
    
    while (i > 0) {
        hal_uart_putc(buffer[--i]);
    }
}

// =========================================================
// PROGRAMA PRINCIPAL
// =========================================================

int main() {

    // -------------------------------------------------------------------------
    // 1. Inicialização do Sistema
    // -------------------------------------------------------------------------

    hal_uart_init();
    hal_uart_puts("\n\r=== NPU IRQ TEST: VALIDACAO FUNCIONAL ===\n\r");

    hal_npu_init();
    hal_irq_init();

    // -------------------------------------------------------------------------
    // 2. Configuração das Interrupções
    // -------------------------------------------------------------------------
    
    // Registra nossa função handler para o ID da NPU
    hal_irq_register(PLIC_SOURCE_NPU, my_npu_handler);
    
    // Define prioridade > 0 (senão o PLIC ignora)
    hal_plic_set_priority(PLIC_SOURCE_NPU, 1);
    
    // Liga a chave geral de interrupções da CPU
    hal_irq_global_enable();

    // -------------------------------------------------------------------------
    // 3. Preparação do Cenário de Teste
    // -------------------------------------------------------------------------
    // Cenário: Produto Escalar (Dot Product) de vetores [10, 20, 30, 40] x [1, 1, 1, 1]
    // Esperado: (10*1) + (20*1) + (30*1) + (40*1) = 100
    
    uint32_t inputs[K_DIM]  = {10, 20, 30, 40};
    uint32_t weights[K_DIM] = {1, 1, 1, 1};

    hal_uart_puts(" -> Configurando NPU (K=4)...\n\r");
    npu_quant_params_t q = { .mult=1, .shift=0, .zero_point=0, .relu=false };
    hal_npu_configure(K_DIM, &q);

    hal_uart_puts(" -> Carregando Pesos e Entradas...\n\r");
    hal_npu_load_weights(weights, K_DIM);
    hal_npu_load_inputs(inputs, K_DIM);   
    
    // -------------------------------------------------------------------------
    // 4. Execução Assíncrona (Padrão Start-Before-Enable)
    // -------------------------------------------------------------------------
    
    g_npu_done = false;
    hal_uart_puts(" -> Disparando...\n\r");
    
    // [PASSO A]: Inicia o Hardware. 
    hal_npu_start(); 

    // [PASSO B]: Habilita a escuta no PLIC.
    hal_plic_enable(PLIC_SOURCE_NPU); 

    // [PASSO C]: Wait for Event (Bloqueante)
    // Aqui poderia ser feito processamento paralelo ou WFI
    while ( !g_npu_done );

    hal_uart_puts(" -> [IRQ] Evento Recebido! Processamento concluido.\n\r");

    // -------------------------------------------------------------------------
    // 5. Coleta e Validação
    // -------------------------------------------------------------------------
    
    // A NPU Systolic Array cospe os dados na ordem inversa de propagação.
    // Primeiro sai a última linha (Row 3), por último a primeira linha (Row 0).
    uint32_t result_buffer[NUM_ROWS];
    hal_npu_read_output(result_buffer, NUM_ROWS); 
    
    // Exibe Dump para Debug
    hal_uart_puts(" -> Dump da FIFO (Output):\n\r");
    for(int i=0; i < NUM_ROWS; i++) {
        hal_uart_puts("    Row "); 
        print_int(NUM_ROWS - 1 - i); // Mostra índice lógico (3, 2, 1, 0)
        hal_uart_puts(": "); 
        print_int(result_buffer[i]); 
        hal_uart_puts("\n\r");
    }

    // O nosso dado de interesse (caminho completo) está na Row 0.
    // Na leitura da FIFO, a Row 0 é o último dado a sair (índice 3).
    int obtido   = (int)result_buffer[3]; 
    int esperado = 100;

    hal_uart_puts(" -> Resultado Obtido:   "); print_int(obtido);   hal_uart_puts("\n\r");
    hal_uart_puts(" -> Resultado Esperado: "); print_int(esperado); hal_uart_puts("\n\r");

    if (obtido == esperado) hal_uart_puts("\n\r>>> SUCESSO: A NPU calculou corretamente. <<<\n\r");
    else hal_uart_puts("\n\r>>> FALHA: Divergencia numerica detectada! <<<\n\r");
    
    return 0;

}