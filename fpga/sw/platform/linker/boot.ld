OUTPUT_ARCH(riscv)
ENTRY(_start)

MEMORY {
  rom (rx) : ORIGIN = 0x00000000, LENGTH = 4K
  ram (rwx) : ORIGIN = 0x80000000, LENGTH = 256K 
}

SECTIONS {

    .text : { 
        *(.text*)      /* Código do programa */
        *(.rodata*)    /* Strings e constantes (Read-Only Data) */
    } > rom

    .data : { *(.data*) } > ram
    .bss  : { *(.bss*)  } > ram
    
    /* Stack nos 2 KB abaixo do app (0x80000800): carregar um app grande não sobrescreve a pilha */
    _stack_start = ORIGIN(ram) + 0x800;
}