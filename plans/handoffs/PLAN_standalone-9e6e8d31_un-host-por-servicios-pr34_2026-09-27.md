# Cerrar el PR #34 y la deuda que deja: decisiones del usuario, sonda de interfaz web en `verificar`, limpieza y pendientes de validación

**Date:** 2026-09-27
**Status:** PLANNED
**Bead(s):** none (`bd` no está instalado)
**Epic:** Proyecto final Redes Corporativas (UD, 678-302). Laboratorio "Reserva Viva"
**Chain:** `standalone-9e6e8d31` seq `7` (copiado del handoff emparejado)
**Context:** See `HANDOFF_standalone-9e6e8d31_un-host-por-servicios-pr34_2026-09-27.md` for session data, test results, and prior approaches.

---

## Problem Statement

La consolidación de un host está hecha y publicada en el PR #34, abierto y sin fusionar:
- un único `docker-compose.yml` y `servicios/`;
- H20, H21 y H22 corregidos;
- 4 documentos nuevos;
- `verificar` con 99 PASS / 0 FAIL / 13 INFO.

Quedan cuatro cosas:
1. **Seis decisiones del usuario sin responder** (Tabla 10 del handoff).
2. **Un hueco de verificación demostrado.** H22 (la interfaz de InvenTree nunca funcionó) pasó 7 pasadas de `verificar` en verde, porque ninguna sonda comprueba la interfaz web.
3. **Limpieza:** el `origin` apunta al nombre viejo del repo, hay 4 worktrees de agentes con sus ramas y 2 worktrees huérfanos.
4. **Pendientes de validación:** el RC=2 de `arrancar` desde Git Bash, los logins reales, H17 y el modo Docker Desktop.

Los datos están en las Tablas 3, 6, 10 y 11 y en los Anexos A y B del handoff.

## Key Findings

