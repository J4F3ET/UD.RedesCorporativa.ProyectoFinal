#!/usr/bin/env bash
# Un solo comando para dejar arriba PC-3 (Servidor de Administración e Infraestructura).
# Orden obligatorio: sub-interfaces 802.1Q (VLAN40/99, +10/20/30 si aplica
# el fallback L2) -> reglas de firewall (solo si FALLBACK_L2=true) -> docker compose.
#
# Requiere root (crea interfaces de red y, en el fallback, reglas nft).
# Ejecutar con: sudo ./deploy.sh
# (IFACE y FALLBACK_L2 se leen del archivo .env de esta carpeta)

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

# Carga IFACE, FALLBACK_L2 (y el resto de .env) al entorno, para que las
# use tanto los scripts de VLANs/firewall como docker compose.
set -a
source .env
set +a

"${REPO_ROOT}/scripts/setup-vlans-pc3.sh"

if [ "${FALLBACK_L2:-false}" = "true" ]; then
  "${REPO_ROOT}/scripts/firewall-pc3-matriz.sh"
fi

# Certificados de LDAPS (CA interna + certificado de OpenLDAP): idempotente, no regenera si siguen vigentes.
"${REPO_ROOT}/scripts/generar-certificados.sh"

docker compose up -d
docker compose ps
