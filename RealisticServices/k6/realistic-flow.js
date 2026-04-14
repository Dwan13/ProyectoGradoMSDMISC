import http from 'k6/http';
import { check, sleep } from 'k6';

const AUTH_BASE = __ENV.AUTH_BASE || 'http://127.0.0.1:18082';
const API_BASE = __ENV.API_BASE || 'http://127.0.0.1:30081';

export const options = {
  scenarios: {
    realistic_flow: {
      executor: 'ramping-vus',
      stages: [
        { duration: '20s', target: 10 },
        { duration: '40s', target: 25 },
        { duration: '20s', target: 0 },
      ],
      gracefulRampDown: '10s',
    },
  },
  thresholds: {
    http_req_failed: ['rate<0.05'],
    http_req_duration: ['p(95)<700'],
    checks: ['rate>0.95'],
  },
};

function login() {
  const payload = JSON.stringify({ username: 'demo', password: 'demo123' });
  const params = { headers: { 'Content-Type': 'application/json' } };
  const res = http.post(`${AUTH_BASE}/login`, payload, params);
  const hasToken = res && res.status === 200 && res.body && !!res.json('access_token');

  check(res, {
    'login status 200': (r) => r.status === 200,
    'login has token': () => hasToken,
  });

  return hasToken ? res.json('access_token') : null;
}

export default function () {
  const token = login();
  if (!token) {
    sleep(1);
    return;
  }

  const profileRes = http.get(`${API_BASE}/profile?user_id=1`, {
    headers: { Authorization: `Bearer ${token}` },
  });

  const hasProfileUser = profileRes && profileRes.status === 200 && profileRes.body && !!profileRes.json('user.username');

  check(profileRes, {
    'profile status 200': (r) => r.status === 200,
    'profile has user': () => hasProfileUser,
  });

  sleep(0.5);
}
