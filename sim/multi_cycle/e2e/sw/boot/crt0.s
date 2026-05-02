/* File: crt0.s (C Run-Time 0) */
.section .text.init
.global _start

_start:
    /* Inicializa o registrador Zero (Hardwired no hardware, mas por garantia) */
    li x0, 0

    /* Carrega o Stack Pointer (sp = x2) com o topo da memória */
    la sp, __stack_top

    /* Pula para a função main() escrita em C */
    jal ra, main

    /* Se a main() retornar, cai num loop infinito de segurança */
halt:
    j halt
