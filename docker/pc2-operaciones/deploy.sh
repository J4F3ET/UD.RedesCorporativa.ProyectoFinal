#!/usr/bin/env bash
# Un solo comando para dejar arriba PC-2 (Servidor de Operaciones).
# Orden obligatorio: primero las sub-interfaces 802.1Q (VLAN20/30, puerto
# TRUNK), después docker compose — si se invierte, la creación de las
# redes macvlan del compose falla porque el "parent" aún no existe.
#
# Requiere root (crea interfaces de red). Ejecutar con: sudo ./deploy.sh

set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")"
REPO_ROOT="$(cd ../.. && pwd)"

if [ "$(id -u)" -ne 0 ]; then
  echo "Este script necesita ejecutarse como root (crea interfaces de red)." >&2
  echo "Uso: sudo ./deploy.sh" >&2
  exit 1
fi

if [ ! -f .env ]; then
  echo "Falta .env — copia .env.example a .env y define las contraseñas antes de continuar." >&2
  exit 1
fi

"${REPO_ROOT}/scripts/setup-vlans-pc2.sh"
docker compose up -d
docker compose ps
