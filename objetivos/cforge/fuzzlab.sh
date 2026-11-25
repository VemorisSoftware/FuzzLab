#!/bin/sh
# objetivos/cforge/fuzzlab.sh — Fuzz Lab 2.0 de Vemoris · objetivo: C-Forge.
#
# Ataca C-Forge sin parar durante MINUTOS, con varios trabajadores en
# paralelo, y deja un reporte en REPORTE.md con cada falla única, ya
# reducida al programa más chico que la provoca. No usa IA: es fuerza bruta.
#
#   CFORGE_DIR=/ruta/a/cforge sh objetivos/cforge/fuzzlab.sh [MINUTOS] [CARPETA_SALIDA]
#
# CFORGE_DIR es una copia del repo de C-Forge ya compilada con 'make build'.
#
# Motores:
#   stdlib       analizadores y descompresores con entradas hostiles
#   programas    programas de estrés generados (recursión, enteros, memoria…)
#   diferencial  el mismo programa en modo normal y --release debe dar lo mismo
#   mutaciones   programas reales con mutaciones (compilador y ejecución)
#   formato      cforge fmt no debe romper ni cambiar lo que hace un programa
#   bytes        bytes aleatorios al compilador
#   cruzadas     resultados incorrectos (propiedades que siempre deben cumplirse)
#   rendimiento  velocidad vs. la corrida anterior y vs. otros lenguajes (1 vez)
#   memoria      fugas de memoria                                      (1 vez)
#   regresiones  vuelve a probar las fallas de corridas anteriores     (1 vez)
#
# Variables opcionales:
#   BASE_RENDIMIENTO  tiempos de la corrida anterior
#   PREVIOS           carpeta con los reportes anteriores (para regresiones)
#   PARALELO          trabajadores en paralelo (por defecto: núcleos, máx. 4)
#
# Una falla es: cierre por señal (segfault, abort, sin memoria), un programa
# bloqueado o demasiado lento, un error que intentar/capturar no atrapó, un
# resultado incorrecto o distinto entre modos, una regresión de velocidad o
# una fuga de memoria. Los errores normales de C-Forge no cuentan.
set -u

MINUTOS=${1:-30}
SALIDA=${2:-fuzzlab-salida}
LAB=$(cd "$(dirname "$0")" && pwd)
RAIZ=$(cd "${CFORGE_DIR:-cforge}" && pwd)
C="$RAIZ/cforge"
export CFORGE_STDLIB="$RAIZ/stdlib"
NUCLEOS=$(nproc 2>/dev/null || echo 2)
PARALELO=${PARALELO:-$NUCLEOS}
[ "$PARALELO" -gt 4 ] && PARALELO=4
[ "$PARALELO" -lt 1 ] && PARALELO=1
MEMORIA_KB=${MEMORIA_KB:-3000000}      # tope de memoria virtual por programa

mkdir -p "$SALIDA/casos"
SALIDA=$(cd "$SALIDA" && pwd)
T=$(mktemp -d)
trap 'rm -rf "$T"; pkill -9 -f "cforge-run-" 2>/dev/null' EXIT
FIN=$(( $(date +%s) + MINUTOS * 60 ))
INICIO=$(date +%s)

[ -x "$C" ] || { echo "Falta $C: corre 'make build' primero."; exit 2; }
for h in ataques_stdlib:ataques generador:generador cruzadas:cruzadas fugas:fugas; do
    "$C" build "$LAB/${h%%:*}.cfv" -o "$T/${h##*:}" >/dev/null || exit 2
done
"$C" build "$LAB/rendimiento.cfv" -o "$T/bench" --release >/dev/null || exit 2

quedan() { [ "$(date +%s)" -lt "$FIN" ]; }

# ── Ejecución vigilada ──────────────────────────────────────────────────
# arbol PID → el proceso y todos sus descendientes (cforge lanza el programa
# compilado como hijo: hay que cerrarlos a todos o quedan corriendo).
arbol() {
    for h in $(pgrep -P "$1" 2>/dev/null); do arbol "$h"; done
    echo "$1"
}
tics() { for p in "$@"; do awk '{print $14 + $15}' "/proc/$p/stat" 2>/dev/null; done | awk '{s += $1} END {print s + 0}'; }

