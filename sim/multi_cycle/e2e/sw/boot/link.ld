/* File: link.ld */
OUTPUT_ARCH("riscv")
ENTRY(_start)

MEMORY
{
  /* Nossa RAM unificada (IMem + DMem) começa no zero e tem 64KB */
  RAM (rwx) : ORIGIN = 0x00000000, LENGTH = 64K
}

SECTIONS
{
  .text : {
    *(.text.init)  /* Código de boot/startup deve ficar no endereço zero */
    *(.text)       /* O resto do código da aplicação */
    *(.text.*)
  } > RAM

  .rodata : {
    *(.rodata)
    *(.rodata.*)
  } > RAM

  .data : {
    *(.data)
    *(.data.*)
  } > RAM

  .bss : {
    __bss_start = .;
    *(.bss)
    *(.bss.*)
    *(COMMON)
    __bss_end = .;
  } > RAM

  /* Define o topo da pilha (Stack Pointer) no final da RAM */
  PROVIDE(__stack_top = ORIGIN(RAM) + LENGTH(RAM));
}