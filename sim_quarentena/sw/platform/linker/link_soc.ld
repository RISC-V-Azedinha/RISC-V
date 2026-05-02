OUTPUT_ARCH(riscv)
ENTRY(_start)

MEMORY
{
  /* Deixa os primeiros 2KB livres para dados do Bootloader */
  ram (rwx) : ORIGIN = 0x80000800, LENGTH = 14K
}

SECTIONS
{
    .text : {
        *(.text*)
    } > ram

    .rodata : {
        *(.rodata*)
    } > ram

    .data : {
        *(.data*)
    } > ram

    .bss : {
        *(.bss*)
        *(COMMON)
    } > ram

    /* Define um símbolo no final da RAM. O topo da pilha começará aqui. */
    _stack_start = ORIGIN(ram) + LENGTH(ram);
}
