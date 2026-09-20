#!/usr/bin/env bash
# Un solo comando para dejar arriba PC-1 (Servidor Médico).
# PC-1 va en puerto ACCESS de VLAN10: no necesita sub-interfaz 802.1Q,
# el macvlan del compose usa la interfaz física directamente.
#
# Requiere root (crea la red macvlan sobre la tarjeta física). Ejecutar con: sudo ./deploy.sh

set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")"

if [ "$(id -u)" -ne 0 ]; then
  echo "Este script necesita ejecutarse como root." >&2
  echo "Uso: sudo ./deploy.sh" >&2
  exit 1
fi

if [ ! -f .env ]; then
  echo "Falta .env — copia .env.example a .env y define las contraseñas antes de continuar." >&2
  exit 1
fi

# Carga IFACE, PERFIL (y el resto de .env). PC-1 no crea sub-interfaces ni rutas en ningún perfil (puerto
# access: su gateway 10.10.10.1 es la SVI del switch en l3 y PC-3 en l2); solo se valida PERFIL para
# detectar un .env mal configurado.
set -a
source .env
set +a
REPO_ROOT="$(cd ../.. && pwd)"
source "${REPO_ROOT}/scripts/perfil.sh"
echo "PC-1: perfil ${PERFIL} (sin sub-interfaces ni rutas propias)."

# IP de gestión opcional (IP_GESTION del .env; vacía = sin IP) sobre la propia tarjeta. Ver scripts/ip-gestion.sh.
source "${REPO_ROOT}/scripts/ip-gestion.sh"
gestion_aplicar "${IP_GESTION:-}" "10:${IFACE:?definir IFACE en .env}"

docker compose up -d
docker compose ps
