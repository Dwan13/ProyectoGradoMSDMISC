#!/usr/bin/env python3
"""S2 final campaign analyzer.

Outputs:
- Per-run and per-experiment timing tables
- Success and latency rankings by endpoint
- PNG plots for quick reporting
- Grafana-friendly long CSV exports
- ANOVA matrix aligned to hypotheses H1-H4
- LaTeX summary for thesis/report integration
"""

from __future__ import annotations

import csv
import json
import os
import re
import urllib.parse
import urllib.request
from collections import defaultdict
from dataclasses import dataclass, asdict
from datetime import datetime
from pathlib import Path
from typing import Dict, Iterable, List, Tuple

import matplotlib.pyplot as plt
import numpy as np
import pandas as pd
import statsmodels.api as sm
import statsmodels.formula.api as smf
from statsmodels.stats.anova import anova_lm


ROOT = Path(__file__).resolve().parents[1]
RESULTS_DIR = ROOT / "Testing/results/auto_runs/randomized_campaigns"
INPUT_GLOB = "s2_academic_base_n8_*.json"
DATE_TAG = datetime.now().strftime("%Y%m%d")
OUT_DIR = RESULTS_DIR / f"s2_final_analysis_{DATE_TAG}"
PLOTS_DIR = OUT_DIR / "plots"

PROM_URL = os.getenv("PROM_URL", "http://localhost:30000")
PROM_STEP = os.getenv("PROM_STEP", "15s")
APP_POD_REGEX = os.getenv(
	"S2_APP_POD_REGEX",
	"gw-nginx|s0|s1|sdb1|api-demo|auth-service|api-service|data-service|postgres|ingress-kong|nginx-ingress-microk8s-controller",
)
APP_NAMESPACE_REGEX = os.getenv("S2_APP_NAMESPACE_REGEX", "default|realistic|mubench-real|kong|ingress")

NAME_RE = re.compile(
	r"s2_academic_base_n8_(B\d+_\d{4}-\d{2}-\d{2})_order(\d+)_([A-Z]\d)_(.+)_(normal|attack)_(\d+)vus\.json$"
)


@dataclass
class RunRow:
	file: str
	block_day: str
	order: int
	control: str
	variant: str
	security_mode: str
	vus: int
	run_start: str
	run_end: str
	run_duration_s: float
	iterations: int
	http_reqs: int
	http_429_count: int
	http_503_count: int
	http_rejected_count: int
	reject_rate_pct: float
	accept_rate_pct: float
	checks_total: int
	checks_ok: int
	checks_rate_pct: float
	error_rate_pct: float
	avg_http_ms: float
	p95_http_ms: float
	login_checks_rate_pct: float
	profile_checks_rate_pct: float
	users_checks_rate_pct: float
	login_p95_ms: float
	profile_p95_ms: float
	users_p95_ms: float
	cpu_mcores: float
	mem_mib: float


def parse_k6_time(ts: str) -> datetime:
	# k6 may emit nanosecond precision (9 digits), while datetime supports microseconds (6).
	if "." in ts:
		head, rest = ts.split(".", 1)
		tz_pos = max(rest.rfind("+"), rest.rfind("-"))
		if tz_pos > 0:
			frac = rest[:tz_pos]
			tz = rest[tz_pos:]
		else:
			frac = rest
			tz = ""
		frac = (frac[:6]).ljust(6, "0")
		ts = f"{head}.{frac}{tz}"
	return datetime.fromisoformat(ts)


def percentile(values: List[float], q: float) -> float:
	if not values:
		return 0.0
	return float(np.percentile(np.array(values), q))


def parse_points(path: Path) -> List[dict]:
	points: List[dict] = []
	with path.open("r", encoding="utf-8", errors="ignore") as fh:
		for line in fh:
			line = line.strip()
			if not line:
				continue
			try:
				obj = json.loads(line)
			except Exception:
				continue
			if obj.get("type") == "Point":
				points.append(obj)
	return points


