/* File: link.ld */

OUTPUT_ARCH("riscv")
ENTRY(_start)

MEMORY
{
  /* RAM unificada (IMem + DMem) */
  RAM (rwx) : ORIGIN = 0x00000000, LENGTH = 64K
}

SECTIONS
{

  /* 1. Seção de código */
  
  .text : {
    . = ALIGN(4);
    *(.text.init)  /* Garante que o crt0.s (boot) fique no início */
    *(.text .text.*)
    . = ALIGN(4);
  } > RAM

  /* 2. Dados somente leitura (constantes, strings) */

  .rodata : {
    . = ALIGN(4);
    *(.rodata .rodata.*)
    *(.srodata .srodata.*)
    . = ALIGN(4);
  } > RAM

  /* 3. Dados inicializados */

  .data : {
    . = ALIGN(4);
    *(.data .data.*)
    
    /* O offset 0x800 (2048 bytes) permite acessar uma área de 4KB 
       com uma única instrução usando o registrador gp */
    __global_pointer$ = . + 0x800;
    
    *(.sdata .sdata.*) /* Small data: essencial para o gp */
    . = ALIGN(4);
  } > RAM

  /* 4. Dados não inicializados (zerados no boot) */
  .bss : {
    . = ALIGN(4);
    __bss_start = .;   /* Marca de início para o crt0.s */
    *(.sbss .sbss.*)   /* Small BSS */
    *(.bss .bss.*)
    *(COMMON)
    . = ALIGN(4);      /* Alinha o fim para garantir escrita de 4 bytes */
    __bss_end = .;     /* Marca de fim para o crt0.s */
  } > RAM

  /* 5. Definição da Pilha (Stack) */
  /* Colocamos no final da RAM. Ela cresce para baixo (em direção ao zero) */
  __stack_top = ORIGIN(RAM) + LENGTH(RAM);
}