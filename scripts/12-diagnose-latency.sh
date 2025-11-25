#!/bin/bash

# Latency Diagnosis Runbook
# Automated diagnostic script for high latency issues
# Triggered by: SLOLatencyCritical alert

set -e

NAMESPACE="monitoring"
PROMETHEUS_URL="http://prometheus.monitoring.svc.cluster.local:9090"

print_header() {
    echo "================================="
    echo "  LATENCY DIAGNOSIS REPORT"
    echo "  $(date)"
    echo "================================="
    echo ""
}

print_section() {
    echo "📊 $1"
    echo "----------------------------------------"
}

print_finding() {
    echo "🔍 $1"
}

print_critical() {
    echo "🚨 $1"
}

print_ok() {
    echo "✅ $1"
}

# Function to query Prometheus
query_prometheus() {
    local query="$1"
    local result=$(curl -s "$PROMETHEUS_URL/api/v1/query" \
        --data-urlencode "query=$query" | \
        jq -r '.data.result[0].value[1] // "N/A"')
    echo "$result"
}

# Function to get top slow endpoints
get_slow_endpoints() {
    print_section "Top 10 Slowest Endpoints (P95)"
    
    local query='topk(10, histogram_quantile(0.95, rate(request_duration_seconds_bucket{app=~".*-service.*", job=~"microservices"}[5m])))'
    
    echo "Querying slowest endpoints..."
    curl -s "$PROMETHEUS_URL/api/v1/query" \
        --data-urlencode "query=$query" | \
        jq -r '.data.result[] | "\(.metric.path // "unknown"): \(.value[1] | tonumber * 1000 | floor)ms"' | \
        sort -k2 -nr | head -10
    
    echo ""
}

# Function to check GC activity
check_gc_activity() {
    print_section "Go GC Activity Analysis"
    
    local gc_duration=$(query_prometheus 'avg(rate(go_gc_duration_seconds_sum{app=~".*-service.*", job=~"microservices"}[5m]))')
    local gc_count=$(query_prometheus 'avg(rate(go_gc_duration_seconds_count{app=~".*-service.*", job=~"microservices"}[5m]))')
    
    if [ "$gc_duration" != "N/A" ] && [ "$gc_count" != "N/A" ]; then
        local avg_gc_duration=$(echo "$gc_duration * 1000" | bc -l)
        local gc_frequency=$(echo "$gc_count" | bc -l)
        
        echo "Average GC Duration: ${avg_gc_duration}ms"
        echo "GC Frequency: ${gc_frequency} GCs/second"
        
        if (( $(echo "$avg_gc_duration > 10" | bc -l) )); then
            print_critical "High GC duration detected (>10ms)"
            echo "Recommendation: Check for memory leaks or increase GC tuning"
        elif (( $(echo "$gc_frequency > 10" | bc -l) )); then
            print_critical "High GC frequency detected (>10 GCs/sec)"
            echo "Recommendation: Check memory allocation patterns"
        else
            print_ok "GC activity appears normal"
        fi
    else
        print_finding "GC metrics not available"
    fi
    
    echo ""
}

# Function to check resource throttling
check_resource_throttling() {
    print_section "Resource Throttling Analysis"
    
    # Check CPU throttling
    local cpu_throttle=$(query_prometheus 'avg(rate(container_cpu_cfs_throttled_seconds_total{container!="POD",pod=~".*-service.*"}[5m]))')
    
    if [ "$cpu_throttle" != "N/A" ]; then
        echo "CPU Throttling Rate: ${cpu_throttle}"
        if (( $(echo "$cpu_throttle > 0.1" | bc -l) )); then
            print_critical "High CPU throttling detected"
            echo "Recommendation: Increase CPU limits or optimize CPU usage"
        else
            print_ok "CPU throttling is minimal"
        fi
    else
        print_finding "CPU throttling metrics not available"
    fi
    
    # Check memory pressure
    local memory_usage=$(query_prometheus 'avg(go_memstats_alloc_bytes{app=~".*-service.*", job=~"microservices"} / go_memstats_sys_bytes{app=~".*-service.*", job=~"microservices"})')
    
    if [ "$memory_usage" != "N/A" ]; then
        local memory_percent=$(echo "$memory_usage * 100" | bc -l)
        echo "Memory Usage: ${memory_percent}%"
        
        if (( $(echo "$memory_percent > 80" | bc -l) )); then
            print_critical "High memory usage detected (>80%)"
            echo "Recommendation: Check for memory leaks or increase memory limits"
        else
            print_ok "Memory usage is acceptable"
        fi
    else
        print_finding "Memory usage metrics not available"
    fi
    
    echo ""
}

