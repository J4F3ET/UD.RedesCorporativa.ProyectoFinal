#!/usr/bin/env bash
# PERFIL L2 (el switch solo conmuta) - PC-3: además de alojar VLAN 40 y 99, es el ROUTER CENTRAL de las
# cinco VLANs (el switch no enruta). El puerto trunk de PC-3 en el switch debe permitir 10, 20, 30, 40 y 99.
#
#   - VLAN 10, 20 y 30 (sin contenedores en PC-3): sub-interfaz 802.1Q con la IP .1 (gateway de la VLAN).
#   - VLAN 40 y 99 (con contenedores macvlan en PC-3): la sub-interfaz es el "parent" de macvlan y NO lleva
#     IP; el gateway .1 va en una interfaz macvlan "gw40"/"gw99" (modo bridge) colgada de ella. Motivo: un
#     macvlan no permite que el host hable con sus propios hijos por el "parent" (el tráfico sale al switch
#     y no vuelve por el mismo puerto), así que el router de PC-3 no alcanzaría a LDAP/DNS/NTP ni a ERPNext
#     de su propia máquina. Con gw40/gw99 como hermana de los contenedores, sí.
#   - Activa net.ipv4.ip_forward. El filtrado de la matriz lo aplica firewall-pc3-matriz.sh.
#
# Idempotente: reutiliza lo que ya existe y deja las direcciones en el estado esperado (ip addr replace).
# Pensado para correr a mano o desde el servicio systemd en cada arranque.
#
# Uso: IFACE=enp2s0 ./setup-vlans-pc3.sh   (deploy.sh exporta IFACE desde el .env)

set -euo pipefail

: "${IFACE:?definir IFACE (nombre real de la tarjeta de red de PC-3, p. ej. enp2s0) en el .env}"

crear_subif() {  # crear_subif <vlan>: sub-interfaz 802.1Q levantada
  local sub="${IFACE}.${1}"
  if ip link show "${sub}" &>/dev/null; then
    echo "${sub} ya existe, se reutiliza."
  else
    ip link add link "${IFACE}" name "${sub}" type vlan id "${1}"
  fi
  ip link set "${sub}" up
}

# VLAN sin contenedores en PC-3: la sub-interfaz lleva el gateway.
for vlan in 10 20 30; do
  crear_subif "${vlan}"
  ip addr replace "10.10.${vlan}.1/24" dev "${IFACE}.${vlan}"
done

# VLAN con contenedores macvlan en PC-3: parent sin IP + interfaz gwNN con el gateway.
for vlan in 40 99; do
  crear_subif "${vlan}"
  ip addr flush dev "${IFACE}.${vlan}"
  gw="gw${vlan}"
  if ip link show "${gw}" &>/dev/null; then
    echo "${gw} ya existe, se reutiliza."
  else
    ip link add link "${IFACE}.${vlan}" name "${gw}" type macvlan mode bridge
  fi
  ip addr replace "10.10.${vlan}.1/24" dev "${gw}"
  ip link set "${gw}" up
done

echo 1 > /proc/sys/net/ipv4/ip_forward   # equivale a sysctl -w net.ipv4.ip_forward=1
if [ -n "${IP_GESTION:-}" ]; then
  echo "IP_GESTION se ignora en el perfil l2: PC-3 ya es alcanzable por sus gateways (p. ej. 10.10.99.1 desde las demás VLAN)."
fi
echo "ip_forward=1. Aplica ahora firewall-pc3-matriz.sh (deploy.sh lo hace solo)."

echo "Interfaces de enrutamiento activas:"
ip -brief addr show | grep -E "^(${IFACE}\.|gw)" || true
