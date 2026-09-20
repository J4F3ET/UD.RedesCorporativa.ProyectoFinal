#!/usr/bin/env bash
# Un solo comando para dejar arriba PC-3 (Servidor de Administración e Infraestructura).
# Orden obligatorio: sub-interfaces 802.1Q (VLAN40/99; en PERFIL=l2 también 10/20/30 y el enrutamiento)
# -> reglas de firewall (solo PERFIL=l2) -> certificados -> docker compose.
#
# Requiere root (crea interfaces de red y, en el perfil l2, reglas nft).
# Ejecutar con: sudo ./deploy.sh
# (IFACE y PERFIL se leen del archivo .env de esta carpeta; PERFIL=l3 o PERFIL=l2, ver .env.example)

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

# Carga IFACE, PERFIL (y el resto de .env) al entorno, para que las
# use tanto los scripts de VLANs/firewall como docker compose.
set -a
source .env
set +a

# Valida PERFIL (l2|l3) y localiza despliegue/<perfil>/scripts.
source "${REPO_ROOT}/scripts/perfil.sh"

"${PERFIL_DIR}/scripts/setup-vlans-pc3.sh"

if [ "${PERFIL}" = "l2" ]; then
  "${PERFIL_DIR}/scripts/firewall-pc3-matriz.sh"
fi

# Certificados de LDAPS (CA interna + certificado de OpenLDAP): idempotente, no regenera si siguen vigentes.
"${REPO_ROOT}/scripts/generar-certificados.sh"

docker compose up -d
docker compose ps
