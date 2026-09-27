# Aplicaciones de Reserva Viva

Guía de las cuatro aplicaciones de la intranet: para qué sirve cada una en el zoológico, qué contenedores la forman, cómo se entra la primera vez y qué hay que saber antes de usarla. Supone que el sistema ya está en marcha con `levantar-sistema` (ver [operacion.md](operacion.md)).

Todas las direcciones son de `localhost`: los puertos se publican solo en `127.0.0.1` (`PUBLISH_IP` de [`sistema/test.env`](../sistema/test.env)), así que se entra desde el propio equipo. Los servicios están definidos en el [`docker-compose.yml`](../docker-compose.yml) de la raíz, agrupados por departamento. Las redes, las IP y los flujos entre servicios están en [arquitectura.md](arquitectura.md).

## Resumen

| Aplicación | Departamento | VLAN | URL | Usuario inicial | Variable de `test.env` con su clave | ¿LDAP? |
|---|---|---|---|---|---|---|
| OpenVPMS | Unidad Médica Veterinaria | 10 | http://localhost:18080/openvpms | `admin` | `OPENVPMS_ADMIN_PASSWORD` | No |
| Pretix | Taquilla y Boletería | 20 | http://localhost:18082 | `admin@reservaviva.local` (`PRETIX_ADMIN_EMAIL`) | `PRETIX_ADMIN_PASSWORD` | No |
| InvenTree | Logística y Almacén | 30 | http://localhost:18083 | `admin` | `INVENTREE_ADMIN_PASSWORD` | Sí (LDAPS) |
| ERPNext (HR) | Recursos Humanos | 40 | http://localhost:18081 | `Administrator` | `ERPNEXT_ADMIN_PASSWORD` | Sí (LDAPS) |

Los puertos salen de `OPENVPMS_PORT`, `PRETIX_PORT`, `INVENTREE_PORT` y `ERPNEXT_PORT` en `test.env`. El script repite esta tabla al terminar el arranque (`levantar-sistema.sh`, función `accesos`).

Las claves de los administradores son de laboratorio y desechables. Viven en [`sistema/test.env`](../sistema/test.env): este documento nunca las copia. Cómo se gestionan y cuándo rotarlas está en [seguridad.md](seguridad.md).

## OpenVPMS: Unidad Médica Veterinaria

**Qué es.** OpenVPMS es un sistema de gestión de clínicas veterinarias. En Reserva Viva sustituye a los expedientes en papel: los veterinarios llevan las historias clínicas, los esquemas de vacunación, los tratamientos y los diagnósticos de las especies del zoológico desde cualquier terminal de la red, con trazabilidad de la salud animal (Entrega 1, objetivo principal y §3.2.1).

**Contenedores** (carpeta [`servicios/openvpms/`](../servicios/openvpms/)):

| Contenedor | Imagen | Función |
|---|---|---|
| `openvpms-app` | propia, construida con [`servicios/openvpms/Dockerfile`](../servicios/openvpms/Dockerfile): Tomcat 9 + Java 11 + OpenVPMS 2.4.0.1 | Aplicación web, puerto 8080 publicado en 18080 |
| `openvpms-db` | `mysql:8.0.46` | Base de datos |

OpenVPMS no publica imagen Docker. El `Dockerfile` descarga el release oficial y el driver JDBC de MySQL al construir, así que el primer build necesita Internet una vez.

**Primera entrada.** En http://localhost:18080/openvpms, con el usuario `admin` y la clave de `OPENVPMS_ADMIN_PASSWORD`. El `entrypoint.sh` la fija en cada inicialización con `toolbox user --setpassword admin` y rechaza arrancar si no cumple la política de OpenVPMS: mínimo 8 caracteres, con mayúscula, minúscula, número y un carácter especial.

**LDAP: no.** OpenVPMS 2.4.0.1 no trae soporte LDAP: sus usuarios viven en la base MySQL. Ningún usuario LDAP de prueba entra aquí, tampoco `vet.prueba`, aunque exista en `ou=medica`. La evaluación completa está en [ldap-pretix-openvpms.md](ldap-pretix-openvpms.md).

**Particularidades.**

- **Primer arranque lento.** Con la base vacía, OpenVPMS crea el esquema (unos 5 minutos), carga los datos base, fija la clave de `admin`, instala las plantillas y despliega el WAR. Solo entonces responde `/openvpms/login` y el contenedor pasa a `healthy`. Es el paso más largo y el de más memoria de todo el arranque. Las cifras medidas están en [resultados-un-host.md](resultados-un-host.md).
- **Arranque reanudable.** La inicialización va por etapas con marcas en el volumen `openvpms_state`. Si se corta, el siguiente arranque retoma donde quedó (`servicios/openvpms/init-lib.sh`, probado por `test-reanudable.sh`).
- **Heap de Tomcat.** El compose fija `CATALINA_OPTS` por debajo del valor del `Dockerfile` para ajustarse a la carga del laboratorio.

## Pretix: Taquilla y Boletería

