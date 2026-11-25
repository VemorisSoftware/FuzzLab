// Fuzz Lab · referencia en Java. Mismos algoritmos que rendimiento.cfv.
import java.util.Arrays;
import java.util.function.LongSupplier;
public class Bench {
    static volatile long sumidero;
    static long fib(long n) { return n < 2 ? n : fib(n - 1) + fib(n - 2); }
    static void medir(String n, LongSupplier f) {
        long mejor = -1;
        for (int i = 0; i < 3; i++) { long a = System.nanoTime(); sumidero = f.getAsLong(); long t = (System.nanoTime() - a) / 1000000; if (mejor < 0 || t < mejor) mejor = t; }
        System.out.println("BENCH " + n + " " + mejor);
    }
    public static void main(String[] a) {
        medir("fib30", () -> fib(30));
        medir("bucle_suma_10M", () -> { long s = 0; for (long i = 0; i < 10000000; i++) s += i % 7; return s; });
        medir("criba_primos_2M", () -> { int n = 2000000; boolean[] m = new boolean[n + 1]; long c = 0;
            for (long p = 2; p <= n; p++) if (!m[(int) p]) { c++; for (long k = p * p; k <= n; k += p) m[(int) k] = true; } return c; });
        medir("ordenar_200k", () -> { long[] l = new long[200000]; long x = 12345;
            for (int i = 0; i < l.length; i++) { x = (x * 1103515245L + 12345) % 2147483648L; l[i] = x; } Arrays.sort(l); return l[0]; });
    }
}
