# Plan para Evidencia Suficiente de Inferencia (Factorial Completo)

## 1. Problema metodologico actual

- Con 1 observacion por celda (control, variante, VUs), un resultado no significativo en C1-C3 no implica ausencia de efecto.
- La interpretacion correcta es: evidencia insuficiente para detectar efectos pequenos o moderados con robustez inferencial.

## 2. Criterio de suficiencia de evidencia

Se propone declarar evidencia suficiente cuando se cumplan simultaneamente:

- Potencia estadistica objetivo >= 0.80.
- Alfa predefinido = 0.05.
- Replicacion minima por celda segun tamano de efecto objetivo.
- Aleatorizacion del orden de corridas dentro de cada bloque.
- Bloqueo por dia/ventana horaria para controlar drift de cluster.
- Reporte de tamano de efecto (eta parcial cuadrado) e IC95%.

## 3. Muestra minima recomendada y lectura correcta del "no significativo"

Archivo base: Testing/results/scaling_tests/power_analysis_anova_guidance.csv

Guia resumida:

- Efecto pequeno (f=0.10): requiere aprox 323 observaciones por grupo.
- Efecto pequeno-moderado (f=0.15): aprox 144 por grupo.
- Efecto moderado (f=0.25): aprox 53 por grupo.
- Efecto moderado-alto (f=0.30): aprox 37 por grupo.
- Efecto grande (f=0.40): aprox 21 por grupo.

Conclusiones practicas para este proyecto:

- 3 replicas/celda: aceptable para detectar efectos grandes y parte de moderados altos.
- 5 replicas/celda: mejora estabilidad de estimaciones e interacciones.
- Para afirmar ausencia de efecto en C1-C3, se requiere potencia demostrada para efecto minimo relevante definido a priori.

Con la variabilidad observada actualmente en C1-C3 (estimada a partir de las dos corridas disponibles), una regla mas realista es:

- `avg_ms`: desviacion intra-celda media ~0.64 ms. Si el efecto minimo relevante es 1.0 ms, se requieren aprox 6 replicas por celda para potencia ~0.80.
- `p95_ms`: desviacion intra-celda media ~1.54 ms. Si el efecto minimo relevante es 3.0 ms, se requieren aprox 5 replicas por celda.
- `rps`: desviacion intra-celda media ~0.12 req/s. Si el efecto minimo relevante es 1.0 req/s, 3 replicas por celda son suficientes.
- `cpu_mcores`: desviacion intra-celda media ~122 mCores. Si el efecto minimo relevante es 100 mCores, se requieren aprox 14 replicas por celda.
- `mem_mib`: desviacion intra-celda media ~293 MiB. Si el efecto minimo relevante es 150 MiB, se requieren aprox 32 replicas por celda.

Esto implica que hoy puedes sostener inferencia razonable para latencia y throughput con 5-6 replicas por celda, pero no para ausencia de efecto pequeno en CPU/memoria si mantienes solo 3 replicas.

Para ANOVA de 3 grupos (baseline + 2 variantes), el tamano de efecto minimo detectable en terminos de Cohen's f queda aproximadamente en:

- 3 replicas por grupo: `f ~ 1.36` (solo efectos muy grandes)
- 5 replicas por grupo: `f ~ 0.91`
- 8 replicas por grupo: `f ~ 0.68`
- 10 replicas por grupo: `f ~ 0.60`
- 12 replicas por grupo: `f ~ 0.54`
- 15 replicas por grupo: `f ~ 0.48`

Por tanto, en C1-C3 un resultado "no significativo" con 1 replica por celda no debe leerse como "no hay efecto". La lectura correcta es:

- con 1 replica/celda: evidencia insuficiente para inferencia robusta;
- con 3 replicas/celda: ausencia de evidencia solo para efectos grandes;
- con 5-6 replicas/celda: evidencia razonable para descartar efectos practicamente relevantes en latencia/p95/rps;
- con >10 replicas/celda: recien empieza a ser defendible descartar efectos moderados en CPU/memoria.

## 4. Diseno para C4: barrido sistematico limite-burst

Archivos:

- `Testing/results/scaling_tests/design_matrix_c4_limit_burst.csv`
- `Testing/results/scaling_tests/design_matrix_c4_limit_burst_randomized_blocks.csv`

Cobertura propuesta:

- Rate limit rps: 5, 10, 15, 20, 30, 40.
- Burst: 0%, 5%, 10%, 20%.
- VUs: 1, 5, 10, 20.
- Replicas: 3 por celda.

Fortaleza del diseno actualizado:

- 6 niveles de rate limit: `5, 10, 15, 20, 30, 40` req/s.
- 4 niveles de burst: `0, 5, 10, 20`.
- 4 niveles de carga: `1, 5, 10, 20` VUs.
- 3 replicas por celda.
- Bloques temporales y orden aleatorio fijo en la version `randomized_blocks`.

Objetivo inferencial:

- Estimar superficie respuesta costo-beneficio (latencia, err_pct, rps, cpu, mem) en funcion de limite y burst.
- Contrastar interacciones con carga (VUs).

## 5. Diseno para C2/C3: granularidad de politicas

Archivos:

- `Testing/results/scaling_tests/design_matrix_c2_c3_granularity.csv`
- `Testing/results/scaling_tests/design_matrix_c2_c3_granularity_randomized_blocks.csv`

C2 (mesh/mTLS + resiliencia):

- variantes: baseline, istio-mtls, linkerd-mtls.
- granularidad: retries {0,1,2} x timeout {250,500,1000}.

C3 (network policy tiers):

- baseline, basic, strict, strict-plus-egress, strict-plus-egress-db.

Fortaleza del diseno actualizado:

- C2 cubre una malla `retries x timeout` balanceada sobre las tres variantes.
- C3 ya incorpora niveles de granularidad superiores a `strict`, lo cual habilita curvas costo-beneficio reales y no solo comparaciones binarias.
- La version `randomized_blocks` agrega bloqueo y orden aleatorio, que eran dos piezas faltantes para mayor rigor.

Objetivo inferencial:

- Curvas costo-beneficio de seguridad vs rendimiento.
- Efectos principales y de interaccion con VUs.

## 6. Modelo estadistico recomendado

- Modelo principal por metrica continua:
  - y ~ C(control) * C(variant_level) * C(vus) + C(block_day)

- Para err_pct (proporcion):
  - GLM binomial (o beta regresion si corresponde) + bloque.

- Post-hoc:
  - Tukey/contrastes planificados con correccion Holm o Benjamini-Hochberg.

## 7. Regla de interpretacion para "no significativo"

Solo reportar "no evidencia de efecto" cuando:

- Se demuestra potencia >= 0.8 para el efecto minimo de interes, y
- El IC95% del efecto excluye impactos practicamente relevantes.

Mejor aun, para sostener una conclusion de "sin efecto practicamente importante" usar:

- prueba de equivalencia (TOST) con margenes predefinidos por metrica, o
- enfoque SESOI + IC95% totalmente contenido dentro del margen.

Margenes iniciales recomendados para C1-C3:

- `avg_ms`: +/-1.0 ms
- `p95_ms`: +/-3.0 ms
- `rps`: +/-1.0 req/s
- `cpu_mcores`: +/-100 mCores
- `mem_mib`: +/-150 MiB

Si no se cumple lo anterior, reportar:

- "Resultado no concluyente por potencia insuficiente".

## 8. Proximo paso operativo

- Ejecutar la campana con matrices de diseno propuestas (C4 y C2/C3).
- Mantener 3-5 replicas por celda con aleatorizacion y bloqueo.
- Recalcular ANOVA factorial completo con post-hoc e IC95%.
