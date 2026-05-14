# Justificación metodológica integral (S2, S3 y S4)

## 1. Pregunta de investigación
La pregunta central es analizar el **trade-off entre seguridad y atributos de calidad**, medidos con 6 métricas:
- `avg_ms`
- `p95_ms`
- `err_pct`
- `rps`
- `cpu_mcores`
- `mem_mib`

Por lo tanto, el diseño experimental debe priorizar:
1. Validez interna (atribuir cambios a controles de seguridad y no a cambios de sistema).
2. Comparabilidad entre condiciones.
3. Reproducibilidad.

---

## 2. Qué significa "semántica" en este trabajo
En este contexto, **semántica** es el significado funcional del experimento, es decir:
- qué operación de negocio se ejecuta,
- sobre qué entidades/datos,
- con qué reglas funcionales,
- y con qué resultado esperado.

Ejemplos concretos:
- Semántica de S2/S4: login + create/read de usuarios sobre base de datos relacional persistente.
- Semántica de S3 nativo: ejecución de flujo de servicios generado (`s0..s7/sdb1`) orientado a benchmark avanzado de topología/cómputo.

Cuando cambia la semántica, deja de ser estrictamente el mismo experimento, aunque se mantengan VUs y métricas.

---

## 3. Por qué S2 es el eje principal para la investigación
**S2 (Postgres real)** es el escenario principal recomendado porque:
1. Mantiene el mismo marco funcional base de la app (comparabilidad fuerte).
2. Introduce base de datos real (más realismo sin romper comparabilidad).
3. Permite evaluar el efecto de controles de seguridad C1-C4 sobre las 6 métricas con mejor inferencia causal.
4. Tiene mejor balance entre validez interna y realismo operativo.

En términos académicos, S2 minimiza confusores: cambia menos cosas a la vez.

---

## 4. Por qué S3 no se usa como eje central (pero sí aporta)
S3 nativo aporta mucho para robustez y estrés, pero no es ideal como eje causal principal para tu pregunta, porque:
1. Cambia topología y flujo funcional respecto a S2.
2. Introduce carga y comportamiento interno diferente por diseño.
3. Puede mezclar el efecto de seguridad con el efecto de arquitectura/workload.

Conclusión: S3 se usa mejor como **validación externa** de robustez y comportamiento en arquitectura avanzada, no como sustituto directo de S2 para inferencia causal principal.

---

## 5. Por qué se creó S4
Para atender exigencia de comparación 1:1 funcional con S2, se separó una capa equivalente como **S4**:
1. Mismo tipo de semántica funcional (login + usuarios + persistencia).
2. Servicios dedicados (`auth-service-s4`, `api-service-s4`, `data-service-s4`, `postgres-s4`).
3. Namespace separado (`mubench-s4`) y puertos propios.

Esto evita mezclar:
- S3 nativo (benchmark avanzado)
- con la comparación funcional 1:1 (S2 vs S4).

---

## 6. Respuesta directa a la duda de equivalencia 1:1
### ¿Se puede lograr 1:1 entre S2 y S3 nativo?
No de forma estricta sin rediseñar profundamente S3, porque su semántica y topología son distintas.

### ¿Se puede lograr 1:1 funcional para comparar con S2?
Sí, mediante S4, que fue creado precisamente para eso.

---

## 7. Persistencia de datos (criterio clave)
### S2
Se validó create/read y persistencia en Postgres (`mubench-real`).

### S3 nativo
No ofrece por sí solo la misma semántica de create/read de usuarios de S2.

### S4
Se validó create/read y persistencia en Postgres (`mubench-s4`) en ejecución separada.

---

## 8. Cómo defenderlo en presentación
Propuesta de argumento corto y sólido:

"El eje principal de análisis fue S2 porque responde directamente a la pregunta de trade-off seguridad-calidad con alta validez interna: mismos controles de seguridad y misma semántica funcional, pero con persistencia real en base de datos. S3 se mantuvo como validación externa de robustez en una arquitectura muBench avanzada, no como comparación causal directa. Para cubrir exigencia de equivalencia funcional 1:1, se definió y ejecutó S4 como escenario separado, preservando la comparabilidad con S2 sin mezclarlo con la semántica nativa de S3." 

---

## 9. Uso recomendado de escenarios en resultados
1. **Análisis principal del trade-off**: S2.
2. **Comparación funcional 1:1**: S2 vs S4.
3. **Validación externa de estrés/arquitectura**: S3.

Esta estructura maximiza rigor metodológico y claridad narrativa.

---

## 10. Evidencia y artefactos clave
- S4 (definición): `Docs/scenario-4-equivalence.md`
- S4 (corrida completa): `Testing/results/scaling_tests/scaling-report_s4_20260509_191809.csv`
- Consolidado 4 escenarios: `Testing/results/scaling_tests/four-scenarios-summary_latest.csv`
- Marco de equivalencia S3: `Docs/scenario-3-step-by-step-equivalence.md`
- Evaluación de no equivalencia estricta S3 nativo: `Docs/scenario-3-equivalence-assessment.md`
