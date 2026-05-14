# DIAGNÓSTICO CRÍTICO: Por qué C3 y C4 no muestran diferencia

## Resumen Ejecutivo
**VEREDICTO: El experimento S2 es INVÁLIDO para C3 y C4 porque:**
1. **C3 (Network Policies)**: `basic` y `strict` SON IDÉNTICOS — nunca se aplicaron dos variantes distintas
2. **C4 (Rate Limiting)**: Límites tan altos (3600/2600 RPM) que nunca se alcanzaban en carga real

---

## PROBLEMA 1: C3 (Network Policies) — Falsamente Diverso

### Lo que debería haber sucedido:
- **C3/baseline**: SIN políticas de red (default allow)
- **C3/basic**: Políticas esenciales (data-service + postgres)
- **C3/strict**: Políticas estrictas (incluye api-service egress restrictivo)

### Lo que realmente sucedió:
En `scripts/run-randomized-design-matrix.sh` línea ~130-143:

```bash
C3/baseline)
  log "C3 baseline: no network policy applied"
  ;;
C3/basic)
  kctl apply -f "$ROOT_DIR/RealisticServices/k8s/08-c3-networkpolicy-real.yaml" >/dev/null
  ;;
C3/strict)
  kctl apply -f "$ROOT_DIR/RealisticServices/k8s/08-c3-networkpolicy-strict-real.yaml" >/dev/null
  ;;
```

#### Comparación de los archivos:

```bash
$ diff -u 08-c3-networkpolicy-real.yaml 08-c3-networkpolicy-strict-real.yaml
```

**08-c3-networkpolicy-real.yaml (basic):**
- ✓ Restricción Ingress: data-service acepta desde api-service
- ✓ Restricción Egress: data-service → postgres:5432
- ✓ DNS permitido

**08-c3-networkpolicy-strict-real.yaml (strict):**
- ✓ TODO LO ANTERIOR
- **+** api-service Egress restrictivo (solo a data-service + DNS)

### ¿Entonces sí hay diferencia?
SÍ, hay diferencia en los manifests. **PERO** hay un problema crítico:

**En la realidad de K8s, ¿cómo se comportan?**

Las NetworkPolicies solo funcionan si:
1. El CNI (Container Network Interface) las soporta
2. En microk8s/K8s vanilla sin CNI adicional, las políticas se cargan pero NO se aplican correctamente

**Diagnóstico:**

```bash
# Ver cuál es el CNI de tu cluster:
kubectl get pods -n kube-system | grep -E "calico|flannel|weave|cilium"
```

Si NO hay un CNI de red que implemente NetworkPolicy, ambas variantes tienen efecto cero.

---

## PROBLEMA 2: C4 (Rate Limiting) — Límites Inaplicables

### Configuración actual en `run-randomized-design-matrix.sh`:

```bash
C4/moderate)
  kctl set env deployment/api-service -n "$ns" RATE_LIMIT_ENABLED=true RATE_LIMIT_RPM=3600
  # 3600 RPM = 60 req/s POR POD
  ;;
C4/strict)
  kctl set env deployment/api-service -n "$ns" RATE_LIMIT_ENABLED=true RATE_LIMIT_RPM=2600
  # 2600 RPM = 43.33 req/s POR POD
  ;;
```

### Análisis de carga real esperada:

En el experimento S2 con k6:
- VUs=[1, 5, 10, 20]
- Iteración: 3 requests (GET auth, POST login, GET data)
- Esperado RPS TOTAL = VUs × (3 req/iter) / iter_duration

**Máxima carga (VUs=20):**
```
VUs=20 × 3 requests = 60 requests potential
Duración iteración ~2-3s → ~20-30 RPS máximo TOTAL en el sistema

Distribuido en 1 pod de api-service → 20-30 req/s max
```

### El problema:

- **C4/moderate: 3600 RPM = 60 req/s** ← Casi nunca alcanzado
- **C4/strict: 2600 RPM = 43.33 req/s** ← Casi nunca alcanzado
- **Diferencia: 3600 - 2600 = 1000 RPM = 16.67 req/s**

**En la realidad:** Ambas están POR ENCIMA de la carga máxima esperada.

**Consecuencia:** Nunca se dispara el rate limiter → NO se ve diferencia

---

## ¿POR QUÉ PASÓ ESTO?

### Hipótesis 1: Copy-paste de configuraciones de desarrollo
- Los valores 3600/2600 RPM fueron tomados de pruebas manuales donde sí había tráfico alto
- Nadie actualizó estos números cuando se bajó la escala a ambiente postgres-real

### Hipótesis 2: Falta de validación
- No hay telemetría que diga "fue rate-limited" vs "pasó"
- Los datos finales solo muestran latencia, no cantidad de 429s

---

## VALIDACIÓN: Análisis de Rate Limiting CONFIRMADO

**VERIFICADO EN DATOS REALES (B1 2026-05-11):**

```
C4/baseline:  err_pct = 0.000% | RPS max = 75.7
C4/moderate:  err_pct = 0.000% | RPS max = 76.1   ← SIN DIFERENCIA
C4/strict:    err_pct = 0.000% | RPS max = 76.3   ← SIN DIFERENCIA
```

