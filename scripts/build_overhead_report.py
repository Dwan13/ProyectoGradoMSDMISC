#!/usr/bin/env python3
"""
Genera por cada control (C1..C4):
  - Figura PDF con boxplots de las 6 metricas por variante (figures/<ctrl>_overhead.pdf)
  - Seccion LaTeX con Resultados (incluye \includegraphics), Analisis, Recomendaciones

Salida principal: resultados_overhead.tex (lista para \input{} en la tesis)
"""
import sys
from pathlib import Path
import numpy as np
import pandas as pd
import matplotlib
matplotlib.use("Agg")
import matplotlib.pyplot as plt
from scipy import stats

CSV = Path(sys.argv[1]) if len(sys.argv) > 1 else Path(
    "/home/dwan13/muBench/Testing/results/auto_runs/crud_grid_20260524_183821/results_all.csv"
)
OUT_DIR = CSV.parent
FIG_DIR = OUT_DIR / "figures"
FIG_DIR.mkdir(exist_ok=True)
ALPHA = 0.05

METRICS = [
    ("avg_ms",       "Latencia media (ms)"),
    ("p95_ms",       "Latencia p95 (ms)"),
    ("rps",          "Throughput (req/s)"),
    ("err_pct",      "Tasa de error (%)"),
    ("cpu_total_m",  "CPU (mCPU)"),
    ("mem_total_Mi", "Memoria (MiB)"),
]

CONTROLS = [
    ("C1", "API Gateway",
     "NGINX Ingress vs Istio Gateway vs Kong",
     ["baseline", "istio", "kong"]),
    ("C2", "mTLS (service mesh)",
     "Baseline (sin mTLS) vs Istio mTLS vs Linkerd mTLS",
     ["baseline", "istio-mtls", "linkerd-mtls"]),
    ("C3", "Network Policies",
     "Baseline (sin políticas) vs Basic vs Strict",
     ["baseline", "basic", "strict"]),
    ("C4", "Rate Limiting",
     "Baseline (sin límite) vs Moderate vs Strict",
     ["baseline", "moderate", "strict"]),
]

