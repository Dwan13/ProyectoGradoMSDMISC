# Dual-Maestría Defense Narrative
## Sistemas y Computación + Seguridad Digital

**Candidato:** Felipe Dwan  
**Fecha:** Mayo 2026  
**Título de Investigación:** *Security-Quality Trade-off Analysis in Microservices: A Systematic Evaluation of Control Mechanisms Under Advanced Threat Scenarios*

---

## 1. PROBLEMA & MOTIVACIÓN

### Contexto
Los microservicios han revolucionado la arquitectura de sistemas distribuidos, ofreciendo escalabilidad, flexibilidad y resiliencia. Sin embargo, esta arquitectura inherentemente distribuida introduce nuevos vectores de ataque y desafíos de seguridad que históricamente no existían en monolitos:

- **Comunicación inter-servicio**: Tráfico de red interno expuesto a sniffing/tampering
- **Manejo de identidad distribuida**: Múltiples puntos de autenticación y autorización
- **Surface de ataque expandida**: N servicios × M endpoints = N×M puntos de entrada

### Problema de Investigación
**¿Cómo pueden los equipos de operaciones balancear efectivamente las exigencias de seguridad con los objetivos de calidad (latencia, throughput, disponibilidad) en sistemas microservicios bajo presión operacional y amenaza real?**

Más específicamente:
1. ¿Qué mecanismos de control de seguridad son más efectivos contra amenazas específicas?
2. ¿Cuál es el costo operacional (CPU, memoria, latencia) de cada control?
3. ¿Existe una estrategia de defensa óptima que balancea múltiples objetivos?

### Hipótesis
**H1 (Seguridad):** Diferentes vectores de ataque requieren diferentes mecanismos de control para ser efectivos. Un control monolítico (ej: solo mTLS) será insuficiente contra un atacante adaptativo.

**H2 (Performance):** Los controles de seguridad incurren en overhead medible de latencia, CPU y memoria, pero este overhead está correlacionado con la efectividad defensiva (no es "gratis").

**H3 (Estrategia):** Existe una combinación de controles que maximiza defensa relativa a costo operacional, alcanzable sin sacrificar significativamente la calidad de servicio.

---

## 2. CONTRIBUCIONES CIENTÍFICAS

### 2.1 Dimensión: Sistemas y Computación Distribuidos

#### 2.1.1 Medición Rigurosa de Performance bajo Carga Adversarial
**Contribución:** Framework experimental sistemático para medir trade-offs de performance en presencia de ataque.

- **Metodología**: Diseño experimental factorizado (4 controles × 3 variantes × 4 niveles de carga × 2 modos de seguridad × 4 replicados = 384 observaciones independientes)
- **Rigor**: Bloques aleatorizados (randomized blocks) para minimizar confounding de máquina/tiempo
- **Métricas**: 6 dimensiones simultáneas (latencia p50/p95, error%, throughput, CPU, memoria)
- **Escala**: Carga progresiva (1-20 VUs) para capturar comportamiento en régimen no-lineal

**Impacto académico:** Demuestra que la evaluación rigurosa de sistemas requiere múltiples dimensiones y no puede reducirse a un solo KPI.

#### 2.1.2 Cuantificación de Overhead de Seguridad
**Contribución:** Modelo explícito del costo operacional de defensa.

- **Hallazgo consolidado** (384 runs):
  - C1: overhead CPU promedio +12.1% (normal vs attack)
  - C2: overhead CPU promedio +12.3% (mayor costo absoluto)
  - C3: overhead CPU promedio +10.2%
  - C4: overhead CPU promedio +9.0%

- **Insight**: El overhead no es uniforme; varía por control, variante, carga y modo de operación. Esto requiere modelado sofisticado.

#### 2.1.3 Escalabilidad Diferencial bajo Carga
**Contribución:** Análisis de cómo diferentes controles escalan con aumento de carga.

**Observación consolidada (384 runs):**
- Efectos de carga, control y modo son estadísticamente fuertes en err_pct (R²=0.9235) y cpu_mcores (R²=0.8678).
- avg_ms también muestra efecto sistemático relevante (R²=0.5730).
- La combinación control-variante-vus presenta comportamiento no lineal en latencia para perfiles estrictos.

