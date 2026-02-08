# =============================================================================
#
#  sources.mk
#  Descoberta Automática de Fontes VHDL
#
# =============================================================================
#
#  Descobre automaticamente fontes VHDL por diretório.
#  Separa fontes puras (RTL) de wrappers de simulação para evitar
#  confundir o sintetizador com código de teste.
#
# =============================================================================

# =============================================================================
#  NPU: Núcleo Neural Processual (Submódulo)
# =============================================================================

NPU_ROOT := $(RTL_DIR)/perips/npu

NPU_SRCS := \
    $(NPU_ROOT)/pkg/npu_pkg.vhd \
    $(NPU_ROOT)/rtl/common/fifo_sync.vhd \
    $(NPU_ROOT)/rtl/common/ram_dual.vhd \
    $(NPU_ROOT)/rtl/core/mac_pe.vhd \
    $(NPU_ROOT)/rtl/core/systolic_array.vhd \
    $(NPU_ROOT)/rtl/core/input_buffer.vhd \
    $(NPU_ROOT)/rtl/core/npu_core.vhd \
    $(NPU_ROOT)/rtl/ppu/post_process.vhd \
    $(NPU_ROOT)/rtl/npu_register_file.vhd \
    $(NPU_ROOT)/rtl/npu_controller.vhd \
    $(NPU_ROOT)/rtl/npu_datapath.vhd \
    $(NPU_ROOT)/rtl/npu_top.vhd

# =============================================================================
#  PACOTES E COMPONENTES GENÉRICOS
# =============================================================================

PKG_SRCS = $(wildcard $(PKG_DIR)/*.vhd) $(CORE_CURRENT)/riscv_uarch_pkg.vhd

# =============================================================================
#  CORE: Componentes Principais do RISC-V
# =============================================================================

COMMON_SRCS = $(wildcard $(CORE_COMMON)/*/*.vhd) $(wildcard $(CORE_COMMON)/*.vhd)
CORE_SRCS   = $(wildcard $(CORE_CURRENT)/*.vhd)

# =============================================================================
#  SOC: Interconexão de Barramento e Controladores
# =============================================================================

SOC_SRCS = $(wildcard $(SOC_DIR)/*.vhd)

# =============================================================================
#  PERIFÉRICOS: GPIO, UART, VGA, etc
# =============================================================================

PERIPS_SRCS = $(wildcard $(PERIPS_DIR)/gpio/*.vhd) \
              $(wildcard $(PERIPS_DIR)/uart/*.vhd) \
              $(PERIPS_DIR)/vga/video_ram.vhd \
              $(PERIPS_DIR)/vga/vga_sync.vhd \
              $(PERIPS_DIR)/vga/vga_peripheral.vhd

# =============================================================================
#  RTL PURO: Síntese e Simulação (sem wrappers)
# =============================================================================

RTL_PURE_SRCS = $(PKG_SRCS) \
                $(COMMON_SRCS) \
                $(CORE_SRCS) \
                $(SOC_SRCS) \
                $(PERIPS_SRCS) \
                $(NPU_SRCS)

# =============================================================================
#  SÍNTESE: RTL + Constraints (XDC)
# =============================================================================

SYNTH_SRCS = $(RTL_PURE_SRCS) fpga/constraints/pins.xdc

# =============================================================================
#  SIMULAÇÃO: Wrappers para Cocotb
# =============================================================================

SIM_WRAPPERS = $(wildcard $(SIM_CORE_DIR)/wrappers/*.vhd) \
               $(wildcard $(SIM_CORE_CURRENT)/wrappers/*.vhd) \
               $(wildcard $(SIM_SOC_DIR)/wrappers/*.vhd)

# =============================================================================
#  SIMULAÇÃO: RTL Puro + Wrappers
# =============================================================================

ALL_SIM_SRCS = $(RTL_PURE_SRCS) $(SIM_WRAPPERS)
