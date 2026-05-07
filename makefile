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
	@echo " 🔌 FPGA E SOFTWARE"
	@echo " ────────────────────────────────────────────────────────────────────"
	@echo "   make fpga-build            Sintetiza e gera o Bitstream/MCS (build.tcl)"
	@echo "   make fpga-prog             Programa a placa via JTAG (program.tcl)"
	@echo "   make fpga-flash            Grava o SoC na memória Flash (flash.tcl)"
	@echo "   make upload SW=<app>       Compila o C e envia via UART (ex: COM=/dev/ttyUSB1)"
	@echo "   make list-apps             Lista todos os apps em C/Assembly disponíveis"
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

# ---------------------------------------------------------
# 🎯 Regra 2: TESTES UNITÁRIOS ("make test-unit-<nome>")
# ---------------------------------------------------------
test-unit-%:
	@echo "================================================="
	@echo "🧪 Executando Teste Unitário: $* [$(CORE_ARCH)]"
	@echo "================================================="
	@mkdir -p build/$(CORE_ARCH)/$*
	@sim_args="--vcd=$(PWD)/build/$(CORE_ARCH)/$*/wave.vcd --ieee-asserts=disable"; \
    if [ "$*" = "boot_rom" ]; then \
        echo "[COMPILER] Detectado teste da Boot ROM! Compilando bootloader real..."; \
        $(MAKE) -C sim/soc/sw all || exit 1; \
        sim_args="$$sim_args -gINIT_FILE=$(PWD)/sim/soc/sw/build/bootloader.hex"; \
        echo "[SUCCESS] Bootloader compilado com sucesso!"; \
    fi; \
	wrapper_top=$$(python3 scripts/query_yaml.py $(CORE_ARCH) $* wrapper_top); \
	wrapper_src=$$(python3 scripts/query_yaml.py $(CORE_ARCH) $* wrapper_src); \
	if [ -n "$$wrapper_src" ]; then src_path="$(PWD)/$$wrapper_src"; else src_path=""; fi; \
	top_lvl=$${wrapper_top:-$*}; \
	target_src=$$(find $(PWD)/rtl -type f -name "$*.vhd" ! -path "*/fpga_tester/*" | head -n 1); \
	if [ -z "$$target_src" ]; then echo "❌ Erro: Arquivo $*.vhd não encontrado em rtl/!"; exit 1; fi; \
	target_dir=$$(dirname "$$target_src"); \
	target_deps=$$(find "$$target_dir" -type f -name "*.vhd" | grep -v "$$target_src" | tr '\n' ' '); \
	HEX_PATH_FOR_TEST="$(PWD)/sim/soc/sw/build/bootloader.hex" \
    $(MAKE) -s --no-print-directory -f $(shell cocotb-config --makefiles)/Makefile.sim \
		SIM=ghdl \
		TOPLEVEL_LANG=vhdl \
		EXTRA_ARGS="--std=08 -frelaxed" \
		VHDL_SOURCES="$(PKG) $$target_deps $$target_src $$src_path" \
		TOPLEVEL=$$top_lvl \
		COCOTB_TEST_MODULES=test_$* \
		COCOTB_RESULTS_FILE=$(PWD)/build/$(CORE_ARCH)/$*/results.xml \
		SIM_BUILD=$(PWD)/build/$(CORE_ARCH)/$* \
		SIM_ARGS="$$sim_args"

# ---------------------------------------------------------
# 🌍 Regra 3: TESTES DE INTEGRAÇÃO ("make test-int-<nome>")
# ---------------------------------------------------------
test-int-%:
	@echo "================================================="
	@echo "🌍 Executando Teste de Integração: $* [$(CORE_ARCH)]"
	@echo "================================================="
	@mkdir -p build/$(CORE_ARCH)/$*
	@wrapper_top=$$(python3 scripts/query_yaml.py $(CORE_ARCH) $* wrapper_top); \
	wrapper_src=$$(python3 scripts/query_yaml.py $(CORE_ARCH) $* wrapper_src); \
	if [ -n "$$wrapper_src" ]; then src_path="$(PWD)/$$wrapper_src"; else src_path=""; fi; \
	top_lvl=$${wrapper_top:-$*}; \
	$(MAKE) -s --no-print-directory -f $(shell cocotb-config --makefiles)/Makefile.sim \
		SIM=ghdl \
		TOPLEVEL_LANG=vhdl \
		EXTRA_ARGS="--std=08" \
		VHDL_SOURCES="$(PKG) $(RTL_SOURCES) $$src_path" \
		TOPLEVEL=$$top_lvl \
		COCOTB_TEST_MODULES=test_$* \
		COCOTB_RESULTS_FILE=$(PWD)/build/$(CORE_ARCH)/$*/results.xml \
		SIM_BUILD=$(PWD)/build/$(CORE_ARCH)/$* \
		SIM_ARGS="--vcd=$(PWD)/build/$(CORE_ARCH)/$*/wave.vcd --ieee-asserts=disable"

