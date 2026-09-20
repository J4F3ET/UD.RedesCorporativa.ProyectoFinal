#!/usr/bin/env bash
# Instala en el LABORATORIO (SIN Internet) el paquete de la Fase 0 que armó preparar-paquete-offline.sh.
#
# ============================================================================================
# NO VERIFICADO — pendiente de ejecutar con el motor Docker sano.
# Este script se escribió sin poder ejecutarlo (el Docker Desktop de la máquina de desarrollo estaba
# caído). Nada de lo de abajo se ha probado de extremo a extremo. Antes de fiarse de él, correrlo en
# una VM Ubuntu Server limpia, sin red, y anotar el resultado en docs/paquete-offline-fase0.md.
# ============================================================================================
#
# Qué hace (en este orden, y se detiene en el primer fallo):
#   1. Comprueba root, arquitectura y versión de Ubuntu contra las del paquete.
#   2. Verifica los checksums de TODO el paquete (MANIFEST.sha256).
#   3. Instala Docker Engine + containerd + plugin compose desde debs/ (sin red).
#   4. Carga las imágenes (docker load) y comprueba que cada una quedó con su etiqueta.
#   5. Deja el proyecto en DESTINO y escribe un docker-compose.override.yml en cada docker/pcN-*/
#      (ver "Por qué el override" abajo).
#
# NO usa curl, git clone, apt desde red, apt-get update ni docker pull. Si algo intenta salir a
# Internet es un fallo del script: repórtalo, no le des red al laboratorio.
#
# Uso (en el PC del laboratorio, con el paquete montado/copiado):
#   sudo ./instalar.sh                      # el paquete es la carpeta donde vive este script
#   sudo PAQUETE=/media/usb/paquete-fase0 DESTINO=/home/ubuntu/UD.RedesCorporativaa.ProyectoFinak ./instalar.sh
#
# Uso interno (lo llama preparar-paquete-offline.sh, no hace falta root ni Docker):
#   ./instalar-paquete-offline.sh --listar <docker-compose.yml>
#     imprime líneas "imagen<TAB>servicio<TAB>referencia" y "build<TAB>servicio<TAB>contexto".
#
# Por qué el override: los compose fijan las imágenes por digest ("mysql:8.0.46@sha256:..."). Una imagen
# cargada con `docker load` NO conserva el digest de origen (queda sin RepoDigests), así que Docker
# intentaría descargarla y en el laboratorio fallaría. El docker-compose.override.yml que se escribe aquí
# (Compose lo lee solo, junto al docker-compose.yml, cuando deploy.sh ejecuta `docker compose up -d`)
# sustituye cada referencia por su etiqueta sin digest y pone pull_policy: never, de modo que un
# olvido falle con un error claro en vez de intentar salir a Internet. La imagen de OpenVPMS
# (que el compose construye con `build:`) se sustituye por la ya construida en el paquete.

set -euo pipefail

# ---------------------------------------------------------------------------------------------
# Modo --listar: parser mínimo del compose (awk, sin dependencias). Lee el YAML tal como está en el repo.
# Reconoce `image: ref`, `image: &ancla ref` (guarda el ancla) e `image: *ancla`, y `build:` a nivel de servicio.
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

# ---------------------------------------------------------------------------------------------
PAQUETE="${PAQUETE:-$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)}"
NOMBRE_PROYECTO="UD.RedesCorporativaa.ProyectoFinak"
# Si se ejecuta con sudo, el proyecto va al home de quien invocó sudo, no al de root (los tutoriales hacen `cd UD.Redes.../docker/pcN`).
USUARIO_REAL="${SUDO_USER:-root}"
HOME_REAL="$(getent passwd "${USUARIO_REAL}" | cut -d: -f6)"
DESTINO="${DESTINO:-${HOME_REAL}/${NOMBRE_PROYECTO}}"

