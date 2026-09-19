#!/usr/bin/env bash
# Verificación básica de la prueba de software en un solo host.
# Ejecutar DESPUÉS de "docker compose up -d" en esta misma carpeta.

set -uo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")"

pass=0
fail=0

check() {
  local desc="$1" cmd="$2"
  printf '%-55s' "$desc"
  if eval "$cmd" >/tmp/verificar-check.log 2>&1; then
    echo "OK"
    pass=$((pass+1))
  else
    echo "FALLÓ"
    fail=$((fail+1))
  fi
}

echo "== Estado de los contenedores =="
docker compose ps
echo

echo "== Comprobaciones =="
check "Pretix responde en :18080"        "curl -fsS --max-time 5 http://localhost:18080/ -o /dev/null"
check "InvenTree responde en :18090"     "curl -fsS --max-time 5 http://localhost:18090/ -o /dev/null"
check "ERPNext responde en :18095"       "curl -fsS --max-time 5 http://localhost:18095/ -o /dev/null"
check "OpenLDAP acepta conexión en :1389" "timeout 5 bash -c '</dev/tcp/localhost/1389'"

echo
echo "Resumen: ${pass} OK, ${fail} fallaron."
if [ "${fail}" -gt 0 ]; then
  echo "Para ver el detalle de un servicio que falló: docker compose logs <servicio>"
  echo "(servicios: pretix-web, pretix-db, pretix-redis, inventree-app, inventree-db, erpnext-hr, openldap)"
fi
