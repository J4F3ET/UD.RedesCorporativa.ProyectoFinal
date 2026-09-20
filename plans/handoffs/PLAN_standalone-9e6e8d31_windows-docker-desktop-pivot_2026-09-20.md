# Plan: saldar las dos deudas de verificación del laboratorio Windows y sanear el entorno antes de la entrega

**Date:** 2026-09-20
**Status:** PLANNED
**Bead(s):** none (bd no está instalado en esta máquina)
**Epic:** Proyecto final Redes Corporativas (UD) — Laboratorio "Reserva Viva"
**Chain:** `standalone-9e6e8d31` seq `3`
**Context:** See `HANDOFF_standalone-9e6e8d31_windows-docker-desktop-pivot_2026-09-20.md` for session data, verification status, and prior approaches.

---

## Problem Statement

El proyecto está consolidado en master (`d467f51`, 13 PRs fusionados, 0 abiertos) y documentado con honestidad mediante una tabla de tres niveles de evidencia. Pero **dos entregables críticos entran en la entrega marcados como NO VERIFICADO**, y en ambos casos por la misma razón: la falta de memoria del sistema mató los procesos a mitad. El arranque completo del arnés murió al minuto 6-7 con los servicios dependientes de `erpnext-create-site` en estado `Created`; la prueba del paquete offline sin red (`instalar.ps1` + `docker load` + `up`) nunca llegó a ejecutarse. Ninguna de las dos tiene un fallo conocido detrás —son deudas de verificación, no defectos— pero descubrirlas rotas el día del laboratorio sería el peor momento posible. Además el entorno arrastra suciedad que ya causó un bloqueo real esta sesión: 8 worktrees huérfanos, 51,7 GB duplicados entre C: y D:, y un almacén de Docker en el disco que se llenó hasta 0 bytes. Ver "Evidence & Data" Tabla 5 en el handoff para el estado exacto de cada entregable.

## Key Findings

- **El arnés arrancó parcialmente y sin fallos**: bind9 con la zona generada, ntp healthy, openldap, erpnext-db healthy, redis, las bases de Pretix/InvenTree, OpenVPMS y `erpnext-configurator` con `Exited(0)`. Lo que faltó fue tiempo y RAM, no corrección. → **drives Phase 1**
- **El cuello es `erpnext-create-site`**, que tarda ~13 minutos en el primer arranque. El proceso murió al minuto 6-7. → **drives Phase 1**
- **La falta de RAM, no de disco, es el bloqueo.** El vigilante confirmó 20 minutos de arnés levantado sin que C: bajara de 11 GB. → **drives Phase 1 y 2**
- **`preparar-paquete-offline.sh` corrió de punta a punta con EXIT 0** y 3,4 GB de salida, pero `instalar-paquete-offline.ps1` no se ha ejecutado nunca. → **drives Phase 2**
- **B3 sigue sin resolver**: los compose fijan `tag@sha256` y `docker load` no conserva el digest. El override `pull_policy: never` debería cubrirlo, y con almacén containerd podría sobrar, pero **nadie lo ha probado**. → **drives Phase 2**
- **El `.vhdx` sigue en C: (51,7 GB) con una copia inútil de 51,7 GB en D:.** El traslado quedó a medias y nunca se capturó el error. → **drives Phase 3**
- **Las 6 redes huérfanas `rvpin_*` bloquearon el arnés** con `Pool overlaps with other one on this address space`. El entorno sucio ya costó tiempo una vez. → **drives Phase 3**
- **Quedan 3 pendientes documentales menores**: el hallazgo B2 (tercer job de ERPNext no documentado), el aviso de "diseño propuesto" en los diagramas, y `docs/handoff-plan-lab-3pcs` sin fusionar desde el seq 1. → **drives Phase 4**

## Anti-Goals (What NOT To Do)

