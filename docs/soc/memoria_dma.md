!!! warning Atualizar referência do link para documentação do barramento.

# Organização do Espaço de Memória do SoC RISC-V

## 1. Espaço de Endereçamento

A arquitetura RV32I define um espaço de endereçamento linear de **32 bits**, resultando em **4 GB (2³² bytes)** de memória virtualmente endereçável. Este espaço é dividido em regiões distintas para memórias e periféricos, seguindo o modelo de **Memory-Mapped I/O (MMIO)** onde cada dispositivo é acessado através de endereços de memória específicos.

A organização deste espaço segue as convenções da especificação RISC-V, onde as regiões de memória principal (ROM e RAM) ocupam os extremos inferiores e superiores do mapa, enquanto os periféricos de I/O são mapeados em uma região intermediária.

### 1.1 Mapa de Endereços do SoC

A tabela abaixo apresenta o mapa de endereçamento completo do SoC, detalhando cada região de memória e periférico:

| Nome | Endereço Base | Endereço Final | Tamanho | Descrição |
|------|---------------|----------------|---------|-----------|
| **Boot ROM** | `0x0000_0000` | `0x0000_0FFF` | 4 KB | Memória apenas de leitura de inicialização (bootloader) |
| **Reservado** | `0x0000_1000` | `0x07FF_FFFF` | ~128 MB | Espaço não utilizado |
| **UART** | `0x1000_0000` | `0x1000_FFFF` | 64 KB | Controlador UART (comunicação serial) |
| **GPIO** | `0x2000_0000` | `0x2000_FFFF` | 64 KB | Pinos de entrada/saída geral |
| **VGA** | `0x3000_0000` | `0x3001_FFFF` | 128 KB | Controlador de vídeo (VRAM) |
| **DMA** | `0x4000_0000` | `0x4000_FFFF` | 64 KB | Controlador DMA |
| **CLINT** | `0x5000_0000` | `0x5000_FFFF` | 64 KB | Core Local Interrupt Controller (timers) |
| **PLIC** | `0x6000_0000` | `0x6003_FFFF` | 256 KB | Platform-Level Interrupt Controller |
| **Reservado** | `0x7000_0000` | `0x7FFF_FFFF` | 256 MB | Espaço não utilizado |
| **RAM** | `0x8000_0000` | `0x8003_FFFF` | 256 KB | Memória RAM principal |
| **Reservado** | `0x8004_0000` | `0x8FFF_FFFF` | ~255 MB | Espaço não utilizado |
| **NPU** | `0x9000_0000` | `0x9FFF_FFFF` | 256 MB | Neural Processing Unit |

#### 1.1.1 Representação Visual do Mapa de Memória

```
0x0000_0000 ┌─────────────────────┐
            │      Boot ROM        │  4 KB
            │    (0x0000_0000)     │
0x0000_0FFF ├─────────────────────┤
            │                     │
            │     Reservado       │  ~128 MB
            │                     │
0x0FFF_FFFF ├─────────────────────┤
            │       UART         │  64 KB
            │    (0x1000_0000)    │
0x1000_FFFF ├─────────────────────┤
            │       GPIO         │  64 KB
            │    (0x2000_0000)    │
0x2000_FFFF ├─────────────────────┤
            │       VGA          │  128 KB
            │    (0x3000_0000)    │
0x3001_FFFF ├─────────────────────┤
            │       DMA          │  64 KB
            │    (0x4000_0000)    │
0x4000_FFFF ├─────────────────────┤
            │      CLINT         │  64 KB
            │    (0x5000_0000)    │
0x5000_FFFF ├─────────────────────┤
            │       PLIC         │  256 KB
            │    (0x6000_0000)    │
0x6003_FFFF ├─────────────────────┤
            │     Reservado       │  256 MB
            │                     │
0x7FFF_FFFF ├─────────────────────┤
            │       RAM          │  256 KB
            │    (0x8000_0000)    │
0x8003_FFFF ├─────────────────────┤
            │     Reservado       │  ~255 MB
            │                     │
0x8FFF_FFFF ├─────────────────────┤
            │       NPU          │  256 MB
            │    (0x9000_0000)    │
0x9FFF_FFFF └─────────────────────┘
```

### 1.2 Decodificação de Endereços

A decodificação de endereços é realizada no módulo `bus_interconnect.vhd`, que utiliza os **bits mais significativos (31-28)** do endereço de 32 bits para identificar qual periférico ou memória deve responder à requisição. Esta abordagem permite uma decodificação rápida e simples, utilizando apenas 4 bits para selecionar entre até 16 regiões distintas.

O código VHDL a seguir demonstra a lógica de decodificação implementada:

