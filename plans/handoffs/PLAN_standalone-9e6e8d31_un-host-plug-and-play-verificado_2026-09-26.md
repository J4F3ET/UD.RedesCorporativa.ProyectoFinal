# Refactor "un solo host": quitar del repositorio todo lo que solo servía al despliegue en 3 PCs, sin romper el arranque verificado

**Date:** 2026-09-26
**Status:** PLANNED
**Bead(s):** none (`bd` no está instalado)
**Epic:** Proyecto final Redes Corporativas (UD, 678-302). Laboratorio "Reserva Viva"
**Chain:** `standalone-9e6e8d31` seq `5` (copiado del handoff emparejado)
**Context:** See `HANDOFF_standalone-9e6e8d31_un-host-plug-and-play-verificado_2026-09-26.md` for session data, test results, and prior approaches.

---

## Problem Statement

La arquitectura completa (25 servicios) ya arranca en un solo equipo con un script plug and play (`levantar-sistema.{sh,ps1,cmd}`): 25/25 sanos en 15 min 45 s y una verificación de arquitectura con 192 PASS. Aun así, el repositorio sigue organizado para un despliegue en 3 PCs. Hay 110 ficheros versionados, con deploys por PC, tutoriales por PC, servicios systemd por PC, dos recetas de switch (L2/L3), un paquete offline con perfiles por PC y guías de Windows para 3 equipos. El arnés que de verdad se usa todavía se llama `pruebas/smoke-test-3-pcs`.

El usuario decidió consolidar en un host y **eliminar lo de 3 PCs**, porque *"el proyecto es muy extenso con 3 host"* y quiere minimizar la curva de aprendizaje. Lo borrado se puede recuperar desde git. El riesgo es borrar material de **diseño de red** que la Entrega 1 promete y que puede ser evaluable, o romper el arranque que acaba de validarse. Los datos están en "Evidence & Data" del handoff (Tablas 2, 3 y 6).

## Key Findings

- La base funciona y tiene una prueba de regresión objetiva: `levantar-sistema verificar` da **192 PASS / 28 INFO** (Tabla 6). Cada tanda del refactor debe mantener esa cifra. → Fases 1, 3 y 4.
- El arnés de un host **reutiliza** los 3 `docker/pc*/docker-compose.yml` mediante `include:` + `override-pcN.yml` (macvlan pasa a bridge). Esos compose **no son** material de 3 PCs: son la definición de los servicios. Lo que sobra son sus `deploy.*` y `.env.example`. → Fase 1 (qué borrar) y Fase 3 (reestructurar).
- Hay un grupo A de ficheros que solo sirven al despliegue en 3 PCs y que nadie discute (lista en "Where We're Going" del handoff). → Fase 1.
- Los grupos B (diseño de red: switch, VLANs, simuladores, diagramas, `docs/arquitectura-3-equipos…`), C (paquete offline) y D (historial) son **ambiguos**. La memoria `proyecto-consolidado-en-un-host` exige preguntar antes de borrarlos. → Fase 1 (pregunta) y Fase 2.
- `verificar_arquitectura.py`, `ldaplogin.py`, `probe.py` y `levantar-sistema.sh` dependen de la ruta `pruebas/smoke-test-3-pcs/`, de los nombres de red (`vlan10_medica`…), del proyecto `reservaviva-smoke` y de la zona en `docker/pc3-administracion-infra/bind/zones/`. Cualquier renombrado debe actualizarlos todos. → Fase 3.
- La memoria del host es justa: ~5,7 GB para el sistema, y Windows pagina con las aplicaciones habituales abiertas (Tabla 5). Cada `arrancar`/`verificar` cuesta de 15 a 20 minutos y deja la máquina lenta. → Validar con `preparar` en las fases de solo borrado y reservar `arrancar` + `verificar` para la Fase 3.
- El PR #31 (13 commits más los pendientes) es la base verificada; conviene fusionarlo antes del refactor para que el diff de borrado sea limpio. → Fase 0.

## Anti-Goals (What NOT To Do)

