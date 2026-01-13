package middleware

import (
	"os"

	"github.com/grafana/pyroscope-go"
)

var profiler *pyroscope.Profiler

// InitProfiling initializes Pyroscope profiling with automatic service detection
func InitProfiling() error {
	// Auto-detect service name and namespace from Kubernetes environment
	// This eliminates the need for manual APP_NAME/NAMESPACE env vars
	serviceName, namespace := detectServiceInfo()

	// Get Pyroscope endpoint from environment
	pyroscopeEndpoint := os.Getenv("PYROSCOPE_ENDPOINT")
	if pyroscopeEndpoint == "" {
		pyroscopeEndpoint = "http://pyroscope.monitoring.svc.cluster.local:4040"
	}

	// Configure Pyroscope with auto-detected service information
	cfg := pyroscope.Config{
		ApplicationName: serviceName,
		ServerAddress:   pyroscopeEndpoint,
		Tags: map[string]string{
			"service":   serviceName,
			"namespace": namespace,
		},
		ProfileTypes: []pyroscope.ProfileType{
			pyroscope.ProfileCPU,
			pyroscope.ProfileAllocObjects,
			pyroscope.ProfileAllocSpace,
			pyroscope.ProfileInuseObjects,
			pyroscope.ProfileInuseSpace,
			pyroscope.ProfileGoroutines,
			pyroscope.ProfileMutexCount,
			pyroscope.ProfileMutexDuration,
			pyroscope.ProfileBlockCount,
			pyroscope.ProfileBlockDuration,
		},
		Logger: pyroscope.StandardLogger,
	}

	// Start profiling
	var err error
	profiler, err = pyroscope.Start(cfg)
	return err
}

// StopProfiling stops Pyroscope profiling
func StopProfiling() {
	if profiler != nil {
		profiler.Stop()
	}
}
