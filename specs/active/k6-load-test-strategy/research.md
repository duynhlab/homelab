# Research: Advanced k6 Load Testing Strategy

**Task ID:** k6-load-test-strategy
**Date:** 2025-12-25
**Status:** Complete

---

## Executive Summary

Current k6 implementation uses `ramping-vus` executor with fixed time-based stages (morning ramp-up, peaks, dips). While functional, this approach has limitations for DevOps/SRE production scenarios: fixed patterns don't capture sudden traffic spikes, burst patterns, or realistic arrival rates. Additionally, **current journeys skip the registration step** - they start with login, missing the full user lifecycle (register → login → browse → purchase).

**Critical Requirement**: k6 must test **full user journeys** that simulate complete end-to-end workflows: account registration → login → browsing products → reading from database → creating orders. This tests the entire stack (Web Layer → Logic Layer → Database Layer), not just API endpoints.

Research reveals three advanced approaches: **arrival-rate executors** (most realistic), **shared-iterations with weighted scenarios** (better control), and **hybrid executors** (combining both). 

**Primary Recommendation**: 
1. **Migrate to `ramping-arrival-rate` executor** with multiple scenarios for realistic production traffic simulation
2. **Enhance journeys to include registration step** - Full user lifecycle: Register → Login → Browse → View Product (DB read) → Add to Cart → Create Order → Read Reviews (DB read)
3. **Focus on end-to-end testing** - Test complete flow from web layer through logic layer to database layer

This approach simulates actual user arrival patterns (requests per second) rather than virtual users, better matching real-world behavior where traffic spikes occur independently of user count. For DevOps/SRE use cases, this provides more accurate capacity planning, identifies bottlenecks during sudden traffic increases, and validates database performance under realistic load.

**Alternative Approach**: Use `shared-iterations` executor with weighted scenario distribution for better control over journey mix, or hybrid approach combining arrival-rate for baseline with ramping-vus for spike simulation.

---

## Codebase Analysis

### Current Implementation

**File:** `k6/load-test-multiple-scenarios.js` (1017 lines)

**Current Pattern:**
- **Executor**: `ramping-vus` (ramping virtual users)
- **Load Pattern**: Fixed time-based stages (8 phases over 6.5 hours)
- **VU Distribution**: 250 peak VUs (100 browser + 75 shopping + 37 registered + 25 API + 13 admin)
- **Stages**: Linear ramp-up/down with fixed percentages (0% → 60% → 100% → 70% → 90% → 100% → 50% → 20% → 0%)

**Code Example:**
```javascript
scenarios: {
  browser_user: {
    executor: 'ramping-vus',
    startVUs: 0,
    stages: [
      { duration: '30m', target: calculateTarget(PEAK_VUS.browser_user, 0.6) },
      { duration: '60m', target: calculateTarget(PEAK_VUS.browser_user, 1.0) },
      // ... more stages
    ],
    exec: 'browserUserScenario',
  }
}
```

**Limitations Identified:**
1. **Fixed Patterns**: Linear ramp-up/down doesn't capture sudden spikes
2. **VU-Based**: Focuses on virtual users, not actual request arrival rates
3. **Predictable**: Same pattern every time, doesn't simulate unpredictable traffic
4. **No Burst Simulation**: Can't simulate sudden traffic bursts (e.g., flash sales, viral content)
5. **Limited Realism**: Real users arrive independently, not in synchronized waves
6. **Missing Registration Flow**: Current journeys start with login, not full user registration → login flow

### Full User Journey Testing (Critical Requirement)

**What is Full User Journey Testing?**

Full user journey testing simulates complete end-to-end user workflows, starting from account creation through all interactions, including database reads. This tests the **entire stack**: Web Layer → Logic Layer → Database Layer.

**Example Full Journey:**
1. **Register Account** (`POST /api/v1/auth/register` or `/api/v2/auth/register`)
   - Creates user account in database
   - Tests Auth service → Database write
   
2. **Login** (`POST /api/v1/auth/login` or `/api/v2/auth/login`)
   - Authenticates user
   - Tests Auth service → Database read
   
