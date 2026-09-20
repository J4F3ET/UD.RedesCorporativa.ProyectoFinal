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
2. ~~Integrar OpenVPMS, Pretix, InvenTree y ERPNext con LDAP (hoy solo hay alcance de red).~~ **Resuelto** (ver §9): cierre parcial, 2 de 4 integradas y 2 descartadas con justificación:
   - OpenVPMS y Pretix: cerrados como **no viables** con la versión actual, por decisión razonada ([§9.2](#92-pretix-y-openvpms-no-se-integran-decisión-razonada); detalle en [`ldap-pretix-openvpms.md`](ldap-pretix-openvpms.md)).
   - ERPNext e InvenTree: **integrados** con LDAPS y cadena verificada ([§9.3](#93-erpnext-e-inventree-integrados-con-ldaps); detalle en [`integracion-ldap-erpnext-inventree.md`](integracion-ldap-erpnext-inventree.md)).
3. ~~Probar LDAPS (636).~~ **Resuelto** (ver §8 y [§9.3](#93-erpnext-e-inventree-integrados-con-ldaps)): el puerto 636 sirve el certificado correcto y se verificó cadena y nombre desde un cliente externo en otro segmento; ERPNext e InvenTree ya lo usan con cadena verificada. Pretix y OpenVPMS no, por lo explicado en §9.2.
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
  (`scp`), el script lo indica al terminar. *(Así quedó en la ronda 4; la integración en ERPNext e InvenTree se cubrió después en §9.3 y el descarte de Pretix y OpenVPMS en §9.2.)*

### Lo que esta ronda sigue sin cubrir
- `deploy.sh` completo, sub-interfaces 802.1Q, `macvlan`, el switch y la matriz de segmentación (requieren Linux con root y el hardware).
- Login de OpenVPMS con usuario y clave (interfaz Echo), y autenticación LDAP *desde* las aplicaciones (solo alcance de red y protocolo). *(Así quedó en la ronda 4; la autenticación LDAP desde las aplicaciones se aborda en §9.)*

## 9. Ronda 5 — integración LDAP en las aplicaciones

> **Estado:** cerrada. Bootstrap de OpenLDAP hecho; ERPNext e InvenTree integrados con LDAPS y cadena TLS verificada;
> Pretix y OpenVPMS evaluados y descartados con justificación.

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

### 9.3 ERPNext e InvenTree: integrados con LDAPS

Cumplen el criterio "Funcional" del plan: autentican usuarios LDAP reales por LDAPS con la cadena TLS verificada
(rama `feat/ldap-erpnext-inventree`, PR #7; detalle en [`integracion-ldap-erpnext-inventree.md`](integracion-ldap-erpnext-inventree.md)).

**Diseño común:**
- Conexión a `ldaps://ldap.reservaviva.local:636` con verificación de **cadena y de nombre** contra la CA de
  `scripts/generar-certificados.sh`, montada como `/certs/ca.crt` en solo lectura.
- El nombre se fija con `extra_hosts` a `10.10.99.10` para que coincida con el certificado sin depender del DNS.
- Flujo: la app hace bind con `cn=svc-lectura`, busca `uid=<usuario>` **solo en la OU de su departamento** y luego hace
  bind con el DN encontrado y la clave del usuario.
- **InvenTree (PC-2):** `django-auth-ldap` con variables `INVENTREE_LDAP_*`, busca en `ou=operaciones`; habla LDAPS
  `inventree-app`.
- **ERPNext (PC-3):** "LDAP Settings" de Frappe (`ldap3`), configurado por un job idempotente nuevo,
  `erpnext-ldap-config`, busca en `ou=rrhh`; habla LDAPS `erpnext-backend`, no el frontend.
- Variables nuevas: `ERPNEXT_LDAP_BIND_PASSWORD` e `INVENTREE_LDAP_BIND_PASSWORD` (ambas, la clave de `svc-lectura`), en
  los dos `.env.example` y en `pruebas/smoke-test-3-pcs/test.env`.

**Resultados** (endpoints: ERPNext `/api/method/frappe.integrations.doctype.ldap_settings.ldap_settings.login`,
InvenTree `/api/user/token/`):

| Prueba | ERPNext | InvenTree |
|---|---|---|
| Usuario de su departamento, clave correcta | 200 (`rrhh.prueba`) | 200 + token (`logistica.prueba`) |
| Clave errónea | 417 | 401 |
| Usuario de **otro** departamento con su clave correcta | 417 (`logistica.prueba`, `vet.prueba`) | 401 (`rrhh.prueba`) |
| Administrador local (no LDAP) | sigue funcionando | 200 |
| Cadena TLS: con `ca.crt` / con la CA del sistema | OK / falla | OK / falla (`self-signed certificate in certificate chain`) |
| `docker compose down` (sin `-v`) + `up -d` | 200 / 417 idénticos | 200 / 401 idénticos |

**Matiz sobre el rechazo de otro departamento:** no es una política de autorización ni un control de acceso por
departamento. Es consecuencia de que cada app busca solo dentro de la OU de su departamento; si se ampliara el ámbito de
búsqueda, ese usuario entraría. Aun así es un buen resultado y encaja con el tema de segmentación del curso.

**Límites:**
- Los usuarios LDAP entran **sin permisos**: un administrador debe asignarles roles/grupos. En ERPNext el rol `Employee`
  se retira solo porque no hay empleado mapeado; el mapeo a empleados y roles de HR queda pendiente.
- La búsqueda no filtra por grupos: cualquier entrada con `uid` dentro de la OU puede autenticar.
- `erpnext-ldap-config` guarda la configuración con `ignore_mandatory`, es decir, **no valida contra LDAP al guardar**;
  la prueba real es el login.
- En ERPNext el login se probó por la API, no por navegador. El formulario web muestra el botón "Login with LDAP" cuando
  está habilitado, pero eso no se verificó.
- Detalle de implementación: el filtro por defecto de la imagen de InvenTree es `(uid= %(user)s)`, con un espacio de más,
  y no encuentra a nadie; hay que sobrescribirlo con `(uid=%(user)s)`.
- Todo se probó en el arnés de un solo host con redes `bridge`: no valida macvlan ni el switch.

> **Confianza:** la verificación es de Juan. Quien consolida este documento revisó su documento y su PR, pero **no
> reejecutó** sus pruebas.

## 10. Ronda 6 — arranque completo del arnés con Docker Engine nativo en WSL (20/09/2026)

Esta ronda salda la deuda de verificación que dejó la ronda anterior (el arranque completo del arnés y `ldaplogin.py`
nunca se habían ejecutado). **Resultado: LDAPS y el login contra ERPNext e InvenTree quedan verificados de verdad; el
arranque completo NO cumple el criterio de «~20 contenedores `Up` y `healthy`»**, por defectos del proyecto que la
prueba ha sacado a la luz (hallazgos H1–H4). Se anota todo tal cual, incluidos los fallos y las correcciones al script.

### 10.1 Entorno de la prueba (distinto al de las rondas anteriores)

- **No es Docker Desktop.** El usuario lo desinstaló ese día: Docker Engine 29.8.1 + Compose v5.5.1 dentro de la distro WSL
  `Ubuntu-24.04`, VM con 7,9 GB de RAM (host de 13,9 GB) y 4 GB de swap. El almacén de imágenes estaba **vacío**
  (0 imágenes, 0 volúmenes), así que hubo que descargar todo. El repo se monta desde `/mnt/d` (los bind mounts cruzan
  la frontera Windows/WSL y son más lentos).
- Puertos publicados solo en `127.0.0.1` y desplazados (18080–18083, 1389, 1636, 1053, 1123); `PUBLISH_IP` sin tocar.
- `ldaplogin.py` se ejecutó con el `python3` de WSL: en Windows `docker` es un `.cmd` y `subprocess` sin shell no lo resuelve
  (no llegó a probarse en Windows; es una expectativa, no un resultado).
- Rama `test/arranque-completo-arnes`, desde `origin/master` (`d34f036`).

### 10.2 Cronología

| Paso | Resultado |
|---|---|
| Zona de bind9 (`docker\pc3-administracion-infra\bind\generar-zona.ps1`) | generada antes del primer `up` |
| `docker compose pull` | `EXIT 0`; 10 imágenes, 8,29 GB. Salieron mensajes `Retrying in N seconds` (red irregular) |
| `docker compose build openvpms-app` | `EXIT 0`, imagen `reservaviva-smoke-openvpms-app` (`sha256:464f70370f93…`). Descargó el zip de `repository.openvpms.org` en 54,3 s y el conector de `repo1.maven.org` en 3,8 s |
| `docker compose up -d` (1.er intento) | **`EXIT 1`**: `dependency failed to start: container erpnext-db is unhealthy` (ver H1) |
| `docker compose up -d` (2.º intento, sin `down`) | `EXIT 0`. `erpnext-create-site` empezó 18:42:34Z y terminó 18:51:12Z (≈ 8,6 min), `exit=0` |

**El arnés arrancó al segundo intento, tras un fallo de dependencia en el primero.** El segundo intento funcionó
precisamente porque la base de datos ya estaba inicializada; **no valida que el defecto H1 esté resuelto**. Salida literal
del primer intento (final del log):

```
 Container erpnext-db Waiting
 Container erpnext-db Error dependency erpnext-db failed to start
dependency failed to start: container erpnext-db is unhealthy
EXIT 1
```

### 10.3 Criterios de aceptación, uno a uno

| # | Criterio | Estado | Evidencia |
|---|---|---|---|
| 1 | Los 3 jobs en `Exited (0)` | **Cumple** | `erpnext-configurator`, `erpnext-create-site`, `erpnext-ldap-config`: `Exited (0)` (lectura de las 14:04 y de las 14:38). Son 3, no 2 (hallazgo B2) |
| 2 | ~20 contenedores permanentes `Up`, los que tienen healthcheck en `healthy` | **NO cumple** | `openvpms-app` en bucle de reinicios (`Restarting (1)`, 40 reinicios; lo paré yo) y `pretix-web` `unhealthy`. `healthy`: `erpnext-db`, `erpnext-hr`, `inventree-app`, `ntp-interno`. Ver H2 y H3 |
| 3 | `ldaplogin.py` con PASS y exit 0 | **Cumple solo con el script corregido** (ver 10.4) | La 1.ª y la 2.ª ejecución dieron `FAIL` / exit 1; la ejecución con el script corregido dio `PASS` / exit 0 |
| 4 | Clave errónea rechazada (401/403; ERPNext 417) | **Cumple** | ERPNext 417, InvenTree 401 en las tres ejecuciones |
| 5 | Resultado real anotado con la salida pegada | **Cumple** | Esta sección |

Lo que la prueba **sí demuestra** (nuevo respecto a la sección 9): que ERPNext e InvenTree autentican contra OpenLDAP con
las claves del README (los hashes del LDIF corresponden a esas claves), que InvenTree acepta `GET` con Basic auth en
`/api/user/token/`, que hay `python3` en ambos contenedores (3.11.16 y 3.14.7) y que una clave errónea se rechaza.

### 10.4 `ldaplogin.py`: tres ejecuciones, salida literal

El `ExecMainStartTimestamp` de `docker.service` fue `14:02:41` al inicio y al final de las tres ejecuciones (14:38–14:44),
es decir, ningún reinicio del daemon a mitad de prueba.

**Ejecución 1 (script original, 14:38)** — `FAIL`, exit 1:

```
== Caso 1: login LDAP correcto
  [FAIL] ERPNext rrhh.prueba: status=None Traceback (most recent call last):
  File "<stdin>", line 8, in <module>
  File
  [PASS] InvenTree logistica.prueba: status=200 {"token":"inv-5312...","name":"","expi
  => Caso 1: login LDAP correcto: FAIL

== Caso 2: contrasena erronea
  [PASS] ERPNext clave erronea: status=417 (esperado 401/403/417)
  [PASS] InvenTree clave erronea: status=401 (esperado 401/403)
  => Caso 2: contrasena erronea: PASS

== Caso 3: ldapsearch LDAPS con CA
  [FAIL] ldapsearch con CA (rrhh.prueba): rc=255 ldap_sasl_bind(SIMPLE): Can't contact LDAP server (-1)
  [FAIL] ldapsearch con CA (logistica.prueba): rc=255 ldap_sasl_bind(SIMPLE): Can't contact LDAP server (-1)
  [FAIL] ldapsearch clave erronea: rc=255 (esperado 49 Invalid credentials)
  [PASS] ldapsearch SIN la CA debe fallar: rc=255 ldap_sasl_bind(SIMPLE): Can't contact LDAP server (-1)
  => Caso 3: ldapsearch LDAPS con CA: FAIL

VEREDICTO GLOBAL: FAIL
EXIT_LDAPLOGIN=1
```

**Ejecución 2 (script original, 14:40)** — `FAIL`, exit 1. Casos 1 y 2 `PASS` (ERPNext 200 con `full_name` «RRHH Prueba»,
InvenTree 200 con token, 417 y 401 con clave errónea); el caso 3 falló igual que en la ejecución 1. El fallo de ERPNext de
la ejecución 1 **fue intermitente y su causa no está determinada**: el script recorta el error a 200 caracteres; la
sospecha (un timeout en el primer login, que crea el usuario) **no está verificada**. Un login manual con el mismo código
dio `200`.

**Ejecución 3 (script corregido, 14:44)** — `PASS`, exit 0:

```
== Caso 1: login LDAP correcto
  [PASS] ERPNext rrhh.prueba: status=200 {"message":"No App","home_page":"/me","full_name":"RRHH Prueba","_server_message
  [PASS] InvenTree logistica.prueba: status=200 {"token":"inv-5312...","name":"","expi
  => Caso 1: login LDAP correcto: PASS

== Caso 2: contrasena erronea
  [PASS] ERPNext clave erronea: status=417 (esperado 401/403/417)
  [PASS] InvenTree clave erronea: status=401 (esperado 401/403)
  => Caso 2: contrasena erronea: PASS

== Caso 3: ldapsearch LDAPS con CA
  [PASS] ldapsearch con CA (rrhh.prueba): rc=0 =rrhh.prueba,ou=rrhh,dc=reservaviva,dc=local | uid: rrhh.prueba | ldap_sasl_bind
  [PASS] ldapsearch con CA (logistica.prueba): rc=0 ,ou=operaciones,dc=reservaviva,dc=local | uid: logistica.prueba | ldap_sasl_bind
  [PASS] ldapsearch clave erronea: rc=49 (esperado 49 Invalid credentials)
  [PASS] ldapsearch con CA ajena debe fallar por certificado no confiable: rc=255 | TLS: can't connect: (unknown error code). | ldap_sasl_bind(SIMPLE): Can't contact LDAP server (-1)
  => Caso 3: ldapsearch LDAPS con CA: PASS

VEREDICTO GLOBAL: PASS
EXIT_LDAPLOGIN=0
```

(En la última comprobación la línea impresa está recortada por el script a sus últimos 100 caracteres; la condición que
lo hace `PASS` exige que la salida completa contenga `untrusted`. La prueba manual equivalente, abajo, muestra la línea
completa `TLS: peer cert untrusted or revoked (0x42)`.)

**Por qué se modificó el script (commit aparte, `73b3dd6`) y por qué no es «forzar un PASS».** El caso 3 original fallaba por
un defecto del propio script, no de LDAPS:

- Se conectaba a `ldaps://localhost:636` desde dentro de `openldap`. El certificado **sí** incluye `DNS:localhost` en el SAN
  (`DNS:ldap.reservaviva.local, DNS:openldap, DNS:localhost, IP:10.10.99.10, IP:127.0.0.1`), pero libldap canonicaliza
  el nombre al hostname del contenedor y rechaza. Literal de `ldapsearch -d1`:
  `TLS: hostname (4f89b94c57b9) does not match common name in certificate (ldap.reservaviva.local).`
- El servidor no estaba roto: el log de `slapd` mostraba `TLS established tls_ssf=256` y binds simples con `err=0`
  de las aplicaciones.
- **Falso PASS del cuarto check** («SIN la CA debe fallar»): con `LDAPTLS_CACERT=/nonexistent` fallaba por
  `TLS: could not use CA certificate file '/nonexistent': Error while reading file. (-64)`, es decir, por fichero ilegible,
  **no** por certificado no verificable. Habría dado `PASS` aunque LDAPS aceptara cualquier certificado.
- Prueba manual del nombre de producción (`ldap.reservaviva.local` resuelve con el DNS del laboratorio a `10.10.99.10`),
  desde un contenedor efímero en la red del arnés: con la CA y clave correcta `rc=0`; con clave errónea `rc=49`
  (`ldap_bind: Invalid credentials (49)`); con una CA válida pero ajena `TLS: peer cert untrusted or revoked (0x42)`,
  `rc=255`. Con esa última se distingue el rechazo por la razón correcta.
- Cambio en el script: URI `ldaps://ldap.reservaviva.local:636` (el mismo que usa `INVENTREE_LDAP_SERVER_URI` en pc2),
  `ldapsearch` en un contenedor efímero con el DNS del laboratorio, y el check negativo con una CA ajena que exige
  `untrusted` en la salida.

Límite: el script corregido se ejecutó **una sola vez**. No se ejecutó con `--persistencia` (caso 4: `down` sin `-v` +
`up -d`), así que la persistencia de los usuarios LDAP tras reiniciar **sigue sin verificarse en este arnés** (la sección 9.3
la había probado en Docker Desktop).

### 10.5 Hallazgos (defectos del proyecto y del entorno)

Ninguno de los ficheros afectados se ha modificado: los compose y el entrypoint están fuera del alcance de esta prueba.

**H1 — `erpnext-db` sin `start_period` (defecto real de robustez, `docker/pc3-administracion-infra/docker-compose.yml:53-57`).**
Healthcheck `mysqladmin ping`, `interval 5s`, `timeout 5s`, `retries 40` y **sin `start_period`**: 200 s de margen. En el
primer arranque la base tardó ≈ 5 min en inicializarse (18:28:11Z → 18:33:00Z; el directorio de datos cruza `/mnt/d`; el
log muestra tres arranques de `mariadbd`), el contenedor pasó a `unhealthy` y `compose up` abortó. Después quedó `healthy`
(`FailingStreak 0`, `RestartCount 0`). Un PC del laboratorio con disco más lento y arranque en frío puede repetirlo. La
solución (un `start_period` de unos 300 s o más reintentos) es decisión del usuario y debe validarse con volumen limpio.

**H2 — el entrypoint de OpenVPMS no es reanudable (`docker/pc1-medica/openvpms/entrypoint.sh:60-74`).** El comentario dice que
la inicialización «se reanuda por etapas»; el código solo borra las marcas cuando la base tiene 0 tablas. Si hay tablas y
falta la marca `schema`, `step schema` reintenta `toolbox database --create` y muere para siempre con
`Cannot create openvpms as there are tables already present` (`exit=1`, `OOMKilled=false`, 40 reinicios). Verificado: el
volumen `reservaviva-smoke_openvpms_state` tiene `/init` **vacío** y la base tiene **49 tablas**. La causa que lo provocó es
compatible con que los reinicios de `docker.service` (H7) mataran el contenedor antes de guardar la marca, pero eso no
está demostrado. Descartada la hipótesis de que fuera falta de memoria del heap de Tomcat.

**H3 — el healthcheck de Pretix no puede pasar (`docker/pc2-operaciones/docker-compose.yml:74`).** Consulta
`http://127.0.0.1/control/login/` y la aplicación responde `HTTP Error 400: Bad Request` (log de Pretix:
`django.request log Bad Request: /control/login/`, cada ≈ 15 s), mientras `PRETIX_PRETIX_URL` apunta a `IP_PC2`
(línea 70). Es coherente con un `Host` no permitido, pero **no se ha verificado la causa exacta del 400**. Con
`start_period: 900s` parece que arranca durante 15 minutos y después queda `unhealthy` para siempre. No depende de la RAM.

**H4 — mismo patrón latente en InvenTree (`docker/pc2-operaciones/docker-compose.yml:137`, hallazgo de la coordinación,
leído en el código; no reproducido aquí).** Su healthcheck usa `http://127.0.0.1:8000/api/` con `INVENTREE_SITE_URL` apuntando
a `IP_PC2` (línea 114). Hoy no falla (`inventree-app` está `healthy`), pero es la misma fragilidad.

**H5 — defecto del caso 3 de `ldaplogin.py` y falso PASS.** Ver 10.4.

**H6 — fallo intermitente del primer login de ERPNext en `ldaplogin.py`.** Ver 10.4; causa sin determinar. Además el script
recorta los errores a 200 caracteres, lo que impidió ver el `Traceback`.

**H7 — entorno: `docker.service` se reinicia solo (no afecta al laboratorio con Docker Desktop, pero invalida
mediciones).** `containerd` arrancó a las 13:27:07, 13:39:44, 13:40:55, 13:52:37, 13:55:09 y 14:02:41 (hora local) con la
VM sin reiniciar y `NRestarts=0`; el servicio está activado por socket (`TriggeredBy: docker.socket`). Cada llamada suelta
`wsl.exe -d Ubuntu-24.04 -- …` desde Windows abre/cierra una sesión de la distro (`wsl: Failed to start the systemd user
session for 'jafet'`) y parece precipitar el ciclo, pero **no es la única causa**: el de las 14:02 ocurrió sin actividad de
la otra sesión. Una sesión de WSL persistente (`wsl -d Ubuntu-24.04 -- sleep infinity`) coincidió con que se detuvieran
(estable desde las 14:02:41 hasta el final de la prueba). Los reinicios relanzaron los contenedores por su política de
reinicio y explican los `Up` de pocos minutos.

**H8 — entorno: `repository.openvpms.org` inalcanzable de forma intermitente.** Una comprobación temprana falló desde
Windows (`curl` exit 28 a los 21 s) y desde WSL (`Could not resolve host`, exit 6) y minutos después el `build` lo descargó
en 54 s. La causa señalada, no verificada por mí, es DNS con Tailscale activo. En el laboratorio conviene construir la imagen
**antes** de quedarse sin Internet, con márgenes de espera holgados.

**H9 — README del arnés: ruta de `generar-zona.ps1` errónea.** Decía `docker\pc3-administracion-infraind\generar-zona.ps1`;
el fichero llevaba un carácter de control (retroceso, `\b`) en lugar de `\bind\`, invisible al leerlo. Corregido a
`docker\pc3-administracion-infra\bind\generar-zona.ps1`.

**H10 — las imágenes van fijadas por digest, y las etiquetas a secas ya no valen (importa para el paquete offline).**
Al pedir `mariadb:10.6.28` sin digest (para listar un volumen) Docker **descargó** la imagen, aunque el arnés usa esa versión
fijada como `mariadb:10.6.28@sha256:…`: es una referencia distinta para el almacén. En un PC sin Internet cualquier comando que
use la etiqueta sin el digest intentará descargar y fallará. Debe tenerse en cuenta al armar y consumir el paquete offline
(Fase 2), que sigue **NO VERIFICADO**. Por otra parte, la imagen `reservaviva-smoke-openvpms-app` se construye (no se descarga
de un registro), así que el paquete offline tiene que transportarla con `docker save` / `docker load`. Que el `build` funciona
desde cero con Internet queda demostrado aquí.

### 10.6 Estado final de los contenedores (lectura de las 14:38, tras parar `openvpms-app`)

```
dns-interno Up 35 minutes                 | erpnext-backend Up 35 minutes
erpnext-configurator Exited (0) 55 min    | erpnext-create-site Exited (0) 47 min
erpnext-db Up 35 min (healthy)            | erpnext-hr Up 35 min (healthy)
erpnext-ldap-config Exited (0) 46 min     | erpnext-queue-long / -short / scheduler / websocket Up
erpnext-redis-cache / -queue Up           | inventree-app Up (healthy) · inventree-db · inventree-worker Up
ntp-interno Up (healthy)                  | openldap Up
openvpms-db Up                            | openvpms-app Exited (1)  (parado a mano por el bucle de H2)
pretix-db Up · pretix-redis Up            | pretix-web Up 35 min (unhealthy)  (H3)
```

Memoria (una lectura, `docker stats --no-stream`, 14:34): `pretix-web` 3,664 GiB, `inventree-worker` 1,053 GiB,
`openvpms-db` 424,9 MiB, `inventree-app` 321,5 MiB, `erpnext-db` 213 MiB; los nueve contenedores de ERPNext juntos
(incluidos su MariaDB y sus dos Redis) suman ≈ 0,67 GiB. Dentro de WSL quedaban 1.274 MB disponibles (`free -m`). El
consumo de Pretix, no el de ERPNext, es el dominante en este arnés.

### 10.7 Lo que sigue sin verificar

- Que el arnés levante **sano** de principio a fin: falta arreglar H1–H3 y repetir con volúmenes limpios.
- La persistencia LDAP tras `down` sin `-v` + `up -d` en este entorno (no se ejecutó `--persistencia`).
- El login de ERPNext por navegador, y el acceso desde otro PC de la red.
- `openvpms-app` y `pretix-web` funcionando (no responden a pruebas útiles en este estado).
- El paquete offline (Fase 2), incluido el comportamiento de las referencias con digest sin red.

## 11. Arreglos de healthcheck H1, H3 y H4 — SIN VALIDAR EN FRÍO (20/09/2026)

**Estado: cambios escritos y comprobados solo por renderizado y por un experimento parcial. NO VERIFICADO: un arranque
en frío (`docker compose down -v` + `up -d`) con estos cambios. Un re-arranque sobre volúmenes existentes no valida nada:
en la ronda 6 `erpnext-db` pasó a `healthy` en segundos precisamente porque su volumen persistía.**

| Defecto | Cambio (rama `fix/healthchecks-arranque-frio`) | Estado |
|---|---|---|
| H1 `erpnext-db` sin margen | `docker/pc3-administracion-infra/docker-compose.yml`: `start_period: 420s` (medido ≈ 300 s de inicialización con el datadir en `/mnt/d`) | Sin validar en frío |
| H3 `pretix-web` sonda con Host `127.0.0.1` → 400 | `docker/pc2-operaciones/docker-compose.yml`: la sonda envía `Host: ${IP_PC2}` (`urllib.request.Request(..., headers={'Host': ...})`); no se tocan los hosts permitidos de Pretix | Sin validar en frío; `start_period` sin cambios (900 s) hasta medir el arranque real |
| H4 `inventree-app` mismo patrón latente | ídem, `Host: ${IP_PC2}` | Sin validar en frío |

`docker compose config` renderiza las tres sondas correctamente (con `IP_PC2=10.10.30.10`,
`headers={'Host': '10.10.30.10'}`).

### 11.1 Experimento previo: qué `Host` aceptan Pretix e InvenTree (volúmenes existentes)

Solo `pretix-web` e `inventree-app` (con sus bases y Redis), volúmenes de la ronda 6. `ExecMainStartTimestamp` de
`docker.service` = `16:57:29` al inicio y al final (16:57:29 → 16:59:59). Se pidió cada URL desde dentro del propio contenedor
con `urllib` y un `Host` distinto. Salida literal:

```
--- esperando a que pretix-web responda (max ~4 min)
pretix-web sin Host explicito: 400
pretix-web Host=10.10.30.10 -> 200
pretix-web Host=10.10.30.10:18082 -> 200
pretix-web Host=10.10.30.10:80 -> 200
pretix-web Host=localhost -> 200
pretix-web Host=127.0.0.1:80 -> 400
--- inventree-app
inventree-app sin Host explicito: 200
inventree-app Host=10.10.30.10 -> 200
inventree-app Host=10.10.30.10:18083 -> 200
inventree-app Host=10.10.30.10:8000 -> 200
inventree-app Up About a minute (healthy)
inventree-db Up 2 minutes
pretix-db Up 2 minutes
pretix-redis Up About a minute
pretix-web Up About a minute (health: starting)
```

Confirma H3: Pretix devuelve 400 con el `Host` por defecto de la sonda (`127.0.0.1`) y 200 con `Host = IP_PC2`
(con o sin puerto). InvenTree acepta ambos, así que H4 sigue siendo un riesgo latente, no un fallo actual. Límite: se
comprobó el código HTTP con volúmenes ya inicializados, **no** el comportamiento del contenedor en un arranque en frío.

### 11.2 Pendiente de esta sección

- Arranque en frío (`down -v` + `up -d`) con EXIT 0 a la primera, 3 jobs en `Exited (0)`, todos los healthchecks en `healthy`
  (incluido `pretix-web`) y `ldaplogin.py` con PASS: **NO VERIFICADO**.
- Medir el tiempo real de arranque de Pretix para decidir si se puede reducir su `start_period` de 900 s: **NO VERIFICADO**
  (se deja en 900 s).
- Cierre del caso 4 de `ldaplogin.py` (`--persistencia`): **NO VERIFICADO**.

## 12. Pretix partido en `pretix-web` + `pretix-worker` — medición de RAM (20/09/2026)

**Cambio** (`docker/pc2-operaciones/docker-compose.yml`, rama `fix/pretix-split-workers`, partida de `fix/healthchecks-arranque-frio`):
`pretix-web` pasa a `command: ["web"]` con `NUM_WORKERS: "2"` (sin prefijo `PRETIX_`, la lee el script de arranque de la imagen);
nuevo servicio `pretix-worker` (misma imagen y digest, `taskworker --concurrency 2`, `AUTOMIGRATE=skip`, `depends_on: pretix-web
service_healthy`, IP `.13`, sin healthcheck ni puertos); volumen nuevo `pretix_data` montado en `/data` de ambos. Imagen, digest,
healthcheck de H3 y `start_period` de 900 s sin tocar. Es la topología que recomienda la documentación oficial de pretix
(`docker_smallscale`). Antes, `pretix-web` no tenía volumen en `/data`: el fichero `secret` se regeneraba en cada recreación del
contenedor; el volumen compartido lo corrige de paso.

**Prueba**: solo `pretix-db`, `pretix-redis`, `pretix-web`, `pretix-worker`, con `--env-file test.env`, desde una sesión WSL
persistente. `ExecMainStartTimestamp` de docker.service idéntico antes y después (`Sun 2026-09-20 16:57:29 -05`): la medición es válida.
RAM libre antes de arrancar: 6.237.156 KB (~5,9 GiB).

| Comprobación | Resultado (salida literal) |
|---|---|
| a) `docker compose config` | Renderiza bien: `command: [web]`, `NUM_WORKERS: "2"`, volumen `pretix_data` en los dos, worker en `10.10.20.13`, `AUTOMIGRATE: skip`, `depends_on ... condition: service_healthy`. Comillas del healthcheck intactas. |
| b) `pretix-web` healthy | **498 s (8 min 18 s)** desde `up -d` en base vacía (migración incluida). Hasta ese punto `starting`. |
| c) celery conecta | `Connected to redis://10.10.20.12:6379/2` · `celery@d59a6992f806 ready.` · `concurrency: 2 (prefork)` · `inspect ping` → `celery@d59a6992f806: OK  pong  1 node online.` |
| f) la web responde | `GET /control/login/` con `Host: <IP_PC2>` → 302 y, siguiendo la redirección, `200 .../control/login?next=/control/login/` con HTML de Pretix. Sin ese `Host` → 400 (comportamiento ya documentado en H3). |
| /data compartido | Fichero escrito en `pretix-web:/data/media/probe.txt`; `pretix-worker` lo lee (`probe`). |

**d) Medición** (`docker stats --no-stream`, ~1 min tras arrancar el worker; segunda lectura 1 min después):

| Contenedor | MiB 1.ª lectura | MiB 2.ª lectura |
|---|---|---|
| pretix-web | 585,0 | 585,9 |
| pretix-worker | 403,5 | 406,0 |
| **web + worker** | **988,5** | **991,9** |
| pretix-db / pretix-redis | 95,5 / 5,6 | 96,1 / 5,7 |

Antes (contenedor único, medición del 20/09 14:34): **3.751,9 MiB**. Después: **~990 MiB**. Ahorro: **~2.760 MiB (≈73,6 %)**,
mejor que la estimación de ≈1.200 MiB / 2.550 MiB de ahorro. Reserva: es una medición en reposo, sin tráfico de usuarios ni tareas
pesadas; con carga real los procesos crecerán (`--max-requests 1200` los recicla).

**e) Procesos** (`ps -eo pid,rss,args`): `pretix-web` = supervisord + nginx (master + **6** workers, uno por CPU, ~10 MB cada uno)
+ gunicorn master + **2** workers (~255-260 MB RSS cada uno). `pretix-worker` = celery padre (~268 MB) + **2** hijos (~238 MB).
Antes: 12 workers de gunicorn + master y 6 hijos de celery.

**Fuera de alcance, anotado y sin tocar**: nginx sigue abriendo 6 procesos (uno por CPU; coste bajo, ~60 MB en total).

**NO VERIFICADO**: comportamiento bajo carga o con tareas reales de celery (generación de PDF, envío de correo, pagos: solo se
probó conexión y `ping`); que el worker genere un PDF y la web lo sirva de extremo a extremo (solo se probó la compartición de
`/data`); arranque en frío con los 23 contenedores a la vez; efecto del cambio sobre el `start_period` (medido 498 s, no cambiado);
que `pretix-worker` reintente bien tras un reinicio de `pretix-web`.

Limpieza: `docker compose down -v` ejecutado (contenedores, volúmenes y redes del arnés eliminados; imágenes locales intactas).
