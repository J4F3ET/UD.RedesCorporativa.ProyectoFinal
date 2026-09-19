# Plan: cerrar la prueba de humo en un solo host y alinear la documentación del repo con el diseño vigente

**Date:** 2026-09-19
**Status:** PLANNED
**Bead(s):** none (`bd` no está instalado)
**Epic:** Proyecto final Redes Corporativas 678-302, Zoológico Reserva Viva
**Chain:** `standalone-cad62bb5` seq `1`
**Context:** See `HANDOFF_standalone-cad62bb5_smoke-test-consolidacion_2026-09-19.md` for session data, Docker failure evidence, and prior approaches.

---

## Problem Statement

El equipo necesita saber, antes de ir al laboratorio con el switch físico, qué servicios del stack (OpenVPMS, Pretix, InvenTree, ERPNext, OpenLDAP, DNS, NTP) arrancan con `docker compose up -d` sin pasos manuales y cuáles no. La prueba nunca se ejecutó en la sesión original porque Docker Desktop no arranca en la máquina del usuario (socket `sailor-ingest.sock` atascado). Un agente en la nube, hoy local tras `--teleport`, empezó una prueba en `pruebas/smoke-test-3-pcs/`, pero deja 3 archivos sin commitear y no ha entregado informe. Además, los documentos que subió la sesión original hablan de 2 equipos y de IPs 192.168.X, mientras el repo usa 3 equipos y 10.10.X. Ver Evidence & Data en el handoff.

## Key Findings

- Docker no responde: `backend.error.json` muestra que no puede renombrar `run\sailor-ingest.sock`; WSL2 funciona y la sesión no es administrador. → drives Phase 1.
- El análisis estático indica que LDAP y las bases de datos son cero-config, y que Pretix, InvenTree y ERPNext necesitan un paso manual. Está sin verificar. → drives Phase 2 y Phase 3.
- El agente de la nube ya tuvo que añadir variables de entorno a `docker/pc2-operaciones/docker-compose.yml` (BD, Redis, Celery, URL del sitio). Eso confirma que el compose original no era cero-config. → drives Phase 2.
- Faltan piezas en el repo: `docker/pc3-administracion-infra/bind/` (el DNS no puede arrancar) y `docker/pc1-medica/openvpms/` (no hay Dockerfile). → drives Phase 3.
- El repo dice 3 equipos desde `1d60ca8`; el usuario dijo "2 equipos". → drives Phase 0.
- `docs/prueba-smoke-test-resultados.md` referencia un archivo que no existe en el repo (`reserva-viva-test/`) y usa subredes 192.168. → drives Phase 4.
- El PR #2 ya está abierto y listo para revisión con 2 commits. → drives Phase 5.

## Anti-Goals (What NOT To Do)

- No intentar arreglar Docker Desktop otra vez con `Remove-Item` sobre `%LOCALAPPDATA%\Docker\run`. Ya falló con error del SO; el remedio real es reiniciar Windows.
- No presentar el análisis estático como resultado de prueba. Solo cuenta lo que se ejecutó y se vio.
- No sobrescribir `docs/arquitectura-3-equipos-departamentos.md` con contenido de 2 equipos. Los borradores viven en `docs/borradores/`.
- No hacer commit de los 3 archivos modificados ni de `ldapprobe.py` sin coordinar: son del agente de la nube.
- No hacer push a `master` ni `--force`. Todo cambio va por rama y PR.
- No volver a hacer menús de preguntas con `AskUserQuestion` cuando el usuario ya dio dirección; preguntar solo lo genuinamente abierto (2 vs 3 equipos).

## Plan

### Phase 0: Coordinar con el usuario y con el agente de la nube

**Goal:** Saber qué ya hizo el agente par y resolver si el laboratorio será de 2 o 3 equipos.

**Why this approach:** El repo y el usuario se contradicen, y hay trabajo vivo sin commitear. Editar sin coordinar arriesga pérdida de trabajo o documentos incoherentes.

