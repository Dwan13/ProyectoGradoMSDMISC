#!/bin/bash
# ================================================================
# 🚀 Proyecto MuBench - Despliegue Automático en MicroK8s + k6
# ================================================================
# Autor: Dwan13
# Descripción: Despliega, configura y gestiona el entorno completo
# de muBench con observabilidad (Prometheus + Grafana + Dashboard)
# y pruebas automáticas de rendimiento con k6.
# 
# Soporta comunicación HTTP/HTTPS entre microservicios para medir
# latencia, throughput y overhead de TLS.
# ================================================================

set -euo pipefail
IFS=$'\n\t'

# --- Variables ---
PROJECT_DIR="${HOME}/muBench"
SIMULATION_DIR="${PROJECT_DIR}/WorkModelGenerator/SimulationWorkspace"
CONFIG_DIR="${PROJECT_DIR}/Configs"
MONITORING_DIR="${PROJECT_DIR}/Monitoring"
TEST_DIR="${PROJECT_DIR}/Testing"
RESULTS_DIR="${TEST_DIR}/results"
TLS_DIR="${PROJECT_DIR}/tls-certs"
EXPERIMENTS_DIR="${PROJECT_DIR}/experiments"
REALISTIC_DIR="${PROJECT_DIR}/RealisticServices"
REALISTIC_RESULTS_DIR="${REALISTIC_DIR}/results/controls"
NAMESPACE="default"

# Protocol selection (http or https)
COMM_PROTOCOL="${COMM_PROTOCOL:-http}"
RUN_HYBRID_MODE="${RUN_HYBRID_MODE:-0}"
RUN_REALISTIC_CONTROLS="${RUN_REALISTIC_CONTROLS:-0}"
RUN_HYBRID_STRESS_MODE="${RUN_HYBRID_STRESS_MODE:-0}"
RUN_HYBRID_QUICK_MODE="${RUN_HYBRID_QUICK_MODE:-0}"

PROM_LOG="/tmp/prometheus_portforward.log"
GRAFANA_LOG="/tmp/grafana_portforward.log"
DASH_LOG="/tmp/dashboard_portforward.log"
CRED_FILE="${HOME}/.mubench_credentials"
ALL_CONTROLS_CSV="${RESULTS_DIR}/all-controls-comparison.csv"
ALL_CONTROLS_MD="${RESULTS_DIR}/all-controls-comparison.md"
ALL_CONTROLS_P95_PNG="${RESULTS_DIR}/all-controls-p95.png"
ALL_CONTROLS_AVG_PNG="${RESULTS_DIR}/all-controls-avg-vus.png"
HYBRID_SUMMARY_FILE=""

# --- Colores ---
GREEN="\e[32m"; YELLOW="\e[33m"; RED="\e[31m"; CYAN="\e[36m"; RESET="\e[0m"

log() { echo -e "${CYAN}[$(date +'%H:%M:%S')]${RESET} $*"; }
success() { echo -e "${GREEN}✅ $*${RESET}"; }
warn() { echo -e "${YELLOW}⚠️ $*${RESET}"; }
error() { echo -e "${RED}❌ $*${RESET}" >&2; exit 1; }

# ================================================================
# 🧩 Funciones auxiliares
# ================================================================

generate_tls_certificates() {
  if [[ "$COMM_PROTOCOL" != "https" ]]; then
    return 0
  fi

  log "🔐 Generando certificados TLS auto-firmados..."
  mkdir -p "${TLS_DIR}"

  for SERVICE in s0 s1 sdb1; do
    if [[ -f "${TLS_DIR}/${SERVICE}-cert.pem" ]]; then
      log "Certificado para ${SERVICE} ya existe, omitiendo..."
      continue
    fi

    openssl req -x509 -newkey rsa:2048 -nodes \
      -keyout "${TLS_DIR}/${SERVICE}-key.pem" \
      -out "${TLS_DIR}/${SERVICE}-cert.pem" \
      -days 365 \
      -subj "/CN=${SERVICE}.${NAMESPACE}.svc.cluster.local/O=muBench/C=US" \
      >/dev/null 2>&1

    success "Certificado generado para ${SERVICE}"
  done

  # Crear secrets en Kubernetes
  for SERVICE in s0 s1 sdb1; do
    if microk8s kubectl get secret ${SERVICE}-tls-secret -n ${NAMESPACE} >/dev/null 2>&1; then
      log "Secret ${SERVICE}-tls-secret ya existe, omitiendo..."
      continue
    fi

    microk8s kubectl create secret tls ${SERVICE}-tls-secret \
      --cert="${TLS_DIR}/${SERVICE}-cert.pem" \
      --key="${TLS_DIR}/${SERVICE}-key.pem" \
      -n ${NAMESPACE} >/dev/null 2>&1

    success "Secret TLS creado para ${SERVICE}"
  done
}

wait_for_pods() {
  log "Esperando a que los pods de muBench estén corriendo..."
  for _ in {1..30}; do
    READY=$(microk8s kubectl get pods -n $NAMESPACE 2>/dev/null | grep -E 's0|s1|sdb1|gw-nginx' | grep -c "Running" || true)
    (( READY >= 4 )) && { success "Pods de muBench listos."; return 0; }
    sleep 5
  done
  warn "Algunos pods no están completamente listos. Continuando..."
}

enable_dashboard() {
  log "🧩 Configurando Kubernetes Dashboard..."
  microk8s enable dashboard >/dev/null 2>&1 || true
  microk8s enable rbac >/dev/null 2>&1 || true

  if ! microk8s kubectl get sa dashboard-admin -n kube-system >/dev/null 2>&1; then
    microk8s kubectl apply -f - <<EOF
apiVersion: v1
kind: ServiceAccount
metadata:
  name: dashboard-admin
  namespace: kube-system
---
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRoleBinding
metadata:
  name: dashboard-admin-binding
roleRef:
  apiGroup: rbac.authorization.k8s.io
  kind: ClusterRole
  name: cluster-admin
subjects:
  - kind: ServiceAccount
    name: dashboard-admin
    namespace: kube-system
EOF
  fi

  nohup microk8s kubectl port-forward -n kube-system service/kubernetes-dashboard 10443:443 >"$DASH_LOG" 2>&1 &
  sleep 5

  DASH_TOKEN=$(microk8s kubectl -n kube-system create token dashboard-admin 2>/dev/null || true)
  echo "$DASH_TOKEN"
}

