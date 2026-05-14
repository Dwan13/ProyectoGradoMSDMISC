# Evaluacion de Suficiencia de Evidencia e Inferencia

## Estado actual

La campana original mejoro de forma importante al combinar dos dias y ajustar un ANOVA factorial completo con bloqueo por dia. Aun asi, para C1-C3 no es metodologicamente correcto interpretar un resultado no significativo como ausencia de efecto. La conclusion correcta sigue siendo: evidencia insuficiente para descartar efectos pequenos o moderados, salvo que se defina un efecto minimo de interes y se demuestre potencia adecuada.

## Que ya esta bien

- Existe ANOVA factorial completo con interacciones y bloqueo por dia.
- Ya hay matrices dedicadas para:
  - C4 barrido limite-burst.
  - C2/C3 granularidad y costo-beneficio.
- Ya existen versiones mejoradas con bloqueo y aleatorizacion:
  - Testing/results/scaling_tests/design_matrix_c4_limit_burst_randomized_blocks.csv
  - Testing/results/scaling_tests/design_matrix_c2_c3_granularity_randomized_blocks.csv

## Que faltaba para inferencia suficiente

### 1. En C1-C3

Para poder afirmar "no hay efecto relevante" se necesita una de estas dos cosas:

- potencia >= 0.80 para el efecto minimo relevante predefinido, o
- prueba de equivalencia (TOST) con IC95% completamente dentro del margen.

Sin eso, la frase correcta no es "no hay efecto", sino:

- resultado no concluyente por potencia insuficiente.

### 2. Recomendacion por metrica en C1-C3

Usando la variabilidad observada entre las corridas de 2026-05-09 y 2026-05-10:

- avg_ms: 6 replicas por celda para detectar 1.0 ms.
- p95_ms: 5 replicas por celda para detectar 3.0 ms.
- rps: 3 replicas por celda para detectar 1.0 req/s.
- cpu_mcores: 14 replicas por celda para detectar 100 mCores.
- mem_mib: 32 replicas por celda para detectar 150 MiB.

Interpretacion practica:

- 3 replicas por celda alcanzan para throughput y efectos grandes.
- 5-6 replicas por celda son una base razonable para latencia y p95.
- CPU y memoria requieren muchas mas replicas si se quiere descartar efectos pequenos con rigor.

## Evaluacion de C4

El barrido C4 propuesto ya es metodologicamente valioso porque:

- expande el espacio experimental de 2 configuraciones a una superficie respuesta;
- separa efecto del limite y efecto del burst;
- permite interaccion con carga (VUs);
- ya tiene 3 replicas por celda.

Lo que convierte esto en una pieza academica fuerte es usar la version aleatorizada y bloqueada, no la matriz plana original.

## Evaluacion de C2/C3

La matriz C2/C3 es valiosa porque deja de comparar solo "tecnologias" y empieza a comparar granularidad de politicas y trade-offs. Eso aumenta mucho el valor academico.

Puntos fuertes:

- C2: malla retries x timeout balanceada entre variantes.
- C3: niveles de politicas mas finos que baseline/basic/strict.
- ya hay 3 replicas y cobertura en 1/5/10/20 VUs.

Punto critico:

- la lectura correcta de resultados negativos sigue dependiendo de potencia suficiente o equivalencia, no solo de p > 0.05.

## Regla final de reporte recomendada

- Si p < 0.05 y el efecto es practicamente relevante: reportar diferencia detectada.
- Si p >= 0.05 pero no hay potencia suficiente: reportar resultado no concluyente.
- Si p >= 0.05 y ademas el IC95% cae dentro del margen SESOI: reportar evidencia de equivalencia practica.

## Conclusión

Lo que mas eleva el rigor no es solo correr mas veces, sino cambiar la logica de interpretacion:

- de NHST simple a inferencia basada en potencia, SESOI y equivalencia;
- de comparaciones puntuales a superficies respuesta y curvas costo-beneficio;
- de corridas secuenciales a matrices bloqueadas y aleatorizadas.
