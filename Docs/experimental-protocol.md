# Protocolo Cerrado de Experimentacion (Sin Sesgo)

Este protocolo asegura comparabilidad entre controles (C1-C4) sin mezclar evaluacion de rendimiento con validacion funcional de cada control.

## 1) Regla Principal

- Misma carga, mismo entorno, mismo flujo, mismo criterio temporal para todos los controles.
- Separar resultados en dos capas:
  - Capa A: comparacion comun (latencia, throughput, error, CPU, memoria).
  - Capa B: validacion funcional del control (ej. rate limiting debe generar 429).

## 2) Congelar Configuracion Antes de Correr

No cambiar estos puntos durante la campana:

- Script de carga: `RealisticServices/k6/realistic-flow.js`
- Runner: `scripts/run-all-controls-experiments.sh`
- Duracion por escenario: 60s
- VUs: valor fijo por ronda (ej. 1, luego 5, luego 10 en rondas separadas)
- Ventanas de Prometheus
- Version de manifiestos por control

Si algo cambia, crear nueva campana (nuevo ID de corrida) y no mezclar resultados.

## 3) Condiciones Identicas de Ejecucion

Para cada escenario:

- Aplicar config del control
- Esperar `rollout status` de `auth-service`, `data-service`, `api-service`
- Iniciar medicion solo cuando los pods esten Ready
- Ejecutar k6 con mismo comando base
- Guardar salida NDJSON + resumen Prometheus

## 4) Metricas Que Siempre Se Comparan (Capa A)

Comparar estas metricas entre todos los controles:

- `http_req_duration` (avg, p95)
- `http_req_failed` (porcentaje total)
- `http_reqs` o RPS efectivo
- CPU total (mcores) por ventana del experimento
- Memoria total (MiB) por ventana del experimento

Adicional recomendado:

- Tasa por codigo HTTP: 2xx, 4xx, 5xx

## 5) Validacion Funcional por Control (Capa B)

No usar una sola regla de pass/fail para todos los controles.

- C1 API Gateway:
  - Verificar enrutamiento correcto (`/auth` y `/api`)
  - Error 5xx bajo
- C2 Service Mesh mTLS:
  - Verificar sidecar/inyeccion esperada por variante
  - Exito de llamadas entre servicios
- C3 Network Policies:
  - Verificar que trafico permitido funciona y trafico no permitido queda bloqueado
- C4 Rate Limiting:
  - Verificar presencia de 429 cuando se supera el limite
  - 429 esperado no equivale a fallo del experimento

## 6) Sobre Thresholds (Para No Sesgar)

- Definir thresholds antes de la corrida.
- No ajustar thresholds despues de ver resultados de esa misma campana.
- Mantener dos resultados en el reporte:
  - Resultado numerico crudo (principal)
  - Estado de thresholds (secundario)

## 7) Diseno Estadistico Minimo

- Repeticiones por escenario: minimo 3 (ideal 5)
- Reportar mediana y p95 por escenario
- Reportar dispersion (min-max o IQR)
- No concluir por una sola corrida

## 8) Plantilla de Tabla Final (Capa A)

Usar esta tabla para comparacion principal:

| Control | Variante | VUs | avg_ms | p95_ms | err_% | rps | CPU_mcores | Mem_MiB |
|---|---|---:|---:|---:|---:|---:|---:|---:|

## 9) Plantilla de Tabla Funcional (Capa B)

| Control | Variante | Validacion esperada | Resultado | Evidencia |
|---|---|---|---|---|

Ejemplos de evidencia:

- C2: pod con sidecar presente/ausente
- C3: politica aplicada y flujo bloqueado/permitido
- C4: conteo de 429 en ventana de carga

## 10) Reglas de Reporte

- Conclusiones de rendimiento solo desde Capa A.
- Conclusiones de comportamiento de control desde Capa B.
- Si un control reduce throughput por diseno (ej. rate limit), reportarlo como trade-off, no como "falla".

## 11) Checklist Operativo Rapido

Antes de correr:

- [ ] Cluster estable
- [ ] Prometheus activo y scrapeando servicios
- [ ] Configuracion congelada para la campana
- [ ] Endpoints de cada escenario validados

Despues de correr:

- [ ] 12/12 escenarios ejecutados
- [ ] CSV de Prometheus generado
- [ ] Tabla Capa A completada
- [ ] Tabla Capa B completada
- [ ] Notas de incidentes anexadas (timeouts/restarts)

---

Aplicando este protocolo, comparar "en las mismas condiciones" si es posible y defendible, sin sesgo metodologico.
