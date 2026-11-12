# BFloat16 routines: hand-written RV32I.
#
# uint16_t bf16_from_f32_asm(uint32_t f32bits)   a0 -> a0
# uint16_t bf16_mul_asm(uint16_t a, uint16_t b)  a0, a1 -> a0
# uint16_t bf16_sqrt_asm(uint16_t a)             a0 -> a0
#
# RV32I and Zicsr only: no mul, div, rem, no floating point, no compressed
# instructions. Tests: tests/tbf16.c.

    .text

# function of bf16_from_f32_asm
    .globl  bf16_from_f32_asm
    .type   bf16_from_f32_asm, @function
    .align  2
bf16_from_f32_asm:
    li t0, 0x7F800000
    and t1, a0, t0                # f32bits & 0x7F800000
    beq t1, t0, bf16_f32_ret      # NaN or Inf: keep the top 16 bits

    srli t1, a0, 16               # rounding = (f32bits >> 16) & 1
    andi t1, t1, 1
    li t0, 0x7FFF
    add a0, a0, t0                # f32bits += 0x7FFF + rounding
    add a0, a0, t1                # round to nearest, ties to even
bf16_f32_ret:
    srli a0, a0, 16               # return (uint16_t)(f32bits >> 16)
    ret
    .size   bf16_from_f32_asm, .-bf16_from_f32_asm

# function of bf16_mul_asm
# a2 = sign, a3 = exp_a / exp, a4 = exp_b
# a5 = ma / mantissa, a6 = mb, a7 = product
    .globl  bf16_mul_asm
    .type   bf16_mul_asm, @function
    .align  2
bf16_mul_asm:
    li t0, 0x8000
    xor a2, a0, a1                # sign = (a ^ b) & 0x8000
    and a2, a2, t0

    srli a3, a0, 7                # exp_a = (a >> 7) & 0xFF
    andi a3, a3, 0xFF
    srli a4, a1, 7                # exp_b = (b >> 7) & 0xFF
    andi a4, a4, 0xFF
    andi a5, a0, 0x7F             # frac_a, later used as ma
    andi a6, a1, 0x7F             # frac_b, later used as mb

    li t0, 0x7FFF
    and t1, a0, t0                # magnitude of a, for the zero check
    and t2, a1, t0                # magnitude of b, for the zero check
    li t0, 0xFF
    beq a3, t0, bf16_mul_a_special # check NaN / Inf of a first
    beq a4, t0, bf16_mul_b_special # then check NaN / Inf of b
    beq t1, zero, bf16_mul_zero  # zero times a finite value
    beq t2, zero, bf16_mul_zero

    bne a3, zero, bf16_mul_a_normal
    li a3, 1                      # denormal a: exp_a = 1
bf16_mul_a_loop:
    andi t0, a5, 0x80             # while ((ma & 0x80) == 0)
    bne t0, zero, bf16_mul_a_ready
    slli a5, a5, 1                # ma <<= 1
    addi a3, a3, -1               # exp_a--
    j bf16_mul_a_loop
bf16_mul_a_normal:
    ori a5, a5, 0x80              # normal a: restore the hidden one
bf16_mul_a_ready:
    bne a4, zero, bf16_mul_b_normal
    li a4, 1                      # denormal b: exp_b = 1
bf16_mul_b_loop:
    andi t0, a6, 0x80             # while ((mb & 0x80) == 0)
    bne t0, zero, bf16_mul_b_ready
    slli a6, a6, 1                # mb <<= 1
    addi a4, a4, -1               # exp_b--
    j bf16_mul_b_loop
bf16_mul_b_normal:
    ori a6, a6, 0x80              # normal b: restore the hidden one
bf16_mul_b_ready:
    li a7, 0                      # product = mul_shift_add(ma, mb)
bf16_mul_product_loop:
    andi t0, a6, 1                # if (mb & 1)
    beq t0, zero, bf16_mul_product_shift
    add a7, a7, a5                # product += ma
bf16_mul_product_shift:
    slli a5, a5, 1                # ma <<= 1
    srli a6, a6, 1                # mb >>= 1
    bne a6, zero, bf16_mul_product_loop

    add a3, a3, a4                # exp = exp_a + exp_b - 127
    addi a3, a3, -127
    li t0, 0x8000
    and t0, a7, t0                # if (product & 0x8000)
    beq t0, zero, bf16_mul_product_small
    srli a5, a7, 8                # mantissa = product >> 8
    addi a3, a3, 1                # exp++
    j bf16_mul_range
bf16_mul_product_small:
    srli a5, a7, 7                # mantissa = product >> 7
bf16_mul_range:
    li t0, 0xFF
    bge a3, t0, bf16_mul_inf    # exp >= 0xFF: overflow
    bge zero, a3, bf16_mul_underflow # exp <= 0: signed comparison

    slli t0, a3, 7                # pack sign | (exp << 7) | fraction
    andi a5, a5, 0x7F
    or a0, a2, t0
    or a0, a0, a5
    ret
bf16_mul_underflow:
    li t0, -6
    blt a3, t0, bf16_mul_zero   # exp < -6: return signed zero
    andi a5, a5, 0x7F             # fraction = mantissa & 0x7F, as in C
    li t0, 1
    sub t0, t0, a3                # shift count = 1 - exp
    srl a5, a5, t0                # fraction >>= (1 - exp)
    or a0, a2, a5
    ret
