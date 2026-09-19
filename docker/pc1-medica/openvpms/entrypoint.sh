#!/usr/bin/env bash
# Primer arranque de OpenVPMS sin pasos manuales: espera a MySQL, escribe la configuración,
# crea el esquema y carga los datos base UNA vez, genera el WAR y lanza Tomcat.
# Es idempotente: si la base ya tiene esquema, solo arranca Tomcat.
set -euo pipefail

: "${OPENVPMS_DB_HOST:?falta OPENVPMS_DB_HOST}"
: "${OPENVPMS_DB_ROOT_PASSWORD:?falta OPENVPMS_DB_ROOT_PASSWORD}"
: "${OPENVPMS_DB_PASSWORD:?falta OPENVPMS_DB_PASSWORD}"
: "${OPENVPMS_ADMIN_PASSWORD:?falta OPENVPMS_ADMIN_PASSWORD}"
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

cat > "${OPENVPMS_HOME}/conf/openvpms.properties" <<EOF
db.driver=com.mysql.cj.jdbc.Driver
db.url=jdbc:mysql://${OPENVPMS_DB_HOST}:${DB_PORT}/${DB_NAME}?useSSL=false&allowPublicKeyRetrieval=true
db.username=${DB_USER}
db.password=${OPENVPMS_DB_PASSWORD}
EOF
chmod 600 "${OPENVPMS_HOME}/conf/openvpms.properties"

tables=$(mysql --host="${OPENVPMS_DB_HOST}" --port="${DB_PORT}" --user=root \
  --password="${OPENVPMS_DB_ROOT_PASSWORD}" -N -B \
  -e "SELECT COUNT(*) FROM information_schema.tables WHERE table_schema='${DB_NAME}'" 2>/dev/null || echo 0)

cd "${OPENVPMS_HOME}/bin"
if [ "${tables}" -eq 0 ]; then
  echo "[openvpms] Base vacía: creando esquema y cargando datos base (primer arranque)..."
  ./toolbox database --create -u root -p "${OPENVPMS_DB_ROOT_PASSWORD}"
  ./dataload.sh setup
  ./toolbox user --setpassword admin -p "${OPENVPMS_ADMIN_PASSWORD}"
  ./toolbox template --load --size A4 --all
else
  echo "[openvpms] Esquema existente (${tables} tablas): se omite la inicialización."
fi

if [ ! -f "${CATALINA_HOME}/webapps/openvpms.war" ]; then
  echo "[openvpms] Generando openvpms.war..."
  ./toolbox war
  war=$(find "${OPENVPMS_HOME}" -name openvpms.war -print -quit)
  [ -n "${war}" ] || { echo "[openvpms] toolbox war no generó openvpms.war" >&2; exit 1; }
  cp "${war}" "${CATALINA_HOME}/webapps/openvpms.war"
fi

cd "${CATALINA_HOME}"
exec "$@"
