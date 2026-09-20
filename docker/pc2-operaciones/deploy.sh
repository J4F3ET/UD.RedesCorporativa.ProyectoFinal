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

# Carga IFACE, PERFIL (y cualquier otra variable de .env) al entorno, para que la
# use tanto el script de VLANs como docker compose.
set -a
source .env
set +a

# Valida PERFIL (l2|l3) y localiza despliegue/<perfil>/scripts.
source "${REPO_ROOT}/scripts/perfil.sh"
"${PERFIL_DIR}/scripts/setup-vlans-pc2.sh"

# ca.crt (CA interna de LDAPS) viene de PC-3 y el compose lo monta como ARCHIVO. Si faltara, Docker crearía un
# directorio vacío en su lugar y InvenTree arrancaría sin poder verificar LDAPS. Por eso se comprueba aquí,
# después de la IP de gestión (sin ella no habría por dónde hacer el scp) y antes de "docker compose up".
# Que falte NO es un error: es el paso que sigue en el primer arranque; se sale con código 0 para relanzar.
if [ -d certs/ca.crt ]; then rmdir certs/ca.crt 2>/dev/null || true; fi   # resto de un arranque anterior sin el archivo
if [ ! -s certs/ca.crt ]; then
  mkdir -p certs
  case "${PERFIL}" in
    l3) PC3_IP=10.10.99.250 ;;   # IP_GESTION de PC-3 (VLAN 99); el switch enruta desde la VLAN de PC-2
    l2) PC3_IP=10.10.99.1 ;;     # gateway de la VLAN 99, que es PC-3
  esac
  echo
  echo "PASO PENDIENTE (no es un error): falta el certificado de la CA interna, certs/ca.crt."
  echo "Cópialo desde PC-3 con este comando (ajusta usuario y ruta del repositorio en PC-3):"
  echo
  echo "  scp <usuario>@${PC3_IP}:<ruta-del-repo-en-PC-3>/docker/pc3-administracion-infra/certs/ca.crt $(pwd)/certs/ca.crt"
  echo
  echo "Después vuelve a lanzar:  sudo ./deploy.sh   (continúa desde aquí; es seguro repetirlo)."
  if [ "${PERFIL}" = "l3" ]; then
    echo "Nota: en el perfil l3 PC-3 debe tener IP_GESTION=10.10.99.250 en su .env (y haber corrido su deploy.sh)."
  fi
  if [ -z "${IP_GESTION:-}" ]; then
    echo "Nota: IP_GESTION está vacía en este PC, así que no tiene dirección para hacer el scp. Defínela en .env"
    echo "y relanza sudo ./deploy.sh, o copia el archivo con un USB a $(pwd)/certs/ca.crt."
  fi
  exit 0
fi

docker compose up -d
init_admins
docker compose ps
