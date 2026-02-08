# =============================================================================
#
#  ARQUIVO: mk/config.mk
#  DESCRIÇÃO: Configurações Globais, Variáveis e Caminhos
#
# =============================================================================
#
#  Este arquivo centraliza todas as definições de caminhos (paths) e
#  configurações de compilação. É o único lugar que é preciso editar
#  se mudar a estrutura de pastas ou configurações padrão.
#
#  NOTA: Detecção de ambiente e ferramentas está em mk/detect.mk
#
# =============================================================================

# Carrega detecção de ambiente e SO
include mk/detect.mk

# =============================================================================
#  DIRETÓRIOS DE ENTRADA (Source)
# =============================================================================

PKG_DIR            = pkg
RTL_DIR            = rtl
SIM_DIR            = sim
FPGA_SW_DIR        = fpga/sw
SIM_SW_DIR         = sim/sw
COMMON_SW_DIR      = sw/apps

# --- RTL (Hardware Sources) ---

CORE_DIR           = $(RTL_DIR)/core
SOC_DIR            = $(RTL_DIR)/soc
PERIPS_DIR         = $(RTL_DIR)/perips
CORE_COMMON        = $(CORE_DIR)/common

# --- Simulação (Testbenches) ---

SIM_CORE_DIR       = $(SIM_DIR)/core
SIM_CORE_COMMON    = $(SIM_CORE_DIR)/common
SIM_PERIPS_DIR     = $(SIM_DIR)/perips
SIM_SOC_DIR        = $(SIM_DIR)/soc
SIM_COMMON_DIR     = $(SIM_DIR)/common

# --- Scripts e Constraints ---

FPGA_CONSTRAINTS   = fpga/constraints
FPGA_SCRIPTS       = fpga/scripts
FPGA_SCRIPTS_BUILD = $(FPGA_SCRIPTS)/build.tcl
FPGA_SCRIPTS_PROG  = $(FPGA_SCRIPTS)/program.tcl

# =============================================================================
#  DIRETÓRIOS DE SAÍDA (Build Output)
# =============================================================================

BUILD_DIR          = build
BUILD_FPGA         = $(BUILD_DIR)/fpga
BUILD_SIM          = $(BUILD_DIR)/sim
BUILD_COCOTB       = $(BUILD_DIR)/cocotb

# Subdirectórios
BUILD_FPGA_BIN     = $(BUILD_FPGA)/bin
BUILD_FPGA_BIT     = $(BUILD_FPGA)/bitstream
BUILD_FPGA_LOGS    = $(BUILD_FPGA)/logs
BUILD_FPGA_BOOT    = $(BUILD_FPGA)/boot
BUILD_FPGA_CPT     = $(BUILD_FPGA)/checkpoints
BUILD_FPGA_RPT     = $(BUILD_FPGA)/reports
BUILD_COCOTB_BOOT  = $(BUILD_COCOTB)/boot

# Caminhos absolutos (necessário para Vivado em WSL)
ABS_BUILD_DIR      = $(abspath $(BUILD_DIR))
ABS_FPGA_SW_DIR    = $(abspath $(FPGA_SW_DIR))
ABS_RTL_DIR        = $(abspath $(RTL_DIR))

# =============================================================================
#  CONFIGURAÇÃO DO CORE (Arquitetura)
# =============================================================================

CORE ?= multi_cycle
CORE_PATH           = $(CORE_DIR)/$(CORE)
CORE_CURRENT        = $(CORE_PATH)
SIM_CORE_CURRENT    = $(SIM_CORE_DIR)/$(CORE)
BUILD_CORE_DIR      = $(BUILD_COCOTB)/$(CORE)

# Validação do Core
ifeq ($(wildcard $(CORE_PATH)),)
    $(error ❌ Erro: Arquitetura '$(CORE)' inválida! '$(CORE_PATH)' não existe.)
endif

# =============================================================================
#  COMPILADOR E FERRAMENTAS
# =============================================================================

# Compilador RISC-V
CC                 = riscv64-unknown-elf-gcc
OBJCOPY            = riscv64-unknown-elf-objcopy

# Ferramentas de simulação
COCOTB_SIM         = ghdl
COCOTB_SIMULATOR   = $(COCOTB_SIM)
COCOTB_PYTHONPATH  = $(SIM_CORE_DIR):$(SIM_SOC_DIR):$(SIM_PERIPS_DIR):$(SIM_COMMON_DIR)

# Ferramentas de visualização
GTKWAVE            = gtkwave

# Python (usar PYTHON_EXEC de detect.mk, com fallback)
PYTHON_BIN         = $(if $(HAS_PYTHON3),$(PYTHON_EXEC),$(PYTHON_EXEC_ALT))

# Vivado (usar VIVADO_EXEC de detect.mk)
VIVADO_BIN         = $(VIVADO_EXEC)

# =============================================================================
#  FLAGS DE COMPILAÇÃO
# =============================================================================

# Flags para RISC-V GCC
BASE_CFLAGS        = -march=rv32i_zicsr -mabi=ilp32 -nostdlib -nostartfiles -g

# Flags para GHDL (simulador)
GHDL_STD_FLAGS     = -fsynopsys --std=08 -frelaxed
GHDL_SIM_FLAGS     = --vcd --ieee-asserts=disable-at-0

# =============================================================================
#  VARIÁVEIS DE VERIFICAÇÃO
# =============================================================================

# Informações do ambiente (para debug)
INFO_OS            = $(OS)
INFO_PLATFORM      = $(PLATFORM)
INFO_PYTHON        = $(PYTHON_BIN)
INFO_COM_DEFAULT   = $(DEFAULT_COM)

# =============================================================================