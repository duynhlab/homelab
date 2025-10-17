import http from 'k6/http';
import { check, sleep } from 'k6';
import { Rate, Trend, Counter } from 'k6/metrics';

// Custom metrics
const errorRate = new Rate('k6_errors');
const requestDuration = new Trend('k6_request_duration');
const requestsTotal = new Counter('k6_requests_total');

// Load test configuration - MASSIVE SCALE
// Target: 2-3 million requests in 1 hour
export const options = {
  stages: [
    { duration: '1m', target: 100 },   // Ramp-up to 100 VUs
    { duration: '2m', target: 200 },   // Ramp-up to 200 VUs
    { duration: '5m', target: 300 },   // Ramp-up to 300 VUs
    { duration: '20m', target: 300 },  // Stay at 300 VUs (peak load)
    { duration: '10m', target: 500 },  // Ramp-up to 500 VUs (stress test)
    { duration: '15m', target: 500 },  // Stay at 500 VUs (max load)
    { duration: '3m', target: 200 },   // Ramp-down to 200 VUs
    { duration: '3m', target: 50 },    // Ramp-down to 50 VUs
    { duration: '1m', target: 0 },     // Ramp-down to 0
  ],
  thresholds: {
    http_req_duration: ['p(95)<1500', 'p(99)<3000'], // More lenient for high load
    http_req_failed: ['rate<0.20'], // Allow 20% error rate under stress
    http_reqs: ['rate>200'], // At least 200 req/s (massive scale)
  },
};

// Base URLs for each service
const BASE_URL_V1 = 'http://demo-go-api.monitoring-demo.svc.cluster.local:8080';
const BASE_URL_V2 = 'http://demo-go-api-v2.monitoring-demo.svc.cluster.local:8080';
const BASE_URL_V3 = 'http://demo-go-api-v3.monitoring-demo.svc.cluster.local:8080';

// Helper function to make requests with proper tagging
function makeRequest(method, url, body, tags) {
  const params = {
    headers: { 'Content-Type': 'application/json' },
    tags: tags,
  };
  
  let response;
  const startTime = new Date().getTime();
  
  if (method === 'GET') {
    response = http.get(url, params);
  } else if (method === 'POST') {
    response = http.post(url, JSON.stringify(body), params);
  } else if (method === 'PUT') {
    response = http.put(url, JSON.stringify(body), params);
  } else if (method === 'DELETE') {
    response = http.del(url, null, params);
  }
  
  const duration = new Date().getTime() - startTime;
  
  // Record custom metrics
  requestDuration.add(duration, tags);
  requestsTotal.add(1, tags);
  errorRate.add(response.status >= 400, tags);
  
  // Check response
  const checkResult = check(response, {
    'status is 2xx or 4xx': (r) => r.status >= 200 && r.status < 500,
  });
  
  return response;
}

// V1 API scenarios
function testV1APIs() {
  const tags = { version: 'v1', service: 'demo-go-api' };
  
  // GET /api/users (80% of traffic)
  for (let i = 0; i < 8; i++) {
    makeRequest('GET', `${BASE_URL_V1}/api/users`, null, { ...tags, endpoint: '/api/users', method: 'GET' });
    sleep(0.1);
  }
  
  // POST /api/users (10% of traffic)
  makeRequest('POST', `${BASE_URL_V1}/api/users`, {
    name: `User-${__VU}-${Date.now()}`,
    email: `user${__VU}@example.com`,
  }, { ...tags, endpoint: '/api/users', method: 'POST' });
  sleep(0.1);
  
  // POST /api/v1/checkout (10% of traffic)
  makeRequest('POST', `${BASE_URL_V1}/api/v1/checkout`, {
    user_id: `user-${__VU}`,
    items: [
      { product_id: 'prod-1', quantity: 2 },
      { product_id: 'prod-2', quantity: 1 },
    ],
    total: 99.99,
  }, { ...tags, endpoint: '/api/v1/checkout', method: 'POST' });
}

