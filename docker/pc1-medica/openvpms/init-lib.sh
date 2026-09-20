#!/usr/bin/env bash
# Inicialización reanudable de OpenVPMS. Se carga con `source` desde entrypoint.sh (y desde test-reanudable.sh, que
# prueba esta lógica sin Docker ni MySQL). No se ejecuta sola.
#
# Requiere, definidas por quien la carga: MARK (carpeta de marcas, en el volumen de estado), DB_NAME, DB_USER, DB_PORT,
# OPENVPMS_DB_HOST y OPENVPMS_DB_ROOT_PASSWORD. Los comandos de las etapas se ejecutan desde el directorio actual
# (./toolbox, ./dataload.sh): el llamador hace `cd` antes.
#
# MODELO DE MARCAS (dos por etapa, en ${MARK}):
#   <etapa>.started   se escribe ANTES de ejecutar la etapa: "esta etapa empezó".
#   <etapa>           se escribe DESPUÉS de que la etapa termine bien: "esta etapa terminó".
# Hay que distinguir las dos cosas porque una interrupción real (docker.service reiniciado, contenedor matado con SIGKILL,
# corte de luz) no ejecuta ningún código de limpieza: no sirve "escribir la marca antes y borrarla si falla", porque el
# borrado nunca ocurre y la etapa quedaría dada por hecha estando a medias. Con .started sí se sabe que hubo un intento
# que no terminó.
#
# LO QUE CUBRE Y LO QUE NO (no fingir más de lo que hace):
#  - Etapa que falla o muere: la siguiente vez se repite ENTERA; las ya terminadas se saltan. Que repetirla sea
#    seguro depende de la etapa: adminpass y templates lo son; NO SE HA VERIFICADO que `dataload.sh setup` pueda
#    repetirse sobre datos cargados a medias (podría fallar o duplicar). Si falla, la salida es `docker compose down -v`.
#  - Etapa schema: `toolbox database --create` NO es repetible (falla con "Cannot create openvpms as there are tables
#    already present"), y que haya tablas NO prueba que el esquema esté completo. Por eso, si hay tablas, no hay marca
#    schema y SÍ hay schema.started (nuestro propio intento interrumpido) y ninguna etapa posterior terminó, se borra la
#    base y sus usuarios y se repite desde cero. Es seguro porque Tomcat solo arranca cuando TODAS las etapas acabaron:
#    en ese punto no puede haber datos de usuario.
#  - Tablas presentes pero SIN ninguna marca (volumen de estado perdido, base restaurada de otro sitio, o el estado que
#    dejó la versión anterior de este script): no hay pruebas de qué es. No se borra nada por defecto: se aborta con un
#    mensaje. Quien sepa que la base es desechable puede pedirlo con OPENVPMS_REINICIALIZAR_BASE=yes.

mysql_root() {
  mysql --host="${OPENVPMS_DB_HOST}" --port="${DB_PORT}" --user=root --password="${OPENVPMS_DB_ROOT_PASSWORD}" "$@"
}

# Imprime el número de tablas de la base. Si la consulta falla NO se responde 0: tomar un fallo de conexión o de
# credenciales por "base vacía" borraría las marcas y relanzaría la inicialización sobre una base que sí tiene datos.
contar_tablas() {
  local n
  if ! n=$(mysql_root -N -B -e "SELECT COUNT(*) FROM information_schema.tables WHERE table_schema='${DB_NAME}'" 2>/dev/null); then
    echo "[openvpms] No pude consultar MySQL para contar las tablas de '${DB_NAME}'; no decido nada a ciegas." >&2
    return 1
  fi
  if ! [[ "${n}" =~ ^[0-9]+$ ]]; then
    echo "[openvpms] Respuesta inesperada al contar las tablas de '${DB_NAME}': '${n}'." >&2
    return 1
  fi
  echo "${n}"
}

hay_etapas_posteriores_a_schema() {
  local n
  for n in data adminpass templates; do
    if [ -f "${MARK}/${n}" ]; then return 0; fi
  done
  return 1
}

