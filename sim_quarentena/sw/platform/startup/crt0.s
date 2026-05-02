.section .text
.globl _start

# Endereço de MMIO para sinalizar o fim da simulação
.equ HALT_MMIO, 0x10000008

_start:

    # -----------------------------------------------------------------
    # Inicializa o Stack Pointer (sp) para o final da RAM,
    # usando o símbolo fornecido pelo linker script (link.ld).
    # Isso garante que a pilha não colidirá com o programa.
    # -----------------------------------------------------------------
    
    # ANTES: li sp, 0x1000
    
    # DEPOIS (CORRIGIDO):
    lui sp, %hi(_stack_start)
    addi sp, sp, %lo(_stack_start)

    # -----------------------------------------------------------------
    # Pula para a função 'main' em C.
    # -----------------------------------------------------------------

    call main

    # -----------------------------------------------------------------
    # A simulação terminará quando a instrução abaixo for executada.
    # Isso garante que a simulação pare após o retorno de 'main'.
    # -----------------------------------------------------------------

    li a0, 1
    li t0, HALT_MMIO
    sw a0, 0(t0)
