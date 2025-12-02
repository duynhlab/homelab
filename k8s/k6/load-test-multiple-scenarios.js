import http from 'k6/http';
import { check, sleep } from 'k6';
import { Rate, Trend, Counter } from 'k6/metrics';

// Custom metrics
const errorRate = new Rate('k6_errors');
const requestDuration = new Trend('k6_request_duration');
const requestsTotal = new Counter('k6_requests_total');

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

// ============================================================================
// MULTIPLE SCENARIOS CONFIGURATION
// ============================================================================

export const options = {
  // Use scenarios - Multiple user personas with different behaviors
  scenarios: {
    // Scenario 1: Browser User (40% of traffic) - Browse & Read
    browser_user: {
      executor: 'ramping-vus',
      startVUs: 0,
      stages: [
        { duration: '1m', target: 8 },     // 40% of 20 VUs
        { duration: '2m', target: 20 },    // 40% of 50 VUs
        { duration: '5m', target: 40 },    // 40% of 100 VUs
        { duration: '10m', target: 40 },   // Stay at 40 VUs
        { duration: '2m', target: 20 },    // Ramp-down
        { duration: '1m', target: 0 },     // Ramp-down to 0
      ],
      gracefulRampDown: '30s',
      exec: 'browserUserScenario',
      tags: { scenario: 'browser_user' },
    },

    // Scenario 2: Shopping User (30% of traffic) - Complete Shopping Flow
    shopping_user: {
      executor: 'ramping-vus',
      startVUs: 0,
      stages: [
        { duration: '1m', target: 6 },     // 30% of 20 VUs
        { duration: '2m', target: 15 },    // 30% of 50 VUs
        { duration: '5m', target: 30 },    // 30% of 100 VUs
        { duration: '10m', target: 30 },   // Stay at 30 VUs
        { duration: '2m', target: 15 },    // Ramp-down
        { duration: '1m', target: 0 },     // Ramp-down to 0
      ],
      gracefulRampDown: '30s',
      exec: 'shoppingUserScenario',
      tags: { scenario: 'shopping_user' },
    },

    // Scenario 3: Registered User (15% of traffic) - Authenticated Actions
    registered_user: {
      executor: 'ramping-vus',
      startVUs: 0,
      stages: [
        { duration: '1m', target: 3 },     // 15% of 20 VUs
        { duration: '2m', target: 8 },      // 15% of 50 VUs
        { duration: '5m', target: 15 },     // 15% of 100 VUs
        { duration: '10m', target: 15 },    // Stay at 15 VUs
        { duration: '2m', target: 8 },      // Ramp-down
        { duration: '1m', target: 0 },      // Ramp-down to 0
      ],
      gracefulRampDown: '30s',
      exec: 'registeredUserScenario',
      tags: { scenario: 'registered_user' },
    },

    // Scenario 4: API Client (10% of traffic) - High Volume
    api_client: {
      executor: 'ramping-vus',
      startVUs: 0,
      stages: [
        { duration: '1m', target: 2 },     // 10% of 20 VUs
        { duration: '2m', target: 5 },     // 10% of 50 VUs
        { duration: '5m', target: 10 },    // 10% of 100 VUs
        { duration: '10m', target: 10 },   // Stay at 10 VUs
        { duration: '2m', target: 5 },     // Ramp-down
        { duration: '1m', target: 0 },     // Ramp-down to 0
      ],
      gracefulRampDown: '30s',
      exec: 'apiClientScenario',
      tags: { scenario: 'api_client' },
    },

    // Scenario 5: Admin User (5% of traffic) - Management Operations
    admin_user: {
      executor: 'ramping-vus',
      startVUs: 0,
      stages: [
        { duration: '1m', target: 1 },     // 5% of 20 VUs
        { duration: '2m', target: 3 },     // 5% of 50 VUs
        { duration: '5m', target: 5 },     // 5% of 100 VUs
        { duration: '10m', target: 5 },    // Stay at 5 VUs
        { duration: '2m', target: 3 },     // Ramp-down
        { duration: '1m', target: 0 },     // Ramp-down to 0
      ],
      gracefulRampDown: '30s',
      exec: 'adminUserScenario',
      tags: { scenario: 'admin_user' },
    },
  },

  thresholds: {
    // Global thresholds
    http_req_duration: ['p(95)<500', 'p(99)<1000'],
    http_req_failed: ['rate<0.05'],
    http_reqs: ['rate>50'],
    
    // Per-scenario thresholds
    'http_req_duration{scenario:browser_user}': ['p(95)<500'],
    'http_req_duration{scenario:shopping_user}': ['p(95)<1000'], // Shopping flow can be slower
    'http_req_duration{scenario:registered_user}': ['p(95)<500'],
    'http_req_duration{scenario:api_client}': ['p(95)<300'],     // API clients expect fast response
    'http_req_duration{scenario:admin_user}': ['p(95)<500'],
  },
};

