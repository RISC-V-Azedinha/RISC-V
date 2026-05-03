# 🧪 Simulação e Testbenches

Utiliza o framework COCOTB (COroutine COmmand-based TestBench)

## Tipos de Testbench

### 1. Testes de Unidade (`sim/core/` e `sim/perips/`)

Testam blocos isolados do processador e periféricos.

- `test_alu.py`: Testa operações matemáticas.
- `test_decoder.py`: Testa a decodificação de instruções.
- `test_uart_controller.py`: Testa a comunicação UART.
- [...]

### 2. Teste do Sistema (`sim/soc/`)

Testa o SoC completo (`test_soc_top.py`).

1. Instancia o soc_top.
2. Carrega um programa real (.hex) na memória RAM simulada.
3. Simula periféricos (ex: imprime saída da UART no terminal do GHDL).

## Como Rodar

Utilize o **makefile** na raiz:

```bash
make cocotb TEST=test_soc_top TOP=soc_top CORE=multi_cycle
```
