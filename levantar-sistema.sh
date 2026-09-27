#!/usr/bin/env bash
# levantar-sistema.sh - Levanta la arquitectura completa de Reserva Viva (25 servicios) en UN solo host.
#
#   git clone <repo> && cd <repo> && ./levantar-sistema.sh
#
# En Windows se usa levantar-sistema.ps1 (o doble clic en levantar-sistema.cmd), que elige donde ejecutar este script
# (Git Bash si Docker Desktop esta en marcha; si no, una distro de WSL con Docker Engine) y mantiene viva la sesion de WSL.
#
# Acciones:
#   arrancar   (por defecto) prepara todo, levanta los 25 servicios y espera a que esten sanos
#   preparar   solo lo previo: certificados, zona DNS, LDIF de LDAP, validacion del compose e imagen de OpenVPMS
#   estado     estado de cada servicio y direcciones de acceso
#   verificar  ejecuta sistema/verificar_arquitectura.py contra el sistema levantado
#   detener    para los contenedores sin borrar nada; "arrancar" los vuelve a levantar en minutos
#   borrar     elimina contenedores Y VOLUMENES (todos los datos del laboratorio). Pide confirmacion
# Opciones:
#   --forzar        no abortar por falta de memoria
#   --timeout MIN   espera maxima a que todo quede sano tras el arranque (por defecto 45)
#   --rapido        (verificar) omite la prueba de persistencia de LDAP (down + up -d); ese caso queda como no verificado
#   --si            (borrar) no pedir confirmacion
#
# Es idempotente: se puede ejecutar las veces que haga falta. Si un arranque se interrumpe, volver a ejecutarlo
# retoma donde quedo (la inicializacion de OpenVPMS y la creacion del sitio de ERPNext son reanudables).
#
# Usa el docker-compose.yml de la raiz (unico; servicios agrupados por departamento, con cada VLAN como un bridge de
# Docker con su misma subred) y los ficheros de cada servicio en servicios/. Todo "docker compose" se ejecuta desde la
# raiz con --env-file sistema/test.env (contrasenas de laboratorio, desechables).
#
# Solo ASCII a proposito: la salida se ve igual en cualquier consola de Windows.

set -euo pipefail

RAIZ="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ARNES="${RAIZ}/sistema"               # test.env, verificar_arquitectura.py y sus informes
ENV_FILE="sistema/test.env"           # relativo a RAIZ: dc() se ejecuta siempre desde la raiz
PROYECTO="reservaviva-smoke"          # "name:" de docker-compose.yml
MARCA_SESION="reservaviva-keepalive"  # proceso que levantar-sistema.ps1 deja vivo en WSL

# Umbral de memoria para la VM de Docker. El consumo medido de los 25 contenedores esta en docs/resultados-un-host.md.
MIN_VM_GIB=6

ACCION="arrancar"
FORZAR=false
TIMEOUT_MIN=45
RAPIDO=false
SI=false

uso() { sed -n '2,21p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'; }

while [ $# -gt 0 ]; do
  case "$1" in
    arrancar|preparar|estado|verificar|detener|borrar) ACCION="$1" ;;
    ayuda|-h|--help) uso; exit 0 ;;
    --forzar) FORZAR=true ;;
    --rapido) RAPIDO=true ;;
    --si) SI=true ;;
    --timeout)
      [ $# -ge 2 ] && [[ "$2" =~ ^[0-9]+$ ]] || { echo "--timeout necesita un numero de minutos" >&2; exit 2; }
      TIMEOUT_MIN="$2"; shift ;;
    *) echo "Argumento desconocido: $1" >&2; uso >&2; exit 2 ;;
  esac
  shift
done

paso()  { printf '\n==> %s\n' "$*"; }
info()  { printf '    %s\n' "$*"; }
aviso() { printf '    AVISO: %s\n' "$*" >&2; }
fallo() { printf '\nERROR: %s\n' "$*" >&2; exit 1; }

# Siempre desde la raiz del repositorio (donde esta docker-compose.yml), sea cual sea el directorio actual.
dc() { (cd "${RAIZ}" && docker compose --env-file "${ENV_FILE}" "$@"); }

# Lee una clave de test.env sin ejecutarlo (tiene contrasenas con caracteres arbitrarios).
valor_env() {
  local v
  v="$(grep -E "^$1=" "${RAIZ}/${ENV_FILE}" | tail -n 1 | cut -d= -f2- | tr -d '\r')"
  printf '%s' "${v:-$2}"
}

