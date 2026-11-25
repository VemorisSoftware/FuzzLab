#!/bin/sh
# objetivos/cforge/fuzzlab.sh — Fuzz Lab de Vemoris · objetivo: C-Forge.
#
# Ataca C-Forge sin parar durante MINUTOS y deja un reporte en REPORTE.md
# con cada falla única y su reproductor. No usa IA: es fuerza bruta.
#
#   CFORGE_DIR=/ruta/a/cforge sh objetivos/cforge/fuzzlab.sh [MINUTOS] [CARPETA_SALIDA]
#
# CFORGE_DIR es una copia del repo de C-Forge ya compilada con 'make build'.
#
# Motores:
#   stdlib     analizadores y descompresores con entradas hostiles
#   programas  programas de estrés generados (recursión, enteros, memoria…)
#   mutaciones programas reales con mutaciones (compilador y ejecución)
#   bytes      bytes aleatorios al compilador
#
# Una falla es: cierre por señal (segfault, abort, sin memoria), cuelgue
# (pasa el tiempo límite) o un error que intentar/capturar no atrapó.
set -u

MINUTOS=${1:-30}
SALIDA=${2:-fuzzlab-salida}
LAB=$(cd "$(dirname "$0")" && pwd)
RAIZ=$(cd "${CFORGE_DIR:-cforge}" && pwd)
C="$RAIZ/cforge"
export CFORGE_STDLIB="$RAIZ/stdlib"

mkdir -p "$SALIDA/casos"
SALIDA=$(cd "$SALIDA" && pwd)
T=$(mktemp -d)
trap 'rm -rf "$T"' EXIT
FIN=$(( $(date +%s) + MINUTOS * 60 ))
INICIO=$(date +%s)

[ -x "$C" ] || { echo "Falta $C: corre 'make build' primero."; exit 2; }
"$C" build "$LAB/ataques_stdlib.cfv" -o "$T/ataques" >/dev/null || exit 2
"$C" build "$LAB/generador.cfv" -o "$T/generador" >/dev/null || exit 2

: > "$SALIDA/fallas.tsv"          # firma \t motor \t tipo \t detalle \t archivo
total_stdlib=0; total_prog=0; total_mut=0; total_bytes=0
n_fallas=0

tipo_de() {   # código de salida → tipo de falla ("" si no es falla)
    case "$1" in
        124) echo "cuelgue" ;;
        134) echo "abort (SIGABRT)" ;;
        136) echo "error de coma flotante (SIGFPE)" ;;
        137) echo "sin memoria o matado (SIGKILL)" ;;
        139) echo "segfault (SIGSEGV)" ;;
        *) if [ "$1" -gt 128 ]; then echo "señal $(( $1 - 128 ))"; fi ;;
    esac
}

# registrar FIRMA MOTOR TIPO DETALLE ARCHIVO — guarda solo 3 ejemplos por firma.
registrar() {
    vistas=$(awk -F '\t' -v f="$1" '$1 == f' "$SALIDA/fallas.tsv" | wc -l)
    [ "$vistas" -ge 3 ] && return
    n_fallas=$((n_fallas + 1))
    destino="$SALIDA/casos/falla-$n_fallas$(echo "$5" | sed -n 's/.*\(\.[a-z]*\)$/\1/p')"
    [ -f "$5" ] && cp "$5" "$destino"
    printf '%s\t%s\t%s\t%s\t%s\n' "$1" "$2" "$3" "$4" "casos/$(basename "$destino")" >> "$SALIDA/fallas.tsv"
    echo "  ✗ [$2] $3 — $4"
}

quedan() { [ "$(date +%s)" -lt "$FIN" ]; }

