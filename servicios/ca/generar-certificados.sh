#!/usr/bin/env bash
# Genera (una sola vez) la CA interna del laboratorio y el certificado LDAPS que usa Samba AD (servicio samba-ad),
# y deja cada archivo donde docker compose lo monta. Es idempotente: si los certificados ya existen, son válidos y
# cubren las direcciones necesarias, no toca nada. Usar --forzar para regenerarlos.
#
# Resultado en servicios/ca/certs/ (junto a este script):
#   ca.crt   CA pública. Es la que deben confiar los clientes de LDAPS (InvenTree y ERPNext la montan en /certs/ca.crt;
#            samba-ad la copia dentro del contenedor, ver más abajo).
#   ca.key   clave privada de la CA. NUNCA se monta en un contenedor ni se comparte.
#   ldap.crt / ldap.key   certificado y clave de LDAPS (los usa el servicio samba-ad). Conservan el nombre "ldap"
#            de cuando los servía OpenLDAP: los consumidores (InvenTree, ERPNext) no cambian, así que renombrarlos
#            no aportaría nada y solo obligaría a tocar más sitios.
#
# Uso:  servicios/ca/generar-certificados.sh [--forzar] [--sin-instalar-ca]
# Variables opcionales: DOMINIO_DNS (reservaviva.lan), LDAP_IP (10.10.99.10), CERTS_DIR (servicios/ca/certs).
# DOMINIO_DNS es el dominio DNS del servidor (el SAN es ldap.<DOMINIO_DNS>), NO el DN base del directorio: ese es
# DC=ad,DC=reservaviva,DC=lan, fijo en servicios/samba-ad/entrypoint.sh (no hay una variable de compose para él,
# a diferencia de LDAP_DOMAIN de la antigua imagen osixia/openldap). Si el SAN del certificado existente no cubre
# ldap.<DOMINIO_DNS> (p. ej. uno anterior con ldap.reservaviva.local), se regenera SOLO ldap.crt/ldap.key, firmado por
# la misma CA; levantar-sistema.sh recrea entonces samba-ad para que lo cargue (un restart no basta, ver allí).
# Como root, además instala ca.crt en el almacén de confianza del host (para que ldapsearch, curl, etc.
# confíen en ella); --sin-instalar-ca lo omite.
#
# Los archivos de certs/ están en .gitignore: cada laboratorio genera los suyos y no se suben al repo.

set -euo pipefail
# En Git Bash (Windows) los argumentos que empiezan con "/" (como -subj "/O=...") se convertirían en rutas.
export MSYS_NO_PATHCONV=1 MSYS2_ARG_CONV_EXCL='*'

AQUI="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"   # servicios/ca
DOMAIN="${DOMINIO_DNS:-reservaviva.lan}"
LDAP_IP="${LDAP_IP:-10.10.99.10}"
OUT="${CERTS_DIR:-${AQUI}/certs}"
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

# --- 2. Certificado LDAPS (lo usa samba-ad) --------------------------------------------------------
cubre_direcciones() {  # el certificado actual incluye la IP y el nombre esperados
  local san
  san="$(openssl x509 -in ldap.crt -noout -ext subjectAltName 2>/dev/null || true)"
  [[ "${san}" == *"${LDAP_IP}"* && "${san}" == *"ldap.${DOMAIN}"* ]]
}
if ${FORZAR} || [ ! -f ldap.key ] || ! vigente ldap.crt \
   || ! openssl verify -CAfile ca.crt ldap.crt >/dev/null 2>&1 || ! cubre_direcciones; then
  if [ -f ldap.crt ] && ! cubre_direcciones; then
    echo "[certs] El SAN del certificado actual no cubre ldap.${DOMAIN} y ${LDAP_IP}: se regenera (la CA se conserva)."
  fi
  echo "[certs] Generando el certificado LDAPS (ldap.${DOMAIN}, dc1.ad.reservaviva.lan, ${LDAP_IP})..."
  GENERADO_LDAP=true
  rm -f ldap.key ldap.crt   # se sustituyen en vez de sobrescribirse, por si el fichero anterior es de otro dueño
  openssl genrsa -out ldap.key 2048 2>/dev/null
  openssl req -new -key ldap.key -subj "/O=Zoologico Reserva Viva/CN=ldap.${DOMAIN}" -out ldap.csr
  cat > ldap.ext <<EOF
basicConstraints=CA:FALSE
keyUsage=critical,digitalSignature,keyEncipherment
extendedKeyUsage=serverAuth
subjectAltName=DNS:ldap.${DOMAIN},DNS:dc1.ad.reservaviva.lan,DNS:samba-ad,DNS:localhost,IP:${LDAP_IP},IP:127.0.0.1
EOF
  openssl x509 -req -in ldap.csr -CA ca.crt -CAkey ca.key -CAcreateserial \
    -sha256 -days 825 -extfile ldap.ext -out ldap.crt 2>/dev/null
  rm -f ldap.csr ldap.ext ca.srl
else
  echo "[certs] Certificado LDAPS existente y vigente: se conserva."
fi

# Permisos: la clave de la CA solo para el dueño; el resto lo puede leer cualquiera (los contenedores los montan
# de solo lectura). Solo se toca lo generado en ESTA ejecución, para no fallar si algún fichero anterior quedó con
# otro dueño (p. ej. tras un chown dentro de un contenedor).
if ${GENERADA_CA}; then chmod 600 ca.key; chmod 644 ca.crt; fi
if ${GENERADO_LDAP}; then chmod 600 ldap.key; chmod 644 ldap.crt; fi

# Los clientes de LDAPS (inventree-app, erpnext-backend) montan esta misma ca.crt desde servicios/ca/certs/: no hay
# copias. samba-ad es distinto: monta los tres ficheros de solo lectura en /certs y su entrypoint los COPIA dentro
# del contenedor (con chmod 600), porque Samba rechaza la clave privada si no tiene esos permisos exactos y un
# montaje de solo lectura no se puede chmodear desde aquí (servicios/samba-ad/entrypoint.sh).

# --- 3. Confianza a nivel del host (solo root) ------------------------------------------------------
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
