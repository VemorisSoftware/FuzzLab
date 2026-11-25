/* objetivos/cforge/bench_c.c — Fuzz Lab de Vemoris · referencia en C.
 *
 * Los mismos algoritmos que rendimiento.cfv, escritos en C (gcc -O2), para
 * comparar la velocidad de C-Forge contra C. Herramienta de medición del
 * Fuzz Lab: no forma parte de C-Forge.
 *
 * Escribe "BENCH nombre milisegundos".
 */
#include <stdio.h>
#include <stdlib.h>
#include <time.h>

static long long ahora_ms(void) {
    struct timespec t;
    clock_gettime(CLOCK_MONOTONIC, &t);
    return (long long)t.tv_sec * 1000 + t.tv_nsec / 1000000;
}

static volatile long long sumidero;

static long long fib(long long n) { return n < 2 ? n : fib(n - 1) + fib(n - 2); }

static long long b_fib(void) { return fib(30); }

static long long b_bucle(void) {
    long long s = 0;
    for (long long i = 0; i < 10000000; i++) s += i % 7;
    return s;
}

static long long b_criba(void) {
    int n = 2000000;
    char *m = calloc(n + 1, 1);
    long long c = 0;
    for (long long p = 2; p <= n; p++) {
        if (!m[p]) {
            c++;
            for (long long k = p * p; k <= n; k += p) m[k] = 1;
        }
    }
    free(m);
    return c;
}

static int cmp(const void *a, const void *b) {
    long long x = *(const long long *)a, y = *(const long long *)b;
    return (x > y) - (x < y);
}

static long long b_ordenar(void) {
    long long *l = malloc(200000 * sizeof *l);
    long long x = 12345;
    for (int i = 0; i < 200000; i++) { x = (x * 1103515245 + 12345) % 2147483648LL; l[i] = x; }
    qsort(l, 200000, sizeof *l, cmp);
    long long r = l[0];
    free(l);
    return r;
}

static void medir(const char *nombre, long long (*f)(void)) {
    long long mejor = -1;
    for (int i = 0; i < 3; i++) {
        long long a = ahora_ms();
        sumidero = f();
        long long t = ahora_ms() - a;
        if (mejor < 0 || t < mejor) mejor = t;
    }
    printf("BENCH %s %lld\n", nombre, mejor);
}

int main(void) {
    medir("fib30", b_fib);
    medir("bucle_suma_10M", b_bucle);
    medir("criba_primos_2M", b_criba);
    medir("ordenar_200k", b_ordenar);
    return 0;
}