# ================================================================
# 🔧 Gateway Nginx / Microservicios
# ================================================================
fix_nginx_dns() {
  log "🔧 Reconfigurando gateway gw-nginx con rutas demo y servicios simulados..."

  microk8s kubectl apply -f - <<EOF
apiVersion: v1
kind: ConfigMap
metadata:
  name: gw-nginx-config
  namespace: default
data:
  default.conf: |
    server {
        listen 80;
        resolver 10.152.183.10 valid=10s ipv6=off;

        # --- Rutas demo ---
        location /demo/ {
            rewrite ^/demo/?(.*)\$ /\$1 break;
            proxy_pass http://api-demo.default.svc.cluster.local:80;
        }
        location / {
            proxy_pass http://api-demo.default.svc.cluster.local:80;
        }

        # --- Microservicios simulados ---
        location /service0/ {
            proxy_pass http://service0.default.svc.cluster.local:80/;
        }
        location /service1/ {
            proxy_pass http://service1.default.svc.cluster.local:80/;
        }
        location /database/ {
            proxy_pass http://service-db.default.svc.cluster.local:80/;
        }
    }
EOF

  if ! microk8s kubectl get deployment gw-nginx -n default >/dev/null 2>&1; then
    warn "❌ No se encontró el deployment 'gw-nginx', se recreará..."
    microk8s kubectl apply -f - <<EOF
apiVersion: apps/v1
kind: Deployment
metadata:
  name: gw-nginx
  namespace: default
  labels:
    app: gw-nginx
spec:
  replicas: 1
  selector:
    matchLabels:
      app: gw-nginx
  template:
    metadata:
      labels:
        app: gw-nginx
    spec:
      containers:
      - name: gw-nginx
        image: nginx:1.25
        ports:
        - containerPort: 80
        volumeMounts:
        - name: nginx-config
          mountPath: /etc/nginx/conf.d
      volumes:
      - name: nginx-config
        configMap:
          name: gw-nginx-config
---
apiVersion: v1
kind: Service
metadata:
  name: gw-nginx
  namespace: default
  labels:
    app: gw-nginx
spec:
  type: NodePort
  selector:
    app: gw-nginx
  ports:
    - name: http
      port: 80
      nodePort: 31113
EOF
  fi

  microk8s kubectl rollout restart deployment gw-nginx -n default
  log "⏳ Esperando que gw-nginx esté Running..."
  for i in {1..20}; do
    STATUS=$(microk8s kubectl get pods -l app=gw-nginx -n default -o jsonpath='{.items[0].status.phase}' 2>/dev/null || echo "")
    [[ "$STATUS" == "Running" ]] && { success "✅ Gateway listo."; sleep 5; return 0; }
    sleep 5
  done
  warn "⚠️ gw-nginx no alcanzó estado Running, continuaré de todas formas..."
}

# ================================================================
# 🧪 k6 Tests
# ================================================================
check_k6() {
  log "Verificando instalación de k6..."
  
  if command -v k6 >/dev/null 2>&1; then
    success "✅ k6 detectado correctamente."
    k6 version
    return 0
  fi
  
  warn "k6 no encontrado."

  if [[ "${ALLOW_SUDO_INSTALL:-0}" != "1" ]]; then
    warn "Instalación automática desactivada (usa ALLOW_SUDO_INSTALL=1 para habilitarla)."
    warn "Instala k6 manualmente y vuelve a ejecutar el script."
    return 1
  fi

  if ! command -v sudo >/dev/null 2>&1 || ! sudo -n true >/dev/null 2>&1; then
    warn "No hay permisos sudo no-interactivos para instalar k6 automáticamente."
    return 1
  fi

  warn "Instalando k6 automáticamente..."
  
  # Detectar OS y instalar
  if [[ "$OSTYPE" == "linux-gnu"* ]]; then
    sudo gpg -k >/dev/null 2>&1 || { error "gpg no encontrado"; }
    sudo gpg --no-default-keyring --keyring /usr/share/keyrings/k6-archive-keyring.gpg \
      --keyserver hkp://keyserver.ubuntu.com:80 --recv-keys C5AD17C747E3415A3642D57D77C6C491D6AC1D69 || true
    echo "deb [signed-by=/usr/share/keyrings/k6-archive-keyring.gpg] https://dl.k6.io/deb stable main" | \
      sudo tee /etc/apt/sources.list.d/k6.list
    sudo apt-get update
    sudo apt-get install -y k6
  elif [[ "$OSTYPE" == "darwin"* ]]; then
    brew install k6
  else
    error "OS no soportado para instalación automática de k6. Instálalo manualmente desde https://k6.io/docs/get-started/installation/"
  fi
  
  success "✅ k6 instalado correctamente."
}

