# Sección de Seguridad — Evaluación de Efectividad de Controles (S6)

> **Fecha:** 2026-05-14  
> **Escenario:** S6 Integrated Dual-Mode  
> **Estado:** En validación previa a corrida final  
> **Nota:** Esta sección es independiente del análisis de rendimiento (S2). No modifica los datos S2.

---

## 1. Modelo de Amenaza

### 1.1 Contexto y Superficie de Ataque

**Aplicación evaluada:** Sistema de microservicios para gestión de usuarios con autenticación JWT.

**Activos críticos:**
| Activo | Clasificación | Ubicación |
|--------|--------------|-----------|
| Credenciales de usuario (username/password) | CRÍTICO | PostgreSQL `users.password_hash` |
| Tokens JWT activos | ALTO | En tránsito + memoria de servicios |
| Datos de perfil de usuario | ALTO | PostgreSQL `users.*` |
| Listado completo de usuarios | MEDIO | API `/api/users` |
| Configuración del servicio | MEDIO | Variables de entorno k8s |

**Actores de amenaza considerados:**
1. **Atacante externo no autenticado** — Acceso solo a través del API Gateway público
2. **Atacante con JWT robado (insider/token leak)** — Tiene un token válido de otro usuario
3. **Atacante con JWT expirado (replay)** — Intenta reutilizar token después de expiración

---

### 1.2 Vectores de Ataque Implementados

#### Vector 1 — Credential Stuffing / Brute Force (CWE-287, OWASP A07:2021)
**Clasificación:** CRITICAL

| Atributo | Valor |
|----------|-------|
| Técnica | Enviar credenciales incorrectas repetidamente |
| Request | `POST /auth/login` con `password: "wrong-password"` |
| Objetivo | Enumerar usuarios válidos; fuerza bruta de contraseñas |
| Respuesta esperada del sistema seguro | HTTP 401 (sin información diferencial) |
| Respuesta que indicaría vulnerabilidad | HTTP 200 o diferencia de timing entre usuario válido/inválido |
| Probe ID en k6 | `bad_login` |
| CWE | CWE-287 (Improper Authentication) |
| OWASP Top 10 | A07:2021 — Identification and Authentication Failures |

---

#### Vector 2 — Acceso No Autenticado a Datos (CWE-639, OWASP A01:2021)
**Clasificación:** CRITICAL

| Atributo | Valor |
|----------|-------|
| Técnica | Petición a endpoint protegido sin cabecera Authorization |
| Request | `GET /api/users?limit=5` (sin Bearer token) |
| Objetivo | Obtener listado de usuarios sin autenticación |
| Respuesta esperada | HTTP 401 |
| Respuesta vulnerable | HTTP 200 con datos |
| Probe ID | `unauth_users` |
| CWE | CWE-639 (Authorization Bypass Through User-Controlled Key) |
| OWASP | A01:2021 — Broken Access Control |

---

#### Vector 3 — Inyección de JWT Manipulado (CWE-347, OWASP A02:2021)
**Clasificación:** HIGH  
**Solo en ATTACK_PROFILE=advanced**

| Atributo | Valor |
|----------|-------|
| Técnica | Enviar token con firma inválida |
| Request | `GET /api/profile` con `Authorization: Bearer tampered.invalid.token` |
| Objetivo | Verificar que el servicio valida la firma JWT (no solo el formato) |
| Respuesta esperada | HTTP 401 |
| Respuesta vulnerable | HTTP 200 (firma no verificada) |
| Probe ID | `tampered_bearer` |
| CWE | CWE-347 (Improper Verification of Cryptographic Signature) |
| OWASP | A02:2021 — Cryptographic Failures |

---

#### Vector 4 — Fuzzing de Header Authorization (CWE-20, OWASP A03:2021)
**Clasificación:** MEDIUM  
**Solo en ATTACK_PROFILE=advanced**

