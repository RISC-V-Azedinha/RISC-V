# =========================================================
# MINIMALIST COCOTB MAKEFILE - UNIT TESTS ONLY
# =========================================================

PWD := $(shell pwd)
PKG := $(PWD)/rtl/single_cycle/pkg/riscv_isa_pkg.vhd \
       $(PWD)/rtl/single_cycle/pkg/riscv_uarch_pkg.vhd

# Exportamos as variáveis globais de forma limpa para os sub-makes
export COCOTB_REDUCED_LOG_FMT := 1
export PYTHONPATH := $(PWD)/sim/single_cycle/unit:$(PWD)/sim/single_cycle/include:$(shell echo $$PYTHONPATH)

.PHONY: clean

# === EXCEÇÕES E OVERRIDES POR MÓDULO ===
# Injeta o wrapper e altera o TOPLEVEL apenas quando rodamos "make test-unit-decoder"
test-unit-decoder: CUSTOM_TOP = decoder_wrapper
test-unit-decoder: CUSTOM_SRC = $(PWD)/rtl/single_cycle/core/wrappers/decoder_wrapper.vhd


# 🎯 Regra Mágica: "make test-unit-<nome>" 
test-unit-%:
	@echo "================================================="
	@echo "🧪 Executando Teste Unitário: $*"
	@echo "================================================="
	@mkdir -p build/$*
	@$(MAKE) -s --no-print-directory -f $(shell cocotb-config --makefiles)/Makefile.sim \
		SIM=ghdl \
		TOPLEVEL_LANG=vhdl \
		EXTRA_ARGS="--std=08" \
		VHDL_SOURCES="$(PKG) $(PWD)/rtl/single_cycle/core/$*.vhd $(CUSTOM_SRC)" \
		TOPLEVEL=$(if $(CUSTOM_TOP),$(CUSTOM_TOP),$*) \
		COCOTB_TEST_MODULES=test_$* \
		COCOTB_RESULTS_FILE=$(PWD)/build/$*/results.xml \
		SIM_BUILD=$(PWD)/build/$* \
		SIM_ARGS="--vcd=$(PWD)/build/$*/wave.vcd"

clean:
	@echo ">>> 🧹 Limpando..."
	@rm -rf build sim_build *.vcd *.cf results.xml .pytest_cache
	@find . -type d -name "__pycache__" -exec rm -rf {} +