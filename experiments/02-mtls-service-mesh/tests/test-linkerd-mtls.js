import http from 'k6/http';
import { check, sleep } from 'k6';

export const options = {
  vus: Number(__ENV.VUS || 5),
  duration: __ENV.DURATION || '60s',
  thresholds: {
    http_req_failed: ['rate<0.03'],
    http_req_duration: ['p(95)<1100'],
  },
};

const targetUrl = __ENV.TARGET_URL || 'http://localhost:30080/process';

export default function () {
  const payload = JSON.stringify({ mode: 'linkerd-mtls' });
  const params = { headers: { 'Content-Type': 'application/json' } };
  const res = http.post(targetUrl, payload, params);

  check(res, {
    'status 200': (r) => r.status === 200,
  });

  sleep(0.25);
}
