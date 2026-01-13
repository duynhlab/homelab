# ===================================
# Stage 1: Build Frontend with Node 24
# ===================================
FROM node:24-alpine AS builder

# Build argument for API base URL (optional - defaults to relative URLs for Nginx proxy)
ARG API_BASE_URL=""

# Set working directory
WORKDIR /app

# Copy package files
COPY package.json package-lock.json ./

# Install dependencies
RUN npm ci --only=production=false

# Copy source code
COPY . .

# Build with API_BASE_URL (empty for relative URLs)
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

# Start nginx
CMD ["nginx", "-g", "daemon off;"]
