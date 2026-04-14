#!/usr/bin/env bash
set -euo pipefail

GRAFANA_URL="${GRAFANA_URL:-http://localhost:3000}"
GRAFANA_USER="${GRAFANA_USER:-admin}"
GRAFANA_PASS="${GRAFANA_PASS:-}"

if [[ -z "${GRAFANA_PASS}" ]]; then
  GRAFANA_PASS=$(microk8s kubectl get secret -n observability kube-prom-stack-grafana -o jsonpath='{.data.admin-password}' 2>/dev/null | base64 --decode || true)
fi

if [[ -z "${GRAFANA_PASS}" ]]; then
  echo "[WARN] No se pudo obtener contraseña de Grafana"
  exit 0
fi

if ! curl -s --max-time 3 "${GRAFANA_URL}/api/health" >/dev/null 2>&1; then
  echo "[WARN] Grafana no está accesible en ${GRAFANA_URL}. Ejecuta port-forward si es necesario."
  exit 0
fi

DS_COUNT=$(curl -s -u "${GRAFANA_USER}:${GRAFANA_PASS}" "${GRAFANA_URL}/api/datasources" | python3 -c 'import sys,json; print(len(json.load(sys.stdin)))' 2>/dev/null || echo "0")
if [[ "${DS_COUNT}" == "0" ]]; then
  echo "[INFO] No datasource found. Creating Prometheus datasource..."
  read -r -d '' DATASOURCE_JSON <<'EOF' || true
{
  "name": "Prometheus",
  "type": "prometheus",
  "access": "proxy",
  "url": "http://kube-prom-stack-kube-prome-prometheus.observability.svc:9090",
  "isDefault": true,
  "jsonData": {
    "timeInterval": "10s"
  }
}
EOF

  DS_RESP=$(curl -s -X POST -H "Content-Type: application/json" \
    -u "${GRAFANA_USER}:${GRAFANA_PASS}" \
    -d "${DATASOURCE_JSON}" \
    "${GRAFANA_URL}/api/datasources")
  echo "[INFO] Datasource response: ${DS_RESP}"
else
  echo "[INFO] Datasource already configured (${DS_COUNT})"
fi