**Hipótesis**: mTLS incurre en overhead de negociación TLS que se amplifica con concurrencia.

### 2.2 Dimensión: Seguridad Digital

#### 2.2.1 Modelo de Amenaza Operacionalizado con Vectores Reales
**Contribución:** Traducción de amenazas conceptuales (OWASP, STRIDE) a ataques ejecutables.

**5 Vectores de Ataque Avanzados Implementados:**

| Vector | Descripción | Atacante Model | Probabilidad |
|--------|-------------|----------------|--------------|
| **bad-login** | Credenciales inválidas (brute force) | Automated | HIGH |
| **unauth** | Solicitud sin token/cookie | Automated | MEDIUM |
| **token-tamper** | JWT modificado/expirado | Adaptive | MEDIUM |
| **bearer-malformed** | Header Authorization malformado | Automated | HIGH |
| **xff-spoof** | X-Forwarded-For spoofing | Sophisticated | MEDIUM |

**Rigor**: No asumimos atacantes "genéricos". Cada vector mapea a técnica específica (injection, circumvention, replay) y capacidad de atacante.

#### 2.2.2 Matriz de Efectividad Control-Amenaza (Formal STRIDE/CIA)
**Contribución:** Modelo explícito de cuál control es efectivo contra cuál amenaza.

**Hallazgo consolidado (384 runs, modo attack):**

| Vector | C1 (Gateway) | C2 (mTLS) | C3 (NetPol) | C4 (RateLimit) |
|--------|--------------|-----------|-------------|----------------|
| bad-login | LOW | **HIGH** | LOW | MEDIUM |
| unauth | MEDIUM | **HIGH** | LOW | MEDIUM |
| token-tamper | LOW | **HIGH** | LOW | MEDIUM |
| bearer-malformed | **HIGH** | HIGH | LOW | LOW |
| xff-spoof | LOW | LOW | **HIGH** | LOW |

**Insight**: No existe un "silver bullet". Cada amenaza requiere múltiples capas y el riesgo residual varía por vector.

La matriz final incluye metadatos formales por vector: categoría STRIDE, propiedad CIA prioritaria, perfil de atacante, activo impactado y riesgo residual. Esta estructura permite responder explícitamente "qué propiedad de seguridad se está defendiendo" y evita sobreafirmar seguridad integral.

#### 2.2.3 Quantificación de Defensa vs Costo
**Contribución:** Marco economía de la seguridad: ¿cuánta defensa obtenemos por unidad de overhead?

**Métrica propuesta:** Defense-to-Cost Ratio = (1 - Attack Error Rate) / CPU Overhead

**Ejemplo (384 runs):**
- C2: err_pct promedio attack=70.0 con overhead CPU +12.3%.
- C3: err_pct promedio attack=76.67 con overhead CPU +10.2%.
- C4: err_pct promedio attack=70.0 con overhead CPU +9.0%.

Interpretación: el mejor punto no es un control único, sino selección por vector de amenaza con presupuesto de CPU/memoria.

### 2.3 Integración: Dual-Maestría
**Contribución principal:** Demostración de que evaluación rigurosa de sistemas requiere simultáneamente:

1. **Pensamiento de sistemas**: Múltiples métricas, interacciones, efectos no-lineales
2. **Pensamiento de seguridad**: Modelo de amenazas, controles específicos, adversarial thinking

No es posible estudiar uno sin el otro en contexto microservicios real.

---

## 3. DESIGN EXPERIMENTAL

### 3.1 Variables Independientes (Factores)

| Factor | Niveles | Justificación |
|--------|---------|---------------|
| **Control** | C1, C2, C3, C4 | Capas de defensa (gateway, auth, network, ratelimit) |
| **Variante** | 3 por control | Baselline, intermediate, strict |
| **Carga (VUs)** | 1, 5, 10, 20 | Cobertura régimen lineal & congestion |
| **Modo Seguridad** | normal, attack | Carga legítima vs 70% probes maliciosas |
| **Bloque** | B1, B2, B3, B4 | Randomización temporal para confounding |
| **Réplica** | 4 por celda | Power análisis exigencia n≥4 |

**Total**: 4 × 3 × 4 × 2 × 4 = 384 observaciones

### 3.2 Variables Dependientes (Métricas)