# ---------------------------------------------------------
# 🚀 Regra 4: TESTES END-TO-END ("make test-e2e-<nome>")
# ---------------------------------------------------------
TARGET_BUILD_DIR ?= $(PWD)/build/$(CORE_ARCH)/$*

test-e2e-%:
	@echo "================================================="
	@echo "🚀 Executando Teste End-to-End: $* [$(CORE_ARCH)]"
	@echo "================================================="
	@mkdir -p $(TARGET_BUILD_DIR)
	@if [ "$(SKIP_C_BUILD)" != "1" ]; then $(MAKE) -C sim/core/$(PKG_ARCH)/e2e/sw/apps APP=$(APP) > /dev/null; fi 
	@sim_args="--vcd=$(TARGET_BUILD_DIR)/wave.vcd --ieee-asserts=disable -gBOOT_ADDR_INT=$(SIM_BOOT_ADDR)"; \
    if [ "$*" = "soc_top" ]; then \
        echo "[COMPILER] Compilando Bootloader do SoC..."; \
        $(MAKE) -C sim/soc/sw all || exit 1; \
        sim_args="--vcd=$(TARGET_BUILD_DIR)/wave.vcd --ieee-asserts=disable -gINIT_FILE=$(PWD)/sim/soc/sw/build/bootloader.hex"; \
    fi; \
	wrapper_top=$$(python3 scripts/query_yaml.py $(CORE_ARCH) $* wrapper_top); \
	wrapper_src=$$(python3 scripts/query_yaml.py $(CORE_ARCH) $* wrapper_src); \
	if [ -n "$$wrapper_src" ]; then src_path="$(PWD)/$$wrapper_src"; else src_path=""; fi; \
	top_lvl=$${wrapper_top:-$*}; \
	PROGRAM_PATH="$(PROGRAM_PATH)" \
	$(MAKE) -s --no-print-directory -f $(shell cocotb-config --makefiles)/Makefile.sim \
		SIM=ghdl \
		TOPLEVEL_LANG=vhdl \
		EXTRA_ARGS="--std=08 -frelaxed" \
		VHDL_SOURCES="$(PKG) $(RTL_SOURCES) $$src_path" \
		TOPLEVEL=$$top_lvl \
		COCOTB_TEST_MODULES=test_$* \
		COCOTB_RESULTS_FILE=$(TARGET_BUILD_DIR)/results.xml \
		SIM_BUILD=$(TARGET_BUILD_DIR) \
		SIM_ARGS="$$sim_args"

# ---------------------------------------------------------
# 🔌 Regra 5: FPGA (Síntese, Implementação e Upload)
# ---------------------------------------------------------
boot-fpga:
	@mkdir -p $(BUILD_FPGA_BOOT)
	@echo ">>> 🔨 [BOOT-FPGA] Compilando bootloader..."
	@$(CC) $(BASE_CFLAGS) -I$(FPGA_SW_DIR)/platform/bsp -T $(FPGA_SW_DIR)/platform/linker/boot.ld \
		-o $(BUILD_FPGA_BOOT)/bootloader.elf $(FPGA_SW_DIR)/platform/startup/start.s \
		$(FPGA_SW_DIR)/platform/bootloader/boot.c $$(find $(FPGA_SW_DIR)/platform/bsp -name "*.c")
	@$(OBJCOPY) -O binary $(BUILD_FPGA_BOOT)/bootloader.elf $(BUILD_FPGA_BOOT)/bootloader.bin
	@od -An -t x4 -v -w4 $(BUILD_FPGA_BOOT)/bootloader.bin > $(BUILD_FPGA_BOOT)/bootloader.hex
	@echo ">>> ✅ Hex gerado: $(BUILD_FPGA_BOOT)/bootloader.hex"