# narrativa por control: (analisis, recomendaciones)
NARRATIVE = {
    "C1": (
        "Con $n=192$ por variante se detectan diferencias estadísticamente "
        "significativas en cinco de las seis métricas, incluyendo latencia "
        "media y p95. Sin embargo, debe distinguirse \\textit{significancia "
        "estadística} de \\textit{relevancia práctica}: los tamaños de efecto "
        "en latencia son triviales ($\\varepsilon^2 \\approx 0{,}02$--$0{,}03$, "
        "por debajo del umbral de Cohen para efectos pequeños), lo que indica "
        "que aunque las distribuciones difieren, la magnitud del overhead en "
        "latencia es operativamente despreciable. Por el contrario, throughput "
        "($\\varepsilon^2 \\approx 0{,}18$, efecto grande) y memoria "
        "($\\varepsilon^2 \\approx 0{,}23$, efecto grande) sí muestran un "
        "impacto sustantivo. La decisión técnica entre NGINX, Istio o Kong se "
        "traduce principalmente en una decisión de \\textit{capacity planning} "
        "y de techo de throughput, no de SLO de latencia percibida.",
        [
            "Si el criterio dominante es minimizar huella de memoria, NGINX "
            "Ingress es la opción más liviana.",
            "Si se requieren features avanzadas (plugins, rate limiting, "
            "auth) y se acepta mayor consumo de memoria, Kong y el Istio "
            "Gateway son justificables.",
            "Dimensionar el cluster considerando el sobrecosto de memoria y "
            "el techo de throughput del gateway elegido; la diferencia en "
            "latencia es estadísticamente detectable pero operativamente "
            "despreciable ($\\varepsilon^2<0{,}05$).",
        ],
    ),
    "C2": (
        "La introducción de mTLS produce diferencias estadísticamente "
        "significativas en cinco de las seis métricas. Análogo al caso del "
        "API Gateway, el impacto sobre la latencia es estadísticamente "
        "detectable pero \\textit{prácticamente trivial} "
        "($\\varepsilon^2 \\approx 0{,}03$--$0{,}04$), confirmando que el "
        "cifrado adicional es absorbido en gran medida por los sidecars sin "
        "penalizar de forma operativa el extremo del flujo. El verdadero "
        "costo del mTLS es infraestructural: throughput sostenido "
        "($\\varepsilon^2 \\approx 0{,}15$) y, especialmente, consumo de "
        "memoria ($\\varepsilon^2 \\approx 0{,}23$, efecto grande). Istio y "
        "Linkerd difieren en huella de recursos, permitiendo elegir el mesh "
        "según las restricciones del cluster.",
        [
            "El overhead de mTLS en latencia es despreciable a efectos "
            "prácticos ($\\varepsilon^2<0{,}05$); no existe justificación de "
            "latencia para evitarlo en cargas sensibles a confidencialidad.",
            "En clusters con recursos limitados, evaluar Linkerd antes que "
            "Istio dado su perfil de memoria más liviano (cf. boxplot).",
            "Reportar el overhead de recursos (memoria sobre todo) en la "
            "planificación de capacidad del mesh, no como un costo aceptable "
            "a posteriori.",
        ],
    ),
    "C3": (
        "Las políticas de red \\textbf{no producen overhead estadísticamente "
        "detectable} en ninguna de las seis métricas ($p>0{,}57$ en todos los "
        "casos, $\\varepsilon^2$ marginalmente negativos). Este es uno de los "
        "resultados más fuertes del estudio: la implementación de políticas "
        "de red en el plano del kernel (eBPF / iptables vía Calico) opera a "
        "velocidad de línea y es transparente para la aplicación.",
        [
            "Aplicar políticas de red \\textit{strict} por defecto en todos los "
            "namespaces: el costo de performance es indistinguible de cero.",
            "No considerar las network policies como un compromiso de "
            "rendimiento; su único costo real es operacional (mantenimiento de "
            "la matriz de reglas).",
            "Usar este resultado como argumento técnico para auditorías de "
            "cumplimiento (PCI, ISO 27001): el control puede activarse sin "
            "impacto medible.",
        ],
    ),
    "C4": (
        "Como era de esperarse, el rate limiting introduce los efectos más "
        "grandes del estudio ($\\varepsilon^2 = 0{,}65$ en latencia media, "
        "$\\varepsilon^2 = 0{,}62$ en p95, $\\varepsilon^2 = 0{,}49$ en "
        "throughput). El control \\textit{strict} reduce el throughput "
        "sostenido y aumenta la latencia por efecto de la cola. La "
        "\\texttt{err\\_pct=0} observada indica que los clientes esperaron en "
        "cola sin disparar timeouts; un escenario complementario de "
        "\\textit{burst} permitiría capturar respuestas HTTP 429 explícitas.",
        [
            "Calibrar los umbrales de rate limiting con base en el percentil "
            "de tráfico legítimo observado: \\textit{moderate} ofrece "
            "protección útil con degradación tolerable, \\textit{strict} "
            "agresivamente afecta UX.",
            "Documentar y publicar el contrato de tasa a los consumidores "
            "(headers \\texttt{X-RateLimit-*}) para evitar errores ciegos en "
            "los clientes.",
            "Complementar este control con un escenario de tráfico burst que "
            "valide el bloqueo explícito (HTTP 429) como evidencia de "
            "mitigación frente a abuso intencionado.",
        ],
    ),
}


def run_test(groups):
    """Aplica Kruskal-Wallis (no parametrico, robusto)."""
    if any(len(g) < 2 for g in groups):
        return ("--", np.nan, np.nan, np.nan)
    if all(np.var(g) == 0 for g in groups):
        return ("--", np.nan, np.nan, np.nan)
    try:
        stat, p = stats.kruskal(*groups)
    except Exception:
        return ("K-W", np.nan, np.nan, np.nan)
    n = sum(len(g) for g in groups)
    eps2 = (stat - len(groups) + 1) / (n - len(groups))
    return ("K-W", float(stat), float(p), float(eps2))


