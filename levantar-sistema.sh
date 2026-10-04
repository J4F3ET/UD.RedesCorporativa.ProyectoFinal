#!/usr/bin/env bash
# levantar-sistema.sh - Levanta la arquitectura completa de Reserva Viva (26 servicios) en UN solo host.
#
#   git clone <repo> && cd <repo> && ./levantar-sistema.sh
#
# En Windows se usa levantar-sistema.ps1 (o doble clic en levantar-sistema.cmd), que elige donde ejecutar este script
# (Git Bash si Docker Desktop esta en marcha; si no, una distro de WSL con Docker Engine) y mantiene viva la sesion de WSL.
#
# Acciones:
#   arrancar   (por defecto) prepara todo, levanta los 26 servicios y espera a que esten sanos
#   preparar   solo lo previo: certificados, zonas DNS, validacion del compose e imagen de OpenVPMS
#   estado     estado de cada servicio, IP y puertos en los que esta publicado y direcciones de acceso
#   verificar  ejecuta sistema/verificar_arquitectura.py contra el sistema levantado (respeta la IP en que este)
#   detener    para los contenedores sin borrar nada; "arrancar" los vuelve a levantar en minutos
#   borrar     elimina contenedores Y VOLUMENES (todos los datos del laboratorio). Pide confirmacion
#   borrar-directorio   elimina SOLO el contenedor y los volumenes de samba-ad (samba_data, samba_etc): para volver a
#                        provisionar el dominio sin tocar los datos de OpenVPMS, Pretix, InvenTree ni ERPNext. Pide
#                        confirmacion, salvo con --si
# Opciones:
#   --forzar        no abortar por falta de memoria
#   --timeout MIN   espera maxima a que todo quede sano tras el arranque (por defecto 45)
#   --rapido        (verificar) omite la prueba de persistencia de LDAP (down + up -d); ese caso queda como no verificado
#   --si            (borrar, borrar-directorio) no pedir confirmacion
#   --ip X.X.X.X    (arrancar/preparar) la IP del equipo en la que se publica todo (HOST_IP). Sin esta opcion se usa la de
#                   la variable de entorno HOST_IP o, si no, la de sistema/test.env (192.168.1.26, la del switch del
#                   laboratorio). El sistema siempre se publica en UNA IP, con un puerto por servicio: proxy web, las
#                   cuatro aplicaciones, LDAP/LDAPS, DNS y NTP. Las aplicaciones tambien en 127.0.0.1 (localhost)
#   --intranet      (arrancar/preparar) autodetecta la IP de la LAN de este equipo y la usa como HOST_IP: sirve para arrancar
#                   en un equipo que no tiene la IP de test.env. --ip tiene prioridad. El DNS va al 53, salvo con Docker
#                   Engine en WSL: ahi va al 1053 y levantar-sistema.ps1 deja un reenviador de Windows en el 53.
#                   Requisitos de la LAN: docs/operacion.md, "Acceso desde la LAN"
#
# Es idempotente: se puede ejecutar las veces que haga falta. Si un arranque se interrumpe, volver a ejecutarlo
# retoma donde quedo (la inicializacion de OpenVPMS y la creacion del sitio de ERPNext son reanudables).
#
# Usa el docker-compose.yml de la raiz (unico; servicios agrupados por departamento, todos en una red bridge de Docker)
# y los ficheros de cada servicio en servicios/. Todo "docker compose" se ejecuta desde la
# raiz con --env-file sistema/test.env (contrasenas de laboratorio, desechables).
#
# Solo ASCII a proposito: la salida se ve igual en cualquier consola de Windows.

set -euo pipefail

RAIZ="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ARNES="${RAIZ}/sistema"               # test.env, verificar_arquitectura.py y sus informes
ENV_FILE="sistema/test.env"           # relativo a RAIZ: dc() se ejecuta siempre desde la raiz
PROYECTO="reservaviva-smoke"          # "name:" de docker-compose.yml
MARCA_SESION="reservaviva-keepalive"  # proceso que levantar-sistema.ps1 deja vivo en WSL

# Umbral de memoria para la VM de Docker. El consumo medido de los contenedores esta en docs/resultados-un-host.md.
MIN_VM_GIB=6

ACCION="arrancar"
FORZAR=false
TIMEOUT_MIN=45
RAPIDO=false
SI=false
INTRANET=false
IP_PEDIDA=""

uso() { sed -n '2,31p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'; }

es_ipv4() { [[ "$1" =~ ^([0-9]{1,3})\.([0-9]{1,3})\.([0-9]{1,3})\.([0-9]{1,3})$ ]] && \
            [ "${BASH_REMATCH[1]}" -le 255 ] && [ "${BASH_REMATCH[2]}" -le 255 ] && \
            [ "${BASH_REMATCH[3]}" -le 255 ] && [ "${BASH_REMATCH[4]}" -le 255 ]; }

