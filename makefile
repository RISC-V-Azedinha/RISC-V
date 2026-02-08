# =============================================================================
#  RISC-V PROJECT MAIN MAKEFILE
# =============================================================================

# Default targets 

.PHONY: all help info clean detect-info
all: help

# Inclusão de Configuração (mk/config.mk carrega mk/detect.mk automaticamente)
include mk/config.mk

# Definição dos Fontes (VHDL)
include mk/sources.mk

# =============================================================================
#  TARGETS PRINCIPAIS
# =============================================================================

# Regras de Software (GCC, Bootloader)
include mk/rules_sw.mk

# Regras de Simulação (Cocotb, GTKWave)
include mk/rules_sim.mk

# Regras de FPGA (Vivado, Bitstream, Upload)
include mk/rules_fpga.mk

# =============================================================================
#  HELP & CLEANUP
# =============================================================================

.PHONY: help
help:
	@echo " "
	@echo " "
	@echo "      ██████╗ ██╗███████╗ ██████╗ ██╗   ██╗     "
	@echo "      ██╔══██╗██║██╔════╝██╔════╝ ██║   ██║     "
	@echo "      ██████╔╝██║███████╗██║█████╗██║   ██║     "
	@echo "      ██╔══██╗██║╚════██║██║╚════╝╚██╗ ██╔╝     "
	@echo "      ██║  ██║██║███████║╚██████╗  ╚████╔╝      "
	@echo "      ╚═╝  ╚═╝╚═╝╚══════╝ ╚═════╝   ╚═══╝       "
	@echo " "
	@echo "========================================================================================================="
	@echo "                         RISC-V Project Build System                                                     "
	@echo "========================================================================================================="
	@echo " "
	@echo " 📦 SOFTWARE COMPILATION"
	@echo " ────────────────────────────────────────────────────────────────────────────────────────────────────────"
	@echo "   make sw SW=<prog>                                            Compilar App (Detecta FPGA ou Simulação)"
	@echo "   make boot                                                    Compilar bootloader da FPGA"
	@echo "   make list-apps                                               Listar aplicações disponíveis"
	@echo " "
	@echo " 🧪 HARDWARE TESTING & SIMULATION"
	@echo " ────────────────────────────────────────────────────────────────────────────────────────────────────────"
	@echo "   make cocotb [CORE=<core>] TEST=<test> TOP=<top> [SW=<prog>]  Rodar teste COCOTB"
	@echo "   make cocotb TEST=<test> TOP=<top>                            Teste de componente (unit)"
	@echo "   make list-tests [CORE=<core>]                                Listar testes disponíveis"
	@echo " "
	@echo " 📊 VISUALIZATION & DEBUG"
	@echo " ────────────────────────────────────────────────────────────────────────────────────────────────────────"
	@echo "   make view TEST=<test>                                        Abrir ondas (VCD) no GTKWave"
	@echo " "
	@echo " 🔌 FPGA & UPLOAD "
	@echo " ─────────────────────────────────────────────────────────────────────────────────────────────────────"
	@echo "   make fpga                                                    Sintetizar e programar a FPGA"
	@echo "   make upload SW=<prog> [COM=<port>]                           Enviar software via UART"
	@echo " "
	@echo " ⚙️  INFORMAÇÕES & DEBUG"
	@echo " ────────────────────────────────────────────────────────────────────────────────────────────────────────"
	@echo "   make info                                                    Mostrar informações do sistema e config"
	@echo "   make detect-info                                             Mostrar detecção do SO e ferramentas"
	@echo " "
	@echo " 🧹 MAINTENANCE"
	@echo " ────────────────────────────────────────────────────────────────────────────────────────────────────────"
	@echo "   make clean                                                   Limpar diretório de build"
	@echo " "
	@echo "========================================================================================================="

# =============================================================================
#                            TARGETS ESPECÍFICOS
# =============================================================================

clean:
	@echo ">>> 🧹 Limpando diretório de build..."
	@rm -rf $(BUILD_DIR) *.cf
	@echo ">>> ✅ Limpeza concluída"

# =============================================================================
#  INFORMAÇÕES E DEBUG
# =============================================================================

info: detect-info
	@echo " "
	@echo "╔═════════════════════════════════════════════════════════════╗"
	@echo "║           CONFIGURAÇÃO DO PROJETO RISC-V                    ║"
	@echo "╚═════════════════════════════════════════════════════════════╝"
	@echo " "
	@echo "  Arquitetura Ativa    : $(CORE)"
	@echo "  Diretório de Build   : $(BUILD_DIR)"
	@echo " "

# =============================================================================
