# Simulador del perfil L3 (switch con SVIs y ACL) en un solo host

Ejecuta la **matriz de segmentación** (sección 4 de `docs/arquitectura-3-equipos-departamentos.md`) sin
hardware ni levantar las apps. Lo que el arnés `pruebas/smoke-test-3-pcs/` no puede hacer (allí las apps
comparten una red bridge y no hay separación) se hace aquí con el kernel de Linux:

| En el laboratorio | En el simulador |
|---|---|
| Switch 802.1Q | Un `bridge` con `vlan_filtering 1` en el namespace `rv-sw` |
| PC-1, puerto ACCESS VLAN 10 | `rv-pc1`; el puerto del bridge lleva `vid 10 pvid untagged` |
| PC-2 / PC-3, puertos TRUNK | `rv-pc2` (VLAN 20, 30) y `rv-pc3` (VLAN 40, 99) con sub-interfaces `eth0.NN`; el puerto lleva las VLAN etiquetadas |
| Contenedores con macvlan | Un namespace `rv-cNN` por VLAN colgado con `macvlan` de su PC, con IP `10.10.NN.10` y un servicio TCP real |
| SVI de cada VLAN (`10.10.NN.1`) | Interfaces `vlanNN` del bridge con IP `.1`, `ip_forward=1` en el switch |
| ACL de la matriz | Reglas `nftables` (`table inet matriz`, `policy drop`) en el namespace del switch, con un contador por regla |

El tráfico entre VLAN de negocio pasa por el veth del trunk, entra al switch y vuelve: incluye el *hairpin*
VLAN20 ↔ VLAN30 de PC-2.

## Cómo ejecutarlo (Windows 11 + Docker Desktop, o cualquier Linux con Docker)

Todo corre dentro de un contenedor `--privileged` **sin red** (`--network none`); no toca el host ni la red
de Docker. Desde la raíz del repositorio:

```powershell
docker run --rm --privileged --network none -v "${PWD}:/repo:ro" nicolaka/netshoot@sha256:b09d9b21381f47a79b3cbcb30da25266dc17186ea00ae65e99fdc51396f48e70 bash /repo/despliegue/l3-switch/pruebas/simular-l3.sh
```

En Git Bash (Windows) añade `MSYS_NO_PATHCONV=1` delante y usa `"$PWD:/repo:ro"`. Tarda unos 30 s y consume
poca memoria. `nicolaka/netshoot` (~900 MB) ya trae iproute2, nftables, socat y bash: no hace falta Internet
después de descargarla una vez.

## Qué comprueba

`despliegue/comun/probar-matriz.sh` recorre las **20 celdas** no diagonales:

- Las 4 VLAN de negocio → VLAN99 (LDAPS 636) y VLAN99 → cada VLAN de negocio (8080): deben **pasar**.
- Las 12 combinaciones negocio ↔ negocio (8080): deben **fallar por descarte**.

Antes de probar comprueba que cada destino **escucha** (`ss -ltn`) y que cada contenedor alcanza su gateway,
para que un fallo signifique red y no "no había nadie". Cada conexión exige la respuesta `ok` del servicio.
Una celda bloqueada solo cuenta como buena si sube **su** contador `drop-ORIGEN-DESTINO`; `drop-resto` debe
quedar en 0. Termina con la tabla de la sección 4 (✅/❌), los contadores de cada regla y salida distinta de
0 si algo no da lo esperado.

Resultado verificado (ejecutado el 2026-09-19 en Docker Desktop 29.8, kernel 6.6.87 WSL2): las 20 celdas
dan lo esperado, cada regla `drop-*` con 4 paquetes (SYN y reintentos), `drop-resto` = 0, salida 0. Además,
sin reglas (forward abierto) las 12 celdas de bloqueo fallan y la salida es 1.

## Límites (qué NO demuestra)

- Es el comportamiento del **kernel de Linux**, no el de un switch concreto: no prueba la sintaxis ni las
  ACL del equipo del laboratorio, solo que la política de la matriz es coherente y realizable con SVIs.
- Solo TCP. No se prueban ICMP, UDP (DNS/NTP) ni puertos concretos más allá de 8080 y 636.
- "VLAN99 → negocio ✅ (responde)" se prueba como una conexión nueva iniciada desde VLAN99 (las reglas de
  `scripts/firewall-pc3-matriz.sh` la permiten); además todas las celdas ✅ implican respuesta de vuelta.
- No sustituye a la prueba en hardware real (Fase 3): macvlan sobre una NIC física y el switch real.

Perfil alternativo (switch solo L2, PC-3 como router-on-a-stick): `despliegue/l2-fallback/pruebas/`.