while [ $# -gt 0 ]; do
  case "$1" in
    arrancar|preparar|estado|verificar|detener|borrar|borrar-directorio) ACCION="$1" ;;
    ayuda|-h|--help) uso; exit 0 ;;
    --forzar) FORZAR=true ;;
    --rapido) RAPIDO=true ;;
    --si) SI=true ;;
    --intranet) INTRANET=true ;;
    --ip)
      [ $# -ge 2 ] && es_ipv4 "$2" || { echo "--ip necesita una direccion IPv4 (p. ej. --ip 192.168.1.13)" >&2; exit 2; }
      IP_PEDIDA="$2"; shift ;;
    --timeout)
      [ $# -ge 2 ] && [[ "$2" =~ ^[0-9]+$ ]] || { echo "--timeout necesita un numero de minutos" >&2; exit 2; }
      TIMEOUT_MIN="$2"; shift ;;
    *) echo "Argumento desconocido: $1" >&2; uso >&2; exit 2 ;;
  esac
  shift
done
if { [ -n "${IP_PEDIDA}" ] || ${INTRANET}; } && [ "${ACCION}" != "arrancar" ] && [ "${ACCION}" != "preparar" ]; then
  echo "--ip y --intranet solo se usan con arrancar o preparar; ${ACCION} usa la IP en la que esta publicado el sistema." >&2
  exit 2
fi

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

# Valor que usara compose para una variable: la del entorno si esta exportada (este script exporta HOST_IP y DNS_PORT para
# esta ejecucion; en compose el entorno manda sobre --env-file) y si no, la de test.env.
valor_efectivo() {
  local v="${!1:-}"
  [ -n "${v}" ] && printf '%s' "${v}" || valor_env "$1" "$2"
}

# --- Publicacion: UNA IP (HOST_IP) y un puerto por servicio ---------------------------------------------------------
#
# Todo se publica en HOST_IP: proxy web, las cuatro aplicaciones (ademas en 127.0.0.1), LDAP/LDAPS, DNS y NTP. HOST_IP se
# resuelve, de menor a mayor prioridad: sistema/test.env, la variable de entorno HOST_IP, --ip X; con --intranet y sin --ip
# se usa la IP de la LAN que detecte este script. Se exporta para esta ejecucion (en compose el entorno manda sobre
# --env-file), sin tocar test.env en disco. Las demas acciones (estado, verificar, detener...) usan la IP en la que ya esta
# publicado el sistema, para que un "up -d" de la verificacion no recree contenedores en otra IP.
#
# Puerto del DNS: 53, salvo con Docker Engine dentro de WSL, donde es PUERTO_DNS_WSL (1053). Con WSL en
# networkingMode=mirrored, Windows NO entrega a Linux el trafico que llega a su puerto 53 (medido el 27/09/2026: un
# servidor en WSL recibe en el 54 y en el 1053, pero en el 53 Windows responde "puerto inalcanzable" por UDP y rechaza la
# conexion TCP). Por eso dns-interno se publica en <IP>:1053 y levantar-sistema.ps1 arranca en Windows
# sistema/reenviador-dns.ps1, que escucha en <IP>:53 (UDP y TCP) y reenvia cada consulta a <IP>:1053. Los clientes de la
# LAN siguen usando el 53. Con Docker Desktop (publica desde Windows) o con Linux nativo el DNS va directo al 53.

HOST_IP=""
PUERTO_DNS_WSL=1053        # puerto de dns-interno con Docker Engine en WSL (ver arriba)

# Todo lo que se publica en el host: contenedor|puerto interno/proto|variable del puerto|valor por defecto|etiqueta|tambien en 127.0.0.1
PUBLICACIONES=(
  "openvpms-app|8080/tcp|OPENVPMS_PORT|8080|OpenVPMS|si"
  "erpnext-hr|8080/tcp|ERPNEXT_PORT|8080|ERPNext|si"
  "pretix-web|80/tcp|PRETIX_PORT|80|Pretix|si"
  "inventree-app|8000/tcp|INVENTREE_PORT|8000|InvenTree|si"
  "samba-ad|389/tcp|LDAP_PORT|389|LDAP|no"
  "samba-ad|636/tcp|LDAPS_PORT|636|LDAPS|no"
  "proxy-web|80/tcp|HTTP_PORT|80|proxy web|no"
  "dns-interno|53/udp|DNS_PORT|53|DNS|no"
  "dns-interno|53/tcp|DNS_PORT|53|DNS|no"
  "ntp-interno|123/udp|NTP_PORT|123|NTP|no"
)

# true si el DNS necesita el reenviador de Windows: Docker Engine dentro de WSL.
dns_por_reenviador() { en_wsl && [ "$(sistema_docker)" != "Docker Desktop" ]; }

# Lineas "IP|puerto" publicadas por un contenedor para un puerto interno (una por enlace), o nada si no existe o no publica.
publicacion_de() {
  docker inspect --format "{{range \$p, \$b := .HostConfig.PortBindings}}{{if eq \$p \"$2\"}}{{range \$b}}{{.HostIp}}|{{.HostPort}}{{\"\\n\"}}{{end}}{{end}}{{end}}" "$1" 2>/dev/null | grep . || true
}

