#!/usr/bin/env python3
"""
run-factorial-campaign.py
=========================

Orquesta la campaña factorial completa:
    4 controles × 3 variantes × 4 cargas (1, 5, 10, 20 VUS) × 8 réplicas = 384 runs

Diseño:
- Aleatorización de bloques: las 8 réplicas de cada celda se distribuyen en
  bloques aleatorios para mitigar drift temporal del cluster.
- Cada run = 30s warmup k6 + 60s de medición efectiva (configurable).
- Métricas exportadas en CSV con columnas EXACTAS:
    control,variant,vus,replica,avg_ms,p95_ms,err_pct,rps,
    cpu_mcores,mem_mib,checks_pct,iterations,run_id,started_at,duration_s,status

Pre-requisitos:
- bash scripts/factorial-bootstrap.sh   (cluster en baseline limpio)
- k6 instalado en PATH
- Prometheus accesible en http://localhost:30000

Uso:
    python3 scripts/run-factorial-campaign.py
    python3 scripts/run-factorial-campaign.py --vus 1 5 --replicas 2 --duration 30
    python3 scripts/run-factorial-campaign.py --dry-run
"""
from __future__ import annotations

import argparse
import csv
import json
import os
import random
import re
import subprocess
import sys
import time
from datetime import datetime
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
APPLY_SH = ROOT / "scripts" / "factorial-apply-scenario.sh"
PROM_URL = "http://localhost:30000"

# Perfiles de carga soportados → script k6 a ejecutar.
# Las 6 métricas (avg_ms, p95_ms, err_pct, rps, cpu_mcores, mem_mib) son
# IDÉNTICAS entre perfiles; cambia solo el contenido del payload.
K6_PROFILES = {
    "crud":        ROOT / "k6" / "crud_products.js",
    "attack_sqli": ROOT / "k6" / "attack_sqli.js",
    "attack_credstuff": ROOT / "k6" / "attack_credstuff.js",
}

CRUD_REQUESTS_PER_ITERATION = 6
C4_RATE_LIMITS_RPM = {
    "moderate": 1200,
    "strict": 300,
}

# Diseño factorial: 12 escenarios
SCENARIOS = [
    ("C1", "baseline"), ("C1", "istio"),       ("C1", "kong"),
    ("C2", "baseline"), ("C2", "istio_mtls"),  ("C2", "linkerd_mtls"),
    ("C3", "baseline"), ("C3", "basic"),       ("C3", "strict"),
    ("C4", "baseline"), ("C4", "moderate"),    ("C4", "strict"),
]


def log(msg: str, level: str = "INFO") -> None:
    ts = datetime.now().strftime("%H:%M:%S")
    print(f"[{ts}] [{level}] {msg}", flush=True)


# ─────────────────────────────────────────────────────────────────────────────
# Aplicación de escenario y obtención de URLs
# ─────────────────────────────────────────────────────────────────────────────
def apply_scenario(control: str, variant: str) -> dict:
    """Ejecuta factorial-apply-scenario.sh y parsea las URLs de stdout."""
    res = subprocess.run(
        ["bash", str(APPLY_SH), control, variant],
        capture_output=True, text=True, check=False,
    )
    if res.returncode != 0:
        log(res.stderr, "ERROR")
        raise RuntimeError(f"apply-scenario {control}/{variant} falló")
    env = {}
    for line in res.stdout.strip().splitlines():
        if "=" in line:
            k, v = line.split("=", 1)
            env[k.strip()] = v.strip()
    return env


# ─────────────────────────────────────────────────────────────────────────────
# Ejecución k6
# ─────────────────────────────────────────────────────────────────────────────
def build_profile_env(profile: str, control: str, variant: str, vus: int) -> dict:
    if profile != "crud" or control != "C4" or variant not in C4_RATE_LIMITS_RPM:
        return {}

    limit_rps = C4_RATE_LIMITS_RPM[variant] / 60.0
    target_rps = limit_rps * 0.7
    iteration_s = (CRUD_REQUESTS_PER_ITERATION * vus) / target_rps
    think_time_s = max(1.0, round(iteration_s, 2))
    return {"THINK_TIME_S": str(think_time_s)}


