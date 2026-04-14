/**
 * k6 Load Testing Script for MuBench
 * Replaces Apache JMeter with modern, scriptable load testing
 * 
 * Features:
 * - Parametrizable via environment variables
 * - JSON output for analysis
 * - Supports HTTP and HTTPS testing
 * - Inter-service communication metrics
 */

import http from 'k6/http';
import { check, sleep } from 'k6';
import { Rate, Trend, Counter } from 'k6/metrics';

// Custom metrics
const errorRate = new Rate('errors');
const requestDuration = new Trend('request_duration');
const requestsTotal = new Counter('requests_total');

// Configuration from environment variables
const TARGET_URL = __ENV.TARGET_URL || 'http://localhost:31113/s0';
const VUS = parseInt(__ENV.VUS || '10');
const DURATION = __ENV.DURATION || '30s';
const PROTOCOL = __ENV.PROTOCOL || 'http';
const INSECURE_SKIP_TLS_VERIFY = __ENV.INSECURE_SKIP_TLS_VERIFY === 'true';

export const options = {
    vus: VUS,
    duration: DURATION,
    thresholds: {
        'http_req_duration': ['p(95)<500', 'p(99)<1000'],
        'errors': ['rate<0.1'],
        'http_req_failed': ['rate<0.05'],
    },
    insecureSkipTLSVerify: INSECURE_SKIP_TLS_VERIFY,
};

export default function() {
    const params = {
        headers: {
            'Content-Type': 'application/json',
            'User-Agent': 'k6-mubench',
        },
        tags: {
            protocol: PROTOCOL,
        },
    };

    // Test main endpoint
    const response = http.get(TARGET_URL, params);
    
    // Track metrics
    const result = check(response, {
        'status is 200': (r) => r.status === 200,
        'response time < 500ms': (r) => r.timings.duration < 500,
        'response has body': (r) => r.body && r.body.length > 0,
    });

    errorRate.add(!result);
    requestDuration.add(response.timings.duration);
    requestsTotal.add(1);

    // Small delay between requests
    sleep(0.1);
}

// Setup function - runs once at the beginning
export function setup() {
    console.log(`Starting k6 load test`);
    console.log(`Target URL: ${TARGET_URL}`);
    console.log(`Virtual Users: ${VUS}`);
    console.log(`Duration: ${DURATION}`);
    console.log(`Protocol: ${PROTOCOL}`);
    
    return { startTime: new Date().toISOString() };
}

// Teardown function - runs once at the end
export function teardown(data) {
    console.log(`Test completed at: ${new Date().toISOString()}`);
    console.log(`Started at: ${data.startTime}`);
}
