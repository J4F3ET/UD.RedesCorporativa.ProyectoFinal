# Reserva Viva: intranet segmentada del Zoológico

Proyecto final de Redes Corporativas (UD, grupo 678-302). Es la intranet del Zoológico "Reserva Viva", una empresa ficticia. Cuatro departamentos tienen cada uno su aplicación y su VLAN, y comparten un directorio central (Samba Active Directory, con LDAPS y Kerberos), DNS y NTP propios, sin depender de Internet.

| Departamento | Aplicación | VLAN | Subred |
|---|---|---|---|
| Unidad Médica Veterinaria | OpenVPMS | 10 | 10.10.10.0/24 |
| Taquilla y Boletería | Pretix | 20 | 10.10.20.0/24 |
| Logística y Almacén | InvenTree | 30 | 10.10.30.0/24 |
| Recursos Humanos | ERPNext (módulo HR) | 40 | 10.10.40.0/24 |
| Infraestructura (transversal) | Samba AD DC + CA interna, bind9, NTP | 99 | 10.10.99.0/24 |

Todo el sistema (26 servicios) corre **en un solo equipo**. Cada VLAN es una red bridge de Docker con su misma subred. Cada aplicación está en la VLAN de su departamento y además en la VLAN 99, para llegar a la infraestructura.

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

| Aplicación | Acceso directo (este equipo) | Por nombre (otros equipos, modo intranet) |
|---|---|---|
| OpenVPMS | http://localhost:18080/openvpms | http://openvpms.reservaviva.lan |
| ERPNext | http://localhost:18081 | http://rrhh.reservaviva.lan |
| Pretix | http://localhost:18082 | http://pretix.reservaviva.lan |
| InvenTree | http://localhost:18083 | http://inventree.reservaviva.lan |

**Modo local (por defecto).** Todo se publica en `127.0.0.1`: solo se entra desde el propio equipo, por el acceso directo.

