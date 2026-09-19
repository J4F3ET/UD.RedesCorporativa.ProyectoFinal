# Resultados de la Prueba de Humo — Un Solo Host (Docker Desktop, Windows 11)

> **Estado:** ejecutada en vivo en **dos rondas**. Ronda 1: compose originales (PC-2 con defectos,
> ERPNext sin site, sin DNS ni OpenVPMS). Ronda 2: con las correcciones de este PR (PC-2 corregido,
> stack completo de ERPNext, bind9, admins automáticos). Reemplaza el análisis estático previo.
> **Ronda 3:** OpenVPMS (PC-1) por separado. **Ronda 4:** prueba completa de los 3 PCs a la vez desde el HEAD de la rama, previa al merge del PR #3 (ver §8).

**Objetivo:** con los compose reales de `docker/pc1-medica`, `docker/pc2-operaciones` y
`docker/pc3-administracion-infra`, verificar qué arranca sin configuración extra, qué falla,
y si cada app alcanza el LDAP por la red de infraestructura.

## 1. Método

- Host único: Docker Desktop 29.x (Windows 11, 8 CPU, ~7 GB RAM para Docker).
- Arnés: `pruebas/smoke-test-3-pcs/docker-compose.yml` usa `include:` de los 3 compose reales y
  solo **sobrescribe**: (a) redes `macvlan` → `bridge` con las mismas subredes `10.10.X.0/24`;
  (b) desactiva lo que no puede arrancar (`openvpms-app`, `dns`); (c) une las apps a la red
  `vlan99_infra` para simular la ruta hacia LDAP.
- Las sondas HTTP se hicieron desde contenedores auxiliares dentro de cada red (en Docker Desktop
  las IP de bridge no son alcanzables desde el host).
- Reproducir: `cd pruebas/smoke-test-3-pcs && docker compose pull && docker compose up -d`.

## 2. Resultado por servicio

| Servicio | Ronda 1 (compose original) | Ronda 2 (con correcciones) | Paso manual que queda |
|---|---|---|---|
| OpenLDAP | Arranca solo; bind + búsqueda OK | igual | Ninguno |
| NTP (`cturra/ntp`) | `healthy` | igual | Ninguno |
| DNS bind9 | No evaluable: faltaba `bind/` | **Resuelve** los 7 nombres internos; inexistente → NXDOMAIN | Ninguno |
| Pretix | **HTTP 500** (sin `PRETIX_DATABASE_*`; Celery a `amqp://127.0.0.1`) | HTTP 200/302; admin creado por `deploy.sh` | Ninguno |
| InvenTree | **Crash loop** (11 reinicios) | login API 200; admin por variables; nuevo `inventree-worker` | Ninguno |
| ERPNext | Contenedor `Up` pero **HTTP 404** (sin site) | site `rrhh.reservaviva.local` creado solo; `/api/method/ping` 200, `/login` 200, login real `Administrator` 200; `create-site` idempotente | Ninguno |
| MySQL/Postgres/Redis/MariaDB | Arrancan | igual | — |
| OpenVPMS app | No evaluable: no existía `openvpms/` | Ronda 3: build OK (2 min); primer arranque ~5 min; `/openvpms/login` HTTP 200; se recupera al recrear el contenedor | Ninguno (ver límites) |

Tiempos de primer arranque: Pretix e InvenTree **~10 min** (cientos de migraciones); ERPNext
`create-site` **~9 min**. En arranques posteriores es inmediato.

DNS verificado (`dns-interno`): `rrhh`→10.10.40.10, `ldap`→10.10.99.10, `pretix`→10.10.20.10,
`inventree`→10.10.30.10, `openvpms`→10.10.10.10, `ntp`→10.10.99.12, `dns`→10.10.99.11.

## 3. Correcciones aplicadas

**`docker/pc2-operaciones`** (defectos propios del compose, detectados en la ronda 1):
- Pretix: `PRETIX_DATABASE_NAME/USER/PASSWORD`, Celery/Redis (`PRETIX_CELERY_BACKEND/BROKER`),
  `PRETIX_REDIS_SESSIONS` y `PRETIX_PRETIX_URL`. La imagen `pretix/standalone` ya trae el worker
  Celery (verificado con `ps`); no hace falta contenedor aparte.