| Atributo | Valor |
|----------|-------|
| Técnica | Enviar cabecera `Authorization: Bearer` (sin token) |
| Request | `GET /api/users` con `Authorization: Bearer` (string vacío post-scheme) |
| Objetivo | Verificar manejo seguro de input malformado; evitar panic/500 |
| Respuesta esperada | HTTP 401 (sin error 500) |
| Respuesta vulnerable | HTTP 500 (crash por input no validado) |
| Probe ID | `malformed_bearer` |
| CWE | CWE-20 (Improper Input Validation) |
| OWASP | A03:2021 — Injection |

---

#### Vector 5 — Spoofing de IP via X-Forwarded-For (CWE-923, OWASP A05:2021)
**Clasificación:** MEDIUM  
**Solo en ATTACK_PROFILE=advanced (3 variantes)**

| Variante | X-Forwarded-For header |
|----------|----------------------|
| Simple | `1.2.3.4` |
| Chain | `10.20.30.40, 44.55.66.77` |
| Complex | `203.0.113.5, 198.51.100.2, 192.0.2.8` |

| Atributo | Valor |
|----------|-------|
| Técnica | Spoofear IP de origen vía header XFF + token inválido |
| Objetivo | Verificar que el rate limiter/WAF no es bypasseable vía XFF |
| Respuesta esperada | HTTP 401 (ignorar XFF para auth; no bypass de rate limit) |
| Respuesta vulnerable | HTTP 200 (XFF trusted para bypass de IP-based controls) |
| Probe ID | `xff_spoof_chain` |
| CWE | CWE-923 (Improper Restriction of Communication Channel) |
| OWASP | A05:2021 — Security Misconfiguration |

---

### 1.3 Resumen del Modelo de Amenaza

```
         Severidad
CRÍTICO  [CWE-287 bad_login] [CWE-639 unauth_users]
ALTO     [CWE-347 tampered_bearer]
MEDIO    [CWE-20 malformed_bearer] [CWE-923 xff_spoof × 3]
BAJO     —
```

**Total de probes por iteración en ADVANCED:**
- 2 probes básicos (siempre activos)
- 5 probes avanzados (solo `ATTACK_PROFILE=advanced`): tampered_bearer + malformed_bearer + xff×3
- **Total: 7 probes de ataque por iteración de VU**

---

## 2. Métricas de Seguridad (S6)

### 2.1 Definición de Éxito de Bloqueo

Un ataque es considerado **bloqueado exitosamente** si el servicio responde con:
- HTTP `401` Unauthorized
- HTTP `403` Forbidden  
- HTTP `429` Too Many Requests

Cualquier respuesta 2xx en respuesta a un probe de ataque indica **vulnerabilidad confirmada**.

### 2.2 Métricas Calculadas

| Métrica | Definición | Fórmula | CSV column |
|---------|-----------|---------|-----------|
| `attack_blocked_pct` | % de probes bloqueados | `blocked / attempted × 100` | `attack_blocked_pct` |
| `attack_blocked_pct_counter` | Basada en contador k6 | `attack_blocked_total / attack_vector_attempts_total × 100` | `attack_blocked_pct_counter` |
| `attack_blocked_pct_inferred` | Inferida desde balance de masa | `(err_pct_attack - err_pct_normal_expected) / attack_traffic_fraction × 100` | `attack_blocked_pct_inferred` |
| `legitimate_error_pct` | % errores en tráfico legítimo | `(login_fail + profile_fail + users_fail) / legit_total × 100` | `legitimate_error_pct` |
| `false_positive_rate` | Tráfico legítimo bloqueado | `legitimate_error_pct` | `false_positive_rate` |
| `security_posture` | Clasificación | STRONG/ADEQUATE/WEAK | `security_posture` |

**Criterios de clasificación `security_posture`:**
```
STRONG:   attack_blocked_pct ≥ 80% AND legitimate_error_pct ≤ 5%
ADEQUATE: attack_blocked_pct ≥ 50% AND legitimate_error_pct ≤ 10%
WEAK:     attack_blocked_pct < 50% OR legitimate_error_pct > 10%
```

---

## 3. Resultados de Seguridad (Datos S6 Actuales)

