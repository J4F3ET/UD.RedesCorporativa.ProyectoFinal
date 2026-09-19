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

# Crea el administrador de Pretix si aun no existe (idempotente). Pretix no lo
# permite por variables de entorno; hay que esperar a que su primer arranque
# termine las migraciones de la base de datos (~10 min la primera vez).
# (InvenTree crea el suyo solo: ver INVENTREE_ADMIN_* en docker-compose.yml.)
init_admins() {
  : "${PRETIX_ADMIN_EMAIL:?definir PRETIX_ADMIN_EMAIL en .env}"
  : "${PRETIX_ADMIN_PASSWORD:?definir PRETIX_ADMIN_PASSWORD en .env}"
  echo "Esperando a Pretix para crear su administrador (primer arranque: ~10 min)..."
  for _ in $(seq 1 120); do
    if docker exec -i -e ADM_EMAIL="$PRETIX_ADMIN_EMAIL" -e ADM_PASS="$PRETIX_ADMIN_PASSWORD"         pretix-web python -m pretix shell >/dev/null 2>&1 <<'PY'
import os
from pretix.base.models import User
email = os.environ["ADM_EMAIL"]
if not User.objects.filter(email__iexact=email).exists():
    User.objects.create_superuser(email, os.environ["ADM_PASS"])
    print("administrador de Pretix creado")
# Pretix trae por defecto admin@localhost con clave "admin": se elimina.
if email.lower() != "admin@localhost":
    User.objects.filter(email="admin@localhost").delete()
PY
    then
      echo "Administrador de Pretix listo: $PRETIX_ADMIN_EMAIL"
      return 0
    fi
    sleep 10
  done
  echo "AVISO: Pretix no quedo listo a tiempo; vuelve a ejecutar: sudo ./deploy.sh --solo-admins" >&2
  return 1
}

if [ "${1:-}" = "--solo-admins" ]; then
  # Solo reintenta la creacion de administradores (no toca VLANs ni contenedores).
  set -a; [ -f .env ] && source .env; set +a
  init_admins
  exit $?
fi

if [ "$(id -u)" -ne 0 ]; then
  echo "Este script necesita ejecutarse como root (crea interfaces de red)." >&2
  echo "Uso: sudo ./deploy.sh" >&2
  exit 1
fi

if [ ! -f .env ]; then
  echo "Falta .env — copia .env.example a .env y define las contraseñas antes de continuar." >&2
  exit 1
fi

# Carga IFACE (y cualquier otra variable de .env) al entorno, para que la
# use tanto el script de VLANs como docker compose.
set -a
source .env
set +a

"${REPO_ROOT}/scripts/setup-vlans-pc2.sh"
docker compose up -d
init_admins
docker compose ps
