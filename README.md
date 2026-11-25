# 🔬 Fuzz Lab · Vemoris Software

> ⚠️ **Software propietario.** El código es visible solo por transparencia. Usar, ejecutar, copiar o modificar Fuzz Lab requiere **permiso previo y por escrito** de Vemoris Software. Ver [LICENSE](LICENSE).

Laboratorio de ataques automáticos de Vemoris. Bombardea nuestros proyectos con miles de entradas hostiles, día y noche, para encontrar cierres, cuelgues y errores antes que nadie. No usa IA: es fuerza bruta, y no cuesta nada.

## Objetivos

**Fuzz Lab Universal** ([`universal/`](universal/README.md)) ataca cualquier programa en cualquier lenguaje, con cobertura real, diccionario automático, inyección dirigida y reducción de fallas.


| Proyecto | Carpeta | Automatización |
|---|---|---|
| **C-Forge** ([VemorisSoftware/cforge](https://github.com/VemorisSoftware/cforge)) | `objetivos/cforge/` | `.github/workflows/cforge.yml` |

## C-Forge: qué ataca

| Motor | Qué hace |
|---|---|
| **stdlib** | JSON, Base64, URL, CSV, regex (incluye ReDoS), XML (incluye entidades en cadena), Markdown, números, LZ4, Snappy, Zstd, zlib, PNG y textos con entradas aleatorias, mutadas y patológicas |
| **programas** | Programas de estrés generados: recursión profunda, enteros gigantes, memoria, closures, excepciones, a veces con el GC en estrés |
| **diferencial** | El mismo programa compilado normal y con `--release` debe dar exactamente lo mismo (encuentra errores del optimizador) |
| **mutaciones** | Programas reales de C-Forge con mutaciones, en el compilador y al ejecutar |
| **formato** | `cforge fmt` no debe caerse, romper un programa ni dar otro resultado si se pasa dos veces |
| **bytes** | Bytes aleatorios al compilador |
| **cruzadas** | Resultados incorrectos: propiedades que siempre deben cumplirse |
| **rendimiento** | Velocidad contra la corrida anterior y contra C, C++, Rust, Java, C#, JavaScript y TypeScript |
| **memoria** | Fugas: repite tareas 1000 y 4000 veces y vigila que la memoria no crezca sin control |
| **regresiones** | Vuelve a probar todas las fallas de corridas anteriores y marca ✅ arreglada o 🔴 sigue |

### Fuzz Lab 2.0

- **Minimizador automático:** cada programa que falla se reduce solo al mínimo de líneas que sigue provocando la falla, y las fallas se agrupan por ese programa reducido (no por síntomas).
- **Cuelgue o lento:** distingue un programa bloqueado (sin usar CPU) de uno demasiado lento.
- **Sin procesos zombis:** al cortar un programa se cierra todo su árbol de procesos.
- **En paralelo:** varios trabajadores a la vez (uno por núcleo, hasta 4), con tope de memoria por programa.

## Cómo funciona

- Corre cada 6 horas, en tandas de 5,5 horas, sobre la última versión de `main` de C-Forge.
- 🔒 **Confidencial:** las vulnerabilidades encontradas nunca se publican. El reporte y los reproductores van solo a un repo privado de Vemoris Software.

**Para pararlo:** Settings → Secrets and variables → Actions → Variables → `FUZZ_LAB_ACTIVO` = `no`.

## Licencia y permisos

Fuzz Lab **no es de código abierto**. Las empresas que quieran auditar sus productos o su código con Fuzz Lab deben solicitar una licencia a Vemoris Software: **contacto@vemoris.cl**.

Aun con permiso, solo se puede usar contra sistemas propios o con autorización expresa de su dueño. Atacar sistemas de terceros sin autorización está prohibido.

## Correrlo a mano (solo con autorización)

```sh
git clone https://github.com/VemorisSoftware/cforge && make -C cforge build
CFORGE_DIR=cforge sh objetivos/cforge/fuzzlab.sh 30 salida   # 30 minutos
```
