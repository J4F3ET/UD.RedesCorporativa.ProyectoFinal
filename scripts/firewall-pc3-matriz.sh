#!/usr/bin/env bash
# Reglas nftables que implementan la matriz de segmentación de
# docs/arquitectura-3-equipos-departamentos.md (sección 4).
#
# Aplicar SOLO en el escenario fallback de switch L2 puro, en PC-3,
# después de correr "FALLBACK_L2=true scripts/setup-vlans-pc3.sh".
# Si el switch es L3, estas ACLs se configuran en el switch, no aquí.
#
# Política: cada VLAN de negocio (10, 20, 30, 40) solo puede hablar con
# VLAN 99 (LDAP/DNS/NTP); el tráfico entre VLANs de negocio está bloqueado,
# incluida VLAN20<->VLAN30 aunque compartan el mismo PC-2 físico.

set -euo pipefail

nft flush ruleset

nft add table inet filter
nft add chain inet filter forward '{ type filter hook forward priority 0; policy drop; }'

# Permitir tráfico ya establecido/relacionado en ambas direcciones.
nft add rule inet filter forward ct state established,related accept

BUSINESS_VLANS=(10 20 30 40)
IFACE_PREFIX="eth0"

# Cada VLAN de negocio <-> VLAN99: permitido (LDAP/DNS/NTP).
for vlan in "${BUSINESS_VLANS[@]}"; do
  nft add rule inet filter forward iifname "${IFACE_PREFIX}.${vlan}" oifname "${IFACE_PREFIX}.99" accept
  nft add rule inet filter forward iifname "${IFACE_PREFIX}.99" oifname "${IFACE_PREFIX}.${vlan}" accept
done

# Todo lo demás (VLAN de negocio <-> otra VLAN de negocio) queda bloqueado
# por la política por defecto (policy drop) del chain forward.

echo "Reglas nftables aplicadas. Verificar con: nft list ruleset"
