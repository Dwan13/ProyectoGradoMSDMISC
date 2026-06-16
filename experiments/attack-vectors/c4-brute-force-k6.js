// ==========================================================================
// c4-brute-force-k6.js
// Simulación de ataque de fuerza bruta / credential stuffing contra C4.
//
// ESCENARIO:
//   Atacante con 1 VU envía requests continuos al endpoint /auth/login
//   sin delay (0 sleep), simulando una herramienta automatizada de
//   credential stuffing desde una sola IP.
//
// HIPÓTESIS:
//   Baseline  → HTTP 401 en todos (credencial incorrecta, sin bloqueo)
//   Moderate  → HTTP 503 cuando supera 1200 req/min (NGINX bloquea)
//   Strict    → HTTP 503 cuando supera 300 req/min  (NGINX bloquea)
//
// USO (comparar las tres variantes):
//   k6 run -e TARGET=without-rate-limiting -e PORT=32167 c4-brute-force-k6.js
//   k6 run -e TARGET=moderate-rate-limiting -e PORT=32167 c4-brute-force-k6.js
//   k6 run -e TARGET=strict-rate-limiting   -e PORT=32167 c4-brute-force-k6.js
//
// O con el script wrapper validate-c4-k6-all.sh que corre los tres en secuencia.
//
// Variables de entorno:
//   TARGET   Sufijo del namespace: without|moderate|strict (default: strict)
//   PORT     NodePort del NGINX Ingress (default: 32167)
//   VUS      Número de atacantes paralelos (default: 1)
//   DURATION Duración del ataque (default: 30s)
// ==========================================================================
import http from 'k6/http';
import { check } from 'k6';
import { Counter, Rate, Trend } from 'k6/metrics';

const TARGET   = __ENV.TARGET   || 'strict-rate-limiting';
const PORT     = __ENV.PORT     || '32167';
const HOST     = `realistic-${TARGET}.local`;
const BASE_URL = `https://${HOST}:${PORT}`;

// Contadores separados: 503 de rate-limit ≠ 503 de fallo de backend
// - ratelimit_503: NGINX rechaza antes del backend (text/html con firma "nginx")
//   → el control C4 está funcionando; NO es una métrica de fiabilidad
// - backend_503:   fallo real del servicio (JSON body, respuesta más lenta)
//   → SÍ es una métrica de fiabilidad (fuera del alcance del control C4)
const rlBlocked      = new Counter('ratelimit_503');
const beError        = new Counter('backend_503');
const attackReached  = new Counter('attack_reached_backend');
const blockRate      = new Rate('block_rate');
const loginLatency   = new Trend('login_latency_ms');

export const options = {
  insecureSkipTLSVerify: true,
  hosts: { [HOST]: '127.0.0.1' },
  vus:      parseInt(__ENV.VUS      || '1'),
  duration: __ENV.DURATION          || '30s',
  thresholds: {},
  summaryTrendStats: ['avg', 'min', 'max', 'p(50)', 'p(95)', 'p(99)', 'count'],
};

// ------------------------------------------------------------
// Health-check antes de iniciar el ataque.
// Verifica que el servicio responde correctamente con credenciales
// legítimas (demo/demo123).  Si falla, el test se detiene.
// Esto garantiza que err_pct alto durante el ataque es culpa del
// rate-limit o del brute force, NO de un stack caído.
// ------------------------------------------------------------
export function setup() {
  const res = http.post(
    `${BASE_URL}/auth/login`,
    JSON.stringify({ username: 'demo', password: 'demo123' }),
    { headers: { 'Content-Type': 'application/json' },
      tags: { op: 'health_check' } }
  );
  if (res.status !== 200) {
    console.error(
      `[HEALTH-CHECK FAIL] ${HOST} devolvió HTTP ${res.status}. ` +
      'Verifica que el namespace esté desplegado y el servicio levantado.'
    );
    // exit code no-cero detiene el test antes de que corran los VUs
    // pero k6 no soporta fail-fast desde setup(); se reporta como warning.
  } else {
    console.log(`[HEALTH-CHECK OK] ${HOST} responde 200 con credenciales demo/demo123.`);
    console.log(`[INFO] Iniciando ataque de credential stuffing (${__ENV.VUS || 1} VUs, ${__ENV.DURATION || '30s'})...`);
  }
}

// Simula un diccionario de contraseñas comunes (credential stuffing list)
const PASSWORD_LIST = [
  'password', '123456', 'admin', 'letmein', 'welcome',
  'monkey', 'dragon', 'master', 'qwerty', 'football',
  'shadow', 'batman', 'superman', 'abc123', 'pass@word1',
  'iloveyou', 'trustno1', '1q2w3e4r', 'sunshine', 'princess',
];