- Ejecutar `git fetch origin && git status -sb` y revisar `gh pr view 2` para ver si el agente ya empujó commits o informe.
- Si el agente `ud-redescorporativaa-proyectofinak-80` respondió, leer su mensaje; no reenviar el encargo original (msg_id `e8afa1cd-de87-4738-80ce-8770527d9047`).
- Si no hay respuesta, enviar UN mensaje corto por `SendMessage` pidiendo estado, y suscribirse con `notify_when_idle: true` en vez de sondear con `ListAgents`.
- Preguntar al usuario, una sola vez y con texto simple: "¿El laboratorio real es de 2 o de 3 equipos? El repo ya dice 3."
- Registrar la respuesta en el README, sección "Estado actual".

**Files:** `README.md` (solo si el usuario decide volver a 2 equipos; en ese caso, avisar antes de tocar el diseño vigente).
**Validates with:** el usuario respondió y el agente par confirmó qué archivos son suyos.
**Rollback:** ninguno; fase de solo lectura y conversación.

### Phase 1: Recuperar Docker en la máquina

**Goal:** Que `docker info` funcione, o determinar que se necesita otra máquina.

**Why this approach:** Sin motor no hay prueba real. Las causas de virtualización ya están descartadas (WSL2 sano), así que el remedio es liberar el handle del socket.

- Pedir al usuario que cierre Docker Desktop y **reinicie Windows** (no puedo hacerlo yo; es una acción disruptiva).
- Tras reiniciar, abrir Docker Desktop y esperar a que `docker info` responda.
- Si sigue fallando: con Docker Desktop cerrado, borrar `%LOCALAPPDATA%\Docker\run\` (el usuario, no yo) y reintentar.
- Como último recurso, reinstalar Docker Desktop, o ejecutar la prueba en una máquina Linux/otra PC del equipo.
- Confirmar con `docker compose version` (esperado v5.5.1) y `docker run --rm hello-world`.

**Files:** ninguno.
**Validates with:** `docker info` sin error y `docker run --rm hello-world` imprime el mensaje de éxito.
**Rollback:** ninguno; no se modifica el repo.

### Phase 2: Ejecutar la prueba de humo real (3 PCs simulados en un host)

**Goal:** Obtener, con evidencia, la lista de servicios que arrancan solos y los que no.

**Why this approach:** Es exactamente el paso 2 de la sección 9 de `docs/arquitectura-3-equipos-departamentos.md`, y responde la pregunta original del usuario. El agente de la nube ya dejó `pruebas/smoke-test-3-pcs/` con `include:` y overrides bridge; reutilizarlo evita duplicar.

- Acordar con el agente par quién ejecuta (evitar dos `docker compose up` simultáneos sobre el mismo `name: reservaviva-smoke`).
- Pull inicial: `docker compose -f pruebas/smoke-test-3-pcs/docker-compose.yml --env-file pruebas/smoke-test-3-pcs/test.env pull`. Son varios GB; correrlo en segundo plano.
- `docker compose ... up -d` y luego `ps` para ver estado. Anotar cada servicio como running / restarting / exited con el motivo de los logs.
- Por servicio, correr `docker compose logs --tail 80 <servicio>` y guardar errores textuales.
- Probar HTTP con `python pruebas/smoke-test-3-pcs/probe.py <urls>` (Pretix en 10.10.20.10, InvenTree en 10.10.30.10:8000). Nota: en Docker Desktop de Windows las IPs de redes bridge no son alcanzables desde el host; probar dentro de un contenedor auxiliar de la misma red o publicar puertos.
- Probar LDAP con `ldapsearch -x -H ldap://10.10.99.10 -b dc=reservaviva,dc=local -D cn=admin,dc=reservaviva,dc=local -w smoketest-ldap` desde un contenedor auxiliar en `vlan99_infra`.
- Ejecutar los pasos manuales candidatos (superusuario de Pretix, `invoke` de InvenTree, site de ERPNext) y anotar el comando exacto que funcionó.