def fmt_p(p):
    if pd.isna(p): return "--"
    if p < 0.001:  return r"$<0{,}001$"
    return f"${p:.3f}$".replace(".", "{,}")


def fmt_num(x, nd=3):
    if x is None or (isinstance(x, float) and np.isnan(x)): return "--"
    s = f"{x:.{nd}f}"
    return s.replace(".", "{,}")


def make_figure(df, ctrl, variants, out_path):
    sub = df[df.control == ctrl]
    n_per_variant = sub.groupby('variant').size().min()
    fig, axes = plt.subplots(2, 3, figsize=(11, 6.5))
    for ax, (mcol, mlabel) in zip(axes.flat, METRICS):
        data = [sub[sub.variant == v][mcol].dropna().values for v in variants]
        bp = ax.boxplot(data, labels=variants, patch_artist=True,
                        medianprops={"color": "black", "linewidth": 1.4})
        colors = ["#4C72B0", "#DD8452", "#55A467"]
        for patch, color in zip(bp['boxes'], colors):
            patch.set_facecolor(color)
            patch.set_alpha(0.65)
        ax.set_title(mlabel, fontsize=10)
        ax.grid(True, axis='y', alpha=0.3)
        ax.tick_params(axis='x', labelsize=8)
        ax.tick_params(axis='y', labelsize=8)
    fig.suptitle(f"{ctrl} — distribución de métricas por variante "
                 f"(n={n_per_variant} por variante)", fontsize=11)
    fig.tight_layout(rect=(0, 0, 1, 0.96))
    fig.savefig(out_path, dpi=140, bbox_inches="tight")
    # tambien PNG para preview rapido
    fig.savefig(str(out_path).replace(".pdf", ".png"), dpi=140, bbox_inches="tight")
    plt.close(fig)


def build_metric_table(df, ctrl, variants):
    """Tabla LaTeX por metrica: media+/-std por variante + K-W + p + eps^2 + decision."""
    sub = df[df.control == ctrl]
    rows = []
    rows.append(r"\begin{table}[H]")
    rows.append(r"\centering")
    rows.append(r"\footnotesize")
    rows.append(r"\caption{" + ctrl + r" --- estadísticos descriptivos y prueba de Kruskal-Wallis por métrica}")
    rows.append(r"\label{tab:" + ctrl.lower() + "_anova}")
    rows.append(r"\begin{tabular}{lrrrrrl}")
    rows.append(r"\hline")
    headers = ["Métrica"] + [f"{v} (media$\\pm$\\textit{{sd}})" for v in variants] + ["$H$", "$p$", "$\\varepsilon^2$", "Decisión"]
    rows.append(" & ".join(headers) + r" \\")
    rows.append(r"\hline")
    for mcol, mlabel in METRICS:
        groups = [sub[sub.variant == v][mcol].dropna().values for v in variants]
        cells = [mlabel]
        for g in groups:
            if len(g):
                cells.append(f"${np.mean(g):.2f}\\pm{np.std(g, ddof=1):.2f}$".replace(".", "{,}"))
            else:
                cells.append("--")
        _, stat, p, eps2 = run_test(groups)
        cells.append(fmt_num(stat, 2))
        cells.append(fmt_p(p))
        cells.append(fmt_num(eps2, 3))
        if not np.isnan(p) and p < ALPHA:
            cells.append(r"\textbf{Rechaza $H_0$}")
        elif np.isnan(p):
            cells.append("n/a")
        else:
            cells.append("No rechaza")
        rows.append(" & ".join(cells) + r" \\")
    rows.append(r"\hline")
    rows.append(r"\end{tabular}")
    rows.append(r"\end{table}")
    return "\n".join(rows)


