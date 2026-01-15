#include "tiny_ml.h"
#include "hal/hal_uart.h" 

void ml_init(void) {
    npu_reset_system();
}

static int8_t clamp_i8(int32_t x) {
    if (x > 127) return 127;
    if (x < -128) return -128;
    return (int8_t)x;
}

void ml_run_layer(const layer_dense_t* layer, const int8_t* input, int8_t* output) {
    // 1. Configura NPU para modo "Raw Accumulation"
    // Deixa o HW somar sem aplicar shift/mult ainda
    int32_t zero_bias[4] = {0,0,0,0};
    npu_configure(0, 1, zero_bias, 0); 

    // Loop pelos Neurônios de Saída (Blocos de 4)
    for (int out_grp = 0; out_grp < layer->out_neurons; out_grp += 4) {
        
        // Acumuladores na CPU (Inicia com Bias)
        int32_t acc[4];
        for(int k=0; k<4; k++) {
            if (out_grp + k < layer->out_neurons)
                acc[k] = layer->bias[out_grp + k];
            else
                acc[k] = 0;
        }

        // Loop pelas Entradas (Blocos de 4)
        for (int in_grp = 0; in_grp < layer->in_features; in_grp += 4) {
            
            // 1. Carrega Pesos
            mat4_t w_chunk;
            for (int col = 0; col < 4; col++) { 
                for (int row = 0; row < 4; row++) { 
                    int out_idx = out_grp + col;
                    int in_idx  = in_grp + row;
                    
                    if (out_idx < layer->out_neurons && in_idx < layer->in_features) {
                        w_chunk.data[row][col] = layer->weights[out_idx * layer->in_features + in_idx];
                    } else {
                        w_chunk.data[row][col] = 0;
                    }
                }
            }
            npu_load_weights(&w_chunk);

            // 2. Prepara Input
            vec4_t v_in;
            for(int k=0; k<4; k++) {
                if (in_grp + k < layer->in_features)
                    v_in.val[k] = input[in_grp + k];
                else
                    v_in.val[k] = 0;
            }

            // 3. Executa NPU
            vec4_t res = npu_execute(v_in);

            // 4. Acumula na CPU
            for(int k=0; k<4; k++) acc[k] += res.val[k];
        }

        // Pós-Processamento (Quantização e Ativação)
        for(int k=0; k<4; k++) {
            if (out_grp + k < layer->out_neurons) {
                
                int32_t scaled = acc[k] * (int32_t)layer->output_mult;
                int32_t shifted = scaled >> layer->output_shift;
                
                // ReLU
                if (layer->use_relu && shifted < 0) shifted = 0;
                
                // Clamp e Salva
                output[out_grp + k] = clamp_i8(shifted);
            }
        }
    }
}