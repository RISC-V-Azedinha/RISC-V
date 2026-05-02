OUTPUT_ARCH( "riscv" )
ENTRY( _start )
MEMORY {
  ram (rwx) : ORIGIN = 0x80000000, LENGTH = 2M
}
SECTIONS {
  .text : {
    *(.text.init)
    *(.text .text.*)
  } > ram
  .data : {
    *(.data .data.*)
    *(.sdata .sdata.*)
  } > ram
  .bss : {
    *(.bss .bss.*)
    *(.sbss .sbss.*)
  } > ram
  _end = .;
}