# =========================================================
# MINIMALIST COCOTB MAKEFILE - UNIT, INT, E2E & FPGA
# =========================================================

PWD := $(shell pwd)
CORE_ARCH ?= multi_cycle

PKG_ARCH := $(if $(filter perips soc,$(CORE_ARCH)),multi_cycle,$(CORE_ARCH))

PKG := $(PWD)/rtl/core/$(PKG_ARCH)/pkg/riscv_isa_pkg.vhd \
       $(PWD)/rtl/core/$(PKG_ARCH)/pkg/riscv_uarch_pkg.vhd

APP ?= hello
PROGRAM_PATH ?= $(PWD)/sim/core/$(PKG_ARCH)/e2e/sw/apps/build/$(APP).hex
SKIP_C_BUILD ?= 0
SIM_BOOT_ADDR ?= 0

export COCOTB_REDUCED_LOG_FMT := 1
export PYTHONPATH := $(PWD)/sim/core/$(CORE_ARCH)/unit:$(PWD)/sim/core/$(CORE_ARCH)/integration:$(PWD)/sim/core/$(CORE_ARCH)/e2e:$(PWD)/sim/core/$(CORE_ARCH)/include:$(PWD)/sim/perips/unit:$(PWD)/sim/perips/integration:$(PWD)/sim/soc/unit:$(PWD)/sim/soc/integration:$(PWD)/sim/soc:$(PWD)/sim/soc/e2e:$(shell echo $$PYTHONPATH)

# =========================================================
# 🛠️ CONFIGURAÇÕES DE DIRETÓRIOS E FONTES
# =========================================================
PERIPS_DIR := $(PWD)/rtl/perips
NPU_DIR    := $(PERIPS_DIR)/npu

# Coleta arquivos da NPU ignorando a pasta de testes
NPU_SOURCES := $(shell find $(NPU_DIR) -name "*.vhd" ! -path "*/fpga_tester/*")

# Monta o RTL_SOURCES principal
RTL_SOURCES := $(wildcard $(PWD)/rtl/core/$(PKG_ARCH)/core/*.vhd) \
               $(wildcard $(PERIPS_DIR)/*/*.vhd) \
               $(wildcard $(PWD)/rtl/soc/*.vhd) \
               $(NPU_SOURCES)

# =========================================================
# ⚙️ CONFIGURAÇÕES DE FPGA E SOFTWARE
# =========================================================
CC           = riscv64-unknown-elf-gcc
OBJCOPY      = riscv64-unknown-elf-objcopy
VIVADO_BIN  ?= vivado
PYTHON_BIN  ?= python3
COM         ?= /dev/ttyUSB1

FPGA_SW_DIR     := $(PWD)/fpga/sw
BUILD_FPGA      := $(PWD)/build/fpga
BUILD_FPGA_BIN  := $(BUILD_FPGA)/bin
BUILD_FPGA_BOOT := $(BUILD_FPGA)/boot
BUILD_FPGA_LOGS := $(BUILD_FPGA)/logs
FPGA_SCRIPTS    := $(PWD)/fpga/scripts

BASE_CFLAGS := -march=rv32i -mabi=ilp32 -nostdlib -nostartfiles -g --specs=picolibc.specs

.PHONY: clean list-tests fpga upload boot-fpga sw-fpga

# ---------------------------------------------------------
# 📋 Regra 0: LISTAR TESTES ("make list-tests")
# ---------------------------------------------------------
list-tests:
	@echo " "
	@echo "🔎 Testes disponíveis para CORE_ARCH=$(CORE_ARCH):"
	@echo "────────────────────────────────────────────────"
	@find $(PWD)/sim -name "test_*.py" | grep "$(CORE_ARCH)\|perips\|soc" | awk -F/ '{print $$NF}' | sed 's/\.py$$//' | sort | uniq | sed 's/^/  • /' || echo "  (Nenhum encontrado)"
	@echo " "

# ---------------------------------------------------------
# 🎯 Regra 1: TESTES UNITÁRIOS ("make test-unit-<nome>")
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
# 🌍 Regra 2: TESTES DE INTEGRAÇÃO ("make test-int-<nome>")
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
# 🚀 Regra 3: TESTES END-TO-END ("make test-e2e-<nome>")
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
# 🔌 Regra 4: FPGA (Síntese, Implementação e Upload)
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

fpga: boot-fpga
	@echo ">>> ⚡ Sintetizando e Programando FPGA..."
	@mkdir -p $(BUILD_FPGA_LOGS)
	@$(VIVADO_BIN) -mode batch -notrace -source $(FPGA_SCRIPTS)/build.tcl -log $(BUILD_FPGA_LOGS)/vivado.log -journal $(BUILD_FPGA_LOGS)/vivado.jou
	@$(VIVADO_BIN) -mode batch -notrace -source $(FPGA_SCRIPTS)/program.tcl -log $(BUILD_FPGA_LOGS)/prog.log -journal $(BUILD_FPGA_LOGS)/prog.jou
	@rm -rf .Xil usage_statistics* vivado*.backup* vivado*.str
	@echo ">>> ✅ FPGA programada com sucesso."

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