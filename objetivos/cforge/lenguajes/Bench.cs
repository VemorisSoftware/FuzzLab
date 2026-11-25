// Fuzz Lab · referencia en C# (.NET, Release). Mismos algoritmos que rendimiento.cfv.
using System;
using System.Diagnostics;
class Bench {
    static long sumidero;
    static long Fib(long n) => n < 2 ? n : Fib(n - 1) + Fib(n - 2);
    static void Medir(string n, Func<long> f) {
        long mejor = -1;
        for (int i = 0; i < 3; i++) { var sw = Stopwatch.StartNew(); sumidero = f(); long t = sw.ElapsedMilliseconds; if (mejor < 0 || t < mejor) mejor = t; }
        Console.WriteLine($"BENCH {n} {mejor}");
    }
    static void Main() {
        Medir("fib30", () => Fib(30));
        Medir("bucle_suma_10M", () => { long s = 0; for (long i = 0; i < 10000000; i++) s += i % 7; return s; });
        Medir("criba_primos_2M", () => { int n = 2000000; var m = new bool[n + 1]; long c = 0;
            for (long p = 2; p <= n; p++) if (!m[p]) { c++; for (long k = p * p; k <= n; k += p) m[k] = true; } return c; });
        Medir("ordenar_200k", () => { var l = new long[200000]; long x = 12345;
            for (int i = 0; i < l.Length; i++) { x = (x * 1103515245L + 12345) % 2147483648L; l[i] = x; } Array.Sort(l); return l[0]; });
    }
}
