import http from 'k6/http';
import { check, sleep } from 'k6';

export const options = {
  vus: Number(__ENV.VUS || 10),
  duration: __ENV.DURATION || '60s',
  thresholds: {
    http_req_duration: ['p(95)<1200'],
    http_req_failed: ['rate<0.05'],
  },
};

const targetUrl = __ENV.TARGET_URL || 'http://localhost:30200/process';

export default function () {
  const payload = JSON.stringify({ mode: 'rl-baseline' });
  const res = http.post(targetUrl, payload, { headers: { 'Content-Type': 'application/json' } });
  check(res, { 'status 200': (r) => r.status === 200 });
  sleep(0.1);
}
