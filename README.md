# 🔬 Fuzz Lab · Vemoris Software

> ⚠️ **Software propietario.** El código es visible solo por transparencia. Usar, ejecutar, copiar o modificar Fuzz Lab requiere **permiso previo y por escrito** de Vemoris Software. Ver [LICENSE](LICENSE).

Laboratorio de ataques automáticos de Vemoris. Bombardea nuestros proyectos con miles de entradas hostiles, día y noche, para encontrar cierres, cuelgues y errores antes que nadie. No usa IA: es fuerza bruta, y no cuesta nada.

## Objetivos

| Proyecto | Carpeta | Automatización |
|---|---|---|
| **C-Forge** ([VemorisSoftware/cforge](https://github.com/VemorisSoftware/cforge)) | `objetivos/cforge/` | `.github/workflows/cforge.yml` |

## C-Forge: qué ataca

| Motor | Qué hace |
|---|---|
| **stdlib** | JSON, Base64, URL, CSV, regex, XML, Markdown, números, LZ4, Snappy, Zstd, zlib, PNG y textos con entradas aleatorias, mutadas y patológicas (`ataques_stdlib.cfv`) |
| **programas** | Programas de estrés generados: recursión profunda, enteros gigantes, memoria, closures, excepciones, a veces con el GC en estrés (`generador.cfv`) |
| **mutaciones** | Programas reales de C-Forge con mutaciones, en el compilador y al ejecutar |
| **bytes** | Bytes aleatorios al compilador |

Una **falla** es un cierre por señal (segfault, abort, sin memoria), un cuelgue o un error que `intentar/capturar` no atrapa. Los errores normales de C-Forge no cuentan.

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
