# =============================================================================
#
#  rules_sim.mk
#  Simulação e Verificação com Cocotb (GHDL)
#
# =============================================================================
#
#  Executa testbenches em Python via Cocotb.
#  Injeta Bootloader e Software (.hex) conforme necessário
#  Diferencia entre testes unitários e testes de sistema (SoC).
#
# =============================================================================

# --- VARIÁVEIS LOCAIS --------------------------------------------------------

TOP            ?= processor_top
TEST           ?= test_processor
APP_HEX_PATH   = $(if $(findstring $(FPGA_SW_DIR),$(SRC_FILE)),$(BUILD_FPGA)/$(SW).hex,$(BUILD_SIM)/$(SW).hex)
BOOT_SIM_PATH  = $(ABS_BUILD_DIR)/cocotb/boot/bootloader.hex
IS_SYSTEM_TEST := $(filter soc% boot% memory_system% memory_wrapper%,$(TOP)$(TEST))

ifdef IS_SYSTEM_TEST
    SIM_ARGS_EXTRA = -gINIT_FILE=$(BOOT_SIM_PATH)
    BOOT_DEP       = boot-sim
else
    SIM_ARGS_EXTRA = 
    BOOT_DEP       = 
endif

.PHONY: cocotb view list-tests

# =============================================================================
#  COCOTB: Execução de Testes
# =============================================================================

cocotb:
	@if [ ! -z "$(BOOT_DEP)" ]; then $(MAKE) -s $(BOOT_DEP); fi
	@if [ ! -z "$(SW)" ]; then $(MAKE) -s sw-sim SW=$(SW); fi
	@mkdir -p $(BUILD_CORE_DIR)
	@echo " "
	@echo "======================================================================"
	@echo ">>> 🧪 COCOTB - Iniciando Testes Automatizados"
	@echo "======================================================================"
	@echo " "
	@echo ">>> 🏗️  Arquitetura :   $(CORE)"
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
		VHDL_SOURCES="$(ALL_SIM_SRCS)" \
		GHDL_ARGS="$(GHDL_STD_FLAGS)" \
		PYTHONPATH=$(COCOTB_PYTHONPATH):$(SIM_CORE_COMMON):$(SIM_CORE_CURRENT) \
		SIM_ARGS="--vcd=$(BUILD_CORE_DIR)/wave-$(TEST).vcd --ieee-asserts=disable-at-0 $(SIM_ARGS_EXTRA)" \
		SIM_BUILD=$(BUILD_CORE_DIR) \
		2>&1 | grep -v "vpi_iterate returned NULL"
	@echo " "
	@echo ">>> ✅ Teste concluído"
	@echo ">>> 🌊 Ondas salvas em: $(BUILD_CORE_DIR)/wave-$(TEST).vcd"

# =============================================================================
#  VIEW: Visualizar ondas
# =============================================================================

view:
	@echo ">>> 📊 Abrindo GTKWave..."
	@if [ -f $(BUILD_CORE_DIR)/wave-$(TEST).vcd ]; then \
		$(GTKWAVE) $(BUILD_CORE_DIR)/wave-$(TEST).vcd 2>/dev/null; \
	else \
		echo ">>> ❌ Erro: Onda não encontrada."; \
		echo ">>> 💡 Dica: Rode 'make cocotb ...' primeiro."; \
	fi

# =============================================================================
#  LIST-TESTS: Listar testes disponíveis
# =============================================================================

list-tests:
	@echo " "
	@echo "🔎 Testes de Arquitetura ($(SIM_CORE_CURRENT)):"
	@echo "────────────────────────────────────────────────"
	@ls -1 $(SIM_CORE_CURRENT)/test_*.py 2>/dev/null | sed 's/.*\///; s/\.py$$//' | sed 's/^/  • /' || echo "  (Nenhum encontrado)"
	@echo " "
	@echo "🧱 Testes Comuns de Core ($(SIM_CORE_COMMON)):"
	@echo "────────────────────────────────────────────────"
	@ls -1 $(SIM_CORE_COMMON)/test_*.py 2>/dev/null | sed 's/.*\///; s/\.py$$//' | sed 's/^/  • /' || echo "  (Nenhum encontrado)"
	@echo " "
	@echo "🧪 Testes de Periféricos ($(SIM_PERIPS_DIR)):"
	@echo "────────────────────────────────────────────────"
	@ls -1 $(SIM_PERIPS_DIR)/test_*.py 2>/dev/null | sed 's/.*\///; s/\.py$$//' | sed 's/^/  • /' || echo "  (Nenhum encontrado)"
	@echo " "
	@echo "🎯 Testes de SoC ($(SIM_SOC_DIR)):"
	@echo "────────────────────────────────────────────────"
	@ls -1 $(SIM_SOC_DIR)/test_*.py 2>/dev/null | sed 's/.*\///; s/\.py$$//' | sed 's/^/  • /' || echo "  (Nenhum encontrado)"
	@echo " "

# =============================================================================
