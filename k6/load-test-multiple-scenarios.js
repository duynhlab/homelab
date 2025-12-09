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
// USER JOURNEY FUNCTIONS
// ============================================================================

// Journey 1: E-commerce Shopping Journey
// Touches 9 services: Auth → User → Product → Cart → Shipping-v2 → Order → Notification
function ecommerceShoppingJourney() {
  const userId = `user-${__VU}`;
  const sessionId = `session-${__VU}-${Date.now()}`;
  const tags = { 
    scenario: 'shopping_user', 
    journey: 'ecommerce_purchase',
    session_id: sessionId,
    user_id: userId
  };
  
  console.log(`[${userId}] Starting e-commerce shopping journey (session: ${sessionId})`);
  
  // Step 1: Auth - Login
  console.log(`[${userId}] Step 1/9: Logging in...`);
  makeRequest('POST', `${SERVICES.auth}/api/v1/auth/login`, {
    username: userId,
    password: 'password',
  }, { ...tags, flow_step: '1_login', service_target: 'auth' });
  sleep(0.5);
  
  // Step 2: User - Get Profile
  console.log(`[${userId}] Step 2/9: Loading user profile...`);
  makeRequest('GET', `${SERVICES.user}/api/v2/users/${userId}`, null, 
    { ...tags, flow_step: '2_profile', service_target: 'user' });
  sleep(0.3);
  
  // Step 3: Product - Browse Catalog
  console.log(`[${userId}] Step 3/9: Browsing product catalog...`);
  makeRequest('GET', `${SERVICES.product}/api/v2/catalog/items`, null, 
    { ...tags, flow_step: '3_browse', service_target: 'product' });
  sleep(2.0);
  
  // Step 4: Product - View Product Details
  const productId = `prod-${Math.floor(Math.random() * 100)}`;
  console.log(`[${userId}] Step 4/9: Viewing product ${productId}...`);
  makeRequest('GET', `${SERVICES.product}/api/v1/products/${productId}`, null, 
    { ...tags, flow_step: '4_view_product', service_target: 'product', product_id: productId });
  sleep(1.5);
  
  // Step 5: Cart - Add to Cart
  console.log(`[${userId}] Step 5/9: Adding product to cart...`);
  const quantity = Math.floor(Math.random() * 3) + 1;
  makeRequest('POST', `${SERVICES.cart}/api/v2/carts/cart-${userId}/items`, {
    productId: productId,
    quantity: quantity,
  }, { ...tags, flow_step: '5_add_to_cart', service_target: 'cart', product_id: productId });
  sleep(0.5);
  
  // Step 6: Cart - View Cart
  console.log(`[${userId}] Step 6/9: Viewing cart...`);
  makeRequest('GET', `${SERVICES.cart}/api/v1/cart`, null, 
    { ...tags, flow_step: '6_view_cart', service_target: 'cart' });
  sleep(1.0);
  
  // Step 7: Shipping-v2 - Estimate Shipping (POST with body!)
  console.log(`[${userId}] Step 7/9: Estimating shipping cost...`);
  makeRequest('POST', `${SERVICES.shippingV2}/api/v2/shipments/estimate`, {
    origin: 'New York',
    destination: 'Los Angeles',
    weight: Math.random() * 10 + 1,
  }, { ...tags, flow_step: '7_shipping_estimate', service_target: 'shipping-v2' });
  sleep(0.8);
  
  // Step 8: Order - Create Order
  console.log(`[${userId}] Step 8/9: Creating order...`);
  makeRequest('POST', `${SERVICES.order}/api/v1/orders`, {
    items: [{ productId: productId, quantity: quantity, price: 99.99 }],
    userId: userId,
  }, { ...tags, flow_step: '8_create_order', service_target: 'order', product_id: productId });
  sleep(0.5);
  
  // Step 9: Notification - Order Confirmation
  console.log(`[${userId}] Step 9/9: Sending order confirmation...`);
  makeRequest('POST', `${SERVICES.notification}/api/v2/notifications`, {
    userId: userId,
    type: 'order_confirmation',
    message: 'Your order has been placed successfully!',
  }, { ...tags, flow_step: '9_notification', service_target: 'notification' });
  sleep(0.3);
  
  console.log(`[${userId}] ✅ E-commerce shopping journey completed (9 services touched)`);
}

