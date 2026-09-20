#!/usr/bin/env bash
# PERFIL L3 (el switch enruta) - PC-2: crea las sub-interfaces 802.1Q de VLAN 20 (Taquilla) y VLAN 30
# (Logística) sobre el puerto físico conectado en modo TRUNK al switch.
#
# Las sub-interfaces NO llevan dirección IP: solo son el "parent" de las redes macvlan de los contenedores
# (docker/pc2-operaciones/docker-compose.yml). Las 10.10.20.1 y 10.10.30.1 son el gateway de cada VLAN y
# pertenecen a las SVI del switch; si PC-2 también se las pusiera, habría dos equipos con la misma IP.
#
# Idempotente: si una sub-interfaz ya existe la reutiliza, y si tiene direcciones de una versión anterior
# de este script las quita. Pensado para correr a mano o desde el servicio systemd en cada arranque.
#
# Uso: IFACE=enp2s0 ./setup-vlans-pc2.sh   (deploy.sh exporta IFACE desde el .env)

set -euo pipefail

: "${IFACE:?definir IFACE (nombre real de la tarjeta de red de PC-2, p. ej. enp2s0) en el .env}"

for vlan in 20 30; do
  sub="${IFACE}.${vlan}"
  if ip link show "${sub}" &>/dev/null; then
    echo "${sub} ya existe, se reutiliza."
  else
    ip link add link "${IFACE}" name "${sub}" type vlan id "${vlan}"
  fi
  ip addr flush dev "${sub}"   # solo es parent de macvlan: sin IP
  ip link set "${sub}" up
done

echo "Sub-interfaces activas (sin IP):"
ip -brief addr show | grep "^${IFACE}\." || true
