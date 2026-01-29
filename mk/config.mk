# =============================================================================
#
#  ARQUIVO: mk/config.mk
#  DESCRIÇÃO: Configurações Globais, Variáveis e Ferramentas
#
# =============================================================================
#
#  Este arquivo centraliza todas as definições de caminhos (paths) e
#  ferramentas do projeto. É o único lugar que é preciso editar
#  se mudar a estrutura de pastas ou trocar de compilador.
#
# =============================================================================

# --- DIRETÓRIOS --------------------------------------------------------------

BUILD_DIR          = build
FPGA_SW_DIR        = fpga/sw
SIM_SW_DIR         = sim/sw
COMMON_SW_DIR      = sw/apps

# Outputs

BUILD_FPGA         = $(BUILD_DIR)/fpga
BUILD_SIM          = $(BUILD_DIR)/sim
BUILD_FPGA_BIN     = $(BUILD_FPGA)/bin
BUILD_FPGA_BIT     = $(BUILD_FPGA)/bitstream
BUILD_FPGA_LOGS    = $(BUILD_FPGA)/logs
BUILD_FPGA_BOOT    = $(BUILD_FPGA)/boot
BUILD_COCOTB_BOOT  = $(BUILD_DIR)/cocotb/boot

# --- ESTRUTURA RTL -----------------------------------------------------------

PKG_DIR            = pkg
RTL_DIR            = rtl
CORE_DIR           = $(RTL_DIR)/core
SOC_DIR            = $(RTL_DIR)/soc
PERIPS_DIR         = $(RTL_DIR)/perips
CORE_COMMON        = $(CORE_DIR)/common

# Simulação Paths

SIM_DIR            = sim
SIM_CORE_DIR       = $(SIM_DIR)/core
SIM_CORE_COMMON    = $(SIM_CORE_DIR)/common
SIM_PERIPS_DIR     = $(SIM_DIR)/perips
SIM_SOC_DIR        = $(SIM_DIR)/soc
SIM_COMMON_DIR     = $(SIM_DIR)/common

# --- FERRAMENTAS -------------------------------------------------------------

CC                 = riscv32-unknown-elf-gcc
OBJCOPY            = riscv32-unknown-elf-objcopy
BASE_CFLAGS        = -march=rv32i_zicsr -mabi=ilp32 -nostdlib -nostartfiles -g
GTKWAVE            = gtkwave
PYTHON             = python3

# Cocotb

COCOTB_SIM         = ghdl
COCOTB_SIMULATOR   = $(COCOTB_SIM)
COCOTB_BUILD       = $(BUILD_DIR)/cocotb
COCOTB_PYTHONPATH  = $(SIM_CORE_DIR):$(SIM_SOC_DIR):$(SIM_PERIPS_DIR):$(SIM_COMMON_DIR)
ABS_BUILD_DIR      = $(abspath $(BUILD_DIR))

# --- CORE SELECTION ----------------------------------------------------------

CORE ?= multi_cycle
CORE_PATH           = $(CORE_DIR)/$(CORE)
CORE_CURRENT        = $(CORE_PATH)
SIM_CORE_CURRENT    = $(SIM_CORE_DIR)/$(CORE)
BUILD_CORE_DIR      = $(COCOTB_BUILD)/$(CORE)

# Validação do Core
ifeq ($(wildcard $(CORE_PATH)),)
    $(error Arquitetura '$(CORE)' inválida! $(CORE_PATH) não existe.)
endif

# =============================================================================