def build_section(df, ctrl, name, factor_desc, variants):
    fig_rel = f"figures/{ctrl}_overhead.pdf"
    fig_abs = FIG_DIR / f"{ctrl}_overhead.pdf"
    make_figure(df, ctrl, variants, fig_abs)
    analisis, recs = NARRATIVE[ctrl]

    out = []
    out.append(r"\section{" + f"{ctrl} --- {name}" + "}")
    out.append(r"\label{sec:" + ctrl.lower() + "_overhead}")
    out.append(r"")
    out.append(r"\textbf{Factor evaluado:} " + factor_desc + r".")
    out.append(r"")
    out.append(r"\subsection{Resultados}")
    out.append(r"")
    out.append(r"La Figura~\ref{fig:" + ctrl.lower() + "_box} muestra la distribución de las seis métricas "
               r"de respuesta para las tres variantes del control. La Tabla~\ref{tab:" + ctrl.lower() + "_anova} "
               r"presenta los estadísticos descriptivos junto al resultado de la prueba de Kruskal-Wallis "
               r"(empleada por la violación de los supuestos de normalidad y homocedasticidad reportados "
               r"en el apéndice de supuestos).")
    out.append(r"")
    out.append(r"\begin{figure}[H]")
    out.append(r"\centering")
    out.append(r"\includegraphics[width=\textwidth]{" + fig_rel + "}")
    out.append(r"\caption{" + f"{ctrl} --- distribución por variante de las seis métricas de respuesta. "
               r"Cajas: cuartiles 1-3, mediana en negro; bigotes: 1.5\,IQR; puntos: outliers.}")
    out.append(r"\label{fig:" + ctrl.lower() + "_box}")
    out.append(r"\end{figure}")
    out.append(r"")
    out.append(build_metric_table(df, ctrl, variants))
    out.append(r"")
    out.append(r"\subsection{Análisis}")
    out.append(r"")
    out.append(analisis)
    out.append(r"")
    out.append(r"\subsection{Recomendaciones}")
    out.append(r"")
    out.append(r"\begin{itemize}")
    for r_ in recs:
        out.append(r"  \item " + r_)
    out.append(r"\end{itemize}")
    out.append(r"")
    return "\n".join(out)