run_k6_tests() {
  check_k6 || { warn "Se omiten pruebas k6 por falta de binario k6"; return 0; }

  mkdir -p "${RESULTS_DIR}"
  TIMESTAMP=$(date +%Y%m%d_%H%M%S)
  K6_VUS="${VUS:-20}"
  K6_DURATION="${DURATION:-60s}"
  
  # Usar port-forward para acceder a los servicios
  LOCAL_PORT=8081
  PF_PID=""

  log "🔌 Iniciando port-forward a servicio s0..."
  for attempt in 1 2 3; do
    microk8s kubectl port-forward svc/s0 ${LOCAL_PORT}:80 -n ${NAMESPACE} > /tmp/k6_portforward.log 2>&1 &
    PF_PID=$!
    sleep 3
    if ps -p $PF_PID > /dev/null 2>&1; then
      break
    fi
    warn "Port-forward intento ${attempt} falló, reintentando..."
  done

  if [[ -z "${PF_PID}" ]] || ! ps -p $PF_PID > /dev/null 2>&1; then
    warn "No se pudo establecer port-forward a s0. Se omiten pruebas k6 en esta ejecución."
    return 0
  fi

  TARGET_URL="http://127.0.0.1:${LOCAL_PORT}/process"

  log "🏁 Ejecutando k6 contra ${TARGET_URL}"
  log "Protocolo de comunicación inter-servicio: ${COMM_PROTOCOL}"

  # Test baseline
  RESULT_FILE="${RESULTS_DIR}/${COMM_PROTOCOL}-baseline-${TIMESTAMP}.json"
  
  k6 run --out json="${RESULT_FILE}" \
    -e TARGET_URL="${TARGET_URL}" \
    -e VUS="${K6_VUS}" \
    -e DURATION="${K6_DURATION}" \
    -e PROTOCOL="${COMM_PROTOCOL}" \
    -e INSECURE_SKIP_TLS_VERIFY=true \
    "${TEST_DIR}/baseline.js" || warn "⚠️ Error al ejecutar prueba k6 baseline"

  success "✅ Prueba baseline completada. Resultados en: ${RESULT_FILE}"

  # Test inter-service communication
  RESULT_FILE_INTER="${RESULTS_DIR}/${COMM_PROTOCOL}-interservice-${TIMESTAMP}.json"
  
  log "🔗 Ejecutando prueba de comunicación inter-servicio..."
  
  # Para inter-service test, usar base URL sin endpoint
  BASE_URL="http://127.0.0.1:${LOCAL_PORT}"
  
  k6 run --out json="${RESULT_FILE_INTER}" \
    -e TARGET_URL="${BASE_URL}" \
    -e VUS="${K6_VUS}" \
    -e DURATION="${K6_DURATION}" \
    -e PROTOCOL="${COMM_PROTOCOL}" \
    -e INSECURE_SKIP_TLS_VERIFY=true \
    "${TEST_DIR}/inter-service-test.js" || warn "⚠️ Error al ejecutar prueba inter-servicio"

  success "✅ Prueba inter-servicio completada. Resultados en: ${RESULT_FILE_INTER}"

  # Cleanup port-forward
  if [[ -n "${PF_PID:-}" ]] && ps -p $PF_PID > /dev/null 2>&1; then
    log "🔌 Cerrando port-forward..."
    kill $PF_PID 2>/dev/null || true
    wait $PF_PID 2>/dev/null || true
  fi

  # Summary
  log "📊 Resumen de resultados:"
  echo "  Baseline:      ${RESULT_FILE}"
  echo "  Inter-service: ${RESULT_FILE_INTER}"
  echo ""
  echo "Analizar con: cat ${RESULT_FILE} | jq '.metrics'"
}

create_grafana_dashboard() {
  log "🔧 Creando dashboards en Grafana..."

  GRAFANA_URL="http://localhost:3000"
  GRAFANA_USER="admin"
  GRAFANA_PASS=$(microk8s kubectl get secret -n observability kube-prom-stack-grafana -o jsonpath='{.data.admin-password}' 2>/dev/null | base64 --decode || echo "")

  [[ -z "$GRAFANA_PASS" ]] && { warn "No se pudo obtener contraseña de Grafana"; return; }

  # Wait for Grafana to be ready
  for _ in {1..10}; do
    if curl -s "${GRAFANA_URL}/api/health" >/dev/null 2>&1; then
      break
    fi
    sleep 2
  done

  DASHBOARD_JSON=$(cat <<'EOF'
{
  "dashboard": {
    "id": null,
    "uid": "mubench-microservices",
    "title": "MuBench Microservices Performance",
    "tags": ["mubench", "microservices", "k6"],
    "timezone": "browser",
    "schemaVersion": 16,
    "version": 0,
    "refresh": "5s",
    "panels": [
      {
        "id": 1,
        "type": "graph",
        "title": "HTTP Request Duration (P95)",
        "datasource": "Prometheus",
        "targets": [
          {
            "expr": "histogram_quantile(0.95, rate(http_request_duration_seconds_bucket[1m]))",
            "legendFormat": "{{service}} - {{endpoint}}"
          }
        ],
        "gridPos": {"x": 0, "y": 0, "w": 12, "h": 8},
        "yaxes": [{"format": "s"}]
      },
      {
        "id": 2,
        "type": "graph",
        "title": "Throughput (requests/sec)",
        "datasource": "Prometheus",
        "targets": [
          {
            "expr": "sum(rate(http_requests_total[1m])) by (service)",
            "legendFormat": "{{service}}"
          }
        ],
        "gridPos": {"x": 12, "y": 0, "w": 12, "h": 8},
        "yaxes": [{"format": "reqps"}]
      },
      {
        "id": 3,
        "type": "graph",
        "title": "Network TX Bytes",
        "datasource": "Prometheus",
        "targets": [
          {
            "expr": "sum(rate(container_network_transmit_bytes_total{namespace=~\"default|realistic\"}[1m])) by (pod)",
            "legendFormat": "{{pod}}"
          }
        ],
        "gridPos": {"x": 0, "y": 8, "w": 12, "h": 8},
        "yaxes": [{"format": "Bps"}]
      },
      {
        "id": 4,
        "type": "graph",
        "title": "Network RX Bytes",
        "datasource": "Prometheus",
        "targets": [
          {
            "expr": "sum(rate(container_network_receive_bytes_total{namespace=~\"default|realistic\"}[1m])) by (pod)",
            "legendFormat": "{{pod}}"
          }
        ],
        "gridPos": {"x": 12, "y": 8, "w": 12, "h": 8},
        "yaxes": [{"format": "Bps"}]
      },
      {
        "id": 5,
        "type": "stat",
        "title": "Error Rate",
        "datasource": "Prometheus",
        "targets": [
          {
            "expr": "sum(rate(http_requests_total{status_code=~\"5..\"}[1m])) / sum(rate(http_requests_total[1m]))"
          }
        ],
        "gridPos": {"x": 0, "y": 16, "w": 6, "h": 4}
      },
      {
        "id": 6,
        "type": "stat",
        "title": "Total Requests/sec",
        "datasource": "Prometheus",
        "targets": [
          {
            "expr": "sum(rate(http_requests_total[1m]))"
          }
        ],
        "gridPos": {"x": 6, "y": 16, "w": 6, "h": 4}
      }
    ]
  },
  "overwrite": true
}
EOF
)
  
  curl -s -X POST -H "Content-Type: application/json" \
       -u "${GRAFANA_USER}:${GRAFANA_PASS}" \
       -d "${DASHBOARD_JSON}" \
       "${GRAFANA_URL}/api/dashboards/db" >/dev/null || warn "No se pudo crear dashboard en Grafana"

  success "✅ Dashboard 'MuBench Microservices Performance' creado en Grafana: ${GRAFANA_URL}"
}

