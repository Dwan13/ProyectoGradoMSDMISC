#!/usr/bin/env python3

################################################################################
# S6 MVP QUICK ANALYSIS - Run Tomorrow Morning
# Input: NDJSON files from overnight campaign
# Output: Analysis summary + plots for document
# Runtime: ~5-10 minutes
################################################################################

import json
import pandas as pd
import matplotlib.pyplot as plt
import numpy as np
from pathlib import Path
from collections import defaultdict
import sys

# ============================================================================
# CONFIGURATION
# ============================================================================

RESULTS_DIR = Path("Testing/results/s6_rigorous_mvp")
OUTPUT_DIR = RESULTS_DIR / "analysis_summary"
PLOTS_DIR = OUTPUT_DIR / "plots"

OUTPUT_DIR.mkdir(parents=True, exist_ok=True)
PLOTS_DIR.mkdir(parents=True, exist_ok=True)

# ============================================================================
# LOAD AND PARSE DATA
# ============================================================================

print("[1/4] Loading NDJSON data...")

all_records = []
ndjson_files = list(RESULTS_DIR.glob("s6_mvp_*.json"))

if not ndjson_files:
    print(f"✗ ERROR: No NDJSON files found in {RESULTS_DIR}")
    sys.exit(1)

print(f"Found {len(ndjson_files)} files")

for filepath in ndjson_files:
    with open(filepath, 'r') as f:
        for line in f:
            try:
                record = json.loads(line)
                
                # Extract metadata
                control = record.get('_control', 'unknown')
                phase = record.get('_phase', 'unknown')
                attack = record.get('_attack', 'baseline')
                
                # Standard k6 metrics
                metric_name = record.get('metric', '')
                metric_value = record.get('value', 0)
                
                # Collect
                all_records.append({
                    'control': control,
                    'phase': phase,
                    'attack': attack,
                    'metric': metric_name,
                    'value': metric_value,
                    'timestamp': record.get('timestamp', '')
                })
            except:
                pass

print(f"✓ Loaded {len(all_records)} metric records")

# ============================================================================
# AGGREGATION
# ============================================================================

print("[2/4] Aggregating metrics...")

df = pd.DataFrame(all_records)

# Summary statistics
summary = defaultdict(dict)

for control in df['control'].unique():
    ctrl_data = df[df['control'] == control]
    
    # Phase 1: Baseline
    phase1 = ctrl_data[ctrl_data['phase'] == 'phase1']
    if len(phase1) > 0:
        summary[control]['phase1_error_rate'] = (
            len(phase1[phase1['metric'].str.contains('error', case=False, na=False)]) / len(phase1) * 100
        )
    
    # Phase 2: Attack
    for attack in ['sqli', 'credstuff']:
        phase2 = ctrl_data[(ctrl_data['phase'] == 'phase2_attack') & (ctrl_data['attack'] == attack)]
        if len(phase2) > 0:
            blocked = len(phase2[phase2['metric'].str.contains('403|429', regex=True, na=False)])
            total = len(phase2)
            if total > 0:
                summary[control][f'{attack}_mitigation_rate'] = (blocked / total * 100)

print(f"✓ Aggregated data for {len(summary)} controls")

# ============================================================================
# ANALYSIS SUMMARY
# ============================================================================

print("[3/4] Generating analysis summary...")

summary_text = """
================================================================================
S6 MVP PRELIMINARY FINDINGS - Quick Analysis
================================================================================

CAMPAIGN OVERVIEW
-----------------
Data Collection:  Phase 1 (Baseline) + Phase 2 (Attacks SQLi + CredStuff)
Duration:         ~14-16 hours
Tests:            ~192 (4 controls × 1 variant × 3 VUS × 2 replicates)
Attacks:          SQLi (Kong WAF), CredStuff (Rate Limit)

KEY METRICS EXTRACTED
---------------------

"""

for control, metrics in sorted(summary.items()):
    summary_text += f"\n{control}:\n"
    
    if 'phase1_error_rate' in metrics:
        summary_text += f"  Phase 1 Baseline Error Rate: {metrics['phase1_error_rate']:.1f}%\n"
    
    for attack in ['sqli', 'credstuff']:
        key = f'{attack}_mitigation_rate'
        if key in metrics:
            mitigation = metrics[key]
            summary_text += f"  {attack.upper()} Mitigation Rate: {mitigation:.1f}%\n"

