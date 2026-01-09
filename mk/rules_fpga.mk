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

BITSTREAM    = $(BUILD_FPGA_BIT)/soc_top.bit
BOOT_HEX     = $(BUILD_FPGA_BOOT)/bootloader.hex
SCRIPT_PROG  = fpga/scripts/program.tcl
COM          ?= COM6

.PHONY: fpga upload

# --- PROGRAMAR FPGA ----------------------------------------------------------

fpga: $(BITSTREAM)
	@echo ">>> ⚡ Programando FPGA..."
	@mkdir -p $(BUILD_FPGA_LOGS)
	@powershell.exe -NoProfile -ExecutionPolicy Bypass -Command "vivado -mode batch -notrace -source $(SCRIPT_PROG) -log $(BUILD_FPGA_LOGS)/prog.log -journal $(BUILD_FPGA_LOGS)/prog.jou"
	@rm -rf .Xil
	@rm -f $(BUILD_FPGA_LOGS)/*.backup*
	@echo ">>> ✅ FPGA pronta."

# --- BUILD (Síntese) ---------------------------------------------------------

$(BITSTREAM): $(SYNTH_SRCS) $(BOOT_HEX)
	@echo ">>> 🛠️  Alterações detectadas."
	@echo ">>> 🔄 Iniciando Síntese..."
	@mkdir -p $(BUILD_FPGA_LOGS)
	@powershell.exe -NoProfile -ExecutionPolicy Bypass -Command "vivado -mode batch -notrace -source fpga/scripts/build.tcl -log $(BUILD_FPGA_LOGS)/vivado.log -journal $(BUILD_FPGA_LOGS)/vivado.jou"
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
	@powershell.exe -NoProfile -ExecutionPolicy Bypass -Command "python fpga/upload.py -p $(COM) -f $(BUILD_FPGA_BIN)/$(SW).bin"

# =============================================================================