generate_all_controls_comparison() {
  log "📈 Generando comparación consolidada C1-C4..."
  mkdir -p "${RESULTS_DIR}"

  python3 - "${EXPERIMENTS_DIR}" "${REALISTIC_RESULTS_DIR}" "${ALL_CONTROLS_CSV}" "${ALL_CONTROLS_MD}" <<'PY'
import csv
import glob
import json
import os
import sys

exp_dir = sys.argv[1]
realistic_dir = sys.argv[2]
out_csv = sys.argv[3]
out_md = sys.argv[4]

rows = []

def percentile(values, p):
    if not values:
        return None
    values = sorted(values)
    k = (len(values) - 1) * (p / 100.0)
    f = int(k)
    c = min(f + 1, len(values) - 1)
    if f == c:
        return values[int(k)]
    d0 = values[f] * (c - k)
    d1 = values[c] * (k - f)
    return d0 + d1

def append_row(control, scenario, vus, p95, avg):
    if p95 is None or avg is None:
        return
    rows.append({
        "control": control,
        "scenario": scenario,
        "vus": vus,
        "avg_ms": round(avg, 4),
        "p95_ms": round(p95, 4),
    })

c1_patterns = [
    ("baseline", os.path.join(exp_dir, "01-api-gateway", "baseline", "results", "baseline-*.json")),
    ("nginx", os.path.join(exp_dir, "01-api-gateway", "nginx", "results", "nginx-*.json")),
    ("kong", os.path.join(exp_dir, "01-api-gateway", "kong", "results", "kong-*.json")),
]

for scenario, pattern in c1_patterns:
    grouped = {}
    for fp in glob.glob(pattern):
        base = os.path.basename(fp)
        vus = None
        for token in base.replace('.json', '').split('-'):
            if token.startswith('vus'):
                try:
                    vus = int(token.replace('vus', ''))
                except ValueError:
                    vus = None
        if vus is None:
            continue
        grouped.setdefault(vus, [])
        with open(fp, 'r') as f:
            for line in f:
                try:
                    row = json.loads(line)
                except json.JSONDecodeError:
                    continue
                if row.get('type') == 'Point' and row.get('metric') == 'http_req_duration':
                    val = row.get('data', {}).get('value')
                    if isinstance(val, (int, float)):
                        grouped[vus].append(float(val))
    for vus, vals in grouped.items():
        if vals:
            append_row("C1-api-gateway", scenario, vus, percentile(vals, 95), sum(vals) / len(vals))

csv_sources = [
    ("C2-mtls", os.path.join(exp_dir, "02-mtls-service-mesh", "analysis", "output-final", "mtls_summary.csv")),
    ("C3-netpol", os.path.join(exp_dir, "03-network-policies", "analysis", "output-final", "netpol_summary.csv")),
    ("C4-ratelimit", os.path.join(exp_dir, "04-rate-limiting", "analysis", "output-final", "ratelimit_summary.csv")),
]

for control, fp in csv_sources:
    if not os.path.exists(fp):
        continue
    with open(fp, 'r', newline='') as f:
        reader = csv.DictReader(f)
        for r in reader:
            try:
                append_row(
                    control,
                    r.get("scenario", "unknown"),
                    int(float(r.get("vus", 0))),
                    float(r.get("p95_ms", 0.0)),
                    float(r.get("avg_ms", 0.0)),
                )
            except Exception:
                continue

realistic_patterns = [
    ("C1-api-gateway", "gateway", os.path.join(realistic_dir, "c1-gateway-*.json")),
    ("C2-mtls", "mesh", os.path.join(realistic_dir, "c2-mtls-*.json")),
    ("C3-netpol", "netpol", os.path.join(realistic_dir, "c3-netpol-*.json")),
    ("C4-ratelimit", "ratelimit", os.path.join(realistic_dir, "c4-ratelimit-*.json")),
]

for control, scenario, pattern in realistic_patterns:
    for fp in glob.glob(pattern):
        vals = []
        vus_samples = []
        with open(fp, 'r') as f:
            for line in f:
                try:
                    row = json.loads(line)
                except json.JSONDecodeError:
                    continue
                if row.get('type') != 'Point':
                    continue
                metric = row.get('metric')
                value = row.get('data', {}).get('value')
                if not isinstance(value, (int, float)):
                    continue
                if metric == 'http_req_duration':
                    vals.append(float(value))
                elif metric == 'vus':
                    vus_samples.append(int(float(value)))
        if vals:
            detected_vus = max(vus_samples) if vus_samples else 0
            append_row(control, f"{scenario}-realistic", detected_vus, percentile(vals, 95), sum(vals) / len(vals))

rows.sort(key=lambda r: (r["control"], r["scenario"], r["vus"]))

with open(out_csv, 'w', newline='') as f:
    w = csv.DictWriter(f, fieldnames=["control", "scenario", "vus", "avg_ms", "p95_ms"])
    w.writeheader()
    for r in rows:
        w.writerow(r)

with open(out_md, 'w') as f:
    f.write("# MuBench - Comparación Consolidada C1-C4\n\n")
    f.write("| Control | Escenario | VUs | Avg (ms) | P95 (ms) |\n")
    f.write("|---|---|---:|---:|---:|\n")
    for r in rows:
        f.write(f"| {r['control']} | {r['scenario']} | {r['vus']} | {r['avg_ms']:.2f} | {r['p95_ms']:.2f} |\n")

print(f"CSV: {out_csv}")
print(f"MD: {out_md}")
PY

  success "Comparación consolidada generada: ${ALL_CONTROLS_MD}"
}

