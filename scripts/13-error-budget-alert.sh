#!/bin/bash

# Error Budget Alert Runbook
# Automated response script for error budget alerts
# Triggered by: SLOAvailabilityBudgetLow, SLOAvailabilityTimeToExhaustion alerts

set -e

NAMESPACE="monitoring"
PROMETHEUS_URL="http://prometheus.monitoring.svc.cluster.local:9090"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

print_header() {
    echo -e "${BLUE}================================${NC}"
    echo -e "${BLUE}  ERROR BUDGET ALERT REPORT${NC}"
    echo -e "${BLUE}  $(date)${NC}"
    echo -e "${BLUE}================================${NC}"
    echo ""
}

print_section() {
    echo -e "${GREEN}📊 $1${NC}"
    echo "----------------------------------------"
}

print_finding() {
    echo -e "${YELLOW}🔍 $1${NC}"
}

print_critical() {
    echo -e "${RED}🚨 $1${NC}"
}

print_ok() {
    echo -e "${GREEN}✅ $1${NC}"
}

# Function to query Prometheus
query_prometheus() {
    local query="$1"
    local result=$(curl -s "$PROMETHEUS_URL/api/v1/query" \
        --data-urlencode "query=$query" | \
        jq -r '.data.result[0].value[1] // "N/A"')
    echo "$result"
}

# Function to get error budget status
get_error_budget_status() {
    print_section "Error Budget Status"
    
    local budget_30d=$(query_prometheus 'slo:availability:error_budget_remaining_30d')
    local budget_7d=$(query_prometheus 'slo:availability:error_budget_remaining_7d')
    local time_to_exhaustion=$(query_prometheus 'slo:availability:time_to_exhaustion_hours')
    local burn_rate=$(query_prometheus 'slo:availability:burn_rate_1h')
    
    if [ "$budget_30d" != "N/A" ]; then
        local budget_percent_30d=$(echo "$budget_30d * 100" | bc -l)
        echo "30-day Budget Remaining: ${budget_percent_30d}%"
    fi
    
    if [ "$budget_7d" != "N/A" ]; then
        local budget_percent_7d=$(echo "$budget_7d * 100" | bc -l)
        echo "7-day Budget Remaining: ${budget_percent_7d}%"
    fi
    
    if [ "$time_to_exhaustion" != "N/A" ]; then
        echo "Time to Exhaustion: ${time_to_exhaustion} hours"
        
        if (( $(echo "$time_to_exhaustion < 24" | bc -l) )); then
            print_critical "CRITICAL: Budget will be exhausted in less than 24 hours!"
        elif (( $(echo "$time_to_exhaustion < 168" | bc -l) )); then
            print_finding "WARNING: Budget will be exhausted in less than 7 days"
        fi
    fi
    
    if [ "$burn_rate" != "N/A" ]; then
        echo "Current Burn Rate: ${burn_rate}x"
        
        if (( $(echo "$burn_rate > 15" | bc -l) )); then
            print_critical "CRITICAL: Burning through budget at 15x+ rate"
        elif (( $(echo "$burn_rate > 4" | bc -l) )); then
            print_finding "WARNING: Burning through budget at 4x+ rate"
        fi
    fi
    
    echo ""
}

# Function to get top error endpoints
get_top_error_endpoints() {
    print_section "Top Error-Generating Endpoints"
    
    local query='topk(10, sum(rate(request_duration_seconds_count{app=~"demo-go-api.*", code=~"4..|5.."}[5m])) by (path))'
    
    echo "Querying top error endpoints..."
    curl -s "$PROMETHEUS_URL/api/v1/query" \
        --data-urlencode "query=$query" | \
        jq -r '.data.result[] | "\(.metric.path // "unknown"): \(.value[1] | tonumber) errors/sec"' | \
        sort -k2 -nr | head -10
    
    echo ""
}

# Function to check recent deployments
check_recent_deployments() {
    print_section "Recent Deployment Analysis"
    
    # Check for recent pod restarts (indicator of deployments)
    local restart_count=$(query_prometheus 'sum(increase(kube_pod_container_status_restarts_total{pod=~"demo-go-api.*"}[1h]))')
    
    if [ "$restart_count" != "N/A" ]; then
        echo "Pod Restarts (last 1h): ${restart_count}"
        
        if (( $(echo "$restart_count > 0" | bc -l) )); then
            print_finding "Recent pod restarts detected"
            echo "Recommendation: Check if recent deployment caused the issues"
        else
            print_ok "No recent pod restarts"
        fi
    else
        print_finding "Pod restart metrics not available"
    fi
    
    # Check deployment age
    local deployment_age=$(query_prometheus 'time() - kube_deployment_created{deployment=~"demo-go-api.*"}')
    
    if [ "$deployment_age" != "N/A" ]; then
        local age_hours=$(echo "$deployment_age / 3600" | bc -l)
        echo "Deployment Age: ${age_hours} hours"
        
        if (( $(echo "$age_hours < 24" | bc -l) )); then
            print_finding "Recent deployment detected (< 24h)"
            echo "Recommendation: Consider rolling back if issues started after deployment"
        fi
    else
        print_finding "Deployment age metrics not available"
    fi
    
    echo ""
}