| Métrica | Definición | Justificación |
|---------|-----------|---------------|
| **avg_ms** | Latencia promedio (HTTP duration) | QoS usuario |
| **p95_ms** | Percentil 95 latencia | SLA tail latency |
| **err_pct** | Porcentaje de requests fallidas | Disponibilidad/defensa |
| **rps** | Requests por segundo | Throughput/escalabilidad |
| **cpu_mcores** | CPU en millicores (Prometheus) | Costo operacional |
| **mem_mib** | Memoria en MiB (Prometheus) | Costo operacional |

### 3.3 Diseño: Randomized Blocks

**Motivación**: Los microservicios son sistemas vivos; cada día puede tener variación de carga de fondo, GC events, etc.

**Estrategia**: 
- Dividir 384 runs en 4 bloques (B1-B4) = 96 runs cada uno
- Dentro de cada bloque, randomizar orden de ejecución
- Incluir bloque como efecto aleatorio en modelo mixto

**Justificación**: Captura variabilidad temporal sin confunding.

### 3.4 Perfil de Ataque: 70% Malicioso / 30% Legítimo

**Motivación**: Atacante adaptativo mantiene traffic "natural" para evasión.

**Vectores por run (modo attack):**
```
De 100 requests:
- 30 requests: Login legítimo + flow normal (valida defensa no rompe usuarios reales)
- 21 requests: bad-login (brute force credentials)
- 21 requests: token-tamper (modify JWT)
- 14 requests: bearer-malformed (invalid headers)
- 14 requests: xff-spoof (spoofed source IPs)
```

---

## 4. HALLAZGOS CONSOLIDADOS (384 Runs)

### 4.1 Performance Bajo Ataque (Consolidado)

**Métricas globales del modelo (384 runs):**
- R² avg_ms = 0.5730
- R² err_pct = 0.9235
- R² cpu_mcores = 0.8678

**Respuesta bajo ataque por familias de control (promedios):**
- C1: err 76.67%, latencia 5.60 ms
- C2: err 70.00%, latencia 8.54 ms
- C3: err 76.67%, latencia 206.45 ms (penalizada por variante strict)
- C4: err 70.00%, latencia 7.62 ms

**Insight**: El costo/beneficio cambia por variante y carga; por eso la interpretación correcta es por matriz amenaza-control-costo y no por promedio aislado.

### 4.2 Efectividad de Control por Vector (Con Riesgo Residual)

- **bad-login**: C2 alto, C4 medio, C1/C3 bajo
- **unauth**: C2 alto, C1/C4 medio, C3 bajo
- **token-tamper**: C2 alto, C4 medio, C1/C3 bajo
- **bearer-malformed**: C1/C2 alto, C4 medio, C3 bajo
- **xff-spoof**: C3 alto, C1/C2/C4 bajo

Interpretación defensiva: la evidencia respalda resiliencia operativa bajo carga adversarial, pero no prueba seguridad criptográfica integral ni resistencia total a bypass internet-scale.

### 4.3 Resource Overhead Cuantificado

| Control | CPU Normal (mC) | CPU Attack (mC) | Overhead |
|---------|------------------|------------------|----------|
| C1 | 218.8 | 245.2 | +12.1% |
| C2 | 352.1 | 395.4 | +12.3% |
| C3 | 211.7 | 233.2 | +10.2% |
| C4 | 310.4 | 338.2 | +9.0% |

**Key**: C2 presenta mayor costo absoluto de CPU y C4 un costo intermedio, ambos con mejoras operativas frente a tráfico adversarial según vector.

---

## 5. IMPLICACIONES PARA DEFENSA DUAL-MAESTRÍA

### 5.1 Tesis para Sistemas y Computación

> **"La evaluación rigurosa de sistemas distribuidos requiere diseño experimental factorial con múltiples dimensiones de performance bajo condiciones adversariales realistas. El overhead de seguridad no es uniforme; varía no-linealmente con carga, arquitectura de control y modo de operación. Un modelo mixto capturando estas interacciones es esencial para toma de decisiones operacional."**

**Evidencia**: 384 observaciones independientes, 6 métricas, 4 niveles de carga, 2 modos, 4 replicados.

### 5.2 Tesis para Seguridad Digital