**Modo intranet (opcional).** `.\levantar-sistema.ps1 -Intranet` (o `./levantar-sistema.sh --intranet`) publica el proxy
web (80) y el DNS del laboratorio (53) en la IP de la LAN, para que cualquier equipo entre por nombre usando ese DNS. En
Windows hay que preparar antes el equipo **una vez**, como administrador, con
[`sistema/habilitar-intranet-windows.ps1`](sistema/habilitar-intranet-windows.ps1) (WSL en modo `mirrored` y reglas de
cortafuegos). Con Docker Engine en WSL, el 53 lo atiende un reenviador de Windows (`sistema/reenviador-dns.ps1`) que
arranca y para el propio lanzador. Las contraseñas de laboratorio son públicas: úsalo solo en una red de laboratorio. Pasos, configuración de
los clientes y pruebas: [`docs/operacion.md`](docs/operacion.md#acceso-desde-la-lan).

Los usuarios aparecen al terminar el arranque. Las contraseñas de laboratorio, que son desechables, están en [`sistema/test.env`](sistema/test.env).

| Acción | Qué hace |
|---|---|
| `arrancar` (por defecto) | Prepara todo, levanta el sistema y espera a que esté sano |
| `verificar` | Comprueba la arquitectura contra el sistema en marcha (ver abajo). Con `--rapido` omite la prueba de persistencia |
| `estado` | Estado de cada servicio, modo de publicación (local o intranet) y direcciones de acceso |
| `detener` | Para los contenedores sin borrar datos |
| `borrar` | Borra contenedores **y datos**. Pide confirmación |
| `borrar-directorio` | Borra solo el contenedor y los volúmenes de Samba AD, para reprovisionar el dominio (solo en el `.sh`; [`docs/operacion.md`](docs/operacion.md#directorio-borrar-directorio)) |

## Qué demuestra `verificar`

[`sistema/verificar_arquitectura.py`](sistema/verificar_arquitectura.py) se ejecuta contra el sistema levantado. Lo que comprueba y cómo leer el resultado está en [`sistema/verificar_arquitectura.md`](sistema/verificar_arquitectura.md).

- **Segmentación:** cada departamento alcanza su propio servicio y no alcanza a los demás. Cada negativo se valida con controles positivos para que un timeout no pase por aislamiento.
- **DNS:** respuestas autoritativas de `reservaviva.lan` en sus dos vistas (IP de contenedor para las VLAN, IP del anfitrión para el resto), NXDOMAIN, la delegación de `ad.reservaviva.lan` a Samba AD, nada resuelto fuera de `reservaviva.lan`, y alcance solo desde la VLAN 99.
- **Acceso por nombre:** el proxy web solo está en la VLAN 99; por cada nombre sirve la página de login **y** un CSS o JS de la aplicación; un nombre desconocido da 404; y el acceso directo por `localhost` sigue funcionando.
- **NTP:** el servidor responde con un stratum válido, un cliente chrony real lo acepta, y solo es alcanzable desde la VLAN 99.
- **LDAP/LDAPS:** login LDAP real en ERPNext e InvenTree; clave errónea rechazada; `ldapsearch` por LDAPS que valida con la CA interna y falla con una CA ajena. También comprueba que todo sobrevive a un `down` + `up -d`.
- **Active Directory:** registros SRV de la zona AD resueltos por bind9 desde la VLAN 99, `kinit`/`klist` de un usuario real, pertenencia a los grupos `GG-*`, y la prueba negativa (un usuario de otro grupo no entra) en ERPNext e InvenTree.

El último resultado y las cifras de cada pasada están en [`docs/resultados-un-host.md`](docs/resultados-un-host.md).

**Lo que un solo equipo no puede demostrar:**

- El etiquetado 802.1Q y los puertos troncales.
- El switch físico.
- La matriz de firewall sobre interfaces reales.

Además, la VLAN 99 es un único dominio L2 compartido por las 4 aplicaciones. `verificar` lo reporta como `INFO`, porque es un hallazgo previsto del diseño.

## Documentación

- [`docs/arquitectura.md`](docs/arquitectura.md): los 26 servicios por departamento, las redes y sus IP, y los flujos de LDAP/Kerberos, DNS (con sus dos vistas y la delegación a Samba AD), NTP y el proxy web por nombre.
- [`docs/operacion.md`](docs/operacion.md): cómo arrancar, vigilar, detener y validar el sistema, cómo abrirlo a la LAN (modo intranet), y las trampas de Windows/WSL.
- [`docs/seguridad.md`](docs/seguridad.md): la CA interna, el directorio y LDAPS, las cuentas de servicio, los secretos de laboratorio y lo que un host no aísla.
- [`docs/aplicaciones.md`](docs/aplicaciones.md): cada aplicación con su departamento, URL, usuario inicial y particularidades.
- [`docs/directorio-activo.md`](docs/directorio-activo.md): el directorio Samba AD (realm, DNS, grupos, Kerberos, `samba-tool`), cómo autentican ERPNext e InvenTree, la guía de migración desde OpenLDAP, y por qué Pretix y OpenVPMS no usan LDAP.
- [`docs/resultados-un-host.md`](docs/resultados-un-host.md): las cifras medidas (arranque, memoria, pasadas de `verificar`) y los pendientes.

## Mapa del repositorio

```
levantar-sistema.sh / .ps1 / .cmd   # arranque plug and play (la lógica está en el .sh)
docker-compose.yml                  # el ÚNICO compose: los 26 servicios, agrupados por departamento
servicios/                          # una carpeta por servicio, con su README
  openvpms/                         # Médica (VLAN 10): Dockerfile, inicialización reanudable y su prueba
  pretix/                           # Taquilla (VLAN 20)
  inventree/                        # Logística (VLAN 30)
  erpnext/                          # RRHH (VLAN 40): prueba de erpnext-create-site
  samba-ad/                         # Infraestructura (VLAN 99): Samba AD DC (Dockerfile, provisión y siembra de OU, grupos y usuarios de prueba)
  bind9/                            # Infraestructura: named.conf (dos vistas) y plantillas de la zona reservaviva.lan
  ntp/                              # Infraestructura: servidor de hora
  proxy/                            # Infraestructura: proxy web por nombre (nginx)
  ca/                               # CA interna + certificado LDAPS (lo ejecuta levantar-sistema.sh)
sistema/                            # test.env (variables y claves de laboratorio), la verificación y los scripts de Windows del modo intranet
docs/                               # arquitectura, operación, seguridad, aplicaciones, directorio activo y resultados vigentes
diseno-red/                         # ANEXO: diseño con switch L2/L3, VLANs 802.1Q, matriz y diagramas (no se despliega)
```

Todo `docker compose` se ejecuta desde la raíz con `--env-file sistema/test.env`. En `docker-compose.yml` los servicios se agrupan por departamento, igual que en el diseño de la Entrega 1 (3 equipos), y cada VLAN es una red bridge.

## Diseño de red (anexo)

El diseño propuesto reparte los servicios en 3 equipos conectados a un switch con VLANs 802.1Q. La carpeta [`diseno-red/`](diseno-red/README.md) lo conserva:

- La matriz de segmentación: [`arquitectura-3-equipos-departamentos.md`](diseno-red/arquitectura-3-equipos-departamentos.md).
- Las recetas para un switch L3 (SVIs + ACL) o L2 (el equipo de infraestructura como router con nftables).
- Los simuladores que reproducen la matriz sobre el kernel de Linux (necesitan la imagen `nicolaka/netshoot`).
- Los diagramas de topología y de flujo: [`topologia-red.html`](diseno-red/diagramas/topologia-red.html) y [`flujo-datos-segmentacion.html`](diseno-red/diagramas/flujo-datos-segmentacion.html).

No se ha probado contra un switch real.

El despliegue en 3 PCs se retiró del repositorio el 26/09/2026 para reducir la curva de aprendizaje. Incluía los scripts `deploy.sh` por PC, los servicios systemd, los tutoriales, las guías de Windows y el paquete offline. Todo se puede recuperar del historial de git: cada commit que lo retiró indica cómo.

## Integración LDAP por aplicación

**ERPNext e InvenTree** autentican contra Samba AD por LDAPS con la CA interna, y solo entra quien pertenece al grupo de su departamento (`GG-RRHH`, `GG-Operaciones`). **Pretix y OpenVPMS** no se integran de forma limpia y usan administradores locales: es una limitación documentada. Detalle en [`docs/directorio-activo.md`](docs/directorio-activo.md); allí también está la guía para migrar un OpenLDAP con datos reales.

## Pendientes

La lista con su contexto está en [`docs/resultados-un-host.md`](docs/resultados-un-host.md#pendientes).