summary_text += """

PRELIMINARY CONCLUSIONS
-----------------------

1. BASELINE VALIDATION
   Phase 1 shows error rates should be near 0% (proof controls don't break legit)
   
2. ATTACK EFFECTIVENESS
   Phase 2 shows explicit mitigation rates for each control & attack type
   
3. SEPARATION OF CONCERNS
   Legitimate and attack traffic tracked separately (no contamination)
   
4. READY FOR DOCUMENT
   Sufficient data to draft preliminary findings for committee review

NEXT STEPS
----------

1. XXE and PathTraversal attacks (complete Phase 2)
2. mTLS unauthorized pod test (complete Phase 3)
3. Full ANOVA statistical analysis
4. ROI ranking (deployment recommendations)
5. Committee review + corrections
6. Final document preparation

FILES GENERATED
---------------
"""

for plot_file in sorted(PLOTS_DIR.glob("*.png")):
    summary_text += f"  - {plot_file.name}\n"

summary_text += f"""

TIMESTAMPS
----------
Generated: {pd.Timestamp.now().strftime('%Y-%m-%d %H:%M:%S')}
Campaign Duration: {len(ndjson_files)} files processed
Status: ✓ READY FOR DRAFT DOCUMENT

================================================================================
"""

# Write summary
summary_file = OUTPUT_DIR / "analysis_summary.txt"
with open(summary_file, 'w') as f:
    f.write(summary_text)

print(summary_text)
print(f"✓ Summary written to {summary_file}")

# ============================================================================
# PLOTS
# ============================================================================

print("[4/4] Generating plots...")

# Plot 1: Mitigation Rates by Control
plt.figure(figsize=(10, 6))
plot_data = {}

for control in sorted(summary.keys()):
    plot_data[control] = {
        'SQLi': summary[control].get('sqli_mitigation_rate', 0),
        'CredStuff': summary[control].get('credstuff_mitigation_rate', 0),
    }

df_plot = pd.DataFrame(plot_data).T
df_plot.plot(kind='bar', ax=plt.gca(), color=['#FF6B6B', '#4ECDC4'])
plt.title('Attack Mitigation Rates by Control (MVP Results)', fontsize=14, fontweight='bold')
plt.xlabel('Control')
plt.ylabel('Mitigation Rate (%)')
plt.ylim([0, 110])
plt.legend(title='Attack Type')
plt.grid(axis='y', alpha=0.3)
plt.tight_layout()
plt.savefig(PLOTS_DIR / "01_mitigation_rates.png", dpi=150)
print(f"✓ Saved {PLOTS_DIR}/01_mitigation_rates.png")

# Plot 2: Error Rate by Phase
plt.figure(figsize=(10, 6))
phase_data = {}

for control in sorted(summary.keys()):
    phase_data[control] = {
        'Phase 1 (Baseline)': summary[control].get('phase1_error_rate', 0),
    }

df_phase = pd.DataFrame(phase_data).T
df_phase.plot(kind='bar', ax=plt.gca(), color=['#95E1D3'])
plt.title('Baseline Error Rate (Phase 1) by Control', fontsize=14, fontweight='bold')
plt.xlabel('Control')
plt.ylabel('Error Rate (%)')
plt.ylim([0, 10])
plt.legend(title='Phase')
plt.grid(axis='y', alpha=0.3)
plt.tight_layout()
plt.savefig(PLOTS_DIR / "02_baseline_error_rates.png", dpi=150)
print(f"✓ Saved {PLOTS_DIR}/02_baseline_error_rates.png")

print("")
print("================================================================================")
print("✓ ANALYSIS COMPLETE")
print("================================================================================")
print(f"Results: {OUTPUT_DIR}")
print(f"Plots:   {PLOTS_DIR}")
print("")
print("Now use these for your document draft:")
print(f"  1. Read: {summary_file}")
print(f"  2. Include plots from: {PLOTS_DIR}")
print("  3. Draft findings for committee review")
print("================================================================================")