3. **Get User Profile** (`GET /api/v1/users/profile` or `/api/v2/users/:id`)
   - Retrieves user data
   - Tests User service → Database read
   
4. **Browse Products** (`GET /api/v1/products` or `/api/v2/catalog/items`)
   - Lists products from database
   - Tests Product service → Database read (full stack)
   
5. **View Product Details** (`GET /api/v1/products/:id` or `/api/v2/catalog/items/:itemId`)
   - Retrieves product details from database
   - Tests Product service → Database read (full stack)
   
6. **Add to Cart** (`POST /api/v2/carts/:cartId/items`)
   - Creates cart entry
   - Tests Cart service → Database write
   
7. **View Cart** (`GET /api/v1/cart` or `/api/v2/carts/:cartId`)
   - Retrieves cart from database
   - Tests Cart service → Database read (full stack)
   
8. **Create Order** (`POST /api/v1/orders` or `/api/v2/orders`)
   - Creates order in database
   - Tests Order service → Database write
   
9. **Read Reviews** (`GET /api/v1/reviews` or `/api/v2/reviews/:reviewId`)
   - Retrieves reviews from database
   - Tests Review service → Database read (full stack)

**Why Full Journey Testing Matters:**
- ✅ **Tests Complete Stack**: Web → Logic → Database (not just API endpoints)
- ✅ **Realistic Load**: Simulates actual user behavior (register → use → interact)
- ✅ **Database Performance**: Tests database read/write performance under load
- ✅ **End-to-End Latency**: Measures complete request flow latency
- ✅ **Data Consistency**: Verifies data flows correctly through all layers
- ✅ **Production-Like**: Matches real user behavior patterns

**Current Gap:**
- Current journeys start with login (assumes user exists)
- Missing registration step (account creation)
- Need to add full registration → login → browse → purchase flow

### Existing Journey Functions

**8 Journey Types Found:**
1. E-commerce Shopping Journey (9 services) - Complete purchase flow
   - **Current**: Starts with login (missing registration)
   - **Should Include**: Register → Login → Browse → Purchase
   
2. Product Review Journey (5 services) - Review workflow
   - **Current**: Starts with login
   - **Should Include**: Register → Login → View Product → Write Review
   
3. Order Tracking Journey (6 services) - Order management
   - **Current**: Starts with login
   - **Should Include**: Register → Login → View Orders → Track
   
4. Quick Browse Journey (4 services) - Abandoned cart scenario
   - **Current**: No authentication (browsing only)
   - **Should Include**: Register → Browse → Add to Cart → Abandon
   
5. API Monitoring Journey (7 services) - API client behavior
   - **Current**: Fast endpoint testing
   - **Note**: May not need registration (API client scenario)
   
6. Timeout/Retry Journey - Resilience testing
7. Concurrent Operations Journey - Race condition testing
8. Error Handling Journey - Error scenario testing

**Journey Distribution:**
- Browser User: 60% Quick Browse, 40% Simple browsing
- Shopping User: 80% E-commerce Journey, 10% Concurrent Ops, 10% Simple shopping
- Registered User: 50% Order Tracking, 30% Product Review, 15% Error Handling, 5% Simple
- API Client: 70% API Monitoring, 10% Timeout/Retry, 20% Fast endpoints
- Admin User: Management operations

**Available APIs for Full Journey (from API_REFERENCE.md):**

**Auth Service:**
- `POST /api/v1/auth/register` - User registration (v1)
- `POST /api/v2/auth/register` - User registration (v2)
- `POST /api/v1/auth/login` - User login (v1)
- `POST /api/v2/auth/login` - User login (v2)

**User Service:**
- `GET /api/v1/users/:id` - Get user by ID (reads from database)
- `GET /api/v2/users/:id` - Get user by ID v2 (reads from database)
- `GET /api/v1/users/profile` - Get user profile (reads from database)
- `POST /api/v1/users` - Create new user (writes to database)

**Product Service:**
- `GET /api/v1/products` - Get all products (reads from database)
- `GET /api/v1/products/:id` - Get product by ID (reads from database)
- `GET /api/v2/catalog/items` - Get all catalog items (reads from database)
- `GET /api/v2/catalog/items/:itemId` - Get catalog item by ID (reads from database)

