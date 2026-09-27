#!/usr/bin/env bash
# Prueba, SIN Docker ni MySQL, la lógica de inicialización reanudable de init-lib.sh.
# MySQL y las herramientas de OpenVPMS (toolbox, dataload.sh) son simulacros que dejan constancia de lo que se les pide y
# pueden fallar o morir a voluntad: una "muerte" es `kill -KILL` al proceso que ejecuta la inicialización, que es lo que
# hace docker.service al reiniciarse (no hay trap ni limpieza que valga).
#
# Uso:  bash servicios/openvpms/test-reanudable.sh        (sale con 0 si todo pasa)
#
# LÍMITE: esto prueba la lógica de decisión, no OpenVPMS. Que `toolbox database --create` tras borrar la base y los
# usuarios vuelva a funcionar, y que `dataload.sh setup` sea repetible, NO se ha verificado aquí.
set -u
AQUI="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LIB="${AQUI}/init-lib.sh"
T="$(mktemp -d)"
trap 'rm -rf "${T}"' EXIT
FALLOS=0

ok()   { echo "  [PASS] $1"; }
mal()  { echo "  [FAIL] $1"; FALLOS=$((FALLOS + 1)); }
chk()  { if eval "$2"; then ok "$1"; else mal "$1   (condición: $2)"; fi; }
cuenta() { grep -c "^$1\$" "${SIM}/log" 2>/dev/null || true; }

# --- simulacros ---------------------------------------------------------------------------------------------------
mkdir -p "${T}/fakebin" "${T}/bin"
cat > "${T}/fakebin/mysql" <<'FAKE'
#!/usr/bin/env bash
sql=""
while [ $# -gt 0 ]; do case "$1" in -e) sql="$2"; shift 2;; *) shift;; esac; done
if [ -f "${SIM}/mysql_caido" ]; then echo "ERROR 2003 (HY000): Can't connect to MySQL server" >&2; exit 1; fi
case "${sql}" in
  *"SELECT COUNT(*)"*) cat "${SIM}/tablas" ;;
  *"DROP DATABASE"*)   echo 0 > "${SIM}/tablas"; echo "drop-base" >> "${SIM}/log" ;;
  *) echo "mysql simulado: consulta inesperada: ${sql}" >&2; exit 2 ;;
esac
FAKE
cat > "${T}/bin/toolbox" <<'FAKE'
#!/usr/bin/env bash
case "$1 ${2:-}" in
  "database --create")
    echo "schema" >> "${SIM}/log"
    if [ "$(cat "${SIM}/tablas")" -gt 0 ]; then echo "Cannot create openvpms as there are tables already present" >&2; exit 1; fi
    echo 49 > "${SIM}/tablas"
    [ "${INTERRUMPIR:-}" = schema ] && kill -KILL "${PPID}"   # tablas ya creadas, marca aún no escrita
    ;;
  "user --setpassword")
    echo "adminpass" >> "${SIM}/log"
    [ "${FALLAR:-}" = adminpass ] && { echo "clave rechazada" >&2; exit 1; }
    ;;
  "template --load") echo "templates" >> "${SIM}/log" ;;
  *) echo "toolbox simulado: ${*}" >&2; exit 2 ;;
esac
exit 0
FAKE
cat > "${T}/bin/dataload.sh" <<'FAKE'
#!/usr/bin/env bash
echo "data" >> "${SIM}/log"
if [ "${INTERRUMPIR:-}" = data ]; then echo parcial > "${SIM}/datos"; kill -KILL "${PPID}"; fi
[ "${FALLAR:-}" = data ] && { echo parcial > "${SIM}/datos"; echo "dataload falló" >&2; exit 1; }
echo completo > "${SIM}/datos"
FAKE
chmod +x "${T}/fakebin/mysql" "${T}/bin/toolbox" "${T}/bin/dataload.sh"

# --- utilidades de escenario ------------------------------------------------------------------------------------
nuevo() {  # escenario limpio: base vacía y sin marcas
  SIM="${T}/sim-$1"; MARK="${T}/estado-$1/init"
  rm -rf "${SIM}" "${T}/estado-$1"; mkdir -p "${SIM}" "${MARK}"
  echo 0 > "${SIM}/tablas"; : > "${SIM}/log"
}
# Ejecuta la inicialización en un proceso bash APARTE (como el entrypoint). $1 = "e" (con set -e, como el entrypoint) o
# "sin_e"; el resto = variables de entorno extra. Devuelve el código de salida del proceso (137 = muerto con SIGKILL).
correr() {
  local modo="$1"; shift
  local -a opts=(-euo pipefail)
  [ "${modo}" = sin_e ] && opts=(-uo pipefail)
  ( cd "${T}/bin" && env PATH="${T}/fakebin:${PATH}" SIM="${SIM}" MARK="${MARK}" DB_NAME=openvpms DB_USER=openvpms DB_PORT=3306 \
      OPENVPMS_DB_HOST=127.0.0.1 OPENVPMS_DB_ROOT_PASSWORD=x OPENVPMS_ADMIN_PASSWORD=Aa1! "$@" \
      bash "${opts[@]}" -c ". '${LIB}'; inicializar" ) >"${SIM}/salida" 2>&1
}
marcas() { ls "${MARK}" 2>/dev/null | tr '\n' ' '; }