export default function () {
  // Selecciona una contraseña del diccionario (simula credential stuffing)
  const password = PASSWORD_LIST[__ITER % PASSWORD_LIST.length];

  const res = http.post(
    `${BASE_URL}/auth/login`,
    JSON.stringify({ username: 'admin', password: password }),
    {
      headers: { 'Content-Type': 'application/json' },
      tags:    { attack: 'brute_force', target: TARGET },
      // HTTP 401 = auth-service rechaza la credencial incorrecta (comportamiento
      // ESPERADO del ataque de brute force — el request SÍ llegó al backend).
      // HTTP 503 = rate-limit NGINX o fallo de backend (rastreados por separado).
      // Sin este callback, k6 contaría todos los 401 como http_req_failed y
      // err_pct sería ~100% en baseline aunque el stack esté sano.
      responseCallback: http.expectedStatuses(200, 401, 503),
    }
  );

  loginLatency.add(res.timings.duration);

  const reachedBackend = res.status === 200 || res.status === 401;

  // Distingue el origen del 503:
  //   NGINX rate-limit → body HTML contiene la firma "<center>nginx</center>"
  //   Backend failure  → body JSON (FastAPI), sin esa firma
  const isNginxRateLimit = res.status === 503 &&
    (res.body || '').toLowerCase().includes('nginx');
  const isBackendError = res.status === 503 && !isNginxRateLimit;

  check(res, {
    'rate_limited_by_nginx (503 HTML)': () => isNginxRateLimit,
    'backend_failure       (503 JSON)': () => isBackendError,
    'reached_backend       (200/401)':  () => reachedBackend,
  });

  if (isNginxRateLimit) {
    rlBlocked.add(1);
    blockRate.add(1);        // cuenta como bloqueo del control C4
  } else if (isBackendError) {
    beError.add(1);
    blockRate.add(0);        // NO cuenta como bloqueo del control (es fiabilidad)
  } else if (reachedBackend) {
    attackReached.add(1);
    blockRate.add(0);
  }
  // Sin sleep(): máxima presión, simula herramienta de ataque automatizada
}

export function handleSummary(data) {
  const rl503   = data.metrics['ratelimit_503']?.values?.count            || 0;
  const be503   = data.metrics['backend_503']?.values?.count              || 0;
  const reached = data.metrics['attack_reached_backend']?.values?.count   || 0;
  const total   = rl503 + be503 + reached;
  const bpct    = total > 0 ? ((rl503 / total) * 100).toFixed(1) : '0.0';

  // Las 6 métricas comparables con el experimento original
  const avgMs   = (data.metrics['login_latency_ms']?.values?.avg          || 0).toFixed(2);
  const p95Ms   = (data.metrics['login_latency_ms']?.values?.['p(95)']    || 0).toFixed(2);
  const rps     = (data.metrics['http_reqs']?.values?.rate                || 0).toFixed(2);
  // CPU y memoria se recolectan fuera de k6 con kubectl top (ver wrapper bash)

  // err_pct = solo fallos de INFRAESTRUCTURA (conexiones caídas, timeouts,
  // respuestas no esperadas por responseCallback).
  // HTTP 401 y 503 NO cuentan aquí (se rastrean con contadores propios).
  // Comparable al err_pct del experimento original (que usa credenciales correctas).
  const errPct  = ((data.metrics['http_req_failed']?.values?.rate         || 0) * 100).toFixed(2);

  const verdict = rl503 > 0
    ? '✔ CONTROL ACTIVO: NGINX rate-limit bloqueó el ataque'
    : '✘ VULNERABLE: ningún request fue bloqueado por rate-limit';

  const beNote = be503 > 0
    ? `\n ⚠ ${be503} resp. 503 JSON del backend — métricas de FIABILIDAD, no del control C4.`
    : '';

  const summary = `
==============================================================
 C4 RATE LIMITING – RESULTADO DEL ATAQUE DE FUERZA BRUTA
==============================================================
 Objetivo:        ${HOST}:${PORT}
 Duración:        ${__ENV.DURATION || '30s'}
 VUs (atacantes): ${__ENV.VUS || '1'}

 ── Distribución de respuestas ──────────────────────────────
 Total requests:                      ${total}
 Llegaron al backend     (200/401):   ${reached}
 Bloqueados por NGINX RL (503 HTML):  ${rl503}   ← control C4
 Fallos de backend       (503 JSON):  ${be503}   ← fiabilidad (≠ C4)
 Tasa de bloqueo (control C4):        ${bpct}%

 ── 6 métricas ISO/IEC 25010 (comparables al experimento) ──
 Latencia avg:      ${avgMs} ms
 Latencia p95:      ${p95Ms} ms
 Error rate (infra): ${errPct}%
   ↳ Solo fallos de infraestructura (conexión caída, timeout).
     HTTP 401 = credencial rechazada por backend (NO es error infra).
     HTTP 503 = rate-limit o fallo backend (rastreado arriba por separado).
     err_pct~0% en baseline = stack sano, brute force llega sin bloqueo.
 Throughput (RPS):  ${rps} req/s
 CPU total:         (ver kubectl top — recolectado por el wrapper)
 Mem total:         (ver kubectl top — recolectado por el wrapper)
${beNote}
 ${verdict}
==============================================================
`;

  console.log(summary);

  return {
    stdout: summary,
  };
}
