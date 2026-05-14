# Plan de Mejora de Rigor y Valor Academico

## Objetivo
Convertir la campana actual en un estudio con mayor fuerza inferencial y mejor defendibilidad academica, manteniendo comparabilidad operativa.

## 1) Diseno experimental recomendado

- Diseno factorial completo: control (4) x variant_level (3) x vus (4).
- Replicaciones por celda: minimo 3, ideal 5.
- Bloques temporales: ejecutar cada replica en bloques separados (por ejemplo, manana/tarde o dias distintos).
- Aleatorizacion: aleatorizar el orden de ejecucion de las 48 celdas dentro de cada bloque.
- Ventana de estabilizacion: mantener fixed warm-up y cooldown entre corridas.

## 2) Modelo estadistico recomendado

- Modelo principal por metrica:
  - y ~ C(control) * C(variant_level) * C(vus) + C(block)
- Para err_pct:
  - preferir GLM binomial (o beta-regresion cuando aplique), no solo OLS.
- Para concluir "ausencia de efecto relevante":
  - usar equivalence testing (TOST) o SESOI + IC95%, no solo p-value > 0.05.
- Post-hoc:
  - Tukey HSD o contrastes planificados con correccion Holm/Benjamini-Hochberg.
- Reportar:
  - p-values, IC95%, y tamano de efecto (eta parcial cuadrado para ANOVA).

## 3) Amenazas a validez y mitigaciones

### Validez interna
- Riesgo: drift del cluster entre corridas.
- Mitigacion: bloqueo por dia/hora, aleatorizacion y health-check estricto pre-run.

### Validez de constructo
- Riesgo: err_pct mezcla fallo funcional con politica esperada (C4).
- Mitigacion: separar metricas de desempeno (Capa A) y validez funcional (Capa B).

### Validez externa
- Riesgo: un solo entorno (postgres-real) limita generalizacion.
- Mitigacion: repetir en al menos 2 entornos adicionales (por ejemplo, distinto nodo/infra).

### Validez de conclusion
- Riesgo: pocas replicas y potencia insuficiente.
- Mitigacion: analisis de potencia previo y minimo 3-5 replicas por celda.

## 4) Reporte academico minimo (estructura)

- Preguntas de investigacion e hipotesis predefinidas.
- Diseno factorial y plan de analisis estadistico pre-registrado.
- Supuestos y diagnosticos del modelo (normalidad residual, homocedasticidad, leverage).
- Resultados con IC95% y efecto, no solo significancia.
- Discusion de trade-offs (latencia vs errores esperados por control).
- Amenazas a validez y limitaciones explicitas.
- Paquete reproducible: datos crudos, scripts, versiones y hashes.

## 5) Checklist de ejecucion para la siguiente campana

- [ ] Fijar semilla y orden aleatorio de ejecucion.
- [ ] Definir bloques y replicas (>=3 por celda).
- [ ] Si el objetivo es descartar efectos pequenos, subir a 5-6 replicas por celda en latencia/rps y >10 para CPU/memoria.
- [ ] Congelar manifiestos/versiones y registrar hashes.
- [ ] Ejecutar Capa A y Capa B por separado.
- [ ] Correr modelo factorial completo y post-hoc.
- [ ] Correr equivalence testing para C1-C3 con margenes predefinidos por metrica.
- [ ] Publicar artefactos y notebook/script de reproduccion.

## 6) Estado actual de avance

- Ya aplicado en esta entrega:
  - ANOVA factorial completo con interacciones dobles y triple.
  - Bloqueo por dia (2026-05-09 y 2026-05-10).
  - Matriz ANOVA exportada y resumen tecnico.

- Siguiente salto para rigor alto:
  - aumentar replicacion por celda y agregar post-hoc con correccion multiple.
  - usar matrices aleatorizadas y bloqueadas para C4 y C2/C3.
  - sustituir la lectura de "no significativo" por una conclusion basada en potencia + equivalencia.