# Puerto de host que un contenedor publica en una IP concreta para un puerto interno (vacio si ninguno).
publicado_en() { publicacion_de "$1" "$2" | awk -F'|' -v ip="$3" '$1 == ip { print $2; exit }'; }

# IP de la LAN por defecto. En Windows (Git Bash o WSL) se pregunta a Windows por la ruta por defecto: en WSL con red NAT
# la IP de la distro (172.x) no es la que ven los otros equipos. Fuera de Windows, la IP de origen de la ruta por defecto.
detectar_ip_lan() {
  local ip=""
  if command -v powershell.exe >/dev/null 2>&1; then
    ip="$(powershell.exe -NoProfile -NonInteractive -Command - 2>/dev/null <<'PS' | tr -d '\r' | grep -E '^[0-9.]+$' | head -n 1
$r = Get-NetRoute -AddressFamily IPv4 -DestinationPrefix '0.0.0.0/0' -ErrorAction SilentlyContinue | ForEach-Object { $i = Get-NetIPInterface -AddressFamily IPv4 -InterfaceIndex $_.ifIndex -ErrorAction SilentlyContinue; [pscustomobject]@{ Idx = $_.ifIndex; M = $_.RouteMetric + $i.InterfaceMetric } } | Sort-Object M | Select-Object -First 1
if ($r) { (Get-NetIPAddress -AddressFamily IPv4 -InterfaceIndex $r.Idx -ErrorAction SilentlyContinue | Where-Object { $_.IPAddress -notlike '169.254.*' } | Select-Object -First 1).IPAddress }
PS
)" || true
  fi
  if [ -z "${ip}" ] && command -v ip >/dev/null 2>&1; then
    ip="$(ip -4 route get 1.1.1.1 2>/dev/null | awk '{for (i = 1; i < NF; i++) if ($i == "src") { print $(i + 1); exit }}')"
  fi
  printf '%s' "${ip}"
}

# Fija HOST_IP y DNS_PORT para esta ejecucion y los exporta (tambien para sistema/verificar_arquitectura.py).
resolver_host_ip() {
  local ip="" origen="" p
  if [ "${ACCION}" != "arrancar" ] && [ "${ACCION}" != "preparar" ]; then
    # Con el sistema en marcha, la IP real es la que publica proxy-web; el puerto del DNS y el del proxy, los suyos.
    p="$(publicacion_de proxy-web 80/tcp | head -n 1)"
    if [ -n "${p}" ]; then
      ip="${p%%|*}"; origen="la que publica proxy-web"
      export HTTP_PORT="${p##*|}"
      p="$(publicacion_de dns-interno 53/udp | head -n 1)"
      [ -z "${p}" ] || export DNS_PORT="${p##*|}"
    fi
  fi
  if [ -z "${ip}" ]; then
    if [ -n "${IP_PEDIDA}" ]; then ip="${IP_PEDIDA}"; origen="--ip"
    elif ${INTRANET}; then
      ip="$(detectar_ip_lan)"; origen="la IP de la LAN detectada (--intranet)"
      es_ipv4 "${ip}" || fallo "No se pudo detectar la IP de la LAN de este equipo. Indicala a mano: --ip X.X.X.X (en PowerShell: -IP X.X.X.X). Es la IPv4 del adaptador Wi-Fi o Ethernet (ipconfig en Windows)."
    elif [ -n "${HOST_IP:-}" ]; then ip="${HOST_IP}"; origen="la variable de entorno HOST_IP"
    else ip="$(valor_env HOST_IP "")"; origen="${ENV_FILE}"
    fi
  fi
  [ -n "${ip}" ] || fallo "No hay HOST_IP: definela en ${ENV_FILE} (la IP del equipo en el switch del laboratorio) o pasa --ip X.X.X.X."
  es_ipv4 "${ip}" || fallo "HOST_IP no es una direccion IPv4 valida (${ip}, de ${origen})."
  case "${ip}" in
    127.*|0.0.0.0) fallo "HOST_IP ${ip} (de ${origen}) no sirve: otros equipos no pueden llegar a ella. Usa la IP del equipo en la LAN (ipconfig en Windows, ip addr en Linux): --ip X.X.X.X, o --intranet para autodetectarla." ;;
  esac
  HOST_IP="${ip}"
  export HOST_IP
  if [ "${ACCION}" = "arrancar" ] || [ "${ACCION}" = "preparar" ]; then
    if dns_por_reenviador; then export DNS_PORT="${PUERTO_DNS_WSL}"; else export DNS_PORT=53; fi
  fi
  info "HOST_IP=${HOST_IP} (${origen}); DNS en el puerto $(valor_efectivo DNS_PORT 53)"
}

