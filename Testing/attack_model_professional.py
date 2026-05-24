#!/usr/bin/env python3
"""
PROFESSIONAL ATTACK MODEL FOR SECURITY EVALUATION
===================================================

Framework: OWASP Top 10 2021 + CWE Top 25
Threat Model: Operational Security in Microservices

ATTACK VECTORS (9 types, mapped to OWASP/CWE):
----------------------------------------------

1. AUTHENTICATION BYPASS (CWE-287: Improper Authentication)
   - OWASP A01: Broken Access Control
   - Vector: bad_login_dictionary
     * Method: POST /auth/login with 10 common password variations
     * Expected: Rate-limited at 429 (Too Many Requests)
     * Metric: login_rate_limit_triggered (should be 1 after N attempts)
   
   - Vector: credential_reuse
     * Method: POST /auth/login with leaked credentials (demo:demo123)
     * Expected: 200 OK (legitimate if creds valid, BUT user should detect this)
     * Detection: JWT token appears in multiple sessions
     * Metric: concurrent_session_count (max 1 per user should be enforced)

2. BROKEN AUTHORIZATION (CWE-639: Authorization Bypass)
   - OWASP A01: Broken Access Control
   - Vector: unauthenticated_access
     * Method: GET /api/users WITHOUT Authorization header
     * Expected: 401 Unauthorized
     * Metric: unauthenticated_requests_blocked (should be 100%)
   
   - Vector: privilege_escalation
     * Method: GET /api/admin/settings (non-existent endpoint)
     * Expected: 403 Forbidden (not found treated as forbidden in security context)
     * Metric: unauthorized_endpoint_access_blocked (should be 100%)

3. INVALID TOKEN INJECTION (CWE-347: Improper Verification of Cryptographic Signature)
   - OWASP A01: Broken Access Control
   - Vector: tampered_jwt_signature
     * Method: GET /api/profile with JWT where signature tampered (last char changed)
     * Expected: 403 Forbidden (signature validation fails)
     * Metric: invalid_signature_requests_blocked (should be 100%)
   
   - Vector: expired_token_reuse
     * Method: GET /api/profile with JWT marked as expired in claims
     * Expected: 401 Unauthorized (expired token rejected)
     * Metric: expired_token_requests_blocked (should be 100%)

4. MALFORMED REQUEST FUZZING (CWE-20: Improper Input Validation)
   - OWASP A03: Injection
   - Vector: malformed_bearer_header
     * Method: GET /api/users with "Authorization: Bearer" (no token)
     * Expected: 401/400 Bad Request
     * Metric: malformed_header_requests_blocked (should be 100%)
   
   - Vector: sql_injection_attempt
     * Method: GET /api/users?offset=1; DROP TABLE users; --
     * Expected: 403/400 (parametrized queries should block)
     * Metric: injection_attempts_blocked (should be 100%)

5. PROXY/HEADER SPOOFING (CWE-923: Improper Restriction of Communication Channel to Intended Endpoints)
   - OWASP A04: Insecure Deserialization (via X-Forwarded-For)
   - Vector: xff_header_spoof
     * Method: GET /api/users with X-Forwarded-For: 203.0.113.5 (fake IP)
     * Expected: Either:
        a) Ingested (if no validation) - security risk, but API still works
        b) Blocked - 403 if strict SPF/rate limit per IP
     * Metric: xff_spoofed_requests (logged, may or may not block depending on control)
   
   - Vector: host_header_injection
     * Method: GET /api/profile with Host: evil.com (cache poisoning attempt)
     * Expected: Ignored or 400 Bad Request
     * Metric: host_header_injection_attempts (should not affect API logic)

6. RATE LIMITING EVASION (CWE-770: Allocation of Resources Without Limits)
   - OWASP A04: Denial of Service
   - Vector: slow_request_attack (Slowloris variant)
     * Method: Send partial HTTP requests, hold connections open
     * Expected: Timeout or connection reset after T seconds
     * Metric: slow_request_connections_closed (should be 100%)
   
   - Vector: distributed_rate_limit_bypass
     * Method: Same user from 5 different IPs within 1 second
     * Expected: Either per-user limit (blocks) or per-IP limit (passes)
     * Metric: rate_limit_enforcement_type (reveals control sophistication)

7. SESSION HIJACKING (CWE-384: Session Fixation)
   - OWASP A07: Authentication and Session Management Flaws
   - Vector: session_fixation_attempt
     * Method: Force user to accept predefined JWT
     * Expected: 401 if session ID already exists in different context
     * Metric: session_fixation_attempts_blocked (should be 100%)
   
   - Vector: cookie_replay
     * Method: Replay JWT from previous session after logout
     * Expected: 401 Unauthorized (logout invalidates token)
     * Metric: replayed_token_attempts_blocked (requires token invalidation on logout)

8. SENSITIVE DATA EXPOSURE (CWE-200: Exposure of Sensitive Information)
   - OWASP A02: Cryptographic Failures
   - Vector: response_timing_attack
     * Method: Measure response time differences between valid/invalid users
     * Expected: Timing should be constant (no information leakage)
     * Metric: response_time_variance (should be <10ms between valid/invalid)
   
   - Vector: error_message_disclosure
     * Method: Query non-existent user to see if error reveals user existence
     * Expected: Generic error "User not found" (no different for existent/non-existent)
     * Metric: error_message_consistency (should be identical regardless of user existence)

9. TRAFFIC ANALYSIS / FINGERPRINTING (CWE-215: Information Exposure Through Debug Information)
   - OWASP A09: Logging and Monitoring Failures
   - Vector: jwt_fingerprinting
     * Method: Extract JWT claims to determine server implementation/library
     * Expected: JWT structure obfuscated or standard (hard to distinguish)
     * Metric: jwt_signature_algorithm_disclosed (should not reveal secure vs insecure algos)

AGGREGATE SECURITY METRICS:
---------------------------
- overall_blocking_rate: Sum of all successful blocks / total attack attempts
  Target: >85% (some attacks may be intentionally allowed for detection/logging)
  
- legitimate_preservation_rate: Legitimate requests that PASSED / total legitimate requests
  Target: 99%+ (must not affect real users)
  
- false_positive_rate: Legitimate requests BLOCKED / total legitimate requests
  Target: <1% (overly aggressive defenses create poor UX)
  
- detection_coverage: Unique attack vectors detected / total attack vectors attempted
  Target: 100% (defense recognizes all known threats)
  
- response_time_impact: P95 latency (attack mode) - P95 latency (normal mode)
  Target: <20ms (defense overhead should be minimal)

STATISTICAL VALIDATION:
-----------------------
For each (control, variant, security_mode) combination, validate:
  ✓ Blocking rate is consistently >80% (p-value from binomial test <0.05)
  ✓ Legitimate preservation >99% (95% CI lower bound >0.99)
  ✓ Response time overhead <50% (p-value from t-test comparing latencies)

REFERENCES:
-----------
1. OWASP Top 10 2021: https://owasp.org/Top10/
2. CWE Top 25 Most Dangerous Software Weaknesses: https://cwe.mitre.org/top25/
3. NIST Cybersecurity Framework: https://www.nist.gov/cyberframework
4. RFC 7519 (JWT): https://tools.ietf.org/html/rfc7519
5. RFC 6265 (HTTP State Management Mechanism): https://tools.ietf.org/html/rfc6265
"""

