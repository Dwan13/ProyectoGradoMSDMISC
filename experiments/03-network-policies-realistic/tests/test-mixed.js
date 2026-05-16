/**
 * k6 Test: Carga mixta realista
 *   50% GET  /profile?user_id=1       — lectura autenticada (perfil de usuario)
 *   30% GET  /users?limit=50&offset=0 — listado de usuarios (consulta DB completa)
 *   20% POST /users                   — creación de usuario (escritura DB)
 *
 * El username generado en POST usa __VU + __ITER + timestamp para garantizar
 * unicidad entre VUs y repeticiones. La tasa de error sobre POST/409 NO se
 * cuenta como fallo — solo fallan status >= 500 o timeouts.
 *
 * Variables de entorno:
 *   TARGET_URL  URL del gateway bajo prueba (default: https://localhost)
 *   AUTH_URL    URL directa de auth-service para login (default: http://localhost:30084)
 *   VUS         Usuarios virtuales concurrentes
 *   DURATION    Duración de la prueba
 */

import http from 'k6/http';
import { check } from 'k6';

export let options = {
  vus:      parseInt(__ENV.VUS)      || 10,
  duration: __ENV.DURATION           || '60s',
  summaryTrendStats: ['min', 'avg', 'med', 'p(90)', 'p(95)', 'p(99)', 'max'],
  insecureSkipTLSVerify: true,
};

export function setup() {
  const authUrl = __ENV.AUTH_URL || 'http://localhost:30084';
  const res = http.post(
    `${authUrl}/login`,
    JSON.stringify({ username: 'demo', password: 'demo123' }),
    { headers: { 'Content-Type': 'application/json' }, timeout: '10s' }
  );
  if (res.status !== 200) {
    throw new Error(`Login failed: ${res.status} ${res.body}`);
  }
  return { token: res.json('access_token') };
}

export default function (data) {
  const base    = __ENV.TARGET_URL || 'https://localhost';
  const headers = {
    Authorization:  `Bearer ${data.token}`,
    'Content-Type': 'application/json',
  };

  // Distribución de operaciones por iteración
  const roll = Math.random();

  if (roll < 0.50) {
    // ── 50% Lectura de perfil (GET /profile) ─────────────────────────────────
    const res = http.get(`${base}/profile?user_id=1`, { headers, timeout: '10s' });
    check(res, {
      'profile 200':     (r) => r.status === 200,
      'profile has user': (r) => {
        try { return r.json('user') !== null; } catch { return false; }
      },
    });

  } else if (roll < 0.80) {
    // ── 30% Listado de usuarios (GET /users) ─────────────────────────────────
    const res = http.get(`${base}/users?limit=50&offset=0`, { headers, timeout: '10s' });
    check(res, {
      'list 200':        (r) => r.status === 200,
      'list has users':  (r) => {
        try { return Array.isArray(r.json('users')); } catch { return false; }
      },
    });

  } else {
    // ── 20% Creación de usuario (POST /users) ────────────────────────────────
    // Username único por VU/iteración/corrida para evitar colisiones entre reruns
    const uid  = `vu${__VU}_i${__ITER}_ts${Date.now()}_r${Math.floor(Math.random() * 1000000)}`;
    const body = JSON.stringify({
      username:  uid,
      email:     `${uid}@bench.local`,
      full_name: 'Bench User',
    });
    const res = http.post(`${base}/users`, body, { headers, timeout: '10s' });
    // 201 = creado OK; 400/409 = duplicado — ambos son respuestas válidas del servicio
    // NOTA: No modificar res.tags, k6 no lo permite. Los checks ya filtran los errores válidos.
    check(res, {
      'create ok or conflict': (r) => r.status === 201 || r.status === 400 || r.status === 409,
      'create not server error': (r) => r.status < 500,
    });
  }
}