**Cart Service:**
- `GET /api/v1/cart` - Get cart (reads from database)
- `POST /api/v2/carts/:cartId/items` - Add item to cart (writes to database)

**Order Service:**
- `GET /api/v1/orders` - Get all orders (reads from database)
- `POST /api/v1/orders` - Create new order (writes to database)

**Review Service:**
- `GET /api/v1/reviews` - Get all reviews (reads from database)
- `POST /api/v2/reviews` - Create new review (writes to database)

**Reusability:** All journey functions are well-structured and can be reused with new executors. **Enhancement needed**: Add registration step to journeys that require authentication.

### Current Configuration

**Helm Values:** `charts/values/k6-scenarios.yaml`
- Resources: 2Gi-4Gi RAM, 1-2 CPU cores
- Conservative: 250 VUs peak
- Duration: 6.5 hours (extended soak test)

**Deployment:** Managed via Helm, auto-restart enabled

---

## External Solutions

### Option 1: Arrival-Rate Executors (Recommended)

**What it is:** k6 executors that control request arrival rate (requests per second) rather than virtual user count.

**Types:**
- `constant-arrival-rate`: Fixed RPS throughout test
- `ramping-arrival-rate`: RPS ramps up/down over time
- `externally-controlled`: RPS controlled by external script/API

**Pros:**
- ✅ **Most Realistic**: Simulates actual user behavior (users arrive independently)
- ✅ **Traffic Spikes**: Can simulate sudden bursts (e.g., flash sales, viral content)
- ✅ **Production-Like**: Matches real-world traffic patterns better
- ✅ **Capacity Planning**: Directly measures system capacity (requests/second)
- ✅ **Burst Testing**: Can simulate sudden traffic increases
- ✅ **SRE-Friendly**: Better for capacity planning and bottleneck identification

**Cons:**
- ⚠️ **Complexity**: Requires understanding of arrival rates vs VU count
- ⚠️ **Resource Estimation**: Harder to estimate VU count from RPS
- ⚠️ **Think Time Impact**: User think time affects actual RPS achieved

**Implementation complexity:** Medium
**Team familiarity:** Medium (new concept, but well-documented)

**Example Pattern:**
```javascript
scenarios: {
  shopping_traffic: {
    executor: 'ramping-arrival-rate',
    startRate: 10,  // 10 RPS at start
    timeUnit: '1s',
    preAllocatedVUs: 50,  // Pre-allocate VUs for efficiency
    maxVUs: 200,  // Max VUs if arrival rate requires it
    stages: [
      { duration: '5m', target: 50 },   // Ramp to 50 RPS
      { duration: '10m', target: 100 },  // Peak: 100 RPS
      { duration: '5m', target: 200 },   // Burst: 200 RPS (flash sale!)
      { duration: '10m', target: 100 }, // Back to peak
      { duration: '5m', target: 20 },    // Wind down
    ],
    exec: 'shoppingUserScenario',
  }
}
```

**Use Cases:**
- Production capacity testing
- Flash sale simulation
- Traffic spike testing
- Realistic user arrival patterns

### Option 2: Shared-Iterations Executor

**What it is:** Executor that runs fixed number of iterations across all VUs, with weighted scenario distribution.

**Pros:**
- ✅ **Better Control**: Precise control over journey mix percentages
- ✅ **Deterministic**: Fixed number of iterations per scenario
- ✅ **Resource Efficient**: Can allocate VUs based on journey complexity
- ✅ **Easy Weighting**: Simple to adjust scenario distribution

**Cons:**
- ❌ **Less Realistic**: Doesn't simulate arrival rates
- ❌ **Fixed Duration**: Hard to predict exact test duration
- ❌ **No Burst Simulation**: Can't simulate sudden spikes

**Implementation complexity:** Low
**Team familiarity:** High (similar to current approach)

**Example Pattern:**
```javascript
scenarios: {
  ecommerce_flow: {
    executor: 'shared-iterations',
    vus: 100,
    iterations: 10000,  // Total iterations across all VUs
    maxDuration: '2h',
    exec: 'ecommerceShoppingJourney',
    weight: 30,  // 30% of total iterations
  },
  quick_browse: {
    executor: 'shared-iterations',
    vus: 150,
    iterations: 20000,  // More iterations (faster journey)
    maxDuration: '2h',
    exec: 'quickBrowseJourney',
    weight: 40,  // 40% of total iterations
  }
}
```

