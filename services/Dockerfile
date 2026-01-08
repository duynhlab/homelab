# Build stage - Go 1.25.5 with static binary compilation
FROM golang:1.25.5-alpine AS builder

# Build argument for service name (must be first)
ARG SERVICE_NAME

WORKDIR /app

# Copy service-specific go mod files
COPY ${SERVICE_NAME}/go.mod ${SERVICE_NAME}/go.sum ./
RUN go mod download

# Copy service source code
COPY ${SERVICE_NAME}/ ./

# Build the application from cmd/main.go
# CGO_ENABLED=0: Create fully static binary (no C dependencies) - perfect for minimal containers
# GOOS=linux: Target Linux platform
# Note: -ldflags="-s -w" is NOT used to preserve stack traces for debugging
RUN CGO_ENABLED=0 GOOS=linux go build -o /app/${SERVICE_NAME} ./cmd/main.go

# Final stage - minimal runtime image
FROM alpine:latest

RUN apk --no-cache add ca-certificates
WORKDIR /root/

# Build argument needed in this stage too
ARG SERVICE_NAME

# Copy the binary from builder stage
COPY --from=builder /app/${SERVICE_NAME} .

# Expose port
EXPOSE 8080

# Run the binary using shell form so ENV variable is resolved
CMD ./${SERVICE_NAME}
