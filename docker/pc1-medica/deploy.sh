#!/usr/bin/env bash
# Un solo comando para dejar arriba PC-1 (Servidor Médico).
# PC-1 va en puerto ACCESS de VLAN10: no necesita sub-interfaz 802.1Q,
# el macvlan del compose usa la interfaz física directamente.

set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")"

if [ ! -f .env ]; then
  echo "Falta .env — copia .env.example a .env y define las contraseñas antes de continuar." >&2
  exit 1
fi

docker compose up -d
docker compose ps