```vhdl
dmem_slv <= SLV_ROM   when dmem_addr_i(31 downto 28) = x"0" else
            SLV_UART  when dmem_addr_i(31 downto 28) = x"1" else
            SLV_GPIO  when dmem_addr_i(31 downto 28) = x"2" else
            SLV_VGA   when dmem_addr_i(31 downto 28) = x"3" else
            SLV_DMA   when dmem_addr_i(31 downto 28) = x"4" else
            SLV_CLINT when dmem_addr_i(31 downto 28) = x"5" else
            SLV_PLIC  when dmem_addr_i(31 downto 28) = x"6" else
            SLV_RAM   when dmem_addr_i(31 downto 28) = x"8" else
            SLV_NPU   when dmem_addr_i(31 downto 28) = x"9" else
            SLV_NONE;
```

É importante observar que as regiões `0x7` e `0xA` até `0xF` não são utilizadas nesta implementação, servindo como espaço reservado para futuras expansões.

---

## 2. Memórias

O SoC dispõe de duas memórias principais: a **Boot ROM**, que armazena o código de inicialização, e a **RAM principal**, utilizada para execução de programas e armazenamento de dados.

### 2.1 Boot ROM 

A Boot ROM é uma memória apenas de leitura que armazena o bootloader do sistema. Ela é inicializada durante a síntese com o conteúdo de um arquivo HEX externo.

#### Características Técnicas

| Parâmetro | Valor |
|-----------|-------|
| **Tamanho** | 4 KB (2¹⁰ palavras de 32 bits) |
| **Tipo** | Dual-port sincronizada |
| **Porta A** | Fetch de instruções (IMem) |
| **Porta B** | Leituras de dados (DMem) |
| **Inicialização** | Carrega conteúdo de arquivo `.hex` |

#### Interface de Sinais

A Boot ROM oferece duas portas de leitura independentes, permitindo acessos simultâneos:

```vhdl
port (
    clk       : in  std_logic;
    
    -- Porta A: Dedicada ao Fetch (Instruções)
    vld_a_i   : in  std_logic;
    addr_a_i  : in  std_logic_vector(31 downto 0);
    data_a_o  : out std_logic_vector(31 downto 0);
    rdy_a_o   : out std_logic;

    -- Porta B: Dedicada ao LOAD/STORE (Dados)
    vld_b_i   : in  std_logic;
    addr_b_i  : in  std_logic_vector(31 downto 0);
    data_b_o  : out std_logic_vector(31 downto 0);
    rdy_b_o   : out std_logic
);
```

#### Inicialização via Arquivo

A ROM é inicializada através da função `init_rom_from_file`, que lê um arquivo no formato HEX:

```vhdl
impure function init_rom_from_file(file_name : string) return t_rom is
    file     f       : text open read_mode is file_name;
    variable l       : line;
    variable v_data  : std_logic_vector(31 downto 0);
    variable v_rom   : t_rom := (others => (others => '0'));
begin
    for i in 0 to (2**ADDR_WIDTH)-1 loop
        exit when endfile(f);
        readline(f, l);
        hread(l, v_data);
        v_rom(i) := v_data;
    end loop;
    return v_rom;
end function;
```

A síntese em FPGA utiliza o atributo `ram_style = "block"` para inferir Block RAM, otimizando recursos.

### 2.2 RAM Principal 

A RAM principal é uma memória de leitura e escrita utilizada para armazenamento temporário de dados e código durante a execução do programa.

#### Características Técnicas

| Parâmetro | Valor |
|-----------|-------|
| **Tamanho** | 256 KB (2¹⁶ palavras de 32 bits) |
| **Tipo** | Dual-port com BRAM inferida |
| **Largura de dados** | 32 bits |
| **Escrita** | Byte-a-byte (WE de 4 bits) |
| **Índices de acesso** | `addr(17 downto 2)` (palavras) |

#### Interface de Sinais

```vhdl
generic (
    ADDR_WIDTH : integer := 16;  -- 256 KB
    DATA_WIDTH : integer := 32
);
port (
    clk        : in  std_logic;
    
    -- Porta A
    vld_a_i    : in  std_logic; 
    we_a       : in  std_logic_vector((DATA_WIDTH/8)-1 downto 0);
    addr_a     : in  std_logic_vector(ADDR_WIDTH-1 downto 0);
    data_a_i   : in  std_logic_vector(DATA_WIDTH-1 downto 0);
    data_a_o   : out std_logic_vector(DATA_WIDTH-1 downto 0);
    rdy_a_o    : out std_logic;
    
    -- Porta B
    vld_b_i    : in  std_logic;
    we_b       : in  std_logic_vector((DATA_WIDTH/8)-1 downto 0);
    addr_b     : in  std_logic_vector(ADDR_WIDTH-1 downto 0);
    data_b_i   : in  std_logic_vector(DATA_WIDTH-1 downto 0);
    data_b_o   : out std_logic_vector(DATA_WIDTH-1 downto 0);
    rdy_b_o    : out std_logic
);
```

