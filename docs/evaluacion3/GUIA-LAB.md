# Guía rápida de laboratorio – Evaluación 3 (monitoreo + cumplimiento)

> Atajo: los pasos 1 a 4 están automatizados en `scripts/lab-setup.sh <USUARIO> <SHA> <SEG_DEPLOY> <COBERTURA>`; el tráfico se genera con `scripts/generate-traffic.sh` y los logs centralizados (opcional) con `scripts/loki-logs.sh`.

Plataforma sugerida: **Killercoda → Playgrounds → Kubernetes** (login con GitHub, sesión de ~1 h: ve rápido y toma capturas).
Reemplaza `<USUARIO>` por tu usuario de GitHub y `<SHA>` por el commit que pasó el pipeline.

## 0. Antes del lab (en tu PC / GitHub) – IE5
1. Haz push de estos cambios a `main` y espera el pipeline verde (anota SHA y mira el resumen: duración de despliegue y cobertura).
2. GitHub → Settings → Branches → *Add rule* sobre `main`: requerir PR, requerir status checks (`Build y pruebas unitarias`, `Análisis de código (SonarCloud)`, `Escaneo de dependencias y secretos`, `Auditoría de cumplimiento`) y bloquear force-push. Captura.
3. GitHub → Packages → `order-manager` → Package settings → visibilidad **Public** (para que el cluster descargue la imagen).
4. Opcional: `CHECK_BRANCH_PROTECTION=1 bash scripts/audit-compliance.sh` (con `gh auth login`).

## 1. Cluster y herramientas (IE2)
```bash
kubectl get nodes
which helm || curl -fsSL https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash
git clone https://github.com/<USUARIO>/order-manager.git && cd order-manager
```

## 2. Prometheus + Grafana (IE1)
```bash
helm repo add prometheus-community https://prometheus-community.github.io/helm-charts && helm repo update
helm install monitoring prometheus-community/kube-prometheus-stack \
  --set prometheus.prometheusSpec.serviceMonitorSelectorNilUsesHelmValues=false \
  --set grafana.adminPassword=admin123 --set grafana.service.type=NodePort
kubectl get pods -w     # esperar Running (2-4 min)
```

## 3. Desplegar el microservicio (IE2)
```bash
kubectl create secret generic order-manager-db --from-literal=DB_USER=orders --from-literal=DB_PASSWORD=$(openssl rand -hex 12)
kubectl apply -f k8s/configmap.yaml -f k8s/postgres.yaml
sed -i "s#image: order-manager:local#image: ghcr.io/<USUARIO>/order-manager:<SHA>#; s#imagePullPolicy: IfNotPresent#imagePullPolicy: Always#" k8s/deployment.yaml
kubectl apply -f k8s/deployment.yaml -f k8s/service.yaml -f k8s/hpa.yaml
kubectl rollout status deploy/order-manager
kubectl get pods,svc,hpa
kubectl run t --rm -it --image=curlimages/curl --restart=Never -- curl -s http://order-manager/actuator/prometheus | head
```
(El HPA necesita metrics-server; si sale `<unknown>` ignóralo o instálalo; no afecta el dashboard.)

## 4. Monitoreo, alertas y dashboard (IE1, IE3)
```bash
kubectl apply -f k8s/monitoring/servicemonitor.yaml -f k8s/monitoring/alerts.yaml
kubectl create configmap order-manager-dashboard --from-file=order-manager.json=k8s/monitoring/dashboard.json
kubectl label configmap order-manager-dashboard grafana_dashboard=1

# Métricas del pipeline (valores del resumen del job deploy)
helm install pushgateway prometheus-community/prometheus-pushgateway \
  --set serviceMonitor.enabled=true --set serviceMonitor.additionalLabels.release=monitoring
kubectl port-forward svc/pushgateway-prometheus-pushgateway 9091:9091 &
./scripts/push-pipeline-metrics.sh <SEGUNDOS_DEPLOY> <COBERTURA_%>

# Generar tráfico y errores para que el dashboard tenga datos
for i in $(seq 1 50); do kubectl run -q --rm -i t$i --image=curlimages/curl --restart=Never -- \
  sh -c 'curl -s -X POST -H "Content-Type: application/json" -d "{\"customerName\":\"x\"}" http://order-manager/api/orders; curl -s http://order-manager/api/orders/99999' >/dev/null; done
```
Grafana: `kubectl get svc monitoring-grafana` (NodePort) o `kubectl port-forward --address 0.0.0.0 svc/monitoring-grafana 3000:80` y abrir el puerto 3000 desde el menú *Traffic/Ports* de Killercoda. Usuario `admin`, clave `admin123`. Dashboard: **Order Manager - Operación y Pipeline**.
Logs: `kubectl logs deploy/order-manager --tail=50`. Prometheus: Status → Targets (debe verse `order-manager` UP) y Alerts.

## 5. Demostrar que el pipeline se detiene (IE6)
Hazlo en una rama, con PR hacia `main`:
- **Seguridad:** agrega al `pom.xml` `org.apache.logging.log4j:log4j-core:2.14.1` → `Escaneo de dependencias` falla (Trivy HIGH/CRITICAL) → `docker` y `deploy` quedan *skipped* → se abre un Issue de alerta.
- **Calidad:** borra o comenta pruebas hasta bajar de 60 % → `mvn verify` falla en JaCoCo.
- **Cumplimiento:** elimina `USER 10001` del Dockerfile → `Auditoría de cumplimiento` falla.
Captura la vista del workflow (jobs en rojo y los siguientes en gris) y el PR bloqueado por branch protection.

## 6. Evidencias para el informe
Capturas: pipeline verde con resumen; branch protection; Quality Gate en SonarCloud; `kubectl get pods,svc,hpa`; Targets en Prometheus; dashboard con las 9 paneles; alerta/Issue; pipeline fallido (IE6).
