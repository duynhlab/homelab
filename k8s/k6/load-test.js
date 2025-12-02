import http from 'k6/http';
import { check, sleep } from 'k6';
import { Rate, Trend, Counter } from 'k6/metrics';

// Custom metrics
const errorRate = new Rate('k6_errors');
const requestDuration = new Trend('k6_request_duration');
const requestsTotal = new Counter('k6_requests_total');

// Load test configuration - 9 Microservices
// Target: Sustainable load across all services
export const options = {
  stages: [
    { duration: '1m', target: 20 },    // Ramp-up to 20 VUs
    { duration: '2m', target: 50 },    // Ramp-up to 50 VUs
    { duration: '5m', target: 100 },   // Ramp-up to 100 VUs
    { duration: '10m', target: 100 },  // Stay at 100 VUs (sustainable load)
    { duration: '2m', target: 50 },    // Ramp-down to 50 VUs
    { duration: '1m', target: 0 },     // Ramp-down to 0
  ],
  thresholds: {
    http_req_duration: ['p(95)<500', 'p(99)<1000'], // Reasonable response times
    http_req_failed: ['rate<0.05'], // Allow 5% error rate
    http_reqs: ['rate>50'], // At least 50 req/s across all services
  },
};

// Service URLs for 9 microservices
const SERVICES = {
  auth: 'http://auth.auth.svc.cluster.local:8080',
  user: 'http://user.user.svc.cluster.local:8080',
  product: 'http://product.product.svc.cluster.local:8080',
  cart: 'http://cart.cart.svc.cluster.local:8080',
  order: 'http://order.order.svc.cluster.local:8080',
  review: 'http://review.review.svc.cluster.local:8080',
  notification: 'http://notification.notification.svc.cluster.local:8080',
  shipping: 'http://shipping.shipping.svc.cluster.local:8080',
  shippingV2: 'http://shipping-v2.shipping.svc.cluster.local:8080',
};

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

// Auth Service Tests
function testAuthService() {
  const tags = { service: 'auth', version: 'v1' };
  
  // POST /api/v1/auth/login (50% of auth traffic)
  makeRequest('POST', `${SERVICES.auth}/api/v1/auth/login`, {
    username: 'admin',
    password: 'password',
  }, { ...tags, endpoint: '/api/v1/auth/login', method: 'POST' });
  sleep(0.1);
  
  // POST /api/v2/auth/register (50% of auth traffic)
  makeRequest('POST', `${SERVICES.auth}/api/v2/auth/register`, {
    username: `user${__VU}`,
    email: `user${__VU}@example.com`,
    password: 'password123',
  }, { ...tags, endpoint: '/api/v2/auth/register', method: 'POST' });
  sleep(0.1);
}

// User Service Tests
function testUserService() {
  const tags = { service: 'user', version: 'v1' };
  
  // GET /api/v1/users (70% of user traffic)
  makeRequest('GET', `${SERVICES.user}/api/v1/users`, null, { ...tags, endpoint: '/api/v1/users', method: 'GET' });
  sleep(0.1);
  
  // GET /api/v2/users/:id (20% of user traffic)
  makeRequest('GET', `${SERVICES.user}/api/v2/users/1`, null, { ...tags, endpoint: '/api/v2/users/:id', method: 'GET' });
  sleep(0.1);
  
  // POST /api/v1/users (10% of user traffic)
  makeRequest('POST', `${SERVICES.user}/api/v1/users`, {
    username: `user${__VU}`,
    email: `user${__VU}@example.com`,
    name: `User ${__VU}`,
  }, { ...tags, endpoint: '/api/v1/users', method: 'POST' });
  sleep(0.1);
}

