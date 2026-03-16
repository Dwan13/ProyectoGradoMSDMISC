import http from 'k6/http';
import { check, sleep } from 'k6';
import { Counter } from 'k6/metrics';

const rateLimited = new Counter('rate_limited_responses');

export const options = {
  vus: Number(__ENV.VUS || 10),
  duration: __ENV.DURATION || '60s',
  thresholds: {
    http_req_duration: ['p(95)<1500'],
    http_req_failed: ['rate<0.30'],
  },
};

const targetUrl = __ENV.TARGET_URL || 'http://localhost:30080/rl-s0/process';

export default function () {
  const payload = JSON.stringify({ mode: 'rl-enabled' });
  const res = http.post(targetUrl, payload, { headers: { 'Content-Type': 'application/json' } });

  if (res.status === 429 || res.status === 503) {
    rateLimited.add(1);
  }

  check(res, {
    'status accepted': (r) => [200, 429, 503].includes(r.status),
  });

  sleep(0.1);
}
