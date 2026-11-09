# op1, op2, op3 and q_mul: hand-written RV32I.
#
# uint32_t op1_asm(uint32_t a, uint32_t b, int *n)   a0, a1, a2 -> a0
# uint32_t op2_asm(uint32_t a, uint32_t b)           a0, a1 -> a0
# uint32_t op3_asm(uint32_t a, uint32_t b)           a0, a1 -> a0
# int32_t  q_mul_asm(int32_t a, int32_t b)           a0, a1 -> a0
#
# RV32I and Zicsr only: no mul, div, rem, no floating point, no compressed
# instructions. q_mul forms a 64-bit product in a register pair. Tests:
# tests/tfixed.c.

    .text

# function of op1_asm
    .globl  op1_asm
    .type   op1_asm, @function
    .align  2
op1_asm:
    li t1, 0        # the value of n
    beq a1, zero, op1_ret
op1_loop:
    and t0, a0, a1  # c = (a & b) << 1
    slli t0, t0, 1
    xor a0, a0, a1  # a = a ^ b
    mv a1, t0       # b = c

    addi t1, t1, 1

    bne a1, zero, op1_loop
op1_ret:
    sw t1, 0(a2)    # store back to *n
    ret
    .size   op1_asm, .-op1_asm

# function of op2_asm
    .globl  op2_asm
    .type   op2_asm, @function
    .align  2
op2_asm:
    sub a0, a0, a1
    ret
#    addi sp, sp, -16
#    sw ra, 0(sp)
#    sw s0, 4(sp)
#
#    mv s0, a0
#
#    not a0, a1      # ~b
#    li a1, 1
#    addi a2, sp, 8
#    call op1_asm    # call op1(~b, 1, &n) and store ret in a1
#    mv a1, a0
#
#    mv a0, s0
#    call op1_asm    # op1(a, op1(~b, 1, &n), &n)
#
#    lw ra, 0(sp)
#    lw s0, 4(sp)
#    addi sp, sp, 16
#    ret
    .size   op2_asm, .-op2_asm

# function of op3_asm
    .globl  op3_asm
    .type   op3_asm, @function
    .align  2
op3_asm:
    and t0, a0, a1      # a & b & 1
    andi t0, t0, 1

    srli a0, a0, 1      # a >> 1
    srli a1, a1, 1      # b >> 1

    add a0, a0, a1
    add a0, a0, t0
    ret
    .size   op3_asm, .-op3_asm

# function of q_mul_asm
    .globl  q_mul_asm
    .type   q_mul_asm, @function
    .align  2
q_mul_asm:
    addi sp, sp, -16
    sw s0, 0(sp)
    sw s1, 4(sp)
    sw s2, 8(sp)
    sw s3, 12(sp)

    xor t3, a0, a1                 # negative = (a < 0) != (b < 0)
    srli t3, t3, 31

    bge a0, zero, mul_a_ready
    neg a0, a0                     # unsigned magnitude of a
mul_a_ready:
    bge a1, zero, mul_b_ready
    neg a1, a1                     # unsigned magnitude of b
mul_b_ready:
    li s0, 0                       # result of low 32 bits
    li s1, 0                       # result of high 32 bits

    mv s2, a0                      # extend unsigned magnitude to 64 bits
    li s3, 0

    beq a1, zero, mul_end
mul_loop:
    andi t0, a1, 1                 # if (ub & 1)
    beq t0, zero, result_not_add
    add s0, s0, s2                 # low 32 bits of result += ua
    sltu t2, s0, s2
    add s1, s1, s3                 # high 32 bits of result += ua
    add s1, s1, t2
result_not_add:
    srli a1, a1, 1                 # ub >>= 1
    srli t2, s2, 31                # ua <<= 1
    slli s2, s2, 1
    slli s3, s3, 1
    or s3, s3, t2
    bne a1, zero, mul_loop
mul_end:
    beq t3, zero, mul_round

    not s0, s0                     # product = -product
    not s1, s1                     # invert both halves, then add 1
    addi t1, s0, 1
    sltu t2, t1, s0
    mv s0, t1
    add s1, s1, t2
mul_round:
    li t0, 524288                  # (1 << 19)
    add t1, s0, t0                 # product += (1 << 19)
    sltu t2, t1, s0
    mv s0, t1
    add s1, s1, t2

    li t0, 0xFFFFF
    and s1, s1, t0                 # low 32 bits of product >> 20
    slli s1, s1, 12
    srli s0, s0, 20
    or a0, s1, s0

    lw s0, 0(sp)
    lw s1, 4(sp)
    lw s2, 8(sp)
    lw s3, 12(sp)
    addi sp, sp, 16
    ret
    .size   q_mul_asm, .-q_mul_asm