- InvenTree: `INVENTREE_DB_*`, `INVENTREE_SITE_URL` (obligatorio para `CSRF_TRUSTED_ORIGINS`),
  `INVENTREE_AUTO_UPDATE=True` (elimina migración manual), volumen `inventree_data`, admin por
  variables `INVENTREE_ADMIN_*` y contenedor `inventree-worker` (`invoke worker`).
- `deploy.sh`: crea el administrador de Pretix (idempotente, con reintentos) y borra el usuario por
  defecto `admin@localhost` (clave `admin`). Se puede repetir con `sudo ./deploy.sh --solo-admins`.

**`docker/pc3-administracion-infra`**:
- ERPNext rediseñado con el stack de `frappe_docker`: `erpnext-db` (MariaDB 10.6), `erpnext-redis-cache`,
  `erpnext-redis-queue`, `erpnext-configurator`, `erpnext-create-site`, `erpnext-backend`,
  `erpnext-websocket`, `erpnext-scheduler`, `erpnext-queue-short`, `erpnext-queue-long` y
  `erpnext-hr` (nginx, 10.10.40.10, **puerto 8080**). Imagen fijada a `frappe/erpnext:v15`
  (`latest` apunta a v17-dev). `configurator` y `create-site` terminan con `Exited (0)`: es lo esperado.
- `bind/named.conf` y `bind/zones/db.reservaviva.local` para el servicio DNS.

**`docker/pc1-medica`** (probado en ronda 3, con bridge en vez de macvlan): `openvpms/Dockerfile` (Tomcat 9, Java 11, OpenVPMS 2.4.0.1,
driver MySQL Connector/J 8.0.33) y `entrypoint.sh` que espera a MySQL, crea el esquema, carga datos
base y genera el WAR en el primer arranque. Variables nuevas: `OPENVPMS_DB_PASSWORD`, `OPENVPMS_ADMIN_PASSWORD`.
La prueba destapó cuatro defectos de la primera versión del entrypoint, ya corregidos:
- `openvpms.properties` estaba incompleto (faltaban `reporting.db.*` y `openvpms.key`): ahora se genera con `toolbox configure --default` y se completa.
- `openvpms.key` cifra datos en la base: el archivo vive en el volumen `openvpms_state` para no perderla al recrear el contenedor (verificado).
- `toolbox database --create` necesita `--host=%` porque la app se conecta desde otro contenedor.
- `toolbox user --setpassword` rechaza claves débiles (mín. 8 caracteres con mayúscula, minúscula, número y especial) y, con `set -e`, dejaba la base a medias en bucle de reinicios: ahora se valida antes de tocar la base y la inicialización se reanuda por etapas.

## 4. Variables nuevas en los `.env.example`

| PC | Variable | Notas |
|---|---|---|
| PC-1 | `OPENVPMS_DB_PASSWORD`, `OPENVPMS_ADMIN_PASSWORD` | obligatorias |
| PC-2 | `INVENTREE_ADMIN_PASSWORD`, `PRETIX_ADMIN_PASSWORD`, `PRETIX_ADMIN_EMAIL` | obligatorias; `INVENTREE_ADMIN_USER`/`EMAIL` con valor por defecto |
| PC-3 | `ERPNEXT_DB_ROOT_PASSWORD`, `ERPNEXT_ADMIN_PASSWORD` | obligatorias; `ERPNEXT_SITE` por defecto `rrhh.reservaviva.local` |

Ninguna variable existente fue renombrada.

## 5. Alcance de LDAP

- `ldapsearch -x -D cn=admin,dc=reservaviva,dc=local` desde un cliente en `vlan99_infra` contra
  `10.10.99.10`: **OK** (`dn: dc=reservaviva,dc=local`).
- Desde `pretix-web`, `inventree-app` y `erpnext-backend`: TCP a `10.10.99.10:389` y `BindResponse`
  LDAP válido — **OK** los tres (en el arnés, `erpnext-backend` queda en vlan99 como 10.10.99.23).
- PC-1: como `openvpms-app` no se probó, se usó un contenedor sustituto en `vlan10` (+ `vlan99`):
  alcanza LDAP **OK** y `openvpms-db:3306` **OK**.
- Esto es el estado de las rondas 1-3: solo alcance de red, sin autenticación LDAP real desde las apps. La integración posterior se documenta en §9.

## 6. Límites de esta prueba (qué NO demuestra)

