#!/usr/bin/env bash
# sembrar.sh - siembra idempotente de OUs, grupos y usuarios de prueba en el Samba AD DC.
#
# La ejecuta entrypoint.sh en cada arranque del contenedor, con reintentos: samba-tool accede a la base local
# (sam.ldb) y puede fallar si se llama demasiado pronto tras arrancar "samba -F". Cada paso comprueba antes de crear
# (o interpreta "ya existe"/"already" en la salida de samba-tool como exito), asi que repetirla no duplica nada ni
# falla si ya se sembro en un arranque anterior.
#
# Claves: las lee de las variables de entorno que compose pasa desde sistema/test.env (unica fuente de verdad). Deben
# cumplir la complejidad de contrasenas de AD (longitud minima, 3 de 4 categorias de caracteres, y no contener el
# nombre de la cuenta): si "samba-tool user create" la rechaza, se cambia la clave en sistema/test.env, nunca la
# politica del dominio (docs/directorio-activo.md, "regla del proyecto"). Cada cuenta (incluida Administrator) lleva
# ademas un "samba-tool user setpassword" en cada arranque para RECONCILIAR la clave real con la de test.env: "user
# create" no toca la clave de una cuenta que ya existia, asi que sin esto una cuenta creada en un arranque o una
# provision anterior se queda con una clave vieja en cuanto test.env cambia, y los logins de prueba fallan sin avisar.
# No se usa --must-change-at-next-login: rompería los logins automaticos de "levantar-sistema.sh verificar".
#
# Caducidad: las 4 cuentas de prueba y svc-lectura llevan "samba-tool user setexpiry --noexpiry" (decision de
# laboratorio, documentada en servicios/samba-ad/README.md; NO se toca la politica del dominio, maxPwdAge). Sin
# esto, la clave caduca a los 41 dias (la politica por defecto de Samba AD) y un login de prueba en una sesion de
# clase fallaria por caducidad, no por credenciales.
#
# Nombre y apellido (givenName/sn): las 4 cuentas de prueba los llevan desde el alta (--given-name/--surname de
# "user create") y se reconcilian en cada arranque con ldapmodify (ver fijar_nombre, mas abajo) por la misma razon
# que la clave: "user create" no los toca si la cuenta ya existia. Sin ellos, el primer login LDAP en ERPNext
# (Frappe) falla con "MandatoryError: [User, ...]: first_name" al crear el User (first_name es obligatorio en el
# doctype User; no es un choque con un User heredado de OpenLDAP, aunque el mensaje lo sugiera: pasa igual en una
# base de ERPNext nueva y vacia). InvenTree (django-auth-ldap) no exige un first_name no vacio, por eso el mismo
# problema no aparecia ahi.
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
: "${SAMBA_ADMIN_PASSWORD:?Falta SAMBA_ADMIN_PASSWORD}"

# --- Administrator: su clave la fija "domain provision" (--adminpass), solo la primera vez que se provisiona. Si
# SAMBA_ADMIN_PASSWORD cambia despues en sistema/test.env con el dominio ya provisionado, "domain provision" no se
# vuelve a ejecutar (ver entrypoint.sh) y la clave real se queda desactualizada; se reconcilia aqui en cada arranque
# por la misma razon que los usuarios de prueba, mas abajo.
intentar_o_existe "clave de Administrator" samba-tool user setpassword "Administrator" --newpassword="${SAMBA_ADMIN_PASSWORD}"

# --- OUs: una por departamento, mas Servicios (cuentas de aplicacion) y Grupos (los GG-*) -----------------------
for ou in Medica Operaciones RRHH Servicios Grupos; do
  intentar_o_existe "OU ${ou}" samba-tool ou create "OU=${ou},${BASE_DN}"
done

# --- Grupos por departamento, en OU=Grupos. No pueden llamarse igual que ningun usuario. ------------------------
intentar_o_existe "grupo GG-Medica"       samba-tool group add "GG-Medica"       --groupou="OU=Grupos"
intentar_o_existe "grupo GG-Operaciones"  samba-tool group add "GG-Operaciones"  --groupou="OU=Grupos"
intentar_o_existe "grupo GG-RRHH"         samba-tool group add "GG-RRHH"         --groupou="OU=Grupos"

