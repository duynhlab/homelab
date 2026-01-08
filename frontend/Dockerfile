# ===================================
# Stage 1: Build Frontend with Node 24
# ===================================
FROM node:24-alpine AS builder

# Build argument for API base URL (required for Docker builds)
ARG API_BASE_URL
RUN if [ -z "$API_BASE_URL" ]; then \
      echo "ERROR: API_BASE_URL build argument is required"; \
      echo "Example: docker build --build-arg API_BASE_URL=http://localhost:8080 ."; \
      exit 1; \
    fi

# Set working directory
WORKDIR /app

# Copy package files
COPY package.json package-lock.json ./

# Install dependencies
RUN npm ci --only=production=false

# Copy source code
COPY . .

# Build with API_BASE_URL baked in
ENV VITE_API_BASE_URL=$API_BASE_URL
RUN npm run build

# Verify dist folder was created
RUN ls -la /app/dist

# ===================================
# Stage 2: Production with Nginx
# ===================================
FROM nginx:alpine

# Remove default nginx static assets
RUN rm -rf /usr/share/nginx/html/*

# Copy built static files from builder
COPY --from=builder /app/dist /usr/share/nginx/html

# Copy nginx configuration
COPY nginx.conf /etc/nginx/conf.d/default.conf

# Expose port 80
EXPOSE 80

# Health check
HEALTHCHECK --interval=30s --timeout=3s --start-period=5s --retries=3 \
  CMD wget --no-verbose --tries=1 --spider http://localhost/health || exit 1

# Start nginx
CMD ["nginx", "-g", "daemon off;"]