#### Escrita Byte-a-Byte

A RAM suporta escrita em granularidade de byte através de um vetor de Write Enable:

```vhdl
for i in 0 to (DATA_WIDTH/8)-1 loop
    if we_b(i) = '1' then
        ram(to_integer(unsigned(addr_b)))(8*i+7 downto 8*i) := data_b_i(8*i+7 downto 8*i);
    end if;
end loop;
```

---

## 3. Registradores de Controle e Status (CSRs)

### 3.1 Conceito e Propósito

Os **Control and Status Registers (CSRs)** são registradores especiais definidos na especificação **RISC-V Privileged Architecture** que permitem a comunicação entre o software e o hardware do processador. Diferentemente dos registradores gerais (x0-x31), os CSRs são acessados através de instruções dedicadas (CSRRC, CSRRCI, CSRRM, CSRRS, CSRRSI, CSRRW, CSRRWI) e ocupam um espaço de endereçamento separado de 12 bits (permitindo até 4096 registradores).

Os CSRs servem para três propósitos principais:

- **Controle de Interrupções:** Habilitar/desabilitar interrupções e configurar handlers
- **Monitoramento de Status:** Indicar condições de erro e estado do processador
- **Configuração de Ambiente:** Definir o modo de operação e contexto de execução

### 3.2 CSRs Implementados (Machine Mode)

O SoC implementa um subconjunto mínimo de CSRs necessários para operação em Machine Mode, conforme especificado na arquitetura RISC-V Privileged:

| Endereço | Nome | Acesso | Descrição |
|----------|------|--------|-----------|
| `0x300` | `mstatus` | RW | Status global do processador (bit MIE = Machine Interrupt Enable) |
| `0x304` | `mie` | RW | Máscara de habilitação de interrupções individuais |
| `0x305` | `mtvec` | RW | Endereço base para vetores de trap |
| `0x340` | `mscratch` | RW | Registro auxiliar para uso do kernel |
| `0x341` | `mepc` | RW | Machine Exception Program Counter (endereço de retorno após trap) |
| `0x342` | `mcause` | RW | Machine Cause Register (código numérico da causa do trap) |
| `0x344` | `mip` | RO | Machine Interrupt Pending (reflete interrupções pendentes em hardware) |

### 3.3 Descrição Detalhada dos CSRs

#### mstatus (Machine Status Register - 0x300)

Este registrador mantém o estado global de interrupção do processador. Após reset, apenas os bits MPIE (Machine Previous Interrupt Enable) e MPP (Machine Previous Privilege) são configurados:

- **Bit 3 (MIE):** Quando em 1, interrupções habilitadas globalmente
- **Bit 7 (MPIE):** Armazena o valor de MIE antes da entrada em trap
- **Bits 12-11 (MPP):** Modo de privilégio anterior (11 = Machine Mode)

```vhdl
-- Configuração após reset
r_mstatus <= (others => '0'); 
r_mstatus(c_MPIE_BIT) <= '1';      -- MPIE = 1
r_mstatus(12 downto 11) <= "11";  -- MPP = 11 (Machine Mode)
```

#### mie (Machine Interrupt Enable - 0x304)

Máscara individual para cada fonte de interrupção:

| Bit | Nome | Descrição |
|-----|------|-----------|
| 11 | MEIE | Machine External Interrupt Enable |
| 7 | MTIE | Machine Timer Interrupt Enable |
| 3 | MSIE | Machine Software Interrupt Enable |

#### mip (Machine Interrupt Pending - 0x344)

Este registrador é **read-only** e reflete o estado atual das linhas de interrupção em tempo real:

```vhdl
s_mip_comb <= (
    11 => Irq_Ext_i,   -- MEIP
    7  => Irq_Timer_i, -- MTIP
    3  => Irq_Soft_i,  -- MSIP
    others => '0'
);
```

### 3.4 Operações Atômicas

As instruções CSR suportam três operações atômicas, implementadas via campo Funct3[1:0]:

| Opcode | Instrução | Operação | Descrição |
|--------|-----------|----------|-----------|
| `01` | CSRRW | Read/Write | Lê o valor antigo, escreve novo valor |
| `10` | CSRRS | Read/Set | Lê o valor antigo, seta bits (OR com máscara) |
| `11` | CSRRC | Read/Clear | Lê o valor antigo, limpa bits (AND NOT máscara) |

A atomicidade é garantida porque a leitura e modificação ocorrem no mesmo ciclo de clock:

```vhdl
case Csr_Op_i is
    when "01" => -- CSRRW
        s_write_val   <= Csr_WData_i;
        s_we_internal <= '1';
    
    when "10" => -- CSRRS
        s_write_val   <= s_curr_val OR Csr_WData_i;
        if unsigned(Csr_WData_i) /= 0 then
            s_we_internal <= '1';
        end if;

    when "11" => -- CSRRC
        s_write_val   <= s_curr_val AND (NOT Csr_WData_i);
        if unsigned(Csr_WData_i) /= 0 then
            s_we_internal <= '1';
        end if;
    
    when others => null;
end case;
```

