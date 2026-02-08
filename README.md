# RISC-V (RV32I) Processor in VHDL

![VHDL](https://img.shields.io/badge/VHDL-2008-blue?style=for-the-badge&logo=vhdl)
![RISC-V](https://img.shields.io/badge/ISA-RISC--V%20RV32I-yellow?style=for-the-badge&logo=riscv)
![GHDL](https://img.shields.io/badge/Simulator-GHDL-green?style=for-the-badge&logo=ghdl)
![GTKWave](https://img.shields.io/badge/Waveform-GTKWave-9cf?style=for-the-badge&logo=gtkwave)
![Python](https://img.shields.io/badge/Python-3.10-blue?style=for-the-badge&logo=python)


```

   ██████╗ ██╗   ██╗██████╗ ██████╗ ██╗
   ██╔══██╗██║   ██║╚════██╗╚════██╗██║
   ██████╔╝██║   ██║ █████╔╝ █████╔╝██║
   ██╔══██╗╚██╗ ██╔╝ ╚═══██╗██╔═══╝ ██║     ->> PROJETO: Processador RISC-V (RV32I) 
   ██║  ██║ ╚████╔╝ ██████╔╝███████╗██║     ->> AUTOR: André Solano F. R. Maiolini 
   ╚═╝  ╚═╝  ╚═══╝  ╚═════╝ ╚══════╝╚═╝     ->> DATA: 15/09/2025

```

This repository contains the implementation of a 32-bit RISC-V processor (RV32I ISA) with support for multiple microarchitectures. The project is developed entirely in VHDL (2008 standard) and is intended as an educational project for studying computer architecture and processor design.

The design is modular, with each main processor component (ALU, Register File, Control Unit, etc.) implemented in its own file. Each module is accompanied by a self-verifying testbench to ensure correctness before final integration. The architecture is extensible, allowing easy addition of new microarchitectures (single-cycle, multi-cycle, pipelined, etc.) without modifying the core ISA definitions.

A top-level processor entity integrates all modules and can execute software compiled from C or Assembly, with the program being loaded dynamically into the simulation at runtime. The project includes a System-on-Chip (SoC) integration layer with bootloader support and configurable memory mapping.

## 🎯 Goals and Features

* **Target ISA:** RISC-V RV32I (Base Integer Instruction Set).
* **Microarchitectures:** Single-cycle, multi-cycle, pipelined [on future].
* **Language:** VHDL-2008.
* **Focus:** Design clarity, modularity, and educational purposes.
* **Verification:** Self-verifying testbenches for each component using COCOTB (Python).
* **Automation:** Fully automated build system via `Makefile` with dynamic CORE selection, automatic software compilation, and linker script selection.

## 📂 Project Structure

The repository is organized as follows to separate the hardware design (RTL), simulation, and software.

```text
RISC-V/
|
├── rtl/                              # Synthesizable VHDL code (Hardware)
│   ├── core/                         # Core processor components
│   │   ├── common/                   # ISA-common components (ALU, RegFile, etc.)
│   │   ├── single_cycle/             # Single-cycle microarchitecture
│   │   └── multi_cycle/              # Multi-cycle microarchitecture
│   │
│   ├── soc/                          # System-on-Chip integration
│   │   ├── boot_rom.vhd              # Boot ROM (holds the bootloader)
│   │   ├── bus_interconnect.vhd      # Wishbone/Custom Bus Interconnect
│   │   └── soc_top.vhd               # Top-level SoC entity
│   │
│   └── perips/                       # Peripheral Controllers
│       ├── gpio/                     # General Purpose I/O
│       ├── uart/                     # UART (Serial Communication)
│       └── vga/                      # VGA Video Controller
│
├── sim/                              # Simulation Environment (Cocotb + GHDL)
│   ├── core/                         # Processor Unit & Integration Tests
│   ├── soc/                          # SoC & Bus Tests
│   ├── perips/                       # Peripheral Tests
│   │
│   └── sw/                           # SIMULATION SOFTWARE 
│       ├── apps/                     # Apps compiled for simulation (e.g., test_all.s)
│       └── platform/                 # Simulation BSP (crt0.s, boot.ld)
│
├── fpga/                             # FPGA Implementation (Nexys 4 DDR)
│   ├── constraints/                  # Physical Constraints (.xdc files)
│   ├── scripts/                      # Vivado TCL build scripts
│   ├── upload.py                     # Python script for UART binary upload 
│   │
│   └── sw/                           # HARDWARE SOFTWARE 
│       ├── apps/                     # Apps with hardware drivers (Pong, Fractal, etc.)
│       └── platform/                 # Hardware BSP (start.s, hal_uart.c, hal_vga.c)
│
├── pkg/                              # VHDL Packages
│   └── riscv_isa_pkg.vhd             # Global RISC-V ISA Definitions
│
├── build/                            # Build Artifacts (Hex, Bin, Waveforms)
├── makefile                          # Automation (Simulation & Synthesis)
└── fpga.ps1                          # PowerShell wrapper for FPGA workflow
```

## 🛠️ Prerequisites

To compile and simulate this project, install the following tools and ensure they are in your PATH:

### Required Tools
1. **GHDL**: Open-source VHDL simulator (for simulation).
2. **GTKWave**: Waveform viewer (for waveform inspection).
3. **RISC-V GCC Toolchain** (riscv64-unknown-elf-gcc): For compiling C/Assembly programs.
4. **COCOTB**: Python-based coroutine testbench framework for hardware simulation.
5. **Python 3.10+**: Required for running cocotb testbenches and build utilities.

### Optional Tools
6. **Vivado**: Required for RTL synthesis, implementation, bitstream generation, and FPGA configuration on Nexys 4 DDR board.

### Platform Support

**Native Linux**: All tools work directly from the terminal.

**Windows Subsystem for Linux (WSL 1/2)**: The build system automatically detects WSL and handles tool invocation correctly:
- Vivado is called as `vivado.exe` from within WSL
- Python is invoked as `python3` or `python.exe` depending on installation
- Serial communication defaults to Windows COM ports (e.g., `COM6`)

The system automatically detects your platform and configures paths appropriately. No manual configuration needed!

## 🏗️ Build System Architecture

The build system is organized into modular Makefiles in the `mk/` directory:

- **mk/detect.mk**: Automatically detects platform (WSL vs Linux) and tool availability
- **mk/config.mk**: Centralized configuration, paths, compiler flags, and architecture selection
- **mk/rules_sw.mk**: Software compilation rules for FPGA and simulation targets
- **mk/rules_sim.mk**: Simulation and COCOTB testbench execution rules
- **mk/rules_fpga.mk**: FPGA synthesis, implementation, and programming rules
- **mk/sources.mk**: Automatic discovery and organization of VHDL source files

This modular structure ensures:
- **Clean separation of concerns**: Each file has a single, well-defined purpose
- **Easy debugging**: Configuration errors are isolated and easy to trace
- **Platform transparency**: WSL and Linux users use identical commands
- **Maintainability**: Adding new tools or architectures requires minimal changes

## 🚀 Quick Start: Using the Makefile

All commands are executed from the root of the repository. The Makefile automates software compilation, hardware simulation via COCOTB, and waveform visualization. It supports dynamic architecture selection (CORE), automatic software compilation, and linker script selection based on the test type.

```

     ██████╗ ██╗███████╗ ██████╗ ██╗   ██╗    
     ██╔══██╗██║██╔════╝██╔════╝ ██║   ██║    
     ██████╔╝██║███████╗██║█████╗██║   ██║    
     ██╔══██╗██║╚════██║██║╚════╝╚██╗ ██╔╝    
     ██║  ██║██║███████║╚██████╗  ╚████╔╝     
     ╚═╝  ╚═╝╚═╝╚══════╝ ╚═════╝   ╚═══╝      

================================================================================
                    RISC-V Project Build System (v2.0)
             Modular • Multi-Platform • WSL & Linux Compatible
================================================================================

📦 SOFTWARE COMPILATION
───────────────────────────────────────────────────────────────────────────────
  make sw SW=<prog>              Compile C/ASM application (auto-detect FPGA/Sim)
  make boot                      Compile FPGA bootloader
  make list-apps                 List available applications

🧪 HARDWARE TESTING & SIMULATION
───────────────────────────────────────────────────────────────────────────────
  make cocotb [CORE=<core>] TEST=<test> TOP=<top> [SW=<prog>]
                                 Run COCOTB simulation with optional software
  make cocotb TEST=<test> TOP=<top>      Unit test (no software)
  make list-tests [CORE=<core>]  List available testbenches

📊 VISUALIZATION & DEBUG
───────────────────────────────────────────────────────────────────────────────
  make view TEST=<test>          Open waveform (VCD) in GTKWave
  make info                      Show system info and project config
  make detect-info               Show platform and tool detection status

🔌 FPGA & UPLOAD
───────────────────────────────────────────────────────────────────────────────
  make fpga                      Synthesize and program FPGA bitstream
  make upload SW=<prog> [COM=<port>]
                                 Upload software via UART serial

🧹 MAINTENANCE
───────────────────────────────────────────────────────────────────────────────
  make clean                     Clean build directory
  make help                      Show this help message

================================================================================

💡 QUICK EXAMPLES:
  make list-apps                 See available programs
  make cocotb TEST=test_processor TOP=processor_top SW=fibonacci
  make view TEST=test_processor
  make fpga                      Synthesize for Nexys 4 DDR
  make upload SW=uart_echo       Send to FPGA via UART

```

### 0. System Information

Check if your platform is correctly detected:
```bash
make detect-info
```

Output example (Linux):
```
OS Detectado         : LINUX
Plataforma           : LINUX
WSL Detectado        : no

Ferramentas Disponíveis:
  • Vivado           : ✓ Sim
  • Python3          : ✓ Sim
  • GTKWave          : ✓ Sim
  • RISC-V GCC       : ✓ Sim

Porta Serial Padrão  : /dev/ttyUSB1
```

Or view complete project configuration:
```bash
make info
```

### 1. Clean Project
Removes all generated files:
```bash
make clean
```

### 2. Compile Software

Compile a program written in C or Assembly located in `sw/apps/`:
```bash
make sw SW=<program_name>
```

Example:
```bash
make sw SW=hello
```

Generates `build/sw/hello.hex` and `build/sw/hello.bin` that can be used as input for processor simulation.

**Note:** When running COCOTB tests with `SW=<prog>`, the software is compiled automatically, so explicit `make sw` is optional.

### 3. Run Automated Tests with COCOTB

Run automated tests using COCOTB (Python-based coroutine testbenches):

```bash
make cocotb [CORE=<core>] TEST=<testbench_name> TOP=<top_level> [SW=<program_name>]
```

**Parameters:**
- `CORE`: Microarchitecture to test (default: `single_cycle`). Options: `single_cycle`, `multi_cycle`, or any custom architecture defined in `rtl/core/`
- `TEST`: Name of the Python testbench file (without `.py` extension) located in `sim/core/<core>/`, `sim/core/common/`, `sim/soc/`, or `sim/perips/`
- `TOP`: Top-level VHDL entity to test (default: `processor_top`)
- `SW`: Optional software program to load into memory during simulation. **Automatically compiled if not present.**

**Key Features:**
- **Automatic bootloader injection**: For SoC tests (`boot_rom`, `soc_top`, `memory_system`, `memory_wrapper`), the bootloader is automatically compiled and injected
- **Automatic compiler selection**: Build system detects test type and selects appropriate linker script:
  - Processor tests use `link.ld` (address 0x00000000)
  - SoC tests use `link_soc.ld` (address 0x80000000)
- **Platform transparent**: Same commands work on Windows WSL and native Linux

**Examples:**

```bash
# List all available testbenches
make list-tests
make list-tests CORE=multi_cycle

# Unit tests - Common components (work with all architectures)
make cocotb TEST=test_alu TOP=alu
make cocotb TEST=test_reg_file TOP=reg_file
make cocotb TEST=test_imm_gen TOP=imm_gen
make cocotb TEST=test_lsu TOP=load_unit

# Single-cycle specific tests (default architecture)
make cocotb TEST=test_processor TOP=processor_top
make cocotb TEST=test_fetch_stage TOP=fetch_stage_wrapper

# Processor test with software (automatic compilation & memory mapping)
make cocotb TEST=test_processor TOP=processor_top SW=fibonacci
make cocotb TEST=test_processor TOP=processor_top SW=branch_test

# Multi-cycle architecture
make cocotb CORE=multi_cycle TEST=test_processor TOP=processor_top
make cocotb CORE=multi_cycle TEST=test_processor TOP=processor_top SW=fibonacci

# SoC tests (automatic bootloader injection)
make cocotb TEST=test_soc_top TOP=soc_top
make cocotb TEST=test_bus_arbiter TOP=bus_arbiter
make cocotb TEST=test_dma_controller TOP=dma_controller

```

**Execution Flow:**
1. Build system detects which test is being run by its name pattern
2. Software is automatically compiled with appropriate linker script (if `SW=` specified)
3. Bootloader is automatically compiled for SoC tests
4. GHDL simulator starts under COCOTB control
5. Python testbenches execute and interact with VHDL signals in real-time
6. Test results displayed in terminal with detailed assertions
7. VCD waveform generated for detailed signal inspection

**Memory Mapping:**
- **Processor unit tests** (processor_top, fetch_stage, etc.): `0x00000000` (using `link.ld`)
- **SoC integration tests** (soc_top, boot_rom, memory_*, bus_*, dma_*, etc.): `0x80000000` (using `link_soc.ld`)
- **Peripheral tests** (gpio, uart, vga): Component-specific memory mapping

**Generated Artifacts:**
- Terminal: Color-coded test pass/fail messages with assertions
- `build/cocotb/<core>/results.xml`: Detailed test results (JUnit format)
- `build/cocotb/<core>/wave-test_<name>.vcd`: Waveform file for GTKWave inspection
- `build/sw/`: Compiled software binaries (.hex, .bin)

### 4. Visualize Waveforms

Open simulation waveforms in GTKWave (requires running test first to generate VCD):
```bash
make view [CORE=<core>] TEST=<testbench_name>
```

**Examples:**
```bash
# Run test and view waveform in one workflow
make cocotb TEST=test_processor TOP=processor_top SW=fibonacci
make view TEST=test_processor

# View specific architecture
make cocotb CORE=multi_cycle TEST=test_processor TOP=processor_top
make view CORE=multi_cycle TEST=test_processor
```

Opens `build/cocotb/<core>/wave-test_<testbench_name>.vcd` in GTKWave for detailed signal inspection and debugging.

## 🔌 FPGA Programming & Upload

Synthesize the hardware and upload software to the physical FPGA board (Nexys 4).

### 1. Program FPGA (Bitstream)
Synthesize the VHDL code using VIVADO TCL script (`build.tcl`):
```bash
make fpga
```
### 2. Upload Software (UART)
Upload a program to the processor's memory via serial:
```bash
make upload SW=<program_name> [COM=<port>]
```

Examples:
```bash
# Upload fibonacci using default port (COM6)
make upload SW=fibonacci

# Upload pong specifying COM3
make upload SW=pong COM=COM3
```

## ✅ Verification & Testing

This project uses **COCOTB** (Coroutine-based Co-simulation Testbench) for comprehensive automated testing:

### Test Organization

- **`sim/core/common/`**: Unit tests for ISA-common components (ALU, RegFile, ImmGen, LSU, etc.) - work with all architectures
- **`sim/core/<arch>/`**: Architecture-specific tests (e.g., datapath, control logic for single-cycle or multi-cycle)
- **`sim/soc/`**: System-on-Chip integration tests (bus, memory, boot, DMA, interrupt controller)
- **`sim/perips/`**: Peripheral controller tests (UART, GPIO, VGA)
- **`sim/sw/`**: Software programs for testing (Assembly and C applications)

### Test Features

- **Python Testbenches**: Written in Python using COCOTB for readability and maintainability versus traditional VHDL testbenches
- **Self-Verifying**: Each testbench includes automated assertions that validate correct behavior
- **Real-Time Signal Access**: Python directly interacts with VHDL signals for precise control and monitoring
- **Automatic Test Detection**: Build system automatically identifies test type (unit vs integration) by name pattern
- **Bootloader Management**: SoC tests automatically compile and inject bootloader at correct memory address
- **Detailed Logging**: Tests provide color-coded console output showing all test cases and detailed assertions
- **Waveform Generation**: Each test generates VCD artifacts for inspection in GTKWave
- **Clean Compilation**: Only recompiles when sources change; smart dependency tracking

### Running Tests in Batch

```bash
# Run all unit tests
make list-tests CORE=single_cycle | grep test_ | xargs -I {} make cocotb TEST={} TOP={}

# Run all SoC tests
make list-tests | grep -E "^  • test_(soc|boot|bus|dma|memory)" | xargs -I {} make cocotb TEST={} TOP={}
```