sw-fpga:
	@if [ -z "$(SW)" ]; then echo "❌ Defina SW=... (ex: make sw-fpga SW=hello)"; exit 1; fi
	@echo ">>> 🏗️  Compilando $(SW) para FPGA..."
	@src_file=$$(find $(FPGA_SW_DIR)/apps $(FPGA_SW_DIR)/tests $(FPGA_SW_DIR)/server -name "$(SW).c" -o -name "$(SW).s" 2>/dev/null | head -n 1); \
	if [ -z "$$src_file" ]; then echo "❌ Erro: $(SW) não encontrado"; exit 1; fi; \
	mkdir -p $(BUILD_FPGA_BIN); \
	$(CC) $(BASE_CFLAGS) -I$(FPGA_SW_DIR)/platform/bsp -T $(FPGA_SW_DIR)/platform/linker/link.ld \
		-o $(BUILD_FPGA_BIN)/$(SW).elf $(FPGA_SW_DIR)/platform/startup/start.s \
		$$(find $(FPGA_SW_DIR)/platform/bsp -name "*.c") $$src_file; \
	$(OBJCOPY) -O binary $(BUILD_FPGA_BIN)/$(SW).elf $(BUILD_FPGA_BIN)/$(SW).bin; \
	$(OBJCOPY) -O verilog $(BUILD_FPGA_BIN)/$(SW).elf $(BUILD_FPGA_BIN)/$(SW).hex
	@echo ">>> ✅ Binário pronto: $(BUILD_FPGA_BIN)/$(SW).bin"

fpga-build: boot-fpga
	@echo ">>> ⚡ Sintetizando o projeto e gerando Bitstream/MCS..."
	@mkdir -p $(BUILD_FPGA_LOGS)
	@$(VIVADO_BIN) -mode batch -notrace -source $(FPGA_SCRIPTS)/build.tcl -log $(BUILD_FPGA_LOGS)/build.log -journal $(BUILD_FPGA_LOGS)/build.jou
	@rm -rf .Xil usage_statistics* vivado*.backup* vivado*.str
	@echo ">>> ✅ Síntese e geração de arquivos concluídas com sucesso."

fpga-prog:
	@echo ">>> 🔌 Programando a FPGA via JTAG..."
	@mkdir -p $(BUILD_FPGA_LOGS)
	@$(VIVADO_BIN) -mode batch -notrace -source $(FPGA_SCRIPTS)/program.tcl -log $(BUILD_FPGA_LOGS)/prog.log -journal $(BUILD_FPGA_LOGS)/prog.jou
	@rm -rf .Xil usage_statistics* vivado*.backup* vivado*.str
	@echo ">>> ✅ FPGA programada com sucesso."

fpga-flash:
	@echo ">>> 💾 Gravando o SoC na memória Flash..."
	@mkdir -p $(BUILD_FPGA_LOGS)
	@$(VIVADO_BIN) -mode batch -notrace -source $(FPGA_SCRIPTS)/flash.tcl -log $(BUILD_FPGA_LOGS)/flash.log -journal $(BUILD_FPGA_LOGS)/flash.jou
	@rm -rf .Xil usage_statistics* vivado*.backup* vivado*.str
	@echo ">>> ✅ Gravação na Flash concluída com sucesso."

upload: sw-fpga
	@echo ">>> 🚀 Enviando $(SW) para a FPGA via porta $(COM)..."
	@$(PYTHON_BIN) fpga/upload.py -p $(COM) -f $(BUILD_FPGA_BIN)/$(SW).bin

# ---------------------------------------------------------
# 🏆 SUÍTE DE COMPLIANCE OFICIAL RISC-V
# ---------------------------------------------------------
.PHONY: test-compliance test-compliance-clean

# Chama o orquestrador do compliance passando o paralelismo automaticamente
test-compliance:
	@echo ">>> TESTING [$(CORE_ARCH)] RV32I COMPLIANCE"
	@$(MAKE) -C sim/core/$(CORE_ARCH)/e2e/sw/compliance --no-print-directory

test-compliance-clean:
	@$(MAKE) -C sim/core/$(CORE_ARCH)/e2e/sw/compliance clean

clean:
	@echo ">>> 🧹 Limpando..."
	@rm -rf build sim_build *.vcd *.cf results.xml .pytest_cache .Xil
	@find . -type d -name "__pycache__" -exec rm -rf {} +