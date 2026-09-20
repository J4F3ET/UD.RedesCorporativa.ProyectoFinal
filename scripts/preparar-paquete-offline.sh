#!/usr/bin/env bash
# Arma el paquete de la Fase 0 en una máquina CON Internet y con Docker sano. Se lleva en un USB/disco al
# laboratorio, que NO tiene Internet, y allí se instala con instalar.sh (= scripts/instalar-paquete-offline.sh).
#
# ============================================================================================
# NO VERIFICADO — pendiente de ejecutar con el motor Docker sano.
# Este script se escribió sin poder ejecutarlo (el Docker Desktop de la máquina de desarrollo estaba
# caído). Solo está comprobado que la sintaxis es válida y que el analizador de compose
# (instalar-paquete-offline.sh --listar) extrae bien las imágenes de los tres compose reales.
# Falta ejecutarlo entero, y después probar el paquete en una VM Ubuntu Server limpia y SIN red.
# ============================================================================================
#
# Qué contiene el paquete (las cuatro cosas de la Fase 0):
#   debs/                      Docker Engine + containerd + buildx + compose-plugin y sus dependencias, para
#                              UNA versión de Ubuntu y UNA arquitectura (los .deb son específicos).
#   imagenes/*.tar             Una imagen por fichero, guardada POR ETIQUETA (nunca por digest), + INVENTARIO.tsv.
#                              Incluye la de OpenVPMS ya construida (reservaviva/openvpms-app:fase0).
#   proyecto.tar.gz            El repositorio (git archive del commit actual: sin .git, sin .env, sin certs).
#   instalar.sh                Copia de scripts/instalar-paquete-offline.sh (para poder ejecutarlo desde el USB).
#   PAQUETE.env, MANIFEST.sha256, INVENTARIO.md
#
# Uso (desde la raíz del repo, en la máquina con Internet):
#   UBUNTU=22.04 ./scripts/preparar-paquete-offline.sh [carpeta_salida]        # por defecto ./paquete-fase0
# Variables:
#   UBUNTU          OBLIGATORIA. Versión de Ubuntu Server de los PCs del laboratorio (22.04, 24.04...). Pendiente de
#                   confirmar cuál es: sin ese dato el paquete no sirve. En cada PC: `lsb_release -a`.
#   ARQ             amd64 (por defecto) o arm64. Debe ser la de los PCs (`dpkg --print-architecture`).
#   DOCKER_VERSION  Opcional. Versión exacta de docker-ce (cadena de `apt-cache madison docker-ce`, p.ej.
#                   5:27.5.1-1~ubuntu.22.04~jammy). Vacía = la más reciente del repositorio de Docker AL PREPARAR;
#                   queda anotada en INVENTARIO.md para reproducirla.
#   PERMITIR_SUCIO  1 = permite armar con cambios sin commitear (el proyecto.tar.gz lleva solo lo commiteado).
#
# La imagen de OpenVPMS se construye aquí con `docker build`, que descarga el release de OpenVPMS y el driver JDBC
# (ver docker/pc1-medica/openvpms/Dockerfile). Esas dos descargas NO se verifican por checksum: quedan cubiertas
# solo por el sha256 del tar resultante, no por el origen. Riesgo asumido y anotado en docs/paquete-offline-fase0.md.

set -euo pipefail

RAIZ="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "${RAIZ}"

: "${UBUNTU:?Falta UBUNTU (versión de Ubuntu Server de los PCs, p.ej. UBUNTU=22.04). Averígualo con lsb_release -a en un PC del laboratorio.}"
ARQ="${ARQ:-amd64}"
DOCKER_VERSION="${DOCKER_VERSION:-}"
SALIDA="$(realpath -m "${1:-./paquete-fase0}")"
NOMBRE_PROYECTO="UD.RedesCorporativaa.ProyectoFinak"
INSTALADOR="${RAIZ}/scripts/instalar-paquete-offline.sh"

paso() { echo; echo "== $* =="; }
fallo(){ echo "[FALLO] $*" >&2; exit 1; }

command -v docker >/dev/null 2>&1 || fallo "No hay docker en esta máquina."
docker info >/dev/null 2>&1       || fallo "El motor Docker no responde (docker info falla). Este script necesita un Docker sano."
command -v git >/dev/null 2>&1    || fallo "Falta git."
[ -e "${SALIDA}" ] && fallo "${SALIDA} ya existe. Bórralo o indica otra carpeta: no mezclo paquetes."
if [ -n "$(git status --porcelain)" ] && [ "${PERMITIR_SUCIO:-0}" != "1" ]; then
  fallo "Hay cambios sin commitear: el paquete llevaría el commit, no tu carpeta. Commitea o usa PERMITIR_SUCIO=1."
