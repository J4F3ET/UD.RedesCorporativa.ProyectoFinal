#!/usr/bin/env bash
# Prueba SIN Docker ni base de datos del bloque `erpnext-create-site` del docker-compose.yml de la raiz (H16: idempotencia real).
# Extrae el script embebido del YAML (desescapando $$ -> $, como hace compose) y lo ejecuta contra un `bench` simulado.
# Pareja de ../openvpms/test-reanudable.sh. Requiere bash, python3 con PyYAML.
# Uso: bash servicios/erpnext/test-create-site.sh
# NO prueba: el formato real de `bench list-apps`, ni un arranque real de ERPNext.
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
python3 - "$DIR/../../docker-compose.yml" "$TMP/h16-script.sh" <<'PY' || { echo "no se pudo extraer el script del YAML" >&2; exit 2; }
import sys, yaml
d = yaml.safe_load(open(sys.argv[1]))
s = d["services"]["erpnext-create-site"]["command"][0]
open(sys.argv[2], "w", newline="\n").write(s.replace("$$", "$"))
PY
bash -n "$TMP/h16-script.sh" || { echo "el script embebido no pasa bash -n" >&2; exit 2; }
set -- "$TMP"
# Prueba sin Docker del bloque erpnext-create-site: `bench` simulado.
SP="$1"; SCRIPT="$SP/h16-script.sh"; fails=0
run() { # run <etiqueta> ; entorno: BENCH_NEWSITE=ok|die|fail BENCH_APPS=... BENCH_LIST=ok|fail
  W=$(mktemp -d); mkdir -p "$W/bin" "$W/sites"; cd "$W"
  cat > bin/bench <<'B'
#!/usr/bin/env bash
echo "bench $*" >> "$PWD/calls.log"
case "$1" in
 new-site) mkdir -p "sites/$2"; echo '{}' > "sites/$2/site_config.json"
   case "$BENCH_NEWSITE" in die) kill -KILL $PPID; exit 137;; fail) exit 1;; esac ;;
 --site) case "$3" in
   list-apps) [ "$BENCH_LIST" = fail ] && { echo "db down" >&2; exit 1; }; printf '%s\n' $BENCH_APPS ;;
   enable-scheduler) : ;; esac ;;
 use) : ;;
 drop-site) echo "DROP" >> "$PWD/calls.log" ;;
esac
B
  chmod +x bin/bench; PATH="$W/bin:$PATH"
  [ -n "$PRE" ] && eval "$PRE"
  SITE=t.local DB_ROOT_PASSWORD=x ADMIN_PASSWORD=y bash "$SCRIPT" >out.log 2>&1; RC=$?
  LAST_W="$W"
}
chk() { if eval "$2"; then echo "PASS  $1"; else echo "FAIL  $1"; fails=$((fails+1)); cat "$LAST_W/out.log" "$LAST_W/calls.log" 2>/dev/null|sed 's/^/      /'; fi; }
M='sites/t.local/.reservaviva-sitio-completo'
BENCH_NEWSITE=ok PRE= run; cd "$LAST_W"
chk "1 sitio nuevo: new-site, marca, scheduler, rc0" '[ $RC -eq 0 ] && [ -f $M ] && grep -q "new-site" calls.log && grep -q enable-scheduler calls.log'
PRE='mkdir -p sites/t.local; echo {} > sites/t.local/site_config.json; touch sites/t.local/.reservaviva-sitio-completo' run; cd "$LAST_W"
chk "2 con marca: no crea, no consulta, scheduler, rc0" '[ $RC -eq 0 ] && ! grep -q new-site calls.log && ! grep -q list-apps calls.log && grep -q enable-scheduler calls.log'
BENCH_NEWSITE=die PRE= run; cd "$LAST_W"
chk "3a new-site muere a mitad: sin marca ni scheduler" '[ ! -f $M ] && [ -f sites/t.local/site_config.json ] && ! grep -q enable-scheduler calls.log'
# segunda ejecucion sobre el estado dejado por la muerte (el caso que rompia antes): sin apps
cp -r "$LAST_W" "$LAST_W.bak"; cd "$LAST_W"; unset BENCH_NEWSITE
W2="$LAST_W"; BENCH_APPS="frappe" bash -c 'PATH="$0/bin:$PATH"; SITE=t.local bash '"$SCRIPT"' >out2.log 2>&1; echo $? > rc2' "$W2"
chk "3b reejecucion tras la muerte: ABORTA, no marca, no scheduler, no drop" '[ "$(cat rc2)" != 0 ] && [ ! -f $M ] && ! grep -q enable-scheduler calls.log && ! grep -q DROP calls.log && grep -q "A MEDIAS" out2.log'
BENCH_APPS="frappe erpnext" bash -c 'PATH="$0/bin:$PATH"; SITE=t.local bash '"$SCRIPT"' >out3.log 2>&1; echo $? > rc3' "$W2"
chk "3c falta hrms: aborta" '[ "$(cat rc3)" != 0 ] && [ ! -f $M ] && grep -q "A MEDIAS" out3.log'
BENCH_LIST=fail bash -c 'PATH="$0/bin:$PATH"; SITE=t.local bash '"$SCRIPT"' >out4.log 2>&1; echo $? > rc4' "$W2"
chk "3d list-apps falla: aborta con mensaje DISTINTO (no 'a medias'), sin marca" '[ "$(cat rc4)" != 0 ] && [ ! -f $M ] && grep -q "no se pudo comprobar" out4.log && ! grep -q "A MEDIAS" out4.log'
BENCH_APPS="frappe erpnext hrms" bash -c 'PATH="$0/bin:$PATH"; SITE=t.local bash '"$SCRIPT"' >out5.log 2>&1; echo $? > rc5' "$W2"
chk "4 volumen anterior completo sin marca: se adopta (marca, use, scheduler)" '[ "$(cat rc5)" = 0 ] && [ -f $M ] && grep -q "bench use" calls.log && grep -q enable-scheduler calls.log && ! grep -q DROP calls.log'
BENCH_NEWSITE=fail PRE= run; cd "$LAST_W"
chk "5 new-site falla (rc!=0): sin marca, rc1, sin scheduler" '[ $RC -eq 1 ] && [ ! -f $M ] && ! grep -q enable-scheduler calls.log'
echo; [ $fails -eq 0 ] && echo "RESULTADO: TODO PASA" || echo "RESULTADO: $fails FALLOS"
[ $fails -eq 0 ]
