# =========================================================
# MINIMALIST COCOTB MAKEFILE - UNIT & INTEGRATION TESTS
# =========================================================

PWD := $(shell pwd)
CORE_ARCH ?= multi_cycle

PKG := $(PWD)/rtl/$(CORE_ARCH)/pkg/riscv_isa_pkg.vhd \
       $(PWD)/rtl/$(CORE_ARCH)/pkg/riscv_uarch_pkg.vhd

APP ?= hello
PROGRAM_PATH ?= $(PWD)/sim/$(CORE_ARCH)/e2e/sw/apps/build/$(APP).hex
SKIP_C_BUILD ?= 0
SIM_BOOT_ADDR ?= 0

export COCOTB_REDUCED_LOG_FMT := 1
export PYTHONPATH := $(PWD)/sim/$(CORE_ARCH)/unit:$(PWD)/sim/$(CORE_ARCH)/integration:$(PWD)/sim/$(CORE_ARCH)/e2e:$(PWD)/sim/$(CORE_ARCH)/include:$(shell echo $$PYTHONPATH)

.PHONY: clean

# ---------------------------------------------------------
# 🎯 Regra 1: TESTES UNITÁRIOS ("make test-unit-<nome>")
# ---------------------------------------------------------
test-unit-%:
	@echo "================================================="
	@echo "🧪 Executando Teste Unitário: $* [$(CORE_ARCH)]"
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
		VHDL_SOURCES="$(PKG) $(PWD)/rtl/$(CORE_ARCH)/core/$*.vhd $$src_path" \
		TOPLEVEL=$$top_lvl \
		COCOTB_TEST_MODULES=test_$* \
		COCOTB_RESULTS_FILE=$(PWD)/build/$(CORE_ARCH)/$*/results.xml \
		SIM_BUILD=$(PWD)/build/$(CORE_ARCH)/$* \
		SIM_ARGS="--vcd=$(PWD)/build/$(CORE_ARCH)/$*/wave.vcd --ieee-asserts=disable"

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
		VHDL_SOURCES="$(PKG) $(wildcard $(PWD)/rtl/$(CORE_ARCH)/core/*.vhd) $$src_path" \
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
	@if [ "$(SKIP_C_BUILD)" != "1" ]; then $(MAKE) -C sim/$(CORE_ARCH)/e2e/sw/apps APP=$(APP) > /dev/null; fi
	@wrapper_top=$$(python3 scripts/query_yaml.py $(CORE_ARCH) $* wrapper_top); \
	wrapper_src=$$(python3 scripts/query_yaml.py $(CORE_ARCH) $* wrapper_src); \
	if [ -n "$$wrapper_src" ]; then src_path="$(PWD)/$$wrapper_src"; else src_path=""; fi; \
	top_lvl=$${wrapper_top:-$*}; \
	PROGRAM_PATH="$(PROGRAM_PATH)" \
	$(MAKE) -s --no-print-directory -f $(shell cocotb-config --makefiles)/Makefile.sim \
		SIM=ghdl \
		TOPLEVEL_LANG=vhdl \
		EXTRA_ARGS="--std=08" \
		VHDL_SOURCES="$(PKG) $(wildcard $(PWD)/rtl/$(CORE_ARCH)/core/*.vhd) $$src_path" \
		TOPLEVEL=$$top_lvl \
		COCOTB_TEST_MODULES=test_$* \
		COCOTB_RESULTS_FILE=$(TARGET_BUILD_DIR)/results.xml \
		SIM_BUILD=$(TARGET_BUILD_DIR) \
		SIM_ARGS="--vcd=$(TARGET_BUILD_DIR)/wave.vcd --ieee-asserts=disable -gBOOT_ADDR_INT=$(SIM_BOOT_ADDR)"

# ---------------------------------------------------------
# 🏆 SUÍTE DE COMPLIANCE OFICIAL RISC-V
# ---------------------------------------------------------
.PHONY: test-compliance test-compliance-clean

# Chama o orquestrador do compliance passando o paralelismo automaticamente
test-compliance:
	@echo ">>> TESTING [$(CORE_ARCH)] RV32I COMPLIANCE"
	@$(MAKE) -C sim/$(CORE_ARCH)/e2e/sw/compliance --no-print-directory

test-compliance-clean:
	@$(MAKE) -C sim/$(CORE_ARCH)/e2e/sw/compliance clean

clean:
	@echo ">>> 🧹 Limpando..."
	@rm -rf build sim_build *.vcd *.cf results.xml .pytest_cache
	@find . -type d -name "__pycache__" -exec rm -rf {} +