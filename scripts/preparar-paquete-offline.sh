#!/usr/bin/env bash
# Arma el paquete de la Fase 0 en una maquina CON Internet y con Docker sano (Git Bash en Windows, o Linux).
# El paquete se lleva en un USB/disco a los TRES PCs del laboratorio (Windows con Docker Desktop, sin Internet)
# y en cada uno se instala con instalar.ps1 -Perfil pc1|pc2|pc3 (= scripts/instalar-paquete-offline.ps1).
#
# ============================================================================================
# PARCIALMENTE VERIFICADO (2026-09-20): este script corrio de punta a punta con Docker 29.8.0 (EXIT 0, 3,4 GB); en esa
# ejecucion NO se comprobo que se genere overrides/ (se perdio por un accidente al borrar la salida). Falta repetirlo y
# probar el paquete en un PC sin red. Detalle en docs/paquete-offline-fase0.md, "Registro de verificacion".
# ============================================================================================
#
# Contenido del paquete (todo se genera en SALIDA):
#   imagenes/*.tar          Una imagen por fichero, guardada POR ETIQUETA (nunca por digest) + INVENTARIO.tsv.
#                           Incluye la de OpenVPMS ya construida (reservaviva/openvpms-app:fase0) y la de los
#                           simuladores de despliegue/*/pruebas (nicolaka/netshoot, perfil "simuladores").
#   overrides/<pc>.yml      docker-compose.override.yml de cada PC: imagenes por etiqueta sin digest + pull_policy: never.
#   certs/<pc>/             Certificados ya generados (CA compartida por los tres PCs; ldap.* solo para PC-3).
#   proyecto.zip            El repositorio (git archive del commit: sin .git, sin .env, sin certs).
#   instalar.ps1            Copia de scripts/instalar-paquete-offline.ps1.
#   PAQUETE.env, MANIFEST.sha256, INVENTARIO.md
#
# Uso (desde la raiz del repo):
#   [LDAP_IP=x.x.x.x] ./scripts/preparar-paquete-offline.sh [carpeta_salida]      # por defecto ./paquete-fase0
# Variables:
#   ARQ             amd64 (por defecto) o arm64: la de los PCs del laboratorio (Docker Desktop en Windows: amd64 casi seguro).
#   LDAP_IP / LDAP_DOMAIN   Se pasan tal cual a generar-certificados.sh (vacias = sus valores por defecto). No hace falta
#                   ajustarlas: los clientes verifican el NOMBRE ldap.<dominio>, que siempre esta en el SAN (ver el doc).
#   PERMITIR_SUCIO  1 = permite armar con cambios sin commitear (proyecto.zip y certs usan solo lo commiteado).
#
# La imagen de OpenVPMS se construye aqui con `docker build`, que descarga el release de OpenVPMS y el driver JDBC
# (ver docker/pc1-medica/openvpms/Dockerfile). Esas descargas no se verifican por checksum: el sha256 del tar resultante
# solo protege del USB, no del origen. Riesgo asumido y anotado en docs/paquete-offline-fase0.md.

set -euo pipefail

