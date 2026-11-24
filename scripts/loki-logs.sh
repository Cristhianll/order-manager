#!/usr/bin/env bash
# OPCIONAL (IE1 al 100%): logs centralizados con Loki + Promtail visibles en Grafana.
set -euo pipefail
helm repo add grafana https://grafana.github.io/helm-charts >/dev/null && helm repo update >/dev/null
helm upgrade --install loki grafana/loki-stack --set promtail.enabled=true --set grafana.enabled=false --wait --timeout 8m
cat <<'Y' | kubectl apply -f -
apiVersion: v1
kind: ConfigMap
metadata:
  name: loki-datasource
  labels: { grafana_datasource: "1" }
data:
  loki.yaml: |
    apiVersion: 1
    datasources:
      - name: Loki
        type: loki
        access: proxy
        url: http://loki:3100
Y
kubectl rollout restart deploy/monitoring-grafana
echo "En Grafana: Explore -> Loki -> {app=\"order-manager\"}  (o filtrar |= \"ERROR\")"