**Use Cases:**
- Journey mix validation
- Resource allocation testing
- Deterministic test runs

### Option 3: Hybrid Approach (Arrival-Rate + Ramping-VUs)

**What it is:** Combine arrival-rate for baseline traffic with ramping-vus for spike simulation.

**Pros:**
- ✅ **Best of Both**: Realistic baseline + spike simulation
- ✅ **Flexible**: Can simulate complex traffic patterns
- ✅ **Production-Ready**: Matches real-world scenarios (steady + spikes)

**Cons:**
- ⚠️ **Complexity**: Requires managing multiple executors
- ⚠️ **Resource Intensive**: May need more VUs allocated
- ⚠️ **Coordination**: Need to coordinate spike timing

**Implementation complexity:** High
**Team familiarity:** Low (requires understanding both executors)

**Example Pattern:**
```javascript
scenarios: {
  baseline_traffic: {
    executor: 'constant-arrival-rate',
    rate: 50,  // 50 RPS baseline
    timeUnit: '1s',
    duration: '2h',
    preAllocatedVUs: 100,
    maxVUs: 200,
    exec: 'browserUserScenario',
  },
  flash_sale_spike: {
    executor: 'ramping-vus',
    startVUs: 0,
    stages: [
      { duration: '1m', target: 0 },    // Wait 1 hour
      { duration: '30s', target: 500 },  // Sudden spike!
      { duration: '5m', target: 500 },  // Sustain spike
      { duration: '30s', target: 0 },    // Quick drop
    ],
    exec: 'shoppingUserScenario',
  }
}
```

**Use Cases:**
- Flash sale simulation
- Marketing campaign spikes
- Realistic production traffic (steady + events)

### Option 4: Per-VU-Iterations Executor

**What it is:** Each VU runs fixed number of iterations independently.

**Pros:**
- ✅ **Simple**: Easy to understand and configure
- ✅ **Predictable**: Each VU completes same number of journeys
- ✅ **Resource Control**: Direct VU count control

**Cons:**
- ❌ **Not Realistic**: Doesn't simulate arrival rates
- ❌ **Synchronized**: All VUs start/end together
- ❌ **No Burst Simulation**: Can't simulate traffic spikes

**Implementation complexity:** Low
**Team familiarity:** High

**Use Cases:**
- Simple load testing
- Journey validation
- Not recommended for production simulation

---

## Comparison Matrix

| Criteria | Arrival-Rate | Shared-Iterations | Hybrid | Per-VU-Iterations | Current (Ramping-VUs) |
|----------|--------------|-------------------|--------|-------------------|------------------------|
| **Realism** | ⭐⭐⭐⭐⭐ | ⭐⭐⭐ | ⭐⭐⭐⭐⭐ | ⭐⭐ | ⭐⭐⭐ |
| **Traffic Spikes** | ⭐⭐⭐⭐⭐ | ⭐⭐ | ⭐⭐⭐⭐⭐ | ⭐ | ⭐⭐ |
| **Burst Simulation** | ⭐⭐⭐⭐⭐ | ⭐ | ⭐⭐⭐⭐⭐ | ⭐ | ⭐ |
| **SRE/DevOps Fit** | ⭐⭐⭐⭐⭐ | ⭐⭐⭐ | ⭐⭐⭐⭐⭐ | ⭐⭐ | ⭐⭐⭐ |
| **Complexity** | ⭐⭐⭐ | ⭐⭐ | ⭐⭐⭐⭐ | ⭐ | ⭐⭐ |
| **Resource Control** | ⭐⭐⭐ | ⭐⭐⭐⭐ | ⭐⭐⭐ | ⭐⭐⭐⭐ | ⭐⭐⭐⭐ |
| **Capacity Planning** | ⭐⭐⭐⭐⭐ | ⭐⭐ | ⭐⭐⭐⭐⭐ | ⭐⭐ | ⭐⭐⭐ |
| **Journey Mix Control** | ⭐⭐⭐ | ⭐⭐⭐⭐⭐ | ⭐⭐⭐⭐ | ⭐⭐⭐ | ⭐⭐⭐ |

