.section .text
.global _start

_start:
    # Inicializa o Stack Pointer (SP) definido no linker script
    la sp, _stack_start

    # Salta para a função main em C
    call main

    # Loop infinito caso o main retorne
_exit:
    j _exit