# ejecutar LIMITE CARPETA SALIDA ERRORES CMD… → CODIGO y CLAVE
#   CLAVE: "" (no es falla), bloqueo, lento, abort, fpe, memoria, segfault, senalN
ejecutar() {
    _lim=$1; _dir=$2; _out=$3; _err=$4; shift 4
    _marca="$_out.cuelgue"
    rm -f "$_marca"
    (cd "$_dir" && ulimit -v "$MEMORIA_KB" 2>/dev/null; exec "$@" > "$_out" 2> "$_err") &
    _pid=$!
    (
        sleep "$_lim"
        if kill -0 "$_pid" 2>/dev/null; then
            _pids=$(arbol "$_pid")
            echo $(( $(tics $_pids) / _lim )) > "$_marca"     # % de CPU usado
            kill -9 $_pids 2>/dev/null
        fi
    ) &
    _vig=$!
    CODIGO=0
    wait "$_pid" || CODIGO=$?
    kill "$_vig" 2>/dev/null; pkill -P "$_vig" sleep 2>/dev/null
    wait "$_vig" 2>/dev/null
    CLAVE=""
    if [ -f "$_marca" ]; then
        if [ "$(cat "$_marca")" -lt 25 ]; then CLAVE=bloqueo; else CLAVE=lento; fi
        return
    fi
    case "$CODIGO" in
        134) CLAVE=abort ;;
        136) CLAVE=fpe ;;
        137) CLAVE=memoria ;;
        139) CLAVE=segfault ;;
        *) [ "$CODIGO" -gt 128 ] && CLAVE="senal$(( CODIGO - 128 ))" ;;
    esac
}

nombre_clave() {
    case "$1" in
        bloqueo) echo "cuelgue: bloqueado sin usar CPU" ;;
        lento) echo "demasiado lento (no termina a tiempo)" ;;
        abort) echo "abort (SIGABRT)" ;;
        fpe) echo "error de coma flotante (SIGFPE)" ;;
        memoria) echo "sin memoria o matado (SIGKILL)" ;;
        segfault) echo "segfault (SIGSEGV)" ;;
        senal*) echo "señal ${1#senal}" ;;
        *) echo "$1" ;;
    esac
}

# ── Minimizador ─────────────────────────────────────────────────────────
# reproduce ARCHIVO MODO LIMITE → la CLAVE con que falla ("" si no falla).
#   MODO: run (compilar y ejecutar) o check (solo compilar)
reproduce() {
    _d=$(dirname "$1")
    if [ "$2" = check ]; then ejecutar "$3" "$_d" "$_d/r.out" "$_d/r.err" "$C" check "$1"
    else ejecutar "$3" "$_d" "$_d/r.out" "$_d/r.err" "$C" "$1"; fi
    echo "$CLAVE"
}

# minimizar ARCHIVO MODO CLAVE LIMITE → deja en ARCHIVO.min el programa más
# chico (quitando bloques de líneas y luego líneas sueltas) que sigue
# fallando con la misma CLAVE. Máximo 4 minutos por falla.
minimizar() {
    _f=$1; _modo=$2; _clave=$3; _lim=$4
    _tope=$(( $(date +%s) + 240 ))
    _w="$(dirname "$_f")/min"; mkdir -p "$_w"
    cp "$_f" "$_w/actual.cfv"
    _n=$(wc -l < "$_w/actual.cfv")
    _paso=$(( _n / 2 ))
    while [ "$_paso" -ge 1 ] && [ "$(date +%s)" -lt "$_tope" ]; do
        _i=1; _quito=0
        while [ "$_i" -le "$_n" ] && [ "$(date +%s)" -lt "$_tope" ]; do
            _j=$(( _i + _paso - 1 ))
            sed "${_i},${_j}d" "$_w/actual.cfv" > "$_w/cand.cfv"
            if [ -s "$_w/cand.cfv" ] && [ "$(reproduce "$_w/cand.cfv" "$_modo" "$_lim")" = "$_clave" ]; then
                mv "$_w/cand.cfv" "$_w/actual.cfv"
                _n=$(wc -l < "$_w/actual.cfv"); _quito=1
            else
                _i=$(( _i + _paso ))
            fi
        done
        [ "$_quito" -eq 0 ] && _paso=$(( _paso / 2 ))
    done
    cp "$_w/actual.cfv" "$_f.min"
}

