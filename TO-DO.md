# 🚀 Plano de Ataque: NPU SoC 

Este plano visa transformar o SoC RISC-V atual em um sistema de alto desempenho com barramento robusto, autonomia de hardware e DMA.

---

## 📅 Fase 1: Upgrade do Barramento (Protocolo Ready/Valid)
**Objetivo:** Implementar controle de fluxo. O mestre coloca dados e sinaliza `VALID`. O escravo processa e sinaliza `READY`. A transferência só ocorre quando `VALID=1` e `READY=1`.

### 1.1. Definição da Interface
- **Alteração:** Adicionar sinais de handshake em todas as entidades conectadas ao barramento.
- **Sinais:**
  - `valid_o`: Indica que o endereço/dados são válidos.
  - `ready_i`: Indica que o escravo aceitou a transação.
- **Arquivos afetados:** `bus_interconnect.vhd`, `soc_top.vhd`, interfaces dos periféricos.

### 1.2. Atualização da CPU (Load/Store Unit)
- **Desafio:** A CPU precisa saber "parar" (Stall) se o periférico não estiver pronto (ex: NPU calculando ou RAM ocupada).
- **Ação:**
  - Modificar `lsu.vhd` para aguardar `dmem_ready_i` antes de avançar o pipeline.
  - Se `dmem_valid_o = '1'` e `dmem_ready_i = '0'`, a CPU deve congelar o PC.

### 1.3. Atualização dos Periféricos (Slaves)
- **RAM/ROM:** Podem ter `ready` fixo em '1' (se forem single-cycle) ou lógica de wait-state.
- **NPU:** Só levanta `ready` quando houver espaço no FIFO. Isso elimina a necessidade da CPU ficar lendo registrador de status (polling) e permite "backpressure" real.

---

## 🧠 Fase 2: Autonomia da NPU (Modo Streaming & Batch)
**Objetivo:** Remover a necessidade da CPU microgerenciar cada multiplicação.

### 2.1. Implementação de Contadores Internos
- **Hardware (`npu_core.vhd`):**
  - Adicionar registrador `REG_X_COUNT` (ex: número de inputs).
  - Adicionar Máquina de Estados (FSM) que, ao receber `CMD_START`, decrementa o contador automaticamente a cada dado consumido do FIFO.
- **Benefício:** A CPU configura "Vou mandar 784 bytes" e a NPU sabe exatamente quando terminar.

### 2.2. Persistência de Acumuladores
- **Hardware (`mac_pe.vhd`):**
  - Adicionar flag de configuração `CFG_ACC_PERSIST`.
  - Se `1`: O registrador acumulador **não zera** entre ativações.
  - Se `0`: Comportamento padrão (zera a cada nova operação).
- **Benefício:** Permite calcular camadas parciais sem ler/escrever resultados intermediários na RAM.

### 2.3. Driver Atualizado (`npu_lib.c`)
- Criar funções `npu_set_count()` e `npu_start_batch()`.
- O loop de envio de dados deixa de checar status a cada byte (confia no hardware ou no `ready` do barramento).

---

## ⚡ Fase 3: Controlador DMA (Direct Memory Access)
**Objetivo:** Mover dados RAM <-> NPU sem ocupar a CPU (Fetch/Decode/Execute).

### 3.1. Hardware do DMA (`dma_controller.vhd`)
- **Máquina de Estados:**
  1. **IDLE:** Espera configuração.
  2. **READ:** Lê da `SRC_ADDR` (via barramento).
  3. **WRITE:** Escreve na `DST_ADDR` (via barramento).
  4. **INC:** Incrementa endereços e decrementa contador.
- **Interfaces:**
  - *Slave:* Para CPU configurar (endereços, tamanho).
  - *Master:* Para acessar o barramento.

### 3.2. Arbitragem no Barramento (Multi-Master)
- **Atualização do `bus_interconnect.vhd`:**
  - Agora aceita duas entradas: `cpu_bus` e `dma_bus`.
  - **Lógica de Prioridade:** Se `dma_request = '1'`, o DMA ganha o barramento.
  - **CPU Stall:** Implementar o sinal que congela o clock da CPU enquanto o DMA usa o barramento (solução simples para evitar conflitos complexos).

### 3.3. Driver de Software (`hal_dma.c`)
- Função `dma_memcpy(src, dst, size)`.
- Ao chamar essa função, a CPU configura o DMA, dá start e "dorme" (clock gate) até a transferência acabar.

---

## 🧪 Fase 4: Integração e Benchmark Final
**Objetivo:** Provar o ganho de desempenho.

1. **Teste Unitário:** Validar o handshake do barramento com um teste simples de memória.
2. **Teste DMA:** Validar cópia de memória RAM->RAM.
3. **Teste NPU:** Rodar MNIST usando DMA + Autonomia.
4. **Benchmark:** Comparar tempos:
   - CPU Pura (sem NPU)
   - NPU v1 (Polling, sem DMA)
   - NPU v2 (DMA + Autonomia) -> **Meta: >10x Speedup.**
  
---

## 🟠 Fase 5: Periféricos e IO 
*Expansão das capacidades de entrada e saída do sistema.*

- [ ] **Controlador de GPIO V2** (`gpio_controller.vhd`)
  - [ ] Implementar registradores de direção (DDR) e dados (PORT/PIN).
  - [ ] Conectar aos LEDs/SWs/BTNs no Top Level.

- [ ] **Controlador de Interrupções (Opcional/Futuro)**
  - [ ] Adicionar suporte básico a interrupções externas (UART/GPIO).
  - [ ] Implementar registrador CSR `mie` e `mip` no Core.

---


