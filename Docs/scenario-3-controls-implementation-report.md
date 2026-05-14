# Escenario 3 - Implementación de Controles y Justificación Técnica

## Alcance
Este reporte documenta la implementación y ejecución de controles C1-C4 adaptados para topología muBench avanzada (`mubench-advanced`) con servicios `s0..s7` y `sdb1`.

## Artefactos implementados
### Runner de matriz completa
- `scripts/run-scaling-scenario3-controls.sh`

### Manifiestos de control adaptados
- `experiments/05-mubench-advanced/k8s-controls/11-c1-ingress-nginx-s3.yaml`
- `experiments/05-mubench-advanced/k8s-controls/11-c1-istio-s3.yaml`
- `experiments/05-mubench-advanced/k8s-controls/11-c1-kong-s3.yaml`
- `experiments/05-mubench-advanced/k8s-controls/12-c2-istio-mtls-s3.yaml`
- `experiments/05-mubench-advanced/k8s-controls/13-c3-basic-s3.yaml`
- `experiments/05-mubench-advanced/k8s-controls/13-c3-strict-s3.yaml`

## Ejecución completa
- CSV completo (48 filas):
  - `Testing/results/scaling_tests/scaling-report_mubench-advanced-controls_20260509_174026.csv`
- Resumen agregado:
  - `Testing/results/scaling_tests/scaling-report_mubench-advanced-controls_20260509_174026_summary.csv`

Cobertura:
- 12 variantes: C1(3), C2(3), C3(3), C4(3).
- 4 niveles de carga: 1, 5, 10, 20 VUs.
- 6 métricas: avg_ms, p95_ms, err_pct, rps, cpu_mcores, mem_mib.

## Qué fue técnicamente posible
1. C1 baseline/istio/kong con enrutamiento de entrada a `/s0`.
2. C2 istio-mtls y linkerd-mtls sobre workloads S3.
3. C3 basic/strict como políticas de red sobre `s0..s7/sdb1`.
4. C4 baseline/moderate/strict como limitación de tasa en `gw-nginx`.

## Qué NO es 1:1 con escenarios 1/2 y por qué
1. C4 no usa `api-service` (inexistente en S3):
   - Se reemplazó por rate limiting en gateway NGINX.
2. C2 istio-mtls requirió excepción para benchmark externo:
   - `PeerAuthentication` PERMISSIVE en `gw-nginx` para tráfico HTTP de entrada.
   - mTLS STRICT se mantiene para el resto del namespace.
3. Flujo funcional distinto:
   - S1/S2 evalúan login/profile/CRUD sobre auth/api/data.
   - S3 evalúa grafo generado `s0..s7/sdb1`.

## Conclusión metodológica
Se logró equivalencia operativa de diseño experimental para S3 (misma matriz y métricas), pero no equivalencia funcional causal estricta 1:1 frente a S1/S2.

Para defensa académica, la comparación con S3 debe enmarcarse como:
- Comparable en estructura de experimento y observabilidad.
- No completamente equivalente en semántica de negocio ni en mecanismo interno exacto de algunos controles.

## Modo adicional: S3 con semántica equivalente a S2
Para cubrir exigencia de equivalencia funcional create/read de usuarios, se implementó un modo híbrido dentro de `mubench-advanced` con servicios paralelos:
- Manifiesto: `experiments/05-mubench-advanced/k8s-controls/14-s3-semantic-services.yaml`
- Setup: `scripts/setup-scenario3-semantic-equivalent.sh`
- Validación de persistencia: `scripts/validate-scenario3-semantic-persistence.sh`

Endpoints del modo equivalente:
- Auth: `http://127.0.0.1:31184/login`
- API: `http://127.0.0.1:31181/users`

Resultado validado:
- Se creó un usuario en API S3 equivalente y se confirmó persistencia en `postgres-s3` (`app_users`).

Alcance y limitación:
- Este modo sí permite equivalencia funcional con S2 para operaciones de usuarios y persistencia.
- No representa la semántica nativa del grafo generado `s0..s7/sdb1`; es una capa de equivalencia para comparación académica 1:1.

## Separación formal como Escenario 4
Para evitar mezclar la semántica nativa avanzada con la capa funcional equivalente, este modo se promueve formalmente a `Escenario 4`:
- Documento: `Docs/scenario-4-equivalence.md`
- Setup: `scripts/setup-scenario4-semantic-equivalent.sh`
- Validación: `scripts/validate-scenario4-semantic-persistence.sh`

Corrida final de S4:
- Benchmark: `scripts/run-scaling-scenario4-semantic-equivalent.sh`
- Reporte: `Testing/results/scaling_tests/scaling-report_s4_20260509_191154.csv`

Conclusión práctica:
- S3 queda reservado para muBench avanzado nativo.
- S4 queda reservado para equivalencia funcional 1:1 con S2.
