#ifndef TINY_ML_H
#define TINY_ML_H

#include <stdint.h>
#include "npu_lib.h" 

// Estrutura de uma Camada Densa (Fully Connected)
typedef struct {
    const int8_t* weights; // Matriz Flattened [out_neurons][in_features]
    const int32_t* bias;   // Vetor de Bias [out_neurons]
    uint16_t in_features;  // Quantas entradas? (Ex: 784)
    uint16_t out_neurons;  // Quantas saídas? (Ex: 128)
    
    // Parâmetros de Quantização Pós-Acumulação
    uint8_t  output_shift;
    uint32_t output_mult;
    uint8_t  use_relu;
} layer_dense_t;

// Inicializa Engine
void ml_init(void);

// Roda uma camada densa de qualquer tamanho
// Entrada: input (int8)
// Saída: output (int8)
void ml_run_layer(const layer_dense_t* layer, const int8_t* input, int8_t* output);

#endif