def summarize_checks(points: Iterable[dict]) -> Dict[str, Tuple[int, int]]:
	# returns {check_name: (ok, total)}
	by_check: Dict[str, List[int]] = defaultdict(lambda: [0, 0])
	for p in points:
		if p.get("metric") != "checks":
			continue
		tags = p.get("data", {}).get("tags", {})
		check = tags.get("check", "unknown")
		value = int(float(p.get("data", {}).get("value", 0)))
		by_check[check][1] += 1
		if value == 1:
			by_check[check][0] += 1
	return {k: (v[0], v[1]) for k, v in by_check.items()}


def sum_metric(points: Iterable[dict], metric: str) -> int:
	total = 0.0
	for p in points:
		if p.get("metric") == metric:
			total += float(p.get("data", {}).get("value", 0) or 0)
	return int(round(total))


def sum_http_reqs_by_status(points: Iterable[dict], status_predicate) -> int:
	total = 0.0
	for p in points:
		if p.get("metric") != "http_reqs":
			continue
		status = str(p.get("data", {}).get("tags", {}).get("status", ""))
		if status_predicate(status):
			total += float(p.get("data", {}).get("value", 0) or 0)
	return int(round(total))


def extract_metric_values(points: Iterable[dict], metric: str) -> List[float]:
	vals: List[float] = []
	for p in points:
		if p.get("metric") == metric:
			vals.append(float(p.get("data", {}).get("value", 0) or 0))
	return vals


def endpoint_durations(points: Iterable[dict]) -> Dict[str, List[float]]:
	data: Dict[str, List[float]] = {"login": [], "profile": [], "users": []}
	for p in points:
		if p.get("metric") != "http_req_duration":
			continue
		tags = p.get("data", {}).get("tags", {})
		name = str(tags.get("name", "")).lower()
		value = float(p.get("data", {}).get("value", 0) or 0)
		if "/login" in name:
			data["login"].append(value)
		elif "/profile" in name:
			data["profile"].append(value)
		elif "/users" in name:
			data["users"].append(value)
	return data


def prom_query_range(query: str, start_ts: int, end_ts: int, step: str) -> List[float]:
	params = urllib.parse.urlencode({
		"query": query,
		"start": str(start_ts),
		"end": str(end_ts),
		"step": step,
	})
	url = f"{PROM_URL}/api/v1/query_range?{params}"
	try:
		with urllib.request.urlopen(url, timeout=15) as resp:
			payload = json.loads(resp.read().decode("utf-8", errors="ignore"))
	except Exception:
		return []
	if payload.get("status") != "success":
		return []
	results = payload.get("data", {}).get("result", [])
	vals: List[float] = []
	for series in results:
		for _, v in series.get("values", []):
			try:
				vals.append(float(v))
			except Exception:
				continue
	return vals


def fetch_run_resource_metrics(run_start: datetime, run_end: datetime) -> Tuple[float, float]:
	start_ts = int(run_start.timestamp())
	end_ts = int(run_end.timestamp())
	if end_ts <= start_ts:
		end_ts = start_ts + 1

	# CPU in millicores (average over run window)
	cpu_query = (
		f'sum(rate(container_cpu_usage_seconds_total{{namespace=~"{APP_NAMESPACE_REGEX}",'
		f'pod=~".*({APP_POD_REGEX}).*",container!="",image!=""}}[1m]))'
	)
	# Memory in MiB (average over run window)
	mem_query = (
		f'sum(container_memory_usage_bytes{{namespace=~"{APP_NAMESPACE_REGEX}",'
		f'pod=~".*({APP_POD_REGEX}).*",container!="",image!=""}})'
	)

	cpu_vals = prom_query_range(cpu_query, start_ts, end_ts, PROM_STEP)
	mem_vals = prom_query_range(mem_query, start_ts, end_ts, PROM_STEP)
	cpu_vals = [x for x in cpu_vals if np.isfinite(x)]
	mem_vals = [x for x in mem_vals if np.isfinite(x)]

	cpu_mcores = float(np.mean(cpu_vals) * 1000.0) if cpu_vals else np.nan
	mem_mib = float(np.mean(mem_vals) / (1024.0 * 1024.0)) if mem_vals else np.nan
	return round(cpu_mcores, 3), round(mem_mib, 3)


