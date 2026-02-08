# =============================================================================
#
#  rules_fpga.mk
#  Síntese, Implementação e Programação da FPGA (Vivado)
#
# =============================================================================
#
#  Fluxo de FPGA:
#   1. Verifica mudanças no hardware (fontes VHDL)
#   2. Se houver mudanças, sintetiza e implementa com Vivado
#   3. Gera e programa o bitstream na placa
#
# =============================================================================

# --- VARIÁVEIS LOCAIS --------------------------------------------------------

BITSTREAM      = $(BUILD_FPGA_BIT)/soc_top.bit
BOOT_HEX       = $(BUILD_FPGA_BOOT)/bootloader.hex
COM            ?= $(DEFAULT_COM)

.PHONY: fpga upload

# =============================================================================
#  BUILD: Síntese e Implementação
# =============================================================================

$(BITSTREAM): $(SYNTH_SRCS) $(BOOT_HEX)
	@echo ">>> 🛠️  Alterações detectadas no design."
	@echo ">>> 🔄 Iniciando síntese e implementação..."
	@mkdir -p $(BUILD_FPGA_LOGS)
	@$(VIVADO_BIN) -mode batch -notrace -source $(FPGA_SCRIPTS_BUILD) \
		-log $(BUILD_FPGA_LOGS)/vivado.log \
		-journal $(BUILD_FPGA_LOGS)/vivado.jou
	@echo ">>> 🧹 Limpando arquivos temporários..."
	@rm -rf .Xil usage_statistics* vivado*.backup* vivado*.str
	@rm -f $(BUILD_FPGA_LOGS)/*.backup*
	@echo ">>> ✨ Build finalizado com sucesso."

# =============================================================================
#  BOOTLOADER: Dependência
# =============================================================================

$(BOOT_HEX):
	@echo ">>> ⚠️  Bootloader ausente. Compilando..."
	@$(MAKE) -s boot-fpga

# =============================================================================
#  FPGA: Programação
# =============================================================================

fpga: $(BITSTREAM)
	@echo ">>> ⚡ Programando FPGA..."
	@mkdir -p $(BUILD_FPGA_LOGS)
	@$(VIVADO_BIN) -mode batch -notrace -source $(FPGA_SCRIPTS_PROG) \
		-log $(BUILD_FPGA_LOGS)/prog.log \
		-journal $(BUILD_FPGA_LOGS)/prog.jou
	@rm -rf .Xil
	@rm -f $(BUILD_FPGA_LOGS)/*.backup*
	@echo ">>> ✅ FPGA pronta."

# =============================================================================
#  UPLOAD: Software via UART
# =============================================================================

upload:
	@if [ -z "$(SW)" ]; then \
		echo "❌ Erro: Defina SW=..."; \
		exit 1; \
	fi
	@$(MAKE) -s sw-fpga SW=$(SW)
	@echo ">>> 🚀 Enviando $(SW) para a FPGA via porta $(COM)..."
	@$(PYTHON_BIN) fpga/upload.py -p $(COM) -f $(BUILD_FPGA_BIN)/$(SW).bin

# =============================================================================
