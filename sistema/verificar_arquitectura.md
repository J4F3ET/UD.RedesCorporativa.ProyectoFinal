# Verificación de la arquitectura en un host (`verificar_arquitectura.py`)

Objetivo: demostrar que la topología diseñada **se comporta como está diseñada**, no solo que los contenedores arrancan.
Estado: **adaptado a Samba AD DC** (rama `feat/samba-ad-dc`, sustituye a OpenLDAP). Los bloques 1-4 y 6 ya estaban
**ejecutados contra el sistema completo** con OpenLDAP; el bloque 5 (Active Directory) es nuevo. La reejecución
completa contra `samba-ad` ocurre en la Fase 2 del plan de migración, una vez dev tenga el servicio arriba con la
siembra completa. Las cifras de cada pasada están en [`../docs/resultados-un-host.md`](../docs/resultados-un-host.md).

## La topología que se prueba

El [`docker-compose.yml`](../docker-compose.yml) de la raíz convierte cada VLAN en un bridge de Docker **con su misma subred**, y las
cuatro apps se conectan además a `vlan99_infra` con IP fija:

| App | VLAN de departamento | Puerto sondeado |
|---|---|---|
| openvpms-app | vlan10 | 8080 |
| pretix-web | vlan20 | 80 |
| inventree-app | vlan30 | 8000 |
| erpnext-backend | vlan40 | 8000 |

