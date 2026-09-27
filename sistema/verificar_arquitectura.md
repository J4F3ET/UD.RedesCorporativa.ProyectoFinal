# Verificación de la arquitectura en un host (`verificar_arquitectura.py`)

Objetivo: demostrar que la topología diseñada **se comporta como está diseñada**, no solo que los contenedores arrancan.
Estado: **ejecutado contra el sistema completo** con `levantar-sistema.sh verificar`. Las cifras de cada pasada están en [`../docs/resultados-un-host.md`](../docs/resultados-un-host.md).

## La topología que se prueba

El [`docker-compose.yml`](../docker-compose.yml) de la raíz convierte cada VLAN en un bridge de Docker **con su misma subred**, y las
cuatro apps se conectan además a `vlan99_infra` con IP fija:

| App | VLAN de departamento | vlan99_infra | Puerto sondeado |
|---|---|---|---|
| openvpms-app | 10.10.10.x | 10.10.99.24 | 8080 |
| pretix-web | 10.10.20.x | 10.10.99.21 | 80 |
| inventree-app | 10.10.30.x | 10.10.99.22 | 8000 |
| erpnext-backend | 10.10.40.x | 10.10.99.23 | 8000 |

`openldap` 10.10.99.10 · `dns-interno` 10.10.99.11 · `ntp-interno` 10.10.99.12. Dos bridges de Docker no se enrutan entre sí:
esa es la segmentación que se pone a prueba.

## Cómo se ejecuta

Lo normal es `./levantar-sistema.sh verificar` (o `.\levantar-sistema.ps1 verificar`), que guarda el informe en `resultados/`.
A mano, con el sistema arriba y sano, desde esta carpeta y **dentro de WSL** (igual que `ldaplogin.py`; el `docker` de Windows
es un `.cmd`). El caso 4 de `ldaplogin.py` ejecuta `docker compose --env-file sistema/test.env down` / `up -d` desde la raíz:

```bash
python3 verificar_arquitectura.py --informe salida.txt      # todo, incluido ldaplogin.py --persistencia
python3 verificar_arquitectura.py --sin-persistencia        # omite el caso 4 (down + up -d)
python3 verificar_arquitectura.py --autotest                # solo la mecánica, sin Docker
```

Sale con 0 solo si **no hay ningún FAIL**. Cada comprobación imprime su nombre, `[PASS]`/`[FAIL]`/`[INFO]` y la salida literal
en la que se apoya. `INFO` son hallazgos que hay que leer; no cuentan como fallo. Registra `ExecMainStartTimestamp` de
docker antes y después: si cambia, el resultado no vale. Los contenedores efímeros usan la imagen de `pretix-web` (Python,
ya local, referencia con digest) con `--pull=never`, y la de `ntp-interno`; llevan la etiqueta `verificacion-arquitectura=1`.

## Qué comprueba

1. **Segmentación (prueba negativa).** Un cliente efímero *solo* en una VLAN de departamento no alcanza otro departamento
   ni `vlan99_infra`; un cliente con la pila de red de la app (`--network container:<app>`, dual-homed) **sí** alcanza
   `openldap:389/636` y **no** otros departamentos.
2. **DNS.** Se consulta a `10.10.99.11` de verdad: cada registro de `servicios/bind9/zones/db.reservaviva.local` (autoritativo, igual que la
   zona), un nombre inexistente (NXDOMAIN) y `example.com` (REFUSED: sin recursión). Además, cada uno de los 7 nombres de la
   zona debe apuntar a la IP real (`docker inspect`) del contenedor que da ese servicio; si no, es **FAIL**:

   | Nombre | Contenedor | Red en la que se toma su IP |
   |---|---|---|
   | `dns` | `dns-interno` | vlan99 |
   | `ldap` | `openldap` | vlan99 |
   | `ntp` | `ntp-interno` | vlan99 |
   | `openvpms` | `openvpms-app` | vlan10 |
   | `pretix` | `pretix-web` | vlan20 |
   | `inventree` | `inventree-app` | vlan30 |
   | `rrhh` | `erpnext-hr` | vlan40 |

   `rrhh` apunta a `erpnext-hr` y no a `erpnext-backend`: `erpnext-hr` es el nginx de ERPNext, el único contenedor de RRHH que
   atiende HTTP a los usuarios (escucha en 8080 y es el que publica `ERPNEXT_PORT` en el host). `erpnext-backend` (gunicorn,
   puerto 8000) no publica nada y solo se llega a él a través de ese nginx. Comprobado con `docker inspect` el 26/09/2026.
3. **NTP.** `chronyc tracking` dentro de `ntp-interno`, un cliente SNTP que valida modo/stratum/LI/offset, y un cliente chrony
   real (`chronyd -Q`, no toca el reloj) que debe aceptar al servidor.
4. **Consolidación.** Invoca `ldapprobe.py`, `probe.py` y `ldaplogin.py --persistencia` (caso 4, que no se ha ejecutado nunca);
   no los duplica.

