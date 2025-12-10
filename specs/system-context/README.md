# System Context - Microservices Monitoring Platform

> **Purpose**: Comprehensive architectural documentation for developers, operators, and AI assistants to understand the monitoring microservices platform.

---

## 📖 Quick Navigation

| Document | Description | Lines |
|----------|-------------|-------|
| **[01. Architecture Overview](01-architecture-overview.md)** | System architecture, deployment patterns, namespace organization | ~300 |
| **[02. Microservices](02-microservices.md)** | 9 microservices catalog, API endpoints, 3-layer architecture | ~400 |
| **[03. Observability Stack](03-observability-stack.md)** | Metrics, Tracing, Logging, Profiling (Prometheus, Tempo, Loki, Pyroscope) | ~500 |
| **[04. SLO System](04-slo-system.md)** | SRE practices, Sloth Operator, error budget tracking | ~250 |
| **[05. Infrastructure](05-infrastructure.md)** | Middleware, Helm charts, deployment scripts, Kubernetes resources | ~400 |
| **[06. Technology Stack](06-technology-stack.md)** | Go dependencies, monitoring tools, versions | ~200 |
| **[07. Data Flows](07-data-flows.md)** | Request lifecycle, metrics, traces, logs flow diagrams | ~300 |
| **[08. Development Workflow](08-development-workflow.md)** | Local setup, build & deploy, testing, debugging | ~250 |

---

## 🎯 Executive Summary

### What Is This Project?

A **production-ready microservices monitoring platform** built with Go, Kubernetes, and a complete observability stack. It demonstrates:

- **9 microservices** (e-commerce domain: auth, user, product, cart, order, review, notification, shipping)
- **Full observability** (metrics, traces, logs, profiles)
- **SRE practices** (SLO tracking, error budgets, burn rate alerts)
- **Professional load testing** (K6 with 8 journey types, 6.5-hour tests)
- **Kubernetes-native** (Operators for Prometheus, Grafana, Sloth)

### Key Architectural Decisions

1. **Microservices Pattern**: 9 independent services with API versioning (v1 & v2)
2. **3-Layer Architecture**: Web → Logic → Core (clean architecture principles)
3. **Observability-First**: Built-in tracing, metrics, logging, profiling via middleware
4. **Operator Pattern**: Kubernetes Operators for infrastructure (Prometheus, Grafana, Sloth)
5. **Namespace Isolation**: One namespace per service for security and resource management
6. **Helm-Based Deployment**: Generic chart with per-service value overrides
7. **GitOps Ready**: All configs in Git, declarative Kubernetes manifests

### Technology Stack Overview

**Core Technologies:**
- **Language**: Go 1.23.0
- **Framework**: Gin (HTTP), Zap (logging), OpenTelemetry (tracing)
- **Platform**: Kubernetes (Kind for local), Helm 3, Docker

**Observability Stack:**
- **Metrics**: Prometheus Operator (kube-prometheus-stack v80.0.0), Grafana Operator (v5.20.0)
- **Tracing**: Grafana Tempo v2.9.0 with metrics-generator
- **Logging**: Loki v3.6.2 + Vector (log collection)
- **Profiling**: Pyroscope (continuous profiling)
- **SLO**: Sloth Operator v0.15.0

**Load Testing:**
- **Tool**: K6 (Grafana k6/1.4.2)
- **Scale**: 250 VUs peak, 3-4M requests over 6.5 hours
- **Scenarios**: 8 journey types (5 user flows + 3 edge cases)

---

## 🏗️ System Components

### Microservices Layer (9 Services)

| Service | Namespace | API Versions | Endpoints | Responsibility |
|---------|-----------|--------------|-----------|----------------|
| **auth** | auth | v1, v2 | `/api/v*/auth/*` | Authentication & registration |
| **user** | user | v1, v2 | `/api/v*/users/*` | User management & profiles |
| **product** | product | v1, v2 | `/api/v1/products/*`, `/api/v2/catalog/*` | Product catalog |
| **cart** | cart | v1, v2 | `/api/v*/cart*` | Shopping cart |
| **order** | order | v1, v2 | `/api/v*/orders/*` | Order management |
| **review** | review | v1, v2 | `/api/v*/reviews/*` | Product reviews |
| **notification** | notification | v1, v2 | `/api/v*/notify*` | Notifications |
| **shipping** | shipping | v1 only | `/api/v1/shipping/*` | Shipping tracking (v1) |
| **shipping-v2** | shipping | v2 only | `/api/v2/shipments/*` | Enhanced shipping (v2) |

**Total**: 9 services, 13 namespaces (9 services + monitoring + kube-system + k6 + default)

### Observability Layer

**Metrics Collection:**
- 6 custom metrics per service (request_duration_seconds, requests_total, requests_in_flight, etc.)
- 32-panel Grafana dashboard (5 row groups: Overview, Traffic, Errors, Runtime, Resources)
- Auto-discovery via ServiceMonitor (namespace-based)

**Distributed Tracing:**
- OpenTelemetry with 10% sampling (configurable)
- Tempo v2.9.0 with metrics-generator for service graphs
- TraceQL support for advanced queries
- W3C Trace Context propagation

**Structured Logging:**
- JSON logs with trace-id correlation
- Loki v3.6.2 with pattern ingestion
- Vector for log collection and self-monitoring
- Log level detection (info, error, warn)