# Deja MySQL como en un primer arranque: sin la base de OpenVPMS ni sus dos usuarios, y sin marcas.
reiniciar_base() {
  echo "[openvpms] Borrando la base '${DB_NAME}' y sus usuarios para repetir la inicialización desde cero..." >&2
  mysql_root -e "DROP DATABASE IF EXISTS \`${DB_NAME}\`; DROP USER IF EXISTS '${DB_USER}'@'%', '${DB_USER}'@'localhost', '${DB_USER}report'@'%', '${DB_USER}report'@'localhost';"
  rm -f "${MARK}"/*
}

# Decide si la etapa schema puede ejecutarse. Devuelve 1 (con mensaje) si el estado es ambiguo.
preparar_esquema() {
  local tables="$1"
  if [ "${tables}" -eq 0 ]; then
    rm -f "${MARK}"/*        # base vacía o recreada: las marcas que hubiera ya no valen
    return 0
  fi
  if [ -f "${MARK}/schema" ]; then return 0; fi

  if [ -f "${MARK}/schema.started" ] && ! hay_etapas_posteriores_a_schema; then
    echo "[openvpms] La creación del esquema se interrumpió en un arranque anterior (${tables} tablas, sin marca 'schema'). Puede estar incompleto." >&2
    reiniciar_base
    return 0
  fi
  if [ "${OPENVPMS_REINICIALIZAR_BASE:-no}" = "yes" ]; then
    echo "[openvpms] OPENVPMS_REINICIALIZAR_BASE=yes: se borra la base '${DB_NAME}' aunque no hay evidencia de un intento interrumpido." >&2
    reiniciar_base
    return 0
  fi
  echo "[openvpms] La base '${DB_NAME}' tiene ${tables} tablas pero no hay marca de esquema ni de intento interrumpido en ${MARK}." >&2
  echo "[openvpms] No sé si el esquema está completo ni si esos datos son valiosos, así que no borro nada." >&2
  echo "[openvpms] Si la base es desechable: 'docker compose down -v' (borra los volúmenes) o arrancar una vez con OPENVPMS_REINICIALIZAR_BASE=yes." >&2
  return 1
}

step() {  # step <marca> <descripción> <comando...>
  local name="$1" desc="$2"; shift 2
  if [ -f "${MARK}/${name}" ]; then return 0; fi
  if [ -f "${MARK}/${name}.started" ]; then
    echo "[openvpms] La etapa '${name}' quedó a medias en un arranque anterior: se repite entera." >&2
  fi
  echo "[openvpms] ${desc}..."
  touch "${MARK}/${name}.started"
  # Comprobación explícita: no depender de `set -e` para no marcar como hecha una etapa que falló.
  if ! "$@"; then
    echo "[openvpms] La etapa '${name}' (${desc}) falló; no se marca como hecha." >&2
    return 1
  fi
  touch "${MARK}/${name}"
  rm -f "${MARK}/${name}.started"
}

# El release 2.4.0.1 trae una plantilla ('Investigation') que apunta a un tipo inexistente
# (act.patientInvestigation): el cargador se detiene ahí, con ~37 plantillas cargadas. Solo afecta a
# plantillas de impresión, no al arranque; se avisa y se continúa.
cargar_plantillas() {
  ./toolbox template --load --size A4 --all \
    || echo "[openvpms] AVISO: la carga de plantillas terminó con error (conocido en 2.4.0.1); algunas plantillas de impresión no están cargadas." >&2
}

inicializar() {
  local tables
  tables=$(contar_tablas) || return 1
  preparar_esquema "${tables}" || return 1
  step schema    "Creando esquema"             ./toolbox database --create --host=% -u root -p "${OPENVPMS_DB_ROOT_PASSWORD}" || return 1
  step data      "Cargando datos base"         ./dataload.sh setup || return 1
  step adminpass "Fijando clave de admin"      ./toolbox user --setpassword admin -p "${OPENVPMS_ADMIN_PASSWORD}" || return 1
  step templates "Cargando plantillas (A4)"    cargar_plantillas || return 1
}
