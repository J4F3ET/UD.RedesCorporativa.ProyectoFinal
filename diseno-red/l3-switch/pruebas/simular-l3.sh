#!/usr/bin/env bash
# Simula el perfil L3 (switch con SVIs y ACL) en un solo host y recorre la matriz de segmentación.
# El bridge con vlan_filtering hace de switch 802.1Q; las interfaces vlanNN del bridge con IP .1 son las
# SVI; las reglas nftables de la matriz van en el namespace del switch. Ver README.md de esta carpeta.
#
# Debe correr como root dentro de un contenedor --privileged --network none (ver README.md).

set -euo pipefail
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
COMUN="$DIR/../../comun"

export RV_PERFIL=l3
# shellcheck source=../../comun/lib-topologia.sh
source "$COMUN/lib-topologia.sh"

trap topo_limpiar EXIT
topo_crear
matriz_aplicar_nft

echo "--- Puertos del switch (bridge vlan show) ---"
ns sw bridge vlan show | sed 's/^/  /'
echo
bash "$COMUN/probar-matriz.sh"