- **NO forzar `wsl --manage --set-sparse --allow-unsafe`.** Windows lo tiene deshabilitado por riesgo de corrupción y dentro del `.vhdx` están los 27 volúmenes del proyecto. Se rechazó deliberadamente en la sesión anterior.
- **NO cerrar Docker Desktop con `Stop-Process`.** Deja sockets AF_UNIX huérfanos que rompen el arranque siguiente; pasó dos veces. Cerrarlo por su interfaz, y si falla, renombrar `%LOCALAPPDATA%\Docker\run`.
- **NO usar `--delete-branch` al fusionar un PR que sea base de otro apilado.** Cerró el #21 automáticamente y hubo que reponerlo como #24.
- **NO hacer `docker system prune -a`.** Quedan imágenes del usuario ajenas al proyecto (`jafetdc/airflow:v1`, `apache/airflow:3.3.0`) que pidió conservar explícitamente.
- **NO intentar `macvlan`, 802.1Q ni ACL sobre el despliegue de Windows.** Decisión cerrada del usuario: el laboratorio va con bridge y la segmentación se demuestra por simulación.
- **NO reabrir el debate de endurecer la VLAN 99.** Quedó sin objeto al no haber VLANs.

## Plan

### Phase 1: Verificar el arranque completo del arnés y ejecutar `ldaplogin.py`

**Goal:** Demostrar que los compose en bridge del #24 levantan los 23 servicios de extremo a extremo y que la autenticación LDAPS funciona de verdad contra ERPNext e InvenTree.

**Why this approach:** El arranque parcial no mostró ningún fallo — bind9, ntp, openldap, erpnext-db y `erpnext-configurator` completaron correctamente. La evidencia apunta a que solo faltó tiempo y RAM, no a un defecto. Es la deuda de mayor valor: valida a la vez el #24 (bridge, puertos, IPs) y el #23 (`ldaplogin.py`).

- **Antes de nada, liberar RAM.** Cerrar navegadores, IDEs y cualquier otra sesión de Claude Code pesada. El arnés pide ~7 GB. Este paso ha sido la causa de los dos fallos anteriores; no lo trates como opcional.
- Comprobar que el entorno arranca limpio: `docker ps -a` debe estar vacío y `docker network ls` no debe mostrar redes `rvpin_*` ni `vlan*` residuales. Si las hay, borrarlas antes (ver Phase 3).
- **Generar la zona de bind9 antes del primer `up`**, o bind9 no arrancará: el fichero final está en `.gitignore` desde el #24. El comando está en `pruebas/smoke-test-3-pcs/README.md`.
- Arrancar con `docker compose up -d --pull never` desde `pruebas/smoke-test-3-pcs/`. El `--pull never` evita descargas y valida de paso que todas las imágenes están presentes localmente.
- **Esperar ~13 minutos.** El cuello es `erpnext-create-site`. No interrumpir: es exactamente donde murieron los dos intentos anteriores.
- Verificar que los **3 jobs** (`erpnext-configurator`, `erpnext-create-site`, `erpnext-ldap-config`) salen con `Exited (0)` — no dos, que es lo que dice la documentación vieja (hallazgo B2).
- Comprobar que los 20 contenedores permanentes quedan `Up` y los que tienen healthcheck llegan a `healthy`.
- Ejecutar `python pruebas/smoke-test-3-pcs/ldaplogin.py`. Cubre login correcto, contraseña errónea (401/403, ERPNext 417), `ldapsearch` LDAPS con la CA, y con `--persistencia` un ciclo `down` sin `-v` + `up -d`.
- **Si `ldaplogin.py` falla, distinguir la causa antes de tocar LDAP.** juan dejó tres supuestos sin verificar que, si son falsos, hacen fallar el script sin que LDAP tenga nada roto: que InvenTree acepta GET con Basic auth en `/api/user/token/`, que hay `python3` en ambos contenedores, y que los hashes del LDIF corresponden a las claves del README.
- Anotar el resultado real en `docs/prueba-smoke-test-resultados.md` y actualizar el bloque "Estado de la verificación" de `docs/puesta-en-marcha-windows.md` §5.

