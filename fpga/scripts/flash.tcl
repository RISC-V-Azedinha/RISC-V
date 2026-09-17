puts "\n--------------------------------------------------------------------------------------------------------------------------------"
puts ">>> Gravando SoC na memoria Flash...\n"

source [file join [file dirname [info script]] board.tcl]

set topEntity "soc_top"
set mcsPath "$outputDir/bitstream/${topEntity}.mcs"

if {![file exists $mcsPath]} {
    puts "!!! ERRO: Arquivo MCS nao encontrado: $mcsPath (rode 'make fpga-build BOARD=$boardName')"
    exit 1
}

open_hw_manager
connect_hw_server
open_hw_target

set device [lindex [get_hw_devices] 0]
current_hw_device $device

# Reduz a velocidade para garantir estabilidade (3 MHz)
set target [current_hw_target]
set_property PARAM.FREQUENCY 3000000 $target

# Configura a memoria Flash da placa (definida em board.tcl)
set cfgmem_obj [lindex [get_cfgmem_parts $flashPart] 0]
if {$cfgmem_obj eq ""} {
    puts "!!! ERRO: Memoria Flash '$flashPart' nao reconhecida pelo Vivado (defina FLASH_PART=...)"
    exit 1
}
set mem_device [create_hw_cfgmem -hw_device $device $cfgmem_obj]

puts ">>> Dispositivo Flash configurado: [get_property NAME $cfgmem_obj]"
puts ">>> Arquivo alvo: $mcsPath"

set_property PROGRAM.FILES [list $mcsPath] $mem_device
set_property PROGRAM.PRM_FILE {} $mem_device
set_property PROGRAM.ADDRESS_RANGE {use_file} $mem_device
set_property PROGRAM.BLANK_CHECK  0 $mem_device
set_property PROGRAM.ERASE  1 $mem_device
set_property PROGRAM.CFG_PROGRAM  1 $mem_device
set_property PROGRAM.VERIFY  1 $mem_device

puts ">>> Apagando e programando a memoria Flash (Isso pode demorar alguns minutos)..."

# =================================================================================
# Bloco explícito de programação do Proxy Core antes da Flash
# =================================================================================
startgroup
create_hw_bitstream -hw_device $device [get_property PROGRAM.HW_CFGMEM_BITFILE $device]
program_hw_devices $device
refresh_hw_device $device

program_hw_cfgmem -hw_cfgmem $mem_device
endgroup

# Força o boot
boot_hw_device $device

close_hw_target
close_hw_manager
puts ">>> Sucesso! Circuito salvo na memoria nao-volatil."
puts "\n--------------------------------------------------------------------------------------------------------------------------------"
exit