**Files:** `pruebas/smoke-test-3-pcs/*` (ajustes mínimos si la prueba lo exige); salida cruda a `pruebas/smoke-test-3-pcs/resultados/` (logs y tabla).
**Validates with:** tabla servicio → estado con al menos LDAP y las 3 bases de datos en `running`; para cada app, "arranca solo: sí/no" respaldado por un log.
**Rollback:** `docker compose ... down -v` limpia contenedores y volúmenes; no toca el repo.

### Phase 3: Cerrar los gaps que la prueba destape

**Goal:** Que cada PC tenga todo lo necesario para arrancar con `deploy.sh`.

**Why this approach:** La prueba ya mostró que el compose de PC-3 depende de archivos inexistentes y que ERPNext no se puede levantar sin site. Dejarlo así rompe el "plug-and-play" prometido.

- **DNS de PC-3:** crear `docker/pc3-administracion-infra/bind/named.conf` y `bind/zones/reservaviva.local.zone` con registros para `veterinaria`, `taquilla`, `logistica`, `rrhh`. Después quitar `dns: !reset null` de `override-pc3.yml`.
- **ERPNext:** decidir entre usar el compose oficial `frappe/frappe_docker` (con job create-site) o añadir un servicio de inicialización propio. Documentar por qué.
- **OpenVPMS:** decidir si se construye el Dockerfile (Tomcat + WAR + MySQL) o si se declara fuera del alcance de esta entrega; en ambos casos, dejarlo escrito.
- **Pretix e InvenTree:** consolidar en `docker/pc2-operaciones/docker-compose.yml` las variables que el agente de la nube descubrió, y añadir un script de primer arranque que cree el superusuario.
- **`.env.example`:** actualizar cada carpeta con las variables nuevas (contraseñas, URLs).
- Coordinar con el agente par para no editar el mismo archivo a la vez.

**Files:** `docker/pc3-administracion-infra/bind/*` (nuevos), `docker/pc3-administracion-infra/docker-compose.yml`, `docker/pc2-operaciones/docker-compose.yml`, `docker/pc1-medica/*`, `.env.example` de cada PC.
**Validates with:** `docker compose config --quiet` en cada carpeta; la prueba de la Phase 2 se repite y `dns` ya no requiere `!reset null`.
**Rollback:** `git checkout -- <archivo>` sobre el archivo tocado (tras confirmar con `git status` que no hay cambios ajenos).

### Phase 4: Alinear la documentación

**Goal:** Un solo relato coherente en el repo.

**Why this approach:** Hoy conviven 3 y 2 equipos, 10.10.X y 192.168.X, y un informe que describe un compose que no está en el repo.

- Reescribir `docs/prueba-smoke-test-resultados.md` con los resultados reales de la Phase 2: tabla de servicios, comandos manuales verificados, logs relevantes.
- Eliminar de ese documento las referencias a `reserva-viva-test/` y cambiar las subredes a 10.10.X.
- Añadir en `docs/arquitectura-3-equipos-departamentos.md` sección 9 un enlace al resultado y marcar el punto 2 como hecho.
- Actualizar los `tutoriales/` con los pasos manuales de primer arranque comprobados.
- Mantener `docs/borradores/arquitectura-2-equipos.md` con su nota histórica, salvo que el usuario elija 2 equipos.
- Actualizar la sección "Pendientes clave" del `README.md`.

**Files:** `docs/prueba-smoke-test-resultados.md`, `docs/arquitectura-3-equipos-departamentos.md`, `tutoriales/*.md`, `README.md`.
**Validates with:** `grep -rn "192.168\|reserva-viva-test" docs README.md tutoriales` no devuelve resultados fuera de `docs/borradores/`.
**Rollback:** `git revert` del commit de documentación.

### Phase 5: Cerrar el PR

**Goal:** Dejar el trabajo integrado en `master` con revisión.

**Why this approach:** El PR #2 ya existe y la política es trabajar por rama.