`samba-ad`, `dns-interno`, `ntp-interno` y `proxy-web` están en `vlan99_infra` (y `erpnext-hr` tiene ahí su pata para el
proxy). Las IP de cada contenedor están en
[`../docs/arquitectura.md`](../docs/arquitectura.md#4-servicios). Dos bridges de Docker no se enrutan entre sí: esa es la
segmentación que se pone a prueba.

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
   `samba-ad:389/636` y **no** otros departamentos.
2. **DNS, vista interna.** Se consulta a `10.10.99.11` de verdad desde `vlan99_infra`: cada registro de
   `servicios/bind9/zones/db.reservaviva.lan` (autoritativo, igual que la zona), un nombre inexistente (NXDOMAIN) y
   `example.com` (REFUSED: sin recursión). Además, cada uno de los 7 nombres de la zona debe apuntar a la IP real
   (`docker inspect`) del contenedor que da ese servicio; si no, es **FAIL**:

   | Nombre | Contenedor | Red en la que se toma su IP |
   |---|---|---|
   | `dns` | `dns-interno` | vlan99 |
   | `ldap` | `samba-ad` | vlan99 |
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
4. **Acceso por nombre** (proxy web y vista lan del DNS):
   - **Topología:** `proxy-web` está **solo** en `vlan99_infra` (en otra VLAN sería un router entre departamentos) y
     `erpnext-hr` tiene su pata en `vlan99_infra`.
   - **Vista lan:** se pregunta a `dns-interno` desde **fuera** de las VLAN, desde el anfitrión por el puerto publicado y por
     **TCP** (el mismo camino que un equipo de la LAN; a bind9 le llega con el gateway del bridge como origen, que la ACL
     deja fuera de la vista interna). `openvpms`, `pretix`, `inventree`, `rrhh` y `dns` deben dar la IP en la que se publica
     el proxy (127.0.0.1 en modo local, la IP de la LAN en modo intranet); `ldap`, `ntp` y `ad` (zona AD completa), NXDOMAIN;
     `example.com`, REFUSED.
     Se contrasta con la vista interna: el mismo nombre da la IP del contenedor desde las VLAN y la del proxy desde fuera.
     TCP y no UDP porque es lo más fiable a través de la publicación de Docker; el cliente UDP ya lo ejercita el bloque 2.
     Con Docker Engine en WSL, en modo intranet el DNS se publica en el 1053 y el 53 lo atiende el reenviador de Windows
     (`sistema/reenviador-dns.ps1`): entonces se consulta además `pretix` por `<IP>:53`, por UDP y por TCP, que es la ruta
     completa de un cliente de la LAN. Desde WSL esa consulta llega de verdad al reenviador (comprobado: con el
     reenviador parado, UDP no responde y TCP da "connection refused").
   - **Proxy:** por cada nombre, con la cabecera `Host` de un navegador que llega por él: la página de login responde 200
     `text/html` (y sin `INVE-E7`), y **el primer CSS o JS que referencia** responde 200 con su `Content-Type` (H22: un 200 del
     HTML no prueba que la web funcione). Además: `openvpms.reservaviva.lan/` redirige a `/openvpms/`, el WebSocket de
     socket.io de ERPNext responde 101, y un nombre desconocido o la IP a secas reciben el 404 del `default_server`.
   - **Acceso directo:** lo mismo (HTML + estático) por `http://localhost:<puerto>` de cada aplicación, que sigue siendo el
     de administración.
   Se hace desde el anfitrión, donde corre el guion, contra lo que Docker publica (`docker inspect`): no hace falta que el
   anfitrión use este DNS.
5. **Active Directory** (nuevo, especifico de Samba AD DC; no existia con OpenLDAP):
   - **SRV via bind9.** `_ldap._tcp.ad.reservaviva.lan` y `_kerberos._tcp.ad.reservaviva.lan`, consultados a
     `dns-interno` (10.10.99.11) desde `vlan99_infra` (una VLAN interna): demuestra que la zona `type forward`
     de bind9 reenvia de verdad hacia `samba-ad` y que el registro apunta al puerto esperado (389 y 88).
   - **Kerberos.** `kinit vet.prueba@AD.RESERVAVIVA.LAN` y `klist` con `docker exec` dentro de `samba-ad`; la
     clave viaja **siempre por stdin**, nunca en el argv (visible con `docker top`/`ps`).
   - **Grupos.** `samba-tool group listmembers` para `GG-Medica`, `GG-Operaciones` y `GG-RRHH` debe devolver
     exactamente los usuarios de prueba esperados de cada grupo.
   - **Prueba NEGATIVA de membresia.** `vet.prueba` (solo en `GG-Medica`) no debe poder entrar en InvenTree
     (exige `GG-Operaciones`) ni en ERPNext (exige `GG-RRHH`): reutiliza el mecanismo HTTP de `ldaplogin.py`
     (casos 1/2) con un usuario valido pero sin el grupo que exige el filtro `memberOf` de cada app.
   - La vista lan sin `ad.reservaviva.lan` (bloque 4, tabla de arriba) completa la prueba: ni el registro
     suelto `ldap` ni la zona AD entera se anuncian a la LAN.
6. **Consolidación.** Invoca `ldapprobe.py` (bind anonimo + busqueda al rootDSE: AD no permite busqueda anonima
   en el resto del arbol), `probe.py` y `ldaplogin.py --persistencia` (caso 4); no los duplica. La verificación
   conserva el modo de publicación (local o intranet) en el `up -d` del caso 4.

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
- **H21 (resuelto): la zona ya no hereda las IP del diseño de 3 equipos.** La prueba en rojo, antes del arreglo, dio FAIL en
  `dns`, `ntp`, `pretix` y `rrhh`. Ahora `levantar-sistema.sh` sustituye un marcador por nombre y los 7 deben dar PASS
  (detalle en [`../docs/resultados-un-host.md`](../docs/resultados-un-host.md)).
- **H11**: `/opt/startup.sh` de la imagen NTP escribe `server 127.127.1.1` **y** `local stratum 10`. `127.127.1.1` es notación de
  ntpd para el reloj local; chrony lo trata como un servidor normal e inalcanzable. Lo que sirve hora es `local stratum 10`,
  así que el stratum publicado debe ser 10. El guion lo comprueba (`chronyc tracking`) y muestra `chronyc sources`.

## Qué NO puede demostrar un solo host

**"Pasa en un host" no es "pasa en el laboratorio".** Quedan fuera y no se prueban:

- El **etiquetado 802.1Q**, los puertos de acceso/troncal y la asignación de VLAN por puerto.
- El **switch físico** (comportamiento L2/L3 real, tablas MAC, aislamiento de puertos).
- La **matriz de firewall** del diseño de 3 equipos sobre interfaces reales (`firewall-pc3-matriz.sh` es anexo de diseño): aquí no hay
  interfaces `vlanXX` ni reglas sobre ellas; el aislamiento lo da Docker, con otro mecanismo.
- El acceso **desde otro equipo** de la LAN. El bloque 4 prueba el proxy y la vista lan desde el propio anfitrión, por el
  puerto que publica Docker; que un equipo distinto llegue depende además de WSL en modo `mirrored`, del cortafuegos de
  Windows y de Hyper-V y de Portmaster. Esa prueba la hace el usuario ([`../docs/operacion.md`](../docs/operacion.md#acceso-desde-la-lan)).

## Estado de verificación

| Qué | Estado |
|---|---|
| Clasificador de conexiones, cliente DNS por UDP (compresión, NXDOMAIN, REFUSED, timeout) y por TCP, cliente SNTP, lector de las dos zonas, extracción del estático del HTML | **Verificado** con `--autotest` en WSL contra sockets locales (PASS). En Windows el caso "puerto cerrado" falla por un artefacto de loopback (sin RST inmediato); en Linux/WSL pasa. |
| Modo `--sonda` por stdin (el que corre dentro del contenedor, sin `__file__`) | **Verificado** en WSL sin Docker |
| Fallo limpio con el sistema apagado (7 FAIL en prerrequisitos, exit 1, sin excepción) | **Verificado** |
| Todo lo que toca contenedores (con OpenLDAP): segmentación, DNS, NTP, ldapprobe/probe/ldaplogin | **Verificado** el 26/09/2026 contra los 25 servicios, incluida la persistencia (cifras en [`../docs/resultados-un-host.md`](../docs/resultados-un-host.md)); base sobre la que se adapto a Samba AD DC |
| Acceso por nombre (bloque 4, con OpenLDAP) | **Verificado** el 27/09/2026 contra los 26 servicios, en modo local y en modo intranet con la IP de la distro de WSL (cifras en [`../docs/resultados-un-host.md`](../docs/resultados-un-host.md)) |
| Supuestos: puertos 8080/80/8000/8000 de las apps, `chronyd -Q` con la imagen de cturra, `--network container:<app>` | **Verificado** en esa misma ejecución (los bloques que dependen de ellos dan PASS) |
| Bloque 5 (Active Directory: SRV, kinit/klist, grupos, prueba negativa) y adaptacion de los bloques 1/2/6 a `samba-ad` | **Pendiente**: escrito y compilado (`python -m py_compile`), probado en `--autotest` (mecanica de SRV) y con un servidor LDAP/BER falso local para `ldapprobe.py`; falta ejecutar contra el `samba-ad` real en la Fase 2 |