- **No borrar los grupos B, C, D ni E sin preguntar.** La Entrega 1 promete 3 equipos con VLANs y switch; borrar el diseño de red sin confirmarlo puede invalidar el entregable (memorias `no-sacrificar-el-entregable` y `proyecto-consolidado-en-un-host`).
- **No borrar `docker/pc*/docker-compose.yml`, `docker/pc1-medica/openvpms/`, `docker/pc3-administracion-infra/{ldap,bind/named.conf,bind/zones/*.tpl}`, `scripts/generar-certificados.sh` ni `pruebas/smoke-test-3-pcs/*`.** Son lo que arranca el sistema de un host.
- **No fusionar los 3 compose en uno** sin la confirmación del usuario (grupo E) y sin la regresión de 192 PASS después. Es el cambio más arriesgado sobre algo que acaba de funcionar.
- **No usar `down -v`** ni `levantar-sistema borrar` durante el refactor: los volúmenes tienen el sistema inicializado (OpenVPMS tardó 5 min en crear el esquema y ERPNext unos 15 en crear el sitio).
- **No relanzar tareas de fondo que haya matado el harness** ni ejecutar `wsl --shutdown` sin la autorización explícita del usuario en la sesión.

## Plan

### Phase 0: Cerrar la base verificada

**Goal:** dejar el PR #31 con todo lo del 26/09 commiteado y fusionado, para que el refactor parta de una base limpia.

**Why this approach:** el refactor borra mucho. Si arranca sobre una rama con cambios pendientes, el diff mezcla correcciones con borrados y la revisión es imposible.

- **Resultado del caso 4 (ya conocido):** 91 PASS y 1 FAIL. 4a falló por una carrera de arranque (ERPNext `status=None`). La repetición sobre el sistema reiniciado dio PASS en los casos 1-3, así que la persistencia está bien (ver Tabla 7 del handoff).
- **Arreglar H18 en `pruebas/smoke-test-3-pcs/ldaplogin.py`**:
  - `esperar_apps()` (~línea 150) solo da por lista a ERPNext cuando responde a la clave errónea. Añadir una **espera con reintentos del login correcto**: `http("erpnext-backend", HTTP_ERP, ERP_USER, ERP_PASS, SITE)` hasta que devuelva 200, con el mismo límite de 1500 s y pausas de 15 s.
  - En `HTTP_ERP` y `HTTP_INV`, capturar las excepciones que no son `HTTPError` e imprimir `None <tipo>: <mensaje>` en vez de dejar un traceback que el recorte a 200 caracteres deja ilegible.
  - Validar con `./levantar-sistema.sh verificar` (completo): esperado 92 PASS, 0 FAIL y RC=0, en unos 14 min más el `down`/`up`.
- Comprobar que los cambios del 26/09 están commiteados (van en el commit de este handoff: `--rapido` y el fix de `verificar_arquitectura.py:280`) y publicados.
- Actualizar la descripción del PR #31 con el resultado de `verificar` (192 PASS, más el del caso 4) y la medida de RAM (4.600,8 MiB).
- **Preguntar al usuario** si se fusiona el PR #31 en master ahora (recomendado) antes del refactor.

**Files:** `pruebas/smoke-test-3-pcs/ldaplogin.py` (H18); `gh pr edit 31`.
**Validates with:** `gh pr view 31` en estado MERGED (o abierto con la aprobación del usuario) y `git status` limpio.
**Rollback:** `git checkout -- pruebas/smoke-test-3-pcs/ldaplogin.py` si el arreglo de H18 empeora la verificación.

### Phase 1: Decidir los grupos ambiguos y borrar el grupo A

**Goal:** preguntar una sola vez por los grupos B-E y borrar ya lo que es claramente despliegue en 3 PCs.

**Why this approach:** el grupo A no es discutible y es lo que más confunde a quien llega nuevo (deploys, tutoriales y guías por PC). Los demás requieren una decisión del usuario que cambia materialmente el trabajo.

