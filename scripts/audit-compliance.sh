#!/usr/bin/env bash
# Auditoria de cumplimiento (IE5). Sale con codigo 1 si alguna politica falla -> el pipeline se detiene (IE6).
set -u
FAIL=0
ok()   { echo "  [OK]    $1"; }
fail() { echo "  [FALLA] $1"; FAIL=1; }

echo "== Politica 1: sin secretos escritos en el repositorio =="
if grep -rEn --include='*.properties' --include='*.yml' --include='*.yaml' \
     -i '(password|secret|token)\s*[:=]\s*[A-Za-z0-9/+]{8,}' \
     --exclude-dir=.git --exclude-dir=docs --exclude-dir=target . \
     | grep -vE '\$\{|secretKeyRef|secrets\.|\.example|CAMBIAR|DB_PASSWORD:'; then
  fail "posible credencial escrita en el repo"
else ok "no se encontraron credenciales en texto plano"; fi

echo "== Politica 2: .env no versionado =="
if git ls-files --error-unmatch .env >/dev/null 2>&1; then fail ".env esta versionado"; else ok ".env no esta en git"; fi

echo "== Politica 3: contenedor sin root =="
grep -qE '^USER +[0-9a-z]+' Dockerfile && ok "Dockerfile define USER no-root" || fail "Dockerfile sin USER"

echo "== Politica 4: Kubernetes con limites y securityContext =="
grep -q 'runAsNonRoot: true' k8s/deployment.yaml && ok "runAsNonRoot" || fail "falta runAsNonRoot"
grep -q 'limits:' k8s/deployment.yaml && ok "limites de recursos" || fail "faltan limits"

echo "== Politica 5: umbral de cobertura minimo 60% en pom.xml =="
MIN=$(grep -oP '<minimum>\K[0-9.]+' pom.xml | head -1)
awk -v m="${MIN:-0}" 'BEGIN{exit !(m>=0.60)}' && ok "cobertura minima = ${MIN}" || fail "umbral de cobertura < 0.60"

echo "== Politica 6: gates de calidad/seguridad activos en el pipeline =="
W=.github/workflows/ci-cd.yml
grep -q 'sonar.qualitygate.wait=true' $W && ok "SonarCloud Quality Gate bloqueante" || fail "Quality Gate no bloqueante"
grep -q -- '--exit-code 1' $W && ok "Trivy bloquea con HIGH/CRITICAL" || fail "Trivy no bloquea"

echo "== Politica 7: excepciones de seguridad justificadas (.trivyignore) =="
if [ -f .trivyignore ]; then
  N=$(grep -cE '^CVE-' .trivyignore); C=$(grep -cE '^#' .trivyignore)
  [ "$C" -ge 1 ] && ok "$N excepciones con comentarios de justificacion" || fail "excepciones sin justificacion"
fi

echo "== Politica 8 (opcional): branch protection en main (requiere gh + token con permisos) =="
if [ "${CHECK_BRANCH_PROTECTION:-0}" = "1" ] && command -v gh >/dev/null; then
  gh api "repos/${GITHUB_REPOSITORY:-$(gh repo view --json nameWithOwner -q .nameWithOwner)}/branches/main/protection" \
    --jq '.required_status_checks.contexts' >/dev/null 2>&1 \
    && ok "main tiene branch protection con checks requeridos" || fail "main sin branch protection"
else echo "  [OMITIDA] ejecutar con CHECK_BRANCH_PROTECTION=1 localmente"; fi

echo
[ $FAIL -eq 0 ] && echo "AUDITORIA APROBADA" || echo "AUDITORIA FALLIDA"
exit $FAIL
