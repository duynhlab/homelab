FROM golang:1.22-alpine AS builder

WORKDIR /app

# Copy go mod files
COPY go.mod go.sum ./
RUN go mod download

# Copy source code
COPY . .

# Build argument for service name
ARG SERVICE_NAME

# Build the application
RUN CGO_ENABLED=0 GOOS=linux go build -o ${SERVICE_NAME} ./cmd/${SERVICE_NAME}

# Final stage
FROM alpine:latest

RUN apk --no-cache add ca-certificates
WORKDIR /root/

# Build argument needed in this stage too
ARG SERVICE_NAME

# Set ENV from ARG so it can be used in CMD
ENV SERVICE_NAME=${SERVICE_NAME}

# Copy the binary from builder stage
COPY --from=builder /app/${SERVICE_NAME} .

# Expose port
EXPOSE 8080

# Run the binary using shell form so ENV variable is resolved
CMD ./${SERVICE_NAME}