fi
COMMIT="$(git rev-parse --short HEAD)"
mkdir -p "${SALIDA}"/{debs,imagenes}

# --- 1. Paquetes .deb de Docker, resueltos dentro de un contenedor Ubuntu de la MISMA versión --------------------
paso "1/5 .deb de Docker Engine para Ubuntu ${UBUNTU} / ${ARQ} (contenedor ubuntu:${UBUNTU})"
# En un contenedor limpio, `install --download-only` descarga el paquete pedido y TODAS sus dependencias que la
# imagen mínima no trae: es un superconjunto de lo que necesita un Ubuntu Server. -o Dir::Cache::archives deja
# los .deb en la carpeta montada (el docker-clean de la imagen los borraría de la caché por defecto).
docker run --rm --platform "linux/${ARQ}" -e "DOCKER_VERSION=${DOCKER_VERSION}" -v "${SALIDA}/debs:/salida" "ubuntu:${UBUNTU}" bash -euc '
  export DEBIAN_FRONTEND=noninteractive
  apt-get update -qq
  apt-get install -y -qq --no-install-recommends ca-certificates curl gnupg
  install -m 0755 -d /etc/apt/keyrings
  curl -fsSL https://download.docker.com/linux/ubuntu/gpg -o /etc/apt/keyrings/docker.asc
  . /etc/os-release
  echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/ubuntu ${VERSION_CODENAME} stable" > /etc/apt/sources.list.d/docker.list
  apt-get update -qq
  if [ -n "${DOCKER_VERSION}" ]; then
    # docker-ce y docker-ce-cli comparten versión; el resto (containerd.io, buildx, compose) va a la más reciente.
    PIN="docker-ce=${DOCKER_VERSION} docker-ce-cli=${DOCKER_VERSION}"
  else
    PIN="docker-ce docker-ce-cli"
  fi
  apt-get install -y --download-only --no-install-recommends -o Dir::Cache::archives=/salida \
    ${PIN} containerd.io docker-buildx-plugin docker-compose-plugin
  rm -rf /salida/partial /salida/lock
  echo "${VERSION_CODENAME}" > /salida/CODENAME
'
ls "${SALIDA}"/debs/docker-ce_*.deb "${SALIDA}"/debs/containerd.io_*.deb "${SALIDA}"/debs/docker-compose-plugin_*.deb >/dev/null \
  || fallo "Faltan docker-ce, containerd.io o docker-compose-plugin entre los .deb descargados."

# --- 2. Imágenes de los compose (leídas de los compose, no de memoria) -------------------------------------------
paso "2/5 Imágenes de docker/pc*/docker-compose.yml"
INV="${SALIDA}/imagenes/INVENTARIO.tsv"
printf '# etiqueta\treferencia_del_compose\tid_de_imagen\tfichero\tbytes\tsha256_del_tar\n' > "${INV}"
declare -A YA=()
guardar() {   # $1 = etiqueta, $2 = referencia de origen (informativa), $3 = fichero
  local etiqueta="$1" origen="$2" fichero="$3" id
  id="$(docker image inspect --format '{{.Id}}' "${etiqueta}")"
  # --platform en save: con el almacén containerd, un índice multi-arquitectura del que solo se bajó una plataforma
  # no se puede exportar entero. Si esta versión de Docker no conoce el flag, se reintenta sin él.
  docker save --platform "linux/${ARQ}" -o "${SALIDA}/imagenes/${fichero}" "${etiqueta}" 2>/dev/null \
    || docker save -o "${SALIDA}/imagenes/${fichero}" "${etiqueta}"
  printf '%s\t%s\t%s\t%s\t%s\t%s\n' "${etiqueta}" "${origen}" "${id}" "${fichero}" \
    "$(stat -c %s "${SALIDA}/imagenes/${fichero}")" "$(sha256sum "${SALIDA}/imagenes/${fichero}" | cut -d' ' -f1)" >> "${INV}"
}
nombre_fichero() { echo "$1" | tr '/:' '__'; }

