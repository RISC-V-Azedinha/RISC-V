puts "\n--------------------------------------------------------------------------------------------------------------------------------"
puts ">>> Gravando SoC na memoria Flash...\n"

set topEntity "soc_top"
set mcsPath "./build/fpga/bitstream/${topEntity}.mcs"

open_hw_manager
connect_hw_server
open_hw_target

set device [lindex [get_hw_devices] 0]
current_hw_device $device

# Reduz a velocidade para garantir estabilidade (3 MHz)
set target [current_hw_target]
set_property PARAM.FREQUENCY 3000000 $target

# Configura o chip Spansion exato que a GUI detectou
set cfgmem_obj [lindex [get_cfgmem_parts {s25fl128sxxxxxx0-spi-x1_x2_x4}] 0]
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