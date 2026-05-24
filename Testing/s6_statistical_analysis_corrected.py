#!/usr/bin/env python3
"""
S6 Statistical Analysis - CORRECTO: Mixed Linear Model

Modelo:
  metric ~ C(control) + C(variant) + C(security_mode) + C(vus) + (1 | replica)

Donde:
  - Fixed effects: control, variant, security_mode, vus
  - Random effects: intercept per replica (accounts for batch effects)
"""

import pandas as pd
import numpy as np
from pathlib import Path
from statsmodels.formula.api import mixedlm, ols
from scipy import stats
import matplotlib.pyplot as plt
import seaborn as sns

def run_mixed_model_analysis(df_path, output_dir=None):
    """
    Run mixed linear model ANOVA on S6 dataset.
    
    Uses: MixedLM with replica as random intercept
    """
    if output_dir is None:
        output_dir = Path(df_path).parent / 's6_analysis_corrected'
    
    output_dir = Path(output_dir)
    output_dir.mkdir(exist_ok=True)
    
    print("="*80)
    print("S6 STATISTICAL ANALYSIS - MIXED LINEAR MODEL")
    print("="*80)
    
    # Load data
    df = pd.read_csv(df_path)
    
    # For this analysis, use CLEAN metrics (if available)
    metrics_to_analyze = [
        'avg_ms',
        'p95_ms',
        'legitimate_error_pct',  # CLEAN metric (not contaminated err_pct)
        'attack_blocked_pct',    # CLEAN metric
        'rps',
        'cpu_mcores',
        'mem_mib'
    ]
    
    # Ensure clean metrics exist; if not, use original err_pct
    if 'legitimate_error_pct' not in df.columns:
        print("WARNING: Clean metrics not found. Using original err_pct (CONTAMINATED)")
        metrics_to_analyze = [
            'avg_ms', 'p95_ms', 'err_pct', 'rps', 'cpu_mcores', 'mem_mib'
        ]
    
    results_summary = {}
    
    for metric in metrics_to_analyze:
        print(f"\n{'='*80}")
        print(f"Metric: {metric}")
        print(f"{'='*80}")
        
        df_clean = df.dropna(subset=[metric])
        
        if len(df_clean) < 10:
            print(f"Insufficient data (n={len(df_clean)})")
            continue
        
        print(f"Sample size: {len(df_clean)}")
        print(f"Mean: {df_clean[metric].mean():.4f}")
        print(f"Std: {df_clean[metric].std():.4f}")
        print(f"Min: {df_clean[metric].min():.4f}")
        print(f"Max: {df_clean[metric].max():.4f}")
        
        # Formula: metric ~ C(control) + C(variant) + C(security_mode) + C(vus)
        # Random: (1 | replica) - intercept varies by replica
        
        try:
            # Ensure replica column exists
            if 'replica' not in df_clean.columns:
                print("ERROR: 'replica' column not found. Cannot fit random effects model.")
                print("Falling back to OLS (fixed effects only)")
                formula = f"{metric} ~ C(control) + C(variant) + C(security_mode) + C(vus)"
                model = ols(formula, data=df_clean).fit()
                
                results_summary[metric] = {
                    'model_type': 'OLS (fixed effects only)',
                    'n': len(df_clean),
                    'r_squared': model.rsquared,
                    'adj_r_squared': model.rsquared_adj,
                    'f_stat': model.fvalue,
                    'p_value': model.f_pvalue,
                }
            else:
                # MixedLM with replica as random intercept
                formula = f"{metric} ~ C(control) + C(variant) + C(security_mode) + C(vus)"
                model = mixedlm(formula, data=df_clean, groups=df_clean['replica'])
                result = model.fit(method='powell')
                
                print("\n[MIXED LINEAR MODEL RESULTS]")
                print(result.summary())
                
                results_summary[metric] = {
                    'model_type': 'MixedLM (random intercept per replica)',
                    'n': len(df_clean),
                    'log_likelihood': result.llf,
                    'aic': result.aic,
                    'bic': result.bic,
                    'fixed_effects': dict(result.fe_params),
                    'random_effects_std': result.cov_re.iloc[0, 0]**0.5,
                }
                
        except Exception as e:
            print(f"ERROR fitting model: {e}")
            results_summary[metric] = {'error': str(e)}
    
    # Save summary
    summary_df = pd.DataFrame(results_summary).T
    summary_path = output_dir / 'mixed_model_summary.csv'
    summary_df.to_csv(summary_path)
    print(f"\nSummary saved to: {summary_path}")
    
    return results_summary

def create_threat_model_clean(df_path, output_dir=None):
    """
    Create threat model matrix using CLEAN metrics.
    
    Matrix:
      Rows: Attack vectors (bad_login, unauth, tampered_bearer, malformed_bearer, xff_spoof)
      Cols: Controls (C1, C2, C3, C4)
      Values: attack_blocked_pct (how many attacks were blocked)
    """
    if output_dir is None:
        output_dir = Path(df_path).parent / 's6_analysis_corrected'
    
    output_dir = Path(output_dir)
    output_dir.mkdir(exist_ok=True)
    
    df = pd.read_csv(df_path)
    df_attack = df[df['security_mode'] == 'attack']
    
    # Assuming attack_blocked_pct is available
    if 'attack_blocked_pct' not in df_attack.columns:
        print("WARNING: attack_blocked_pct not found. Skipping threat model.")
        return
    
    # Aggregate by control (average across variants, vus, replicas)
    threat_matrix = df_attack.groupby('control').agg({
        'attack_blocked_pct': 'mean',
        'cpu_mcores': 'mean',
        'avg_ms': 'mean'
    }).round(2)
    
    threat_matrix.to_csv(output_dir / 'threat_model_clean.csv')
    print(f"Threat model saved to: {output_dir / 'threat_model_clean.csv'}")
    print("\nThreat Model (Clean Metrics):")
    print(threat_matrix)

if __name__ == '__main__':
    df_path = '/home/dwan13/muBench/Testing/results/s6_integrated_clean_metrics.csv'
    
    # Check if clean metrics exist
    if not Path(df_path).exists():
        print(f"ERROR: {df_path} not found")
        print("Run extract_clean_metrics.py first")
        exit(1)
    
    # Run analysis
    run_mixed_model_analysis(df_path)
    create_threat_model_clean(df_path)
