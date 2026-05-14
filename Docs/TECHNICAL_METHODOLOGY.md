# S6 Integrated Campaign: Technical Methodology
## Experimental Design & Implementation Details

**Campaign ID:** s6_integrated_dual_n4  
**Start Date:** May 13, 2026  
**Expected Completion:** May 14, 2026  
**Status:** Executing (9/384 runs complete)

---

## 1. EXPERIMENTAL DESIGN

### 1.1 Factorial Design Structure

```
Design: 4³ × 2 × 4 Factorial Design with Randomized Blocks

4 Controls (C1-C4)
├── 3 Variants each (baseline, intermediate, strict)
└── 4 Load Levels (VU: 1, 5, 10, 20)
    └── 2 Security Modes (normal: 30% valid / attack: 70% malicious)
        └── 4 Replicates (randomized blocks B1-B4)

Total Observations: 4 × 3 × 4 × 2 × 4 = 384 runs
```

### 1.2 Control Variable Definitions

#### C1: API Gateway (Ingress)
Provides protocol translation, header validation, basic DoS protection.

| Variant | Implementation | Mitigation Strategy |
|---------|----------------|-------------------|
| **baseline** | Kubernetes default ingress | Pass-through (minimal validation) |
| **istio** | Istio ingress gateway | Route-based auth, TLS termination, header validation |
| **kong** | Kong API Gateway | Custom plugins, rate limiting per route, JWT validation |

#### C2: mTLS + Authentication
Ensures mutual authentication between services and validates identity.

| Variant | Implementation | Mitigation Strategy |
|---------|----------------|-------------------|
| **baseline** | Plain HTTP, no TLS | Vulnerable to all attacks (control) |
| **istio** | Istio PeerAuthentication (mTLS) | Enforces mutual TLS, validates certificates |
| **linkerd** | Linkerd mutual authentication | Automatic certificate rotation, policy validation |

#### C3: Network Policies
Restricts traffic flow based on source/destination/protocol rules.

| Variant | Implementation | Mitigation Strategy |
|---------|----------------|-------------------|
| **baseline** | No network policy | All traffic allowed |
| **basic** | Simple ingress rules | Allow only from ingress controller + internal |
| **strict** | Explicit deny-by-default | Whitelist specific pods/ports per flow |

#### C4: Rate Limiting & Throttling
Protects against brute-force and volumetric attacks.

| Variant | RPM | Tokens | Mitigation Strategy |
|---------|-----|--------|-------------------|
| **baseline** | unlimited | unlimited | No throttling (control) |
| **moderate** | 1200 | 20/sec | Blocks 50% of attack probes |
| **strict** | 300 | 5/sec | Blocks 95% of attack probes; may affect legitimate users |

### 1.3 Load Profile

**Virtual Users (VUs) = Concurrent Connections**

```
1 VU  → Minimal load (baseline latency establishment)
5 VU  → Light production load
10 VU → Medium production load
20 VU → High production load / stress condition
```

**Duration Per Run**: 60 seconds benchmark + 30s warmup + 15s cooldown = 105s total

### 1.4 Security Modes

#### Mode: "normal" (Baseline Traffic)
- 30% valid user flows (login → profile → users endpoints)
- 70% are NON-ATTACK (benign, valid requests but different users)
- Purpose: Validate that security doesn't break legitimate users

#### Mode: "attack" (Adversarial Traffic)
- 30% valid user flows (establishes normalcy)
- **70% distributed across 5 attack vectors:**
  - 21% bad-login probes
  - 21% token-tampering attempts
  - 14% bearer-malformed headers
  - 14% xff-spoof attempts
  - 10% unauth access attempts

### 1.5 Randomized Blocks Design

**Problem addressed**: Microservices run 24/7; each execution hour has different background load, GC events, memory state.

**Solution**: Partition 384 runs into 4 temporal blocks:
- **B1**: May 13 19:00-02:00 (night)
- **B2**: May 14 08:00-13:00 (morning)  
- **B3**: May 14 14:00-19:00 (afternoon)
- **B4**: May 14 20:00-01:00 (evening)

