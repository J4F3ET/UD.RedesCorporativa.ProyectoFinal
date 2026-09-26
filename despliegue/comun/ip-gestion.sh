#!/usr/bin/env bash
# Biblioteca común (se hace "source", no se ejecuta): IP de gestión OPCIONAL del propio PC.
#
# Para qué sirve: los sub-interfaces 802.1Q (y la tarjeta de PC-1) que solo hacen de "parent" de macvlan
# NO llevan IP, así que por defecto el PC no es alcanzable por la red del laboratorio. Con IP_GESTION en el
# .env se le añade una dirección para (1) copiar por scp el certificado ca.crt de PC-3 a PC-1 y PC-2 y
# (2) poder hacer ping/ssh para diagnosticar. Vacía (lo normal) = comportamiento sin IP.
#
# Reglas que valida (falla con un mensaje claro si no se cumplen):
#   - Cada dirección debe estar en una de las VLAN que ese PC aloja, y su último número entre 16 y 254: los
#     contenedores usan .1-.14 (ip_range x.x.x.0/28 de los compose) y la .1 es el gateway.
#   - Como máximo UNA VLAN por PC. Motivo (no es una manía): Docker activa net.ipv4.ip_forward=1 por su
#     cuenta. Si PC-2 tuviera IP en eth0.20 Y en eth0.30, el propio PC-2 enrutaría en local entre VLAN 20 y
#     VLAN 30 y el tráfico originado en él ya no saldría al switch y volvería (hairpin). Eso invalidaría la
#     evidencia central de la segmentación (el switch/PC-3 es quien decide). Con una sola VLAN no hay
#     nada que enrutar en local. Se aplica igual a PC-3 por coherencia.
#   - Se añade una ruta 10.10.0.0/16 por la .1 de esa VLAN para poder llegar a las demás subredes; qué
#     puede alcanzar de verdad lo decide la matriz (una VLAN de negocio solo llega a la VLAN 99, así que
#     el certificado se copia desde/hacia PC-3 usando su dirección de la VLAN 99).
#
# Uso: gestion_aplicar "<IP_GESTION>" "<vlan>:<interfaz>" ["<vlan>:<interfaz>" ...]
#   p. ej. PC-2:  gestion_aplicar "${IP_GESTION:-}" "20:${IFACE}.20" "30:${IFACE}.30"
# Idempotente ("ip addr replace"). Con IP_GESTION vacía no hace nada.

gestion_aplicar() {
  local valor="$1"; shift
  local -a candidatas=() vlans_usadas=()
  local par vlan dev ip host octetos tercero elegido_dev="" elegido_vlan="" e

  valor="${valor//,/ }"
  # shellcheck disable=SC2206
  candidatas=(${valor})
  [ "${#candidatas[@]}" -eq 0 ] && return 0

  for e in "${candidatas[@]}"; do
    ip="${e%/24}"
    if [[ ! "${ip}" =~ ^10\.10\.([0-9]{1,3})\.([0-9]{1,3})$ ]]; then
      echo "IP_GESTION='${e}' no es válida: usa una dirección 10.10.<VLAN>.<host>, p. ej. 10.10.99.250." >&2
      return 1
    fi
    tercero="${BASH_REMATCH[1]}"; host="${BASH_REMATCH[2]}"
    if [ "${host}" -lt 16 ] || [ "${host}" -gt 254 ]; then
      echo "IP_GESTION='${e}': el último número debe estar entre 16 y 254 (.1-.14 son de los contenedores y el gateway; usa p. ej. .250)." >&2
      return 1
    fi
    elegido_dev=""
    for par in "$@"; do
      vlan="${par%%:*}"; dev="${par#*:}"
      if [ "${vlan}" = "${tercero}" ]; then elegido_dev="${dev}"; elegido_vlan="${vlan}"; fi
    done
    if [ -z "${elegido_dev}" ]; then
      octetos=""; for par in "$@"; do octetos="${octetos} ${par%%:*}"; done
      echo "IP_GESTION='${e}' está en la VLAN ${tercero}, que este PC no aloja. VLAN válidas aquí:${octetos}." >&2
      return 1
    fi
    vlans_usadas+=("${elegido_vlan}")
  done

  if [ "$(printf '%s\n' "${vlans_usadas[@]}" | sort -u | wc -l)" -gt 1 ]; then
    echo "IP_GESTION tiene direcciones en más de una VLAN (${vlans_usadas[*]}). Solo se permite UNA por PC:" >&2
    echo "con IP en dos VLAN, Docker (ip_forward=1) haría que este PC enrutara entre ellas por sí mismo y se" >&2
    echo "perdería el hairpin por el switch/PC-3 que demuestra la segmentación. Deja solo una dirección." >&2
    return 1
  fi
  if [ "${#candidatas[@]}" -gt 1 ]; then
    echo "IP_GESTION: pon una sola dirección (recibido: ${candidatas[*]})." >&2
    return 1
  fi

  ip="${candidatas[0]%/24}"
  ip addr replace "${ip}/24" dev "${elegido_dev}"
  ip route replace 10.10.0.0/16 via "10.10.${elegido_vlan}.1" dev "${elegido_dev}"
  echo "IP de gestión ${ip}/24 en ${elegido_dev} (ruta 10.10.0.0/16 vía 10.10.${elegido_vlan}.1)."
}