def run_k6(env: dict, vus: int, duration_s: int, summary_path: Path,
           script: Path, extra_env: dict | None = None) -> tuple[bool, str, str]:
    cmd = [
        "k6", "run",
        "--vus", str(vus),
        "--duration", f"{duration_s}s",
        "--summary-export", str(summary_path),
        "--no-color",
        "--quiet",
        str(script),
    ]
    proc_env = os.environ.copy()
    proc_env.update({
        "API_URL":  env.get("API_URL", ""),
        "AUTH_URL": env.get("AUTH_URL", env.get("API_URL", "")),
        "HOST_HEADER": env.get("HOST_HEADER", ""),
        "USERNAME": "demo",
        "PASSWORD": "demo123",
    })
    if extra_env:
        proc_env.update(extra_env)
    res = subprocess.run(cmd, env=proc_env, capture_output=True, text=True)
    return (
        res.returncode == 0,
        res.stdout or "",
        res.stderr[-2000:] if res.returncode != 0 else "",
    )


def parse_k6_summary(p: Path) -> dict:
    """Devuelve métricas k6 normalizadas."""
    if not p.exists():
        return {}
    try:
        s = json.loads(p.read_text())
    except Exception:
        return {}
    metrics = s.get("metrics", {})
    http = metrics.get("http_req_duration", {})
    avg_ms = float(http.get("avg", 0.0))
    p95_ms = float(http.get("p(95)", 0.0))

    def _rate_or_passfail(m: dict) -> float:
        # k6 v1.6+ expone `value` (la rate calculada). Versiones previas usaban
        # `rate`. Como último fallback, calcularla de passes/fails (semántica
        # k6 Rate: passes = #true, fails = #false → rate = passes/(passes+fails)).
        v = m.get("value")
        if v is not None:
            return float(v)
        r = m.get("rate")
        if r is not None:
            return float(r)
        p = float(m.get("passes", 0) or 0)
        f = float(m.get("fails", 0) or 0)
        tot = p + f
        return (p / tot) if tot > 0 else 0.0

    failed = metrics.get("http_req_failed", {})
    err_pct = _rate_or_passfail(failed) * 100.0
    reqs = metrics.get("http_reqs", {})
    rps = float(reqs.get("rate", 0.0))
    iters = float(metrics.get("iterations", {}).get("count", 0.0))
    checks = metrics.get("checks", {})
    chk_pct = _rate_or_passfail(checks) * 100.0
    return {
        "avg_ms": round(avg_ms, 2),
        "p95_ms": round(p95_ms, 2),
        "err_pct": round(err_pct, 2),
        "rps": round(rps, 2),
        "iterations": int(iters),
        "checks_pct": round(chk_pct, 2),
    }


def parse_attack_summary(profile: str, summary_path: Path) -> dict:
    """Extrae métricas específicas desde el summary-export JSON de k6."""
    if not summary_path.exists():
        return {}

    try:
        payload = json.loads(summary_path.read_text())
    except Exception:
        return {}

    metrics = payload.get("metrics", {})

    if profile == "attack_sqli":
        attempts = int(metrics.get("sqli_attempts_total", {}).get("count", 0) or 0)
        blocked = int(metrics.get("sqli_blocked_total", {}).get("count", 0) or 0)
        leaked = int(metrics.get("sqli_leaked_total", {}).get("count", 0) or 0)
        other = int(metrics.get("sqli_other_total", {}).get("count", 0) or 0)
        mitigation = round((blocked * 100.0 / attempts), 2) if attempts > 0 else 0.0
        return {
            "sqli_attempts_total": attempts,
            "sqli_blocked_total": blocked,
            "sqli_leaked_total": leaked,
            "sqli_other_total": other,
            "sqli_mitigation_rate": mitigation,
        }

    if profile != "attack_credstuff":
        return {}

    attempts = int(metrics.get("credstuff_attempts_total", {}).get("count", 0) or 0)
    ratelimited = int(metrics.get("credstuff_ratelimited_total", {}).get("count", 0) or 0)
    unauthorized = int(metrics.get("credstuff_unauthorized_total", {}).get("count", 0) or 0)
    success = int(metrics.get("credstuff_success_total", {}).get("count", 0) or 0)
    mitigation = round((ratelimited * 100.0 / attempts), 2) if attempts > 0 else 0.0
    return {
        "credstuff_attempts_total": attempts,
        "credstuff_ratelimited_total": ratelimited,
        "credstuff_unauthorized_total": unauthorized,
        "credstuff_success_total": success,
        "credstuff_mitigation_rate": mitigation,
    }


# ─────────────────────────────────────────────────────────────────────────────
# Métricas Prometheus
# ─────────────────────────────────────────────────────────────────────────────
def prom_query(q: str) -> float | None:
    import urllib.parse, urllib.request
    url = f"{PROM_URL}/api/v1/query?query={urllib.parse.quote(q)}"
    try:
        with urllib.request.urlopen(url, timeout=5) as r:
            data = json.loads(r.read())
        result = data.get("data", {}).get("result", [])
        if not result:
            return 0.0
        return float(result[0]["value"][1])
    except Exception:
        return None