# ---------------------------------------------------------------------------------------------
# Analizador minimo del compose (awk, sin dependencias). Emite "imagen<TAB>servicio<TAB>referencia" y
# "build<TAB>servicio<TAB>contexto". Reconoce `image: ref`, `image: &ancla ref`, `image: *ancla` y `build:` de servicio.
# ---------------------------------------------------------------------------------------------
listar_compose() {
  awk '
    /^services:/            { en = 1; next }
    /^[A-Za-z_]/            { en = 0 }
    !en                     { next }
    /^  [A-Za-z0-9_.-]+:[ \t]*(#.*)?$/ {
      s = $0; sub(/^  /, "", s); sub(/:.*/, "", s); srv = s; next
    }
    /^    image:[ \t]+/ {
      v = $0; sub(/^    image:[ \t]+/, "", v); sub(/[ \t]+#.*$/, "", v); sub(/[ \t]+$/, "", v)
      if (v ~ /^&/) { nombre = v; sub(/^&/, "", nombre); sub(/[ \t].*$/, "", nombre); sub(/^&[^ \t]+[ \t]+/, "", v); ancla[nombre] = v }
      else if (v ~ /^\*/) { nombre = v; sub(/^\*/, "", nombre); v = ancla[nombre] }
      if (v != "") printf "imagen\t%s\t%s\n", srv, v
      next
    }
    /^    build:[ \t]*[^ \t#]/ {
      v = $0; sub(/^    build:[ \t]*/, "", v); sub(/[ \t]+#.*$/, "", v); printf "build\t%s\t%s\n", srv, v; next
    }
  ' "$1"
}

if [ "${1:-}" = "--listar" ]; then
  [ -f "${2:-}" ] || { echo "Uso: $0 --listar <docker-compose.yml>" >&2; exit 2; }
  listar_compose "$2"
  exit 0
fi

RAIZ="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "${RAIZ}"

ARQ="${ARQ:-amd64}"
SALIDA="$(realpath -m "${1:-./paquete-fase0}")"
NOMBRE_PROYECTO="UD.RedesCorporativaa.ProyectoFinak"

paso() { echo; echo "== $* =="; }
fallo(){ echo "[FALLO] $*" >&2; exit 1; }

command -v docker >/dev/null 2>&1 || fallo "No hay docker en esta maquina."
docker info >/dev/null 2>&1       || fallo "El motor Docker no responde (docker info falla). Este script necesita un Docker sano."
command -v git >/dev/null 2>&1    || fallo "Falta git."
command -v openssl >/dev/null 2>&1|| fallo "Falta openssl (viene con Git Bash) para generar los certificados."
[ -e "${SALIDA}" ] && fallo "${SALIDA} ya existe. Borralo o indica otra carpeta: no mezclo paquetes."
if [ -n "$(git status --porcelain)" ] && [ "${PERMITIR_SUCIO:-0}" != "1" ]; then
  fallo "Hay cambios sin commitear: el paquete llevaria el commit, no tu carpeta. Commitea o usa PERMITIR_SUCIO=1."
fi
COMMIT="$(git rev-parse --short HEAD)"
mkdir -p "${SALIDA}"/{imagenes,overrides,certs}

# Carpetas de PC leidas del repo: docker/pc1-medica -> perfil "pc1", etc.
declare -A CARPETA=()
for compose in docker/pc*/docker-compose.yml; do
  c="$(basename "$(dirname "${compose}")")"      # pc1-medica
  CARPETA["${c%%-*}"]="${c}"                     # pc1 -> pc1-medica
done

# --- 1. Que imagenes hay que llevar, y que PC usa cada una (leido de los compose) --------------------------------
paso "1/6 Leyendo docker/pc*/docker-compose.yml"
declare -A ORIGEN=() PERFILES=()
for perfil in "${!CARPETA[@]}"; do
  compose="docker/${CARPETA[${perfil}]}/docker-compose.yml"
  override="${SALIDA}/overrides/${CARPETA[${perfil}]}.yml"
  {
    echo "# Generado por preparar-paquete-offline.sh - NO editar. Sustituye las referencias por digest por su etiqueta"
    echo "# (docker load no conserva el digest en el almacen clasico) y prohibe descargar imagenes."
    echo "services:"
  } > "${override}"
  while IFS=$'\t' read -r tipo servicio valor; do
    if [ "${tipo}" = "imagen" ]; then
      etiqueta="${valor%%@*}"                    # mysql:8.0.46@sha256:... -> mysql:8.0.46
      ORIGEN[${etiqueta}]="${valor}"
      printf '  %s:\n    image: %s\n    pull_policy: never\n' "${servicio}" "${etiqueta}" >> "${override}"
    else
      etiqueta="reservaviva/${servicio}:fase0"   # imagen construida con build:
      ORIGEN[${etiqueta}]="build:docker/${CARPETA[${perfil}]}/${valor#./}"
      # Con image: + build:, Compose usa la imagen local si existe y solo construye si falta.
      printf '  %s:\n    image: %s\n' "${servicio}" "${etiqueta}" >> "${override}"
    fi
    case " ${PERFILES[${etiqueta}]:-} " in *" ${perfil} "*) ;; *) PERFILES[${etiqueta}]="${PERFILES[${etiqueta}]:-} ${perfil}" ;; esac
  done < <(listar_compose "${compose}")
  echo "  ${perfil}: ${CARPETA[${perfil}]} -> overrides/${CARPETA[${perfil}]}.yml"