ronda=0
while quedan; do
    ronda=$((ronda + 1))
    semilla=$(( INICIO + ronda * 7919 ))

    # ── stdlib ───────────────────────────────────────────────────────────
    desde=0
    while quedan; do
        codigo=0
        timeout 30 "$T/ataques" "$semilla" 300 "$desde" > "$T/s.out" 2> "$T/s.err" || codigo=$?
        ultimo=$(grep '^caso ' "$T/s.out" | tail -1)
        caso=$(echo "$ultimo" | awk '{print $2}')
        objetivo=$(echo "$ultimo" | awk '{print $3}')
        if grep -q '^FIN' "$T/s.out"; then
            total_stdlib=$((total_stdlib + 300 - desde)); break
        fi
        tipo=$(tipo_de "$codigo")
        [ -z "$tipo" ] && tipo="error no capturable"
        [ -z "$caso" ] && break
        timeout 5 "$T/ataques" "$semilla" 300 0 "$caso" "$T/entrada.bin" > /dev/null 2>&1
        detalle="$objetivo con entrada de $(wc -c < "$T/entrada.bin" 2>/dev/null || echo ?) bytes (semilla $semilla, caso $caso) $(head -c 160 "$T/s.err" | tr '\n\t' '  ')"
        registrar "stdlib|$objetivo|$tipo" stdlib "$tipo" "$detalle" "$T/entrada.bin"
        total_stdlib=$((total_stdlib + caso - desde + 1))
        desde=$((caso + 1))
    done

    # ── programas de estrés ─────────────────────────────────────────────
    k=0
    while [ "$k" -lt 10 ] && quedan; do
        k=$((k + 1)); s=$((semilla + k))
        "$T/generador" "$s" > "$T/prog.cfv"
        codigo=0
        estres=""
        [ $((s % 4)) -eq 0 ] && estres="CFORGE_GC_ESTRES=1"
        (cd "$T" && env $estres timeout 60 "$C" prog.cfv > "$T/p.out" 2> "$T/p.err") || codigo=$?
        total_prog=$((total_prog + 1))
        tipo=$(tipo_de "$codigo")
        if [ -n "$tipo" ]; then
            firma="programas|$tipo|$(grep -v '^//' "$T/prog.cfv" | tail -1 | sed 's/[0-9][0-9]*/N/g' | head -c 80)"
            registrar "$firma" programas "$tipo" "programa de estrés semilla $s ${estres:+(GC en estrés)} $(head -c 120 "$T/p.err" | tr '\n\t' '  ')" "$T/prog.cfv"
        fi
    done

    # ── mutaciones de programas reales ──────────────────────────────────
    ls "$RAIZ"/tests/cfv/*.cfv "$RAIZ"/ejemplos/*.cfv 2>/dev/null | grep -v -e servidor -e microservicio -e web_api > "$T/fuentes"
    total=$(wc -l < "$T/fuentes")
    k=0
    while [ "$k" -lt 40 ] && quedan; do
        k=$((k + 1)); s=$((semilla + k))
        src=$(sed -n "$(( s % total + 1 ))p" "$T/fuentes")
        awk -v semilla="$s" -f "$LAB/mutar.awk" "$src" > "$T/a.cfv"
        awk -v semilla=$((s + 100000)) -f "$LAB/mutar.awk" "$T/a.cfv" > "$T/mut.cfv"
        codigo=0
        timeout 20 "$C" check "$T/mut.cfv" > /dev/null 2> "$T/m.err" || codigo=$?
        total_mut=$((total_mut + 1))
        tipo=$(tipo_de "$codigo")
        if [ -n "$tipo" ]; then
            registrar "compilador|$tipo|$(head -c 60 "$T/m.err" | tr '\n\t' '  ')" mutaciones "$tipo en el compilador" "mutación de $(basename "$src") (semilla $s)" "$T/mut.cfv"
            continue
        fi
        [ "$codigo" -ne 0 ] && continue
        codigo=0
        (cd "$T" && timeout 20 "$C" mut.cfv > /dev/null 2> "$T/m.err") || codigo=$?
        tipo=$(tipo_de "$codigo")
        if [ -n "$tipo" ] && [ "$codigo" -ne 124 ]; then
            registrar "ejecucion|$tipo|$(basename "$src")" mutaciones "$tipo al ejecutar" "mutación de $(basename "$src") (semilla $s) $(head -c 120 "$T/m.err" | tr '\n\t' '  ')" "$T/mut.cfv"
        fi
    done

    # ── bytes aleatorios al compilador ──────────────────────────────────
    k=0
    while [ "$k" -lt 20 ] && quedan; do
        k=$((k + 1))
        head -c $(( (semilla + k) % 2000 + 1 )) /dev/urandom > "$T/bytes.cfv"
        codigo=0
        timeout 20 "$C" check "$T/bytes.cfv" > /dev/null 2>&1 || codigo=$?
        total_bytes=$((total_bytes + 1))
        tipo=$(tipo_de "$codigo")
        [ -n "$tipo" ] && registrar "bytes|$tipo" bytes "$tipo en el compilador" "$(wc -c < "$T/bytes.cfv") bytes aleatorios" "$T/bytes.cfv"
    done
done

# ── Reporte ─────────────────────────────────────────────────────────────
DUR=$(( ($(date +%s) - INICIO) / 60 ))
unicas=$(cut -f1 "$SALIDA/fallas.tsv" | sort -u | wc -l)
{
    echo "# 🔬 Reporte Fuzz Lab · C-Forge"
    echo
    echo "- **Fecha:** $(date -u '+%Y-%m-%d %H:%M UTC')"
    echo "- **Versión:** $("$C" --version | head -1)"
    echo "- **Commit de C-Forge:** $(git -C "$RAIZ" rev-parse --short HEAD 2>/dev/null || echo '?')"
    echo "- **Duración:** $DUR min · $ronda rondas"
    echo "- **Ataques:** $total_stdlib a la stdlib · $total_prog programas de estrés · $total_mut mutaciones · $total_bytes entradas de bytes"
    echo "- **Fallas únicas:** $unicas"
    echo
    if [ "$unicas" -eq 0 ]; then
        echo "✅ Sin cierres, cuelgues ni errores escapados en esta corrida."
    else
        echo "## Fallas"
        echo
        cut -f1 "$SALIDA/fallas.tsv" | sort -u | while IFS= read -r firma; do
            awk -F '\t' -v f="$firma" '$1 == f' "$SALIDA/fallas.tsv" | head -1 | while IFS="$(printf '\t')" read -r _ motor tipo detalle archivo; do
                veces=$(awk -F '\t' -v f="$firma" '$1 == f' "$SALIDA/fallas.tsv" | wc -l)
                echo "### $tipo · $motor"
                echo
                echo "- **Detalle:** $detalle"
                echo "- **Ejemplos guardados:** $veces · reproductor: \`$archivo\`"
                if [ -f "$SALIDA/$archivo" ] && [ "$(wc -c < "$SALIDA/$archivo")" -le 1500 ] && LC_ALL=C grep -qv '[^[:print:][:space:]]' "$SALIDA/$archivo" 2>/dev/null; then
                    echo
                    echo '```cfv'
                    cat "$SALIDA/$archivo"
                    echo
                    echo '```'
                fi
                echo
            done
        done
        echo "## Cómo reproducir"
        echo
        echo "Descarga el artefacto de esta corrida y ejecuta el reproductor:"
        echo "- programas y mutaciones: \`cforge casos/falla-N.cfv\` (o \`cforge check\`)"
        echo "- stdlib: la línea indica semilla y caso; la entrada exacta está en \`casos/falla-N.bin\`"
    fi
} > "$SALIDA/REPORTE.md"

echo
echo "  Reporte: $SALIDA/REPORTE.md ($unicas fallas únicas en $DUR min)"
[ "$unicas" -eq 0 ]
