OUTPUT_ARCH(riscv)
ENTRY(_start)

MEMORY {
  rom (rx) : ORIGIN = 0x00000000, LENGTH = 4K
  ram (rwx) : ORIGIN = 0x80000000, LENGTH = 128K 
}

SECTIONS {

    .text : { 
        *(.text*)      /* Código do programa */
        *(.rodata*)    /* Strings e constantes (Read-Only Data) */
    } > rom

    .data : { *(.data*) } > ram
    .bss  : { *(.bss*)  } > ram
    
    /* Stack no final da RAM */
    _stack_start = ORIGIN(ram) + LENGTH(ram);
}