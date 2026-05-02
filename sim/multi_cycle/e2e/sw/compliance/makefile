# =========================================================
# 🏆 RISC-V COMPLIANCE TEST SUITE (RV32I)
# =========================================================

# Cores
GREEN  = \033[0;32m
RED    = \033[0;31m
YELLOW = \033[0;33m
NC     = \033[0m

# Microarquitetura
CORE_ARCH ?= multi_cycle

RISCV_GCC = riscv64-unknown-elf-gcc
RISCV_OBJCOPY = riscv64-unknown-elf-objcopy
RISCV_NM = riscv64-unknown-elf-nm

SW_COMPLIANCE_FLAGS = -march=rv32i -mabi=ilp32 -static -mcmodel=medany -fvisibility=hidden -nostdlib -nostartfiles -Ienv -Itarget -Ttarget/compliance.ld -DXLEN=32 -DTEST_CASE_1=1

SRC_DIR = rv32i_m/I/src
REF_DIR = references
BUILD_DIR = build

COMPLIANCE_SRCS := $(wildcard $(SRC_DIR)/*.S)
COMPLIANCE_TESTS := $(patsubst $(SRC_DIR)/%.S, %, $(COMPLIANCE_SRCS))

# Caminho para o Makefile raiz do projeto (5 níveis acima)
ROOT_DIR = $(abspath ../../../../..)

.PHONY: all prepare test-compliance-all clean

all: test-compliance-all

prepare:
	@mkdir -p $(BUILD_DIR)

# 1. Regra para compilar o Assembly para ELF e HEX
$(BUILD_DIR)/%.elf: $(SRC_DIR)/%.S | prepare
	@$(RISCV_GCC) $(SW_COMPLIANCE_FLAGS) $< -o $@
	@$(RISCV_OBJCOPY) -O verilog $@ $(BUILD_DIR)/$*.hex

# 2. Regra para rodar um teste específico
test-compliance-%: $(BUILD_DIR)/%.elf
	@printf "  %-40s" "TESTING $*..."
	@SIG_START=$$( $(RISCV_NM) $< | grep begin_signature | awk '{print $$1}' ); \
	SIG_END=$$( $(RISCV_NM) $< | grep end_signature | awk '{print $$1}' ); \
	$(MAKE) -C $(ROOT_DIR) -s test-e2e-processor_top \
		CORE_ARCH=$(CORE_ARCH) \
		SKIP_C_BUILD=1 \
		PROGRAM_PATH=$(abspath $(BUILD_DIR)/$*.hex) \
		SIM_BOOT_ADDR=-2147483648 \
		TARGET_BUILD_DIR=$(ROOT_DIR)/build/$(CORE_ARCH)/comp_$* \
		SIG_START=$$SIG_START \
		SIG_END=$$SIG_END \
		SIG_OUT=$(abspath $(BUILD_DIR)/$*.signature) \
		> $(BUILD_DIR)/$*.run.log 2>&1 || \
		(printf "[ $(RED)FAIL$(NC) ] (Simulation Error)\n" && exit 1)
	@diff -q $(BUILD_DIR)/$*.signature $(REF_DIR)/$*.reference_output > /dev/null \
		&& printf "[ $(GREEN)PASS$(NC) ]\n" \
		|| (printf "[ $(RED)FAIL$(NC) ] (Signature Mismatch)\n" && diff -y $(BUILD_DIR)/$*.signature $(REF_DIR)/$*.reference_output | head -n 20 && exit 1)

# 3. Orquestrador Final
test-compliance-all: $(addprefix test-compliance-, $(COMPLIANCE_TESTS))
	@printf "\n"
	@printf "$(GREEN)========================================================$(NC)\n"
	@printf "$(GREEN)            MULTI-CYCLE COMPLIANCE TEST SUITE          $(NC)\n"
	@printf "$(GREEN)========================================================$(NC)\n"
	@printf "  TARGET ARCHITECTURE : $(YELLOW)RV32I Base Integer$(NC)\n"
	@printf "  VERIFICATION STATUS : $(GREEN)100%% PASSED$(NC)\n"
	@printf "  TOTAL TESTS RUN     : $(YELLOW)$(words $(COMPLIANCE_TESTS)) / $(words $(COMPLIANCE_TESTS))$(NC)\n"
	@printf "$(GREEN)========================================================$(NC)\n\n"

clean:
	rm -rf $(BUILD_DIR)