## Cómo se lee un resultado (esto decide si la prueba vale algo)

Un destino inalcanzable y un nombre que no resuelve dan resultados parecidos y significan cosas distintas. Por eso:

- Los negativos usan **siempre IP literal**: el DNS no interviene.
- Cada conexión se clasifica: `ABIERTO`, `RECHAZADO` (RST: el destino existe y contesta), `SIN_RESPUESTA` (timeout) o `SIN_RUTA`
  (ICMP/sin ruta). `ABIERTO` y `RECHAZADO` en un negativo son **FAIL: segmentación rota**.
- **Un negativo solo es PASS con dos controles positivos**: (a) el cliente alcanza a su propio servicio desde su VLAN
  (su herramienta funciona) y (b) el destino contesta desde *su* VLAN (existe y escucha). Sin ellos, un timeout es
  **FAIL "inconcluyente"**, no PASS. Con los controles, `SIN_RESPUESTA` ⇒ "el paquete no llega a un destino que sí está
  vivo", es decir, no hay camino. En bridges de Docker el aislamiento **descarta** paquetes, así que el resultado esperado es
  timeout y no "no route"; solo los controles permiten atribuirlo a la segmentación.
- En DNS, NXDOMAIN (rcode 3 autoritativo) ≠ REFUSED (rcode 5) ≠ timeout: los tres se distinguen y se exigen por separado.
- En NTP, un cliente que recibe respuesta con LI=3 ("no sincronizado") o stratum fuera de 1–15 la rechazaría: FAIL.
  Si `chronyd -Q` responde "No suitable source", el cliente rechazó al servidor: es un **hallazgo**, no un fallo del guion.

## Hallazgos (leer los `INFO`; observados en las pasadas de [`../docs/resultados-un-host.md`](../docs/resultados-un-host.md))

- **`vlan99_infra` es un único dominio L2 compartido por las 4 apps.** Aunque los departamentos estén aislados, una app dual-homed
  probablemente alcance a otra por su IP de infraestructura. En el diseño de 3 equipos (anexo `diseno-red/`) lo limita su matriz de firewall,
  no el bridge. El guion lo marca `INFO`, con la salida literal.
- **H21 (resuelto el 26/09/2026): la zona ya no hereda las IP del diseño de 3 equipos.** Antes ponía `dns`, `ntp` y `rrhh` en
  `10.10.99.10` (la IP de `openldap`) y `pretix` en `10.10.30.10` (la de `inventree-app`). La prueba en rojo, antes del arreglo,
  dio FAIL en esos cuatro nombres. Ahora `levantar-sistema.sh` sustituye un marcador por nombre y los 7 deben dar PASS.
- **H11**: `/opt/startup.sh` de la imagen NTP escribe `server 127.127.1.1` **y** `local stratum 10`. `127.127.1.1` es notación de
  ntpd para el reloj local; chrony lo trata como un servidor normal e inalcanzable. Lo que sirve hora es `local stratum 10`,
  así que el stratum publicado debe ser 10. El guion lo comprueba (`chronyc tracking`) y muestra `chronyc sources`.

## Qué NO puede demostrar un solo host

**"Pasa en un host" no es "pasa en el laboratorio".** Quedan fuera y no se prueban:

- El **etiquetado 802.1Q**, los puertos de acceso/troncal y la asignación de VLAN por puerto.
- El **switch físico** (comportamiento L2/L3 real, tablas MAC, aislamiento de puertos).
- La **matriz de firewall** del diseño de 3 equipos sobre interfaces reales (`firewall-pc3-matriz.sh` es anexo de diseño): aquí no hay
  interfaces `vlanXX` ni reglas sobre ellas; el aislamiento lo da Docker, con otro mecanismo.
- El acceso desde otros equipos por la IP LAN y los puertos publicados (aquí `PUBLISH_IP=127.0.0.1`).

## Estado de verificación

| Qué | Estado |
|---|---|
| Clasificador de conexiones, cliente DNS (compresión, NXDOMAIN, REFUSED, timeout), cliente SNTP, lector de zona | **Verificado** con `--autotest` en WSL contra sockets locales (PASS). En Windows el caso "puerto cerrado" falla por un artefacto de loopback (sin RST inmediato); en Linux/WSL pasa. |
| Modo `--sonda` por stdin (el que corre dentro del contenedor, sin `__file__`) | **Verificado** en WSL sin Docker |
| Fallo limpio con el sistema apagado (7 FAIL en prerrequisitos, exit 1, sin excepción) | **Verificado** |
| Todo lo que toca contenedores: segmentación, DNS, NTP, ldapprobe/probe/ldaplogin | **Verificado** el 26/09/2026 contra los 25 servicios, incluida la persistencia (cifras en [`../docs/resultados-un-host.md`](../docs/resultados-un-host.md)) |
| Supuestos: puertos 8080/80/8000/8000 de las apps, `chronyd -Q` con la imagen de cturra, `--network container:<app>` | **Verificado** en esa misma ejecución (los bloques que dependen de ellos dan PASS) |