# Function to check concurrent requests
check_concurrent_requests() {
    print_section "Concurrent Request Analysis"
    
    local in_flight=$(query_prometheus 'avg(requests_in_flight{app=~".*-service.*", job=~"microservices"})')
    local max_in_flight=$(query_prometheus 'max(requests_in_flight{app=~".*-service.*", job=~"microservices"})')
    
    if [ "$in_flight" != "N/A" ] && [ "$max_in_flight" != "N/A" ]; then
        echo "Average In-Flight Requests: ${in_flight}"
        echo "Max In-Flight Requests: ${max_in_flight}"
        
        if (( $(echo "$in_flight > 100" | bc -l) )); then
            print_critical "High concurrent request load detected"
            echo "Recommendation: Check for request queuing or slow downstream services"
        else
            print_ok "Concurrent request load is normal"
        fi
    else
        print_finding "In-flight request metrics not available"
    fi
    
    echo ""
}

# Function to check error patterns
check_error_patterns() {
    print_section "Error Pattern Analysis"
    
    local error_rate=$(query_prometheus 'sum(rate(request_duration_seconds_count{app=~".*-service.*", job=~"microservices", code=~"4..|5.."}[5m])) / sum(rate(request_duration_seconds_count{app=~".*-service.*", job=~"microservices"}[5m]))')
    
    if [ "$error_rate" != "N/A" ]; then
        local error_percent=$(echo "$error_rate * 100" | bc -l)
        echo "Error Rate: ${error_percent}%"
        
        if (( $(echo "$error_rate > 0.05" | bc -l) )); then
            print_critical "High error rate detected (>5%)"
            echo "Recommendation: Investigate error causes and fix underlying issues"
        else
            print_ok "Error rate is acceptable"
        fi
    else
        print_finding "Error rate metrics not available"
    fi
    
    echo ""
}

# Function to generate recommendations
generate_recommendations() {
    print_section "Recommendations"
    
    echo "Based on the analysis above, consider these actions:"
    echo ""
    echo "1. 🔧 Immediate Actions:"
    echo "   - Check application logs for errors"
    echo "   - Verify database connection health"
    echo "   - Check external service dependencies"
    echo ""
    echo "2. 📊 Monitoring:"
    echo "   - Set up alerts for P95 latency > 500ms"
    echo "   - Monitor GC duration and frequency"
    echo "   - Track memory usage trends"
    echo ""
    echo "3. 🚀 Optimization:"
    echo "   - Review slow database queries"
    echo "   - Optimize application code paths"
    echo "   - Consider horizontal scaling"
    echo ""
    echo "4. 🔍 Deep Dive:"
    echo "   - Use Go pprof for CPU profiling"
    echo "   - Analyze memory allocation patterns"
    echo "   - Review network latency to dependencies"
    echo ""
}

# Main execution
main() {
    print_header
    
    # Check if Prometheus is accessible
    if ! curl -s "$PROMETHEUS_URL/api/v1/query" > /dev/null; then
        print_critical "Cannot connect to Prometheus at $PROMETHEUS_URL"
        echo "Please ensure Prometheus is running and accessible"
        exit 1
    fi
    
    print_ok "Connected to Prometheus successfully"
    echo ""
    
    # Run diagnostic checks
    get_slow_endpoints
    check_gc_activity
    check_resource_throttling
    check_concurrent_requests
    check_error_patterns
    generate_recommendations
    
    print_header
    echo "Latency diagnosis completed at $(date)"
}

# Run the main function
main "$@"
