# 🔬 Fuzz Lab Universal · Vemoris Software

> ⚠️ **Software propietario.** Ver [LICENSE](../LICENSE).

Ataca **cualquier programa, en cualquier lenguaje**, que lea una entrada desde un archivo o desde la entrada estándar: C, C++, Rust, Go, Swift, Python, JavaScript, Java, C-Forge, una herramienta de línea de comandos… Escrito 100 % en C-Forge, sin depender de otras herramientas de fuzzing.

```sh
cforge build universal/fuzzlab.cfv -o fuzzlab
./fuzzlab objetivo.json
```

```json
{
  "nombre": "mi-parser",
  "comando": "./mi_parser @@",
  "semillas": "semillas",
  "diccionario": ["<a>", "SELECT"],
  "limite_ms": 2000,
  "minutos": 30,
  "salida": "fuzzlab-salida"
}
```

`@@` es el archivo con la entrada; si no está, la entrada va por stdin. Opcionales: `carpeta`, `excepciones_son_fallas` (para Python, JS, Java… una excepción sin atrapar cuenta), `patrones_falla` y `codigos_falla`.

## 🧪 Sanitizadores (C, C++, Rust, Swift, Objective-C)

Con `"compilar"`, Fuzz Lab compila el programa una vez por sanitizador y ataca con el primero (con cobertura real). Al final repasa el corpus, las fallas y miles de mutaciones con los demás, porque cada uno ve errores distintos:

| Sanitizador | Encuentra |
|---|---|
| `asan` | desbordes de memoria, uso después de liberar, doble liberación, fugas |
| `ubsan` | comportamiento indefinido: desborde de enteros, división por cero, punteros mal alineados |
| `msan` | lectura de memoria sin iniciar |
| `tsan` | carreras de datos entre hilos |

```json
{"compilar": "clang -g -O1 {banderas} parser.c -o {binario}",
 "comando": "{binario} @@",
 "sanitizadores": ["asan", "ubsan", "msan"]}
```

Las palabras entre comillas del código fuente (cabeceras mágicas, comandos) se usan como diccionario prioritario y como semillas.

## Cómo piensa

| Técnica | Qué hace |
|---|---|
| **Cobertura real** | Si el programa se compila con `-fsanitize=address -fsanitize-coverage=trace-pc-guard` (clang: C, C++, Rust, Swift), lee qué partes del código recorrió cada entrada y guarda las que llegan a zonas nuevas. Sin eso, usa el comportamiento (código de salida, mensajes, tamaños y tiempos) |
| **Corpus que evoluciona** | Cada entrada que logra algo nuevo pasa a ser base de las siguientes; prefiere las recientes, chicas y poco explotadas |
| **Mutaciones havoc** | Bits, bytes, valores límite, aritmética, bloques borrados o repetidos, cruces entre entradas, números extremos |
| **Diccionario automático** | Palabras sacadas del propio programa atacado (cabeceras mágicas, palabras clave) y de las semillas |
| **Barrido determinista** | Prueba cada carácter en las primeras posiciones de cada entrada nueva: abre los "candados" de un byte |
| **Inyección dirigida** | Mete cargas de inyección de comandos, SQL, rutas, formato y plantillas donde termina cada valor |
| **Detectores** | Cierres por señal, cuelgues, ASan/UBSan/LSan/TSan/MSan, excepciones sin atrapar, inyección de comandos confirmada (programa canario), inyección SQL, recorrido de rutas |
| **Reducción** | Cada falla se reduce al mínimo de bytes que la sigue provocando y se agrupa por su firma (tipo de error + función donde ocurre) |
| **Memoria de fallas** | Al empezar vuelve a probar las fallas guardadas y marca ✅ arreglada / 🔴 sigue |
| **Corpus mínimo** | Al terminar deja en `corpus/` las entradas más chicas que mantienen toda la cobertura; la próxima corrida parte desde ahí |

## Ejemplos (vulnerables a propósito)

```sh
clang -g -fsanitize=address -fsanitize-coverage=trace-pc-guard universal/ejemplos/parser.c -o universal/ejemplos/parser
./fuzzlab universal/ejemplos/parser.json   # desbordamiento de memoria escondido tras 2 candados
./fuzzlab universal/ejemplos/ping.json     # inyección de comandos (Python)
./fuzzlab universal/ejemplos/buscar.json   # inyección SQL (Python)
./fuzzlab universal/ejemplos/tres.json     # 3 errores en C: cada sanitizador encuentra el suyo
```

Resultado: `salida-*/REPORTE.md`, `fallas/` (entradas mínimas), `fallas.json` y `corpus/`.

Solo se puede usar contra sistemas propios o con autorización expresa de su dueño.
