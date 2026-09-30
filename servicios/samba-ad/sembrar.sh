#!/usr/bin/env bash
# sembrar.sh - siembra idempotente de OUs, grupos y usuarios de prueba en el Samba AD DC.
#
# La ejecuta entrypoint.sh en cada arranque del contenedor, con reintentos: samba-tool accede a la base local
# (sam.ldb) y puede fallar si se llama demasiado pronto tras arrancar "samba -F". Cada paso comprueba antes de crear
# (o interpreta "ya existe"/"already" en la salida de samba-tool como exito), asi que repetirla no duplica nada ni
# falla si ya se sembro en un arranque anterior.
#
# Claves: las lee de las variables de entorno que compose pasa desde sistema/test.env (unica fuente). Deben cumplir
# la complejidad de contrasenas de AD (longitud minima, 3 de 4 categorias de caracteres, y no contener el nombre de
# la cuenta): si "samba-tool user create" la rechaza, se cambia la clave en sistema/test.env, nunca la politica del
# dominio (docs/directorio-activo.md, "regla del proyecto").
set -euo pipefail

BASE_DN="DC=ad,DC=reservaviva,DC=lan"

log() { printf '[sembrar] %s\n' "$*"; }

# intentar_o_existe "descripcion" comando...: ejecuta el comando; si falla, pero la salida dice que el objeto ya
# existe (o la membresia ya estaba), lo trata como exito. Cualquier otro fallo (p. ej. clave que no cumple la
# complejidad de AD) se propaga tal cual, con la salida real de samba-tool, para que quede en el log del contenedor.
intentar_o_existe() {
  local desc="$1" salida
  shift
  if salida="$("$@" 2>&1)"; then
    log "${desc}: hecho."
    return 0
  fi
  if printf '%s' "${salida}" | grep -qiE "already|ya existe"; then
    log "${desc}: ya existia."
    return 0
  fi
  log "ERROR (${desc}): ${salida}"
  return 1
}

: "${LDAP_SVC_LECTURA_PASSWORD:?Falta LDAP_SVC_LECTURA_PASSWORD}"
: "${LDAP_PRUEBA_VET_PASSWORD:?Falta LDAP_PRUEBA_VET_PASSWORD}"
: "${LDAP_PRUEBA_LOGISTICA_PASSWORD:?Falta LDAP_PRUEBA_LOGISTICA_PASSWORD}"
: "${LDAP_PRUEBA_TAQUILLA_PASSWORD:?Falta LDAP_PRUEBA_TAQUILLA_PASSWORD}"
: "${LDAP_PRUEBA_RRHH_PASSWORD:?Falta LDAP_PRUEBA_RRHH_PASSWORD}"

# --- OUs: una por departamento, mas Servicios (cuentas de aplicacion) y Grupos (los GG-*) -----------------------
for ou in Medica Operaciones RRHH Servicios Grupos; do
  intentar_o_existe "OU ${ou}" samba-tool ou create "OU=${ou},${BASE_DN}"
done

# --- Grupos por departamento, en OU=Grupos. No pueden llamarse igual que ningun usuario. ------------------------
intentar_o_existe "grupo GG-Medica"       samba-tool group add "GG-Medica"       --groupou="OU=Grupos"
intentar_o_existe "grupo GG-Operaciones"  samba-tool group add "GG-Operaciones"  --groupou="OU=Grupos"
intentar_o_existe "grupo GG-RRHH"         samba-tool group add "GG-RRHH"         --groupou="OU=Grupos"

# --- Usuarios de prueba, uno por departamento (menos Servicios, que lleva la cuenta de busqueda svc-lectura) ----
# --use-username-as-cn: sin esto el CN seria el nombre completo (Samba lo pide asi para bind, User_and_Group_management
# de la wiki de Samba); con el, el CN coincide con el login y el DN es previsible: CN=<uid>,OU=<depto>,DC=ad,...
crear_usuario() {  # crear_usuario <uid> <OU> <clave> <grupo>
  local uid="$1" ou="$2" clave="$3" grupo="$4"
  intentar_o_existe "usuario ${uid}" samba-tool user create "${uid}" "${clave}" \
    --userou="OU=${ou}" --mail-address="${uid}@reservaviva.lan" --use-username-as-cn
  intentar_o_existe "membresia de ${uid} en ${grupo}" samba-tool group addmembers "${grupo}" "${uid}"
}

crear_usuario "vet.prueba"       "Medica"      "${LDAP_PRUEBA_VET_PASSWORD}"       "GG-Medica"
crear_usuario "logistica.prueba" "Operaciones" "${LDAP_PRUEBA_LOGISTICA_PASSWORD}" "GG-Operaciones"
crear_usuario "taquilla.prueba"  "Operaciones" "${LDAP_PRUEBA_TAQUILLA_PASSWORD}"  "GG-Operaciones"
crear_usuario "rrhh.prueba"      "RRHH"        "${LDAP_PRUEBA_RRHH_PASSWORD}"      "GG-RRHH"

# --- svc-lectura: cuenta de servicio (bind de InvenTree y ERPNext), sin grupo y con la clave sin caducar --------
intentar_o_existe "usuario svc-lectura" samba-tool user create "svc-lectura" "${LDAP_SVC_LECTURA_PASSWORD}" \
  --userou="OU=Servicios" --mail-address="svc-lectura@reservaviva.lan" --use-username-as-cn
samba-tool user setexpiry "svc-lectura" --noexpiry >/dev/null
log "svc-lectura: clave sin caducidad."

log "Siembra completa."
