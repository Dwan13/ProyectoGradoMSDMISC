#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
RULE_GEN_SCRIPT="${ROOT_DIR}/RealisticServices/generate-final-thesis-comparison-rule.py"
RULE_FILE="${ROOT_DIR}/RealisticServices/k8s/06-final-thesis-comparison-rule.yaml"

GRAFANA_URL="${GRAFANA_URL:-http://localhost:3000}"
GRAFANA_USER="${GRAFANA_USER:-admin}"
GRAFANA_PASS="${GRAFANA_PASS:-}"

if [[ -z "${GRAFANA_PASS}" ]]; then
  for ns in observability monitoring; do
    for secret in kube-prom-stack-grafana prometheus-grafana; do
      GRAFANA_PASS=$(microk8s kubectl get secret -n "${ns}" "${secret}" -o jsonpath='{.data.admin-password}' 2>/dev/null | base64 --decode || true)
      if [[ -n "${GRAFANA_PASS}" ]]; then
        GRAFANA_USER=$(microk8s kubectl get secret -n "${ns}" "${secret}" -o jsonpath='{.data.admin-user}' 2>/dev/null | base64 --decode || echo "${GRAFANA_USER}")
        break 2
      fi
    done
  done
fi

python3 "${RULE_GEN_SCRIPT}"

if microk8s kubectl get ns monitoring >/dev/null 2>&1; then
  microk8s kubectl apply -f "${RULE_FILE}"
  echo "[INFO] Applied PrometheusRule: ${RULE_FILE}"
else
  echo "[WARN] Namespace monitoring not found. Apply manually:"
  echo "  microk8s kubectl apply -f ${RULE_FILE}"
fi

if [[ -z "${GRAFANA_PASS}" ]]; then
  echo "[WARN] Could not obtain Grafana password."
  echo "[INFO] Rule was generated/applied; publish dashboard manually if needed."
  exit 0
fi

if ! curl -s --max-time 3 "${GRAFANA_URL}/api/health" >/dev/null 2>&1; then
  echo "[WARN] Grafana not reachable at ${GRAFANA_URL}."
  echo "[INFO] Start a port-forward, then rerun this script:"
  echo "  microk8s kubectl -n observability port-forward svc/kube-prom-stack-grafana 3000:80"
  exit 0
fi

