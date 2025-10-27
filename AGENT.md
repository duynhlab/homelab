# AI Agent Documentation

## Project Overview

**Name**: Go REST API Monitoring & Observability Platform  
**Purpose**: Production-ready monitoring solution with Prometheus, Grafana, k6, and SLO tracking  
**Target**: Kubernetes microservices with Go applications

## Current Technologies

- **Backend**: Go 1.22+
- **Orchestration**: Kubernetes (Kind for local)
- **Monitoring**: Prometheus, Grafana, VictoriaMetrics (future)
- **Load Testing**: k6 with continuous load generation
- **SLO/SRE**: Prometheus recording rules, multi-window burn rate alerts

## Architecture Patterns

- **Metrics Collection**: Pull-based (Prometheus scraping pods via ServiceMonitor)
- **Dashboard Provisioning**: ConfigMap-based auto-loading
- **Multi-version Deployment**: 3 app versions (v1, v2, v3) for A/B testing
- **Namespace Isolation**: monitoring-demo namespace

## Key Components

- **32 Grafana Panels** in 5 row groups (Overview, Traffic, Errors, Runtime, Resources)
- **6 Custom Metrics** (request_duration_seconds, requests_total, requests_in_flight, memory_allocations, cache_operations, active_connections)
- **Go Runtime Metrics** for memory leak detection
- **SLO System** with error budgets and burn rate alerts
- **k6 Load Generator** with realistic scenarios

## Development Guidelines

- Always use namespace `monitoring-demo`
- Dashboard UID: `microservices-monitoring-001`
- ConfigMap updates require pod restart: `kubectl rollout restart`
- Prometheus queries use `$rate` and `$namespace` variables
- Panel descriptions should be concise and actionable
- Memory leak detection requires 3 heap metrics + goroutines + GC

## Quick Reference

### Key Files
- `grafana-dashboard.json` - Main dashboard (32 panels)
- `k8s/prometheus/configmap.yaml` - Prometheus configuration
- `slo/k8s/` - SLO rules and alerts
- `docs/METRICS.md` - Comprehensive metrics documentation

### Common Commands
- Deploy: `./scripts/deploy-all.sh`
- Port forward: `kubectl port-forward -n monitoring-demo svc/grafana 3000:3000`
- Restart Grafana: `kubectl rollout restart deployment/grafana -n monitoring-demo`
- Check logs: `kubectl logs -l app=demo-go-api -n monitoring-demo`

### Access Points
- Grafana: http://localhost:3000 (admin/admin)
- Prometheus: http://localhost:9090
- API: http://localhost:8080
