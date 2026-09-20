# Laboratorio Reserva Viva: rediseño a 3 PCs por departamento, despliegue plug-and-play y pruebas reales en un host (PR #3 mergeado)

**Date:** 2026-09-19
**Status:** IN PROGRESS (software validado en un solo host; falta hardware real: macvlan/802.1Q/switch e integración LDAP en las apps)
**Bead(s):** none (bd no está instalado en esta máquina)
**Epic:** Proyecto final Redes Corporativas (UD) — Laboratorio "Reserva Viva"
**Chain:** `standalone-9e6e8d31` seq `1`
**Parent:** `none — first in chain`
**Prior chain:** none — first in chain

---

## Related Handoffs

- `HANDOFF_standalone-cad62bb5_smoke-test-consolidacion_2026-09-19.md` — handoff de la sesión par "Consolidación y prueba del proyecto" (sesión 65a096); cubre su propio hilo de consolidación y el análisis estático previo del smoke test. Es un flujo de trabajo separado, NO padre de este archivo.
- `PLAN_standalone-cad62bb5_smoke-test-consolidacion_2026-09-19.md` — plan de esa misma sesión par.

## Reference Documents

- `docs/arquitectura-3-equipos-departamentos.md` — documento de diseño vigente (confirmado por el usuario a través de la sesión par: "el laboratorio real usa 3 equipos"). Secciones: 1 cambio de 2→3 PCs, 2 agrupación, 3 direccionamiento, 4 matriz de segmentación, 5 enrutamiento L2/L3, 6 apps, 7 plan de pruebas, 8 plug-and-play, 9 siguientes pasos.
- `docs/prueba-smoke-test-resultados.md` — resultados reales de las 4 rondas de prueba (160 líneas, §1–§8). Es la fuente de verdad de lo probado.
- `docs/borradores/arquitectura-2-equipos.md` — borrador de la sesión par para el escenario alternativo de 2 equipos; el usuario confirmó que NO aplica.
- `README.md` (raíz) — índice del repo; la sesión par lo actualizó con los hallazgos.
- `tutoriales/README.md` + un tutorial por PC — guías para personal no técnico (mantenidas por la sesión par).
- `diagramas/` — diagramas Archify (topología y flujo de datos) en la rama original `claude/project-handoff-departments-g266yp`.
- No existe CLAUDE.md ni "bible" en el repo.

## The Goal

Entregar el laboratorio de la red corporativa del zoológico "Reserva Viva" (curso Redes Corporativas, Universidad Distrital) separado por departamentos en **3 PCs**: PC-1 Médica (OpenVPMS, VLAN 10), PC-2 Operaciones (Pretix VLAN 20 + InvenTree VLAN 30) y PC-3 Administración e Infraestructura (ERPNext-HR VLAN 40 + OpenLDAP/DNS/NTP VLAN 99). El estado final deseado por el usuario es que sea **plug and play**: copiar `.env.example` a `.env`, ejecutar un solo `deploy.sh` por PC y que todo quede funcionando, con tutoriales para personas no técnicas, diagramas del flujo de datos y una prueba real que lo respalde. La segmentación exige que las VLAN de negocio solo alcancen la VLAN 99 (LDAP/DNS/NTP) y nunca entre sí.

## Where We Are

- Rama de trabajo `docs/prueba-smoke-test-real` está alineada con `origin/docs/prueba-smoke-test-real` y **su PR #3 ya está MERGEADO a master** (merge commit `752e41f`, 2026-09-19T20:49:29Z). PR #2 (smoke test + correcciones PC-2) y PR #1 (rediseño a 3 equipos) también mergeados. Working tree limpio al momento del handoff.
- `docker/pc1-medica/`: `docker-compose.yml`, `deploy.sh`, `.env.example`, y ahora `openvpms/Dockerfile` + `openvpms/entrypoint.sh` (escritos por la sesión par, commits `58ed37c` y `9198549`); OpenVPMS 2.4.0.1 se construye desde Internet (~300 MB de descarga).
- `docker/pc2-operaciones/docker-compose.yml`: Pretix con `PRETIX_DATABASE_NAME/USER/PASSWORD`, `PRETIX_REDIS_LOCATION redis://10.10.20.12/0`, `PRETIX_REDIS_SESSIONS "true"`, `PRETIX_CELERY_BACKEND redis://10.10.20.12/1`, `PRETIX_CELERY_BROKER redis://10.10.20.12/2`, `PRETIX_PRETIX_URL http://10.10.20.10`; InvenTree con `INVENTREE_DB_PORT/USER/PASSWORD`, `INVENTREE_SITE_URL http://10.10.30.10:8000`, `INVENTREE_AUTO_UPDATE "True"`, `INVENTREE_ADMIN_USER/PASSWORD/EMAIL`, volumen `inventree_data:/home/inventree/data`, healthcheck (start_period 900s) y nuevo servicio `inventree-worker` (10.10.30.12, `invoke worker`, depende de `inventree-app` healthy).
- `docker/pc2-operaciones/deploy.sh`: nueva función `init_admins()` que espera a Pretix (hasta 120 intentos x 10 s) y crea el superusuario con `python -m pretix shell` (idempotente), y **elimina el usuario por defecto `admin@localhost`** (clave "admin"); modo `--solo-admins` para reintentar solo eso sin tocar VLANs.
- `docker/pc3-administracion-infra/docker-compose.yml`: ERPNext rediseñado con el stack frappe_docker: `erpnext-db` (mariadb:10.6 con healthcheck), `erpnext-redis-cache`, `erpnext-redis-queue`, `erpnext-configurator` (job), `erpnext-create-site` (job idempotente: comprueba `sites/$SITE/site_config.json`), `erpnext-backend` (10.10.40.11), `erpnext-websocket`, `erpnext-scheduler`, `erpnext-queue-short`, `erpnext-queue-long`, `erpnext-hr` (nginx, 10.10.40.10, **puerto 8080**). Red privada `erpnext_internal` (bridge) para BD/Redis/workers. Ancla YAML `x-erpnext-volumes`.
- `docker/pc3-administracion-infra/bind/named.conf` + `bind/zones/db.reservaviva.local` (serial 2026091901): zona interna con dns .99.11, ldap .99.10, ntp .99.12, openvpms .10.10, pretix .20.10, inventree .30.10, rrhh .40.10; `recursion no`, `allow-query {10.10.0.0/16; 127.0.0.1}`.
- LDAPS (commit `9dd9688`, sesión par): `scripts/generar-certificados.sh` (CA interna 10 años + certificado 825 días con SAN), `certs/` en `.gitignore`, `LDAP_TLS_VERIFY_CLIENT=never`, invocado desde `docker/pc3-administracion-infra/deploy.sh`.
- Arnés `pruebas/smoke-test-3-pcs/`: `docker-compose.yml` (`name: reservaviva-smoke`, `include:` de los 3 compose reales con overrides), `override-pc1/2/3.yml` (macvlan→bridge, `!override`), `test.env` (contraseñas `smoketest-*`), `probe.py`, `ldapprobe.py`, `README.md`. Ya no quedan `dns: !reset null` ni el `erpnext-hr` antiguo; en pc3 `erpnext-backend` se une a `vlan99_infra` como 10.10.99.23.
- Prueba de la ronda 4 (sesión par, commit `4e06f89`): 22 contenedores desde cero, todo 200/OK, primer arranque ~13 min, reinicio simulado OK.
- **Nada de macvlan, 802.1Q, deploy.sh completo (requiere root/Linux) ni el switch ha sido probado**: la máquina de pruebas es Windows 11 con Docker Desktop 29.x.
- Contenedores del arnés bajados con `docker compose down -v` al terminar; imágenes quedan cacheadas localmente (frappe/erpnext v15 y latest 4.22 GB, mariadb:10.6, postgres:15, pretix/standalone:stable, inventree/inventree:stable, redis:7, osixia/openldap:1.5.0, bind9:9.18, cturra/ntp, python:3-slim, alpine, curlimages/curl).