generate_all_controls_visuals() {
  log "🖼️ Generando gráficas visuales C1-C4..."

  if [[ ! -f "${ALL_CONTROLS_CSV}" ]]; then
    warn "No existe CSV consolidado para generar gráficas visuales"
    return
  fi

  if python3 - "${ALL_CONTROLS_CSV}" "${ALL_CONTROLS_P95_PNG}" "${ALL_CONTROLS_AVG_PNG}" <<'PY'
import csv
import statistics
import sys
from collections import defaultdict

try:
    import matplotlib
    matplotlib.use("Agg")
    import matplotlib.pyplot as plt
except Exception as e:
    print(f"ERROR: matplotlib no disponible ({e})", file=sys.stderr)
    sys.exit(2)

csv_path = sys.argv[1]
p95_png = sys.argv[2]
avg_png = sys.argv[3]

records = []
with open(csv_path, 'r', newline='') as f:
    reader = csv.DictReader(f)
    for r in reader:
        try:
            records.append({
                "control": r["control"],
                "scenario": r["scenario"],
                "vus": int(float(r["vus"])),
                "avg_ms": float(r["avg_ms"]),
                "p95_ms": float(r["p95_ms"]),
            })
        except Exception:
            continue

if not records:
    print("ERROR: sin datos para graficar", file=sys.stderr)
    sys.exit(3)

by_csv_key = defaultdict(lambda: {"avg": [], "p95": []})
for rec in records:
    k = (rec["control"], rec["scenario"], rec["vus"])
    by_csv_key[k]["avg"].append(rec["avg_ms"])
    by_csv_key[k]["p95"].append(rec["p95_ms"])

aggregated = []
for (control, scenario, vus), vals in by_csv_key.items():
    aggregated.append({
        "control": control,
        "scenario": scenario,
        "vus": vus,
        "avg_ms": statistics.mean(vals["avg"]),
        "p95_ms": statistics.mean(vals["p95"]),
    })

scenario_groups = defaultdict(list)
for rec in aggregated:
    scenario_groups[(rec["control"], rec["scenario"])].append(rec)

labels = []
p95_values = []
for (control, scenario), rows in sorted(scenario_groups.items()):
    labels.append(f"{control}\\n{scenario}")
    p95_values.append(statistics.mean([r["p95_ms"] for r in rows]))

plt.figure(figsize=(14, 7))
bars = plt.bar(labels, p95_values)
for b, v in zip(bars, p95_values):
    plt.text(b.get_x() + b.get_width() / 2, v, f"{v:.1f}", ha="center", va="bottom", fontsize=8)
plt.title("MuBench C1-C4: P95 promedio por escenario")
plt.ylabel("P95 (ms)")
plt.xticks(rotation=25, ha="right")
plt.tight_layout()
plt.savefig(p95_png, dpi=180)
plt.close()

plt.figure(figsize=(14, 7))
for (control, scenario), rows in sorted(scenario_groups.items()):
    rows = sorted(rows, key=lambda x: x["vus"])
    x = [r["vus"] for r in rows]
    y = [r["avg_ms"] for r in rows]
    plt.plot(x, y, marker="o", linewidth=2, label=f"{control}:{scenario}")
plt.title("MuBench C1-C4: AVG vs VUs por escenario")
plt.xlabel("VUs")
plt.ylabel("AVG (ms)")
plt.grid(True, alpha=0.25)
plt.legend(fontsize=8, ncol=2)
plt.tight_layout()
plt.savefig(avg_png, dpi=180)
plt.close()

print(f"P95_PNG: {p95_png}")
print(f"AVG_PNG: {avg_png}")
PY
  then
    success "Gráficas generadas: ${ALL_CONTROLS_P95_PNG} y ${ALL_CONTROLS_AVG_PNG}"
  else
    warn "No se pudieron generar gráficas visuales (revisar matplotlib/datos)"
  fi
}