import json
import pandas as pd
import numpy as np
from pathlib import Path
from collections import defaultdict
from scipy import stats

# ATTACK VECTOR CONFIGURATION (Professional, Academic-grade)
ATTACK_VECTORS = {
    'bad_login_dictionary': {
        'name': 'Authentication Dictionary Attack',
        'owasp': 'A01: Broken Access Control',
        'cwe': 'CWE-287: Improper Authentication',
        'method': 'POST /auth/login',
        'payload': {'username': 'demo', 'password': 'wrong_pass_variant_N'},
        'expected_status': [401, 403, 429],
        'severity': 'HIGH',
        'description': 'Multiple failed login attempts should trigger rate limiting'
    },
    
    'credential_reuse': {
        'name': 'Credential Reuse Detection',
        'owasp': 'A01: Broken Access Control',
        'cwe': 'CWE-287: Improper Authentication',
        'method': 'POST /auth/login',
        'payload': {'username': 'demo', 'password': 'demo123'},
        'expected_status': [200],  # Will pass, but should detect concurrent sessions
        'severity': 'MEDIUM',
        'description': 'Legitimate credentials reused; should limit concurrent sessions'
    },
    
    'unauthenticated_access': {
        'name': 'Unauthenticated Endpoint Access',
        'owasp': 'A01: Broken Access Control',
        'cwe': 'CWE-639: Authorization Bypass',
        'method': 'GET /api/users',
        'payload': {},
        'headers': {},  # No Authorization header
        'expected_status': [401],
        'severity': 'CRITICAL',
        'description': 'Endpoints MUST require valid authentication token'
    },
    
    'privilege_escalation': {
        'name': 'Privilege Escalation Attempt',
        'owasp': 'A01: Broken Access Control',
        'cwe': 'CWE-639: Authorization Bypass',
        'method': 'GET /api/admin/settings',
        'payload': {},
        'expected_status': [403, 404],
        'severity': 'CRITICAL',
        'description': 'Non-existent admin endpoints should return 403, not 500'
    },
    
    'tampered_jwt_signature': {
        'name': 'JWT Signature Tampering',
        'owasp': 'A01: Broken Access Control',
        'cwe': 'CWE-347: Improper Verification of Cryptographic Signature',
        'method': 'GET /api/profile',
        'payload': {'Authorization': 'Bearer eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJzdWIiOiJkZW1vIn0.TAMPERED'},
        'expected_status': [403, 401],
        'severity': 'CRITICAL',
        'description': 'Tampered JWT should be rejected immediately (signature validation)'
    },
    
    'expired_token_reuse': {
        'name': 'Expired Token Reuse',
        'owasp': 'A01: Broken Access Control',
        'cwe': 'CWE-347: Improper Verification of Cryptographic Signature',
        'method': 'GET /api/profile',
        'payload': {'Authorization': 'Bearer <expired_token>'},
        'expected_status': [401],
        'severity': 'HIGH',
        'description': 'Tokens past expiration time (exp claim) must be rejected'
    },
    
    'malformed_bearer_header': {
        'name': 'Malformed Bearer Header',
        'owasp': 'A03: Injection',
        'cwe': 'CWE-20: Improper Input Validation',
        'method': 'GET /api/users',
        'payload': {'Authorization': 'Bearer'},  # No token
        'expected_status': [400, 401],
        'severity': 'MEDIUM',
        'description': 'Incomplete Bearer header should fail with 400/401, not 500'
    },
    
    'sql_injection_attempt': {
        'name': 'SQL Injection via Query Parameter',
        'owasp': 'A03: Injection',
        'cwe': 'CWE-89: SQL Injection',
        'method': 'GET /api/users',
        'payload': {'offset': '1; DROP TABLE users; --'},
        'expected_status': [400, 403],
        'severity': 'CRITICAL',
        'description': 'SQL-like injection in parameters should be blocked (parametrized queries)'
    },
    
    'xff_header_spoof': {
        'name': 'X-Forwarded-For Header Spoofing',
        'owasp': 'A04: Insecure Deserialization',
        'cwe': 'CWE-923: Improper Restriction of Communication Channel',
        'method': 'GET /api/users',
        'payload': {'X-Forwarded-For': '203.0.113.5, 198.51.100.2'},
        'expected_status': [200, 429],  # May pass or be rate-limited
        'severity': 'MEDIUM',
        'description': 'X-Forwarded-For should be validated or rate-limited per real IP'
    },
    
    'host_header_injection': {
        'name': 'Host Header Injection (Cache Poisoning)',
        'owasp': 'A04: Insecure Deserialization',
        'cwe': 'CWE-923: Improper Restriction of Communication Channel',
        'method': 'GET /api/profile',
        'payload': {'Host': 'evil.com'},
        'expected_status': [400, 200],  # Should be ignored or rejected
        'severity': 'LOW',
        'description': 'Host header from attacker should not affect API logic'
    },
    
    'slow_request_attack': {
        'name': 'Slowloris: Slow Request Attack',
        'owasp': 'A04: Denial of Service',
        'cwe': 'CWE-770: Allocation of Resources Without Limits',
        'method': 'GET /api/users (with delayed body)',
        'payload': {},
        'expected_status': [408, 504],  # Timeout
        'severity': 'HIGH',
        'description': 'Incomplete requests should timeout/close after MAX_WAIT_TIME'
    }
}

