# Simulador del perfil L2 (switch sin capa 3, PC-3 como router-on-a-stick) en un solo host

Misma topología y misma prueba de la matriz que el perfil L3 (ver `../../l3-switch/pruebas/README.md` para
la tabla de equivalencias y los límites), pero:

- El bridge con `vlan_filtering 1` **no lleva ninguna IP** (switch L2 puro).
- El puerto de PC-3 lleva las **5 VLAN** (10, 20, 30, 40, 99); el de PC-2 solo 20 y 30; el de PC-1, 10 access.
- PC-3 crea `eth0.10/20/30/40/99` con la IP `.1` de cada VLAN, habilita `ip_forward` y aplica las reglas
  `nftables` de la matriz (router-on-a-stick). El tráfico VLAN20 ↔ VLAN30 sale por el trunk de PC-2, sube a
  PC-3, se filtra y vuelve (hairpin real).

## Cómo ejecutarlo

Desde la raíz del repositorio (contenedor `--privileged` sin red; ver el README del perfil L3 para Git Bash):

```powershell
# Gateway .1 en una macvlan hermana (funciona):
docker run --rm --privileged --network none -e RV_L2_GATEWAY=macvlan -v "${PWD}:/repo:ro" nicolaka/netshoot@sha256:b09d9b21381f47a79b3cbcb30da25266dc17186ea00ae65e99fdc51396f48e70 bash /repo/despliegue/l2-fallback/pruebas/simular-l2.sh

# Gateway .1 en la sub-interfaz eth0.NN (como hace hoy scripts/setup-vlans-pc3.sh) — FALLA, ver abajo:
docker run --rm --privileged --network none -v "${PWD}:/repo:ro" nicolaka/netshoot@sha256:b09d9b21381f47a79b3cbcb30da25266dc17186ea00ae65e99fdc51396f48e70 bash /repo/despliegue/l2-fallback/pruebas/simular-l2.sh
```

Variables: `RV_L2_GATEWAY=parent|macvlan` (por defecto `parent`), `RV_SETUP_PC3=<ruta>` (usa ese
`setup-vlans-pc3.sh` de L2 dentro de PC-3, con `IFACE=eth0`, en vez de crear los gateways la biblioteca) y
`RV_FIREWALL_PC3=<ruta>` (ejecuta ese firewall en PC-3 con `IFACE=eth0` en vez de las reglas de la biblioteca;
se leen los contadores de su tabla `inet reservaviva` y se exige que cada bloqueo suba **su** regla).
Al terminar imprime `nft list table inet reservaviva`. Ejemplo con los scripts reales (rama de los perfiles):

```powershell
docker run --rm --privileged --network none -v "${PWD}:/repo:ro" -v "${PWD}\..\otra-copia:/scripts:ro" `
  -e RV_SETUP_PC3=/scripts/despliegue/l2-fallback/scripts/setup-vlans-pc3.sh `
  -e RV_FIREWALL_PC3=/scripts/despliegue/l2-fallback/scripts/firewall-pc3-matriz.sh `
  nicolaka/netshoot@sha256:b09d9b21381f47a79b3cbcb30da25266dc17186ea00ae65e99fdc51396f48e70 bash /repo/despliegue/l2-fallback/pruebas/simular-l2.sh
```

## Verificación con los scripts reales de la rama `feat/perfiles-l2-l3-red` (commit 9d3317c)

Ejecutado el 2026-09-19 (Docker Desktop 29.8, kernel 6.6.87 WSL2):

- **Con `setup-vlans-pc3.sh` + `firewall-pc3-matriz.sh` reales:** las 20 celdas dan lo esperado y **los 12
  contadores de descarte suben, cada uno en su pareja** (4 paquetes / 240 bytes cada uno, todos con
  `iifname "gwNN" oifname "gwMM"`); salida 0. No es solo "no llegó": lo paró su regla.
- **Mutación (mismo firewall, `setup-vlans-pc3.sh` sin las líneas `arp_ignore`/`arp_announce`):** 15
  comprobaciones fallan. Con `policy accept`, los bloqueos entre VLAN10/20/30 (6 celdas) **dejan pasar el
  tráfico prohibido en silencio** y sus contadores quedan a 0; solo siguen bloqueadas las 6 celdas que
  tocan VLAN40, y los únicos contadores que suben son los de origen VLAN40. Es decir: sin `arp_ignore=1` la segmentación se cae sin error visible.
- **Perfil L3 frente a `despliegue/l3-switch/scripts/setup-vlans-pc3.sh`:** la topología simulada coincide
  (PC-3 solo con `eth0.40` y `eth0.99` sin IP, sin `gwNN`; las IP `.1` están en las SVI del switch).

## Hallazgo: el diseño L2 actual no funciona con macvlan en PC-3

Verificado el 2026-09-19 (Docker Desktop 29.8, kernel 6.6.87 WSL2):

1. **IP `.1` en la sub-interfaz padre (`eth0.40`, `eth0.99`), como hoy `scripts/setup-vlans-pc3.sh`: falla.**
   Los contenedores de PC-3 (ERPNext en VLAN40 y LDAP en VLAN99) son macvlan de esa misma interfaz y **no
   alcanzan su gateway** `10.10.40.1` / `10.10.99.1`: un macvlan no entrega tramas a su propia interfaz
   padre, la trama sale al cable y el switch no la devuelve por el mismo puerto. Resultado: 11 de las
   comprobaciones fallan (todo lo que va hacia VLAN99 o desde ella, y los bloqueos desde VLAN40 no llegan a
   ninguna regla). Salida 1.
2. **Gateway en una macvlan hermana (`RV_L2_GATEWAY=macvlan`) con `arp_ignore=1`: funciona.** El router y los
   contenedores de PC-3 son hijos del mismo padre y se ven entre sí. Las 20 celdas dan lo esperado, cada
   `drop-*` con 4 paquetes y `drop-resto` = 0, salida 0.
3. **Sin `arp_ignore=1` también falla, más sutil:** la interfaz padre (sin IP) contesta al ARP de la IP
   `.1` (ARP flux), los paquetes entran por `eth0.NN` en vez de por el gateway y las reglas por nombre de
   interfaz no casan (`drop-resto` sube y algunas reglas no se activan). Se detectó con `nft monitor trace`.

Para el `firewall-pc3-matriz.sh` y `setup-vlans-pc3.sh` del fallback L2 esto significa: la IP `.1` de cada
VLAN debe estar en una macvlan hermana (no en `eth0.NN`), con `net.ipv4.conf.all.arp_ignore=1` y
`arp_announce=2` en PC-3, y las reglas deben casar con esas interfaces.

## Límites

Los mismos que el perfil L3 (kernel de Linux, no el switch del laboratorio; solo TCP). Además, el
comportamiento de macvlan y ARP aquí es el del kernel de WSL2; conviene confirmarlo en el PC-3 real (Fase 3).
