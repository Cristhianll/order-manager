#!/usr/bin/env bash
# Automatiza la preparacion del cluster para la EP3 (IE1, IE2, IE3).
# Uso (dentro del playground de Kubernetes, en la raiz del repo clonado):
#   ./scripts/lab-setup.sh <USUARIO_GITHUB> <SHA_COMMIT> [SEGUNDOS_DEPLOY] [COBERTURA]
set -euo pipefail
GH_USER="${1:?usuario de GitHub}"; SHA="${2:?sha del commit}"
DEPLOY_S="${3:-}"; COV="${4:-}"
IMAGE="ghcr.io/${GH_USER,,}/order-manager:${SHA}"

command -v helm >/dev/null || curl -fsSL https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash
helm repo add prometheus-community https://prometheus-community.github.io/helm-charts >/dev/null
helm repo update >/dev/null

echo ">> [IE1] Prometheus + Grafana"
helm upgrade --install monitoring prometheus-community/kube-prometheus-stack \
  --set prometheus.prometheusSpec.serviceMonitorSelectorNilUsesHelmValues=false \
  --set grafana.adminPassword=admin123 --set grafana.service.type=NodePort \
  --wait --timeout 10m

echo ">> [IE2] Base de datos y aplicacion (imagen $IMAGE)"
kubectl create secret generic order-manager-db --from-literal=DB_USER=orders \
  --from-literal=DB_PASSWORD="$(openssl rand -hex 12)" --dry-run=client -o yaml | kubectl apply -f -
kubectl apply -f k8s/configmap.yaml -f k8s/postgres.yaml
sed "s#image: order-manager:local#image: ${IMAGE}#; s#imagePullPolicy: IfNotPresent#imagePullPolicy: Always#" \
  k8s/deployment.yaml > /tmp/deployment.yaml
kubectl apply -f /tmp/deployment.yaml -f k8s/service.yaml -f k8s/hpa.yaml
kubectl rollout status deploy/order-manager --timeout=300s

echo ">> [IE1/IE3] ServiceMonitor, alertas y dashboard como codigo"
kubectl apply -f k8s/monitoring/servicemonitor.yaml -f k8s/monitoring/alerts.yaml
kubectl create configmap order-manager-dashboard \
  --from-file=order-manager.json=k8s/monitoring/dashboard.json --dry-run=client -o yaml | kubectl apply -f -
kubectl label configmap order-manager-dashboard grafana_dashboard=1 --overwrite

echo ">> [IE3] Pushgateway para metricas del pipeline"
helm upgrade --install pushgateway prometheus-community/prometheus-pushgateway \
  --set serviceMonitor.enabled=true --set serviceMonitor.additionalLabels.release=monitoring --wait
if [ -n "$DEPLOY_S" ] && [ -n "$COV" ]; then
  kubectl port-forward svc/pushgateway-prometheus-pushgateway 9091:9091 >/dev/null 2>&1 &
  sleep 4; ./scripts/push-pipeline-metrics.sh "$DEPLOY_S" "$COV"
fi

echo
kubectl get pods,svc,hpa
echo "Grafana NodePort:"; kubectl get svc monitoring-grafana
echo "Usuario: admin  Clave: admin123"
