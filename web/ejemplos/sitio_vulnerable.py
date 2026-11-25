# Sitio VULNERABLE A PROPÓSITO para probar Fuzz Lab Web. Solo en 127.0.0.1.
# Nunca lo publiques. Uso: python3 sitio_vulnerable.py 8790
import json, sqlite3, sys, time, os
from http.server import ThreadingHTTPServer, BaseHTTPRequestHandler
from urllib.parse import urlparse, parse_qs

DB = sqlite3.connect(':memory:', check_same_thread=False)
DB.execute('create table usuarios (id integer, nombre text)')
DB.execute("insert into usuarios values (1, 'ana')")

OPENAPI = {
  "openapi": "3.0.0", "info": {"title": "Tienda de prueba", "version": "1"},
  "paths": {
    "/api/productos/{id}": {"get": {"parameters": [{"name": "id", "in": "path", "required": True, "schema": {"type": "integer", "minimum": 1, "maximum": 100}}],
                                     "responses": {"200": {"description": "ok"}, "404": {"description": "no existe"}}}},
    "/api/pedidos": {"post": {"requestBody": {"content": {"application/json": {"schema": {"$ref": "#/components/schemas/Pedido"}}}},
                              "responses": {"201": {"description": "creado"}, "400": {"description": "datos malos"}}}},
    "/api/lento": {"get": {"parameters": [{"name": "n", "in": "query", "schema": {"type": "integer", "minimum": 0, "maximum": 3}}],
                           "responses": {"200": {"description": "ok"}}}}
  },
  "components": {"schemas": {"Pedido": {"type": "object", "required": ["producto", "cantidad"],
      "properties": {"producto": {"type": "string", "maxLength": 20}, "cantidad": {"type": "integer", "minimum": 1, "maximum": 10}}}}}
}

class H(BaseHTTPRequestHandler):
    def log_message(self, *a): pass
    def enviar(self, estado, cuerpo, tipo='text/html; charset=utf-8', extra=None):
        datos = cuerpo.encode() if isinstance(cuerpo, str) else cuerpo
        self.send_response(estado)
        self.send_header('Content-Type', tipo)
        self.send_header('Content-Length', str(len(datos)))
        origen = self.headers.get('Origin')
        if origen:                                       # CORS que refleja cualquier origen
            self.send_header('Access-Control-Allow-Origin', origen)
            self.send_header('Access-Control-Allow-Credentials', 'true')
        for k, v in (extra or {}).items(): self.send_header(k, v)
        self.end_headers(); self.wfile.write(datos)

    def do_GET(self):
        u = urlparse(self.path); q = parse_qs(u.query); p = u.path
        if p == '/':
            return self.enviar(200, '<h1>Tienda</h1>', extra={'Set-Cookie': 'sesion=abc123; Path=/'})
        if p == '/buscar':                               # XSS reflejado
            return self.enviar(200, '<p>Resultados para ' + q.get('q', [''])[0] + '</p>')
        if p == '/usuario':                              # inyección SQL
            try:
                fila = DB.execute("select nombre from usuarios where id = '" + q.get('id', [''])[0] + "'").fetchall()
                return self.enviar(200, json.dumps(fila), 'application/json')
            except Exception as e:
                return self.enviar(500, 'Traceback (most recent call last): sqlite3.OperationalError: ' + str(e))
        if p == '/ir':                                   # redirección abierta
            return self.enviar(302, '', extra={'Location': q.get('next', ['/'])[0]})
        if p == '/archivo':                              # recorrido de rutas
            try: return self.enviar(200, open('/tmp/' + q.get('nombre', ['x'])[0]).read(), 'text/plain')
            except Exception: return self.enviar(404, 'no')
        if p == '/.env': return self.enviar(200, 'DB_PASSWORD=supersecreta\nAPI_KEY=xyz', 'text/plain')
        if p == '/.git/config': return self.enviar(200, '[core]\n\trepositoryformatversion = 0', 'text/plain')
        if p == '/openapi.json': return self.enviar(200, json.dumps(OPENAPI), 'application/json')
        if p.startswith('/api/productos/'):
            try: n = int(p.rsplit('/', 1)[1])
            except ValueError: return self.enviar(500, 'Traceback: ValueError')   # tipo malo → 500
            return self.enviar(200 if 1 <= n <= 100 else 404, json.dumps({"id": n}), 'application/json')
        if p == '/api/lento':
            try: time.sleep(min(int(q.get('n', ['0'])[0]), 3))
            except ValueError: pass
            return self.enviar(200, '{}', 'application/json')
        if p == '/hola':
            time.sleep(0.005)
            return self.enviar(200, 'hola')
        return self.enviar(200, '<p>Página no encontrada</p>')    # "404" falso con 200

    def do_POST(self):
        largo = int(self.headers.get('Content-Length', 0)); cuerpo = self.rfile.read(largo)
        if self.path == '/api/pedidos':
            try: d = json.loads(cuerpo)
            except Exception: return self.enviar(400, '{"error": "json"}', 'application/json')
            if not isinstance(d, dict) or 'producto' not in d: return self.enviar(400, '{}', 'application/json')
            total = 1000 / d.get('cantidad', 1) if isinstance(d.get('cantidad'), (int, float)) else 0   # cantidad 0 → error 500
            return self.enviar(201, json.dumps({"total": total}), 'application/json')
        return self.enviar(404, '')

ThreadingHTTPServer(('127.0.0.1', int(sys.argv[1]) if len(sys.argv) > 1 else 8790), H).serve_forever()
