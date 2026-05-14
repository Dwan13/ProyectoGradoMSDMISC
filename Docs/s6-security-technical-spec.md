# S6 Integrated Security and Quality Validation Specification

## 1. Purpose

S6 is a full integrated campaign designed to support a dual-master defense:

- Digital Security: evidence of control effectiveness against realistic abuse patterns.
- Systems and Computing: quantitative trade-off analysis across quality attributes.

S6 extends S2 by adding a security condition factor while preserving full coverage of controls, variants, and VU levels.

## 2. Scope and Claims

### 2.1 Supported claims

S6 can support with high confidence:

1. Relative effectiveness of C1-C4 controls under normal and attack conditions.
2. Cost of security in quality attributes (latency, error, throughput, CPU, memory).
3. End-to-end operational behavior for login and user listing paths up to PostgreSQL.

### 2.2 Explicit non-claims

S6 does not claim full security completeness. It does not exhaustively test all attacker models (for example distributed botnet IP rotation at internet scale).

## 3. Experimental Design

### 3.1 Factors

1. Control family: C1, C2, C3, C4.
2. Variant level: 3 variants per control.
3. Load level: 1, 5, 10, 20 VUs.
4. Security mode: normal, attack.
5. Block/replicate: randomized daily block.

### 3.2 Matrix size

- Cells per block: 4 x 3 x 4 x 2 = 96.
- Replicates: 4.
- Total runs: 384.

Matrix generator:

- [Testing/generate_s6_integrated_matrix.py](Testing/generate_s6_integrated_matrix.py)

Generated matrix path:

- [Testing/results/scaling_tests/design_matrix_s6_integrated_dual_n4_randomized_blocks.csv](Testing/results/scaling_tests/design_matrix_s6_integrated_dual_n4_randomized_blocks.csv)

## 4. Architecture and Control Mapping

Architecture source:

- [Docs/s6-integrated-security-architecture.puml](Docs/s6-integrated-security-architecture.puml)

Operational mapping:

1. C1 gateway: ingress implementation choice (baseline, Istio gateway, Kong).
2. C2 trust channel: service mesh mTLS (Istio or Linkerd) versus baseline.
3. C3 segmentation: NetworkPolicy strictness.
4. C4 edge abuse control: ingress rate limiting.

## 5. Security Validation Mechanism

Security is tested inside the same campaign using security_mode.

### 5.1 normal mode

Per iteration:

1. POST /login with valid credentials.
2. GET /profile with bearer token.
3. GET /users with bearer token.

### 5.2 attack mode

Per iteration, after successful normal flow:

1. POST /login with invalid password.
2. GET /users without bearer token.
3. Classify blocked responses as 401, 403, or 429.
4. GET /profile with tampered bearer token.
5. GET /users with malformed bearer header.
6. GET /users with spoofed/rotating X-Forwarded-For chain and forged token.

Implemented in:

- [RealisticServices/k6/realistic-flow.js](RealisticServices/k6/realistic-flow.js)

Attack profile is set to `advanced` by default from benchmark runner, which enables all listed vectors.

## 6. Metrics

### 6.1 Core six metrics by run

1. avg_ms
2. p95_ms
3. err_pct
4. rps
5. cpu_mcores
6. mem_mib

### 6.2 Security and business traces

1. login_ok
2. users_ok
3. jwt_trace_events
4. unique_jwt_fp
5. profile_db_latency_ms_avg
6. users_db_latency_ms_avg

Analyzer:

- [Testing/analyze_s6_integrated_results.py](Testing/analyze_s6_integrated_results.py)

Integrated output:

- [Testing/results/s6_integrated_all_6_metrics.csv](Testing/results/s6_integrated_all_6_metrics.csv)
- [Testing/results/s6_analysis/S6_INTEGRATED_REPORT.md](Testing/results/s6_analysis/S6_INTEGRATED_REPORT.md)
- [Testing/results/s6_analysis/threat_model_matrix.csv](Testing/results/s6_analysis/threat_model_matrix.csv)

## 7. Execution Procedure

### 7.1 Preconditions

1. Validate environment and profile.
2. Verify S6 scripts and manifests.

Verifier:

- [scripts/verify-s6-integrated-config.sh](scripts/verify-s6-integrated-config.sh)

### 7.2 Reproducible run

Runner:

- [scripts/run-s6-integrated-repro.sh](scripts/run-s6-integrated-repro.sh)