// ============================================================================
// SCENARIO FUNCTIONS
// ============================================================================

// Scenario 1: Browser User - Browse products, read reviews, view catalog
export function browserUserScenario() {
  const tags = { scenario: 'browser_user', user_type: 'browser' };
  
  // Browse products (70% of browser traffic)
  const browseRand = Math.random();
  if (browseRand < 0.5) {
    // GET products v1
    makeRequest('GET', `${SERVICES.product}/api/v1/products`, null, {
      ...tags,
      endpoint: '/api/v1/products',
      method: 'GET',
    });
    sleep(Math.random() * 2 + 2); // 2-4 seconds (browsing)
  } else if (browseRand < 0.8) {
    // GET catalog v2
    makeRequest('GET', `${SERVICES.product}/api/v2/catalog/items`, null, {
      ...tags,
      endpoint: '/api/v2/catalog/items',
      method: 'GET',
    });
    sleep(Math.random() * 2 + 2);
  } else {
    // Read reviews
    makeRequest('GET', `${SERVICES.review}/api/v1/reviews`, null, {
      ...tags,
      endpoint: '/api/v1/reviews',
      method: 'GET',
    });
    sleep(Math.random() * 2 + 2);
  }
  
  // View shipping estimates (20% of browser traffic)
  if (Math.random() < 0.2) {
    makeRequest('GET', `${SERVICES.shippingV2}/api/v2/shipments/estimate`, null, {
      ...tags,
      endpoint: '/api/v2/shipments/estimate',
      method: 'GET',
    });
    sleep(Math.random() * 1 + 1); // 1-2 seconds
  }
  
  // Health check - only 10% of iterations (monitoring, not load testing)
  if (Math.random() < 0.1) {
    http.get(`${SERVICES.product}/health`, { tags: { ...tags, endpoint: '/health' } });
  }
}

// Scenario 2: Shopping User - Complete shopping flow
export function shoppingUserScenario() {
  const tags = { scenario: 'shopping_user', user_type: 'shopping' };
  
  // Step 1: Browse products
  makeRequest('GET', `${SERVICES.product}/api/v1/products`, null, {
    ...tags,
    endpoint: '/api/v1/products',
    method: 'GET',
    flow_step: 'browse',
  });
  sleep(Math.random() * 3 + 2); // 2-5 seconds (looking at products)
  
  // Step 2: Add to cart (70% proceed to cart)
  if (Math.random() < 0.7) {
    makeRequest('POST', `${SERVICES.cart}/api/v2/carts/cart-${__VU}/items`, {
      productId: `prod-${Math.floor(Math.random() * 10)}`,
      quantity: Math.floor(Math.random() * 3) + 1,
    }, {
      ...tags,
      endpoint: '/api/v2/carts/:cartId/items',
      method: 'POST',
      flow_step: 'add_to_cart',
    });
    sleep(Math.random() * 2 + 1); // 1-3 seconds
  }
  
  // Step 3: View cart
  makeRequest('GET', `${SERVICES.cart}/api/v1/cart`, null, {
    ...tags,
    endpoint: '/api/v1/cart',
    method: 'GET',
    flow_step: 'view_cart',
  });
  sleep(Math.random() * 2 + 1);
  
  // Step 4: Place order (50% of cart viewers)
  if (Math.random() < 0.5) {
    makeRequest('POST', `${SERVICES.order}/api/v1/orders`, {
      items: [
        { productId: 'prod-1', quantity: 2, price: 100 },
        { productId: 'prod-2', quantity: 1, price: 50 },
      ],
    }, {
      ...tags,
      endpoint: '/api/v1/orders',
      method: 'POST',
      flow_step: 'place_order',
    });
    sleep(Math.random() * 2 + 1);
  }
  
  // Health check - only 10% of iterations (monitoring, not load testing)
  if (Math.random() < 0.1) {
    http.get(`${SERVICES.cart}/health`, { tags: { ...tags, endpoint: '/health' } });
  }
}

