#!/usr/bin/env bash
# Simula el perfil L2 (switch sin capa 3; PC-3 hace de router-on-a-stick) en un solo host y recorre la
# matriz de segmentación. El bridge con vlan_filtering NO lleva ninguna IP; PC-3 crea eth0.10/20/30/40/99
# con la IP .1, habilita ip_forward y aplica las reglas nftables de la matriz. Ver README.md de esta carpeta.
#
# Variables:
#   RV_L2_GATEWAY=parent|macvlan  dónde pone PC-3 la IP .1 (por defecto parent: en eth0.NN, como hoy
#                                 scripts/setup-vlans-pc3.sh). macvlan: en una interfaz macvlan hermana.
#   RV_SETUP_PC3=<ruta>           usa ese setup-vlans-pc3.sh (perfil L2) en vez de crear los gateways la
#                                 biblioteca; se ejecuta dentro de PC-3 con IFACE=eth0.
#   RV_FIREWALL_PC3=<ruta>        usa ese script de firewall en vez de las reglas de la biblioteca; se ejecuta
#                                 dentro de PC-3 con IFACE=eth0. Se leen los contadores de su tabla
#                                 (RV_NFT_TABLA, por defecto reservaviva) y se exige que cada bloqueo suba
#                                 SU regla, igual que con las reglas propias.
#
# Debe correr como root dentro de un contenedor --privileged --network none (ver README.md).

set -euo pipefail
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
COMUN="$DIR/../../comun"

export RV_PERFIL=l2
export RV_L2_GATEWAY="${RV_L2_GATEWAY:-parent}"
# shellcheck source=../../comun/lib-topologia.sh
source "$COMUN/lib-topologia.sh"

trap topo_limpiar EXIT
topo_crear

if [ -n "${RV_FIREWALL_PC3:-}" ]; then
  echo "--- Aplicando el firewall externo en PC-3: $RV_FIREWALL_PC3 ---"
  export RV_NFT_TABLA="${RV_NFT_TABLA:-reservaviva}"
  IFACE=eth0 ns pc3 bash "$RV_FIREWALL_PC3"
else
  matriz_aplicar_nft
fi

echo "--- Puertos del switch (bridge vlan show) ---"
ns sw bridge vlan show | sed 's/^/  /'
echo
rc=0
bash "$COMUN/probar-matriz.sh" || rc=$?
if [ -n "${RV_FIREWALL_PC3:-}" ]; then
  echo
  echo "--- nft list table inet ${RV_NFT_TABLA} (namespace de PC-3, tras la prueba) ---"
  ns pc3 nft list table inet "$RV_NFT_TABLA" | sed 's/^/  /'
fi
exit $rc