# huella de un programa: sin comentarios, números → N, espacios colapsados.
huella() { grep -v '^ *//' "$1" | sed 's/[0-9][0-9]*/N/g' | tr -s ' \t' ' ' | md5sum | cut -c1-12; }

# ── Rendimiento (una vez por corrida, antes de los trabajadores) ────────
: > "$SALIDA/fallas.tsv"
falla_global() {    # FIRMA MOTOR TIPO DETALLE ARCHIVO (fuera de los trabajadores)
    destino=""
    if [ -n "$5" ] && [ -f "$5" ]; then
        destino="casos/global-$(wc -l < "$SALIDA/fallas.tsv")-$(basename "$5")"
        cp "$5" "$SALIDA/$destino"
    fi
    printf '%s\t%s\t%s\t%s\t%s\n' "$1" "$2" "$3" "$4" "$destino" >> "$SALIDA/fallas.tsv"
}

: > "$SALIDA/rendimiento.tsv"
ejecutar 1500 "$T" "$T/bench.out" "$T/bench.err" "$T/bench"
awk '$1 == "BENCH" {print $2 "\t" $3}' "$T/bench.out" > "$SALIDA/rendimiento.tsv"
if [ "$CODIGO" -ne 0 ]; then
    falla_global "rendimiento|${CLAVE:-error}" rendimiento "$(nombre_clave "${CLAVE:-error}") en las pruebas de velocidad" "rendimiento.cfv terminó con código $CODIGO" "$LAB/rendimiento.cfv"
fi
sh "$LAB/lenguajes/medir.sh" "$SALIDA/lenguajes.tsv" > /dev/null 2>&1 || true
if [ -n "${BASE_RENDIMIENTO:-}" ] && [ -s "$BASE_RENDIMIENTO" ]; then
    while IFS="$(printf '\t')" read -r nombre ms; do
        base=$(awk -F '\t' -v n="$nombre" '$1 == n {print $2}' "$BASE_RENDIMIENTO")
        [ -z "$base" ] && continue
        if [ "$ms" -gt $(( base * 13 / 10 )) ] && [ $(( ms - base )) -ge 30 ]; then
            falla_global "lento|$nombre" rendimiento "más lento que antes" "$nombre: $base ms → $ms ms (+$(( (ms - base) * 100 / (base + 1) ))%)" ""
        fi
    done < "$SALIDA/rendimiento.tsv"
fi

# ── Memoria: fugas (una vez por corrida) ───────────────────────────────
pico_kb() {     # pico_kb SEGUNDOS ESCENARIO REPETICIONES
    "$T/fugas" "$2" "$3" > /dev/null 2>&1 &
    _p=$!; _max=0; _t=0
    while kill -0 "$_p" 2>/dev/null; do
        _v=$(awk '/^VmHWM:/ {print $2}' "/proc/$_p/status" 2>/dev/null)
        [ -n "$_v" ] && [ "$_v" -gt "$_max" ] && _max=$_v
        sleep 0.1; _t=$((_t + 1))
        if [ "$_t" -gt $(( $1 * 10 )) ]; then kill -9 "$_p" 2>/dev/null; wait "$_p" 2>/dev/null; echo cuelgue; return; fi
    done
    _c=0; wait "$_p" 2>/dev/null || _c=$?
    if [ "$_c" -gt 128 ]; then echo "caida:$_c"; else echo "$_max"; fi
}
: > "$SALIDA/memoria.tsv"
for escenario in listas textos mapas closures excepciones json objetos enteros; do
    quedan || break
    a=$(pico_kb 300 "$escenario" 1000)
    b=$(pico_kb 900 "$escenario" 4000)
    printf '%s\t%s\t%s\n' "$escenario" "$a" "$b" >> "$SALIDA/memoria.tsv"
    case "$a$b" in
        *cuelgue*|*caida*) falla_global "memoria|$escenario|$a$b" memoria "falla en prueba de memoria" "escenario $escenario: 1000 rep. = $a, 4000 rep. = $b" ""; continue ;;
    esac
    if [ "$b" -gt $((a * 2)) ] && [ $((b - a)) -gt 51200 ]; then
        falla_global "fuga|$escenario" memoria "posible fuga de memoria" "escenario $escenario: pico $((a / 1024)) MB con 1000 repeticiones → $((b / 1024)) MB con 4000" ""
    fi
