#!/usr/bin/env bash
set -euo pipefail

GRAFANA_URL="${GRAFANA_URL:-http://127.0.0.1:30030}"
GRAFANA_USER="${GRAFANA_USER:-}"
GRAFANA_PASS="${GRAFANA_PASS:-}"

kctl() {
  if command -v microk8s >/dev/null 2>&1; then
    microk8s kubectl "$@"
  else
    kubectl "$@"
  fi
}

if [[ -z "${GRAFANA_USER}" || -z "${GRAFANA_PASS}" ]]; then
  GRAFANA_USER=$(kctl -n monitoring get secret prometheus-grafana -o jsonpath='{.data.admin-user}' 2>/dev/null | base64 -d || true)
  GRAFANA_PASS=$(kctl -n monitoring get secret prometheus-grafana -o jsonpath='{.data.admin-password}' 2>/dev/null | base64 -d || true)
fi

if [[ -z "${GRAFANA_USER}" || -z "${GRAFANA_PASS}" ]]; then
  echo "[ERROR] Missing Grafana credentials"
  exit 1
fi

if ! curl -sS --max-time 5 "${GRAFANA_URL}/api/health" >/dev/null 2>&1; then
  echo "[ERROR] Grafana unreachable at ${GRAFANA_URL}"
  exit 1
fi

read -r -d '' DASHBOARD_JSON <<'EOF' || true
{
  "dashboard": {
    "id": null,
    "uid": "mubench-live-control-compare",
    "title": "MuBench Live Control Comparison",
    "tags": ["mubench", "live", "control", "comparison"],
    "timezone": "browser",
    "schemaVersion": 39,
    "version": 0,
    "refresh": "5s",
    "templating": {
      "list": [
        {
          "name": "service",
          "type": "query",
          "datasource": "Prometheus",
          "refresh": 1,
          "query": "label_values(mubench_http_requests_total, service)",
          "includeAll": true,
          "multi": true,
          "current": {
            "selected": true,
            "text": "All",
            "value": "$__all"
          }
        }
      ]
    },
    "annotations": {
      "list": [
        {
          "builtIn": 1,
          "datasource": {
            "type": "grafana",
            "uid": "-- Grafana --"
          },
          "enable": true,
          "hide": false,
          "iconColor": "rgba(255, 96, 96, 1)",
          "name": "Annotations & Alerts",
          "target": {
            "limit": 100,
            "matchAny": false,
            "tags": ["mubench-live"],
            "type": "tags"
          },
          "type": "dashboard"
        }
      ]
    },
    "panels": [
      {
        "id": 1,
        "type": "timeseries",
        "title": "Request rate (RPS) by service",
        "datasource": "Prometheus",
        "targets": [
          {
            "expr": "sum by (service) (rate(mubench_http_requests_total{service=~\"$service\"}[1m]))",
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
            "expr": "1000 * histogram_quantile(0.95, sum by (le, service) (rate(mubench_http_request_duration_seconds_bucket{service=~\"$service\"}[5m])))",
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
            "expr": "sum by (service) (rate(mubench_http_requests_total{service=~\"$service\",status=~\"5..\"}[5m])) / sum by (service) (rate(mubench_http_requests_total{service=~\"$service\"}[5m]))",
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
        "title": "Node CPU usage (mcores)",
        "datasource": "Prometheus",
        "targets": [
          {
            "expr": "sum(rate(container_cpu_usage_seconds_total{container!=\"\",image!=\"\"}[1m])) * 1000",
            "legendFormat": "node cpu"
          }
        ],
        "gridPos": {"x": 12, "y": 8, "w": 12, "h": 8}
      },
      {
        "id": 5,
        "type": "timeseries",
        "title": "Node memory usage (MiB)",
        "datasource": "Prometheus",
        "targets": [
          {
            "expr": "sum(container_memory_working_set_bytes{container!=\"\",image!=\"\"}) / 1024 / 1024",
            "legendFormat": "node mem"
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

RESP=$(curl -sS -X POST -H "Content-Type: application/json" \
  -u "${GRAFANA_USER}:${GRAFANA_PASS}" \
  -d "${DASHBOARD_JSON}" \
  "${GRAFANA_URL}/api/dashboards/db")

echo "[INFO] Publish response: ${RESP}"
echo "[INFO] Dashboard URL: ${GRAFANA_URL}/d/mubench-live-control-compare/mubench-live-control-comparison"
echo "[INFO] Tip: use helper script to generate annotations by control/variant/action"
