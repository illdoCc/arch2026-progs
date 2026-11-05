#include "gcd.h"

uint8_t ctz(uint32_t num)
{
    int i = 0;

    for (i = 0; i < 32; i++) {
        if (num & 1) {
            return i;
        }
        num >>= 1;
    }

    return i;
}

uint32_t gcd_u32(uint32_t a, uint32_t b)
{
    if (a == 0)
        return b;
    if (b == 0)
        return a;

    uint8_t k = ctz(a) < ctz(b) ? ctz(a) : ctz(b);
    a >>= ctz(a);
    b >>= ctz(b);

    while (a != b) {
        /* swap a, b */
        if (a < b) {
            uint32_t temp = a;
            a = b;
            b = temp;
        }

        a = a - b;
        a >>= ctz(a);
    }

    return a << k;
}