---

## Industry Best Practices

### Production Load Testing Patterns

**1. Traffic Pattern Simulation:**
- **Baseline Traffic**: Constant arrival-rate (steady RPS)
- **Peak Hours**: Ramping arrival-rate (morning/evening peaks)
- **Traffic Spikes**: Sudden burst with ramping-vus or ramping-arrival-rate
- **Low Traffic**: Reduced arrival-rate (night hours)

**2. Realistic User Behavior:**
- **Full User Lifecycle**: Register → Login → Browse → Purchase (complete journey)
- **Database Interaction**: Test both reads (GET products, reviews) and writes (POST orders, carts)
- **Think Time**: Variable delays between requests (not fixed)
- **Session Duration**: Users stay active for varying durations
- **Journey Mix**: Different users take different paths (weighted scenarios)
- **Error Handling**: Some requests fail (realistic error rates)
- **End-to-End Flow**: Test complete stack (Web → Logic → Database) not just API endpoints

**3. SRE/DevOps Focus:**
- **Capacity Planning**: Test at expected peak load + 20% buffer
- **Burst Testing**: Simulate sudden traffic increases (flash sales, viral content)
- **Gradual Ramp-Up**: Start low, increase gradually to identify breaking points
- **Sustained Load**: Run at peak for extended period (soak testing)

### k6 Executor Selection Guide

**Use Arrival-Rate When:**
- Simulating realistic user arrival patterns
- Testing system capacity (requests/second)
- Simulating traffic spikes/bursts
- Production capacity planning

**Use Ramping-VUs When:**
- Testing system behavior under increasing load
- Finding breaking points
- Simple load testing scenarios
- Legacy compatibility

**Use Shared-Iterations When:**
- Need precise control over journey mix
- Testing specific journey combinations
- Resource allocation validation

**Use Hybrid When:**
- Complex production scenarios (baseline + spikes)
- Flash sale simulation
- Marketing campaign testing

---

## Recommendations

### Primary Recommendation: Arrival-Rate Executors

**Approach:** Migrate to `ramping-arrival-rate` executor with multiple scenarios for realistic production traffic simulation.

**Rationale:**
1. **Most Realistic**: Simulates actual user arrival patterns (requests/second)
2. **Traffic Spikes**: Can simulate sudden bursts (flash sales, viral content)
3. **SRE-Friendly**: Better for capacity planning and bottleneck identification
4. **Production-Like**: Matches real-world traffic patterns better than VU-based approach

**Implementation Strategy:**
1. **Baseline Traffic**: Use `constant-arrival-rate` for steady background traffic
2. **Peak Hours**: Use `ramping-arrival-rate` for morning/evening peaks
3. **Traffic Spikes**: Use `ramping-arrival-rate` with sudden target increases
4. **Multiple Scenarios**: Keep existing 5 personas with arrival-rate executors

**Example Configuration:**
```javascript
scenarios: {
  // Baseline: Steady traffic throughout day
  baseline_traffic: {
    executor: 'constant-arrival-rate',
    rate: 30,  // 30 RPS baseline
    timeUnit: '1s',
    duration: '6h',
    preAllocatedVUs: 50,
    maxVUs: 200,
    exec: 'browserUserScenario',
  },
  
  // Peak Hours: Morning and evening peaks
  peak_hours: {
    executor: 'ramping-arrival-rate',
    startRate: 20,
    timeUnit: '1s',
    preAllocatedVUs: 100,
    maxVUs: 300,
    stages: [
      { duration: '30m', target: 50 },   // Morning ramp-up
      { duration: '60m', target: 100 },  // Morning peak
      { duration: '30m', target: 60 },   // Lunch dip
      { duration: '30m', target: 90 },   // Afternoon recovery
      { duration: '60m', target: 100 },  // Evening peak
      { duration: '30m', target: 40 },    // Wind down
      { duration: '30m', target: 20 },  // Night low
    ],
    exec: 'shoppingUserScenario',
  },
  
  // Traffic Spike: Flash sale simulation
  flash_sale: {
    executor: 'ramping-arrival-rate',
    startRate: 0,
    timeUnit: '1s',
    preAllocatedVUs: 200,
    maxVUs: 500,
    stages: [
      { duration: '2h', target: 0 },     // Wait for event
      { duration: '30s', target: 200 },  // Sudden spike!
      { duration: '5m', target: 200 },  // Sustain spike
      { duration: '30s', target: 50 },   // Quick drop
      { duration: '1h', target: 0 },     // Back to baseline
    ],
    exec: 'shoppingUserScenario',
  }
}
```