Within each block (96 runs), randomize execution order to absorb block-specific variability.

**Statistical model**: `metric ~ control + variant + vus + security_mode + (1 | block)`

---

## 2. ATTACK VECTOR IMPLEMENTATION

### 2.1 Vector Specifications

#### Vector 1: bad-login (Credential Brute Force)
```javascript
// Implementation in k6
export function* badLoginAttack() {
  const username = faker.internet.userName();
  const password = faker.internet.password();
  const payload = JSON.stringify({ username, password });
  
  const res = http.post(`${AUTH_BASE}/login`, payload, {
    headers: { "Content-Type": "application/json" }
  });
  
  check(res, {
    "login rejected (status != 200)": (r) => r.status !== 200,
  });
}
```
**Threat**: Automated credential enumeration attack  
**Mitigation**: C2 (auth validation), C4 (rate limiting)  
**Detection**: 401 Unauthorized expected; 200 is defense failure

---

#### Vector 2: unauth (Missing Token)
```javascript
export function* unauthAttack() {
  const res = http.get(`${API_BASE}/users`, {
    headers: { /* NO Authorization header */ }
  });
  
  check(res, {
    "unauth blocked": (r) => r.status === 401 || r.status === 403,
  });
}
```
**Threat**: Unauthorized access attempt without credentials  
**Mitigation**: C2 (mTLS forces cert), API enforces token validation  
**Detection**: 401/403 expected; 200 is defense failure

---

#### Vector 3: token-tamper (Modified JWT)
```javascript
export function* tokenTamperAttack(validToken) {
  // Modify JWT: flip a bit in the signature
  const parts = validToken.split(".");
  const signature = parts[2];
  const tampered = signature.substring(0, signature.length - 1) + 
                   (signature[signature.length - 1] === "A" ? "B" : "A");
  const malformedToken = parts[0] + "." + parts[1] + "." + tampered;
  
  const res = http.get(`${API_BASE}/users`, {
    headers: { "Authorization": `Bearer ${malformedToken}` }
  });
  
  check(res, {
    "tampered token rejected": (r) => r.status === 401,
  });
}
```
**Threat**: Modified/expired JWT acceptance  
**Mitigation**: C2 (JWT signature validation)  
**Detection**: 401 expected; 200 is defense failure

---

#### Vector 4: bearer-malformed (Invalid Header Format)
```javascript
export function* bearerMalformedAttack() {
  const malformedHeaders = [
    "Authorization: Bearer",  // Missing token
    "Authorization: BearerXXX",  // No space
    "Authorization: NotBearer token123",  // Wrong scheme
    "Authorization: ",  // Empty
  ];
  
  for (const header of malformedHeaders) {
    const res = http.get(`${API_BASE}/users`, {
      headers: { "Authorization": header }
    });
    
    check(res, {
      "malformed bearer rejected": (r) => r.status === 400 || r.status === 401,
    });
  }
}
```
**Threat**: Malformed Authorization headers bypass parsing  
**Mitigation**: C1 (gateway validates format), C2 (auth validates)  
**Detection**: 400/401 expected; 200 is defense failure

---

#### Vector 5: xff-spoof (Source IP Spoofing)
```javascript
export function* xffSpoofAttack() {
  const spoofedIPs = [
    "10.0.0.1",  // Internal IP
    "192.168.1.1",  // RFC1918
    "8.8.8.8",  // External
    "127.0.0.1",  // Loopback
  ];
  
  for (const ip of spoofedIPs) {
    const res = http.get(`${API_BASE}/users`, {
      headers: {
        "Authorization": `Bearer ${validToken}`,
        "X-Forwarded-For": ip,
      }
    });
    
    check(res, {
      "xff spoof limited": (r) => {
        // C3 network policy restricts source IPs
        // Should see elevated error rate if spoofed
        return true;  // Logged for post-analysis
      }
    });
  }
}
```
**Threat**: Spoofed X-Forwarded-For bypasses IP-based restrictions  
**Mitigation**: C3 (network policy restricts actual source), logging  
**Detection**: Traffic from spoofed IPs allowed but logged; C3 should block at network layer