# =====================================================================================================================
echo "== 0. Comprobaciones previas sobre bash =="
salida=$(bash -c 'set -euo pipefail; tables=5; [ "${tables}" -eq 0 ] && rm -f /nonexistent-x; echo sigue-vivo' 2>&1)
chk "bajo set -e, '[ test-falso ] && rm ...' NO aborta el script (la línea 65 antigua no era el problema)" '[ "${salida}" = "sigue-vivo" ]'

# =====================================================================================================================
echo "== 1. Base vacía y sin marcas: ejecuta todas las etapas =="
nuevo 1
correr e; rc=$?
chk "termina con 0"                              '[ ${rc} -eq 0 ]'
chk "orden: schema, data, adminpass, templates"  '[ "$(tr "\n" " " < "${SIM}/log")" = "schema data adminpass templates " ]'
chk "las cuatro marcas existen y no quedan .started" '[ "$(marcas)" = "adminpass data schema templates " ]'

# =====================================================================================================================
echo "== 2. Todas las etapas hechas: no ejecuta ninguna =="
: > "${SIM}/log"
correr e; rc=$?
chk "termina con 0"                              '[ ${rc} -eq 0 ]'
chk "no se ejecutó ningún comando"               '[ ! -s "${SIM}/log" ]'

# =====================================================================================================================
echo "== 3. Muerte a mitad de 'schema' (tablas creadas, sin marca): EL CASO QUE ROMPÍA =="
nuevo 3
correr e INTERRUMPIR=schema; rc=$?
chk "el primer arranque muere (SIGKILL, código 137)"   '[ ${rc} -eq 137 ]'
chk "queda el estado que se midió: 49 tablas, schema.started, sin marca schema" \
    '[ "$(cat "${SIM}/tablas")" = 49 ] && [ "$(marcas)" = "schema.started " ]'
correr e; rc=$?
chk "el segundo arranque termina con 0 (se recupera)"  '[ ${rc} -eq 0 ]'
chk "borró la base una vez y repitió schema (2 intentos en total)" '[ "$(cuenta drop-base)" = 1 ] && [ "$(cuenta schema)" = 2 ]'
chk "completó data, adminpass y templates"             '[ "$(cuenta data)" = 1 ] && [ "$(cuenta adminpass)" = 1 ] && [ "$(cuenta templates)" = 1 ]'
chk "marcas finales completas, sin .started"           '[ "$(marcas)" = "adminpass data schema templates " ]'
: > "${SIM}/log"
correr e; rc=$?
chk "un tercer arranque no ejecuta nada"               '[ ${rc} -eq 0 ] && [ ! -s "${SIM}/log" ]'

