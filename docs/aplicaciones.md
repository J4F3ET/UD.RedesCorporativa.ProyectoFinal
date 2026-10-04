# Aplicaciones de Reserva Viva

Guía de las cuatro aplicaciones de la intranet: para qué sirve cada una en el zoológico, qué contenedores la forman, cómo se entra la primera vez y qué hay que saber antes de usarla. Supone que el sistema ya está en marcha con `levantar-sistema` (ver [operacion.md](operacion.md)).

Cada aplicación tiene dos entradas. El **acceso directo** por `HOST_IP:puerto` (la IP del equipo, variable `HOST_IP` de [`sistema/test.env`](../sistema/test.env)), que además se publica en `127.0.0.1` con el mismo puerto (`http://localhost:<puerto>`), es el de administración. El **acceso por nombre** (`*.reservaviva.lan`, a través del proxy web en `HOST_IP:80`) es el que usan los demás equipos de la LAN con el DNS del sistema ([operacion.md](operacion.md#acceso-desde-la-lan)). Los servicios están definidos en el [`docker-compose.yml`](../docker-compose.yml) de la raíz, agrupados por departamento. La red, los puertos y los flujos entre servicios están en [arquitectura.md](arquitectura.md).

## Resumen

| Aplicación | Departamento | Por nombre (LAN) | Acceso directo (`HOST_IP` o `localhost`) | Usuario inicial | Variable de `test.env` con su clave | ¿LDAP? |
|---|---|---|---|---|---|---|
| OpenVPMS | Unidad Médica Veterinaria | http://openvpms.reservaviva.lan | http://HOST_IP:18080/openvpms | `admin` | `OPENVPMS_ADMIN_PASSWORD` | No |
| Pretix | Taquilla y Boletería | http://pretix.reservaviva.lan | http://localhost:18082 (por `HOST_IP:18082` da 400) | `admin@reservaviva.local` (`PRETIX_ADMIN_EMAIL`) | `PRETIX_ADMIN_PASSWORD` | No |
| InvenTree | Logística y Almacén | http://inventree.reservaviva.lan | http://HOST_IP:18083 | `admin` | `INVENTREE_ADMIN_PASSWORD` | Sí (LDAPS) |
| ERPNext (HR) | Recursos Humanos | http://rrhh.reservaviva.lan | http://HOST_IP:18081 | `Administrator` | `ERPNEXT_ADMIN_PASSWORD` | Sí (LDAPS) |

Los puertos del acceso directo salen de `OPENVPMS_PORT`, `PRETIX_PORT`, `INVENTREE_PORT` y `ERPNEXT_PORT` en `test.env`. El script repite esta tabla al terminar el arranque (`levantar-sistema.sh`, función `accesos`), con la `HOST_IP` en uso y las URL por nombre. El correo del administrador de Pretix conserva el sufijo `.local`: es un identificador guardado en su base, no un nombre DNS ([arquitectura.md](arquitectura.md#identificadores-con-el-sufijo-antiguo)).

Las claves de los administradores son de laboratorio y desechables. Viven en [`sistema/test.env`](../sistema/test.env): este documento nunca las copia. Cómo se gestionan y cuándo rotarlas está en [seguridad.md](seguridad.md).

## OpenVPMS: Unidad Médica Veterinaria

**Qué es.** OpenVPMS es un sistema de gestión de clínicas veterinarias. En Reserva Viva sustituye a los expedientes en papel: los veterinarios llevan las historias clínicas, los esquemas de vacunación, los tratamientos y los diagnósticos de las especies del zoológico desde cualquier terminal de la red, con trazabilidad de la salud animal (Entrega 1, objetivo principal y §3.2.1).

**Contenedores** (carpeta [`servicios/openvpms/`](../servicios/openvpms/)):

| Contenedor | Imagen | Función |
|---|---|---|
| `openvpms-app` | propia, construida con [`servicios/openvpms/Dockerfile`](../servicios/openvpms/Dockerfile): Tomcat 9 + Java 11 + OpenVPMS 2.4.0.1 | Aplicación web, puerto 8080 publicado en 18080; por nombre, `openvpms.reservaviva.lan` (la raíz lleva a `/openvpms/`) |
| `openvpms-db` | `mysql:8.0.46` | Base de datos |

OpenVPMS no publica imagen Docker. El `Dockerfile` descarga el release oficial y el driver JDBC de MySQL al construir, así que el primer build necesita Internet una vez.

**Primera entrada.** En http://localhost:18080/openvpms, con el usuario `admin` y la clave de `OPENVPMS_ADMIN_PASSWORD`. El `entrypoint.sh` la fija en cada inicialización con `toolbox user --setpassword admin` y rechaza arrancar si no cumple la política de OpenVPMS: mínimo 8 caracteres, con mayúscula, minúscula, número y un carácter especial.

**LDAP: no.** OpenVPMS 2.4.0.1 no trae soporte LDAP: sus usuarios viven en la base MySQL. Ningún usuario LDAP de prueba entra aquí, tampoco `vet.prueba`, aunque exista en `OU=Medica` y en `GG-Medica`. La evaluación completa está en [directorio-activo.md](directorio-activo.md#openvpms-2401-sin-soporte-ldap).

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

**Primera entrada.** En http://localhost:18082 o http://pretix.reservaviva.lan (el panel de administración es `/control/`), con el correo `admin@reservaviva.local` (`PRETIX_ADMIN_EMAIL`) y la clave de `PRETIX_ADMIN_PASSWORD`.

**LDAP: no.** Pretix no trae backend LDAP. El único plugin disponible es de terceros y no verifica el certificado del servidor, así que no se integró. Detalle en [directorio-activo.md](directorio-activo.md#pretix-solo-con-un-plugin-de-terceros-que-no-verifica-tls). El usuario `taquilla.prueba` existe en el directorio, pero no sirve para entrar en Pretix.

**Particularidades.**

- **El administrador lo crea el script, no la imagen (H19).** La imagen de Pretix trae de fábrica un superusuario `admin@localhost` con una clave conocida. Tras el arranque, `levantar-sistema.sh` (función `crear_admin_pretix`) crea `admin@reservaviva.local` si no existe y **borra `admin@localhost`**. Si Pretix se levanta a mano con `docker compose up` sin el script, ese paso no ocurre: hay que ejecutar el script o repetirlo a mano.
- **Primer arranque.** `pretix-web` migra la base antes de responder. Por eso `pretix-worker` y `pretix-cron` esperan a que esté `healthy`.
- **URL de Pretix (H20).** `PRETIX_PRETIX_URL` es `http://pretix.reservaviva.lan`. Pretix solo acepta el `Host` de esa URL o `localhost` (`LOCAL_HOST_NAMES` de su middleware multidominio), así que funcionan el nombre y http://localhost:18082, pero no `127.0.0.1` ni `HOST_IP:18082`, que responden 400 (limitación conocida: se entra por nombre o por `localhost`). Comprobado el 27/09/2026: un login con credenciales inventadas se rechaza por credenciales, no por CSRF, por las dos entradas. Los enlaces absolutos que genere Pretix (correos, PDF) llevan el nombre.
- **Aviso "unexpected origin" en el log: inofensivo y esperado.** Pretix 2026.7.0 calcula el origen esperado sin puerto (`http://pretix.reservaviva.lan`, de `PRETIX_PRETIX_URL`) y lo compara con el que manda el navegador (por ejemplo `http://localhost:18082`). Al no coincidir, la vista de login y la vista `bad_origin_report` (`@csrf_exempt`) solo registran un `warning`; el resultado del login no depende de esa comparación, así que no lo bloquea.

## InvenTree: Logística y Almacén

**Qué es.** InvenTree es un sistema de inventario. Logística lo usa para controlar en tiempo real el stock de alimentos, insumos veterinarios y material, los proveedores y las compras, con trazabilidad de lotes y fechas de vencimiento (Entrega 1, §3.1.2.7 y §3.2.1).

**Contenedores** (carpeta [`servicios/inventree/`](../servicios/inventree/)):

| Contenedor | Imagen | Función |
|---|---|---|
| `inventree-app` | `inventree/inventree:1.5.5` | Web y API (gunicorn), puerto 8000 publicado en 18083; por nombre, `inventree.reservaviva.lan`. Habla LDAPS con Samba AD |
| `inventree-worker` | la misma | Tareas en segundo plano: correo, importaciones, informes |
| `inventree-db` | `postgres:15.19` | Base de datos |

**Primera entrada.** En http://localhost:18083 o http://inventree.reservaviva.lan, con el usuario `admin` y la clave de `INVENTREE_ADMIN_PASSWORD`. InvenTree crea este superusuario al arrancar si no existe. El nombre sale de `INVENTREE_ADMIN_USER`, que `test.env` no define, así que se usa el valor por defecto del compose, `admin`.

**LDAP: sí.** Autentica contra Samba AD por LDAPS, verificando la cadena con la CA interna, por `sAMAccountName`, y solo entra quien sea miembro directo del grupo `GG-Operaciones`. `inventree-app` espera a que `samba-ad` esté sano. Detalle y pruebas en [directorio-activo.md](directorio-activo.md#4-cómo-autentican-inventree-y-erpnext).

- Pertenecen a `GG-Operaciones` `logistica.prueba` y `taquilla.prueba`. `logistica.prueba` entra, y `vet.prueba` (`GG-Medica`) es rechazado: es la prueba negativa de `verificar`.
- `taquilla.prueba` también está en `GG-Operaciones`, así que por configuración también entraría. **No verificado.**
- Las claves de estos usuarios están en `sistema/test.env` (`LDAP_PRUEBA_<UID>_PASSWORD`; tabla en [directorio-activo.md](directorio-activo.md#3-objetos-del-directorio)).
- Un usuario LDAP se crea en InvenTree en su primer login, **sin permisos**: el administrador tiene que asignárselos.

**Particularidades.** `inventree-worker` espera a que `inventree-app` esté `healthy` para no competir con él por las migraciones. `INVENTREE_AUTO_UPDATE` aplica las migraciones al arrancar.

- **Dos orígenes (H20).** `INVENTREE_SITE_URL` es `http://inventree.reservaviva.lan`, y la interfaz `/web` responde 500 ("INVE-E7") a cualquier URL que no coincida con ella… salvo que haya más de un origen de confianza y la URL visitada sea uno de ellos. Por eso `INVENTREE_TRUSTED_ORIGINS` añade `http://localhost:<INVENTREE_PORT>`: `/web` y su JavaScript funcionan por las dos entradas (lo comprueba `verificar`), y un login con credenciales inventadas se rechaza por credenciales, no por CSRF, en las dos.

- **Estáticos (H22, resuelto).** `INVENTREE_AUTO_UPDATE` solo migra: no recoge los estáticos, y la interfaz `/web` fallaba con "INVE-E1" porque `/static/web/assets/*.js` redirigía a `/web`. Ahora el `command` de `inventree-app` ejecuta `invoke static` antes de gunicorn. Detalle en [resultados-un-host.md](resultados-un-host.md).
- **`/media` sin servir (defecto latente).** Sin `DEBUG`, nadie sirve `/media`: las imágenes de artículos y los adjuntos que se suban no se verán. Hoy solo existe `media/report` (plantillas de informes y etiquetas, que se usan en el servidor), así que no se pierde nada. Arreglarlo exige un proxy delante (un contenedor nuevo y la descarga de su imagen): pendiente de decisión del usuario.

## ERPNext (HR): Recursos Humanos

**Qué es.** ERPNext es un ERP. Recursos Humanos usa el módulo de gestión de personal para los expedientes digitales de los colaboradores (hojas de vida y contratos) y la programación de turnos rotativos que cubren el zoológico 24/7 (Entrega 1, §3.1.2.7 y §3.2.1). Los turnos no están en ERPNext sino en la app `hrms`, que por eso va instalada en el sitio.

**Contenedores** (carpeta [`servicios/erpnext/`](../servicios/erpnext/)). Salvo la base y los Redis, todos usan la imagen oficial `ghcr.io/frappe/hrms:v15.64.1` (frappe 15.121.0, erpnext 15.121.3 y hrms 15.64.1):

| Contenedor | Función |
|---|---|
| `erpnext-hr` | nginx, puerto 8080 publicado en 18081. Único punto de entrada web; el proxy llega a él por `HOST_IP:18081` para `rrhh.reservaviva.lan` |
| `erpnext-backend` | Aplicación Frappe. Es quien habla LDAPS con Samba AD |
| `erpnext-websocket` | Tiempo real (socket.io) |
| `erpnext-scheduler`, `erpnext-queue-short`, `erpnext-queue-long` | Tareas programadas y colas de trabajo |
| `erpnext-db` (`mariadb:10.6.28`), `erpnext-redis-cache` y `erpnext-redis-queue` (`redis:7.4.11`) | Base de datos y Redis, en una red privada |
| `erpnext-configurator`, `erpnext-create-site`, `erpnext-ldap-config` | Trabajos de un solo disparo que terminan en `Exited (0)` |

**Primera entrada.** En http://localhost:18081 o http://rrhh.reservaviva.lan, con el usuario `Administrator` y la clave de `ERPNEXT_ADMIN_PASSWORD`. El sitio de Frappe se llama `rrhh.reservaviva.local` (identificador interno que conserva el sufijo antiguo) y nginx lo elige por la cabecera `FRAPPE_SITE_NAME_HEADER`, no por el nombre de host, así que funciona con cualquiera. El tiempo real (socket.io) pasa también por el proxy (WebSocket).

**LDAP: sí.** `erpnext-ldap-config` deja configurado "LDAP Settings" de Frappe como "Active Directory": LDAPS con la CA interna, login por `sAMAccountName` y acceso solo para los miembros directos de `GG-RRHH`. Tanto `erpnext-ldap-config` como `erpnext-backend` esperan a que `samba-ad` esté sano. Detalle y pruebas en [directorio-activo.md](directorio-activo.md#4-cómo-autentican-inventree-y-erpnext).

- Probado por la API: `rrhh.prueba` (`GG-RRHH`) entra, y `vet.prueba` (`GG-Medica`) es rechazado.
- La clave de `rrhh.prueba` es `LDAP_PRUEBA_RRHH_PASSWORD` en `sistema/test.env`.
- El botón "Login with LDAP" del formulario `/login` no se ha probado en el navegador.
- El usuario se crea en el primer login y sin permisos útiles: falta asignarle un empleado y sus roles de HR. Esto lo hace posible `givenName`/`sn` en la cuenta de AD: `first_name` es obligatorio en el doctype User de Frappe.
- La base puede conservar un User huérfano `rrhh.prueba@reservaviva.local` del stack anterior (con OpenLDAP): es inofensivo y su limpieza manual es opcional ([directorio-activo.md](directorio-activo.md#quien-venía-del-stack-viejo-limpiar-los-restos)).

**Particularidades.**

- **Primer arranque lento.** `erpnext-create-site` crea el sitio con `bench new-site` e instala `erpnext` y `hrms`. Hasta que termina, la web devuelve error y los demás contenedores de ERPNext no arrancan. Las cifras están en [resultados-un-host.md](resultados-un-host.md).
- **Creación idempotente.** El trabajo solo da el sitio por completo si encuentra su marca `.reservaviva-sitio-completo`. Ante un sitio a medias se detiene con instrucciones y no borra nada solo. El caso está cubierto por `servicios/erpnext/test-create-site.sh`.
- **Scheduler.** `bench new-site` lo deja apagado, así que el trabajo lo enciende en cada arranque.

## Infraestructura compartida

Las cuatro aplicaciones comparten cuatro servicios de infraestructura, todos en la misma red `reservaviva`. Puertos y flujos, en [arquitectura.md](arquitectura.md). La CA y las cuentas de servicio, en [seguridad.md](seguridad.md).

| Servicio | Contenedor | Carpeta | Uso |
|---|---|---|---|
| Samba AD DC (imagen propia sobre `debian:trixie`, Samba 4.22) | `samba-ad` | [`servicios/samba-ad/`](../servicios/samba-ad/README.md) | Directorio `DC=ad,DC=reservaviva,DC=lan` (realm `AD.RESERVAVIVA.LAN`): LDAPS, Kerberos y DNS de su zona, con una OU y un grupo `GG-*` por departamento |
| bind9 9.18 | `dns-interno` | [`servicios/bind9/`](../servicios/bind9/) | Zona autoritativa `reservaviva.lan`, con una sola vista: todos los nombres apuntan a `HOST_IP` |
| NTP (`cturra/ntp`) | `ntp-interno` | [`servicios/ntp/`](../servicios/ntp/) | Hora de referencia local (stratum 10) |
| nginx 1.30 | `proxy-web` | [`servicios/proxy/`](../servicios/proxy/) | Acceso por nombre a las cuatro aplicaciones (`HOST_IP:80`); llega a ellas por `HOST_IP:puerto` |

Sus puertos en el equipo están en [arquitectura.md](arquitectura.md#7-puertos-publicados). Los usuarios de prueba del directorio y en qué aplicación entra cada uno, en [directorio-activo.md](directorio-activo.md#3-objetos-del-directorio).
