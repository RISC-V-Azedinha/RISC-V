# =========================================================
# MINIMALIST COCOTB MAKEFILE - UNIT TESTS ONLY
# =========================================================

PWD := $(shell pwd)

# Pacotes essenciais que sempre devem ser compilados primeiro
PKG := $(PWD)/rtl/single_cycle/pkg/riscv_isa_pkg.vhd

.PHONY: clean

# 🎯 Regra Mágica: "make test-unit-<nome>" 
# O símbolo % captura o nome (ex: alu) e armazena na variável $*
test-unit-%:
	@echo "================================================="
	@echo "🧪 Executando Teste Unitário: $*"
	@echo "================================================="
	@mkdir -p build/$*
	@export COCOTB_REDUCED_LOG_FMT=1; \
	$(MAKE) -s --no-print-directory -f $(shell cocotb-config --makefiles)/Makefile.sim \
		SIM=ghdl \
		TOPLEVEL_LANG=vhdl \
		EXTRA_ARGS="--std=08" \
		VHDL_SOURCES="$(PKG) $(PWD)/rtl/single_cycle/core/$*.vhd" \
		TOPLEVEL=$* \
		COCOTB_TEST_MODULES=test_$* \
		COCOTB_RESULTS_FILE=$(PWD)/build/$*/results.xml \''
		SIM_BUILD=$(PWD)/build/$* \
		SIM_ARGS="--vcd=$(PWD)/build/$*/wave.vcd" \
		PYTHONPATH="$(PWD)/sim/single_cycle/unit:$(PWD)/sim/single_cycle/include:$(PYTHONPATH)"

clean:
	@echo ">>> 🧹 Limpando..."
	@rm -rf build sim_build *.vcd *.cf results.xml .pytest_cache
	@find . -type d -name "__pycache__" -exec rm -rf {} +