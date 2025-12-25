# Research and Learning Patterns

This guide documents research patterns and industry best practices that agents should follow when working on different aspects of the codebase.

---

## API Design and Architecture

When working on API-related features (endpoints, versioning, documentation, patterns), **ALWAYS research industry best practices** from large-scale companies before implementing:

### Research Sources

- **Uber** - Microservices architecture, API versioning, graceful degradation
- **Twitch** - Real-time APIs, WebSocket patterns, high-throughput systems
- **Dropbox** - API design, versioning strategy, backward compatibility
- **SoundCloud** - RESTful API patterns, developer experience
- **Grab** - Southeast Asia scale, multi-region APIs, mobile-first design
- **Shopee** - E-commerce APIs, high-traffic patterns, regional considerations

### Research Areas

1. **API Versioning**: How do they handle v1/v2/v3 migrations?
2. **Error Handling**: Standard error response formats
3. **Rate Limiting**: Strategies for high-traffic APIs
4. **Documentation**: API documentation patterns and tools
5. **Graceful Shutdown**: Production-grade shutdown patterns
6. **Monitoring**: API observability and metrics
7. **Security**: Authentication, authorization patterns
8. **Performance**: Caching, optimization strategies

### Before Implementing

1. Research how similar companies solve the problem
2. Document findings and rationale
3. Adapt patterns to our codebase (don't copy blindly)
4. Consider our scale and constraints
5. Follow our existing conventions where possible

### Example Workflow

```
Task: "Add API rate limiting"
1. Research: How do Uber/Twitch/Dropbox handle rate limiting?
2. Document: Create research.md with findings
3. Plan: Adapt to our Go/Gin/Kubernetes stack
4. Implement: Follow our middleware patterns
5. Document: Update API_REFERENCE.md
```

---

## APM (Application Performance Monitoring)

When working on observability features (tracing, logging, profiling, metrics), **ALWAYS reference our existing APM documentation** and follow established patterns:

### Documentation

See [`docs/apm/`](../apm/) for complete APM system documentation:
- [`docs/apm/README.md`](../apm/README.md) - APM system overview
- [`docs/apm/ARCHITECTURE.md`](../apm/ARCHITECTURE.md) - Middleware chain and architecture
- [`docs/apm/TRACING.md`](../apm/TRACING.md) - Distributed tracing (OpenTelemetry, Tempo, Jaeger)
- [`docs/apm/LOGGING.md`](../apm/LOGGING.md) - Structured logging patterns
- [`docs/apm/PROFILING.md`](../apm/PROFILING.md) - Continuous profiling (Pyroscope)
- [`docs/apm/JAEGER.md`](../apm/JAEGER.md) - Jaeger UI usage

### Key Patterns

1. **Middleware Chain Order**: Tracing → Logging → Metrics (see ARCHITECTURE.md)
2. **OpenTelemetry**: Use OTLP protocol, centralized config via `pkg/config/config.go`
3. **Structured Logging**: Use zap logger with trace_id/span_id correlation
4. **Metrics**: Prometheus format, exposed via `/metrics` endpoint
5. **Profiling**: Pyroscope integration for continuous profiling

### Before Implementing

1. Read relevant APM documentation in `docs/apm/`
2. Check existing middleware patterns in `services/pkg/middleware/`
3. Follow established conventions (don't reinvent)
4. Ensure consistency across all 9 services

---

## Database and System Design Patterns

When working on database features, migrations, connection pooling, or system architecture, **ALWAYS research industry best practices** and reference our existing database documentation:

### Research Sources

- **Uber** - Microservices database patterns, connection pooling, multi-region replication
- **Twitch** - High-throughput database design, read replicas, caching strategies
- **Dropbox** - Database scaling, migration strategies, data consistency patterns
- **SoundCloud** - PostgreSQL optimization, connection pool management
- **Grab** - Multi-region database architecture, failover patterns
- **Shopee** - E-commerce database patterns, transaction handling, sharding strategies

### Research Areas

1. **Connection Pooling**: PgBouncer vs PgCat patterns, pool sizing strategies
2. **Database Migrations**: Flyway best practices, zero-downtime migrations
3. **High Availability**: PostgreSQL operators (Zalando, CloudNativePG), replication patterns
4. **Performance**: Query optimization, indexing strategies, connection management
5. **Scalability**: Read replicas, sharding, partitioning patterns
6. **Data Consistency**: Transaction patterns, eventual consistency, distributed transactions
7. **Monitoring**: Database observability, slow query detection, connection pool metrics

### Documentation

See [`docs/guides/DATABASE.md`](DATABASE.md) for complete database architecture:
- **5 PostgreSQL Clusters**: review-db, auth-db, supporting-db, product-db, transaction-db
- **Connection Poolers**: PgBouncer (Auth), PgCat (Product, Cart+Order)
- **Operators**: Zalando Postgres Operator (v1.15.0), CloudNativePG Operator (v1.24.0)
- **Migrations**: Flyway 11.19.0 with 8 migration images
- **Connection Patterns**: Direct connections, PgBouncer pool mode, PgCat sharding

### Key Patterns

1. **3-Layer Architecture**: Web → Logic → Core (see [AGENTS.md](../../AGENTS.md#architecture-overview))
2. **Database Connection**: Use `core/database.go` for centralized database connections
3. **Migration Strategy**: Flyway init containers, versioned migrations (`V{version}__{description}.sql`)
4. **Connection Pooling**: Configure via `DB_POOL_MODE` and `DB_POOLER_TYPE` environment variables
5. **High Availability**: Use PostgreSQL operators for automated failover and replication

### Before Implementing

1. Research how similar companies solve the database problem
2. Read `docs/guides/DATABASE.md` for existing patterns
3. Check existing database configurations in Helm values
4. Consider connection pooler requirements (PgBouncer vs PgCat)
5. Follow established migration patterns (Flyway naming conventions)

### Example Workflow

```
Task: "Add new database cluster"
1. Research: How do Uber/Twitch handle multi-database architecture?
2. Document: Create design doc with cluster strategy
3. Plan: Choose operator (Zalando vs CloudNativePG), connection pooler
4. Implement: Create CRD, Helm values, migration Dockerfile
5. Document: Update DATABASE.md with new cluster details
```

---

## Related Documentation

- **[AGENTS.md](../../AGENTS.md)** - Main agent guide with workflow and quick reference
- **[API_REFERENCE.md](API_REFERENCE.md)** - Complete API documentation
- **[DATABASE.md](DATABASE.md)** - Database architecture and patterns
- **[docs/apm/](../apm/)** - Complete APM system documentation