en_wsl() { grep -qi microsoft /proc/version 2>/dev/null; }

sistema_docker() { docker info --format '{{.OperatingSystem}}' 2>/dev/null || true; }

contenedores_en_marcha() { docker ps -q --filter "label=com.docker.compose.project=${PROYECTO}" | grep -c . || true; }

# --- Requisitos -----------------------------------------------------------------------------------------------------

comprobar_requisitos() {
  paso "Comprobando requisitos"
  command -v docker >/dev/null || fallo "No se encuentra 'docker'. Instala Docker Desktop (Windows/macOS) o Docker Engine (Linux/WSL)."
  docker info >/dev/null 2>&1 || fallo "Docker no responde. Arranca Docker Desktop, o en Linux/WSL: sudo systemctl start docker"
  docker compose version >/dev/null 2>&1 || fallo "Falta el plugin 'docker compose' (v2)."

  # Minimo heredado: los antiguos overrides usaban "!override" (Compose 2.24.4). El compose unico ya no lo usa, pero no
  # se ha probado con versiones anteriores, asi que se sigue exigiendo.
  local ver may min par
  ver="$(docker compose version --short 2>/dev/null | sed 's/^v//')"
  IFS=. read -r may min par <<<"${ver}"
  may="${may:-0}"; min="${min:-0}"; par="${par%%[!0-9]*}"; par="${par:-0}"
  if [ "${may}" -lt 2 ] || { [ "${may}" -eq 2 ] && { [ "${min}" -lt 24 ] || { [ "${min}" -eq 24 ] && [ "${par}" -lt 4 ]; }; }; }; then
    fallo "Docker Compose ${ver} es demasiado antiguo: hace falta 2.24.4 o superior. Actualiza Docker."
  fi
  command -v openssl >/dev/null || fallo "Falta openssl (genera la CA y el certificado LDAPS). En Ubuntu/WSL: sudo apt install openssl"
  info "Docker $(docker version --format '{{.Server.Version}}' 2>/dev/null) ($(sistema_docker)), Compose ${ver}"
}

comprobar_memoria() {
  paso "Comprobando memoria"
  local en_marcha
  en_marcha="$(contenedores_en_marcha)"
  if [ "${en_marcha}" -gt 0 ]; then
    info "Ya hay ${en_marcha} contenedores del sistema en marcha: la memoria que usan ya esta asignada; no se comprueba."
    return 0
  fi
  local total_gib
  total_gib="$(docker info --format '{{.MemTotal}}' | awk '{printf "%.1f", $1/1073741824}')"
  info "Memoria disponible para Docker: ${total_gib} GiB (hacen falta al menos ${MIN_VM_GIB})"
  if awk -v t="${total_gib}" -v m="${MIN_VM_GIB}" 'BEGIN{exit !(t < m)}'; then
    local msg="Docker solo dispone de ${total_gib} GiB y los 25 servicios necesitan ~5 GiB mas margen. Sube la memoria asignada (Docker Desktop: Settings > Resources; WSL: memory= en %UserProfile%\\.wslconfig)."
    ${FORZAR} && aviso "${msg} Se continua por --forzar." || fallo "${msg} Usa --forzar para intentarlo igualmente."
  fi
  if [ -r /proc/meminfo ] && [ "$(uname -s)" = "Linux" ]; then
    local libre_gib
    libre_gib="$(awk '/^MemAvailable:/ {printf "%.1f", $2/1048576}' /proc/meminfo)"
    info "Memoria libre en este sistema: ${libre_gib} GiB"
    if awk -v l="${libre_gib}" 'BEGIN{exit !(l < 5)}'; then
      aviso "Menos de 5 GiB libres: el arranque puede quedarse sin memoria. Cierra aplicaciones antes de seguir."
    fi
  fi
}

# --- Preparacion ----------------------------------------------------------------------------------------------------

