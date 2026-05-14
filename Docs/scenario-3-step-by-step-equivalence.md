# Escenario 3 (muBench) - Ejecución Paso a Paso con Equivalencia Estricta

## Objetivo
Asegurar una postura metodológica estricta para escenario 3:
- Reproducir todo lo técnicamente posible en condiciones comparables a escenarios 1/2.
- Declarar explícitamente lo no posible con muBench nativo (sin rediseño).
- Ajustar benchmark solo cuando sea necesario para no introducir sesgo.

## Veredicto de factibilidad
| Componente | Estado | Justificación |
|---|---|---|
| VUs (1/5/10/20) | Posible | Igual en k6 para los tres escenarios. |
| 6 métricas (avg, p95, err, rps, cpu, mem) | Posible | Mismo pipeline de recolección. |
| Flujo funcional login/profile+DB de S1/S2 | No posible (nativo) | S3 usa topología s0..s7/sdb1 y endpoint de entrada distinto. |
| C1/C2/C3/C4 exactamente iguales a S1/S2 | No posible (nativo) | Manifiestos de S1/S2 están acoplados a auth/api/data y rutas /auth,/api. |
| Equivalencia causal 1:1 entre S3 y S1/S2 | No posible sin rediseño | Cambia topología, rutas y punto de control. |
| Comparación exploratoria de estrés | Posible | Válida si se declara explícitamente como no causal 1:1. |

## Paso 1 - Fijar alcance de equivalencia
1. Declarar equivalencia parcial: misma carga y mismas métricas.
2. Declarar no equivalencia funcional/control-plane.
3. Etiquetar comparación S3 como exploratoria en reportes.

Estado: COMPLETADO.
Evidencia:
- `Docs/scenario-3-equivalence-assessment.md`
- `Docs/three-scenarios-comparison-report.md`

## Paso 2 - Ajuste mínimo necesario del benchmark de S3
### Qué se ajustó
1. Corrección de RPS en `scripts/run-scaling-scenario3.sh`:
   - Antes: `rps = reqs / 60` (incorrecto si DURATION != 60s).
   - Ahora: `rps = reqs / duration_real_segundos`.
2. Parametrización controlada en `Testing/baseline.js`:
   - `BENCH_PROFILE` para distinguir modo nativo vs perfil más estricto.
   - `TARGET_URLS` para permitir lista de endpoints explícitos (si aplica).
   - `THINK_TIME` configurable.

### Por qué era necesario
- Sin corregir RPS, las comparaciones con duraciones distintas introducen error sistemático.
- La parametrización evita forks de script y mantiene trazabilidad de configuración.

### Qué NO se cambió (a propósito)
- El comportamiento por defecto sigue siendo nativo de S3, para no falsear resultados históricos.

Estado: COMPLETADO.

## Paso 3 - Regla de decisión para ajustes adicionales
Aplicar ajuste adicional solo si cumple ambos criterios:
1. Reduce sesgo metodológico real.
2. No simula artificialmente controles inexistentes.

Si no cumple ambos criterios, documentar como no comparable en vez de “emular” equivalencia.

Estado: COMPLETADO (criterio documentado).

## Paso 4 - Qué falta para equivalencia fuerte real
Para una equivalencia 1:1 real, hace falta rediseñar controles sobre topología S3:
1. C1: variantes de entrada sobre gateway/s0.
2. C2: mTLS equivalente para `mubench-advanced`.
3. C3: network policies para grafo s0..s7/sdb1.
4. C4: rate limiting en gateway/mesh (no en api-service inexistente).
5. Repetir matriz completa 12x4 y consolidar.

Estado: PENDIENTE (requiere implementación nueva).

## Avance ejecutado en esta iteración
1. Se implementaron controles adaptados a S3 en:
   - `experiments/05-mubench-advanced/k8s-controls/11-c1-ingress-nginx-s3.yaml`
   - `experiments/05-mubench-advanced/k8s-controls/11-c1-istio-s3.yaml`
   - `experiments/05-mubench-advanced/k8s-controls/11-c1-kong-s3.yaml`
   - `experiments/05-mubench-advanced/k8s-controls/12-c2-istio-mtls-s3.yaml`
   - `experiments/05-mubench-advanced/k8s-controls/13-c3-basic-s3.yaml`
   - `experiments/05-mubench-advanced/k8s-controls/13-c3-strict-s3.yaml`
2. Se ejecutó la matriz completa C1-C4 (12 variantes x 4 VUs) en S3:
   - `Testing/results/scaling_tests/scaling-report_mubench-advanced-controls_20260509_174026.csv`
3. Se consolidó resumen por control/variante:
   - `Testing/results/scaling_tests/scaling-report_mubench-advanced-controls_20260509_174026_summary.csv`

Resultado metodológico:
- Se alcanzó equivalencia operativa de matriz de controles para S3 (misma estructura 12x4 y mismas 6 métricas).
- Sigue sin existir equivalencia funcional estricta 1:1 con S1/S2 (workload y rutas de negocio distintas), por lo que la inferencia causal cruzada sigue limitada.

## Paso 5 - Equivalencia funcional S3<->S2 (modo híbrido)
Para cubrir requisito de misma semántica de negocio (login + create/read de usuarios con persistencia), se agregó un modo paralelo en `mubench-advanced`:
1. Despliegue de `auth-service-s3`, `api-service-s3`, `data-service-s3`, `postgres-s3`.
2. Endpoints equivalentes a S2 en NodePorts dedicados (31184/31181/31182).
3. Validación create+persistencia con consulta SQL en `postgres-s3`.

Artefactos:
- `experiments/05-mubench-advanced/k8s-controls/14-s3-semantic-services.yaml`
- `scripts/setup-scenario3-semantic-equivalent.sh`
- `scripts/validate-scenario3-semantic-persistence.sh`

Estado: COMPLETADO.

## Paso 6 - Separación formal a Escenario 4
La capa funcional equivalente se separa ahora como `Escenario 4` para no mezclarla con el muBench avanzado nativo:
1. Nuevo namespace: `mubench-s4`.
2. Nuevos servicios: `auth-service-s4`, `api-service-s4`, `data-service-s4`, `postgres-s4`.
3. Nuevos puertos NodePort: `32184/32181/32182`.

Artefactos:
- `Docs/scenario-4-equivalence.md`
- `scripts/setup-scenario4-semantic-equivalent.sh`
- `scripts/validate-scenario4-semantic-persistence.sh`

Estado: COMPLETADO.

## Paso 7 - Corrida final de Escenario 4
1. Benchmark ejecutado con `scripts/run-scaling-scenario4-semantic-equivalent.sh`.
2. Reporte final generado:
   - `Testing/results/scaling_tests/scaling-report_s4_20260509_191154.csv`
3. Consolidado de los cuatro escenarios:
   - `Testing/results/scaling_tests/four-scenarios-summary_latest.csv`

Estado: COMPLETADO.

## Mensaje recomendado para presentación
"Escenario 3 es válido para benchmark avanzado de estrés con mismas VUs y métricas, pero no es una réplica causal 1:1 de S1/S2 porque su topología y puntos de control son distintos. Donde no es técnicamente portable con muBench nativo, se declara explícitamente y se evita simular equivalencia."