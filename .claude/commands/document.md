# /document Command

## Purpose
Update documentation after changes

## Instructions
1. Update METRICS.md if panels or queries changed
2. Update README.md if features or architecture changed
3. Update SLO docs if SLI/SLO definitions changed
4. Keep documentation concise and actionable
5. Include examples and screenshots if helpful

## Documentation Updates

### Dashboard Changes
1. **Update METRICS.md**
   - Location: `docs/monitoring/METRICS.md`
   - Add new panel descriptions
   - Update panel count in overview
   - Document new queries and their purpose
   - Update row group descriptions

2. **Update README.md**
   - Update panel count in title
   - Add new features to highlights
   - Update architecture diagram if needed
   - Update namespace references

### SLO Changes
1. **Update SLO Documentation**
   - `docs/slo/README.md` - Overview and concepts
   - `docs/slo/GETTING_STARTED.md` - Setup and deployment
   - `docs/slo/SLI_DEFINITIONS.md` - SLI specifications
   - `docs/slo/SLO_TARGETS.md` - SLO targets and objectives
   - `docs/slo/ALERTING.md` - Alert configuration and runbooks
   - `docs/slo/ERROR_BUDGET_POLICY.md` - Error budget management

2. **Update SLO Data Files**
   - Definitions: `slo/definitions/{service-name}.yaml`
   - Generated rules: `slo/generated/{service-name}-rules.yaml`

### Architecture Changes
1. **Update AGENTS.md**
   - Technology stack changes
   - New components added
   - Architecture pattern updates
   - Namespace structure changes

2. **Update README.md**
   - Quick start instructions
   - Access points
   - New features
   - Namespace references

### Service-Specific Changes
1. **Update API Documentation**
   - Location: `docs/api/API_REFERENCE.md`
   - Add new endpoints
   - Update service examples
   - Include namespace context

2. **Update Setup Guide**
   - Location: `docs/getting-started/SETUP.md`
   - Add new service deployment steps
   - Update namespace examples
   - Update verification commands

### Code Changes
1. **Update Go Documentation**
   - Custom metrics changes
   - Middleware updates
   - New handlers or endpoints
   - Service-specific implementations

2. **Update Kubernetes Documentation**
   - New manifests
   - Resource changes
   - Service updates
   - Namespace structure

## Documentation Standards
- Keep descriptions concise and actionable
- Include code examples where helpful
- Use consistent formatting
- Update version numbers if applicable
- Include troubleshooting tips
- Reference correct namespace structure (service namespaces and `monitoring`)

## Documentation Structure
- **Getting Started**: `docs/getting-started/`
- **Monitoring**: `docs/monitoring/`
- **API**: `docs/api/`
- **Load Testing**: `docs/load-testing/`
- **SLO**: `docs/slo/`
- **Archive**: `docs/archive/` (historical docs)
