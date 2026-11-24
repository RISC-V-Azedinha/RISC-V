# Aritmética em software

O núcleo implementa só o RV32I, sem a extensão M: não há instruções de multiplicação nem de divisão. Quando um programa em C multiplica ou divide, o GCC troca a operação por uma chamada a uma rotina de suporte, e a BSP fornece essas rotinas em `math_ops.c`:

| Rotina | Operação |
|---|---|
| `__mulsi3`, `__muldi3` | Multiplicação de 32 e de 64 bits |
| `__divsi3`, `__udivsi3` | Divisão de 32 bits, com e sem sinal |
| `__modsi3`, `__umodsi3` | Resto de 32 bits, com e sem sinal |
| `__udivdi3`, `__umoddi3` | Divisão e resto de 64 bits sem sinal |

Nada precisa ser chamado explicitamente: basta escrever `a * b` ou `a / b`, e o *linker* encontra a rotina na BSP.

## Custo

A multiplicação é feita por somas e deslocamentos, um bit do multiplicador por vez, e termina quando o multiplicador zera. Por isso, ela custa dezenas de ciclos e **depende dos dados**: multiplicar por um número pequeno, ou por zero, é bem mais rápido que por um número grande. É esse o motivo de o *benchmark* da NPU mostrar a CPU acelerando com ativações nulas, enquanto a NPU, que multiplica em hardware, gasta sempre o mesmo tempo.

!!! tip "Evitando multiplicações"
    Em laços críticos, multiplicações por potências de 2 podem ser escritas como deslocamentos (`x << 3` em vez de `x * 8`); o GCC já faz isso sozinho quando a constante é conhecida. Divisões de números sem sinal por potências de 2 também viram deslocamentos (`x >> 3`).
