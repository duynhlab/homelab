#!/bin/bash
set -e

echo "Reloading Grafana Dashboards..."

# Delete and recreate to force update
# ConfigMaps: main (microservices), tempo (APM), pgcat (database pooler)
# Note: cnpg-grafana-dashboard ConfigMap is managed by Helm chart (cnpg-grafana-cluster)
kubectl delete configmap grafana-dashboard-main grafana-dashboard-tempo grafana-dashboard-pgcat -n monitoring --ignore-not-found
# GrafanaDashboards: microservices-monitoring, tempo-observability, vector-monitoring, slo-overview, slo-detailed, pgcat, cloudnative-pg
kubectl delete grafanadashboard microservices-monitoring tempo-observability vector-monitoring slo-overview slo-detailed pgcat cloudnative-pg -n monitoring --ignore-not-found

# Apply dashboards via kustomization
# Note: cloudnative-pg dashboard references ConfigMap created by Helm chart
kubectl apply -k k8s/grafana-operator/dashboards/
kubectl rollout restart deployment/grafana-deployment -n monitoring

echo "SUCCESS: Dashboards reloaded!"
echo ""
echo "Reloaded dashboards:"
echo "  - Observability folder:"
echo "    * Microservices Monitoring (microservices-monitoring)"
echo "    * Tempo Observability (tempo-observability)"
echo "    * Vector Monitoring (vector-monitoring)"
echo "  - SLO folder:"
echo "    * SLO Overview (slo-overview)"
echo "    * SLO Detailed (slo-detailed)"
echo "  - Databases folder:"
echo "    * PgCat Dashboard (pgcat)"
echo "    * CloudNativePG (cloudnative-pg)"
echo ""
echo "Access Grafana:"
echo "  kubectl port-forward -n monitoring svc/grafana-service 3000:3000"
echo "  Then open http://localhost:3000/dashboards"
echo "  Or access specific dashboard: http://localhost:3000/d/cloudnative-pg/"