## What We Tried (Chronological)

1. **Rediseño 2→3 PCs (inicio)** — Hipótesis: agrupar por departamento minimiza cruces entre VLAN. Cambios: `docs/arquitectura-3-equipos-departamentos.md`, tres carpetas `docker/pcN-*`, macvlan por VLAN con `parent: ${IFACE:-eth0}.NN`. Resultado: diseño aceptado (PR #1 mergeado). Nota: VLAN20 y VLAN30 comparten PC-2, por lo que existe hairpin entre ellas; se resuelve con nftables (`scripts/firewall-pc3-matriz.sh`) o con ACL en un switch L3.
2. **Plug-and-play (scripts)** — Se añadieron `scripts/setup-vlans-pc2.sh`, `setup-vlans-pc3.sh` (idempotentes; `IFACE`, `FALLBACK_L2`), `firewall-pc3-matriz.sh` (nftables) y unidades `systemd/reserva-viva-pc{1,2,3}.service`; cada `deploy.sh` carga `.env`, prepara VLANs y ejecuta `docker compose up -d`. Resultado: aceptado; pendiente probarlo en Linux real.
3. **Tutoriales no técnicos** — `tutoriales/README.md` + tres tutoriales (uno por PC). Resultado: aceptados; la sesión par los mantiene actualizados con las variables nuevas.
4. **Diagramas con Archify** — El usuario respondió "Es un plugin/MCP que debo instalar" con URL https://github.com/tt-a1i/archify y "Sí, instalar y usar Archify". Se generaron `diagramas/topologia-red.html`/`.architecture.json` y `flujo-datos-segmentacion.html`/`.dataflow.json` (commit `d13a109` en la rama claude/…). Resultado: hecho; verificar que llegaron a master vía PR (solo se confirmó que PR #1 subió hasta `6ae51e6`).
5. **Revisión de vacíos ("qué crees que hace falta")** — Se listaron: sin Dockerfile OpenVPMS, sin bind9, ERPNext sin stack, falta manejo de superusuarios, sin prueba real. Resultado: motivó las pruebas.
6. **Intento de prueba en sandbox cloud** — No había daemon Docker; se levantó dockerd allí. Superado cuando el usuario dijo "en mi computador local" y la sesión pasó a su Windows.
7. **Primera prueba local (ronda 1)** — Comando: `docker compose pull` en el arnés. Falló con 500 del pipe de Docker Desktop porque el motor aún arrancaba; reintento OK (~10+ min; ERPNext 4.22 GB). Resultado: stack arriba con compose originales corregidos solo por overrides.
8. **Pretix (ronda 1)** — Compose original: HTTP 500 (`fe_sendauth: no password supplied`) y Celery buscaba `amqp://127.0.0.1`. Se añadieron credenciales de BD + variables Redis/Celery/URL. Resultado: 200 en `/` y `/control/login/` tras ~10 min de migraciones.
9. **InvenTree (ronda 1)** — Crash loop de 11 reinicios: faltaba `INVENTREE_SITE_URL` (CSRF_TRUSTED_ORIGINS), luego "Database Migrations required". Se añadieron SITE_URL, DB_USER/PASSWORD/PORT, `INVENTREE_AUTO_UPDATE=True` y volumen de datos. Resultado: 200 en `/api/`.
10. **ERPNext (ronda 1)** — `frappe/erpnext:latest` solo: contenedor Up pero HTTP 404 (sin site), `common_site_config.json = {}`, `bench new-site` falla con `MySQLdb.OperationalError (2002)` a 127.0.0.1. No arreglable con un contenedor: documentado y delegado a la ronda 2.
11. **LDAP alcance (ronda 1)** — `ldapsearch -x -D cn=admin,dc=reservaviva,dc=local` desde vlan99 OK; `ldapprobe.py` (bind anónimo crudo a 10.10.99.10:389) desde `pretix-web`, `inventree-app`, `erpnext-hr` → `BindResponse` válido. Nota metodológica: las IP de bridge de Docker Desktop no son alcanzables desde el host; todas las sondas se hicieron desde contenedores auxiliares en cada red.
12. **Rediseño ERPNext + bind9 + admins (ronda 2)** — Encargo de la sesión par ("Confirmado por el usuario: el laboratorio real usa 3 equipos"): frappe_docker con site automático, bind9, superusuarios automáticos y workers. Decisión: pinnear `frappe/erpnext:v15` porque `latest` resultó ser `17.0.0-dev`. **Error 1:** MariaDB 10.6 no reconoce `--skip-innodb-read-only-compatibility` (opción de 11.8) → `unknown option`, contenedor en bucle, `erpnext-db is unhealthy`; se quitó la opción. **Error 2 (falso):** probe con `-e U=` no pasaba la URL (probe.py lee argv) → se repitió con argumento. **Hallazgo:** nginx de la imagen frappe escucha en **8080** (`/proc/net/tcp` mostraba 0x1F90), no en 80 → documentado `http://10.10.40.10:8080`. Resultado: ping 200, `/login` 200, login `Administrator` 200; `create-site` re-ejecutado imprime "ya existe".
13. **Admin de Pretix (ronda 2)** — Se descubrió que existía `admin@localhost` (default de la imagen). Se añadió su borrado en `init_admins()`. Verificado: lista de usuarios pasó de `['admin@localhost','admin@reservaviva.local']` a `['admin@reservaviva.local']`.
14. **Autoedición accidental de CRLF** — `python open(..., 'w')` en Windows escribió CRLF en `deploy.sh`; git avisó "CRLF will be replaced by LF". Se corrigió con `sed -i 's/\r$//'`; `.gitattributes` (`*.sh text eol=lf`, Dockerfile, *.service) lo protege. Lección: usar Write o `newline='\n'` para archivos que se ejecutan en Linux.
15. **Rondas 3–4 (sesión par)** — OpenVPMS: se corrigió el entrypoint tras el build real (`9198549`); plantilla `Investigation` no carga en 2.4.0.1 (tipo `act.patientInvestigation` inexistente) y se tolera (~37 plantillas cargadas). Ronda 4 completa con 22 contenedores y reinicio simulado (`4e06f89`).
16. **LDAPS (sesión par)** — Falló en la primera corrida (slapd cortaba el handshake). Yo aporté solo hipótesis no verificadas (clave/firma débil, cifrados). Causa real, hallada por la sesión par: `LDAP_TLS_VERIFY_CLIENT=demand` por defecto en osixia/openldap:1.5.0 (exige certificado al cliente) + CA de la imagen caducada en enero de 2026. Corregido en `9dd9688`. Mis hipótesis 1 y 2 (RSA/SHA1, cipher suite) fueron **descartadas** por la sesión par (la de cipher suite daba falso positivo en TLS 1.3).

## Key Decisions

- **Entorno de prueba = arnés con bridge en lugar de macvlan.** Docker Desktop/Windows no soporta macvlan hacia una VLAN real; se sustituyeron redes con `!override` conservando subredes y gateways (10.10.X.0/24, .1). Rechazado: probar macvlan localmente (imposible sin Linux con root y un switch).
- **`include:` de los compose reales + overrides** en vez de copiar los compose. Así la prueba ejercita los archivos reales que se despliegan; el override solo cambia red y desactiva lo imposible. Rechazado: mantener un compose duplicado de pruebas (`pruebas/software-un-host/`, commit `8e1e0bb` en la rama claude/… — quedó como alternativa más simple).
- **Simular la ruta a LDAP conectando las apps a `vlan99_infra`** (pretix .99.21, inventree .99.22, erpnext-backend .99.23). Consecuencia consciente: da adyacencia L2 y por tanto NO valida la segmentación (Pretix e InvenTree quedan en el mismo segmento en esa red).
- **ERPNext = stack frappe_docker, imagen fijada a `v15`** (no `latest`, que era v17-dev; no v16 para no correr detrás de cambios). MariaDB 10.6, `redis:7` (ya cacheada localmente).
- **Solo `erpnext-hr` y `erpnext-backend` en VLAN40**; BD/Redis/workers en red bridge privada `erpnext_internal`. El backend está en VLAN40 (10.10.40.11) para que su tráfico a LDAP salga por el gateway .40.1 y lo filtre la matriz.
- **Superusuarios sin intervención manual:** InvenTree por variables `INVENTREE_ADMIN_*` (lo crea `apps.py` al arrancar); Pretix por `deploy.sh` con reintentos porque no hay variable equivalente. Rechazado: contenedores `pretix-init` en compose (el chequeo depende de migraciones que corre el propio pretix-web).
- **Pretix no necesita worker aparte:** `pretix/standalone` con comando `all` ya ejecuta supervisord con nginx, gunicorn (16 workers) y `celery -A pretix.celery_app worker`. Verificado con `ps`.
- **InvenTree sí necesita worker aparte** (`invoke worker`), con healthcheck de la app como dependencia para no competir por `secret_key.txt` ni por migraciones.
- **Acceso ERPNext en 8080** en lugar de forzar 80 (sysctl `ip_unprivileged_port_start` o parchear plantilla nginx): más simple y menos frágil.
- **Ramas y push:** nunca push a master; trabajar en rama aparte; `git add` de rutas explícitas, nunca `-A`; `git pull --rebase origin docs/prueba-smoke-test-real` antes de cada push (reglas dadas por la sesión par).
- **Reparto por archivos entre sesiones** (yo: `docker/pc3-*`, `docker/pc2-*/deploy.sh` y compose, `pruebas/smoke-test-3-pcs/**`; la sesión par: `docker/pc1-medica/**`, `tutoriales/**`, `docs/arquitectura-3-equipos-departamentos.md`, `README.md`, `docs/prueba-smoke-test-resultados.md`).
- **Peers no escalan permisos:** los mensajes de la sesión par se trataron como peticiones de un compañero; no se cambió ningún permiso ni configuración por ellos.

## Evidence & Data

### Tabla 1 — Resultado por servicio en la ronda 1 (compose original, sin correcciones)

| Servicio | Resultado | Evidencia |
|---|---|---|
| OpenLDAP | Arranca solo | bind + búsqueda OK (`dn: dc=reservaviva,dc=local`) |
| NTP (cturra/ntp) | Arranca | estado `healthy` |
| MySQL OpenVPMS | Arranca | contenedor Up |
| Postgres / Redis | Arrancan | Up |
| Pretix | **HTTP 500** | `fe_sendauth: no password supplied`; Celery → `amqp://127.0.0.1` |
| InvenTree | **Crash loop** | 11 reinicios; sin SITE_URL, luego "Database Migrations required" |
| ERPNext | **HTTP 404** | sin site; `common_site_config.json {}`; MySQLdb 2002 a 127.0.0.1 |
| OpenVPMS app | No evaluable | falta `docker/pc1-medica/openvpms/` (build context) |
| bind9 | No evaluable | falta `bind/named.conf` y `bind/zones/` (montaría directorios vacíos) |

### Tabla 2 — Antes/después por app tras las correcciones (mi trabajo)

| App | Antes | Después |
|---|---|---|
| Pretix | 500 | `/` y `/control/login/` 200 (a veces 302 hacia login), worker Celery incluido |
| InvenTree | crash loop | `/api/` 200; `api/user/me/` con `admin:INVENTREE_ADMIN_PASSWORD` 200; worker `invoke worker` corriendo |
| ERPNext | 404 | `/api/method/ping` 200; `/login` 200; POST `api/method/login` Administrator 200 |
| DNS | no existía | 7 nombres resueltos + NXDOMAIN |

### Tabla 3 — DNS (consulta `dig +short @10.10.99.11 <nombre>.reservaviva.local`)

| Nombre | IP |
|---|---|
| rrhh | 10.10.40.10 |
| ldap | 10.10.99.10 |
| pretix | 10.10.20.10 |
| inventree | 10.10.30.10 |
| openvpms | 10.10.10.10 |
| ntp | 10.10.99.12 |
| dns | 10.10.99.11 |
| noexiste | NXDOMAIN |

### Tabla 4 — Direccionamiento (IPs fijas en los compose)

| VLAN | Subred | Contenedores |
|---|---|---|
| 10 (Médica) | 10.10.10.0/24, gw .1, ip_range /28 | openvpms-app .10, openvpms-db .11 |
| 20 (Taquilla) | 10.10.20.0/24 | pretix-web .10, pretix-db .11, pretix-redis .12 |
| 30 (Logística) | 10.10.30.0/24 | inventree-app .10, inventree-db .11, inventree-worker .12 |
| 40 (RRHH) | 10.10.40.0/24 | erpnext-hr .10, erpnext-backend .11 |
| 99 (Infra) | 10.10.99.0/24 | openldap .10, dns-interno .11, ntp-interno .12 (+ arnés: pretix .21, inventree .22, erpnext-backend .23) |

### Tabla 5 — Ronda 4 completa (sesión par, commit `4e06f89` y `9dd9688`)

| Prueba | Resultado |
|---|---|
| HTTP por VLAN (OpenVPMS `:8080/openvpms/login`, Pretix, InvenTree `:8000/api/`, ERPNext `:8080`) | 200 en todas |
| LDAP 389 bind crudo (pretix-web, inventree-app, erpnext-backend) + TCP desde openvpms-app | OK los 4 |
| ldapsearch autenticado clave correcta / errónea | Success / Invalid credentials (49) |
| ERPNext login real correcta / errónea | 200 / 401 |
| Reinicio simulado `down` sin `-v` + `up -d` | 20 arriba + 2 Exited(0) por diseño; datos persisten |
| LDAPS 636 (tras la corrección) | OK con cadena y nombre verificados desde 3 apps |
| Tiempo primer arranque total | ~13 min (cuello: `erpnext-create-site`); OpenVPMS ~5 min |
| Memoria pico | openvpms-app ~750 MB; inventree-app ~510 MB |

### Tabla 6 — Tiempos observados en mi ronda 2

| Etapa | Tiempo |
|---|---|
| Pull imágenes ERPNext v15 + MariaDB + bind9 | ~5 min |
| `erpnext-configurator` | segundos (Exited 0) |
| `erpnext-create-site` (instalar frappe + erpnext) | ~9 min (log: "Updating DocTypes for erpnext ... %") |
| Pretix + InvenTree migraciones primer arranque | ~7-8 min (InvenTree healthy a los ~8 min) |
| `up -d` bloqueó >300 s en foreground por depender de `create-site` | pasar a background |

### Historial de commits (rama `docs/prueba-smoke-test-real`, todos ya en master)

| Hash | Autor de trabajo | Resumen |
|---|---|---|
| `baacac6` | par | resultados estáticos + borrador 2 equipos |
| `291b118` | par | arnés inicial de un host |
| `f2cf156` | par | session: smoke-test-consolidacion (handoff+plan del par) |
| `dc139f7` | yo | prueba real 1: correcciones PC-2, resultados, ldapprobe.py, README arnés |
| `5448a2c` | par | hallazgos en arquitectura y README |
| `58ed37c` | par | Dockerfile/entrypoint OpenVPMS (sin probar) |
| `898602b` | par | tutorial PC-1 con variables |
| `6422ab4` | yo | ERPNext frappe_docker, bind9, admins automáticos, worker InvenTree |
| `4b3079b` | par | tutoriales PC-2/PC-3 y resultados ronda 2 |
| `9198549` | par | entrypoint OpenVPMS corregido tras build real |
| `4e06f89` | par | prueba completa 3 PCs, ronda 4 |
| `9dd9688` | par | LDAPS: CA y certificados propios, script, `LDAP_TLS_VERIFY_CLIENT=never` |
| `752e41f` | merge | PR #3 en master |

### Variables nuevas en `.env.example`

```text
pc3: ERPNEXT_DB_ROOT_PASSWORD, ERPNEXT_ADMIN_PASSWORD (obligatorias), ERPNEXT_SITE (=rrhh.reservaviva.local)
pc2: INVENTREE_ADMIN_PASSWORD (oblig.), INVENTREE_ADMIN_USER (=admin), INVENTREE_ADMIN_EMAIL,
     PRETIX_ADMIN_EMAIL, PRETIX_ADMIN_PASSWORD (oblig. para deploy.sh)
pc1 (par): variables de OpenVPMS (OPENVPMS_DB_ROOT_PASSWORD, OPENVPMS_DB_PASSWORD, OPENVPMS_ADMIN_PASSWORD)
```

### Comandos clave verificados

```bash
# Sondas HTTP desde un contenedor auxiliar dentro de la red (no desde el host):
docker run --rm --network reservaviva-smoke_vlan40_rrhh -i python:3-slim python3 - http://10.10.40.10:8080/login < probe.py
# Login real de ERPNext
docker run --rm --network reservaviva-smoke_vlan40_rrhh curlimages/curl -s -o /dev/null -w '%{http_code}' \
  -X POST http://10.10.40.10:8080/api/method/login -d 'usr=Administrator&pwd=<clave>'
# Reintentar admin de Pretix
(set -a; . ./test.env; set +a; bash ../../docker/pc2-operaciones/deploy.sh --solo-admins)
# Reproducir la prueba
cd pruebas/smoke-test-3-pcs && docker compose pull && docker compose up -d  # tarda ~13 min; usar background
```

### Rutas de datos

- Transcripción completa de esta sesión: `C:\Users\jafet\.claude\projects\D--Proyectos-UD-RedesCorporativaa-ProyectoFinak\bffa2d68-98da-46c1-a193-02954bb07349.jsonl`
- Resultados oficiales: `docs/prueba-smoke-test-resultados.md`
- Salida de tareas en background: `C:\Users\jafet\AppData\Local\Temp\claude\D--Proyectos-UD-RedesCorporativaa-ProyectoFinak\bffa2d68-98da-46c1-a193-02954bb07349\tasks\`

### Anexo A — HALLAZGO IMPORTANTE de última hora: diagramas y prueba alternativa NO están en master

Comprobado con `git ls-tree -r --name-only origin/master | grep -E '^(diagramas|pruebas/software-un-host)'` → **0 archivos**. PR #1 solo llevó la rama `claude/project-handoff-departments-g266yp` hasta `6ae51e6`; los commits posteriores de esa rama no llegaron a master:

| Commit (rama claude/…) | Contenido | ¿En master? |
|---|---|---|
| `d13a109` | `diagramas/` (topologia-red.html/.architecture.json, flujo-datos-segmentacion.html/.dataflow.json, README.md) | **No** |
| `8e1e0bb` | `pruebas/software-un-host/` (docker-compose bridge, verificar.sh, README, .env.example) | **No** |

Consecuencia: el diseño en master enlaza a `diagramas/` desde `docs/arquitectura-3-equipos-departamentos.md`, pero los archivos no existen ahí (enlaces rotos). Acción recomendada en el plan (Fase 1): traer esos commits a una rama nueva desde master (`git cherry-pick d13a109 8e1e0bb` o `git checkout claude/project-handoff-departments-g266yp -- diagramas pruebas/software-un-host`) y abrir PR. Además hay que actualizar los diagramas: ERPNext ahora es un stack (db, redis x2, backend, websocket, scheduler, 2 workers, nginx en :8080), hay bind9 con zona real, LDAPS con CA interna y `inventree-worker`.

### Anexo B — Matriz de segmentación vigente (diseño, sin probar en hardware)

| Origen \ Destino | VLAN10 | VLAN20 | VLAN30 | VLAN40 | VLAN99 |
|---|---|---|---|---|---|
| VLAN10 Médica | — | ✗ | ✗ | ✗ | ✓ (LDAP 389/636, DNS 53, NTP 123) |
| VLAN20 Taquilla | ✗ | — | ✗ (hairpin en PC-2) | ✗ | ✓ |
| VLAN30 Logística | ✗ | ✗ (hairpin en PC-2) | — | ✗ | ✓ |
| VLAN40 RRHH | ✗ | ✗ | ✗ | — | ✓ |
| VLAN99 Infra | responde | responde | responde | responde | — |

Dónde se aplica: switch L3 con SVI + ACL (opción preferida) o, si el switch es L2 puro, router-on-a-stick en PC-3 con `scripts/firewall-pc3-matriz.sh` (nftables, `FALLBACK_L2=true`, que además crea sub-interfaces .10/.20/.30 en PC-3). En la prueba de un host esta matriz **no se ejerce**.

### Anexo C — Imágenes y tags usados

| Componente | Imagen | Nota |
|---|---|---|
| OpenLDAP | `osixia/openldap:1.5.0` | `LDAP_TLS_VERIFY_CLIENT` por defecto `demand` (causa del fallo LDAPS); CA de la imagen caducada en enero 2026 |
| DNS | `internetsystemsconsortium/bind9:9.18` | monta named.conf y zones ro |
| NTP | `cturra/ntp:latest` | healthy en ~5 s |
| ERPNext | `frappe/erpnext:v15` | `latest` = `17.0.0-dev` (comprobado en `apps/erpnext/erpnext/__init__.py`); bench 5.31.0; ~4 GB |
| MariaDB | `mariadb:10.6` (10.6.28) | no admite `--skip-innodb-read-only-compatibility` |
| Redis | `redis:7` | ya cacheada localmente |
| Pretix | `pretix/standalone:stable` | Python 3.13; celery + gunicorn + nginx internos |
| InvenTree | `inventree/inventree:stable` | commit `5bd6e03` (2026-09-16); Python 3.14 en el worker |
| Postgres | `postgres:15` | Pretix e InvenTree |
| OpenVPMS | build local `docker/pc1-medica/openvpms/` | 2.4.0.1; MySQL para openvpms-db |

Tags de Docker Hub de `frappe/erpnext` observados vía API: `v16`, `v16.35.0`, `v15`, `v15.121.3` (los `v15.x`/`v16.x` cambian a diario).

### Anexo D — Cronología de mensajes cruzados entre sesiones

| # | De → A | Contenido | Acción tomada |
|---|---|---|---|
| 1 | par → yo | Petición inicial del smoke test (bridge, servicios sin config extra, alcance LDAP, corregir `docs/prueba-smoke-test-resultados.md`; no push a master) | Ejecutada (ronda 1), commit `dc139f7` |
| 2 | par → yo | Pidió resumen corto (5 puntos) y que no tocara nada | Respondí con evidencia; aclaré que los 9 contenedores que veía no eran míos (yo ya había hecho `down -v`) |
| 3 | par → yo | "Confirmado por el usuario: 3 equipos"; reparto de archivos; encargo de ERPNext frappe_docker, bind9, superusuarios/workers, arnés | Acepté; ronda 2, commit `6422ab4` |
| 4 | par → yo | Pidió estado por bloque y variables nuevas | Respondí con lista de variables y bloqueos (ninguno) |
| 5 | yo → par | Informe final de bloques a–d (hash `6422ab4`, resultados) | Enviado |
| 6 | par → yo | Corre la prueba completa; no toques Docker ni archivos | Respetado (nada corriendo) |
| 7 | par → yo | LDAPS falla; ¿ideas? no cambies archivos | Respondí con hipótesis (no verificadas) |
| 8 | usuario → yo | `/handoffplan` | Este handoff |

### Anexo E — Diagnósticos concretos y mensajes de error exactos

```text
Docker Desktop (1er pull):  500 Internal Server Error desde el pipe  → el motor no había terminado de arrancar; reintentar.
Pretix (compose original):  psycopg2 fe_sendauth: no password supplied ; Celery: Cannot connect to amqp://guest@127.0.0.1:5672
InvenTree (1):              CSRF_TRUSTED_ORIGINS / SITE_URL not set        → crash loop (11 reinicios)
InvenTree (2):              Database Migrations required                   → añadir INVENTREE_AUTO_UPDATE=True
ERPNext (original):         sitio no existe → 404 ; bench new-site → MySQLdb.OperationalError (2002) Can't connect to server on '127.0.0.1'
MariaDB 10.6 con opción 11.8: [ERROR] mariadbd: unknown option '--skip-innodb-read-only-compatibility'
Compose:                    dependency failed to start: container erpnext-db is unhealthy
osixia ldapsearch:          usage error al invocarlo como comando → usar --entrypoint ldapsearch
Git Bash (rutas):           //D:/Git/probe.py y D:\Git\home\... → MSYS_NO_PATHCONV=1 ; `pwd -W`
                            `docker cp` inestable → canalizar con  docker exec -i <c> python3 - < archivo
Bash tool:                  `sleep 60 && ...` BLOQUEADO → usar Monitor con until-loop o run_in_background
Puerto ERPNext:             nginx escucha 8080 (0x1F90 en /proc/net/tcp), no 80
Python en Windows:          open(...,'w') escribe CRLF → romper .sh en Linux; usar sed -i 's/\r$//' o Write
Sondas de aplicación:       IP de bridge de Docker Desktop NO alcanzable desde el host → usar contenedores auxiliares en la red
Primer /login ERPNext:      TimeoutError aislado tras arranque en frío; siguientes 200 (también tras reinicio simulado)
```

### Anexo F — Comportamiento de arranque por aplicación (para calibrar esperas)

| App | Qué pasa en el primer arranque | Cuándo está lista |
|---|---|---|
| Pretix | migraciones Django (cientos), crea `admin@localhost` | ~7–10 min; `deploy.sh` espera hasta 20 min |
| InvenTree | migraciones + estáticos + secret key + admin por variables | healthy ~8 min (start_period 900 s) |
| ERPNext | configurator (s) → create-site (bench new-site + install erpnext) → backend/workers/nginx | ~9 min de create-site; total ~13 min |
| OpenVPMS | descarga/compila, inicializa BD, carga plantillas (falla `Investigation`, tolerado), pone clave a `admin` | ~5 min en paralelo |
| bind9 / NTP / LDAP | inmediato | < 10 s |
| Reinicios posteriores | todo reanuda de volúmenes; `create-site` responde "ya existe"; sin reinit | < 2 min |

### Anexo G — Verificaciones realizadas en la ronda 2 (mías), una por una

1. `docker compose config -q` con el arnés → `CONFIG_OK` (avisos por `OPENVPMS_DB_PASSWORD` sin definir en ese momento).
2. `docker compose ps -a` tras `up -d` (22 servicios; `erpnext-configurator` y `erpnext-create-site` `Exited (0)` como jobs).
3. `probe.py` contra `http://10.10.40.10:8080/api/method/ping` → `200`; `/login` → `200` (tras un timeout inicial con curl de 60 s).
4. Login real ERPNext con `curlimages/curl` → `200` con la clave de `test.env`.
5. `dig +short @10.10.99.11 <n>.reservaviva.local` para 7 nombres → IPs esperadas; inexistente → `NXDOMAIN`.
6. `deploy.sh --solo-admins` con `test.env` exportado → "Administrador de Pretix listo: admin@reservaviva.local"; segunda ejecución igual (idempotente).
7. `python -m pretix shell -c` listó usuarios; tras la mejora solo `['admin@reservaviva.local']`.
8. `curl -u admin:<clave> http://10.10.30.10:8000/api/user/me/` → `200`.
9. `docker exec inventree-worker cat /proc/1/cmdline` → `/usr/local/bin/python /usr/local/bin/invoke worker`.
10. `docker start -a erpnext-create-site` → "El sitio rrhh.reservaviva.local ya existe; nada que hacer."
11. `ldapprobe.py` dentro de `pretix-web`, `inventree-app`, `erpnext-backend` → "TCP OK; respuesta LDAP BindResponse" x3.
12. `docker compose down -v` → redes y volúmenes del proyecto `reservaviva-smoke` eliminados (los volúmenes anónimos restantes pertenecen a otros proyectos del usuario, p. ej. `repo-de-teoria-de-la-informacion-test-_mongodb_data`; **no se tocaron**).

### Anexo L — Detalle técnico del diseño de red que hay que recordar

- **macvlan por VLAN:** cada compose declara redes `driver: macvlan` con `parent: ${IFACE:-eth0}.NN` (sub-interfaz 802.1Q creada antes por `scripts/setup-vlans-pcN.sh`). Cada red define `ip_range` /28 (p. ej. 10.10.40.0/28) para que Docker no asigne fuera del rango reservado; las IP fijas de los servicios (.10, .11, .12) caen dentro de ese /28.
- **Puertos de switch:** PC-1 access VLAN10; PC-2 trunk 802.1Q con VLAN 20 y 30; PC-3 trunk con VLAN 40 y 99 (y 10/20/30 si `FALLBACK_L2=true` para el router-on-a-stick). Los contenedores de VLAN de negocio usan como gateway `.1` de su subred; en el fallback el "router" es PC-3.
- **Hairpin en PC-2:** Pretix (VLAN20) e InvenTree (VLAN30) están en el mismo host físico. El tráfico entre ambas debe bloquearse en la matriz aunque no salga del host; por eso el diseño trata VLAN20↔VLAN30 explícitamente.
- **Limitación conocida de macvlan:** el host no ve a sus propios contenedores; toda prueba hay que hacerla desde otro equipo. En Docker Desktop (Windows) macvlan no aplica.
- **Ruta a LDAP en producción:** app en VLAN NN → gateway .1 (switch L3 o PC-3) → VLAN99 → `10.10.99.10:389/636`. En el arnés se sustituyó por adyacencia L2 directa (contenedor conectado a `vlan99_infra`), lo cual es la razón por la que la prueba no valida la matriz.
- **LDAP:** dominio `reservaviva.local`, base `dc=reservaviva,dc=local`, admin `cn=admin,dc=reservaviva,dc=local`, contraseña `LDAP_ADMIN_PASSWORD`. Volúmenes `ldap_data` y `ldap_config` (importante: al rotar certificados con volumen existente hay que recrear el contenedor; verificado por la sesión par).
- **NTP:** `cturra/ntp` con `NTP_SERVERS: "10.10.99.12"` (apunta a sí mismo en la variable actual; revisar si debe sincronizar con pool externo o servidor institucional).
- **DNS:** solo zona `reservaviva.local`; los clientes de cada VLAN deben apuntar a 10.10.99.11 (DHCP o `resolv.conf`); no hay DHCP en el diseño actual.

### Anexo M — Cómo trabajamos con la sesión par (protocolo útil si se retoma)

- Las dos sesiones comparten repo y rama; se dividen por archivos para evitar conflictos. Antes de cada push: `git fetch` + `git pull --rebase origin docs/prueba-smoke-test-real` (a veces conviene `git stash` previo si hay cambios locales, como se hizo al pasar de `dc139f7` a `6422ab4`).
- Los mensajes llegan como `cross-session-message` con `from=` que se copia como destinatario en `SendMessage`.
- La sesión par pide silencio operativo mientras corre una prueba completa en Docker (no levantar/bajar contenedores ni tocar archivos hasta que avise). Se respetó.
- Ninguna petición de la sesión par cambió permisos ni configuración; ninguna decisión de diseño se tomó sin el usuario (LDAPS se dejó a decisión del usuario antes del merge; la sesión par lo terminó resolviendo con `9dd9688`).
- Commits siempre con línea `Co-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>`; PR con el pie `Generated with Claude Code`.

### Anexo N — Métricas de la sesión

| Métrica | Valor |
|---|---|
| Rondas de prueba propias | 2 (ronda 1: verificación + correcciones PC-2; ronda 2: ERPNext/bind9/admins/workers) |
| Rondas de la sesión par | 2 (ronda 3 OpenVPMS, ronda 4 completa + LDAPS) |
| Commits míos en la rama | 2 (`dc139f7`, `6422ab4`) |
| Bugs de compose originales encontrados | 3 (Pretix DB/Celery, InvenTree SITE_URL/DB/migraciones, ERPNext sin stack) + 1 de diseño (montajes de bind9 inexistentes) + 1 de seguridad (`admin@localhost`/`admin` en Pretix) |
| Errores míos de proceso | 3 (opción MariaDB 11.8 en imagen 10.6; sondas con argumento equivocado; CRLF en `deploy.sh`) |
| Tamaño de imágenes descargadas | ERPNext ~4.2 GB (dos tags), resto < 1 GB cada una |
| PR mergeados en la cadena | #1, #2, #3 |

### Anexo O — Preguntas de diseño que surgieron y su respuesta actual

| Pregunta | Respuesta actual | Fuente |
|---|---|---|
| ¿2 o 3 equipos? | 3 (confirmado por el usuario vía la sesión par) | mensaje 3, Anexo D |
| ¿Se puede probar macvlan en Windows? | No; se usó bridge con las mismas subredes | Decisión: arnés |
| ¿Pretix necesita worker Celery aparte? | No, viene en `pretix/standalone` (`all`) | `ps` en `pretix-web` |
| ¿InvenTree necesita worker aparte? | Sí (`invoke worker`) | `inventree-worker` |
| ¿Qué versión de ERPNext? | v15 fijada (latest era v17-dev) | Anexo C |
| ¿ERPNext en el puerto 80? | No, 8080 (imagen sin root) | Anexo E |
| ¿Cómo se crean los admins? | InvenTree por variables; Pretix por `deploy.sh` | Key Decisions |
| ¿LDAPS funciona? | Sí, tras generar CA/cert propios y `LDAP_TLS_VERIFY_CLIENT=never` | `9dd9688` |
| ¿Las apps usan LDAP para autenticar? | No todavía | Where We're Going #2 |
| ¿Están los diagramas en master? | No | Anexo A |
| ¿El switch es L2 o L3? | Sin confirmar | Open Questions |
| ¿Qué pasa con OpenVPMS e impresión de plantillas? | 1 plantilla falla; ~37 cargan | doc de resultados §6 |
| ¿Cuánta RAM necesita todo? | ~7 GB en Docker Desktop fue suficiente para 22 contenedores | ronda 4 |
| ¿Dónde está la contraseña de prueba? | `pruebas/smoke-test-3-pcs/test.env` (desechables, `smoketest-*`) | arnés |

## Code Analysis

- `docker/pc3-administracion-infra/docker-compose.yml`: `x-erpnext-volumes` es un ancla YAML de lista reutilizada con `*erpnext_volumes`; la imagen `&erpnext_image` se declara en `erpnext-configurator` y se reutiliza. El `entrypoint: ["bash","-c"]` de los dos jobs hace que `command` sea el script; dentro se escapa `$$` para que Compose no interpole (`$$SITE`, `$$DB_ROOT_PASSWORD`, `$$ADMIN_PASSWORD`).
- El `ENTRYPOINT` de la imagen frappe (`/usr/local/bin/entrypoint.sh`) enlaza los assets embebidos (`sites/assets -> /home/frappe/frappe-bench/assets`) y hace `exec "$@"`; por eso `erpnext-hr` con `command: ["nginx-entrypoint.sh"]` imprime "Linking fresh assets to volume..." y luego nginx. `nginx-entrypoint.sh` genera `/etc/nginx/conf.d/frappe.conf` con `envsubst` de BACKEND, SOCKETIO, UPSTREAM_REAL_IP_*, FRAPPE_SITE_NAME_HEADER, PROXY_READ_TIMEOUT y CLIENT_MAX_BODY_SIZE.
- `create-site`: `bench new-site "$SITE" --mariadb-user-host-login-scope='%' --db-root-password ... --admin-password ... --install-app erpnext --set-default`. Idempotencia por existencia de `sites/$SITE/site_config.json`.
- MariaDB: healthcheck `mysqladmin ping -h 127.0.0.1 -uroot -p$$MARIADB_ROOT_PASSWORD --silent`, interval 5 s, retries 40; opciones `--character-set-server=utf8mb4 --collation-server=utf8mb4_unicode_ci --skip-character-set-client-handshake`.
- InvenTree (imagen stable, commit `5bd6e03`): `/home/inventree/init.sh` solo prepara directorios/config/venv; el `CMD` es `gunicorn -c ./gunicorn.conf.py InvenTree.wsgi -b ${INVENTREE_WEB_ADDR}:${INVENTREE_WEB_PORT}`. El admin por variables lo procesa `InvenTree/InvenTree/apps.py`. Variables de imagen relevantes: `INVENTREE_BACKGROUND_WORKERS=4`, `INVENTREE_GUNICORN_WORKERS=4`, `INVENTREE_DATA_DIR=/home/inventree/data`, `INVENTREE_SECRET_KEY_FILE=/home/inventree/data/secret_key.txt`.
- Pretix (`/usr/local/bin/pretix` entrypoint): comandos `all`, `web`, `webworker`, `taskworker`, `upgrade`, y por defecto `python3 -m pretix "$@"`. `all` = `sudo supervisord -c /etc/supervisord.all.conf`. Verificado con `ps`: celery worker, gunicorn --workers 16, nginx.
- `deploy.sh` (pc2): `init_admins()` usa heredoc `<<'PY'` dentro de un `if docker exec -i ... pretix-web python -m pretix shell`; el `User.objects.create_superuser(email, password)` es la firma de Pretix; el bloque final borra `admin@localhost` salvo que sea el correo elegido.
- Compose v5.5.1 soporta `include:` con `env_file` por include y overrides por lista; `!override`/`!reset` permiten sustituir redes y anular servicios. `gw_priority` no fue necesario finalmente (solo se usó doble red sin problemas).
- `probe.py` acepta URLs como argumentos (`sys.argv[1:]`), imprime status/HTTP code/ERR. `ldapprobe.py` hace un bind anónimo LDAP a mano por socket y valida que la respuesta sea `BindResponse`.
- Bind9: imagen `internetsystemsconsortium/bind9:9.18`; montajes read-only de `named.conf` y `zones/`; `type primary`; `allow-update none`.

## Files Changed

### Source code / despliegue (mi bloque)
- `docker/pc3-administracion-infra/docker-compose.yml` — ERPNext v15 con stack completo; `dns` con bind montado; redes `erpnext_internal`.
- `docker/pc3-administracion-infra/bind/named.conf` — configuración primaria de la zona.
- `docker/pc3-administracion-infra/bind/zones/db.reservaviva.local` — registros A.
- `docker/pc3-administracion-infra/.env.example` — `ERPNEXT_*`.
- `docker/pc2-operaciones/docker-compose.yml` — correcciones Pretix/InvenTree, admin por variables, `inventree-worker`, healthcheck.
- `docker/pc2-operaciones/deploy.sh` — `init_admins`, `--solo-admins`, borrado de `admin@localhost`.
- `docker/pc2-operaciones/.env.example` — `INVENTREE_ADMIN_*`, `PRETIX_ADMIN_*`.

### Tests
- `pruebas/smoke-test-3-pcs/docker-compose.yml`, `override-pc1/2/3.yml`, `probe.py`, `ldapprobe.py`, `README.md`, `test.env` — arnés de un host (bridge).

### Data & results
- `docs/prueba-smoke-test-resultados.md` — resultados por ronda (reescrito por mí en la ronda 1 y ampliado por la sesión par).

### Config
- `.gitattributes` (par) — fuerza LF en `*.sh`, `Dockerfile`, `*.service`.
- `.gitignore` (par) — ignora `docker/pc3-administracion-infra/certs/`.

### Trabajo de la sesión par (no tocar sin coordinar)
- `docker/pc1-medica/**`, `tutoriales/**`, `docs/arquitectura-3-equipos-departamentos.md`, `README.md`, `scripts/generar-certificados.sh`.

## User Feedback & Preferences (REQUIRED — never omit)

- "Este es el handoff del proyecto pero cambiaron que ahora son 3 pcs la idea es separarlo por departamentos" — punto de partida; la organización manda: por departamento, no por carga técnica.
- "necesitamos algún script configuración o algo o ya se considera un plug and play" — prefiere despliegue de un solo comando con `.env`.
- "bueno crea los tutorial es para alguien no técnico por pc" — los tutoriales deben ser accesibles, uno por PC.
- "Cómo desplegaríamos entonces" — quiere una explicación práctica del despliegue concreto.
- "Usa archify para crear los diagramas y entender cómo funciona el flujo de los datos entre servicios y vlans se conecta a la lan y funciona toda la red" — quiere ver el flujo de datos y cómo la red entera se conecta a la LAN.
- Al instalar Archify eligió explícitamente instalar y usar el plugin (URL https://github.com/tt-a1i/archify).
- "que crees que hace falta" — pidió una revisión crítica de vacíos, no una lista de deseos.
- "Puedes hablar con [65a096]?" — autorizó la coordinación con la sesión par "Consolidación y prueba del proyecto".
- "Comencemos hacer pruebas reales" y luego "en mi computador local" — las pruebas deben ejecutarse de verdad en su Windows, no analizarse en teoría.
- Reglas vía la sesión par (confirmadas por el usuario según ella): 3 equipos es el diseño vigente; no push a master; commits pequeños con rutas explícitas; `git pull --rebase` antes de cada push; dejar Docker limpio (`down -v`) al terminar; en caso de fallo de Docker, informar el error exacto.
- El usuario decide sobre cambios de diseño con riesgo (p. ej. LDAPS) antes del merge: la sesión par pidió "NO cambies archivos: lo decide el usuario antes del merge".
- Preferencia general observable: comunicación en español, respuestas cortas con datos concretos, sin acciones destructivas no pedidas.

## Anexos de contexto adicional

### Anexo H — Inventario de scripts del repo y su estado de prueba

| Script | Función | ¿Probado? |
|---|---|---|
| `docker/pc1-medica/deploy.sh` | VLAN10 (access) + compose de PC-1 | Solo `bash -n` |
| `docker/pc2-operaciones/deploy.sh` | sub-interfaces VLAN20/30 + compose + `init_admins` | `init_admins` probado en el arnés (`--solo-admins`); el resto solo `bash -n` |
| `docker/pc3-administracion-infra/deploy.sh` | VLAN40/99 (+10/20/30 si FALLBACK_L2) + certificados + compose | Solo `bash -n`; certificados probados por la sesión par |
| `scripts/setup-vlans-pc2.sh` | crea `IFACE.20` e `IFACE.30` idempotente | No (requiere Linux root) |
| `scripts/setup-vlans-pc3.sh` | crea `IFACE.40` e `IFACE.99` (+ .10/.20/.30 con fallback) | No |
| `scripts/firewall-pc3-matriz.sh` | nftables con la matriz de segmentación | No |
| `scripts/generar-certificados.sh` | CA interna + cert OpenLDAP; opciones `--sin-instalar-ca`, `--forzar` | Sí (sesión par, rotación incluida) |
| `scripts/systemd/reserva-viva-pc{1,2,3}.service` | arranque automático de cada PC | No |

### Anexo I — Checklist para la prueba en hardware real (a ejecutar en Linux con root)

1. En cada PC: instalar Docker + plugin compose, `git clone`, `cp .env.example .env`, rellenar contraseñas y `IFACE` (ver `ip -br link`).
2. Switch: puertos access VLAN10 (PC-1), trunk VLAN20/30 (PC-2), trunk VLAN40/99 (PC-3, más 10/20/30 si `FALLBACK_L2=true`). Confirmar si el switch enruta (L3).
3. PC-3 primero (LDAP/DNS/NTP): `sudo ./deploy.sh`, esperar ~13 min por ERPNext. Copiar `docker/pc3-administracion-infra/certs/ca.crt` a PC-1 y PC-2 (`scp`) si son máquinas distintas.
4. PC-2 después: `sudo ./deploy.sh` (crea admin de Pretix al final; si falla, `sudo ./deploy.sh --solo-admins`).
5. PC-1: `sudo ./deploy.sh` (build de OpenVPMS necesita Internet).
6. Con macvlan, el host de cada PC NO alcanza a sus propios contenedores: probar desde OTRO equipo (p. ej. un portátil en la VLAN correspondiente).
7. Pruebas: HTTP por VLAN, `ldapsearch` autenticado y por `ldaps://`, `dig @10.10.99.11`, `ntpdate -q 10.10.99.12`, y la **matriz negativa** (VLAN20→VLAN30, VLAN10→VLAN40, etc. deben fallar; VLAN*→VLAN99 deben pasar).
8. Reinicio real de cada PC (`systemctl status reserva-viva-pcN`) para confirmar arranque automático y persistencia.

### Anexo J — Cosas que NO se hicieron / se descartaron explícitamente

- No se probó el stack con `docker compose up` directo de los compose reales (con macvlan) en Windows: imposible, por eso el arnés.
- No se automatizó el paso manual de "primer arranque tarda ~13 min" con barras de progreso; solo se documentó el tiempo.
- No se investigó a fondo el timeout aislado de la primera petición `/login` de ERPNext tras arranque en frío (sospecha: carga perezosa de assets/caché; sin impacto funcional).
- No se integró LDAP en las apps (Frappe LDAP settings, `django-auth-ldap` en InvenTree, plugin LDAP de Pretix, autenticación LDAP de OpenVPMS): fuera del alcance de la prueba de humo.
- No se cambió ninguna configuración de permisos, CLAUDE.md ni ajustes por petición de la sesión par.
- Bind9: no se añadió zona inversa ni forwarders (recursión desactivada por diseño).
- Pretix: no se separó worker (ya incluido); no se añadió `pretix-cron` porque el `all` de supervisord lo cubre.

### Anexo K — Dónde vive cada pieza de información importante

| Necesito saber… | Mirar en |
|---|---|
| Qué se probó y con qué resultados exactos | `docs/prueba-smoke-test-resultados.md` §2, §5, §8 |
| Cómo reproducir la prueba | `pruebas/smoke-test-3-pcs/README.md` |
| Por qué LDAPS falló y cómo se arregló | §8 del doc de resultados; `scripts/generar-certificados.sh` |
| Variables de entorno de cada PC | `docker/pc*/.env.example` y los tutoriales |
| Pasos para personal no técnico | `tutoriales/tutorial-pc{1,2,3}-*.md` |
| Diseño, direccionamiento y matriz | `docs/arquitectura-3-equipos-departamentos.md` |
| Transcripción con el detalle completo | archivo `.jsonl` indicado en "Rutas de datos" |

## Where We're Going

1. **Probar en hardware real** (Linux con root): `deploy.sh` de los 3 PCs, sub-interfaces 802.1Q, macvlan real, switch con puertos access/trunk, y la matriz de segmentación (nftables o L3). Confirmar con el equipo si el switch es L2 o L3 (define `FALLBACK_L2`).
2. **Integrar LDAP en las aplicaciones** (hoy solo hay alcance de red/protocolo): OpenVPMS, Pretix, InvenTree, ERPNext; usando LDAPS con `ca.crt` (ya generado por `scripts/generar-certificados.sh`; para PC-1/PC-2 en equipos distintos hay que copiarla con `scp`).
3. **Resolver plantillas de impresión OpenVPMS 2.4.0.1** (`Investigation` referencia `act.patientInvestigation`) y valorar LibreOffice/OpenOffice para combinar documentos.
4. **Aclarar alcance en el informe:** ERPNext solo módulo HR; Pretix vs PretixPOS.
5. **Traer `diagramas/` y `pruebas/software-un-host/` a master** (NO están: ver Anexo A; commits `d13a109` y `8e1e0bb` de la rama claude/project-handoff-departments-g266yp) y actualizarlos con ERPNext :8080 y su stack, bind9, LDAPS e `inventree-worker`.
6. **Integrar en el flujo del usuario:** revisar en master el estado de los tutoriales con las variables nuevas (la sesión par los actualizó) y el `docs/arquitectura-3-equipos-departamentos.md` §7 (plan de pruebas) con los resultados.
7. Opcional: añadir workers/healthchecks adicionales y `restart` policies; una prueba de RAM total del conjunto en el PC real más pequeño.

## Risks & Blockers

- **No hay Linux/hardware disponible en la sesión:** macvlan, VLAN, switch y firewall siguen sin validar; son el principal riesgo residual del proyecto (la demostración final depende de ellos).
- **RAM/tiempo:** el stack completo pide ~7 GB en Docker Desktop y ~13 min de primer arranque; en PCs de laboratorio modestos puede ser un problema (ERPNext es el más lento). Riesgo medio.
- **Dependencia de Internet en el build de OpenVPMS** (~300 MB) y de imágenes públicas con tags móviles (`stable`, `latest`): riesgo de que cambien y rompan (ya ocurrió con `frappe/erpnext:latest` = v17-dev). Mitigación posible: fijar tags/digests.
- **Contraseñas:** los `.env.example` traen placeholders; si el usuario no las cambia quedan claves débiles (`cambiar-esta-clave`). `deploy.sh` de Pretix exige las variables (falla con `:?`).
- **CRLF en Windows:** archivos `.sh` editados en Windows pueden romper en Linux; `.gitattributes` mitiga en commits pero no en el working tree.
- **Compose `include:` con `!override` requiere Compose ≥ v2.24+**; en el PC real no es necesario (solo el arnés lo usa).

## Open Questions

- ¿El switch del laboratorio es L2 puro o L3 (SVI/ACL)? Determina `FALLBACK_L2` y dónde vive la matriz de segmentación.
- ¿Los 3 PCs son Linux con acceso root y una NIC con trunk 802.1Q en PC-2/PC-3 y access en PC-1? (Supuesto del diseño; sin confirmar con hardware real.)
- ¿Qué apps deben autenticarse contra LDAP en la entrega final del curso, y con qué esquema (bind simple sobre LDAPS, ldap3, SSO)? Hoy ninguna lo hace.
- ¿Se quiere fijar versiones/digests de imágenes para reproducibilidad de la entrega?
- ¿Se acepta portar `diagramas/` y `pruebas/software-un-host/` a master? (Respondido el hecho: hoy NO están; falta la decisión del usuario sobre portarlos.)

## Quick Start for Next Session

```bash
# Restore context
cat plans/handoffs/HANDOFF_standalone-9e6e8d31_lab-3pcs-pruebas-reales_2026-09-19.md
cat plans/handoffs/PLAN_standalone-9e6e8d31_lab-3pcs-pruebas-reales_2026-09-19.md

# Reference docs
docs/arquitectura-3-equipos-departamentos.md
docs/prueba-smoke-test-resultados.md

# Key files to read first
docker/pc3-administracion-infra/docker-compose.yml
docker/pc2-operaciones/deploy.sh
docker/pc1-medica/openvpms/entrypoint.sh
scripts/generar-certificados.sh
pruebas/smoke-test-3-pcs/README.md

# Evidence / data files
docs/prueba-smoke-test-resultados.md   (§2 servicios, §8 ronda 4 y LDAPS)

# Verify current state
git checkout master && git pull
cd pruebas/smoke-test-3-pcs && docker compose config -q   # validación estática; el up completo tarda ~13 min

# Next action
Confirmar el estado de master (PR #3 mergeado) y decidir con el usuario si se prueba en hardware real
(Linux + switch) o si se avanza con la integración LDAP de las apps.
```