// Product Service Tests
function testProductService() {
  const tags = { service: 'product', version: 'v1' };
  
  // GET /api/v1/products (60% of product traffic)
  makeRequest('GET', `${SERVICES.product}/api/v1/products`, null, { ...tags, endpoint: '/api/v1/products', method: 'GET' });
  sleep(0.1);
  
  // GET /api/v2/catalog/items (30% of product traffic)
  makeRequest('GET', `${SERVICES.product}/api/v2/catalog/items`, null, { ...tags, endpoint: '/api/v2/catalog/items', method: 'GET' });
  sleep(0.1);
  
  // POST /api/v1/products (10% of product traffic)
  makeRequest('POST', `${SERVICES.product}/api/v1/products`, {
    name: `Product ${__VU}`,
    price: Math.random() * 100,
    description: 'Test product',
    category: 'electronics',
  }, { ...tags, endpoint: '/api/v1/products', method: 'POST' });
  sleep(0.1);
}

// Cart Service Tests
function testCartService() {
  const tags = { service: 'cart', version: 'v1' };
  
  // GET /api/v1/cart (70% of cart traffic)
  makeRequest('GET', `${SERVICES.cart}/api/v1/cart`, null, { ...tags, endpoint: '/api/v1/cart', method: 'GET' });
  sleep(0.1);
  
  // POST /api/v2/carts/:cartId/items (30% of cart traffic)
  makeRequest('POST', `${SERVICES.cart}/api/v2/carts/cart-${__VU}/items`, {
    productId: `prod-${Math.floor(Math.random() * 10)}`,
    quantity: Math.floor(Math.random() * 3) + 1,
  }, { ...tags, endpoint: '/api/v2/carts/:cartId/items', method: 'POST' });
  sleep(0.1);
}

// Order Service Tests
function testOrderService() {
  const tags = { service: 'order', version: 'v1' };
  
  // GET /api/v1/orders (50% of order traffic)
  makeRequest('GET', `${SERVICES.order}/api/v1/orders`, null, { ...tags, endpoint: '/api/v1/orders', method: 'GET' });
  sleep(0.1);
  
  // GET /api/v2/orders/:orderId/status (30% of order traffic)
  makeRequest('GET', `${SERVICES.order}/api/v2/orders/order-${__VU}/status`, null, { ...tags, endpoint: '/api/v2/orders/:orderId/status', method: 'GET' });
  sleep(0.1);
  
  // POST /api/v1/orders (20% of order traffic)
  makeRequest('POST', `${SERVICES.order}/api/v1/orders`, {
    items: [
      { productId: 'prod-1', quantity: 2, price: 100 },
      { productId: 'prod-2', quantity: 1, price: 50 },
    ],
  }, { ...tags, endpoint: '/api/v1/orders', method: 'POST' });
  sleep(0.1);
}

// Review Service Tests
function testReviewService() {
  const tags = { service: 'review', version: 'v1' };
  
  // GET /api/v1/reviews (60% of review traffic)
  makeRequest('GET', `${SERVICES.review}/api/v1/reviews`, null, { ...tags, endpoint: '/api/v1/reviews', method: 'GET' });
  sleep(0.1);
  
  // GET /api/v2/reviews/:reviewId (30% of review traffic)
  makeRequest('GET', `${SERVICES.review}/api/v2/reviews/review-${__VU}`, null, { ...tags, endpoint: '/api/v2/reviews/:reviewId', method: 'GET' });
  sleep(0.1);
  
  // POST /api/v1/reviews (10% of review traffic)
  makeRequest('POST', `${SERVICES.review}/api/v1/reviews`, {
    productId: `prod-${Math.floor(Math.random() * 10)}`,
    userId: `user-${__VU}`,
    rating: Math.floor(Math.random() * 5) + 1,
    comment: 'Great product!',
  }, { ...tags, endpoint: '/api/v1/reviews', method: 'POST' });
  sleep(0.1);
}

