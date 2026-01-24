#ifndef HAL_NPU_H
#define HAL_NPU_H

#include <stdint.h>
#include <stdbool.h>

// Estrutura para facilitar a configuração de Quantização
typedef struct {
    uint32_t mult;          // Multiplicador (Ponto Fixo)
    uint32_t shift;         // Shift à direita (0-31)
    uint32_t zero_point;    // Ponto Zero (Offset)
    bool     relu;          // true = Ativar ReLU, false = Desativar
} npu_quant_params_t;

// ============================================================================
// DMA
// ============================================================================

/*
 * Habilita ou desabilita o uso de DMA para transferências.
 * enable: true => tenta usar DMA se possível.
 *         false => força uso da CPU (loop de escrita).
 */
void hal_npu_set_dma_enabled(bool enable);

// ============================================================================
// CONTROLE E STATUS
// ============================================================================

/* 
 * Inicializa a NPU (reseta ponteiros globais e limpa estado).
 * Deve ser chamada antes de qualquer operação.
 */
void hal_npu_init(void);

/*
 * Verifica se a NPU está ocupada.
 * Retorna: 1 se 'busy', 0 se 'idle'.
 */
int hal_npu_is_busy(void);

/*
 * Aguarda a conclusão do processamento atual (Blocking).
 * Faz polling no bit DONE.
 */
void hal_npu_wait_done(void);

// ============================================================================
// CONFIGURAÇÃO
// ============================================================================

/*
 * Configura os parâmetros de execução.
 * k_dim: Profundidade da acumulação (número de iterações/ciclos).
 * quant: Ponteiro para struct com parâmetros de quantização.
 */
void hal_npu_configure(uint32_t k_dim, npu_quant_params_t *quant);

/*
 * Carrega o vetor de BIAS.
 * bias_buffer: Array de 4 valores (32-bit cada).
 */
void hal_npu_load_bias(const uint32_t *bias_buffer);

// ============================================================================
// TRANSFERÊNCIA DE DADOS
// ============================================================================

/*
 * Carrega Pesos (Weights) na FIFO interna.
 * data: Buffer de dados (já empacotados em 32-bit: int8x4).
 * num_words: Quantidade de palavras de 32 bits a escrever.
 */
void hal_npu_load_weights(const uint32_t *data, uint32_t num_words);

/*
 * Carrega Entradas (Inputs/Activations) na FIFO interna.
 * data: Buffer de dados (já empacotados em 32-bit: int8x4).
 * num_words: Quantidade de palavras de 32 bits a escrever.
 */
void hal_npu_load_inputs(const uint32_t *data, uint32_t num_words);

/*
 * Lê os resultados da FIFO de saída.
 * buffer: Onde os dados serão salvos.
 * num_words: Quantidade de palavras de 32 bits a ler.
 */
void hal_npu_read_output(uint32_t *buffer, uint32_t num_words);

// ============================================================================
// EXECUÇÃO
// ============================================================================

/*
 * Dispara a execução da NPU (Non-blocking).
 * Automaticamente aplica as flags de reset de leitura (RST_RD) e clear (ACC_CLEAR)
 * para garantir uma execução limpa padrão.
 */
void hal_npu_start(void);

/*
 * Dispara a execução SEM limpar os acumuladores.
 * Útil para operações de Tiling (quebrar matrizes grandes em pedaços).
 */
void hal_npu_start_accumulate(void);

#endif /* HAL_NPU_H */