#!/usr/bin/env python3
"""
ANOVA / Kruskal-Wallis para hipotesis de overhead por control (C1..C4).
Lee results_all.csv del grid completo y emite:
  - tabla LaTeX (anova_results.tex)
  - CSV con todos los p-valores (anova_results.csv)
  - assumptions CSV (assumptions.csv)
"""
import sys
from pathlib import Path
import numpy as np
import pandas as pd
from scipy import stats

CSV = Path(sys.argv[1]) if len(sys.argv) > 1 else Path(
    "/home/dwan13/muBench/Testing/results/auto_runs/crud_grid_20260524_183821/results_all.csv"
)
OUT_DIR = CSV.parent
ALPHA = 0.05

METRICS = [
    ("avg_ms",       "Latencia media (ms)"),
    ("p95_ms",       "Latencia p95 (ms)"),
    ("rps",          "Throughput (req/s)"),
    ("err_pct",      "Tasa de error (\\%)"),
    ("cpu_total_m",  "CPU (mCPU)"),
    ("mem_total_Mi", "Memoria (MiB)"),
]

CONTROLS = {
    "C1": "API Gateway",
    "C2": "mTLS",
    "C3": "Network Policies",
    "C4": "Rate Limiting",
}

df = pd.read_csv(CSV)
df = df.dropna(subset=[m for m, _ in METRICS])
print(f"Reps cargadas: {len(df)}")
print(f"Controles: {sorted(df['control'].unique())}")
for c in sorted(df['control'].unique()):
    print(f"  {c}: variantes={sorted(df[df.control==c]['variant'].unique())}  n_total={(df.control==c).sum()}")

rows = []          # filas resultado por (control, metric)
asum_rows = []     # supuestos

for ctrl, ctrl_name in CONTROLS.items():
    sub = df[df.control == ctrl]
    if sub.empty:
        continue
    variants = sorted(sub.variant.unique())
    for mcol, mname in METRICS:
        groups = [sub[sub.variant == v][mcol].dropna().values for v in variants]
        ns = [len(g) for g in groups]
        means = [float(np.mean(g)) if len(g) else np.nan for g in groups]
        stds  = [float(np.std(g, ddof=1)) if len(g) > 1 else np.nan for g in groups]

        # --- supuestos ---
        # Shapiro por grupo
        shapiro_ps = []
        for g in groups:
            if len(g) >= 3 and np.var(g) > 0:
                try:
                    shapiro_ps.append(stats.shapiro(g).pvalue)
                except Exception:
                    shapiro_ps.append(np.nan)
            else:
                shapiro_ps.append(np.nan)
        normal = all((p is not None and not np.isnan(p) and p > ALPHA) for p in shapiro_ps)
        # Levene
        try:
            lev_p = stats.levene(*groups, center='median').pvalue if all(len(g) >= 2 for g in groups) else np.nan
        except Exception:
            lev_p = np.nan
        homo = (not np.isnan(lev_p)) and lev_p > ALPHA

        # --- elegir test ---
        if normal and homo:
            test_name = "ANOVA"
            try:
                stat, pval = stats.f_oneway(*groups)
            except Exception:
                stat, pval = (np.nan, np.nan)
        else:
            test_name = "Kruskal-Wallis"
            try:
                stat, pval = stats.kruskal(*groups)
            except Exception:
                stat, pval = (np.nan, np.nan)

        # epsilon-squared (effect size) para KW;  eta^2 para ANOVA
        if test_name == "ANOVA":
            # eta^2 = SSB / SST
            allv = np.concatenate(groups)
            grand = np.mean(allv)
            ssb = sum(len(g) * (np.mean(g) - grand) ** 2 for g in groups)
            sst = np.sum((allv - grand) ** 2)
            effect = ssb / sst if sst > 0 else np.nan
        else:
            n = sum(ns)
            effect = (stat - len(groups) + 1) / (n - len(groups)) if n > len(groups) else np.nan

        reject = (not np.isnan(pval)) and pval < ALPHA

        rows.append({
            "control": ctrl, "factor": ctrl_name, "metric": mcol, "metric_label": mname,
            "test": test_name, "statistic": stat, "p_value": pval,
            "effect_size": effect, "reject_H0": reject,
            "n_per_group": "/".join(str(x) for x in ns),
        })
        asum_rows.append({
            "control": ctrl, "metric": mcol,
            "shapiro_p_min": float(np.nanmin(shapiro_ps)) if shapiro_ps else np.nan,
            "normality_ok": normal,
            "levene_p": lev_p, "homoscedasticity_ok": homo,
            "means": "/".join(f"{m:.3g}" for m in means),
            "stds":  "/".join(f"{s:.3g}" for s in stds),
        })

res = pd.DataFrame(rows)
asu = pd.DataFrame(asum_rows)

out_csv = OUT_DIR / "anova_results.csv"
out_asu = OUT_DIR / "assumptions.csv"
res.to_csv(out_csv, index=False)
asu.to_csv(out_asu, index=False)
print(f"\nGuardado: {out_csv}")
print(f"Guardado: {out_asu}")

