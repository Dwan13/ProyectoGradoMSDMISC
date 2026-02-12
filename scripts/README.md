# MuBench Scripts

Scripts auxiliares para despliegue y gestión del entorno MuBench.

## Scripts Disponibles

### 🚀 deploy_microk8s.sh

Script principal de despliegue automático.

**Uso:**

```bash
# Iniciar con HTTP (sin cifrado)
./deploy_microk8s.sh --start --protocol http

# Iniciar con HTTPS (con TLS)
./deploy_microk8s.sh --start --protocol https

# Detener servicios
./deploy_microk8s.sh --stop
```

**Funcionalidades:**

- ✅ Despliega servicios muBench en MicroK8s
- ✅ Configura Prometheus y Grafana
- ✅ Genera certificados TLS (si HTTPS)
- ✅ Ejecuta tests con k6
- ✅ Crea dashboards en Grafana
- ✅ Port-forwarding automático

**Variables de entorno:**

```bash
COMM_PROTOCOL=http|https    # Protocolo de comunicación (default: http)
NAMESPACE=default            # Namespace de K8s (default: default)
```

**Outputs:**

- Credenciales en: `~/.mubench_credentials`
- Logs en: `/tmp/prometheus_portforward.log`, `/tmp/grafana_portforward.log`
- Certificados TLS en: `~/muBench/tls-certs/`

---

### 🔧 install_k6.sh

Instala k6 load testing tool.

**Uso:**

```bash
./install_k6.sh
```

**Soporta:**

- Linux (Ubuntu/Debian) via APT
- macOS via Homebrew

**Verifica instalación:**

```bash
k6 version
```

---

## Ejemplos de Uso

### Despliegue Completo HTTP

```bash
cd ~/muBench

# 1. Instalar k6 si no está
./scripts/install_k6.sh

# 2. Desplegar con HTTP
./scripts/deploy_microk8s.sh --start --protocol http

# 3. Ver credenciales
cat ~/.mubench_credentials

# 4. Acceder a Grafana
# http://localhost:3000 (user: admin, ver contraseña en credenciales)
```

### Despliegue Completo HTTPS

```bash
cd ~/muBench

# 1. Desplegar con HTTPS (genera certificados automáticamente)
COMM_PROTOCOL=https ./scripts/deploy_microk8s.sh --start

# 2. Verificar certificados
ls -la ~/muBench/tls-certs/

# 3. Verificar secrets de K8s
microk8s kubectl get secrets -n default | grep tls

# 4. Ejecutar experimento HTTPS
cd experiments
# Seguir instrucciones en scenario-https.md
```

### Ejecutar Solo Tests k6

```bash
cd ~/muBench/Testing

# Test básico
k6 run -e TARGET_URL=http://localhost:31113/s0 \
       -e VUS=10 \
       -e DURATION=30s \
       baseline.js

# Test inter-servicio
k6 run -e TARGET_URL=http://localhost:31113 \
       -e VUS=20 \
       -e DURATION=60s \
       -e PROTOCOL=http \
       inter-service-test.js
```

### Comparar HTTP vs HTTPS

```bash
cd ~/muBench

# 1. Deploy HTTP y ejecutar tests
./scripts/deploy_microk8s.sh --start --protocol http
# Esperar a que complete tests...

# 2. Deploy HTTPS y ejecutar tests
./scripts/deploy_microk8s.sh --stop
./scripts/deploy_microk8s.sh --start --protocol https
# Esperar a que complete tests...

# 3. Analizar overhead
cd Testing
python3 analyze_k6_results.py \
  results/http-baseline-*.json \
  results/https-baseline-*.json
```

## Troubleshooting

### Script falla en generación de certificados

```bash
# Limpiar y regenerar
rm -rf ~/muBench/tls-certs
microk8s kubectl delete secret s0-tls-secret s1-tls-secret sdb1-tls-secret -n default
./scripts/deploy_microk8s.sh --start --protocol https
```

### k6 no se instala automáticamente

```bash
# Instalación manual
./scripts/install_k6.sh

# O descarga directa
curl -L https://github.com/grafana/k6/releases/download/v0.47.0/k6-v0.47.0-linux-amd64.tar.gz | tar xvz
sudo mv k6-v0.47.0-linux-amd64/k6 /usr/local/bin/
```

### Port-forward no funciona

```bash
# Matar procesos anteriores
sudo pkill -f "port-forward"

# Reiniciar manualmente
microk8s kubectl port-forward -n observability svc/kube-prom-stack-grafana 3000:80 &
microk8s kubectl port-forward -n observability svc/kube-prom-stack-kube-prome-prometheus 9090:9090 &
```

### Pods no arrancan

```bash
# Ver logs
microk8s kubectl get pods -n default
microk8s kubectl describe pod <pod-name> -n default
microk8s kubectl logs <pod-name> -n default

# Reiniciar deployment
microk8s kubectl rollout restart deployment/<service-name> -n default
```

## Configuración Avanzada

### Cambiar Parámetros de k6 en el Script

Editar `deploy_microk8s.sh`, función `run_k6_tests()`:

```bash
k6 run --out json="${RESULT_FILE}" \
  -e TARGET_URL="${TARGET_URL}" \
  -e VUS=50 \              # <- Cambiar VUs
  -e DURATION=300s \       # <- Cambiar duración
  -e PROTOCOL="${COMM_PROTOCOL}" \
  "${TEST_DIR}/baseline.js"
```

### Personalizar Endpoints Nginx

Editar `deploy_microk8s.sh`, función `fix_nginx_dns()`:

```bash
location /custom-endpoint/ {
    proxy_pass http://custom-service.default.svc.cluster.local:80/;
}
```

## Archivos Generados

```
~/.mubench_credentials              # Credenciales de acceso
~/muBench/tls-certs/                # Certificados TLS
~/muBench/Testing/results/          # Resultados de k6
/tmp/prometheus_portforward.log     # Log de Prometheus
/tmp/grafana_portforward.log        # Log de Grafana
/tmp/dashboard_portforward.log      # Log de K8s Dashboard
```

## Ver También

- [../experiments/README.md](../experiments/README.md) - Guía de experimentos
- [../CHANGES.md](../CHANGES.md) - Changelog completo
- [../Docs/Manual.md](../Docs/Manual.md) - Manual original de muBench
