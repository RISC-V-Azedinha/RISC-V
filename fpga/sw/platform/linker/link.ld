OUTPUT_ARCH(riscv)
ENTRY(_start)

MEMORY
{
  /* Deixa os primeiros 2KB livres para dados do Bootloader (a RAM física vai até 0x8003FFFF) */
  ram (rwx) : ORIGIN = 0x80000800, LENGTH = 256K - 2K
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
        *(.sdata*)
    } > ram

    /* Zerada pelo start.s (__bss_start..__bss_end, alinhados em palavras) */
    .bss : {
        . = ALIGN(4);
        __bss_start = .;
        *(.sbss*)
        *(.bss*)
        *(COMMON)
        . = ALIGN(4);
        __bss_end = .;
    } > ram

    /* Define um símbolo no final da RAM. O topo da pilha começará aqui. */
    _stack_start = ORIGIN(ram) + LENGTH(ram);
}