bf16_mul_a_special:
    bne a5, zero, bf16_mul_ret  # NaN a: return a unchanged
    beq t2, zero, bf16_mul_nan  # Inf a times zero b: quiet NaN
    j bf16_mul_inf              # Inf a wins even when b is NaN
bf16_mul_b_special:
    bne a6, zero, bf16_mul_return_b
    beq t1, zero, bf16_mul_nan  # zero a times Inf b: quiet NaN
bf16_mul_inf:
    li t0, 0x7F80
    or a0, a2, t0                 # return sign | 0x7F80
    ret
bf16_mul_return_b:
    mv a0, a1                     # NaN b: return b unchanged
    ret
bf16_mul_nan:
    li a0, 0x7FC0                 # return quiet NaN
    ret
bf16_mul_zero:
    mv a0, a2                     # return zero with the product sign
bf16_mul_ret:
    ret
    .size   bf16_mul_asm, .-bf16_mul_asm

# function of bf16_sqrt_asm
# a2 = e / result_exp, a3 = m, a4 = left, a5 = right
# a6 = ans, a7 = mid; t1 and t2 are the shift-and-add operands
    .globl  bf16_sqrt_asm
    .type   bf16_sqrt_asm, @function
    .align  2
bf16_sqrt_asm:
    li t0, 0x8000
    and t0, a0, t0                # sign = a & 0x8000
    srli a2, a0, 7                # exp = (a >> 7) & 0xFF
    andi a2, a2, 0xFF
    andi a3, a0, 0x7F             # frac = a & 0x7F
    li t1, 0xFF
    beq a2, t1, bf16_sqrt_special

    li t1, 0x7FFF
    and t1, a0, t1
    beq t1, zero, bf16_sqrt_zero # both +0 and -0 give +0
    bne t0, zero, bf16_sqrt_nan # negative nonzero gives quiet NaN
    beq a2, zero, bf16_sqrt_zero # positive denormal gives +0

    addi a2, a2, -127             # e = exp - 127
    addi a3, a3, 128              # m = 128 + frac
    andi t0, a2, 1
    beq t0, zero, bf16_sqrt_search_init
    addi a2, a2, -1               # odd exponent: e-- to make it even
    slli a3, a3, 1                # m <<= 1
bf16_sqrt_search_init:
    li a4, 90                     # left = 90
    li a5, 256                    # right = 256
    li a6, 90                     # ans = 90
bf16_sqrt_search_loop:
    blt a5, a4, bf16_sqrt_search_end # stop when left > right
    sub a7, a5, a4                # mid = left + (right - left) / 2
    srli a7, a7, 1                # right - left >= 0: shift replaces / 2
    add a7, a7, a4

    mv t1, a7                     # square = mul_shift_add(mid, mid)
    mv t2, a7
    li t3, 0                      # square = 0
bf16_sqrt_square_loop:
    andi t0, t2, 1                # if (multiplier & 1)
    beq t0, zero, bf16_sqrt_square_shift
    add t3, t3, t1                # square += multiplicand
bf16_sqrt_square_shift:
    slli t1, t1, 1                # multiplicand <<= 1
    srli t2, t2, 1                # multiplier >>= 1
    bne t2, zero, bf16_sqrt_square_loop

    srli t3, t3, 7                # square >> 7
    bltu a3, t3, bf16_sqrt_search_lower # (square >> 7) > m
    mv a6, a7                     # ans = mid
    addi a4, a7, 1                # left = mid + 1
    j bf16_sqrt_search_loop
bf16_sqrt_search_lower:
    addi a5, a7, -1               # right = mid - 1
    j bf16_sqrt_search_loop
bf16_sqrt_search_end:
    srai a2, a2, 1                # signed e >> 1, preserving negative e
    addi a2, a2, 127              # result_exp = (e >> 1) + 127
    li t0, 256
    bltu a6, t0, bf16_sqrt_range
    srli a6, a6, 1                # ans >= 256: ans >>= 1
    addi a2, a2, 1                # result_exp++
bf16_sqrt_range:
    li t0, 0xFF
    bge a2, t0, bf16_sqrt_inf   # result_exp >= 0xFF: overflow
    bge zero, a2, bf16_sqrt_zero # result_exp <= 0: underflow
    slli a0, a2, 7                # pack (result_exp << 7) | (ans & 0x7F)
    andi a6, a6, 0x7F
    or a0, a0, a6
    ret
bf16_sqrt_special:
    bne a3, zero, bf16_sqrt_ret # NaN: return a unchanged
    beq t0, zero, bf16_sqrt_ret # +Inf: return a unchanged
bf16_sqrt_nan:
    li a0, 0x7FC0                 # -Inf or negative nonzero: quiet NaN
    ret
bf16_sqrt_inf:
    li a0, 0x7F80                 # return +Inf
    ret
bf16_sqrt_zero:
    li a0, 0                      # return +0
bf16_sqrt_ret:
    ret
    .size   bf16_sqrt_asm, .-bf16_sqrt_asm
