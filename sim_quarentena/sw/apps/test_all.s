# RISC-V RV32I - Suíte de Teste de Instruções em Assembly
#
# ESTRATÉGIA:
# - Usa um registrador temporário (t5) para o endereço de MMIO.
# - Se todos os testes passam, imprime 999 e sinaliza HALT.
# - Se um teste falha, imprime -1 e sinaliza HALT.

.section .text
.globl _start

# Endereços de MMIO
.equ INT_OUTPUT, 0x10000004
.equ HALT_MMIO,  0x10000008
.equ STACK_TOP,  0x00001000

_start:
    # Configura o stack pointer e o ponteiro de MMIO
    li sp, STACK_TOP
    li t5, INT_OUTPUT

    # --- INÍCIO DOS TESTES ---

    # Teste 1: ADDI
    li t0, 10
    addi t1, t0, 5
    li t2, 15
    bne t1, t2, fail
    li a0, 1
    sw a0, 0(t5)

    # Teste 2: ADD
    li t0, 20
    li t1, 22
    add t2, t0, t1
    li t3, 42
    bne t2, t3, fail
    li a0, 2
    sw a0, 0(t5)

    # TESTE 3: SUB 
    li t0, 50
    li t1, 10
    sub t2, t0, t1
    li t3, 40
    bne t2, t3, fail
    li a0, 3
    sw a0, 0(t5)

    # TESTE 4: LUI (Load Upper Immediate)
    lui t0, 0xABCDE
    li t1, 0xABCDE000
    bne t0, t1, fail
    li a0, 4
    sw a0, 0(t5)

    # TESTE 5: AUIPC (Add Upper Immediate to PC) 
    auipc t0, 0
    li a0, 5
    sw a0, 0(t5)

    # --- TESTES LÓGICOS ---

    li t0, 0b1010
    li t1, 0b1100

    # TESTE 6: AND 
    and t2, t0, t1
    li t3, 8
    bne t2, t3, fail
    li a0, 6
    sw a0, 0(t5)

    # TESTE 7: OR 
    or t2, t0, t1
    li t3, 14
    bne t2, t3, fail
    li a0, 7
    sw a0, 0(t5)

    # TESTE 8: XOR 
    xor t2, t0, t1
    li t3, 6
    bne t2, t3, fail
    li a0, 8
    sw a0, 0(t5)

    # --- TESTES LÓGICOS IMEDIATOS ---

    li t0, 0b1010

    # TESTE 9: ANDI
    andi t1, t0, 0b1100
    li t2, 8
    bne t1, t2, fail
    li a0, 9
    sw a0, 0(t5)

    # TESTE 10: ORI 
    ori t1, t0, 0b1100
    li t2, 14
    bne t1, t2, fail
    li a0, 10
    sw a0, 0(t5)

    # TESTE 11: XORI
    xori t1, t0, 0b1100
    li t2, 6
    bne t1, t2, fail
    li a0, 11
    sw a0, 0(t5)

    # --- TESTES DE SHIFT ---

    li t0, 2

    # TESTE 12: SLL 
    li t1, 3
    sll t2, t0, t1
    li t3, 16
    bne t2, t3, fail
    li a0, 12
    sw a0, 0(t5)

    # TESTE 13: SLLI 
    slli t1, t0, 4
    li t2, 32
    bne t1, t2, fail
    li a0, 13
    sw a0, 0(t5)

    # TESTE 14: SRL / SRLI
    li t0, 16
    srli t1, t0, 2
    li t2, 4
    bne t1, t2, fail
    li a0, 14
    sw a0, 0(t5)

    # TESTE 15: SRA / SRAI
    li t0, -16
    srai t1, t0, 2
    li t2, -4
    bne t1, t2, fail
    li a0, 15
    sw a0, 0(t5)

    # --- TESTES DE COMPARAÇÃO ---

    li t0, 10
    li t1, 20
    li t2, -10

    # TESTE 16: SLT
    slt t3, t0, t1
    li t4, 1
    bne t3, t4, fail
    li a0, 16
    sw a0, 0(t5)

    # TESTE 17: SLTU
    sltu t3, t2, t0
    li t4, 0
    bne t3, t4, fail
    li a0, 17
    sw a0, 0(t5)

    # TESTE 18: SLTI / SLTIU
    slti t3, t0, 5
    li t4, 0
    bne t3, t4, fail
    li a0, 18
    sw a0, 0(t5)

    # --- TESTES DE BRANCH ---

    li t0, 10
    li t1, 10
    li t2, 20

    # TESTE 19: BEQ
    beq t0, t1, beq_ok
    j fail

    beq_ok:

        li a0, 19
        sw a0, 0(t5)

    # TESTE 20: BNE
    bne t0, t1, fail
    li a0, 20
    sw a0, 0(t5)

    # TESTE 21: BLT
    blt t0, t2, blt_ok
    j fail

    blt_ok:
        li a0, 21
        sw a0, 0(t5)

    # TESTE 22: BGE
    bge t0, t2, fail
    li a0, 22
    sw a0, 0(t5)

    # TESTE 23: BLTU
    bltu t0, t2, bltu_ok
    j fail

    bltu_ok:
        li a0, 23
        sw a0, 0(t5)

    # TESTE 24: BGEU
    bgeu t2, t0, bgeu_ok
    j fail

    bgeu_ok:
        li a0, 24
        sw a0, 0(t5)

    # --- TESTES DE MEMÓRIA (Store/Load com verificação de alinhamento) ---

    # Endereço base para os testes de memória
    li t1, 0x00000200

    # TESTE 25: SW e LW (Palavra Completa)
    li t0, 0x1A2B3C4D
    sw t0, 0(t1)
    lw t2, 0(t1)
    bne t0, t2, fail
    li a0, 25
    sw a0, 0(t5)

    # TESTE 26: SH e LH (Meia-Palavra com Sinal)
    li t0, -3          # Carrega um valor negativo pequeno (0xFFFFFFFD)
    # Metade inferior (endereço 0x200)
    sh t0, 0(t1)       # Armazena a meia-palavra 0xFFFD
    lh t2, 0(t1)       # Carrega de volta com extensão de sinal
    bne t0, t2, fail   # t2 deve ser -3 (0xFFFFFFFD)
    # Metade superior (endereço 0x202)
    sh t0, 2(t1)
    lh t2, 2(t1)
    bne t0, t2, fail
    li a0, 26
    sw a0, 0(t5)

    # TESTE 27: SB e LBU (Byte sem Sinal em Posições Diferentes)
    li t0, 250         # Valor 0xFA
    # Posição 0 (0x200)
    sb t0, 0(t1)
    lbu t2, 0(t1)
    bne t0, t2, fail
    # Posição 1 (0x201)
    sb t0, 1(t1)
    lbu t2, 1(t1)
    bne t0, t2, fail
    # Posição 2 (0x202)
    sb t0, 2(t1)
    lbu t2, 2(t1)
    bne t0, t2, fail
    # Posição 3 (0x203)
    sb t0, 3(t1)
    lbu t2, 3(t1)
    bne t0, t2, fail
    li a0, 27
    sw a0, 0(t5)
    
    # TESTE 28: SB e LB (Byte com Sinal)
    li t0, -10         # Valor -10 (0xFFFFFFF6)
    sb t0, 0(t1)       # Armazena o byte 0xF6
    lb t2, 0(t1)       # Carrega com extensão de sinal, deve voltar a ser -10
    bne t0, t2, fail
    li a0, 28
    sw a0, 0(t5)

    # --- TESTES DE JUMP ---

    # TESTE 29: JAL
    la t0, jal_target
    jal ra, jal_target

    # TESTE 30: JALR
    li a0, 30
    sw a0, 0(t5)
    j jal_continue

    jal_target:
        li a0, 29
        sw a0, 0(t5)
        jalr x0, ra, 0

jal_continue:

    # TESTE 31: FENCE
    fence
    li a0, 31
    sw a0, 0(t5)
    
    j pass

# --- Rotinas de Fim ---
pass:
    li a0, 999
    sw a0, 0(t5)
    j halt_sim      # Pula para a rotina de parada

fail:
    li a0, -1
    sw a0, 0(t5)
    j halt_sim      # Pula para a rotina de parada

halt_sim:
    # Escreve no endereço de HALT para terminar a simulação
    li a0, 1
    li t0, HALT_MMIO
    sw a0, 0(t0)
    