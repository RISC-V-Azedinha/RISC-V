#ifndef _COMPLIANCE_MODEL_H
#define _COMPLIANCE_MODEL_H

/* 1. HALT: Sinal de sucesso (0xDEADBEEF) */
#define RVMODEL_HALT \
    li x31, 0x10000008; \
    li x30, 1; \
    sw x30, 0(x31); \
    1: j 1b;

/* 2. BOOT e TRAP: Se o hardware falhar, ele vai para o Bad Address */
#define RVMODEL_BOOT       \
    .section ".text.init"; \
    .globl _start;         \
    _start:                \
    j _actual_start;       \
    .align 4;              \
    _trap_handler:         \
    li t0, 0x10000000;     \
    li t1, 0xBAD0BAD0;     \
    sw t1, 0(t0);          \
    _loop_trap:            \
    j _loop_trap;          \
    .align 4;              \
    _actual_start:

/* 3. SIGNATURE DATA */
#define RVMODEL_DATA_BEGIN   \
    .section ".data";        \
    .align 4;                \
    .global begin_signature; \
    begin_signature:

#define RVMODEL_DATA_END   \
    .align 4;              \
    .global end_signature; \
    end_signature:         \
    .align 4;              \
    .global tohost;        \
    tohost:                \
    .word 0;               \
    .global fromhost;      \
    fromhost:              \
    .word 0;

/* Macros obrigatorias vazias */
#define RVMODEL_IO_INIT
#define RVMODEL_IO_WRITE_STR(_R, _STR)
#define RVMODEL_IO_CHECK()
#define RVMODEL_IO_ASSERT_GPR_EQ(_S, _R, _I)
#define RVMODEL_IO_ASSERT_SFPR_EQ(_F, _R, _I)
#define RVMODEL_IO_ASSERT_DFPR_EQ(_D, _R, _I)

#endif