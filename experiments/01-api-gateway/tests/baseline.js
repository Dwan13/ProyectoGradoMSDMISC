/**
 * k6 Test: Baseline (Sin API Gateway)
 * 
 * Prueba de carga directa al servicio s0 via NodePort
 * Sin autenticación, sin rate limiting, sin plugins
 */

import http from 'k6/http';
import { check, sleep } from 'k6';
import { Counter, Trend, Rate } from 'k6/metrics';

// Métricas personalizadas
const errors = new Counter('errors');
const latency = new Trend('latency');
const errorRate = new Rate('error_rate');

// Configuración del test
export let options = {
  vus: parseInt(__ENV.VUS) || 10,
  duration: __ENV.DURATION || '5m',
  
  thresholds: {
    'http_req_duration': ['p(95)<500', 'p(99)<1000'],
    'http_req_failed': ['rate<0.01'],  // < 1% errores
    'errors': ['count<50'],
  },
  
  summaryTrendStats: ['min', 'avg', 'med', 'p(90)', 'p(95)', 'p(99)', 'max'],
};

export default function () {
  const url = __ENV.TARGET_URL || 'http://localhost:30080/process';
  
  const payload = JSON.stringify({});
  
  const params = {
    headers: {
      'Content-Type': 'application/json',
    },
  };
  
  const started = Date.now();
  let res = http.post(url, payload, params);
  const duration = Date.now() - started;
  
  // Métricas personalizadas
  latency.add(duration);
  
  // Validaciones
  const success = check(res, {
    'status is 200': (r) => r.status === 200,
    'response time < 500ms': (r) => r.timings.duration < 500,
    'response has body': (r) => r.body.length > 0,
    'response is JSON': (r) => {
      try {
        JSON.parse(r.body);
        return true;
      } catch (e) {
        return false;
      }
    },
    'response has status field': (r) => {
      try {
        const body = JSON.parse(r.body);
        return body.hasOwnProperty('status');
      } catch (e) {
        return false;
      }
    },
  });
  
  if (!success) {
    errors.add(1);
    errorRate.add(1);
    console.error(`Request failed: ${res.status} - ${res.body.substring(0, 100)}`);
  } else {
    errorRate.add(0);
  }
  
  // Pequeña pausa entre requests (simular comportamiento real)
  sleep(0.1);
}

export function handleSummary(data) {
  return {
    'stdout': textSummary(data, { indent: ' ', enableColors: true }),
  };
}

function textSummary(data, options) {
  const indent = options.indent || '';
  const colors = options.enableColors || false;
  
  let summary = '\\n';
  summary += indent + '============================================\\n';
  summary += indent + '  Baseline Test Summary - No Gateway       \\n';
  summary += indent + '============================================\\n\\n';
  
  summary += indent + 'Configuration:\\n';
  summary += indent + `  VUs: ${data.options.vus}\\n`;
  summary += indent + `  Duration: ${data.options.duration}\\n`;
  summary += indent + `  Endpoint: ${__ENV.TARGET_URL}\\n\\n`;
  
  summary += indent + 'Results:\\n';
  
  const metrics = data.metrics;
  
  if (metrics.http_reqs) {
    summary += indent + `  Requests: ${metrics.http_reqs.values.count} (${metrics.http_reqs.values.rate.toFixed(2)} req/s)\\n`;
  }
  
  if (metrics.http_req_duration) {
    summary += indent + `  Latency:\\n`;
    summary += indent + `    avg: ${metrics.http_req_duration.values.avg.toFixed(2)}ms\\n`;
    summary += indent + `    p95: ${metrics.http_req_duration.values['p(95)'].toFixed(2)}ms\\n`;
    summary += indent + `    p99: ${metrics.http_req_duration.values['p(99)'].toFixed(2)}ms\\n`;
  }
  
  if (metrics.http_req_failed) {
    summary += indent + `  Failures: ${(metrics.http_req_failed.values.rate * 100).toFixed(2)}%\\n`;
  }
  
  summary += indent + '\\n============================================\\n';
  
  return summary;
}
