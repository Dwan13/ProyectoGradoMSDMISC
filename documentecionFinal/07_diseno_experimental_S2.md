# Diseño Experimental Final — Escenario S2 (Baseline Legítimo)

> **Fecha:** 2026-05-14  
> **Escenario:** S2 — Academic Baseline (n=8 réplicas nominales, n=48 celdas de medición)  
> **Datos:** `Testing/results/anova/anova_matrix_s1_s2_fullfactor.csv` (filas `scenario==S2`)  
> **Análisis:** ANOVA one-way + Kruskal-Wallis + effect size (eta²)

---

## 1. Contexto del Escenario S2

S2 es el escenario de **línea base académica**: solo tráfico legítimo (`SECURITY_MODE=normal`), sin ataques. Su objetivo es caracterizar el overhead de rendimiento puro de cada control de seguridad, separado del efecto de los ataques. Es el dataset de referencia para validar hipótesis sobre latencia, throughput y consumo de recursos.

**S2 vs S6:**
| Característica | S2 | S6 |
|---------------|----|----|
| Tráfico | Solo legítimo | Legítimo + ataque |
| SECURITY_MODE | normal | normal + attack |
| Réplicas | 8 por celda | 4 por celda |
| Total corridas | 384 ejecuciones brutas / 48 filas agregadas | 384 filas |
| Propósito | Overhead de control | Efectividad de defensa |

---

## 2. Diseño Factorial

### Factores y Niveles

| Factor | Símbolo | Niveles | Tipo |
|--------|---------|---------|------|
| Control de seguridad | C | C1, C2, C3, C4 (4 niveles) | Fijo |
| Variante de control | V | 3 por control (baseline, v1, v2) | Fijo (anidado en C) |
| Nivel de carga (VUS) | L | 1, 5, 10, 20 (4 niveles) | Fijo |
| Réplica | R | 8 (n=8) | Aleatorio (bloque) |

### Diseño

```
Factorial 4×3×4 en bloques aleatorizados
Celdas totales: 4 controles × 3 variantes × 4 VUS = 48 celdas
Total observaciones por escenario S2: 48 filas agregadas (una por celda) derivadas de 384 ejecuciones brutas
```

**Nota:** La tabla ANOVA opera sobre los 48 puntos del CSV de S2, cada uno representando el promedio de 8 réplicas independientes dentro del bloque experimental correspondiente.

### Matriz de Diseño Experimental (S2)

| Control | Variantes | VUS testados | Métricas objetivo |
|---------|-----------|-------------|------------------|
| C1 (API Gateway) | baseline, istio, kong | 1, 5, 10, 20 | avg_ms, p95_ms, cpu_mcores |
| C2 (mTLS) | baseline, istio-mtls, linkerd-mtls | 1, 5, 10, 20 | avg_ms, mem_mib, cpu_mcores |
| C3 (NetworkPolicy) | baseline, basic, strict | 1, 5, 10, 20 | avg_ms, err_pct, rps |
| C4 (RateLimit) | baseline, moderate(1200rpm), strict(300rpm) | 1, 5, 10, 20 | err_pct, rps, avg_ms |

---

## 3. Hipótesis del Estudio

### H1 — Efecto del Tipo de Control sobre Latencia Media

> **H₁₀** (nula): El tipo de control de seguridad (C1–C4) no afecta la latencia media de las peticiones (`avg_ms`).  
> **H₁ₐ** (alternativa): Al menos un tipo de control produce latencia media significativamente diferente.

**Justificación:** mTLS (C2) introduce cifrado y proxies adicionales entre servicios; API Gateway (C1) añade un salto de intermediación; NetworkPolicy (C3) añade filtrado a nivel de red; y C4 introduce respuestas tempranas cuando el límite de tasa entra en efecto. Estas diferencias justifican contrastar la latencia media entre controles.

---

### H2 — Efecto del Nivel de Carga sobre Latencia

> **H₂₀** (nula): El nivel de VUS no afecta la latencia media (`avg_ms`).  
> **H₂ₐ** (alternativa): A mayor número de VUS, mayor latencia media (relación monotónica).

**Justificación:** En sistemas con recursos limitados (single-node MicroK8s), la contención de CPU/memoria bajo carga alta debe producir latencias mayores.

---

### H3 — Efecto del Control sobre Tasa de Error

> **H₃₀** (nula): El tipo de control no afecta la tasa de error HTTP (`err_pct`).  
> **H₃ₐ** (alternativa): Al menos un control produce tasa de error significativamente diferente.

**Justificación:** En el dataset S2 analizado, la principal fuente esperable de error es C4, ya que las respuestas HTTP 429 son contabilizadas por k6 como fallas de solicitud. Por ello resulta pertinente contrastar si el porcentaje de error cambia entre controles.

