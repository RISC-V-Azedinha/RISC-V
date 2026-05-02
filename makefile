# =========================================================
# MINIMALIST COCOTB MAKEFILE - APENAS ALU
# =========================================================

SIM ?= ghdl
TOPLEVEL_LANG ?= vhdl
EXTRA_ARGS += --std=08

# 1. Ajustado exatamente para a sua estrutura do 'ls -R'
VHDL_SOURCES += $(PWD)/rtl/pkg/riscv_isa_pkg.vhd
VHDL_SOURCES += $(PWD)/rtl/core/alu.vhd

# 2. Entidade VHDL e Script Python
TOPLEVEL = alu
MODULE   = test_alu

# 3. Ajustado para onde os arquivos Python realmente estão
export PYTHONPATH := $(PWD)/sim

# 4. Inclui o motor do Cocotb
include $(shell cocotb-config --makefiles)/Makefile.sim

# 5. Limpeza
clean::
	@rm -rf sim_build *.vcd results.xml __pycache__