- Usar `AskUserQuestion` con 4 preguntas, una por grupo, cada una con su recomendación:
  - **B, diseño de red:** conservar como anexo en `diseno-red/` (recomendado, por la Entrega 1) o borrar.
  - **C, paquete offline:** borrar, porque hoy es por PC y el plug and play asume red (recomendado), o adaptarlo más adelante.
  - **D, historial:** borrar `plans/handoffs/*` antiguos y las actas, o conservarlos (recomendado: dejar solo el último handoff y el plan).
  - **E, reestructuración:** solo renombrar el arnés (recomendado) o, además, fusionar los compose.
- Crear la rama `refactor/un-solo-host` desde master (o desde la #31 si no se fusionó).
- Borrar el grupo A con `git rm`:
  - `docker/pc{1-medica,2-operaciones,3-administracion-infra}/{deploy.sh,deploy.ps1,.env.example}`
  - `docker/pc3-administracion-infra/bind/generar-zona.ps1`
  - `scripts/systemd/`, `scripts/ip-gestion.sh` y `scripts/perfil.sh`
  - `tutoriales/`
  - `docs/puesta-en-marcha-windows.md` y `docs/despliegue-windows-docker-desktop.md`
  - `despliegue/docker-desktop/`
  - `docs/borradores/`
  - `pruebas/software-un-host/`
- Buscar las referencias colgantes: `git grep -nE "deploy\.(sh|ps1)|\.env\.example|generar-zona|tutoriales/|puesta-en-marcha-windows|despliegue-windows-docker-desktop|docker-desktop/|software-un-host|systemd/|ip-gestion|perfil\.sh"`. Corregir cada una o eliminar el párrafo, en especial `README.md` ("Estructura del repositorio"), `docs/*.md` y los comentarios de los compose.
- Revisar que los compose no citan en comentarios los ficheros borrados (por ejemplo, "Lo llama deploy.ps1" en `generar-zona.ps1` ya no aplica).
- Un commit por tanda con un mensaje que diga **cómo recuperar**: `git checkout <commit>^ -- <ruta>`.

**Files:** unos 30 ficheros borrados; `README.md`, `docs/*.md` y los comentarios de `docker/pc*/docker-compose.yml` actualizados.
**Validates with:**
- `.\levantar-sistema.ps1 preparar` con RC 0.
- `git grep` de las rutas borradas sin resultados fuera de `plans/handoffs/`.
- `bash docker/pc1-medica/openvpms/test-reanudable.sh` y `bash docker/pc3-administracion-infra/test-create-site.sh` en PASS.

**Rollback:** `git revert <commit>` o `git checkout master -- <ruta>`.

### Phase 2: Aplicar las decisiones sobre los grupos B, C y D

**Goal:** ejecutar exactamente lo que el usuario decidió para el diseño de red, el paquete offline y el historial.

**Why this approach:** son decisiones de alcance del entregable; se aplican tal cual, sin reinterpretarlas.

- **B conservar:** mover `despliegue/` + `diagramas/` + `docs/arquitectura-3-equipos-departamentos.md` a un único `diseno-red/`, con un README corto: "Diseño de red propuesto (VLANs 802.1Q, switch L2/L3, matriz de segmentación). No se despliega: el sistema corre en un host; los simuladores reproducen la segmentación". Los simuladores (`simular-l2.sh`, `simular-l3.sh`) necesitan `nicolaka/netshoot`: dejarlo anotado.
- **B borrar:** `git rm -r despliegue/ diagramas/ docs/arquitectura-3-equipos-departamentos.md` y quitar las referencias del README.
- **C borrar:** `git rm scripts/preparar-paquete-offline.sh scripts/instalar-paquete-offline.ps1 docs/paquete-offline-fase0.md`. Quitar de `.gitignore` y `README.md` lo que los cite.
- **D:** borrar los handoffs y planes anteriores al seq 5 y las actas `docs/prueba-smoke-test-resultados.md` y `docs/auditoria-coherencia-documental.md` si así se decide. Nota: el paste prompt de esta sesión apunta al handoff del seq 5; ese **no** se borra.
- `git grep` de las rutas movidas o borradas y corrección de las referencias.

**Files:** según la decisión.
**Validates with:** `.\levantar-sistema.ps1 preparar` con RC 0; `git grep` limpio; los enlaces de `README.md` resuelven (comprobar con `grep -oE '\]\([^)]+\)' README.md` y `test -e`).
**Rollback:** `git revert` del commit de la tanda.

### Phase 3: Reestructurar lo que queda para un solo host

**Goal:** que la estructura diga "un host": el arnés deja de llamarse `smoke-test-3-pcs` y, si el usuario lo aprobó, los 3 compose pasan a ser uno nativo.

**Why this approach:** `pruebas/smoke-test-3-pcs/` es hoy el corazón del sistema, no una prueba. Su nombre y los `override-pc*.yml` son la principal fuente de confusión que queda.

- **Mínimo (E = solo renombrar):**
  - `git mv pruebas/smoke-test-3-pcs sistema` (o el nombre que elija el usuario).
  - Actualizar `ARNES` en `levantar-sistema.sh`, las rutas en `verificar_arquitectura.py` (`AQUI`, `RAIZ`, `ZONA`), en `ldaplogin.py` y en `probe.py` si las tienen, el `.gitignore` (`resultados/`) y los README.
  - Mantener `name: reservaviva-smoke`, o cambiarlo **sabiendo** que un nombre de proyecto nuevo crea volúmenes nuevos y obliga a reinicializar todo (unos 30 min). Recomendado: mantenerlo, o migrar los volúmenes de forma deliberada.
- **Ampliado (E = fusionar):** un `docker-compose.yml` único con redes bridge nativas (las subredes 10.10.X.0/24 que hoy fijan los overrides) y sin `IP_PC*`, `PUBLISH_IP` ni `IFACE`.
  - Mantener **los mismos nombres de red** si se conserva `verificar_arquitectura.py` (usa `vlan10_medica`…).
  - Mantener el mismo nombre de proyecto para no perder los volúmenes.
  - Comparar `docker compose config` antes y después: deben coincidir los servicios, las IP y los volúmenes.
- Renombrar las carpetas `docker/pc1-medica` y compañía solo si el usuario lo pide: son la agrupación por departamento que describe la Entrega 1.

**Files:** `levantar-sistema.sh`, `verificar_arquitectura.py`, `ldaplogin.py`, `probe.py`, los compose, `.gitignore` y los README.
**Validates with:**
- `.\levantar-sistema.ps1 arrancar` con **25/25 sanos** (referencia: 15 min 45 s en frío de aplicación, o minutos con los volúmenes ya inicializados).
- `.\levantar-sistema.ps1 verificar` con **≥ 192 PASS y 0 FAIL** (sin el FAIL deliberado, porque `verificar` ya es completo por defecto).
- Mismo `ExecMainStartTimestamp` antes y después.
- Liberar memoria antes (el umbral son 6,9 GB libres) o usar `-Forzar` con el permiso del usuario.

**Rollback:** `git revert`. Si cambió el nombre del proyecto y se crearon volúmenes nuevos, los viejos siguen ahí (`docker volume ls | grep reservaviva-smoke`).

### Phase 4: Documentación mínima para quien llega nuevo

**Goal:** un README que se entienda en 5 minutos: qué es, cómo se arranca y qué demuestra.

**Why this approach:** el objetivo del usuario es reducir la curva de aprendizaje; sin un README corto, el borrado se queda a medias.

- Reescribir `README.md`:
  - Qué es (la intranet del Zoológico y las 4 apps más la infraestructura).
  - Arranque rápido (lo que ya existe).
  - Mapa de carpetas tras el refactor.
  - Qué demuestra `verificar` (segmentación por VLAN como bridges, DNS, NTP y LDAPS).
  - Qué no demuestra un solo host (802.1Q y el switch físico).
  - Enlace al diseño de red si se conservó.
- Dejar un solo documento de resultados vigente con las cifras del 26/09 (Tablas 2, 3 y 6 del handoff) en lugar de las actas históricas.
- Anotar los pendientes que sobreviven: H12 (cita de OpenLDAP 2.6 en la Entrega 1), las contraseñas en la línea de comandos de `erpnext-create-site`, el SIGKILL (137) de `inventree-worker` y `pretix-cron`, la falta de `mem_limit`, `performance_schema` en openvpms-db y el frío con volúmenes vacíos (H17).

**Files:** `README.md` y quizá `docs/resultados-un-host.md`.
**Validates with:** los enlaces del README resuelven; lo revisa el usuario.
**Rollback:** `git revert`.

## Dependencies & Order

- Fase 0 → Fase 1 (la rama del refactor sale de la base fusionada).
- La pregunta de la Fase 1 es un **bloqueo** para las Fases 2 y 3. El borrado del grupo A de la Fase 1 no depende de la respuesta y se puede hacer mientras tanto.
- Fase 2 → Fase 3 (no se renombra lo que se va a borrar).
- La Fase 4 va al final, porque describe la estructura final.
- Nada se paraleliza: es un solo repositorio con cambios que se tocan entre sí.

## Risks & Mitigations

- **Borrar diseño evaluable (B).** Probabilidad media y alto impacto para la nota. Mitigación: preguntar; la opción recomendada es conservarlo como anexo.
- **Referencias colgantes tras borrar.** Probabilidad alta, porque hay muchos documentos que se enlazan entre sí. Mitigación: `git grep` de cada ruta borrada, un commit por tanda y comprobación de enlaces.
- **Romper el arranque al renombrar o fusionar (Fase 3).** Probabilidad media. Mitigación: comparar `docker compose config` antes y después; regresión con `arrancar` + `verificar` (192 PASS); mismo nombre de proyecto para conservar los volúmenes.
- **Memoria insuficiente para la regresión.** Probabilidad alta con las aplicaciones del usuario abiertas (Tabla 5). Mitigación: pedirle que cierre navegadores, o usar `-Forzar` con su permiso; el 26/09 aguantó con 157 MB disponibles.
- **Que el caso 4 de persistencia falle.** Probabilidad desconocida (estaba en curso). Mitigación: la Fase 0 lo revisa antes de empezar; si falla, es un defecto aparte y no bloquea el borrado del grupo A.

## Success Criteria

- **Mínimo:** grupo A borrado, sin referencias colgantes, y `levantar-sistema preparar` con RC 0; las dos suites sin Docker en PASS.
- **Completo:** grupos B-E resueltos según el usuario; `levantar-sistema arrancar` con 25/25 sanos y `verificar` con ≥ 192 PASS y 0 FAIL tras la reestructuración.
- El repositorio pasa de 110 ficheros versionados a unos 60 o menos (sin el grupo B, unos 30 menos), con un README que explica el arranque en una pantalla.
- Cada commit de borrado indica cómo recuperar lo borrado.

## Quick Start

```bash
# Contexto completo
cat plans/handoffs/HANDOFF_standalone-9e6e8d31_un-host-plug-and-play-verificado_2026-09-26.md

# Ficheros clave para la Fase 0 y la Fase 1
cat levantar-sistema.sh
cat README.md
cat pruebas/smoke-test-3-pcs/docker-compose.yml
git ls-files | awk -F/ '{print $1"/"$2}' | sort | uniq -c

# Datos de referencia
# Tabla 6 del handoff (192 PASS / 28 INFO) y Tabla 3 (4.600,8 MiB)
# Informes: pruebas/smoke-test-3-pcs/resultados/verificacion-20260926-*.txt (gitignorados)

# Verificar el estado de partida
git status -sb && gh pr view 31 --json state,title
powershell -File .\levantar-sistema.ps1 estado

# Primera acción concreta
# Fase 0: leer el resultado del caso 4 en resultados/verificacion-20260926-172430.txt y preguntar al usuario si fusiona el PR #31.
```
