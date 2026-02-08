# =============================================================================
#
#  ARQUIVO: mk/rules_fpga.mk
#  DESCRIÇÃO: Regras de Síntese e Implementação (Vivado)
#
# =============================================================================
#
#  Automação do fluxo de FPGA:
#   1. Verifica se o hardware mudou
#   2. Se mudou, chama o Vivado (via script TCL) para sintetizar
#   3. Se não mudou, apenas grava o bitstream existente na placa
#
# =============================================================================

# --- DETECTA O AMBIENTE ------------------------------------------------------

UNAME_R := $(shell uname -r)

ifneq ($(filter %microsoft %WSL,$(UNAME_R)),)
    # [WINDOWS/WSL] 
    # Usa PowerShell para chamar o Vivado e Python do Windows
    # Aspas são necessárias para encapsular o comando no PS
    VIVADO_CMD  = powershell.exe -NoProfile -ExecutionPolicy Bypass -Command "vivado
    PYTHON_CMD  = powershell.exe -NoProfile -ExecutionPolicy Bypass -Command "python
    CMD_END     = "
    DEFAULT_COM = COM6
else
    # [LINUX NATIVO] 
    # Chama o Vivado e Python direto do PATH
    # Sem aspas extras
    VIVADO_CMD  = vivado
    PYTHON_CMD  = python3
    CMD_END     = 
    DEFAULT_COM = /dev/ttyUSB1
endif

# --- DIRETÓRIOS --------------------------------------------------------------

BITSTREAM    = $(BUILD_FPGA_BIT)/soc_top.bit
BOOT_HEX     = $(BUILD_FPGA_BOOT)/bootloader.hex
SCRIPT_PROG  = fpga/scripts/program.tcl

# Define a porta padrão baseada no sistema (pode sobrescrever com make upload COM=...)
COM          ?= $(DEFAULT_COM)

.PHONY: fpga upload

# --- PROGRAMAR FPGA ----------------------------------------------------------

fpga: $(BITSTREAM)
	@echo ">>> ⚡ Programando FPGA..."
	@mkdir -p $(BUILD_FPGA_LOGS)
	@$(VIVADO_CMD) -mode batch -notrace -source $(SCRIPT_PROG) -log $(BUILD_FPGA_LOGS)/prog.log -journal $(BUILD_FPGA_LOGS)/prog.jou$(CMD_END)
	@rm -rf .Xil
	@rm -f $(BUILD_FPGA_LOGS)/*.backup*
	@echo ">>> ✅ FPGA pronta."

# --- BUILD (Síntese) ---------------------------------------------------------

$(BITSTREAM): $(SYNTH_SRCS) $(BOOT_HEX)
	@echo ">>> 🛠️  Alterações detectadas."
	@echo ">>> 🔄 Iniciando Síntese..."
	@mkdir -p $(BUILD_FPGA_LOGS)
	@$(VIVADO_CMD) -mode batch -notrace -source fpga/scripts/build.tcl -log $(BUILD_FPGA_LOGS)/vivado.log -journal $(BUILD_FPGA_LOGS)/vivado.jou$(CMD_END)
	@echo ">>> 🧹 Limpando..."
	@rm -rf .Xil usage_statistics* vivado*.backup* vivado*.str
	@rm -f $(BUILD_FPGA_LOGS)/*.backup*
	@echo ">>> ✨ Build finalizado."

# --- BOOTLOADER DEP ----------------------------------------------------------

$(BOOT_HEX):
	@echo ">>> ⚠️  Bootloader ausente. Compilando..."
	@$(MAKE) -s boot-fpga

# --- UPLOAD ------------------------------------------------------------------
upload:
	@if [ -z "$(SW)" ]; then echo "❌ Erro: Defina SW=..."; exit 1; fi
	@$(MAKE) -s sw-fpga SW=$(SW)
	@echo ">>> 🚀 Uploading $(SW) na porta $(COM)..."
	@$(PYTHON_CMD) fpga/upload.py -p $(COM) -f $(BUILD_FPGA_BIN)/$(SW).bin$(CMD_END)

# =============================================================================