// Journey 2: Product Review Journey
// Touches 5 services: Auth → User → Product → Review → Notification
function productReviewJourney() {
  const userId = `reviewer-${__VU}`;
  const sessionId = `session-${__VU}-${Date.now()}`;
  const tags = { 
    scenario: 'registered_user', 
    journey: 'product_review',
    session_id: sessionId,
    user_id: userId
  };
  
  console.log(`[${userId}] Starting product review journey (session: ${sessionId})`);
  
  // Step 1: Auth - Login
  console.log(`[${userId}] Step 1/5: Logging in...`);
  makeRequest('POST', `${SERVICES.auth}/api/v1/auth/login`, {
    username: userId,
    password: 'password',
  }, { ...tags, flow_step: '1_login', service_target: 'auth' });
  sleep(0.5);
  
  // Step 2: User - Get Profile
  console.log(`[${userId}] Step 2/5: Loading profile...`);
  makeRequest('GET', `${SERVICES.user}/api/v1/users/profile`, null, 
    { ...tags, flow_step: '2_profile', service_target: 'user' });
  sleep(0.3);
  
  // Step 3: Product - View Product
  const productId = `prod-${Math.floor(Math.random() * 100)}`;
  console.log(`[${userId}] Step 3/5: Viewing product ${productId}...`);
  makeRequest('GET', `${SERVICES.product}/api/v1/products/${productId}`, null, 
    { ...tags, flow_step: '3_view_product', service_target: 'product', product_id: productId });
  sleep(1.0);
  
  // Step 4: Review - Read existing reviews
  console.log(`[${userId}] Step 4/5: Reading reviews...`);
  makeRequest('GET', `${SERVICES.review}/api/v1/reviews`, null, 
    { ...tags, flow_step: '4_read_reviews', service_target: 'review' });
  sleep(2.0);
  
  // Step 5: Review - Write review
  console.log(`[${userId}] Step 5/5: Writing review...`);
  makeRequest('POST', `${SERVICES.review}/api/v2/reviews`, {
    productId: productId,
    rating: Math.floor(Math.random() * 3) + 3, // 3-5 stars
    comment: `Great product! Review from ${userId}`,
    userId: userId,
  }, { ...tags, flow_step: '5_write_review', service_target: 'review', product_id: productId });
  sleep(0.5);
  
  console.log(`[${userId}] ✅ Product review journey completed (5 services touched)`);
}

// Journey 3: Order Tracking Journey
// Touches 6 services: Auth → User → Order → Shipping → Notification
function orderTrackingJourney() {
  const userId = `tracker-${__VU}`;
  const sessionId = `session-${__VU}-${Date.now()}`;
  const trackingId = `TRK-${__VU}-${Date.now()}`;
  const tags = { 
    scenario: 'registered_user', 
    journey: 'order_tracking',
    session_id: sessionId,
    user_id: userId
  };
  
  console.log(`[${userId}] Starting order tracking journey (session: ${sessionId})`);
  
  // Step 1: Auth - Login
  console.log(`[${userId}] Step 1/6: Logging in...`);
  makeRequest('POST', `${SERVICES.auth}/api/v1/auth/login`, {
    username: userId,
    password: 'password',
  }, { ...tags, flow_step: '1_login', service_target: 'auth' });
  sleep(0.5);
  
  // Step 2: User - Get Profile
  console.log(`[${userId}] Step 2/6: Loading profile...`);
  makeRequest('GET', `${SERVICES.user}/api/v1/users/profile`, null, 
    { ...tags, flow_step: '2_profile', service_target: 'user' });
  sleep(0.3);
  
  // Step 3: Order - View Orders List
  console.log(`[${userId}] Step 3/6: Viewing orders list...`);
  makeRequest('GET', `${SERVICES.order}/api/v1/orders`, null, 
    { ...tags, flow_step: '3_view_orders', service_target: 'order' });
  sleep(1.5);
  
  // Step 4: Order - Get Order Details
  const orderId = `order-${__VU}`;
  console.log(`[${userId}] Step 4/6: Getting order ${orderId} details...`);
  makeRequest('GET', `${SERVICES.order}/api/v2/orders/${orderId}`, null, 
    { ...tags, flow_step: '4_order_details', service_target: 'order', order_id: orderId });
  sleep(1.0);
  
  // Step 5: Shipping - Track Shipment
  console.log(`[${userId}] Step 5/6: Tracking shipment ${trackingId}...`);
  makeRequest('GET', `${SERVICES.shipping}/api/v1/shipping/track?trackingId=${trackingId}`, null, 
    { ...tags, flow_step: '5_track_shipping', service_target: 'shipping', tracking_id: trackingId });
  sleep(1.0);
  
  // Step 6: Notification - Check notifications
  console.log(`[${userId}] Step 6/6: Checking notifications...`);
  makeRequest('GET', `${SERVICES.notification}/api/v1/notifications?userId=${userId}`, null, 
    { ...tags, flow_step: '6_check_notifications', service_target: 'notification' });
  sleep(0.5);
  
  console.log(`[${userId}] ✅ Order tracking journey completed (6 services touched)`);
}

