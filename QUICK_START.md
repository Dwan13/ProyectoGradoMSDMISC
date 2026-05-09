# 🚀 COMIENZA AQUÍ - Guía Rápida de Ejecución

Este archivo te guía paso a paso para ejecutar la experimentación completa en muBench.

## 📍 Tu Situación Actual

✅ **Máquina**: AMD Ryzen 5 3600 (6 cores) + 16GB RAM
✅ **SO**: Windows 10/11 con WSL2
✅ **Proyecto**: muBench con 12 escenarios implementados (C1-C4)
✅ **Estado**: Campaña previa completada (1 VU × 12 escenarios)

## ⚙️ Requisito: Aumentar Recursos de WSL2

**CRÍTICO**: Tu WSL2 está limitado a 4 cores + 7.8GB. Necesita 6 cores + 12GB.

### En Windows (PowerShell como Admin):

```powershell
# 1. Crear/editar C:\Users\<TuUsuario>\.wslconfig
notepad $env:USERPROFILE\.wslconfig

# 2. Pegar contenido (crea el archivo si no existe):
```

```ini
[wsl2]
memory=12GB
processors=6
swap=4GB
localhostForwarding=true
```

```powershell
# 3. Guardar y reiniciar WSL
wsl --shutdown
```

### En WSL2 (verificar):

```bash
nproc          # Debe mostrar 6
free -h        # Debe mostrar ~12GB
```

---

## 🎯 Flujo de Ejecución

### Opción A: Ejecutar Todo (Recomendado para Producción)

```bash
cd ~/muBench

# 1. BENCHMARK COMPLETO (1 VU × 12 escenarios)
bash scripts/run-all-controls-experiments.sh
# ⏱️ Tiempo: 20-30 minutos
# 📊 Salida: Testing/results/auto_runs/*.json

# 2. TEST DE ESCALABILIDAD (1→5→10→20 VUs)
bash scripts/run-scaling-tests.sh
# ⏱️ Tiempo: 40-60 minutos
# 📊 Salida: Testing/results/scaling_tests/scaling-report_*.csv
```

### Opción B: Tests Individuales (Para Validación Rápida)

```bash
# Test un escenario con VUs específicos
bash scripts/run-k6-benchmark.sh \
  --control C1 --variant baseline --vus 1 --duration 60

bash scripts/run-k6-benchmark.sh \
  --control C2 --variant istio-mtls --vus 5 --duration 60

# Dry-run (solo ver configuración)
bash scripts/run-k6-benchmark.sh \
  --control C3 --variant strict --vus 10 --dry-run
```

### Opción C: Setup desde Cero

Si necesitas empezar desde cero:

```bash
# Setup completo (instala MicroK8s, despliega servicios, etc.)
bash scripts/full-project-setup.sh
# ⏱️ Tiempo: 15-30 minutos

# Luego ejecuta tests
bash scripts/run-all-controls-experiments.sh
```

---

## 📊 Entender los Resultados

### Después de Ejecutar Tests

```bash
# Ver archivos generados
ls -lh Testing/results/auto_runs/
ls -lh Testing/results/scaling_tests/

# Ver resumen CSV (si existe)
cat Testing/results/scaling_tests/scaling-report_*.csv

# Ver logs de último test
tail -100 /tmp/*.log
```

### Interpretar Resultados

**Cada test produce JSON con estas métricas**:
- `checks`: % de validaciones exitosas (>95% es bueno)
- `p95`: Latencia percentil 95 (en ms)
- `error_rate`: % de requests que fallaron
- `http_reqs`: Total de requests completados
- `cpu_mC`: CPU usado (milicores)
- `memory_MiB`: Memoria usada (megabytes)

**Ejemplo de análisis**:
```
C1_baseline (1 VU):   p95=18.72ms, checks=100%, cpu=51mC
C1_istio (1 VU):      p95=17.74ms, checks=100%, cpu=46mC (mejor!)
C1_kong (1 VU):       p95=18.61ms, checks=100%, cpu=50mC

Conclusión: Istio Gateway tiene MEJOR rendimiento que NGINX Ingress
```

---

## 🎛️ Controles Explicados

### C1: API Gateways
- **baseline**: NGINX Ingress (referencia)
- **istio**: Istio Gateway con Envoy proxy
- **kong**: Kong Ingress Controller

**Qué mide**: Overhead de la capa de ingress

### C2: Service Mesh (mTLS)
- **baseline**: Sin service mesh
- **istio-mtls**: Istio con mutual TLS automático
- **linkerd-mtls**: Linkerd service mesh

**Qué mide**: Costo de encripción entre servicios (~40% más lento con Istio)

### C3: Network Policies
- **baseline**: Sin restricciones
- **basic**: Políticas permisivas
- **strict**: Políticas muy restrictivas