def compute_security_metrics(raw_metrics):
    """
    Compute professional security metrics.
    
    Returns:
    --------
    dict with keys:
      - legitimate_error_pct: % of legitimate ops that failed
      - attack_blocked_pct: % of attack probes blocked
      - false_positive_rate: % of legitimate requests incorrectly blocked
      - overall_blocking_rate: aggregate across all vectors
      - security_posture: 'STRONG' | 'ADEQUATE' | 'WEAK'
    """
    
    legit_total = (raw_metrics['login_success'] + raw_metrics['login_fail'] +
                   raw_metrics['profile_success'] + raw_metrics['profile_fail'] +
                   raw_metrics['users_success'] + raw_metrics['users_fail'])
    
    legit_fail = (raw_metrics['login_fail'] + 
                  raw_metrics['profile_fail'] + 
                  raw_metrics['users_fail'])
    
    legitimate_error_pct = (legit_fail / legit_total * 100) if legit_total > 0 else 0
    
    attack_blocked_pct = (raw_metrics['attack_blocked'] / raw_metrics['attack_attempted'] * 100) \
        if raw_metrics['attack_attempted'] > 0 else 0
    
    # False positive rate: legitimate requests blocked (estimate from metadata)
    false_positive_rate = 0.0  # TODO: Extract from k6 custom metrics
    
    # Security posture classification
    if legitimate_error_pct > 5:
        security_posture = 'WEAK'  # Too many false positives
    elif attack_blocked_pct < 50:
        security_posture = 'WEAK'  # Too permissive
    elif legitimate_error_pct > 1:
        security_posture = 'ADEQUATE'
    elif attack_blocked_pct >= 90:
        security_posture = 'STRONG'
    else:
        security_posture = 'ADEQUATE'
    
    return {
        'legitimate_error_pct': legitimate_error_pct,
        'attack_blocked_pct': attack_blocked_pct,
        'false_positive_rate': false_positive_rate,
        'overall_blocking_rate': attack_blocked_pct,
        'security_posture': security_posture,
        'legitimate_total': legit_total,
        'legitimate_failed': legit_fail,
        'attack_total': raw_metrics['attack_attempted'],
        'attack_blocked': raw_metrics['attack_blocked'],
    }

if __name__ == '__main__':
    print("="*80)
    print("PROFESSIONAL ATTACK MODEL FOR SECURITY EVALUATION")
    print("="*80)
    print("\nAttack Vectors Defined:")
    for vec_name, vec_config in ATTACK_VECTORS.items():
        print(f"\n[{vec_config['severity']}] {vec_config['name']}")
        print(f"  OWASP: {vec_config['owasp']}")
        print(f"  CWE: {vec_config['cwe']}")
        print(f"  Description: {vec_config['description']}")
