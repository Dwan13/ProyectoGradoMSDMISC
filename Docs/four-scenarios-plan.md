# Cuatro Escenarios - Plan de Consolidación Final

## Escenarios
1. Escenario 1: sintético original.
2. Escenario 2: Postgres real.
3. Escenario 3: muBench avanzado nativo.
4. Escenario 4: capa funcional equivalente para comparación 1:1 con S2.

## Criterio de separación
- S3 no se mezcla con la capa funcional equivalente.
- S4 queda como el candidato para la comparación 1:1 de semántica de usuarios.
- La consolidación final debe distinguir entre:
  - comparaciones de topología/estrés (S3)
  - comparaciones funcionales (S2 vs S4)

## Siguiente corrida recomendada
- Ejecutar S4 equivalente.
- Consolidar cuatro escenarios con reporte final.

## Estado actual
- S4 ya fue desplegado, validado y corrido.
- El consolidado final está en `Testing/results/scaling_tests/four-scenarios-summary_latest.csv`.