# true si ya hay escuchas ajenas en <proto> <ip>:<puerto> (en esa IP o en todas); imprime hasta tres.
escuchan_en() {
  local flag="-ltn"; [ "$1" = "udp" ] && flag="-lun"
  ss -H "${flag}" "( sport = :$3 )" 2>/dev/null | awk -v ip="$2" '$4 ~ "^(" ip "|0\\.0\\.0\\.0|\\*|\\[::\\]):"' | head -n 3
}

# Comprobaciones previas, ANTES de tocar ningun contenedor: el sistema siempre se publica en HOST_IP. Cada fallo dice que hacer.
comprobar_publicacion() {
  paso "Comprobando la publicacion en ${HOST_IP}"
  local so; so="$(sistema_docker)"
  # (a) Que la IP este en este sistema. Con Docker Desktop, Desktop publica en Windows y no hace falta.
  if [ "${so}" != "Docker Desktop" ]; then
    if en_wsl; then
      local red; red="$(wslinfo --networking-mode 2>/dev/null || echo desconocido)"
      info "Red de WSL: ${red}"
      if [ "${red}" != "mirrored" ]; then
        fallo "WSL esta en modo de red '${red}', no 'mirrored'. En ese modo la distro no tiene la IP ${HOST_IP}: Docker no puede publicar en ella y otros equipos de la LAN no llegarian a los contenedores.
       Que hacer: ejecutar UNA vez, en PowerShell como administrador, sistema\\habilitar-intranet-windows.ps1 (activa
       networkingMode=mirrored en .wslconfig y abre el cortafuegos para los puertos del sistema), despues 'wsl --shutdown'
       (para los contenedores) y volver a lanzar: .\\levantar-sistema.ps1 -Forzar
       Pasos completos: docs/operacion.md, 'Acceso desde la LAN'. Nada se ha cambiado."
      fi
    fi
    if ! ip -4 -o addr show 2>/dev/null | grep -q " ${HOST_IP}/"; then
      fallo "La IP ${HOST_IP} no esta en ninguna interfaz de este sistema ($(ip -4 -o addr show 2>/dev/null | awk '{print $4}' | tr '\n' ' ')).
       Este equipo no tiene la IP de ${ENV_FILE}. Pasa la suya con --ip X.X.X.X (PowerShell: -IP X.X.X.X), o --intranet para
       que la detecte (ipconfig en Windows, ip addr en Linux). Nada se ha cambiado."
    fi
  fi
  # (b) Que los puertos esten libres en HOST_IP (y en 127.0.0.1 las aplicaciones) o ya sean nuestros, de una ejecucion
  # anterior. En WSL el del DNS es el 1053: el 53 de Windows es del reenviador y lo comprueba levantar-sistema.ps1.
  local ocupado="" fila cont pint var def etiq loop puerto proto l ip
  if command -v ss >/dev/null 2>&1; then
    for fila in "${PUBLICACIONES[@]}"; do
      IFS='|' read -r cont pint var def etiq loop <<<"${fila}"
      puerto="$(valor_efectivo "${var}" "${def}")"; proto="${pint#*/}"
      for ip in "${HOST_IP}" 127.0.0.1; do
        [ "${ip}" = "127.0.0.1" ] && [ "${loop}" != "si" ] && continue
        [ "$(publicado_en "${cont}" "${pint}" "${ip}")" = "${puerto}" ] && continue
        l="$(escuchan_en "${proto}" "${ip}" "${puerto}")"
        [ -n "${l}" ] && ocupado+=$'\n'"       ${ip}:${puerto}/${proto} (${etiq}): ${l//$'\n'/ ; }"
      done
    done
  fi
  if [ -n "${ocupado}" ]; then
    fallo "Hay puertos ocupados por otros programas de este sistema:${ocupado}
       Para 53: suele ser systemd-resolved (DNSStubListener) o dnsmasq; para 80: otro servidor web. Liberalos o cambia el
       puerto con su variable (p. ej. HTTP_PORT=8088 ./levantar-sistema.sh; los clientes entraran entonces con
       http://<nombre>:<puerto>). Nada se ha cambiado."
  fi
  info "IP presente en el sistema y los puertos del sistema libres en ella (vistos desde aqui)."
  if [ "$(valor_efectivo DNS_PORT 53)" != "53" ]; then
    info "DNS en ${HOST_IP}:$(valor_efectivo DNS_PORT 53): con WSL mirrored, Windows no entrega su puerto 53 a Linux. El 53 lo atiende"
    info "el reenviador de Windows (sistema/reenviador-dns.ps1), que arranca levantar-sistema.ps1."
  fi
}

# Version anterior del sistema: cinco redes bridge reservaviva-smoke_vlan10_medica/20/30/40/99. La red unica usa la misma
# subred que vlan99_infra y Docker rechazaria crearla. Se para el sistema SIN borrar volumenes (nunca "down -v": en ellos
# estan el dominio de Samba y el sitio de ERPNext, ~30 min de reinicializacion) y se eliminan esas redes.
migrar_redes_vlan() {
  local viejas v
  viejas="$(docker network ls --format '{{.Name}}' | grep -E "^${PROYECTO}_vlan" || true)"
  [ -n "${viejas}" ] || return 0
  paso "Migracion: el sistema tiene las redes de la version con VLAN ($(printf '%s' "${viejas}" | tr '\n' ' '))"
  aviso "Se paran y recrean los contenedores del sistema y se eliminan esas redes. Los volumenes (datos) NO se tocan."
  dc down --remove-orphans || fallo "No se pudo parar el sistema para migrar las redes."
  for v in ${viejas}; do
    if docker network rm "${v}" >/dev/null 2>&1; then
      info "Red ${v} eliminada."
    else
      fallo "No se pudo eliminar la red ${v} (en uso por: $(docker network inspect "${v}" --format '{{range .Containers}}{{.Name}} {{end}}' 2>/dev/null)). Paralos y repite."
    fi
  done
}

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
    local msg="Docker solo dispone de ${total_gib} GiB y los 26 servicios necesitan ~5 GiB mas margen. Sube la memoria asignada (Docker Desktop: Settings > Resources; WSL: memory= en %UserProfile%\\.wslconfig)."
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
  paso "Certificados LDAPS (CA interna + Samba AD)"
  # Idempotente: si existen, son validos y cubren las direcciones (HOST_IP incluida), no toca nada. No instala la CA en el host.
  HOST_IP="${HOST_IP}" bash "${RAIZ}/servicios/ca/generar-certificados.sh" --sin-instalar-ca | sed 's/^/    /'
  # Si falta un fichero de un bind mount, Docker crea un DIRECTORIO vacio en su lugar y LDAPS falla sin avisar.
  local f
  for f in ca.crt ldap.crt ldap.key; do
    if [ ! -f "${RAIZ}/servicios/ca/certs/${f}" ] || [ ! -s "${RAIZ}/servicios/ca/certs/${f}" ]; then
      fallo "Falta servicios/ca/certs/${f} (o esta vacio): samba-ad, inventree-app y erpnext-backend lo montan. Revisa la salida de servicios/ca/generar-certificados.sh."
    fi
  done
}

