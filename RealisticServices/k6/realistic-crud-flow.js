// realistic-crud-flow.js
// Flujo k6 con CRUD completo sobre /products + login + profile.
// Variables de entorno:
//   AUTH_BASE    base URL para /login (ej: https://realistic.local:32167/auth)
//   API_BASE     base URL para /products, /profile (ej: https://realistic.local:32167/api)
//   HOST_HEADER  (opcional) header Host a inyectar
//   RESOLVE      (opcional) "host:ip" para forzar resolución (k6 hosts map)
//   K6_INSECURE_SKIP_TLS_VERIFY  default true
import http from 'k6/http';
import { check, sleep } from 'k6';
import { Counter, Trend } from 'k6/metrics';

const AUTH_BASE = (__ENV.AUTH_BASE || 'https://localhost/auth').replace(/\/?$/, '');
const API_BASE = (__ENV.API_BASE || 'https://localhost/api').replace(/\/?$/, '');
const INSECURE_TLS = ((__ENV.K6_INSECURE_SKIP_TLS_VERIFY || 'true').toLowerCase() === 'true');
const HOST_HEADER = __ENV.HOST_HEADER || '';

// RESOLVE="host:ip" → mapea host→ip en k6 (equivalente a curl --resolve)
const hostsMap = {};
if (__ENV.RESOLVE) {
  for (const entry of __ENV.RESOLVE.split(',')) {
    const [h, ip] = entry.split(':');
    if (h && ip) hostsMap[h.trim()] = ip.trim();
  }
}

// Métricas por operación CRUD
const loginOk = new Counter('login_success_total');
const loginFail = new Counter('login_fail_total');
const createOk = new Counter('crud_create_success_total');
const createFail = new Counter('crud_create_fail_total');
const readOk = new Counter('crud_read_success_total');
const readFail = new Counter('crud_read_fail_total');
const updateOk = new Counter('crud_update_success_total');
const updateFail = new Counter('crud_update_fail_total');
const deleteOk = new Counter('crud_delete_success_total');
const deleteFail = new Counter('crud_delete_fail_total');
const listOk = new Counter('crud_list_success_total');
const listFail = new Counter('crud_list_fail_total');

const createLatency = new Trend('crud_create_latency_ms');
const readLatency = new Trend('crud_read_latency_ms');
const updateLatency = new Trend('crud_update_latency_ms');
const deleteLatency = new Trend('crud_delete_latency_ms');
const listLatency = new Trend('crud_list_latency_ms');

export const options = {
  insecureSkipTLSVerify: INSECURE_TLS,
  hosts: hostsMap,
  thresholds: {
    http_req_failed: ['rate<0.05'],
    http_req_duration: ['p(95)<700'],
    checks: ['rate>0.95'],
    crud_create_success_total: ['count>0'],
    crud_read_success_total: ['count>0'],
    crud_update_success_total: ['count>0'],
    crud_delete_success_total: ['count>0'],
  },
};

function hdr(extra) {
  const h = { 'Content-Type': 'application/json', ...(extra || {}) };
  if (HOST_HEADER) h.Host = HOST_HEADER;
  return h;
}

function login() {
  const res = http.post(`${AUTH_BASE}/login`,
    JSON.stringify({ username: 'demo', password: 'demo123' }),
    { headers: hdr(), tags: { op: 'login' } });
  const ok = res.status === 200 && !!res.json('access_token');
  check(res, { 'login 200': (r) => r.status === 200, 'login has token': () => ok });
  ok ? loginOk.add(1) : loginFail.add(1);
  return ok ? res.json('access_token') : null;
}

function createProduct(token, vu, iter) {
  const body = JSON.stringify({
    name: `k6-prod-vu${vu}-it${iter}-${Date.now()}`,
    description: 'created by k6 load test',
    price: Math.round(Math.random() * 10000) / 100,
  });
  const res = http.post(`${API_BASE}/products`, body,
    { headers: hdr({ Authorization: `Bearer ${token}` }), tags: { op: 'create' } });
  const ok = res.status === 200 && !!res.json('data.id');
  check(res, { 'create 200': (r) => r.status === 200, 'create has id': () => ok });
  createLatency.add(res.timings.duration);
  if (ok) { createOk.add(1); return res.json('data.id'); }
  createFail.add(1);
  return null;
}

function readProduct(token, id) {
  const res = http.get(`${API_BASE}/products/${id}`,
    { headers: hdr({ Authorization: `Bearer ${token}` }), tags: { op: 'read' } });
  const ok = res.status === 200;
  check(res, { 'read 200': (r) => r.status === 200 });
  readLatency.add(res.timings.duration);
  ok ? readOk.add(1) : readFail.add(1);
}

function updateProduct(token, id) {
  const body = JSON.stringify({
    name: `k6-prod-${id}-upd`,
    description: 'updated',
    price: 99.99,
  });
  const res = http.put(`${API_BASE}/products/${id}`, body,
    { headers: hdr({ Authorization: `Bearer ${token}` }), tags: { op: 'update' } });
  const ok = res.status === 200;
  check(res, { 'update 200': (r) => r.status === 200 });
  updateLatency.add(res.timings.duration);
  ok ? updateOk.add(1) : updateFail.add(1);
}

function deleteProduct(token, id) {
  const res = http.del(`${API_BASE}/products/${id}`, null,
    { headers: hdr({ Authorization: `Bearer ${token}` }), tags: { op: 'delete' } });
  const ok = res.status === 200 || res.status === 204;
  check(res, { 'delete 2xx': (r) => ok });
  deleteLatency.add(res.timings.duration);
  ok ? deleteOk.add(1) : deleteFail.add(1);
}

function listProducts(token) {
  const res = http.get(`${API_BASE}/products?limit=20&offset=0`,
    { headers: hdr({ Authorization: `Bearer ${token}` }), tags: { op: 'list' } });
  const ok = res.status === 200;
  check(res, { 'list 200': (r) => r.status === 200 });
  listLatency.add(res.timings.duration);
  ok ? listOk.add(1) : listFail.add(1);
}

export default function () {
  const token = login();
  if (!token) { sleep(1); return; }

  // Flujo CRUD completo por iteración
  listProducts(token);
  const id = createProduct(token, __VU, __ITER);
  if (id !== null) {
    readProduct(token, id);
    updateProduct(token, id);
    readProduct(token, id);
    deleteProduct(token, id);
  }
  sleep(0.3);
}