**Files:** `docs/prueba-smoke-test-resultados.md`, `docs/puesta-en-marcha-windows.md` (§5), y `pruebas/smoke-test-3-pcs/ldaplogin.py` si hay que corregirlo.
**Validates with:** los 3 jobs en `Exited (0)`; 20 contenedores `Up`; `ldaplogin.py` con veredicto global PASS y código de salida 0; login con clave errónea rechazado.
**Rollback:** `docker compose down` sin `-v` (conserva volúmenes). Nada en master cambia hasta que se anoten los resultados.

### Phase 2: Verificar el paquete offline con la red cortada (cierra B3)

**Goal:** Demostrar que un PC sin Internet puede desplegar el laboratorio solo con el USB, que es la premisa entera de la Fase 0.

**Why this approach:** `preparar-paquete-offline.sh` ya corrió con EXIT 0 y 3,4 GB de salida, así que la mitad cara está hecha. Lo que falta es la mitad que de verdad prueba la premisa: cargar e instalar sin red. B3 sigue abierto porque `docker load` no conserva el digest y los compose fijan `tag@sha256`.

- Repetir `preparar-paquete-offline.sh` limpio para confirmar que genera la carpeta `overrides/`. La ejecución anterior salió sin ella **por un accidente del operador** (borró la carpeta de salida con otra ejecución viva), **no por un fallo del script**.
- Escribir la salida en **D:**, no en C:. Son ~3,4 GB y C: solo tiene 11-12 GB libres.
- Ejecutar `instalar-paquete-offline.ps1 -Perfil pc3` en un motor de pruebas aislado. pepe usaba `docker:dind` para esto; esa imagen se borró en la limpieza, así que hay que volver a descargarla (esta máquina sí tiene Internet).
- **Cortar la red del motor de pruebas** y hacer `docker compose up -d --pull never`. Ese es el momento de la verdad para B3.
- Comprobar `docker info -f '{{.DriverStatus}}'` en el motor de pruebas: con almacén **containerd** el digest del manifiesto se conserva y la referencia `tag@sha256` podría resolverse sola; con el **clásico** hace falta el override. El paquete debe funcionar en ambos casos, que es justo lo que el override garantiza.
- Verificar que `proyecto.zip` conserva **LF** en los `.sh`. pepe lo comprobó con `od` sin resultado concluyente; un CRLF rompería los scripts en Linux.
- Confirmar que el zip incluye `bind/generar-zona.ps1` y `zones/db.reservaviva.local.tpl`, sin los cuales bind9 no arranca en el laboratorio.
- Actualizar el "Registro de verificación" de `docs/paquete-offline-fase0.md` con lo que realmente se probó, y cambiar la cabecera de NO VERIFICADO a lo que corresponda.

**Files:** `docs/paquete-offline-fase0.md` (registro y cabecera), y `scripts/instalar-paquete-offline.ps1` o `scripts/preparar-paquete-offline.sh` si aparecen fallos.
**Validates with:** `up --pull never` sin red levanta los servicios del perfil; `Get-FileHash` cuadra con `MANIFEST.sha256`; la carpeta `overrides/` existe con un `.yml` por PC.
**Rollback:** borrar la carpeta de salida en D: y el motor de pruebas. No toca master ni el Docker principal.

### Phase 3: Sanear el entorno (almacén en D:, worktrees, suciedad de Docker)

**Goal:** Dejar la máquina en un estado donde el próximo arnés no compita por disco ni tropiece con restos, y eliminar la duplicación de 51,7 GB.

**Why this approach:** El disco lleno provocó la caída completa del motor Docker esta sesión (sockets huérfanos, horas perdidas), y las redes huérfanas `rvpin_*` bloquearon el arnés con un error críptico. Es deuda técnica que ya se ha cobrado dos veces.

