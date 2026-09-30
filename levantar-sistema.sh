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
#   estado     estado de cada servicio, modo de publicacion (local o intranet) y direcciones de acceso
#   verificar  ejecuta sistema/verificar_arquitectura.py contra el sistema levantado (respeta el modo en que este)
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
#   --intranet      (arrancar/preparar) publica el proxy web (80) y el DNS en la IP de la LAN, para que otros
#                   equipos entren por nombre (*.reservaviva.lan). El DNS va al 53, salvo con Docker Engine en WSL: ahi
#                   va al 1053 y levantar-sistema.ps1 deja un reenviador de Windows en el 53. Sin esta opcion,
#                   "arrancar" deja el modo local (todo en 127.0.0.1). Requisitos: docs/operacion.md, "Acceso desde la LAN"
#   --ip X.X.X.X    (con --intranet) la IP de la LAN a usar; si no se da, la de la ruta por defecto de Windows (o del
#                   sistema, fuera de Windows)
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

# Umbral de memoria para la VM de Docker. El consumo medido de los contenedores esta en docs/resultados-un-host.md.
MIN_VM_GIB=6

ACCION="arrancar"
FORZAR=false
TIMEOUT_MIN=45
RAPIDO=false
SI=false
INTRANET=false
IP_PEDIDA=""

uso() { sed -n '2,30p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'; }

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
if [ -n "${IP_PEDIDA}" ] && ! ${INTRANET}; then
  echo "--ip solo tiene sentido con --intranet" >&2; exit 2
fi
if ${INTRANET} && [ "${ACCION}" != "arrancar" ] && [ "${ACCION}" != "preparar" ]; then
  echo "--intranet solo se usa con arrancar o preparar; ${ACCION} detecta solo el modo en que esta publicado el sistema." >&2
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

# Valor que usara compose para una variable de publicacion: la del entorno si esta exportada (el modo intranet las exporta
# para esta ejecucion; en compose el entorno manda sobre --env-file) y si no, la de test.env.
valor_efectivo() {
  local v="${!1:-}"
  [ -n "${v}" ] && printf '%s' "${v}" || valor_env "$1" "$2"
}

# --- Modo de publicacion: local (127.0.0.1, por defecto) o intranet (IP de la LAN) ----------------------------------
#
# Solo cambian dos contenedores: proxy-web (INTRANET_IP:HTTP_PORT -> 80) y dns-interno (DNS_BIND_IP:DNS_PORT -> 53). El
# modo intranet no toca test.env en disco: exporta INTRANET_IP, DNS_BIND_IP y DNS_PORT para esta ejecucion. Por eso
# "arrancar" sin --intranet vuelve al modo local, y "verificar"/"estado"/"preparar" detectan el modo en que esta
# publicado el sistema, con el puerto real del DNS (para que el down + up -d de la verificacion no lo cambie).
#
# Puerto del DNS en modo intranet: 53, salvo con Docker Engine dentro de WSL, donde es PUERTO_DNS_WSL (1053). Con WSL en
# networkingMode=mirrored, Windows NO entrega a Linux el trafico que llega a su puerto 53 (medido el 27/09/2026: un
# servidor en WSL recibe en el 54 y en el 1053, pero en el 53 Windows responde "puerto inalcanzable" por UDP y rechaza la
# conexion TCP). Por eso dns-interno se publica en <IP>:1053 y levantar-sistema.ps1 arranca en Windows
# sistema/reenviador-dns.ps1, que escucha en <IP>:53 (UDP y TCP) y reenvia cada consulta a <IP>:1053. Los clientes de la
# LAN siguen usando el 53. Con Docker Desktop (publica desde Windows) o con Linux nativo el DNS va directo al 53.

MODO="local"
IP_ANFITRION="127.0.0.1"   # a donde apunta la vista "lan" del DNS: la IP en la que escucha el proxy web
PUERTO_DNS_WSL=1053        # puerto de dns-interno en modo intranet con Docker Engine en WSL (ver arriba)

# true si el DNS del modo intranet necesita el reenviador de Windows: Docker Engine dentro de WSL.
dns_por_reenviador() { en_wsl && [ "$(sistema_docker)" != "Docker Desktop" ]; }