---

### H4 — Efecto del Control sobre Throughput (RPS)

> **H₄₀** (nula): El tipo de control no afecta el throughput (`rps`).  
> **H₄ₐ** (alternativa): Al menos un control reduce significativamente el throughput.

**Justificación:** Si un control introduce throttling o bloqueos efectivos, el throughput agregado debería disminuir. Esta hipótesis contrasta esa expectativa contra el comportamiento observado en el CSV S2.

---

## 4. Resultados del Análisis ANOVA

### 4.1 Matriz ANOVA — Efectos Principales

| Hipótesis | Respuesta | Factor | F | p-value | η² | Decisión |
|-----------|-----------|--------|---|---------|-----|---------|
| H1 | avg_ms | Control (C1–C4) | **14.60** | **9.75×10⁻⁷** | **0.499** | **Rechazar H₁₀** |
| H2 | avg_ms | VUS (1,5,10,20) | 2.61 | 6.31×10⁻² | — | No rechazar H₂₀ (p=0.063) |
| H3 | err_pct | Control (C1–C4) | **15.18** | **6.37×10⁻⁷** | **0.509** | **Rechazar H₃₀** |
| H4 | rps | Control (C1–C4) | 0.002 | 9.99×10⁻¹ | — | No rechazar H₄₀ |

> α = 0.05 | N = 48 (una medición por celda) | k = 4 grupos (para ANOVA by control)

### 4.2 Interpretación por Hipótesis

#### H1 — avg_ms ~ Control ✅ RECHAZADA (p = 9.75×10⁻⁷, η² = 0.499)
El tipo de control explica el **50% de la varianza** en latencia media. Este es un efecto de tamaño grande (Cohen 1988: η² > 0.14 = grande).

**Driver principal:** C4 (rate limiting) produce latencias artificialmente bajas en sus variantes moderate y strict porque las peticiones son respondidas con HTTP 429 muy rápidamente (sin procesamiento real). Esto baja el `avg_ms` de C4 al incluir los 429s en el promedio.

```
avg_ms por control (S2 promedio):
  C1: 11.53 ms (NGINX, Istio GW, Kong)
  C2: 12.03 ms (mTLS overhead leve)
  C3: 10.41 ms (NetworkPolicy overhead mínimo)
  C4:  6.75 ms (promedio bajo asociado a respuestas tempranas en moderate/strict)
```

#### H2 — avg_ms ~ VUS (p = 0.063) ⚠️ NO RECHAZADA (marginalmente)
El efecto del VUS sobre la latencia media **no es estadísticamente significativo** al nivel α=0.05 en S2, posiblemente porque:
1. El single-node tiene suficiente capacidad para 20 VUS (CPU no saturada en modo legítimo)
2. La variante C4/strict enmascara el efecto: sus latencias son bajas independientemente del VUS
3. El análisis posterior en S6 (MixedLM) sí confirma el efecto del VUS cuando se controla por otras variables

#### H3 — err_pct ~ Control ✅ RECHAZADA (p = 6.37×10⁻⁷, η² = 0.509)
El tipo de control explica el **51% de la varianza** en tasa de error. La fuente principal es C4: sus variantes moderate y strict generan tasas de error del 33% y 47% respectivamente (todos errores HTTP 429 por rate limiting).

```
err_pct por control (S2 promedio):
  C1: 0.00% (ningún request bloqueado)
  C2: 0.00% (mTLS no bloquea tráfico legítimo)
  C3: 0.00% (sin errores observados en el agregado S2)
  C4: 26.74% (promedio de 0% baseline + 33% moderate + 47% strict)
```

#### H4 — rps ~ Control (p = 0.9998) ❌ NO RECHAZADA
El throughput (rps) es virtualmente idéntico entre controles (F=0.002). Esto indica que ningún control afecta significativamente la **velocidad** de entrega de respuestas (incluyendo 429s). El throughput está determinado principalmente por el número de VUS, no por el tipo de control.

---

## 5. Resultados por Variante (Tabla Completa S2)