- Commitear (por separado y con mensajes claros) los cambios del agente de la nube, una vez que él confirme que están listos, y luego los míos.
- Empujar a `docs/prueba-smoke-test-real` y actualizar la descripción del PR con el resultado real.
- Pedir revisión a otro integrante del equipo antes de fusionar.
- Tras el merge, borrar la rama remota `docs/prueba-smoke-test-y-borrador-2-equipos`, que ya no es necesaria.

**Files:** el PR #2 y su descripción.
**Validates with:** `gh pr view 2 --json state,mergeStateStatus` con estado limpio y CI en verde si existe.
**Rollback:** cerrar el PR sin fusionar; `master` no cambia.

## Dependencies & Order

- Phase 0 va primero y es corta; define quién toca qué.
- Phase 1 bloquea a Phase 2 (sin Docker no hay ejecución).
- Phase 2 bloquea a Phase 3 (los gaps se conocen tras ejecutar) y a Phase 4 (los resultados alimentan los documentos).
- Phase 3 y Phase 4 se pueden paralelizar en worktrees distintos, siempre que no editen los mismos archivos.
- Phase 5 va al final.

## Risks & Mitigations

- **Docker sigue caído tras reiniciar** (probabilidad media: el handle atascado ya persistió entre sesiones desde el 16-ago). Mitigación: borrar `run\` con Docker cerrado; si no, ejecutar en otra máquina o pedirle al agente de la nube que lo intente en un entorno con Docker sano.
- **Dos agentes editando lo mismo** (probabilidad alta: ya hay 3 archivos sin commitear). Mitigación: Phase 0 fija responsables por archivo; usar `git worktree` para paralelizar.
- **ERPNext no arranca sin BD/Redis propios** (probabilidad media: el compose de PC-3 no los define en lo leído). Mitigación: revisar el archivo completo y, si falta, usar `frappe_docker`.
- **`frappe/erpnext:latest` cambia entre ejecuciones** (probabilidad baja-media). Mitigación: fijar una versión concreta y anotarla en los resultados.
- **Redes bridge en Docker Desktop no exponen IPs al host** (probabilidad alta en Windows). Mitigación: contenedor auxiliar en la red o `ports:`.
- **La prueba de un solo host no valida el switch** (certeza). Mitigación: dejar explícito en el informe que 802.1Q, `macvlan` y la matriz de segmentación se validan solo en el laboratorio.

## Success Criteria

- **Mínimo:** `docker info` funciona y hay una tabla real servicio → estado con evidencia de logs para LDAP, las bases de datos, Pretix, InvenTree y ERPNext.
- **Mínimo:** `docs/prueba-smoke-test-resultados.md` describe únicamente lo ejecutado.
- **Completo:** todos los servicios levantan con `deploy.sh` más, como máximo, un paso de primer arranque documentado por app.
- **Completo:** el DNS de PC-3 y la decisión sobre OpenVPMS están resueltos y descritos.
- **Completo:** el repo no tiene contradicciones entre 2 y 3 equipos ni entre 10.10.X y 192.168.X fuera de `docs/borradores/`.
- **Completo:** PR #2 fusionado a `master` tras revisión.

## Quick Start

```bash
# Restore full context
cat plans/handoffs/HANDOFF_standalone-cad62bb5_smoke-test-consolidacion_2026-09-19.md

# Key source files for Phase 0-2
#   pruebas/smoke-test-3-pcs/docker-compose.yml
#   pruebas/smoke-test-3-pcs/override-pc2.yml
#   docker/pc2-operaciones/docker-compose.yml
#   docker/pc3-administracion-infra/docker-compose.yml
#   docs/arquitectura-3-equipos-departamentos.md

# Baseline data
#   %LOCALAPPDATA%\Docker\backend.error.json
#   docs/prueba-smoke-test-resultados.md (análisis estático, por reemplazar)

# Verify starting state
git fetch origin && git status -sb && gh pr view 2 --json state,isDraft
docker info

# First concrete action
git fetch origin && git log --oneline origin/docs/prueba-smoke-test-real -5
```
