# Ejemplo VULNERABLE A PROPÓSITO para probar Fuzz Lab Universal. No usar en producción.
import sys, subprocess
dato = open(sys.argv[1], "rb").read().decode('utf-8', 'replace')
if dato.startswith('ping '):
    subprocess.run('echo ' + dato[5:40], shell=True)   # inyección de comandos
