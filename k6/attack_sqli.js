import http from 'k6/http';
import { check, group } from 'k6';
import { Counter, Trend } from 'k6/metrics';
import encoding from 'k6/encoding';

/**
 * S6 RIGOROUS: SQL Injection Attack Script
 * 
 * Purpose: Inject SQL injection payloads and measure block rate
 * Defended By: C1 (API Gateway - Kong WAF)
 * 
 * Configuration:
 *   ENDPOINT: http://api.svc.cluster.local:5000
 *   PAYLOAD_FILE: attack_vectors/sqli_payloads.txt
 *   VUS: 3 (attacks only, separate from legitimate traffic)
 *   DURATION: 30s
 * 
 * Metrics:
 *   sqli_sent_total: Total SQL injection attempts
 *   sqli_blocked_total: Requests with 403/400 status (blocked)
 *   sqli_leaked_total: Requests with 200 status (LEAKED - control failed)
 *   sqli_response_time: Response time distribution
 */

// Custom metrics
const sqli_sent_total = new Counter('sqli_sent_total');
const sqli_blocked_total = new Counter('sqli_blocked_total');
const sqli_leaked_total = new Counter('sqli_leaked_total');
const sqli_response_time = new Trend('sqli_response_time');
const sqli_response_status = new Counter('sqli_response_status');

// Payload library - OWASP documented SQLi payloads
const SQLI_PAYLOADS = [
  "' OR '1'='1' --",
  "1; DROP TABLE users; --",
  "' UNION SELECT NULL, NULL --",
  "admin' --",
  "1' AND '1'='1",
  "' OR 1=1 --",
  "' OR 'x'='x' --",
  "1'; DELETE FROM users; --",
  "'; EXEC sp_executesql; --",
  "' OR 'a'='a' /*",
];

export const options = {
  vus: __ENV.VUS || 3,
  duration: __ENV.DURATION || '30s',
  thresholds: {
    // No thresholds; we're measuring, not enforcing
  },
};

export default function () {
  const endpoint = __ENV.ENDPOINT || 'http://localhost:5000';
  const targetPath = '/api/users';
  
  group('SQL Injection Attacks', () => {
    // Cycle through payloads
    const payload = SQLI_PAYLOADS[Math.floor(Math.random() * SQLI_PAYLOADS.length)];
    const url = `${endpoint}${targetPath}?offset=${encodeURIComponent(payload)}&limit=10`;
    
    // Record that we sent an attack
    sqli_sent_total.add(1);
    
    // Send the attack
    const response = http.get(url, {
      tags: {
        attack_type: 'sqli',
        endpoint: targetPath,
        phase: 'under_attack',
      },
      headers: {
        'User-Agent': 'k6-attacker/sqli',
        'Accept': 'application/json',
      },
      timeout: '5s',
    });
    
    // Record response status
    sqli_response_status.add(1, { status: response.status });
    sqli_response_time.add(response.timings.duration, { status: response.status });
    
    // Classify: blocked (403/400) or leaked (200)
    if (response.status === 403 || response.status === 400) {
      sqli_blocked_total.add(1);
      check(response, {
        'SQLi blocked with 403/400': (r) => r.status === 403 || r.status === 400,
      });
    } else if (response.status === 200) {
      // This is a FAILURE - attack leaked through
      sqli_leaked_total.add(1);
      check(response, {
        'SQLi LEAKED (200 OK) - CONTROL FAILED': (r) => false, // Always fail if here
      });
    } else {
      // Other status (401, 500, timeout, etc.)
      check(response, {
        'Other status': (r) => true, // Just log it
      });
    }
  });
}

export function handleSummary(data) {
  // Output summary to file for post-processing
  const summary = {
    timestamp: new Date().toISOString(),
    attack_type: 'sqli',
    metrics: data.metrics,
    summary_counters: {
      sqli_sent_total: data.metrics.sqli_sent_total ? data.metrics.sqli_sent_total.value : 0,
      sqli_blocked_total: data.metrics.sqli_blocked_total ? data.metrics.sqli_blocked_total.value : 0,
      sqli_leaked_total: data.metrics.sqli_leaked_total ? data.metrics.sqli_leaked_total.value : 0,
    },
  };
  
  console.log(JSON.stringify(summary, null, 2));
  return { stdout: JSON.stringify(summary, null, 2) };
}