**Benefits:**
- Realistic traffic simulation (requests/second)
- Can simulate sudden spikes (flash sales, viral content)
- Better capacity planning (direct RPS measurement)
- Production-ready patterns

### Alternative Approach: Hybrid (Baseline + Spikes)

**Approach:** Combine `constant-arrival-rate` for baseline with `ramping-vus` for spike simulation.

**Rationale:**
- Provides realistic baseline traffic
- Allows spike simulation for special events
- More flexible for complex scenarios

**Use When:**
- Need to simulate special events (flash sales, marketing campaigns)
- Want realistic baseline + event spikes
- Complex production scenarios

---

## Full User Journey Testing Patterns

### Pattern: Complete User Lifecycle Journey

**Use Case:** Test full user journey from account creation to purchase, including all database operations.

**Example Full Journey Flow:**

```javascript
function completeUserLifecycleJourney() {
  const userId = `user-${__VU}-${Date.now()}`;
  const email = `${userId}@test.com`;
  const sessionId = `session-${__VU}-${Date.now()}`;
  const tags = { 
    scenario: 'new_user', 
    journey: 'complete_lifecycle',
    session_id: sessionId,
    user_id: userId
  };
  
  // Step 1: REGISTER (Web → Logic → Database WRITE)
  console.log(`[${userId}] Step 1: Registering account...`);
  const registerRes = makeRequest('POST', `${SERVICES.auth}/api/v2/auth/register`, {
    username: userId,
    email: email,
    password: 'password123',
  }, { ...tags, flow_step: '1_register', service_target: 'auth', operation: 'db_write' });
  sleep(1.0); // User reads confirmation
  
  // Step 2: LOGIN (Web → Logic → Database READ)
  console.log(`[${userId}] Step 2: Logging in...`);
  makeRequest('POST', `${SERVICES.auth}/api/v2/auth/login`, {
    username: userId,
    password: 'password123',
  }, { ...tags, flow_step: '2_login', service_target: 'auth', operation: 'db_read' });
  sleep(0.5);
  
  // Step 3: GET PROFILE (Web → Logic → Database READ)
  console.log(`[${userId}] Step 3: Loading profile...`);
  makeRequest('GET', `${SERVICES.user}/api/v2/users/${userId}`, null, 
    { ...tags, flow_step: '3_profile', service_target: 'user', operation: 'db_read' });
  sleep(0.3);
  
  // Step 4: BROWSE PRODUCTS (Web → Logic → Database READ)
  console.log(`[${userId}] Step 4: Browsing products...`);
  makeRequest('GET', `${SERVICES.product}/api/v2/catalog/items`, null, 
    { ...tags, flow_step: '4_browse', service_target: 'product', operation: 'db_read' });
  sleep(2.0); // User browsing time
  
  // Step 5: VIEW PRODUCT DETAILS (Web → Logic → Database READ)
  const productId = `prod-${Math.floor(Math.random() * 100)}`;
  console.log(`[${userId}] Step 5: Viewing product ${productId}...`);
  makeRequest('GET', `${SERVICES.product}/api/v1/products/${productId}`, null, 
    { ...tags, flow_step: '5_view_product', service_target: 'product', operation: 'db_read', product_id: productId });
  sleep(1.5); // User reading product details
  
  // Step 6: READ REVIEWS (Web → Logic → Database READ)
  console.log(`[${userId}] Step 6: Reading reviews...`);
  makeRequest('GET', `${SERVICES.review}/api/v1/reviews`, null, 
    { ...tags, flow_step: '6_read_reviews', service_target: 'review', operation: 'db_read' });
  sleep(2.0); // User reading reviews
  
  // Step 7: ADD TO CART (Web → Logic → Database WRITE)
  console.log(`[${userId}] Step 7: Adding to cart...`);
  makeRequest('POST', `${SERVICES.cart}/api/v2/carts/cart-${userId}/items`, {
    productId: productId,
    quantity: Math.floor(Math.random() * 3) + 1,
  }, { ...tags, flow_step: '7_add_cart', service_target: 'cart', operation: 'db_write', product_id: productId });
  sleep(0.5);
  
  // Step 8: VIEW CART (Web → Logic → Database READ)
  console.log(`[${userId}] Step 8: Viewing cart...`);
  makeRequest('GET', `${SERVICES.cart}/api/v1/cart`, null, 
    { ...tags, flow_step: '8_view_cart', service_target: 'cart', operation: 'db_read' });
  sleep(1.0);
  
  // Step 9: CREATE ORDER (Web → Logic → Database WRITE)
  console.log(`[${userId}] Step 9: Creating order...`);
  makeRequest('POST', `${SERVICES.order}/api/v1/orders`, {
    items: [{ productId: productId, quantity: 1, price: 99.99 }],
    userId: userId,
  }, { ...tags, flow_step: '9_create_order', service_target: 'order', operation: 'db_write', product_id: productId });
  sleep(0.5);
  
  console.log(`[${userId}] ✅ Complete user lifecycle journey finished (9 steps, full stack tested)`);
}
```