# Function to analyze error patterns
analyze_error_patterns() {
    print_section "Error Pattern Analysis"
    
    # Check error rate by status code
    local error_4xx=$(query_prometheus 'sum(rate(request_duration_seconds_count{app=~"demo-go-api.*", code=~"4.."}[5m]))')
    local error_5xx=$(query_prometheus 'sum(rate(request_duration_seconds_count{app=~"demo-go-api.*", code=~"5.."}[5m]))')
    local total_requests=$(query_prometheus 'sum(rate(request_duration_seconds_count{app=~"demo-go-api.*"}[5m]))')
    
    if [ "$error_4xx" != "N/A" ] && [ "$error_5xx" != "N/A" ] && [ "$total_requests" != "N/A" ]; then
        local error_4xx_percent=$(echo "($error_4xx / $total_requests) * 100" | bc -l)
        local error_5xx_percent=$(echo "($error_5xx / $total_requests) * 100" | bc -l)
        
        echo "4xx Errors: ${error_4xx_percent}%"
        echo "5xx Errors: ${error_5xx_percent}%"
        
        if (( $(echo "$error_5xx_percent > 1" | bc -l) )); then
            print_critical "High 5xx error rate detected (>1%)"
            echo "Recommendation: Check server-side issues, database connections, external services"
        elif (( $(echo "$error_4xx_percent > 5" | bc -l) )); then
            print_finding "High 4xx error rate detected (>5%)"
            echo "Recommendation: Check client requests, API validation, authentication"
        else
            print_ok "Error rates are within acceptable range"
        fi
    else
        print_finding "Error pattern metrics not available"
    fi
    
    echo ""
}

# Function to check system health
check_system_health() {
    print_section "System Health Check"
    
    # Check pod status
    local running_pods=$(query_prometheus 'sum(kube_pod_status_phase{pod=~"demo-go-api.*", phase="Running"})')
    local total_pods=$(query_prometheus 'sum(kube_pod_status_phase{pod=~"demo-go-api.*"})')
    
    if [ "$running_pods" != "N/A" ] && [ "$total_pods" != "N/A" ]; then
        echo "Running Pods: ${running_pods}/${total_pods}"
        
        if [ "$running_pods" != "$total_pods" ]; then
            print_critical "Not all pods are running"
            echo "Recommendation: Check pod status and restart failed pods"
        else
            print_ok "All pods are running"
        fi
    else
        print_finding "Pod status metrics not available"
    fi
    
    # Check resource usage
    local cpu_usage=$(query_prometheus 'avg(rate(process_cpu_seconds_total{app=~"demo-go-api.*"}[5m])) * 100')
    local memory_usage=$(query_prometheus 'avg(go_memstats_alloc_bytes{app=~"demo-go-api.*"} / 1024 / 1024)')
    
    if [ "$cpu_usage" != "N/A" ]; then
        echo "Average CPU Usage: ${cpu_usage}%"
    fi
    
    if [ "$memory_usage" != "N/A" ]; then
        echo "Average Memory Usage: ${memory_usage} MB"
    fi
    
    echo ""
}

# Function to generate action plan
generate_action_plan() {
    print_section "Immediate Action Plan"
    
    local budget_30d=$(query_prometheus 'slo:availability:error_budget_remaining_30d')
    local time_to_exhaustion=$(query_prometheus 'slo:availability:time_to_exhaustion_hours')
    
    if [ "$budget_30d" != "N/A" ] && [ "$time_to_exhaustion" != "N/A" ]; then
        local budget_percent=$(echo "$budget_30d * 100" | bc -l)
        
        if (( $(echo "$budget_percent < 10" | bc -l) )); then
            print_critical "CRITICAL ACTIONS REQUIRED:"
            echo "1. 🚫 STOP all deployments immediately"
            echo "2. 🔍 Investigate root cause of errors"
            echo "3. 📞 Escalate to on-call engineer"
            echo "4. 🔄 Consider emergency rollback"
            echo "5. 📊 Monitor error budget every 15 minutes"
        elif (( $(echo "$budget_percent < 20" | bc -l) )); then
            print_finding "HIGH PRIORITY ACTIONS:"
            echo "1. ⚠️  Pause non-critical deployments"
            echo "2. 🔍 Investigate error patterns"
            echo "3. 📊 Increase monitoring frequency"
            echo "4. 🛠️  Prepare rollback plan"
        else
            print_ok "STANDARD ACTIONS:"
            echo "1. 📊 Monitor error budget trends"
            echo "2. 🔍 Investigate if error rate is increasing"
            echo "3. 📝 Document findings"
        fi
    fi
    
    echo ""
    echo "📋 Follow-up Actions:"
    echo "1. 📈 Review error budget consumption patterns"
    echo "2. 🔧 Implement fixes for identified issues"
    echo "3. 📊 Adjust SLO targets if needed"
    echo "4. 📚 Update runbooks based on findings"
    echo "5. 🎯 Plan capacity improvements"
    echo ""
}

# Function to send notification (placeholder)
send_notification() {
    local message="$1"
    local severity="$2"
    
    # This is a placeholder - in production, you would integrate with:
    # - Slack webhook
    # - PagerDuty
    # - Email
    # - SMS
    
    echo "📢 Notification would be sent:"
    echo "   Severity: $severity"
    echo "   Message: $message"
    echo "   Timestamp: $(date)"
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
    
    # Run analysis
    get_error_budget_status
    get_top_error_endpoints
    check_recent_deployments
    analyze_error_patterns
    check_system_health
    generate_action_plan
    
    # Send notification based on severity
    local budget_30d=$(query_prometheus 'slo:availability:error_budget_remaining_30d')
    if [ "$budget_30d" != "N/A" ]; then
        local budget_percent=$(echo "$budget_30d * 100" | bc -l)
        
        if (( $(echo "$budget_percent < 10" | bc -l) )); then
            send_notification "CRITICAL: Error budget below 10% - immediate action required" "critical"
        elif (( $(echo "$budget_percent < 20" | bc -l) )); then
            send_notification "WARNING: Error budget below 20% - monitor closely" "warning"
        fi
    fi
    
    print_header
    echo "Error budget alert analysis completed at $(date)"
}

# Run the main function
main "$@"