create_grafana_comparison_dashboard() {
  log "📊 Publicando dashboard comparativo C1-C4 en Grafana..."

  GRAFANA_URL="http://localhost:3000"
  GRAFANA_USER="admin"
  GRAFANA_PASS=$(microk8s kubectl get secret -n observability kube-prom-stack-grafana -o jsonpath='{.data.admin-password}' 2>/dev/null | base64 --decode || echo "")

  [[ -z "$GRAFANA_PASS" ]] && { warn "No se pudo obtener contraseña de Grafana"; return; }
  [[ ! -f "${ALL_CONTROLS_MD}" ]] && { warn "No existe comparación consolidada para publicar"; return; }

  VISUAL_MARKDOWN_JSON=$(python3 - "${ALL_CONTROLS_P95_PNG}" "${ALL_CONTROLS_AVG_PNG}" <<'PY'
import base64
import json
import os
import sys

p95_png = sys.argv[1]
avg_png = sys.argv[2]

sections = ["# MuBench - Comparación Visual C1-C4"]

def add_image(path, title):
    if not os.path.exists(path):
        sections.append(f"> No se encontró imagen: {path}")
        return
    with open(path, 'rb') as f:
        b64 = base64.b64encode(f.read()).decode('ascii')
    sections.append(f"## {title}")
    sections.append(f"![{title}](data:image/png;base64,{b64})")

add_image(p95_png, "P95 promedio por escenario")
add_image(avg_png, "AVG vs VUs por escenario")

print(json.dumps("\\n\\n".join(sections)))
PY
)

  MARKDOWN_JSON=$(python3 - "${ALL_CONTROLS_MD}" <<'PY'
import json
import sys
with open(sys.argv[1], 'r') as f:
    content = f.read()
print(json.dumps(content))
PY
)

  HYBRID_SUMMARY_JSON=$(python3 - "${HYBRID_SUMMARY_FILE:-}" <<'PY'
import json
import os
import sys

path = sys.argv[1] if len(sys.argv) > 1 else ""
if path and os.path.exists(path):
    with open(path, 'r', encoding='utf-8') as f:
        content = f.read()
else:
    content = "Resumen híbrido no disponible en esta ejecución."

print(json.dumps(content))
PY
)

  DASHBOARD_JSON=$(cat <<EOF
{
  "dashboard": {
    "id": null,
    "uid": "mubench-controls-comparison",
    "title": "MuBench - Comparación C1-C4",
    "tags": ["mubench", "comparison", "controls"],
    "timezone": "browser",
    "schemaVersion": 39,
    "version": 0,
    "refresh": "30s",
    "panels": [
      {
        "id": 1,
        "type": "text",
        "title": "Gráficas Comparativas C1-C4",
        "gridPos": {"x": 0, "y": 0, "w": 24, "h": 18},
        "options": {
          "mode": "markdown",
          "content": ${VISUAL_MARKDOWN_JSON}
        }
      },
      {
        "id": 2,
        "type": "text",
        "title": "Tabla Consolidada (Offline)",
        "gridPos": {"x": 0, "y": 18, "w": 24, "h": 12},
        "options": {
          "mode": "markdown",
          "content": ${MARKDOWN_JSON}
        }
      },
      {
        "id": 3,
        "type": "text",
        "title": "Resumen Híbrido k6 (Auto)",
        "gridPos": {"x": 0, "y": 30, "w": 24, "h": 8},
        "options": {
          "mode": "markdown",
          "content": ${HYBRID_SUMMARY_JSON}
        }
      }
    ]
  },
  "overwrite": true
}

EOF
)

  DASH_TMP="$(mktemp /tmp/mubench-comparison-dashboard.XXXXXX.json)"
  printf '%s' "${DASHBOARD_JSON}" > "${DASH_TMP}"

  RESP=$(curl -s -X POST -H "Content-Type: application/json" \
    -u "${GRAFANA_USER}:${GRAFANA_PASS}" \
    --data-binary @"${DASH_TMP}" \
    "${GRAFANA_URL}/api/dashboards/db" || true)
  rm -f "${DASH_TMP}"

  if echo "${RESP}" | grep -q '"status":"success"'; then
    success "Dashboard 'MuBench - Comparación C1-C4' publicado en Grafana"
  else
    warn "No se pudo crear dashboard comparativo C1-C4"
    [[ -n "${RESP}" ]] && warn "Respuesta Grafana: ${RESP}"
  fi
}

