#!/bin/sh
# objetivos/cforge/biseccion.sh — Fuzz Lab de Vemoris: ¿qué commit de C-Forge
# introdujo una falla? (bisección automática, como ClusterFuzz).
#
#   CFORGE_DIR=cforge sh objetivos/cforge/biseccion.sh REPRODUCTOR [MODO] [MAX_COMMITS]
#
#   REPRODUCTOR  programa .cfv que hace fallar a C-Forge (de casos/)
#   MODO         run (compilar y ejecutar, por defecto) o check (solo compilar)
#   MAX_COMMITS  cuántos commits hacia atrás buscar una versión sana (200)
#
# CFORGE_DIR debe ser un clon de C-Forge con historia (git fetch --depth=…).
# Escribe una línea: "introducida en <commit> <fecha> <título>", o
# "ya estaba antes de <commit>" si falla en todo el rango, o "no falla".
# El repo de C-Forge queda en el commit en que estaba al empezar.
set -u

REPRO=$(cd "$(dirname "$1")" && pwd)/$(basename "$1")
MODO=${2:-run}
MAX=${3:-200}
RAIZ=$(cd "${CFORGE_DIR:-cforge}" && pwd)
T=$(mktemp -d)
INICIAL=$(git -C "$RAIZ" rev-parse HEAD)
trap 'git -C "$RAIZ" bisect reset >/dev/null 2>&1; git -C "$RAIZ" checkout -q "$INICIAL" 2>/dev/null; make -C "$RAIZ" build >/dev/null 2>&1; rm -rf "$T"' EXIT

# Prueba guardada en un archivo: la usa "git bisect run".
#   0 = sana · 1 = falla · 125 = no compila (saltar este commit)
cat > "$T/probar.sh" <<EOF
#!/bin/sh
cd "$RAIZ" || exit 125
make build > /dev/null 2>&1 || exit 125
[ -x ./cforge ] || exit 125
cp "$REPRO" "$T/p.cfv"
cd "$T"
if [ "$MODO" = check ]; then
    timeout -s KILL 30 "$RAIZ/cforge" check p.cfv > /dev/null 2>&1
else
    CFORGE_STDLIB="$RAIZ/stdlib" timeout -s KILL 60 "$RAIZ/cforge" p.cfv > /dev/null 2>&1
fi
c=\$?
pkill -9 -f cforge-run- 2>/dev/null
# Señal (> 128) o cuelgue (137 por timeout -s KILL) = falla.
if [ "\$c" -gt 128 ]; then exit 1; fi
exit 0
EOF
chmod +x "$T/probar.sh"

if sh "$T/probar.sh"; then
    echo "no falla en $(git -C "$RAIZ" rev-parse --short HEAD)"
    exit 0
fi

# Buscar una versión sana hacia atrás: 1, 2, 4, 8… commits.
paso=1; sana=""
total=$(git -C "$RAIZ" rev-list --count HEAD)
while [ "$paso" -le "$MAX" ] && [ "$paso" -lt "$total" ]; do
    c=$(git -C "$RAIZ" rev-parse "HEAD~$paso" 2>/dev/null) || break
    git -C "$RAIZ" checkout -q "$c"
    if sh "$T/probar.sh"; then sana=$c; break; fi
    git -C "$RAIZ" checkout -q "$INICIAL"
    paso=$((paso * 2))
done
git -C "$RAIZ" checkout -q "$INICIAL"

if [ -z "$sana" ]; then
    mas_viejo=$(git -C "$RAIZ" rev-parse --short "HEAD~$(( paso / 2 ))" 2>/dev/null || echo "?")
    echo "ya estaba antes de $mas_viejo (no se encontró una versión sana en $MAX commits)"
    exit 0
fi

git -C "$RAIZ" bisect start "$INICIAL" "$sana" > /dev/null 2>&1
git -C "$RAIZ" bisect run sh "$T/probar.sh" > "$T/bisect.log" 2>&1
[ -n "${FL_DEPURAR:-}" ] && cat "$T/bisect.log"
culpable=$(grep -m1 "is the first bad commit" "$T/bisect.log" | awk '{print $1}')
if [ -n "$culpable" ]; then
    echo "introducida en $(git -C "$RAIZ" log -1 --format='%h %ad %s' --date=short "$culpable")"
else
    echo "no se pudo determinar (ver la bisección: algunos commits no compilan)"
fi
