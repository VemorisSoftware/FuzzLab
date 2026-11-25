# 🌐 Fuzz Lab Web · Vemoris Software

> ⚠️ **Software propietario.** Ver [LICENSE](../LICENSE). Úsalo solo contra sitios y APIs propias o con permiso escrito de su dueño.

Pone a prueba sitios web y APIs, 100 % en C-Forge.

```sh
cforge build web/fuzzlab-web.cfv -o fuzzlab-web
./fuzzlab-web carga   objetivo.json
./fuzzlab-web api     objetivo.json
./fuzzlab-web rutas   objetivo.json
./fuzzlab-web revisar objetivo.json
```

## 🔒 Seguridad incorporada

- **Solo ataca dominios autorizados:** `"autorizados": ["misitio.cl"]` (incluye subdominios). Sin esa lista, solo `127.0.0.1` y `localhost`.
- **Nunca sigue redirecciones:** usa su propio cliente HTTP/HTTPS y no termina en un dominio ajeno.
- **Tasa máxima:** `api`, `rutas` y `revisar` van a 50 peticiones por segundo como máximo (`"tasa_maxima"`).

## Modos

| Modo | Inspirado en | Qué hace |
|---|---|---|
| **carga** | wrk, vegeta, k6, locust | Tasa fija (`"tasa"`: peticiones/s) o usuarios simultáneos (`"usuarios"`), escenarios de varios pasos, latencias p50/p90/p95/p99, códigos de respuesta, gráfico por segundo y **umbrales** que hacen fallar el CI |
| **api** | schemathesis | Lee el OpenAPI (archivo o URL) y ataca cada endpoint con datos válidos, valores límite e inválidos. Detecta errores 5xx, conexiones cortadas, respuestas no documentadas, datos inválidos aceptados, JSON roto, respuestas lentas y detalles internos expuestos. Cada hallazgo trae su `curl` para reproducirlo |
| **rutas** | ffuf | Busca más de 75 archivos y rutas sensibles (`.env`, `.git`, respaldos SQL, claves, phpinfo, Actuator, paneles…) con autocalibración contra el "no existe" del sitio (aunque responda 200). Palabras propias y `FUZZ` en cualquier parte de la URL |
| **revisar** | nuclei, ZAP | Cabeceras de seguridad, versión del servidor, cookies inseguras, CORS, XSS reflejado, inyección SQL, redirección abierta, inyección de plantillas (SSTI), recorrido de rutas, TRACE, listado de carpetas, errores internos visibles, HTTPS. **Plantillas propias** en JSON |

## Ejemplos

```json
{"url": "https://api.misitio.cl", "autorizados": ["misitio.cl"],
 "escenario": [{"metodo": "GET", "ruta": "/"}, {"metodo": "POST", "ruta": "/api/login", "cuerpo": "{}", "esperar": 401}],
 "tasa": 200, "duracion_s": 60, "umbrales": {"p95_ms": 300, "errores_pct": 1}}
```

Plantilla propia para `revisar` (carpeta `"plantillas"`):

```json
{"id": "panel-viejo", "severidad": "alta", "titulo": "Panel antiguo expuesto",
 "ruta": "/admin-viejo", "coincide": {"estado": 200, "cuerpo": ["Panel"], "cabecera": {"server": "Apache/2.2"}}}
```

Prueba local con el sitio vulnerable a propósito de `ejemplos/`:

```sh
python3 web/ejemplos/sitio_vulnerable.py 8790 &
./fuzzlab-web revisar web/ejemplos/revisar.json   # 8 hallazgos: SQL, XSS, rutas, CORS, redirección…
./fuzzlab-web rutas   web/ejemplos/rutas.json     # .env y .git expuestos
./fuzzlab-web api     web/ejemplos/api.json       # 500, caída, validación faltante, lentitud
./fuzzlab-web carga   web/ejemplos/carga.json     # 300 peticiones/s con umbrales
```

Resultados en `REPORTE.md` y `hallazgos.json`. Sale con código 1 si hay hallazgos críticos o altos (útil en CI).
