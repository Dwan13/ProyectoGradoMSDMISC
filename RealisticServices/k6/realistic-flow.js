import http from 'k6/http';
import { check, sleep } from 'k6';
import encoding from 'k6/encoding';
import crypto from 'k6/crypto';
import { Counter, Trend } from 'k6/metrics';

// AUTH_BASE y API_BASE pueden incluir prefijo de ruta cuando se usa ingress.
// Ejemplo HTTPS realista: AUTH_BASE=https://localhost/auth  API_BASE=https://localhost/api
const AUTH_BASE = (__ENV.AUTH_BASE || 'https://localhost/auth').replace(/\/?$/, '');
const API_BASE = (__ENV.API_BASE || 'https://localhost/api').replace(/\/?$/, '');
const INSECURE_TLS = ((__ENV.K6_INSECURE_SKIP_TLS_VERIFY || 'true').toLowerCase() === 'true');
const HOST_HEADER = __ENV.HOST_HEADER || '';
const SECURITY_MODE = (__ENV.SECURITY_MODE || 'normal').toLowerCase();
const ATTACK_PROFILE = (__ENV.ATTACK_PROFILE || 'advanced').toLowerCase();

const loginSuccessTotal = new Counter('login_success_total');
const loginFailTotal = new Counter('login_fail_total');
const profileSuccessTotal = new Counter('profile_success_total');
const usersListSuccessTotal = new Counter('users_list_success_total');
const jwtIssuedTotal = new Counter('jwt_issued_total');
const jwtTraceEvents = new Counter('jwt_trace_events');
const attackBlockedTotal = new Counter('attack_blocked_total');
const attackVectorAttempts = new Counter('attack_vector_attempts_total');
const attackVectorBlocked = new Counter('attack_vector_blocked_total');
const profileDbLatencyMs = new Trend('profile_db_latency_ms');
const usersDbLatencyMs = new Trend('users_db_latency_ms');

function withOptionalHostHeader(headers) {
  if (!HOST_HEADER) {
    return headers;
  }
  return { ...headers, Host: HOST_HEADER };
}

export const options = {
  insecureSkipTLSVerify: INSECURE_TLS,
  thresholds: {
    http_req_failed: SECURITY_MODE === 'attack' ? ['rate<0.80'] : ['rate<0.05'],
    http_req_duration: ['p(95)<700'],
    checks: ['rate>0.95'],
  },
};

function decodeJwtPayload(token) {
  if (!token || token.split('.').length < 2) {
    return null;
  }
  const base64Url = token.split('.')[1];
  const base64 = base64Url.replace(/-/g, '+').replace(/_/g, '/');
  const padded = base64 + '='.repeat((4 - (base64.length % 4)) % 4);

  try {
    const decoded = encoding.b64decode(padded, 'rawstd', 's');
    return JSON.parse(decoded);
  } catch (err) {
    return null;
  }
}

function login() {
  const payload = JSON.stringify({ username: 'demo', password: 'demo123' });
  const params = { headers: withOptionalHostHeader({ 'Content-Type': 'application/json' }) };
  const res = http.post(`${AUTH_BASE}/login`, payload, params);
  const hasToken = res && res.status === 200 && res.body && !!res.json('access_token');

  check(res, {
    'login status 200': (r) => r.status === 200,
    'login has token': () => hasToken,
  });

  if (hasToken) {
    loginSuccessTotal.add(1, { security_mode: SECURITY_MODE });
    jwtIssuedTotal.add(1, { security_mode: SECURITY_MODE });

    const token = res.json('access_token');
    const claims = decodeJwtPayload(token);
    if (claims) {
      const fp = crypto.sha256(String(token), 'hex');
      jwtTraceEvents.add(1, {
        security_mode: SECURITY_MODE,
        jwt_sub: String(claims.sub || 'unknown'),
        jwt_iat: String(claims.iat || 0),
        jwt_fp: fp,
      });
    }
  } else {
    loginFailTotal.add(1, { security_mode: SECURITY_MODE });
  }

  return hasToken ? res.json('access_token') : null;
}

function getProfile(token) {
  const profileRes = http.get(`${API_BASE}/profile?user_id=1`, {
    headers: withOptionalHostHeader({ Authorization: `Bearer ${token}` }),
  });

  const hasProfileUser = profileRes && profileRes.status === 200 && profileRes.body && !!profileRes.json('user.username');

  check(profileRes, {
    'profile status 200': (r) => r.status === 200,
    'profile has user': () => hasProfileUser,
  });

  if (profileRes && profileRes.status === 200) {
    profileSuccessTotal.add(1, { security_mode: SECURITY_MODE });
    const dbLatency = Number(profileRes.json('db_latency_ms') || 0);
    if (!Number.isNaN(dbLatency) && dbLatency > 0) {
      profileDbLatencyMs.add(dbLatency, { security_mode: SECURITY_MODE });
    }
  }
}

