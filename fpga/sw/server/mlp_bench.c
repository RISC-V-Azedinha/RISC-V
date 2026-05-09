/**
 * @file main.c
 * @brief Firmware Edge AI (RISC-V) com suporte a HIL, DMA e Benchmark CPU vs NPU.
 *        Versão Otimizada (Loop Unrolling na CPU).
 */

#include <stdint.h>
#include "memory_map.h"
#include "hal/hal_uart.h"
#include "hal/hal_dma.h"
#include "hal/hal_timer.h"

// ============================================================================
// ALOCAÇÃO DE MEMÓRIA (Rede Neural)
// ============================================================================
__attribute__((aligned(4))) uint32_t W1_packed[25088]; // 100 KB
__attribute__((aligned(4))) int32_t  B1[128];
__attribute__((aligned(4))) uint32_t W2_packed[384];   // 1.5 KB
__attribute__((aligned(4))) int32_t  B2[12];           // Padding para 12

__attribute__((aligned(4))) int8_t input_image[784];
__attribute__((aligned(4))) int8_t hidden_acts[128];
__attribute__((aligned(4))) int8_t output_logits[10];

// ============================================================================
// FUNÇÕES AUXILIARES DA UART
// ============================================================================
uint32_t uart_read_uint32_be(void) {
    uint32_t val = 0;
    val |= ((uint32_t)hal_uart_getc() & 0xFF) << 24;
    val |= ((uint32_t)hal_uart_getc() & 0xFF) << 16;
    val |= ((uint32_t)hal_uart_getc() & 0xFF) << 8;
    val |= ((uint32_t)hal_uart_getc() & 0xFF) << 0;
    return val;
}

void uart_print_uint(uint64_t val) {
    char buf[20];
    int i = 0;
    if (val == 0) { hal_uart_putc('0'); return; }
    while (val > 0) {
        buf[i++] = (val % 10) + '0';
        val /= 10;
    }
    while (i > 0) {
        hal_uart_putc(buf[--i]);
    }
}

// ============================================================================
// INFERÊNCIA EM SOFTWARE (CPU RISC-V) - >> CORRIGIDA <<
// ============================================================================
void cpu_run_layer(uint32_t* weights_packed, int32_t* biases, int8_t* inputs, int8_t* outputs,
                   int in_features, int out_features, uint32_t mult, uint32_t shift, int apply_relu) {
    
    // Processa de 4 em 4 neurônios de saída (alinhado com o empacotamento do Python/NPU)
    for (int chunk_start = 0; chunk_start < out_features; chunk_start += 4) {
        int chunk_size = (out_features - chunk_start < 4) ? (out_features - chunk_start) : 4;
        int chunk_idx = chunk_start / 4;

        // Inicializa 4 acumuladores paralelos com os biases
        int32_t acc0 = (chunk_size > 0) ? biases[chunk_start + 0] : 0;
        int32_t acc1 = (chunk_size > 1) ? biases[chunk_start + 1] : 0;
        int32_t acc2 = (chunk_size > 2) ? biases[chunk_start + 2] : 0;
        int32_t acc3 = (chunk_size > 3) ? biases[chunk_start + 3] : 0;

        // Loop Interno: Varre as entradas UMA ÚNICA VEZ para as 4 saídas
        for (int in_idx = 0; in_idx < in_features; in_idx++) {
            // Um único acesso à memória
            uint32_t w_pack = weights_packed[chunk_idx * in_features + in_idx];
            int8_t in_val = inputs[in_idx];

            // Extrai os 4 pesos do pacote e multiplica
            if (chunk_size > 0) acc0 += in_val * (int8_t)((w_pack >> 0)  & 0xFF);
            if (chunk_size > 1) acc1 += in_val * (int8_t)((w_pack >> 8)  & 0xFF);
            if (chunk_size > 2) acc2 += in_val * (int8_t)((w_pack >> 16) & 0xFF);
            if (chunk_size > 3) acc3 += in_val * (int8_t)((w_pack >> 24) & 0xFF);
        }

        // PPU Software e Armazenamento (processa os 4 resultados)
        int32_t accs[4] = {acc0, acc1, acc2, acc3};

        for (int b = 0; b < chunk_size; b++) {
            int32_t acc = accs[b];

            // Quantização (Shift)
            acc = (acc * mult) >> shift;

            // Ativação ReLU
            if (apply_relu && acc < 0) acc = 0;

            // Clamping para INT8
            if (acc > 127) acc = 127;
            else if (acc < -128) acc = -128;

            outputs[chunk_start + b] = (int8_t)acc;
        }
    }
}

