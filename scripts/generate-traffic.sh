#!/usr/bin/env bash
# Genera trafico normal y errores (404) para poblar el dashboard. Uso: ./scripts/generate-traffic.sh [N]
N="${1:-60}"
kubectl port-forward svc/order-manager 8098:80 >/dev/null 2>&1 & PF=$!
sleep 3
for i in $(seq 1 "$N"); do
  curl -s -o /dev/null -X POST -H 'Content-Type: application/json' -d '{"customerName":"cliente-'$i'"}' http://localhost:8098/api/orders
  curl -s -o /dev/null http://localhost:8098/api/orders
  curl -s -o /dev/null http://localhost:8098/api/orders/999999   # error controlado (404)
done
kill $PF; echo "trafico generado"
