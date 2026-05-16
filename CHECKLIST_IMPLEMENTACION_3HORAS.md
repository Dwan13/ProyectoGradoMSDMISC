# CHECKLIST DE IMPLEMENTACIÓN: 3 HORAS PARA TESIS DEFENSIBLE

## FASE 1: LIMPIAR MÉTRICA CONTAMINADA (45 min)

**Objetivo:** Separar err_pct en dos métricas limpias

- [ ] **Ejecutar:** `python3 Testing/extract_clean_metrics.py`
  - Input: `Testing/results/auto_runs/randomized_campaigns/s6_integrated_dual_n4_*.json` (385 NDJSON files)
  - Output: `Testing/results/s6_integrated_clean_metrics.csv` (384 rows con 2 columnas nuevas)
  - Columnas nuevas:
    - `legitimate_error_pct`: Errores en ops legítimas (0% si todo OK)
    - `attack_blocked_pct`: % de ataques bloqueados (100% es máximo, 70% significa incompleto)

- [ ] **Verificar:** Revisar output
  ```bash
  head -5 Testing/results/s6_integrated_clean_metrics.csv | cut -d, -f1-12
  # Debe mostrar: control,variant,security_mode,vus,avg_ms,p95_ms,err_pct,rps,cpu_mcores,mem_mib,legitimate_error_pct,attack_blocked_pct
  ```

- [ ] **Interpretar:** 
  - Attack mode row con legitimate_error_pct=0, attack_blocked_pct=70% significa:
    - Legítimas pasaron OK (0% error)
    - Ataques fueron bloqueados (70% del total eran ataques que se bloquearon exitosamente)
    - ✓ Sistema está funcionando correctamente

---

## FASE 2: ARREGLAR ANÁLISIS ESTADÍSTICO (1 hora)

**Objetivo:** Usar MixedLM en lugar de OLS, con replicates como random effects

- [ ] **Ejecutar:** `python3 Testing/s6_statistical_analysis_corrected.py`
  - Input: `Testing/results/s6_integrated_clean_metrics.csv`
  - Output directory: `Testing/results/s6_analysis_corrected/`
  - Archivos generados:
    - `mixed_model_summary.csv` (resultados ANOVA con MixedLM)
    - `threat_model_clean.csv` (matriz amenazas con attack_blocked_pct)

- [ ] **Revisar output:**
  ```bash
  cat Testing/results/s6_analysis_corrected/mixed_model_summary.csv
  # Debe mostrar: model_type=MixedLM, random_effects_std (varianza entre replicas)
  ```

- [ ] **Interpretar cambios vs. OLS antiguo:**
  - R² podría variar ligeramente (MixedLM vs OLS)
  - Random intercept stderr = variabilidad entre replicas (normal)
  - p-values siguen siendo significativos (p<0.001 en effects principales)

---

## FASE 3: REESCRIBIR DOCUMENTACIÓN DE SCOPE (1 hora)

**Objetivo:** Tesis defensible con claims honestos

### 3a. Título y Abstract (15 min)

- [ ] **Cambiar título en tesis a:**
  ```
  "Quantifying Security-Performance Trade-offs in Kubernetes Microservices: 
   An Experimental Evaluation of Control Implementations Under Synthetic Adversarial Load"
  ```

- [ ] **Reemplazar abstract con texto de CHANGE 1 en THESIS_SCOPE_REWRITE_COMPLETO.md**

### 3b. Methods Section (20 min)

- [ ] **Reemplazar Methods section con contenido de CHANGE 2:**
  - Experimental Design (factorial matrix)
  - Load Testing Protocol (k6 config)
  - Metrics Collection (primary, secondary, tertiary)
  - Statistical Analysis (Mixed LM formula)

### 3c. Limitations Section (20 min)

- [ ] **Reemplazar Limitations CON texto BRUTAL de CHANGE 3:**
  - DEBE incluir: "Single cluster", "Synthetic attacks", "Metric contamination"
  - DEBE incluir: "No baseline comparison", "No field validation"
  - **IMPORTANTE:** Evita "estos son limitaciones menores"; escribe honestamente

