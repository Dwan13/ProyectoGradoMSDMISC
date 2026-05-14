# S6 Defense Script (15 Minutes)

Purpose: full spoken defense script, aligned with S6 final evidence and strict-jury posture.

Evidence anchors to repeat during delivery:
- 384/384 completed runs
- 6 core metrics per run
- 0 missing CPU and 0 missing memory in consolidated dataset
- threat matrix with STRIDE/CIA metadata
- ANOVA + diagnostics with explicit interpretation boundaries

## 0:00-1:00 Opening and Thesis

"En plataformas de microservicios, muchas decisiones de seguridad se toman por intuicion o por moda tecnologica. El problema es que esas decisiones tienen costo operativo, y ese costo casi nunca se mide de forma integrada."

"Esta tesis evalua seguridad y calidad de servicio en el mismo diseno experimental. No pregunto solo que control bloquea mas, ni solo cual control es mas rapido. Pregunto como se decide bajo trade-offs medibles."

"Tesis central: la optimizacion conjunta de seguridad y calidad solo es posible con analisis por vector de amenaza, bajo carga, y con costo operativo explicito."

## 1:00-3:00 Problem Framing and Dual Contribution

"Desde Sistemas, el reto es metodologico: comparar configuraciones de forma causal y reproducible, no con pruebas aisladas."

"Desde Seguridad, el reto es semantico y operativo: mapear amenazas concretas a controles concretos, con riesgo residual visible."

"La integracion dual esta en el metodo: los controles de seguridad son factores del experimento de rendimiento, y el resultado se interpreta con criterio de ingenieria y criterio defensivo al mismo tiempo."

Contributions to state explicitly:
1. Full factorial design: 4 controles x 3 variantes x 4 VUs x 2 modos x 4 bloques = 384 corridas.
2. Unified six-metric evidence per run: avg_ms, p95_ms, err_pct, rps, cpu_mcores, mem_mib.
3. Formal threat matrix: STRIDE, CIA, attacker profile, impacted asset, residual risk.
4. Scope discipline: operational security under adversarial load, not full cryptographic-depth certification.

## 3:00-5:30 Methodology Rigor

"El protocolo uso bloques aleatorizados para reducir confusores temporales del cluster."

"Mantuvimos los mismos niveles de carga y las mismas familias de control en todas las condiciones para conservar comparabilidad."

Security modes:
- normal: flujo legitimo
- attack: insercion de vectores adversariales sinteticos

Attack vectors:
- bad-login
- unauth
- token-tamper
- bearer-malformed
- xff-spoof

"La consolidacion operacional se hizo por corrida con merge temporal de Prometheus para CPU y memoria, y verificacion de completitud previa al modelado."

Key jury sentence:
"Esto no es una corrida unica de benchmark. Es experimentacion diseniada con replicacion y artefactos auditables."

## 5:30-8:30 Results and Trade-offs

"En ajuste global del modelo, los resultados son fuertes para variables clave."

Numbers to pronounce:
- R2 avg_ms = 0.5730
- R2 err_pct = 0.9235
- R2 cpu_mcores = 0.8678

"La explicacion de comportamiento de error y de costo CPU es alta, con efectos sistematicos por control, modo y carga."

CPU overhead normal->attack:
- C1: +12.1%
- C2: +12.3%
- C3: +10.2%
- C4: +9.0%

Threat-control interpretation:
- C2 destaca en abuso de credenciales y token.
- C3 destaca en restricciones de origen y segmentacion.
- C1 y C2 responden mejor a headers malformados.
- C4 complementa para moderar presion volumetrica.

"La conclusion operacional no es un ganador unico. Es una matriz de decisiones condicionada por tipo de amenaza y presupuesto."

## 8:30-10:30 Statistical Validity and Boundaries

"Ejecute diagnosticos de supuestos: Q-Q, residuals-vs-fitted, scale-location, Shapiro, Levene y Durbin-Watson."

"Durbin-Watson cercano a 2 indica bajo riesgo de autocorrelacion residual."

"Shapiro y Levene muestran desviaciones de normalidad y homocedasticidad en metricas relevantes."

Defensive but honest line:
"Por eso reporto evidencia direccional fuerte con alta capacidad explicativa, y evito afirmar certeza parametrica perfecta."

If pressed on OLS:
"OLS se usa como baseline inferencial en este entorno; robustez adicional con HC3/GLM/no parametrico esta definida como siguiente fase metodologica."

## 10:30-12:00 Practical Recommendations

"La estrategia recomendada es por tier de riesgo, no por marca tecnologica."

Deployment logic:
1. Baseline amplio: C1 + C4.
2. Rutas sensibles: agregar C2.
3. Segmentos de alto riesgo: reforzar con C3 estricto.

Decision rule to memorize:
"Seleccionar por pesos objetivo entre eficacia defensiva, presupuesto de latencia y presupuesto de CPU."

## 12:00-13:30 Limitations and Future Work

Read almost verbatim:
"Esta tesis demuestra seguridad operativa bajo carga adversarial. No afirma seguridad criptografica integral, ni resistencia completa de bypass a escala botnet internet, ni cobertura forense profunda."

Future work:
1. Auditoria criptografica profunda (suites, llaves, secretos).
2. Validacion de bypass en escenarios distribuidos a escala internet.
3. Replicacion multi-cluster para ampliar validez externa.
4. Endurecimiento estadistico con sensibilidad robusta.

## 13:30-15:00 Closing and Q&A Transition

"El aporte principal es convertir decisiones de arquitectura de seguridad en decisiones medibles, comparables y defendibles."

"Para Sistemas, hay evidencia multifactorial bajo carga adversarial. Para Seguridad, hay trazabilidad amenaza-control-riesgo residual con costo operativo visible."

"El trabajo esta cerrado para su alcance declarado, es reproducible desde artefactos del repositorio, y es explicitamente honesto sobre sus limites."

Transition line:
"Estoy listo para preguntas de detalle sobre threat model, diagnosticos estadisticos y pipeline de replicacion."

---

## Quick Delivery Notes

- Keep speed at ~120-135 words/minute.
- If jury interrupts, jump directly to "Statistical Validity and Boundaries" or "Limitations".
- Do not defend beyond declared scope.
- Repeat three anchors if under pressure: reproducible, integrated, scope-honest.