### 3.5 Tratamento de Traps

Quando uma exceção ou interrupção ocorre, o hardware salva automaticamente o contexto:

```vhdl
if Trap_Enter_i = '1' then
    r_mepc   <= Trap_PC_i;      -- Salva PC atual para retorno
    r_mcause <= Trap_Cause_i;    -- Salva motivo do trap
    
    -- Salva contexto de interrupção
    r_mstatus(c_MPIE_BIT) <= r_mstatus(c_MIE_BIT); -- Backup MIE
    r_mstatus(c_MIE_BIT)  <= '0';                    -- Desabilita interrupções
```

O retorno do trap (instrução MRET) restaura o contexto:

```vhdl
elsif Trap_Return_i = '1' then
    r_mstatus(c_MIE_BIT)  <= r_mstatus(c_MPIE_BIT);
    r_mstatus(c_MPIE_BIT) <= '1';
```

---

## 4. Memory-Mapped I/O (MMIO)

### 4.1 Conceito

**Memory-Mapped I/O (MMIO)** é uma técnica de comunicação onde os periféricos de hardware são acessados como se fossem posições de memória comum. Esta abordagem simplifica a programação, permitindo que instruções normais de load/store acessem registradores de controle e buffers de dados dos periféricos.

No contexto do SoC, cada periférico possui um conjunto de registradores mapeados em endereços específicos dentro do espaço de endereçamento.

### 4.2 Acesso em Software (BSP)

O Board Support Package (BSP) fornece macros para acesso volátil a registradores MMIO:

```c
#define MMIO32(addr) (*(volatile uint32_t *)(addr))
#define MMIO8(addr)  (*(volatile uint8_t  *)(addr))
```

A palavra-chave `volatile` garante que o compilador não otimize away acessos consecutivos ao mesmo endereço, essencial para registradores de status.

### 4.3 Registradores MMIO por Periférico

#### UART (`0x1000_0000`)

O controlador UART (Universal Asynchronous Receiver-Transmitter) gerencia a comunicação serial com o computador host.

| Offset | Nome | Acesso | Descrição |
|--------|------|--------|-----------|
| `0x00` | `DATA` | RW | Registrador de dados TX/RX |
| `0x04` | `CTRL` | RW | Registrador de controle e status |

Definições de bits do registrador de controle:

```c
#define UART_STATUS_TX_BUSY  (1 << 0)   // Transmissor ocupado
#define UART_STATUS_RX_VALID (1 << 1)   // Dado RX disponível
#define UART_CMD_RX_POP      (1 << 0)   // Comando: remover dado
#define UART_CMD_RX_FLUSH    (1 << 2)   // Comando: limpar buffer
```

#### CLINT (`0x5000_0000`)

O **Core Local Interrupt Controller** gerencia interrupções de timer e software localmente ao núcleo, funcionando em conjunto com o PLIC para interrupções externas.

| Offset | Nome | Acesso | Descrição |
|--------|------|--------|-----------|
| `0x00` | `MSIP` | RW | Machine Software Interrupt Pending |
| `0x08` | `MTIMECMP_LO` | RW | Timer Compare Low (32 bits inferiores) |
| `0x0C` | `MTIMECMP_HI` | RW | Timer Compare High (32 bits superiores) |
| `0x10` | `MTIME_LO` | RW | Timer Value Low |
| `0x14` | `MTIME_HI` | RW | Timer Value High |

O timer de 64 bits é implementado como dois registradores de 32 bits, permitindo contagens superiores a 4 segundos a 100 MHz.

#### PLIC (`0x6000_0000`)

O **Platform-Level Interrupt Controller** gerencia prioridades e roteamento de interrupções de múltiplas fontes para o núcleo.

| Offset | Nome | Acesso | Descrição |
|--------|------|--------|-----------|
| `0x000000` | `PRIORITY` | RW | Prioridade das fontes de interrupção (escalável por ID) |
| `0x001000` | `PENDING` | RO | Bitmap de interrupções pendentes (bits 0-31) |
| `0x002000` | `ENABLE` | RW | Habilita interrupções por fonte |
| `0x200000` | `THRESHOLD` | RW | Limiar de prioridade (interrupções abaixo são ignoradas) |
| `0x200004` | `CLAIM` | RW | Claim: lê fonte; Complete: marca como tratada |

#### NPU (`0x9000_0000`)

A **Neural Processing Unit** é um acelerador de hardware para operações de redes neurais (multiplicação de matrizes).

