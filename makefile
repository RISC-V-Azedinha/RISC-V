# ==========================================================================================
#                             RISC-V PROJECT CONFIGURATION
# ==========================================================================================
# Este makefile coordena a compilação de hardware (VHDL), software (C/ASM) e testes (COCOTB)
# ==========================================================================================

# ==========================================================================================
#                                 ESTRUTURA DE DIRETÓRIOS
# ==========================================================================================

# Diretório Base de Build
BUILD_DIR          = build

# --- CAMINHOS DE SOFTWARE (SEPARAÇÃO) ---
FPGA_SW_DIR        = fpga/sw
SIM_SW_DIR         = sim/sw
COMMON_SW_DIR      = sw/apps

# Saídas de Build Organizadas
BUILD_FPGA         = $(BUILD_DIR)/fpga
BUILD_SIM          = $(BUILD_DIR)/sim
# Bootloader específico para Simulação (Cocotb)
BUILD_COCOTB_BOOT  = $(BUILD_DIR)/cocotb/boot
# Bootloader específico para FPGA
BUILD_FPGA_BOOT    = $(BUILD_FPGA)/boot

# Estrutura de Hardware (RTL)
PKG_DIR            = pkg
RTL_DIR            = rtl
CORE_DIR           = $(RTL_DIR)/core
SOC_DIR            = $(RTL_DIR)/soc
PERIPS_DIR         = $(RTL_DIR)/perips
CORE_COMMON        = $(CORE_DIR)/common

# Estrutura de Simulação
SIM_DIR            = sim
SIM_CORE_DIR       = $(SIM_DIR)/core
SIM_CORE_COMMON    = $(SIM_CORE_DIR)/common
SIM_PERIPS_DIR     = $(SIM_DIR)/perips
SIM_SOC_DIR        = $(SIM_DIR)/soc
SIM_COMMON_DIR     = $(SIM_DIR)/common

# ==========================================================================================
#                                  FERRAMENTAS E COMPILADORES
# ==========================================================================================

# RISC-V GCC Toolchain
CC                 = riscv32-unknown-elf-gcc
OBJCOPY            = riscv32-unknown-elf-objcopy

# Compilação C/Assembly
BASE_CFLAGS        = -march=rv32i -mabi=ilp32 -nostdlib -nostartfiles -g

# Simulação e Visualização
GTKWAVE            = gtkwave
PYTHON             = python3

# COCOTB - CoSimulation Testbench Framework
COCOTB_SIM         = ghdl
COCOTB_SIMULATOR   = $(COCOTB_SIM)
COCOTB_BUILD       = $(BUILD_DIR)/cocotb
COCOTB_PYTHONPATH  = $(SIM_CORE_DIR):$(SIM_SOC_DIR):$(SIM_PERIPS_DIR):$(SIM_COMMON_DIR)

# Necessário para passar caminhos absolutos para o GHDL (Generic)
ABS_BUILD_DIR      = $(abspath $(BUILD_DIR))

# ==========================================================================================
#                              SELEÇÃO DINÂMICA DE CORE
# ==========================================================================================

CORE ?= multi_cycle

CORE_PATH           = $(CORE_DIR)/$(CORE)
CORE_EXISTS         = $(wildcard $(CORE_PATH))
ifeq ($(CORE_EXISTS),)
    $(error Arquitetura '$(CORE)' inválida! O diretório $(CORE_PATH) não existe.)
endif

CORE_CURRENT        = $(CORE_PATH)
SIM_CORE_CURRENT    = $(SIM_CORE_DIR)/$(CORE)
BUILD_CORE_DIR      = $(COCOTB_BUILD)/$(CORE)

# ==========================================================================================
#                                FONTES VHDL (Automático)
# ==========================================================================================

PKG_SRCS           = $(wildcard $(PKG_DIR)/*.vhd) $(CORE_CURRENT)/riscv_uarch_pkg.vhd
COMMON_SRCS        = $(wildcard $(CORE_COMMON)/*/*.vhd) $(wildcard $(CORE_COMMON)/*.vhd)
CORE_SRCS          = $(wildcard $(CORE_CURRENT)/*.vhd)
SOC_SRCS           = $(wildcard $(SOC_DIR)/*.vhd)
PERIPS_SRCS        = $(wildcard $(PERIPS_DIR)/*/*.vhd)