def build_run_row(path: Path) -> RunRow:
	m = NAME_RE.match(path.name)
	if not m:
		raise ValueError(f"Unexpected file naming: {path.name}")
	block_day, order, control, variant, security_mode, vus = m.groups()

	points = parse_points(path)
	if not points:
		raise ValueError(f"No points found in: {path.name}")

	times = [parse_k6_time(p.get("data", {}).get("time")) for p in points if p.get("data", {}).get("time")]
	run_start = min(times)
	run_end = max(times)
	run_duration_s = (run_end - run_start).total_seconds()

	dur_vals = extract_metric_values(points, "http_req_duration")
	fail_vals = extract_metric_values(points, "http_req_failed")

	checks = summarize_checks(points)
	checks_total = sum(v[1] for v in checks.values())
	checks_ok = sum(v[0] for v in checks.values())
	checks_rate_pct = 100.0 * checks_ok / checks_total if checks_total else 0.0

	endpoint_checks = {
		"login": ["login status 200", "login has token"],
		"profile": ["profile status 200", "profile has user"],
		"users": ["users status 200", "users has count"],
	}
	endpoint_rates: Dict[str, float] = {}
	for endpoint, names in endpoint_checks.items():
		ok = 0
		total = 0
		for n in names:
			c_ok, c_total = checks.get(n, (0, 0))
			ok += c_ok
			total += c_total
		endpoint_rates[endpoint] = (100.0 * ok / total) if total else 0.0

	by_ep = endpoint_durations(points)
	cpu_mcores, mem_mib = fetch_run_resource_metrics(run_start, run_end)
	http_reqs_total = sum_metric(points, "http_reqs")
	http_429_count = sum_http_reqs_by_status(points, lambda s: s == "429")
	http_503_count = sum_http_reqs_by_status(points, lambda s: s == "503")
	http_rejected_count = http_429_count + http_503_count
	http_2xx_count = sum_http_reqs_by_status(points, lambda s: s.startswith("2"))
	reject_rate_pct = (100.0 * http_rejected_count / http_reqs_total) if http_reqs_total else 0.0
	accept_rate_pct = (100.0 * http_2xx_count / http_reqs_total) if http_reqs_total else 0.0

	return RunRow(
		file=path.name,
		block_day=block_day,
		order=int(order),
		control=control,
		variant=variant,
		security_mode=security_mode,
		vus=int(vus),
		run_start=run_start.isoformat(),
		run_end=run_end.isoformat(),
		run_duration_s=round(run_duration_s, 3),
		iterations=sum_metric(points, "iterations"),
		http_reqs=http_reqs_total,
		http_429_count=http_429_count,
		http_503_count=http_503_count,
		http_rejected_count=http_rejected_count,
		reject_rate_pct=round(reject_rate_pct, 3),
		accept_rate_pct=round(accept_rate_pct, 3),
		checks_total=checks_total,
		checks_ok=checks_ok,
		checks_rate_pct=round(checks_rate_pct, 3),
		error_rate_pct=round(100.0 * (sum(fail_vals) / len(fail_vals)) if fail_vals else 0.0, 3),
		avg_http_ms=round(float(np.mean(dur_vals)) if dur_vals else 0.0, 3),
		p95_http_ms=round(percentile(dur_vals, 95), 3),
		login_checks_rate_pct=round(endpoint_rates["login"], 3),
		profile_checks_rate_pct=round(endpoint_rates["profile"], 3),
		users_checks_rate_pct=round(endpoint_rates["users"], 3),
		login_p95_ms=round(percentile(by_ep["login"], 95), 3),
		profile_p95_ms=round(percentile(by_ep["profile"], 95), 3),
		users_p95_ms=round(percentile(by_ep["users"], 95), 3),
		cpu_mcores=cpu_mcores,
		mem_mib=mem_mib,
	)


def save_markdown_table(df: pd.DataFrame, path: Path, title: str) -> None:
	def esc(v: object) -> str:
		return str(v).replace("|", "\\|")

	with path.open("w", encoding="utf-8") as fh:
		fh.write(f"# {title}\n\n")
		cols = list(df.columns)
		fh.write("| " + " | ".join(cols) + " |\n")
		fh.write("| " + " | ".join(["---"] * len(cols)) + " |\n")
		for _, row in df.iterrows():
			fh.write("| " + " | ".join(esc(row[c]) for c in cols) + " |\n")
		fh.write("\n")