| Offset | Nome | Acesso | Descrição |
|--------|------|--------|-----------|
| `0x00` | `STATUS` | RO | Flags de status (BUSY, DONE, OUT_VLD) |
| `0x04` | `CMD` | WO | Comandos de controle (START, RST_PTRS) |
| `0x08` | `CONFIG` | RW | Dimensão K da matriz |
| `0x10` | `WRITE_W` | WO | Porta de escrita de pesos |
| `0x14` | `WRITE_A` | WO | Porta de escrita de ativações |
| `0x18` | `READ_OUT` | RO | Porta de leitura de resultados |
| `0x40` | `QUANT_CFG` | RW | Configuração de quantização (shift, zero-point) |
| `0x44` | `QUANT_MULT` | RW | Multiplicador PPU |
| `0x48` | `FLAGS` | RW | Flags de controle (ReLU) |
| `0x80` | `BIAS_BASE` | RW | Endereço base do vetor de bias |

Bits de status:

```c
#define NPU_STATUS_BUSY     (1 << 0)  // Operação em andamento
#define NPU_STATUS_DONE     (1 << 1)  // Operação concluída
#define NPU_STATUS_OUT_VLD  (1 << 3)  // Saída válida disponível
```

Bits de comando:

```c
#define NPU_CMD_RST_PTRS     (1 << 0)  // Reseta ponteiros internos
#define NPU_CMD_START        (1 << 1)  // Inicia execução
#define NPU_CMD_ACC_CLEAR    (1 << 2)  // Limpa acumuladores
#define NPU_CMD_ACC_NO_DRAIN (1 << 3)  // Mantém resultado no array (tiling)
```

#### GPIO (`0x2000_0000`)

Controlador de pinos de entrada/saída de propósito geral.

| Offset | Nome | Acesso | Descrição |
|--------|------|--------|-----------|
| `0x00` | `DATA` | RW | Leituras de chaves e escritas nos LEDs |

#### VGA (`0x3000_0000`)

Controlador de vídeo VGA com buffer de frame de 320x240 pixels.

| Offset | Nome | Acesso | Descrição |
|--------|------|--------|-----------|
| `0x00000` - `0x1FFFC` | `FRAME_BUFFER` | RW | Pixels do frame buffer (24 bits/pixel) |
| `0x1FFFE` | `VSYNC` | RW | Registrador de sincronização vertical |

---

## 5. Controlador DMA

### 5.1 Gargalo de Desempenho: Transferência por Polling/Busy-Wait

#### O Problema da Cópia por Software

Quando o processador RISC-V executa uma cópia de memória via software (load/store em loop), cada palavra transferida consome ciclos de CPU que poderiam ser utilizados para outras tarefas. Para uma transferência de **256 KB** (tamanho total da RAM principal):

```
Palavras de 32 bits em 256 KB = 262.144 / 4 = 65.536 palavras

Ciclos consumidos por iteração do loop:
├── LOAD do endereço fonte:         1 ciclo
├── STORE no endereço destino:       1 ciclo
├── Incremento de ponteiros:      ~2 ciclos
└── Atualização de contador:      ~2 ciclos
                                      ──────────
Total por palavra transferida:      ~6 ciclos

Total para 256 KB: 65.536 × 6 ≈ 393.216 ciclos de CPU
```

Durante esses aproximadamente **400.000 ciclos**, o processador fica **indisponível** para:

- Processamento de interrupções UART (podendo perder dados)
- Atualização de timers e agendamento
- Manipulação de outros periféricos
- Execução de lógica de aplicação

#### Impacto no Throughput do Sistema

| Cenário | Tempo (100 MHz) | Ciclos CPU | Utilização CPU |
|---------|-----------------|------------|----------------|
| Cópia 256 KB via CPU (busy-wait) | 3,93 µs | 393.216 | 100% |
| Cópia 256 KB via DMA | ~0,65 µs (efetivo) | ~6 | 0% (livre) |

A CPU poderia utilizar esses ~393.000 ciclos economizados para:

- Processar ~2.000 interrupções UART (200 ciclos cada)
- Executar ~50.000 operações aritméticas inteiras
- Atender múltiplas requisições de software

### 5.2 Visão Geral do DMA

O **Direct Memory Access (DMA)** é um controlador que permite transferência de dados entre memória e periféricos **sem intervenção do núcleo de processamento**. Enquanto a CPU configura a transferência, o DMA executa a cópia de dados de forma autônoma, permitindo que o processador execute outras tarefas em paralelo.

O DMA deste SoC opera em **modo 1D (linear)**, transferindo um bloco contíguo de palavras de 32 bits de uma região de memória para outra. A arquitetura dual-interface permite que o DMA seja simultaneamente **slave** (configurado pela CPU) e **master** (acesso autônomo ao barramento).

### 5.3 Microarquitetura do Controlador DMA

O DMA possui uma arquitetura **dual-interface**:

