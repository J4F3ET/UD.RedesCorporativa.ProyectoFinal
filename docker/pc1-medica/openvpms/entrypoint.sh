#!/usr/bin/env bash
# Primer arranque de OpenVPMS sin pasos manuales: espera a MySQL, escribe la configuración,
# crea el esquema y carga los datos base UNA vez, genera el WAR y lanza Tomcat.
# Es idempotente: si la base ya tiene esquema, solo arranca Tomcat.
set -euo pipefail

: "${OPENVPMS_DB_HOST:?falta OPENVPMS_DB_HOST}"
: "${OPENVPMS_DB_ROOT_PASSWORD:?falta OPENVPMS_DB_ROOT_PASSWORD}"
: "${OPENVPMS_DB_PASSWORD:?falta OPENVPMS_DB_PASSWORD}"
: "${OPENVPMS_ADMIN_PASSWORD:?falta OPENVPMS_ADMIN_PASSWORD}"
# OpenVPMS rechaza claves débiles a mitad del primer arranque; mejor fallar antes de tocar la base.
pw="${OPENVPMS_ADMIN_PASSWORD}"
if [ "${#pw}" -lt 8 ] || ! [[ "${pw}" =~ [A-Z] ]] || ! [[ "${pw}" =~ [a-z] ]] \
   || ! [[ "${pw}" =~ [0-9] ]] || ! [[ "${pw}" =~ [^A-Za-z0-9] ]]; then
  echo "[openvpms] OPENVPMS_ADMIN_PASSWORD no cumple la política: mínimo 8 caracteres con mayúscula, minúscula, número y un carácter especial (p. ej. !)." >&2
  exit 1
fi
DB_PORT="${OPENVPMS_DB_PORT:-3306}"
DB_NAME="${OPENVPMS_DB_NAME:-openvpms}"
DB_USER="${OPENVPMS_DB_USER:-openvpms}"

echo "[openvpms] Esperando a MySQL en ${OPENVPMS_DB_HOST}:${DB_PORT}..."
for i in $(seq 1 90); do
  if mysqladmin --host="${OPENVPMS_DB_HOST}" --port="${DB_PORT}" --user=root \
       --password="${OPENVPMS_DB_ROOT_PASSWORD}" --silent ping >/dev/null 2>&1; then
    break
  fi
  [ "$i" -eq 90 ] && { echo "[openvpms] MySQL no respondió a tiempo." >&2; exit 1; }
  sleep 2
done

# openvpms.properties vive en un volumen: contiene openvpms.key, la clave que cifra datos en la base.
# Si se pierde al recrear el contenedor, esos datos quedan ilegibles.
STATE_DIR="${OPENVPMS_STATE_DIR:-/var/lib/openvpms-state}"
PROPS="${OPENVPMS_HOME}/conf/openvpms.properties"
mkdir -p "${STATE_DIR}"
if [ ! -f "${STATE_DIR}/openvpms.properties" ]; then
  # `toolbox configure --default` genera la clave de cifrado; luego fijamos nuestros valores.
  (cd "${OPENVPMS_HOME}/bin" && ./toolbox configure --default >/dev/null)
  key=$(grep '^openvpms.key=' "${PROPS}")
  URL="jdbc:mysql://${OPENVPMS_DB_HOST}:${DB_PORT}/${DB_NAME}?useSSL=false&allowPublicKeyRetrieval=true"
  {
    echo "db.driver=com.mysql.cj.jdbc.Driver"
    echo "db.url=${URL}"
    echo "db.username=${DB_USER}"
    echo "db.password=${OPENVPMS_DB_PASSWORD}"
    echo "reporting.db.url=${URL}"
    echo "reporting.db.username=${DB_USER}report"
    echo "reporting.db.password=${OPENVPMS_DB_PASSWORD}-report"
    echo "${key}"
  } > "${STATE_DIR}/openvpms.properties"
fi
cp "${STATE_DIR}/openvpms.properties" "${PROPS}"
chmod 600 "${PROPS}" "${STATE_DIR}/openvpms.properties"

tables=$(mysql --host="${OPENVPMS_DB_HOST}" --port="${DB_PORT}" --user=root \
  --password="${OPENVPMS_DB_ROOT_PASSWORD}" -N -B \
  -e "SELECT COUNT(*) FROM information_schema.tables WHERE table_schema='${DB_NAME}'" 2>/dev/null || echo 0)

cd "${OPENVPMS_HOME}/bin"
# La inicialización se reanuda por etapas: si un arranque se interrumpe a mitad (p. ej. por una clave
# rechazada), el siguiente completa solo lo que falta. Las marcas viven junto a openvpms.properties.
MARK="${STATE_DIR}/init"
mkdir -p "${MARK}"
[ "${tables}" -eq 0 ] && rm -f "${MARK}"/*   # base vacía o recreada: empezar de cero

step() {  # step <marca> <descripción> <comando...>
  local name="$1" desc="$2"; shift 2
  if [ -f "${MARK}/${name}" ]; then return 0; fi
  echo "[openvpms] ${desc}..."
  "$@"
  touch "${MARK}/${name}"
}
step schema    "Creando esquema"             ./toolbox database --create --host=% -u root -p "${OPENVPMS_DB_ROOT_PASSWORD}"
step data      "Cargando datos base"         ./dataload.sh setup
step adminpass "Fijando clave de admin"      ./toolbox user --setpassword admin -p "${OPENVPMS_ADMIN_PASSWORD}"
# El release 2.4.0.1 trae una plantilla ('Investigation') que apunta a un tipo inexistente
# (act.patientInvestigation): el cargador se detiene ahí, con ~37 plantillas cargadas. Solo afecta a
# plantillas de impresión, no al arranque; se avisa y se continúa.
load_templates() {
  ./toolbox template --load --size A4 --all \
    || echo "[openvpms] AVISO: la carga de plantillas terminó con error (conocido en 2.4.0.1); algunas plantillas de impresión no están cargadas." >&2
}
step templates "Cargando plantillas (A4)"    load_templates
echo "[openvpms] Inicialización completa."

if [ ! -f "${CATALINA_HOME}/webapps/openvpms.war" ]; then
  echo "[openvpms] Generando openvpms.war..."
  ./toolbox war
  war=$(find "${OPENVPMS_HOME}" -name openvpms.war -print -quit)
  [ -n "${war}" ] || { echo "[openvpms] toolbox war no generó openvpms.war" >&2; exit 1; }
  cp "${war}" "${CATALINA_HOME}/webapps/openvpms.war"
fi

cd "${CATALINA_HOME}"
exec "$@"
