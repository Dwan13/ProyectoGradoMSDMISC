// k6 attack profile — SQL Injection (OWASP A03:2021 / API8:2023, CWE-89).
// Mismo flujo y MISMAS 6 métricas que crud_products.js
// (avg_ms, p95_ms, err_pct, rps, cpu_mcores, mem_mib via runner Python).
// Inyecta payloads SQLi rotativos en los campos controlados por el usuario:
// name/description (body) y search/id (query/path). Login siempre legítimo:
// el escenario realista es un USUARIO AUTENTICADO que intenta inyección
// (token robado, insider, account takeover).
import http from 'k6/http';
import { check, sleep } from 'k6';
import { Counter, Trend } from 'k6/metrics';

export let options = {
    vus: Number(__ENV.VUS || 1),
    duration: __ENV.DURATION || '30s',
    insecureSkipTLSVerify: true,
    hosts: { 'realistic.local': '127.0.0.1' },
};

const API_BASE = __ENV.API_URL || 'http://localhost:30081';
const AUTH_BASE = __ENV.AUTH_URL || 'http://localhost:30084';
const IS_HTTPS = API_BASE.startsWith('https');
const API_URL = IS_HTTPS ? `${API_BASE}/api` : `${API_BASE}`;
const AUTH_URL = IS_HTTPS ? `${AUTH_BASE}/auth` : `${AUTH_BASE}`;
const USERNAME = __ENV.USERNAME || 'demo';
const PASSWORD = __ENV.PASSWORD || 'demo123';
const HOST_HEADER = __ENV.HOST_HEADER || '';

// Mismas Trends que crud_products.js → el runner Python las recoge sin cambios.
const loginTrend = new Trend('op_login_duration_ms');
const createTrend = new Trend('op_create_duration_ms');
const readTrend = new Trend('op_read_duration_ms');
const updateTrend = new Trend('op_update_duration_ms');
const listTrend = new Trend('op_list_duration_ms');
const deleteTrend = new Trend('op_delete_duration_ms');

// C1 mide mitigación SQLi a nivel gateway. Solo contamos probes que en baseline
// deberían pasar normalmente y en WAF deberían bloquearse de forma explícita.
const sqliAttemptsTotal = new Counter('sqli_attempts_total');
const sqliBlockedTotal = new Counter('sqli_blocked_total');
const sqliLeakedTotal = new Counter('sqli_leaked_total');
const sqliOtherTotal = new Counter('sqli_other_total');

// Payloads SQLi — subset OWASP CRS REQUEST-942 (mismas categorías que el WAF Lua).
// 12 patrones lógicos rotativos; cubren UNION/tautology/stacked/time-based/
// error-based/file-ops/schema-enum/MSSQL-stored-proc.
const SQLI_PAYLOADS = [
    "' OR 1=1 --",                                     // tautología numérica + comentario
    "' OR 'a'='a' --",                                 // tautología string
    "1; DROP TABLE products --",                       // stacked DDL
    "' UNION SELECT username,password FROM users --",  // union select
    "' UNION ALL SELECT NULL,NULL,NULL --",            // union all
    "1' AND SLEEP(5) --",                              // time-based MySQL
    "1' AND pg_sleep(5) --",                           // time-based PostgreSQL
    "'; WAITFOR DELAY '0:0:5' --",                     // time-based MSSQL
    "1' AND extractvalue(1,concat(0x7e,version())) --",// error-based
    "' UNION SELECT load_file('/etc/passwd') --",      // file ops
    "' UNION SELECT table_name FROM information_schema.tables --", // schema enum
    "1; EXEC xp_cmdshell('whoami') --",                // MSSQL stored proc
];

function pickPayload() {
    return SQLI_PAYLOADS[(__ITER + __VU) % SQLI_PAYLOADS.length];
}

function baseHeaders(withAuth = false, token = null) {
    const headers = { 'Content-Type': 'application/json' };
    if (HOST_HEADER) headers.Host = HOST_HEADER;
    if (withAuth && token) headers.Authorization = `Bearer ${token}`;
    return { headers };
}

function getToken() {
    const payload = JSON.stringify({ username: USERNAME, password: PASSWORD });
    const res = http.post(`${AUTH_URL}/login`, payload, baseHeaders(false));
    loginTrend.add(res.timings.duration);
    check(res, { 'login status 200': (r) => r.status === 200 });
    return res.json('access_token');
}

function recordSqliOutcome(res) {
    sqliAttemptsTotal.add(1);
    if (res.status === 400 || res.status === 403) {
        sqliBlockedTotal.add(1);
    } else if (res.status >= 200 && res.status < 300) {
        sqliLeakedTotal.add(1);
    } else {
        sqliOtherTotal.add(1);
    }
}

export default function () {
    const token = getToken();
    if (!token) return;

    const authHeaders = baseHeaders(true, token);
    const sqli = pickPayload();
    const sqliEnc = encodeURIComponent(sqli);

    // CREATE — inyección en name + description
    const createPayload = JSON.stringify({
        name: `Producto_${sqli}`,
        description: `desc ${sqli}`,
        price: 1.99,
    });
    let res = http.post(`${API_URL}/products`, createPayload, authHeaders);
    createTrend.add(res.timings.duration);
    recordSqliOutcome(res);
    // El check pasa si el sistema RESPONDIÓ (independiente de bloqueo).
    // err_pct (http_req_failed) ya distinguirá: 4xx WAF vs 2xx pass-through.
    check(res, { 'create handled': (r) => r.status >= 200 && r.status < 600 });

    let productId = null;
    if (res.status >= 200 && res.status < 300) {
        try {
            const body = res.json();
            productId = body.id || (body.data && body.data.id);
        } catch (e) { productId = null; }
    }

    // READ — inyección en path
    res = http.get(`${API_URL}/products/${sqliEnc}`, authHeaders);
    readTrend.add(res.timings.duration);
    check(res, { 'read handled': (r) => r.status >= 200 && r.status < 600 });

    // UPDATE — inyección en body sobre id válido si existe, sino 1
    const updateId = productId || 1;
    const updatePayload = JSON.stringify({
        name: `Upd_${sqli}`,
        description: `upd ${sqli}`,
        price: 2.99,
    });
    res = http.put(`${API_URL}/products/${updateId}`, updatePayload, authHeaders);
    updateTrend.add(res.timings.duration);
    check(res, { 'update handled': (r) => r.status >= 200 && r.status < 600 });

    // LIST — inyección en query string
    res = http.get(`${API_URL}/products?search=${sqliEnc}`, authHeaders);
    listTrend.add(res.timings.duration);
    recordSqliOutcome(res);
    check(res, { 'list handled': (r) => r.status >= 200 && r.status < 600 });

    // DELETE — inyección en path
    res = http.del(`${API_URL}/products/${sqliEnc}`, null, authHeaders);
    deleteTrend.add(res.timings.duration);
    check(res, { 'delete handled': (r) => r.status >= 200 && r.status < 600 });

    sleep(1);
}