# "IP|puerto" publicados por un contenedor para un puerto interno, o vacio si no existe o no publica.
publicacion_de() {
  docker inspect --format "{{range \$p, \$b := .HostConfig.PortBindings}}{{if eq \$p \"$2\"}}{{range \$b}}{{.HostIp}}|{{.HostPort}}{{end}}{{end}}{{end}}" "$1" 2>/dev/null || true
}

# Detecta el modo del sistema en marcha a partir de lo que publica proxy-web. Exporta las variables para que cualquier
# "compose up" de esta ejecucion lo conserve.
detectar_modo_actual() {
  local p d
  p="$(publicacion_de proxy-web 80/tcp)"
  [ -n "${p}" ] || return 0
  if [ "${p%%|*}" != "127.0.0.1" ] && [ -n "${p%%|*}" ]; then
    MODO="intranet"; IP_ANFITRION="${p%%|*}"
    export INTRANET_IP="${p%%|*}" HTTP_PORT="${p##*|}"
    d="$(publicacion_de dns-interno 53/udp)"
    if [ -n "${d}" ]; then export DNS_BIND_IP="${d%%|*}" DNS_PORT="${d##*|}"; fi
  fi
}

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

# Fija el modo de esta ejecucion y exporta las variables de publicacion.
resolver_modo() {
  if ${INTRANET}; then
    local ip="${IP_PEDIDA}"
    if [ -z "${ip}" ]; then
      ip="$(detectar_ip_lan)"
      es_ipv4 "${ip}" || fallo "No se pudo detectar la IP de la LAN de este equipo. Indicala a mano: --ip X.X.X.X (en PowerShell: -Intranet -IP X.X.X.X). Es la IPv4 del adaptador Wi-Fi o Ethernet (ipconfig en Windows)."
    fi
    case "${ip}" in
      127.*|0.0.0.0) fallo "La IP ${ip} no sirve para el modo intranet: otros equipos no pueden llegar a ella. Usa la IP de la LAN (ipconfig en Windows) o arranca sin --intranet para el modo local." ;;
    esac
    MODO="intranet"; IP_ANFITRION="${ip}"
    local puerto_dns=53
    if dns_por_reenviador; then puerto_dns="${PUERTO_DNS_WSL}"; fi
    export INTRANET_IP="${ip}" DNS_BIND_IP="${ip}" DNS_PORT="${puerto_dns}"
  elif [ "${ACCION}" != "arrancar" ]; then
    detectar_modo_actual
  fi
}

