FROM ubuntu:22.04

# Evitar prompts interativos durante a instalação
ENV DEBIAN_FRONTEND=noninteractive

# Atualizar e instalar dependências base, GHDL, Python e Toolchain RISC-V
RUN apt-get update && apt-get install -y \
    build-essential \
    git \
    curl \
    wget \
    ghdl \
    gtkwave \
    python3 \
    python3-pip \
    python3-dev \
    gcc-riscv64-unknown-elf \
    && rm -rf /var/lib/apt/lists/*

# Atualizar o pip e instalar ferramentas Python
RUN pip3 install --no-cache-dir --upgrade pip && \
    pip3 install --no-cache-dir cocotb pytest vsg mkdocs

# Definir diretório de trabalho padrão
WORKDIR /workspace