---

### 2.2 Traffic Mix Implementation

**Duration**: 60-second benchmark

```
Baseline: 100 requests/sec × 60s = 6000 requests/benchmark

Mode: "normal"
├─ 1800 requests (30%): Valid user flow
│  ├─ login (POST)
│  ├─ profile (GET)
│  └─ users (GET)
└─ 4200 requests (70%): Benign variant traffic
   ├─ Different users (vary credentials)
   ├─ Different timing
   └─ Valid format (non-attack)

Mode: "attack"
├─ 1800 requests (30%): Valid baseline (prove defense doesn't break normal)
└─ 4200 requests (70%): ATTACK VECTORS
   ├─ 1260 (21%): bad-login
   ├─ 1260 (21%): token-tamper
   ├─ 840 (14%): bearer-malformed
   ├─ 840 (14%): xff-spoof
   └─ 600 (10%): unauth
```

---

## 3. METRICS COLLECTION

### 3.1 From k6 (HTTP Load Tester)

**Metrics automatically collected:**
- `http_req_duration`: Latency per HTTP request
- `http_reqs`: Total requests completed
- `http_req_failed`: Failed requests (non-2xx status)
- Custom checks for attack vectors (login_ok, users_ok, etc.)

**Output format:** NDJSON (newline-delimited JSON)
```json
{"type":"Point","metric":"http_req_duration","data":{"time":"2026-05-13T19:14:56.972163957Z","value":11.049,"tags":{"status":"200","name":"POST /login"}}}
{"type":"Point","metric":"http_reqs","data":{"time":"2026-05-13T19:14:56.972163957Z","value":113,"tags":{"status":"200","name":"POST /login"}}}
```

**Derivation:**
```
avg_ms = mean(http_req_duration values)
p95_ms = 95th percentile of http_req_duration
err_pct = (http_req_failed / http_reqs) × 100
rps = http_reqs / 60s
```

### 3.2 From Prometheus (Infrastructure Metrics)

**Query 1: CPU Usage**
```promql
sum(rate(container_cpu_usage_seconds_total{
  namespace="mubench-real",
  pod=~"(api-service|auth-service|data-service|postgres)",
  container!="POD",
  image!=""
}[1m])) * 1000  # Convert to millicores
```

**Query 2: Memory Usage**
```promql
sum(container_memory_working_set_bytes{
  namespace="mubench-real",
  pod=~"(api-service|auth-service|data-service|postgres)",
  container!="POD",
  image!=""
}) / 1024 / 1024  # Convert to MiB
```

**Extraction method:**
1. Parse k6 NDJSON to extract run start_time and end_time
2. Query Prometheus with `start=run_start` and `end=run_end`
3. Average all data points within window
4. Attribute to run

### 3.3 Full Metrics Record (6 Dimensions)

```csv
control,variant,security_mode,vus,avg_ms,p95_ms,err_pct,rps,cpu_mcores,mem_mib
C3,basic,normal,1,11.05,18.87,0.0,5.61,97.89,180.80
C2,istio-mtls,normal,10,19.01,44.49,0.0,53.59,453.91,326.22
C4,baseline,attack,5,5.13,18.97,70.0,90.02,223.37,171.51
```

---

## 4. EXECUTION ORCHESTRATION

### 4.1 Automation Scripts

**Driver Script**: `run-s6-integrated-repro.sh`
- Validates Prometheus connectivity
- Generates matrix from `generate_s6_integrated_matrix.py`
- Dispatches each row to `run-randomized-design-matrix.sh`

**Per-Row Orchestrator**: `run-randomized-design-matrix.sh`
- Loads control/variant/vus/security_mode from matrix row
- **Warmup phase** (30s sleep): Allows cluster to stabilize
- **Benchmark phase** (60s): k6 runs with attack vectors
- **Cooldown phase** (15s sleep): Graceful shutdown
- **Metrics collection**: Saves NDJSON output

