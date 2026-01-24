/**
 * @file main.c
 * @brief Firmware de Controle e Benchmarking para Systolic Neural Processing Unit (IRIS)
 * * Este módulo gerencia a comunicação entre um host (via UART) e a NPU hardware.
 * Permite a configuração de parâmetros de quantização, carga de tensores e 
 * execução de inferência comparativa entre CPU e Acelerador.
 */

#include <stdint.h>
#include <stdbool.h>
#include "hal/hal_uart.h"
#include "hal/hal_npu.h"
#include "hal/hal_dma.h"
#include "hal/hal_timer.h"

/* --- Definições e Constantes --- */
#define MAX_K_DIM 2048  // Capacidade máxima de profundidade do produto escalar

/* --- Memória de Trabalho (SRAM) --- */
// Alinhamento pode ser necessário dependendo da arquitetura do DMA
static uint32_t buffer_weights[MAX_K_DIM];
static uint32_t buffer_inputs[MAX_K_DIM];

/* --- Estado do Sistema --- */
typedef struct {
    uint32_t current_k;  // Dimensão atual dos vetores
    uint32_t mult;       // Fator multiplicativo de quantização
    uint32_t shift;      // Deslocamento binário (ponto fixo)
    bool     relu;       // Ativação Rectified Linear Unit
} npu_state_t;

static npu_state_t g_npu_ctx = {0, 1, 8, false};

/* --- Protótipos das Funções Auxiliares --- */
static void     uart_read_bytes(uint8_t *dest, uint32_t len);
static uint32_t uart_read_u32(void);
static void     uart_write_u32(uint32_t val);
static void     uart_write_u64(uint64_t val);
static void     cpu_inference(uint32_t *results_out);

/**
 * @brief Loop Principal: Máquina de Estados baseada em Comandos UART
 */
int main(void) {
    // Inicialização do Hardware Abstraction Layer (HAL)
    hal_uart_init();
    hal_npu_init();
    hal_npu_set_dma_enabled(true);

    // Envia sinal de pronto ('B' de Boot) para o Host Python
    hal_uart_putc('B'); 

    while (1) {
        uint8_t cmd = hal_uart_getc();

        switch (cmd) {
            /**
             * COMANDO 'C': Configuração de Parâmetros de Quantização
             * Protocolo: [Mult:u32][Shift:u32][ReLU:u32]
             */
            case 'C': { 
                g_npu_ctx.mult  = uart_read_u32(); 
                g_npu_ctx.shift = uart_read_u32();
                uint32_t r      = uart_read_u32(); 
                g_npu_ctx.relu  = (r > 0);
                hal_uart_putc('K'); // Acknowledge
                break;
            }

            /**
             * COMANDO 'W': Carga de Pesos (Weights)
             * Protocolo: [K:u32][Dados: K * 4 bytes]
             */
            case 'W': { 
                uint32_t k = uart_read_u32(); 
                if (k > MAX_K_DIM) k = MAX_K_DIM;
                
                g_npu_ctx.current_k = k;
                NPU_REG_CMD = NPU_CMD_RST_PTRS; // Reseta ponteiros internos da NPU
                
                uart_read_bytes((uint8_t*)buffer_weights, k * 4);
                hal_npu_load_weights(buffer_weights, k);
                
                hal_uart_putc('K'); 
                break;
            }

            /**
             * COMANDO 'I': Carga de Ativações (Inputs)
             * Protocolo: [K:u32][Dados: K * 4 bytes]
             */
            case 'I': { 
                uint32_t k = uart_read_u32(); 
                if (k > MAX_K_DIM) k = MAX_K_DIM;
                
                g_npu_ctx.current_k = k;
                uart_read_bytes((uint8_t*)buffer_inputs, k * 4);
                
                hal_uart_putc('K'); 
                break;
            }

            /**
             * COMANDO 'P': Handshake de Sincronia (Ping)
             */
            case 'P': { 
                hal_uart_putc('P'); 
                break;
            }

            /**
             * COMANDO 'B': Execução de Inferência e Benchmarking
             * Realiza a operação em CPU, NPU (PIO) e NPU (DMA) para medir performance.
             */
            case 'B': { 
                uint32_t flags = uart_read_u32();
                bool reuse_input = (flags & 1);

                uint64_t c_cpu, c_pio, c_dma;
                uint32_t result_cpu, result_hw;
                
                npu_quant_params_t q = { 
                    .mult  = g_npu_ctx.mult, 
                    .shift = g_npu_ctx.shift, 
                    .relu  = g_npu_ctx.relu 
                };
                
                // Configura a NPU com os parâmetros atuais
                hal_npu_configure(g_npu_ctx.current_k, &q);

                /* --- 1. Inferência via Software (CPU) --- */
                hal_timer_reset(); hal_timer_start();
                uint64_t t0 = hal_timer_get_cycles();
                cpu_inference(&result_cpu);
                c_cpu = hal_timer_get_cycles() - t0;

                /* --- 2. Inferência via Hardware (NPU - Programmed I/O) --- */
                hal_npu_set_dma_enabled(false);
                NPU_REG_CMD = NPU_CMD_RST_PTRS;
                
                // Se o input já estiver carregado, não re-carregamos para isolar o tempo de cálculo
                if (reuse_input) hal_npu_load_inputs(buffer_inputs, g_npu_ctx.current_k);

                hal_timer_reset(); hal_timer_start();
                t0 = hal_timer_get_cycles();
                if (!reuse_input) hal_npu_load_inputs(buffer_inputs, g_npu_ctx.current_k);
                hal_npu_load_weights(buffer_weights, g_npu_ctx.current_k);
                hal_npu_start(); 
                hal_npu_wait_done();
                c_pio = hal_timer_get_cycles() - t0;

                /* --- 3. Inferência via Hardware (NPU - DMA) --- */
                hal_npu_set_dma_enabled(true);
                NPU_REG_CMD = NPU_CMD_RST_PTRS;
                if (reuse_input) hal_npu_load_inputs(buffer_inputs, g_npu_ctx.current_k);

                hal_timer_reset(); hal_timer_start();
                t0 = hal_timer_get_cycles();
                if (!reuse_input) hal_npu_load_inputs(buffer_inputs, g_npu_ctx.current_k);
                hal_npu_load_weights(buffer_weights, g_npu_ctx.current_k);
                hal_npu_start(); 
                hal_npu_wait_done();
                c_dma = hal_timer_get_cycles() - t0;
                
                // Captura resultado final do hardware
                result_hw = NPU_REG_READ_OUT;

                // Transmissão de Resultados: [HW_RES:u32][Cycles_CPU:u64][Cycles_PIO:u64][Cycles_DMA:u64]
                uart_write_u32(result_hw);
                uart_write_u64(c_cpu);
                uart_write_u64(c_pio);
                uart_write_u64(c_dma);
                break;
            }

            default: break; // Comandos desconhecidos são ignorados
        }
    }
    return 0;
}

