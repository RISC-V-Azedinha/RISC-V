#ifndef NPU_LIB_H
#define NPU_LIB_H

#include <stdint.h>

// Estruturas de Dados Simples
typedef struct { int8_t val[4]; } vec4_t;
typedef struct { int8_t data[4][4]; } mat4_t;

// --- API ---

// Inicializa o sistema (Zera tudo)
void npu_reset_system(void);

// Configura parâmetros globais (Bias, Shift, ReLU)
void npu_configure(uint8_t shift, uint32_t mult, const int32_t bias[4], uint8_t use_relu);

// Carrega pesos (Faz a inversão de linhas automaticamente)
void npu_load_weights(const mat4_t* weights);

// Executa inferência (Cuida do Dummy Clear e Timing)
vec4_t npu_execute(vec4_t input);

// Helpers
vec4_t vec4(int8_t v0, int8_t v1, int8_t v2, int8_t v3);

#endif