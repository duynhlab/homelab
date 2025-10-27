# Strict Requirements

## MUST NOT Rules
- **MUST NOT** change dashboard UID after creation (`microservices-monitoring-001`)
- **MUST NOT** hardcode datasource UIDs (use `${DS_PROMETHEUS}`)
- **MUST NOT** remove panel descriptions
- **MUST NOT** use hardcoded time windows (use `$rate` variable)

## MUST Rules
- **MUST** restart pods after ConfigMap changes
- **MUST** include panel descriptions in dashboard
- **MUST** use `$rate` variable for all rate queries
- **MUST** validate Prometheus rules with `promtool check config`
- **MUST** test SLO alerts before deploying to production
- **MUST** use namespace isolation (`monitoring-demo`)

## Configuration Requirements
- **Dashboard UID**: `microservices-monitoring-001`
- **Namespace**: `monitoring-demo`
- **Template Variables**: `$app`, `$namespace`, `$rate`
- **Datasource**: `${DS_PROMETHEUS}` (not hardcoded UID)

## Deployment Requirements
- **ConfigMap Updates**: Always restart deployment after ConfigMap changes
- **Prometheus Rules**: Validate with `promtool check config` before applying
- **SLO Testing**: Test alerts in staging before production
- **Resource Limits**: Set appropriate memory and CPU limits

## Quality Requirements
- **Panel Descriptions**: All panels must have concise, actionable descriptions
- **Query Performance**: Use efficient Prometheus queries
- **Error Handling**: Proper error handling in Go applications
- **Documentation**: Keep documentation up-to-date with changes
