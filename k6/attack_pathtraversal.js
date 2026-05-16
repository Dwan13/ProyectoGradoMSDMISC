import http from 'k6/http';
import { check, group } from 'k6';
import { Counter, Trend } from 'k6/metrics';

/**
 * S6 RIGOROUS: Path Traversal Attack Script
 * 
 * Purpose: Inject path traversal payloads and measure block rate
 * Defended By: C1 (API Gateway - URL validation)
 * 
 * Configuration:
 *   ENDPOINT: http://api.svc.cluster.local:5000
 *   VUS: 3
 *   DURATION: 30s
 * 
 * Metrics:
 *   pathtraversal_sent_total: Total path traversal attempts
 *   pathtraversal_blocked_total: Blocked (400/403)
 *   pathtraversal_leaked_total: Leaked (200)
 */

const pathtraversal_sent_total = new Counter('pathtraversal_sent_total');
const pathtraversal_blocked_total = new Counter('pathtraversal_blocked_total');
const pathtraversal_leaked_total = new Counter('pathtraversal_leaked_total');
const pathtraversal_response_time = new Trend('pathtraversal_response_time');

// Path traversal payloads - multiple encoding/bypass attempts
const PATHTRAVERSAL_PAYLOADS = [
  '../../etc/passwd',
  '..\\..\\windows\\system32\\config\\sam',
  '....//....//etc/passwd',
  '..%252f..%252fetc%252fpasswd',
  '..%c0%af..%c0%afetc%c0%afpasswd',
  '......//......//etc/passwd',
  '..%00/..%00/etc/passwd',
  '....\\....\\etc\\passwd',
  '/%2e%2e/%2e%2e/etc/passwd',
  '///..///..//etc/passwd',
];

export const options = {
  vus: __ENV.VUS || 3,
  duration: __ENV.DURATION || '30s',
};

export default function () {
  const endpoint = __ENV.ENDPOINT || 'http://localhost:5000';
  const targetPath = '/api/file';
  
  group('Path Traversal Attacks', () => {
    const payload = PATHTRAVERSAL_PAYLOADS[Math.floor(Math.random() * PATHTRAVERSAL_PAYLOADS.length)];
    const url = `${endpoint}${targetPath}?path=${encodeURIComponent(payload)}`;
    
    pathtraversal_sent_total.add(1);
    
    const response = http.get(url, {
      headers: {
        'User-Agent': 'k6-attacker/pathtraversal',
        'Accept': 'application/json',
      },
      tags: {
        attack_type: 'pathtraversal',
        endpoint: targetPath,
        phase: 'under_attack',
      },
      timeout: '5s',
    });
    
    pathtraversal_response_time.add(response.timings.duration, { status: response.status });
    
    if (response.status === 400 || response.status === 403) {
      pathtraversal_blocked_total.add(1);
      check(response, {
        'Path traversal blocked with 400/403': (r) => r.status === 400 || r.status === 403,
      });
    } else if (response.status === 200) {
      pathtraversal_leaked_total.add(1);
      check(response, {
        'Path traversal LEAKED (200 OK) - CONTROL FAILED': (r) => false,
      });
    }
  });
}

export function handleSummary(data) {
  const summary = {
    timestamp: new Date().toISOString(),
    attack_type: 'pathtraversal',
    summary_counters: {
      pathtraversal_sent_total: data.metrics.pathtraversal_sent_total ? data.metrics.pathtraversal_sent_total.value : 0,
      pathtraversal_blocked_total: data.metrics.pathtraversal_blocked_total ? data.metrics.pathtraversal_blocked_total.value : 0,
      pathtraversal_leaked_total: data.metrics.pathtraversal_leaked_total ? data.metrics.pathtraversal_leaked_total.value : 0,
    },
  };
  console.log(JSON.stringify(summary, null, 2));
  return { stdout: JSON.stringify(summary, null, 2) };
}
