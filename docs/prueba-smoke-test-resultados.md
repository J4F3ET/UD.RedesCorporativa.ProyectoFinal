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

## 6. Límites de esta prueba (qué NO demuestra)

- **No valida macvlan, 802.1Q, ni el switch.** Solo la capa de software.
- **No valida la segmentación:** para llegar a LDAP las apps se unieron directamente a `vlan99_infra`,
  así que Pretix, InvenTree y ERPNext quedan en el mismo segmento L2 (el diseño real lo bloquea la
  matriz del switch/PC-3).
- No se probó autenticación LDAP real desde las apps (solo alcance de red y protocolo), ni LDAPS (636).
- Con `macvlan`, un PC no alcanza sus propios contenedores desde el host: probar desde otro equipo.
- OpenVPMS: el build necesita Internet (~300 MB). La carga de plantillas de impresión (`toolbox template --load --all`) falla en 2.4.0.1 en la plantilla `Investigation` (referencia el tipo inexistente `act.patientInvestigation`); el entrypoint lo tolera y quedan ~37 plantillas cargadas. No se probó el login con usuario/clave (la UI es Echo, no HTTP simple), solo que `admin` recibió su clave (`Password updated`) y que `/openvpms/login` responde 200.

## 7. Pendientes
0. **LDAPS (636) no funciona** (defecto abierto, ver §8): bloquea cualquier integración que exija LDAPS.

1. Resolver o documentar las plantillas de impresión que no cargan en OpenVPMS 2.4.0.1 y añadir LibreOffice/OpenOffice si se necesita combinar documentos.
2. Integrar OpenVPMS, Pretix, InvenTree y ERPNext con LDAP (hoy solo hay alcance de red).
3. Probar LDAPS (636).
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
| LDAPS 636 | **FALLA** (ver abajo) |

Nota: tras el reinicio, la primera petición a `/login` de ERPNext dio un timeout aislado; las siguientes, 200.

### Defecto abierto: LDAPS no funciona (`osixia/openldap:1.5.0`)
- El puerto 636 escucha, pero `slapd` corta la conexión: `TLS: can't accept` / `TLS negotiation failure`.
  Falla con clientes de Python/OpenSSL 3, tanto en TLS 1.2 como en 1.3, y con `ldapsearch -H ldaps://`.
- Solo un `openssl s_client` antiguo (1.1.1) llega a completar el handshake TLS 1.2. Además, la CA por
  defecto de la imagen caducó en enero de 2026, así que un cliente que verifique el certificado lo rechazaría.
- Descartado: no es el tamaño de DH (2048 bits) ni el certificado (ECDSA P-384, válido). Probar
  `LDAP_TLS_CIPHER_SUITE=NORMAL` hizo que el cliente *creyera* completar TLS 1.3, pero al enviar datos la
  conexión se rompía (falso positivo); el cambio se revirtió y **no** está en el repo.
- Ruta sugerida: certificados propios (RSA, CA vigente) montados con `LDAP_TLS_CRT_FILENAME`,
  `LDAP_TLS_KEY_FILENAME` y `LDAP_TLS_CA_CRT_FILENAME`, o cambiar de imagen de OpenLDAP.
- Impacto: con LDAP 389 todo lo probado funciona; si el informe o la sustentación exigen LDAPS, hay que resolverlo.

### Lo que esta ronda sigue sin cubrir
- `deploy.sh` completo, sub-interfaces 802.1Q, `macvlan`, el switch y la matriz de segmentación (requieren Linux con root y el hardware).
- Login de OpenVPMS con usuario y clave (interfaz Echo), y autenticación LDAP *desde* las aplicaciones (solo alcance de red y protocolo).