done

# ── Regresiones: ¿siguen fallando las fallas de corridas anteriores? ────
: > "$SALIDA/regresiones.tsv"      # estado \t firma \t motor \t tipo \t corrida
# Corre en paralelo con los trabajadores, máximo 45 minutos y 30 s por falla.
regresiones() {
    [ -n "${PREVIOS:-}" ] && [ -d "$PREVIOS" ] || return 0
    tope_reg=$(( $(date +%s) + 2700 ))
    mkdir -p "$T/reg"
    # La versión más reciente de cada firma (últimas 20 corridas).
    for d in $(ls -d "$PREVIOS"/*/ 2>/dev/null | sort | tail -20); do
        [ -s "$d/fallas.tsv" ] || continue
        awk -F '\t' -v c="$(basename "$d")" -v d="$d" 'NF >= 5 && $5 != "" {print $1 "\t" $2 "\t" $3 "\t" d $5 "\t" c}' "$d/fallas.tsv"
    done | awk -F '\t' '{u[$1] = $0} END {for (f in u) print u[f]}' | sort > "$T/reg/lista.tsv"
    while IFS="$(printf '\t')" read -r firma motor tipo archivo corrida; do
        quedan || break
        [ "$(date +%s)" -lt "$tope_reg" ] || break
        [ -f "$archivo" ] || continue
        clave=""
        case "$motor" in
            stdlib)
                objetivo=$(echo "$firma" | cut -d'|' -f2)
                ejecutar 30 "$T/reg" "$T/reg/o" "$T/reg/e" "$T/ataques" --archivo "$objetivo" "$archivo"
                clave=$CLAVE
                [ -z "$clave" ] && ! grep -q '^FIN' "$T/reg/o" && clave=error ;;
            programas|diferencial)
                cp "$archivo" "$T/reg/p.cfv"; clave=$(reproduce "$T/reg/p.cfv" run 30) ;;
            mutaciones|bytes|formato)
                cp "$archivo" "$T/reg/p.cfv"
                case "$tipo" in *compilador*|*formato*) clave=$(reproduce "$T/reg/p.cfv" check 30) ;; *) clave=$(reproduce "$T/reg/p.cfv" run 30) ;; esac ;;
            *) continue ;;
        esac
        if [ -n "$clave" ]; then estado=sigue; else estado=arreglada; fi
        printf '%s\t%s\t%s\t%s\t%s\n' "$estado" "$firma" "$motor" "$tipo" "$corrida" >> "$SALIDA/regresiones.tsv"
    done < "$T/reg/lista.tsv"
}

# ── Trabajador: ataca en bucle hasta que se acabe el tiempo ─────────────
trabajador() {
    id=$1
    W="$T/w$id"; S="$SALIDA/w$id"
    mkdir -p "$W" "$S/casos"
    : > "$S/fallas.tsv"; : > "$S/pre.tsv"
    total_stdlib=0; total_prog=0; total_dif=0; total_mut=0; total_fmt=0; total_bytes=0; total_cruz=0
    n=0

    # registrar FIRMA MOTOR TIPO DETALLE ARCHIVO — hasta 3 ejemplos por firma.
    registrar() {
        vistas=$(awk -F '\t' -v f="$1" '$1 == f' "$S/fallas.tsv" | wc -l)
        [ "$vistas" -ge 3 ] && return
        n=$((n + 1))
        ext=$(echo "$5" | sed -n 's/.*\(\.[a-z]*\)$/\1/p')
        destino="casos/w$id-falla-$n$ext"
        [ -f "$5" ] && cp "$5" "$SALIDA/$destino"
        printf '%s\t%s\t%s\t%s\t%s\n' "$1" "$2" "$3" "$4" "$destino" >> "$S/fallas.tsv"
    }

    # falla_programa MOTOR ARCHIVO MODO CLAVE LIMITE DETALLE PREFIRMA
    # Reduce el programa (solo la primera vez que aparece la prefirma) y
    # agrupa por la huella del programa reducido.
    falla_programa() {
        _motor=$1; _arch=$2; _modo=$3; _clave=$4; _lim=$5; _det=$6; _pre=$7
        _min=$(awk -F '\t' -v p="$_pre" '$1 == p {print $2; exit}' "$S/pre.tsv")
        if [ -z "$_min" ]; then
            _limmin=$_lim; [ "$_lim" -gt 20 ] && _limmin=20
            minimizar "$_arch" "$_modo" "$_clave" "$_limmin"
            _antes=$(wc -l < "$_arch"); _despues=$(wc -l < "$_arch.min")
            [ "$_despues" -lt "$_antes" ] && { cp "$_arch.min" "$_arch"; _det="$_det · reducido de $_antes a $_despues líneas"; }
            _min="$_motor|$_clave|$(huella "$_arch")"
            printf '%s\t%s\n' "$_pre" "$_min" >> "$S/pre.tsv"
        fi
        registrar "$_min" "$_motor" "$(nombre_clave "$_clave")" "$_det" "$_arch"
    }

    ls "$RAIZ"/tests/cfv/*.cfv "$RAIZ"/ejemplos/*.cfv 2>/dev/null | grep -v -e servidor -e microservicio -e web_api > "$W/fuentes"
    nfuentes=$(wc -l < "$W/fuentes")

    ronda=0
    while quedan; do
        ronda=$((ronda + 1))
        semilla=$(( INICIO + ronda * 7919 + id * 1000003 ))

        # ── stdlib ───────────────────────────────────────────────────────
        desde=0
        while quedan; do
            ejecutar 30 "$W" "$W/s.out" "$W/s.err" "$T/ataques" "$semilla" 300 "$desde"
            ultimo=$(grep '^caso ' "$W/s.out" | tail -1)
            caso=$(echo "$ultimo" | awk '{print $2}')
            objetivo=$(echo "$ultimo" | awk '{print $3}')
            if grep -q '^FIN' "$W/s.out"; then total_stdlib=$((total_stdlib + 300 - desde)); break; fi
            [ -z "$caso" ] && break
            clave=${CLAVE:-escape}
            "$T/ataques" "$semilla" 300 0 "$caso" "$W/entrada.bin" > /dev/null 2>&1 &
            _p=$!; ( sleep 5; kill -9 $(arbol $_p) 2>/dev/null ) & _k=$!; wait "$_p" 2>/dev/null; kill "$_k" 2>/dev/null
            tipo=$(nombre_clave "$clave"); [ "$clave" = escape ] && tipo="error no capturable"
            registrar "stdlib|$objetivo|$tipo" stdlib "$tipo" "$objetivo con entrada de $(wc -c < "$W/entrada.bin" 2>/dev/null || echo ?) bytes (semilla $semilla, caso $caso) $(head -c 160 "$W/s.err" | tr '\n\t' '  ')" "$W/entrada.bin"
            total_stdlib=$((total_stdlib + caso - desde + 1))
            desde=$((caso + 1))
        done

        # ── pruebas cruzadas ────────────────────────────────────────────
        if quedan; then
            ejecutar 300 "$W" "$W/c.out" "$W/c.err" "$T/cruzadas" "$semilla" 300
            total_cruz=$((total_cruz + 300))
            grep '^FALLA ' "$W/c.out" > "$W/c.fallas" || true
            while IFS= read -r l; do
                prop=$(echo "$l" | sed 's/^FALLA \([^ |]*\).*/\1/')
                printf '%s\n' "$l" > "$W/cruz.txt"
                registrar "cruzadas|$prop" cruzadas "resultado incorrecto" "$(echo "$l" | cut -c7-400) (semilla $semilla)" "$W/cruz.txt"
            done < "$W/c.fallas"
            [ -n "$CLAVE" ] && registrar "cruzadas|$CLAVE" cruzadas "$(nombre_clave "$CLAVE") en pruebas cruzadas" "semilla $semilla $(head -c 120 "$W/c.err" | tr '\n\t' '  ')" ""
        fi

        # ── programas de estrés + diferencial normal/--release ──────────
        k=0
        while [ "$k" -lt 10 ] && quedan; do
            k=$((k + 1)); s=$((semilla + k))
            mkdir -p "$W/p"
            "$T/generador" "$s" > "$W/p/prog.cfv"
            estres=""
            [ $((s % 4)) -eq 0 ] && estres="CFORGE_GC_ESTRES=1"
            t0=$(date +%s)
            ejecutar 60 "$W/p" "$W/p/out" "$W/p/err" env $estres "$C" prog.cfv
            t1=$(date +%s)
            total_prog=$((total_prog + 1))
            if [ -n "$CLAVE" ]; then
                cp "$W/p/prog.cfv" "$W/p/falla.cfv"
                falla_programa programas "$W/p/falla.cfv" run "$CLAVE" 60 "programa de estrés semilla $s ${estres:+(GC en estrés)} $(head -c 120 "$W/p/err" | tr '\n\t' '  ')" "programas|$CLAVE|$(grep -v '^//' "$W/p/prog.cfv" | tail -1 | sed 's/[0-9][0-9]*/N/g' | head -c 80)"
                continue
            fi
            # Diferencial: solo programas rápidos y sin GC en estrés.
            if [ -z "$estres" ] && [ $((t1 - t0)) -le 5 ] && [ $((s % 2)) -eq 0 ]; then
                cod_normal=$CODIGO
                if (cd "$W/p" && timeout 120 "$C" build prog.cfv --release -o rel > /dev/null 2>&1); then
                    ejecutar 60 "$W/p" "$W/p/out.rel" "$W/p/err.rel" ./rel
                    total_dif=$((total_dif + 1))
                    if [ -n "$CLAVE" ]; then
                        registrar "diferencial|$CLAVE|$(huella "$W/p/prog.cfv")" diferencial "$(nombre_clave "$CLAVE") solo en --release" "programa semilla $s: en modo normal termina bien" "$W/p/prog.cfv"
                    elif [ "$CODIGO" -ne "$cod_normal" ] || ! cmp -s "$W/p/out" "$W/p/out.rel"; then
                        primera=$(diff "$W/p/out" "$W/p/out.rel" | grep '^[<>]' | head -2 | tr '\n\t' '  ' | head -c 160)
                        registrar "diferencial|distinto|$(huella "$W/p/prog.cfv")" diferencial "resultado distinto en --release" "programa semilla $s: código $cod_normal vs $CODIGO · $primera" "$W/p/prog.cfv"
                    fi
                fi
            fi
        done

        # ── mutaciones + formato ─────────────────────────────────────────
        k=0
        while [ "$k" -lt 40 ] && quedan; do
            k=$((k + 1)); s=$((semilla + k))
            mkdir -p "$W/m"
            src=$(sed -n "$(( s % nfuentes + 1 ))p" "$W/fuentes")
            awk -v semilla="$s" -f "$LAB/mutar.awk" "$src" > "$W/m/a.cfv"
            awk -v semilla=$((s + 100000)) -f "$LAB/mutar.awk" "$W/m/a.cfv" > "$W/m/mut.cfv"
            ejecutar 20 "$W/m" "$W/m/o" "$W/m/e" "$C" check mut.cfv
            total_mut=$((total_mut + 1))
            if [ -n "$CLAVE" ]; then
                cp "$W/m/mut.cfv" "$W/m/falla.cfv"
                falla_programa mutaciones "$W/m/falla.cfv" check "$CLAVE" 20 "$(nombre_clave "$CLAVE") en el compilador · mutación de $(basename "$src") (semilla $s)" "compilador|$CLAVE|$(head -c 60 "$W/m/e" | tr '\n\t' '  ')"
                continue
            fi
            [ "$CODIGO" -ne 0 ] && continue

            # El formateador: no debe caerse, romper el programa ni cambiar
            # su resultado, y pasarlo dos veces debe dar lo mismo.
            cp "$W/m/mut.cfv" "$W/m/f1.cfv"
            ejecutar 20 "$W/m" "$W/m/fo" "$W/m/fe" "$C" fmt f1.cfv
            total_fmt=$((total_fmt + 1))
            if [ -n "$CLAVE" ]; then
                registrar "formato|$CLAVE|$(huella "$W/m/mut.cfv")" formato "$(nombre_clave "$CLAVE") en cforge fmt" "mutación de $(basename "$src") (semilla $s)" "$W/m/mut.cfv"
            elif [ "$CODIGO" -eq 0 ]; then
                ejecutar 20 "$W/m" "$W/m/fo" "$W/m/fe" "$C" check f1.cfv
                if [ "$CODIGO" -ne 0 ]; then
                    registrar "formato|rompe" formato "cforge fmt rompe un programa válido" "mutación de $(basename "$src") (semilla $s): después de formatear ya no compila · $(head -c 120 "$W/m/fe" | tr '\n\t' '  ')" "$W/m/mut.cfv"
                else
                    cp "$W/m/f1.cfv" "$W/m/f2.cfv"
                    ejecutar 20 "$W/m" "$W/m/fo" "$W/m/fe" "$C" fmt f2.cfv
                    if ! cmp -s "$W/m/f1.cfv" "$W/m/f2.cfv"; then
                        registrar "formato|no-idempotente" formato "cforge fmt da otro resultado la segunda vez" "mutación de $(basename "$src") (semilla $s)" "$W/m/mut.cfv"
                    fi
                fi
            fi

            ejecutar 20 "$W/m" "$W/m/o" "$W/m/e" "$C" mut.cfv
            if [ -n "$CLAVE" ] && [ "$CLAVE" != lento ] && [ "$CLAVE" != bloqueo ]; then
                cp "$W/m/mut.cfv" "$W/m/falla.cfv"
                falla_programa mutaciones "$W/m/falla.cfv" run "$CLAVE" 20 "$(nombre_clave "$CLAVE") al ejecutar · mutación de $(basename "$src") (semilla $s) $(head -c 120 "$W/m/e" | tr '\n\t' '  ')" "ejecucion|$CLAVE|$(basename "$src")"
            fi
        done

        # ── bytes aleatorios al compilador ───────────────────────────────
        k=0
        while [ "$k" -lt 20 ] && quedan; do
            k=$((k + 1))
            head -c $(( (semilla + k) % 2000 + 1 )) /dev/urandom > "$W/bytes.cfv"
            ejecutar 20 "$W" "$W/b.o" "$W/b.e" "$C" check bytes.cfv
            total_bytes=$((total_bytes + 1))
            [ -n "$CLAVE" ] && registrar "bytes|$CLAVE" bytes "$(nombre_clave "$CLAVE") en el compilador" "$(wc -c < "$W/bytes.cfv") bytes aleatorios" "$W/bytes.cfv"
        done
        rm -f /tmp/cforge-run-* 2>/dev/null
    done
    printf '%s %s %s %s %s %s %s %s\n' "$ronda" "$total_stdlib" "$total_cruz" "$total_prog" "$total_dif" "$total_mut" "$total_fmt" "$total_bytes" > "$S/totales"
}

regresiones > "$T/regresiones.log" 2>&1 &
i=1
while [ "$i" -le "$PARALELO" ]; do
    trabajador "$i" > "$T/trabajador$i.log" 2>&1 &
    i=$((i + 1))
done
wait

# ── Unir los resultados de los trabajadores ─────────────────────────────
cat "$SALIDA"/w*/fallas.tsv >> "$SALIDA/fallas.tsv" 2>/dev/null
awk -F '\t' '{v[$1]++} v[$1] <= 3' "$SALIDA/fallas.tsv" > "$T/f.tsv" && mv "$T/f.tsv" "$SALIDA/fallas.tsv"
set -- $(cat "$SALIDA"/w*/totales 2>/dev/null | awk '{for (i = 1; i <= NF; i++) s[i] += $i} END {for (i = 1; i <= 8; i++) printf "%d ", s[i] + 0}')
rondas=$1; total_stdlib=$2; total_cruz=$3; total_prog=$4; total_dif=$5; total_mut=$6; total_fmt=$7; total_bytes=$8
rm -rf "$SALIDA"/w*

# ── Reporte ─────────────────────────────────────────────────────────────
DUR=$(( ($(date +%s) - INICIO) / 60 ))
unicas=$(cut -f1 "$SALIDA/fallas.tsv" | sort -u | wc -l)
{
    echo "# 🔬 Reporte Fuzz Lab 2.0 · C-Forge"
    echo
    echo "- **Fecha:** $(date -u '+%Y-%m-%d %H:%M UTC')"
    echo "- **Versión:** $("$C" --version | head -1)"
    echo "- **Commit de C-Forge:** $(git -C "$RAIZ" rev-parse --short HEAD 2>/dev/null || echo '?')"
    echo "- **Duración:** $DUR min · $PARALELO trabajadores en paralelo · $rondas rondas"
    echo "- **Ataques:** $total_stdlib a la stdlib · $total_cruz pruebas cruzadas · $total_prog programas de estrés · $total_dif comparaciones normal/--release · $total_mut mutaciones · $total_fmt pruebas de formato · $total_bytes entradas de bytes"
    echo "- **Fallas únicas:** $unicas"
    if [ -s "$SALIDA/regresiones.tsv" ]; then
        echo "- **Fallas anteriores:** $(grep -c '^arreglada' "$SALIDA/regresiones.tsv") ✅ arregladas · $(grep -c '^sigue' "$SALIDA/regresiones.tsv") 🔴 siguen"
    fi
    echo
    if [ "$unicas" -eq 0 ]; then
        echo "✅ Sin cierres, cuelgues ni errores escapados en esta corrida."
    else
        echo "## Fallas"
        echo
        cut -f1 "$SALIDA/fallas.tsv" | awk '!v[$0]++' | while IFS= read -r firma; do
            awk -F '\t' -v f="$firma" '$1 == f' "$SALIDA/fallas.tsv" | head -1 | while IFS="$(printf '\t')" read -r _ motor tipo detalle archivo; do
                veces=$(awk -F '\t' -v f="$firma" '$1 == f' "$SALIDA/fallas.tsv" | wc -l)
                echo "### $tipo · $motor"
                echo
                echo "- **Detalle:** $detalle"
                echo "- **Ejemplos guardados:** $veces${archivo:+ · reproductor: \`$archivo\`}"
                if [ -n "$archivo" ] && [ -f "$SALIDA/$archivo" ] && [ "$(wc -c < "$SALIDA/$archivo")" -le 1500 ] && LC_ALL=C grep -qv '[^[:print:][:space:]]' "$SALIDA/$archivo" 2>/dev/null; then
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
        echo "- programas, mutaciones y diferencial: \`cforge casos/…cfv\` (o \`cforge check\`; diferencial: compara con \`cforge build … --release\`)"
        echo "- stdlib: \`ataques --archivo OBJETIVO casos/…bin\` (la entrada exacta)"
        echo "- Los programas de estrés y mutaciones ya vienen reducidos al mínimo que sigue fallando."
    fi
    if [ -s "$SALIDA/regresiones.tsv" ]; then
        echo
        echo "## 🔁 Fallas de corridas anteriores"
        echo
        echo "| Estado | Motor | Tipo | Cuántas | Vistas en |"
        echo "|---|---|---|---|---|"
        awk -F '\t' '{k = $1 "\t" $3 "\t" $4; n[k]++; c[k] = (k in c && index(c[k], $5)) ? c[k] : (c[k] ? c[k] ", " $5 : $5)} END {for (k in n) print k "\t" n[k] "\t" c[k]}' "$SALIDA/regresiones.tsv" | sort | while IFS="$(printf '\t')" read -r estado motor tipo cuantas corridas; do
            if [ "$estado" = arreglada ]; then e="✅ arreglada"; else e="🔴 sigue"; fi
            echo "| $e | $motor | $tipo | $cuantas | $corridas |"
        done
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
    echo "Las pruebas sin equivalente en otros lenguajes solo se comparan con la corrida anterior. Una **regresión** es una prueba más de 30 % (y 30 ms) más lenta que la corrida anterior."
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
