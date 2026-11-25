// Fuzz Lab · referencia en TypeScript (compilado con tsc, ejecutado en Node.js).
// Mismos algoritmos que rendimiento.cfv.
let sumidero: number = 0;
const fib = (n: number): number => (n < 2 ? n : fib(n - 1) + fib(n - 2));
function medir(n: string, f: () => number): void {
  let mejor = -1;
  for (let i = 0; i < 3; i++) { const a = performance.now(); sumidero = f(); const t = Math.round(performance.now() - a); if (mejor < 0 || t < mejor) mejor = t; }
  console.log(`BENCH ${n} ${mejor}`);
}
medir("fib30", () => fib(30));
medir("bucle_suma_10M", () => { let s = 0; for (let i = 0; i < 10000000; i++) s += i % 7; return s; });
medir("criba_primos_2M", () => { const n = 2000000; const m = new Uint8Array(n + 1); let c = 0;
  for (let p = 2; p <= n; p++) if (!m[p]) { c++; for (let k = p * p; k <= n; k += p) m[k] = 1; } return c; });
medir("ordenar_200k", () => { const l: number[] = new Array(200000); let x = 12345;
  for (let i = 0; i < l.length; i++) { x = (Math.imul(x, 1103515245) + 12345) & 0x7fffffff; l[i] = x; } l.sort((a, b) => a - b); return l[0]; });
