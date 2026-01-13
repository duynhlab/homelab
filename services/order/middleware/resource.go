package middleware

import (
	"context"
	"os"
	"strings"

	"go.opentelemetry.io/otel/sdk/resource"
	semconv "go.opentelemetry.io/otel/semconv/v1.24.0"
)

// detectServiceInfo automatically detects service name and namespace from Kubernetes environment
// This function uses multiple detection methods with fallback priority:
// 1. OTEL_SERVICE_NAME env var (highest priority)
// 2. POD_NAME extraction (strip deployment hash)
// 3. Hostname extraction (for Kubernetes pods)
// 4. Fallback to "unknown-service"
func detectServiceInfo() (serviceName, namespace string) {
	// Try OTEL_SERVICE_NAME first (standard OpenTelemetry env var)
	serviceName = os.Getenv("OTEL_SERVICE_NAME")

	// If not set, try to extract from Kubernetes pod name
	if serviceName == "" {
		// Try POD_NAME env var (if injected via Downward API)
		podName := os.Getenv("POD_NAME")
		if podName == "" {
			// Fallback to hostname (Kubernetes sets this to pod name)
			podName, _ = os.Hostname()
		}

		// Extract service name from pod name pattern
		// Kubernetes pod naming: <deployment-name>-<replicaset-hash>-<pod-hash>
		// Examples:
		//   "auth-75c98b4b9c-kdv2n" -> "auth"
		//   "shipping-v2-6dd695b778-7p4gz" -> "shipping-v2"
		//   "user-service-abc123-xyz456" -> "user-service"
		//
		// Strategy: Remove last 2 parts (replicaset-hash and pod-hash)
		// - Replicaset hash: 10 chars (e.g., "75c98b4b9c")
		// - Pod hash: 5 chars (e.g., "kdv2n")
		if podName != "" {
			parts := strings.Split(podName, "-")
			if len(parts) >= 3 {
				// Remove last 2 parts (hashes), keep everything before
				serviceName = strings.Join(parts[:len(parts)-2], "-")
			} else if len(parts) > 0 {
				// Fallback to first part if pattern doesn't match
				serviceName = parts[0]
			}
		}
	}

	// Fallback if still empty
	if serviceName == "" {
		serviceName = "unknown-service"
	}

	// Detect namespace
	// 1. OTEL_RESOURCE_ATTRIBUTES (e.g., "service.namespace=production")
	if attrs := os.Getenv("OTEL_RESOURCE_ATTRIBUTES"); attrs != "" {
		for _, attr := range strings.Split(attrs, ",") {
			kv := strings.SplitN(attr, "=", 2)
			if len(kv) == 2 && kv[0] == "service.namespace" {
				namespace = kv[1]
				return serviceName, namespace
			}
		}
	}

	// 2. Read from Kubernetes service account namespace file
	// This file is automatically mounted by Kubernetes
	if data, err := os.ReadFile("/var/run/secrets/kubernetes.io/serviceaccount/namespace"); err == nil {
		namespace = strings.TrimSpace(string(data))
		return serviceName, namespace
	}

	// 3. POD_NAMESPACE env var (if injected via Downward API)
	if ns := os.Getenv("POD_NAMESPACE"); ns != "" {
		namespace = ns
		return serviceName, namespace
	}

	// Fallback
	namespace = "default"
	return serviceName, namespace
}

// CreateResource creates an OpenTelemetry resource with auto-detected attributes
// This function is exported for use by other middleware (tracing, profiling)
func CreateResource(ctx context.Context) (*resource.Resource, error) {
	serviceName, namespace := detectServiceInfo()

	// Create resource with detected attributes
	res, err := resource.New(
		ctx,
		resource.WithFromEnv(),   // Read OTEL_* env vars if set
		resource.WithProcess(),   // Add process info (PID, executable path)
		resource.WithOS(),        // Add OS info
		resource.WithContainer(), // Add container ID if running in container
		resource.WithHost(),      // Add hostname
		resource.WithAttributes(
			// Service identification (these will override if detection finds them)
			semconv.ServiceNameKey.String(serviceName),
			semconv.ServiceNamespaceKey.String(namespace),
		),
	)

	if err != nil {
		// If resource creation fails, create minimal resource
		return resource.NewWithAttributes(
			semconv.SchemaURL,
			semconv.ServiceNameKey.String(serviceName),
			semconv.ServiceNamespaceKey.String(namespace),
		), nil
	}

	return res, nil
}

// GetServiceName extracts service name from a resource
func GetServiceName(res *resource.Resource) string {
	for _, attr := range res.Attributes() {
		if attr.Key == semconv.ServiceNameKey {
			return attr.Value.AsString()
		}
	}
	return "unknown-service"
}
