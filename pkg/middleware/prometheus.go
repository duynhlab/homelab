package middleware

import (
	"net/http"
	"os"
	"strconv"
	"time"

	"github.com/prometheus/client_golang/prometheus"
	"github.com/prometheus/client_golang/prometheus/promauto"
)

var (
	// Get app name from environment or use default
	appName = getAppName()

	// RequestLatency tracks HTTP request duration in seconds
	RequestLatency = promauto.NewHistogramVec(
		prometheus.HistogramOpts{
			Name: "request_duration_seconds",
			Help: "Latency of HTTP requests in seconds",
			// Buckets optimized for Apdex score calculation
			Buckets: []float64{0.005, 0.01, 0.025, 0.05, 0.1, 0.25, 0.5, 1, 2.5, 5, 10},
		},
		[]string{"app", "method", "path", "code"},
	)

	// RequestTotal counts total number of HTTP requests
	RequestTotal = promauto.NewCounterVec(
		prometheus.CounterOpts{
			Name: "requests_total",
			Help: "Total number of HTTP requests",
		},
		[]string{"app", "method", "path", "code"},
	)

	// RequestsInFlight tracks concurrent requests
	RequestsInFlight = promauto.NewGaugeVec(
		prometheus.GaugeOpts{
			Name: "requests_in_flight",
			Help: "Number of requests currently being processed",
		},
		[]string{"app", "method", "path"},
	)

	// RequestSize tracks HTTP request body size
	RequestSize = promauto.NewHistogramVec(
		prometheus.HistogramOpts{
			Name:    "request_size_bytes",
			Help:    "Size of HTTP request bodies in bytes",
			Buckets: []float64{0, 100, 500, 1000, 5000, 10000, 50000},
		},
		[]string{"app", "method", "path"},
	)

	// ResponseSize tracks HTTP response body size
	ResponseSize = promauto.NewHistogramVec(
		prometheus.HistogramOpts{
			Name:    "response_size_bytes",
			Help:    "Size of HTTP response bodies in bytes",
			Buckets: []float64{0, 100, 500, 1000, 5000, 10000, 50000},
		},
		[]string{"app", "method", "path", "code"},
	)

	// ErrorRateTotal counts HTTP errors (4xx, 5xx)
	ErrorRateTotal = promauto.NewCounterVec(
		prometheus.CounterOpts{
			Name: "error_rate_total",
			Help: "Total number of HTTP requests with errors (4xx, 5xx)",
		},
		[]string{"app", "method", "path", "code"},
	)
)

func getAppName() string {
	if name := os.Getenv("APP_NAME"); name != "" {
		return name
	}
	return "demo-go-api"
}

// responseWriter wraps http.ResponseWriter to capture status code and size
type responseWriter struct {
	http.ResponseWriter
	statusCode int
	size       int
}

func (rw *responseWriter) WriteHeader(code int) {
	rw.statusCode = code
	rw.ResponseWriter.WriteHeader(code)
}

func (rw *responseWriter) Write(b []byte) (int, error) {
	size, err := rw.ResponseWriter.Write(b)
	rw.size += size
	return size, err
}

// PrometheusMiddleware wraps HTTP handlers to collect metrics
func PrometheusMiddleware(next http.Handler) http.Handler {
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		start := time.Now()

		// Track requests in flight
		RequestsInFlight.WithLabelValues(appName, r.Method, r.URL.Path).Inc()
		defer RequestsInFlight.WithLabelValues(appName, r.Method, r.URL.Path).Dec()

		// Track request size
		RequestSize.WithLabelValues(appName, r.Method, r.URL.Path).Observe(float64(r.ContentLength))

		// Wrap response writer to capture status code and response size
		rw := &responseWriter{
			ResponseWriter: w,
			statusCode:     http.StatusOK,
		}

		// Call the next handler
		next.ServeHTTP(rw, r)

		// Calculate duration
		duration := time.Since(start).Seconds()
		statusCode := strconv.Itoa(rw.statusCode)

		// Record metrics
		RequestLatency.WithLabelValues(appName, r.Method, r.URL.Path, statusCode).Observe(duration)
		RequestTotal.WithLabelValues(appName, r.Method, r.URL.Path, statusCode).Inc()
		ResponseSize.WithLabelValues(appName, r.Method, r.URL.Path, statusCode).Observe(float64(rw.size))

		// Track errors (4xx, 5xx)
		if rw.statusCode >= 400 {
			ErrorRateTotal.WithLabelValues(appName, r.Method, r.URL.Path, statusCode).Inc()
		}
	})
}

