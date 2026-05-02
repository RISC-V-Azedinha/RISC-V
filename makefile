# =========================================================
# MINIMALIST COCOTB MAKEFILE - UNIT & INTEGRATION TESTS
# =========================================================

PWD := $(shell pwd)
PKG := $(PWD)/rtl/single_cycle/pkg/riscv_isa_pkg.vhd \
       $(PWD)/rtl/single_cycle/pkg/riscv_uarch_pkg.vhd

APP ?= hello

export COCOTB_REDUCED_LOG_FMT := 1
export PYTHONPATH := $(PWD)/sim/single_cycle/unit:$(PWD)/sim/single_cycle/integration:$(PWD)/sim/single_cycle/e2e:$(PWD)/sim/single_cycle/include:$(shell echo $$PYTHONPATH)

.PHONY: clean

# ---------------------------------------------------------
# 🎯 Regra Mágica 1: TESTES UNITÁRIOS ("make test-unit-<nome>")
# ---------------------------------------------------------
test-unit-%:
	@echo "================================================="
	@echo "🧪 Executando Teste Unitário: $*"
	@echo "================================================="
	@mkdir -p build/$*
	@wrapper_top=$$(python3 scripts/query_yaml.py $* wrapper_top); \
	wrapper_src=$$(python3 scripts/query_yaml.py $* wrapper_src); \
	if [ -n "$$wrapper_src" ]; then src_path="$(PWD)/$$wrapper_src"; else src_path=""; fi; \
	top_lvl=$${wrapper_top:-$*}; \
	$(MAKE) -s --no-print-directory -f $(shell cocotb-config --makefiles)/Makefile.sim \
		SIM=ghdl \
		TOPLEVEL_LANG=vhdl \
		EXTRA_ARGS="--std=08" \
		VHDL_SOURCES="$(PKG) $(PWD)/rtl/single_cycle/core/$*.vhd $$src_path" \
		TOPLEVEL=$$top_lvl \
		COCOTB_TEST_MODULES=test_$* \
		COCOTB_RESULTS_FILE=$(PWD)/build/$*/results.xml \
		SIM_BUILD=$(PWD)/build/$* \
		SIM_ARGS="--vcd=$(PWD)/build/$*/wave.vcd"

# ---------------------------------------------------------
# 🌍 Regra Mágica 2: TESTES DE INTEGRAÇÃO ("make test-int-<nome>")
# ---------------------------------------------------------
test-int-%:
	@echo "================================================="
	@echo "🌍 Executando Teste de Integração: $*"
	@echo "================================================="
	@mkdir -p build/$*
	@wrapper_top=$$(python3 scripts/query_yaml.py $* wrapper_top); \
	wrapper_src=$$(python3 scripts/query_yaml.py $* wrapper_src); \
	if [ -n "$$wrapper_src" ]; then src_path="$(PWD)/$$wrapper_src"; else src_path=""; fi; \
	top_lvl=$${wrapper_top:-$*}; \
	$(MAKE) -s --no-print-directory -f $(shell cocotb-config --makefiles)/Makefile.sim \
		SIM=ghdl \
		TOPLEVEL_LANG=vhdl \
		EXTRA_ARGS="--std=08" \
		VHDL_SOURCES="$(PKG) $(wildcard $(PWD)/rtl/single_cycle/core/*.vhd) $$src_path" \
		TOPLEVEL=$$top_lvl \
		COCOTB_TEST_MODULES=test_$* \
		COCOTB_RESULTS_FILE=$(PWD)/build/$*/results.xml \
		SIM_BUILD=$(PWD)/build/$* \
		SIM_ARGS="--vcd=$(PWD)/build/$*/wave.vcd"

# ---------------------------------------------------------
# 🚀 Regra Mágica 3: TESTES END-TO-END ("make test-e2e-<nome>")
# ---------------------------------------------------------
test-e2e-%:
	@echo "================================================="
	@echo "🚀 Executando Teste End-to-End: $* (App: $(APP))"
	@echo "================================================="
	@mkdir -p build/$*
	@$(MAKE) -C sim/single_cycle/e2e/sw/apps APP=$(APP) > /dev/null
	@wrapper_top=$$(python3 scripts/query_yaml.py $* wrapper_top); \
	wrapper_src=$$(python3 scripts/query_yaml.py $* wrapper_src); \
	if [ -n "$$wrapper_src" ]; then src_path="$(PWD)/$$wrapper_src"; else src_path=""; fi; \
	top_lvl=$${wrapper_top:-$*}; \
	PROGRAM_PATH="$(PWD)/sim/single_cycle/e2e/sw/apps/build/$(APP).hex" \
	$(MAKE) -s --no-print-directory -f $(shell cocotb-config --makefiles)/Makefile.sim \
		SIM=ghdl \
		TOPLEVEL_LANG=vhdl \
		EXTRA_ARGS="--std=08" \
		VHDL_SOURCES="$(PKG) $(wildcard $(PWD)/rtl/single_cycle/core/*.vhd) $$src_path" \
		TOPLEVEL=$$top_lvl \
		COCOTB_TEST_MODULES=test_$* \
		COCOTB_RESULTS_FILE=$(PWD)/build/$*/results.xml \
		SIM_BUILD=$(PWD)/build/$* \
		SIM_ARGS="--vcd=$(PWD)/build/$*/wave.vcd"

clean:
	@echo ">>> 🧹 Limpando..."
	@rm -rf build sim_build *.vcd *.cf results.xml .pytest_cache
	@find . -type d -name "__pycache__" -exec rm -rf {} +