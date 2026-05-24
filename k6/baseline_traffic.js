import http from 'k6/http';
import { check, sleep } from 'k6';

/**
 * S6 BASELINE TRAFFIC GENERATION
 * Purpose: Generate legitimate traffic for Phase 1 (baseline) and Phase 2 (legitimate part)
 * VUS: Variable (passed via environment)
 * Duration: 30 seconds
 * Metrics: Response times, error rates, throughput
 */

export const options = {
  vus: parseInt(__ENV.K6_VUS || '1'),
  duration: __ENV.K6_DURATION || '30s',
  rps: 100,  // Rate: 100 requests per second (reasonable for 4 services)
  thresholds: {
    http_req_duration: ['p(95)<200'],  // 95th percentile < 200ms
    http_req_failed: ['rate<0.1'],      // Error rate < 10%
  },
};

// Configuration
const SERVICES = {
  auth: __ENV.AUTH_SERVICE_URL || 'http://auth-service:3000',
  api: __ENV.API_SERVICE_URL || 'http://api-service:3001',
  data: __ENV.DATA_SERVICE_URL || 'http://data-service:3002',
};

const CONTROL = __ENV.CONTROL || 'C1';
const PHASE = __ENV.PHASE || 'baseline';

export default function () {
  // Mix of legitimate requests to different endpoints
  const scenario = Math.random();

  // Scenario 1: Auth flow (25% of traffic)
  if (scenario < 0.25) {
    const loginRes = http.post(`${SERVICES.auth}/auth/login`, {
      username: 'user@example.com',
      password: 'password123',
    });

    check(loginRes, {
      'Auth: login returns 200 or 401': (r) => r.status === 200 || r.status === 401,
      'Auth: response time < 200ms': (r) => r.timings.duration < 200,
    });
  }

  // Scenario 2: API queries (35% of traffic)
  else if (scenario < 0.60) {
    const apiRes = http.get(`${SERVICES.api}/api/users?offset=0&limit=10`, {
      headers: { 'Content-Type': 'application/json' },
    });

    check(apiRes, {
      'API: GET returns 200': (r) => r.status === 200,
      'API: response time < 200ms': (r) => r.timings.duration < 200,
    });
  }

  // Scenario 3: Data service (25% of traffic)
  else if (scenario < 0.85) {
    const dataRes = http.post(`${SERVICES.data}/api/data`, {
      query: 'SELECT * FROM records LIMIT 10',
    });

    check(dataRes, {
      'Data: POST returns 200': (r) => r.status === 200,
      'Data: response time < 200ms': (r) => r.timings.duration < 200,
    });
  }

  // Scenario 4: File operations (15% of traffic)
  else {
    const fileRes = http.get(`${SERVICES.api}/api/file?path=/data/users.json`, {
      headers: { 'Content-Type': 'application/json' },
    });

    check(fileRes, {
      'File: GET returns 200 or 403': (r) => r.status === 200 || r.status === 403,
      'File: response time < 200ms': (r) => r.timings.duration < 200,
    });
  }

  // Small delay between requests
  sleep(0.1);
}

export function setup() {
  console.log(`
    ========================================
    S6 BASELINE TRAFFIC GENERATION
    ========================================
    Control:    ${CONTROL}
    Phase:      ${PHASE}
    VUS:        ${options.vus}
    Duration:   ${options.duration}
    ========================================
  `);

  // Health check
  const healthCheck = http.get(`${SERVICES.auth}/health`);
  if (healthCheck.status !== 200) {
    console.warn('Auth service not responding to health check');
  }

  return {};
}

export function teardown(data) {
  console.log(`
    ========================================
    BASELINE TRAFFIC TEST COMPLETE
    ========================================
  `);
}
