puts "\n--------------------------------------------------------------------------------------------------------------------------------"
puts ">>> [6/6] Tentando programar a placa...\n"

source [file join [file dirname [info script]] board.tcl]

set topEntity "soc_top"
set bitstreamPath "$outputDir/bitstream/${topEntity}.bit"

if {![file exists $bitstreamPath]} {
    puts "!!! ERRO: Bitstream nao encontrado: $bitstreamPath (rode 'make fpga-build BOARD=$boardName')"
    exit 1
}

open_hw_manager
connect_hw_server
open_hw_target

set device [lindex [get_hw_devices] 0]
current_hw_device $device
refresh_hw_device -update_hw_probes false $device

puts ">>> Programando dispositivo: $device"
set_property PROGRAM.FILE $bitstreamPath $device
program_hw_devices $device

close_hw_target
close_hw_manager
puts ">>> Sucesso! FPGA Programada."
puts "\n--------------------------------------------------------------------------------------------------------------------------------"
exit