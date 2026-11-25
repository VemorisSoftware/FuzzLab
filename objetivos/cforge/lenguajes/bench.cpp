// Fuzz Lab · referencia en C++ (g++ -O2). Mismos algoritmos que rendimiento.cfv.
#include <algorithm>
#include <chrono>
#include <cstdio>
#include <vector>
using namespace std;
static volatile long long sumidero;
static long long ms() { return chrono::duration_cast<chrono::milliseconds>(chrono::steady_clock::now().time_since_epoch()).count(); }
static long long fib(long long n) { return n < 2 ? n : fib(n - 1) + fib(n - 2); }
template <class F> static void medir(const char *n, F f) {
    long long mejor = -1;
    for (int i = 0; i < 3; i++) { long long a = ms(); sumidero = f(); long long t = ms() - a; if (mejor < 0 || t < mejor) mejor = t; }
    printf("BENCH %s %lld\n", n, mejor);
}
int main() {
    medir("fib30", [] { return fib(30); });
    medir("bucle_suma_10M", [] { long long s = 0; for (long long i = 0; i < 10000000; i++) s += i % 7; return s; });
    medir("criba_primos_2M", [] { int n = 2000000; vector<char> m(n + 1, 0); long long c = 0;
        for (long long p = 2; p <= n; p++) if (!m[p]) { c++; for (long long k = p * p; k <= n; k += p) m[k] = 1; } return c; });
    medir("ordenar_200k", [] { vector<long long> l(200000); long long x = 12345;
        for (auto &v : l) { x = (x * 1103515245 + 12345) % 2147483648LL; v = x; } sort(l.begin(), l.end()); return l[0]; });
}