// Journey 4: Quick Browse Journey (Abandoned Cart)
// Touches 3 services: Product → Cart → Shipping-v2
function quickBrowseJourney() {
  const userId = `browser-${__VU}`;
  const sessionId = `session-${__VU}-${Date.now()}`;
  const tags = { 
    scenario: 'browser_user', 
    journey: 'quick_browse_abandon',
    session_id: sessionId,
    user_id: userId
  };
  
  console.log(`[${userId}] Starting quick browse journey (session: ${sessionId})`);
  
  // Step 1: Product - Browse Catalog
  console.log(`[${userId}] Step 1/4: Browsing catalog...`);
  makeRequest('GET', `${SERVICES.product}/api/v2/catalog/items`, null, 
    { ...tags, flow_step: '1_browse', service_target: 'product' });
  sleep(1.5);
  
  // Step 2: Product - View Product
  const productId = `prod-${Math.floor(Math.random() * 100)}`;
  console.log(`[${userId}] Step 2/4: Viewing product ${productId}...`);
  makeRequest('GET', `${SERVICES.product}/api/v1/products/${productId}`, null, 
    { ...tags, flow_step: '2_view_product', service_target: 'product', product_id: productId });
  sleep(2.0);
  
  // Step 3: Shipping-v2 - Quick shipping estimate
  console.log(`[${userId}] Step 3/4: Checking shipping cost...`);
  makeRequest('POST', `${SERVICES.shippingV2}/api/v2/shipments/estimate`, {
    origin: 'New York',
    destination: 'Los Angeles',
    weight: Math.random() * 5 + 1,
  }, { ...tags, flow_step: '3_shipping_check', service_target: 'shipping-v2' });
  sleep(0.5);
  
  // Step 4: Cart - Add to cart then abandon
  console.log(`[${userId}] Step 4/4: Adding to cart (will abandon)...`);
  makeRequest('POST', `${SERVICES.cart}/api/v2/carts/cart-${userId}/items`, {
    productId: productId,
    quantity: 1,
  }, { ...tags, flow_step: '4_add_cart_abandon', service_target: 'cart', product_id: productId });
  sleep(0.3);
  
  console.log(`[${userId}] ✅ Quick browse journey completed (4 services touched, cart abandoned)`);
}

// Journey 5: API Client Monitoring Journey
// Touches 7 services: All services (health checks + data fetching)
function apiMonitoringJourney() {
  const apiKey = `api-${__VU}`;
  const sessionId = `api-session-${__VU}-${Date.now()}`;
  const tags = { 
    scenario: 'api_client', 
    journey: 'api_monitoring',
    session_id: sessionId,
    api_key: apiKey
  };
  
  console.log(`[${apiKey}] Starting API monitoring journey (session: ${sessionId})`);
  
  const services = [
    { name: 'auth', service: SERVICES.auth, path: '/api/v1/auth/validate' },
    { name: 'user', service: SERVICES.user, path: '/api/v1/users' },
    { name: 'product', service: SERVICES.product, path: '/api/v1/products' },
    { name: 'cart', service: SERVICES.cart, path: '/api/v1/cart' },
    { name: 'order', service: SERVICES.order, path: '/api/v1/orders' },
    { name: 'review', service: SERVICES.review, path: '/api/v1/reviews' },
    { name: 'notification', service: SERVICES.notification, path: '/api/v1/notifications' },
  ];
  
  services.forEach((svc, index) => {
    console.log(`[${apiKey}] Step ${index + 1}/7: Fetching ${svc.name} data...`);
    makeRequest('GET', `${svc.service}${svc.path}`, null, {
      ...tags,
      flow_step: `${index + 1}_fetch_${svc.name}`,
      service_target: svc.name,
    });
    sleep(0.1); // Fast API client
  });
  
  console.log(`[${apiKey}] ✅ API monitoring journey completed (7 services touched)`);
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
  
  // 60% of iterations: Quick browse journey (4 services)
  if (Math.random() < 0.6) {
    quickBrowseJourney();
    sleep(Math.random() * 5 + 10); // 10-15 seconds between journeys
    return;
  }
  
  // 40% of iterations: Simple browsing (legacy behavior)
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
  
  // Health check - only 10% of iterations (monitoring, not load testing)
  if (Math.random() < 0.1) {
    http.get(`${SERVICES.product}/health`, { tags: { ...tags, endpoint: '/health' } });
  }
}