def collect_resources() -> dict:
    cpu = prom_query(
        'sum(rate(container_cpu_usage_seconds_total{namespace="realistic",'
        'container!="POD",container!=""}[1m])) * 1000'
    )
    mem = prom_query(
        'sum(container_memory_working_set_bytes{namespace="realistic",'
        'container!="POD",container!=""}) / 1024 / 1024'
    )
    return {
        "cpu_mcores": round(cpu, 1) if cpu is not None else -1,
        "mem_mib":    round(mem, 1) if mem is not None else -1,
    }


# ─────────────────────────────────────────────────────────────────────────────
# Plan de ejecución (aleatorización por bloques)
# ─────────────────────────────────────────────────────────────────────────────
def build_plan(scenarios, vus_levels, replicas, seed):
    """
    Aleatorización por bloques:
    - Cada bloque contiene UNA réplica de las 12*len(vus_levels) celdas.
    - Se generan `replicas` bloques, cada uno con orden aleatorio independiente.
    - Esto reduce confounding por drift temporal.
    """
    rng = random.Random(seed)
    plan = []
    for r in range(1, replicas + 1):
        block = [(c, v, vus, r) for (c, v) in scenarios for vus in vus_levels]
        rng.shuffle(block)
        plan.extend(block)
    return plan


def build_plan_for_replica_range(scenarios, vus_levels, replica_start, replica_end, seed):
    """
    Igual que build_plan(), pero ejecuta solo un rango explícito de réplicas.
    Esto permite partir una campaña grande en bloques pequeños sin perder los
    IDs reales de réplica del diseño experimental final.
    """
    rng = random.Random(seed)
    plan = []
    for r in range(replica_start, replica_end + 1):
        block = [(c, v, vus, r) for (c, v) in scenarios for vus in vus_levels]
        rng.shuffle(block)
        plan.extend(block)
    return plan