// ============================================================================
// INFERÊNCIA EM HARDWARE (NPU + DMA)
// ============================================================================
void npu_run_layer(uint32_t* weights_packed, int32_t* biases, int8_t* inputs, int8_t* outputs,
                   int in_features, int out_features, uint32_t mult, uint32_t shift, int apply_relu) {

    // Configura PPU
    MMIO32(NPU_BASE_ADDR + 0x44) = mult;   
    MMIO32(NPU_BASE_ADDR + 0x40) = shift;  
    MMIO32(NPU_BASE_ADDR + 0x48) = apply_relu ? 1 : 0; 

    // Reset Total
    MMIO32(NPU_BASE_ADDR + 0x04) = 0xC1; 

    // Carrega Ativações (Inputs)
    for (int k = 0; k < in_features; k++) {
        MMIO32(NPU_BASE_ADDR + 0x14) = inputs[k] & 0xFF; 
    }

    int chunk_idx = 0;
    for (int chunk_start = 0; chunk_start < out_features; chunk_start += 4) {
        int chunk_size = (out_features - chunk_start < 4) ? (out_features - chunk_start) : 4;

        for (int b = 0; b < 4; b++) {
            if (b < chunk_size) MMIO32(NPU_BASE_ADDR + 0x80 + (b * 4)) = biases[chunk_start + b];
            else MMIO32(NPU_BASE_ADDR + 0x80 + (b * 4)) = 0; 
        }

        MMIO32(NPU_BASE_ADDR + 0x04) = (1 << 6); 
        
        // Dispara o DMA
        uint32_t src_addr = (uint32_t)(&weights_packed[chunk_idx * in_features]);
        hal_dma_memcpy(src_addr, NPU_BASE_ADDR + 0x10, in_features, 1);

        MMIO32(NPU_BASE_ADDR + 0x08) = in_features; 
        MMIO32(NPU_BASE_ADDR + 0x04) = 0x36;        

        // Bloqueio seguro: Aguarda sair de IDLE e depois aguarda DONE
        while (!(MMIO32(NPU_BASE_ADDR + 0x00) & (1 << 0))); 
        while (!(MMIO32(NPU_BASE_ADDR + 0x00) & (1 << 1))); 

        // Descarta lixo das outras linhas não usadas do Array
        uint32_t trash, valid_res;
        while (!(MMIO32(NPU_BASE_ADDR + 0x00) & (1 << 3))); trash = MMIO32(NPU_BASE_ADDR + 0x18);
        while (!(MMIO32(NPU_BASE_ADDR + 0x00) & (1 << 3))); trash = MMIO32(NPU_BASE_ADDR + 0x18);
        while (!(MMIO32(NPU_BASE_ADDR + 0x00) & (1 << 3))); trash = MMIO32(NPU_BASE_ADDR + 0x18);
        while (!(MMIO32(NPU_BASE_ADDR + 0x00) & (1 << 3))); valid_res = MMIO32(NPU_BASE_ADDR + 0x18);

        // Guarda o resultado
        if (chunk_size > 0) outputs[chunk_start + 0] = (int8_t)((valid_res >> 0)  & 0xFF);
        if (chunk_size > 1) outputs[chunk_start + 1] = (int8_t)((valid_res >> 8)  & 0xFF);
        if (chunk_size > 2) outputs[chunk_start + 2] = (int8_t)((valid_res >> 16) & 0xFF);
        if (chunk_size > 3) outputs[chunk_start + 3] = (int8_t)((valid_res >> 24) & 0xFF);

        chunk_idx++;
    }
}

// ============================================================================
// ROTINA PRINCIPAL (SERVIÇO HIL & BENCHMARK)
// ============================================================================
int main(void) {
    hal_uart_init();
    hal_timer_reset(); 

    while(1) {
        uint8_t cmd = hal_uart_getc();

        // Download dos Pesos (Setup)
        if (cmd == 0xAA) {
            for(int i = 0; i < 25088; i++) W1_packed[i] = uart_read_uint32_be();
            hal_uart_putc('A'); 
        }
        else if (cmd == 0xBB) {
            for(int i = 0; i < 128; i++) B1[i] = (int32_t)uart_read_uint32_be();
            hal_uart_putc('B');
        }
        else if (cmd == 0xCC) {
            for(int i = 0; i < 384; i++) W2_packed[i] = uart_read_uint32_be();
            hal_uart_putc('C');
        }
        else if (cmd == 0xDD) {
            for(int i = 0; i < 12; i++) B2[i] = (int32_t)uart_read_uint32_be();
            hal_uart_putc('D');
        }

        // Inferência Normal na NPU (Retorna os Logits)
        else if (cmd == 0xFF) {
            for(int i = 0; i < 784; i++) input_image[i] = (int8_t)hal_uart_getc();
            npu_run_layer(W1_packed, B1, input_image, hidden_acts, 784, 128, 1, 9, 1);
            npu_run_layer(W2_packed, B2, hidden_acts, output_logits, 128, 10, 1, 9, 0);
            for(int i = 0; i < 10; i++) hal_uart_putc((char)output_logits[i]);
        }

        // Benchmark (Corre na CPU, depois na NPU, retorna Ciclos)
        else if (cmd == 0xEE) {
            uint64_t start_cpu, end_cpu, start_npu, end_npu;

            // Corrida CPU
            start_cpu = hal_timer_get_cycles();
            cpu_run_layer(W1_packed, B1, input_image, hidden_acts, 784, 128, 1, 9, 1);
            cpu_run_layer(W2_packed, B2, hidden_acts, output_logits, 128, 10, 1, 9, 0);
            end_cpu = hal_timer_get_cycles();

            // Corrida NPU
            start_npu = hal_timer_get_cycles();
            npu_run_layer(W1_packed, B1, input_image, hidden_acts, 784, 128, 1, 9, 1);
            npu_run_layer(W2_packed, B2, hidden_acts, output_logits, 128, 10, 1, 9, 0);
            end_npu = hal_timer_get_cycles();

            // Envia Resposta
            hal_uart_puts("CPU_CYCLES:");
            uart_print_uint(end_cpu - start_cpu);
            hal_uart_puts(",NPU_CYCLES:");
            uart_print_uint(end_npu - start_npu);
            hal_uart_puts("\n");
        }
    }
    return 0;
}