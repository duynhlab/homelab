FROM golang:1.22-alpine AS builder

WORKDIR /app

# Copy go mod files
COPY go.mod ./
RUN go mod download

# Copy source code
COPY . .

# Build the application
RUN CGO_ENABLED=0 GOOS=linux go build -o shipping-service-v2 ./cmd/shipping-service-v2

# Final stage
FROM alpine:latest

RUN apk --no-cache add ca-certificates
WORKDIR /root/

# Copy the binary from builder stage
COPY --from=builder /app/shipping-service-v2 .

# Expose port
EXPOSE 8080

# Run the binary
CMD ["./shipping-service-v2"]