// Notification Service Tests
function testNotificationService() {
  const tags = { service: 'notification', version: 'v1' };
  
  // POST /api/v1/notify/email (50% of notification traffic)
  makeRequest('POST', `${SERVICES.notification}/api/v1/notify/email`, {
    to: `user${__VU}@example.com`,
    subject: 'Test Email',
    body: 'This is a test email notification',
  }, { ...tags, endpoint: '/api/v1/notify/email', method: 'POST' });
  sleep(0.1);
  
  // GET /api/v2/notifications (50% of notification traffic)
  makeRequest('GET', `${SERVICES.notification}/api/v2/notifications`, null, { ...tags, endpoint: '/api/v2/notifications', method: 'GET' });
  sleep(0.1);
}

// Shipping Service Tests
function testShippingService() {
  const tags = { service: 'shipping', version: 'v1' };
  
  // GET /api/v1/shipping/track (100% of shipping traffic)
  makeRequest('GET', `${SERVICES.shipping}/api/v1/shipping/track?trackingId=TRK${__VU}`, null, { ...tags, endpoint: '/api/v1/shipping/track', method: 'GET' });
  sleep(0.1);
}

// Shipping Service V2 Tests
function testShippingServiceV2() {
  const tags = { service: 'shipping-v2', version: 'v2' };
  
  // GET /api/v2/shipments/estimate (100% of shipping-v2 traffic)
  makeRequest('GET', `${SERVICES.shippingV2}/api/v2/shipments/estimate`, {
    origin: 'New York',
    destination: 'Los Angeles',
    weight: Math.random() * 10 + 1,
  }, { ...tags, endpoint: '/api/v2/shipments/estimate', method: 'GET' });
  sleep(0.1);
}

// Main test function
export default function() {
  // Health check - only 10% of iterations (monitoring, not load testing)
  if (Math.random() < 0.1) {
    const healthChecks = [
      `${SERVICES.auth}/health`,
      `${SERVICES.user}/health`,
      `${SERVICES.product}/health`,
      `${SERVICES.cart}/health`,
      `${SERVICES.order}/health`,
      `${SERVICES.review}/health`,
      `${SERVICES.notification}/health`,
      `${SERVICES.shipping}/health`,
      `${SERVICES.shippingV2}/health`,
    ];
    
    // Random health check
    const healthUrl = healthChecks[Math.floor(Math.random() * healthChecks.length)];
    http.get(healthUrl, { tags: { endpoint: '/health', method: 'GET' } });
  }
  
  // Randomize which service to test (simulate real user behavior)
  const rand = Math.random();
  
  if (rand < 0.11) {
    testAuthService();
  } else if (rand < 0.22) {
    testUserService();
  } else if (rand < 0.33) {
    testProductService();
  } else if (rand < 0.44) {
    testCartService();
  } else if (rand < 0.55) {
    testOrderService();
  } else if (rand < 0.66) {
    testReviewService();
  } else if (rand < 0.77) {
    testNotificationService();
  } else if (rand < 0.88) {
    testShippingService();
  } else {
    testShippingServiceV2();
  }
  
  // Think time between iterations
  sleep(Math.random() * 2 + 1); // 1-3 seconds
}

// Setup function (runs once per VU)
export function setup() {
  console.log('🚀 k6 Load Test Starting...');
  console.log('Target services:');
  console.log(`  - Auth: ${SERVICES.auth}`);
  console.log(`  - User: ${SERVICES.user}`);
  console.log(`  - Product: ${SERVICES.product}`);
  console.log(`  - Cart: ${SERVICES.cart}`);
  console.log(`  - Order: ${SERVICES.order}`);
  console.log(`  - Review: ${SERVICES.review}`);
  console.log(`  - Notification: ${SERVICES.notification}`);
  console.log(`  - Shipping: ${SERVICES.shipping}`);
  console.log(`  - Shipping V2: ${SERVICES.shippingV2}`);
}

// Teardown function (runs once at the end)
export function teardown(data) {
  console.log('✅ k6 Load Test Completed!');
}