for compose in docker/pc*/docker-compose.yml; do
  while IFS=$'\t' read -r tipo servicio valor; do
    [ "${tipo}" = "imagen" ] || continue
    etiqueta="${valor%%@*}"                       # mysql:8.0.46@sha256:... -> mysql:8.0.46
    [ -z "${YA[${etiqueta}]:-}" ] || continue      # postgres, redis y erpnext se repiten entre servicios
    YA[${etiqueta}]=1
    echo "  -> ${valor}"
    # Se descarga por digest (lo que fija el compose) y se etiqueta sin él: docker load no conserva el digest.
    docker pull --platform "linux/${ARQ}" "${valor}" >/dev/null || fallo "docker pull ${valor} falló (¿el digest no tiene manifiesto para ${ARQ}?)."
    docker tag "${valor}" "${etiqueta}"
    guardar "${etiqueta}" "${valor}" "$(nombre_fichero "${etiqueta}").tar"
  done < <("${INSTALADOR}" --listar "${compose}")
done

# --- 3. Imágenes que el compose CONSTRUYE (OpenVPMS) --------------------------------------------------------------
paso "3/5 Imágenes construidas con build: (OpenVPMS)"
for compose in docker/pc*/docker-compose.yml; do
  carpeta="$(dirname "${compose}")"
  while IFS=$'\t' read -r tipo servicio valor; do
    [ "${tipo}" = "build" ] || continue
    etiqueta="reservaviva/${servicio}:fase0"
    echo "  -> docker build ${carpeta}/${valor} -> ${etiqueta} (descarga OpenVPMS y el driver JDBC: necesita Internet)"
    docker build --platform "linux/${ARQ}" -t "${etiqueta}" "${carpeta}/${valor}"
    guardar "${etiqueta}" "build:${carpeta}/${valor}" "$(nombre_fichero "${etiqueta}").tar"
  done < <("${INSTALADOR}" --listar "${compose}")
done

# --- 4. Proyecto e instalador -------------------------------------------------------------------------------------
paso "4/5 Proyecto (commit ${COMMIT}) e instalador"
git archive --format=tar.gz --prefix="${NOMBRE_PROYECTO}/" -o "${SALIDA}/proyecto.tar.gz" HEAD
cp "${INSTALADOR}" "${SALIDA}/instalar.sh"
chmod +x "${SALIDA}/instalar.sh"
sed -i 's/\r$//' "${SALIDA}/instalar.sh"
cat > "${SALIDA}/PAQUETE.env" <<EOF
UBUNTU_PAQUETE=${UBUNTU}
ARQ_PAQUETE=${ARQ}
FECHA_PAQUETE=$(date +%F)
COMMIT_PAQUETE=${COMMIT}
EOF

# --- 5. Inventario legible y checksums ---------------------------------------------------------------------------
paso "5/5 INVENTARIO.md y MANIFEST.sha256"
{
  echo "# Inventario del paquete de la Fase 0"
  echo
  echo "Generado el $(date +%F) por preparar-paquete-offline.sh — commit ${COMMIT} — Ubuntu ${UBUNTU} (\`$(cat "${SALIDA}/debs/CODENAME")\`) / ${ARQ}."
  echo
  echo "## Paquetes .deb (Docker Engine y dependencias)"
  echo
  echo "| Paquete | Versión | Tamaño (bytes) | sha256 |"
  echo "|---|---|---|---|"
  for d in "${SALIDA}"/debs/*.deb; do
    echo "| $(dpkg-deb -f "${d}" Package 2>/dev/null || basename "${d}") | $(dpkg-deb -f "${d}" Version 2>/dev/null || echo '?') | $(stat -c %s "${d}") | \`$(sha256sum "${d}" | cut -d' ' -f1)\` |"
  done
  echo
  echo "## Imágenes"
  echo
  echo "| Etiqueta | Referencia del compose | Tamaño del tar (bytes) | sha256 del tar |"
  echo "|---|---|---|---|"
  grep -v '^#' "${INV}" | while IFS=$'\t' read -r etiqueta origen _id fichero bytes sha; do
    echo "| \`${etiqueta}\` | \`${origen}\` | ${bytes} | \`${sha}\` |"
  done
} > "${SALIDA}/INVENTARIO.md"
( cd "${SALIDA}" && find . -type f ! -name MANIFEST.sha256 | sort | xargs sha256sum > MANIFEST.sha256 )

echo
echo "Paquete listo en ${SALIDA} ($(du -sh "${SALIDA}" | cut -f1))."
echo "Cópialo entero al USB. En cada PC del laboratorio:  sudo ./instalar.sh"
echo "Recuerda: NO VERIFICADO hasta probarlo en una VM Ubuntu ${UBUNTU} limpia y sin red."