**Qué es.** Pretix es un sistema de venta de entradas. La taquilla lo usa para vender entradas, gestionar el ingreso diario de visitantes y controlar el aforo en tiempo real. Al ejecutarse en un servidor local, sigue vendiendo sin conexión a Internet (Entrega 1, §3.1.2.7 y §3.2.1). La Entrega 1 habla de "PretixPOS": el repositorio despliega el servidor de Pretix; la aplicación de caja PretixPOS no está incluida.

**Contenedores** (carpeta [`servicios/pretix/`](../servicios/pretix/)):

| Contenedor | Imagen | Función |
|---|---|---|
| `pretix-web` | `pretix/standalone:stable`, fijada por digest (pretix 2026.7.0) | Web (nginx + gunicorn), puerto 80 publicado en 18082. Migra la base al arrancar |
| `pretix-worker` | la misma | Tareas de celery: pagos, correos, PDF |
| `pretix-cron` | la misma | Ejecuta `pretix cron` (tareas periódicas) cada 15 minutos |
| `pretix-db` | `postgres:15.19` | Base de datos |
| `pretix-redis` | `redis:7.4.11` | Caché, sesiones y cola de celery |

**Primera entrada.** En http://localhost:18082 (el panel de administración es `/control/`), con el correo `admin@reservaviva.local` (`PRETIX_ADMIN_EMAIL`) y la clave de `PRETIX_ADMIN_PASSWORD`.

**LDAP: no.** Pretix no trae backend LDAP. El único plugin disponible es de terceros y no verifica el certificado del servidor, así que no se integró. Detalle en [ldap-pretix-openvpms.md](ldap-pretix-openvpms.md). El usuario `taquilla.prueba` existe en el directorio, pero no sirve para entrar en Pretix.

**Particularidades.**

- **El administrador lo crea el script, no la imagen (H19).** La imagen de Pretix trae de fábrica un superusuario `admin@localhost` con una clave conocida. Tras el arranque, `levantar-sistema.sh` (función `crear_admin_pretix`) crea `admin@reservaviva.local` si no existe y **borra `admin@localhost`**. Si Pretix se levanta a mano con `docker compose up` sin el script, ese paso no ocurre: hay que ejecutar el script o repetirlo a mano.
- **Primer arranque.** `pretix-web` migra la base antes de responder. Por eso `pretix-worker` y `pretix-cron` esperan a que esté `healthy`.
- **URL de Pretix e InvenTree (H20, resuelto en `41d54ef`).** `PRETIX_PRETIX_URL` e `INVENTREE_SITE_URL` apuntaban a la IP de `inventree-app` (resto del diseño de 3 equipos), lo que hacía responder 500 (INVE-E7) a la interfaz `/web` de InvenTree, y pasaron a ser `http://localhost:<puerto>`. Como Pretix solo acepta el `Host` de esa URL (o `localhost`), hay que entrar por http://localhost:18082 y no por `127.0.0.1`, que responde 400.

## InvenTree: Logística y Almacén

**Qué es.** InvenTree es un sistema de inventario. Logística lo usa para controlar en tiempo real el stock de alimentos, insumos veterinarios y material, los proveedores y las compras, con trazabilidad de lotes y fechas de vencimiento (Entrega 1, §3.1.2.7 y §3.2.1).

**Contenedores** (carpeta [`servicios/inventree/`](../servicios/inventree/)):

| Contenedor | Imagen | Función |
|---|---|---|
| `inventree-app` | `inventree/inventree:1.5.5` | Web y API (gunicorn), puerto 8000 publicado en 18083. Habla LDAPS con OpenLDAP |
| `inventree-worker` | la misma | Tareas en segundo plano: correo, importaciones, informes |
| `inventree-db` | `postgres:15.19` | Base de datos |

**Primera entrada.** En http://localhost:18083, con el usuario `admin` y la clave de `INVENTREE_ADMIN_PASSWORD`. InvenTree crea este superusuario al arrancar si no existe. El nombre sale de `INVENTREE_ADMIN_USER`, que `test.env` no define, así que se usa el valor por defecto del compose, `admin`.

**LDAP: sí.** Autentica contra OpenLDAP por LDAPS, verificando la cadena con la CA interna, y busca a los usuarios solo en `ou=operaciones`. Detalle y pruebas en [integracion-ldap-erpnext-inventree.md](integracion-ldap-erpnext-inventree.md).

- Probado: `logistica.prueba` entra y `rrhh.prueba` es rechazado (otra OU).
- `taquilla.prueba` también está en `ou=operaciones`, así que por configuración también entraría. **No verificado.**
- Las claves de estos usuarios están en [`servicios/openldap/README.md`](../servicios/openldap/README.md).
- Un usuario LDAP se crea en InvenTree en su primer login, **sin permisos**: el administrador tiene que asignárselos.

**Particularidades.** `inventree-worker` espera a que `inventree-app` esté `healthy` para no competir con él por las migraciones. `INVENTREE_AUTO_UPDATE` aplica las migraciones al arrancar.

## ERPNext (HR): Recursos Humanos

