#!/usr/bin/env bash
# Primer arranque de OpenVPMS sin pasos manuales: espera a MySQL, escribe la configuración,
# crea el esquema y carga los datos base UNA vez, genera el WAR y lanza Tomcat.
# Si la inicialización ya terminó (marcas en el volumen de estado), solo arranca Tomcat. Si un arranque anterior se
# interrumpió, ver init-lib.sh: qué se recupera solo y qué exige intervención.
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
# La URL de la base se reescribe en CADA arranque desde OPENVPMS_DB_HOST: el fichero del volumen puede venir de una version
# anterior con otra direccion (la IP fija que tenia openvpms-db antes de existir una sola red). Solo cambian db.url y
# reporting.db.url; la clave de cifrado y las claves de la base no se tocan.
URL="jdbc:mysql://${OPENVPMS_DB_HOST}:${DB_PORT}/${DB_NAME}?useSSL=false&allowPublicKeyRetrieval=true"
{ grep -v -e '^db\.url=' -e '^reporting\.db\.url=' "${STATE_DIR}/openvpms.properties" || true
  echo "db.url=${URL}"
  echo "reporting.db.url=${URL}"
} > "${STATE_DIR}/openvpms.properties.nuevo"
mv "${STATE_DIR}/openvpms.properties.nuevo" "${STATE_DIR}/openvpms.properties"
cp "${STATE_DIR}/openvpms.properties" "${PROPS}"
chmod 600 "${PROPS}" "${STATE_DIR}/openvpms.properties"

cd "${OPENVPMS_HOME}/bin"
# Inicialización por etapas (esquema, datos base, clave de admin, plantillas), reanudable tras una interrupción.
# Toda la lógica, incluido qué cubre y qué NO, está documentada en init-lib.sh y probada sin Docker por test-reanudable.sh.
MARK="${STATE_DIR}/init"
mkdir -p "${MARK}"
# shellcheck source=init-lib.sh
. "${OPENVPMS_INIT_LIB:-/init-lib.sh}"
inicializar
echo "[openvpms] Inicialización completa."

if [ ! -f "${CATALINA_HOME}/webapps/openvpms.war" ]; then
  echo "[openvpms] Generando openvpms.war..."
  ./toolbox war
  war=$(find "${OPENVPMS_HOME}" -name openvpms.war -print -quit)
  [ -n "${war}" ] || { echo "[openvpms] toolbox war no generó openvpms.war" >&2; exit 1; }
  # Copia con otro nombre y renombra: si el contenedor muere a mitad de la copia, Tomcat no encuentra un .war truncado
  # (el `[ ! -f openvpms.war ]` de arriba lo daría por bueno) y la siguiente vez se genera de nuevo.
  cp "${war}" "${CATALINA_HOME}/webapps/openvpms.war.tmp"
  mv "${CATALINA_HOME}/webapps/openvpms.war.tmp" "${CATALINA_HOME}/webapps/openvpms.war"
fi

cd "${CATALINA_HOME}"
exec "$@"