### 3.1 Resumen por Control y Modo

| Control | Variante | Modo | avg_ms | err_pct | legitimate_err% | attack_blocked% | posture |
|---------|----------|------|--------|---------|----------------|----------------|---------|
| C1 | baseline | normal | ~10.5 | ~0.0% | ~0.0% | — | STRONG |
| C1 | baseline | attack | ~10.5 | ~35.0% | ~0.01% | ~100% (inferred) | STRONG |
| C1 | kong | normal | ~5.5 | ~0.0% | ~0.0% | — | STRONG |
| C1 | kong | attack | ~5.5 | ~35.0% | ~0.01% | ~100% (inferred) | STRONG |
| C2 | istio-mtls | normal | ~14.2 | ~0.0% | ~0.0% | — | STRONG |
| C2 | istio-mtls | attack | ~14.2 | ~35.0% | ~0.01% | ~100% (inferred) | STRONG |
| C3 | strict | normal | ~1306 | ~0.0% | ~0.0% | — | N/A (red bloqueada) |
| C3 | strict | attack | ~1306 | ~78.3% | ~0.0% | — | N/A (red bloqueada) |
| C4 | moderate | normal | ~10.5 | ~0.0% | ~0.0% | — | STRONG |
| C4 | strict | attack | ~10.3 | ~35.0% | ~0.01% | ~100% (inferred) | STRONG |

### 3.2 Hallazgo Principal: Preservación del Tráfico Legítimo

```
legitimate_error_pct (modo attack, todos los controles):
  Media:   0.0144%   (≈ 1.4 peticiones fallidas por cada 10,000 legítimas)
  Máximo:  0.5%
```

**Interpretación:** Bajo ataque, el sistema mantiene el tráfico legítimo prácticamente intacto. Los falsos positivos (tráfico legítimo bloqueado por los controles) son despreciables.

### 3.3 Advertencia Metodológica Sobre `attack_blocked_pct`

**Problema conocido:** Los datos actuales (385 NDJSON de corridas existentes) fueron generados con una versión **anterior** del script k6 que tenía un bug: `attackBlockedTotal.add()` solo se emitía para los 2 primeros vectores en modo `basic`.

```
attack_blocked_pct_counter (actual):  26.19%  ← SUBESTIMADO por bug pre-fix
attack_blocked_pct_inferred (actual): 100.0%  ← Calculado desde balance de masa de err_pct
```

**Decisión metodológica:** Se usa `attack_blocked_pct_inferred` para los datos actuales porque es más consistente con la evidencia empírica (todos los 401/403/429 son contabilizados).

**La corrida final** (con el script corregido) producirá `attack_blocked_pct_counter` consistente con el valor inferido, eliminando esta discrepancia.

---

## 4. Efectividad de Bloqueo por Vector (Inferida)

Los 401/403 observados en modo attack provienen de:

| Vector | CWE | Bloqueado por | Código HTTP | Evidencia |
|--------|-----|--------------|-------------|----------|
| bad_login | CWE-287 | auth-service (password validation) | 401 | `login_fail_total` counter |
| unauth_users | CWE-639 | api-service (JWT middleware) | 401 | err_pct en modo attack |
| tampered_bearer | CWE-347 | api-service (JWT signature validation) | 401 | err_pct en modo attack |
| malformed_bearer | CWE-20 | api-service (Authorization header parser) | 401 | err_pct en modo attack |
| xff_spoof × 3 | CWE-923 | api-service (token still invalid) | 401 | err_pct en modo attack |

**Nota sobre C4 (Rate Limiting) y ataques:** El rate limiter también puede generar 429 para los probes de ataque si el volumen total supera el threshold configurado, añadiendo una capa de defensa en profundidad.

---

## 5. Cobertura OWASP Top 10 2021