# Escribe ${2} desde ${2}.tmp solo si cambio algo mas que el serial (o no existia). Imprime "Generada" o "Sin cambios".
# Conservar el fichero anterior hace que su fecha diga cuando cambio de verdad, y que reiniciar_dns_si_zona_nueva solo
# reinicie bind9 cuando hace falta.
reemplazar_si_cambia() {
  local out="$1"
  if grep -q '\${[A-Z0-9_]*}' "${out}.tmp"; then
    rm -f "${out}.tmp"; fallo "Quedan marcadores sin sustituir al generar $(basename "${out}")."
  fi
  if [ -f "${out}" ] && diff -q <(grep -v '; serial$' "${out}") <(grep -v '; serial$' "${out}.tmp") >/dev/null; then
    rm -f "${out}.tmp"; printf 'Sin cambios'
  else
    mv -f "${out}.tmp" "${out}"; printf 'Generada  '
  fi
}

# La zona reservaviva.lan (una sola, servicios/bind9/named.conf) y la ACL de los contenedores con recursion.
generar_zona() {
  paso "Zona DNS reservaviva.lan (todos los nombres -> ${HOST_IP})"
  local dir="${RAIZ}/servicios/bind9/zones"
  local tpl="${dir}/db.reservaviva.lan.tpl" out="${dir}/db.reservaviva.lan"
  local acl="${dir}/acl-interna.conf"
  [ -f "${tpl}" ] || fallo "Falta la plantilla ${tpl}"
  # dns, ldap, ntp y las cuatro aplicaciones apuntan a HOST_IP; solo el glue de la delegacion ad.reservaviva.lan lleva la IP
  # fija de samba-ad en la red del sistema (la misma que le da el compose: NET_INTERNA .10).
  local red ip_dc serial r
  red="$(valor_efectivo NET_INTERNA 10.10.99)"
  ip_dc="${red}.10"
  serial="$(date +%Y%m%d%H)"
  tr -d '\r' <"${tpl}" | sed -e "s/\${IP_ANFITRION}/${HOST_IP}/g" -e "s/\${IP_DC}/${ip_dc}/g" \
                             -e "s/\${SERIAL}/${serial}/g" >"${out}.tmp"
  r="$(reemplazar_si_cambia "${out}")"
  info "${r} zona: dns, ldap, ntp, openvpms, pretix, inventree y rrhh -> ${HOST_IP}; dc1.ad -> ${ip_dc} (delegacion de ad.reservaviva.lan)"
  # ACL de los contenedores: la subred de la red del sistema sin su gateway .1 (por el .1 llega el anfitrion, ver named.conf).
  { printf '// GENERADO por levantar-sistema.sh (generar_zona) desde NET_INTERNA del compose: no editar.\n'
    printf '// Contenedores del sistema (con recursion): la subred de la red reservaviva, sin el gateway .1 del bridge.\n'
    printf 'acl "red-interna" { !%s.1; %s.0/24; };\n' "${red}" "${red}"; } >"${acl}.tmp"
  r="$(reemplazar_si_cambia "${acl}")"
  info "${r} ACL de recursion: ${red}.0/24 (sin el ${red}.1)"
}

