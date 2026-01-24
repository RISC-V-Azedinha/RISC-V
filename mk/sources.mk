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

# Definição da NPU (Submódulo)
# -----------------------------------------------------------------------------

# O diretório base onde o submódulo foi baixado

NPU_ROOT := $(RTL_DIR)/perips/npu

NPU_SRCS := \
    $(NPU_ROOT)/pkg/npu_pkg.vhd \
    $(NPU_ROOT)/rtl/common/fifo_sync.vhd \
    $(NPU_ROOT)/rtl/core/mac_pe.vhd \
    $(NPU_ROOT)/rtl/core/systolic_array.vhd \
    $(NPU_ROOT)/rtl/core/input_buffer.vhd \
    $(NPU_ROOT)/rtl/core/npu_core.vhd \
    $(NPU_ROOT)/rtl/ppu/post_process.vhd \
    $(NPU_ROOT)/rtl/npu_top.vhd

# Fontes de Hardware do RISC-V 
# -----------------------------------------------------------------------------

# Fontes de Hardware (Sintetizáveis) ------------------------------------------

PKG_SRCS       = $(wildcard $(PKG_DIR)/*.vhd) $(CORE_CURRENT)/riscv_uarch_pkg.vhd
COMMON_SRCS    = $(wildcard $(CORE_COMMON)/*/*.vhd) $(wildcard $(CORE_COMMON)/*.vhd)
CORE_SRCS      = $(wildcard $(CORE_CURRENT)/*.vhd)
SOC_SRCS       = $(wildcard $(SOC_DIR)/*.vhd)

# Periféricos simples (GPIO, UART etc.) ---------------------------------------

PERIPS_SRCS    = $(wildcard $(PERIPS_DIR)/gpio/*.vhd) \
                 $(wildcard $(PERIPS_DIR)/uart/*.vhd) \
                 $(wildcard $(PERIPS_DIR)/vga/*.vhd)

# RTL Puro (Simulação e Síntese) ----------------------------------------------

RTL_PURE_SRCS  = $(PKG_SRCS) \
                 $(COMMON_SRCS) \
                 $(CORE_SRCS) \
                 $(SOC_SRCS) \
                 $(PERIPS_SRCS) \
                 $(NPU_SRCS)

# Fonte Síntese (Com XDC) -----------------------------------------------------

SYNTH_SRCS         = $(RTL_PURE_SRCS) fpga/constraints/pins.xdc

# Wrappers Simulação ----------------------------------------------------------

SIM_WRAPPERS   = $(wildcard $(SIM_CORE_DIR)/wrappers/*.vhd) \
                 $(wildcard $(SIM_CORE_CURRENT)/wrappers/*.vhd) \
                 $(wildcard $(SIM_SOC_DIR)/wrappers/*.vhd)

# Fonte Simulação (Com Wrappers) ----------------------------------------------

ALL_SIM_SRCS   = $(RTL_PURE_SRCS) $(SIM_WRAPPERS)

# =============================================================================