### 3d. Threat Model Table (5 min)

- [ ] **Copiar tabla de CHANGE 6** (Control Effectiveness matriz)
- [ ] **Reemplazar valores** con datos reales del output de Fase 2:
  ```bash
  cat Testing/results/s6_analysis_corrected/threat_model_clean.csv
  ```

---

## FASE 4: VERIFICACIÓN FINAL (15 min)

### 4a. Verificar que NO haces claims falsos

- [ ] ❌ Eliminar cualquier mención de "validated against field attacks"
- [ ] ❌ Eliminar "recommended for production"
- [ ] ✅ Reemplazar con "controlled environment", "synthetic threats"

- [ ] Buscar en tesis por palabras peligrosas:
  ```bash
  grep -i "real.*attack\|field.*test\|production.*ready" thesis.docx 2>/dev/null || echo "✓ OK"
  ```

### 4b. Verificar que scripts se ejecutan sin error

```bash
cd /home/dwan13/muBench

# Test 1: Clean metrics extraction
python3 Testing/extract_clean_metrics.py 2>&1 | tail -5
# Esperado: "Saved clean metrics to: Testing/results/s6_integrated_clean_metrics.csv"

# Test 2: Statistical analysis
python3 Testing/s6_statistical_analysis_corrected.py 2>&1 | tail -10
# Esperado: "Summary saved to: Testing/results/s6_analysis_corrected/mixed_model_summary.csv"

# Test 3: Verify data files exist
ls -lah Testing/results/s6_integrated_clean_metrics.csv
# Esperado: archivo con size > 10KB

ls -lah Testing/results/s6_analysis_corrected/
# Esperado: 2-3 archivos CSV generados
```

### 4c. Spot-check datos crudos (confirmar no corrupted)

```bash
# Verificar S6 NDJSON sample
head -20 Testing/results/auto_runs/randomized_campaigns/s6_integrated_dual_n4_C1_baseline_normal_1_rep1_*.json | python3 -m json.tool | head -40
# Esperado: JSON válido, fields como "metric", "value", "tags"

# Verificar S2 NDJSON sample
head -20 Testing/results/auto_runs/randomized_campaigns/s2_min1vu_C1_baseline_1_*.json | python3 -m json.tool | head -40
# Esperado: JSON válido, similar estructura
```

---

## TABLA DE TIEMPO

| Fase | Tarea | Duración | Acumulado |
|------|-------|----------|-----------|
| 1 | Ejecutar extract_clean_metrics.py | 5 min | 5 min |
| 1 | Verificar output | 10 min | 15 min |
| 1 | Interpretar métricas limpias | 30 min | 45 min |
| 2 | Ejecutar s6_statistical_analysis_corrected.py | 10 min | 55 min |
| 2 | Revisar MixedLM output vs OLS antiguo | 30 min | 1h 25m |
| 2 | Entender random effects variance | 20 min | 1h 45m |
| 3 | Reescribir título, abstract, methods | 30 min | 2h 15m |
| 3 | Reescribir limitations brutales | 20 min | 2h 35m |
| 3 | Actualizar threat model tabla | 10 min | 2h 45m |
| 4 | Verificación final (claims falsos, scripts test) | 15 min | 3h 00m |

**Total: ~3 horas**

---

## DECISIONES A TOMAR AHORA

### Decisión 1: ¿Reescribir full thesis o solo Methods/Limitations?

- **Option A (Recomendado):** Solo actualizar Methods, Limitations, Threat Model, Abstract
  - Tiempo: 1-2 horas
  - Beneficio: Tesis defensible sin reescritura completa
  - Riesgo: Resto de tesis podría tener contradictions

- **Option B:** Reescribir full thesis (Introduction, Methods, Results, Discussion, Conclusions)
  - Tiempo: 5-8 horas
  - Beneficio: Tesis coherente de punta a punta
  - Riesgo: Mayor effort, pero mejor calidad

**Recomendación:** Option A (Methods + Limitations) ahora; Option B después si tiempo lo permite.

### Decisión 2: ¿Presentar S6 como "Scenario" o como "Experiment"?