> **"La defensa efectiva contra amenazas avanzadas en microservicios requiere estrategia multi-capa donde cada control mapea específicamente a amenazas concretas. No existe control singular que mitigue todos vectores. La matriz control-amenaza, cuantificada con carga adversarial, es herramienta esencial para arquitectura de seguridad defensible."**

**Evidencia**: 5 vectores de ataque operacionalizados, matriz 4×5 de efectividad, validación bajo 70% traffic malicioso.

### 5.3 Integración: Diseño de Defensa Óptimo

**Recomendación emergente** (validada con 384 runs):

```
Defensa Estratificada:
Nivel 1: API Gateway (C1) → Valida format, bloques malformed headers
Nivel 2: mTLS + Auth (C2) → Valida identidad, JWT signature
Nivel 3: Network Policies (C3) → Bloquea source spoofing, non-auth IPs
Nivel 4: Rate Limiting (C4) → Frena brute force de multiple capas
```

**Costo**: Overhead promedio por familia entre 9.0% y 12.3% en CPU entre modos normal/attack.  
**Beneficio**: Mejoras operativas dependientes de vector y variante (no existe ganador único).  
**ROI**: Justificado para servicios críticos cuando se aplica defensa en profundidad por riesgo.

---

## 6. CONTRIBUCIÓN A CUERPO DE CONOCIMIENTO

### 6.1 Para Comunidad Académica
1. **Framework experimental reproducible** para evaluar seguridad en microservicios
2. **Cuantificación rigurosa** del trade-off security-performance
3. **Threat model operacionalizado** con vectores reales

### 6.2 Para Industria / Operaciones
1. **Guía de selección de controles** basada en amenaza específica
2. **Modelo de costo** para planificación de infraestructura
3. **Playbook de defensa estratificada** para equipos de DevSecOps

---

## 7. LIMITACIONES & TRABAJO FUTURO

### 7.1 Limitaciones Actuales (Explícitas para Jurado)
- **Alcance del claim**: Este estudio demuestra seguridad operativa bajo carga adversarial, no seguridad integral certificada.
- **Propiedades cubiertas**: Disponibilidad y comportamiento de enforcement en presencia de ataques sintéticos.
- **Propiedades no cerradas**: Validación criptográfica profunda (cipher suites, key rotation, hardening de secretos) y no repudio.
- **Bypass avanzado**: No se validó evasión internet-scale (rotación distribuida de IP/proxy chaining).
- **Validez externa**: Single-cluster; resultados pueden variar en otras topologías/cloud providers.
- **Rigor estadístico**: Los diagnósticos ANOVA evidencian desviaciones de normalidad/homoscedasticidad, por lo que se interpreta como evidencia direccional fuerte y no prueba paramétrica perfecta.

### 7.2 Extensiones Futuras
1. **Ataques combinados**: Coordinar múltiples vectores en una sola sesión
2. **Adaptive attacks**: Atacante que aprende y ajusta estrategia
3. **Escalabilidad 10k+ VU**: Validar no-linearidades a escala producción
4. **Otros workloads**: Evaluar con patrones de acceso realistas (Zipf, temporal locality)
5. **Modelado robusto**: Incorporar MixedLM completo y/o errores robustos/GLM para reforzar inferencia estadística
6. **Validación criptográfica**: Auditoría formal de mTLS/JWT/secrets management

---

## 8. CONCLUSIÓN

Esta investigación dual-maestría demuestra que **la seguridad en microservicios no es un add-on; es un componente integral del diseño de sistemas que requiere evaluación rigurosa, pensamiento sistémico y validación empírica**.

Los 384 runs del S6 campaign proporcionarán evidencia suficiente para defender ambas dimensiones:
- **Sistemas**: Metodología experimental rigurosa, medición multi-dimensional, análisis de interacciones
- **Seguridad**: Modelo de amenazas concreto, matriz de controles específicos, cuantificación de defensa

Juntas, estas contribuciones ofrecen framework defendible para arquitectos de seguridad y equipos de operaciones.

---

**Estado**: Narrativa actualizada con 384 runs completos y evidencia consolidada.  
**Siguiente**: Integración final con apéndice de reproducibilidad externa.  
**Target**: Defensa dual-maestría Junio 2026.