- **Interface Slave (cfg_*)**: Utilizada pela CPU para configurar registradores de controle
- **Interface Master (m_*)**: Utilizada para acessar o barramento de memória de forma autônoma

```
┌─────────────────────────────────────────────────────────┐
│                    DMA CONTROLLER                        │
│                                                         │
│  ┌───────────────┐         ┌───────────────────────┐  │
│  │   Interface   │         │    Máquina de          │  │
│  │   Slave       │         │    Estados (FSM)       │  │
│  │  (Config)     │         │                        │  │
│  │               │         │  IDLE → READ_REQ →     │  │
│  │  cfg_addr     │         │  READ_WAIT → WRITE_REQ │  │
│  │  cfg_data     │         │  → CHECK_DONE          │  │
│  │  cfg_we       │         │                        │  │
│  └───────────────┘         └───────────┬───────────┘  │
│                                        │              │
│  ┌───────────────┐                     │              │
│  │   Interface   │◄────────────────────┘              │
│  │   Master      │                                     │
│  │  (Barramento) │                                     │
│  │               │         ┌───────────────────────┐  │
│  │  m_addr       │────────►│      Bus Arbiter      │  │
│  │  m_data       │         └───────────────────────┘  │
│  │  m_we         │                                     │
│  │  m_vld        │                                     │
│  │  m_rdy        │                                     │
│  └───────────────┘                                     │
│                                                         │
│  irq_done_o ──────────────────────────────────────────►│
└─────────────────────────────────────────────────────────┘
```

### 5.3 Registradores de Configuração

O DMA expõe quatro registradores mapeados em seu espaço de endereço:

| Offset | Nome | Tamanho | Descrição |
|--------|------|--------|-----------|
| `0x00` | `SRC_ADDR` | 32 bits | Endereço de origem (RAM) |
| `0x04` | `DST_ADDR` | 32 bits | Endereço de destino (RAM ou periférico) |
| `0x08` | `COUNT` | 32 bits | Número de palavras de 32 bits a transferir |
| `0x0C` | `CONTROL` | 32 bits | Bits de controle e status |

#### Detalhamento do Registrador CONTROL

| Bit | Nome | Acesso | Descrição |
|-----|------|--------|-----------|
| 0 | START | RW | Escreve 1 para iniciar transferência; hardware limpa ao completar |
| 1 | FIXED_DST | RW | 1 = destino fixo (FIFO mode), 0 = incremento automático |
| 2 | BUSY | RO | 1 = transferência em andamento |

### 5.4 Máquina de Estados

O DMA implementa uma FSM (Finite State Machine) com os seguintes estados:

```vhdl
type state_type is (
    IDLE,       -- Ocioso, aguardando START
    READ_REQ,   -- Requisição de leitura da origem
    READ_WAIT,  -- Espera intermediária para arbiter
    WRITE_REQ,  -- Requisição de escrita no destino
    CHECK_DONE  -- Verifica se transferência terminou
);
```

#### Diagrama de Estados

```
                    ┌───────────────────────────────────────────────┐
                    │                                               │
                    ▼                                               │
┌───────┐   busy=1    ┌─────────┐   m_rdy=1   ┌───────────┐         │
│ IDLE  │────────────►│READ_REQ │────────────►│READ_WAIT  │         │
└───┬───┘             └────┬────┘             └─────┬─────┘         │
    ▲                       │                        │               │
    │                       │ m_rdy=1                ▼               │
    │                       │              ┌─────────────┐           │
    │                       └─────────────►│ WRITE_REQ   │───────────┤
    │                                ┌───►└──────┬──────┘           │
    │                                │          │                  │
    │                                │          ▼                  │
    │                                │    ┌───────────┐             │
    │                                │    │CHECK_DONE │             │
    │                                │    └─────┬─────┘             │
    │                                │          │                   │
    │                                │  count<=1?┘                 │
    │                                │    │         \              │
    │                                │    │          │              │
    │(count<=1)──── irq_done=1       │    ▼          ▼              │
    └────────────────────────────────┴───┐IDLE      │READ_REQ      │
                                          │(termina)  └──────────────┘
```

#### Descrição dos Estados

**IDLE:** Estado inicial. O DMA aguarda até que a CPU escreva 1 no bit START do registrador CONTROL. Quando ativado, levanta a flag `r_busy` e transita para `READ_REQ` se `r_count > 0`.

**READ_REQ:** Coloca o endereço `r_src_addr` no barramento (`m_addr_o`) e levanta o sinal `m_vld_o` indicando uma requisição de leitura. Permanece neste estado até que `m_rdy_i` seja asserted pelo arbiter. Quando pronto, captura o dado em `m_data_i` para o buffer interno.

**READ_WAIT:** Estado de espera intermediário onde `m_vld_o` é baixado por um ciclo. Esta pausa é necessária para que o bus_arbiter possa sair do estado de travamento (WAIT_M1) e aceitar a nova requisição de escrita no próximo ciclo.

