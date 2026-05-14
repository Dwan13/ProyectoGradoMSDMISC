# Escenario 4 - Equivalencia Funcional Separada para Comparación con S2

## Propósito
Escenario 4 representa la capa que originalmente se había promovido como "S3 equivalente", pero separada formalmente para evitar confusión con el muBench avanzado nativo.

## Aislamiento
- Namespace: `mubench-s4`
- Servicios: `auth-service-s4`, `api-service-s4`, `data-service-s4`, `postgres-s4`
- NodePorts: `32184` (auth), `32181` (api), `32182` (data)

## Semántica
- Login de usuario
- Creación de usuario
- Persistencia en Postgres
- Consulta posterior por SQL

## Artefactos
- `experiments/05-mubench-advanced/k8s-controls/15-s4-semantic-services.yaml`
- `scripts/setup-scenario4-semantic-equivalent.sh`
- `scripts/validate-scenario4-semantic-persistence.sh`
- `scripts/run-scaling-scenario4-semantic-equivalent.sh`
- `Testing/results/scaling_tests/scaling-report_s4_20260509_191154.csv`

## Justificación
Se separa como S4 porque:
1. No es la semántica nativa de muBench avanzado (S3).
2. Sí es la capa adecuada para equivalencia funcional 1:1 con S2.
3. Facilita consolidar resultados sin mezclar topologías distintas.

## Resultado final
- S4 fue desplegado, validado y ejecutado con 1/5/10/20 VUs.
- La persistencia create/read se confirmó contra `postgres-s4`.
- El reporte final queda consolidado con los otros tres escenarios.
