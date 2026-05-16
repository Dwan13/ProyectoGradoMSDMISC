# Métricas Configuradas — Descripción Completa

> **Fecha:** 2026-05-14  
> **Experimento:** S6 Integrated Dual-Mode  
> **Total métricas primarias:** 6

---

## Visión General

Las 6 métricas primarias se dividen en dos grupos:

| Grupo | Métricas | Origen | Alcance |
|-------|----------|--------|---------|
| Rendimiento (k6) | avg_ms, p95_ms, err_pct, rps | k6 HTTP metrics → NDJSON | Por corrida (60 s de carga) |
| Recursos (Prometheus) | cpu_mcores, mem_mib | node-exporter / cAdvisor | Promedio durante la corrida |

---

## Métrica 1 — `avg_ms` (Latencia Media)

### ¿Cuál es?
Media aritmética del tiempo de respuesta HTTP en milisegundos.

### ¿Por qué?
Es el indicador más intuitivo de experiencia de usuario. Un aumento en `avg_ms` indica degradación de servicio. En este experimento, valida si el control de seguridad introduce overhead de latencia en el camino crítico.

### ¿Cómo se obtiene?
- k6 mide cada petición HTTP con precisión de microsegundos usando la métrica interna `http_req_duration`
- Al finalizar la corrida, k6 emite un objeto JSON `Point` con `metric="http_req_duration"` y `type="Point"`
- El script `Testing/extract_clean_metrics.py` extrae el valor `data.value` donde `data.name == "http_req_duration"` y `data.tags.stat == "avg"` del NDJSON de cada corrida

### ¿Dónde se almacena?
- Raw: `Testing/results/auto_runs/randomized_campaigns/*.json` (NDJSON, una línea por evento de métrica)
- Consolidado: columna `avg_ms` en `Testing/results/s6_integrated_all_6_metrics.csv`

### Alcance
- Incluye **todas** las peticiones HTTP de la corrida: login, profile, users y (en modo attack) probes de ataque
- Unidad: milisegundos (ms)
- Rango observado: 3.8 ms (C1/kong/1VU/normal) — 1,306 ms (C3/strict/20VU, red bloqueada)

---

## Métrica 2 — `p95_ms` (Percentil 95 de Latencia)

### ¿Cuál es?
El percentil 95 de la distribución de tiempos de respuesta: el 95% de las peticiones tardaron menos que este valor.

### ¿Por qué?
La media puede ocultar picos de latencia (long tails). El P95 captura el "peor caso típico" experimentado por los usuarios. SLA comunes especifican P95 < 200-500 ms. En este experimento, el threshold configurado en k6 es `p(95) < 700ms`.

### ¿Cómo se obtiene?
- Igual que `avg_ms` pero extrayendo `data.tags.stat == "p(95)"` del objeto `http_req_duration` en el NDJSON
- k6 calcula el percentil al final de la corrida sobre el histograma completo

### ¿Dónde se almacena?
- Raw: mismos NDJSON que `avg_ms`
- Consolidado: columna `p95_ms` en el CSV consolidado

### Alcance
- Unidad: milisegundos (ms)
- Rango observado: 14 ms — 3,013 ms (C3/strict)
- Threshold de alerta PrometheusRule: P95 > 400 ms por 5 min → warning

---

## Métrica 3 — `err_pct` (Porcentaje de Error HTTP)

### ¿Cuál es?
Porcentaje de peticiones HTTP que terminaron con código de error (4xx/5xx) sobre el total de peticiones.

### ¿Por qué?
Mide la disponibilidad efectiva del servicio. En modo `normal`, un `err_pct` alto indica que el control de seguridad bloquea tráfico legítimo (falsos positivos). En modo `attack`, un `err_pct` alto es **esperado** porque los ataques reciben 401/403/429.

**Nota importante:** En modo attack, `err_pct` es una métrica contaminada porque mezcla errores legítimos con bloqueos de ataque. Por ello se derivan dos métricas limpias en el análisis:
- `legitimate_error_pct`: errores en tráfico legítimo (login_fail + profile_fail + users_fail) / total_legítimo
- `attack_blocked_pct`: porcentaje de probes de ataque correctamente bloqueadas

### ¿Cómo se obtiene?
- k6 métrica interna: `http_req_failed` (boolean counter)
- Del NDJSON: `metric=="http_req_failed"`, `data.value` = tasa de fallos
- Multiplicado × 100 para expresar como porcentaje

### ¿Dónde se almacena?
- Columna `err_pct` en CSV consolidado
- Threshold k6: `rate < 0.05` en modo normal; `rate < 0.80` en modo attack

### Alcance
- Unidad: % (0–100)
- Normal mode: rango 0–0.5% (ideal); C3/strict produce 0% porque las peticiones simplemente timeout
- Attack mode: rango 33–70% (reflexión del porcentaje de probes en el mix de tráfico)

---

## Métrica 4 — `rps` (Requests Per Second)

### ¿Cuál es?
Throughput del sistema: número de peticiones HTTP completadas por segundo.