# Comprobaciones previas del modo intranet, ANTES de tocar ningun contenedor. Cada fallo dice que hacer.
comprobar_intranet() {
  paso "Comprobando el modo intranet (IP ${IP_ANFITRION})"
  local so; so="$(sistema_docker)"
  # (a) Que la IP este en este sistema. Con Docker Desktop, Desktop publica en Windows y no hace falta.
  if [ "${so}" != "Docker Desktop" ]; then
    if en_wsl; then
      local red; red="$(wslinfo --networking-mode 2>/dev/null || echo desconocido)"
      info "Red de WSL: ${red}"
      if [ "${red}" != "mirrored" ]; then
        fallo "WSL esta en modo de red '${red}', no 'mirrored'. En ese modo la distro no tiene la IP ${IP_ANFITRION}: Docker no puede publicar en ella y otros equipos de la LAN no llegarian a los contenedores.
       Que hacer: ejecutar UNA vez, en PowerShell como administrador, sistema\\habilitar-intranet-windows.ps1 (activa
       networkingMode=mirrored en .wslconfig y abre el cortafuegos para 80/tcp y 53/udp+tcp), despues 'wsl --shutdown'
       (para los contenedores) y volver a lanzar: .\\levantar-sistema.ps1 -Intranet -Forzar
       Pasos completos: docs/operacion.md, 'Acceso desde la LAN'. Nada se ha cambiado: el sistema sigue en el modo en que estaba."
      fi
    fi
    if ! ip -4 -o addr show 2>/dev/null | grep -q " ${IP_ANFITRION}/"; then
      fallo "La IP ${IP_ANFITRION} no esta en ninguna interfaz de este sistema ($(ip -4 -o addr show 2>/dev/null | awk '{print $4}' | tr '\n' ' ')).
       Comprueba la IP con ipconfig (Windows) o ip addr y pasala con --ip (PowerShell: -IP). Nada se ha cambiado."
    fi
  fi
  # (b) Que el puerto del proxy y el del DNS esten libres en esa IP (o ya sean nuestros, de una ejecucion anterior en modo
  # intranet). En WSL el del DNS es el 1053: el 53 de Windows es del reenviador y lo comprueba levantar-sistema.ps1.
  local http_port dns_port="${DNS_PORT}" ocupado="" l
  http_port="$(valor_efectivo HTTP_PORT 80)"
  if command -v ss >/dev/null 2>&1; then
    if [ "$(publicacion_de proxy-web 80/tcp)" != "${IP_ANFITRION}|${http_port}" ]; then
      l="$(ss -H -ltn "( sport = :${http_port} )" 2>/dev/null | awk -v ip="${IP_ANFITRION}" '$4 ~ "^(" ip "|0\\.0\\.0\\.0|\\*|\\[::\\]):"' | head -n 3)"
      [ -n "${l}" ] && ocupado+=$'\n'"       ${http_port}/tcp (proxy web): ${l//$'\n'/ ; }"
    fi
    if [ "$(publicacion_de dns-interno 53/udp)" != "${IP_ANFITRION}|${dns_port}" ]; then
      l="$(ss -H -lun "( sport = :${dns_port} )" 2>/dev/null | awk -v ip="${IP_ANFITRION}" '$4 ~ "^(" ip "|0\\.0\\.0\\.0|\\*|\\[::\\]):"' | head -n 3)"
      [ -n "${l}" ] && ocupado+=$'\n'"       ${dns_port}/udp (DNS): ${l//$'\n'/ ; }"
      l="$(ss -H -ltn "( sport = :${dns_port} )" 2>/dev/null | awk -v ip="${IP_ANFITRION}" '$4 ~ "^(" ip "|0\\.0\\.0\\.0|\\*|\\[::\\]):"' | head -n 3)"
      [ -n "${l}" ] && ocupado+=$'\n'"       ${dns_port}/tcp (DNS): ${l//$'\n'/ ; }"
    fi
  fi
  if [ -n "${ocupado}" ]; then
    fallo "Hay puertos ocupados en ${IP_ANFITRION} por otros programas de este sistema:${ocupado}
       Para 53: suele ser systemd-resolved (DNSStubListener) o dnsmasq; para ${http_port}: otro servidor web.
       Liberalos o, para el proxy web, usa otro puerto libre: HTTP_PORT=<puerto> ./levantar-sistema.sh --intranet
       (los clientes entraran entonces con http://<nombre>:<puerto>). Nada se ha cambiado."
  fi
  info "IP presente en el sistema y puertos ${http_port}/tcp y ${dns_port}/udp+tcp libres en ella (vistos desde aqui)."
  if [ "${dns_port}" != "53" ]; then
    info "DNS en ${IP_ANFITRION}:${dns_port}: con WSL mirrored, Windows no entrega su puerto 53 a Linux. El 53 lo atiende"
    info "el reenviador de Windows (sistema/reenviador-dns.ps1), que arranca levantar-sistema.ps1 -Intranet."
  fi
}

# Publica primero SOLO proxy-web y dns-interno en la IP de la LAN. Si Docker no puede (puerto ocupado en Windows por el
# servicio ICS o por Portmaster, IP ausente...), explica la causa y vuelve a publicarlos en 127.0.0.1: el sistema no queda
# a medias.
publicar_intranet() {
  paso "Publicando el proxy web (${IP_ANFITRION}:$(valor_efectivo HTTP_PORT 80)) y el DNS (${IP_ANFITRION}:${DNS_PORT}) en la LAN"
  local salida
  if salida="$(dc up -d --no-deps proxy dns 2>&1)"; then
    printf '%s\n' "${salida}" | sed 's/^/    /'
    return 0
  fi
  printf '%s\n' "${salida}" | sed 's/^/    /' >&2
  local causa="Docker no pudo publicar en ${IP_ANFITRION} (salida de compose arriba)."
  if printf '%s' "${salida}" | grep -qi 'address already in use'; then
    if printf '%s' "${salida}" | grep -q ":${DNS_PORT}[^0-9]"; then
      causa="El puerto ${DNS_PORT} de ${IP_ANFITRION} (DNS) ya esta en uso por otro programa. Si es el 53, en Windows lo
       suelen tener el servicio 'Conexion compartida a Internet' (ICS, SharedAccess, en 0.0.0.0:53/udp) y Portmaster
       (portmaster-core, en [::]:53): sistema\\habilitar-intranet-windows.ps1, como administrador, detecta quien lo ocupa
       y da los comandos para liberarlo (no los ejecuta por su cuenta). Si es otro puerto, liberalo y repite."
    else
      causa="El puerto $(valor_efectivo HTTP_PORT 80) de ${IP_ANFITRION} ya esta en uso por otro servidor web (en Windows: IIS,
       Skype antiguo, otro contenedor...). Liberalo o usa otro puerto libre para el proxy: HTTP_PORT=<puerto> en el entorno."
    fi
  elif printf '%s' "${salida}" | grep -qi 'cannot assign requested address'; then
    causa="La IP ${IP_ANFITRION} no esta en el sistema donde corre Docker. En WSL hace falta networkingMode=mirrored
       (sistema\\habilitar-intranet-windows.ps1)."
  fi
  aviso "Vuelvo a publicar proxy-web y dns-interno como dice sistema/test.env (modo local) para no dejar el sistema a medias."
  MODO="local"; IP_ANFITRION="127.0.0.1"
  unset INTRANET_IP DNS_BIND_IP DNS_PORT HTTP_PORT
  generar_zona >/dev/null
  dc up -d --no-deps proxy dns >&2 || aviso "Tampoco se pudo volver al modo local: revisa 'docker compose ps' y vuelve a ejecutar sin --intranet."
  fallo "${causa}"
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
  # Idempotente: si existen, son validos y cubren las direcciones, no toca nada. No instala la CA en el host.
  bash "${RAIZ}/servicios/ca/generar-certificados.sh" --sin-instalar-ca | sed 's/^/    /'
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

# Dos zonas de reservaviva.lan (una por vista de servicios/bind9/named.conf) y la ACL de la vista interna.
generar_zona() {
  paso "Zonas DNS reservaviva.lan (vista interna y vista lan) - modo ${MODO}"
  local dir="${RAIZ}/servicios/bind9/zones"
  local tpl="${dir}/db.reservaviva.lan.tpl" out="${dir}/db.reservaviva.lan"
  local tpl_lan="${dir}/db.reservaviva.lan.vista-lan.tpl" out_lan="${dir}/db.reservaviva.lan.vista-lan"
  local acl="${dir}/acl-interna.conf"
  [ -f "${tpl}" ] || fallo "Falta la plantilla ${tpl}"
  [ -f "${tpl_lan}" ] || fallo "Falta la plantilla ${tpl_lan}"
  # Vista interna: cada nombre apunta al contenedor que da ese servicio, con la misma IP fija que le da el compose
  # (mismas subredes NET_* y mismos valores por defecto). rrhh es erpnext-hr, el nginx de ERPNext: el que atiende HTTP.
  local infra medica taquilla logistica rrhh serial r
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
  r="$(reemplazar_si_cambia "${out}")"
  info "${r} vista interna: dns=${ip_dns} ldap=${ip_ldap} ntp=${ip_ntp} openvpms=${ip_openvpms} pretix=${ip_pretix}"
  info "                         inventree=${ip_inventree} rrhh=${ip_rrhh}"
  # Vista lan: las cuatro aplicaciones y el DNS apuntan a la IP del anfitrion (proxy web y DNS publicados).
  tr -d '\r' <"${tpl_lan}" | sed -e "s/\${IP_ANFITRION}/${IP_ANFITRION}/g" -e "s/\${SERIAL}/${serial}/g" >"${out_lan}.tmp"
  r="$(reemplazar_si_cambia "${out_lan}")"
  info "${r} vista lan:     openvpms, pretix, inventree, rrhh y dns -> ${IP_ANFITRION} (sin ldap ni ntp)"
  # ACL de la vista interna: las subredes de las VLAN sin su gateway .1 (por el .1 llega el anfitrion, ver named.conf).
  local s nets=() excl=()
  for s in "${medica}" "${taquilla}" "${logistica}" "${rrhh}" "${infra}"; do excl+=("!${s}.1;"); nets+=("${s}.0/24;"); done
  { printf '// GENERADO por levantar-sistema.sh (generar_zona) desde las subredes NET_* del compose: no editar.\n'
    printf '// Clientes de la vista "interna": los contenedores de las VLAN, sin el gateway .1 de cada bridge.\n'
    printf 'acl "red-interna" { %s %s };\n' "${excl[*]}" "${nets[*]}"; } >"${acl}.tmp"
  r="$(reemplazar_si_cambia "${acl}")"
  info "${r} ACL de la vista interna: ${nets[*]} (sin los .1)"
}

# bind9 lee su configuracion y las zonas al arrancar y no vigila los ficheros. Si alguno (named.conf, las dos zonas o la
# ACL) es mas nuevo que el arranque de dns-interno (p. ej. tras cambiar una plantilla o el modo de publicacion), se
# reinicia solo ese contenedor: unos segundos, sin tocar datos.
reiniciar_dns_si_zona_nueva() {
  local d="${RAIZ}/servicios/bind9" inicio t_dns t f
  inicio="$(docker inspect --format '{{.State.StartedAt}}' dns-interno 2>/dev/null)" || return 0
  t_dns="$(date -d "${inicio}" +%s 2>/dev/null)" || return 0
  for f in "${d}/named.conf" "${d}/zones/db.reservaviva.lan" "${d}/zones/db.reservaviva.lan.vista-lan" "${d}/zones/acl-interna.conf"; do
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
recrear_ldap_si_cert_nuevo() {
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
  local p1 p2 p3 p4 ldap ldaps dns ntp hp suf="" dns_ip
  p1="$(valor_env OPENVPMS_PORT 8080)"; p2="$(valor_env ERPNEXT_PORT 8080)"
  p3="$(valor_env PRETIX_PORT 80)";     p4="$(valor_env INVENTREE_PORT 8000)"
  ldap="$(valor_env LDAP_PORT 389)"; ldaps="$(valor_env LDAPS_PORT 636)"
  dns="$(valor_efectivo DNS_PORT 53)"; ntp="$(valor_env NTP_PORT 123)"
  dns_ip="$(valor_efectivo DNS_BIND_IP 127.0.0.1)"
  hp="$(valor_efectivo HTTP_PORT 80)"; [ "${hp}" = "80" ] || suf=":${hp}"
  if [ "${MODO}" = "intranet" ]; then
    cat <<EOF

    Modo INTRANET: el proxy web y el DNS se publican en ${IP_ANFITRION}. Desde cualquier equipo de la LAN:
      Medica             OpenVPMS   http://openvpms.reservaviva.lan${suf}      usuario: admin
      Taquilla           Pretix     http://pretix.reservaviva.lan${suf}        usuario: $(valor_env PRETIX_ADMIN_EMAIL admin@reservaviva.local)
      Logistica          InvenTree  http://inventree.reservaviva.lan${suf}     usuario: $(valor_env INVENTREE_ADMIN_USER admin)
      RRHH               ERPNext    http://rrhh.reservaviva.lan${suf}          usuario: Administrator
    Para que esos nombres resuelvan, cada cliente debe usar como DNS la IP ${dns_ip} (puerto 53):
      - a mano en el cliente (Windows: Configuracion > Red > Editar DNS; comprobar con: nslookup pretix.reservaviva.lan ${dns_ip}), o
      - para toda la LAN, en el DHCP del router (DNS primario ${dns_ip}). OJO: este DNS solo conoce reservaviva.lan
        (no hace recursion); con el DHCP, los clientes necesitan un DNS secundario para Internet.
    AVISO: las contrasenas de laboratorio estan PUBLICAS en git (sistema/test.env). Cualquiera en esta red puede entrar
    como administrador. Usa este modo solo en una red de laboratorio y vuelve al modo local al terminar:
      .\\levantar-sistema.ps1 -Forzar   (o ./levantar-sistema.sh, sin --intranet)
    Acceso directo desde este equipo (administracion): http://localhost:${p1}/openvpms  :${p3}  :${p4}  :${p2}
      Infra              LDAP localhost:${ldap}  LDAPS localhost:${ldaps}  NTP localhost:${ntp}/udp  (solo este equipo)
EOF
    if [ "${dns}" != "53" ]; then
      info "DNS: dns-interno se publica en ${dns_ip}:${dns}; el puerto 53 lo atiende el reenviador de Windows"
      info "(sistema/reenviador-dns.ps1), que arranca y comprueba levantar-sistema.ps1 -Intranet. Si lanzaste este script"
      info "desde WSL a mano, ejecuta en Windows .\\levantar-sistema.ps1 -Intranet para tener el 53."
    fi
  else
    cat <<EOF

    Modo LOCAL: todo se publica en 127.0.0.1 (solo desde este equipo). Para otros equipos: --intranet (-Intranet).
      Medica             OpenVPMS   http://localhost:${p1}/openvpms     usuario: admin
      Taquilla           Pretix     http://localhost:${p3}              usuario: $(valor_env PRETIX_ADMIN_EMAIL admin@reservaviva.local)
      Logistica          InvenTree  http://localhost:${p4}              usuario: $(valor_env INVENTREE_ADMIN_USER admin)
      RRHH               ERPNext    http://localhost:${p2}              usuario: Administrator
      Por nombre (proxy web en 127.0.0.1${suf}): http://pretix.reservaviva.lan${suf}, etc. Requiere que este equipo
      resuelva *.reservaviva.lan a 127.0.0.1 (archivo hosts); el DNS local escucha en el puerto ${dns}, no en el 53.
      Infra              LDAP localhost:${ldap}  LDAPS localhost:${ldaps}  DNS localhost:${dns}  NTP localhost:${ntp}/udp
    Contrasenas de laboratorio (desechables): sistema/test.env
EOF
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
  resolver_modo
  ${INTRANET} && comprobar_intranet
  comprobar_memoria
  preparar
  reiniciar_unhealthy
  ${INTRANET} && publicar_intranet
  local n; n="$(dc config --services | grep -c .)"
  paso "Levantando los ${n} servicios en modo ${MODO} (la primera vez descarga varios GB de imagenes)"
  if ! dc up -d; then
    diagnostico
    fallo "docker compose up fallo. Volver a ejecutar el script es seguro: retoma donde quedo."
  fi
  reiniciar_dns_si_zona_nueva
  recrear_ldap_si_cert_nuevo
  esperar_sano
  crear_admin_pretix
  paso "Sistema en marcha: los ${n} servicios estan sanos"
  accesos
  info ""
  info "Siguiente paso recomendado:  $0 verificar   (segmentacion, DNS, NTP, LDAP y acceso por nombre)"
  aviso_sesion_wsl
}

accion_preparar() {
  comprobar_requisitos
  resolver_modo
  preparar
  paso "Preparacion completa (zonas DNS para el modo ${MODO}). Para levantar el sistema: $0 arrancar"
}

accion_estado() {
  cd "${RAIZ}"
  docker info >/dev/null 2>&1 || fallo "Docker no responde."
  resolver_modo
  paso "Estado de los servicios"
  dc ps -a --format 'table {{.Service}}\t{{.State}}\t{{.Status}}'
  paso "Modo de publicacion: ${MODO}"
  local p d
  p="$(publicacion_de proxy-web 80/tcp)"; d="$(publicacion_de dns-interno 53/udp)"
  if [ -n "${p}" ]; then p="${p/|/:}"; else p="no publicado (contenedor ausente)"; fi
  if [ -n "${d}" ]; then d="${d/|/:} udp y tcp"; else d="no publicado (contenedor ausente)"; fi
  info "proxy web (proxy-web):  ${p}"
  info "DNS (dns-interno):      ${d}"
  accesos
  aviso_sesion_wsl
}

accion_verificar() {
  # Conserva el modo en que esta publicado el sistema: la prueba de persistencia hace down + up -d, y sin las variables
  # exportadas ese up -d devolveria proxy-web y dns-interno al modo local.
  resolver_modo
  [ "${MODO}" = "intranet" ] && info "Sistema publicado en modo intranet (${IP_ANFITRION}): la verificacion lo conserva."
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
