#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
Extrae consumo promedio de CPU y memoria desde Prometheus para cada run de k6.

Notas importantes para este workspace:
- Los servicios objetivo viven en el namespace realistic.
- Los pods relevantes son api-service, auth-service, data-service y postgres.
- Se suman métricas de consumo por ventana temporal de cada experimento.
"""
import os
import json
import csv
import requests
from datetime import datetime, timedelta
from glob import glob

def parse_k6_run(file_path):
    """Extrae el timestamp de inicio y fin del experimento desde el archivo JSON de k6."""
    with open(file_path) as f:
        lines = f.readlines()
    # Buscar el primer y último timestamp de tipo 'Point'
    times = [json.loads(l)["data"]["time"] for l in lines if '"type":"Point"' in l or '"type": "Point"' in l]
    if not times:
        return None, None
    def fix_iso(s):
        # Trunca microsegundos a 6 dígitos si es necesario
        if '.' in s:
            pre, post = s.split('.', 1)
            if '-' in post:
                frac, tz = post.split('-', 1)
                frac = frac[:6]
                s = f"{pre}.{frac}-{tz}"
            elif '+' in post:
                frac, tz = post.split('+', 1)
                frac = frac[:6]
                s = f"{pre}.{frac}+{tz}"
        return s.replace('Z', '+00:00')
    t0 = datetime.fromisoformat(fix_iso(times[0]))
    t1 = datetime.fromisoformat(fix_iso(times[-1]))
    return t0, t1

def query_prometheus(prom_url, query, start, end, step="15s"):
    """Consulta Prometheus usando la API HTTP para un rango de tiempo dado."""
    url = f"{prom_url}/api/v1/query_range"
    params = {
        "query": query,
        "start": start.timestamp(),
        "end": end.timestamp(),
        "step": step
    }
    r = requests.get(url, params=params)
    r.raise_for_status()
    return r.json()

def summarize_metric(result):
    """Calcula el promedio de la métrica en el rango consultado."""
    if result["status"] != "success" or not result["data"]["result"]:
        return None
    values = []
    for serie in result["data"]["result"]:
        serie_vals = [float(v[1]) for v in serie["values"]]
        values.extend(serie_vals)
    if not values:
        return None
    return sum(values) / len(values)

def main():
    prom_url = "http://localhost:30000"
    results_dir = "Testing/results/auto_runs"
    namespace = "realistic"
    pod_regex = "(api-service|auth-service|data-service|postgres).*"

    print("\nResumen de consumo de CPU y memoria por experimento (Prometheus):\n")
    print(f"{'Experimento':40} {'CPU total (mC)':>18} {'Memoria total (MiB)':>22}")
    print("-"*80)
    csv_rows = []

    for f in sorted(glob(os.path.join(results_dir, "*.json"))):
        t0, t1 = parse_k6_run(f)
        if not t0 or not t1:
            continue

        # CPU total en milicores. Se excluye la pseudo-container POD y series vacias.
        cpu_query = (
            "sum(rate(container_cpu_usage_seconds_total{"
            f'namespace="{namespace}", pod=~"{pod_regex}", container!="POD", image!=""'
            "}[1m])) * 1000"
        )

        # Memoria total en MiB (working set), excluyendo POD y series vacias.
        mem_query = (
            "sum(container_memory_working_set_bytes{"
            f'namespace="{namespace}", pod=~"{pod_regex}", container!="POD", image!=""'
            "}) / 1024 / 1024"
        )

        cpu_result = query_prometheus(prom_url, cpu_query, t0, t1)
        mem_result = query_prometheus(prom_url, mem_query, t0, t1)
        cpu_avg = summarize_metric(cpu_result)
        mem_avg = summarize_metric(mem_result)

        # Si no hay datos en la ventana exacta, reintenta con margen de 5 min
        # para capturar retrasos de scrape o ligeros desfases de reloj.
        if cpu_avg is None:
            cpu_result = query_prometheus(prom_url, cpu_query, t0 - timedelta(minutes=5), t1 + timedelta(minutes=5))
            cpu_avg = summarize_metric(cpu_result)
        if mem_avg is None:
            mem_result = query_prometheus(prom_url, mem_query, t0 - timedelta(minutes=5), t1 + timedelta(minutes=5))
            mem_avg = summarize_metric(mem_result)

        status = "ok" if cpu_avg is not None and mem_avg is not None else "sin_datos_en_ventana"
        cpu_str = f"{cpu_avg:18.2f}" if cpu_avg is not None else f"{'-':>18}"
        mem_str = f"{mem_avg:22.2f}" if mem_avg is not None else f"{'-':>22}"
        print(f"{os.path.basename(f):40} {cpu_str} {mem_str}")

        csv_rows.append(
            {
                "experimento": os.path.basename(f),
                "inicio": t0.isoformat(),
                "fin": t1.isoformat(),
                "cpu_total_mcores_prom": "" if cpu_avg is None else f"{cpu_avg:.6f}",
                "mem_total_mib_prom": "" if mem_avg is None else f"{mem_avg:.6f}",
                "status": status,
            }
        )

    out_csv = "Testing/results/control-kpis-prometheus.csv"
    with open(out_csv, "w", newline="", encoding="utf-8") as fh:
        writer = csv.DictWriter(
            fh,
            fieldnames=[
                "experimento",
                "inicio",
                "fin",
                "cpu_total_mcores_prom",
                "mem_total_mib_prom",
                "status",
            ],
        )
        writer.writeheader()
        writer.writerows(csv_rows)

    print(f"\nCSV generado: {out_csv}")

if __name__ == "__main__":
    main()
