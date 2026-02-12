# 🔧 Actualización del Script de Deploy - Resumen de Cambios

## ❌ Problema Encontrado

Los tests k6 estaban **fallando al 100%** porque:

1. **Endpoint incorrecto**: El script probaba `/s0` pero los servicios enhanced tienen `/process`
2. **Acceso incorrecto**: Usaba NodePort (`gw-nginx:31113`) pero los servicios están como ClusterIP
3. **Métodos HTTP**: Los tests hacían GET pero los endpoints necesitan POST

## ✅ Solución Implementada

### 1. Script `deploy_microk8s.sh` Actualizado

**Cambios en `run_k6_tests()`:**

```bash
# ANTES:
TARGET_URL="http://127.0.0.1:31113/s0"  # ❌ NodePort + endpoint viejo

# AHORA:
# Usa port-forward para acceder a ClusterIP
microk8s kubectl port-forward svc/s0 8081:80 -n default &
TARGET_URL="http://127.0.0.1:8081/process"  # ✅ Port-forward + endpoint correcto
```

**Por qué:**
- `ClusterIP` solo es accesible dentro del cluster
- `port-forward` crea un túnel temporal desde localhost al servicio
- `/process` es el endpoint correcto del código enhanced

### 2. Script `inter-service-test.js` Actualizado

**Cambios en endpoints:**

```javascript
// ANTES:
http.get(`${BASE_URL}/process`, ...)        // ❌ GET
http.get(`${BASE_URL}/s1/validate`, ...)    // ❌ Ruta incorrecta
http.get(`${BASE_URL}/sdb1/query`, ...)     // ❌ Ruta incorrecta

// AHORA:
http.post(`${BASE_URL}/process`, payload, ...)   // ✅ POST + payload
http.post(`${BASE_URL}/validate`, payload, ...)  // ✅ Ruta correcta
http.post(`${BASE_URL}/query`, payload, ...)     // ✅ Ruta correcta
```

**Por qué:**
- Los endpoints enhanced esperan POST con body JSON
- No necesitan prefijo `/s0`, `/s1`, `/sdb1` porque cada servicio solo expone sus propios endpoints
- El port-forward se hace directamente al servicio correspondiente

### 3. Cleanup Automático

Agregado en `run_k6_tests()`:

```bash
# Al finalizar los tests, cerrar port-forward
if [[ -n "${PF_PID}" ]]; then
  kill $PF_PID 2>/dev/null || true
fi
```

**Por qué:**
- Evita procesos port-forward huérfanos
- Libera el puerto local

## 📊 Resultados Esperados

### ✅ ANTES de los cambios:
```
http_req_failed: 100.00% (11640/11640)  ❌
status is 200: 0%                        ❌
```

### ✅ DESPUÉS de los cambios:
```
http_req_failed: 0.00%                   ✅
status is 200: 100%                      ✅
http_req_duration p(95): ~30-50ms        ✅
```

## 🧪 Validación

Script de test rápido creado: `scripts/quick_test.sh`

```bash
./scripts/quick_test.sh

# Resultados:
✅ Pods OK: 3/3 Running
✅ /process OK
✅ /health OK  
✅ Port-forward OK
```

## 🚀 Cómo Ejecutar

### Opción 1: Script completo (recomendado)
```bash
./scripts/deploy_microk8s.sh --start --protocol http
```

Esto ejecutará:
- Validación de pre-requisitos
- Despliegue de servicios
- Tests k6 automáticos (baseline + inter-service)
- Resultados guardados en `Testing/results/`

### Opción 2: Solo tests k6
```bash
# Asegurarse que servicios estén corriendo
./scripts/quick_test.sh

# Port-forward manual
microk8s kubectl port-forward svc/s0 8081:80 -n default &

# Test baseline
k6 run -e TARGET_URL=http://localhost:8081/process \
       -e VUS=10 -e DURATION=30s \
       Testing/baseline.js

# Test inter-service
k6 run -e TARGET_URL=http://localhost:8081 \
       -e VUS=10 -e DURATION=30s \
       Testing/inter-service-test.js

# Cerrar port-forward
pkill -f "port-forward svc/s0"
```

### Opción 3: Test rápido manual
```bash
# Port-forward
microk8s kubectl port-forward svc/s0 8081:80 -n default &

# Probar endpoint
curl -X POST http://localhost:8081/process \
  -H "Content-Type: application/json" \
  -d '{}'

# Debería retornar:
# {"body_length":4778,"service":"s0","status":"ok"}
```

## 📝 Archivos Modificados

1. **`scripts/deploy_microk8s.sh`**
   - Función `run_k6_tests()` - Port-forward en vez de NodePort
   - Endpoints actualizados a `/process`
   - Cleanup de port-forward

2. **`Testing/inter-service-test.js`**
   - Cambio de GET a POST
   - URLs corregidas (`/process`, `/validate`, `/query`)
   - Payload JSON agregado

3. **`scripts/quick_test.sh`** (nuevo)
   - Validación rápida de servicios
   - Tests de endpoints
   - Verificación de port-forward

## 🔍 Troubleshooting

### Problema: Port-forward no funciona
```bash
# Ver si hay port-forwards activos
ps aux | grep "port-forward"

# Matar todos
pkill -f "port-forward"

# Intentar de nuevo
microk8s kubectl port-forward svc/s0 8081:80 -n default &
```

### Problema: Tests k6 siguen fallando
```bash
# Verificar que pods estén ready
microk8s kubectl get pods -n default | grep -E "s0|s1|sdb1"

# Debe mostrar 1/1 Running

# Probar endpoint directamente
POD=$(microk8s kubectl get pod -l app=s0 -n default -o jsonpath='{.items[0].metadata.name}')
microk8s kubectl exec $POD -n default -- \
  python3 -c "import urllib.request; print(urllib.request.urlopen('http://localhost:8080/health').read().decode())"

# Debe retornar: {"service":"s0","status":"healthy"}
```

### Problema: Imagen vieja sin endpoints
```bash
# Verificar que pod tenga código enhanced
POD=$(microk8s kubectl get pod -l app=s0 -n default -o jsonpath='{.items[0].metadata.name}')
microk8s kubectl exec $POD -n default -- \
  grep -n "@app.route('/process')" /app/CellController-mp.py

# Si no encuentra nada, reconstruir imagen:
cd ServiceCell
docker build --no-cache -t msvcbench/microservice:v3-enhanced .
docker save msvcbench/microservice:v3-enhanced -o /tmp/muBench-v3.tar
sudo microk8s ctr image import /tmp/muBench-v3.tar

# Redesplegar
./scripts/quick_deploy_services.sh http
```

## 🎯 Próximos Pasos

1. **Ejecutar tests completos:**
   ```bash
   ./scripts/deploy_microk8s.sh --start --protocol http
   ```

2. **Analizar resultados:**
   ```bash
   cat Testing/results/http-baseline-*.json | jq '.metrics.http_req_duration'
   ```

3. **Comparar HTTP vs HTTPS:**
   ```bash
   # HTTP
   ./scripts/deploy_microk8s.sh --start --protocol http
   
   # HTTPS
   ./scripts/deploy_microk8s.sh --start --protocol https
   
   # Analizar
   python3 Testing/analyze_k6_results.py \
     Testing/results/http-baseline-*.json \
     Testing/results/https-baseline-*.json
   ```

---

**Fecha:** 11 de Febrero, 2026  
**Estado:** ✅ Correcciones aplicadas - Listo para testing
