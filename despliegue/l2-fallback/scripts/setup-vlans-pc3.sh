#!/usr/bin/env bash
# PERFIL L2 (el switch solo conmuta) - PC-3: además de alojar VLAN 40 y 99, es el ROUTER CENTRAL de las
# cinco VLANs (el switch no enruta). El puerto trunk de PC-3 en el switch debe permitir 10, 20, 30, 40 y 99.
#
#   - Las cinco VLAN: la sub-interfaz 802.1Q <IFACE>.NN NO lleva IP (en 40 y 99 es el "parent" de macvlan de
#     los contenedores) y el gateway .1 va en una interfaz macvlan "gwNN" (modo bridge) colgada de ella.
#     Motivo: un macvlan no permite que el host hable con sus propios hijos por el "parent" (el tráfico sale
#     al switch y no vuelve por el mismo puerto), así que con la .1 en <IFACE>.40/.99 el router de PC-3 no
#     alcanzaría a LDAP/DNS/NTP ni a ERPNext de su propia máquina. Con gwNN como hermana de los contenedores,
#     sí. Se usa gwNN también en 10/20/30 (aunque ahí no haya contenedores) para tener una sola regla.
#   - arp_ignore=1 y arp_announce=2 (ver más abajo): sin ellos, "ARP flux".
#   - Activa net.ipv4.ip_forward. El filtrado de la matriz lo aplica firewall-pc3-matriz.sh, que casa por
#     nombre de interfaz (gwNN).
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

# Parent sin IP + interfaz gwNN con el gateway .1, en las cinco VLAN.
for vlan in 10 20 30 40 99; do
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

# ARP flux: la .1 vive en gwNN, pero <IFACE>.NN (el padre) comparte la dirección física y, por defecto, el
# kernel contesta al ARP de CUALQUIER IP local por cualquier interfaz. Los equipos de la VLAN podrían entonces
# aprender la MAC de <IFACE>.NN como la de su gateway, y sus paquetes entrarían por <IFACE>.NN en vez de gwNN:
# las reglas de firewall-pc3-matriz.sh (que casan por gwNN) no coincidirían y, con política accept, el tráfico
# prohibido PASARÍA en silencio. arp_ignore=1 solo responde si la IP está en la interfaz que recibe la
# petición; arp_announce=2 anuncia siempre con la IP propia de la interfaz de salida.
# Detectado con el simulador de topología (nft monitor trace); confirmar en el PC-3 real.
echo 1 > /proc/sys/net/ipv4/conf/all/arp_ignore
echo 2 > /proc/sys/net/ipv4/conf/all/arp_announce

if [ -n "${IP_GESTION:-}" ]; then
  echo "IP_GESTION se ignora en el perfil l2: PC-3 ya es alcanzable por sus gateways (p. ej. 10.10.99.1 desde las demás VLAN)."
fi
echo "ip_forward=1, arp_ignore=1, arp_announce=2. Aplica ahora firewall-pc3-matriz.sh (deploy.sh lo hace solo)."

echo "Interfaces de enrutamiento activas:"
ip -brief addr show | grep -E "^(${IFACE}\.|gw)" || true