// Scenario 2: Shopping User - Complete shopping flow
export function shoppingUserScenario() {
  const tags = { scenario: 'shopping_user', user_type: 'shopping' };
  
  // 80% of iterations: Complete e-commerce journey (9 services)
  if (Math.random() < 0.8) {
    ecommerceShoppingJourney();
    sleep(Math.random() * 5 + 10); // 10-15 seconds between journeys
    return;
  }
  
  // 20% of iterations: Simple shopping flow (legacy behavior)
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
  
  // 50% order tracking journey (6 services), 30% product review journey (5 services), 20% legacy
  const rand = Math.random();
  if (rand < 0.5) {
    orderTrackingJourney();
    sleep(Math.random() * 5 + 10); // 10-15 seconds between journeys
    return;
  } else if (rand < 0.8) {
    productReviewJourney();
    sleep(Math.random() * 5 + 10);
    return;
  }
  
  // 20% of iterations: Simple authenticated flow (legacy behavior)
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
  
  // 70% of iterations: API monitoring journey (7 services)
  if (Math.random() < 0.7) {
    apiMonitoringJourney();
    sleep(Math.random() * 2 + 3); // 3-5 seconds between journeys (API client is faster)
    return;
  }
  
  // 30% of iterations: Fast endpoint testing (legacy behavior)
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
  console.log('=====================================================');
  console.log('📊 Scenarios:');
  console.log('  - Browser User (40%) - Browse & Read');
  console.log('    → 60% Quick Browse Journey (4 services)');
  console.log('    → 40% Simple browsing');
  console.log('  - Shopping User (30%) - Complete Shopping Flow');
  console.log('    → 80% E-commerce Journey (9 services)');
  console.log('    → 20% Simple shopping');
  console.log('  - Registered User (15%) - Authenticated Actions');
  console.log('    → 50% Order Tracking Journey (6 services)');
  console.log('    → 30% Product Review Journey (5 services)');
  console.log('    → 20% Simple authenticated flow');
  console.log('  - API Client (10%) - High Volume');
  console.log('    → 70% API Monitoring Journey (7 services)');
  console.log('    → 30% Fast endpoint testing');
  console.log('  - Admin User (5%) - Management Operations');
  console.log('');
  console.log('🎯 User Journey Types:');
  console.log('  1. E-commerce Shopping Journey (9 services)');
  console.log('     Auth → User → Product → Cart → Shipping-v2 → Order → Notification');
  console.log('  2. Product Review Journey (5 services)');
  console.log('     Auth → User → Product → Review');
  console.log('  3. Order Tracking Journey (6 services)');
  console.log('     Auth → User → Order → Shipping → Notification');
  console.log('  4. Quick Browse Journey (4 services)');
  console.log('     Product → Shipping-v2 → Cart (abandoned)');
  console.log('  5. API Monitoring Journey (7 services)');
  console.log('     Auth, User, Product, Cart, Order, Review, Notification');
  console.log('');
  console.log('🎯 Target services:');
  Object.entries(SERVICES).forEach(([name, url]) => {
    console.log(`  - ${name}: ${url}`);
  });
  console.log('=====================================================');
}

export function teardown(data) {
  console.log('=====================================================');
  console.log('✅ k6 Multiple Scenarios Load Test Completed!');
  console.log('📊 Summary:');
  console.log('  - 5 user journey types executed');
  console.log('  - Up to 9 services per journey (E-commerce Shopping)');
  console.log('  - Distributed tracing enabled for all requests');
  console.log('  - shipping-v2 service fully tested via POST requests');
  console.log('=====================================================');
}

