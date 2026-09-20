#!/usr/bin/env bash
# Biblioteca común (se hace "source", no se ejecuta): valida PERFIL y deja en PERFIL_DIR la carpeta
# despliegue/<perfil>/ que corresponde. La usan los deploy.sh de los tres PCs.
#
#   PERFIL=l3  -> despliegue/l3-switch/    el switch enruta entre VLANs y aplica las ACL (tiene SVIs)
#   PERFIL=l2  -> despliegue/l2-fallback/  el switch solo conmuta; PC-3 enruta y filtra con nftables
#
# Requiere REPO_ROOT definido por quien la incluye.

: "${REPO_ROOT:?REPO_ROOT no definido}"

case "${PERFIL:-}" in
  l3) PERFIL_DIR="${REPO_ROOT}/despliegue/l3-switch" ;;
  l2) PERFIL_DIR="${REPO_ROOT}/despliegue/l2-fallback" ;;
  *)
    echo "PERFIL='${PERFIL:-}' no es válido: en el .env de esta carpeta debe ser PERFIL=l2 o PERFIL=l3." >&2
    echo "  l3 -> el switch del laboratorio tiene SVIs (interface Vlan10, 20...) y enruta entre VLANs." >&2
    echo "  l2 -> el switch solo conmuta VLANs (no enruta); PC-3 hace de router." >&2
    echo "Si no sabes cuál es, mira el tutorial o pregunta al encargado del switch antes de continuar." >&2
    exit 1
    ;;
esac

if [ ! -d "${PERFIL_DIR}/scripts" ]; then
  echo "No existe ${PERFIL_DIR}/scripts (¿repositorio incompleto?)." >&2
  exit 1
fi
