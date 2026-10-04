# Verificación de la arquitectura en un host (`verificar_arquitectura.py`)

Objetivo: demostrar que el sistema **se comporta como está diseñado**, no solo que los contenedores arrancan.
Estado: **adaptado el 04/10/2026 a la eliminación de las VLAN** (una IP, un puerto por servicio). La pasada real con el
compose nuevo está en [`../docs/resultados-un-host.md`](../docs/resultados-un-host.md); las anteriores corresponden al
diseño con una red por departamento y siguen ahí como registro.

## La topología que se prueba

El switch del laboratorio obliga a **una sola IP** (`HOST_IP`) y **un puerto por servicio**. El
[`docker-compose.yml`](../docker-compose.yml) de la raíz pone todos los contenedores en una única red, `reservaviva`
(`reservaviva-smoke_reservaviva` en Docker), y conserva `erpnext_internal` para la BD, Redis y los workers de ERPNext.

- **IP fijas:** solo `samba-ad` (`.10`) y `dns-interno` (`.11`). El resto, IP dinámica.
- **Dentro de una aplicación,** por nombre de servicio (`pretix-db`, `inventree-db`, `openvpms-db`…). Bases de datos y Redis
  **no se publican**.
- **Entre aplicaciones,** por `HOST_IP:puerto` publicado: el proxy va a las cuatro aplicaciones y `inventree-app` /
  `erpnext-backend` van a `ldap.reservaviva.lan:LDAPS_PORT`, que resuelve a `HOST_IP`.
- **Publicación:** todo en `HOST_IP`; las cuatro aplicaciones además en `127.0.0.1` con el mismo puerto.

Ya **no hay segmentación entre departamentos** que demostrar (ver [`../docs/seguridad.md`](../docs/seguridad.md)). Los
puertos y servicios están en [`../docs/arquitectura.md`](../docs/arquitectura.md#4-servicios).

## De dónde sale `HOST_IP`

`levantar-sistema` la exporta al entorno al llamar al verificador (`--ip X` la sobrescribe en esa ejecución). A mano, el
verificador usa la variable de entorno `HOST_IP` y, si no existe, la de `sistema/test.env`. Como comprobación cruzada la
compara con la IP en que Docker publica `proxy-web`; si no coinciden, es **FAIL**. Los puertos salen del entorno o de
`sistema/test.env`.

## Cómo se ejecuta

Lo normal es `./levantar-sistema.sh verificar` (o `.\levantar-sistema.ps1 verificar`), que guarda el informe en `resultados/`.
A mano, con el sistema arriba y sano, desde esta carpeta y **dentro de WSL** (igual que `ldaplogin.py`; el `docker` de Windows
es un `.cmd`). El caso 4 de `ldaplogin.py` ejecuta `docker compose --env-file sistema/test.env down` / `up -d` desde la raíz:

```bash
HOST_IP=192.168.1.26 python3 verificar_arquitectura.py --informe salida.txt   # todo, incluido ldaplogin.py --persistencia
python3 verificar_arquitectura.py --sin-persistencia                          # omite el caso 4 (down + up -d)
python3 verificar_arquitectura.py --autotest                                  # solo la mecánica, sin Docker
```

Sale con 0 solo si **no hay ningún FAIL**. Cada comprobación imprime su nombre, `[PASS]`/`[FAIL]`/`[INFO]` y la salida literal
en la que se apoya. `INFO` son hallazgos que hay que leer; no cuentan como fallo. Registra `ExecMainStartTimestamp` de
docker antes y después: si cambia, el resultado no vale. Los contenedores efímeros usan la imagen de `pretix-web` (Python,
ya local, referencia con digest) con `--pull=never`, y la de `ntp-interno`; llevan la etiqueta `verificacion-arquitectura=1`.

## Qué comprueba

**Prerrequisitos.** Los contenedores existen y están en la red `reservaviva` con IP (la BD y los Redis de ERPNext, solo en
`erpnext_internal`); no hay más redes que esas dos; `erpnext-backend` y `erpnext-hr` están además en `erpnext_internal`;
`samba-ad` y `dns-interno` tienen sus IP fijas; y `HOST_IP` coincide con la IP en que Docker publica `proxy-web`.

1. **Puertos (una IP, un puerto por servicio).**
   - **Publicación** (`docker inspect`): cada servicio publica exactamente en `HOST_IP:puerto` (las cuatro aplicaciones,
     además en `127.0.0.1:puerto`). Una publicación en `0.0.0.0` es FAIL.
   - **a) Desde el anfitrión:** las cuatro aplicaciones, el proxy, LDAP, LDAPS y DNS (tcp) están **abiertos** en
     `HOST_IP:puerto`; DNS y NTP responden por UDP con sus clientes.
   - **b) Desde un contenedor efímero de la red:** lo mismo. Es el camino real proxy → aplicaciones.
   - **c) Desde la pila de red de `inventree-app` y `erpnext-backend`** (`--network container:<app>`): `HOST_IP:LDAPS_PORT`
     abierto y handshake TLS verificando la CA del proyecto (`servicios/ca/certs/ca.crt`) con el nombre
     `ldap.reservaviva.lan`. Desde el anfitrión se comprueba además que el certificado cubre la IP `HOST_IP` (SAN).
   - **d) Negativos:** las bases de datos y Redis (`openvpms-db`, `pretix-db`, `pretix-redis`, `inventree-db`,
     `erpnext-db`, `erpnext-redis-cache`, `erpnext-redis-queue`) **no tienen `PortBindings`** y su puerto (3306, 5432, 6379)
     **no está abierto** en `HOST_IP`. Con dos controles: `HOST_IP` es alcanzable (el proxy abre) y el servicio **sí escucha
     dentro de su red**, por su nombre (los de ERPNext, desde la pila de red de `erpnext-backend`).
