#!/usr/bin/env bash
# Genera (una sola vez) la CA interna del laboratorio y el certificado LDAPS de OpenLDAP, y deja cada
# archivo donde docker compose lo monta. Es idempotente: si los certificados ya existen, son válidos y
# cubren las direcciones necesarias, no toca nada. Usar --forzar para regenerarlos.
#
# Resultado en docker/pc3-administracion-infra/certs/:
#   ca.crt   CA pública. Es la que deben confiar los clientes de LDAPS (se copia también a PC-1 y PC-2).
#   ca.key   clave privada de la CA. NUNCA se monta en un contenedor ni se comparte.
#   ldap.crt / ldap.key   certificado y clave de OpenLDAP (los monta docker-compose.yml de PC-3).
#
# Uso:  scripts/generar-certificados.sh [--forzar] [--sin-instalar-ca]
# Variables opcionales: LDAP_DOMAIN (reservaviva.local), LDAP_IP (10.10.99.10), CERTS_DIR.
# Como root, además instala ca.crt en el almacén de confianza del host (para que ldapsearch, curl, etc.
# confíen en ella); --sin-instalar-ca lo omite.
#
# Los archivos de certs/ están en .gitignore: cada laboratorio genera los suyos y no se suben al repo.

set -euo pipefail
# En Git Bash (Windows) los argumentos que empiezan con "/" (como -subj "/O=...") se convertirían en rutas.
export MSYS_NO_PATHCONV=1 MSYS2_ARG_CONV_EXCL='*'

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DOMAIN="${LDAP_DOMAIN:-reservaviva.local}"
LDAP_IP="${LDAP_IP:-10.10.99.10}"
OUT="${CERTS_DIR:-${REPO_ROOT}/docker/pc3-administracion-infra/certs}"
FORZAR=false
INSTALAR_CA=true
GENERADA_CA=false
GENERADO_LDAP=false
for arg in "$@"; do
  case "${arg}" in
    --forzar) FORZAR=true ;;
    --sin-instalar-ca) INSTALAR_CA=false ;;
    *) echo "Argumento desconocido: ${arg}" >&2; echo "Uso: $0 [--forzar] [--sin-instalar-ca]" >&2; exit 2 ;;
  esac
done

command -v openssl >/dev/null || { echo "Falta openssl. Instálalo (sudo apt install openssl) y repite." >&2; exit 1; }

umask 077
mkdir -p "${OUT}"
cd "${OUT}"

DIAS_MIN=30   # si a un certificado le quedan menos días, se regenera

vigente() {  # vigente <cert>: existe y no vence en ${DIAS_MIN} días
  [ -f "$1" ] && openssl x509 -in "$1" -noout -checkend $((DIAS_MIN * 86400)) >/dev/null 2>&1
}

# --- 1. CA interna ---------------------------------------------------------------------------------
if ${FORZAR} || [ ! -f ca.key ] || ! vigente ca.crt; then
  echo "[certs] Generando la CA interna..."
  GENERADA_CA=true
  rm -f ca.key ca.crt ldap.key ldap.crt   # una CA nueva invalida el certificado anterior
  openssl genrsa -out ca.key 4096 2>/dev/null
  openssl req -x509 -new -key ca.key -sha256 -days 3650 \
    -subj "/O=Zoologico Reserva Viva/CN=Reserva Viva CA interna" \
    -addext "basicConstraints=critical,CA:TRUE" \
    -addext "keyUsage=critical,keyCertSign,cRLSign" \
    -out ca.crt
else
  echo "[certs] CA existente y vigente: se conserva."
fi

# --- 2. Certificado de OpenLDAP --------------------------------------------------------------------
cubre_direcciones() {  # el certificado actual incluye la IP y el nombre esperados
  local san
  san="$(openssl x509 -in ldap.crt -noout -ext subjectAltName 2>/dev/null || true)"
  [[ "${san}" == *"${LDAP_IP}"* && "${san}" == *"ldap.${DOMAIN}"* ]]
}
if ${FORZAR} || [ ! -f ldap.key ] || ! vigente ldap.crt \
   || ! openssl verify -CAfile ca.crt ldap.crt >/dev/null 2>&1 || ! cubre_direcciones; then
  echo "[certs] Generando el certificado de OpenLDAP (ldap.${DOMAIN}, ${LDAP_IP})..."
  GENERADO_LDAP=true
  rm -f ldap.key ldap.crt   # pueden ser del contenedor (uid 911): no se sobrescriben, se sustituyen
  openssl genrsa -out ldap.key 2048 2>/dev/null
  openssl req -new -key ldap.key -subj "/O=Zoologico Reserva Viva/CN=ldap.${DOMAIN}" -out ldap.csr
  cat > ldap.ext <<EOF
basicConstraints=CA:FALSE
keyUsage=critical,digitalSignature,keyEncipherment
extendedKeyUsage=serverAuth
subjectAltName=DNS:ldap.${DOMAIN},DNS:openldap,DNS:localhost,IP:${LDAP_IP},IP:127.0.0.1
EOF
  openssl x509 -req -in ldap.csr -CA ca.crt -CAkey ca.key -CAcreateserial \
    -sha256 -days 825 -extfile ldap.ext -out ldap.crt 2>/dev/null
  rm -f ldap.csr ldap.ext ca.srl
else
  echo "[certs] Certificado de OpenLDAP existente y vigente: se conserva."
fi

# Permisos: la clave de la CA solo para el dueño; el resto lo lee el contenedor (arranca como root).
# Solo sobre lo generado en ESTA ejecución: al arrancar, el contenedor de OpenLDAP (osixia) se apropia de los certificados
# montados (uid 911), y desde entonces el usuario del host ya no puede hacerles chmod. Tocarlos siempre hacía fallar la
# segunda ejecución con "Operation not permitted", aunque no hubiera nada que regenerar.
if ${GENERADA_CA}; then chmod 600 ca.key; chmod 644 ca.crt; fi
if ${GENERADO_LDAP}; then chmod 600 ldap.key; chmod 644 ldap.crt; fi

# --- 3. Copiar la CA pública a donde la necesitarán los clientes de LDAPS ---------------------------
for pc in pc1-medica pc2-operaciones; do
  mkdir -p "${REPO_ROOT}/docker/${pc}/certs"
  destino="${REPO_ROOT}/docker/${pc}/certs/ca.crt"
  # Solo si cambió: misma razón que los chmod de arriba (un contenedor puede haberse apropiado de la copia).
  if ! cmp -s ca.crt "${destino}"; then
    cp ca.crt "${destino}"
    chmod 644 "${destino}"
  fi
done

# --- 4. Confianza a nivel del host (solo root) ------------------------------------------------------
if ${INSTALAR_CA}; then
  if [ "$(id -u)" -eq 0 ] && command -v update-ca-certificates >/dev/null; then
    install -m 644 ca.crt /usr/local/share/ca-certificates/reserva-viva-ca.crt
    update-ca-certificates >/dev/null
    echo "[certs] CA instalada en el almacén de confianza de este equipo."
  else
    echo "[certs] CA no instalada en el host (requiere root y update-ca-certificates); ca.crt: ${OUT}/ca.crt"
  fi
fi

echo "[certs] Listo. Vence: CA $(openssl x509 -in ca.crt -noout -enddate | cut -d= -f2), LDAP $(openssl x509 -in ldap.crt -noout -enddate | cut -d= -f2)."
echo "[certs] Para que PC-1 y PC-2 (equipos distintos) confíen en la CA, copia ${OUT}/ca.crt a docker/pc1-medica/certs/ y docker/pc2-operaciones/certs/ de cada uno (p. ej. con scp)."