def main() -> int:
	OUT_DIR.mkdir(parents=True, exist_ok=True)
	PLOTS_DIR.mkdir(parents=True, exist_ok=True)

	files = sorted(RESULTS_DIR.glob(INPUT_GLOB))
	if not files:
		raise SystemExit(f"No files with pattern {INPUT_GLOB} in {RESULTS_DIR}")

	run_rows = [build_run_row(p) for p in files]
	run_df = pd.DataFrame([asdict(r) for r in run_rows]).sort_values(["block_day", "order"])
	run_df["rps_observed"] = run_df["http_reqs"] / run_df["run_duration_s"].replace(0, np.nan)
	run_df["rps_observed"] = run_df["rps_observed"].fillna(0).round(4)
	run_df.to_csv(OUT_DIR / "s2_runs_detailed.csv", index=False)

	exp_group_cols = ["control", "variant", "vus", "security_mode"]
	exp_df = (
		run_df.groupby(exp_group_cols, as_index=False)
		.agg(
			runs=("file", "count"),
			duration_real_mean_s=("run_duration_s", "mean"),
			duration_real_std_s=("run_duration_s", "std"),
			http_429_mean=("http_429_count", "mean"),
			http_503_mean=("http_503_count", "mean"),
			http_rejected_mean=("http_rejected_count", "mean"),
			reject_rate_mean_pct=("reject_rate_pct", "mean"),
			accept_rate_mean_pct=("accept_rate_pct", "mean"),
			p95_http_mean_ms=("p95_http_ms", "mean"),
			avg_http_mean_ms=("avg_http_ms", "mean"),
			error_rate_mean_pct=("error_rate_pct", "mean"),
			checks_rate_mean_pct=("checks_rate_pct", "mean"),
			rps_observed_mean=("rps_observed", "mean"),
			cpu_mcores_mean=("cpu_mcores", "mean"),
			mem_mib_mean=("mem_mib", "mean"),
			login_success_mean_pct=("login_checks_rate_pct", "mean"),
			profile_success_mean_pct=("profile_checks_rate_pct", "mean"),
			users_success_mean_pct=("users_checks_rate_pct", "mean"),
			login_p95_mean_ms=("login_p95_ms", "mean"),
			profile_p95_mean_ms=("profile_p95_ms", "mean"),
			users_p95_mean_ms=("users_p95_ms", "mean"),
		)
		.sort_values(["control", "variant", "vus"])
	)

	# Nominal orchestrator time: warmup(30) + run(60) + cooldown(15) = 105s
	exp_df["duration_nominal_slot_s"] = 105
	exp_df["duration_real_mean_s"] = exp_df["duration_real_mean_s"].round(3)
	exp_df["duration_real_std_s"] = exp_df["duration_real_std_s"].fillna(0).round(3)
	exp_df["rps_observed_mean"] = exp_df["rps_observed_mean"].round(4)
	exp_df["cpu_mcores_mean"] = exp_df["cpu_mcores_mean"].round(3)
	exp_df["mem_mib_mean"] = exp_df["mem_mib_mean"].round(3)
	exp_df.to_csv(OUT_DIR / "s2_time_by_experiment.csv", index=False)

	best_overall = exp_df.sort_values(["checks_rate_mean_pct", "p95_http_mean_ms"], ascending=[False, True]).head(10)
	best_overall.to_csv(OUT_DIR / "s2_best_overall_response.csv", index=False)

	# Endpoint-specific winners: require near-perfect endpoint success
	winners = []
	endpoint_specs = [
		("login", "login_success_mean_pct", "login_p95_mean_ms"),
		("profile", "profile_success_mean_pct", "profile_p95_mean_ms"),
		("users", "users_success_mean_pct", "users_p95_mean_ms"),
	]
	for endpoint, success_col, latency_col in endpoint_specs:
		candidates = exp_df[exp_df[success_col] >= 99.0].sort_values([latency_col, "error_rate_mean_pct"])
		if not candidates.empty:
			row = candidates.iloc[0].to_dict()
			row["endpoint"] = endpoint
			winners.append(row)
	winners_df = pd.DataFrame(winners)
	winners_df.to_csv(OUT_DIR / "s2_endpoint_winners.csv", index=False)

	# Hypotheses ANOVA (H1-H4 + block effect)
	# H1: control main effect
	# H2: variant main effect
	# H3: vus main effect
	# H4: control x vus interaction
	anova_input = run_df[[
		"p95_http_ms", "avg_http_ms", "error_rate_pct", "checks_rate_pct", "rps_observed", "run_duration_s", "cpu_mcores", "mem_mib",
		"reject_rate_pct",
		"control", "variant", "vus", "block_day"
	]].copy()
	anova_input.rename(columns={
		"p95_http_ms": "p95_ms",
		"avg_http_ms": "avg_ms",
		"error_rate_pct": "err_pct",
		"checks_rate_pct": "checks_pct",
		"rps_observed": "rps",
		"run_duration_s": "duration_s",
		"cpu_mcores": "cpu_mcores",
		"mem_mib": "mem_mib",
		"reject_rate_pct": "reject_pct",
	}, inplace=True)
	anova_input.to_csv(OUT_DIR / "s2_anova_input_matrix.csv", index=False)

	metrics = ["p95_ms", "avg_ms", "err_pct", "checks_pct", "rps", "duration_s", "cpu_mcores", "mem_mib", "reject_pct"]
	anova_rows = []
	model_formula_tpl = "{metric} ~ C(control) + C(variant) + C(vus) + C(control):C(vus) + C(block_day)"
	for metric in metrics:
		metric_df = anova_input[[metric, "control", "variant", "vus", "block_day"]].replace([np.inf, -np.inf], np.nan).dropna()
		if metric_df.empty or metric_df[metric].nunique() < 2:
			anova_rows.append(
				{
					"metric": metric,
					"term": "SKIPPED_NO_DATA",
					"sum_sq": np.nan,
					"df": np.nan,
					"F": np.nan,
					"PR(>F)": np.nan,
				}
			)
			continue
		model = smf.ols(model_formula_tpl.format(metric=metric), data=metric_df).fit()
		table = anova_lm(model, typ=2)
		for term, row in table.iterrows():
			anova_rows.append(
				{
					"metric": metric,
					"term": term,
					"sum_sq": float(row.get("sum_sq", np.nan)),
					"df": float(row.get("df", np.nan)),
					"F": float(row.get("F", np.nan)) if not pd.isna(row.get("F", np.nan)) else np.nan,
					"PR(>F)": float(row.get("PR(>F)", np.nan)) if not pd.isna(row.get("PR(>F)", np.nan)) else np.nan,
				}
			)
	anova_df = pd.DataFrame(anova_rows)
	anova_df.to_csv(OUT_DIR / "s2_anova_matrix_hypotheses.csv", index=False)

	# Grafana long format
	grafana_rows = []
	for _, r in run_df.iterrows():
		ts = r["run_start"]
		exp_name = f"{r['control']}/{r['variant']}/vu{int(r['vus'])}"
		metrics_map = {
			"run_duration_s": r["run_duration_s"],
			"rps_observed": r["rps_observed"],
			"http_429_count": r["http_429_count"],
			"http_503_count": r["http_503_count"],
			"http_rejected_count": r["http_rejected_count"],
			"reject_rate_pct": r["reject_rate_pct"],
			"accept_rate_pct": r["accept_rate_pct"],
			"p95_http_ms": r["p95_http_ms"],
			"avg_http_ms": r["avg_http_ms"],
			"error_rate_pct": r["error_rate_pct"],
			"checks_rate_pct": r["checks_rate_pct"],
			"cpu_mcores": r["cpu_mcores"],
			"mem_mib": r["mem_mib"],
			"users_success_pct": r["users_checks_rate_pct"],
			"profile_success_pct": r["profile_checks_rate_pct"],
			"login_success_pct": r["login_checks_rate_pct"],
		}
		for m_name, m_val in metrics_map.items():
			grafana_rows.append(
				{
					"time": ts,
					"experiment": exp_name,
					"control": r["control"],
					"variant": r["variant"],
					"vus": int(r["vus"]),
					"block_day": r["block_day"],
					"metric": m_name,
					"value": float(m_val),
				}
			)
	grafana_df = pd.DataFrame(grafana_rows)
	grafana_df.to_csv(OUT_DIR / "s2_grafana_long.csv", index=False)

	# Plots
	plt.rcParams.update({"figure.dpi": 160, "savefig.dpi": 180, "font.size": 10})

	# 1) Real duration by experiment
	p1 = exp_df.copy()
	p1["label"] = p1["control"] + "/" + p1["variant"] + "/vu" + p1["vus"].astype(str)
	p1 = p1.sort_values("duration_real_mean_s")
	fig, ax = plt.subplots(figsize=(11, 6))
	ax.barh(p1["label"], p1["duration_real_mean_s"], xerr=p1["duration_real_std_s"], alpha=0.8)
	ax.set_title("Duracion real por experimento (media +/- std)")
	ax.set_xlabel("segundos")
	ax.grid(axis="x", alpha=0.3)
	fig.tight_layout()
	fig.savefig(PLOTS_DIR / "time_by_experiment.png")
	plt.close(fig)

	# 2) Success vs p95 scatter
	fig, ax = plt.subplots(figsize=(8.5, 6))
	ax.scatter(exp_df["checks_rate_mean_pct"], exp_df["p95_http_mean_ms"], c=exp_df["vus"], cmap="viridis", alpha=0.8)
	ax.set_title("Exito de checks vs latencia p95 (color=VUs)")
	ax.set_xlabel("checks exito (%)")
	ax.set_ylabel("p95 HTTP (ms)")
	ax.grid(alpha=0.3)
	fig.tight_layout()
	fig.savefig(PLOTS_DIR / "success_vs_p95.png")
	plt.close(fig)

	# 3) Endpoint winners by latency and success
	fig, axes = plt.subplots(1, 2, figsize=(12, 4.8))
	ep_plot = winners_df.copy()
	if not ep_plot.empty:
		axes[0].bar(ep_plot["endpoint"], ep_plot[["login_p95_mean_ms", "profile_p95_mean_ms", "users_p95_mean_ms"]].to_numpy().diagonal())
		axes[0].set_title("Ganador por endpoint: p95(ms)")
		axes[0].set_ylabel("ms")
		axes[0].grid(axis="y", alpha=0.3)

		axes[1].bar(ep_plot["endpoint"], ep_plot[["login_success_mean_pct", "profile_success_mean_pct", "users_success_mean_pct"]].to_numpy().diagonal())
		axes[1].set_title("Ganador por endpoint: exito(%)")
		axes[1].set_ylabel("%")
		axes[1].set_ylim(0, 101)
		axes[1].grid(axis="y", alpha=0.3)
	else:
		axes[0].text(0.5, 0.5, "Sin ganadores (filtro >=99% exito)", ha="center", va="center")
		axes[1].text(0.5, 0.5, "Sin datos", ha="center", va="center")
	fig.tight_layout()
	fig.savefig(PLOTS_DIR / "endpoint_winners.png")
	plt.close(fig)

	# 4) Heatmap p95 by control/variant/vus
	heat = exp_df.pivot_table(index=["control", "variant"], columns="vus", values="p95_http_mean_ms")
	fig, ax = plt.subplots(figsize=(8.5, 5.5))
	im = ax.imshow(heat.values, aspect="auto")
	ax.set_title("Heatmap p95 HTTP (ms)")
	ax.set_xlabel("VUs")
	ax.set_ylabel("control/variant")
	ax.set_xticks(np.arange(len(heat.columns)))
	ax.set_xticklabels([str(x) for x in heat.columns])
	ax.set_yticks(np.arange(len(heat.index)))
	ax.set_yticklabels([f"{i[0]}/{i[1]}" for i in heat.index])
	cbar = fig.colorbar(im, ax=ax)
	cbar.set_label("ms")
	fig.tight_layout()
	fig.savefig(PLOTS_DIR / "heatmap_p95.png")
	plt.close(fig)

	# 5) Throughput (RPS) by experiment
	p_rps = exp_df.copy()
	p_rps["label"] = p_rps["control"] + "/" + p_rps["variant"] + "/vu" + p_rps["vus"].astype(str)
	p_rps = p_rps.sort_values("rps_observed_mean", ascending=True)
	fig, ax = plt.subplots(figsize=(11, 6))
	ax.barh(p_rps["label"], p_rps["rps_observed_mean"], alpha=0.85)
	ax.set_title("Throughput observado (RPS) por experimento")
	ax.set_xlabel("requests por segundo")
	ax.grid(axis="x", alpha=0.3)
	fig.tight_layout()
	fig.savefig(PLOTS_DIR / "throughput_by_experiment.png")
	plt.close(fig)

	# Markdown summaries
	save_markdown_table(
		exp_df[[
			"control", "variant", "vus", "runs", "duration_real_mean_s", "duration_nominal_slot_s",
			"rps_observed_mean", "avg_http_mean_ms", "p95_http_mean_ms", "error_rate_mean_pct", "checks_rate_mean_pct", "cpu_mcores_mean", "mem_mib_mean",
		]].sort_values(["control", "variant", "vus"]),
		OUT_DIR / "table_time_and_quality.md",
		"Tiempo Por Experimento y Calidad"
	)

	save_markdown_table(
		exp_df[[
			"control", "variant", "vus", "runs",
			"duration_real_mean_s", "rps_observed_mean", "avg_http_mean_ms", "p95_http_mean_ms",
			"http_429_mean", "http_503_mean", "http_rejected_mean", "reject_rate_mean_pct", "accept_rate_mean_pct",
			"error_rate_mean_pct", "checks_rate_mean_pct", "cpu_mcores_mean", "mem_mib_mean",
		]].sort_values(["control", "variant", "vus"]),
		OUT_DIR / "table_6_metrics_by_experiment.md",
		"Ocho Metricas Por Experimento"
	)

	save_markdown_table(
		best_overall[[
			"control", "variant", "vus", "checks_rate_mean_pct", "p95_http_mean_ms",
			"error_rate_mean_pct", "users_success_mean_pct",
		]],
		OUT_DIR / "table_top10_response.md",
		"Top 10 Mejor Respuesta Global"
	)

	if not winners_df.empty:
		keep_cols = [
			"endpoint", "control", "variant", "vus",
			"duration_real_mean_s", "rps_observed_mean", "avg_http_mean_ms", "p95_http_mean_ms", "error_rate_mean_pct", "checks_rate_mean_pct", "cpu_mcores_mean", "mem_mib_mean",
			"login_success_mean_pct", "profile_success_mean_pct", "users_success_mean_pct",
			"login_p95_mean_ms", "profile_p95_mean_ms", "users_p95_mean_ms",
		]
		save_markdown_table(winners_df[keep_cols], OUT_DIR / "table_endpoint_winners.md", "Ganador Por Endpoint")

	# LaTeX report
	total_runs = len(run_df)
	total_experiments = len(exp_df)
	overall_mean_duration = run_df["run_duration_s"].mean()
	overall_mean_p95 = run_df["p95_http_ms"].mean()
	overall_mean_checks = run_df["checks_rate_pct"].mean()
	overall_mean_err = run_df["error_rate_pct"].mean()
	overall_mean_cpu = run_df["cpu_mcores"].mean()
	overall_mean_mem = run_df["mem_mib"].mean()

	hypothesis_rows = []
	h_map = {
		"C(control)": "H1: Efecto principal de control",
		"C(variant)": "H2: Efecto principal de variante",
		"C(vus)": "H3: Efecto principal de VUs",
		"C(control):C(vus)": "H4: Interaccion control x VUs",
		"C(block_day)": "Bloque: dia",
	}
	h_df = anova_df[anova_df["metric"] == "p95_ms"].copy()
	for term, label in h_map.items():
		rr = h_df[h_df["term"] == term]
		if rr.empty:
			continue
		hypothesis_rows.append((label, float(rr.iloc[0]["F"]), float(rr.iloc[0]["PR(>F)"])))

	latex_path = OUT_DIR / "s2_experiment_summary.tex"
	with latex_path.open("w", encoding="utf-8") as fh:
		fh.write("\\documentclass[11pt]{article}\n")
		fh.write("\\usepackage[utf8]{inputenc}\n")
		fh.write("\\usepackage{booktabs}\n")
		fh.write("\\usepackage{geometry}\n")
		fh.write("\\geometry{margin=1in}\n")
		fh.write("\\title{Resumen S2: Tiempo, Calidad de Respuesta y ANOVA}\n")
		fh.write("\\date{}\n")
		fh.write("\\begin{document}\n")
		fh.write("\\maketitle\n")
		fh.write("\\section*{Resumen Ejecutivo}\n")
		fh.write(f"Corridas analizadas: {total_runs}. Experimentos unicos: {total_experiments}.\\\\\n")
		fh.write(f"Duracion real media por corrida: {overall_mean_duration:.2f}s.\\\\\n")
		fh.write(f"Latencia p95 media global: {overall_mean_p95:.2f}ms.\\\\\n")
		fh.write(f"Exito medio de checks: {overall_mean_checks:.2f}\\%.\\\\\n")
		fh.write(f"Error medio HTTP: {overall_mean_err:.2f}\\%.\n")
		fh.write(f"CPU media (mcores): {overall_mean_cpu:.2f}.\\\\\n")
		fh.write(f"Memoria media (MiB): {overall_mean_mem:.2f}.\n")

		fh.write("\\section*{Hipotesis y Matriz ANOVA (metrica p95)}\n")
		fh.write("\\begin{tabular}{lrr}\n")
		fh.write("\\toprule\n")
		fh.write("Hipotesis/Termino & F & p-value \\\\ \n")
		fh.write("\\midrule\n")
		for label, f_val, p_val in hypothesis_rows:
			fh.write(f"{label} & {f_val:.3f} & {p_val:.6g} \\\\ \n")
		fh.write("\\bottomrule\n")
		fh.write("\\end{tabular}\n")

		fh.write("\\section*{Interpretacion breve}\n")
		fh.write("Se evaluaron H1-H4 con bloqueo por dia usando OLS y ANOVA tipo II. ")
		fh.write("Los resultados detallados para todas las metricas estan en el CSV de matriz ANOVA.\n")
		fh.write("\\end{document}\n")

	# README for output bundle
	with (OUT_DIR / "README.md").open("w", encoding="utf-8") as fh:
		fh.write("# S2 Final Analysis Bundle\n\n")
		fh.write("## Contenido\n")
		fh.write("- `s2_runs_detailed.csv`: corrida por corrida con duracion real y metricas.\n")
		fh.write("- `s2_time_by_experiment.csv`: tiempo y calidad por experimento (control/variante/vus).\n")
		fh.write("- `table_6_metrics_by_experiment.md`: tabla consolidada de 8 metricas por experimento (incluye CPU y memoria).\n")
		fh.write("- `s2_best_overall_response.csv`: ranking general de respuesta exitosa.\n")
		fh.write("- `s2_endpoint_winners.csv`: mejor experimento por endpoint (login/profile/users).\n")
		fh.write("- `s2_anova_input_matrix.csv`: matriz de entrada para ANOVA.\n")
		fh.write("- `s2_anova_matrix_hypotheses.csv`: resultados ANOVA para H1-H4 y bloque.\n")
		fh.write("- `s2_grafana_long.csv`: formato largo para paneles Grafana.\n")
		fh.write("- `table_time_and_quality.md`, `table_top10_response.md`, `table_endpoint_winners.md`: tablas resumidas.\n")
		fh.write("- `s2_experiment_summary.tex`: resumen listo para compilar en LaTeX.\n")
		fh.write("- `plots/*.png`: graficas de duracion, exito-vs-latencia, ganadores por endpoint, heatmap p95 y throughput.\n\n")
		fh.write("## Grafana\n")
		fh.write("Carga `s2_grafana_long.csv` con un datasource CSV/Infinity y usa:\n")
		fh.write("- Time field: `time`\n")
		fh.write("- Series: `metric` (o `experiment`)\n")
		fh.write("- Value: `value`\n")

	print(f"Generated analysis in: {OUT_DIR}")
	return 0


if __name__ == "__main__":
	raise SystemExit(main())