# bind9 lee su configuracion y las zonas al arrancar y no vigila los ficheros. Si alguno (named.conf, la zona o la ACL) es
# mas nuevo que el arranque de dns-interno (p. ej. tras cambiar una plantilla o HOST_IP), se reinicia solo ese contenedor:
# unos segundos, sin tocar datos.
reiniciar_dns_si_zona_nueva() {
  local d="${RAIZ}/servicios/bind9" inicio t_dns t f
  inicio="$(docker inspect --format '{{.State.StartedAt}}' dns-interno 2>/dev/null)" || return 0
  t_dns="$(date -d "${inicio}" +%s 2>/dev/null)" || return 0
  for f in "${d}/named.conf" "${d}/zones/db.reservaviva.lan" "${d}/zones/acl-interna.conf"; do
    t="$(stat -c %Y "${f}" 2>/dev/null)" || continue
    if [ "${t}" -gt "${t_dns}" ]; then
      paso "La configuracion DNS cambio despues de arrancar dns-interno ($(basename "${f}")): se reinicia para que bind9 la lea"
      dc restart dns
      return 0
    fi
  done
}

# samba-ad SI copia su certificado en cada arranque del contenedor (servicios/samba-ad/entrypoint.sh: el paso que
# copia ca.crt/ldap.crt/ldap.key a /var/lib/samba/private/tls con chmod 600 no esta dentro del "if no existe sam.ldb",
# se repite siempre), a diferencia de OpenLDAP/osixia, que solo lo copiaba en el PRIMER arranque del contenedor y
# necesitaba recrearlo entero. Por eso aqui basta con REINICIAR samba-ad (no hace falta --force-recreate) cuando
# generar-certificados.sh lo acaba de regenerar (el certificado es mas nuevo que el ultimo arranque del contenedor);
# los datos del volumen samba_data se conservan y no se reprovisiona el dominio.
# Se compara contra StartedAt (no Created, que no cambia con un restart) para no reiniciar en cada "arrancar" una vez
# que ya se recogio el certificado nuevo, igual que reiniciar_dns_si_zona_nueva mas arriba.
# Despues se reinician los dos clientes LDAPS (inventree-app y erpnext-backend) y, tras erpnext-backend, erpnext-hr
# (su nginx resuelve la IP del backend solo al arrancar): el mismo problema medido con OpenLDAP el 27/09/2026 (estado
# de TLS/LDAP por proceso; erpnext-backend puede volver con otra IP en erpnext_internal, red sin IP fija) no depende
# de la imagen del directorio. Reiniciar es barato y solo ocurre cuando cambia el certificado.
reiniciar_directorio_si_cert_nuevo() {
  local iniciado t_ldap t_cert c
  iniciado="$(docker inspect --format '{{.State.StartedAt}}' samba-ad 2>/dev/null)" || return 0
  t_ldap="$(date -d "${iniciado}" +%s 2>/dev/null)" || return 0
  t_cert="$(stat -c %Y "${RAIZ}/servicios/ca/certs/ldap.crt" 2>/dev/null)" || return 0
  if [ "${t_cert}" -gt "${t_ldap}" ]; then
    paso "El certificado LDAPS es mas nuevo que el ultimo arranque de samba-ad: se reinicia para que lo recoja (datos conservados)"
    dc restart samba-ad
    for c in inventree-app erpnext-backend erpnext-hr; do
      [ "$(docker inspect --format '{{.State.Running}}' "${c}" 2>/dev/null)" = "true" ] && dc restart "${c}"
    done
  fi
  return 0
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
  validar_compose
  preparar_imagen_openvpms
}

