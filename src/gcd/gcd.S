# gcd_u32_asm: binary GCD, hand-written RV32I.
#
# uint32_t gcd_u32_asm(uint32_t a, uint32_t b)   a in a0, b in a1, result in a0
#
# RV32I and Zicsr only: no mul, div, rem, no floating point, no compressed
# instructions. Tests: tests/tgcd.c.

    .text

    .globl  gcd_u32_asm
    .type   gcd_u32_asm, @function
    .align  2

# function gcd_u32
gcd_u32_asm:
    beq a1, zero, b_is_zero   # if(b == 0) return a;
    beq a0, zero, a_is_zero   # if(a == 0) return b;
    j non_zero
a_is_zero:   # let return value be b
    mv a0, a1
b_is_zero:
    ret
non_zero:
    addi sp, sp, -16
    sw ra, 0(sp)
    sw s0, 4(sp)
    sw s1, 8(sp)
    sw s2, 12(sp)

    mv s0, a0
    mv s1, a1

    mv t1, s0             # ctz(a)
    call ctz
    mv s2, a0             # result of ctz(a) in s2
    srl s0, s0, s2            # a >>= ctz(a)

    mv t1, s1             # ctz(b)
    call ctz
    mv t1, a0             # result of ctz(b) in t1

    # s2: k
    bltu s2, t1, cmp_result   # if ctz(a) < ctz(b), jump
    mv s2, t1
cmp_result:
    srl s1, s1, t1            # b >>= ctz(b)
loop_gcd:
    beq s0, s1, gcd_return    # return a << k when a == b
    bgeu s0, s1, no_swap      # if(a >= b) goto no_swap

    xor s0, s0, s1            # swap(a, b) if a < b
    xor s1, s0, s1
    xor s0, s0, s1
no_swap:
    sub s0, s0, s1            # a = a - b

strip_even:
    srli s0, s0, 1
    andi t0, s0, 1
    beqz t0, strip_even

    j loop_gcd
gcd_return:
    sll a0, s0, s2

    lw ra, 0(sp)
    lw s0, 4(sp)
    lw s1, 8(sp)
    lw s2, 12(sp)
    addi sp, sp, 16
    ret
    .size   gcd_u32_asm, .-gcd_u32_asm

# function ctz
# num in t1
ctz:
    li a0, 0                # int i = 0
    li t0, 32
loop_ctz:
    andi t2, t1, 1          # if(num & 1) return
    bnez t2, ctz_return
    srli t1, t1, 1
    addi a0, a0, 1
    bltu a0, t0, loop_ctz
ctz_return:                 # return i
    ret