| OWASP Category | Cubierto | Vectores | Resultado |
|---------------|---------|---------|-----------|
| A01 — Broken Access Control | ✅ | unauth_users, tampered_bearer | BLOQUEADO |
| A02 — Cryptographic Failures | ✅ | tampered_bearer (JWT sig) | BLOQUEADO |
| A03 — Injection | ✅ | malformed_bearer (input fuzzing) | BLOQUEADO |
| A04 — Insecure Design | ⚠️ | No testeable con probes HTTP | N/A |
| A05 — Security Misconfiguration | ✅ | xff_spoof (header trust) | BLOQUEADO |
| A06 — Vulnerable Components | ❌ | No testeable en este benchmark | N/A |
| A07 — Auth Failures | ✅ | bad_login (brute force) | BLOQUEADO |
| A08 — Software Integrity | ❌ | Fuera del scope de k6 | N/A |
| A09 — Logging & Monitoring | ⚠️ | Prometheus alertas configuradas | PARCIAL |
| A10 — SSRF | ❌ | No testeable con probes actuales | N/A |

**Cobertura efectiva:** 5/10 categorías OWASP testeadas directamente.

---

## 6. Defensa en Profundidad

El sistema implementa múltiples capas de control:

```
┌─────────────────────────────────────────────────────┐
│  Capa 1: API Gateway (C1)                           │
│  → TLS termination, routing, opcionalmente WAF/JWT  │
├─────────────────────────────────────────────────────┤
│  Capa 2: Rate Limiting (C4)                         │
│  → Protección contra volumen (DDoS, brute-force)   │
├─────────────────────────────────────────────────────┤
│  Capa 3: Autenticación JWT (auth-service)           │
│  → Validación de credenciales + emisión de tokens  │
├─────────────────────────────────────────────────────┤
│  Capa 4: Autorización JWT (api-service middleware)  │
│  → Validación de firma + claims en cada request    │
├─────────────────────────────────────────────────────┤
│  Capa 5: mTLS inter-servicio (C2)                   │
│  → Encriptación + autenticación mutua East-West    │
├─────────────────────────────────────────────────────┤
│  Capa 6: Network Policy (C3)                        │
│  → Micro-segmentación: pods solo hablan con lo      │
│     necesario (data-service solo accesible          │
│     desde api-service, postgres solo desde data)   │
└─────────────────────────────────────────────────────┘
```

---

## 7. Pendiente: Corrida Final (Post-Validación)

### Items a validar antes de la corrida:
- [ ] Verificar que `attack_blocked_pct_counter` con el script corregido produce valores ≥ 80%
- [ ] Confirmar que `legitimate_error_pct` permanece < 1% en todos los controles
- [ ] Verificar que la corrida final produce exactamente 384 nuevas filas en el CSV
- [ ] Ejecutar `validate_environment.sh` para confirmar que todos los servicios están up

### Comando de corrida final:
```bash
cd /home/dwan13/muBench

# 1. Verificar entorno
bash scripts/verify-s6-integrated-config.sh

# 2. Corrida real
bash scripts/run-s6-integrated-repro.sh --execute

# 3. Análisis post-corrida
python3 Testing/extract_clean_metrics.py
python3 Testing/s6_statistical_analysis_rigorous.py

# 4. Validar que attack_blocked_pct_counter ≈ inferred
python3 -c "
import pandas as pd
df = pd.read_csv('Testing/results/s6_integrated_clean_metrics.csv')
attack = df[df.security_mode=='attack']
print('counter:', attack.attack_blocked_pct_counter.mean().round(2), '%')
print('inferred:', attack.attack_blocked_pct_inferred.mean().round(2), '%')
print('OK' if abs(attack.attack_blocked_pct_counter.mean() - attack.attack_blocked_pct_inferred.mean()) < 20 else 'DISCREPANCY')
"
```

### Gates de calidad esperados post-corrida:
| Gate | Condición | Valor objetivo |
|------|-----------|---------------|
| Blocking effectiveness | `attack_blocked_pct_counter` | ≥ 80% |
| False positive rate | `legitimate_error_pct` | ≤ 1% |
| Counter-inferred consistency | `|counter - inferred|` | ≤ 10pp |
| Security posture | `security_posture` | STRONG (todas las filas de attack) |