- **No valida macvlan, 802.1Q, ni el switch.** Solo la capa de software.
- **No valida la segmentación:** para llegar a LDAP las apps se unieron directamente a `vlan99_infra`,
  así que Pretix, InvenTree y ERPNext quedan en el mismo segmento L2 (el diseño real lo bloquea la
  matriz del switch/PC-3).
- No se probó autenticación LDAP real desde las apps (solo alcance de red y protocolo), ni LDAPS (636). *(Así quedó en las rondas 1-3; LDAPS se resolvió en §8 y la integración LDAP en las aplicaciones se aborda en §9.)*
- Con `macvlan`, un PC no alcanza sus propios contenedores desde el host: probar desde otro equipo.
- OpenVPMS: el build necesita Internet (~300 MB). La carga de plantillas de impresión (`toolbox template --load --all`) falla en 2.4.0.1 en la plantilla `Investigation` (referencia el tipo inexistente `act.patientInvestigation`); el entrypoint lo tolera y quedan ~37 plantillas cargadas. No se probó el login con usuario/clave (la UI es Echo, no HTTP simple), solo que `admin` recibió su clave (`Password updated`) y que `/openvpms/login` responde 200.

## 7. Pendientes
0. ~~LDAPS (636) no funciona~~ **Resuelto** (ver §8): causa raíz `LDAP_TLS_VERIFY_CLIENT=demand` + CA de la imagen caducada; se generan certificados propios con `scripts/generar-certificados.sh`.