2. **DNS (una vista, una zona).** Se consulta a `HOST_IP:DNS_PORT` de verdad, por UDP y TCP desde el anfitrión y por UDP
   desde un contenedor: los 7 nombres de la zona (`dns`, `ldap`, `ntp`, `openvpms`, `pretix`, `inventree`, `rrhh`) deben
   dar `HOST_IP`, de forma autoritativa y coincidiendo con `servicios/bind9/zones/db.reservaviva.lan`. Además: un nombre
   inexistente da NXDOMAIN autoritativo; `example.com` desde el anfitrión da REFUSED (el anfitrión y la LAN no tienen
   recursión); la delegación `ad.reservaviva.lan` (`dc1.ad`) se resuelve desde un contenedor consultando a `dns-interno`
   por su IP fija; `example.com` desde un contenedor no resuelve (SERVFAIL o REFUSED, sin respuestas). Con Docker Engine en
   WSL, cuando `DNS_PORT` ≠ 53, se consulta además `pretix` por `HOST_IP:53`, por UDP y TCP: es la ruta del reenviador de
   Windows (`sistema/reenviador-dns.ps1`).
   La consulta con recursión se hace a la IP fija de `dns-interno` y no a `HOST_IP:DNS_PORT` porque, por el puerto
   publicado, la consulta llega a bind9 con el gateway de la red como origen, que la ACL deja sin recursión.
3. **NTP.** `chronyc tracking` dentro de `ntp-interno`, un cliente SNTP (desde el anfitrión y desde un contenedor) contra
   `HOST_IP:NTP_PORT` que valida modo/stratum/LI/offset, y un cliente chrony real (`chronyd -Q`, no toca el reloj) que debe
   aceptar a `HOST_IP:NTP_PORT` como fuente.
4. **Acceso por nombre y directo.**
   - **Proxy** (`HOST_IP:HTTP_PORT`): por cada nombre, con la cabecera `Host` de un navegador que llega por él, la página de
     login responde 200 `text/html` (y sin `INVE-E7`), y **el primer CSS o JS que referencia** responde 200 con su
     `Content-Type` (H22: un 200 del HTML no prueba que la web funcione). Como el proxy llega a las aplicaciones por
     `HOST_IP:puerto`, cada 200 prueba también ese camino. Además: `openvpms.reservaviva.lan/` redirige a `/openvpms/`, el
     WebSocket de socket.io de ERPNext responde 101, y un nombre desconocido o la IP a secas reciben el 404 del
     `default_server`.
   - **Acceso directo** por `http://HOST_IP:<puerto>` y por `http://localhost:<puerto>`: HTML + estático. Pretix responde 400
     a todo `Host` que no sea `pretix.reservaviva.lan` o `localhost`: por `HOST_IP:puerto` se registra como `INFO`
     (limitación conocida; se entra por nombre o por `localhost`).
5. **Active Directory** (Samba AD DC):
   - **SRV via bind9.** `_ldap._tcp.ad.reservaviva.lan` y `_kerberos._tcp.ad.reservaviva.lan`, consultados a `dns-interno`
     desde un contenedor de la red: demuestra que la delegación llega de verdad a `samba-ad` y que el registro apunta al
     puerto esperado (389 y 88).
   - **Kerberos.** `kinit vet.prueba@AD.RESERVAVIVA.LAN` y `klist` con `docker exec` dentro de `samba-ad`; la clave viaja
     **siempre por stdin**, nunca en el argv (visible con `docker top`/`ps`).
   - **Grupos.** `samba-tool group listmembers` para `GG-Medica`, `GG-Operaciones` y `GG-RRHH` debe devolver exactamente los
     usuarios de prueba esperados de cada grupo.
   - **Prueba NEGATIVA de membresía.** `vet.prueba` (solo en `GG-Medica`) no debe poder entrar en InvenTree (exige
     `GG-Operaciones`) ni en ERPNext (exige `GG-RRHH`): reutiliza el mecanismo HTTP de `ldaplogin.py` con un usuario válido
     pero sin el grupo que exige el filtro `memberOf` de cada app. Hoy es el **único control de acceso entre departamentos**.
