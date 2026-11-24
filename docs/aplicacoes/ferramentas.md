# Ferramentas do hospedeiro

As ferramentas em Python se comunicam com a placa pela UART do USB, a 921.600 bit/s, e cobrem o ciclo de uso do SoC: enviar programas, gravá-los no cartão, depurar a execução e conversar com os servidores da NPU.

| Ferramenta | Função |
|---|---|
| `fpga/upload.py` | Envia um programa ao bootloader pela UART; opcionalmente o grava no cartão microSD |
| `fpga/sd_image.py` | Grava um programa no cartão microSD direto pelo computador |
| `tools/debugger.py` | Depurador interativo: pausa, passo a passo, *breakpoint* e registradores |
| `tools/cnn_client.py` | Cliente do [servidor da CNN](servidores-npu.md#servidor-da-cnn-cnn_serverc), com treino, quantização e interface de desenho |
| `tools/bench_client.py`, `tools/bench_v2.py` | Clientes do [servidor de *benchmark*](servidores-npu.md#servidor-de-benchmark-bench_serverc) |

## Envio de programas (`upload.py`)

O `upload.py` reinicia o SoC no bootloader pelo [controlador de depuração](../soc/depuracao.md), envia o binário e, ao final, passa a mostrar o que o programa escreve na UART. É chamado pelo `make upload`, mas também pode ser usado diretamente:

```bash
python3 fpga/upload.py -p /dev/ttyUSB1 -f build/fpga/bin/blink.bin           # envia e executa
python3 fpga/upload.py -p /dev/ttyUSB1 -f build/fpga/bin/blink.bin --save    # e grava no cartão
python3 fpga/upload.py -p /dev/ttyUSB1 --erase-sd                            # apaga o cartão
```

| Opção | Padrão | Função |
|---|---|---|
| `-p`, `--port` | `COM6` | Porta serial |
| `-b`, `--baud` | `921600` | Taxa da UART |
| `-f`, `--file` | `app.bin` | Programa a enviar |
| `-s`, `--save` | — | Grava também no cartão microSD |
| `--erase-sd` | — | Apaga o programa do cartão |

O protocolo (palavra mágica `0xCAFEBABE`, tamanho, blocos de 64 bytes e confirmação) está descrito em [Boot](../software/boot.md).

## Gravação do cartão pelo computador (`sd_image.py`)

O caminho alternativo ao `make upload SAVE=1`: grava o programa no cartão microSD inserido no computador, no mesmo formato que o bootloader lê. O cabeçalho (`"RVSD"`, tamanho e *checksum*) vai no bloco 1 e o programa a partir do bloco 2, no espaço livre entre o MBR e a primeira partição; o cartão continua funcionando normalmente no computador.

```bash
sudo python3 fpga/sd_image.py /dev/sdX build/fpga/bin/blink.bin   # o cartão inteiro, não uma partição
```

## Depurador (`debugger.py`)

O depurador conversa com o [controlador de depuração](../soc/depuracao.md), que compartilha a UART do USB com o SoC: o sinal RTS escolhe quem está na linha. A tela mostra os 32 registradores e o PC, e aceita os comandos:

| Comando | Função |
|---|---|
| `h`, `halt` | Pausa a CPU |
| `r`, `resume` | Retoma a execução |
| `s`, `step` | Executa uma instrução |
| `b <endereço>`, `bkp` | Define um *breakpoint* em hardware (endereço em hexadecimal) |
| `c`, `clr` | Remove o *breakpoint* |
| `p`, `regs` | Atualiza a leitura dos registradores |
| `cr`, `clrregs` | Zera os registradores |
| `rst`, `reset` | Reinicia o SoC |
| `boot` | Reinicia no bootloader |
| `fibo` | Injeta na RAM um programa de Fibonacci de demonstração |
| `q`, `quit` | Sai |

A porta é configurada em `PORTA`, no início do arquivo.

## Interface gráfica (GUI-TCC)

A aplicação [GUI-TCC](https://github.com/RISC-V-Azedinha/GUI-TCC), em PyQt5, reúne as ferramentas acima em experimentos didáticos: o *datapath* do processador, E/S mapeada em memória, arbitragem de barramento, multitarefa, o fluxo de dados da NPU e a inferência de dígitos na FPGA. Ela é mantida em um repositório próprio.