**WRITE_REQ:** Coloca o endereço `r_dst_addr` e o dado do buffer no barramento, levantando simultaneamente `m_vld_o` e `m_we_o`. Aguarda confirmação do arbiter via `m_rdy_i`.

**CHECK_DONE:** Incrementa `r_src_addr` (+4 bytes) e aplica a lógica de destino:
- Se `FIXED_DST = 0`: incrementa `r_dst_addr` (+4 bytes)
- Se `FIXED_DST = 1`: mantém `r_dst_addr` fixo (modo FIFO)

Se `r_count` atingir 1 ou 0, a transferência está completa: transita para IDLE e_assert `irq_done_o`. Caso contrário, retorna para `READ_REQ`.

### 5.5 Modo Destino Fixo (FIFO Mode)

Quando o bit `FIXED_DST` está setado, o endereço de destino permanece constante durante toda a transferência. Este modo é essencial para periféricos com interface FIFO, como a NPU:

```vhdl
if r_ctrl_fixed_dst = '0' then
    r_dst_addr <= r_dst_addr + 4;  -- Incrementa para próximo endereço
else
    -- Mantém destino fixo (FIFO mode)
end if;
```

### 5.6 Exemplo de Uso em Software

#### Transferência Memória-para-Memória

```c
// Transferir 1024 palavras de buf_src para buf_dst
DMA_SRC_ADDR  = (uint32_t)buf_src;    // Endereço de origem
DMA_DST_ADDR  = (uint32_t)buf_dst;    // Endereço de destino
DMA_COUNT     = 1024;                  // 1024 palavras (4 KB)
DMA_CONTROL   = 0x01;                  // START = 1

// Aguardar conclusão via polling
while (DMA_CONTROL & 0x04);  // Espera BUSY=0
```

#### Transferência para NPU (FIFO Mode)

```c
// Enviar pesos para a NPU (endereço fixo)
DMA_SRC_ADDR  = weights_buffer;                    // Endereço dos pesos
DMA_DST_ADDR  = NPU_BASE_ADDR + 0x10;             // WRITE_W da NPU
DMA_COUNT     = K_DIM * K_DIM;                     // K² palavras
DMA_CONTROL   = 0x03;                              // START | FIXED_DST

// Poll ou interrupção quando concluído
while (DMA_CONTROL & 0x04);  // Aguarda BUSY=0

// Iniciar execução da NPU após carregamento
NPU_CMD = NPU_CMD_START;
```

### 5.7 Interação com o Bus Arbiter

O DMA compartilha o barramento de dados com a CPU através de um **bus_arbiter**. Este componente implementa uma política de prioridade onde:

1. Se ambos solicitam acesso simultâneo, o arbiter concede ao primeiro que fez a requisição
2. O DMA pode ser pausado a qualquer momento pela CPU, pois não há garantia de acesso contínuo
3. O estado `READ_WAIT` foi introduzido especificamente para resolver um problema de handshaking onde o arbiter ficava travado entre requisições de leitura e escrita

### 5.8 Eficiência do Sistema: Liberação do Núcleo RISC-V

#### Análise Comparativa de Ciclos

A tabela a seguir compara os recursos consumidos pela CPU entre os dois métodos de transferência:

| Método | Ciclos CPU | Ciclos Totais (DMA) | CPU Disponível |
|--------|------------|---------------------|----------------|
| **Busy-Wait (256 KB)** | 393.216 | 393.216 | 0% |
| **DMA (256 KB)** | ~6 | 393.216 | 99,99% |

**Detalhamento dos ciclos de CPU com DMA:**
```
Configuração:        4 writes × 1 ciclo    =     4 ciclos
Poll/Interrupção:   ~2 verificações × 1   =     2 ciclos
                                                ─────────
Total CPU:                                      ~6 ciclos
```

#### Ganho de Eficiência

Para uma transferência de **256 KB**:

```
Ciclos economizados   = 393.216 - 6 = 393.210 ciclos
Taxa de liberação     = 393.210 / 393.216 × 100 ≈ 99,998%
```

#### Oportunidades de Paralelismo

Com o DMA em operação, a CPU pode executar **concorrentemente**:

1. **Processamento de dados anteriores** — já processa o bloco N-1 enquanto o bloco N é transferido
2. **Atendimento de interrupções** — não perde eventos de UART ou timers
3. **Tarefas de controle** — lógica de aplicação continua executando

```
Tempo ─────────────────────────────────────────────────────────────────────►

CPU:   [Config DMA][ Poll ][Processa][Processa][Processa][Processa]
                │       │         │         │         │         │
DMA:            [ ══════════════ 256KB ══════════════ ] [Done]
                │       │                   │         │         │
                └───────┴───────────────────┴─────────┴─────────┘
                        ~6 ciclos               ~400.000 ciclos livres

RESULTADO: CPU livre para executar outras ~400.000+ instruções
```

