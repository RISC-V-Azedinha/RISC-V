/**
 * @file hal_npu.c
 * @brief Camada de Abstração de Hardware (HAL) para a NPU.
 * 
 * Implementa a lógica de controle, configuração e transferência de dados
 * para o Acelerador Sistólico. Suporta dois modos de transferência:
 * 1. PIO (Programmed I/O): a CPU copia dados word-por-word.
 * 2. DMA (Direct Memory Access): o controlador DMA assume a cópia, liberando a CPU.
 *
 * @author André Maiolini
 * @date 23/01/2026
 */

#include "hal_npu.h"
#include "hal_dma.h"
#include "memory_map.h"

// ============================================================================
// DEFINIÇÕES PRIVADAS E ENDEREÇAMENTO
// ============================================================================

/* Endereços Físicos dos Portais de Escrita (FIFOs).
 * Necessários para o DMA, pois o DMA precisa saber para onde "despejar" os dados.
 * Estes offsets (+0x10, +0x14) devem coincidir com o mapa de registradores da FPGA.
 */

#define NPU_ADDR_FIFO_WEIGHTS   (NPU_BASE_ADDR + 0x10) // Porta de entrada de Pesos
#define NPU_ADDR_FIFO_INPUTS    (NPU_BASE_ADDR + 0x14) // Porta de entrada de Ativações

// Flag de controle do modo de operação (Default: PIO/Manual)
static bool s_use_dma = false;

// ============================================================================
// CONTROLE E ESTADO
// ============================================================================

/**
 * @brief Habilita ou desabilita o uso do DMA para transferências de dados.
 * @param enable true para usar DMA, false para usar CPU (PIO).
 */
void hal_npu_set_dma_enabled(bool enable) {
    s_use_dma = enable;
}

/**
 * @brief Inicializa a NPU, resetando ponteiros internos e FIFOs.
 */
void hal_npu_init(void) {
    // Envia comando de reset para os ponteiros de escrita dos buffers internos
    NPU_REG_CMD = NPU_CMD_RST_PTRS;
}

/**
 * @brief Verifica se a NPU está ocupada processando.
 * @return 1 se ocupada, 0 se ociosa (DONE).
 * Útil para evitar bloquear a CPU se quisermos fazer outras coisas.
 */
int hal_npu_is_busy(void) {
    // Se o bit DONE (bit 0) for 1, ela NÃO está ocupada.
    // Se DONE for 0, ela ESTÁ ocupada.
    return !(NPU_REG_STATUS & NPU_STATUS_DONE);
}

/**
 * @brief Bloqueia a execução (Polling) até que a NPU termine o processamento.
 * @note Em um sistema com OS, isso deveria ser substituído por uma interrupção.
 */
void hal_npu_wait_done(void) {
    // Bit 0 do STATUS indica DONE
    while (!(NPU_REG_STATUS & NPU_STATUS_DONE));
}

// ============================================================================
// CONFIGURAÇÃO
// ============================================================================

/**
 * @brief Configura os parâmetros da camada (Dimensão e Quantização).
 * * @param k_dim Profundidade do cálculo (quantas iterações de soma/produto).
 * @param quant Ponteiro para struct de quantização. Se NULL, usa bypass (1:1).
 */
void hal_npu_configure(uint32_t k_dim, npu_quant_params_t *quant) {
    // 1. Define a profundidade do loop sistólico
    NPU_REG_CONFIG = k_dim;

    // 2. Configura a aritmética de pós-processamento (Quantização)
    // Fórmula: Output = (Accumulator * mult) >> shift
    if (quant) {
        NPU_REG_QUANT_MULT = quant->mult;
        
        // Empacota Shift (5 bits) e Zero Point (8 bits) em um registrador
        NPU_REG_QUANT_CFG = (quant->shift & 0x1F) | 
                           ((quant->zero_point & 0xFF) << 8);
        
        // Configura Flags de ativação (Ex: ReLU)
        NPU_REG_FLAGS = quant->relu ? NPU_FLAG_RELU : 0;
    } else {
        // Configuração Padrão (Sem quantização, sem ReLU)
        NPU_REG_QUANT_MULT = 1;
        NPU_REG_QUANT_CFG  = 0;
        NPU_REG_FLAGS      = 0;
    }
}

// ============================================================================
// TRANSFERÊNCIA DE DADOS (DATA PATH)
// ============================================================================

/**
 * @brief Carrega os Pesos (Weights) para a memória interna da NPU.
 * Usa DMA ou CPU dependendo da flag 's_use_dma'.
 */
void hal_npu_load_weights(const uint32_t *data, uint32_t num_words) {
    if (num_words == 0) return;

    if (s_use_dma) {

        /* MODO DMA (Burst Transfer)
         * Src: Endereço do buffer na RAM.
         * Dst: Endereço da FIFO de Pesos (NPU).
         * Flag '1' no final indica "Fixed Destination Address":
         * O DMA não incrementa o endereço de destino, escrevendo sempre na mesma porta.
         */

        hal_dma_memcpy((uint32_t)data, NPU_ADDR_FIFO_WEIGHTS, num_words, 1);

    } else {

        /* MODO PIO (CPU Copy)
         * A CPU lê da RAM e escreve no registrador mapeado em memória.
         * Mais lento devido ao overhead de busca de instrução (Loop unrolling ajudaria).
         */

        volatile uint32_t *npu_port = (volatile uint32_t *)&NPU_REG_WRITE_W;
        for (uint32_t i = 0; i < num_words; i++) {
            *npu_port = data[i];
        }

    }

}

/**
 * @brief Carrega os Dados de Entrada (Inputs/Activations) para a NPU.
 */
void hal_npu_load_inputs(const uint32_t *data, uint32_t num_words) {
    if (num_words == 0) return;

    if (s_use_dma) {

        // MODO DMA: RAM -> NPU FIFO A
        hal_dma_memcpy((uint32_t)data, NPU_ADDR_FIFO_INPUTS, num_words, 1);

    } else {

        // MODO PIO: RAM -> NPU Reg A
        volatile uint32_t *npu_port = (volatile uint32_t *)&NPU_REG_WRITE_A;
        for (uint32_t i = 0; i < num_words; i++) {
            *npu_port = data[i];
        }

    }

}

/**
 * @brief Lê o resultado do processamento (Output Buffer).
 * @note Atualmente suporta apenas leitura via CPU (PIO).
 */
void hal_npu_read_output(uint32_t *buffer, uint32_t num_words) {

    // A leitura de output geralmente é pequena (ex: 1x4 pixels), 
    // então o overhead de configurar o DMA muitas vezes não compensa.
    for (uint32_t i = 0; i < num_words; i++) {
        buffer[i] = NPU_REG_READ_OUT;
    }

}

// ============================================================================
// EXECUÇÃO
// ============================================================================

/**
 * @brief Dispara o processamento sistólico.
 * Reseta ponteiros de leitura (para reusar dados se necessário) e limpa acumuladores.
 */
void hal_npu_start(void) {

    // CMD_START: Inicia a máquina de estados
    // RST_W/I_RD: Reinicia a leitura dos buffers internos do início (Reuso)
    // ACC_CLEAR: Zera os acumuladores antes de começar a somar
    NPU_REG_CMD = NPU_CMD_START | NPU_CMD_RST_W_RD | NPU_CMD_RST_I_RD | NPU_CMD_ACC_CLEAR;
    
}