# ─────────────────────────────────────────────────────────────────────────────
# Main
# ─────────────────────────────────────────────────────────────────────────────
def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--vus", nargs="+", type=int, default=[1, 5, 10, 20])
    ap.add_argument("--replicas", type=int, default=8)
    ap.add_argument("--replica-start", type=int, default=None,
                    help="primera réplica a ejecutar (para correr por bloques)")
    ap.add_argument("--replica-end", type=int, default=None,
                    help="última réplica a ejecutar (para correr por bloques)")
    ap.add_argument("--duration", type=int, default=60, help="seg de carga por run")
    ap.add_argument("--warmup", type=int, default=15, help="seg estabilización pre-run")
    ap.add_argument("--out-dir", default=None)
    ap.add_argument("--seed", type=int, default=20260520)
    ap.add_argument("--dry-run", action="store_true")
    ap.add_argument("--scenarios", nargs="*", default=None,
                    help="filtrar: ej C1/baseline C2/istio_mtls")
    ap.add_argument("--profile", choices=sorted(K6_PROFILES.keys()),
                    default="crud",
                    help="perfil de carga k6 (crud=legítimo, attack_sqli=SQLi, attack_credstuff=burst login)")
    args = ap.parse_args()

    k6_script = K6_PROFILES[args.profile]
    if not k6_script.exists():
        log(f"k6 script no existe: {k6_script}", "ERROR")
        sys.exit(1)
    log(f"Profile: {args.profile}  →  {k6_script.name}")

    scenarios = SCENARIOS
    if args.scenarios:
        wanted = {tuple(s.split("/")) for s in args.scenarios}
        scenarios = [s for s in SCENARIOS if s in wanted]

    if (args.replica_start is None) != (args.replica_end is None):
        log("--replica-start y --replica-end deben usarse juntos", "ERROR")
        sys.exit(2)

    if args.replica_start is not None:
        if args.replica_start < 1 or args.replica_end < args.replica_start:
            log("rango de réplicas inválido", "ERROR")
            sys.exit(2)
        replica_count = args.replica_end - args.replica_start + 1
        plan = build_plan_for_replica_range(
            scenarios, args.vus, args.replica_start, args.replica_end, args.seed
        )
        replica_label = f"réplicas {args.replica_start}-{args.replica_end}"
    else:
        replica_count = args.replicas
        plan = build_plan(scenarios, args.vus, args.replicas, args.seed)
        replica_label = f"{args.replicas} réplicas"

    total = len(plan)
    log(f"Plan: {len(scenarios)} escenarios × {len(args.vus)} cargas × "
        f"{replica_label} = {total} runs")
    log(f"Estimado: ~{total * (args.duration + args.warmup + 5) / 60:.1f} min "
        f"(asumiendo {args.duration}s + {args.warmup}s + overhead)")

    if args.dry_run:
        for i, (c, v, vus, r) in enumerate(plan[:20], 1):
            print(f"  {i:3d}/{total}: {c}/{v}  VUS={vus}  rep={r}")
        if total > 20:
            print(f"  ... +{total-20} más")
        return

    ts = datetime.now().strftime("%Y%m%d_%H%M%S")
    out_dir = Path(args.out_dir) if args.out_dir else (
        ROOT / "Testing" / "results" / "factorial_campaign" / f"campaign_{ts}"
    )
    out_dir.mkdir(parents=True, exist_ok=True)
    csv_path = out_dir / "results_factorial.csv"
    log(f"Output: {csv_path}")

    cols = [
        "run_id", "started_at", "profile", "control", "variant", "vus", "replica",
        "avg_ms", "p95_ms", "err_pct", "rps", "cpu_mcores", "mem_mib",
        "checks_pct", "iterations",
        "sqli_attempts_total", "sqli_blocked_total", "sqli_leaked_total",
        "sqli_other_total", "sqli_mitigation_rate",
        "credstuff_attempts_total", "credstuff_ratelimited_total",
        "credstuff_unauthorized_total", "credstuff_success_total",
        "credstuff_mitigation_rate",
        "duration_s", "status", "error",
    ]
    with csv_path.open("w", newline="") as f:
        w = csv.DictWriter(f, fieldnames=cols)
        w.writeheader()

        # Para evitar reaplicar el mismo escenario consecutivamente sin necesidad,
        # tracking del último escenario aplicado
        last_scn = None
        last_env = None

        for idx, (control, variant, vus, replica) in enumerate(plan, 1):
            run_id = f"{args.profile}_{control}_{variant}_vus{vus}_r{replica}"
            log(f"[{idx:3d}/{total}] {run_id}")
            row = {
                "run_id": run_id,
                "started_at": datetime.now().isoformat(timespec="seconds"),
                "profile": args.profile,
                "control": control, "variant": variant, "vus": vus, "replica": replica,
                "avg_ms": "", "p95_ms": "", "err_pct": "", "rps": "",
                "cpu_mcores": "", "mem_mib": "", "checks_pct": "", "iterations": "",
                "sqli_attempts_total": "", "sqli_blocked_total": "",
                "sqli_leaked_total": "", "sqli_other_total": "",
                "sqli_mitigation_rate": "",
                "credstuff_attempts_total": "", "credstuff_ratelimited_total": "",
                "credstuff_unauthorized_total": "", "credstuff_success_total": "",
                "credstuff_mitigation_rate": "",
                "duration_s": args.duration, "status": "fail", "error": "",
            }
            try:
                if (control, variant) != last_scn:
                    last_env = apply_scenario(control, variant)
                    last_scn = (control, variant)
                    log(f"  scenario applied: API={last_env.get('API_URL')}", "DEBUG")
                    time.sleep(args.warmup)
                summary = out_dir / f"{run_id}_summary.json"
                extra_env = build_profile_env(args.profile, control, variant, vus)
                if extra_env:
                    log(f"  pacing env: {extra_env}", "DEBUG")
                ok, stdout, err = run_k6(last_env, vus, args.duration, summary, k6_script, extra_env)
                m = parse_k6_summary(summary)
                custom = parse_attack_summary(args.profile, summary)
                res = collect_resources()
                row.update(m); row.update(custom); row.update(res)
                # En attack_sqli el WAF responde 4xx legítimamente → checks_pct
                # baja (esperado). No usar checks_pct como gate de éxito.
                if args.profile in {"attack_sqli", "attack_credstuff"}:
                    row["status"] = "ok" if ok else "fail"
                else:
                    row["status"] = "ok" if ok and m.get("checks_pct", 0) >= 80 else "fail"
                if not ok:
                    row["error"] = err.replace("\n", " | ")[:300]
            except Exception as e:
                row["error"] = str(e)[:300]
                log(f"  ERROR: {e}", "ERROR")

            w.writerow(row); f.flush()
            log(f"  {row['status']}  avg={row['avg_ms']}  p95={row['p95_ms']}  "
                f"rps={row['rps']}  cpu={row['cpu_mcores']}  mem={row['mem_mib']}  "
                f"err%={row['err_pct']}"
                     + (f"  sqli_mitig%={row['sqli_mitigation_rate']}"
                         if args.profile == "attack_sqli" else "")
                + (f"  credstuff_mitig%={row['credstuff_mitigation_rate']}"
                   if args.profile == "attack_credstuff" else ""))

    log(f"Campaña terminada: {csv_path}")


if __name__ == "__main__":
    main()
