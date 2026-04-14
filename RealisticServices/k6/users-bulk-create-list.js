import http from 'k6/http';
import { check, sleep } from 'k6';
import { Counter, Trend } from 'k6/metrics';

const AUTH_BASE = __ENV.AUTH_BASE || 'http://127.0.0.1:18082';
const API_BASE = __ENV.API_BASE || 'http://127.0.0.1:18081';
const CREATE_SLEEP_MS = Number(__ENV.CREATE_SLEEP_MS || '50');
const LIST_SLEEP_MS = Number(__ENV.LIST_SLEEP_MS || '100');
const LIST_LIMIT = Number(__ENV.LIST_LIMIT || '100');

const createdUsers = new Counter('users_created_total');
const listedUsers = new Counter('users_listed_total');
const createDuration = new Trend('users_create_duration', true);
const listDuration = new Trend('users_list_duration', true);

export const options = {
  scenarios: {
    create_users: {
      executor: 'constant-vus',
      exec: 'createUsers',
      vus: Number(__ENV.CREATE_VUS || '15'),
      duration: __ENV.CREATE_DURATION || '45s',
    },
    list_users: {
      executor: 'constant-vus',
      exec: 'listUsers',
      startTime: __ENV.LIST_START || '50s',
      vus: Number(__ENV.LIST_VUS || '5'),
      duration: __ENV.LIST_DURATION || '25s',
    },
  },
  thresholds: {
    http_req_failed: ['rate<0.10'],
    checks: ['rate>0.90'],
    users_create_duration: ['p(95)<1000'],
    users_list_duration: ['p(95)<1000'],
  },
};

export function setup() {
  const loginPayload = JSON.stringify({ username: 'demo', password: 'demo123' });
  const loginRes = http.post(`${AUTH_BASE}/login`, loginPayload, {
    headers: { 'Content-Type': 'application/json' },
  });

  check(loginRes, {
    'setup login status 200': (r) => r.status === 200,
    'setup login token exists': (r) => !!r.json('access_token'),
  });

  const token = loginRes.status === 200 ? loginRes.json('access_token') : null;
  if (!token) {
    throw new Error('Unable to authenticate in setup()');
  }

  return { token };
}

export function createUsers(data) {
  const unique = `${__VU}-${__ITER}-${Date.now()}`;
  const payload = JSON.stringify({
    username: `load_user_${unique}`,
    email: `load_user_${unique}@example.com`,
  });

  const res = http.post(`${API_BASE}/users`, payload, {
    headers: {
      'Content-Type': 'application/json',
      Authorization: `Bearer ${data.token}`,
    },
  });

  createDuration.add(res.timings.duration);

  const ok = check(res, {
    'create status 200 or 409': (r) => r.status === 200 || r.status === 409,
    'create has body': (r) => !!r.body,
  });

  if (ok && res.status === 200) {
    createdUsers.add(1);
  }

  sleep(CREATE_SLEEP_MS / 1000);
}

export function listUsers(data) {
  const offset = Math.floor(Math.random() * 50);
  const res = http.get(`${API_BASE}/users?limit=${LIST_LIMIT}&offset=${offset}`, {
    headers: {
      Authorization: `Bearer ${data.token}`,
    },
  });

  listDuration.add(res.timings.duration);

  const ok = check(res, {
    'list status 200': (r) => r.status === 200,
    'list has users array': (r) => Array.isArray(r.json('users')),
  });

  if (ok && res.status === 200) {
    const count = Number(res.json('count') || 0);
    if (count > 0) {
      listedUsers.add(count);
    }
  }

  sleep(LIST_SLEEP_MS / 1000);
}
