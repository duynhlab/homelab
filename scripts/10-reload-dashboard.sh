#!/bin/bash
set -e

echo "Reloading Grafana Dashboards..."

# Delete and recreate to force update
# ConfigMaps: main (microservices), tempo (APM), pgcat (database pooler)
kubectl delete configmap grafana-dashboard-main grafana-dashboard-tempo grafana-dashboard-pgcat -n monitoring --ignore-not-found
# GrafanaDashboards: microservices-monitoring, tempo-observability, vector-monitoring, slo-overview, slo-detailed, pgcat
kubectl delete grafanadashboard microservices-monitoring tempo-observability vector-monitoring slo-overview slo-detailed pgcat -n monitoring --ignore-not-found
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
echo ""
echo "Access Grafana:"
echo "  kubectl port-forward -n monitoring svc/grafana-service 3000:3000"
echo "  Then open http://localhost:3000/dashboards"
echo "  Or access specific dashboard: http://localhost:3000/d/microservices-monitoring-001/"
