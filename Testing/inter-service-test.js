/**
 * k6 Load Testing Script - Inter-Service Communication Test
 * Tests the full chain: s0 -> s1 -> sdb1
 * 
 * Usage:
 *   k6 run --out json=results.json \
 *     -e TARGET_URL=http://localhost:31113 \
 *     -e VUS=20 \
 *     -e DURATION=60s \
 *     inter-service-test.js
 */

import http from 'k6/http';
import { check, sleep, group } from 'k6';
import { Rate, Trend, Counter } from 'k6/metrics';

// Custom metrics for each service
const s0Duration = new Trend('s0_request_duration');
const s1Duration = new Trend('s1_request_duration');
const sdbDuration = new Trend('sdb_request_duration');

const s0ErrorRate = new Rate('s0_errors');
const s1ErrorRate = new Rate('s1_errors');
const sdbErrorRate = new Rate('sdb_errors');

const totalRequests = new Counter('total_requests');
const totalErrors = new Counter('total_errors');

// Configuration
const BASE_URL = __ENV.TARGET_URL || 'http://localhost:31113';
const VUS = parseInt(__ENV.VUS || '10');
const DURATION = __ENV.DURATION || '60s';
const PROTOCOL = __ENV.PROTOCOL || 'http';

export const options = {
    vus: VUS,
    duration: DURATION,
    thresholds: {
        'http_req_duration': ['p(95)<1000', 'p(99)<2000'],
        's0_request_duration': ['p(95)<500'],
        's1_request_duration': ['p(95)<500'],
        'sdb_request_duration': ['p(95)<500'],
        's0_errors': ['rate<0.05'],
        's1_errors': ['rate<0.05'],
        'sdb_errors': ['rate<0.05'],
    },
    insecureSkipTLSVerify: PROTOCOL === 'https',
};

export default function() {
    const params = {
        headers: {
            'Content-Type': 'application/json',
        },
        tags: {
            protocol: PROTOCOL,
        },
    };

    // Test Service 0 - /process endpoint
    group('Service0 Process', function() {
        const payload = JSON.stringify({});
        const s0Response = http.post(`${BASE_URL}/process`, payload, params);
        
        const s0Check = check(s0Response, {
            's0: status is 200': (r) => r.status === 200,
            's0: has response': (r) => r.body && r.body.length > 0,
        });

        s0Duration.add(s0Response.timings.duration);
        s0ErrorRate.add(!s0Check);
        totalRequests.add(1);
        if (!s0Check) totalErrors.add(1);
    });

    sleep(0.2);

    // Test Service 1 - /validate endpoint
    group('Service1 Validate', function() {
        const payload = JSON.stringify({});
        const s1Response = http.post(`${BASE_URL}/validate`, payload, params);
        
        const s1Check = check(s1Response, {
            's1: status is 200': (r) => r.status === 200,
            's1: has response': (r) => r.body && r.body.length > 0,
        });

        s1Duration.add(s1Response.timings.duration);
        s1ErrorRate.add(!s1Check);
        totalRequests.add(1);
        if (!s1Check) totalErrors.add(1);
    });

    sleep(0.2);

    // Test Service DB - /query endpoint
    group('ServiceDB Query', function() {
        const payload = JSON.stringify({});
        const sdbResponse = http.post(`${BASE_URL}/query`, payload, params);
        
        const sdbCheck = check(sdbResponse, {
            'sdb: status is 200': (r) => r.status === 200,
            'sdb: has response': (r) => r.body && r.body.length > 0,
        });

        sdbDuration.add(sdbResponse.timings.duration);
        sdbErrorRate.add(!sdbCheck);
        totalRequests.add(1);
        if (!sdbCheck) totalErrors.add(1);
    });

    sleep(0.5);
}

export function setup() {
    console.log('=================================================');
    console.log('  MuBench Inter-Service Communication Test');
    console.log('=================================================');
    console.log(`Base URL: ${BASE_URL}`);
    console.log(`Protocol: ${PROTOCOL}`);
    console.log(`Virtual Users: ${VUS}`);
    console.log(`Duration: ${DURATION}`);
    console.log('=================================================');
    
    return {
        startTime: new Date().toISOString(),
        config: { BASE_URL, PROTOCOL, VUS, DURATION }
    };
}

export function teardown(data) {
    console.log('=================================================');
    console.log(`Test Started:  ${data.startTime}`);
    console.log(`Test Finished: ${new Date().toISOString()}`);
    console.log('=================================================');
}
