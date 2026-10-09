# ==========================================================================================
#                             SELECAO DE PLACA
# ==========================================================================================
#
# Incluído por build.tcl, program.tcl e flash.tcl. A placa é recebida como primeiro
# argumento do Vivado (vivado ... -tclargs <placa>), e define:
#
#   boardName   : nome da placa
#   targetPart  : part da FPGA usado na síntese
#   xdcFiles    : constraints (comuns + pinagem da placa)
#   flashPart   : memória Quad-SPI da placa (pode ser sobrescrita por FLASH_PART no ambiente)
#   outputDir   : diretório de saída (separado por placa, evita gravar bitstream da placa errada)

set boardName [expr {[llength $argv] > 0 ? [lindex $argv 0] : "nexys4"}]

switch -- $boardName {
    nexys4 {
        # Digilent Nexys 4 (XC7A100T-1CSG324C, Flash Spansion S25FL128S)
        set targetPart "xc7a100tcsg324-1"
        set flashPart  "s25fl128sxxxxxx0-spi-x1_x2_x4"
    }
    nexys_a7 {
        # Digilent Nexys A7-100T (XC7A100T-1CSG324C, Flash Spansion S25FL128S)
        set targetPart "xc7a100tcsg324-1"
        set flashPart  "s25fl128sxxxxxx0-spi-x1_x2_x4"
    }
    default {
        puts "!!! ERRO: Placa desconhecida '$boardName'. Opcoes: nexys4, nexys_a7"
        exit 1
    }
}

if {[info exists ::env(FLASH_PART)] && $::env(FLASH_PART) ne ""} {
    set flashPart $::env(FLASH_PART)
}

set xdcFiles [list "./fpga/constraints/common.xdc" "./fpga/constraints/${boardName}.xdc"]
set outputDir "./build/fpga/$boardName"

puts ">>> Placa alvo: $boardName ($targetPart)"
