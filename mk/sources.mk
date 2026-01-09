# =============================================================================
#
#  ARQUIVO: mk/sources.mk
#  DESCRIÇÃO: Descoberta Automática de Fontes (Source Discovery)
#
# =============================================================================
#
#  Usa o comando 'wildcard' para criar listas de arquivos VHDL dinamicamente.
#  Separa os arquivos em grupos (RTL Puro vs Wrappers de Simulação) para
#  evitar que arquivos de teste sejam sintetizados na FPGA.
#
# =============================================================================

# Fontes de Hardware (Sintetizáveis) ------------------------------------------

PKG_SRCS           = $(wildcard $(PKG_DIR)/*.vhd) $(CORE_CURRENT)/riscv_uarch_pkg.vhd
COMMON_SRCS        = $(wildcard $(CORE_COMMON)/*/*.vhd) $(wildcard $(CORE_COMMON)/*.vhd)
CORE_SRCS          = $(wildcard $(CORE_CURRENT)/*.vhd)
SOC_SRCS           = $(wildcard $(SOC_DIR)/*.vhd)
PERIPS_SRCS        = $(wildcard $(PERIPS_DIR)/*/*.vhd)

# RTL Puro (Simulação e Síntese) ----------------------------------------------

RTL_PURE_SRCS      = $(PKG_SRCS) $(COMMON_SRCS) $(CORE_SRCS) $(SOC_SRCS) $(PERIPS_SRCS)

# Fonte Síntese (Com XDC) -----------------------------------------------------

SYNTH_SRCS         = $(RTL_PURE_SRCS) fpga/constraints/pins.xdc

# Wrappers Simulação ----------------------------------------------------------

SIM_WRAPPERS       = $(wildcard $(SIM_CORE_DIR)/wrappers/*.vhd) \
                     $(wildcard $(SIM_CORE_CURRENT)/wrappers/*.vhd) \
                     $(wildcard $(SIM_SOC_DIR)/wrappers/*.vhd)

# Fonte Simulação (Com Wrappers) ----------------------------------------------

ALL_SIM_SRCS       = $(RTL_PURE_SRCS) $(SIM_WRAPPERS)

# =============================================================================
