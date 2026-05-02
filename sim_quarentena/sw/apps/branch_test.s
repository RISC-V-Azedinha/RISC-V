.section .text
.globl _start

.equ INT_OUTPUT, 0x10000004
.equ HALT_MMIO,  0x10000008

_start:
    li t5, INT_OUTPUT

# =========================================================
# BRANCHES – IGUALDADE
# =========================================================

    # TESTE 1: BEQ tomado
    li t0, 10
    li t1, 10
    beq t0, t1, beq_taken
    j fail
beq_taken:
    li a0, 1
    sw a0, 0(t5)

    # TESTE 2: BEQ não tomado
    li t0, 10
    li t1, 20
    beq t0, t1, fail
    li a0, 2
    sw a0, 0(t5)

    # TESTE 3: BNE tomado
    bne t0, t1, bne_taken
    j fail
bne_taken:
    li a0, 3
    sw a0, 0(t5)

    # TESTE 4: BNE não tomado
    li t1, 10
    bne t0, t1, fail
    li a0, 4
    sw a0, 0(t5)

# =========================================================
# BRANCHES – COMPARAÇÃO COM SINAL
# =========================================================

    # TESTE 5: BLT tomado (signed)
    li t0, -5
    li t1, 3
    blt t0, t1, blt_taken
    j fail
blt_taken:
    li a0, 5
    sw a0, 0(t5)

    # TESTE 6: BLT não tomado
    blt t1, t0, fail
    li a0, 6
    sw a0, 0(t5)

    # TESTE 7: BGE tomado
    bge t1, t0, bge_taken
    j fail
bge_taken:
    li a0, 7
    sw a0, 0(t5)

    # TESTE 8: BGE não tomado
    bge t0, t1, fail
    li a0, 8
    sw a0, 0(t5)

# =========================================================
# BRANCHES – COMPARAÇÃO SEM SINAL
# =========================================================

    # TESTE 9: BLTU tomado
    li t0, 1
    li t1, 0xFFFFFFFF
    bltu t0, t1, bltu_taken
    j fail
bltu_taken:
    li a0, 9
    sw a0, 0(t5)

    # TESTE 10: BLTU não tomado
    bltu t1, t0, fail
    li a0, 10
    sw a0, 0(t5)

    # TESTE 11: BGEU tomado
    bgeu t1, t0, bgeu_taken
    j fail
bgeu_taken:
    li a0, 11
    sw a0, 0(t5)

    # TESTE 12: BGEU não tomado
    bgeu t0, t1, fail
    li a0, 12
    sw a0, 0(t5)

# =========================================================
# JAL – PC RELATIVE
# =========================================================

    # TESTE 13: JAL forward
    jal ra, jal_forward
    j fail
jal_forward:
    li a0, 13
    sw a0, 0(t5)

    # TESTE 14: JAL backward
    jal ra, jal_back_target
    j fail

jal_back_target:
    li a0, 14
    sw a0, 0(t5)
    jal x0, jal_back_exit

jal_back_exit:

# =========================================================
# JALR – REGISTRO + OFFSET
# =========================================================

    # TESTE 15: JALR básico
    la t0, jalr_target
    jalr ra, t0, 0

jalr_return:
    li a0, 16
    sw a0, 0(t5)
    j next_test

jalr_target:
    li a0, 15
    sw a0, 0(t5)
    jalr x0, ra, 0

next_test:

# =========================================================
# JUMP SEM LINK (J)
# =========================================================

    # TESTE 17: J (pseudo-instrução)
    j jump_ok
    j fail
jump_ok:
    li a0, 17
    sw a0, 0(t5)

# =========================================================
# STRESS: LOOP COM BRANCH
# =========================================================

    # TESTE 18: Loop decremental com BLT
    li t0, 0
    li t1, 5

loop_test:
    addi t0, t0, 1
    blt t0, t1, loop_test
    li a0, 18
    sw a0, 0(t5)

# =========================================================
# SUCESSO FINAL
# =========================================================

pass:
    li a0, 999
    sw a0, 0(t5)
    j halt

fail:
    li a0, -1
    sw a0, 0(t5)

halt:
    li a0, 1
    li t0, HALT_MMIO
    sw a0, 0(t0)
