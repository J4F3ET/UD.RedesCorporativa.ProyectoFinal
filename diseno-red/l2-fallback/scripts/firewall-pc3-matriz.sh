#!/usr/bin/env bash
# PERFIL L2 - PC-3: reglas nftables que implementan la matriz de segmentación de
# diseno-red/arquitectura-3-equipos-departamentos.md (sección 4). Aplicar después de setup-vlans-pc3.sh.
#
# Lógica: política por defecto ACCEPT + una regla de DROP explícita, con contador, por cada celda "Bloqueado"
# de la matriz: las 6 parejas de VLAN de negocio (10-20, 10-30, 10-40, 20-30, 20-40, 30-40) en los dos
# sentidos = 12 reglas. VLAN de negocio <-> VLAN 99 no se toca (permitido). Ventajas frente a "policy drop":
#   - Solo hace match entre interfaces de VLAN, así que no toca el tráfico de Docker (p. ej. los ~12 servicios
#     de ERPNext hablando por su bridge privado pasan por este mismo hook forward).
#   - Cada regla cuenta sus paquetes: "nft -a list ruleset" muestra la evidencia en vivo para la sustentación.
#
# Las reglas casan por gwNN (ver setup-vlans-pc3.sh); ese script fija arp_ignore/arp_announce para que los
# paquetes entren de verdad por gwNN y no por <IFACE>.NN, donde ninguna regla casaría.
#
# Usa una tabla propia (inet reservaviva) que borra y recrea de forma atómica: correrlo dos veces deja el
# mismo resultado y NUNCA se vacía el ruleset completo (borraría las cadenas de Docker).
#
# Docker deja la política FORWARD de iptables en DROP, y un paquete debe ser aceptado por todas las cadenas
# del hook forward. Por eso también se añade (una sola vez) un ACCEPT para 10.10.0.0/16 en DOCKER-USER; el
# bloqueo sigue siendo el de la tabla nft, que es una cadena independiente.
#
# Uso: IFACE=enp2s0 ./firewall-pc3-matriz.sh [--quitar]   (deploy.sh exporta IFACE desde el .env)
#      --quitar elimina la tabla nft y la regla de DOCKER-USER.

set -euo pipefail

: "${IFACE:?definir IFACE (nombre real de la tarjeta de red de PC-3, p. ej. enp2s0) en el .env}"

TABLA="reservaviva"
DOCKER_USER_ARGS=(-s 10.10.0.0/16 -d 10.10.0.0/16 -j ACCEPT)

docker_user_disponible() {
  command -v iptables >/dev/null && iptables -w -n -L DOCKER-USER >/dev/null 2>&1
}

if [ "${1:-}" = "--quitar" ]; then
  nft delete table inet "${TABLA}" 2>/dev/null || true
  if docker_user_disponible; then
    while iptables -w -C DOCKER-USER "${DOCKER_USER_ARGS[@]}" 2>/dev/null; do
      iptables -w -D DOCKER-USER "${DOCKER_USER_ARGS[@]}"
    done
  fi
  echo "Tabla inet ${TABLA} y regla de DOCKER-USER eliminadas."
  exit 0
fi

# Interfaz por la que entra/sale cada VLAN en PC-3: el gateway gwNN de setup-vlans-pc3.sh. Si faltara alguna,
# ninguna regla casaría y la política accept dejaría pasar el tráfico prohibido SIN avisar, así que se exige
# que existan (junto con su parent <IFACE>.NN) antes de aplicar nada.
interfaz_vlan() { echo "gw$1"; }
for v in 10 20 30 40; do
  for n in "${IFACE}.${v}" "$(interfaz_vlan "${v}")"; do
    ip link show "${n}" >/dev/null 2>&1 || {
      echo "No existe la interfaz ${n}: ejecuta antes setup-vlans-pc3.sh (con el mismo IFACE) y reintenta." >&2
      exit 1
    }
  done
done

# Solo ahora (con las interfaces verificadas) se reemplaza la tabla anterior, para no dejar un hueco si algo falla.
nft delete table inet "${TABLA}" 2>/dev/null || true
{
  echo "table inet ${TABLA} {"
  echo "  chain forward {"
  echo "    type filter hook forward priority 0; policy accept;"
  negocio=(10 20 30 40)
  for a in "${negocio[@]}"; do
    for b in "${negocio[@]}"; do
      [ "${a}" = "${b}" ] && continue
      echo "    iifname \"$(interfaz_vlan "${a}")\" oifname \"$(interfaz_vlan "${b}")\" counter drop comment \"VLAN${a} -> VLAN${b} bloqueado\""
    done
  done
  echo "  }"
  echo "}"
} | nft -f -

if docker_user_disponible; then
  iptables -w -C DOCKER-USER "${DOCKER_USER_ARGS[@]}" 2>/dev/null \
    || iptables -w -I DOCKER-USER 1 "${DOCKER_USER_ARGS[@]}"
else
  echo "AVISO: no se encontró la cadena DOCKER-USER (¿Docker sin iniciar?). Si Docker deja FORWARD en DROP," >&2
  echo "       el tráfico entre VLANs no se enrutará; vuelve a ejecutar este script con Docker en marcha." >&2
fi

echo "Reglas aplicadas. Contadores en vivo: nft -a list ruleset   (o: watch -n1 nft list table inet ${TABLA})"
