import http from 'k6/http';
import { check, sleep } from 'k6';

const AUTH_BASE = __ENV.AUTH_BASE || 'http://127.0.0.1:32184';
const API_BASE = __ENV.API_BASE || 'http://127.0.0.1:32181';
const VUS = parseInt(__ENV.VUS || '1');
const DURATION = __ENV.DURATION || '60s';
const THINK_TIME = parseFloat(__ENV.THINK_TIME || '0.1');

export const options = {
  vus: VUS,
  duration: DURATION,
  thresholds: {
    http_req_failed: ['rate<0.05'],
    http_req_duration: ['p(95)<700'],
  },
};

function login() {
  const res = http.post(`${AUTH_BASE}/login`, JSON.stringify({ username: 'demo', password: 'demo123' }), {
    headers: { 'Content-Type': 'application/json' },
  });
  check(res, { 'login 200': (r) => r.status === 200, 'login token': (r) => !!r.json('access_token') });
  return res.json('access_token');
}

export default function () {
  const token = login();
  if (!token) {
    sleep(1);
    return;
  }

  const username = `s4_${__VU}_${Date.now()}_${Math.floor(Math.random() * 100000)}`;
  const createRes = http.post(`${API_BASE}/users`, JSON.stringify({ username, email: `${username}@example.com` }), {
    headers: { 'Content-Type': 'application/json', Authorization: `Bearer ${token}` },
  });
  check(createRes, { 'create 200/201': (r) => r.status === 200 || r.status === 201 });

  const listRes = http.get(`${API_BASE}/users?limit=20000`, {
    headers: { Authorization: `Bearer ${token}` },
  });
  check(listRes, {
    'list 200': (r) => r.status === 200,
    'list contains username': (r) => r.body && r.body.indexOf(username) !== -1,
  });

  sleep(THINK_TIME);
}
