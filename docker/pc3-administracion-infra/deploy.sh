#!/usr/bin/env bash
# Un solo comando para dejar arriba PC-3 (Servidor de Administración e Infraestructura).
# Orden obligatorio: sub-interfaces 802.1Q (VLAN40/99, +10/20/30 si aplica
# el fallback L2) -> reglas de firewall (solo si FALLBACK_L2=true) -> docker compose.
#
# Requiere root (crea interfaces de red y, en el fallback, reglas nft).
# Ejecutar con: sudo ./deploy.sh
#   o, si el switch es L2 puro:  sudo FALLBACK_L2=true ./deploy.sh

set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")"
REPO_ROOT="$(cd ../.. && pwd)"
FALLBACK_L2="${FALLBACK_L2:-false}"

if [ "$(id -u)" -ne 0 ]; then
  echo "Este script necesita ejecutarse como root (crea interfaces de red)." >&2
  echo "Uso: sudo ./deploy.sh   (o sudo FALLBACK_L2=true ./deploy.sh si el switch es L2 puro)" >&2
  exit 1
fi

if [ ! -f .env ]; then
  echo "Falta .env — copia .env.example a .env y define las contraseñas antes de continuar." >&2
  exit 1
fi

FALLBACK_L2="${FALLBACK_L2}" "${REPO_ROOT}/scripts/setup-vlans-pc3.sh"

if [ "${FALLBACK_L2}" = "true" ]; then
  "${REPO_ROOT}/scripts/firewall-pc3-matriz.sh"
fi

docker compose up -d
docker compose ps