done

# Imagen de los simuladores (despliegue/*/pruebas): se lee de los README, que la citan por digest. Su etiqueta local
# es nicolaka/netshoot:fase0; los README usan la referencia por digest, que solo se resuelve con el almacen containerd.
NETSHOOT="$(git grep -hoE 'nicolaka/netshoot@sha256:[0-9a-f]{64}' HEAD -- despliegue | sort -u)"
[ "$(echo "${NETSHOOT}" | grep -c .)" = "1" ] || fallo "Esperaba UNA referencia de nicolaka/netshoot en despliegue/, encontre: ${NETSHOOT:-ninguna}"
ORIGEN["nicolaka/netshoot:fase0"]="${NETSHOOT}"
PERFILES["nicolaka/netshoot:fase0"]="simuladores"
echo "  simuladores: ${NETSHOOT}"
echo "  ${#ORIGEN[@]} imagenes distintas."

# --- 2. Imagenes: pull por digest, etiqueta sin digest, save ------------------------------------------------------
paso "2/6 Descargando y guardando las imagenes"
INV="${SALIDA}/imagenes/INVENTARIO.tsv"
printf '# etiqueta\treferencia_de_origen\tid_de_imagen\tfichero\tbytes\tsha256_del_tar\tperfiles\n' > "${INV}"
nombre_fichero() { echo "$1" | tr '/:' '__'; }
guardar() {   # $1 = etiqueta
  local etiqueta="$1" fichero id
  fichero="$(nombre_fichero "${etiqueta}").tar"
  id="$(docker image inspect --format '{{.Id}}' "${etiqueta}")"
  # --platform en save: con el almacen containerd, un indice multi-arquitectura del que solo se bajo una plataforma no
  # se puede exportar entero. Si esta version de Docker no conoce el flag, se reintenta sin el.
  docker save --platform "linux/${ARQ}" -o "${SALIDA}/imagenes/${fichero}" "${etiqueta}" 2>/dev/null \
    || docker save -o "${SALIDA}/imagenes/${fichero}" "${etiqueta}"
  printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\n' "${etiqueta}" "${ORIGEN[${etiqueta}]}" "${id}" "${fichero}" \
    "$(stat -c %s "${SALIDA}/imagenes/${fichero}")" "$(sha256sum "${SALIDA}/imagenes/${fichero}" | cut -d' ' -f1)" \
    "$(echo ${PERFILES[${etiqueta}]})" >> "${INV}"
}
for etiqueta in $(printf '%s\n' "${!ORIGEN[@]}" | sort); do
  origen="${ORIGEN[${etiqueta}]}"
  case "${origen}" in
    build:*)
      ruta="${origen#build:}"
      echo "  -> docker build ${ruta} -> ${etiqueta} (descarga OpenVPMS y el driver JDBC: necesita Internet)"
      docker build --platform "linux/${ARQ}" -t "${etiqueta}" "${ruta}"
      ;;
    *)
      echo "  -> ${origen}"
      # Se descarga por digest (lo que fija el compose) y se etiqueta sin el: docker load no siempre conserva el digest.
      docker pull --platform "linux/${ARQ}" "${origen}" >/dev/null || fallo "docker pull ${origen} fallo (el digest no tiene manifiesto para ${ARQ}?)."
      docker tag "${origen}" "${etiqueta}"
      ;;
  esac
  guardar "${etiqueta}"