### ¿Por qué?
Cuantifica la capacidad de servicio real bajo carga. Un `rps` bajo indica throttling (C4/strict), saturación de recursos (CPU), o bloqueo de red (C3/strict). Permite correlacionar el número de VUS con el throughput real obtenido.

### ¿Cómo se obtiene?
- k6 métrica interna: `http_reqs` (counter)
- Del NDJSON: `metric=="http_reqs"`, `data.value` = tasa en req/s
- Extraído del aggregate final de la corrida

### ¿Dónde se almacena?
- Columna `rps` en CSV consolidado

### Alcance
- Unidad: req/s
- Rango observado: 8.9 rps (C3/strict/1VU) — 131 rps (C1/kong/20VU/normal)
- Incluye **todas** las peticiones: legítimas + probes de ataque en modo attack
- En modo attack, el mix es ≈ 70% legítimas + 30% probes (varía según ATTACK_PROFILE)

---

## Métrica 5 — `cpu_mcores` (Consumo de CPU en Millicores)

### ¿Cuál es?
Consumo medio de CPU de todos los pods del namespace `mubench-real` durante la ventana de carga, expresado en millicores (1 core = 1,000 millicores).

### ¿Por qué?
El overhead de CPU es el principal costo operativo de controles como mTLS (encriptación/desencriptación) e inspección de paquetes. Permite calcular el costo por request adicional de cada control.

### ¿Cómo se obtiene?
- Fuente: Prometheus + cAdvisor (MicroK8s incluye cAdvisor embebido)
- Query PromQL: `sum(rate(container_cpu_usage_seconds_total{namespace="mubench-real"}[1m])) * 1000`
- El script de campaña ejecuta esta query al final de cada corrida y almacena el valor en el NDJSON

### ¿Dónde se almacena?
- Columna `cpu_mcores` en CSV consolidado

### Alcance
- Scope: **todos los pods** del namespace `mubench-real` (auth-service + api-service + data-service + postgres + sidecars Istio/Linkerd si están presentes)
- Unidad: millicores
- Rango observado: 29 mcores (C3/strict, tráfico bloqueado → idle) — 683 mcores (C3/basic/20VU)
- El overhead de Istio sidecar es ≈ +95 mcores por pod en reposo

---

## Métrica 6 — `mem_mib` (Consumo de Memoria en MiB)

### ¿Cuál es?
Consumo medio de memoria RSS de todos los pods del namespace `mubench-real` durante la ventana de carga, en Mebibytes (MiB).

### ¿Por qué?
La memoria es un recurso más estático que CPU pero visible en controles que añaden sidecars (Istio +163 MiB, Linkerd +12 MiB). Permite dimensionar correctamente los nodos antes del despliegue de controles de seguridad.

### ¿Cómo se obtiene?
- Fuente: Prometheus + cAdvisor
- Query PromQL: `sum(container_memory_rss{namespace="mubench-real"}) / 1024 / 1024`
- Almacenado igual que `cpu_mcores`

### ¿Dónde se almacena?
- Columna `mem_mib` en CSV consolidado

### Alcance
- Scope: todos los pods del namespace `mubench-real`
- Unidad: MiB
- Rango observado: 159 MiB — 342 MiB
- C2/istio-mtls: +163 MiB sobre baseline (3 sidecars Envoy × ≈ 54 MiB cada uno)
- C2/linkerd-mtls: +12 MiB sobre baseline (proxies Rust más ligeros)

---

## Métricas Derivadas (análisis limpio, S6)

Además de las 6 métricas primarias, `Testing/extract_clean_metrics.py` genera:

| Métrica derivada | Descripción | Columna CSV |
|-----------------|-------------|-------------|
| `legitimate_error_pct` | % errores en tráfico legítimo exclusivamente | `legitimate_error_pct` |
| `attack_blocked_pct` | % probes de ataque bloqueadas | `attack_blocked_pct` |
| `attack_blocked_pct_counter` | Basada en contador k6 `attack_blocked_total` | `attack_blocked_pct_counter` |
| `attack_blocked_pct_inferred` | Inferida desde balance de masa de err_pct | `attack_blocked_pct_inferred` |
| `false_positive_rate` | Tráfico legítimo incorrectamente bloqueado | `false_positive_rate` |
| `security_posture` | Clasificación: STRONG / ADEQUATE / WEAK | `security_posture` |

---

## Tabla Resumen de Métricas

| # | Nombre | Fuente | Herramienta | Unidad | Tipo |
|---|--------|--------|-------------|--------|------|
| 1 | avg_ms | http_req_duration (avg) | k6 | ms | Latencia |
| 2 | p95_ms | http_req_duration (p95) | k6 | ms | Latencia |
| 3 | err_pct | http_req_failed (rate×100) | k6 | % | Disponibilidad |
| 4 | rps | http_reqs (rate) | k6 | req/s | Throughput |
| 5 | cpu_mcores | container_cpu_usage_seconds_total | Prometheus/cAdvisor | mcores | Recurso |
| 6 | mem_mib | container_memory_rss | Prometheus/cAdvisor | MiB | Recurso |
