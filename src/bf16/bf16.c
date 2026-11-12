#include "bf16.h"

/* Dummies: every function returns 0. Replace with the real routines. */
uint16_t bf16_from_f32(uint32_t f32bits)
{
    /* 0xFF of exponent */
    if ((f32bits & 0x7F800000) == 0x7F800000) {
        return (uint16_t) (f32bits >> 16);
    }

    /* Ties to even */
    int rounding = (f32bits >> 16) & 1;

    return (uint16_t) ((f32bits + 0x7FFF + rounding) >> 16);
}

/* Multiplication without MUL instruction */
static uint32_t mul_shift_add(uint32_t a, uint32_t b)
{
    uint32_t result = 0;

    while (b) {
        if (b & 1)
            result += a;

        a <<= 1;
        b >>= 1;
    }

    return result;
}

uint16_t bf16_mul(uint16_t a, uint16_t b)
{
    uint16_t sign = (a ^ b) & 0x8000;

    int exp_a = (a >> 7) & 0xFF;
    int exp_b = (b >> 7) & 0xFF;

    uint32_t frac_a = a & 0x7F;
    uint32_t frac_b = b & 0x7F;

    /* Handle NaN and Inf: check a first */
    if (exp_a == 0xFF) {
        if (frac_a != 0)
            return a;

        if ((b & 0x7FFF) == 0)
            return 0x7FC0;

        return sign | 0x7F80;
    }

    /* Check b second */
    if (exp_b == 0xFF) {
        if (frac_b != 0)
            return b;

        if ((a & 0x7FFF) == 0)
            return 0x7FC0;

        return sign | 0x7F80;
    }

    /* Handle zero */
    if ((a & 0x7FFF) == 0 || (b & 0x7FFF) == 0)
        return sign;

    /* Restore the significands */
    uint32_t ma = frac_a;
    uint32_t mb = frac_b;

    /* Normalize a */
    if (exp_a == 0) {
        exp_a = 1;
        while ((ma & 0x80) == 0) {
            ma <<= 1;
            exp_a--;
        }
    } else {
        ma |= 0x80;
    }

    /* Normalize b */
    if (exp_b == 0) {
        exp_b = 1;
        while ((mb & 0x80) == 0) {
            mb <<= 1;
            exp_b--;
        }
    } else {
        mb |= 0x80;
    }

    /* Multiply significands */
    uint32_t product = mul_shift_add(ma, mb);

    int exp = exp_a + exp_b - 127;

    /* Renormalize and truncate */
    uint32_t mantissa;

    if (product & 0x8000) {
        mantissa = product >> 8;
        exp++;
    } else {
        mantissa = product >> 7;
    }

    /* Overflow */
    if (exp >= 0xFF)
        return sign | 0x7F80;

    /* Underflow / denormal result */
    if (exp <= 0) {
        if (exp < -6)
            return sign;

        uint32_t fraction = mantissa & 0x7F;
        fraction >>= (1 - exp);

        return sign | (uint16_t) fraction;
    }

    /* Pack into BF16 */
    return sign | (exp << 7) | (mantissa & 0x7F);
}

uint16_t bf16_sqrt(uint16_t a)
{
    uint16_t sign = a & 0x8000;
    int exp = (a >> 7) & 0xFF;
    uint32_t frac = a & 0x7F;

    /* NaN and Infinity */
    if (exp == 0xFF) {
        if (frac != 0)
            return a;

        return sign ? 0x7FC0 : a;
    }

    /* +0 and -0 */
    if ((a & 0x7FFF) == 0)
        return 0x0000;

    /* Negative nonzero */
    if (sign)
        return 0x7FC0;

    /* Positive denormal */
    if (exp == 0)
        return 0x0000;

    /* Restore significand */
    int e = exp - 127;
    uint32_t m = 128 + frac;

    /* Make exponent even */
    if ((e & 1) != 0) {
        e--;
        m <<= 1;
    }

    /* Binary search for integer square root */
    int left = 90;
    int right = 256;
    uint32_t ans = 90;

    while (left <= right) {
        uint32_t mid = left + (right - left) / 2;

        uint32_t square = mul_shift_add(mid, mid);

        if ((square >> 7) <= m) {
            ans = mid;
            left = mid + 1;
        } else {
            right = mid - 1;
        }
    }

    /* Result exponent */
    int result_exp = (e >> 1) + 127;

    /* Renormalize */
    if (ans >= 256) {
        ans >>= 1;
        result_exp++;
    }

    /* Overflow */
    if (result_exp >= 0xFF)
        return 0x7F80;

    /* Underflow */
    if (result_exp <= 0)
        return 0x0000;

    /* Pack into BF16 */
    return (uint16_t) ((result_exp << 7) | (ans & 0x7F));
}
