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
#   cruzadas   resultados incorrectos (propiedades que siempre deben cumplirse)
#   rendimiento velocidad vs. la corrida anterior y vs. C, C++, Rust, Java,
#               C#, JavaScript y TypeScript               (una vez por corrida)
#   memoria    fugas de memoria                            (una vez por corrida)
#
# BASE_RENDIMIENTO (opcional): archivo con los tiempos de la corrida anterior.
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
"$C" build "$LAB/cruzadas.cfv" -o "$T/cruzadas" >/dev/null || exit 2
"$C" build "$LAB/fugas.cfv" -o "$T/fugas" >/dev/null || exit 2
"$C" build "$LAB/rendimiento.cfv" -o "$T/bench" --release >/dev/null || exit 2

: > "$SALIDA/fallas.tsv"          # firma \t motor \t tipo \t detalle \t archivo
total_stdlib=0; total_prog=0; total_mut=0; total_bytes=0; total_cruz=0
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

# pico_kb SEGUNDOS CMD… → pico de memoria (KB) del proceso, o "cuelgue".
pico_kb() {
    limite=$1; shift
    "$@" > /dev/null 2> "$T/pico.err" &
    pid=$!
    max=0; t=0
    while kill -0 "$pid" 2>/dev/null; do
        v=$(awk '/^VmHWM:/ {print $2}' "/proc/$pid/status" 2>/dev/null)
        [ -n "$v" ] && [ "$v" -gt "$max" ] && max=$v
        sleep 0.1; t=$((t + 1))
        if [ "$t" -gt $((limite * 10)) ]; then kill -9 "$pid" 2>/dev/null; wait "$pid" 2>/dev/null; echo cuelgue; return; fi
    done
    codigo=0; wait "$pid" 2>/dev/null || codigo=$?
    tipo=$(tipo_de "$codigo")
    if [ -n "$tipo" ]; then echo "caida:$tipo"; else echo "$max"; fi
}

# ── Rendimiento (una vez por corrida) ───────────────────────────────────
: > "$SALIDA/rendimiento.tsv"
codigo=0
timeout 1500 "$T/bench" > "$T/bench.out" 2>&1 || codigo=$?
awk '$1 == "BENCH" {print $2 "\t" $3}' "$T/bench.out" > "$SALIDA/rendimiento.tsv"
if [ "$codigo" -ne 0 ]; then
    tipo=$(tipo_de "$codigo"); [ -z "$tipo" ] && tipo="error"
    registrar "rendimiento|$tipo" rendimiento "$tipo en las pruebas de velocidad" "rendimiento.cfv terminó con código $codigo" "$LAB/rendimiento.cfv"
fi
sh "$LAB/lenguajes/medir.sh" "$SALIDA/lenguajes.tsv" > /dev/null 2>&1 || true
regresiones=0
if [ -n "${BASE_RENDIMIENTO:-}" ] && [ -s "$BASE_RENDIMIENTO" ]; then
    while IFS="$(printf '\t')" read -r nombre ms; do
        base=$(awk -F '\t' -v n="$nombre" '$1 == n {print $2}' "$BASE_RENDIMIENTO")
        [ -z "$base" ] && continue
        if [ "$ms" -gt $(( base * 13 / 10 )) ] && [ $(( ms - base )) -ge 30 ]; then
            regresiones=$((regresiones + 1))
            registrar "lento|$nombre" rendimiento "más lento que antes" "$nombre: $base ms → $ms ms (+$(( (ms - base) * 100 / (base + 1) ))%)" ""
        fi
    done < "$SALIDA/rendimiento.tsv"
fi

# ── Memoria: fugas (una vez por corrida) ───────────────────────────────
: > "$SALIDA/memoria.tsv"
for escenario in listas textos mapas closures excepciones json objetos enteros; do
    quedan || break
    a=$(pico_kb 300 "$T/fugas" "$escenario" 1000)
    b=$(pico_kb 900 "$T/fugas" "$escenario" 4000)
    printf '%s\t%s\t%s\n' "$escenario" "$a" "$b" >> "$SALIDA/memoria.tsv"
    case "$a$b" in
        *cuelgue*|*caida*) registrar "memoria|$escenario|$a$b" memoria "falla en prueba de memoria" "escenario $escenario: 1000 rep. = $a, 4000 rep. = $b" "" ; continue ;;
    esac
    if [ "$b" -gt $((a * 2)) ] && [ $((b - a)) -gt 51200 ]; then
        registrar "fuga|$escenario" memoria "posible fuga de memoria" "escenario $escenario: pico $((a / 1024)) MB con 1000 repeticiones → $((b / 1024)) MB con 4000" ""
    fi