// Scenario 3: Registered User - Authenticated user actions
export function registeredUserScenario() {
  const tags = { scenario: 'registered_user', user_type: 'registered' };
  
  // Step 1: Login
  makeRequest('POST', `${SERVICES.auth}/api/v1/auth/login`, {
    username: `user${__VU}`,
    password: 'password',
  }, {
    ...tags,
    endpoint: '/api/v1/auth/login',
    method: 'POST',
    flow_step: 'login',
  });
  sleep(Math.random() * 1 + 0.5); // 0.5-1.5 seconds
  
  // Step 2: View profile
  makeRequest('GET', `${SERVICES.user}/api/v1/users/profile`, null, {
    ...tags,
    endpoint: '/api/v1/users/profile',
    method: 'GET',
    flow_step: 'view_profile',
  });
  sleep(Math.random() * 1 + 1); // 1-2 seconds
  
  // Step 3: View orders (80% of logged-in users)
  if (Math.random() < 0.8) {
    makeRequest('GET', `${SERVICES.order}/api/v1/orders`, null, {
      ...tags,
      endpoint: '/api/v1/orders',
      method: 'GET',
      flow_step: 'view_orders',
    });
    sleep(Math.random() * 1 + 1);
  }
  
  // Step 4: Track shipping (50% of order viewers)
  if (Math.random() < 0.5) {
    makeRequest('GET', `${SERVICES.shipping}/api/v1/shipping/track?trackingId=TRK${__VU}`, null, {
      ...tags,
      endpoint: '/api/v1/shipping/track',
      method: 'GET',
      flow_step: 'track_shipping',
    });
    sleep(Math.random() * 1 + 1);
  }
  
  // Health check - only 10% of iterations (monitoring, not load testing)
  if (Math.random() < 0.1) {
    http.get(`${SERVICES.user}/health`, { tags: { ...tags, endpoint: '/health' } });
  }
}

// Scenario 4: API Client - High volume, all endpoints
export function apiClientScenario() {
  const tags = { scenario: 'api_client', user_type: 'api' };
  
  // Test multiple endpoints quickly (API client behavior)
  const endpoints = [
    { service: SERVICES.product, path: '/api/v1/products', method: 'GET' },
    { service: SERVICES.user, path: '/api/v1/users', method: 'GET' },
    { service: SERVICES.order, path: '/api/v1/orders', method: 'GET' },
    { service: SERVICES.review, path: '/api/v1/reviews', method: 'GET' },
    { service: SERVICES.cart, path: '/api/v1/cart', method: 'GET' },
  ];
  
  // Randomly select 2-3 endpoints per iteration
  const numEndpoints = Math.floor(Math.random() * 2) + 2; // 2-3 endpoints
  const selectedEndpoints = endpoints
    .sort(() => Math.random() - 0.5)
    .slice(0, numEndpoints);
  
  selectedEndpoints.forEach(endpoint => {
    makeRequest(endpoint.method, `${endpoint.service}${endpoint.path}`, null, {
      ...tags,
      endpoint: endpoint.path,
      method: endpoint.method,
    });
    sleep(0.1); // Fast API client (100ms between requests)
  });
  
  // Health check
  http.get(`${SERVICES.product}/health`, { tags: { ...tags, endpoint: '/health' } });
}

// Scenario 5: Admin User - Management operations
export function adminUserScenario() {
  const tags = { scenario: 'admin_user', user_type: 'admin' };
  
  // Admin operations mix
  const adminRand = Math.random();
  
  if (adminRand < 0.4) {
    // Create product (40% of admin traffic)
    makeRequest('POST', `${SERVICES.product}/api/v1/products`, {
      name: `Product ${__VU}`,
      price: Math.random() * 100,
      description: 'Admin created product',
      category: 'electronics',
    }, {
      ...tags,
      endpoint: '/api/v1/products',
      method: 'POST',
      operation: 'create_product',
    });
    sleep(Math.random() * 1 + 0.5);
  } else if (adminRand < 0.7) {
    // Create user (30% of admin traffic)
    makeRequest('POST', `${SERVICES.user}/api/v1/users`, {
      username: `admin-user-${__VU}`,
      email: `admin-user-${__VU}@example.com`,
      name: `Admin User ${__VU}`,
    }, {
      ...tags,
      endpoint: '/api/v1/users',
      method: 'POST',
      operation: 'create_user',
    });
    sleep(Math.random() * 1 + 0.5);
  } else {
    // View users/products for management (30% of admin traffic)
    makeRequest('GET', `${SERVICES.user}/api/v1/users`, null, {
      ...tags,
      endpoint: '/api/v1/users',
      method: 'GET',
      operation: 'view_users',
    });
    sleep(Math.random() * 1 + 1);
  }
  
  // Health check - only 10% of iterations (monitoring, not load testing)
  if (Math.random() < 0.1) {
    http.get(`${SERVICES.user}/health`, { tags: { ...tags, endpoint: '/health' } });
  }
}

// ============================================================================
// SETUP & TEARDOWN
// ============================================================================

export function setup() {
  console.log('🚀 k6 Multiple Scenarios Load Test Starting...');
  console.log('Scenarios:');
  console.log('  - Browser User (40%) - Browse & Read');
  console.log('  - Shopping User (30%) - Complete Shopping Flow');
  console.log('  - Registered User (15%) - Authenticated Actions');
  console.log('  - API Client (10%) - High Volume');
  console.log('  - Admin User (5%) - Management Operations');
  console.log('\nTarget services:');
  Object.entries(SERVICES).forEach(([name, url]) => {
    console.log(`  - ${name}: ${url}`);
  });
}

export function teardown(data) {
  console.log('✅ k6 Multiple Scenarios Load Test Completed!');
}

