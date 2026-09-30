#!/usr/bin/env bash
# entrypoint.sh - arranca el contenedor samba-ad (Samba AD DC).
#
# Provisiona el dominio SOLO la primera vez, cuando el volumen samba_data todavia no tiene sam.ldb (compose lo monta
# en /var/lib/samba). Con datos ya existentes, no se reprovisiona: solo se repiten los pasos idempotentes (copiar el
# certificado con los permisos que Samba exige, asegurar smb.conf y /etc/hosts) y se arranca "samba -F". Detalle del
# diseno: docs/directorio-activo.md (o, mientras se escribe, el plan de migracion en C:\Users\jafet\.claude\plans\).
set -euo pipefail

REALM="AD.RESERVAVIVA.LAN"
DOMINIO="RESERVAVIVA"
HOST_IP="10.10.99.10"      # la misma IP que tenia openldap en vlan99_infra: el DC se registra a si mismo en su DNS
                            # con la IP que ve aqui, nunca con 127.0.0.1 (si no, los clientes no lo alcanzarian).
FQDN="dc1.ad.reservaviva.lan"
SAM_LDB="/var/lib/samba/private/sam.ldb"
KRB5_PRIVADO="/var/lib/samba/private/krb5.conf"
TLS_DIR="/var/lib/samba/private/tls"
CERTS_ORIGEN="/certs"      # montaje de solo lectura: ca.crt, ldap.crt y ldap.key (servicios/ca/certs)
SMB_CONF="/etc/samba/smb.conf"

log() { printf '[samba-ad] %s\n' "$*"; }

# --- Provision (solo la primera vez) --------------------------------------------------------------------------------
if [ ! -f "${SAM_LDB}" ]; then
  : "${SAMBA_ADMIN_PASSWORD:?Falta SAMBA_ADMIN_PASSWORD (definida en sistema/test.env y pasada por compose)}"
  log "No existe ${SAM_LDB}: provisionando el dominio ${DOMINIO} (realm ${REALM})..."
  # El paquete deja un smb.conf de ejemplo en el volumen samba_etc; "domain provision" exige que no exista.
  rm -f "${SMB_CONF}"
  samba-tool domain provision \
    --server-role=dc \
    --realm="${REALM}" \
    --domain="${DOMINIO}" \
    --dns-backend=SAMBA_INTERNAL \
    --use-rfc2307 \
    --host-ip="${HOST_IP}" \
    --adminpass="${SAMBA_ADMIN_PASSWORD}"
  log "Dominio provisionado."
else
  log "${SAM_LDB} ya existe: no se reprovisiona (datos conservados)."
fi

# private/krb5.conf esta en el volumen samba_data y persiste; /etc/krb5.conf es del contenedor y NO persiste (se
# recrea con cada "docker compose up"): hay que copiarlo en cada arranque, no solo tras provisionar.
if [ -f "${KRB5_PRIVADO}" ]; then
  cp "${KRB5_PRIVADO}" /etc/krb5.conf
fi

# /etc/hosts tampoco persiste entre arranques: Docker lo regenera cada vez.
if ! grep -q "${FQDN}" /etc/hosts; then
  printf '%s\t%s dc1\n' "${HOST_IP}" "${FQDN}" >> /etc/hosts
fi

# --- Certificado TLS -------------------------------------------------------------------------------------------------
# Trampa conocida: Samba rechaza la clave privada si no tiene permisos 0600 exactos. El montaje de solo lectura viene
# con los permisos del host (0644, o de otro propietario) y no se puede chmodear desde aqui: se copia dentro del
# contenedor (en el volumen samba_data, que persiste) y se ajustan los permisos ahi. Se repite en cada arranque para
# recoger un certificado rotado (levantar-sistema.sh recrea este contenedor cuando eso pasa).
mkdir -p "${TLS_DIR}"
for f in ca.crt ldap.crt ldap.key; do
  [ -f "${CERTS_ORIGEN}/${f}" ] || { log "ERROR: falta ${CERTS_ORIGEN}/${f} (servicios/ca/generar-certificados.sh)"; exit 1; }
  cp "${CERTS_ORIGEN}/${f}" "${TLS_DIR}/${f}"
done
chmod 600 "${TLS_DIR}/ca.crt" "${TLS_DIR}/ldap.crt" "${TLS_DIR}/ldap.key"

# --- smb.conf: directivas del laboratorio ---------------------------------------------------------------------------
# smb.conf esta en el volumen samba_etc (persiste): estas directivas solo hacen falta la primera vez, pero se
# comprueban en cada arranque (idempotente, sin duplicar) para no depender de que la provision sea siempre la unica
# que las escribe.
asegurar_directiva() {  # asegurar_directiva "clave = valor"
  grep -qF "$1" "${SMB_CONF}" || sed -i "/^\[global\]/a\\	$1" "${SMB_CONF}"
}
# SAMBA_INTERNAL solo resuelve la zona AD; el resto (reservaviva.lan) lo da bind9 (dns-interno, 10.10.99.11).
asegurar_directiva "dns forwarder = 10.10.99.11"
asegurar_directiva "tls enabled = yes"
# Rutas relativas a la carpeta "private" (aqui: /var/lib/samba/private/tls/...).
asegurar_directiva "tls keyfile = tls/ldap.key"
asegurar_directiva "tls certfile = tls/ldap.crt"
asegurar_directiva "tls cafile = tls/ca.crt"
asegurar_directiva "interfaces = eth0"
asegurar_directiva "bind interfaces only = yes"
# Valor por defecto de Samba (CVE-2016-2112): el bind simple solo se acepta por TLS. InvenTree y ERPNext ya usan
# LDAPS, asi que se deja en "yes" en vez de bajar la seguridad para admitir bind simple en el 389 sin cifrar.
asegurar_directiva "ldap server require strong auth = yes"

# --- Arranque ----------------------------------------------------------------------------------------------------
# samba en segundo plano, como hijo de este script (que es el PID 1 del contenedor): asi se puede sembrar despues y
# reenviar la senal de parada de Docker al proceso real.
samba -F --no-process-group &
SAMBA_PID=$!
trap 'log "Deteniendo samba..."; kill -TERM "${SAMBA_PID}" 2>/dev/null; wait "${SAMBA_PID}"' TERM INT

log "Sembrando OUs, grupos y usuarios de prueba (idempotente)..."
intento=0
until /usr/local/bin/sembrar.sh; do
  intento=$((intento + 1))
  if [ "${intento}" -ge 5 ]; then
    log "AVISO: la siembra no se completo tras ${intento} intentos; se reintentara en el proximo arranque del contenedor."
    break
  fi
  log "La siembra fallo (intento ${intento}/5): reintentando en 5s..."
  sleep 5
done

wait "${SAMBA_PID}"