preparar_certificados() {
  paso "Certificados LDAPS (CA interna + OpenLDAP)"
  # Idempotente: si existen, son validos y cubren las direcciones, no toca nada. No instala la CA en el host.
  bash "${RAIZ}/servicios/ca/generar-certificados.sh" --sin-instalar-ca | sed 's/^/    /'
  # Si falta un fichero de un bind mount, Docker crea un DIRECTORIO vacio en su lugar y LDAPS falla sin avisar.
  local f
  for f in ca.crt ldap.crt ldap.key; do
    if [ ! -f "${RAIZ}/servicios/ca/certs/${f}" ] || [ ! -s "${RAIZ}/servicios/ca/certs/${f}" ]; then
      fallo "Falta servicios/ca/certs/${f} (o esta vacio): openldap, inventree-app y erpnext-backend lo montan. Revisa la salida de servicios/ca/generar-certificados.sh."
    fi
  done
}

generar_zona() {
  paso "Zona DNS reservaviva.local"
  local dir="${RAIZ}/servicios/bind9/zones"
  local tpl="${dir}/db.reservaviva.local.tpl" out="${dir}/db.reservaviva.local"
  [ -f "${tpl}" ] || fallo "Falta la plantilla ${tpl}"
  # Cada nombre apunta al contenedor que da ese servicio, con la misma IP fija que le da el compose (mismas subredes
  # NET_* y mismos valores por defecto). rrhh es erpnext-hr, el nginx de ERPNext: el que atiende HTTP a los usuarios.
  local infra medica taquilla logistica rrhh serial
  infra="$(valor_env NET_INFRA 10.10.99)";         medica="$(valor_env NET_MEDICA 10.10.10)"
  taquilla="$(valor_env NET_TAQUILLA 10.10.20)";   logistica="$(valor_env NET_LOGISTICA 10.10.30)"
  rrhh="$(valor_env NET_RRHH 10.10.40)"
  local ip_ldap="${infra}.10" ip_dns="${infra}.11" ip_ntp="${infra}.12" ip_openvpms="${medica}.10" \
        ip_pretix="${taquilla}.10" ip_inventree="${logistica}.10" ip_rrhh="${rrhh}.10"
  serial="$(date +%Y%m%d%H)"
  tr -d '\r' <"${tpl}" | sed -e "s/\${IP_DNS}/${ip_dns}/g" -e "s/\${IP_LDAP}/${ip_ldap}/g" \
                             -e "s/\${IP_NTP}/${ip_ntp}/g" -e "s/\${IP_OPENVPMS}/${ip_openvpms}/g" \
                             -e "s/\${IP_PRETIX}/${ip_pretix}/g" -e "s/\${IP_INVENTREE}/${ip_inventree}/g" \
                             -e "s/\${IP_RRHH}/${ip_rrhh}/g" -e "s/\${SERIAL}/${serial}/g" >"${out}.tmp"
  if grep -q '\${[A-Z0-9_]*}' "${out}.tmp"; then
    rm -f "${out}.tmp"; fallo "Quedan marcadores sin sustituir en la plantilla de zona."
  fi
  # Si solo cambia el serial se conserva el fichero anterior: asi su fecha dice cuando cambio la zona de verdad, y
  # reiniciar_dns_si_zona_nueva solo reinicia bind9 cuando hace falta.
  if [ -f "${out}" ] && diff -q <(grep -v '; serial$' "${out}") <(grep -v '; serial$' "${out}.tmp") >/dev/null; then
    rm -f "${out}.tmp"
    info "Sin cambios (dns=${ip_dns} ldap=${ip_ldap} ntp=${ip_ntp} openvpms=${ip_openvpms} pretix=${ip_pretix}"
  else
    mv -f "${out}.tmp" "${out}"
    info "Generada (dns=${ip_dns} ldap=${ip_ldap} ntp=${ip_ntp} openvpms=${ip_openvpms} pretix=${ip_pretix}"
  fi
  info "          inventree=${ip_inventree} rrhh=${ip_rrhh})"
}

# Hash {SSHA} de OpenLDAP: base64(sha1(clave + sal) + sal). Con openssl, que ya es requisito, para no depender de python ni
# de la imagen de openldap (que en un primer arranque aun no esta descargada). La clave nunca va en la linea de comandos
# de ningun proceso: printf es un builtin de bash y openssl la lee por la tuberia.
hash_ssha() {
  local clave="$1" tmp h
  tmp="$(mktemp -d)"
  openssl rand 8 >"${tmp}/sal"
  { printf '%s' "${clave}"; cat "${tmp}/sal"; } | openssl dgst -sha1 -binary >"${tmp}/dig"
  h="$(cat "${tmp}/dig" "${tmp}/sal" | openssl base64 -A)"
  rm -rf "${tmp}"
  [ "${#h}" -eq 40 ] || fallo "No se pudo calcular el hash SSHA con openssl."
  printf '{SSHA}%s' "${h}"
}