SIM_WRAPPERS_COMMON = $(wildcard $(SIM_CORE_DIR)/wrappers/*.vhd)
SIM_WRAPPERS_CORE   = $(wildcard $(SIM_CORE_CURRENT)/wrappers/*.vhd)
SIM_WRAPPERS_SOC    = $(wildcard $(SIM_SOC_DIR)/wrappers/*.vhd)
SIM_WRAPPERS        = $(SIM_WRAPPERS_COMMON) $(SIM_WRAPPERS_CORE) $(SIM_WRAPPERS_SOC)

ALL_RTL_SRCS       = $(PKG_SRCS) $(COMMON_SRCS) $(CORE_SRCS) $(SOC_SRCS) $(PERIPS_SRCS) $(SIM_WRAPPERS)

# ==========================================================================================
#                               TARGETS PADRÃO E AJUDA
# ==========================================================================================

.PHONY: all
all:
	@echo " "
	@echo " "
	@echo "     ██████╗ ██╗███████╗ ██████╗ ██╗   ██╗    "
	@echo "     ██╔══██╗██║██╔════╝██╔════╝ ██║   ██║    "
	@echo "     ██████╔╝██║███████╗██║█████╗██║   ██║    "
	@echo "     ██╔══██╗██║╚════██║██║╚════╝╚██╗ ██╔╝    "
	@echo "     ██║  ██║██║███████║╚██████╗  ╚████╔╝     "
	@echo "     ╚═╝  ╚═╝╚═╝╚══════╝ ╚═════╝   ╚═══╝      "
	@echo " "
	@echo "========================================================================================================="
	@echo "                        RISC-V Project Build System                      "
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
	@echo " 🧹 MAINTENANCE"
	@echo " ────────────────────────────────────────────────────────────────────────────────────────────────────────"
	@echo "   make clean                                                   Limpar diretório de build"
	@echo " "
	@echo "========================================================================================================="
	@echo " "
	@echo " CONFIGURAÇÃO PADRÃO:"
	@echo " ────────────────────────────────────────────────────────────────────────────────────────────────────────"
	@echo "   CORE = $(CORE)  (Alterar com CORE=<nome>)"
	@echo "   Arquiteturas: single_cycle, multi_cycle"
	@echo " "
	@echo " EXEMPLOS DE USO:"
	@echo " ────────────────────────────────────────────────────────────────────────────────────────────────────────"
	@echo "   # Compilar aplicação hello (detecta se é FPGA ou Sim)"
	@echo "   $$ make sw SW=hello"
	@echo " "
	@echo "   # Compilar e rodar teste do datapath com single_cycle"
	@echo "   $$ make cocotb CORE=single_cycle TEST=test_datapath TOP=datapath_wrapper"
	@echo " "
	@echo "   # Testar Sistema Completo (Usa bootloader de simulação)"
	@echo "   $$ make cocotb TOP=soc_top TEST=test_soc_top SW=hello"
	@echo " "
	@echo "   # Programar FPGA e Enviar Código"
	@echo "   $$ make fpga"
	@echo "   $$ make upload SW=fibonacci"
	@echo " "
	@echo "========================================================================================================="
	@echo " "

# ==========================================================================================
#                            SOFTWARE: TARGETS ESPECÍFICOS
# ==========================================================================================

.PHONY: sw sw-fpga sw-sim boot boot-fpga boot-sim list-apps

# --- SW-FPGA: Compila EXCLUSIVAMENTE para Hardware ---
sw-fpga:
	@if [ -z "$(SW)" ]; then echo "❌ Defina SW=..."; exit 1; fi
	@echo ">>> 🏗️  [FPGA] Buscando $(SW)..."
	
	$(eval SRC := $(shell find $(FPGA_SW_DIR)/apps $(COMMON_SW_DIR) -name "$(SW).c" -o -name "$(SW).s" 2>/dev/null | head -n 1))
	
	@if [ -z "$(SRC)" ]; then \
		echo "❌ Erro: $(SW) não encontrado em $(FPGA_SW_DIR)/apps ou $(COMMON_SW_DIR)"; \
		exit 1; \
	fi
	
	@echo ">>> 📂 Fonte: $(SRC)"
	@mkdir -p $(BUILD_FPGA)
	
	@$(CC) $(BASE_CFLAGS) \
		-I$(FPGA_SW_DIR)/platform/bsp \
		-T $(FPGA_SW_DIR)/platform/linker/link.ld \
		-o $(BUILD_FPGA)/$(SW).elf \
		$(FPGA_SW_DIR)/platform/startup/start.s \
		$(wildcard $(FPGA_SW_DIR)/platform/bsp/*.c) \
		$(SRC)
	
	@$(OBJCOPY) -O binary $(BUILD_FPGA)/$(SW).elf $(BUILD_FPGA)/$(SW).bin
	@$(OBJCOPY) -O verilog $(BUILD_FPGA)/$(SW).elf $(BUILD_FPGA)/$(SW).hex
	@echo ">>> ✅ [FPGA] Binário pronto: $(BUILD_FPGA)/$(SW).bin"

# --- SW-SIM: Compila EXCLUSIVAMENTE para Simulação ---
sw-sim:
	@if [ -z "$(SW)" ]; then echo "❌ Defina SW=..."; exit 1; fi
	@echo ">>> 🧪 [SIM] Buscando $(SW)..."
	
	$(eval SRC := $(shell find $(SIM_SW_DIR)/apps $(COMMON_SW_DIR) -name "$(SW).c" -o -name "$(SW).s" 2>/dev/null | head -n 1))
	
	@if [ -z "$(SRC)" ]; then \
		echo "❌ Erro: $(SW) não encontrado em $(SIM_SW_DIR)/apps ou $(COMMON_SW_DIR)"; \
		exit 1; \
	fi
	
	@echo ">>> 📂 Fonte: $(SRC)"
	@mkdir -p $(BUILD_SIM)
	
	@$(CC) $(BASE_CFLAGS) \
		-I$(SIM_SW_DIR)/platform/bsp \
		-T $(SIM_SW_DIR)/platform/linker/link.ld \
		-o $(BUILD_SIM)/$(SW).elf \
		$(SIM_SW_DIR)/platform/startup/crt0.s \
		$(wildcard $(SIM_SW_DIR)/platform/bsp/*.c) \
		$(SRC)
	
	@$(OBJCOPY) -O verilog $(BUILD_SIM)/$(SW).elf $(BUILD_SIM)/$(SW).hex
	@echo ">>> ✅ [SIM] Hex pronto: $(BUILD_SIM)/$(SW).hex"

# --- SW: Dispatcher Inteligente ---
sw:
	@if [ -z "$(SW)" ]; then echo "❌ Defina SW=..."; exit 1; fi
	@if [ -n "$$(find $(FPGA_SW_DIR)/apps -name "$(SW).c" -o -name "$(SW).s" 2>/dev/null)" ]; then \
		$(MAKE) -s sw-fpga SW=$(SW); \
	elif [ -n "$$(find $(SIM_SW_DIR)/apps -name "$(SW).c" -o -name "$(SW).s" 2>/dev/null)" ]; then \
		$(MAKE) -s sw-sim SW=$(SW); \
	elif [ -n "$$(find $(COMMON_SW_DIR) -name "$(SW).c" -o -name "$(SW).s" 2>/dev/null)" ]; then \
		echo ">>> 🔄 App Comum detectado. Compilando para ambos..."; \
		$(MAKE) -s sw-fpga SW=$(SW); \
		$(MAKE) -s sw-sim SW=$(SW); \
	else \
		echo "❌ App $(SW) não encontrado em lugar nenhum."; \
		exit 1; \
	fi

# --- BOOTLOADERS ---
boot: boot-fpga

boot-fpga:
	@mkdir -p $(BUILD_FPGA_BOOT)
	@echo ">>> 🔨 [BOOT-FPGA] Compilando..."
	@$(CC) $(BASE_CFLAGS) -I$(FPGA_SW_DIR)/platform/bsp -T $(FPGA_SW_DIR)/platform/linker/boot.ld \
		-o $(BUILD_FPGA_BOOT)/bootloader.elf \
		$(FPGA_SW_DIR)/platform/startup/start.s \
		$(FPGA_SW_DIR)/platform/bootloader/boot.c \
		$(wildcard $(FPGA_SW_DIR)/platform/bsp/*.c)
	@$(OBJCOPY) -O binary $(BUILD_FPGA_BOOT)/bootloader.elf $(BUILD_FPGA_BOOT)/bootloader.bin
	@od -An -t x4 -v -w4 $(BUILD_FPGA_BOOT)/bootloader.bin > $(BUILD_FPGA_BOOT)/bootloader.hex

boot-sim:
	@mkdir -p $(BUILD_COCOTB_BOOT)
	@echo ">>> 🧪 [BOOT-SIM] Compilando..."
	@$(CC) $(BASE_CFLAGS) -I$(SIM_SW_DIR)/platform/bsp -T $(SIM_SW_DIR)/platform/linker/boot.ld \
		-o $(BUILD_COCOTB_BOOT)/bootloader.elf \
		$(SIM_SW_DIR)/platform/startup/start.s \
		$(SIM_SW_DIR)/platform/bootloader/boot.c \
		$(wildcard $(SIM_SW_DIR)/platform/bsp/*.c)
	@$(OBJCOPY) -O binary $(BUILD_COCOTB_BOOT)/bootloader.elf $(BUILD_COCOTB_BOOT)/bootloader.bin
	@od -An -t x4 -v -w4 $(BUILD_COCOTB_BOOT)/bootloader.bin > $(BUILD_COCOTB_BOOT)/bootloader.hex

list-apps:
	@echo "⚡ FPGA: $$(ls $(FPGA_SW_DIR)/apps 2>/dev/null | sed 's/\..*//' | tr '\n' ' ')"
	@echo "🧪 SIM:  $$(ls $(SIM_SW_DIR)/apps 2>/dev/null | sed 's/\..*//' | tr '\n' ' ')"
	@echo "🔄 COMUM: $$(ls $(COMMON_SW_DIR) 2>/dev/null | sed 's/\..*//' | tr '\n' ' ')"

# ==========================================================================================
#                          COCOTB SIMULATION TARGETS
# ==========================================================================================

TOP  ?= processor_top
TEST ?= test_processor

# Define qual HEX carregar no Cocotb
ifneq (,$(findstring $(FPGA_SW_DIR),$(SRC_FILE)))
    APP_HEX_PATH = $(BUILD_FPGA)/$(SW).hex
else
    APP_HEX_PATH = $(BUILD_SIM)/$(SW).hex
endif

# Bootloader path para simulação
BOOT_SIM_PATH = $(ABS_BUILD_DIR)/cocotb/boot/bootloader.hex

# Lógica para Injetar Bootloader SOMENTE em testes de SoC
IS_SYSTEM_TEST := $(filter soc% boot% bus_interconnect% dual_port_ram% memory_system%,$(TOP)$(TEST))

ifdef IS_SYSTEM_TEST
    SIM_ARGS_EXTRA = -gINIT_FILE=$(BOOT_SIM_PATH)
    BOOT_DEP = boot-sim
else
    SIM_ARGS_EXTRA = 
    BOOT_DEP = 
endif

cocotb:
	@if [ ! -z "$(BOOT_DEP)" ]; then $(MAKE) -s $(BOOT_DEP); fi
	@if [ ! -z "$(SW)" ]; then $(MAKE) -s sw-sim SW=$(SW); fi
	
	@mkdir -p $(BUILD_CORE_DIR)
	@echo " "
	@echo "======================================================================"
	@echo ">>> 🧪 COCOTB - Iniciando Testes Automatizados"
	@echo "======================================================================"
	@echo " "
	@echo ">>> 🏗️  Arquitetura  :   $(CORE)"
	@echo ">>> 🎯 Top Level    :   $(TOP)"
	@echo ">>> 📂 Testbench    :   $(TEST)"
	@echo ">>> 💾 Software     :   $(if $(SW),$(SW).hex,nenhum)"
	@echo ">>> 🔌 Bootloader   :   $(if $(IS_SYSTEM_TEST),$(BOOT_SIM_PATH),N/A (Unit Test))"
	@echo " "
	
	@export COCOTB_ANSI_OUTPUT=1; \
	export COCOTB_RESULTS_FILE=$(BUILD_CORE_DIR)/results.xml; \
	export PROGRAM_PATH=$(if $(SW),$(APP_HEX_PATH),); \
	export HEX_PATH_FOR_TEST=$(BOOT_SIM_PATH); \
	$(MAKE) -s -f $(shell cocotb-config --makefiles)/Makefile.sim \
		SIM=$(COCOTB_SIMULATOR) \
		TOPLEVEL_LANG=vhdl \
		TOPLEVEL=$(TOP) \
		COCOTB_TEST_MODULES=$(TEST) \
		WORKDIR=$(BUILD_CORE_DIR) \
		VHDL_SOURCES="$(ALL_RTL_SRCS)" \
		GHDL_ARGS="-fsynopsys" \
		PYTHONPATH=$(COCOTB_PYTHONPATH):$(SIM_CORE_COMMON):$(SIM_CORE_CURRENT) \
		SIM_ARGS="--vcd=$(BUILD_CORE_DIR)/wave-$(TEST).vcd --ieee-asserts=disable-at-0 $(SIM_ARGS_EXTRA)" \
		SIM_BUILD=$(BUILD_CORE_DIR) \
		2>&1 | grep -v "vpi_iterate returned NULL"
	@echo " "
	@echo ">>> ✅ Teste concluído"
	@echo ">>> 🌊 Ondas salvas em: $(BUILD_CORE_DIR)/wave-$(TEST).vcd"

# Listar testes (Mantido igual)
list-tests:
	@echo "🔎 Testes disponíveis em $(SIM_CORE_CURRENT):"
	@echo "────────────────────────────────────────────"
	@ls -1 $(SIM_CORE_CURRENT)/test_*.py 2>/dev/null | sed 's/.*\///; s/\.py$$//' | sed 's/^/  • /'
	@echo " "
	@echo "🧪 Testes disponíveis em $(SIM_PERIPS_DIR):"
	@echo "────────────────────────────────────────────"
	@ls -1 $(SIM_PERIPS_DIR)/test_*.py 2>/dev/null | sed 's/.*\///; s/\.py$$//' | sed 's/^/  • /'
	@echo " "
	@echo "🎯 Testes disponíveis em $(SIM_SOC_DIR):"
	@echo "────────────────────────────────────────────"
	@ls -1 $(SIM_SOC_DIR)/test_*.py 2>/dev/null | sed 's/.*\///; s/\.py$$//' | sed 's/^/  • /'
	@echo " "

# ==========================================================================================
#                        VISUALIZATION & DEBUG TARGETS
# ==========================================================================================

view:
	@echo ">>> 📊 Abrindo GTKWave..."
	@if [ -f $(BUILD_CORE_DIR)/wave-$(TEST).vcd ]; then \
		echo ">>> 🌊 Arquivo: $(BUILD_CORE_DIR)/wave-$(TEST).vcd"; \
		$(GTKWAVE) $(BUILD_CORE_DIR)/wave-$(TEST).vcd 2>/dev/null; \
	else \
		echo ">>> ❌ Erro: Nenhuma onda VCD encontrada para TEST=$(TEST) e CORE=$(CORE)"; \
		echo ">>> 💡 Dica: Execute 'make cocotb CORE=$(CORE) TEST=$(TEST)' primeiro"; \
	fi

# ==========================================================================================
#                           CLEANUP & MAINTENANCE
# ==========================================================================================

clean:
	@echo ">>> 🧹 Limpando diretório de build..."
	@rm -rf $(BUILD_DIR) *.cf
	@echo ">>> ✅ Limpeza concluída"

# ==========================================================================================
# Programação da FPGA e Upload
# ==========================================================================================

fpga: boot-fpga
	@echo ">>> ⚡ Programando FPGA..."
	@powershell.exe -NoProfile -ExecutionPolicy Bypass -Command "./fpga.ps1"
	@echo ">>> ✅ FPGA programada com sucesso"

upload:
	@if [ -z "$(SW)" ]; then echo "❌ Erro: Defina SW=..."; exit 1; fi
	
	@$(MAKE) -s sw-fpga SW=$(SW)
	
	@echo ">>> 🚀 Uploading $(SW)..."
	@powershell.exe -NoProfile -ExecutionPolicy Bypass -Command "python fpga/upload.py -f $(BUILD_FPGA)/$(SW).bin"

.PHONY: all cocotb clean view fpga upload