- **Capturar primero el error del traslado.** Abrir Docker Desktop → Settings → Resources → Advanced → *Disk image location* y anotar qué ruta aparece y qué error da al aplicar el cambio a `D:\Docker\DockerDesktopWSL`. Sin ese dato no se puede diagnosticar; es la información que faltó toda la sesión anterior.
- **Hacer esto con Docker parado y sin nada del arnés corriendo**, y cerrar Docker Desktop **por su interfaz**, nunca con `Stop-Process`.
- Si el traslado se completa, verificar cuál `.vhdx` usa realmente el motor comparando `LastWriteTime` de ambos con Docker activo; el que se escribe es el vivo. Solo entonces borrar el de C: y recuperar 51,7 GB.
- Si el traslado vuelve a fallar, la alternativa es compactar con `diskpart` (`select vdisk` + `attach readonly` + `compact vdisk` + `detach`) **desde una consola elevada** — requiere administrador, que es lo que bloqueó el intento anterior.
- Borrar los 8 worktrees huérfanos. Los 8 tienen su contenido en master, verificado con `git merge-base --is-ancestor`. El único fichero de valor, `preparar-imagenes-offline.sh`, es el precursor obsoleto del paquete (asume Ubuntu con `.deb`) y está superado.
- Ejecutar `git worktree prune` después, y confirmar que `git worktree list` solo muestra el repo principal.
- Dejar Docker limpio: `docker ps -a` vacío y sin redes fuera de `bridge`, `host` y `none`.

**Files:** ninguno del repositorio; es saneamiento de entorno.
**Validates with:** `C:` con >60 GB libres si el traslado funciona; `git worktree list` con una sola entrada; `docker network ls` sin redes de proyecto.
**Rollback:** los directorios `run.roto-*` y `docker-secrets-engine.roto-*` siguen en `%LOCALAPPDATA%` por si hiciera falta; la copia de D: no se borra hasta confirmar cuál es la viva.

### Phase 4: Cerrar los pendientes documentales

**Goal:** Que no queden afirmaciones desactualizadas ni documentos fuera de master antes de entregar.

**Why this approach:** La auditoría dejó estos hallazgos catalogados y son de coste bajo, pero uno de ellos (B2) provoca una falsa alarma al operador justo durante el despliegue.

- **B2:** las recetas y el tutorial de PC-3 dicen que solo `configurator` y `create-site` salen `Exited(0)`. Hay un tercero, `erpnext-ldap-config`. Corregir en `despliegue/README.md:228` y `:223` y en `tutoriales/tutorial-pc3-administracion-infraestructura.md:116`. Son tres frases.
- **Aviso en los diagramas:** decidir con el usuario si los diagramas de VLAN llevan una nota de "diseño propuesto" remitiendo a `README.md#estado-de-validación`. Está mitigado porque el README ya los clasifica en el nivel 3, pero un evaluador que abra un diagrama suelto no lo vería. **La pregunta se hizo y quedó sin responder.**
- **`docs/handoff-plan-lab-3pcs`:** decidir si se fusiona o se archiva. Arrastra dos handoffs y dos planes sin llegar a master desde el seq 1, y es una de las dos únicas ramas remotas vivas.
- **Variables de LDAP en los tutoriales:** siguen sin documentarse `ERPNEXT_LDAP_BIND_PASSWORD` e `INVENTREE_LDAP_BIND_PASSWORD`, más la nota de `down -v`. Heredado del seq 2.
- Si Phase 1 y 2 salieron bien, **actualizar la tabla de tres niveles del README**: parte de lo que hoy está en "Implementado y ejecutado" gana respaldo, y las dos deudas desaparecen del runbook.

**Files:** `despliegue/README.md`, `tutoriales/tutorial-pc3-administracion-infraestructura.md`, `README.md`, los diagramas si se aprueba el aviso.
**Validates with:** ninguna afirmación sobre "2 jobs" en el repositorio; el comprobador de enlaces de daniel sigue dando 0 rotos.
**Rollback:** trivial, son cambios de texto en una rama con PR.

## Dependencies & Order

- **Phase 1 y Phase 2 son independientes entre sí** y las dos son independientes de Phase 3 y 4. Pueden hacerse en cualquier orden.
- **Phase 1 tiene prioridad** si solo hay tiempo para una: valida el despliegue que se va a usar el día del laboratorio.
- **Phase 3 debe hacerse con Docker parado**, así que no puede solaparse con Phase 1 ni Phase 2.
- **Phase 4 debería ir la última**, porque Phase 1 y 2 cambian lo que hay que escribir en el estado de validación.

