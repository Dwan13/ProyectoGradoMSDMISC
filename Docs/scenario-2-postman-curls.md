# Escenario 2 - cURL para Postman (crear y consultar usuario)

## 1) Login para obtener token
```bash
curl -X POST 'http://127.0.0.1:30184/login' \
  -H 'Content-Type: application/json' \
  -d '{"username":"demo","password":"demo123"}'
```

Respuesta esperada (resumen):
```json
{"access_token":"...","token_type":"bearer"}
```

## 2) Crear usuario (usar token del paso 1)
```bash
curl -X POST 'http://127.0.0.1:30181/users' \
  -H 'Authorization: Bearer TU_TOKEN' \
  -H 'Content-Type: application/json' \
  -d '{"username":"usuario_postman_001","email":"usuario_postman_001@example.com"}'
```

## 3) Consultar usuarios y verificar que existe
```bash
curl -X GET 'http://127.0.0.1:30181/users?limit=20000' \
  -H 'Authorization: Bearer TU_TOKEN'
```

Nota:
- En esta implementación, la verificación práctica se hace por listado (`/users?limit=...`) y/o SQL directa en Postgres.
- Si quieres validación SQL directa:
```bash
kubectl exec -n mubench-real deploy/postgres -- \
  psql -U mubench -d mubench_real -t -c "SELECT id,username,email FROM app_users WHERE username='usuario_postman_001';"
```