**Qué mide**: Impacto de firewall intra-cluster (negligible)

### C4: Rate Limiting
- **baseline**: Sin límite
- **moderate**: 120 requests/minuto
- **strict**: 20 requests/minuto (bloquea 41% de requests)

**Qué mide**: Efectividad del rate limiting en reducir carga

---

## 🔍 Monitoreo en Tiempo Real

Mientras se ejecutan tests, puedes monitorear:

### Terminal 1: Ver estado de pods
```bash
kubectl get pods -n realistic -w
```

### Terminal 2: Ver uso de CPU/memoria
```bash
watch kubectl top pods -n realistic
```

### Terminal 3: Ver logs del servicio
```bash
kubectl logs -n realistic deployment/api-service -f
```

### Grafana (UI):
- Abre: http://localhost:30001
- Login: admin / prom-operator
- Ver dashboard "muBench" para gráficos en tiempo real

---

## 📈 Escalabilidad Recomendada

Con tu máquina (6 cores, 12GB):

| VUs | Viable? | Tiempo | Notas |
|---|---|---|---|
| 1 | ✅ Sí | 20 min | Baseline (completo) |
| 5 | ✅ Sí | 40 min | Recomendado para validar |
| 10 | ⚠️ Marginal | 60 min | Monitorear CPU/RAM |
| 20 | ❌ No | - | Requiere cluster real |

**Mi recomendación**: Ejecuta `run-scaling-tests.sh` que automáticamente detiene si supera thresholds.

---

## 🆘 Troubleshooting Rápido

### Error: "Connection refused" en smoke test

```bash
# Verificar que servicios estén corriendo
kubectl get pods -n realistic

# Ver logs del servicio
kubectl logs -n realistic deployment/api-service

# Reiniciar
kubectl rollout restart deployment/api-service -n realistic
```

### Error: "Out of Memory"

```bash
# Aumentar WSL2 memory (ver arriba)
# O reducir VUs en scripts/run-scaling-tests.sh
```

### Error: "k6 threshold failure"

Nota: **C4 strict está diseñado para fallar al bloquear 41% de requests.** Es intencional.

Para otros, ver: `Docs/SETUP_GUIDE.md` Sección Troubleshooting

---

## 📚 Documentación Completa

Para detalles técnicos profundos:
- **[Docs/SETUP_GUIDE.md](../Docs/SETUP_GUIDE.md)** - Guía técnica completa (100+ páginas)

Para scripts específicos:
- **[scripts/run-k6-benchmark.sh](scripts/run-k6-benchmark.sh)** - Wrapper de k6 unificado
- **[scripts/run-scaling-tests.sh](scripts/run-scaling-tests.sh)** - Tests progresivos (1→5→10→20)
- **[scripts/full-project-setup.sh](scripts/full-project-setup.sh)** - Setup desde cero

---

## 💡 Quick Commands

```bash
# START: Full campaign (1 VU)
bash scripts/run-all-controls-experiments.sh

# START: Scaling tests (5/10/20 VUs)
bash scripts/run-scaling-tests.sh

# START: Single test
bash scripts/run-k6-benchmark.sh --control C1 --variant istio --vus 5

# SETUP: Fresh install
bash scripts/full-project-setup.sh

# MONITOR: Real-time pods
kubectl get pods -n realistic -w

# MONITOR: Real-time resources
watch kubectl top pods -n realistic

# VIEW: Results
ls Testing/results/auto_runs/*.json
cat Testing/results/scaling_tests/scaling-report_*.csv

# VIEW: Logs
kubectl logs -n realistic deployment/api-service -f

# DASHBOARD: Grafana
open http://localhost:30001   # macOS
start http://localhost:30001  # Windows
```

---

## 🎓 Próximos Pasos Después de Tests

1. **Analizar resultados**:
   ```bash
   python3 Testing/analyze_k6_results.py \
     --input-dir Testing/results/auto_runs/ \
     --output Testing/results/summary.csv
   ```

2. **Generar gráficos**:
   ```bash
   python3 Testing/generate_plots.py \
     --input Testing/results/summary.csv \
     --output Testing/plots/
   ```

3. **Documentar hallazgos**:
   - Crear reporte en Markdown
   - Incluir gráficos de comparativa
   - Análisis de overhead por control
   - Recomendaciones de escalabilidad

---

## 🤝 Soporte y Contacto

Si tienes problemas:
1. Revisa `Docs/SETUP_GUIDE.md` Sección Troubleshooting
2. Verifica que WSL2 esté configurado correctamente
3. Asegúrate de tener 6 cores + 12GB en WSL2
4. Ejecuta `kubectl cluster-info` para validar cluster

---

**¡Listo! Comienza con `bash scripts/run-scaling-tests.sh` o `bash scripts/run-all-controls-experiments.sh`**

✨ Happy Benchmarking! ✨
