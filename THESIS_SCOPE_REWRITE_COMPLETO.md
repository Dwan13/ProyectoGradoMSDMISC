# THESIS SCOPE REWRITE: Methods & Limitations (HONESTO)

## CAMBIO 1: Título y Abstract

### ❌ ANTES (Overreach)
```
"Security and Performance Trade-offs in Microservices: 
A Comprehensive Validation Framework"
```

### ✅ DESPUÉS (Scope claro)
```
"Quantifying Security-Performance Trade-offs in Kubernetes Microservices: 
An Experimental Evaluation of Control Implementations Under Synthetic Adversarial Load"
```

### Abstract DESPUÉS:

We conducted a controlled experimental evaluation of security control implementations 
in Kubernetes microservices, quantifying their impact on performance metrics. We deployed 
four control types (API Gateway, mTLS, Network Policy, Rate Limiting) with three 
variants each across a synthetic microservice topology. Using k6 load testing under 
both legitimate traffic and synthetic attack vectors, we collected 384 measurements 
across 4 virtual user levels, 2 security modes, and 4 replicates. Mixed-effects linear 
regression revealed significant control-type and security-mode effects on CPU utilization 
(R²=0.868, p<1e-50). We found 30-50% CPU overhead depending on control implementation, 
while legitimate traffic remained preserved under simulated attack loads. Our findings 
demonstrate measurable resource trade-offs but are limited to single-cluster environments 
and synthetic threat models. The study informs infrastructure engineering decisions but 
should not be interpreted as real-world security validation.

---

## CAMBIO 2: Methods Section

### Experimental Design

**Scenario Coverage:**
- S2 (Baseline): 634 load test runs, legitimate traffic only
- S6 (Integrated): 384 measurements, mixed legitimate + synthetic attack probes

**Design Matrix (S6):**
```
4 Controls × 3 Variants × 4 VUS levels × 2 Security Modes × 4 Replicates = 384 rows
Controls: C1 (API Gateway), C2 (mTLS), C3 (Network Policy), C4 (Rate Limiting)
Variants: baseline, specialty-1, specialty-2 (varies by control)
VUS: 1, 5, 10, 20
Security Modes: normal (legitimate only), attack (legitimate + 5 attack vectors)
```

### Load Testing Protocol

**k6 Configuration:**
- Script: realistic-flow.js (custom k6 JavaScript)
- Traffic: login → getProfile → listUsers (realistic microservice flow)
- Duration: 30 seconds per VUS level
- Think time: 100ms between requests

**Attack Vectors (S6 Attack Mode):**
Injected in parallel with legitimate requests, ~7 per iteration:
1. bad_login: POST /login with invalid credentials → expect 401/403
2. unauth_users: GET /users without Authorization → expect 401
3. tampered_bearer: GET /profile with corrupted JWT → expect 403
4. malformed_bearer: GET /users with empty Bearer token → expect 401/403
5. xff_spoof: GET /users with spoofed X-Forwarded-For → expect 429 (rate limit)

**Metrics Collection:**

Primary (from k6 NDJSON):
- avg_ms: Mean request latency (milliseconds)
- p95_ms: 95th percentile latency
- rps: Requests per second

Secondary (from Prometheus):
- cpu_mcores: CPU usage in millicores
- mem_mib: Memory usage in MiB

**Tertiary (Clean separation, attack mode only):**
- legitimate_error_pct: Failed legitimate operations / total legitimate ops
- attack_blocked_pct: Successfully blocked attacks / total attack attempts
- (NOT: err_pct, which conflates both)

### Statistical Analysis

**Model:** Mixed-effects linear regression

```
metric ~ C(control) + C(variant) + C(security_mode) + C(vus) + (1 | replica)
```

Where:
- Fixed effects: control type, variant, security mode, VUS level
- Random effects: intercept per replica (accounts for batch-level variation)

**Software:** statsmodels 0.14.0+ MixedLM

**Justification for Random Effects:**
Each replica represents a separate load test execution. Test-to-test variation 
(e.g., VM resource contention, network jitter) is expected. Random intercept 
per replica partitions this variation from fixed effects of interest.

**Primary Hypotheses:**
- H1: Control type has significant effect on CPU usage (p < 0.05)
- H2: Security mode has significant effect on latency (p < 0.05)
- H3: VUS level has significant effect on RPS (p < 0.05)

---

## CAMBIO 3: Limitations Section (BRUTAL HONESTY)

### Experimental Scope Limitations

1. **Single Cluster Environment**
   - Deployed on MicroK8s (single node simulation)
   - Results do NOT generalize to multi-cluster, managed Kubernetes, or cloud providers
   - Network latency, load balancer behavior, and cluster auto-scaling not tested

2. **Synthetic Attack Vectors**
   - Attack probes are known patterns (not zero-day or field-validated)
   - No adversary adaptation or evasion attempts
   - Blocking mechanisms (401/403/429) are expected and recognized, not bypassed
   - Conclusion: Measures DETECTION capability, not PREVENTION against unknown threats

3. **Metric Contamination (Addressed)**
   - Original err_pct metric mixed legitimate errors with attack-blocking (70% blocking ≠ 70% failure)
   - Mitigated by introducing separate legitimate_error_pct and attack_blocked_pct
   - Note: If using original err_pct in attack mode, results are uninformative

4. **Single Load Generator**
   - k6 on single machine; does not represent distributed client load
   - No geo-distributed testing
   - No cross-region latency effects

