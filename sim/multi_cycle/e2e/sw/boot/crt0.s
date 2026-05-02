/* File: crt0.s (C Run-Time 0) */

.section .text.init
.global _start
.align 2

# Endereço de MMIO para sinalizar o fim da simulação
.equ HALT_MMIO, 0x10000008

_start:

    /* 1. Zerar todos os registradores (GPRs) */
    # É uma boa prática para garantir determinismo e evitar 
    # que valores aleatórios de boot interfiram na lógica ou debug.

    li x1, 0
    # x2 (sp) será carregado logo abaixo
    li x3, 0
    li x4, 0
    li x5, 0
    li x6, 0
    li x7, 0
    li x8, 0
    li x9, 0
    li x10, 0
    li x11, 0
    li x12, 0
    li x13, 0
    li x14, 0
    li x15, 0
    li x16, 0
    li x17, 0
    li x18, 0
    li x20, 0
    li x21, 0
    li x22, 0
    li x23, 0
    li x24, 0
    li x25, 0
    li x26, 0
    li x27, 0
    li x28, 0
    li x29, 0
    li x30, 0
    li x31, 0

    /* 2. Inicializar registradores de controle (Zicsr) */
    # Configura o endereço base para o tratamento de interrupções/exceções

    la t0, trap_vector
    csrw mtvec, t0

    # Garante que as interrupções globais começam desabilitadas (mstatus.MIE = 0)
    # Isso evita interrupções antes da main() estar pronta.
    csrw mstatus, zero

    /* 3. Setup de Ponteiros (ABI RISC-V) */

    .option push
    .option norelax
    la gp, __global_pointer$  # Global Pointer para otimização de variáveis
    .option pop
    la sp, __stack_top        # Stack Pointer no topo da memória

    /* 4. Limpar a seção .bss (Zero-fill) */

    la a0, __bss_start
    la a1, __bss_end
    bge a0, a1, end_bss

zero_bss:

    sw zero, 0(a0)
    addi a0, a0, 4
    blt a0, a1, zero_bss

end_bss:

    /* 5. Chamar a main() */
    li a0, 0                  # argc = 0
    li a1, 0                  # argv = NULL
    jal ra, main

    /* 6. Halt / Exit */

halt:

    li a0, 1
    li t0, HALT_MMIO
    sw a0, 0(t0)

    # Caso a simulação continue por um ciclo extra:

1:  j 1b

/* Handler de Trap Minimalista */

.align 4
trap_vector:

    # Se o seu hardware entrar aqui sem você ter escrito um handler em C,
    # ele ficará preso aqui, facilitando o debug no GTKWave.
    j trap_vector