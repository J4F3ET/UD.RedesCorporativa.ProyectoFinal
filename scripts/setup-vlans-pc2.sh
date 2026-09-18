#!/usr/bin/env bash
# Crea las sub-interfaces 802.1Q para VLAN 20 (Taquilla) y VLAN 30 (Logística)
# sobre el puerto físico conectado en modo TRUNK al switch.
#
# Idempotente: si una sub-interfaz ya existe, la deja tal cual y sigue con
# la siguiente. Pensado para correr tanto a mano como desde
# scripts/systemd/reserva-viva-vlans@.service en cada arranque.
#
# PC-2 NO enruta entre VLANs ni con el resto de la red: solo usa estas
# sub-interfaces como "parent" de las redes macvlan de sus propios
# contenedores. El enrutamiento/filtrado entre VLANs lo hace el switch
# (si es L3) o PC-3 como router-on-a-stick central (si el switch es L2
# puro) — ver docs/arquitectura-3-equipos-departamentos.md, sección 5.

set -euo pipefail

IFACE="${IFACE:-eth0}"   # ajustar al nombre real de la interfaz física de PC-2, p. ej. IFACE=enp2s0

for vlan_if_ip in "20:10.10.20.1/24" "30:10.10.30.1/24"; do
  vlan="${vlan_if_ip%%:*}"
  ip="${vlan_if_ip##*:}"
  sub="${IFACE}.${vlan}"

  if ip link show "${sub}" &>/dev/null; then
    echo "${sub} ya existe, se omite."
  else
    ip link add link "${IFACE}" name "${sub}" type vlan id "${vlan}"
    ip addr add "${ip}" dev "${sub}"
  fi
  ip link set "${sub}" up
done

echo "Sub-interfaces activas:"
ip -brief addr show | grep "${IFACE}\."
