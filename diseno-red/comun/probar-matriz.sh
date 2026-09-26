#!/usr/bin/env bash
# Recorre las 20 celdas no diagonales de la matriz de segmentación (sección 4 de
# diseno-red/arquitectura-3-equipos-departamentos.md) y saca una tabla PASA/FALLA.
#
#   - VLAN de negocio (10/20/30/40) -> VLAN99 (LDAPS 636) y VLAN99 -> VLAN de negocio (8080): deben PASAR.
#   - Las 12 combinaciones negocio <-> negocio (8080): deben FALLAR, y "fallar" es que el paquete se
#     DESCARTA: el destino existe y escucha (se comprueba antes con `ss`), así que un fallo significa red.
#   - Una celda bloqueada solo cuenta como buena si además sube el contador de SU regla de drop
#     (drop-ORIGEN-DESTINO); si falla por otra causa (sin ruta, gateway inalcanzable) es un FALLO de la prueba.
#
# Se ejecuta DESPUÉS de montar la topología (ver simular-l3.sh / simular-l2.sh), en el mismo contenedor,
# con RV_ROUTER_NS y RV_IFACE_FMT exportados por diseno-red/comun/lib-topologia.sh.
# Salida distinta de 0 si alguna celda (o comprobación) no da lo esperado.
# RV_CHECK_COUNTERS=0 desactiva la comprobación de contadores (p. ej. si las reglas no llevan comentarios).

set -uo pipefail
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib-topologia.sh
source "$DIR/lib-topologia.sh"
: "${RV_ROUTER_NS:?ejecuta primero topo_crear (simular-l3.sh / simular-l2.sh)}"
RV_CHECK_COUNTERS="${RV_CHECK_COUNTERS:-1}"

fallos=0
nombre() { case "$1" in 10) echo Médica;; 20) echo Taquilla;; 30) echo Logística;; 40) echo RRHH;; 99) echo Infra;; esac; }

# Conecta por TCP desde el contenedor de la VLAN $1 al servicio de la VLAN $2 y exige la respuesta "ok".
alcanza() {
  local puerto=$RV_PUERTO_NEGOCIO; [ "$2" = "$RV_INFRA" ] && puerto=$RV_PUERTO_INFRA
  ns "c$1" timeout 4 bash -c 'exec 3<>"/dev/tcp/$0/$1" && read -t 2 -u 3 l && [ "$l" = ok ]' "$(rv_ip "$2")" "$puerto" 2>/dev/null
}

echo "=== Perfil: ${RV_PERFIL} (router: rv-${RV_ROUTER_NS}${RV_PERFIL:+, gateway L2: ${RV_L2_GATEWAY:-parent}}) ==="
echo
echo "--- Comprobaciones previas (para que un fallo signifique red y no 'no había nadie') ---"
for v in "${RV_VLANS[@]}"; do
  puerto=$RV_PUERTO_NEGOCIO; [ "$v" = "$RV_INFRA" ] && puerto=$RV_PUERTO_INFRA
  if ns "c$v" ss -ltn 2>/dev/null | grep -q ":${puerto} "; then esc="escucha :${puerto}"; else esc="NO escucha :${puerto}"; fallos=$((fallos+1)); fi
  if ns "c$v" ping -c1 -W1 "$(rv_gw "$v")" >/dev/null 2>&1; then gw="gateway $(rv_gw "$v") alcanza"; else gw="gateway $(rv_gw "$v") NO alcanzable"; fi
  printf '  VLAN%-3s %-10s %-16s %s\n' "$v" "$(nombre "$v")" "$esc" "$gw"
done
echo

declare -A res
esperado_pasa() { [ "$1" = "$RV_INFRA" ] || [ "$2" = "$RV_INFRA" ]; }

for a in "${RV_VLANS[@]}"; do
  for b in "${RV_VLANS[@]}"; do
    [ "$a" = "$b" ] && continue
    if alcanza "$a" "$b"; then real=pasa; else real=falla; fi
    if esperado_pasa "$a" "$b"; then exp=pasa; else exp=falla; fi
    if [ "$real" = "$exp" ]; then
      [ "$exp" = pasa ] && res[$a,$b]="✅ Permitido" || res[$a,$b]="❌ Bloqueado"
    else
      [ "$exp" = pasa ] && res[$a,$b]="⚠️ FALLA: debía pasar" || res[$a,$b]="⚠️ FALLA: debía bloquearse"
      fallos=$((fallos+1))
    fi
  done
done

# Contadores: cada celda bloqueada debe haber hecho subir SU regla de drop; nada debe caer en drop-resto.
declare -A pk
if [ "$RV_CHECK_COUNTERS" = 1 ]; then
  while read -r c p b; do pk[$c]=$p; done < <(matriz_contadores)
  for a in "${RV_NEGOCIO[@]}"; do
    for b in "${RV_NEGOCIO[@]}"; do
      [ "$a" = "$b" ] && continue
      if [ "${pk[drop-$a-$b]:-0}" -eq 0 ]; then
        echo "  ⚠️  la celda ${a}->${b} no subió el contador drop-${a}-${b}: si se bloqueó, fue por otra causa" ; fallos=$((fallos+1))
      fi
    done
  done
  if [ "${pk[drop-resto]:-0}" -gt 0 ]; then
    echo "  ⚠️  drop-resto=${pk[drop-resto]}: hubo tráfico descartado sin regla específica"; fallos=$((fallos+1))
  fi
fi

echo "=== Matriz de segmentación (misma forma que la sección 4) ==="
printf '| Origen \\ Destino | VLAN10 (Médica) | VLAN20 (Taquilla) | VLAN30 (Logística) | VLAN40 (RRHH) | VLAN99 (Infra) |\n'
printf '|---|---|---|---|---|---|\n'
for a in "${RV_VLANS[@]}"; do
  fila="| **VLAN${a} ($(nombre "$a"))** |"
  for b in "${RV_VLANS[@]}"; do
    if [ "$a" = "$b" ]; then fila+=" — |"; else fila+=" ${res[$a,$b]} |"; fi
  done
  echo "$fila"
done
echo

echo "=== Contadores de las reglas del router (rv-${RV_ROUTER_NS}) — la evidencia de cada bloqueo ==="
printf '%-16s %10s %10s\n' regla paquetes bytes
matriz_contadores | while read -r c p b; do printf '%-16s %10s %10s\n' "$c" "$p" "$b"; done
echo

if [ "$fallos" -eq 0 ]; then echo "RESULTADO: las 20 celdas dan lo esperado."; else echo "RESULTADO: $fallos comprobación(es) NO dieron lo esperado."; fi
exit $(( fallos > 0 ? 1 : 0 ))
