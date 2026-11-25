#include <stdio.h>
#include <string.h>
#include <stdlib.h>
#include <limits.h>
// Ejemplo VULNERABLE A PROPÓSITO: tres errores que ve cada sanitizador.
int main(int argc, char **argv) {
    FILE *f = fopen(argv[1], "rb"); if (!f) return 1;
    char d[256]; size_t n = fread(d, 1, sizeof d - 1, f); fclose(f); d[n] = 0;
    if (n >= 4 && memcmp(d, "SUMA", 4) == 0) {          // UBSan: desborde de entero con signo
        int x = INT_MAX - 5; x += (unsigned char)d[4]; printf("%d\n", x);
    }
    if (n >= 4 && memcmp(d, "LEER", 4) == 0) {          // MSan: memoria sin iniciar
        int *v = malloc(8 * sizeof(int)); v[0] = 1;
        int i = d[4] & 7; if (v[i] > 3) puts("grande"); free(v);
    }
    if (n >= 4 && memcmp(d, "COPY", 4) == 0) {          // ASan: desborde de búfer
        char b[8]; memcpy(b, d, n); puts(b);
    }
    return 0;
}
