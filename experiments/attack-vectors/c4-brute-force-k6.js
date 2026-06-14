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

const attackBlocked  = new Counter('attack_blocked_503');
const attackReached  = new Counter('attack_reached_backend');
const blockRate      = new Rate('block_rate');
const loginLatency   = new Trend('login_latency_ms');

export const options = {
  insecureSkipTLSVerify: true,
  hosts: { [HOST]: '127.0.0.1' },
  vus:      parseInt(__ENV.VUS      || '1'),
  duration: __ENV.DURATION          || '30s',
  thresholds: {
    // El test "pasa" si se detecta bloqueo (block_rate > 0) en variantes no-baseline
    // Para baseline se espera block_rate = 0
  },
  summaryTrendStats: ['avg', 'min', 'max', 'p(50)', 'p(95)', 'p(99)', 'count'],
};

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
    }
  );

  loginLatency.add(res.timings.duration);

  const is503 = res.status === 503;
  const reachedBackend = res.status === 200 || res.status === 401;

  check(res, {
    'rate_limited (503)': (r) => r.status === 503,
    'reached_backend':    (r) => r.status === 200 || r.status === 401,
  });

  if (is503) {
    attackBlocked.add(1);
    blockRate.add(1);
  } else if (reachedBackend) {
    attackReached.add(1);
    blockRate.add(0);
  }
  // Sin sleep(): máxima presión, simula herramienta de ataque automatizada
}

export function handleSummary(data) {
  const blocked  = data.metrics['attack_blocked_503']?.values?.count  || 0;
  const reached  = data.metrics['attack_reached_backend']?.values?.count || 0;
  const total    = blocked + reached;
  const bpct     = total > 0 ? ((blocked / total) * 100).toFixed(1) : '0.0';
  const avgMs    = data.metrics['login_latency_ms']?.values?.avg?.toFixed(2) || '?';
  const p95Ms    = data.metrics['login_latency_ms']?.values?.['p(95)']?.toFixed(2) || '?';

  const verdict = blocked > 0
    ? '✔ CONTROL ACTIVO: rate limiting bloqueó el ataque'
    : '✘ VULNERABLE: ningún request fue bloqueado';

  const summary = `
==============================================================
 C4 RATE LIMITING – RESULTADO DEL ATAQUE DE FUERZA BRUTA
==============================================================
 Objetivo:       ${HOST}:${PORT}
 Duración:       ${__ENV.DURATION || '30s'}
 VUs (atacantes): ${__ENV.VUS || '1'}

 Total requests:          ${total}
 Llegaron al backend:     ${reached}   (HTTP 200/401)
 Bloqueados (HTTP 503):   ${blocked}
 Tasa de bloqueo:         ${bpct}%

 Latencia promedio:  ${avgMs} ms
 Latencia p95:       ${p95Ms} ms

 ${verdict}
==============================================================
`;

  console.log(summary);

  return {
    stdout: summary,
  };
}