**Current (Post-rewrite):** S6 = Integrated experiment (legitimate + attacks)

**Alternative:** Separar en:
- Exp 6a: Legitimate load only (= control)
- Exp 6b: Attack probes interspersed (= treatment)

**Recomendación:** Mantener S6 integrated (es más realista que separado).

### Decisión 3: ¿Incluir resultados de Scripts o solo análisis manual?

- **Option A:** Solo incluir en appendix (no contamina main text)
- **Option B:** Incluir en Results (pero declare OLS → MixedLM change)

**Recomendación:** Option B (declare change, es más transparente).

---

## PRÓXIMOS PASOS DESPUÉS DE LAS 3 HORAS

### Corto plazo (1-2 días)
1. Ejecutar 3 scripts
2. Reescribir scope en tesis
3. Generar plots finales con clean metrics
4. Hacer spot-check de datos crudos

### Mediano plazo (1 semana)
1. Presentar draft de Methods/Limitations a advisor
2. Incorporar feedback
3. Revisar si hay claims que todavía sean overreach

### Largo plazo (antes de defensa)
1. Full thesis review for consistency
2. Simulated defense Q&A (prepare for "pero ¿y en producción?")
3. Prepare rebuttal slides: "What we CAN claim" vs "What we CANNOT"

---

## CÓMO RESPONDER PREGUNTAS EN DEFENSA

| Pregunta | Respuesta ANTES | Respuesta DESPUÉS (Honesta) |
|---|---|---|
| "¿Validaron seguridad real?" | "Sí, con ataques sintéticos" ❌ | "No, con ataques sintéticos en ambiente controlado. Field testing recomendado." ✓ |
| "¿Por qué err_pct 70% en attack mode?" | "El sistema está fallando" ❌ | "70% de requests son attack probes bloqueados. Legítimas pasaron 100%. Métrica está contaminada." ✓ |
| "¿Qué control recomiendan?" | "C2 es mejor que C1" ❌ | "En nuestro test, C2 tiene overhead 45%. Cada control tiene trade-offs. Campo testing necesario." ✓ |
| "¿Generalizas a producción?" | "Seguramente sí" ❌ | "No. Single MicroK8s cluster, ataques sintéticos. Nuestro scope es muy específico." ✓ |

---

## ARCHIVOS CLAVE

### Documentos que YA CREÉ:
- [ARQUITECTURAS_S2_VS_S6_ANÁLISIS_HONESTO.md](ARQUITECTURAS_S2_VS_S6_ANÁLISIS_HONESTO.md) — Diagrama técnico
- [VEREDICTO_FINAL_1PAGINA.md](VEREDICTO_FINAL_1PAGINA.md) — Resumen ejecutivo
- [THESIS_SCOPE_REWRITE_COMPLETO.md](THESIS_SCOPE_REWRITE_COMPLETO.md) — Cambios específicos (copy/paste)

### Scripts que DEBES EJECUTAR:
- `Testing/extract_clean_metrics.py` — Genera CSV con métricas limpias
- `Testing/s6_statistical_analysis_corrected.py` — MixedLM ANOVA (reemplaza OLS)

### Datos existentes (verificados):
- `Testing/results/s6_integrated_all_6_metrics.csv` (384 rows original)
- `Testing/results/auto_runs/randomized_campaigns/s6_*.json` (385 files raw)
- `Testing/results/auto_runs/randomized_campaigns/s2_*.json` (634 files raw)

---

## ¿LISTO PARA COMENZAR?

```bash
cd /home/dwan13/muBench

# STEP 1: Run clean metrics extraction (5 min)
python3 Testing/extract_clean_metrics.py

# STEP 2: Run statistical analysis (10 min)
python3 Testing/s6_statistical_analysis_corrected.py

# STEP 3: Review outputs (10 min)
ls -lah Testing/results/s6_analysis_corrected/
head -5 Testing/results/s6_integrated_clean_metrics.csv

# STEP 4: Copy methods/limitations text (1h)
# From THESIS_SCOPE_REWRITE_COMPLETO.md → your thesis.docx

# DONE: Tesis defensible ✓
```

**¿Empezamos?**