done

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

    # ── pruebas cruzadas (resultados incorrectos) ───────────────────────
    if quedan; then
        codigo=0
        timeout 300 "$T/cruzadas" "$semilla" 300 > "$T/c.out" 2> "$T/c.err" || codigo=$?
        total_cruz=$((total_cruz + 300))
        grep '^FALLA ' "$T/c.out" > "$T/c.fallas" || true
        while IFS= read -r l; do
            prop=$(echo "$l" | sed 's/^FALLA \([^ |]*\).*/\1/')
            printf '%s\n' "$l" > "$T/cruz.txt"
            registrar "cruzadas|$prop" cruzadas "resultado incorrecto" "$(echo "$l" | cut -c7-400) (semilla $semilla)" "$T/cruz.txt"
        done < "$T/c.fallas"
        tipo=$(tipo_de "$codigo")
        [ -n "$tipo" ] && registrar "cruzadas|$tipo" cruzadas "$tipo en pruebas cruzadas" "semilla $semilla $(head -c 120 "$T/c.err" | tr '\n\t' '  ')" ""
    fi

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
    echo "- **Ataques:** $total_stdlib a la stdlib · $total_cruz pruebas cruzadas · $total_prog programas de estrés · $total_mut mutaciones · $total_bytes entradas de bytes"
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
    echo
    echo "## ⚡ Rendimiento: C-Forge contra los demás lenguajes"
    echo
    echo "Milisegundos (menos es mejor). Mismo algoritmo en cada lenguaje. **C-Forge / mejor** = cuántas veces más lento es C-Forge que el lenguaje más rápido."
    echo
    langs=$(cut -f1 "$SALIDA/lenguajes.tsv" 2>/dev/null | awk '!v[$0]++' | tr '\n' '|')
    printf '| Prueba | **C-Forge** |'; echo "$langs" | tr '|' '\n' | while IFS= read -r l; do [ -n "$l" ] && printf ' %s |' "$l"; done; echo ' Más rápido | C-Forge / mejor | Puesto de C-Forge | Corrida anterior |'
    printf '|---|---|'; echo "$langs" | tr '|' '\n' | while IFS= read -r l; do [ -n "$l" ] && printf -- '---|'; done; echo '---|---|---|---|'
    while IFS="$(printf '\t')" read -r nombre ms; do
        fila="| $nombre | **$ms** |"
        mejor_l="C-Forge"; mejor_ms=$ms; puesto=1; total=1
        for l in $(echo "$langs" | tr ' |' '_ '); do
            ln=$(echo "$l" | tr '_' ' ')
            v=$(awk -F '\t' -v a="$ln" -v n="$nombre" '$1 == a && $2 == n {print $3}' "$SALIDA/lenguajes.tsv")
            fila="$fila ${v:-—} |"
            if [ -n "$v" ]; then
                total=$((total + 1))
                [ "$v" -lt "$ms" ] && puesto=$((puesto + 1))
                if [ "$v" -lt "$mejor_ms" ]; then mejor_ms=$v; mejor_l=$ln; fi
            fi
        done
        b=""; [ -n "${BASE_RENDIMIENTO:-}" ] && [ -s "$BASE_RENDIMIENTO" ] && b=$(awk -F '\t' -v n="$nombre" '$1 == n {print $2}' "$BASE_RENDIMIENTO")
        if [ "$total" -gt 1 ]; then
            r=$(awk -v a="$ms" -v b="$mejor_ms" 'BEGIN { if (b < 1) b = 1; if (a < 1) a = 1; printf "%.1f×", a / b }')
            echo "$fila $mejor_l | $r | $puesto de $total | ${b:-—} |"
        else
            echo "$fila — | — | — | ${b:-—} |"
        fi
    done < "$SALIDA/rendimiento.tsv"
    echo
    echo "Las pruebas sin equivalente en otros lenguajes solo se comparan con la corrida anterior. Una **regresión** es una prueba más de 30 % (y 30 ms) más lenta que la corrida anterior. Los tiempos de los servidores de GitHub varían un poco entre corridas."
    echo
    echo "## 💧 Memoria"
    echo
    echo "| Escenario | Pico con 1000 rep. (KB) | Pico con 4000 rep. (KB) |"
    echo "|---|---|---|"
    while IFS="$(printf '\t')" read -r e a b; do echo "| $e | $a | $b |"; done < "$SALIDA/memoria.tsv"
    echo
    echo "Si la memoria con 4000 repeticiones es más del doble (y más de 50 MB) que con 1000, se marca como posible fuga."
} > "$SALIDA/REPORTE.md"

echo
echo "  Reporte: $SALIDA/REPORTE.md ($unicas fallas únicas en $DUR min)"
[ "$unicas" -eq 0 ]