**What This Tests:**
- ✅ **Account Creation**: Auth service → Database write
- ✅ **Authentication**: Auth service → Database read
- ✅ **User Profile**: User service → Database read
- ✅ **Product Browsing**: Product service → Database read (full stack)
- ✅ **Product Details**: Product service → Database read (full stack)
- ✅ **Review Reading**: Review service → Database read (full stack)
- ✅ **Cart Operations**: Cart service → Database write + read
- ✅ **Order Creation**: Order service → Database write
- ✅ **End-to-End Latency**: Complete flow latency measurement
- ✅ **Database Performance**: Read/write performance under load

**Key Benefits:**
- Tests complete user lifecycle (not just isolated API calls)
- Validates database performance (reads and writes)
- Measures end-to-end latency (Web → Logic → Database)
- Simulates realistic user behavior
- Identifies bottlenecks across entire stack

### Pattern: New User Registration Flow

**Use Case:** Test new user onboarding flow with registration → profile setup → first purchase.

```javascript
function newUserOnboardingJourney() {
  // Step 1: Register
  // Step 2: Login
  // Step 3: Update Profile (if API exists)
  // Step 4: Browse Products
  // Step 5: First Purchase
}
```

### Pattern: Returning User Flow

**Use Case:** Test returning user flow (login → browse → purchase).

```javascript
function returningUserJourney() {
  // Step 1: Login (user already exists)
  // Step 2: Browse Products
  // Step 3: View Previous Orders
  // Step 4: Add to Cart
  // Step 5: Purchase
}
```

---

## Advanced Patterns

### Pattern 1: Time-of-Day Traffic Simulation

**Use Case:** Simulate realistic daily traffic patterns (morning peak, lunch dip, evening peak, night low)

**Implementation:**
```javascript
scenarios: {
  daily_traffic: {
    executor: 'ramping-arrival-rate',
    startRate: 10,
    timeUnit: '1s',
    stages: [
      // Morning: 6 AM - 9 AM (gradual increase)
      { duration: '3h', target: 80 },
      // Peak: 9 AM - 12 PM (high traffic)
      { duration: '3h', target: 120 },
      // Lunch: 12 PM - 2 PM (dip)
      { duration: '2h', target: 60 },
      // Afternoon: 2 PM - 6 PM (recovery)
      { duration: '4h', target: 100 },
      // Evening: 6 PM - 10 PM (peak)
      { duration: '4h', target: 120 },
      // Night: 10 PM - 6 AM (low)
      { duration: '8h', target: 20 },
    ],
  }
}
```

### Pattern 2: Burst Traffic Simulation

**Use Case:** Simulate sudden traffic spikes (flash sales, viral content, marketing campaigns)

