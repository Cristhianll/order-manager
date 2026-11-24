#!/usr/bin/env bash
# Envia metricas del pipeline (tiempo de despliegue, cobertura) al Pushgateway del cluster.
# Uso: ./push-pipeline-metrics.sh <deploy_seconds> <coverage_percent>
# (los valores salen del resumen del job "deploy" o del artefacto pipeline-metrics.prom)
set -e
URL="${PUSHGATEWAY_URL:-http://localhost:9091}"
cat <<M | curl -fsS --data-binary @- "$URL/metrics/job/order-manager-pipeline"
# TYPE pipeline_deploy_duration_seconds gauge
pipeline_deploy_duration_seconds ${1:?segundos}
# TYPE pipeline_test_coverage_percent gauge
pipeline_test_coverage_percent ${2:?cobertura}
M
echo "metricas enviadas a $URL"