# "up -d" no recrea un contenedor cuya configuracion no cambio: si un arranque anterior lo dejo unhealthy (p. ej.
# pretix-web tras migrar contra una base que aun no aceptaba conexiones), el siguiente "up -d" aborta enseguida con
# "dependency failed to start" y el arranque no se puede retomar. Se reinician esos contenedores (sin tocar datos) para
# que su arranque se repita; "up -d" vuelve a esperar a que queden sanos.
reiniciar_unhealthy() {
  local ids
  ids="$(docker ps -q --filter "label=com.docker.compose.project=${PROYECTO}" --filter health=unhealthy)"
  [ -n "${ids}" ] || return 0
  paso "Reiniciando contenedores que quedaron unhealthy en un arranque anterior"
  # shellcheck disable=SC2086
  docker restart ${ids} | sed 's/^/    /'
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
  info "El primer arranque tarda: la base de OpenVPMS ~8 min y despues la aplicacion ~15; el sitio de ERPNext ~25-30."
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
  local p1 p2 p3 p4 ldap ldaps dns ntp hp suf=""
  p1="$(valor_efectivo OPENVPMS_PORT 8080)"; p2="$(valor_efectivo ERPNEXT_PORT 8080)"
  p3="$(valor_efectivo PRETIX_PORT 80)";     p4="$(valor_efectivo INVENTREE_PORT 8000)"
  ldap="$(valor_efectivo LDAP_PORT 389)"; ldaps="$(valor_efectivo LDAPS_PORT 636)"
  dns="$(valor_efectivo DNS_PORT 53)"; ntp="$(valor_efectivo NTP_PORT 123)"
  hp="$(valor_efectivo HTTP_PORT 80)"; [ "${hp}" = "80" ] || suf=":${hp}"
  cat <<EOF

    Sistema publicado en ${HOST_IP}: una IP y un puerto por servicio (las cuatro aplicaciones tambien en localhost).
      Departamento       Aplicacion  Directo (IP:puerto)                       Por nombre (proxy web)                     Usuario
      Medica             OpenVPMS    http://${HOST_IP}:${p1}/openvpms     http://openvpms.reservaviva.lan${suf}      admin
      Taquilla           Pretix      http://localhost:${p3}  (la IP: ${HOST_IP}:${p3} da 400)  http://pretix.reservaviva.lan${suf}  $(valor_env PRETIX_ADMIN_EMAIL admin@reservaviva.local)
      Logistica          InvenTree   http://${HOST_IP}:${p4}                  http://inventree.reservaviva.lan${suf}     $(valor_env INVENTREE_ADMIN_USER admin)
      RRHH               ERPNext     http://${HOST_IP}:${p2}                  http://rrhh.reservaviva.lan${suf}          Administrator
      Infra              LDAP ${HOST_IP}:${ldap}  LDAPS ${HOST_IP}:${ldaps}  DNS ${HOST_IP}:${dns}  NTP ${HOST_IP}:${ntp}/udp  proxy web ${HOST_IP}:${hp}
    Para entrar por nombre, el cliente debe usar como DNS la IP ${HOST_IP} (puerto 53):
      - a mano en el cliente (Windows: Configuracion > Red > Editar DNS; comprobar con: nslookup pretix.reservaviva.lan ${HOST_IP}), o
      - para toda la LAN, en el DHCP del router (DNS primario ${HOST_IP}). OJO: este DNS solo conoce reservaviva.lan
        (no hace recursion); con el DHCP, los clientes necesitan un DNS secundario para Internet.
    AVISO: las contrasenas de laboratorio estan PUBLICAS en git (sistema/test.env) y todos los servicios son accesibles desde
    la LAN en ${HOST_IP}: no hay aislamiento entre departamentos. Usalo solo en una red de laboratorio.
EOF
  if [ "${dns}" != "53" ]; then
    info "DNS: dns-interno se publica en ${HOST_IP}:${dns}; el puerto 53 lo atiende el reenviador de Windows"
    info "(sistema/reenviador-dns.ps1), que arranca y comprueba levantar-sistema.ps1. Si lanzaste este script"
    info "desde WSL a mano, ejecuta en Windows .\\levantar-sistema.ps1 para tener el 53."
  fi
}

aviso_sesion_wsl() {
  if en_wsl && [ "$(sistema_docker)" != "Docker Desktop" ] && ! pgrep -f "${MARCA_SESION}" >/dev/null 2>&1; then
    aviso "Estas en WSL con Docker Engine: si se cierran TODAS las terminales de WSL, Docker se detiene y se lleva los"
    aviso "contenedores. Deja esta terminal abierta, o arranca desde Windows con levantar-sistema.ps1, que mantiene la sesion."
  fi
}

accion_arrancar() {
  comprobar_requisitos
  paso "IP de publicacion"
  resolver_host_ip
  comprobar_publicacion
  comprobar_memoria
  preparar
  migrar_redes_vlan
  reiniciar_unhealthy
  local n; n="$(dc config --services | grep -c .)"
  paso "Levantando los ${n} servicios en ${HOST_IP} (la primera vez descarga varios GB de imagenes)"
  # --remove-orphans: quien venia de un stack con "openldap" (servicio ya borrado del compose, sustituido por
  # samba-ad) se encuentra ese contenedor huerfano en cada "arrancar", con el aviso de Docker pero sin fallar.
  # Este flag SOLO borra contenedores que ya no estan en el compose actual; nunca toca volumenes (ldap_data y
  # ldap_config de quien venia del stack viejo siguen intactos y hay que borrarlos a mano si ya no hacen falta).
  if ! dc up -d --remove-orphans; then
    diagnostico
    fallo "docker compose up fallo. Volver a ejecutar el script es seguro: retoma donde quedo."
  fi
  reiniciar_dns_si_zona_nueva
  reiniciar_directorio_si_cert_nuevo
  esperar_sano
  crear_admin_pretix
  paso "Sistema en marcha: los ${n} servicios estan sanos"
  accesos
  info ""
  info "Siguiente paso recomendado:  $0 verificar   (puertos, DNS, NTP, LDAP y acceso por nombre)"
  aviso_sesion_wsl
}

