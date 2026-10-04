# Reserva Viva: intranet del Zoológico

Proyecto final de Redes Corporativas (UD, grupo 678-302). Es la intranet del Zoológico "Reserva Viva", una empresa ficticia. Cuatro departamentos tienen cada uno su aplicación y comparten un directorio central (Samba Active Directory, con LDAPS y Kerberos), DNS y NTP propios, sin depender de Internet.

| Departamento | Aplicación | Puerto publicado |
|---|---|---|
| Unidad Médica Veterinaria | OpenVPMS | `OPENVPMS_PORT` (18080) |
| Taquilla y Boletería | Pretix | `PRETIX_PORT` (18082) |
| Logística y Almacén | InvenTree | `INVENTREE_PORT` (18083) |
| Recursos Humanos | ERPNext (módulo HR) | `ERPNEXT_PORT` (18081) |
| Infraestructura (transversal) | Samba AD DC + CA interna, bind9, NTP, proxy web | LDAP 1389, LDAPS 1636, DNS 1053, NTP 1123, proxy 80 |

Todo el sistema (26 servicios) corre **en un solo equipo**, con **una sola IP** (`HOST_IP`, la del equipo; `192.168.1.26` en el laboratorio) y **un puerto por servicio**. Es lo que obliga el switch del laboratorio. Los contenedores comparten una única red de Docker (`reservaviva`) y ya **no hay segmentación entre departamentos**: ver [`docs/seguridad.md`](docs/seguridad.md). Las bases de datos y Redis no se publican.

## Arranque rápido

**Requisitos.** Las cifras medidas están en [`docs/resultados-un-host.md`](docs/resultados-un-host.md).

- **Sistema:** Windows 11 con WSL2 y Docker Engine dentro de una distro (el entorno probado), o Docker Desktop con Git for Windows. En Linux o macOS, Docker Engine o Docker Desktop.
- **Docker Compose 2.24.4 o superior**, y `openssl` donde corre el `.sh`.
- **RAM:** el sistema completo necesita varios GB libres. El lanzador comprueba la memoria antes de arrancar y se niega si no hay suficiente (`-Forzar` salta la comprobación).
- **Disco:** del orden de una decena de GB para imágenes y datos.
- **Internet en el primer arranque**, que descarga las imágenes y construye la de OpenVPMS. Ese primer arranque es largo.
- En [`docs/operacion.md`](docs/operacion.md) están el `.wslconfig` recomendado, qué hacer tras reiniciar el PC y las trampas de Windows/WSL.

| Sistema | Cómo |
|---|---|
| Windows | Doble clic en **`levantar-sistema.cmd`**, o `.\levantar-sistema.ps1` en PowerShell |
| Linux / WSL / macOS | `./levantar-sistema.sh` |

El script hace todo lo necesario y se puede volver a ejecutar sin riesgo: si un arranque se corta, retoma donde quedó.

1. Genera lo que no va en git: la CA interna, el certificado LDAPS y las zonas DNS.
2. Construye la imagen de OpenVPMS.
3. Levanta los 26 servicios y **espera a que todos estén sanos**.
4. Crea el administrador de Pretix.
5. Muestra las direcciones de acceso.

| Aplicación | Acceso directo | Por nombre (con el DNS del sistema) |
|---|---|---|
| OpenVPMS | http://HOST_IP:18080/openvpms | http://openvpms.reservaviva.lan |
| ERPNext | http://HOST_IP:18081 | http://rrhh.reservaviva.lan |
| Pretix | solo por nombre o por `localhost` (ver abajo) | http://pretix.reservaviva.lan |
| InvenTree | http://HOST_IP:18083 | http://inventree.reservaviva.lan |

Las cuatro aplicaciones también se publican en `127.0.0.1` con el mismo puerto (`http://localhost:1808x`). Pretix responde 400 a cualquier `Host` que no sea `pretix.reservaviva.lan` o `localhost`: por `HOST_IP:18082` no entra, es una limitación conocida.

**IP de publicación.** Todo se publica en `HOST_IP` (variable de [`sistema/test.env`](sistema/test.env), `192.168.1.26` en el laboratorio): las cuatro aplicaciones, el proxy web (80), LDAP/LDAPS, el DNS y el NTP. Ya no existe un "modo local" frente a un "modo intranet". El equipo debe tener esa IP en una interfaz; si no, el arranque falla con un mensaje que indica `--ip`.