run_realistic_hybrid_flow() {
  if [[ "${RUN_HYBRID_MODE}" != "1" ]]; then
    return 0
  fi

  log "🔁 Ejecutando esquema híbrido (muBench + RealisticServices)..."

  [[ -d "${REALISTIC_DIR}" ]] || { warn "No existe ${REALISTIC_DIR}; se omite flujo híbrido"; return 0; }
  [[ -x "${REALISTIC_DIR}/deploy-realistic.sh" ]] || { warn "No existe deploy-realistic.sh ejecutable"; return 0; }
  [[ -x "${REALISTIC_DIR}/run-k6-users-bulk.sh" ]] || { warn "No existe run-k6-users-bulk.sh ejecutable"; return 0; }

  log "🧱 Desplegando micros realistas..."
  (cd "${REALISTIC_DIR}" && ./deploy-realistic.sh)

  if [[ "${RUN_HYBRID_STRESS_MODE}" == "1" ]]; then
    REALISTIC_CREATE_VUS="${REALISTIC_CREATE_VUS:-25}"
    REALISTIC_CREATE_DURATION="${REALISTIC_CREATE_DURATION:-90s}"
    REALISTIC_LIST_START="${REALISTIC_LIST_START:-95s}"
    REALISTIC_LIST_VUS="${REALISTIC_LIST_VUS:-12}"
    REALISTIC_LIST_DURATION="${REALISTIC_LIST_DURATION:-60s}"
    REALISTIC_LIST_LIMIT="${REALISTIC_LIST_LIMIT:-250}"
    log "🔥 Perfil hybrid-stress activo (CREATE_VUS=${REALISTIC_CREATE_VUS}, LIST_VUS=${REALISTIC_LIST_VUS})"
  elif [[ "${RUN_HYBRID_QUICK_MODE}" == "1" ]]; then
    REALISTIC_CREATE_VUS="${REALISTIC_CREATE_VUS:-4}"
    REALISTIC_CREATE_DURATION="${REALISTIC_CREATE_DURATION:-8s}"
    REALISTIC_LIST_START="${REALISTIC_LIST_START:-10s}"
    REALISTIC_LIST_VUS="${REALISTIC_LIST_VUS:-2}"
    REALISTIC_LIST_DURATION="${REALISTIC_LIST_DURATION:-6s}"
    REALISTIC_LIST_LIMIT="${REALISTIC_LIST_LIMIT:-80}"
    log "⚡ Perfil hybrid-quick activo (CREATE_VUS=${REALISTIC_CREATE_VUS}, LIST_VUS=${REALISTIC_LIST_VUS})"
  fi

  log "📦 Ejecutando carga k6 (create/list usuarios) sobre micros realistas..."
  if ! (
    cd "${REALISTIC_DIR}" && \
    AUTH_PORT="${REALISTIC_AUTH_PORT:-18092}" \
    API_PORT="${REALISTIC_API_PORT:-18091}" \
    CREATE_VUS="${REALISTIC_CREATE_VUS:-15}" \
    CREATE_DURATION="${REALISTIC_CREATE_DURATION:-45s}" \
    LIST_START="${REALISTIC_LIST_START:-50s}" \
    LIST_VUS="${REALISTIC_LIST_VUS:-5}" \
    LIST_DURATION="${REALISTIC_LIST_DURATION:-25s}" \
    LIST_LIMIT="${REALISTIC_LIST_LIMIT:-100}" \
    ./run-k6-users-bulk.sh
  ); then
    warn "Primer intento k6 realista falló. Reintentando con puertos alternos locales..."
    (
      cd "${REALISTIC_DIR}" && \
      AUTH_PORT="${REALISTIC_AUTH_PORT_FALLBACK:-18192}" \
      API_PORT="${REALISTIC_API_PORT_FALLBACK:-18191}" \
      CREATE_VUS="${REALISTIC_CREATE_VUS:-15}" \
      CREATE_DURATION="${REALISTIC_CREATE_DURATION:-45s}" \
      LIST_START="${REALISTIC_LIST_START:-50s}" \
      LIST_VUS="${REALISTIC_LIST_VUS:-5}" \
      LIST_DURATION="${REALISTIC_LIST_DURATION:-25s}" \
      LIST_LIMIT="${REALISTIC_LIST_LIMIT:-100}" \
      ./run-k6-users-bulk.sh
    )
  fi

  if [[ "${RUN_REALISTIC_CONTROLS}" == "1" ]] && [[ -x "${REALISTIC_DIR}/run-controls-realistic.sh" ]]; then
    log "🧪 Ejecutando benchmark de controles C1-C4 en micros realistas..."
    (cd "${REALISTIC_DIR}" && ./run-controls-realistic.sh)
  fi

  LAST_BULK_RESULT="$(ls -1t "${REALISTIC_DIR}/results"/k6-users-bulk-*.json 2>/dev/null | head -n1 || true)"
  if [[ -n "${LAST_BULK_RESULT}" && -f "${LAST_BULK_RESULT}" ]]; then
    STAMP="$(date +%Y%m%d_%H%M%S)"
    HYBRID_SUMMARY_FILE="${REALISTIC_DIR}/results/hybrid-k6-summary-${STAMP}.txt"

    if python3 - "${LAST_BULK_RESULT}" > "${HYBRID_SUMMARY_FILE}" <<'PY'
import json
import math
import sys

path = sys.argv[1]

req_durations = []
failed = 0.0
failed_points = 0
created = 0.0
listed = 0.0

with open(path, "r", encoding="utf-8") as f:
    for line in f:
        line = line.strip()
        if not line:
            continue
        try:
            row = json.loads(line)
        except json.JSONDecodeError:
            continue
        if row.get("type") != "Point":
            continue
        metric = row.get("metric")
        value = row.get("data", {}).get("value")
        if not isinstance(value, (int, float)):
            continue

        if metric == "http_req_duration":
            req_durations.append(float(value))
        elif metric == "http_req_failed":
            failed += float(value)
            failed_points += 1
        elif metric == "users_created_total":
            created += float(value)
        elif metric == "users_listed_total":
            listed += float(value)

def pctl(values, p):
    if not values:
        return None
    values = sorted(values)
    k = (len(values) - 1) * (p / 100.0)
    f = math.floor(k)
    c = math.ceil(k)
    if f == c:
        return values[int(k)]
    return values[f] * (c - k) + values[c] * (k - f)

p95 = pctl(req_durations, 95)
err_rate = (failed / failed_points) if failed_points else None

print("MuBench Hybrid k6 Summary")
print("========================")
print(f"result_file: {path}")
print(f"users_created_total: {int(round(created))}")
print(f"users_listed_total: {int(round(listed))}")
print(f"http_req_duration_p95_ms: {p95:.3f}" if p95 is not None else "http_req_duration_p95_ms: N/A")
print(f"http_req_failed_rate: {err_rate:.6f}" if err_rate is not None else "http_req_failed_rate: N/A")
print(f"http_samples: {len(req_durations)}")
PY
    then
      log "📄 Resumen híbrido exportado: ${HYBRID_SUMMARY_FILE}"
      cat "${HYBRID_SUMMARY_FILE}"
    else
      warn "No se pudo generar resumen automático de k6 realista"
    fi
  else
    warn "No se encontró resultado k6 realista para resumir"
  fi

  success "Flujo híbrido finalizado correctamente"
}