ok()   { echo "  [OK]  $*"; }
aviso(){ echo "  [AVISO] $*" >&2; }
fallo(){ echo "  [FALLO] $*" >&2; exit 1; }
paso() { echo; echo "== $* =="; }

[ "$(id -u)" -eq 0 ] || fallo "Ejecuta con sudo: sudo ./instalar.sh"
[ -f "${PAQUETE}/MANIFEST.sha256" ] || fallo "No encuentro ${PAQUETE}/MANIFEST.sha256: PAQUETE no apunta a la carpeta del paquete."

# --- 1. Compatibilidad con el paquete ----------------------------------------------------------
paso "1/5 Comprobando que el paquete es para este PC"
. "${PAQUETE}/PAQUETE.env"   # define UBUNTU_PAQUETE, ARQ_PAQUETE, FECHA_PAQUETE, COMMIT_PAQUETE
. /etc/os-release
ARQ_LOCAL="$(dpkg --print-architecture)"
[ "${VERSION_ID:-}" = "${UBUNTU_PAQUETE}" ] || fallo "Este PC es Ubuntu ${VERSION_ID:-?} y el paquete es para Ubuntu ${UBUNTU_PAQUETE}. Los .deb son específicos de la versión: hay que rehacer el paquete."
[ "${ARQ_LOCAL}" = "${ARQ_PAQUETE}" ]      || fallo "Este PC es ${ARQ_LOCAL} y el paquete es ${ARQ_PAQUETE}."
ok "Ubuntu ${VERSION_ID} / ${ARQ_LOCAL}; paquete del ${FECHA_PAQUETE}, commit ${COMMIT_PAQUETE}"

# --- 2. Integridad -----------------------------------------------------------------------------
paso "2/5 Verificando checksums (puede tardar: son varios GB)"
( cd "${PAQUETE}" && sha256sum --quiet -c MANIFEST.sha256 ) || fallo "Algún archivo del paquete está corrupto o falta (copia incompleta del USB). Vuelve a copiar el paquete."
ok "todos los archivos coinciden con MANIFEST.sha256"

# --- 3. Docker ---------------------------------------------------------------------------------
paso "3/5 Instalando Docker Engine desde los .deb (sin red)"
if command -v docker >/dev/null 2>&1 && docker compose version >/dev/null 2>&1; then
  ok "Docker y el plugin compose ya estaban instalados: $(docker --version)"