- `--ip X` (`-IP X` en PowerShell) sustituye `HOST_IP` solo en esa ejecución.
- `--intranet` (`-Intranet`) autodetecta la IP de la LAN y la usa como `HOST_IP`.

En Windows hay que preparar antes el equipo **una vez**, como administrador, con
[`sistema/habilitar-intranet-windows.ps1`](sistema/habilitar-intranet-windows.ps1) (WSL en modo `mirrored` y reglas de
cortafuegos). Con Docker Engine en WSL, si `DNS_PORT` no es 53, el 53 de la LAN lo atiende un reenviador de Windows (`sistema/reenviador-dns.ps1`) que
arranca y para el propio lanzador. Las contraseñas de laboratorio son públicas y todo queda accesible desde la LAN: úsalo solo en una red de laboratorio. Pasos, configuración de
los clientes y pruebas: [`docs/operacion.md`](docs/operacion.md#acceso-desde-la-lan).

Los usuarios aparecen al terminar el arranque. Las contraseñas de laboratorio, que son desechables, están en [`sistema/test.env`](sistema/test.env).

| Acción | Qué hace |
|---|---|
| `arrancar` (por defecto) | Prepara todo, levanta el sistema y espera a que esté sano |
| `verificar` | Comprueba la arquitectura contra el sistema en marcha (ver abajo). Con `--rapido` omite la prueba de persistencia |
| `estado` | Estado de cada servicio, `HOST_IP` en uso y direcciones de acceso |
| `detener` | Para los contenedores sin borrar datos |
| `borrar` | Borra contenedores **y datos**. Pide confirmación |
| `borrar-directorio` | Borra solo el contenedor y los volúmenes de Samba AD, para reprovisionar el dominio ([`docs/operacion.md`](docs/operacion.md#directorio-borrar-directorio)) |

## Qué demuestra `verificar`

[`sistema/verificar_arquitectura.py`](sistema/verificar_arquitectura.py) se ejecuta contra el sistema levantado. Lo que comprueba y cómo leer el resultado está en [`sistema/verificar_arquitectura.md`](sistema/verificar_arquitectura.md).

- **Puertos (una IP, un puerto por servicio):** cada servicio está abierto en `HOST_IP:puerto` desde el host y desde un contenedor de la red; InvenTree y ERPNext llegan a `HOST_IP:LDAPS_PORT` con TLS validado con la CA; las bases de datos y Redis no tienen puertos publicados y están cerrados en `HOST_IP`.
- **DNS:** una sola zona `reservaviva.lan` cuyos nombres apuntan a `HOST_IP`, consultada en `HOST_IP:DNS_PORT` por UDP y TCP; NXDOMAIN, la delegación de `ad.reservaviva.lan` a Samba AD y nada resuelto fuera de la zona.
- **Acceso por nombre:** el proxy web sirve por cada nombre la página de login **y** un CSS o JS de la aplicación; un nombre desconocido da 404; y el acceso directo por `localhost` sigue funcionando.
- **NTP:** el servidor responde con un stratum válido en `HOST_IP:NTP_PORT` y un cliente chrony real lo acepta.
- **LDAP/LDAPS:** login LDAP real en ERPNext e InvenTree; clave errónea rechazada; `ldapsearch` por LDAPS que valida con la CA interna y falla con una CA ajena. También comprueba que todo sobrevive a un `down` + `up -d`.
- **Active Directory:** registros SRV de la zona AD resueltos por bind9 desde un contenedor de la red, `kinit`/`klist` de un usuario real, pertenencia a los grupos `GG-*`, y la prueba negativa (un usuario de otro grupo no entra) en ERPNext e InvenTree.

El último resultado y las cifras de cada pasada están en [`docs/resultados-un-host.md`](docs/resultados-un-host.md).

**Lo que `verificar` no demuestra:** la segmentación entre departamentos, porque ya no existe (decisión impuesta por el switch del laboratorio, 04/10/2026). Tampoco prueba el switch físico. Lo que sí garantiza es que cada servicio está donde dice (puerto abierto) y que las bases de datos no están expuestas.

## Documentación

- [`docs/arquitectura.md`](docs/arquitectura.md): los 26 servicios por departamento, la red única, los puertos publicados y los flujos de LDAP/Kerberos, DNS (una zona y la delegación a Samba AD), NTP y el proxy web por nombre.
- [`docs/operacion.md`](docs/operacion.md): cómo arrancar, vigilar, detener y validar el sistema, `HOST_IP`, `--ip` y `--intranet`, el acceso desde la LAN, y las trampas de Windows/WSL.
- [`docs/seguridad.md`](docs/seguridad.md): la CA interna, el directorio y LDAPS, las cuentas de servicio, los secretos de laboratorio y que ya no hay aislamiento de red entre departamentos.
- [`docs/aplicaciones.md`](docs/aplicaciones.md): cada aplicación con su departamento, URL, usuario inicial y particularidades.
- [`docs/directorio-activo.md`](docs/directorio-activo.md): el directorio Samba AD (realm, DNS, grupos, Kerberos, `samba-tool`), cómo autentican ERPNext e InvenTree, la guía de migración desde OpenLDAP, y por qué Pretix y OpenVPMS no usan LDAP.
- [`docs/resultados-un-host.md`](docs/resultados-un-host.md): las cifras medidas (arranque, memoria, pasadas de `verificar`) y los pendientes.

## Mapa del repositorio

```
levantar-sistema.sh / .ps1 / .cmd   # arranque plug and play (la lógica está en el .sh)
docker-compose.yml                  # el ÚNICO compose: los 26 servicios, agrupados por departamento
servicios/                          # una carpeta por servicio, con su README
  openvpms/                         # Médica: Dockerfile, inicialización reanudable y su prueba
  pretix/                           # Taquilla
  inventree/                        # Logística
  erpnext/                          # RRHH: prueba de erpnext-create-site
  samba-ad/                         # Infraestructura: Samba AD DC (Dockerfile, provisión y siembra de OU, grupos y usuarios de prueba)
  bind9/                            # Infraestructura: named.conf (una vista) y plantillas de la zona reservaviva.lan
  ntp/                              # Infraestructura: servidor de hora
  proxy/                            # Infraestructura: proxy web por nombre (nginx)
  ca/                               # CA interna + certificado LDAPS (lo ejecuta levantar-sistema.sh)
sistema/                            # test.env (variables y claves de laboratorio), la verificación y los scripts de Windows para abrirlo a la LAN
docs/                               # arquitectura, operación, seguridad, aplicaciones, directorio activo y resultados vigentes
diseno-red/                         # HISTÓRICO: diseño con VLAN 802.1Q, sustituido el 04/10/2026 (no se despliega)
```

Todo `docker compose` se ejecuta desde la raíz con `--env-file sistema/test.env`. En `docker-compose.yml` los servicios se agrupan por departamento y comparten la red `reservaviva` (más `erpnext_internal` para ERPNext).

## Diseño de red anterior (histórico)

La carpeta [`diseno-red/`](diseno-red/README.md) conserva, como registro, el diseño original de 3 equipos conectados a un switch con VLAN 802.1Q, con su matriz de segmentación, recetas de switch, simuladores y diagramas. **El 04/10/2026 ese diseño se sustituyó** por una IP y un puerto por servicio, porque el switch del laboratorio no admite VLAN. No describe el sistema vigente y nunca se probó contra un switch real.

El despliegue en 3 PCs se retiró del repositorio el 26/09/2026. Todo se puede recuperar del historial de git: cada commit que lo retiró indica cómo.

## Integración LDAP por aplicación

**ERPNext e InvenTree** autentican contra Samba AD por LDAPS con la CA interna, y solo entra quien pertenece al grupo de su departamento (`GG-RRHH`, `GG-Operaciones`). **Pretix y OpenVPMS** no se integran de forma limpia y usan administradores locales: es una limitación documentada. Detalle en [`docs/directorio-activo.md`](docs/directorio-activo.md); allí también está la guía para migrar un OpenLDAP con datos reales.

## Pendientes

La lista con su contexto está en [`docs/resultados-un-host.md`](docs/resultados-un-host.md#pendientes).
