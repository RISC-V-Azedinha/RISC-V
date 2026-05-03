/* File: crt0.s (C Run-Time 0) */
.section .text.init
.global _start

# Endereço de MMIO para sinalizar o fim da simulação
.equ HALT_MMIO, 0x10000008

_start:

    /* Carrega o Stack Pointer (sp = x2) com o topo da memória */
    la sp, __stack_top

    /* Pula para a função main() escrita em C */
    jal ra, main

    /* Quando a main() retornar, cairá no halt */

halt:
    
    # -----------------------------------------------------------------
    # A simulação terminará quando a instrução abaixo for executada.
    # Isso garante que a simulação pare após o retorno de 'main'.
    # -----------------------------------------------------------------

    li a0, 1
    li t0, HALT_MMIO
    sw a0, 0(t0)