**Continuous Profiling:**
- Pyroscope for CPU, heap, goroutines, locks
- Integration with tracing for correlation

### SLO & SRE Layer

- **Sloth Operator v0.15.0** for SLO management
- **PrometheusServiceLevel CRDs** for all 9 services
- **Automatic rule generation** for error budgets and burn rates
- **2 Grafana dashboards** (overview + detailed)

### Infrastructure Layer

**Kubernetes Resources:**
- **Namespaces**: 13 total (1 per service + shared)
- **ServiceMonitors**: Auto-discovery for all microservices
- **PrometheusRules**: SLO rules + alerting rules
- **GrafanaDashboards**: Operator-managed (4 dashboards)
- **ConfigMaps**: Vector, Tempo, Loki configs

**Deployment Tools:**
- **Helm**: Generic microservice chart v0.2.0
- **Scripts**: 12 numbered scripts (01-12) for deployment automation
- **CI/CD**: GitHub Actions for image builds
- **Registry**: OCI registry (ghcr.io/duynhne)

---

## 📊 System Scale & Capacity

### Current Configuration

**Services:**
- 9 microservices × 2 replicas = 18 pods
- Resource: 64-128Mi RAM, 50-100m CPU per pod
- Total: ~1.5-2.5GB RAM, 1-2 CPU cores

**Monitoring Stack:**
- Prometheus, Grafana, Tempo, Loki, Pyroscope, Vector
- Total: ~5-8GB RAM, 2-4 CPU cores

**Load Testing:**
- K6: 250 VUs peak
- Duration: 6.5 hours
- Requests: 3-4 million
- Resource: 2 CPU / 4GB RAM

**Total Cluster:**
- **Minimum**: ~7.5 CPU cores, 17.5GB RAM
- **Recommended**: 12 CPU cores, 32GB RAM (with headroom)

### Performance Targets

**SLO Targets:**
- **Availability**: 99.9% (43.2 min downtime/month)
- **Latency**: p95 < 500ms, p99 < 1000ms
- **Error Rate**: < 1%

**Load Test Results:**
- **RPS**: 250-1000 sustained (avg ~400 RPS)
- **Success Rate**: > 90%
- **Response Time**: p95 < 800ms, p99 < 1500ms

---

## 🚀 Quick Start

### Recommended Reading Order

**For New Developers:**
1. Start here (README.md) → Overview
2. [01. Architecture Overview](01-architecture-overview.md) → Big picture
3. [02. Microservices](02-microservices.md) → Understand services
4. [08. Development Workflow](08-development-workflow.md) → Start coding

**For SRE/Operators:**
1. [01. Architecture Overview](01-architecture-overview.md) → Infrastructure
2. [03. Observability Stack](03-observability-stack.md) → Monitoring
3. [04. SLO System](04-slo-system.md) → SRE practices
4. [05. Infrastructure](05-infrastructure.md) → Deployment

**For AI Assistants:**
- Read all documents in order (01-08)
- Focus on [07. Data Flows](07-data-flows.md) for understanding interactions
- Reference [06. Technology Stack](06-technology-stack.md) for dependencies

### External Documentation

- **[AGENTS.md](../../AGENTS.md)**: AI agent workflows and conventions
- **[README.md](../../README.md)**: Project overview and quick start
- **[docs/](../../docs/)**: Detailed documentation (API, metrics, SLO, APM)
- **[CHANGELOG.md](../../CHANGELOG.md)**: Version history

---

## 🎓 Learning Path

### Week 1: Understanding the System
- **Day 1-2**: Read architecture overview, understand microservices
- **Day 3-4**: Deploy locally, explore Grafana dashboards
- **Day 5**: Review observability stack, check traces in Tempo

### Week 2: Hands-On Development
- **Day 1-2**: Add a new endpoint to an existing service
- **Day 3-4**: Create a new microservice from scratch
- **Day 5**: Add custom metrics and dashboard panels

### Week 3: Advanced Topics
- **Day 1-2**: Implement SLO for a new service
- **Day 3-4**: Create custom K6 load test scenarios
- **Day 5**: Debug production issues using traces and logs

---

## 📞 Support & Contribution

### Getting Help

- **Issues**: Check existing issues in GitHub
- **Documentation**: See [docs/](../../docs/) for detailed guides
- **AI Assistant**: Ask questions referencing this system context

### Contributing

1. Read [02. Microservices](02-microservices.md) for architecture patterns
2. Follow [08. Development Workflow](08-development-workflow.md) for setup
3. Update this documentation when adding new components

---

## 📝 Document Maintenance

### When to Update This Documentation

- **New microservice added**: Update [02. Microservices](02-microservices.md)
- **Monitoring tool upgraded**: Update [03. Observability Stack](03-observability-stack.md) and [06. Technology Stack](06-technology-stack.md)
- **Architecture changed**: Update [01. Architecture Overview](01-architecture-overview.md) and [07. Data Flows](07-data-flows.md)
- **New deployment pattern**: Update [05. Infrastructure](05-infrastructure.md)
- **SLO definitions changed**: Update [04. SLO System](04-slo-system.md)

### Version Information

- **Last Updated**: 2025-12-10
- **Project Version**: v0.6.12
- **Helm Chart Version**: 0.2.0
- **Documentation Format**: Markdown with Mermaid diagrams

---

**Next**: Start with [01. Architecture Overview](01-architecture-overview.md) →

