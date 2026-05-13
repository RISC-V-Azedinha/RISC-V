# Protocolo de Comunicação Host--FPGA

## Visão Geral

O sistema desenvolvido estabelece comunicação entre um computador
hospedeiro (**Host**), executando ferramentas em Python, e um
**System-on-Chip (SoC)** baseado na arquitetura **RISC-V**, implementado
em FPGA.

O objetivo dessa comunicação é permitir que dados abstratos --- como
modelos de Inteligência Artificial pré-treinados, comandos de controle e
informações de depuração --- sejam transmitidos do ambiente de software
para o hardware de forma estruturada e confiável.

Como o hardware digital não interpreta diretamente estruturas de alto
nível do Python, os dados passam por um processo composto pelas
seguintes etapas:

1.  serialização dos dados;
2.  empacotamento em mensagens binárias;
3.  transmissão via protocolo serial UART;
4.  reconstrução das informações no lado da FPGA.

------------------------------------------------------------------------

## Arquitetura de Comunicação

A comunicação entre Host e FPGA é **serial, bidirecional e orientada a
pacotes (frames)**.

### Diagrama Geral

``` mermaid
flowchart LR

Host[Host Python]
Serializer[Serialização]
UART[UART Serial]
FPGA[SoC RISC-V]

Host --> Serializer
Serializer --> UART
UART --> FPGA
FPGA --> UART
UART --> Host
```

O Host envia comandos e dados, enquanto a FPGA retorna respostas e
resultados de execução.

------------------------------------------------------------------------

### Comunicação Bidirecional

``` mermaid
sequenceDiagram
participant Host
participant FPGA

Host->>FPGA: Envio de frame UART
FPGA->>FPGA: Reconstrução dos dados
FPGA->>FPGA: Execução
FPGA-->>Host: Resposta
Host->>Host: Interpretação do resultado
```

------------------------------------------------------------------------

## Comunicação Serial UART

A **UART (Universal Asynchronous Receiver-Transmitter)** é utilizada
como meio físico de comunicação entre o computador e a FPGA.

### Características principais

-   transmissão assíncrona;
-   envio sequencial de bytes;
-   baixo custo de implementação em hardware;
-   suporte a comunicação full-duplex utilizando linhas TX e RX
    independentes.

A UART transmite apenas uma sequência contínua de bytes:

    Byte1 → Byte2 → Byte3 → Byte4 ...

Assim, qualquer estrutura complexa precisa ser previamente convertida
para esse formato por meio da serialização.

------------------------------------------------------------------------

## Serialização de Dados

Serialização é o processo de converter estruturas de dados de alto nível
em uma sequência linear de bytes transmissíveis.

Transformação geral:

    Objeto Python → Representação Binária → Stream de Bytes

Esse processo permite que dados produzidos no Host sejam corretamente
interpretados pelo processador RISC-V.

------------------------------------------------------------------------

## Transformação de Dados

O fluxo de conversão ocorre conforme o diagrama abaixo:

``` mermaid
flowchart LR

A[Dados Python<br>listas/matrizes]
--> B[Flatten]
--> C[Conversão para bytes]
--> D[Empacotamento]
--> E[UART]
--> F[FPGA]
```

### 1. Linearização (Flatten)

O hardware acessa memória **linear endereçável byte a byte**.\
Assim, matrizes precisam ser convertidas em vetores sequenciais.

Exemplo:

    [a b
     c d]

↓

    [a b c d]

------------------------------------------------------------------------

### 2. Conversão para Bytes

Os valores numéricos são convertidos para sua representação binária,
tornando-se uma sequência contínua de bytes pronta para transmissão.

------------------------------------------------------------------------

## Endianness (Ordem dos Bytes)

Endianness define a ordem em que os bytes de um número são armazenados
ou transmitidos.

A arquitetura **RISC-V** utiliza tipicamente o formato
**Little-Endian**, no qual o byte menos significativo é transmitido
primeiro.

Consequentemente, o Host deve respeitar essa ordem durante a
serialização para garantir a correta reconstrução dos dados na FPGA.

!!! warning 
    Diferenças de endianness entre transmissor e receptor resultam em interpretação incorreta dos valores numéricos.

------------------------------------------------------------------------

## Empacotamento de Dados

Como a UART transmite apenas fluxos contínuos de bytes, é necessário
definir uma estrutura de mensagem (frame) que permita identificar
limites e tipos de operação.

### Estrutura Conceitual do Frame

    [HEADER][COMANDO][TAMANHO][PAYLOAD][CHECKSUM]

| Campo     | Função                                 |
|-----------|----------------------------------------|
| HEADER    | Indica início do frame                 |
| COMANDO   | Tipo de operação                       |
| TAMANHO   | Quantidade de bytes do payload         |
| PAYLOAD   | Dados serializados                     |
| CHECKSUM  | Verificação de integridade             |

Esse formato permite que o hardware:

-   sincronize a recepção;
-   identifique o tipo de operação;
-   determine quantos bytes devem ser lidos.

------------------------------------------------------------------------

### Fluxo Completo do Sistema

``` mermaid
flowchart TB

User[Ação do Usuário]
GUI[Interface Gráfica]
Python[Script Host]
Serialize[Serialização]
Packet[Empacotamento]
UART[Envio UART]
FPGA[SoC RISC-V]

User --> GUI
GUI --> Python
Python --> Serialize
Serialize --> Packet
Packet --> UART
UART --> FPGA
```

------------------------------------------------------------------------

## Reconstrução dos Dados na FPGA

Ao receber um frame UART, o sistema embarcado executa as seguintes
etapas:

1.  detecção do início da mensagem;
2.  leitura do comando recebido;
3.  recepção do payload byte a byte;
4.  reconstrução dos valores numéricos;
5.  armazenamento dos dados em memória.

Após essa etapa, o processador RISC-V passa a operar diretamente sobre
as informações recebidas.

------------------------------------------------------------------------

## Limitações da Comunicação Serial

Apesar da simplicidade e baixo custo de implementação, a comunicação
UART apresenta limitações inerentes:

-   largura de banda reduzida quando comparada a interfaces paralelas ou
    barramentos de alta velocidade;
-   ausência nativa de controle avançado de fluxo;
-   dependência de sincronização correta entre transmissor e receptor;
-   maior latência para transferência de grandes volumes de dados.

Ainda assim, a UART mostra-se adequada para o contexto educacional do
projeto, oferecendo simplicidade de integração, facilidade de depuração
e alta portabilidade entre plataformas.