# fijar_nombre <uid> <OU> <nombre-de-pila>: reconcilia givenName/sn (apellido siempre "Prueba") con ldapmodify por
# LDAPS, autenticado como Administrator (UPN, igual que sistema/ldaplogin.py hace con las cuentas de prueba: mas
# robusto que el DN, que --use-username-as-cn deja igual al CN pero no conviene asumir aqui). samba-tool no tiene
# un "set-attribute" para una cuenta que ya existe (solo fija estos campos al crearla, con --given-name/--surname);
# ldap-utils ya esta instalado (Dockerfile) y la CA del proyecto ya es de confianza (ENV LDAPTLS_CACERT, mismo
# Dockerfile), asi que no hace falta ningun paquete nuevo. Si samba -F todavia no escucha en el 636 (arranque en
# frio), esto falla como cualquier otro paso y entrypoint.sh reintenta sembrar.sh entero.
fijar_nombre() {
  local uid="$1" ou="$2" nombre="$3" salida
  if salida="$(ldapmodify -H ldaps://10.10.99.10 -D "Administrator@AD.RESERVAVIVA.LAN" -w "${SAMBA_ADMIN_PASSWORD}" <<LDIF 2>&1
dn: CN=${uid},OU=${ou},DC=ad,DC=reservaviva,DC=lan
changetype: modify
replace: givenName
givenName: ${nombre}
-
replace: sn
sn: Prueba
LDIF
  )"; then
    log "nombre de ${uid}: hecho (givenName=${nombre}, sn=Prueba)."
    return 0
  fi
  log "ERROR (nombre de ${uid}): ${salida}"
  return 1
}

# --- Usuarios de prueba, uno por departamento (menos Servicios, que lleva la cuenta de busqueda svc-lectura) ----
# --use-username-as-cn: sin esto el CN seria el nombre completo (Samba lo pide asi para bind, User_and_Group_management
# de la wiki de Samba); con el, el CN coincide con el login y el DN es previsible: CN=<uid>,OU=<depto>,DC=ad,...
crear_usuario() {  # crear_usuario <uid> <OU> <clave> <grupo> <nombre-de-pila>
  local uid="$1" ou="$2" clave="$3" grupo="$4" nombre="$5"
  intentar_o_existe "usuario ${uid}" samba-tool user create "${uid}" "${clave}" \
    --userou="OU=${ou}" --mail-address="${uid}@reservaviva.lan" --use-username-as-cn \
    --given-name="${nombre}" --surname="Prueba"
  # Reconciliar la clave con sistema/test.env en cada arranque: "user create" no toca la clave si la cuenta ya
  # existia (creada en un arranque o una provision anterior), asi que sin este paso una cuenta vieja se queda con
  # una clave que ya no coincide con test.env y el kinit/bind LDAPS de las pruebas falla en silencio.
  intentar_o_existe "clave de ${uid}" samba-tool user setpassword "${uid}" --newpassword="${clave}"
  intentar_o_existe "membresia de ${uid} en ${grupo}" samba-tool group addmembers "${grupo}" "${uid}"
  fijar_nombre "${uid}" "${ou}" "${nombre}"
  # Decision de laboratorio (NO toca la politica del dominio, maxPwdAge): estas cuentas son de demostracion y su
  # clave caduca a los 41 dias (la politica por defecto de Samba AD); un login de prueba en una sesion de clase
  # fallaria por caducidad, no por credenciales. Se reconcilia en cada arranque igual que svc-lectura, por si la
  # cuenta se creo antes de este cambio.
  samba-tool user setexpiry "${uid}" --noexpiry >/dev/null
  log "${uid}: clave sin caducidad (decision de laboratorio)."
}

crear_usuario "vet.prueba"       "Medica"      "${LDAP_PRUEBA_VET_PASSWORD}"       "GG-Medica"      "Vet"
crear_usuario "logistica.prueba" "Operaciones" "${LDAP_PRUEBA_LOGISTICA_PASSWORD}" "GG-Operaciones" "Logistica"
crear_usuario "taquilla.prueba"  "Operaciones" "${LDAP_PRUEBA_TAQUILLA_PASSWORD}"  "GG-Operaciones" "Taquilla"
crear_usuario "rrhh.prueba"      "RRHH"        "${LDAP_PRUEBA_RRHH_PASSWORD}"      "GG-RRHH"        "RRHH"

# --- svc-lectura: cuenta de servicio (bind de InvenTree y ERPNext), sin grupo y con la clave sin caducar --------
intentar_o_existe "usuario svc-lectura" samba-tool user create "svc-lectura" "${LDAP_SVC_LECTURA_PASSWORD}" \
  --userou="OU=Servicios" --mail-address="svc-lectura@reservaviva.lan" --use-username-as-cn
intentar_o_existe "clave de svc-lectura" samba-tool user setpassword "svc-lectura" --newpassword="${LDAP_SVC_LECTURA_PASSWORD}"
samba-tool user setexpiry "svc-lectura" --noexpiry >/dev/null
log "svc-lectura: clave sin caducidad."

log "Siembra completa."
