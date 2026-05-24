import http from 'k6/http';
import { check, group } from 'k6';
import { Counter, Trend } from 'k6/metrics';

/**
 * S6 RIGOROUS: XXE (XML External Entity) Injection Script
 * 
 * Purpose: Inject XXE payloads and measure block rate
 * Defended By: C1 (API Gateway - XML validation)
 * 
 * Configuration:
 *   ENDPOINT: http://api.svc.cluster.local:5000
 *   VUS: 3
 *   DURATION: 30s
 * 
 * Metrics:
 *   xxe_sent_total: Total XXE attempts
 *   xxe_blocked_total: Requests with 400/403 status
 *   xxe_leaked_total: Requests with 200 status (LEAKED)
 */

const xxe_sent_total = new Counter('xxe_sent_total');
const xxe_blocked_total = new Counter('xxe_blocked_total');
const xxe_leaked_total = new Counter('xxe_leaked_total');
const xxe_response_time = new Trend('xxe_response_time');

// XXE payloads - OWASP documented
const XXE_PAYLOADS = [
  `<?xml version="1.0"?><!DOCTYPE foo [<!ENTITY xxe SYSTEM "file:///etc/passwd">]><data>&xxe;</data>`,
  `<?xml version="1.0"?><!DOCTYPE root [<!ENTITY xxe SYSTEM "file:///windows/win.ini">]><root>&xxe;</root>`,
  `<?xml version="1.0"?><!DOCTYPE root [<!ELEMENT root ANY><!ENTITY xxe SYSTEM "file:///dev/null">]><root>&xxe;</root>`,
  `<?xml version="1.0" encoding="UTF-8"?><!DOCTYPE svg [<!ENTITY xxe SYSTEM "file:///etc/shadow">]><svg>&xxe;</svg>`,
  `<?xml version="1.0"?><!DOCTYPE data [<!ENTITY % xxe SYSTEM "file:///etc/hosts">%xxe;]><data/>`,
];

export const options = {
  vus: __ENV.VUS || 3,
  duration: __ENV.DURATION || '30s',
};

export default function () {
  const endpoint = __ENV.ENDPOINT || 'http://localhost:5000';
  const targetPath = '/api/data';
  
  group('XXE Injection Attacks', () => {
    const payload = XXE_PAYLOADS[Math.floor(Math.random() * XXE_PAYLOADS.length)];
    const url = `${endpoint}${targetPath}`;
    
    xxe_sent_total.add(1);
    
    const response = http.post(url, payload, {
      headers: {
        'Content-Type': 'application/xml',
        'User-Agent': 'k6-attacker/xxe',
      },
      tags: {
        attack_type: 'xxe',
        endpoint: targetPath,
        phase: 'under_attack',
      },
      timeout: '5s',
    });
    
    xxe_response_time.add(response.timings.duration, { status: response.status });
    
    if (response.status === 400 || response.status === 403) {
      xxe_blocked_total.add(1);
      check(response, {
        'XXE blocked with 400/403': (r) => r.status === 400 || r.status === 403,
      });
    } else if (response.status === 200) {
      xxe_leaked_total.add(1);
      check(response, {
        'XXE LEAKED (200 OK) - CONTROL FAILED': (r) => false,
      });
    }
  });
}

export function handleSummary(data) {
  const summary = {
    timestamp: new Date().toISOString(),
    attack_type: 'xxe',
    summary_counters: {
      xxe_sent_total: data.metrics.xxe_sent_total ? data.metrics.xxe_sent_total.value : 0,
      xxe_blocked_total: data.metrics.xxe_blocked_total ? data.metrics.xxe_blocked_total.value : 0,
      xxe_leaked_total: data.metrics.xxe_leaked_total ? data.metrics.xxe_leaked_total.value : 0,
    },
  };
  console.log(JSON.stringify(summary, null, 2));
  return { stdout: JSON.stringify(summary, null, 2) };
}
