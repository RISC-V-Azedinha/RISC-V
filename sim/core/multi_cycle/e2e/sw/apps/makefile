# =========================================================
# COMPILAÇÃO DE SOFTWARE RISC-V (C para HEX)
# =========================================================

CC      = riscv64-unknown-elf-gcc
OBJCOPY = riscv64-unknown-elf-objcopy
OBJDUMP = riscv64-unknown-elf-objdump

# Auto-detecta suporte/exigência da extensão _zicsr
ZICSR_EXT := $(shell $(CC) -march=rv32i_zicsr -mabi=ilp32 -E - < /dev/null > /dev/null 2>&1 && echo "_zicsr" || echo "")

ARCH_FLAGS = -march=rv32i$(ZICSR_EXT) -mabi=ilp32
CFLAGS = -O2 -ffreestanding -nostdlib -nostartfiles $(ARCH_FLAGS) -Wall

PLATFORM_DIR = ../boot
STARTUP_SRC  = $(PLATFORM_DIR)/crt0.s
LINKER_SRC   = $(PLATFORM_DIR)/link.ld

# Aplicação padrão (pode ser sobrescrita pelo Makefile raiz)
APP ?= hello

# Diretório de saída
BUILD_DIR = build

# Nomes dos arquivos de saída dentro da pasta build
TARGET_ELF = $(BUILD_DIR)/$(APP).elf
TARGET_HEX = $(BUILD_DIR)/$(APP).hex
TARGET_ASM = $(BUILD_DIR)/$(APP).asm

all: $(BUILD_DIR) $(TARGET_HEX)

# Cria a pasta build se ela não existir
$(BUILD_DIR):
	mkdir -p $(BUILD_DIR)

$(TARGET_ELF): $(APP).c $(STARTUP_SRC) | $(BUILD_DIR)
	$(CC) $(CFLAGS) -T $(LINKER_SRC) $(STARTUP_SRC) $(APP).c -o $(TARGET_ELF)

$(TARGET_HEX): $(TARGET_ELF)
	$(OBJCOPY) -O verilog $(TARGET_ELF) $(TARGET_HEX)
	$(OBJDUMP) -D $(TARGET_ELF) > $(TARGET_ASM)

clean:
	rm -rf $(BUILD_DIR)