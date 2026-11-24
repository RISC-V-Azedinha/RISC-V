# Verificação

A verificação do SoC usa testes **Cocotb**, escritos em Python, sobre o simulador **GHDL**. Cada teste gera os estímulos, calcula o resultado esperado com um modelo de referência em Python e o compara com a saída do RTL. Os testes são organizados em níveis, do bloco isolado ao SoC completo executando o bootloader.

## Níveis de teste

| Nível | Alvo | O que verifica | Exemplos |
|---|---|---|---|
| Unitário | `make test-unit-<bloco>` | Um bloco isolado, contra um modelo de referência | `alu`, `reg_file`, `imm_gen`, `lsu`, `main_fsm`, `csr_file`, `clint`, `plic`, `dma_controller`, `uart_controller`, `sd_spi` |
| Integração | `make test-int-<bloco>` | Vários blocos do núcleo juntos | `datapath`, `control` |
| *End-to-end* | `make test-e2e-<topo>` | Um programa em C compilado e executado | `processor_top` (núcleo + memória), `soc_top` (SoC com o bootloader) |
| Conformidade | `make test-compliance` | A suíte oficial de testes de arquitetura RV32I | todas as instruções da ISA base |

Os testes do núcleo existem para as duas microarquiteturas, escolhidas por `CORE_ARCH=multi_cycle` (padrão) ou `CORE_ARCH=single_cycle`. Os testes de periféricos ficam em `sim/perips/`, e os do SoC, em `sim/soc/`. Para listar todos:

```bash
make list-tests
```

### Testes *end-to-end*

No teste `processor_top`, um programa de `sim/core/<núcleo>/e2e/sw/apps/` é compilado com o GCC e carregado na memória simulada; o teste acompanha a execução e confere o resultado. `APP=<programa>` escolhe o programa:

```bash
make test-e2e-processor_top APP=fibonacci
```

No teste `soc_top`, o bootloader real é compilado e embutido na Boot ROM, e o SoC inteiro é simulado a partir do *reset*.

### Formas de onda

Cada teste grava as formas de onda em `build/<núcleo>/<teste>/wave.vcd` e os resultados em `results.xml` no mesmo diretório:

```bash
make test-unit-alu
gtkwave build/multi_cycle/alu/wave.vcd
```

## Testes na placa

Além da simulação, `fpga/sw/tests/` reúne programas que verificam cada periférico no hardware real, com autoverificação pela UART: `gpio_test`, `uart2_test`, `vga_test`, `timer_test`, `clint_test`, `plic_test`, `dma_test`, `dma_irq_test`, `npu_test`, `npu_irq_test` e `debug_test`. Eles são enviados como qualquer programa:

```bash
make upload SW=plic_test
```

## Integração contínua

O *workflow* do GitHub Actions (`.github/workflows/ci.yml`) roda a cada *push* e *pull request* na `main`:

1. **Detecção de mudanças:** um filtro de caminhos verifica se o RTL, os testes ou os *scripts* mudaram; se não, a simulação não roda.
2. **Testes seletivos:** o `scripts/smart_test.py` compara os arquivos alterados com o grafo de dependências de `soc_deps.yml` (gerado por `scripts/gera_deps.py`) e executa apenas os testes afetados.
3. **Conformidade:** a suíte oficial RV32I roda para as duas microarquiteturas, monociclo e multiciclo.
