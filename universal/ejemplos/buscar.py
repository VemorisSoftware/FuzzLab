# Ejemplo VULNERABLE A PROPÓSITO para probar Fuzz Lab Universal. No usar en producción.
import sys, sqlite3
dato = open(sys.argv[1], 'rb').read().decode('utf-8', 'replace')[:100]
db = sqlite3.connect(':memory:'); db.execute('create table u (n text)')
db.execute("select * from u where n = '" + dato + "'")   # inyección SQL