## Risks & Mitigations

- **Que la RAM vuelva a matar el arnés.** Probabilidad alta: ya ha pasado dos veces. **Mitigación:** cerrar todo lo demás antes de empezar, y no lanzar Phase 2 en paralelo con Phase 1.
- **Que `ldaplogin.py` falle por sus propios supuestos** y se confunda con un fallo de LDAP. Probabilidad media. **Mitigación:** los tres supuestos están listados en Phase 1; comprobarlos antes de tocar la configuración LDAP.
- **Que el traslado del almacén vuelva a fallar.** Probabilidad media-alta, ya falló una vez. **Mitigación:** capturar el error exacto esta vez; alternativa con `diskpart` desde consola elevada.
- **Que B3 revele que el override no basta** y las imágenes no resuelvan sin red. Probabilidad baja con almacén containerd. **Mitigación:** el override `pull_policy: never` cubre ambos tipos de almacén; si aun así falla, la salida es etiquetar las imágenes sin digest en los compose del paquete.
- **Que aparezcan choques de puertos en el laboratorio** (123/udp con w32time, 53/udp con ICS, solape de `10.10.x.0/24`). Probabilidad media. **Mitigación:** todo está parametrizado (`*_PORT`, `DNS_BIND_IP`, `NET_*`) para cambiarlo allí mismo; los comandos de diagnóstico están en `docs/despliegue-windows-docker-desktop.md`.

## Success Criteria

- **Mínimo viable:** Phase 1 completa. El arnés levanta los 23 servicios, los 3 jobs salen con `Exited (0)` y `ldaplogin.py` da veredicto PASS. Con eso el despliegue del laboratorio deja de ser una promesa.
- **Éxito completo:** Phase 1 y 2 completas, con las cabeceras NO VERIFICADO retiradas de `docs/paquete-offline-fase0.md` y del runbook, y la tabla de tres niveles del README actualizada con lo que realmente se probó.
- C: con más de 60 GB libres (hoy 11-12) si Phase 3 completa el traslado.
- `git worktree list` con una sola entrada y `docker ps -a` vacío.
- Ninguna afirmación en el repositorio que contradiga lo verificado: el comprobador de enlaces sigue en 0 rotos y desaparece la mención a "2 jobs".

## Quick Start

```bash
# Restaurar contexto completo
cat plans/handoffs/HANDOFF_standalone-9e6e8d31_windows-docker-desktop-pivot_2026-09-20.md

# Ficheros clave para la Phase 1
pruebas/smoke-test-3-pcs/README.md          # cómo levantar el arnés y generar la zona de bind9
pruebas/smoke-test-3-pcs/ldaplogin.py       # el script a ejecutar (nunca ejecutado)
docker/pc3-administracion-infra/deploy.ps1  # qué valida y qué espera
docs/puesta-en-marcha-windows.md            # §5 es donde se anota el resultado

# Verificar estado de partida
git checkout master && git pull --ff-only    # esperado: d467f51 o posterior
gh pr list --state open                      # esperado: vacío
docker version --format '{{.Server.Version}}' # esperado: 29.8.0
docker ps -a                                 # esperado: vacío
df -h /c                                     # esperado: 11-12 GB libres

# ANTES DE EMPEZAR: cerrar navegadores, IDEs y otras sesiones pesadas.
# La falta de RAM ha matado este arranque dos veces.

# Primera acción concreta
cd pruebas/smoke-test-3-pcs
# 1) generar la zona de bind9 (está en .gitignore desde el #24; sin esto bind9 no arranca)
# 2) docker compose up -d --pull never
# 3) esperar ~13 min sin interrumpir (erpnext-create-site es el cuello)
# 4) docker compose ps  -> los 3 jobs en Exited (0), 20 contenedores Up
# 5) python ldaplogin.py
```