**Implementation:**
```javascript
scenarios: {
  burst_traffic: {
    executor: 'ramping-arrival-rate',
    startRate: 0,
    timeUnit: '1s',
    preAllocatedVUs: 300,
    maxVUs: 1000,
    stages: [
      { duration: '1h', target: 0 },      // Pre-event
      { duration: '10s', target: 500 },    // Sudden burst!
      { duration: '5m', target: 500 },     // Sustain
      { duration: '10s', target: 100 },    // Quick drop
      { duration: '30m', target: 50 },     // Post-event
    ],
  }
}
```

### Pattern 3: Weighted Scenario Distribution

**Use Case:** Control exact journey mix percentages

**Implementation:**
```javascript
scenarios: {
  ecommerce_journey: {
    executor: 'constant-arrival-rate',
    rate: 50,
    timeUnit: '1s',
    duration: '2h',
    exec: 'ecommerceShoppingJourney',
    weight: 30,  // 30% of traffic
  },
  quick_browse: {
    executor: 'constant-arrival-rate',
    rate: 70,
    timeUnit: '1s',
    duration: '2h',
    exec: 'quickBrowseJourney',
    weight: 40,  // 40% of traffic
  },
  // ... more scenarios
}
```

### Pattern 4: Gradual Ramp-Up with Sustained Peak

**Use Case:** Find system breaking points gradually

**Implementation:**
```javascript
scenarios: {
  capacity_test: {
    executor: 'ramping-arrival-rate',
    startRate: 10,
    timeUnit: '1s',
    stages: [
      { duration: '5m', target: 50 },    // Ramp-up
      { duration: '5m', target: 100 },   // Increase
      { duration: '5m', target: 150 },    // More
      { duration: '5m', target: 200 },    // Peak
      { duration: '30m', target: 200 },  // Sustained peak
      { duration: '5m', target: 100 },   // Ramp-down
    ],
  }
}
```

---

## Open Questions (RESOLVED)

1. **What are the expected peak traffic patterns?** ✅ **RESOLVED**
   - Morning peak: TBD (to be defined in specification)
   - Evening peak: TBD (to be defined in specification)
   - Flash sale spikes: TBD (to be defined in specification)
   - Baseline traffic: TBD (to be defined in specification)

2. **What journey mix percentages are realistic?** ✅ **RESOLVED**
   - Current: 40% browser, 30% shopping, 15% registered, 10% API, 5% admin
   - **Decision**: Keep current distribution (confirmed by user)

3. **What burst scenarios need simulation?** ✅ **RESOLVED**
   - Flash sales: ✅ Yes
   - Marketing campaigns: ✅ Yes
   - Viral content: ✅ Yes
   - Scheduled events: ✅ Yes

4. **What are the capacity targets?** ✅ **RESOLVED**
   - Maximum sustainable RPS: TBD (to be defined in specification)
   - Peak burst RPS: TBD (to be defined in specification)
   - Error rate tolerance: TBD (to be defined in specification)

5. **Should we use hybrid approach?** ✅ **RESOLVED**
   - Baseline traffic + spike scenarios: ✅ Yes (confirmed by user)

6. **Full User Journey Testing** ✅ **CLARIFIED**
   - **Requirement**: Test complete user lifecycle from registration to purchase
   - **Flow**: Register → Login → Browse Products (DB read) → View Product (DB read) → Add to Cart (DB write) → Create Order (DB write) → Read Reviews (DB read)
   - **Stack Coverage**: Web Layer → Logic Layer → Database Layer (end-to-end)
   - **APIs Available**: All required APIs exist (see API_REFERENCE.md)
   - **Enhancement Needed**: Add registration step to existing journeys

---

## Next Steps

1. **Review findings** - Confirm arrival-rate approach aligns with SRE/DevOps needs
2. **Gather production data** - Analyze real traffic patterns (if available)
3. **Define traffic profiles** - Specify RPS targets for baseline, peaks, spikes
4. **Proceed to `/specify`** - Define detailed requirements for new load testing strategy
5. **Or proceed to `/plan`** - If requirements are clear, create implementation plan

---

*Research completed with SDD 2.0*

