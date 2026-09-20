# Plan: cerrar el laboratorio Reserva Viva de 3 PCs (recuperar diagramas, integrar LDAP en las apps y validar en hardware real)

**Date:** 2026-09-19
**Status:** PLANNED
**Bead(s):** none (bd no está instalado en esta máquina)
**Epic:** Proyecto final Redes Corporativas (UD) — Laboratorio "Reserva Viva"
**Chain:** `standalone-9e6e8d31` seq `1`
**Context:** See `HANDOFF_standalone-9e6e8d31_lab-3pcs-pruebas-reales_2026-09-19.md` for session data, test results, and prior approaches.

---

## Problem Statement

El diseño de 3 PCs por departamento (PR #1, #2 y #3 ya en master) está validado solo a nivel de software en un único host Windows con redes bridge: 22 contenedores arrancan desde cero, todas las apps responden 200, DNS/NTP/LDAP/LDAPS funcionan y los administradores se crean solos. Lo que NO está validado es lo que hace de esto una red corporativa: macvlan, sub-interfaces 802.1Q, el switch y la matriz de segmentación; además ninguna app autentica contra LDAP (solo hay alcance de red) y los diagramas Archify (`diagramas/`) y la prueba alternativa `pruebas/software-un-host/` **no llegaron a master** aunque el documento de arquitectura los enlaza. Ver "Evidence & Data" (Anexos A, I, J) en el handoff.

## Key Findings

- `diagramas/` y `pruebas/software-un-host/` existen solo en la rama `claude/project-handoff-departments-g266yp` (commits `d13a109`, `8e1e0bb`); `git ls-tree origin/master` los da como 0 archivos → drives Phase 1.
- Los diagramas están desactualizados respecto al estado real (ERPNext ahora es un stack de 10 servicios con nginx en :8080, hay bind9, LDAPS con CA interna e `inventree-worker`) → drives Phase 1.
- Los compose originales tenían defectos que solo la prueba real detectó (Pretix 500, InvenTree crash loop, ERPNext 404, montajes de bind9 inexistentes, `admin@localhost`/`admin` en Pretix); ya están corregidos y probados → base para Phase 2 y 3.
- LDAP solo se probó como alcance de red y bind; `LDAP_TLS_VERIFY_CLIENT=demand` por defecto y una CA caducada rompían LDAPS; se resolvió con `scripts/generar-certificados.sh` → Phase 2 puede usar LDAPS con `ca.crt`.
- El arnés une las apps a `vlan99_infra` (adyacencia L2), así que NO ejerce la matriz de segmentación → drives Phase 3.
- Primer arranque completo ~13 min (cuello: `erpnext-create-site`), pico ~750 MB (`openvpms-app`) y ~510 MB (`inventree-app`); ~7 GB de Docker fueron suficientes → dimensiona el hardware en Phase 3.
- Con macvlan el host no alcanza a sus propios contenedores: las pruebas deben hacerse desde otro equipo → drives Phase 3.
- Sin confirmar: si el switch es L2 o L3 (`FALLBACK_L2`) → bloquea el diseño final de Phase 3.

## Anti-Goals (What NOT To Do)

- **No** intentar probar macvlan/802.1Q en Docker Desktop/Windows: no aplica; ya se decidió el arnés en bridge (Key Decisions del handoff).
- **No** volver a `frappe/erpnext:latest` (era `17.0.0-dev`) ni añadir `--skip-innodb-read-only-compatibility` a MariaDB 10.6 (rompe el contenedor).
- **No** hacer push a master ni usar `git add -A`; trabajar en rama nueva con rutas explícitas, `git fetch` + `git pull --rebase` antes de cada push (reglas acordadas con la sesión par).
- **No** escribir archivos `.sh` con `python open(..., 'w')` en Windows (CRLF rompe en Linux); usar Write o `sed -i 's/\\r$//'`.
- **No** sondear IP de contenedor desde el host de Docker Desktop (no son alcanzables): usar contenedores auxiliares en la red.
- **No** tocar los archivos de la sesión par sin coordinar (`docker/pc1-medica/**`, `tutoriales/**`, `docs/arquitectura-3-equipos-departamentos.md`, `README.md`, `docs/prueba-smoke-test-resultados.md`).

## Plan

### Phase 1: Recuperar diagramas y prueba alternativa a master y actualizarlos

**Goal:** que `diagramas/` y `pruebas/software-un-host/` existan en master y reflejen el estado real del stack.

**Why this approach:** el handoff (Anexo A) demuestra con `git ls-tree` que no están en master; el documento de arquitectura los enlaza y quedarían enlaces rotos en la entrega.

- Crear rama nueva desde master actualizado: `git checkout master && git pull && git checkout -b docs/recuperar-diagramas`.
- Traer los archivos: `git checkout claude/project-handoff-departments-g266yp -- diagramas pruebas/software-un-host` (o `git cherry-pick d13a109 8e1e0bb`); resolver conflictos si `pruebas/` ya cambió.
- Decidir con el usuario si `pruebas/software-un-host/` se conserva o se elimina (el arnés `smoke-test-3-pcs` lo reemplaza en la práctica); por defecto conservarlo con una nota en su README apuntando al arnés vigente.
- Actualizar `diagramas/topologia-red.architecture.json` y `flujo-datos-segmentacion.dataflow.json`: ERPNext como stack (erpnext-db, redis-cache/queue, configurator, create-site, backend .40.11, websocket, scheduler, queue-short/long, erpnext-hr .40.10 :8080), bind9 (.99.11), `inventree-worker` (.30.12), LDAPS 636 con CA interna. Regenerar HTML con Archify (validate/deliver/visual-check).
- Verificar los enlaces de `docs/arquitectura-3-equipos-departamentos.md` (archivo de la sesión par: si hay que cambiarlo, pedirle a esa sesión o coordinar antes).
- Abrir PR a master (sin push directo).

**Files:** `diagramas/**` (nuevo/actualizado), `pruebas/software-un-host/**` (nuevo).
**Validates with:** `git ls-tree -r --name-only origin/master | grep -c '^diagramas/'` ≥ 6 tras el merge; abrir los dos HTML y comprobar que muestran ERPNext :8080, bind9 y `inventree-worker`.
**Rollback:** cerrar el PR / borrar la rama; master no cambia hasta el merge.

### Phase 2: Integrar LDAP (preferiblemente LDAPS) en las aplicaciones

**Goal:** que al menos una autenticación real por app contra `ldap.reservaviva.local` funcione, no solo el alcance de red.

**Why this approach:** la prueba solo cubrió bind anónimo/protocolo (Tabla 5 del handoff); "Sin cubrir" en LDAPS: que las apps usen la CA. Es la brecha funcional más grande entre software y objetivo del curso.

- Empezar por la más simple: **ERPNext/Frappe** (LDAP Settings en la UI o `bench` con `ldap3`), luego **InvenTree** (`django-auth-ldap` vía variables `INVENTREE_LDAP_*`), luego **Pretix** (plugin/soporte LDAP) y por último **OpenVPMS** (su propio mecanismo). Si una app no lo soporta limpiamente, documentarlo como limitación en vez de forzarlo.
- Crear usuarios de prueba en OpenLDAP (LDIF en `docker/pc3-administracion-infra/ldap/` montado en `/container/service/slapd/assets/config/bootstrap/ldif/custom`), con OU por departamento (`ou=medica`, `ou=operaciones`, `ou=rrhh`).
- Montar `ca.crt` (generada por `scripts/generar-certificados.sh`) en cada app y usar `ldaps://ldap.reservaviva.local:636` (resuelto por bind9) con verificación de cadena.
- Añadir variables nuevas a los `.env.example` correspondientes (avisar a la sesión par para que refleje en tutoriales).
- Probar login real (correcto/incorrecto) por app, y persistencia tras `down` sin `-v` + `up -d`.

**Files:** `docker/pc*/docker-compose.yml`, `docker/pc*/.env.example`, `docker/pc3-administracion-infra/ldap/*.ldif` (nuevo), `pruebas/smoke-test-3-pcs/test.env` y `probe.py`/nuevo `ldaplogin.py`.
**Validates with:** para cada app, login con usuario LDAP → 200/sesión válida; clave errónea → 401/403; `ldapsearch -H ldaps://10.10.99.10 -D <user> -w <pw>` con verificación completa OK; resultados anotados en `docs/prueba-smoke-test-resultados.md` (coordinando con la sesión par).
**Rollback:** revertir los cambios en los compose/`.env.example`; las apps siguen funcionando con su usuario local (admin creado por `deploy.sh`).

### Phase 3: Prueba en hardware real (macvlan, 802.1Q, switch, segmentación)

**Goal:** demostrar que `deploy.sh` deja cada PC funcionando y que la matriz de segmentación se cumple de verdad.

**Why this approach:** es lo único que el arnés no puede probar (Anexo J) y lo que evalúa el curso; el checklist ya está redactado en el handoff (Anexo I).

- Confirmar con el equipo/curso si el switch es L2 o L3 y fijar `FALLBACK_L2` en cada `.env`.
- Ejecutar el checklist del Anexo I en orden: PC-3 (~13 min), copiar `ca.crt` a PC-1/PC-2, PC-2, PC-1.
- Probar desde un equipo distinto al host (limitación de macvlan): HTTP por VLAN, `ldapsearch` (389 y 636), `dig @10.10.99.11`, `ntpdate -q 10.10.99.12`.
- **Matriz negativa:** VLAN20→VLAN30, VLAN10→VLAN40, etc. deben fallar; VLAN*→VLAN99 (389/636/53/123) deben pasar. Con `FALLBACK_L2=true`, revisar `nft list ruleset`.
- Reiniciar cada PC y comprobar `systemctl status reserva-viva-pcN` y que no hay reinicialización.
- Registrar tiempos y consumo de RAM reales del hardware del laboratorio.

**Files:** `docs/prueba-smoke-test-resultados.md` (nueva ronda; coordinar con la sesión par) y ajustes puntuales en `scripts/**` si algo falla.
**Validates with:** todas las filas positivas de la matriz pasan y todas las negativas fallan; `deploy.sh` de los 3 PCs termina sin intervención manual; apps responden 200 tras reinicio.
**Rollback:** `sudo docker compose down` en cada PC + `ip link del IFACE.NN`; si la matriz falla, volver a `FALLBACK_L2` alternativo y reintentar.

### Phase 4: Endurecer reproducibilidad de la entrega

**Goal:** que la entrega no se rompa por cambios externos de imágenes.

**Why this approach:** ya ocurrió una vez (`frappe/erpnext:latest` = v17-dev); tags `stable`/`latest` de Pretix, InvenTree y cturra/ntp también son móviles.

- Fijar tags o digests de todas las imágenes (Pretix, InvenTree, cturra/ntp, bind9, redis, postgres) tras la última prueba exitosa (`docker image inspect --format '{{index .RepoDigests 0}}'`).
- Añadir política `restart: unless-stopped` donde falte y healthchecks útiles (Pretix, ERPNext).
- Documentar en tutoriales/README el tiempo de primer arranque y los requisitos de RAM (~7 GB).

**Files:** `docker/pc*/docker-compose.yml`, `docker/pc*/.env.example` (si se parametriza el tag), tutoriales (vía la sesión par).
**Validates with:** repetir el arnés completo desde cero con las imágenes fijadas: mismos resultados que la Tabla 5 del handoff.
**Rollback:** volver a los tags anteriores por `git revert`.

## Dependencies & Order

- Phase 1 es independiente y puede empezar de inmediato (solo Git/Archify, sin Docker).
- Phase 2 puede correr en el arnés (un host) en paralelo a Phase 1; usa la CA que ya genera `scripts/generar-certificados.sh`.
- Phase 3 depende de acceso a Linux con root, switch y los 3 PCs; idealmente después de Phase 2 para probar LDAPS entre VLAN real.
- Phase 4 va al final, tras una ronda exitosa de Phase 2/3, para fijar lo que realmente funcionó.
- Coordinación: los archivos de la sesión par (Where We're Going / reparto) no se tocan sin avisar; los resultados nuevos se pasan a esa sesión para `docs/prueba-smoke-test-resultados.md` y tutoriales.

## Risks & Mitigations

- **Sin hardware/Linux root disponible** (probabilidad alta): mitigación = validar `deploy.sh` y `bash -n` en una VM Linux con `macvlan` sobre una interfaz virtual (bridge Linux + VLAN sub-interfaces) como aproximación; documentar como limitación si no hay switch.
- **Apps sin soporte LDAP limpio (Pretix/OpenVPMS)** (probabilidad media): documentar la limitación y dejar el admin local; no forzar parches propios.
- **Tiempos largos y RAM** (media): esperar ~13 min; usar `docker compose up -d` en background (bloquea >5 min en foreground) y Monitor; si la RAM del PC de laboratorio es < 7 GB, arrancar por PC en lugar de todo en uno.
- **Conflictos con la sesión par en los mismos archivos** (media): respetar el reparto por archivos, `git fetch` + `git pull --rebase` antes de cada push, commits pequeños con rutas explícitas.
- **Imágenes móviles rompen la entrega** (media): Phase 4 las fija.
- **CRLF en Windows** (baja con `.gitattributes`, pero real en el working tree): comprobar `file deploy.sh` antes de commitear scripts.

## Success Criteria

- Mínimo viable: `diagramas/` y `pruebas/software-un-host/` en master y actualizados; el arnés vuelve a pasar completo (mismo resultado que Tabla 5: 200 en todas las apps, LDAP/LDAPS/DNS/NTP OK, ~13 min primer arranque).
- Funcional: al menos ERPNext e InvenTree autentican usuarios LDAP reales por LDAPS con cadena verificada; clave errónea rechazada.
- Completo: `deploy.sh` de los 3 PCs funciona en hardware real sin pasos manuales, la matriz de segmentación pasa (positivos y negativos), sobrevive a reinicio y las imágenes están fijadas por tag/digest.

## Quick Start

```bash
# Restore full context
cat plans/handoffs/HANDOFF_standalone-9e6e8d31_lab-3pcs-pruebas-reales_2026-09-19.md

# Prior context (if OV available)
# /memory-recall reserva viva 3 pcs smoke test

# Key source files for Phase 1
docs/arquitectura-3-equipos-departamentos.md
git show claude/project-handoff-departments-g266yp:diagramas/README.md
git show claude/project-handoff-departments-g266yp:diagramas/topologia-red.architecture.json

# Baseline data to reference
docs/prueba-smoke-test-resultados.md   # §2, §5, §8
pruebas/smoke-test-3-pcs/README.md

# Verify starting state
git fetch && git ls-tree -r --name-only origin/master | grep -E '^(diagramas|pruebas/software-un-host)' | wc -l   # esperado 0
cd pruebas/smoke-test-3-pcs && docker compose config -q

# First concrete action
git checkout master && git pull && git checkout -b docs/recuperar-diagramas \
  && git checkout claude/project-handoff-departments-g266yp -- diagramas pruebas/software-un-host
```
