# =====================================================================================================
# File: Makefile (Para o Software Bare-Metal do RISC-V)
# =====================================================================================================

# Toolchain do RISC-V (ajuste se o seu prefixo for diferente)
TOOLCHAIN_PREFIX = riscv64-unknown-elf-
CC      = $(TOOLCHAIN_PREFIX)gcc
OBJCOPY = $(TOOLCHAIN_PREFIX)objcopy
OBJDUMP = $(TOOLCHAIN_PREFIX)objdump

# Diretórios
SRC_DIR   = platform
BOOT_DIR  = $(SRC_DIR)/bootloader
START_DIR = $(SRC_DIR)/startup
LINK_DIR  = $(SRC_DIR)/linker
BUILD_DIR = build

# Arquivos
BOOT_SRC   = $(BOOT_DIR)/boot.c
START_SRC  = $(START_DIR)/crt0.s
LINKER_SCR = $(LINK_DIR)/boot.ld

# Alvos
ELF = $(BUILD_DIR)/bootloader.elf
BIN = $(BUILD_DIR)/bootloader.bin
HEX = $(BUILD_DIR)/bootloader.hex

# Flags de Compilação
# -march=rv32i: Arquitetura base de 32 bits. Se usar multiplicador, mude para rv32im
# -mabi=ilp32: ABI base de 32 bits
# -ffreestanding: Diz ao GCC para não assumir que existe um Sistema Operacional
# -nostdlib: Não usa as bibliotecas padrão do C (libc)
CFLAGS = -march=rv32i -mabi=ilp32 -O2 -ffreestanding -nostdlib -Wall -Wextra

# Flags de Linker
# -Wl,-T...: Especifica o script de linker customizado
LDFLAGS = -Wl,-T$(LINKER_SCR)

.PHONY: all clean

all: $(HEX)

# Compilação e Linkagem (Gera o ELF)
$(ELF): $(START_SRC) $(BOOT_SRC) $(LINKER_SCR)
	@mkdir -p $(BUILD_DIR)
	@echo "[COMPILER]  Compilando e Linkando o Bootloader..."
	$(CC) $(CFLAGS) $(LDFLAGS) $(START_SRC) $(BOOT_SRC) -o $(ELF)

# Geração do Binário (Opcional, mas útil)
$(BIN): $(ELF)
	@echo "[COMPILER] Extraindo Binário Bruto..."
	$(OBJCOPY) -O binary $(ELF) $(BIN)

# Geração do Arquivo HEX formatado para a BRAM
$(HEX): $(BIN)
	@echo "[COMPILER] Gerando arquivo HEX para a Boot ROM (via Python)..."
	python3 -c "import sys; data = sys.stdin.buffer.read(); sys.stdout.write(''.join(f'{int.from_bytes(data[i:i+4], byteorder=\"little\"):08x}\n' for i in range(0, len(data), 4)))" < $(BIN) > $(HEX)

clean:
	@echo "🧹 Limpando build do software..."
	rm -rf $(BUILD_DIR)