# Tipos de Carga y Comportamiento de las Peticiones

> **Fecha:** 2026-05-14  
> **Script:** `RealisticServices/k6/realistic-flow.js`  
> **Experimento:** S6 Integrated Dual-Mode

---

## 1. Tipos de Carga Utilizados

### 1.1 Carga Constante (Constant VUs)

Se utilizó el modelo de **Virtual Users (VUs) constantes** de k6, no un modelo de rampa. Cada VU ejecuta el escenario de forma continua durante toda la duración de la corrida.

| Parámetro | Valor |
|-----------|-------|
| Modelo | Constant VUs (no ramp-up) |
| VUS levels | 1, 5, 10, 20 |
| Duración por corrida | 60 segundos |
| Warm-up previo | 30 segundos (espera readiness) |
| Cooldown posterior | 15 segundos |
| Sleep entre iteraciones | 0.5 segundos (dentro del VU loop) |
| Iteraciones aprox. por VU | ~40 iteraciones/min a 1VU, ~80/min a 20VU |

### 1.2 Justificación de Niveles de VUS

| VUS | Carga esperada (rps aprox) | Propósito |
|-----|--------------------------|-----------|
| 1 | ~18 rps | Carga mínima — overhead puro sin contención |
| 5 | ~90 rps | Carga ligera — operación normal |
| 10 | ~100 rps | Carga media — saturación parcial |
| 20 | ~130 rps | Carga alta — límite del single-node |

Los 4 niveles de VUS permiten modelar la relación latencia-throughput (curva de codo) y detectar el punto de saturación de cada control.

### 1.3 Carga Total por Experimento

```
4 controles × 3 variantes × 4 VUS × 2 modos × 4 réplicas = 384 corridas
Tiempo por corrida: 30s warmup + 60s load + 15s cooldown ≈ 105s
Tiempo total estimado: 384 × 105s ≈ 11.2 horas
```

---

## 2. Modos de Carga

### 2.1 Modo Normal (`SECURITY_MODE=normal`)

**Descripción:** Tráfico 100% legítimo. Simula un usuario autenticado que realiza operaciones normales de la aplicación. Ninguna petición de ataque.

**Flujo por iteración de VU:**
```
1. POST /auth/login        ← obtener JWT
   ↓ (si token OK)
2. GET /api/profile        ← consultar perfil
3. GET /api/users          ← listar usuarios
   ↓
4. sleep(0.5s)             ← pausa entre iteraciones
```

**Comportamiento esperado:**
- `err_pct ≈ 0%` (solo errores de infraestructura)
- `login_success_total = jwt_issued_total` (todos los logins exitosos)
- `profile_success_total ≈ login_success_total`
- `users_list_success_total ≈ login_success_total`

**Threshold k6:** `http_req_failed: rate < 0.05`

### 2.2 Modo Attack (`SECURITY_MODE=attack`)

**Descripción:** Tráfico mixto. Cada VU ejecuta el flujo legítimo **completo** y luego ejecuta probes de ataque adicionales. Los ataques son diseñados para ser bloqueados (401/403/429).

**Flujo por iteración de VU:**
```
1. POST /auth/login        ← flujo legítimo
   ↓ (si token OK)
2. GET /api/profile
3. GET /api/users
   ↓
4. runAttackProbes()       ← ATAQUES (adicionales)
   ↓
5. sleep(0.5s)
```

**Threshold k6:** `http_req_failed: rate < 0.80` (los ataques generan errores esperados)

---

## 3. Detalle de Cada Petición

### 3.1 POST /auth/login — Autenticación

**Endpoint:** `{AUTH_BASE}/login`  
**Método:** POST  
**Content-Type:** `application/json`

**Cuerpo de la petición:**
```json
{
  "username": "demo",
  "password": "demo123"
}
```

**Comportamiento esperado:**
- **HTTP 200** → autenticación exitosa
- Body de respuesta:
  ```json
  {
    "access_token": "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9...",
    "token_type": "bearer",
    "expires_in": 3600
  }
  ```
- k6 verifica:
  - `check: login status 200`
  - `check: login has token` (campo `access_token` presente y no vacío)
- Métricas emitidas: `login_success_total++`, `jwt_issued_total++`, `jwt_trace_events++` (con fingerprint SHA-256 del token)

**Comportamiento en fallo:**
- HTTP 401/403: credenciales inválidas → `login_fail_total++`
- El VU hace `sleep(1)` y termina la iteración sin llamar a profile/users
- Contador de fallo: `loginFailTotal.add(1, {security_mode})`

**JWT Payload típico:**
```json
{
  "sub": "demo",
  "iat": 1715734800,
  "exp": 1715738400,
  "jti": "uuid-v4"
}
```

---

### 3.2 GET /api/profile — Consulta de Perfil

**Endpoint:** `{API_BASE}/profile?user_id=1`  
**Método:** GET  
**Headers:**
```
Authorization: Bearer {token_obtenido_en_login}
```

**Comportamiento esperado:**
- **HTTP 200** → perfil encontrado
- Body de respuesta:
  ```json
  {
    "user": {
      "id": 1,
      "username": "demo",
      "email": "demo@mubench.local",
      "created_at": "2026-01-01T00:00:00Z"
    },
    "db_latency_ms": 9.54
  }
  ```
- k6 verifica:
  - `check: profile status 200`
  - `check: profile has user` (campo `user.username` presente)