// V2 API scenarios
function testV2APIs() {
  const tags = { version: 'v2', service: 'demo-go-api-v2' };
  
  // GET /api/products (70% of traffic)
  for (let i = 0; i < 7; i++) {
    makeRequest('GET', `${BASE_URL_V2}/api/products`, null, { ...tags, endpoint: '/api/products', method: 'GET' });
    sleep(0.1);
  }
  
  // POST /api/products (15% of traffic)
  for (let i = 0; i < 2; i++) {
    makeRequest('POST', `${BASE_URL_V2}/api/products`, {
      name: `Product-${__VU}-${Date.now()}`,
      price: Math.random() * 100,
      category: 'electronics',
    }, { ...tags, endpoint: '/api/products', method: 'POST' });
    sleep(0.1);
  }
  
  // GET /api/v2/orders (10% of traffic)
  makeRequest('GET', `${BASE_URL_V2}/api/v2/orders`, null, { ...tags, endpoint: '/api/v2/orders', method: 'GET' });
  sleep(0.1);
  
  // POST /api/v2/orders (5% of traffic)
  if (Math.random() < 0.5) {
    makeRequest('POST', `${BASE_URL_V2}/api/v2/orders`, {
      user_id: `user-${__VU}`,
      product_id: `prod-${Math.floor(Math.random() * 100)}`,
      quantity: Math.floor(Math.random() * 5) + 1,
      total: Math.random() * 500,
    }, { ...tags, endpoint: '/api/v2/orders', method: 'POST' });
  }
}

// V3 API scenarios
function testV3APIs() {
  const tags = { version: 'v3', service: 'demo-go-api-v3' };
  
  // GET /api/v3/users (30% of traffic)
  for (let i = 0; i < 3; i++) {
    makeRequest('GET', `${BASE_URL_V3}/api/v3/users`, null, { ...tags, endpoint: '/api/v3/users', method: 'GET' });
    sleep(0.1);
  }
  
  // GET /api/v3/products (30% of traffic)
  for (let i = 0; i < 3; i++) {
    makeRequest('GET', `${BASE_URL_V3}/api/v3/products`, null, { ...tags, endpoint: '/api/v3/products', method: 'GET' });
    sleep(0.1);
  }
  
  // POST /api/v3/users (10% of traffic)
  makeRequest('POST', `${BASE_URL_V3}/api/v3/users`, {
    name: `V3User-${__VU}-${Date.now()}`,
    email: `v3user${__VU}@example.com`,
    role: 'customer',
  }, { ...tags, endpoint: '/api/v3/users', method: 'POST' });
  sleep(0.1);
  
  // POST /api/v3/products (10% of traffic)
  makeRequest('POST', `${BASE_URL_V3}/api/v3/products`, {
    name: `V3Product-${__VU}`,
    price: Math.random() * 200,
    stock: Math.floor(Math.random() * 100),
  }, { ...tags, endpoint: '/api/v3/products', method: 'POST' });
  sleep(0.1);
  
  // GET /api/v3/orders (10% of traffic)
  makeRequest('GET', `${BASE_URL_V3}/api/v3/orders`, null, { ...tags, endpoint: '/api/v3/orders', method: 'GET' });
  sleep(0.1);
  
  // POST /api/v3/orders (5% of traffic)
  if (Math.random() < 0.5) {
    makeRequest('POST', `${BASE_URL_V3}/api/v3/orders`, {
      user_id: `v3user-${__VU}`,
      items: [
        { product_id: `v3prod-${Math.floor(Math.random() * 50)}`, quantity: 2 },
      ],
      total: Math.random() * 300,
    }, { ...tags, endpoint: '/api/v3/orders', method: 'POST' });
  }
  sleep(0.1);
  
  // POST /api/v3/checkout (5% of traffic)
  if (Math.random() < 0.5) {
    makeRequest('POST', `${BASE_URL_V3}/api/v3/checkout`, {
      user_id: `v3user-${__VU}`,
      payment_method: 'credit_card',
      total: Math.random() * 500,
    }, { ...tags, endpoint: '/api/v3/checkout', method: 'POST' });
  }
}

// Main test function
export default function() {
  // Health check first
  http.get(`${BASE_URL_V1}/health`, { tags: { endpoint: '/health', method: 'GET' } });
  
  // Randomize which APIs to test (simulate real user behavior)
  const rand = Math.random();
  
  if (rand < 0.33) {
    // 33% - Focus on V1
    testV1APIs();
  } else if (rand < 0.66) {
    // 33% - Focus on V2
    testV2APIs();
  } else {
    // 34% - Focus on V3
    testV3APIs();
  }
  
  // Think time between iterations
  sleep(Math.random() * 2 + 1); // 1-3 seconds
}

// Setup function (runs once per VU)
export function setup() {
  console.log('🚀 k6 Load Test Starting...');
  console.log('Target services:');
  console.log(`  - V1: ${BASE_URL_V1}`);
  console.log(`  - V2: ${BASE_URL_V2}`);
  console.log(`  - V3: ${BASE_URL_V3}`);
}

// Teardown function (runs once at the end)
export function teardown(data) {
  console.log('✅ k6 Load Test Completed!');
}

