#include "fixed.h"

uint32_t op1(uint32_t a, uint32_t b, int *n)
{
    *n = 0;
    while (b) {
        unsigned c = (a & b) << 1;
        a = a ^ b;
        b = c;
        ++*n;
    }
    return a;
}

uint32_t op2(uint32_t a, uint32_t b)
{
    return a - b;
}

uint32_t op3(uint32_t a, uint32_t b)
{
    return (a >> 1) + (b >> 1) + (a & b & 1);
}

int32_t q_mul(int32_t a, int32_t b)
{
    int negative = (a < 0) != (b < 0);

    uint64_t ua = a < 0 ? 0u - (uint32_t) a : (uint32_t) a;
    uint32_t ub = b < 0 ? 0u - (uint32_t) b : (uint32_t) b;
    volatile uint64_t result = 0;

    while (ub) {
        if (ub & 1u)
            result += ua;

        ub >>= 1;
        ua <<= 1;
    }

    int64_t product = (int64_t) result;
    if (negative)
        product = -product;

    product += (int64_t) 1 << 19;
    return (int32_t) (product >> 20);
}