accion_preparar() {
  comprobar_requisitos
  paso "IP de publicacion"
  resolver_host_ip
  preparar
  paso "Preparacion completa (zona DNS para ${HOST_IP}). Para levantar el sistema: $0 arrancar"
}

accion_estado() {
  cd "${RAIZ}"
  docker info >/dev/null 2>&1 || fallo "Docker no responde."
  resolver_host_ip
  paso "Estado de los servicios"
  dc ps -a --format 'table {{.Service}}\t{{.State}}\t{{.Status}}'
  paso "Publicacion en el host (HOST_IP ${HOST_IP})"
  local fila cont pint var def etiq loop p
  for fila in "${PUBLICACIONES[@]}"; do
    IFS='|' read -r cont pint var def etiq loop <<<"${fila}"
    p="$(publicacion_de "${cont}" "${pint}" | sed 's/|/:/' | tr '\n' ' ')"
    printf '    %-10s %-14s %-9s %s\n' "${etiq}" "${cont}" "${pint}" "${p:-no publicado (contenedor ausente)}"
  done
  accesos
  aviso_sesion_wsl
}

accion_verificar() {
  # Conserva la IP en que esta publicado el sistema: la prueba de persistencia hace down + up -d, y sin HOST_IP exportada
  # ese up -d recrearia los contenedores en otra IP. El verificador lee HOST_IP del entorno (os.environ["HOST_IP"]).
  resolver_host_ip
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
  resolver_host_ip >/dev/null
  paso "Deteniendo los contenedores (no se borra nada)"
  dc stop
  info "Detenidos. Para volver a levantarlos: $0 arrancar"
}

accion_borrar() {
  cd "${RAIZ}"
  resolver_host_ip >/dev/null
  if ! ${SI}; then
    printf '\nEsto BORRA los contenedores y TODOS los datos (bases de datos, sitio de ERPNext, directorio AD).\n'
    printf 'El siguiente arranque volvera a inicializarlo todo (~40 min). Escribe "borrar" para confirmar: '
    local r; read -r r
    [ "${r}" = "borrar" ] || { echo "Cancelado."; exit 0; }
  fi
  paso "Eliminando contenedores, redes y volumenes"
  dc down -v --remove-orphans
}

# Borra SOLO el contenedor samba-ad y sus dos volumenes (samba_data, samba_etc): para reprovisionar el dominio de AD
# sin tocar los datos de OpenVPMS, Pretix, InvenTree ni ERPNext. NUNCA usar "borrar" (dc down -v) completo para esto:
# se llevaria por delante TODOS los volumenes del laboratorio (docs del plan de migracion, "trampas").
# Los nombres de volumen que crea Compose son "<name: de docker-compose.yml>_<clave del volumen>"; PROYECTO ya
# guarda ese "name:" (reservaviva-smoke).
accion_borrar_directorio() {
  cd "${RAIZ}"
  resolver_host_ip >/dev/null
  local v1="${PROYECTO}_samba_data" v2="${PROYECTO}_samba_etc"
  if ! ${SI}; then
    printf '\nEsto borra el contenedor samba-ad y SUS volumenes (%s, %s): el dominio de AD se reprovisiona desde cero\n' "${v1}" "${v2}"
    printf 'en el siguiente arranque (usuarios y claves de sistema/test.env). NO toca OpenVPMS, Pretix, InvenTree ni\n'
    printf 'ERPNext. Escribe "borrar" para confirmar: '
    local r; read -r r
    [ "${r}" = "borrar" ] || { echo "Cancelado."; exit 0; }
  fi
  paso "Eliminando el contenedor samba-ad"
  dc rm -f -s samba-ad
  paso "Eliminando los volumenes ${v1} y ${v2}"
  local v ok=true
  for v in "${v1}" "${v2}"; do
    if docker volume inspect "${v}" >/dev/null 2>&1; then
      docker volume rm "${v}" | sed 's/^/    /' || ok=false
    else
      info "${v} no existe (ya se habia borrado)."
    fi
  done
  ${ok} || fallo "No se pudo borrar algun volumen. Revisa 'docker volume ls' y quien lo usa (docker ps -a --filter volume=<nombre>)."
  info "Listo. El siguiente '$0 arrancar' reprovisiona el dominio de AD desde cero."
}

case "${ACCION}" in
  arrancar)          accion_arrancar ;;
  preparar)          accion_preparar ;;
  estado)            accion_estado ;;
  verificar)         accion_verificar ;;
  detener)           accion_detener ;;
  borrar)            accion_borrar ;;
  borrar-directorio) accion_borrar_directorio ;;
esac
