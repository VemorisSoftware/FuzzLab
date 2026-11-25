// Fuzz Lab · referencia en Rust (rustc -O). Mismos algoritmos que rendimiento.cfv.
use std::time::Instant;
fn fib(n: i64) -> i64 { if n < 2 { n } else { fib(n - 1) + fib(n - 2) } }
fn medir<F: Fn() -> i64>(n: &str, f: F) {
    let mut mejor = u128::MAX;
    for _ in 0..3 { let a = Instant::now(); std::hint::black_box(f()); mejor = mejor.min(a.elapsed().as_millis()); }
    println!("BENCH {} {}", n, mejor);
}
fn main() {
    medir("fib30", || fib(std::hint::black_box(30)));
    medir("bucle_suma_10M", || { let mut s = 0i64; for i in 0..std::hint::black_box(10_000_000i64) { s += i % 7; } s });
    medir("criba_primos_2M", || { let n = 2_000_000usize; let mut m = vec![false; n + 1]; let mut c = 0i64;
        for p in 2..=n { if !m[p] { c += 1; let mut k = p * p; while k <= n { m[k] = true; k += p; } } } c });
    medir("ordenar_200k", || { let mut x: i64 = 12345; let mut l: Vec<i64> = (0..200000).map(|_| { x = (x * 1103515245 + 12345) % 2147483648; x }).collect();
        l.sort_unstable(); l[0] });
}