done

# --- 3. Certificados ya generados ----------------------------------------------------------------------------------
paso "3/6 Certificados (CA interna + certificado LDAPS), generados desde el commit ${COMMIT}"
# Se extrae el commit a una carpeta temporal y se ejecuta AHI generar-certificados.sh, que escribe en su propio repo:
# asi no toca los certs de este arbol de trabajo (estan en .gitignore y pueden ser los de otro laboratorio).
TMP="$(mktemp -d)"
trap 'rm -rf "${TMP}"' EXIT
git -c core.autocrlf=false archive --format=tar HEAD | tar -x -C "${TMP}"
( cd "${TMP}" && env ${LDAP_IP:+LDAP_IP="${LDAP_IP}"} ${LDAP_DOMAIN:+LDAP_DOMAIN="${LDAP_DOMAIN}"} bash scripts/generar-certificados.sh --sin-instalar-ca ) \
  || fallo "generar-certificados.sh fallo."
for perfil in "${!CARPETA[@]}"; do
  mkdir -p "${SALIDA}/certs/${perfil}"
  cp "${TMP}/docker/${CARPETA[${perfil}]}/certs/"* "${SALIDA}/certs/${perfil}/"
done
[ -s "${SALIDA}/certs/pc3/ldap.crt" ] || fallo "No se genero ldap.crt para PC-3."
echo "  SAN de ldap.crt: $(openssl x509 -in "${SALIDA}/certs/pc3/ldap.crt" -noout -ext subjectAltName | tail -1 | sed 's/^ *//')"

# --- 4. Proyecto e instalador ---------------------------------------------------------------------------------------
paso "4/6 Proyecto (commit ${COMMIT}) e instalador"
git -c core.autocrlf=false archive --format=zip --prefix="${NOMBRE_PROYECTO}/" -o "${SALIDA}/proyecto.zip" HEAD
cp scripts/instalar-paquete-offline.ps1 "${SALIDA}/instalar.ps1"
cat > "${SALIDA}/PAQUETE.env" <<EOF
ARQ_PAQUETE=${ARQ}
FECHA_PAQUETE=$(date +%F)
COMMIT_PAQUETE=${COMMIT}
NOMBRE_PROYECTO=${NOMBRE_PROYECTO}
EOF

# --- 5. Inventario legible -------------------------------------------------------------------------------------------
paso "5/6 INVENTARIO.md"
{
  echo "# Inventario del paquete de la Fase 0"
  echo
  echo "Generado el $(date +%F) por preparar-paquete-offline.sh - commit ${COMMIT} - ${ARQ}."
  echo
  echo "| Etiqueta | Origen | PCs | Tamano del tar (bytes) | sha256 del tar |"
  echo "|---|---|---|---|---|"
  grep -v '^#' "${INV}" | while IFS=$'\t' read -r etiqueta origen _id _fichero bytes sha perfiles; do
    echo "| \`${etiqueta}\` | \`${origen}\` | ${perfiles} | ${bytes} | \`${sha}\` |"
  done
} > "${SALIDA}/INVENTARIO.md"

# --- 6. Manifiesto de checksums (formato: "<sha256>  <ruta relativa>") -----------------------------------------------
paso "6/6 MANIFEST.sha256"
( cd "${SALIDA}" && find . -type f ! -name MANIFEST.sha256 | sed 's|^\./||' | sort | xargs sha256sum > MANIFEST.sha256 )

echo
echo "Paquete listo en ${SALIDA} ($(du -sh "${SALIDA}" | cut -f1))."
echo "Copialo entero al USB. En cada PC:  powershell -ExecutionPolicy Bypass -File .\\instalar.ps1 -Perfil pc1|pc2|pc3"
echo "Recuerda: NO VERIFICADO hasta probarlo con Docker sano y en un PC sin red."