# ============================================================
# Veredicto por hipotesis: H0 se rechaza si CUALQUIER metrica
# tiene p < alpha
# ============================================================
print("\n=== VEREDICTO POR HIPOTESIS ===")
veredicto = {}
for ctrl in CONTROLS:
    sub = res[res.control == ctrl]
    any_sig = bool(sub.reject_H0.any())
    sig_metrics = sub[sub.reject_H0].metric.tolist()
    veredicto[ctrl] = (any_sig, sig_metrics)
    estado = "RECHAZA H0" if any_sig else "NO RECHAZA H0"
    print(f"  {ctrl} ({CONTROLS[ctrl]}): {estado}  ({len(sig_metrics)}/6 metricas significativas: {sig_metrics})")

# ============================================================
# Construir LaTeX
# ============================================================
def fmt_p(p):
    if pd.isna(p): return "--"
    if p < 0.001:  return "<0.001"
    return f"{p:.3f}"

def fmt_eff(e):
    if pd.isna(e): return "--"
    return f"{e:.3f}"

def fmt_stat(s, test):
    if pd.isna(s): return "--"
    return f"{s:.2f}"

tex = []
tex.append(r"\begin{table}[htbp]")
tex.append(r"\centering")
tex.append(r"\caption{Resultados del an\'alisis ANOVA / Kruskal-Wallis para las hip\'otesis de overhead por control}")
tex.append(r"\label{tab:anova_overhead}")
tex.append(r"\renewcommand{\arraystretch}{1.15}")
tex.append(r"\footnotesize")
tex.append(r"\begin{tabular}{llrrrrl}")
tex.append(r"\hline")
tex.append(r"\textbf{Control} & \textbf{M\'etrica} & \textbf{Test} & \textbf{Estad.} & \textbf{p-valor} & \textbf{$\eta^2/\varepsilon^2$} & \textbf{Decisi\'on} \\")
tex.append(r"\hline")
for ctrl in CONTROLS:
    sub = res[res.control == ctrl]
    first = True
    for _, r in sub.iterrows():
        decision = r"\textbf{Rechaza $H_0$}" if r.reject_H0 else r"No rechaza"
        ctrl_cell = f"{ctrl} ({CONTROLS[ctrl]})" if first else ""
        test_short = "ANOVA" if r.test == "ANOVA" else "K-W"
        tex.append(
            f"{ctrl_cell} & {r.metric_label} & {test_short} & "
            f"{fmt_stat(r.statistic, r.test)} & {fmt_p(r.p_value)} & "
            f"{fmt_eff(r.effect_size)} & {decision} \\\\"
        )
        first = False
    tex.append(r"\hline")
tex.append(r"\end{tabular}")
tex.append(r"")
tex.append(r"\vspace{0.2cm}")
tex.append(r"{\raggedright \scriptsize \textit{Nota.} Se aplica ANOVA de una v\'ia cuando se cumplen los supuestos "
           r"de normalidad (Shapiro-Wilk, $p>0.05$ en todos los grupos) y homogeneidad de varianzas "
           r"(Levene, $p>0.05$); en caso contrario se reporta la prueba no param\'etrica de Kruskal-Wallis. "
           r"El tama\~no del efecto se reporta como $\eta^2$ (ANOVA) o $\varepsilon^2$ (Kruskal-Wallis). "
           r"Nivel de significancia $\alpha=0.05$. "
           f"N total = {len(df)} r\'eplicas (12 escenarios $\\times$ 4 niveles de VUS $\\times$ 8 r\'eplicas).\\par}}")
tex.append(r"\end{table}")

# Tabla resumen de veredicto
tex.append(r"")
tex.append(r"\begin{table}[htbp]")
tex.append(r"\centering")
tex.append(r"\caption{Veredicto sobre las hip\'otesis de overhead}")
tex.append(r"\label{tab:veredicto_hipotesis}")
tex.append(r"\renewcommand{\arraystretch}{1.3}")
tex.append(r"\begin{tabular}{p{1cm} p{3.5cm} p{2.5cm} p{6cm}}")
tex.append(r"\hline")
tex.append(r"\textbf{ID} & \textbf{Factor} & \textbf{Decisi\'on} & \textbf{M\'etricas significativas ($p<0.05$)} \\")
tex.append(r"\hline")
for ctrl, name in CONTROLS.items():
    any_sig, sig_metrics = veredicto[ctrl]
    dec = r"\textbf{Rechaza $H_0$}" if any_sig else "No rechaza"
    metric_labels = {m: lbl for m, lbl in METRICS}
    sig_str = ", ".join(metric_labels[m] for m in sig_metrics) if sig_metrics else "ninguna"
    tex.append(f"{ctrl} & {name} & {dec} & {sig_str} \\\\")
    tex.append(r"\hline")
tex.append(r"\end{tabular}")
tex.append(r"\end{table}")

tex_out = OUT_DIR / "anova_results.tex"
tex_out.write_text("\n".join(tex), encoding="utf-8")
print(f"Guardado: {tex_out}")