# ================================================================
# 🚀 Inicio de servicios
# ================================================================
start_services() {
  log "Iniciando despliegue automatizado MuBench..."
  log "Protocolo de comunicación: ${COMM_PROTOCOL}"
  
  microk8s status --wait-ready >/dev/null 2>&1 || error "❌ MicroK8s no está listo"

  # Generate TLS certificates if HTTPS mode
  generate_tls_certificates

  wait_for_pods
  fix_nginx_dns

  log "Iniciando port-forward Prometheus y Grafana..."
  pkill -f "port-forward.*prometheus" || true
  pkill -f "port-forward.*grafana" || true
  
  nohup microk8s kubectl port-forward -n observability svc/kube-prom-stack-kube-prome-prometheus 9090:9090 >"$PROM_LOG" 2>&1 &
  nohup microk8s kubectl port-forward -n observability svc/kube-prom-stack-grafana 3000:80 >"$GRAFANA_LOG" 2>&1 &
  
  sleep 5
  
  log "Configurando Dashboard de Kubernetes..."
  DASH_TOKEN=$(enable_dashboard | tail -n1 || true)

  run_k6_tests
  create_grafana_dashboard
  run_realistic_hybrid_flow
  generate_all_controls_comparison
  generate_all_controls_visuals
  create_grafana_comparison_dashboard

  log "Obteniendo credenciales..."
  GRAFANA_PASS=$(microk8s kubectl get secret -n observability kube-prom-stack-grafana -o jsonpath='{.data.admin-password}' 2>/dev/null | base64 --decode || echo "N/A")

  {
    echo "============================"
    echo "🧩 MuBench Access Credentials"
    echo "============================"
    echo
    echo "Communication Protocol: ${COMM_PROTOCOL^^}"
    echo
    echo "Grafana"
    echo "--------"
    echo "URL: http://localhost:3000"
    echo "Usuario: admin"
    echo "Contraseña: ${GRAFANA_PASS}"
    echo
    echo "Prometheus"
    echo "-----------"
    echo "URL: http://localhost:9090"
    echo
    echo "Kubernetes Dashboard"
    echo "---------------------"
    echo "URL: https://localhost:10443"
    echo "Token: ${DASH_TOKEN}"
    echo
    echo "Experiments"
    echo "------------"
    echo "HTTP:  ${PROJECT_DIR}/experiments/scenario-http.md"
    echo "HTTPS: ${PROJECT_DIR}/experiments/scenario-https.md"
    echo
    echo "Comparison"
    echo "----------"
    echo "CSV: ${ALL_CONTROLS_CSV}"
    echo "MD:  ${ALL_CONTROLS_MD}"
    if [[ -n "${HYBRID_SUMMARY_FILE}" && -f "${HYBRID_SUMMARY_FILE}" ]]; then
      echo
      echo "Hybrid k6 Summary"
      echo "-----------------"
      echo "File: ${HYBRID_SUMMARY_FILE}"
    fi
  } > "${CRED_FILE}"

  chmod 600 "${CRED_FILE}"
  success "Credenciales guardadas en: ${CRED_FILE}"

  success "✅ Despliegue completo. Accesos:"
  echo -e "${CYAN}Grafana:${RESET}     http://localhost:3000"
  echo -e "${CYAN}Prometheus:${RESET}  http://localhost:9090"
  echo -e "${CYAN}Dashboard:${RESET}   https://localhost:10443"
  echo -e "${CYAN}Protocol:${RESET}    ${COMM_PROTOCOL^^}"
  echo ""
  echo -e "${GREEN}Ver experimentos en: ${PROJECT_DIR}/experiments/${RESET}"
}

# ================================================================
# 🛑 Detener servicios
# ================================================================
stop_services() {
  log "Deteniendo port-forwards..."
  pkill -f "port-forward" || true
  rm -f "${PROM_LOG}" "${GRAFANA_LOG}" "${DASH_LOG}"
  success "Servicios detenidos correctamente."
}

# ================================================================
# CLI principal
# ================================================================
usage() {
  cat <<EOF
${CYAN}MuBench Deployment Script${RESET}

${GREEN}Usage:${RESET}
  $0 [OPTIONS]

${GREEN}Options:${RESET}
  --start               Iniciar servicios y ejecutar tests
  --stop                Detener port-forwards
  --protocol <http|https>  Configurar protocolo de comunicación (default: http)
  --hybrid              Ejecutar flujo híbrido con RealisticServices + k6 create/list
  --hybrid-quick        Ejecutar flujo híbrido rápido (sanity check)
  --hybrid-stress       Ejecutar flujo híbrido con perfil de carga alta predefinido
  --hybrid-controls     En modo híbrido, también ejecutar benchmark C1-C4 realista
  --help                Mostrar esta ayuda

${GREEN}Examples:${RESET}
  # Desplegar con HTTP
  $0 --start --protocol http

  # Desplegar y ejecutar esquema híbrido
  $0 --start --hybrid

  # Esquema híbrido rápido (sanity)
  $0 --start --hybrid-quick

  # Esquema híbrido con carga alta
  $0 --start --hybrid-stress

  # Esquema híbrido + benchmark C1-C4 realista
  $0 --start --hybrid --hybrid-controls

  # Desplegar con HTTPS
  COMM_PROTOCOL=https $0 --start

  # Detener servicios
  $0 --stop

${GREEN}Environment Variables:${RESET}
  COMM_PROTOCOL         http | https (default: http)
  VUS                   Virtual users para k6 (default: 20)
  DURATION              Duración de tests k6 (default: 60s)
  RUN_HYBRID_MODE       0 | 1 (default: 0)
  RUN_HYBRID_QUICK_MODE 0 | 1 (default: 0)
  RUN_HYBRID_STRESS_MODE 0 | 1 (default: 0)
  RUN_REALISTIC_CONTROLS 0 | 1 (default: 0)

${GREEN}More Info:${RESET}
  Experiments: ${PROJECT_DIR}/experiments/
  Results:     ${RESULTS_DIR}/
  Credentials: ${CRED_FILE}
EOF
}

# Parse arguments
COMMAND="--start"
while [[ $# -gt 0 ]]; do
  case $1 in
    --start)
      COMMAND="--start"
      shift
      ;;
    --stop)
      COMMAND="--stop"
      shift
      ;;
    --protocol)
      COMM_PROTOCOL="$2"
      shift 2
      ;;
    --hybrid)
      RUN_HYBRID_MODE="1"
      shift
      ;;
    --hybrid-quick)
      RUN_HYBRID_QUICK_MODE="1"
      RUN_HYBRID_MODE="1"
      shift
      ;;
    --hybrid-stress)
      RUN_HYBRID_STRESS_MODE="1"
      RUN_HYBRID_MODE="1"
      shift
      ;;
    --hybrid-controls)
      RUN_REALISTIC_CONTROLS="1"
      RUN_HYBRID_MODE="1"
      shift
      ;;
    --help)
      usage
      exit 0
      ;;
    *)
      warn "Opción desconocida: $1"
      usage
      exit 1
      ;;
  esac
done

# Validate protocol
if [[ "$COMM_PROTOCOL" != "http" && "$COMM_PROTOCOL" != "https" ]]; then
  error "Protocolo inválido: $COMM_PROTOCOL. Usar 'http' o 'https'"
fi

case "${COMMAND}" in
  --start) start_services ;;
  --stop) stop_services ;;
  *) usage ;;
esac
