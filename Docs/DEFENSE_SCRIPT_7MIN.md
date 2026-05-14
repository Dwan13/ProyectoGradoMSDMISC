# S6 Defense Script (7 Minutes)

Purpose: ultra-synthetic spoken version for a strict jury.

Use with one slide per block. Keep pace and avoid adding technical detours.

## 0:00-0:40 Opening

"En microservicios existe una tension constante: mas seguridad suele implicar mas costo operativo. Esta tesis no discute esa tension en abstracto; la mide con evidencia controlada."

"Ejecute una campana integrada de 384 corridas y analice seis metricas por corrida para responder una pregunta concreta: como decidir controles de seguridad con impacto real en calidad de servicio."

## 0:40-1:40 Problem + Contribution

"El aporte dual es claro. Desde Sistemas: diseno experimental multifactorial bajo carga. Desde Seguridad: mapeo amenaza-control con riesgo residual observable."

"El diseno fue 4 controles por 3 variantes por 4 niveles de carga por 2 modos de seguridad por 4 bloques aleatorizados: 384 corridas. No es benchmark de una sola toma; es experimentacion reproducible."

## 1:40-3:00 Method

"Modele dos modos: normal y attack. En attack injecte vectores sinteticos ejecutables: bad-login, unauth, token-tamper, bearer-malformed y xff-spoof."

"Por corrida medi latencia promedio, p95, error, throughput, CPU y memoria. CPU y memoria se consolidaron desde Prometheus con ventanas temporales por corrida."

"La evidencia final quedo completa: 384 filas, sin faltantes en CPU ni memoria."

## 3:00-4:40 Results

"En terminos estadisticos, el modelo explica fuertemente el comportamiento de error y costo de CPU: R2 de err_pct 0.9235 y R2 de cpu_mcores 0.8678."

"En overhead de CPU bajo ataque: C1 +12.1%, C2 +12.3%, C3 +10.2%, C4 +9.0%."

"Interpretacion de seguridad por vector: C2 fue mas fuerte para abuso de credenciales y token; C3 fue mas fuerte para restricciones de origen; C1 y C2 defendieron mejor headers malformados; C4 fue complementario para moderar presion volumetrica."

"No hay control bala de plata. La evidencia respalda defensa en profundidad con asignacion por vector y por presupuesto."

## 4:40-5:40 Statistical Honesty

"Valide supuestos con Q-Q, residuals-vs-fitted, scale-location, Shapiro, Levene y Durbin-Watson."

"Durbin-Watson cerca de 2 sugiere baja autocorrelacion. Shapiro y Levene muestran desviaciones de normalidad/homocedasticidad en metricas clave."

"Por eso la conclusion se presenta como evidencia direccional fuerte, no como certeza parametrica perfecta."

## 5:40-6:30 Practical Decision Rule

"La recomendacion no es elegir un ganador unico; es elegir por tier de riesgo:"

1. "Base: C1 + C4"
2. "Rutas sensibles: agregar C2"
3. "Segmentos de alto riesgo: aplicar C3 estricto"

"La regla de decision es ponderar eficacia de seguridad, presupuesto de latencia y presupuesto de CPU."

## 6:30-7:00 Close

"Esta tesis queda cerrada para su alcance declarado: seguridad operativa bajo carga adversarial, con pipeline reproducible y limites explicitos."

"No afirmo seguridad criptografica total ni validacion de bypass a escala botnet internet. Esos son trabajos futuros ya definidos."

"Estoy listo para preguntas sobre formalizacion del threat model, validez estadistica y reproducibilidad end-to-end."
