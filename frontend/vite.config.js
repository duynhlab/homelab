import { defineConfig } from 'vite'
import react from '@vitejs/plugin-react'

// https://vitejs.dev/config/
//
// Local Development Proxy Configuration
// ======================================
// Each API path prefix routes to the corresponding microservice.
// Use kubectl port-forward to expose services locally:
//
//   kubectl port-forward -n product svc/product 8081:8080 &
//   kubectl port-forward -n cart svc/cart 8082:8080 &
//   kubectl port-forward -n order svc/order 8083:8080 &
//   kubectl port-forward -n auth svc/auth 8084:8080 &
//   kubectl port-forward -n user svc/user 8085:8080 &
//   kubectl port-forward -n review svc/review 8086:8080 &
//   kubectl port-forward -n notification svc/notification 8087:8080 &
//   kubectl port-forward -n shipping svc/shipping 8088:8080 &
//
// Or use the single-gateway approach (simpler, but requires frontend pod):
//   kubectl port-forward -n default svc/frontend 8080:80 &
//   Then change all targets below to 'http://localhost:8080'
//
export default defineConfig({
  plugins: [react()],
  server: {
    port: 3000,
    proxy: {
      // Product Service
      '/api/v1/products': {
        target: 'http://localhost:8081',
        changeOrigin: true
      },
      // Cart Service
      '/api/v1/cart': {
        target: 'http://localhost:8082',
        changeOrigin: true
      },
      // Order Service
      '/api/v1/orders': {
        target: 'http://localhost:8083',
        changeOrigin: true
      },
      // Auth Service
      '/api/v1/auth': {
        target: 'http://localhost:8084',
        changeOrigin: true
      },
      // User Service
      '/api/v1/users': {
        target: 'http://localhost:8085',
        changeOrigin: true
      },
      // Review Service
      '/api/v1/reviews': {
        target: 'http://localhost:8086',
        changeOrigin: true
      },
      // Notification Service
      '/api/v1/notifications': {
        target: 'http://localhost:8087',
        changeOrigin: true
      },
      // Shipping Service
      '/api/v1/shipping': {
        target: 'http://localhost:8088',
        changeOrigin: true
      }
    }
  }
});