- **El usuario fusiona los PR por su cuenta** (lo hizo con #31, #32 y #33). El #34 puede estar ya en master. → Fase 0.
- **Las decisiones de la Tabla 10 cambian el alcance:** si el proxy de `/media` sí o no, qué hacer con la clave del LDIF, con los worktrees y con `0.0.0.0` → `127.0.0.1`. → Fases 0, 2 y 4.
- **`verificar` no ve la interfaz web.** `curl /web` = 200 es falso positivo en una SPA: el HTML llega y los JS son HTML (Tabla 6, Anexo A #22). → Fase 1.
- **Los logins reales no los puede hacer un agente.** El clasificador deniega leer las claves de `test.env` (Anexo A #21). → Fase 5, que produce una lista de comprobación para el usuario.
- **`arrancar` desde Git Bash dio RC=2 con 25/25 sanos,** y desde PowerShell RC=0. Si el RC miente, el plug-and-play miente. → Fase 3.
- **La memoria fijada exige delegar con encargos exhaustivos.** Las fases 1-3 tocan ficheros distintos y pueden ir en paralelo, salvo que la Fase 2 toque `docker-compose.yml` (lo hace si se aprueba `127.0.0.1`). → Reparto en la Fase 0.

## Anti-Goals (What NOT To Do)

- **No fusionar el PR #34 sin un "sí" explícito,** y no planear sobre la rama si ya está MERGED.
- **No leer ni mostrar claves de `sistema/test.env`** ni intentar sortear la denegación del clasificador. Los logins reales son del usuario.
- **No añadir el proxy de `/media` ni descargar imágenes** sin aprobación explícita. Tampoco hacer `borrar`, `down -v`, `wsl --shutdown` ni `docker pull`.
- **No cambiar** `name: reservaviva-smoke`, las claves de red, servicio y volumen, ni los `container_name`.
- **No dar por buena una prueba de interfaz web con `/web` = 200** (Anexo B). Ni `git add -A` (Anexo A #17).

## Plan

### Phase 0: Estado, decisiones y reparto

**Goal:** saber si el PR #34 sigue abierto y fijar las decisiones del usuario antes de tocar nada.

**Why this approach:** la Tabla 10 lleva una sesión sin respuesta, y dos de sus decisiones (el proxy y `0.0.0.0`) cambian la configuración y la documentación.

- `gh pr view 34 --json state,mergedAt,mergeCommit`.
  - Si está MERGED: `git fetch origin && git switch -c chore/post-un-host origin/master`.
  - Si sigue OPEN: trabajar en `docs/consolidacion-un-host`. Los commits nuevos entran en el mismo PR.
- `powershell -File .\levantar-sistema.ps1 estado`, con `timeout` 300000 o en segundo plano (Anexo A #24). Esperado: 22 Up + 3 `Exited (0)`.
- Un único AskUserQuestion con 4 preguntas, cada una con la recomendación de la Tabla 10 marcada "(Recomendado)":
  1. `/media` de InvenTree: dejarlo documentado, o proxy (contenedor 26.º y descarga).
  2. `PUBLISH_IP`/`DNS_BIND_IP` por defecto: pasar a `127.0.0.1` o dejar `0.0.0.0`.
  3. La clave del comentario de `servicios/openldap/10-estructura.ldif`: dejarla o quitarla.
  4. Worktrees huérfanos, en multiselección: borrar `ProyectoFinak-ldap`; borrar `ProyectoFinak-off` (advirtiendo que `scripts/preparar-imagenes-offline.sh` no está en git).

  Si el PR sigue abierto, añadir "¿Fusiono el #34 al terminar?".
- `ListAgents` para ver si hay peers de ESTE repo. Si no los hay, repartir con la herramienta Agent (memoria fijada). Propiedad de ficheros:
  - la Fase 1 es dueña de `sistema/verificar_arquitectura.{py,md}`;
  - la Fase 2, de `docker-compose.yml`, `.gitignore`, el LDIF y el `git remote`;
  - la Fase 3, de `levantar-sistema.{sh,ps1}`.
  - Si se aprueba `127.0.0.1`, las Fases 2 y 3 no pueden ir a la vez con `arrancar`: van en serie.

**Files:** ninguno (solo memoria si una decisión es durable).
**Validates with:** respuestas registradas; `estado` 22 + 3.
**Rollback:** n/a.

### Phase 1: Sonda de interfaz web en `verificar` (cierra el hueco que dejó pasar H22)

**Goal:** que `verificar` falle si la interfaz web de cualquiera de las 4 apps no puede cargar sus assets.

**Why this approach:** H22 pasó 7 pasadas en verde. Comprobar un asset referenciado por el HTML y su `content-type` es lo que lo habría detectado (Tabla 6).

- En `sistema/verificar_arquitectura.py`, un bloque nuevo `bloque_web` (tras `bloque_ldap` o donde encaje con el RESUMEN) que, por cada app, pida la página de entrada desde el host a `localhost:<puerto>` (los puertos salen de `test.env`, como hace el resto del guion):
  - InvenTree: `/web/login`.
  - Pretix: `/control/login`.
  - OpenVPMS: `/openvpms/login`.
  - ERPNext: `/login`.
- Del HTML, extraer 1-2 URL de `<script src>` o `<link rel=stylesheet|modulepreload href>` con un regex simple, pedirlas, y exigir 200 con un `content-type` que NO sea `text/html` (`javascript` o `css`). Así sí se detecta la redirección 302 → `/web`.
- Pretix: además, que el HTML contenga `csrfmiddlewaretoken`. **No** usar `127.0.0.1`: da 400 (Anexo A #26).
- Añadir un caso al `--autotest` (~línea 568) con HTML simulado cuyo asset devuelve `text/html`: debe dar FAIL. Así se prueba el "rojo" sin romper el sistema real.
- Documentar el bloque en `sistema/verificar_arquitectura.md` ("Qué comprueba") y en `docs/operacion.md` §8 si cita los bloques.
- Las cifras nuevas van SOLO a `docs/resultados-un-host.md`. Esperado: 99 + N PASS, donde N es el número de comprobaciones nuevas (unas 8-12).

**Files:** `sistema/verificar_arquitectura.py`, `sistema/verificar_arquitectura.md`, `docs/resultados-un-host.md` (y `docs/operacion.md` si aplica).
**Validates with:**
- `python sistema/verificar_arquitectura.py --autotest`: el caso nuevo da FAIL donde debe y el resto no cambia.
- `levantar-sistema.ps1 verificar --rapido` y luego el completo: **≥ 99 PASS, 0 FAIL, 13 INFO, RC=0**, con las 4 apps en PASS en el bloque web.
**Rollback:** `git revert` del commit (solo toca el guion de verificación).

### Phase 2: Limpieza y decisiones de configuración

**Goal:** aplicar las decisiones de la Fase 0 y dejar el repo sin restos operativos de la sesión anterior.

**Why this approach:** son tareas pequeñas e independientes. Solo `127.0.0.1` cambia la configuración y necesita diff y `arrancar`.

- `git remote set-url origin https://github.com/J4F3ET/UD.RedesCorporativa.ProyectoFinal.git` y `git fetch origin`. Comprobar que `git status -sb` sigue en seguimiento.
- Worktrees de agentes: para cada uno de `.claude/worktrees/agent-{a1782ec5174f89d9e,ac82ea4d0bf8fd6a7,af479db2a17bdaadc,afc28bc3fbb9c2cdd}`:
  - `git -C <ruta> status --porcelain`;
  - si está limpio, `git worktree unlock <ruta>` (aparecen como `locked`) y `git worktree remove <ruta>`;
  - después, `git branch -d worktree-agent-<id>`. Todo su contenido ya está integrado; si `-d` se niega, **no** usar `-D` sin preguntar.
  - Nunca `--force`.
- Worktrees huérfanos: los que el usuario haya elegido, con el mismo procedimiento y **sin** `--force`. Si falla por ficheros sin versionar, preguntar.
- Si se aprobó `127.0.0.1`:
  - en `docker-compose.yml`, las 9 entradas `${PUBLISH_IP:-0.0.0.0}` / `${DNS_BIND_IP:-0.0.0.0}` pasan a `:-127.0.0.1`;
  - el `config` con `test.env` debe salir **idéntico**, porque `test.env` ya fija 127.0.0.1;
  - probar también sin la variable: `PUBLISH_IP= docker compose … config | grep published` o similar;
  - actualizar `docs/arquitectura.md` §7 y `docs/seguridad.md` §5.
- Si se aprobó quitar la clave del LDIF: quitar la clave del comentario de `servicios/openldap/10-estructura.ldif`, sin tocar las entradas, y dejar en su lugar "clave en `servicios/openldap/README.md`". El LDIF solo se carga con `ldap_data` vacío, así que no afecta al sistema vivo. Actualizar `docs/seguridad.md` §3.
- Commits separados: remoto y worktrees no generan commit; un commit para `127.0.0.1` y otro para el LDIF.

**Files:** `docker-compose.yml` (condicional), `servicios/openldap/10-estructura.ldif` (condicional), `docs/arquitectura.md`, `docs/seguridad.md`.
**Validates with:**
- `git worktree list` según la decisión y `git branch --list 'worktree-agent-*'` vacío.
- Si hubo `127.0.0.1`: `config` con `test.env` idéntico al anterior; `arrancar` RC=0 25/25; `verificar --rapido` en verde.
**Rollback:** `git revert` de cada commit. Los worktrees borrados no se recuperan, pero sus ramas se conservan si `-d` se negó.

### Phase 3: El RC=2 de `arrancar` desde Git Bash

**Goal:** que el código de salida de `levantar-sistema.sh` sea fiable: 0 si y solo si el sistema queda 25/25.

**Why this approach:** el plug-and-play depende de él (el `.ps1` y el usuario lo leen), y hoy un RC=2 convive con "Sistema en marcha" (Anexo A #25).

- Reproducir sin cambiar nada: con el sistema arriba, `bash ./levantar-sistema.sh arrancar; echo "RC=$?"` desde Git Bash (modo Docker Desktop si se detecta; si no, a través de `wsl.exe`), y comparar con `powershell -File .\levantar-sistema.ps1 arrancar; $LASTEXITCODE`.
- Si no se reproduce, anotar "no reproducible" en `resultados-un-host.md` y cerrar la fase.
- Si se reproduce:
  - `bash -x` o `set -o errtrace` con `trap 'echo "ERR $LINENO $BASH_COMMAND" >&2' ERR` en una copia en el scratchpad (no en el repo) para localizar el comando que devuelve 2 bajo `set -euo pipefail`;
  - candidatos: un `grep` sin coincidencias en un pipeline, `cmp`, `docker compose … ps` o `wait`.
- Arreglo mínimo en `levantar-sistema.sh` (ASCII y LF). Después, `bash -n` y dos `arrancar` seguidos con RC=0.

**Files:** `levantar-sistema.sh` (si hay arreglo), `docs/resultados-un-host.md`.
**Validates with:** RC=0 en Git Bash y en PowerShell con el sistema arriba, y RC≠0 si se fuerza un fallo (p. ej. `--timeout 1` con un servicio recreado).
**Rollback:** `git revert`.

### Phase 4 (CONDICIONAL: solo si la Fase 0 aprobó el proxy de `/media` y la descarga): proxy delante de InvenTree

**Goal:** servir `/static` y `/media` como el despliegue oficial, con `/media` autenticado.

**Why this approach:** es la única opción que arregla `/media` (Tabla 7 del handoff). Sigue necesitando el `invoke static` de H22.

- Pedir permiso de descarga indicando la imagen exacta (p. ej. `caddy:2-alpine`, fijada por digest tras descargarla) y su tamaño.
- El servicio nuevo `inventree-proxy` va en vlan30 con una IP fija libre (comprobar en `docs/arquitectura.md`; el diagnóstico sugirió .13). Monta `inventree_data` en solo lectura y usa un Caddyfile en `servicios/inventree/Caddyfile`, calcado del oficial de InvenTree 1.5.5 con `forward_auth` a `/auth/` para `/media`.
- El `ports` 18083 pasa de `inventree-app` al proxy. `INVENTREE_SITE_URL` no cambia.
- Revisar en `verificar_arquitectura.py` los conteos de contenedores e IP y las sondas de vlan30. La sonda web de la Fase 1 debe seguir en PASS.
- Actualizar `docs/arquitectura.md` (26 servicios, diagrama y tablas), `docs/aplicaciones.md`, `docs/operacion.md` y `servicios/inventree/README.md`. Quitar el pendiente de `/media` en resultados.

**Files:** `docker-compose.yml`, `servicios/inventree/Caddyfile` (nuevo), `sistema/verificar_arquitectura.py`, docs.
**Validates with:** `config` diff (solo el servicio nuevo y el `ports`); `arrancar` 26/26; `verificar` completo 0 FAIL; subir una imagen de prueba en InvenTree lo hace el usuario.
**Rollback:** `git revert` y `arrancar`. El volumen `inventree_data` no cambia.

### Phase 5: Deuda de validación y cierre

**Goal:** dejar documentado qué está probado por quién, y master al día.

- Añadir a `docs/operacion.md` una **lista de comprobación del usuario**, sin claves, que solo diga en qué variable de `test.env` está cada una:
  - login real en las 4 apps;
  - `rrhh.prueba` por LDAP en ERPNext (botón LDAP);
  - `logistica.prueba` y `taquilla.prueba` en InvenTree;
  - subir una imagen en InvenTree (si se hizo la Fase 4).
- H17 (frío con volúmenes vacíos): **solo** con permiso explícito para `borrar`. Si no hay permiso, queda en pendientes.
- `docs/resultados-un-host.md`:
  - pasadas nuevas;
  - resultado de la Fase 3;
  - pendientes al día: quitar lo resuelto y añadir que "ninguna app es cliente de `ntp-interno`" como limitación documentada (lo descubrió el agente de arquitectura; ya lo dice `arquitectura.md`).
- Push. Si el PR #34 sigue abierto, los commits entran en él: actualizar su descripción con `gh pr edit 34 --body-file`. Si ya se fusionó, abrir un PR nuevo listo para revisión (no borrador). En ambos casos, `gh pr view` antes de fusionar.

**Validates with:** `verificar` final ≥ 99 PASS / 0 FAIL, todos los enlaces resolviendo (bucle `grep -oE '\]\([^)#]+'` + `test -e`) y el PR abierto o fusionado según el usuario.
**Rollback:** n/a.

## Dependencies & Order

- La Fase 0 bloquea todo: sus respuestas deciden si existe la Fase 4 y el alcance de la 2.
- Las Fases 1, 2 y 3 son independientes por ficheros y pueden ir en paralelo con agentes, **salvo** que se ejecuten `arrancar` o `verificar` a la vez. El sistema vivo es uno solo: serializar las pruebas que levantan contenedores (un solo dueño del sistema vivo en cada momento).
- La Fase 4 va después de la 1, porque la sonda web valida el proxy, y después del `127.0.0.1` de la 2 si se aprobó, porque ambas tocan `ports`.
- La Fase 5 va al final.

## Risks & Mitigations

- **Falsos FAIL en la sonda web:** OpenVPMS y ERPNext pueden servir assets con rutas o `content-type` inesperados. Probabilidad media. Mitigación: mirar primero con `curl -sI` qué devuelve cada app y ajustar la expectativa por app, documentando cada elección.
- **Que el PR #34 se fusione a mitad de la sesión:** probable. Mitigación: `gh pr view` antes de cada push y rebase sobre `origin/master` si hace falta.
- **Que `127.0.0.1` rompa algún acceso desde fuera de WSL:** poco probable, porque `test.env` ya fija 127.0.0.1. Mitigación: el `config` con `test.env` debe salir idéntico.
- **Que el RC=2 no se reproduzca:** probable. Se documenta y se cierra; no se persigue indefinidamente.
- **Memoria del host:** `verificar` completo dura unos 14 min. Usar `--rapido` entre tandas.

## Success Criteria

- **Mínimo:**
  - Decisiones de la Tabla 10 registradas.
  - Sonda web en `verificar`, con el autotest en rojo para un asset HTML y el sistema real en verde: ≥ 99 PASS, 0 FAIL, 13 INFO, RC=0.
  - `origin` actualizado y 0 worktrees de agentes.
- **Completo:** lo anterior, más:
  - RC de `arrancar` fiable o documentado como no reproducible;
  - decisiones de configuración aplicadas con el `config` validado;
  - lista de comprobación del usuario en `operacion.md`;
  - resultados al día;
  - el PR fusionado o listo para revisión;
  - la Fase 4 hecha, si se aprobó.

## Quick Start

```bash
# Contexto completo
cat plans/handoffs/HANDOFF_standalone-9e6e8d31_un-host-por-servicios-pr34_2026-09-27.md

# Estado del PR y de la rama
gh pr view 34 --json state,mergedAt,mergeCommit
git fetch origin && git status -sb

# Ficheros clave de la Fase 1
sed -n 1,60p sistema/verificar_arquitectura.py        # AQUI, RAIZ, ZONA, helpers
grep -n "def bloque_\|autotest" sistema/verificar_arquitectura.py
sed -n '/^## Qué comprueba/,/^## /p' sistema/verificar_arquitectura.md

# Línea base
cat sistema/resultados/verificacion-20260926-224652.txt | tr -d '\000' | tail -5   # 99/0/13

# Estado del sistema
powershell -File .\levantar-sistema.ps1 estado     # 22 Up + 3 Exited(0); usar timeout 300000

# Primera acción concreta
# Fase 0: gh pr view 34 y después AskUserQuestion con la Tabla 10 del handoff.
```
