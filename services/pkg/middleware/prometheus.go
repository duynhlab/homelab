package middleware

import (
	"strconv"
	"time"

	"github.com/gin-gonic/gin"
	"github.com/prometheus/client_golang/prometheus"
	"github.com/prometheus/client_golang/prometheus/promauto"
)

var (
	requestDuration = promauto.NewHistogramVec(
		prometheus.HistogramOpts{
			Name:    "request_duration_seconds",
			Help:    "Duration of HTTP requests in seconds",
			Buckets: []float64{0.005, 0.01, 0.025, 0.05, 0.1, 0.25, 0.5, 1, 2.5, 5, 10},
		},
		[]string{"method", "path", "code"},
	)

	requestTotal = promauto.NewCounterVec(
		prometheus.CounterOpts{
			Name: "requests_total",
			Help: "Total number of HTTP requests",
		},
		[]string{"method", "path", "code"},
	)

	requestsInFlight = promauto.NewGaugeVec(
		prometheus.GaugeOpts{
			Name: "requests_in_flight",
			Help: "Number of HTTP requests currently being processed",
		},
		[]string{"method", "path"},
	)

	requestSize = promauto.NewHistogramVec(
		prometheus.HistogramOpts{
			Name:    "request_size_bytes",
			Help:    "Size of HTTP requests in bytes",
			Buckets: []float64{100, 1000, 10000, 100000, 1000000},
		},
		[]string{"method", "path", "code"},
	)

	responseSize = promauto.NewHistogramVec(
		prometheus.HistogramOpts{
			Name:    "response_size_bytes",
			Help:    "Size of HTTP responses in bytes",
			Buckets: []float64{100, 1000, 10000, 100000, 1000000},
		},
		[]string{"method", "path", "code"},
	)

	errorRate = promauto.NewCounterVec(
		prometheus.CounterOpts{
			Name: "error_rate_total",
			Help: "Total number of HTTP errors",
		},
		[]string{"method", "path", "code"},
	)
)

func PrometheusMiddleware() gin.HandlerFunc {
	return func(c *gin.Context) {
		start := time.Now()
		
		method := c.Request.Method
		path := c.Request.URL.Path
		
		// Increment in-flight requests
		requestsInFlight.WithLabelValues(method, path).Inc()
		
		// Record request size
		requestSize.WithLabelValues(method, path, "").Observe(float64(c.Request.ContentLength))
		
		// Process request
		c.Next()
		
		// Calculate duration
		duration := time.Since(start).Seconds()
		statusCode := strconv.Itoa(c.Writer.Status())
		
		// Record metrics
		requestDuration.WithLabelValues(method, path, statusCode).Observe(duration)
		requestTotal.WithLabelValues(method, path, statusCode).Inc()
		
		// Record response size
		responseSize.WithLabelValues(method, path, statusCode).Observe(float64(c.Writer.Size()))
		
		// Record errors (5xx)
		if c.Writer.Status() >= 500 {
			errorRate.WithLabelValues(method, path, statusCode).Inc()
		}
		
		// Decrement in-flight requests
		requestsInFlight.WithLabelValues(method, path).Dec()
	}
}