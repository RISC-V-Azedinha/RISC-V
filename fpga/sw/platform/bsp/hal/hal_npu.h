#ifndef HAL_NPU_H
#define HAL_NPU_H

#include <stdint.h>

/* Definições de Flags de Controle (para facilitar o uso) */
#define NPU_CTRL_RELU       (1 << 0)
#define NPU_CTRL_LOAD       (1 << 1)
#define NPU_CTRL_CLEAR      (1 << 2)
#define NPU_CTRL_DUMP       (1 << 3)

/*
 * Inicializa a NPU (Zera controle, limpa FIFOs se necessário).
 */
void hal_npu_init(void);

/*
 * Configura os parâmetros de quantização e escala.
 * shift: Quantos bits deslocar à direita (divisão por 2^n).
 * zero_point: Valor de ponto zero (para soma pós-scaling).
 * multiplier: Fator multiplicativo da PPU.
 */
void hal_npu_config(uint8_t shift, uint8_t zero_point, uint32_t multiplier);

/*
 * Define o registrador de controle diretamente.
 * Ex: hal_npu_set_ctrl(NPU_CTRL_RELU | NPU_CTRL_LOAD);
 */
void hal_npu_set_ctrl(uint32_t flags);

/*
 * Envia um pacote de 4 pesos (Int8) para a FIFO de Pesos.
 * (Blocking: Espera se a FIFO estiver cheia).
 * Os pesos devem estar empacotados: [w3, w2, w1, w0] (w0 é o byte menos significativo).
 */
void hal_npu_write_weight(int8_t w0, int8_t w1, int8_t w2, int8_t w3);

/*
 * Envia um pacote de 4 ativações (Int8) para a FIFO de Entrada.
 * (Blocking: Espera se a FIFO estiver cheia).
 */
void hal_npu_write_input(int8_t i0, int8_t i1, int8_t i2, int8_t i3);

/*
 * Lê um pacote de 4 resultados (Int8) da FIFO de Saída.
 * (Blocking: Espera até que o dado esteja disponível).
 */
uint32_t hal_npu_read_output(void);

/*
 * Verifica se há resultado pronto para leitura.
 * Retorna: 1 se houver dado, 0 se vazio.
 */
int hal_npu_result_ready(void);

#endif /* HAL_NPU_H */