#### Resumo: Benefícios Arquiteturais do DMA

| Aspecto | Sem DMA | Com DMA |
|---------|---------|---------|
| **Ciclos CPU (256 KB)** | 393.216 | ~6 |
| **Disponibilidade da CPU** | 0% durante cópia | 99,99% |
| **Latência outras tarefas** | Bloqueadas | Executam em paralelo |
| **Throughput do barramento** | Competição impossível | Arbiter gerencia |
| **Perda de interrupções** | Alta probabilidade | Mínima |

---

## 6. Arquitetura do Sistema de Barramentos

### 6.1 Visão Geral da Interconexão

O SoC implementa uma arquitetura de barramentos hierárquica com três canais distintos:

1. **Canal de Instruções (IMem):** Acesso exclusivo à memória de instruções (ROM/RAM)
2. **Canal de Dados (DMem):** Acesso a memória e periféricos via arbiter
3. **Canal CSR:** Acesso dedicado aos registradores de controle do processador

Esta separação permite que fetch de instruções e acessos a dados ocorram simultaneamente, aumentando o throughput do sistema.

### 6.2 Topologia de Barramentos

```
                         ┌─────────────────────────────────────────┐
                         │            PROCESSOR_TOP                │
                         │                                         │
                         │  ┌───────────────────────────────────┐  │
                         │  │         Datapath (Pipeline)       │  │
                         │  │                                   │  │
                         │  │  IMem ──────► Fetch/Decode/Exec   │  │
                         │  │  DMem ──────► Load/Store          │  │
                         │  │  CSRs ──────► Control/Status      │  │
                         │  │                                   │  │
                         │  └───────────────────────────────────┘  │
                         └─────────────────┬───────────────────────┘
                                           │
              ┌────────────────────────────┼────────────────────────────┐
              │                            │                            │
    ┌─────────▼─────────┐        ┌─────────▼─────────┐                  │
    │   Canal IMem      │        │   Canal DMem       │                  │
    │  (Fetch Only)      │        │  (Load/Store)       │                  │
    │                   │        │                  │                  │
    │  ┌─────────────┐  │        │  ┌───────────┐    │                  │
    │  │ Bus         │  │        │  │ Bus       │    │                  │
    │  │ Interconnect│◄─┼────────┼─►│ Arbiter   │    │                  │
    │  │ (Decodif.) │  │        │  │ (CPU+DMA) │    │                  │
    │  └─────────────┘  │        │  └─────┬─────┘    │                  │
    │        │          │        │        │          │                  │
    │        ▼          │        │        ▼          │                  │
    │  ┌───────────┐    │        │  ┌───────────┐    │                  │
    │  │ Boot ROM  │    │        │  │ Bus       │    │                  │
    │  │   RAM     │    │        │  │ Interconnect    │                  │
    │  └───────────┘    │        │  │ (Decodif.) │    │                  │
    └────────────────────┘        │  └─────┬─────┘    │                  │
                                  │        │          │                  │
                                  │        ▼          │                  │
                                  │  ┌───────────┐    │                  │
                                  │  │  Perif.   │    │                  │
                                  │  │  UART     │    │                  │
                                  │  │  GPIO     │    │                  │
                                  │  │  VGA      │    │                  │
                                  │  │  CLINT    │    │                  │
                                  │  │  PLIC     │    │                  │
                                  │  │  NPU      │    │                  │
                                  │  │  DMA      │    │                  │
                                  │  └───────────┘    │                  │
                                  └──────────────────┘                  │
                                                                   │
                         ┌─────────────────────────────────────────┼─┐
                         │         DMA Controller                  │ │
                         │                                          │ │
                         │  CPU configura via DMem                 │◄┘
                         │  DMA acessa memória via m_*              
                         │  Gera interrupção ao concluir            
                         └─────────────────────────────────────────┘
```

### 6.3 Bus Arbiter

O **bus_arbiter** resolve conflitos entre CPU e DMA no canal de dados, implementando arbitragem baseada em prioridades fixas. Quando ambos os mestres solicitam acesso simultâneo:

1. CPU mantém prioridade sobre DMA para operações críticas de fetch
2. DMA aguarda até que a CPU libere o barramento
3. Requisições de DMA são empacotadas e servidas em ordem

### 6.4 Bus Interconnect

O **bus_interconnect** realiza a decodificação de endereços e roteamento de dados. Para cada requisição:

1. Extrai os bits de seleção de periférico (31-28)
2. Identifica o slave correspondente
3. Roteia os sinais de endereço, dados e controle
4. Multiplexa o dado de resposta ao master

!!! info Mais informações sobre o barramento em [Barramento: Mestres e Escravos ](https://url.com).
---