**Qué es.** ERPNext es un ERP. Recursos Humanos usa el módulo de gestión de personal para los expedientes digitales de los colaboradores (hojas de vida y contratos) y la programación de turnos rotativos que cubren el zoológico 24/7 (Entrega 1, §3.1.2.7 y §3.2.1). Los turnos no están en ERPNext sino en la app `hrms`, que por eso va instalada en el sitio.

**Contenedores** (carpeta [`servicios/erpnext/`](../servicios/erpnext/)). Salvo la base y los Redis, todos usan la imagen oficial `ghcr.io/frappe/hrms:v15.64.1` (frappe 15.121.0, erpnext 15.121.3 y hrms 15.64.1):

| Contenedor | Función |
|---|---|
| `erpnext-hr` | nginx, puerto 8080 publicado en 18081. Único punto de entrada web |
| `erpnext-backend` | Aplicación Frappe. Es quien habla LDAPS con OpenLDAP |
| `erpnext-websocket` | Tiempo real (socket.io) |
| `erpnext-scheduler`, `erpnext-queue-short`, `erpnext-queue-long` | Tareas programadas y colas de trabajo |
| `erpnext-db` (`mariadb:10.6.28`), `erpnext-redis-cache` y `erpnext-redis-queue` (`redis:7.4.11`) | Base de datos y Redis, en una red privada |
| `erpnext-configurator`, `erpnext-create-site`, `erpnext-ldap-config` | Trabajos de un solo disparo que terminan en `Exited (0)` |

**Primera entrada.** En http://localhost:18081, con el usuario `Administrator` y la clave de `ERPNEXT_ADMIN_PASSWORD`. El sitio se llama `rrhh.reservaviva.local` y nginx lo sirve para cualquier nombre de host, así que `localhost` funciona.

**LDAP: sí.** `erpnext-ldap-config` deja configurado "LDAP Settings" de Frappe: LDAPS con la CA interna y búsqueda solo en `ou=rrhh`. Detalle y pruebas en [integracion-ldap-erpnext-inventree.md](integracion-ldap-erpnext-inventree.md).

- Probado por la API: `rrhh.prueba` entra, y `logistica.prueba` y `vet.prueba` son rechazados.
- La clave de `rrhh.prueba` está en [`servicios/openldap/README.md`](../servicios/openldap/README.md).
- El botón "Login with LDAP" del formulario `/login` no se ha probado en el navegador.
- El usuario se crea en el primer login y sin permisos útiles: falta asignarle un empleado y sus roles de HR.

**Particularidades.**

- **Primer arranque lento.** `erpnext-create-site` crea el sitio con `bench new-site` e instala `erpnext` y `hrms`. Hasta que termina, la web devuelve error y los demás contenedores de ERPNext no arrancan. Las cifras están en [resultados-un-host.md](resultados-un-host.md).
- **Creación idempotente.** El trabajo solo da el sitio por completo si encuentra su marca `.reservaviva-sitio-completo`. Ante un sitio a medias se detiene con instrucciones y no borra nada solo. El caso está cubierto por `servicios/erpnext/test-create-site.sh`.
- **Scheduler.** `bench new-site` lo deja apagado, así que el trabajo lo enciende en cada arranque.

## Infraestructura compartida

Las cuatro aplicaciones comparten tres servicios en la VLAN 99. Cada aplicación está en la VLAN de su departamento y en la VLAN 99 para llegar a ellos. Direcciones, reglas y flujos, en [arquitectura.md](arquitectura.md). La CA y las cuentas de servicio, en [seguridad.md](seguridad.md).

| Servicio | Contenedor | Carpeta | Puerto en el equipo | Uso |
|---|---|---|---|---|
| OpenLDAP (`osixia/openldap:1.5.0`) | `openldap` | [`servicios/openldap/`](../servicios/openldap/) | `localhost:1389` (LDAP) y `localhost:1636` (LDAPS) | Directorio `dc=reservaviva,dc=local`, una OU por departamento |
| bind9 9.18 | `dns-interno` | [`servicios/bind9/`](../servicios/bind9/) | `localhost:1053` (UDP y TCP) | Zona autoritativa `reservaviva.local` |
| NTP (`cturra/ntp`) | `ntp-interno` | [`servicios/ntp/`](../servicios/ntp/) | `localhost:1123/udp` | Hora de referencia local (stratum 10) |

Usuarios de prueba del directorio, sin sus claves:

| `uid` | OU | Aplicación en la que entra |
|---|---|---|
| `vet.prueba` | `ou=medica` | Ninguna (OpenVPMS no usa LDAP) |
| `logistica.prueba` | `ou=operaciones` | InvenTree |
| `taquilla.prueba` | `ou=operaciones` | InvenTree por configuración (no verificado); Pretix no usa LDAP |
| `rrhh.prueba` | `ou=rrhh` | ERPNext |

Las aplicaciones buscan a los usuarios con la cuenta de solo lectura `cn=svc-lectura,ou=servicios`, cuya clave está en `INVENTREE_LDAP_BIND_PASSWORD` y `ERPNEXT_LDAP_BIND_PASSWORD`. Los LDIF solo se cargan con el volumen `ldap_data` vacío.