| Control | Variante | avg_ms | p95_ms | err_pct | rps |
|---------|----------|--------|--------|---------|-----|
| C1 | baseline | 10.81 | 21.62 | 0.00% | 34.44 |
| C1 | istio | 12.55 | 25.12 | 0.00% | 34.17 |
| C1 | kong | 11.23 | 22.49 | 0.00% | 34.40 |
| C2 | baseline | 10.58 | 22.08 | 0.00% | 34.48 |
| C2 | istio-mtls | 13.02 | 27.08 | 0.00% | 33.97 |
| C2 | linkerd-mtls | 12.50 | 25.65 | 0.00% | 34.23 |
| C3 | baseline | 10.34 | 21.43 | 0.00% | 34.51 |
| C3 | basic | 10.45 | 21.90 | 0.00% | 34.48 |
| C3 | strict | 10.43 | 21.69 | 0.00% | 34.48 |
| C4 | baseline | 10.43 | 21.56 | 0.00% | 34.50 |
| C4 | moderate | 5.89 | 14.59 | 33.06% | 35.41 |
| C4 | strict | 3.93 | 9.19 | 47.16% | 35.47 |

> Valores promediados sobre VUS = {1, 5, 10, 20}

### Hallazgos destacados:
1. **C2/istio-mtls** tiene la latencia más alta (13.02 ms) entre los controles funcionales (no rate-limiting): overhead de encriptación Envoy
2. **C3/strict** tiene prácticamente el mismo avg_ms que C3/baseline en el agregado S2; en este escenario no aparece una degradación apreciable en latencia ni error para C3.
3. **C4/strict** tiene la latencia aparente más baja (3.93 ms) pero un 47% de error — los 429 son respuestas rápidas que distorsionan el promedio
4. **mTLS overhead (C2):** istio-mtls = +23% latencia vs baseline; linkerd-mtls = +18% vs baseline

---

## 6. Análisis de Efectos de Variante (Post-hoc)

### C1 — Overhead por tipo de Ingress
```
C1/baseline (NGINX):   10.81 ms  ← referencia
C1/istio   (Gateway):  12.55 ms  ← +16% overhead (Envoy sidecar routing)
C1/kong    (Plugin):   11.23 ms  ← +4%  overhead (plugin execution)
```
**Conclusión:** Kong introduce menos overhead que Istio para el mismo nivel de funcionalidad de gateway en S2.

### C2 — Overhead por stack mTLS
```
C2/baseline:      10.58 ms  ← sin mTLS
C2/istio-mtls:    13.02 ms  ← +23% (TLS handshake × 2 hops + Envoy)
C2/linkerd-mtls:  12.50 ms  ← +18% (proxy Rust más ligero)
```
**Conclusión:** Ambos stacks mTLS añaden overhead significativo pero Linkerd es ~24% más eficiente que Istio en latencia.

### C3 — Overhead de NetworkPolicy
```
C3/baseline: 10.34 ms  ← referencia
C3/basic:    10.45 ms  ← +1%  (overhead negligible)
C3/strict:   10.43 ms  ← +1%  (sin degradación apreciable en el agregado S2)
```
**Conclusión:** NetworkPolicy tiene overhead negligible en latencia dentro del agregado S2 analizado. En este escenario no se observa impacto relevante en tasa de error ni throughput.

---

## 7. Limitaciones del Análisis S2

1. **No normalidad:** Los datos de latencia siguen distribución log-normal (Shapiro-Wilk p < 0.05). El ANOVA es robusto a esto por el teorema central del límite con n≥30, pero los intervalos de confianza son aproximados.

2. **Pseudo-replicación:** Las 48 filas son promedios de 8 réplicas, no observaciones individuales. El análisis correcto requeriría las 8×48 = 384 observaciones brutas (disponibles en los NDJSON de S2) para un análisis de efectos mixtos riguroso.

3. **Confusión C4:** Las variantes C4/moderate y C4/strict distorsionan los estadísticos de `avg_ms` y `err_pct` porque sus respuestas 429 son cualitativamente diferentes a respuestas de servicio reales. Deberían analizarse por separado o excluirse del ANOVA principal.

4. **Single-node bias:** Los recursos compartidos del nodo MicroK8s introducen variación entre corridas que no es atribuible al control testeado.

---

## 8. Conclusión General de S2

**S2 establece tres hallazgos fundamentales:**

1. **mTLS (C2) introduce overhead de latencia medible (+18–23%)** sin afectar la disponibilidad en tráfico legítimo. Este es el costo operativo de la encriptación East-West.

2. **Rate Limiting (C4) afecta drásticamente la disponibilidad** (47% de error en variante strict) y es el control con mayor impacto en tráfico legítimo cuando está mal calibrado.

3. **NetworkPolicy (C3) y API Gateway (C1) tienen overhead operacional mínimo** en tráfico legítimo bajo S2. Su valor de seguridad se observa únicamente en S6 (modo attack) donde se ve la efectividad de bloqueo.

Estos resultados fundamentan el diseño de S6: se añade la dimensión de modo de seguridad (normal vs attack) para medir tanto el overhead (presente en S2) como la efectividad de defensa (solo visible con ataques reales).
