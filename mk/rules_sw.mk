# =============================================================================
#
#  ARQUIVO: mk/rules_sw.mk
#  DESCRIÇÃO: Regras de Compilação de Software (Firmware & Bootloader)
#
# =============================================================================
#
#  Contém as regras para:
#   - Compilar aplicações de usuário (.c -> .elf -> .bin/.hex)
#   - Compilar o Bootloader (código de inicialização da ROM)
#   - Listar softwares disponíveis
#
# =============================================================================

.PHONY: sw sw-fpga sw-sim boot boot-fpga boot-sim list-apps

# --- COMPILAÇÃO SW -----------------------------------------------------------

sw-fpga:
	@if [ -z "$(SW)" ]; then echo "❌ Defina SW=..."; exit 1; fi
	@echo ">>> 🏗️  [FPGA] Buscando $(SW)..."
	$(eval SRC := $(shell find $(FPGA_SW_DIR)/apps $(COMMON_SW_DIR) -name "$(SW).c" -o -name "$(SW).s" 2>/dev/null | head -n 1))
	@if [ -z "$(SRC)" ]; then echo "❌ Erro: $(SW) não encontrado"; exit 1; fi
	@mkdir -p $(BUILD_FPGA_BIN)
	@$(CC) $(BASE_CFLAGS) -I$(FPGA_SW_DIR)/platform/bsp -T $(FPGA_SW_DIR)/platform/linker/link.ld \
		-o $(BUILD_FPGA_BIN)/$(SW).elf $(FPGA_SW_DIR)/platform/startup/start.s \
		$(wildcard $(FPGA_SW_DIR)/platform/bsp/*.c) \
		$(wildcard $(FPGA_SW_DIR)/platform/bsp/hal/*.c) \
		$(wildcard $(FPGA_SW_DIR)/platform/bsp/npu/*.c) \
		$(SRC)
	@$(OBJCOPY) -O binary $(BUILD_FPGA_BIN)/$(SW).elf $(BUILD_FPGA_BIN)/$(SW).bin
	@$(OBJCOPY) -O verilog $(BUILD_FPGA_BIN)/$(SW).elf $(BUILD_FPGA_BIN)/$(SW).hex
	@echo ">>> ✅ [FPGA] Binário pronto: $(BUILD_FPGA_BIN)/$(SW).bin"

sw-sim:
	@if [ -z "$(SW)" ]; then echo "❌ Defina SW=..."; exit 1; fi
	@echo ">>> 🧪 [SIM] Buscando $(SW)..."
	$(eval SRC := $(shell find $(SIM_SW_DIR)/apps $(COMMON_SW_DIR) -name "$(SW).c" -o -name "$(SW).s" 2>/dev/null | head -n 1))
	@if [ -z "$(SRC)" ]; then echo "❌ Erro: $(SW) não encontrado"; exit 1; fi
	@mkdir -p $(BUILD_SIM)
	@$(CC) $(BASE_CFLAGS) -I$(SIM_SW_DIR)/platform/bsp -T $(SIM_SW_DIR)/platform/linker/link.ld \
		-o $(BUILD_SIM)/$(SW).elf $(SIM_SW_DIR)/platform/startup/crt0.s \
		$(wildcard $(SIM_SW_DIR)/platform/bsp/*.c) $(SRC)
	@$(OBJCOPY) -O verilog $(BUILD_SIM)/$(SW).elf $(BUILD_SIM)/$(SW).hex
	@echo ">>> ✅ [SIM] Hex pronto: $(BUILD_SIM)/$(SW).hex"

sw:
	@if [ -z "$(SW)" ]; then echo "❌ Defina SW=..."; exit 1; fi
	@if [ -n "$$(find $(FPGA_SW_DIR)/apps -name "$(SW).c" -o -name "$(SW).s" 2>/dev/null)" ]; then \
		$(MAKE) -s sw-fpga SW=$(SW); \
	elif [ -n "$$(find $(SIM_SW_DIR)/apps -name "$(SW).c" -o -name "$(SW).s" 2>/dev/null)" ]; then \
		$(MAKE) -s sw-sim SW=$(SW); \
	elif [ -n "$$(find $(COMMON_SW_DIR) -name "$(SW).c" -o -name "$(SW).s" 2>/dev/null)" ]; then \
		echo ">>> 🔄 App Comum detectado."; $(MAKE) -s sw-fpga SW=$(SW); $(MAKE) -s sw-sim SW=$(SW); \
	else echo "❌ App $(SW) não encontrado."; exit 1; fi

# --- BOOTLOADER --------------------------------------------------------------

boot: boot-fpga
boot-fpga:
	@mkdir -p $(BUILD_FPGA_BOOT)
	@echo ">>> 🔨 [BOOT-FPGA] Compilando..."
	@$(CC) $(BASE_CFLAGS) -I$(FPGA_SW_DIR)/platform/bsp -T $(FPGA_SW_DIR)/platform/linker/boot.ld \
		-o $(BUILD_FPGA_BOOT)/bootloader.elf $(FPGA_SW_DIR)/platform/startup/start.s \
		$(FPGA_SW_DIR)/platform/bootloader/boot.c $(wildcard $(FPGA_SW_DIR)/platform/bsp/*.c)
	@$(OBJCOPY) -O binary $(BUILD_FPGA_BOOT)/bootloader.elf $(BUILD_FPGA_BOOT)/bootloader.bin
	@od -An -t x4 -v -w4 $(BUILD_FPGA_BOOT)/bootloader.bin > $(BUILD_FPGA_BOOT)/bootloader.hex
	@echo ">>> ✅ [BOOT-FPGA] Hex gerado: $(BUILD_FPGA_BOOT)/bootloader.hex"

boot-sim:
	@mkdir -p $(BUILD_COCOTB_BOOT)
	@echo ">>> 🧪 [BOOT-SIM] Compilando..."
	@$(CC) $(BASE_CFLAGS) -I$(SIM_SW_DIR)/platform/bsp -T $(SIM_SW_DIR)/platform/linker/boot.ld \
		-o $(BUILD_COCOTB_BOOT)/bootloader.elf $(SIM_SW_DIR)/platform/startup/start.s \
		$(SIM_SW_DIR)/platform/bootloader/boot.c $(wildcard $(SIM_SW_DIR)/platform/bsp/*.c)
	@$(OBJCOPY) -O binary $(BUILD_COCOTB_BOOT)/bootloader.elf $(BUILD_COCOTB_BOOT)/bootloader.bin
	@od -An -t x4 -v -w4 $(BUILD_COCOTB_BOOT)/bootloader.bin > $(BUILD_COCOTB_BOOT)/bootloader.hex

# --- LISTAGEM DE APPS --------------------------------------------------------

list-apps:
	@echo " "
	@echo "💾 Aplicações para FPGA ($(FPGA_SW_DIR)/apps):"
	@echo "────────────────────────────────────────────"
	@ls -1 $(FPGA_SW_DIR)/apps 2>/dev/null | grep -E "\.(c|s)$$" | sed 's/\..*//' | sed 's/^/  • /' || echo "  (Nenhuma encontrada)"
	@echo " "
	
	@echo "🧪 Aplicações para Simulação ($(SIM_SW_DIR)/apps):"
	@echo "────────────────────────────────────────────"
	@ls -1 $(SIM_SW_DIR)/apps 2>/dev/null | grep -E "\.(c|s)$$" | sed 's/\..*//' | sed 's/^/  • /' || echo "  (Nenhuma encontrada)"
	@echo " "

# =============================================================================