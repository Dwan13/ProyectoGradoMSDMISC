# 🔄 Instrucciones de Integración

## Cómo Usar el Código Nuevo (CellController-enhanced.py)

El archivo `ServiceCell/CellController-enhanced.py` contiene todas las mejoras. Para usarlo:

### Opción 1: Reemplazar el Original (Recomendado)

```bash
cd ~/muBench/ServiceCell

# Backup del original
cp CellController-mp.py CellController-mp.py.backup

# Reemplazar con versión mejorada
cp CellController-enhanced.py CellController-mp.py
```

### Opción 2: Modificar Dockerfile

Si prefieres mantener ambos archivos, edita el Dockerfile:

```dockerfile
# Cambiar esta línea en ServiceCell/Dockerfile
# De:
CMD ["python3", "CellController-mp.py"]

# A:
CMD ["python3", "CellController-enhanced.py"]
```

### Opción 3: Build Nueva Imagen

```bash
cd ~/muBench/ServiceCell

# Build imagen con código nuevo
docker build -t mubench/servicecell:v2 -f Dockerfile .

# Actualizar deployments para usar nueva imagen
# Editar Configs/K8sParameters.json y cambiar imagen
```

---

## Rebuild de Imágenes Docker

Si modificaste el código Python:

```bash
cd ~/muBench/ServiceCell

# Build y push imagen (si tienes registry)
./builder.sh

# O build local
docker build -t mubench/servicecell:latest .

# Si usas MicroK8s con registry local
microk8s ctr image import mubench-servicecell.tar
```

---

## Verificar que Funciona

Después de integrar el código:

```bash
# 1. Desplegar
./scripts/deploy_microk8s.sh --start --protocol http

# 2. Verificar pods
microk8s kubectl get pods -n default

# 3. Test manual de endpoints
microk8s kubectl port-forward svc/s0 8080:80 &
curl http://localhost:8080/process
curl http://localhost:8080/health
curl http://localhost:8080/metrics

# 4. Ver logs
microk8s kubectl logs deployment/s0 -f
```

Deberías ver en los logs:
```
[timestamp] s0: /process endpoint called
[timestamp] Calling service1 at http://s1.default.svc.cluster.local:80/validate
```

---

## Si Ya Tienes Pods Corriendo

```bash
# Opción A: Restart deployments (usa nueva imagen)
microk8s kubectl rollout restart deployment/s0 -n default
microk8s kubectl rollout restart deployment/s1 -n default
microk8s kubectl rollout restart deployment/sdb1 -n default

# Opción B: Delete y redeploy
microk8s kubectl delete deployment s0 s1 sdb1 -n default
# Luego ejecutar tu script de despliegue
```

---

## Configuración de Templates K8s

Los templates ya están actualizados en:

```
Deployers/K8sDeployer/Templates/
├── DeploymentTemplate.yaml    ✅ Listo para usar
└── ServiceTemplate.yaml        ✅ Listo para usar
```

Cuando ejecutes el deployer de muBench (`RunK8sDeployer.py`), automáticamente usará los templates actualizados.

---

## Variables de Entorno Importantes

Asegúrate que los deployments tengan:

```yaml
env:
  - name: COMM_PROTOCOL
    value: "http"  # o "https"
  - name: NAMESPACE
    valueFrom:
      fieldRef:
        fieldPath: metadata.namespace
```

Esto ya está en `DeploymentTemplate.yaml` actualizado.

---

## Quick Test Completo

```bash
#!/bin/bash
# Test completo de integración

cd ~/muBench

# 1. Integrar código
cp ServiceCell/CellController-enhanced.py ServiceCell/CellController-mp.py

# 2. Rebuild imagen (si necesario)
cd ServiceCell
docker build -t mubench/servicecell:latest .
cd ..

# 3. Desplegar
./scripts/deploy_microk8s.sh --start --protocol http

# 4. Esperar pods
sleep 30

# 5. Test endpoints
echo "Testing s0..."
microk8s kubectl port-forward svc/s0 8080:80 &
PF_PID=$!
sleep 3
curl -s http://localhost:8080/process | jq .
curl -s http://localhost:8080/health | jq .
kill $PF_PID

# 6. Run k6 tests
cd Testing
k6 run -e TARGET_URL=http://localhost:31113 -e VUS=5 -e DURATION=10s baseline.js

echo "✅ Integración completada"
```

---

## Problemas Comunes

### "Module not found: prometheus_client"

```bash
# Verificar que requirements.txt incluya:
cat ServiceCell/requirements.txt | grep prometheus

# Debería estar:
prometheus_client==0.16.0
```

### "ConnectionError: s1.default.svc.cluster.local"

```bash
# Verificar DNS de K8s
microk8s kubectl exec -it deployment/s0 -- nslookup s1.default.svc.cluster.local

# Verificar que service existe
microk8s kubectl get svc s1 -n default
```

### "ImportError: No module named 'urllib3'"

```bash
# Añadir a requirements.txt
echo "urllib3>=1.26.0" >> ServiceCell/requirements.txt
```

---

## Rollback si Algo Sale Mal

```bash
# Restaurar código original
cd ~/muBench/ServiceCell
cp CellController-mp.py.backup CellController-mp.py

# Rebuild y redeploy
docker build -t mubench/servicecell:latest .
microk8s kubectl rollout restart deployment/s0 -n default
```

---

## Validación Final

```bash
# Ejecutar validación completa
./scripts/validate_environment.sh

# Debe mostrar:
# ✅ Sistema listo para usar muBench
```

---

**Listo!** Ahora tienes comunicación HTTP/HTTPS real entre servicios con métricas Prometheus completas.
