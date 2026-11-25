#!/bin/sh
# objetivos/cforge/lenguajes/medir.sh SALIDA.tsv
# Compila y corre el mismo benchmark en C, C++, Rust, Java, C#, JavaScript y
# TypeScript (los que estén instalados) y escribe "lenguaje\tprueba\tms".
# Herramienta de medición del Fuzz Lab: no forma parte de C-Forge.
set -u
D=$(cd "$(dirname "$0")" && pwd)
OUT=${1:-lenguajes.tsv}
T=$(mktemp -d)
trap 'rm -rf "$T"' EXIT
: > "$OUT"

anotar() {   # anotar LENGUAJE < salida del benchmark
    awk -v l="$1" '$1 == "BENCH" {print l "\t" $2 "\t" $3}' >> "$OUT"
}

if command -v gcc > /dev/null 2>&1 && gcc -O2 "$D/bench.c" -o "$T/c" 2>/dev/null; then
    timeout 300 "$T/c" | anotar C
fi
if command -v g++ > /dev/null 2>&1 && g++ -O2 "$D/bench.cpp" -o "$T/cpp" 2>/dev/null; then
    timeout 300 "$T/cpp" | anotar "C++"
fi
if command -v rustc > /dev/null 2>&1 && rustc -O "$D/bench.rs" -o "$T/rs" 2>/dev/null; then
    timeout 300 "$T/rs" | anotar Rust
fi
if command -v javac > /dev/null 2>&1 && javac -d "$T" "$D/Bench.java" 2>/dev/null; then
    timeout 300 java -cp "$T" Bench | anotar Java
fi
if command -v dotnet > /dev/null 2>&1; then
    mkdir -p "$T/cs"
    (cd "$T/cs" && dotnet new console --force -o . > /dev/null 2>&1 && cp "$D/Bench.cs" Program.cs \
        && dotnet build -c Release -o bin > /dev/null 2>&1) && timeout 300 dotnet "$T/cs/bin/cs.dll" | anotar "C#"
fi
if command -v node > /dev/null 2>&1; then
    timeout 300 node "$D/bench.js" | anotar JavaScript
    if command -v tsc > /dev/null 2>&1 || npm install -g typescript > /dev/null 2>&1; then
        tsc --target es2022 --outDir "$T/ts" "$D/bench.ts" > /dev/null 2>&1 && timeout 300 node "$T/ts/bench.js" | anotar TypeScript
    fi
fi
