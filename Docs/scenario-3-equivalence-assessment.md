# Evaluación de Equivalencia: Escenario 3 vs Escenarios 1 y 2

## Resumen ejecutivo
No es técnicamente equivalente ejecutar el mismo experimento (mismas operaciones de negocio y mismos controles C1-C4 tal como se implementaron en escenarios 1/2) sobre escenario 3 sin rediseñar los controles para la topología avanzada.

Sí se puede replicar parcialmente la metodología (escalado VU y 6 métricas), pero no la semántica experimental completa de controles y flujo funcional.

## Qué sí fue equivalente
- Escalado por VU: 1, 5, 10, 20.
- Métricas recolectadas: avg_ms, p95_ms, err_pct, rps, cpu_mcores, mem_mib.
- Entorno aislado por namespace (mubench-advanced).
- Prueba de estrés repetible con k6.

## Qué NO fue equivalente (y por qué)

### 1) Flujo funcional de negocio
Escenarios 1/2 usan login/profile y CRUD sobre auth/api/data con JWT.
Escenario 3 usa endpoints generados por muBench (s0..s7, sdb1), típicamente via /s0.

Implicación: no son las mismas operaciones de aplicación; por tanto no hay comparabilidad causal 1:1 de latencia funcional.

### 2) Controles C1-C4 de 1/2 no aplican directamente a 3
Los manifiestos de controles existentes están acoplados a auth-service, api-service, data-service y rutas /auth, /api.
En escenario 3 esos servicios/rutas no existen.

Evidencia:
- Manifiestos de controles con acoplamiento a auth/api/data:
  - [RealisticServices/k8s/07-c1-ingress-gateway.yaml](RealisticServices/k8s/07-c1-ingress-gateway.yaml)
  - [RealisticServices/k8s/08-c3-networkpolicy.yaml](RealisticServices/k8s/08-c3-networkpolicy.yaml)
  - [RealisticServices/k8s/03-services-real.yaml](RealisticServices/k8s/03-services-real.yaml)
- Servicios reales en escenario 3 (s0..s7, sdb1):
  - [scripts/setup-scenario3-mubench-advanced.sh](scripts/setup-scenario3-mubench-advanced.sh)

### 3) C4 (rate limit) no portable tal cual
En 1/2 C4 se implementa manipulando variables de entorno de api-service (RATE_LIMIT_ENABLED, RATE_LIMIT_RPM).
En escenario 3 no existe api-service.

Conclusión técnica: C4 no se puede "copiar y pegar"; hay que rediseñar un mecanismo equivalente para gw-nginx/s0 (ej. anotaciones de ingress o filtro de mesh).

### 4) Observabilidad de reglas/alertas no equivalente
Reglas y monitores de RealisticServices están centrados en labels de auth/api/data.
Para escenario 3 (s0..s7/sdb1) se necesitan reglas específicas nuevas.

## Nivel de equivalencia alcanzado
- Equivalencia de carga y métricas: Alta.
- Equivalencia de operaciones de negocio: Baja.
- Equivalencia de implementación de controles C1-C4: Baja (sin rediseño).
- Equivalencia estadística total frente a 1/2: No alcanzada.

## Qué sería necesario para equivalencia total
1. Redefinir C1-C4 sobre topología s0..s7/sdb1:
   - C1: variantes gateway para entrada a s0.
   - C2: mTLS mesh en namespace mubench-advanced con políticas de tráfico equivalentes.
   - C3: netpol baseline/basic/strict para grafo s0..s7/sdb1.
   - C4: rate limiting sobre gateway o sidecar para tráfico hacia s0.
2. Definir flujo funcional análogo (equivalente en complejidad) al login/profile+DB de 1/2.
3. Repetir matriz completa 12x4 (3 variantes por control x 4 controles x 4 VUs).

## Justificación para presentación
Es correcto afirmar que escenario 3 actual es un benchmark avanzado válido de estrés, pero no una réplica 1:1 de escenarios 1/2 por incompatibilidad de control-plane y de endpoints funcionales.

Se hizo lo máximo técnicamente portable sin falsear equivalencia. La comparación de los tres escenarios debe presentarse como comparativa exploratoria, no causal estricta entre controles C1-C4.