function listUsers(token) {
  const usersRes = http.get(`${API_BASE}/users?limit=20&offset=0`, {
    headers: withOptionalHostHeader({ Authorization: `Bearer ${token}` }),
  });

  check(usersRes, {
    'users status 200': (r) => r.status === 200,
    'users has count': (r) => r.status === 200 && Number(r.json('count') || 0) >= 0,
  });

  if (usersRes && usersRes.status === 200) {
    usersListSuccessTotal.add(1, { security_mode: SECURITY_MODE });
    const dbLatency = Number(usersRes.json('db_latency_ms') || 0);
    if (!Number.isNaN(dbLatency) && dbLatency > 0) {
      usersDbLatencyMs.add(dbLatency, { security_mode: SECURITY_MODE });
    }
  }
}

function runAttackProbes() {
  let blockedCount = 0;

  const badLogin = http.post(
    `${AUTH_BASE}/login`,
    JSON.stringify({ username: 'demo', password: 'wrong-password' }),
    { headers: withOptionalHostHeader({ 'Content-Type': 'application/json' }) }
  );
  attackVectorAttempts.add(1, { security_mode: SECURITY_MODE, vector: 'bad_login' });

  const unauthUsers = http.get(`${API_BASE}/users?limit=5&offset=0`, {
    headers: withOptionalHostHeader({}),
  });
  attackVectorAttempts.add(1, { security_mode: SECURITY_MODE, vector: 'unauth_users' });

  if ([401, 403, 429].includes(badLogin.status)) {
    blockedCount += 1;
    attackVectorBlocked.add(1, { security_mode: SECURITY_MODE, vector: 'bad_login' });
  }
  if ([401, 403, 429].includes(unauthUsers.status)) {
    blockedCount += 1;
    attackVectorBlocked.add(1, { security_mode: SECURITY_MODE, vector: 'unauth_users' });
  }

  check(badLogin, {
    'attack bad-login blocked': (r) => [401, 403, 429].includes(r.status),
  });

  check(unauthUsers, {
    'attack unauth-users blocked': (r) => [401, 403, 429].includes(r.status),
  });

  if (ATTACK_PROFILE !== 'advanced') {
    attackBlockedTotal.add(blockedCount, { security_mode: SECURITY_MODE });
    return;
  }

  // Vector: forged/tampered bearer token
  const tamperedTokenProfile = http.get(`${API_BASE}/profile?user_id=1`, {
    headers: withOptionalHostHeader({ Authorization: 'Bearer tampered.invalid.token' }),
  });
  attackVectorAttempts.add(1, { security_mode: SECURITY_MODE, vector: 'tampered_bearer' });
  if ([401, 403, 429].includes(tamperedTokenProfile.status)) {
    blockedCount += 1;
    attackVectorBlocked.add(1, { security_mode: SECURITY_MODE, vector: 'tampered_bearer' });
  }

  check(tamperedTokenProfile, {
    'attack tampered-bearer blocked': (r) => [401, 403, 429].includes(r.status),
  });

  // Vector: malformed bearer header abuse
  const malformedBearer = http.get(`${API_BASE}/users?limit=5&offset=0`, {
    headers: withOptionalHostHeader({ Authorization: 'Bearer' }),
  });
  attackVectorAttempts.add(1, { security_mode: SECURITY_MODE, vector: 'malformed_bearer' });
  if ([401, 403, 429].includes(malformedBearer.status)) {
    blockedCount += 1;
    attackVectorBlocked.add(1, { security_mode: SECURITY_MODE, vector: 'malformed_bearer' });
  }

  check(malformedBearer, {
    'attack malformed-bearer blocked': (r) => [401, 403, 429].includes(r.status),
  });

  // Vector: spoofed proxy chain / rotating X-Forwarded-For
  const spoofHeaders = [
    '1.2.3.4',
    '10.20.30.40, 44.55.66.77',
    '203.0.113.5, 198.51.100.2, 192.0.2.8',
  ];

  for (const xff of spoofHeaders) {
    const spoofedReq = http.get(`${API_BASE}/users?limit=5&offset=0`, {
      headers: withOptionalHostHeader({
        Authorization: 'Bearer tampered.invalid.token',
        'X-Forwarded-For': xff,
      }),
    });
    attackVectorAttempts.add(1, { security_mode: SECURITY_MODE, vector: 'xff_spoof_chain' });
    if ([401, 403, 429].includes(spoofedReq.status)) {
      blockedCount += 1;
      attackVectorBlocked.add(1, { security_mode: SECURITY_MODE, vector: 'xff_spoof_chain' });
    }

    check(spoofedReq, {
      'attack xff-spoof blocked': (r) => [401, 403, 429].includes(r.status),
    });
  }

  attackBlockedTotal.add(blockedCount, { security_mode: SECURITY_MODE });
}

export default function () {
  const token = login();
  if (!token) {
    sleep(1);
    return;
  }

  getProfile(token);
  listUsers(token);

  if (SECURITY_MODE === 'attack') {
    runAttackProbes();
  }

  sleep(0.5);
}