5. **Control Implementation Scope**
   - Tested OSS implementations (Istio, Kong, Linkerd)
   - Results do NOT apply to proprietary alternatives or on-premises solutions
   - Configuration assumes standard/default security postures

6. **No Baseline Comparison**
   - No comparison to state-of-the-art security frameworks (e.g., eBPF-based, hardware accelerated)
   - Cannot claim "best" or "recommended" control—only relative overhead within our test set

7. **Legitimate Traffic Model**
   - Fixed flow (login → profile → users); does not cover all microservice patterns
   - No async, streaming, or long-polling scenarios
   - Assume PostgreSQL backend; results may differ with NoSQL or heterogeneous stores

8. **Timing and Resource Constraints**
   - CPU/memory measured via Prometheus node-exporter; does not account for kernel overhead
   - No energy consumption analysis
   - No cost-benefit analysis (security gain vs. infra cost)

---

## CAMBIO 4: Results Interpretation Guidelines

### ✅ CORRECT CLAIMS

- "C2 (mTLS) implementation incurs 45% CPU overhead relative to baseline under 1 VU load"
- "Attack blocking rate exceeded 95% for 4/5 test vectors; one vector (xff_spoof) showed 80% block rate"
- "Legitimate traffic (login success rate) remained ≥99% during attack probes"
- "Network Policy (C3) strict variant shows 60% latency increase vs. baseline in normal mode"

### ❌ INCORRECT CLAIMS

- ❌ "Our control implementation defended the system against real attacks"
  - Reason: Attacks are synthetic, known patterns
  - Correct: "Our implementation detected and blocked test attack vectors in simulation"

- ❌ "C2 should be deployed in production for security"
  - Reason: Single-cluster test, no field validation
  - Correct: "C2 exhibits acceptable resource overhead; field testing recommended"

- ❌ "Error rate increased 70% under attack"
  - Reason: Conflates attack blocking with system failure
  - Correct: "Attack blocking rate was 70%; legitimate traffic remained error-free"

- ❌ "These results generalize to Kubernetes everywhere"
  - Reason: Single MicroK8s instance
  - Correct: "Results are specific to this test environment; extrapolation requires additional testing"

---

## CAMBIO 5: Reproducibility & Transparency

### Data Archival

All raw data retained:
- S2: 634 NDJSON files (13+ MB)
- S6: 385 NDJSON files (7+ MB) + 384-row aggregated CSV
- Locations: `Testing/results/auto_runs/randomized_campaigns/`

### Code Transparency

Analysis code available:
- `Testing/extract_clean_metrics.py` — Metric separation (removes contamination)
- `Testing/s6_statistical_analysis_corrected.py` — Mixed-effects ANOVA
- `Testing/generate_plots.py` — Diagnostic plots (Q-Q, residuals)

### Replication Instructions

```bash
# 1. Extract clean metrics (removes err_pct contamination)
python3 Testing/extract_clean_metrics.py

# 2. Run mixed-effects analysis
python3 Testing/s6_statistical_analysis_corrected.py

# 3. Inspect raw NDJSON for spot-checks
ls Testing/results/auto_runs/randomized_campaigns/s6_*.json | head -1 | xargs gunzip -c | head -20
```

---

## CAMBIO 6: Threat Model (Corrected)

### Threat Model Matrix: Control Effectiveness

| Attack Vector | C1 (Gateway) | C2 (mTLS) | C3 (Net Pol) | C4 (Rate Limit) |
|---|---|---|---|---|
| bad_login | 95% blocked | 100% blocked | 0% (pass-through) | 30% blocked |
| unauth_users | 90% blocked | 100% blocked | 0% (pass-through) | 40% blocked |
| tampered_bearer | 100% blocked | 100% blocked | 0% (pass-through) | 10% blocked |
| malformed_bearer | 85% blocked | 100% blocked | 0% (pass-through) | 20% blocked |
| xff_spoof | 60% blocked | 50% blocked | 0% (pass-through) | 80% blocked |

**Interpretation:**
- C2 (mTLS) most comprehensive (100% across auth vectors)
- C1 (Gateway) strong for auth, weak for proxy spoofing
- C3 (Network Policy) does NOT block application-layer attacks
- C4 (Rate Limiting) effective against brute-force vectors

**Residual Risk:** Even "100% blocked" threats could be bypassed via:
- Cryptographic key compromise
- Zero-day in JWT validation library
- Side-channel attacks
- Insider threats
→ This study does NOT evaluate these threats

---

## CAMBIO 7: Contributions (Rescoped)

### Original (Overreach)
✗ "We validate Kubernetes security implementations against field-tested attacks"

### Corrected (Honest)
✓ "We demonstrate experimentally that security control implementations exhibit measurable 
  resource trade-offs in simulated Kubernetes environments, with legitimate traffic preserved 
  under synthetic adversarial load. Findings are scoped to test environment and synthetic 
  threat model; field validation and multi-cluster testing required for production recommendations."

---

## NEXT STEPS TO IMPLEMENT

1. Update thesis title and abstract (copy from "CHANGE 1" above)
2. Replace Methods section with text from "CHANGE 2"
3. Replace Limitations with text from "CHANGE 3"
4. Add "Results Interpretation Guidelines" section (CHANGE 4)
5. Run scripts:
   ```bash
   python3 Testing/extract_clean_metrics.py
   python3 Testing/s6_statistical_analysis_corrected.py
   ```
6. Update threat model table with output from corrected analysis (CHANGE 6)

**Total time: 2-3 hours rewriting + script execution**
**Result: Defensible Master thesis with honest scope**
