#!/usr/bin/env bash
# Ejecutar UNA sola vez en PC-3 (Servidor de Administración e Infraestructura)
# antes de "docker compose up".
#
# Caso normal (switch L3 con SVIs): PC-3 solo necesita sus propias VLANs,
# 40 (RRHH) y 99 (Infraestructura).
#
# Caso fallback (switch L2 puro): PC-3 además actúa como router-on-a-stick
# central para TODA la matriz de segmentación (ver docs/arquitectura-3-equipos-departamentos.md,
# sección 5), por lo que necesita sub-interfaces extra para las VLANs que
# físicamente viven en PC-1 y PC-2. En ese caso el puerto trunk de PC-3 en
# el switch debe permitir las 5 VLANs, no solo 40 y 99.

set -euo pipefail

IFACE="eth0"   # ajustar al nombre real de la interfaz física de PC-3
FALLBACK_L2="${FALLBACK_L2:-false}"   # exportar FALLBACK_L2=true si el switch es solo L2

# VLANs propias de PC-3 (siempre se crean)
for vlan_if_ip in "40:10.10.40.1/24" "99:10.10.99.1/24"; do
  vlan="${vlan_if_ip%%:*}"
  ip="${vlan_if_ip##*:}"
  sub="${IFACE}.${vlan}"

  ip link add link "${IFACE}" name "${sub}" type vlan id "${vlan}"
  ip addr add "${ip}" dev "${sub}"
  ip link set "${sub}" up
done

if [ "${FALLBACK_L2}" = "true" ]; then
  echo "FALLBACK_L2=true: creando sub-interfaces de enrutamiento para VLAN 10/20/30"
  # Sin contenedores enganchados aquí: solo se usan para enrutar entre VLANs.
  for vlan_if_ip in "10:10.10.10.1/24" "20:10.10.20.1/24" "30:10.10.30.1/24"; do
    vlan="${vlan_if_ip%%:*}"
    ip="${vlan_if_ip##*:}"
    sub="${IFACE}.${vlan}"

    ip link add link "${IFACE}" name "${sub}" type vlan id "${vlan}"
    ip addr add "${ip}" dev "${sub}"
    ip link set "${sub}" up
  done

  sysctl -w net.ipv4.ip_forward=1
  echo "Recuerda aplicar scripts/firewall-pc3-matriz.sh para filtrar el forwarding."
fi

echo "Sub-interfaces creadas:"
ip -brief addr show | grep "${IFACE}\."
