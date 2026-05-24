import http from 'k6/http';
import { check, sleep } from 'k6';
import { Trend } from 'k6/metrics';

export let options = {
    vus: Number(__ENV.VUS || 1),
    duration: __ENV.DURATION || '30s',
    insecureSkipTLSVerify: true,
    // Resolve realistic.local locally so TLS SNI matches the cert/Gateway
    // (required by Istio Gateway; harmless for nginx/kong).
    hosts: { 'realistic.local': '127.0.0.1' },
};

// Support both HTTP (C2/C3: localhost:300xx) and HTTPS (C1: localhost with ingress)
const API_BASE = __ENV.API_URL || 'http://localhost:30081';
const AUTH_BASE = __ENV.AUTH_URL || 'http://localhost:30084';
const IS_HTTPS = API_BASE.startsWith('https');
// For HTTPS (ingress), add /api prefix; for HTTP (NodePort), don't add prefix
const API_URL = IS_HTTPS ? `${API_BASE}/api` : `${API_BASE}`;
const AUTH_URL = IS_HTTPS ? `${AUTH_BASE}/auth` : `${AUTH_BASE}`;
const USERNAME = __ENV.USERNAME || 'demo';
const PASSWORD = __ENV.PASSWORD || 'demo123';
const HOST_HEADER = __ENV.HOST_HEADER || '';

const loginTrend = new Trend('op_login_duration_ms');
const createTrend = new Trend('op_create_duration_ms');
const readTrend = new Trend('op_read_duration_ms');
const updateTrend = new Trend('op_update_duration_ms');
const listTrend = new Trend('op_list_duration_ms');
const deleteTrend = new Trend('op_delete_duration_ms');

function baseHeaders(withAuth = false, token = null) {
    const headers = {
        'Content-Type': 'application/json',
    };
    if (HOST_HEADER) {
        headers.Host = HOST_HEADER;
    }
    if (withAuth && token) {
        headers.Authorization = `Bearer ${token}`;
    }
    return { headers };
}

function getToken() {
    const payload = JSON.stringify({ username: USERNAME, password: PASSWORD });
    const res = http.post(`${AUTH_URL}/login`, payload, baseHeaders(false));
    loginTrend.add(res.timings.duration);
    check(res, { 'login status 200': (r) => r.status === 200 });
    return res.json('access_token');
}

export default function () {
    const token = getToken();
    if (!token) {
        return;
    }

    const authHeaders = baseHeaders(true, token);

    const createPayload = JSON.stringify({
        name: `Producto_${__VU}_${__ITER}`,
        description: 'Producto de prueba',
        price: Math.floor(Math.random() * 1000) / 10 + 1,
    });
    let res = http.post(`${API_URL}/products`, createPayload, authHeaders);
    createTrend.add(res.timings.duration);
    check(res, { 'create product 200/201': (r) => r.status === 200 || r.status === 201 });
    
    // Extract product ID from response (handle multiple response formats)
    let product = res.json();
    if (!product) {
        return;
    }
    let productId = product.id || (product.data && product.data.id);
    if (!productId) {
        return;
    }

    res = http.get(`${API_URL}/products/${productId}`, authHeaders);
    readTrend.add(res.timings.duration);
    check(res, { 'get product 200': (r) => r.status === 200 });

    const updatePayload = JSON.stringify({
        name: `Producto_${__VU}_${__ITER}_upd`,
        description: 'Producto actualizado',
        price: Math.floor(Math.random() * 1000) / 10 + 1,
    });
    res = http.put(`${API_URL}/products/${productId}`, updatePayload, authHeaders);
    updateTrend.add(res.timings.duration);
    check(res, { 'update product 200': (r) => r.status === 200 });

    res = http.get(`${API_URL}/products`, authHeaders);
    listTrend.add(res.timings.duration);
    check(res, { 'list products 200': (r) => r.status === 200 });

    res = http.del(`${API_URL}/products/${productId}`, null, authHeaders);
    deleteTrend.add(res.timings.duration);
    check(res, { 'delete product 200': (r) => r.status === 200 });

    sleep(1);
}