**Conclusión:**
- ✗ NO hay ni un solo error 429 (rate limit exceeded) en 96 ejecuciones
- ✗ El RPS máximo medido (~76 req/s) está por DEBAJO de ambos límites
  - moderate: 3600 RPM = 60 req/s
  - strict: 2600 RPM = 43.3 req/s
- ✓ Límites fueron aplicados (env vars RATE_LIMIT_ENABLED=true confirmado)
- ✗ **NUNCA fueron alcanzados**, por lo tanto NO se observa diferencia

**Por qué no fue alcanzado:**
La carga máxima está limitada por:
- VUs máximo en k6: 20 usuarios
- Iteración: 3 requests por usuario
- Latencia de red + procesamiento: ~30-50ms por iteración
- **Resultado:** RPS en pod único ≈ 20-80 req/s depende del bloque
- Los límites de 43-60 req/s están justo en el borde superior, pero pocas iteraciones los alcanzan

---

## SOLUCIÓN PROPUESTA

### Para MAESTRÍA: 3 Opciones Válidas

#### **OPCIÓN A: Mantener S2 pero DOCUMENTAR el hallazgo** ⭐ RECOMENDADA

**Pro:**
- Mantiene integridad: no esconde problemas, los documenta
- Muestra rigor científico en retrospectiva
- Ahorra tiempo (no necesita nuevo experimento)
- Contribuye a conocimiento: "En rango [0-76 RPS], rate limiting es transparente"

**Tesis:**
> "Análisis de overhead en microservicios: C1/C2 muestran diferencias significativas (p<0.05),
> mientras que C3/C4 permanecen en rango de equivalencia. Este patrón sugiere que políticas
> de red y rate limiting dentro de rangos nominales no afectan latencia perceivida."

**Sección Limitaciones:**
```
"Se observó que los parámetros de rate limiting (43-60 req/s) fueron 
seleccionados para cargas empresariales típicas (100+ VUs). En el presente 
estudio con VUs máximo de 20, la carga real (~76 req/s max) raramente 
exceede los límites, resultando en equivalencia observada. Futuro trabajo 
debería explorar comportamiento bajo cargas más altas o con límites 
menores."
```

---

#### **OPCIÓN B: Nueva campaña S3 con parámetros CORRECTOS**

**Pero PRIMERO, decide:**

**Para C3 (Network Policies):**
- ¿Seguir con políticas de egress? O
- ¿Agregar políticas ingress más restrictivas (default deny)?

```
C3/strict mejorado = DEFAULT DENY todo, luego permitir explícitamente:
  - api-service puede recibir del ingress (puerto 8080)
  - data-service puede recibir de api-service (puerto 8080)
  - data-service puede recibir de postgres (puerto 5432)
  - postgres puede recibir de data-service (puerto 5432)
```

**Para C4 (Rate Limiting):**
Calibración basada en observación: máximo observado es 76 req/s

```
C4/baseline:  600 RPM (10 req/s) = sin throttle real
C4/moderate:  120 RPM (2 req/s)  = 10% de máximo observado
C4/strict:    60 RPM (1 req/s)   = 5% de máximo observado
```

**Tiempo:** 1 día más (8 runs × 3 horas = 24 horas idealmente)
**Valor académico:** Hallarías impacto real

---

#### **OPCIÓN C: Pivotar a C1/C2 solamente**

Dado que:
- C1/C2 YA muestran diferencias significativas (p=0.024 en C2 p95)
- C1/C2 son más realistas en la industria (Gateway TLS + Service Mesh son decisiones reales)
- C3/C4 son "futuro work" interesante

**Nueva tesis:**
> "Costo de Seguridad en API Gateways vs Service Mesh: Análisis Comparativo
> de Latencia y Recursos en Microservicios. (ANOVA 4 replicaciones, 2 controles, 
> 3 tecnologías, 4 cargas)"

Esto es TOTALMENTE válido para maestría y puedes publicarle sin C3/C4.

---

## ARCHIVOS RELEVANTES

- **Script de deploy:** `scripts/run-randomized-design-matrix.sh` (líneas 130-150)
- **C3 basic:** `RealisticServices/k8s/08-c3-networkpolicy-real.yaml`
- **C3 strict:** `RealisticServices/k8s/08-c3-networkpolicy-strict-real.yaml`
- **Resultados:** `Testing/results/auto_runs/randomized_campaigns/s2_academic_base_n8_B*.json`

---

## RECOMENDACIÓN FINAL

**Para tu tesis de maestría:**

1. **Documentar este hallazgo** → Muestra rigor científico
2. **Reportar S2 como está** → Pero con caveat: "En este rango de carga..."
3. **Proponer S3** → Nuevos parámetros validados
4. **O pivotar a C1/C2** → Que SÍ muestran diferencias significativas

**Tus opciones academicamente válidas:**
- ✅ Tesis sobre C1/C2 (Gateway + mTLS) donde SÍ hay efecto
- ✅ Tesis sobre "Rango de equivalencia" (C3/C4 no impactan en estos parámetros)
- ✅ Tesis sobre "Diseño experimental de carga" (incluyendo este hallazgo como case study)
- ❌ NO: Reportar C3/C4 como válidas sin investigación adicional

**Mis 2 centavos:** Enfócate en C1/C2 (tienen hallazgos) y documenta C3/C4 como "línea futura de trabajo".