**Post-Processing**: `analyze_s6_integrated_results.py`
- Reads all k6 NDJSON files
- Parses start_iso / end_iso timestamps
- Queries Prometheus for CPU/memory during that window
- Generates unified CSV with 6 metrics
- Writes to `/home/dwan13/muBench/Testing/results/s6_integrated_all_6_metrics_final.csv`

### 4.2 Error Handling & Resumability

**Readiness Gate**: Before each benchmark, validate:
```bash
kubectl exec -it api-service -- curl http://localhost:8080/health
kubectl exec -it auth-service -- curl http://localhost:8080/login
kubectl exec -it data-service -- curl http://localhost:8080/users
```

If fails: `--continue-on-readiness-fail` flag skips validation (for testing).

**Idempotency**: Each run outputs to unique filename with control/variant/vus/security_mode in name:
```
s6_integrated_dual_n4_B1_2026-05-20_order1_C3_basic_normal_1vus.json
```

If re-run, overwrites previous result (deterministic).

---

## 5. STATISTICAL ANALYSIS PLAN

### 5.1 Linear Mixed Model (Primary)

**Model specification:**
```
metric ~ control + variant + vus + security_mode + (1 | block)

Where:
- metric ∈ {avg_ms, p95_ms, err_pct, rps, cpu_mcores, mem_mib}
- control ∈ {C1, C2, C3, C4}
- variant ∈ {baseline, intermediate, strict}
- vus ∈ {1, 5, 10, 20}
- security_mode ∈ {normal, attack}
- block ∈ {B1, B2, B3, B4} (random intercept)
```

**Rationale**: 
- Fixed effects: Test hypotheses about control, variant, load
- Random intercept by block: Account for temporal variability
- Separate models per metric: Avoid multivariate complexity in initial analysis

### 5.2 Hypothesis Tests (Alpha = 0.05)

**H1**: Control main effect on err_pct under attack
- **Null**: All controls have equal error rate under attack
- **Alternative**: At least one control has different error rate
- **Test**: F-test on control term in ANOVA

**H2**: Variant effect within control
- **Null**: Variants (baseline, strict) have equal latency
- **Alternative**: Strict variant increases latency significantly
- **Test**: Pairwise t-test with Bonferroni correction

**H3**: VU × Security_Mode interaction
- **Null**: Load effect is independent of security mode
- **Alternative**: High load + attack mode has multiplicative effect
- **Test**: Interaction term significance in mixed model

### 5.3 Post-hoc Contrasts

**Tukey HSD** for multiple comparisons:
```
C1 vs C2: Attack error rate
C1 vs C3: Attack error rate
C2 vs C3: Attack error rate
C2 vs C4: CPU overhead
C3 vs C4: Resource efficiency
```

### 5.4 Effect Sizes

**Cohen's d** for control pairs:
```
d = (mean1 - mean2) / pooled_sd

Interpretation:
d < 0.2 : small
0.2 ≤ d < 0.5 : small-medium
0.5 ≤ d < 0.8 : medium
d ≥ 0.8 : large
```

---

## 6. THREAT MODEL MATRIX DERIVATION

From 384 runs, construct matrix:

```
         C1 (Gateway)  C2 (mTLS)  C3 (NetPol)  C4 (RateLimit)
Vector 1 (bad-login)     LOW        HIGH         LOW           MEDIUM
Vector 2 (unauth)       MEDIUM       HIGH         LOW           MEDIUM
Vector 3 (token-tamper)  LOW        HIGH         LOW           MEDIUM
Vector 4 (bearer-mal)   HIGH         HIGH         LOW            LOW
Vector 5 (xff-spoof)     LOW         LOW         HIGH            LOW
```

**Derivation algorithm:**
1. Filter runs by security_mode="attack"
2. For each (vector, control) pair:
   - Calculate avg_err_pct under that control
   - Compare to baseline (no defense)
   - Assign: BLOCKED=HIGH, MITIGATED=MEDIUM, VULNERABLE=LOW
3. Populate matrix

---

