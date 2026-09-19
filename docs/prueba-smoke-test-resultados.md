# Resultados de la Prueba de Humo — Un Solo Host (Docker Desktop, Windows 11)

> **Estado:** ejecutada en vivo en **dos rondas**. Ronda 1: compose originales (PC-2 con defectos,
> ERPNext sin site, sin DNS ni OpenVPMS). Ronda 2: con las correcciones de este PR (PC-2 corregido,
> stack completo de ERPNext, bind9, admins automáticos). Reemplaza el análisis estático previo.
> **Pendiente de probar:** el build y arranque de `openvpms-app` (PC-1).

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
| OpenVPMS app | No evaluable: no existía `openvpms/` | Dockerfile y entrypoint escritos, **sin probar** | Por confirmar |

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

**`docker/pc1-medica`** (sin probar): `openvpms/Dockerfile` (Tomcat 9, Java 11, OpenVPMS 2.4.0.1,
driver MySQL Connector/J 8.0.33) y `entrypoint.sh` que espera a MySQL, crea el esquema, carga datos
base y genera el WAR en el primer arranque. Variables nuevas: `OPENVPMS_DB_PASSWORD`, `OPENVPMS_ADMIN_PASSWORD`.

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
- `openvpms-app` (PC-1) no se ha construido ni arrancado.

## 7. Pendientes

1. Construir y probar `openvpms-app` (~300 MB de descarga; necesita Internet una vez).
2. Integrar OpenVPMS, Pretix, InvenTree y ERPNext con LDAP (hoy solo hay alcance de red).
3. Probar LDAPS (636).
4. Repetir con macvlan real en los 3 PCs + switch; confirmar si es L2 o L3.
5. Aclarar en el informe el alcance de ERPNext (solo HR) y Pretix vs. PretixPOS.
