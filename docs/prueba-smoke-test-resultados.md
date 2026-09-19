# Resultados de la Prueba de Humo — Un Solo Host (Docker Desktop, Windows 11)

> **Estado:** ejecutada en vivo. Reemplaza el análisis estático previo de esta misma ruta
> (que no se pudo ejecutar porque Docker Desktop no arrancaba). Los hallazgos de aquel
> análisis se contrastan abajo con datos reales.

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

| Servicio | Compose original (sin cambios) | Con correcciones de este PR | Paso manual que queda |
|---|---|---|---|
| OpenLDAP | Arranca solo; bind + búsqueda OK | igual | Ninguno |
| NTP (`cturra/ntp`) | Arranca, `healthy` | igual | Ninguno |
| MySQL (OpenVPMS) | Arranca | igual | — |
| Postgres / Redis (Pretix, InvenTree) | Arrancan | igual | Ninguno |
| **Pretix** | **HTTP 500** (migración falla: `no password supplied`); además Celery buscaba `amqp://127.0.0.1` | HTTP 200 en `/` y `/control/login/` | `createsuperuser` (1 vez) |
| **InvenTree** | **Crash loop** (11 reinicios): falta `SITE_URL`/`CSRF_TRUSTED_ORIGINS`; luego `Database Migrations required` | HTTP 200 en `/api/` | `createsuperuser` (1 vez) |
| **ERPNext** | Contenedor `Up`, gunicorn sirve **HTTP 404** (sin *site*) | sin cambio | Requiere stack completo (ver §4) |
| OpenVPMS app | No evaluable: `docker/pc1-medica/openvpms/` no existe | — | Escribir Dockerfile |
| DNS bind9 | No evaluable: `bind/named.conf` y `bind/zones/` no existen | — | Escribir configuración |

Tiempo de primer arranque: **~10 min** hasta responder HTTP (Pretix e InvenTree aplican cientos
de migraciones). En arranques posteriores es inmediato.

## 3. Correcciones aplicadas a `docker/pc2-operaciones/docker-compose.yml`

El análisis estático previo solo anticipaba el `createsuperuser`; la prueba real mostró que el
compose además tenía **defectos propios**:

- **Pretix:** faltaban `PRETIX_DATABASE_NAME/USER/PASSWORD` (sin ellos no conecta a Postgres) y
  la configuración de Celery (`PRETIX_CELERY_BACKEND/BROKER` → Redis) y `PRETIX_REDIS_SESSIONS`.
  Añadidos, más `PRETIX_PRETIX_URL`.
- **InvenTree:** faltaban `INVENTREE_DB_USER/PASSWORD/PORT` y `INVENTREE_SITE_URL`
  (obligatorio para `CSRF_TRUSTED_ORIGINS`). Se añadió `INVENTREE_AUTO_UPDATE=True`, que elimina
  el paso manual de migraciones, y el volumen `inventree_data` (antes `/home/inventree/data`
  —config, media, backups— se perdía al recrear el contenedor).

## 4. Pasos manuales exactos que faltan

**Pretix** (una vez, tras el primer arranque):
```bash
docker exec -e DJANGO_SUPERUSER_PASSWORD='<clave>' pretix-web \
  python -m pretix createsuperuser --noinput --email admin@reservaviva.local
```

**InvenTree** (una vez):
```bash
docker exec -e DJANGO_SUPERUSER_PASSWORD='<clave>' inventree-app sh -c \
  'cd /home/inventree/src/backend/InvenTree && python manage.py createsuperuser --noinput --username admin --email admin@reservaviva.local'
```

**ERPNext:** no basta con `frappe/erpnext:latest` solo. Evidencia: `sites/common_site_config.json`
está vacío (`{}`) y `bench new-site` falla con `MySQLdb.OperationalError (2002) Can't connect to
server on '127.0.0.1'` (no hay MariaDB). Hace falta el stack de `frappe/frappe_docker`:
MariaDB + `redis-cache` + `redis-queue` + job `configurator` + job `create-site`
(`bench new-site rrhh.reservaviva.local ...`) + `backend`/`frontend`/`scheduler`/`websocket`.
Esto rompe el supuesto de "un contenedor ERPNext" del diseño actual y requiere rediseñar el
servicio en `pc3-administracion-infra`.

## 5. Alcance de LDAP (punto 3 de la solicitud)

- `ldapsearch -x -D cn=admin,dc=reservaviva,dc=local` desde un cliente en `vlan99_infra`
  contra `10.10.99.10`: **OK** (`dn: dc=reservaviva,dc=local`).
- Desde dentro de `pretix-web`, `inventree-app` y `erpnext-hr`: conexión TCP a `10.10.99.10:389`
  y `BindResponse` LDAP válido — **OK** los tres.
- PC-1: como `openvpms-app` no existe, se usó un contenedor sustituto en `vlan10` (+ `vlan99`):
  alcanza LDAP **OK** y `openvpms-db:3306` **OK**.

## 6. Límites de esta prueba (qué NO demuestra)

- **No valida macvlan, 802.1Q, ni el switch.** Solo la capa de software.
- **No valida la segmentación:** para llegar a LDAP las apps se conectaron directamente a
  `vlan99_infra`; por eso, además, Pretix e InvenTree quedan en el mismo segmento L2 en esa red
  (en el diseño real ese tráfico lo bloquearía la matriz del switch/PC-3).
- No se probó autenticación LDAP real desde las apps (solo alcance de red y protocolo).

## 7. Pendientes derivados

1. Rediseñar ERPNext con el stack de `frappe_docker` (bloqueante para PC-3).
2. Dockerfile de OpenVPMS (`docker/pc1-medica/openvpms/`).
3. Configuración de bind9 (`docker/pc3-administracion-infra/bind/`); hoy `docker compose up` en
   PC-3 crearía directorios vacíos en lugar de archivos al montar esas rutas.
4. Documentar en los tutoriales los pasos manuales de la §4 y el tiempo de primer arranque (~10 min).
5. Repetir con macvlan real en los 3 PCs + switch.