6. **Consolidación.** Invoca `ldapprobe.py HOST PUERTO` (bind anónimo + búsqueda al rootDSE: AD no permite búsqueda anónima
   en el resto del árbol) contra `HOST_IP:LDAP_PORT` y contra la IP fija del DC, `probe.py` contra las cuatro aplicaciones
   por `HOST_IP:puerto`, y `ldaplogin.py --persistencia` (caso 4); no los duplica. `ldaplogin.py` hace su `ldapsearch` por
   `ldaps://ldap.reservaviva.lan:LDAPS_PORT`.

## Cómo se lee un resultado (esto decide si la prueba vale algo)

Un puerto cerrado y un destino mudo dan resultados parecidos y significan cosas distintas. Por eso:

- Cada conexión se clasifica: `ABIERTO`, `RECHAZADO` (RST: el destino existe y contesta), `SIN_RESPUESTA` (timeout) o
  `SIN_RUTA` (ICMP/sin ruta). En TLS: `VERIFICADO`, `TLS_FALLA` (el handshake o la verificación fallan) o `SIN_CONEXION`.
- **Un negativo solo es PASS con dos controles positivos**: (a) el origen alcanza `HOST_IP` (el proxy contesta) y (b) el
  servicio sí escucha dentro de su red, por su nombre. Sin ellos, un puerto cerrado es **FAIL "inconcluyente"**, no PASS. Si
  otro servicio del anfitrión usa justo ese puerto (p. ej. un PostgreSQL local en el 5432), el negativo da FAIL y la
  evidencia lo dice.
- En DNS, NXDOMAIN (rcode 3 autoritativo) ≠ REFUSED (rcode 5) ≠ timeout: los tres se distinguen y se exigen por separado.
- En NTP, un cliente que recibe respuesta con LI=3 ("no sincronizado") o stratum fuera de 1–15 la rechazaría: FAIL.
  Si `chronyd -Q` responde "No suitable source", el cliente rechazó al servidor: es un **hallazgo**, no un fallo del guion.

## Hallazgos (leer los `INFO`; observados en las pasadas de [`../docs/resultados-un-host.md`](../docs/resultados-un-host.md))

- **Los contenedores tienen recursión en bind9.** La delegación real de `ad.reservaviva.lan` exige `recursion yes`; BIND no
  permite acotarla a una zona. Que `example.com` no resuelva depende de la zona `.` vacía, no de la red (esta red tiene
  salida a Internet). El anfitrión y la LAN no tienen recursión.
- **H21 (resuelto): la zona ya no hereda las IP del diseño de 3 equipos.** Hoy `levantar-sistema.sh` genera la zona con
  `HOST_IP` y los 7 nombres deben dar PASS.
- **H11**: `/opt/startup.sh` de la imagen NTP escribe `server 127.127.1.1` **y** `local stratum 10`. `127.127.1.1` es notación de
  ntpd para el reloj local; chrony lo trata como un servidor normal e inalcanzable. Lo que sirve hora es `local stratum 10`,
  así que el stratum publicado debe ser 10. El guion lo comprueba (`chronyc tracking`) y muestra `chronyc sources`.

## Qué NO puede demostrar un solo host

**"Pasa en un host" no es "pasa en el laboratorio".** Quedan fuera y no se prueban:

- **Segmentación entre departamentos:** ya no existe. Todos los contenedores comparten una red y todo lo publicado queda
  accesible en `HOST_IP`; no hay nada que demostrar, y el guion no lo finge.
- El **switch físico** del laboratorio (que fija la IP y reparte puertos).
- El acceso **desde otro equipo** de la LAN. El guion prueba desde el propio anfitrión y desde contenedores, contra lo que
  Docker publica; que un equipo distinto llegue depende además de WSL en modo `mirrored`, del cortafuegos de Windows y de
  Hyper-V y de Portmaster. Esa prueba la hace el usuario ([`../docs/operacion.md`](../docs/operacion.md#acceso-desde-la-lan)).

## Estado de verificación

| Qué | Estado |
|---|---|
| Cliente DNS por UDP (compresión, NXDOMAIN, REFUSED, timeout) y por TCP, cliente SNTP, paso del puerto en la sonda, handshake TLS (fallos), lectura de `PortBindings`, lector de la zona, extracción del estático del HTML | **Verificado** con `--autotest` en WSL contra sockets locales (PASS). En Windows el caso "puerto cerrado" falla por un artefacto de loopback (sin RST inmediato); en Linux/WSL pasa. |
| Todo lo que toca contenedores con el compose nuevo (bloques 1-6) | Ver la sección del 04/10/2026 de [`../docs/resultados-un-host.md`](../docs/resultados-un-host.md) |
| Pasadas del 26/09, 27/09 y 01/10/2026 | Corresponden al diseño anterior (redes por departamento); se conservan como registro en [`../docs/resultados-un-host.md`](../docs/resultados-un-host.md) |