/**
 * @brief Simulação funcional da NPU em C (CPU)
 * * Realiza o produto escalar (dot product) com precisão de 8 bits,
 * acumuladores de 32 bits e posterior quantização com saturação.
 */
static void cpu_inference(uint32_t *results_out) {
    int32_t acc[4] = {0, 0, 0, 0};

    for (uint32_t k = 0; k < g_npu_ctx.current_k; k++) {
        uint32_t w_pack = buffer_weights[k];
        uint32_t i_pack = buffer_inputs[k];

        // Desempacotamento de vetores de 4 elementos (int8_t) de dentro do registro de 32 bits
        for (int n = 0; n < 4; n++) {
            int8_t weight = (int8_t)(w_pack >> (n * 8));
            int8_t input  = (int8_t)(i_pack >> (n * 8));
            acc[n] += (int32_t)input * (int32_t)weight;
        }
    }

    uint32_t packed_res = 0;
    for (int n = 0; n < 4; n++) {
        // Quantização: Aplicação de multiplicador e shift (Ponto Fixo)
        int32_t val = (acc[n] * (int32_t)g_npu_ctx.mult) >> g_npu_ctx.shift;
        
        // Ativação ReLU
        if (g_npu_ctx.relu && val < 0) val = 0;
        
        // Saturação (Clamping para int8_t)
        if (val > 127)  val = 127; 
        if (val < -128) val = -128;
        
        packed_res |= ((uint8_t)val & 0xFF) << (n * 8);
    }
    *results_out = packed_res;
}

/* --- Implementações de Baixo Nível (UART) --- */

static void uart_read_bytes(uint8_t *dest, uint32_t len) {
    for (uint32_t i = 0; i < len; i++) {
        dest[i] = hal_uart_getc();
    }
}

static uint32_t uart_read_u32(void) {
    uint8_t b[4];
    uart_read_bytes(b, 4);
    return (uint32_t)b[0] | ((uint32_t)b[1] << 8) | ((uint32_t)b[2] << 16) | ((uint32_t)b[3] << 24);
}

static void uart_write_u32(uint32_t val) {
    uint8_t b[4] = { val & 0xFF, (val >> 8) & 0xFF, (val >> 16) & 0xFF, (val >> 24) & 0xFF };
    for (int i = 0; i < 4; i++) hal_uart_putc(b[i]);
}

static void uart_write_u64(uint64_t val) {
    uart_write_u32((uint32_t)(val & 0xFFFFFFFF));
    uart_write_u32((uint32_t)(val >> 32));
}