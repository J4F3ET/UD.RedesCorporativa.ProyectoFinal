#!/usr/bin/env bash
# PERFIL L3 (el switch enruta) - PC-3: crea las sub-interfaces 802.1Q de VLAN 40 (RRHH) y VLAN 99
# (Infraestructura) sobre el puerto físico conectado en modo TRUNK al switch.
#
# Las sub-interfaces NO llevan dirección IP: solo son el "parent" de las redes macvlan de los contenedores
# (docker/pc3-administracion-infra/docker-compose.yml). Las 10.10.40.1 y 10.10.99.1 son el gateway de cada
# VLAN y pertenecen a las SVI del switch. PC-3 no enruta en este perfil (sin ip_forward ni nftables).
#
# Idempotente: si una sub-interfaz ya existe la reutiliza, y si tiene direcciones de una versión anterior
# de este script las quita. Pensado para correr a mano o desde el servicio systemd en cada arranque.
#
# Excepción opcional: IP_GESTION (en el .env) añade UNA dirección de gestión en UNA sola de las dos VLAN
# (para copiar ca.crt por scp y hacer ping). En ambas a la vez el script se niega: ver diseno-red/comun/ip-gestion.sh.
#
# Uso: IFACE=enp2s0 ./setup-vlans-pc3.sh   (deploy.sh exporta IFACE desde el .env)

set -euo pipefail

source "$(dirname "${BASH_SOURCE[0]}")/../../comun/ip-gestion.sh"

: "${IFACE:?definir IFACE (nombre real de la tarjeta de red de PC-3, p. ej. enp2s0) en el .env}"

for vlan in 40 99; do
  sub="${IFACE}.${vlan}"
  if ip link show "${sub}" &>/dev/null; then
    echo "${sub} ya existe, se reutiliza."
  else
    ip link add link "${IFACE}" name "${sub}" type vlan id "${vlan}"
  fi
  ip addr flush dev "${sub}"   # solo es parent de macvlan: sin IP
  ip link set "${sub}" up
done

# IP de gestión opcional (IP_GESTION del .env; vacía = sin IP). Ver diseno-red/comun/ip-gestion.sh.
gestion_aplicar "${IP_GESTION:-}" "40:${IFACE}.40" "99:${IFACE}.99"

echo "Sub-interfaces activas:"
ip -brief addr show | grep "^${IFACE}\." || true
