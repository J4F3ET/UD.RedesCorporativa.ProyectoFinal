#!/usr/bin/env bash
# Biblioteca (se usa con `source`, no se ejecuta) que monta en UN solo host Linux una réplica de la
# topología del laboratorio con network namespaces:
#
#   rv-sw   = el switch: un bridge con vlan_filtering 1 (802.1Q por software)
#   rv-pc1  = PC-1, puerto ACCESS en VLAN 10 (PVID 10 sin etiqueta)
#   rv-pc2  = PC-2, puerto TRUNK con VLAN 20 y 30 (sub-interfaces eth0.20/eth0.30)
#   rv-pc3  = PC-3, puerto TRUNK con VLAN 40 y 99 (más 10/20/30 en el perfil L2)
#   rv-cNN  = un contenedor por VLAN NN, colgado de su PC con macvlan (igual que los compose reales)
#
# Perfiles (variable RV_PERFIL):
#   l3 : el bridge lleva interfaces vlanNN con la IP .1 de cada VLAN y hace forwarding; las ACL de la
#        matriz van en rv-sw (es lo que haría un switch L3 con SVIs).
#   l2 : el bridge NO lleva IP. PC-3 crea eth0.10/20/30/40/99 con la IP .1, habilita ip_forward y aplica
#        la matriz (router-on-a-stick). RV_L2_GATEWAY controla dónde se pone la IP .1 en PC-3:
#          parent  (por defecto) -> en la propia sub-interfaz eth0.NN, como hace hoy scripts/setup-vlans-pc3.sh
#          macvlan               -> en una interfaz macvlan "hermana" de las de los contenedores de PC-3
#
# Requiere root con CAP_NET_ADMIN (dentro de un contenedor: --privileged), iproute2, nftables, socat y bash.
# Ver despliegue/l3-switch/pruebas/README.md para el comando exacto en Windows.

RV_PERFIL="${RV_PERFIL:-l3}"
RV_L2_GATEWAY="${RV_L2_GATEWAY:-parent}"

# VLAN de negocio, VLAN de infraestructura y IP del servicio de cada VLAN (.10, igual que los compose).
RV_NEGOCIO=(10 20 30 40)
RV_INFRA=99
RV_VLANS=(10 20 30 40 99)
rv_ip() { echo "10.10.$1.10"; }
rv_gw() { echo "10.10.$1.1"; }

# Puerto de aplicación que responde en cada destino. Los de VLAN99 son LDAPS y LDAP.
RV_PUERTO_NEGOCIO=8080
RV_PUERTO_INFRA=636

# Interfaz (dentro del router) por la que entra/sale cada VLAN: la usan las reglas nftables.
RV_ROUTER_NS="${RV_ROUTER_NS:-}"
RV_IFACE_FMT="${RV_IFACE_FMT:-}"

ns() { local n="$1"; shift; ip netns exec "rv-${n}" "$@"; }

topo_limpiar() {
  pkill -x socat 2>/dev/null || true
  local n
  for n in $(ip netns list 2>/dev/null | awk '/^rv-/{print $1}'); do ip netns del "$n" 2>/dev/null || true; done
}

# Crea un veth entre rv-sw y rv-pcN (en el PC queda con el nombre eth0).
_cable() {
  local pc="$1"
  ip link add "p${pc}-sw" type veth peer name "p${pc}-eth"
  ip link set "p${pc}-sw" netns rv-sw
  ip link set "p${pc}-eth" netns "rv-pc${pc}"
  ip -n "rv-pc${pc}" link set "p${pc}-eth" name eth0
  ip -n rv-sw link set "p${pc}-sw" master br0 up
  ip -n "rv-pc${pc}" link set eth0 up
}

# Contenedor de una VLAN: macvlan sobre la interfaz padre indicada, dentro del namespace rv-cNN.
_contenedor() {
  local pc="$1" vlan="$2" padre="$3" mv="mv${2}"
  ip -n "rv-pc${pc}" link add link "$padre" name "$mv" type macvlan mode bridge
  ip -n "rv-pc${pc}" link set "$mv" netns "rv-c${vlan}"
  ip -n "rv-c${vlan}" link set "$mv" name eth0
  ip -n "rv-c${vlan}" addr add "$(rv_ip "$vlan")/24" dev eth0
  ip -n "rv-c${vlan}" link set eth0 up
  ip -n "rv-c${vlan}" route add default via "$(rv_gw "$vlan")"
}

_subif() { # _subif pc vlan  -> eth0.VLAN
  ip -n "rv-pc${1}" link add link eth0 name "eth0.${2}" type vlan id "$2"
  ip -n "rv-pc${1}" link set "eth0.${2}" up
}

_escucha() { # _escucha vlan puerto
  ns "c$1" socat "TCP-LISTEN:$2,fork,reuseaddr,bind=$(rv_ip "$1")" SYSTEM:"echo ok" >/dev/null 2>&1 &
}

