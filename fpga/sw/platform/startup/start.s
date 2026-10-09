.section .text
.global _start

_start:
    # Inicializa o Stack Pointer (SP) definido no linker script
    la sp, _stack_start

    # Zera a .bss: variáveis globais sem valor inicial (ou "= 0") têm que começar em zero, mas a RAM
    # guarda o que o programa anterior deixou nela (por exemplo, o AXON-OS carregado do cartão SD)
    la t0, __bss_start
    la t1, __bss_end
1:  bgeu t0, t1, 2f
    sw zero, 0(t0)
    addi t0, t0, 4
    j 1b
2:

    # Salta para a função main em C
    call main

    # Loop infinito caso o main retorne
_exit:
    j _exit