# LDIF del primer arranque de OpenLDAP. sistema/test.env es la UNICA fuente de las claves del directorio: las plantillas
# servicios/openldap/*.ldif.tpl (versionadas, sin claves) llevan marcadores ${SSHA_<CUENTA>} y aqui se sustituyen por el
# hash de la variable de test.env correspondiente. El resultado va a servicios/openldap/generado/ (ignorado por git), que
# es la carpeta que el compose monta como bootstrap "custom" de la imagen. La imagen solo la carga con el directorio
# vacio (volumenes ldap_data y ldap_config), asi que regenerarla en cada "preparar" no cambia un directorio existente.
generar_ldif() {
  paso "LDIF del primer arranque de OpenLDAP (claves de sistema/test.env)"
  local dir="${RAIZ}/servicios/openldap" out="${RAIZ}/servicios/openldap/generado"
  local par marca var clave f base
  local -a sust=()
  for par in SVC_LECTURA:LDAP_SVC_LECTURA_PASSWORD VET:LDAP_PRUEBA_VET_PASSWORD \
             LOGISTICA:LDAP_PRUEBA_LOGISTICA_PASSWORD TAQUILLA:LDAP_PRUEBA_TAQUILLA_PASSWORD \
             RRHH:LDAP_PRUEBA_RRHH_PASSWORD; do
    marca="SSHA_${par%%:*}"; var="${par#*:}"
    clave="$(valor_env "${var}" "")"
    [ -n "${clave}" ] || fallo "Falta la clave de LDAP ${var}: definir ${var} en sistema/test.env (ver docs/seguridad.md)."
    # El hash usa base64 (A-Z a-z 0-9 + / =): "|" como separador de sed no puede aparecer en el.
    sust+=(-e "s|\${${marca}}|$(hash_ssha "${clave}")|g")
  done
  # Se escribe DENTRO de la carpeta existente (no se reemplaza la carpeta): un bind mount apunta a la carpeta, y si se
  # borrara y se creara de nuevo, un contenedor ya creado seguiria viendo la vieja.
  mkdir -p "${out}"
  rm -f "${out}"/*.tmp
  tr -d '\r' <"${dir}/05-acl-servicio.ldif" >"${out}/05-acl-servicio.ldif.tmp"
  for f in "${dir}"/*.ldif.tpl; do
    base="$(basename "${f}" .tpl)"
    { printf '# GENERADO por levantar-sistema.sh preparar desde servicios/openldap/%s.tpl: no editar.\n' "${base}"
      tr -d '\r' <"${f}" | sed "${sust[@]}"; } >"${out}/${base}.tmp"
  done
  if grep -q '\${[A-Z0-9_]*}' "${out}"/*.tmp; then
    rm -f "${out}"/*.tmp; fallo "Quedan marcadores sin sustituir en servicios/openldap/*.ldif.tpl."
  fi
  for f in "${out}"/*.tmp; do mv -f "${f}" "${f%.tmp}"; done
  # Un .ldif que ya no tenga plantilla se cargaria igual en el proximo primer arranque: se quita.
  for f in "${out}"/*.ldif; do
    base="$(basename "${f}")"
    [ "${base}" = "05-acl-servicio.ldif" ] || [ -f "${dir}/${base}.tpl" ] || rm -f "${f}"
  done
  info "Generados en servicios/openldap/generado/: $(cd "${out}" && ls *.ldif | tr '\n' ' ')"
  info "(OpenLDAP solo los carga con el directorio vacio; con datos ya existentes no cambian nada)"
}

# bind9 lee la zona al arrancar y no vigila el fichero. Si la zona es mas nueva que el arranque de dns-interno (p. ej.
# tras cambiar la plantilla), se reinicia solo ese contenedor: unos segundos, sin tocar datos.
reiniciar_dns_si_zona_nueva() {
  local zona="${RAIZ}/servicios/bind9/zones/db.reservaviva.local" inicio t_zona t_dns
  inicio="$(docker inspect --format '{{.State.StartedAt}}' dns-interno 2>/dev/null)" || return 0
  t_dns="$(date -d "${inicio}" +%s 2>/dev/null)" || return 0
  t_zona="$(stat -c %Y "${zona}" 2>/dev/null)" || return 0
  if [ "${t_zona}" -gt "${t_dns}" ]; then
    paso "La zona DNS cambio despues de arrancar dns-interno: se reinicia para que bind9 la lea"
    dc restart dns
  fi
}

validar_compose() {
  paso "Validando la configuracion de compose"
  dc config -q || fallo "docker compose config fallo: la configuracion no es valida."
  info "$(dc config --services | grep -c .) servicios definidos"
}

# La imagen de OpenVPMS es la unica que se construye aqui, y lleva DENTRO entrypoint.sh e init-lib.sh. "up -d" no la
# reconstruye cuando cambian, asi que se reconstruye siempre (con cache son segundos). Sin red, el build falla al consultar
# los metadatos de tomcat aunque tenga todo en cache: entonces solo se acepta la imagen existente si su entrypoint.sh e
# init-lib.sh son identicos a los del repositorio.
preparar_imagen_openvpms() {
  paso "Imagen de OpenVPMS (se construye localmente)"
  if dc build openvpms-app; then
    info "Imagen construida."
    return 0
  fi
  local img cid f distinto=false
  img="$(dc config --images 2>/dev/null | grep -i openvpms | head -n 1 || true)"
  if [ -z "${img}" ] || ! docker image inspect "${img}" >/dev/null 2>&1; then
    fallo "No se pudo construir la imagen de OpenVPMS y no hay una anterior. Hace falta Internet la primera vez."
  fi
  cid="$(docker create "${img}")"
  for f in entrypoint.sh init-lib.sh; do
    if ! MSYS2_ARG_CONV_EXCL='*' docker cp "${cid}:/${f}" - 2>/dev/null | tar -xO 2>/dev/null \
         | cmp -s - "${RAIZ}/servicios/openvpms/${f}"; then
      distinto=true
    fi
  done
  docker rm "${cid}" >/dev/null
  ${distinto} && fallo "No se pudo reconstruir la imagen de OpenVPMS y la existente NO coincide con el codigo actual (${img}). Conectate a Internet y repite."
  aviso "No se pudo reconstruir (sin red?); la imagen existente coincide con el codigo actual y se usa."
}

preparar() {
  cd "${RAIZ}"
  preparar_certificados
  generar_zona
  generar_ldif
  validar_compose
  preparar_imagen_openvpms
}

# --- Espera a que todo este sano ------------------------------------------------------------------------------------

# Estado de un contenedor en una linea: servicio|politica de reinicio|estado|codigo de salida|salud|reinicios
estado_contenedores() {
  local ids
  ids="$(dc ps -a -q)"
  [ -n "${ids}" ] || return 0
  # shellcheck disable=SC2086
  docker inspect --format '{{index .Config.Labels "com.docker.compose.service"}}|{{.HostConfig.RestartPolicy.Name}}|{{.State.Status}}|{{.State.ExitCode}}|{{if .State.Health}}{{.State.Health.Status}}{{else}}-{{end}}|{{.RestartCount}}' ${ids}
}

diagnostico() {
  local s
  printf '\n----- Estado de los contenedores -----\n' >&2
  dc ps -a >&2 || true
  for s in "$@"; do
    printf '\n----- Ultimas 40 lineas de %s -----\n' "${s}" >&2
    dc logs --no-color --tail 40 "${s}" >&2 || true
  done
}

esperar_sano() {
  paso "Esperando a que los servicios queden sanos (maximo ${TIMEOUT_MIN} min)"
  info "El primer arranque tarda: la base de OpenVPMS ~8 min y despues la aplicacion ~5; el sitio de ERPNext ~15."
  local inicio limite servicios n
  inicio="$(date +%s)"; limite=$(( inicio + TIMEOUT_MIN * 60 ))
  servicios="$(dc config --services)"
  n="$(printf '%s\n' "${servicios}" | grep -c .)"
  while :; do
    local lineas ok=0 pendientes=() malos=() s l politica est codigo salud reinicios
    lineas="$(estado_contenedores)"
    while IFS= read -r s; do
      [ -n "${s}" ] || continue
      l="$(printf '%s\n' "${lineas}" | grep -E "^${s}\|" | head -n 1 || true)"
      if [ -z "${l}" ]; then pendientes+=("${s}(sin crear)"); continue; fi
      IFS='|' read -r _ politica est codigo salud reinicios <<<"${l}"
      if [ "${politica}" = "no" ]; then
        # Trabajos de un solo disparo (configurator, create-site, ldap-config): terminar con 0 es el exito.
        if [ "${est}" = "exited" ]; then
          if [ "${codigo}" = "0" ]; then ok=$((ok + 1)); else malos+=("${s}"); fi
        else
          pendientes+=("${s}")
        fi
      elif [ "${est}" = "running" ] && { [ "${salud}" = "-" ] || [ "${salud}" = "healthy" ]; }; then
        ok=$((ok + 1))
      elif [ "${salud}" = "unhealthy" ] || [ "${est}" = "exited" ] || [ "${est}" = "dead" ] || [ "${reinicios:-0}" -gt 3 ]; then
        malos+=("${s}")
      else
        pendientes+=("${s}")
      fi
    done <<<"${servicios}"

    local t=$(( $(date +%s) - inicio ))
    printf '    [%02d:%02d] sanos %d/%d' $((t / 60)) $((t % 60)) "${ok}" "${n}"
    [ ${#pendientes[@]} -gt 0 ] && printf ' - esperando: %s' "${pendientes[*]}"
    printf '\n'

    if [ ${#malos[@]} -gt 0 ]; then
      diagnostico "${malos[@]}"
      fallo "Servicios con fallo: ${malos[*]}. Revisa los logs de arriba. Volver a ejecutar el script es seguro: retoma donde quedo."
    fi
    [ "${ok}" -eq "${n}" ] && return 0
    if [ "$(date +%s)" -ge "${limite}" ]; then
      diagnostico "${pendientes[@]%%(*}"
      fallo "Tras ${TIMEOUT_MIN} min siguen sin estar listos: ${pendientes[*]}. Puedes esperar mas con: $0 --timeout 90 (desde PowerShell: -TimeoutMin 90)"
    fi
    sleep 20
  done
}

# Pretix no crea su administrador por variables de entorno: trae admin@localhost con clave "admin". Se crea el de
# test.env (PRETIX_ADMIN_EMAIL / PRETIX_ADMIN_PASSWORD) y se borra admin@localhost. Idempotente. Antes lo hacia
# init_admins en el deploy.sh del despliegue en 3 equipos (retirado en 95e0da4). La clave va por el entorno de
# docker exec, no por la linea de comandos.
crear_admin_pretix() {
  paso "Administrador de Pretix"
  local email
  email="$(valor_env PRETIX_ADMIN_EMAIL "")"
  [ -n "${email}" ] || fallo "Falta PRETIX_ADMIN_EMAIL en ${ENV_FILE}."
  [ -n "$(valor_env PRETIX_ADMIN_PASSWORD "")" ] || fallo "Falta PRETIX_ADMIN_PASSWORD en ${ENV_FILE}."
  local intento
  for intento in 1 2 3 4 5 6; do
    if ADM_EMAIL="${email}" ADM_PASS="$(valor_env PRETIX_ADMIN_PASSWORD "")"         docker exec -i -e ADM_EMAIL -e ADM_PASS pretix-web python -m pretix shell >/dev/null 2>&1 <<'PY'
import os
from pretix.base.models import User
email = os.environ["ADM_EMAIL"]
if not User.objects.filter(email__iexact=email).exists():
    User.objects.create_superuser(email, os.environ["ADM_PASS"])
if email.lower() != "admin@localhost":
    User.objects.filter(email="admin@localhost").delete()
assert User.objects.filter(email__iexact=email, is_staff=True).exists()
assert not User.objects.filter(email="admin@localhost").exists()
PY
    then
      info "Listo: ${email} (admin@localhost eliminado)"
      return 0
    fi
    sleep 10
  done
  fallo "No se pudo crear el administrador de Pretix. Volver a ejecutar el script es seguro."
}

# --- Acciones -------------------------------------------------------------------------------------------------------

accesos() {
  local p1 p2 p3 p4 ldap ldaps dns ntp
  p1="$(valor_env OPENVPMS_PORT 8080)"; p2="$(valor_env ERPNEXT_PORT 8080)"
  p3="$(valor_env PRETIX_PORT 80)";     p4="$(valor_env INVENTREE_PORT 8000)"
  ldap="$(valor_env LDAP_PORT 389)"; ldaps="$(valor_env LDAPS_PORT 636)"
  dns="$(valor_env DNS_PORT 53)";    ntp="$(valor_env NTP_PORT 123)"
  cat <<EOF

    Accesos (solo desde este equipo):
      Medica             OpenVPMS   http://localhost:${p1}/openvpms     usuario: admin
      Taquilla           Pretix     http://localhost:${p3}              usuario: $(valor_env PRETIX_ADMIN_EMAIL admin@reservaviva.local)
      Logistica          InvenTree  http://localhost:${p4}              usuario: $(valor_env INVENTREE_ADMIN_USER admin)
      RRHH               ERPNext    http://localhost:${p2}              usuario: Administrator
      Infra              LDAP localhost:${ldap}  LDAPS localhost:${ldaps}  DNS localhost:${dns}  NTP localhost:${ntp}/udp
    Contrasenas de laboratorio (desechables): sistema/test.env
EOF
}

aviso_sesion_wsl() {
  if en_wsl && [ "$(sistema_docker)" != "Docker Desktop" ] && ! pgrep -f "${MARCA_SESION}" >/dev/null 2>&1; then
    aviso "Estas en WSL con Docker Engine: si se cierran TODAS las terminales de WSL, Docker se detiene y se lleva los"
    aviso "contenedores. Deja esta terminal abierta, o arranca desde Windows con levantar-sistema.ps1, que mantiene la sesion."
  fi
}

accion_arrancar() {
  comprobar_requisitos
  comprobar_memoria
  preparar
  paso "Levantando los 25 servicios (la primera vez descarga varios GB de imagenes)"
  if ! dc up -d; then
    diagnostico
    fallo "docker compose up fallo. Volver a ejecutar el script es seguro: retoma donde quedo."
  fi
  reiniciar_dns_si_zona_nueva
  esperar_sano
  crear_admin_pretix
  paso "Sistema en marcha: los 25 servicios estan sanos"
  accesos
  info ""
  info "Siguiente paso recomendado:  $0 verificar   (segmentacion, DNS, NTP y LDAP)"
  aviso_sesion_wsl
}

accion_preparar() {
  comprobar_requisitos
  preparar
  paso "Preparacion completa. Para levantar el sistema: $0 arrancar"
}

accion_estado() {
  cd "${RAIZ}"
  docker info >/dev/null 2>&1 || fallo "Docker no responde."
  paso "Estado de los servicios"
  dc ps -a --format 'table {{.Service}}\t{{.State}}\t{{.Status}}'
  accesos
  aviso_sesion_wsl
}

accion_verificar() {
  cd "${ARNES}"
  local py
  py="$(command -v python3 || command -v python || true)"
  [ -n "${py}" ] || fallo "Falta python3 para ejecutar la verificacion."
  mkdir -p resultados
  local informe
  informe="resultados/verificacion-$(date +%Y%m%d-%H%M%S).txt"
  local args=(--informe "${informe}")
  ${RAPIDO} && args+=(--sin-persistencia)
  paso "Verificando la arquitectura (${py} verificar_arquitectura.py ${args[*]})"
  local rc=0
  "${py}" verificar_arquitectura.py "${args[@]}" || rc=$?
  info "Informe completo: sistema/${informe}"
  [ "${rc}" -eq 0 ] && paso "Verificacion superada" || fallo "La verificacion tiene fallos (codigo ${rc}); detalle en el informe."
}

accion_detener() {
  cd "${RAIZ}"
  paso "Deteniendo los contenedores (no se borra nada)"
  dc stop
  info "Detenidos. Para volver a levantarlos: $0 arrancar"
}

accion_borrar() {
  cd "${RAIZ}"
  if ! ${SI}; then
    printf '\nEsto BORRA los contenedores y TODOS los datos (bases de datos, sitio de ERPNext, directorio LDAP).\n'
    printf 'El siguiente arranque volvera a inicializarlo todo (~30 min). Escribe "borrar" para confirmar: '
    local r; read -r r
    [ "${r}" = "borrar" ] || { echo "Cancelado."; exit 0; }
  fi
  paso "Eliminando contenedores, redes y volumenes"
  dc down -v --remove-orphans
}

case "${ACCION}" in
  arrancar)  accion_arrancar ;;
  preparar)  accion_preparar ;;
  estado)    accion_estado ;;
  verificar) accion_verificar ;;
  detener)   accion_detener ;;
  borrar)    accion_borrar ;;
esac