# ============================================================
def main():
    df = pd.read_csv(CSV)
    print(f"Reps: {len(df)}  Controles: {sorted(df.control.unique())}")

    doc = []
    doc.append(r"% =========================================================")
    doc.append(r"% Resultados de overhead por control defensivo")
    doc.append(r"% Generado automaticamente por scripts/build_overhead_report.py")
    doc.append(r"% Fuente: " + str(CSV.relative_to(CSV.parents[3])))
    doc.append(r"% =========================================================")
    doc.append(r"% Requiere en preambulo:  \usepackage{graphicx} \usepackage{float}")
    doc.append(r"")
    doc.append(r"\chapter{Análisis de overhead de los controles defensivos}")
    doc.append(r"\label{chap:overhead_controles}")
    doc.append(r"")
    doc.append(r"Este capítulo presenta los resultados experimentales obtenidos de "
               r"la matriz completa de 384 mediciones (12 escenarios $\times$ 4 niveles "
               r"de carga $\times$ 8 réplicas). Para cada control se reportan: "
               r"(i) los resultados con gráficas comparativas por métrica, "
               r"(ii) un análisis estadístico basado en la prueba de Kruskal-Wallis "
               r"con tamaño de efecto $\varepsilon^2$, y (iii) recomendaciones prácticas "
               r"derivadas.")
    doc.append(r"")
    doc.append(r"La elección de Kruskal-Wallis sobre ANOVA paramétrico responde a la "
               r"violación de los supuestos de normalidad (Shapiro-Wilk) y "
               r"homocedasticidad (Levene) en los grupos, derivada de la mezcla de "
               r"niveles de carga en cada celda experimental. El nivel de "
               r"significancia adoptado es $\alpha = 0{,}05$.")
    doc.append(r"")
    doc.append(r"\subsection*{Nota sobre tamaño muestral y poder estadístico}")
    doc.append(r"")
    doc.append(r"El estudio se ejecutó en dos corridas independientes del grid "
               r"completo (cada una de 384 réplicas) que se consolidaron en una sola "
               r"matriz de 768 observaciones (16 réplicas por celda experimental: "
               r"3 variantes $\times$ 4 niveles de carga $\times$ 4 controles). "
               r"Al duplicar el tamaño muestral se incrementó el poder estadístico, "
               r"lo que permitió detectar como significativas algunas diferencias en "
               r"latencia en C1 y C2 que con $n=384$ no cruzaban el umbral $\alpha=0{,}05$. "
               r"Es importante destacar que \textbf{los tamaños de efecto "
               r"($\varepsilon^2$) se mantuvieron prácticamente idénticos entre ambas "
               r"corridas} (variaciones $<0{,}02$), confirmando que el fenómeno medido "
               r"es el mismo y que el cambio en el veredicto se debe exclusivamente al "
               r"poder estadístico, no a una diferencia real subyacente. Esta es la "
               r"distinción clásica entre \textit{significancia estadística} "
               r"(detectabilidad) y \textit{relevancia práctica} (magnitud del "
               r"efecto): para C1 y C2 la latencia es estadísticamente distinta entre "
               r"variantes ($p<0{,}05$) pero el efecto es trivial "
               r"($\varepsilon^2<0{,}05$, muy por debajo del umbral de Cohen para "
               r"efecto pequeño); para C4 ambas cosas coinciden ($p<10^{-20}$, "
               r"$\varepsilon^2>0{,}5$). En este capítulo se reportan ambas cantidades "
               r"para evitar conclusiones engañosas.")
    doc.append(r"")
    for ctrl, name, factor_desc, variants in CONTROLS:
        doc.append(build_section(df, ctrl, name, factor_desc, variants))
        doc.append(r"")

    # Resumen veredicto
    doc.append(r"\section{Síntesis del veredicto}")
    doc.append(r"\label{sec:veredicto_overhead}")
    doc.append(r"")
    doc.append(r"La Tabla~\ref{tab:veredicto_overhead} consolida la decisión sobre las "
               r"cuatro hipótesis del estudio.")
    doc.append(r"")
    doc.append(r"\begin{table}[H]")
    doc.append(r"\centering")
    doc.append(r"\caption{Síntesis del veredicto sobre las hipótesis de overhead}")
    doc.append(r"\label{tab:veredicto_overhead}")
    doc.append(r"\renewcommand{\arraystretch}{1.25}")
    doc.append(r"\begin{tabular}{p{0.8cm} p{3.5cm} p{2.8cm} p{6cm}}")
    doc.append(r"\hline")
    doc.append(r"\textbf{ID} & \textbf{Factor} & \textbf{Decisión} & \textbf{Métricas significativas} \\")
    doc.append(r"\hline")
    for ctrl, name, _, variants in CONTROLS:
        sub = df[df.control == ctrl]
        sig = []
        for mcol, mlabel in METRICS:
            groups = [sub[sub.variant == v][mcol].dropna().values for v in variants]
            _, _, p, _ = run_test(groups)
            if not np.isnan(p) and p < ALPHA:
                sig.append(mlabel)
        decision = r"\textbf{Rechaza $H_0$}" if sig else "No rechaza"
        doc.append(f"{ctrl} & {name} & {decision} & " + (", ".join(sig) if sig else "ninguna") + r" \\")
        doc.append(r"\hline")
    doc.append(r"\end{tabular}")
    doc.append(r"\end{table}")
    doc.append(r"")

    out_tex = OUT_DIR / "resultados_overhead.tex"
    out_tex.write_text("\n".join(doc), encoding="utf-8")
    print(f"\nGuardado: {out_tex}")
    print(f"Figuras:  {FIG_DIR}/C[1-4]_overhead.pdf")


if __name__ == "__main__":
    main()