1. Resolver o documentar las plantillas de impresión que no cargan en OpenVPMS 2.4.0.1 y añadir LibreOffice/OpenOffice si se necesita combinar documentos.
2. Integrar OpenVPMS, Pretix, InvenTree y ERPNext con LDAP (hoy solo hay alcance de red). Ya no es un bloque único (ver §9):
   - OpenVPMS y Pretix: cerrados como **no viables** con la versión actual, por decisión razonada ([§9.2](#92-pretix-y-openvpms-no-se-integran-decisión-razonada); detalle en [`ldap-pretix-openvpms.md`](ldap-pretix-openvpms.md)).
   - ERPNext e InvenTree: **siguen abiertos**, en curso en la ronda 5.
3. ~~Probar LDAPS (636).~~ **Resuelto** (ver §8): LDAPS verificado con cadena y nombre desde las apps y desde otro segmento; lo que falta es que las aplicaciones lo usen (punto 2).
4. Repetir con macvlan real en los 3 PCs + switch; confirmar si es L2 o L3.
5. Aclarar en el informe el alcance de ERPNext (solo HR) y Pretix vs. PretixPOS.

## 8. Ronda 4 — prueba completa de los 3 PCs (previa al merge del PR #3)

Arnés `pruebas/smoke-test-3-pcs/` desde cero (sin volúmenes previos), con **OpenVPMS incluido** (antes
estaba desactivado): 22 contenedores, red `bridge`. Primer arranque completo: **~13 min** (limitado por
`erpnext-create-site`); OpenVPMS ~5 min (en paralelo). Pico de memoria por contenedor: `openvpms-app` ~750 MB,
`inventree-app` ~510 MB. Comprobaciones estáticas previas: los 3 `docker-compose.yml` validan con su
`.env.example` (`docker compose config`) y los 3 `deploy.sh` + 3 scripts de `scripts/` pasan `bash -n`.

| Prueba | Resultado |
|---|---|
| HTTP por VLAN: OpenVPMS `:8080/openvpms/login`, Pretix `/` y `/control/login/`, InvenTree `:8000/api/`, ERPNext `:8080/login` y `/api/method/ping` | **200** en todas |
| LDAP 389: bind crudo desde `pretix-web`, `inventree-app`, `erpnext-backend`; TCP desde `openvpms-app` | **OK** los 4 |
| LDAP autenticado (`ldapsearch -D cn=admin`): clave correcta / clave errónea | `Success` / `Invalid credentials (49)` |
| DNS: 7 nombres (`rrhh`, `ldap`, `pretix`, `inventree`, `openvpms`, `ntp`, `dns`) + inexistente | IPs correctas / `NXDOMAIN` |
| NTP | `healthy` |
| Login real: ERPNext `Administrator` (y clave errónea) | **200** / **401** |
| Login real: InvenTree `admin` (API con auth básica) | **200** |
| Administrador de Pretix: mismo bloque de `deploy.sh`, dos veces | 1ª crea; 2ª no hace nada; clave correcta, superusuario, y `admin@localhost` borrado |
| **Reinicio simulado** (`docker compose down` sin `-v` y `up -d`) | 20 contenedores arriba + 2 que terminan por diseño (`Exited (0)`); `create-site` dice "ya existe"; OpenVPMS no reinicializa; admin de Pretix, login de ERPNext y DNS persisten |
| LDAPS 636 | **FALLABA** en la primera corrida. Tras la corrección se repitió la prueba **completa desde cero**: LDAPS con cadena y nombre verificados y `BindResponse` real desde `pretix-web`, `inventree-app` y `erpnext-backend`, también tras el reinicio simulado (ver abajo) |

Nota: tras el reinicio, la primera petición a `/login` de ERPNext dio un timeout aislado; las siguientes, 200.

### Defecto encontrado y corregido: LDAPS no funcionaba (`osixia/openldap:1.5.0`)
- **Síntoma:** el puerto 636 escuchaba, pero `slapd` cortaba la conexión (`TLS: can't accept` / `TLS negotiation failure`)
  con cualquier cliente moderno, en TLS 1.2 y 1.3.
- **Causa raíz** (aislada en un contenedor aparte, con intercambio de datos real): la imagen trae
  `LDAP_TLS_VERIFY_CLIENT=demand` por defecto, que **exige certificado también al cliente**; con
  `LDAP_TLS_VERIFY_CLIENT=never` el mismo contenedor responde bien en TLS 1.2 y 1.3. Además, la CA que
  genera la imagen caducó en enero de 2026, así que ningún cliente que verifique la cadena la aceptaría.
  Descartados: tamaño de DH, tipo de clave/firma del certificado y `LDAP_TLS_CIPHER_SUITE` (este último daba
  un falso positivo: en TLS 1.3 el cliente cree terminar el handshake antes que el servidor).
- **Corrección:** `scripts/generar-certificados.sh` crea una CA interna (10 años) y el certificado de OpenLDAP
  (825 días; SAN `ldap.reservaviva.local`, `openldap`, `localhost`, `10.10.99.10`, `127.0.0.1`) en
  `docker/pc3-administracion-infra/certs/` (en `.gitignore`); `docker-compose.yml` los monta en el contenedor y
  fija `LDAP_TLS_VERIFY_CLIENT=never`; el `deploy.sh` de PC-3 lo ejecuta antes del `docker compose up`. Es
  idempotente, regenera si al certificado le quedan menos de 30 días o falta la IP, copia `ca.crt` a
  `docker/pc1-medica/certs/` y `docker/pc2-operaciones/certs/`, y como root la instala en el almacén de confianza
  del host (`--sin-instalar-ca` lo evita, `--forzar` regenera todo).
- **Verificado** (cliente Python con cadena y nombre verificados, desde otro segmento): por nombre
  `ldap.reservaviva.local` y por IP, TLS 1.2 con `BindResponse` real; se **rechaza** un nombre distinto y una CA
  desconocida; el certificado servido coincide con el archivo; sobrevive a un reinicio y a una **rotación**
  (`--forzar` + recrear con el volumen `ldap_config` ya existente sirve el certificado nuevo); `ldapsearch` autenticado
  por `ldaps://10.10.99.10` con verificación completa. Particularidad: `ldapsearch -H ldaps://localhost` con
  verificación estricta falla en el cliente GnuTLS de la imagen; usar la IP o el nombre.
- **Sin cubrir:** que las aplicaciones (Pretix, InvenTree, ERPNext, OpenVPMS) usen LDAPS con esa CA (aún no hay
  integración LDAP en las apps); y `ca.crt` no llega sola a PC-1/PC-2 si son equipos distintos: hay que copiarla
  (`scp`), el script lo indica al terminar.

### Lo que esta ronda sigue sin cubrir
- `deploy.sh` completo, sub-interfaces 802.1Q, `macvlan`, el switch y la matriz de segmentación (requieren Linux con root y el hardware).
- Login de OpenVPMS con usuario y clave (interfaz Echo), y autenticación LDAP *desde* las aplicaciones (solo alcance de red y protocolo).

## 9. Ronda 5 — integración LDAP en las aplicaciones

> **Estado:** en curso. Bootstrap de OpenLDAP hecho; Pretix y OpenVPMS evaluados y descartados; **ERPNext e
> InvenTree pendientes de resultados en esta misma ronda** (no se da ningún resultado por bueno hasta que se reporte).

### 9.1 Bootstrap de OpenLDAP (rama `feat/ldap-erpnext-inventree`, commit `d84c59e`)

- **Archivos nuevos** en `docker/pc3-administracion-infra/ldap/`: `05-acl-servicio.ldif`, `10-estructura.ldif`,
  `20-usuarios-prueba.ldif` y un `README.md` con las claves. Se montan en
  `/container/service/slapd/assets/config/bootstrap/ldif/custom`; el servicio `openldap` lleva
  `command: ["--copy-service"]`.
- **Estructura:** `ou=medica`, `ou=operaciones`, `ou=rrhh`, `ou=servicios`.
- **Usuarios de prueba** (claves desechables, solo laboratorio):

  | Usuario | OU | Clave |
  |---|---|---|
  | `vet.prueba` | medica | `Medica-Prueba1` |
  | `logistica.prueba`, `taquilla.prueba` | operaciones | `Oper-Prueba1` |
  | `rrhh.prueba` | rrhh | `Rrhh-Prueba1` |

- **Cuenta de búsqueda:** `cn=svc-lectura,ou=servicios,dc=reservaviva,dc=local` / `Svc-Lectura1`.

**Defecto encontrado: la ACL por defecto de `osixia/openldap:1.5.0` no deja buscar a nadie salvo a `admin`.** Sin
`05-acl-servicio.ldif` ninguna aplicación podría resolver usuarios en el directorio. Es un defecto real descubierto en
esta ronda, del mismo nivel que el de LDAPS de §8.

**Verificado** (Juan, en un contenedor aislado): carga del bootstrap OK; bind correcto OK; bind con clave errónea
devuelve `49`; búsqueda con `svc-lectura` OK.

**Limitación operativa:** el bootstrap solo se carga si el volumen `ldap_data` está **vacío**. Con un volumen ya
existente hay que ejecutar `docker compose down -v` (borra los datos de todo el compose) antes de volver a levantar. Afecta
a quien repita la prueba sobre un entorno previo.

### 9.2 Pretix y OpenVPMS: no se integran (decisión razonada)

Resultado negativo deliberado, en línea con el plan ("si una app no lo soporta limpiamente, documentarlo como
limitación en vez de forzarlo"). Lo evaluó Pepe (PR #5, rama `feat/ldap-pretix-openvpms`); el detalle y la evidencia
están en [`ldap-pretix-openvpms.md`](ldap-pretix-openvpms.md). Resumen:

- **OpenVPMS 2.4.0.1: sin soporte LDAP.** No hay `spring-security-ldap` entre los JAR del WAR, no hay clases LDAP en
  `openvpms-web-security` ni en `openvpms-framework`, y los usuarios son arquetipos en MySQL.
  `openvpms-auth-plugin` solo cubre el framework de plugins, no el login.
- **Pretix: sin backend LDAP propio.** El único plugin es `pretix-ldap` 0.2.5 (comunitario, un mantenedor). Crea
  `Server()` sin objeto `Tls`, así que `ldap3` usa `validate=CERT_NONE` y acepta cualquier certificado; no hay forma de
  pasarle `ca.crt` sin parchearlo. Demostrado: con la CA del repo, el bind por `ldaps://` devuelve `success` con
  `validate=0`, y con `Tls(CERT_REQUIRED)` sin CA falla como debe. Además usa una conexión compartida con `rebind`
  (carrera con varios workers) y autentica por correo sin mapear OU a roles.

**Por qué es la decisión correcta:** integrar un plugin que aparenta LDAPS sin verificar el servidor habría sido peor que
no tener LDAP en Pretix, justamente en un proyecto cuyo objetivo es demostrar comunicación fiable. Ambas apps siguen con
su administrador local (creado por `deploy.sh`).

> **Confianza:** esta evaluación es de Pepe. Quien consolida este documento revisó el texto de `ldap-pretix-openvpms.md`
> pero **no volvió a ejecutar** la prueba de TLS ni la inspección de los JAR; no está verificada de forma independiente.

### 9.3 ERPNext e InvenTree: pendiente

- **ERPNext (LDAP Settings):** *pendiente de resultados de esta ronda.*
- **InvenTree (`django-auth-ldap`, variables `INVENTREE_LDAP_*`):** *pendiente de resultados de esta ronda.*

Se completarán aquí cuando se reporten; hasta entonces no debe leerse ninguna integración como lograda.
