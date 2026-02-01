# ==========================================================================================
#                             CONFIGURACOES DO PROJETO
# ==========================================================================================

# Nome do Top Level
set topEntity "soc_top"

# Parte da FPGA (Digilent Nexys 4)
set targetPart "xc7a100tcsg324-1"

# Arquitetura do Core (multi_cycle)
set coreArch "multi_cycle"

# Define diretórios de saída
set outputDir "./build/fpga"
set bitDir    "$outputDir/bitstream"
set rptDir    "$outputDir/reports"
set dcpDir    "$outputDir/checkpoints"

# Cria a estrutura de pastas
file mkdir $outputDir
file mkdir $bitDir
file mkdir $rptDir
file mkdir $dcpDir

# ==========================================================================================
#                             PREPARACAO DO AMBIENTE
# ==========================================================================================
puts "\n--------------------------------------------------------------------------------------------------------------------------------"
puts ">>> [1/6] Configurando ambiente...\n"

# Suprime mensagens informativas padrao
set_msg_config -severity INFO -suppress
set_msg_config -severity STATUS -suppress

# Define o caminho do HEX de produção (FPGA)
set bootHex "build/fpga/boot/bootloader.hex"

# ==========================================================================================
#                             LEITURA DE FONTES
# ==========================================================================================
puts "\n--------------------------------------------------------------------------------------------------------------------------------"
puts ">>> [2/6] Lendo arquivos fonte do projeto RISC-V...\n"

proc read_dir {dir pattern} {
    if {[file exists $dir]} {
        set files [glob -nocomplain -directory $dir $pattern]
        if {[llength $files] > 0} {
            read_vhdl $files
        }
    }
}

# Packages do RISC-V
read_dir "./pkg" "*.vhd"
read_dir "./rtl/core/$coreArch" "*pkg.vhd"

# Arquivos da NPU
set npu_root "./rtl/perips/npu"

# NPU Package 
read_vhdl "$npu_root/pkg/npu_pkg.vhd"

# NPU Modules (Core, PPU, Common)
read_dir "$npu_root/rtl/common" "*.vhd"
read_dir "$npu_root/rtl/core"   "*.vhd"
read_dir "$npu_root/rtl/ppu"    "*.vhd"

# NPU Top Level
read_dir "$npu_root/rtl/"       "*.vhd"

# Core Common
read_dir "./rtl/core/common" "*.vhd"

# Core Architecture
set core_files [glob -nocomplain -directory "./rtl/core/$coreArch" "*.vhd"]
foreach f $core_files {
    if {[string first "pkg.vhd" $f] == -1} {
        read_vhdl $f
    }
}

# Outros Periféricos (GPIO, UART, VGA)
set perip_dirs [glob -nocomplain -type d "./rtl/perips/*"]
foreach dir $perip_dirs {
    if {[string first "npu" $dir] == -1} {
        read_dir $dir "*.vhd"
    }
}

# Lê arquivos soltos na raiz de perips (se houver)
read_dir "./rtl/perips" "*.vhd"

# SoC
read_dir "./rtl/soc" "*.vhd"

# Constraints
set xdc_file "./fpga/constraints/pins.xdc" 
if {[file exists $xdc_file]} {
    puts "    + Lendo Constraints: [file tail $xdc_file]"
    read_xdc $xdc_file
} else {
    puts "!!! ERRO: Arquivo de constraints nao encontrado: $xdc_file"
    exit 1
}

# ==========================================================================================
#                             SINTESE
# ==========================================================================================
puts "\n--------------------------------------------------------------------------------------------------------------------------------"
puts ">>> [3/6] Executando Sintese do Projeto...\n"

if {[catch {
    synth_design -top $topEntity -part $targetPart -generic "INIT_FILE=$bootHex" -flatten_hierarchy rebuilt -retiming -quiet
} err]} {
    puts "\n!!! FALHA NA SINTESE !!!"
    puts "$err"
    exit 1
}

write_checkpoint -force $dcpDir/post_synth.dcp
report_utilization -file $rptDir/utilization_synth.rpt

# ==========================================================================================
#                             IMPLEMENTACAO
# ==========================================================================================
puts "\n--------------------------------------------------------------------------------------------------------------------------------"
puts ">>> [4/6] Opt, Place & Route...\n"

if {[catch {
    opt_design -quiet
    place_design -quiet
    route_design -quiet
} err]} {
    puts "\n!!! FALHA NA IMPLEMENTACAO !!!"
    puts "$err"
    exit 1
}

write_checkpoint -force $dcpDir/post_route.dcp
report_utilization -file $rptDir/utilization_route.rpt
report_timing_summary -file $rptDir/timing_summary.rpt
report_power -file $rptDir/power.rpt

# ==========================================================================================
#                             BITSTREAM
# ==========================================================================================
puts "\n--------------------------------------------------------------------------------------------------------------------------------"
puts ">>> [5/6] Gerando Bitstream...\n"

write_bitstream -force $bitDir/${topEntity}.bit -quiet

puts " "
puts "================================================================"
puts "   SUCESSO! Bitstream gerado:"
puts "   $outputDir/${topEntity}.bit"
puts "================================================================"

if {[file exists "clockInfo.txt"]} {
    puts ">>> Movendo clockInfo.txt para $rptDir..."
    file rename -force "clockInfo.txt" "$rptDir/clockInfo.txt"
}

exit