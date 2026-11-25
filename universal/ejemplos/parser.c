// Ejemplo VULNERABLE A PROPÓSITO para probar Fuzz Lab Universal. No usar en producción.
#include <stdio.h>
#include <string.h>
#include <stdlib.h>
// Analizador vulnerable: solo se cae si la entrada empieza con "VMRS",
// el byte 5 es 'X' y luego trae un nombre largo (desborda el búfer).
int main(int argc, char **argv) {
    FILE *f = fopen(argv[1], "rb"); if (!f) return 1;
    char datos[4096]; size_t n = fread(datos, 1, sizeof datos - 1, f); fclose(f); datos[n] = 0;
    if (n < 6 || memcmp(datos, "VMRS", 4) != 0) { fprintf(stderr, "cabecera invalida\n"); return 2; }
    if (datos[4] != 'X') { fprintf(stderr, "version no soportada\n"); return 3; }
    char nombre[16];
    if (datos[5] == ':') { strcpy(nombre, datos + 6); printf("hola %s\n", nombre); }
    else fprintf(stderr, "falta nombre\n");
    return 0;
}