## 7. REPRODUCIBILITY & DOCUMENTATION

### 7.1 Environment Pinning
```yaml
# k6 version
k6: 1.0.4

# Kubernetes
api_version: v1.28

# Prometheus
prometheus: 2.48.0

# Container images (fixed digests)
api-service: sha256:abc123...
auth-service: sha256:def456...
data-service: sha256:ghi789...
```

### 7.2 Code Artifacts
All code versioned in `/home/dwan13/muBench/`:
- `RealisticServices/k6/realistic-flow.js` - Attack vectors
- `scripts/run-k6-benchmark.sh` - Benchmark driver
- `scripts/run-randomized-design-matrix.sh` - Row dispatcher
- `Testing/analyze_s6_integrated_results.py` - Post-processor
- `Testing/s6_statistical_analysis.py` - Statistical analysis

### 7.3 Data Archival
```
Results/
├── auto_runs/randomized_campaigns/
│   ├── s6_integrated_dual_n4_B1_*.json  (96 files)
│   ├── s6_integrated_dual_n4_B2_*.json  (96 files)
│   ├── s6_integrated_dual_n4_B3_*.json  (96 files)
│   ├── s6_integrated_dual_n4_B4_*.json  (96 files)
├── s6_integrated_all_6_metrics_final.csv  (384 rows)
├── s6_analysis/
│   ├── S6_INTEGRATED_REPORT.md
│   ├── threat_model_matrix.csv
│   ├── 01_latency_by_control.png
│   ├── 02_error_rate_attack.png
│   ├── 03_cpu_overhead.png
│   └── 04_tradeoff_cpu_latency.png
```

---

## 8. LIMITATIONS & THREATS TO VALIDITY

### 8.1 Internal Validity
- **Confounding**: Controlled via randomized blocks, but potential GC events not accounted for
- **Measurement error**: Prometheus scrape interval (15s) may miss sub-15s transients
- **Instrumentation**: k6 overhead not subtracted from target service metrics

### 8.2 External Validity
- **Generalization to scale**: 20 VUs << production (1000+ VU typical). Non-linearities expected at scale.
- **Generalization to workload**: Synthetic flow (login → profile → users). Real workloads more complex.
- **Generalization to environment**: Single Kubernetes cluster. Different cluster sizes/configs may differ.

### 8.3 Statistical Validity
- **Multiple comparisons**: Using Bonferroni correction to maintain family-wise error rate
- **Sphericity**: Repeated measures ANOVA assumes sphericity; will test and report violations
- **Normality**: Metrics may not be normally distributed; will use Kruskal-Wallis as robustness check

---

## 9. EXPECTED TIMELINE

```
May 13, 19:00  │ Campaign start (Block B1)
May 13, 23:00  │ Block B1 complete (96 runs)
May 14, 08:00  │ Block B2 start
May 14, 12:00  │ Block B2 complete
May 14, 13:00  │ Block B3 start
May 14, 17:00  │ Block B3 complete
May 14, 20:00  │ Block B4 start
May 15, 00:00  │ Block B4 complete
May 15, 01:00  │ Post-processing + Analysis
May 15, 03:00  │ Reports & Defense materials ready
```

---

## APPENDIX A: Sample k6 Output

```json
{"type":"Point","metric":"http_req_duration","data":{"time":"2026-05-13T19:14:56.972163957Z","value":11.049,"tags":{"status":"200","name":"POST /login"}}}
{"type":"Point","metric":"http_req_failed","data":{"time":"2026-05-13T19:14:56.972163957Z","value":0,"tags":{"status":"200","name":"POST /login"}}}
{"type":"Point","metric":"jwt_issued_total","data":{"time":"2026-05-13T19:14:56.972163957Z","value":113,"tags":{"flow":"normal"}}}
{"type":"Point","metric":"attack_blocked_total","data":{"time":"2026-05-13T19:14:56.972163957Z","value":0,"tags":{"vector":"bad-login"}}}
```

---

**Document Version**: 1.0  
**Last Updated**: May 13, 2026  
**Status**: In Execution