# =====================================================================================================================
echo "== 3b. REGRESIÓN: la lógica ANTERIOR (f3e647d) con el mismo estado entra en bucle =="
viejo() {  # copia de las líneas 56-84 del entrypoint.sh anterior
  ( cd "${T}/bin" && env PATH="${T}/fakebin:${PATH}" SIM="${SIM}" MARK="${MARK}" DB_NAME=openvpms DB_PORT=3306 \
      OPENVPMS_DB_HOST=127.0.0.1 OPENVPMS_DB_ROOT_PASSWORD=x "$@" bash -euo pipefail -c '
    tables=$(mysql -N -B -e "SELECT COUNT(*) FROM information_schema.tables" 2>/dev/null || echo 0)
    [ "${tables}" -eq 0 ] && rm -f "${MARK}"/*
    step() { local name="$1" desc="$2"; shift 2; if [ -f "${MARK}/${name}" ]; then return 0; fi; echo "[openvpms] ${desc}..."; "$@"; touch "${MARK}/${name}"; }
    step schema "Creando esquema" ./toolbox database --create --host=% -u root -p "${OPENVPMS_DB_ROOT_PASSWORD}"
    step data "Cargando datos base" ./dataload.sh setup
  ' ) >"${SIM}/salida" 2>&1
}
nuevo 3b
viejo INTERRUMPIR=schema; rc=$?
chk "arranque 1 (antiguo): muere a mitad de schema" '[ ${rc} -eq 137 ]'
fallos_viejo=0
for i in 1 2 3; do viejo; rc=$?; [ ${rc} -eq 1 ] && fallos_viejo=$((fallos_viejo + 1)); done
chk "arranques 2-4 (antiguo): fallan los tres con 'tables already present' (bucle de reinicios)" \
    '[ ${fallos_viejo} -eq 3 ] && grep -q "tables already present" "${SIM}/salida"'

# =====================================================================================================================
echo "== 4. Muerte a mitad de 'data': continúa desde ahí =="
nuevo 4
correr e INTERRUMPIR=data; rc=$?
chk "el primer arranque muere (137) con schema hecho y data a medias" \
    '[ ${rc} -eq 137 ] && [ "$(marcas)" = "data.started schema " ]'
correr e; rc=$?
chk "el segundo arranque termina con 0"                '[ ${rc} -eq 0 ]'
chk "NO repitió schema (1 sola vez) ni borró la base"  '[ "$(cuenta schema)" = 1 ] && [ "$(cuenta drop-base)" = 0 ]'
chk "repitió data entera (2 intentos) y siguió con adminpass y templates" \
    '[ "$(cuenta data)" = 2 ] && [ "$(cuenta adminpass)" = 1 ] && [ "$(cuenta templates)" = 1 ]'
chk "marcas finales completas"                         '[ "$(marcas)" = "adminpass data schema templates " ]'

# =====================================================================================================================
echo "== 5. Casos límite =="
# 5a. Tablas presentes y NINGUNA marca (estado heredado / volumen de estado perdido): no se borra nada.
nuevo 5a; echo 49 > "${SIM}/tablas"
correr e; rc=$?
chk "5a: con tablas y sin marcas aborta (código 1) y NO borra la base" '[ ${rc} -eq 1 ] && [ "$(cuenta drop-base)" = 0 ] && [ "$(cat "${SIM}/tablas")" = 49 ]'
chk "5a: el mensaje explica qué hacer"                  'grep -q "no borro nada" "${SIM}/salida" && grep -q "OPENVPMS_REINICIALIZAR_BASE" "${SIM}/salida"'
correr e OPENVPMS_REINICIALIZAR_BASE=yes; rc=$?
chk "5a: con OPENVPMS_REINICIALIZAR_BASE=yes (decisión del operador) se recupera" '[ ${rc} -eq 0 ] && [ "$(cuenta drop-base)" = 1 ]'

# 5b. Tablas + schema.started pero YA hay una etapa posterior hecha: contradicción, no se borra.
nuevo 5b; echo 49 > "${SIM}/tablas"; touch "${MARK}/schema.started" "${MARK}/data"
correr e; rc=$?
chk "5b: estado contradictorio (data hecha sin schema) aborta sin borrar" '[ ${rc} -eq 1 ] && [ "$(cuenta drop-base)" = 0 ]'

# 5c. MySQL no responde al contar tablas: NO se toma por base vacía (la lógica anterior hacía `|| echo 0`).
nuevo 5c; echo 49 > "${SIM}/tablas"; touch "${MARK}/schema" "${MARK}/data"; touch "${SIM}/mysql_caido"
correr e; rc=$?
chk "5c: MySQL caído -> aborta (código 1) y CONSERVA las marcas" '[ ${rc} -eq 1 ] && [ "$(marcas)" = "data schema " ]'
chk "5c: no ejecutó ninguna etapa"                      '[ ! -s "${SIM}/log" ]'

# 5d. Base vacía pero marcas viejas (base recreada, volumen de estado conservado): se descartan y se empieza de cero.
nuevo 5d; touch "${MARK}/schema" "${MARK}/data" "${MARK}/adminpass" "${MARK}/templates"
correr e; rc=$?
chk "5d: 0 tablas con marcas viejas -> repite todo"     '[ ${rc} -eq 0 ] && [ "$(tr "\n" " " < "${SIM}/log")" = "schema data adminpass templates " ]'

# 5e. Una etapa FALLA con código de salida (sin morir) y el shell NO tiene `set -e`: no se marca como hecha.
nuevo 5e
correr sin_e FALLAR=adminpass; rc=$?
chk "5e: adminpass falla -> la inicialización devuelve error, sin depender de set -e" '[ ${rc} -ne 0 ]'
chk "5e: adminpass queda como .started, NO como hecha"    '[ -f "${MARK}/adminpass.started" ] && [ ! -f "${MARK}/adminpass" ] && [ ! -f "${MARK}/templates" ]'
correr e; rc=$?
chk "5e: el siguiente arranque repite solo adminpass y termina" '[ ${rc} -eq 0 ] && [ "$(cuenta schema)" = 1 ] && [ "$(cuenta adminpass)" = 2 ]'

# =====================================================================================================================
echo
if [ "${FALLOS}" -eq 0 ]; then echo "RESULTADO: TODO PASA"; exit 0; fi
echo "RESULTADO: ${FALLOS} comprobación(es) FALLARON"; exit 1
