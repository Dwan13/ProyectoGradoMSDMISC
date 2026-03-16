/**
 * k6 Test: Kong API Gateway
 * 
 * Prueba con autenticación via API Key
 * Rate limiting activo (100 req/s)
 */

import http from 'k6/http';
import { check, sleep } from 'k6';
import { Counter, Trend, Rate } from 'k6/metrics';

// Métricas personalizadas
const errors = new Counter('errors');
const latency = new Trend('latency');
const errorRate = new Rate('error_rate');
const rateLimitHits = new Counter('rate_limit_hits');

export let options = {
  vus: parseInt(__ENV.VUS) || 10,
  duration: __ENV.DURATION || '5m',
  
  thresholds: {
    'http_req_duration': ['p(95)<1000'],  // Más permisivo por overhead de gateway
    'http_req_failed': ['rate<0.05'],  // Permitir algunos rate limit errors
    'errors': ['count<100'],
  },
  
  summaryTrendStats: ['min', 'avg', 'med', 'p(90)', 'p(95)', 'p(99)', 'max'],
};

export default function () {
  const url = __ENV.TARGET_URL || 'http://localhost:30082/process';
  
  const payload = JSON.stringify({});
  
  const params = {
    headers: {
      'Content-Type': 'application/json',
    },
  };
  
  const started = Date.now();
  let res = http.post(url, payload, params);
  const duration = Date.now() - started;
  
  latency.add(duration);
  
  // Validaciones
  const success = check(res, {
    'status is 200 or 429': (r) => r.status === 200 || r.status === 429,
    'status is 200': (r) => r.status === 200,
    'not unauthorized': (r) => r.status !== 401,
    'response time < 1000ms': (r) => r.timings.duration < 1000,
    'response has body': (r) => r.body.length > 0,
    'Kong headers present': (r) => {
      return r.headers['X-Gateway'] === 'Kong' || 
             r.headers['X-Kong-Upstream-Latency'] !== undefined;
    },
  });
  
  // Contar rate limits
  if (res.status === 429) {
    rateLimitHits.add(1);
    console.log('Rate limit hit - 429 response');
  }
  
  if (res.status !== 200 && res.status !== 429) {
    errors.add(1);
    errorRate.add(1);
    console.error(`Request failed: ${res.status} - ${res.body.substring(0, 100)}`);
  } else {
    errorRate.add(0);
  }
  
  sleep(0.1);
}

export function handleSummary(data) {
  let summary = '\\n';
  summary += '============================================\\n';
  summary += '  Kong Gateway Test Summary                \\n';
  summary += '============================================\\n\\n';
  
  summary += 'Configuration:\\n';
  summary += `  VUs: ${data.options.vus}\\n`;
  summary += `  Duration: ${data.options.duration}\\n`;
  summary += `  Endpoint: ${__ENV.TARGET_URL}\\n`;
  summary += `  Rate Limit: 100 req/s\\n\\n`;
  
  summary += 'Results:\\n';
  
  const metrics = data.metrics;
  
  if (metrics.http_reqs) {
    summary += `  Requests: ${metrics.http_reqs.values.count} (${metrics.http_reqs.values.rate.toFixed(2)} req/s)\\n`;
  }
  
  if (metrics.http_req_duration) {
    summary += `  Latency:\\n`;
    summary += `    avg: ${metrics.http_req_duration.values.avg.toFixed(2)}ms\\n`;
    summary += `    p95: ${metrics.http_req_duration.values['p(95)'].toFixed(2)}ms\\n`;
    summary += `    p99: ${metrics.http_req_duration.values['p(99)'].toFixed(2)}ms\\n`;
  }
  
  if (metrics.http_req_failed) {
    summary += `  Failures: ${(metrics.http_req_failed.values.rate * 100).toFixed(2)}%\\n`;
  }
  
  if (metrics.rate_limit_hits) {
    summary += `  Rate Limit Hits: ${metrics.rate_limit_hits.values.count}\\n`;
  }
  
  summary += '\\n============================================\\n';
  
  return {
    'stdout': summary,
  };
}