read -r -d '' DASHBOARD_JSON <<'EOF' || true
{
  "dashboard": {
    "id": null,
    "uid": "mubench-realistic-observability",
    "title": "MuBench Realistic Services - Realtime",
    "tags": ["mubench", "realistic", "realtime"],
    "timezone": "browser",
    "schemaVersion": 39,
    "version": 0,
    "refresh": "10s",
    "panels": [
      {
        "id": 1,
        "type": "timeseries",
        "title": "RPS by service",
        "datasource": "Prometheus",
        "targets": [
          {
            "expr": "sum by (service) (rate(mubench_http_requests_total[1m]))",
            "legendFormat": "{{service}}"
          }
        ],
        "gridPos": {"x": 0, "y": 0, "w": 12, "h": 8}
      },
      {
        "id": 2,
        "type": "timeseries",
        "title": "HTTP P95 latency by service (ms)",
        "datasource": "Prometheus",
        "targets": [
          {
            "expr": "1000 * histogram_quantile(0.95, sum by (le, service) (rate(mubench_http_request_duration_seconds_bucket[5m])))",
            "legendFormat": "{{service}}"
          }
        ],
        "gridPos": {"x": 12, "y": 0, "w": 12, "h": 8}
      },
      {
        "id": 3,
        "type": "timeseries",
        "title": "HTTP error rate by service",
        "datasource": "Prometheus",
        "targets": [
          {
            "expr": "sum by (service) (rate(mubench_http_requests_total{status=~\"5..\"}[5m])) / sum by (service) (rate(mubench_http_requests_total[5m]))",
            "legendFormat": "{{service}}"
          }
        ],
        "fieldConfig": {
          "defaults": {
            "unit": "percentunit",
            "min": 0
          },
          "overrides": []
        },
        "gridPos": {"x": 0, "y": 8, "w": 12, "h": 8}
      },
      {
        "id": 4,
        "type": "timeseries",
        "title": "DB query P95 (ms)",
        "datasource": "Prometheus",
        "targets": [
          {
            "expr": "1000 * histogram_quantile(0.95, sum by (le, query_name) (rate(mubench_db_query_duration_seconds_bucket[5m])))",
            "legendFormat": "{{query_name}}"
          }
        ],
        "gridPos": {"x": 12, "y": 8, "w": 12, "h": 8}
      },
      {
        "id": 5,
        "type": "timeseries",
        "title": "API downstream P95 to data-service (ms)",
        "datasource": "Prometheus",
        "targets": [
          {
            "expr": "1000 * histogram_quantile(0.95, sum by (le, downstream) (rate(mubench_downstream_request_duration_seconds_bucket[5m])))",
            "legendFormat": "{{downstream}}"
          }
        ],
        "gridPos": {"x": 0, "y": 16, "w": 12, "h": 8}
      },
      {
        "id": 6,
        "type": "stat",
        "title": "Total request rate",
        "datasource": "Prometheus",
        "targets": [
          {
            "expr": "sum(rate(mubench_http_requests_total[1m]))"
          }
        ],
        "fieldConfig": {
          "defaults": {
            "unit": "reqps"
          },
          "overrides": []
        },
        "gridPos": {"x": 12, "y": 16, "w": 12, "h": 8}
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
echo "[INFO] Dashboard URL: ${GRAFANA_URL}/d/mubench-realistic-observability/mubench-realistic-services-realtime"

read -r -d '' DASHBOARD_COMPARISON_JSON <<'EOF' || true
{
  "dashboard": {
    "id": null,
    "uid": "mubench-controls-tech-comparison",
    "title": "MuBench Controls - Tech Comparison",
    "tags": ["mubench", "controls", "comparison"],
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
          "query": "label_values(mubench_experiment_avg_ms, control)",
          "includeAll": true,
          "multi": false,
          "current": {
            "selected": true,
            "text": "All",
            "value": "$__all"
          }
        }
      ]
    },
    "panels": [
      {
        "id": 1,
        "type": "bargauge",
        "title": "AVG latency by technology/vus (ms)",
        "datasource": "Prometheus",
        "targets": [
          {
            "expr": "mubench_experiment_avg_ms{control=~\"$control\"}",
            "legendFormat": "{{control}} | {{technology}} | vus={{vus}}",
            "instant": true
          }
        ],
        "fieldConfig": {
          "defaults": {
            "unit": "ms"
          },
          "overrides": []
        },
        "options": {
          "displayMode": "gradient",
          "orientation": "horizontal",
          "showUnfilled": true,
          "valueMode": "color"
        },
        "gridPos": {"x": 0, "y": 0, "w": 24, "h": 8}
      },
      {
        "id": 2,
        "type": "bargauge",
        "title": "P95 latency by technology/vus (ms)",
        "datasource": "Prometheus",
        "targets": [
          {
            "expr": "mubench_experiment_p95_ms{control=~\"$control\"}",
            "legendFormat": "{{control}} | {{technology}} | vus={{vus}}",
            "instant": true
          }
        ],
        "fieldConfig": {
          "defaults": {
            "unit": "ms"
          },
          "overrides": []
        },
        "options": {
          "displayMode": "gradient",
          "orientation": "horizontal",
          "showUnfilled": true,
          "valueMode": "color"
        },
        "gridPos": {"x": 0, "y": 8, "w": 24, "h": 8}
      },
      {
        "id": 3,
        "type": "bargauge",
        "title": "AVG overhead vs baseline (%)",
        "datasource": "Prometheus",
        "targets": [
          {
            "expr": "mubench_experiment_overhead_avg_pct{control=~\"$control\",technology!~\"baseline\"}",
            "legendFormat": "{{control}} | {{technology}} | vus={{vus}}",
            "instant": true
          }
        ],
        "fieldConfig": {
          "defaults": {
            "unit": "percent",
            "decimals": 2
          },
          "overrides": []
        },
        "options": {
          "displayMode": "gradient",
          "orientation": "horizontal",
          "showUnfilled": true,
          "valueMode": "color"
        },
        "gridPos": {"x": 0, "y": 16, "w": 24, "h": 8}
      },
      {
        "id": 4,
        "type": "bargauge",
        "title": "P95 overhead vs baseline (%)",
        "datasource": "Prometheus",
        "targets": [
          {
            "expr": "mubench_experiment_overhead_p95_pct{control=~\"$control\",technology!~\"baseline\"}",
            "legendFormat": "{{control}} | {{technology}} | vus={{vus}}",
            "instant": true
          }
        ],
        "fieldConfig": {
          "defaults": {
            "unit": "percent",
            "decimals": 2
          },
          "overrides": []
        },
        "options": {
          "displayMode": "gradient",
          "orientation": "horizontal",
          "showUnfilled": true,
          "valueMode": "color"
        },
        "gridPos": {"x": 0, "y": 24, "w": 24, "h": 8}
      }
    ]
  },
  "overwrite": true
}
EOF

RESP2=$(curl -s -X POST -H "Content-Type: application/json" \
  -u "${GRAFANA_USER}:${GRAFANA_PASS}" \
  -d "${DASHBOARD_COMPARISON_JSON}" \
  "${GRAFANA_URL}/api/dashboards/db")

echo "[INFO] Comparison dashboard response: ${RESP2}"
echo "[INFO] Comparison dashboard URL: ${GRAFANA_URL}/d/mubench-controls-tech-comparison/mubench-controls-tech-comparison"