Profile:

- [scripts/s6-integrated-profile.env](scripts/s6-integrated-profile.env)

Randomized dispatcher:

- [scripts/run-randomized-design-matrix.sh](scripts/run-randomized-design-matrix.sh)

Benchmark wrapper:

- [scripts/run-k6-benchmark.sh](scripts/run-k6-benchmark.sh)

## 8. Statistical Inference Plan

### 8.1 Primary model

Mixed-effects model per metric:

- y ~ control * variant * vus * security_mode + (1 | block_day)

Alternative if needed:

- robust or non-parametric contrast for heavy-tailed residuals.

### 8.2 Decision criteria

1. Report effect size and confidence intervals, not only p-values.
2. Distinguish expected security enforcement responses from system failures.
3. For no-difference claims, use equivalence testing with predeclared SESOI.

### 8.3 Error interpretation

In attack mode, a high err_pct can be expected because blocked malicious requests are counted by HTTP failure thresholds.
This must be interpreted jointly with:

- attack_blocked_total,
- check pass rate,
- successful protected-path operations.

## 9. 20 VU Feasibility Evidence Under New Conditions

A direct validation run was executed at 20 VUs under attack mode (C3 strict).

Evidence files:

- [Testing/results/auto_runs/randomized_campaigns/s6_integrated_dual_n4_B1_2026-05-20_order999_C3_strict_attack_20vus.json](Testing/results/auto_runs/randomized_campaigns/s6_integrated_dual_n4_B1_2026-05-20_order999_C3_strict_attack_20vus.json)
- [Testing/results/scaling_tests/s6_attack_validation_C3_strict_20vus_metrics.csv](Testing/results/scaling_tests/s6_attack_validation_C3_strict_20vus_metrics.csv)

Observed key values:

1. p95_ms = 36.9631
2. rps = 175.8205
3. cpu_mcores = 1131.6277
4. mem_mib = 175.8008
5. login_ok = 1073
6. users_ok = 1073

Interpretation:

- 20 VUs are operationally feasible with stable checks.
- Attack-mode err_pct is elevated by design due to blocked malicious probes.

## 10. Threat Model Coverage Summary

### 10.1 Covered threats

1. Credential misuse attempts (invalid login).
2. Unauthorized resource access (missing token).
3. Forged and malformed bearer token abuse.
4. Spoofed proxy-chain headers (`X-Forwarded-For`) with token forgery.
5. Edge abuse pressure with rate-limiting controls.
6. Segmentation behavior under restrictive policy levels.

### 10.2 Residual risk and follow-up

1. Token uniqueness is currently bounded by issued claim granularity (iat in seconds).
2. For strict per-token uniqueness evidence, add jti in auth-service claims.
3. Add distributed source spoofing tests for stronger anti-botnet claims.

## 11. Readiness for Double-Master Defense

With complete S6 execution and statistical reporting, evidence is sufficient to support:

1. Security-control effectiveness claims within declared scope.
2. Integrated quality-security trade-off conclusions.
3. A stronger unified narrative than separate S2 plus S5 interpretation.

Readiness condition status:

- Full S6 matrix execution and analysis is complete (384/384 runs).

## 12. Final Closure Status (2026-05-14)

### 12.1 Execution integrity

1. Official matrix runs: 384/384.
2. Partial files: 0.
3. Missing files: 0.

### 12.2 Final dataset integrity

1. Consolidated rows: 384.
2. Core 6 metrics present for all runs: avg_ms, p95_ms, err_pct, rps, cpu_mcores, mem_mib.
3. Missing CPU entries: 0.
4. Missing memory entries: 0.

### 12.3 Global quantitative snapshot

1. Mean avg_ms: 118.10.
2. Mean p95_ms: 276.13.
3. Mean err_pct: 42.23.
4. Mean rps: 91.89.
5. Mean cpu_mcores: 288.11.
6. Mean mem_mib: 193.41.

### 12.4 Key inferential outcomes

1. avg_ms model fit: R² = 0.5730, p = 1.42e-59.
2. err_pct model fit: R² = 0.9235, p = 4.40e-196.
3. cpu_mcores model fit: R² = 0.8678, p = 2.05e-152.

Interpretation:

- Factor effects are statistically strong for latency, error rate, and CPU cost under integrated conditions.
- Attack-mode error inflation must be interpreted as security enforcement behavior where malicious probes are intentionally blocked.