read -r -d '' DASHBOARD_JSON <<'EOF' || true
{
  "dashboard": {
    "id": null,
    "uid": "mubench-final-thesis-controls",
    "title": "MuBench Final Comparative Evaluation - Security Controls",
    "tags": ["mubench", "final", "thesis", "comparison"],
    "timezone": "browser",
    "schemaVersion": 39,
    "version": 0,
    "refresh": "30s",
    "templating": {
      "list": [
        {
          "name": "control",
          "type": "query",
          "datasource": "Prometheus",
          "refresh": 1,
          "query": "label_values(mubench_final_avg_ms, control)",
          "includeAll": true,
          "multi": false,
          "current": {"selected": true, "text": "All", "value": "$__all"}
        },
        {
          "name": "technology",
          "type": "query",
          "datasource": "Prometheus",
          "refresh": 1,
          "query": "label_values(mubench_final_avg_ms, technology)",
          "includeAll": true,
          "multi": true,
          "current": {"selected": true, "text": "All", "value": "$__all"}
        }
      ]
    },
    "panels": [
      {
        "id": 1,
        "type": "bargauge",
        "title": "Average Latency (ms) by Control/Technology/VUS",
        "datasource": "Prometheus",
        "targets": [
          {
            "expr": "mubench_final_avg_ms{control=~\"$control\",technology=~\"$technology\"}",
            "legendFormat": "{{control}} | {{technology}} | vus={{vus}}",
            "instant": true
          }
        ],
        "fieldConfig": {"defaults": {"unit": "ms"}, "overrides": []},
        "options": {"displayMode": "gradient", "orientation": "horizontal", "showUnfilled": true, "valueMode": "color"},
        "gridPos": {"x": 0, "y": 0, "w": 12, "h": 9}
      },
      {
        "id": 2,
        "type": "bargauge",
        "title": "P95 Latency (ms) by Control/Technology/VUS",
        "datasource": "Prometheus",
        "targets": [
          {
            "expr": "mubench_final_p95_ms{control=~\"$control\",technology=~\"$technology\"}",
            "legendFormat": "{{control}} | {{technology}} | vus={{vus}}",
            "instant": true
          }
        ],
        "fieldConfig": {"defaults": {"unit": "ms"}, "overrides": []},
        "options": {"displayMode": "gradient", "orientation": "horizontal", "showUnfilled": true, "valueMode": "color"},
        "gridPos": {"x": 12, "y": 0, "w": 12, "h": 9}
      },
      {
        "id": 3,
        "type": "bargauge",
        "title": "Error Rate (%) by Control/Technology/VUS",
        "datasource": "Prometheus",
        "targets": [
          {
            "expr": "mubench_final_err_pct{control=~\"$control\",technology=~\"$technology\"}",
            "legendFormat": "{{control}} | {{technology}} | vus={{vus}}",
            "instant": true
          }
        ],
        "fieldConfig": {"defaults": {"unit": "percent"}, "overrides": []},
        "options": {"displayMode": "gradient", "orientation": "horizontal", "showUnfilled": true, "valueMode": "color"},
        "gridPos": {"x": 0, "y": 9, "w": 12, "h": 9}
      },
      {
        "id": 4,
        "type": "bargauge",
        "title": "Throughput (req/s) by Control/Technology/VUS",
        "datasource": "Prometheus",
        "targets": [
          {
            "expr": "mubench_final_rps{control=~\"$control\",technology=~\"$technology\"}",
            "legendFormat": "{{control}} | {{technology}} | vus={{vus}}",
            "instant": true
          }
        ],
        "fieldConfig": {"defaults": {"unit": "reqps"}, "overrides": []},
        "options": {"displayMode": "gradient", "orientation": "horizontal", "showUnfilled": true, "valueMode": "color"},
        "gridPos": {"x": 12, "y": 9, "w": 12, "h": 9}
      },
      {
        "id": 5,
        "type": "bargauge",
        "title": "CPU Consumption (mcores) by Control/Technology/VUS",
        "datasource": "Prometheus",
        "targets": [
          {
            "expr": "mubench_final_cpu_mcores{control=~\"$control\",technology=~\"$technology\"}",
            "legendFormat": "{{control}} | {{technology}} | vus={{vus}}",
            "instant": true
          }
        ],
        "fieldConfig": {"defaults": {"unit": "short"}, "overrides": []},
        "options": {"displayMode": "gradient", "orientation": "horizontal", "showUnfilled": true, "valueMode": "color"},
        "gridPos": {"x": 0, "y": 18, "w": 12, "h": 9}
      },
      {
        "id": 6,
        "type": "bargauge",
        "title": "Memory Consumption (MiB) by Control/Technology/VUS",
        "datasource": "Prometheus",
        "targets": [
          {
            "expr": "mubench_final_mem_mib{control=~\"$control\",technology=~\"$technology\"}",
            "legendFormat": "{{control}} | {{technology}} | vus={{vus}}",
            "instant": true
          }
        ],
        "fieldConfig": {"defaults": {"unit": "decmbytes"}, "overrides": []},
        "options": {"displayMode": "gradient", "orientation": "horizontal", "showUnfilled": true, "valueMode": "color"},
        "gridPos": {"x": 12, "y": 18, "w": 12, "h": 9}
      }
    ]
  },
  "overwrite": true
}
EOF

RESP=$(curl -s -X POST -H "Content-Type: application/json" \
  -u "${GRAFANA_USER}:${GRAFANA_PASS}" \
  -d "${DASHBOARD_JSON}" \
  "${GRAFANA_URL}/api/dashboards/db")

echo "[INFO] Dashboard publish response: ${RESP}"
echo "[INFO] Dashboard URL: ${GRAFANA_URL}/d/mubench-final-thesis-controls/mubench-final-comparative-evaluation-security-controls"