topo_crear() {
  topo_limpiar
  local n v
  for n in sw pc1 pc2 pc3 c10 c20 c30 c40 c99; do
    ip netns add "rv-$n"
    ip -n "rv-$n" link set lo up
    ns "$n" sysctl -qw net.ipv4.conf.all.rp_filter=0 net.ipv4.conf.default.rp_filter=0
  done

  # --- El switch: bridge 802.1Q sin VLAN por defecto (cada puerto solo lleva las que se le dan) ---
  ip -n rv-sw link add br0 type bridge vlan_filtering 1 vlan_default_pvid 0
  ip -n rv-sw link set br0 up
  _cable 1; _cable 2; _cable 3
  ns sw bridge vlan add dev p1-sw vid 10 pvid untagged      # ACCESS
  ns sw bridge vlan add dev p2-sw vid 20                    # TRUNK PC-2
  ns sw bridge vlan add dev p2-sw vid 30
  ns sw bridge vlan add dev p3-sw vid 40                    # TRUNK PC-3
  ns sw bridge vlan add dev p3-sw vid 99
  if [ "$RV_PERFIL" = "l2" ]; then                          # PC-3 es el router: ve las 5 VLAN
    for v in 10 20 30; do ns sw bridge vlan add dev p3-sw vid "$v"; done
  fi

  # --- PC-1 (access, sin etiqueta), PC-2 y PC-3 (trunk) y sus contenedores macvlan ---
  _contenedor 1 10 eth0
  _subif 2 20; _subif 2 30; _contenedor 2 20 eth0.20; _contenedor 2 30 eth0.30
  _subif 3 40; _subif 3 99; _contenedor 3 40 eth0.40; _contenedor 3 99 eth0.99

  case "$RV_PERFIL" in
    l3)
      for v in "${RV_VLANS[@]}"; do
        ns sw bridge vlan add dev br0 vid "$v" self
        ip -n rv-sw link add link br0 name "vlan${v}" type vlan id "$v"
        ip -n rv-sw addr add "$(rv_gw "$v")/24" dev "vlan${v}"
        ip -n rv-sw link set "vlan${v}" up
      done
      ns sw sysctl -qw net.ipv4.ip_forward=1
      RV_ROUTER_NS=sw; RV_IFACE_FMT="vlan%s"
      ;;
    l2)
      for v in 10 20 30; do _subif 3 "$v"; done
      for v in "${RV_VLANS[@]}"; do
        if [ "$RV_L2_GATEWAY" = "macvlan" ]; then
          ip -n rv-pc3 link add link "eth0.${v}" name "gw${v}" type macvlan mode bridge
          ip -n rv-pc3 addr add "$(rv_gw "$v")/24" dev "gw${v}"
          ip -n rv-pc3 link set "gw${v}" up
        else
          ip -n rv-pc3 addr add "$(rv_gw "$v")/24" dev "eth0.${v}"
        fi
      done
      ns pc3 sysctl -qw net.ipv4.ip_forward=1
      # Con el gateway en una macvlan hermana, la interfaz padre eth0.NN (sin IP) contestaria tambien al ARP de la
      # IP .1 ("ARP flux") y los paquetes entrarian por eth0.NN en vez de gwNN: las reglas por interfaz no casarian.
      if [ "$RV_L2_GATEWAY" = "macvlan" ]; then ns pc3 sysctl -qw net.ipv4.conf.all.arp_ignore=1 net.ipv4.conf.all.arp_announce=2; fi
      RV_ROUTER_NS=pc3
      if [ "$RV_L2_GATEWAY" = "macvlan" ]; then RV_IFACE_FMT="gw%s"; else RV_IFACE_FMT="eth0.%s"; fi
      ;;
    *) echo "RV_PERFIL debe ser l3 o l2" >&2; return 1 ;;
  esac

  # Servicios reales: cada contenedor responde "ok" por TCP; el de VLAN99 además en 636 (LDAPS).
  for v in "${RV_VLANS[@]}"; do _escucha "$v" "$RV_PUERTO_NEGOCIO"; done
  _escucha "$RV_INFRA" "$RV_PUERTO_INFRA"
  export RV_PERFIL RV_L2_GATEWAY RV_ROUTER_NS RV_IFACE_FMT
  sleep 1
}

# Aplica en el router (rv-sw en L3, rv-pc3 en L2) las reglas de la matriz de
# docs/arquitectura-3-equipos-departamentos.md (sección 4), con un contador por regla.
matriz_aplicar_nft() {
  local a b ia ib
  {
    echo 'table inet matriz {'
    echo '  chain forward {'
    echo '    type filter hook forward priority 0; policy drop;'
    echo '    ct state established,related counter accept comment "est-rel"'
    for a in "${RV_NEGOCIO[@]}"; do
      ia=$(printf "$RV_IFACE_FMT" "$a"); ib=$(printf "$RV_IFACE_FMT" "$RV_INFRA")
      echo "    iifname \"$ia\" oifname \"$ib\" counter accept comment \"permite-$a-99\""
      echo "    iifname \"$ib\" oifname \"$ia\" counter accept comment \"permite-99-$a\""
    done
    for a in "${RV_NEGOCIO[@]}"; do
      for b in "${RV_NEGOCIO[@]}"; do
        [ "$a" = "$b" ] && continue
        ia=$(printf "$RV_IFACE_FMT" "$a"); ib=$(printf "$RV_IFACE_FMT" "$b")
        echo "    iifname \"$ia\" oifname \"$ib\" counter drop comment \"drop-$a-$b\""
      done
    done
    echo '    counter drop comment "drop-resto"'
    echo '  }'
    echo '}'
  } | ns "$RV_ROUTER_NS" nft -f -
}

# Salida "comentario paquetes bytes" de cada regla con contador, del router.
matriz_contadores() {
  ns "$RV_ROUTER_NS" nft list chain inet matriz forward 2>/dev/null |
    sed -n 's/.*packets \([0-9]*\) bytes \([0-9]*\).*comment "\([^"]*\)".*/\3 \1 \2/p'
}