else
  # apt resuelve el orden entre los .deb locales; --no-download impide que salga a la red.
  # Si apt rechazara algún .deb por un conflicto de versiones con lo ya instalado, ver "Si falla" en docs/paquete-offline-fase0.md.
  apt-get install -y --no-download --no-install-recommends "${PAQUETE}"/debs/*.deb \
    || fallo "apt no pudo instalar los .deb. Lee el error de arriba; no intentes 'apt update' (no hay Internet)."
fi
systemctl enable --now docker || fallo "El servicio docker no arrancó (journalctl -u docker)."
docker info >/dev/null 2>&1 || fallo "'docker info' falla: el motor no responde."
docker compose version >/dev/null 2>&1 || fallo "Falta el plugin docker compose."
ok "$(docker --version) — $(docker compose version)"
if [ -n "${SUDO_USER:-}" ] && ! id -nG "${SUDO_USER}" | grep -qw docker; then
  usermod -aG docker "${SUDO_USER}" && ok "${SUDO_USER} añadido al grupo docker (vale tras cerrar sesión y volver a entrar; los deploy.sh se ejecutan con sudo igualmente)"
fi

# --- 4. Imágenes -------------------------------------------------------------------------------
paso "4/5 Cargando las imágenes (docker load)"
# INVENTARIO.tsv: referencia_con_etiqueta <TAB> referencia_del_compose <TAB> id_de_imagen <TAB> fichero <TAB> bytes <TAB> sha256_del_tar
while IFS=$'\t' read -r etiqueta _compose_ref id fichero _bytes _sha; do
  [ -n "${etiqueta}" ] || continue
  [[ "${etiqueta}" == \#* ]] && continue
  echo "  -> ${etiqueta}"
  docker load -i "${PAQUETE}/imagenes/${fichero}" >/dev/null || fallo "docker load falló con ${fichero}."
  docker image inspect "${etiqueta}" >/dev/null 2>&1 || fallo "Tras cargar ${fichero} no existe la etiqueta ${etiqueta}."
  actual="$(docker image inspect --format '{{.Id}}' "${etiqueta}")"
  [ "${actual}" = "${id}" ] || aviso "${etiqueta}: el ID (${actual}) difiere del registrado (${id}). Es normal si el almacén de imágenes de este Docker no es el del PC que armó el paquete; los checksums del paso 2 ya validaron el contenido."
done < "${PAQUETE}/imagenes/INVENTARIO.tsv"
ok "imágenes cargadas"

# --- 5. Proyecto y overrides -------------------------------------------------------------------
paso "5/5 Dejando el proyecto en ${DESTINO} y escribiendo los overrides"
if [ -e "${DESTINO}" ]; then
  fallo "${DESTINO} ya existe. No lo piso: muévelo o indica otro DESTINO=... (si es una instalación previa y quieres rehacerla, bórrala tú a mano)."
fi
mkdir -p "$(dirname "${DESTINO}")"
tar -xzf "${PAQUETE}/proyecto.tar.gz" -C "$(dirname "${DESTINO}")"
[ -d "${DESTINO}/docker" ] || fallo "proyecto.tar.gz no contiene ${NOMBRE_PROYECTO}/docker (¿se extrajo con otro nombre?)."
chown -R "${USUARIO_REAL}:${USUARIO_REAL}" "${DESTINO}"

for compose in "${DESTINO}"/docker/pc*/docker-compose.yml; do
  carpeta="$(dirname "${compose}")"
  override="${carpeta}/docker-compose.override.yml"
  {
    echo "# Generado por instalar-paquete-offline.sh — NO editar. Sustituye las referencias por digest por su etiqueta"
    echo "# (docker load no conserva el digest) y prohíbe descargar imágenes. Borrar este fichero devuelve el compose original."
    echo "services:"
  } > "${override}"
  while IFS=$'\t' read -r tipo servicio valor; do
    if [ "${tipo}" = "imagen" ]; then
      etiqueta="${valor%%@*}"
      grep -q "^${etiqueta}"$'\t' "${PAQUETE}/imagenes/INVENTARIO.tsv" \
        || fallo "El compose ${compose##*/docker/} usa ${etiqueta} (servicio ${servicio}) y el paquete NO la lleva: el paquete se armó con otro commit. Hay que rehacerlo."
      printf '  %s:\n    image: %s\n    pull_policy: never\n' "${servicio}" "${etiqueta}" >> "${override}"
    else
      construida="reservaviva/${servicio}:fase0"
      grep -q "^${construida}"$'\t' "${PAQUETE}/imagenes/INVENTARIO.tsv" \
        || fallo "El servicio ${servicio} se construye (build: ${valor}) y el paquete NO lleva la imagen ${construida}."
      # Con image: + build:, Compose usa la imagen local si existe y solo construye si falta (aquí no faltará).
      printf '  %s:\n    image: %s\n' "${servicio}" "${construida}" >> "${override}"
    fi
  done < <(listar_compose "${compose}")
  chown "${USUARIO_REAL}:${USUARIO_REAL}" "${override}"
  ok "${override#"${DESTINO}"/}"
done

paso "Listo"
echo "Proyecto en: ${DESTINO}"
echo "Siguiente: seguir el tutorial del PC (Paso: identificar la tarjeta de red y copiar .env.example a .env)."
echo "Comprobación que no necesita red, en cada docker/pcN-*/:  docker compose config --quiet && echo compose-ok"