- Métricas emitidas: `profile_success_total++`, `profileDbLatencyMs.add(db_latency_ms)`

**Flujo interno del api-service:**
1. Valida JWT en cabecera `Authorization` (llamada a auth-service o validación local)
2. Llama a data-service: `GET /data/profile?user_id=1`
3. data-service ejecuta `SELECT * FROM users WHERE id = $1` en PostgreSQL
4. data-service devuelve el registro + `db_latency_ms`
5. api-service construye y devuelve `ProfileResponse`

**Comportamiento en error:**
- HTTP 401: token inválido/expirado
- HTTP 403: usuario no autorizado para ese perfil
- HTTP 503: data-service no alcanzable (C3/strict produce este escenario)

---

### 3.3 GET /api/users — Listado de Usuarios

**Endpoint:** `{API_BASE}/users?limit=20&offset=0`  
**Método:** GET  
**Headers:**
```
Authorization: Bearer {token_obtenido_en_login}
```

**Comportamiento esperado:**
- **HTTP 200** → lista de usuarios
- Body de respuesta:
  ```json
  {
    "users": [
      {"id": 1, "username": "demo", "email": "demo@mubench.local"},
      {"id": 2, "username": "user2", "email": "user2@mubench.local"}
    ],
    "count": 2,
    "db_latency_ms": 11.2
  }
  ```
- k6 verifica:
  - `check: users status 200`
  - `check: users has count` (`count >= 0`)
- Métricas emitidas: `users_list_success_total++`, `usersDbLatencyMs.add(db_latency_ms)`

**Parámetros de paginación:**
- `limit=20`: máximo 20 registros por página
- `offset=0`: inicio desde el primer registro

---

### 3.4 Probes de Ataque (Solo Modo Attack)

Se ejecutan **después** del flujo legítimo en cada iteración. Todos están diseñados para producir respuesta de bloqueo (401/403/429).

#### Probe 1 — Bad Login (CWE-287)
```http
POST {AUTH_BASE}/login
{"username": "demo", "password": "wrong-password"}
```
- **Esperado:** HTTP 401 (credenciales inválidas)
- **Propósito:** Detectar si el servicio expone información diferencial en errores de auth

#### Probe 2 — Acceso No Autenticado (CWE-639)
```http
GET {API_BASE}/users?limit=5&offset=0
(sin cabecera Authorization)
```
- **Esperado:** HTTP 401 (sin token)
- **Propósito:** Verificar que el endpoint de usuarios no sea públicamente accesible

#### Probe 3 — Token Manipulado / Firma Inválida (CWE-347) [solo ADVANCED]
```http
GET {API_BASE}/profile?user_id=1
Authorization: Bearer tampered.invalid.token
```
- **Esperado:** HTTP 401 (firma JWT inválida)
- **Propósito:** Verificar validación de firma JWT; el servidor no debe aceptar tokens con payload arbitrario

#### Probe 4 — Bearer Malformado (CWE-20) [solo ADVANCED]
```http
GET {API_BASE}/users?limit=5&offset=0
Authorization: Bearer
```
- **Esperado:** HTTP 401 (formato de header inválido)
- **Propósito:** Fuzzing del parser de Authorization; verificar que no genera 500 (error interno)

#### Probes 5/6/7 — XFF Spoofing (CWE-923) [solo ADVANCED]
```http
GET {API_BASE}/users?limit=5&offset=0
Authorization: Bearer tampered.invalid.token
X-Forwarded-For: 1.2.3.4
```
```http
X-Forwarded-For: 10.20.30.40, 44.55.66.77
```
```http
X-Forwarded-For: 203.0.113.5, 198.51.100.2, 192.0.2.8
```
- **Esperado:** HTTP 401 (token inválido independientemente de XFF)
- **Propósito:** Verificar que el gateway no confía ciegamente en la IP del header XFF para bypassing de controles

---

## 4. Resumen del Mix de Tráfico por Modo

### Modo Normal
| Petición | Proporción del tráfico | Esperado |
|----------|----------------------|---------|
| POST /auth/login | 33% | 200 OK + JWT |
| GET /api/profile | 33% | 200 OK + user JSON |
| GET /api/users | 33% | 200 OK + users list |

### Modo Attack (ADVANCED profile)
| Petición | Proporción | Esperado |
|----------|------------|---------|
| POST /auth/login (legítimo) | ~22% | 200 OK |
| GET /api/profile (legítimo) | ~22% | 200 OK |
| GET /api/users (legítimo) | ~22% | 200 OK |
| Probe bad_login | ~7% | 401 Blocked |
| Probe unauth_users | ~7% | 401 Blocked |
| Probe tampered_bearer | ~7% | 401 Blocked |
| Probe malformed_bearer | ~7% | 401 Blocked |
| Probes xff_spoof (×3) | ~21% | 401 Blocked |

> En este mix, ~66% es tráfico legítimo y ~34% son probes de ataque, lo que explica `err_pct ≈ 33–35%` en modo attack con todos los ataques bloqueados correctamente.

---

## 5. Thresholds y Criterios de Calidad por Petición

| Petición | Threshold k6 | Alerta Prometheus |
|----------|-------------|------------------|
| Todas | `p(95) < 700ms` | P95 > 400ms por 5min |
| Todas | `checks rate > 95%` | — |
| Normal mode | `http_req_failed < 5%` | Error rate > 5% por 5min |
| Attack mode | `http_req_failed < 80%` | — |
| DB queries | — | DB P95 > 200ms por 5min |
