# =============================================================================
#
#  detect.mk
#  Detecção de Sistema Operacional e Ambiente
#
# =============================================================================
#
#  Detecta automaticamente o SO e ambiente (WSL/Linux) e configura
#  as variáveis de comando e paths apropriadas.
#
#  Suporta:
#   - Linux Nativo (qualquer distribuição)
#   - WSL 1 (Windows Subsystem for Linux versão 1)
#   - WSL 2 (Windows Subsystem for Linux versão 2)
#
# =============================================================================

.PHONY: detect-info

# Detecção Robusta de Ambiente
# =============================================================================

# Método 1: Detectar WSL através da presença de /proc/version
IS_WSL := $(shell grep -qi microsoft /proc/version 2>/dev/null && echo yes || echo no)

# Método 2: Fallback usando uname -r (caso /proc/version não exista)
ifeq ($(IS_WSL),no)
    UNAME_R := $(shell uname -r 2>/dev/null)
    ifneq ($(filter %WSL %wsl %microsoft,$(UNAME_R)),)
        IS_WSL := yes
    endif
endif

# Detectar SO base
UNAME_S := $(shell uname -s)
ifeq ($(UNAME_S),Linux)
    OS := LINUX
else ifeq ($(UNAME_S),Darwin)
    OS := MACOS
else
    OS := UNKNOWN
endif

# =============================================================================
#  CONFIGURAÇÃO DE COMANDOS POR AMBIENTE
# =============================================================================

ifeq ($(IS_WSL),yes)
    # --- WSL (Windows Subsystem for Linux) ---
    PLATFORM := WSL
    
    # Vivado e ferramentas Windows são chamadas através do .exe direto do WSL
    # Sem necessidade de powershell, o WSL consegue chamar executáveis Windows
    VIVADO_EXEC     := vivado.exe
    PYTHON_EXEC     := python.exe
    PYTHON_EXEC_ALT := python3.exe
    
    # Porta serial padrão no Windows (COM em vez de /dev/ttyUSB)
    DEFAULT_COM     := COM6
    
    # Função para converter paths para Windows se necessário
    TO_WINDOWS_PATH  = $(shell wslpath -w $(1) 2>/dev/null || echo $(1))
    
else ifeq ($(OS),LINUX)
    # --- Linux Nativo ---
    PLATFORM := LINUX
    
    VIVADO_EXEC     := vivado
    PYTHON_EXEC     := python3
    PYTHON_EXEC_ALT := python
    
    DEFAULT_COM     := /dev/ttyUSB1
    
    # No Linux nativo, não precisa converter paths
    TO_WINDOWS_PATH  = $(1)
    
else
    # --- Fallback para outros SOs ---
    PLATFORM := UNKNOWN
    
    VIVADO_EXEC     := vivado
    PYTHON_EXEC     := python3
    PYTHON_EXEC_ALT := python
    
    DEFAULT_COM     := /dev/ttyUSB0
    
    TO_WINDOWS_PATH  = $(1)
endif

# =============================================================================
#  VERIFICAÇÃO DE FERRAMENTAS
# =============================================================================

# Função auxiliar para verificar se um comando existe
TOOL_EXISTS = $(shell command -v $(1) >/dev/null 2>&1 && echo yes || echo no)

# Verifica disponibilidade de ferramentas (não obrigado, apenas info)
HAS_VIVADO      := $(call TOOL_EXISTS,$(VIVADO_EXEC))
HAS_PYTHON3     := $(call TOOL_EXISTS,$(PYTHON_EXEC))
HAS_PYTHON      := $(call TOOL_EXISTS,$(PYTHON_EXEC_ALT))
HAS_GTKWAVE     := $(call TOOL_EXISTS,gtkwave)
HAS_RISCV_GCC   := $(call TOOL_EXISTS,riscv64-unknown-elf-gcc)

# =============================================================================
#  INFORMAÇÕES DE DEBUG (para diagnóstico)
# =============================================================================

.PHONY: detect-info
detect-info:
	@echo " "
	@echo "╔═════════════════════════════════════════════════════════════╗"
	@echo "║           DETECÇÃO DE AMBIENTE E SISTEMA                    ║"
	@echo "╚═════════════════════════════════════════════════════════════╝"
	@echo " "
	@echo "  OS Detectado         : $(OS)"
	@echo "  Plataforma           : $(PLATFORM)"
	@echo "  WSL Detectado        : $(IS_WSL)"
	@echo " "
	@echo "  Ferramentas Disponíveis:"
	@echo "    • Vivado           : $(if $(findstring yes,$(HAS_VIVADO)),✓ Sim,✗ Não)"
	@echo "    • Python3          : $(if $(findstring yes,$(HAS_PYTHON3)),✓ Sim,✗ Não)"
	@echo "    • Python           : $(if $(findstring yes,$(HAS_PYTHON)),✓ Sim,✗ Não)"
	@echo "    • GTKWave          : $(if $(findstring yes,$(HAS_GTKWAVE)),✓ Sim,✗ Não)"
	@echo "    • RISC-V GCC       : $(if $(findstring yes,$(HAS_RISCV_GCC)),✓ Sim,✗ Não)"
	@echo " "
	@echo "  Porta Serial Padrão  : $(DEFAULT_COM)"
	@echo " "

# =============================================================================
