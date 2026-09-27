# Refactor "un solo host" fusionado (PR #31, #32, #33) con 92 PASS / 0 FAIL. Siguiente: quitar del sistema vivo lo que queda de 3 PCs y escribir la documentación de un host

**Date:** 2026-09-26
**Status:** IN PROGRESS. El refactor que pedía el seq 5 está **COMPLETADO Y FUSIONADO** en master (`93b106d`). El usuario abre un objetivo nuevo: *"consolidar todo lo de un host eliminando lo que no corresponda, y consolidarlo y crear los documentos de la documentación correspondiente"*. Todavía no se ha empezado.
**Bead(s):** none (`bd` no está instalado)
**Epic:** Proyecto final Redes Corporativas (UD, grupo 678-302). Laboratorio "Reserva Viva"
**Chain:** `standalone-9e6e8d31` seq `6`
**Parent:** `HANDOFF_standalone-9e6e8d31_un-host-plug-and-play-verificado_2026-09-26.md`. **Borrado del árbol a petición del usuario** ("elimina el anterior handoff") en el commit de este traspaso. Se lee con `git show 93b106d:plans/handoffs/HANDOFF_standalone-9e6e8d31_un-host-plug-and-play-verificado_2026-09-26.md`.
**Prior chain:** `…_lab-3pcs-pruebas-reales_2026-09-19` > `…_diagramas-y-ldap-en-master_2026-09-19` > `…_windows-docker-desktop-pivot_2026-09-20` > `…_arranque-arnes-ldaps-verificado_2026-09-20` > `…_un-host-plug-and-play-verificado_2026-09-26` > this. Todos están borrados del árbol y se recuperan de git: los seq 1-4 con `git show 95e0da4:plans/handoffs/<fichero>` y el seq 5 con `93b106d`.

---

## Stale References

Identificadores del seq 5 que **ya no existen** en el árbol. No es un error: el refactor los movió o los borró a propósito.

- `pruebas/smoke-test-3-pcs/` → ahora es `sistema/` (`d57a50f`).
- `docker/pc*/deploy.sh`, `deploy.ps1` y `.env.example`, `generar-zona.ps1`, `scripts/systemd/`, `scripts/perfil.sh`, `tutoriales/`, `docs/puesta-en-marcha-windows.md`, `docs/despliegue-windows-docker-desktop.md`, `despliegue/docker-desktop/`, `docs/borradores/` y `pruebas/software-un-host/` → borrados (`95e0da4`). Se recuperan con `git checkout cceb54c -- <ruta>`.
- `scripts/ip-gestion.sh` → movido a `diseno-red/comun/ip-gestion.sh` (`95e0da4`).
- `despliegue/` → `diseno-red/`; `diagramas/` → `diseno-red/diagramas/`; `docs/arquitectura-3-equipos-departamentos.md` → `diseno-red/` (`ea55bf7`).
- `scripts/preparar-paquete-offline.sh`, `scripts/instalar-paquete-offline.ps1`, `docs/paquete-offline-fase0.md`, `docs/prueba-smoke-test-resultados.md` y `docs/auditoria-coherencia-documental.md` → borrados (`ea55bf7`). Se recuperan con `git checkout 95e0da4 -- <ruta>`.
- Los informes de `verificar` estaban en `pruebas/smoke-test-3-pcs/resultados/`; ahora están en `sistema/resultados/` (gitignorado).

## Since Last Handoff

El seq 5 dejaba un plan de 5 fases (Fase 0 a Fase 4). **Se ejecutaron todas en esta sesión.** Así fue cada una:

- **Fase 0 (cerrar la base verificada): HECHA.**
  - H18 corregido en `ldaplogin.py` (`20f65e7`). `verificar` completo dio **92 PASS / 0 FAIL / 14 INFO, RC=0**, justo lo esperado.
  - Sorpresa: el PR #31 **ya estaba fusionado**, pero solo hasta `5c09945`. El commit del traspaso `10bac21` (`--rapido` y el fix del `KeyError: 99`) no estaba en master. Se abrió el **PR #32** con `10bac21` + `20f65e7`. El usuario eligió "Merge now". Al intentar fusionarlo, ya estaba fusionado (`d9f81e5`), así que lo hizo el usuario o algo fuera de esta sesión.
- **Fase 1 (preguntar B-E y borrar A): HECHA.**
  - La pregunta dio **B = conservar como anexo, C = borrar, D = dejar solo el último, E = solo renombrar** (Tabla 2).
  - Al borrar el grupo A apareció un defecto real, **H19**: el sistema de un host no creaba el administrador de Pretix y dejaba `admin@localhost` / `admin`. Corregido en `cceb54c`.
- **Fase 2 (B, C y D): HECHA** (`ea55bf7`). Los simuladores del anexo **no se ejecutaron**, porque `nicolaka/netshoot` no está en local.
- **Fase 3 (renombrar el arnés): HECHA** (`d57a50f`). El `docker compose config` resuelto es idéntico antes y después. La regresión dio **92 PASS / 0 FAIL**.
- **Fase 4 (README y resultados): HECHA** (`9141feb`): `README.md` reescrito y `docs/resultados-un-host.md` nuevo.
- **PR #33** (`cceb54c`..`9141feb`) abierto y **fusionado en master como `93b106d`** (23:28:07Z).
- Las preguntas abiertas del seq 5 quedaron así:
  - "¿Qué grupos B-E se borran?": respondida.
  - "¿Pasa el caso 4?": sí.
  - "¿#31 antes o después?": antes.
  - Siguen abiertas: el ahorro de `performance_schema` y el modo Docker Desktop.
- **Trayectoria:** el repositorio ya se organiza como "un host" (112 → 70 ficheros). El usuario pide ahora dos cosas:
  - **Consolidar más a fondo:** el *código vivo* (compose, `test.env`, scripts) todavía razona en "IP LAN de PC-2/PC-3" (Tabla 5).
  - **Escribir la documentación** correspondiente.

## Reference Documents

- `README.md` (raíz, reescrito en `9141feb`): qué es, arranque rápido, qué demuestra `verificar`, mapa, anexo e integración LDAP.
- `docs/resultados-un-host.md` (nuevo): el **único** documento de resultados vigente (arranque, RAM, pasadas de `verificar`, pendientes).
- `sistema/README.md` y `sistema/verificar_arquitectura.md`: el arnés y qué verifica el guion, con sus "hallazgos previstos".
- `diseno-red/README.md`: el anexo de diseño (no se despliega), con la nota de recuperación.
- `docs/integracion-ldap-erpnext-inventree.md` y `docs/ldap-pretix-openvpms.md`: la integración LDAP por aplicación.
- Memorias del usuario (`C:\Users\jafet\.claude\projects\D--Proyectos-UD-RedesCorporativaa-ProyectoFinak\memory\`):
  - `delegacion-detallada-a-agentes.md` (**fijada**): coordinar, delegar con encargos exhaustivos y verificar lo entregado.
  - `no-sacrificar-el-entregable.md`: los problemas de recursos se resuelven con configuración, nunca quitando funciones.
  - `proyecto-consolidado-en-un-host.md`: **actualizada en esta sesión** con las decisiones B-E, incluida la de "no fusionar los compose salvo que el usuario cambie de idea".
- PDF de la Entrega 1: `C:\Users\jafet\Downloads\Entrega-1-Proyecto-RC-302-G6 (2).pdf`. Promete 3 equipos con VLANs y switch, y nombra las 4 apps del piloto.

## The Goal

El usuario está cerrando el proyecto final de Redes Corporativas: la intranet del Zoológico "Reserva Viva", con 4 aplicaciones (OpenVPMS, Pretix, InvenTree y ERPNext/HR) más la infraestructura (OpenLDAP con LDAPS y CA interna, bind9 y NTP), segmentadas por VLAN.

El 26/09 decidió que el proyecto se entrega y se explica **como un sistema de un solo host**, para reducir la curva de aprendizaje. El diseño de 3 equipos con switch queda como anexo de diseño.

El objetivo nuevo, con sus palabras, es: *"consolidar todo lo de un host eliminando lo que no corresponda, y consolidarlo y crear los documentos de la documentación correspondiente"*. En la práctica son dos cosas:

- **(a) Código vivo.** Quitar del código que arranca el sistema los restos del diseño de 3 PCs: variables `IP_PC2`/`IP_PC3` ("IP LAN de PC-x"), `IFACE`, las copias de la CA "a PC-1 y PC-2", las etiquetas "PC-1 Medica" y los comentarios. Todo ello sin perder la agrupación por departamento ni romper la regresión (92 PASS / 0 FAIL).
- **(b) Documentación.** Escribir el juego de documentos del sistema de un host: arquitectura, operación, seguridad y aplicaciones, además de los resultados que ya existen.

## Where We Are

- **Rama actual:** `docs/consolidacion-un-host`, creada desde `origin/master` (`93b106d`). Solo tiene el commit de este traspaso: borra el handoff/plan del seq 5 y añade este handoff y su plan.
- **master** = `93b106d` (merge del PR #33). Contiene todo lo de esta sesión:
  - `20f65e7` (H18), `cceb54c` (H19), `95e0da4` (A), `ea55bf7` (B/C/D), `d57a50f` (E) y `9141feb` (docs).
  - PRs fusionados: #31, #32 y #33. **No hay PRs abiertos.**
- **70 ficheros versionados** (antes 112). El mapa:
  - `levantar-sistema.{sh,ps1,cmd}`, `sistema/` (11) y `docker/pc1-medica` (5).
  - `docker/pc2-operaciones` (1) y `docker/pc3-administracion-infra` (8).
  - `scripts/generar-certificados.sh` y `docs/` (3).
  - `diseno-red/` (35, de ellos 6 HTML de ~15.000 líneas cada uno) y `plans/handoffs/` (2 tras este commit).
- **Sistema levantado ahora mismo** en WSL (Docker Engine 29.8.1, Compose 5.5.1, `Ubuntu-24.04`):
  - Proyecto `reservaviva-smoke`: 22 contenedores en marcha y sanos, más 3 trabajos terminados en `Exited (0)`.
  - Sesión keepalive `reservaviva-keepalive` viva.
  - `docker.service` con `ExecMainStartTimestamp` 17:01:17 (-05) **sin cambios en toda la sesión**.
- **Pretix** tiene solo `admin@reservaviva.local` (is_staff=True). `check_password` de la clave de `sistema/test.env` da True. `admin@localhost` está borrado (H19).
- **Últimas cifras** (Tabla 3):
  - `verificar` completo desde `sistema/`: **92 PASS / 0 FAIL / 14 INFO, RC=0**. Informe: `sistema/resultados/verificacion-20260926-181713.txt`.
  - `arrancar`: RC=0, 25/25 sanos en 31 s de espera, porque el sistema ya estaba arriba.
- **Suites sin Docker:** `docker/pc1-medica/openvpms/test-reanudable.sh` → "TODO PASA"; `docker/pc3-administracion-infra/test-create-site.sh` → "TODO PASA".
- **Enlaces:** todos los enlaces relativos de todos los `.md` resuelven (comprobado con un bucle `grep -oE '\]\([^)]+\)'` + `test -e`).
- **Restos de 3 PCs en el sistema vivo** (medidos con `git grep -c`; detalle en la Tabla 5):
  - `IP_PC2`/`IP_PC3` en los 3 compose, la plantilla de zona, `levantar-sistema.sh` y `test.env`.
  - `IFACE=eth0` en `test.env` (resto de macvlan, sin uso).
  - `generar-certificados.sh` copia `ca.crt` a `docker/pc1-medica/certs/` y `docker/pc2-operaciones/certs/` "para PC-1 y PC-2".
  - Etiquetas "PC-1 Medica / PC-2 Taquilla / PC-3 RRHH" en la salida de `levantar-sistema.sh`.
  - "NO VERIFICADO" en las cabeceras de los compose de PC-1 y PC-3.
- **Hallazgo de esta sesión (sin corregir), H20:** `IP_PC2=10.10.30.10` es la IP de **InvenTree** (vlan30), pero los compose la usan como URL de Pretix. En `docker/pc2-operaciones/docker-compose.yml`:
  - `PRETIX_PRETIX_URL: http://${IP_PC2}:${PRETIX_PORT}` aparece en las líneas 73, 115 y 158.
  - La sonda de Pretix manda `Host: ${IP_PC2}` (línea 79).
  - En 3 PCs era correcto, porque PC-2 alojaba ambas apps con una sola IP LAN. En un host es incoherente. **No se ha comprobado** si el navegador en `http://localhost:18082` sufre por ello (CSRF, enlaces o `ALLOWED_HOSTS`).
- **Hallazgo previsto documentado:** la zona pone `dns`, `ntp` y `ldap` en `${IP_PC3}` = 10.10.99.10 (la IP de openldap), en vez de .11 (dns-interno) y .12 (ntp-interno).
  - Lo dice `sistema/verificar_arquitectura.md`, en "Hallazgos previstos".
  - El guion compara la zona con las IP reales (`verificar_arquitectura.py:403`) y lo reporta.
- **Worktrees huérfanos:** 8, sin tocar. Siguen como en el seq 5 (lista en "Evidence & Data").
- **Sesiones peer (juan, pepe):** no existen. Todo lo de esta sesión lo hice yo directamente.

## What We Tried (Chronological)

**Bloque temprano: Fase 0 (base verificada)**

1. **H18 en `ldaplogin.py`.** Hipótesis: el caso 4a fallaba porque `esperar_apps()` daba ERPNext por listo cuando respondía a la clave errónea, y el primer login correcto llegaba a un gunicorn en frío. Cambios:
   - Un segundo bucle dentro del mismo límite (1500 s, pausas de 15 s) que reintenta `http("erpnext-backend", HTTP_ERP, ERP_USER, ERP_PASS, SITE)` hasta obtener 200, e imprime `ERPNext aun no acepta el login correcto: status=…`.
   - En `HTTP_ERP` y `HTTP_INV`, `except Exception as e: print("None", type(e).__name__ + ":", e)`.
   - Prueba local del script embebido contra un puerto cerrado: `'None URLError: <urlopen error [WinError 10061] …>'`. `http()` lo devuelve como `(None, "None URLError: …")`, legible.
   - Resultado en real: **92 PASS / 0 FAIL / 14 INFO, RC=0** (17:47). **El bucle de reintento no llegó a iterar**, porque ERPNext aceptó a la primera. El arreglo está correcto, pero no se ejercitó en su rama de reintento.
2. **PR #31 "ya fusionado".** `gh pr view 31` → MERGED el 2026-09-26T22:09:31Z, `ee791c0`, head `5c09945`. `git log origin/master..HEAD` → solo `10bac21`.
   - Decisión: PR nuevo (#32) en lugar de editar #31. Se redactó el cuerpo con el resultado "en curso" y se actualizó al terminar.
   - `gh pr merge 32` → "already merged" (`d9f81e5`).

**Bloque intermedio: Fase 1 (decisión B-E y grupo A)**

3. **AskUserQuestion con 4 preguntas.** Todas las respuestas fueron las opciones recomendadas (Tabla 2). Se guardaron en la memoria `proyecto-consolidado-en-un-host.md`.
4. **Rama `refactor/un-solo-host`** con `git switch -c … origin/master`. El clasificador no la bloqueó, al contrario que el `git checkout -b` del seq 5.
5. **Borrado del grupo A.** Antes, `git grep` de las rutas para buscar dependencias. Dos hallazgos:
   - **`scripts/ip-gestion.sh` no era del grupo A de verdad:** lo hacen `source` `diseno-red/{l2-fallback,l3-switch}/scripts/setup-vlans-pc2.sh` y `l3-switch/…/setup-vlans-pc3.sh` (anexo que se conserva). Se movió a `diseno-red/comun/ip-gestion.sh` y se cambió la ruta a `/../../comun/ip-gestion.sh`. `bash -n` OK en los 4 scripts.
   - **H19.** `deploy.sh` de PC-2 contenía `init_admins()`, que creaba el superusuario de Pretix y borraba `admin@localhost`, y **nada en el sistema de un host lo hacía**. Comprobado en vivo: `User.objects.all()` → `[('admin@localhost', True)]`. El script anunciaba `usuario: admin@reservaviva.local`, que no existía.
6. **Fix H19** (`cceb54c`). `crear_admin_pretix()` en `levantar-sistema.sh` se llama tras `esperar_sano`:
   - Hace hasta 6 intentos con 10 s de pausa. Pasa `ADM_EMAIL`/`ADM_PASS` por el entorno de `docker exec -e ADM_EMAIL -e ADM_PASS`, así que no van en argv.
   - Usa un heredoc Python con `create_superuser`, borra `admin@localhost` y termina con dos `assert`.
   - Validado con `arrancar` RC=0, `check_password` True y una segunda ejecución idempotente (sourcing solo de la función).
7. **Trampa de fines de línea.** El primer intento de editar los compose con Python falló (`AssertionError … 0`), porque la copia de trabajo es **CRLF** (`core.autocrlf=true`). Los `.sh` son LF por `.gitattributes`.
   - Solución: un helper que lee con `newline=''`, normaliza a `\n`, edita y reescribe con CRLF si el original lo era.
   - `levantar-sistema.sh` se escribió conservando LF (0 CR), porque `.gitattributes` fuerza `*.sh eol=lf`.

**Bloque intermedio-tardío: Fase 2 (B, C y D)**

8. **`git mv despliegue diseno-red`**, `git mv diagramas diseno-red/diagramas` y `git mv docs/arquitectura-3-equipos-departamentos.md diseno-red/`.
   - Reescritura global con regex `(?<![\w./-])despliegue/` → `diseno-red/`.
   - Excluidos `plans/handoffs/` y los `.json`/`.html` de diagramas, que están fijados a una revisión.
9. **Actas borradas pero citadas como procedencia.**
   - `ldaplogin.py` citaba `§9.3`, `ldap-pretix-openvpms.md` citaba `§8`, y la arquitectura tenía 4 enlaces.
   - Donde era procedencia, se sustituyó por "(retirado; se lee con `git show 95e0da4:docs/prueba-smoke-test-resultados.md`)".
   - Donde era "dónde están los resultados", se apuntó a `sistema/verificar_arquitectura.md`.
   - Tropiezo: se esperaban 3 apariciones del enlace y había 4. El `assert` abortó antes de escribir, sin estado a medias, y se repitió con 4.
10. **Enlace roto a `../tutoriales/`** en la arquitectura del anexo. Se reemplazó por una nota con `git checkout cceb54c -- tutoriales`.
11. **Simuladores:** `docker image inspect nicolaka/netshoot@sha256:b09d9b21…` falló porque no está en local. **No se descargó**: es una descarga y necesita el permiso del usuario. Queda como pendiente.

**Bloque tardío: Fases 3 y 4**

12. **Renombrado del arnés.** Primero se capturó `docker compose --env-file test.env config` → `config-antes.yml` (869 líneas, **0** apariciones de `smoke-test-3-pcs`).
    - `git mv pruebas/smoke-test-3-pcs sistema` movió también el `resultados/` sin versionar. Mi `mv` posterior falló con "cannot stat", inofensivo.
    - Cambios: `include:` a `../docker/`, `RAIZ = AQUI.parent` y `ARNES="${RAIZ}/sistema"`.
    - `diff config-antes config-despues` → **vacío**.
13. **Regresión de la Fase 3:** `arrancar` RC=0 (25/25) y después `verificar` → **92 PASS / 0 FAIL / 14 INFO, RC=0**, sin reinicio de `docker.service`.
    - Hubo un momento de duda: el log mostraba solo `[00:07] sanos 24/25` a las 18:16. Era progreso normal: `erpnext-ldap-config` se vuelve a ejecutar en cada `up`.
14. **Documentación.**
    - `README.md` reescrito completo. La primera `Write` falló porque el fichero había cambiado desde la última lectura; hubo que leerlo antes.
    - `docs/resultados-un-host.md` nuevo. Al revisarlo encontré un error aritmético mío: la fila "resto" decía 137,6 y la suma real es **127,7** (total 4.600,9 ≈ 4.600,8). Corregido.
    - También quité dos afirmaciones sin respaldo: el detalle de H12 ("la imagen trae otra versión") y "al pararse" en los SIGKILL.
15. **Anclas rotas:** `diseno-red/{l2-fallback,l3-switch}/README.md` enlazaban a `../../README.md#estado-de-validación`, sección que ya no existe. Se reescribió la frase.
16. **PR #33** creado y fusionado (`93b106d`).
17. **Encuesta de restos (tras la fusión, para este traspaso)**: `git grep -c` sobre el sistema vivo. Resultados en la Tabla 5. De ahí salió H20.

## Key Decisions

- **Grupo B se conserva como anexo** (`diseno-red/`), porque es contenido de la Entrega 1 (VLANs, switch, matriz). Rechazado: borrarlo.
- **No fusionar los 3 compose** (E = solo renombrar). Motivo: es el cambio más arriesgado sobre algo recién verificado, y los `docker/pcN-*` son la agrupación por departamento que describe la Entrega 1. **El nuevo encargo dice "consolidarlo": hay que preguntar si ahora sí se fusiona** (ver Open Questions). No hay que suponerlo.
- **Mantener `name: reservaviva-smoke`**: un nombre nuevo crea volúmenes nuevos y obliga a reinicializar (~30 min; OpenVPMS 5 min de esquema, ERPNext ~15 min de sitio).
- **`scripts/ip-gestion.sh` al anexo, no a la papelera**: el anexo que se conserva lo necesita.
- **H19 se arregla en `levantar-sistema.sh`**, no con un servicio compose nuevo. El `deploy.sh` ya lo hacía así, con `docker exec` tras el arranque. Rechazado: añadir un contenedor "init" (más superficie, y cambia el `compose config`).
- **Las actas borradas se citan por `git show <commit>:<ruta>`** donde son procedencia, en vez de dejar enlaces rotos o borrar la procedencia.
- **PR nuevo (#32) en lugar de reabrir o editar #31**: #31 ya estaba fusionado sin `10bac21`.
- **No descargar `nicolaka/netshoot` sin permiso**: descargar requiere la aprobación explícita del usuario.
- **Commits por tanda con "COMO RECUPERARLO"** en el mensaje (`git checkout <commit> -- <ruta>`), como pedía el plan.

## Evidence & Data

### Tabla 1: Commits de esta sesión (todos en master)

| Commit | Qué | PR |
|---|---|---|
| `20f65e7` | H18: `esperar_apps()` reintenta el login correcto; excepciones como `None <tipo>: <msg>` | #32 |
| `d9f81e5` | merge de #32 | — |
| `cceb54c` | H19: `crear_admin_pretix()` en `levantar-sistema.sh` | #33 |
| `95e0da4` | grupo A borrado; `ip-gestion.sh` → `diseno-red/comun/`; referencias corregidas | #33 |
| `ea55bf7` | B → `diseno-red/`; C y D borrados; procedencias vía `git show` | #33 |
| `d57a50f` | `pruebas/smoke-test-3-pcs` → `sistema/`; guiones sin "NO VERIFICADO" | #33 |
| `9141feb` | `README.md` reescrito; `docs/resultados-un-host.md` | #33 |
| `93b106d` | merge de #33 (2026-09-26T23:28:07Z) | — |

Anteriores de la cadena, ya en master: `596e772` (H2+H13), `6a07251` (verificar), `624b81f` (H11), `b5031c7` (H17), `4088c14` (pool 128M), `191f5ca` (gunicorn 2), `4284ccd` (CATALINA_OPTS), `bb70328`+`3691d36` (H16), `b9a5d41`/`7a6c3f1`/`d3eb139` (docs de hrms), `5c09945` (levantar-sistema) y `10bac21` (handoff seq 5, `--rapido`, KeyError 99).

**Commits de recuperación:**
- `cceb54c`: todo el grupo A existe.
- `95e0da4`: existen los grupos C y D, y los handoffs seq 1-4.
- `93b106d`: existen el handoff y el plan del seq 5.

### Tabla 2: Decisiones del usuario sobre los grupos (AskUserQuestion, 26/09)

| Pregunta | Opciones ofrecidas | Respuesta |
|---|---|---|
| ¿Fusionar el PR #32 antes del refactor? | Merge now (Rec.) / Don't merge yet | **Merge now** |
| B: diseño de red | Keep as an annex (Rec.) / Delete it | **Keep as an annex** |
| C: paquete offline | Delete it (Rec.) / Keep it to adapt later | **Delete it** |
| D: historial | Keep only the latest (Rec.) / Keep everything / Delete all of it | **Keep only the latest** |
| E: reestructurar | Only rename the harness (Rec.) / Rename and merge the compose files / No restructuring | **Only rename the harness** |

### Tabla 3: Pasadas de `verificar` y validaciones

| Cuándo | Qué | Resultado |
|---|---|---|
| 26/09 17:18 | `verificar --sin-persistencia` (seq 5) | 192 PASS / 28 INFO / 1 FAIL (deliberado) |
| 26/09 17:22 | `verificar` completo, sin H18 (seq 5) | 91 PASS / 1 FAIL (caso 4a `status=None`) |
| 26/09 17:47 | `verificar` completo, con H18 | **92 PASS / 0 FAIL / 14 INFO, RC=0** (`verificacion-20260926-174700.txt`) |
| 26/09 ~17:55 | `arrancar` tras H19 (sistema arriba) | RC=0; `[00:28] sanos 25/25`; "Listo: admin@reservaviva.local (admin@localhost eliminado)" |
| ~17:57 | Usuarios de Pretix | `[('admin@reservaviva.local', True)]`, `check_password: True`; 2ª ejecución idempotente |
| ~17:57 | `test-reanudable.sh` / `test-create-site.sh` | TODO PASA / TODO PASA |
| ~18:05 | `levantar-sistema.ps1 preparar` tras la Fase 2 | RC=0; zona serial 2026092618 |
| ~18:10 | `compose config` antes/después del renombrado | 869 líneas, `diff` vacío |
| 26/09 18:16 | `arrancar` desde `sistema/` | RC=0; `[00:31] sanos 25/25` |
| 26/09 18:17 | `verificar` completo desde `sistema/` | **92 PASS / 0 FAIL / 14 INFO, RC=0** (`verificacion-20260926-181713.txt`) |
| todas | `docker.service` `ExecMainStartTimestamp` | 17:01:17 (-05) antes = después |

**Desglose de las 14 INFO** (sacado de `sistema/resultados/verificacion-20260926-181713.txt`; en el informe aparecen dos veces, una en el bloque y otra en el RESUMEN, y por eso la pasada rápida contaba 28):

| # | INFO | Significado |
|---:|---|---|
| 12 | `<app> -> <otra app>@vlan99 (otra app, por la VLAN de infraestructura)`, las 12 parejas de openvpms-app, pretix-web, inventree-app y erpnext-backend | Hallazgo previsto: vlan99 es un único dominio L2. En el diseño de 3 PCs lo corta la matriz de firewall de PC-3; en un host no hay nada que lo corte |
| 1 | `los nombres dns/ntp/ldap apuntan al contenedor que los sirve` → `dns: la zona dice 10.10.99.10, el contenedor real esta en 10.10.99.11` y `ntp: la zona dice 10.10.99.10, … 10.10.99.12` | **H21**: la zona usa `IP_PC3` para los tres |
| 1 | `chronyc sources (contexto: se espera 127.127.1.1 sin alcanzar; el reloj local lo aporta 'local stratum')` | Contexto de H11, no es un defecto |

**Hueco del test:** `bloque_dns` solo compara con la IP real los nombres `dns`, `ntp` y `ldap`. **No compara** `pretix`, `inventree`, `openvpms` ni `rrhh`. Por eso H21 (`pretix` → IP de inventree 10.10.30.10) no aparece en ningún INFO. Si se corrige la zona, conviene ampliar ese bloque para que cubra los 7 nombres, en vez de fiarse de que "no hay INFO".

**Comprobación hecha para este traspaso:** `grep -c IFACE config-antes.yml` = **0**. Ningún servicio usa `IFACE` en la configuración resuelta, así que es un resto muerto de `test.env`.

### Tabla 4: Inventario de ficheros

| Momento | Ficheros versionados |
|---|---:|
| Inicio del refactor (master `d9f81e5`) | 112 |
| Tras el grupo A (`95e0da4`) | 83 |
| Tras B/C/D (`ea55bf7`) | 69 |
| Tras E + docs (`9141feb`) | 70 (+ `docs/resultados-un-host.md`) |
| Tras este traspaso | 70 (−2 del seq 5, +2 de este) |

Por carpeta ahora: `diseno-red/` 35, `sistema/` 11, `docker/` 14, `docs/` 3, `scripts/` 1, raíz 6 (`.gitattributes`, `.gitignore`, `README.md` y los 3 `levantar-sistema.*`) y `plans/handoffs/` 2.

### Tabla 5: Restos del diseño de 3 PCs en el sistema VIVO (`git grep -c`, 26/09 tras la fusión)

| Patrón | Dónde (apariciones) | Qué significa en un host |
|---|---|---|
| `IP_PC[123]` | pc1 compose 4, pc2 compose 10, pc3 compose 1, zona `.tpl` 8, `levantar-sistema.sh` 2, `sistema/README.md` 1, `test.env` 3 | "IP LAN de PC-x". En un host, `IP_PC3=10.10.99.10` (openldap) y `IP_PC2=10.10.30.10` (inventree) |
| `PUBLISH_IP` / `DNS_BIND_IP` | pc1 1, pc2 2, pc3 4, `test.env` 1, `verificar_arquitectura.md` 1 | Vale `127.0.0.1`; sigue siendo útil (publicar solo en localhost), pero los comentarios hablan de "IP LAN de PC-3" |
| `IFACE` | `test.env` 1 (`IFACE=eth0`) | Resto de macvlan. Ningún compose lo usa (comprobar antes de quitarlo) |
| `PC-[123]` | README 1, pc1 5, pc2 9, pc3 5, `named.conf` 1, zona 4, docs 3, `levantar-sistema.sh` 6, `generar-certificados.sh` 3, `test.env` 2, `verificar_arquitectura.{md,py}` 3+3 | Etiquetas y comentarios |
| `NO VERIFICADO` | pc1 compose 1, pc3 compose 1 | Obsoleto: el sistema está verificado |
| `Docker Desktop` | README 2, resultados 2, `.ps1` 6, `.sh` 5, `test.env` 1 | Legítimo en el lanzador (modo Desktop + Git Bash); en `test.env` es un comentario viejo |
| `\.env\b` | los 3 compose (3/8/5), `levantar-sistema.sh` 5, `sistema/*` | Mensajes `:?definir X en .env`: en un host el fichero es `sistema/test.env` |
| `smoke` | `test.env` 9, `ldaplogin.py` 2, `.ps1` 2 y otros | Nombre de proyecto (se mantiene) y claves `Smoketest-…` |
| `NET_(MEDICA\|…\|INFRA)` | 46 en `docker/` y `sistema/` | Subredes parametrizables "si chocan con la LAN del laboratorio" |
| CA copiada a pc1/pc2 | `generar-certificados.sh:99` (`for pc in pc1-medica pc2-operaciones`) y `:121` | En un host bastaría un solo `certs/`, montado desde pc3 o desde una ruta común |
| overrides `!override` | `sistema/override-pc{1,2,3}.yml` redefinen las redes como bridge (ya lo son en los compose) y añaden las IP de vlan99 | Duplicación heredada de cuando los compose eran macvlan |

### Tabla 6: `test.env` (valores no secretos)

```
IFACE=eth0
IP_PC3=10.10.99.10      # comentario: "la de openldap en el bridge vlan99_infra"
IP_PC2=10.10.30.10      # = inventree-app en vlan30 (!)
PUBLISH_IP=127.0.0.1
DNS_BIND_IP=127.0.0.1
OPENVPMS_PORT=18080  ERPNEXT_PORT=18081  PRETIX_PORT=18082  INVENTREE_PORT=18083
LDAP_PORT=1389  LDAPS_PORT=1636  DNS_PORT=1053  NTP_PORT=1123
PRETIX_ADMIN_EMAIL=admin@reservaviva.local
# secretos (no copiar a informes): *_DB_*PASSWORD, *_ADMIN_PASSWORD, LDAP_ADMIN_PASSWORD, *_LDAP_BIND_PASSWORD
```

### Tabla 7: IP del sistema (verificadas por el bloque de prerrequisitos de `verificar`)

| Servicio | VLAN propia | vlan99 |
|---|---|---|
| openvpms-app | 10.10.10.10 | 10.10.99.24 |
| pretix-web | 10.10.20.10 | 10.10.99.21 |
| inventree-app | 10.10.30.10 | 10.10.99.22 |
| erpnext-backend | 10.10.40.11 | 10.10.99.23 |
| openldap | — | 10.10.99.10 |
| dns-interno | — | 10.10.99.11 |
| ntp-interno | — | 10.10.99.12 |

La zona (`db.reservaviva.local.tpl` + `generar_zona` de `levantar-sistema.sh`) sustituye `IP_PC1=10.10.10.10`, `IP_PC2=10.10.30.10` e `IP_PC3=10.10.99.10`. Resultado:
- `dns`, `ldap`, `ntp` y `rrhh` → .99.10.
- `openvpms` → .10.10.
- `pretix` e `inventree` → .30.10. **`pretix` apunta a la IP de inventree.**

### Tabla 8: RAM por contenedor (sistema completo, `docker stats`, 26/09 17:28, del seq 5)

| Contenedor | MiB | | Contenedor | MiB |
|---|---:|---|---|---:|
| inventree-worker | 998,4 | | erpnext-queue-long | 90,7 |
| openvpms-app | 829,8 | | erpnext-queue-short | 83,5 |
| pretix-web | 651,5 | | erpnext-scheduler | 72,2 |
| openvpms-db | 437,2 | | pretix-db | 48,7 |
| pretix-worker | 431,7 | | inventree-db | 36,6 |
| inventree-app | 423,9 | | erpnext-websocket | 28,9 |
| erpnext-backend | 192,3 | | openldap | 28,6 |
| erpnext-db | 176,7 | | dns-interno | 25,6 |
| pretix-cron | 13,2 | | erpnext-redis-queue / -cache | 10,3 / 6,8 |
| erpnext-hr (nginx) | 5,9 | | ntp-interno / pretix-redis | 4,6 / 3,8 |
| **TOTAL 22** | **4.600,8** | | | |

En el host cuesta unos 5,7 GB (factor ~1,23 GB libres por GiB de stats). El umbral del `.ps1` es 6,9 GB libres; `-Forzar` lo salta. El peor momento del arranque en frío dejó 157 MB disponibles y 647 páginas/s.

### Tabla 9: Arranque en frío de aplicación (seq 5, `.\levantar-sistema.ps1 -Forzar -TimeoutMin 60`)

| Hito | Hora |
|---|---|
| Inicio (libre 5,57 GB → AVISO, sigue por `-Forzar`) | 17:01:13 |
| 22 en marcha + 3 Exited(0) | 17:06:29 |
| OpenVPMS: "Database 'openvpms' updated … in 00:05:04.488" | 17:07-17:12 |
| Peor memoria: 157 MB disponibles, 647 páginas/s | 17:08:55 |
| Tomcat despliega `openvpms.war` | 17:14:45 |
| FIN, RC=0, 25/25 (15 min 45 s) | 17:16:58 |

### Tabla 10: Estado de los defectos

| ID | Qué | Estado |
|---|---|---|
| H1, H2, H3/H4, H11, H13, H14, H15, H16 | (seq 1-5) | arreglados y validados |
| H12 | cita de OpenLDAP 2.6 en la bibliografía de la Entrega 1 | **abierto** (documentación) |
| H17 | `start_period` de openvpms-db | arreglado; **el frío con volúmenes vacíos no se ha repetido** |
| H18 | carrera del caso 4a de `ldaplogin.py` | arreglado (`20f65e7`); la rama de reintento no se ejercitó |
| H19 | un host sin administrador de Pretix; `admin@localhost`/`admin` vivo | **arreglado** (`cceb54c`), validado en vivo |
| H20 | `IP_PC2` = IP de InvenTree, usada como URL y `Host` de Pretix | **abierto (nuevo)**; efecto en el navegador sin comprobar |
| H21 | zona: `dns`/`ntp` → IP de openldap, `pretix` → IP de inventree | **abierto**; `verificar` ya lo reporta como INFO |

### Tabla 11: Documentación existente y huecos (para la fase de documentación)

| Documento | Líneas | Qué cubre | Hueco para "un host" |
|---|---:|---|---|
| `README.md` | 110 | Qué es, arranque, acciones, qué demuestra `verificar`, mapa, anexo, LDAP por app | Es la portada, no una referencia. Remite a documentos que aún no existen (arquitectura, operación) |
| `docs/resultados-un-host.md` | 87 | Arranque, RAM, pasadas de `verificar`, pendientes | Actualizar tras cada regresión. Los pendientes viven aquí |
| `docs/integracion-ldap-erpnext-inventree.md` | 29 | LDAPS en ERPNext e InvenTree (probada el 19/09) | Todavía cita el "arnés"; no describe la CA ni las cuentas de servicio |
| `docs/ldap-pretix-openvpms.md` | 98 | Por qué Pretix y OpenVPMS no usan LDAP | Correcto |
| `sistema/README.md` | 18 | El arnés y su uso manual | Corto; todavía habla de "macvlan -> bridge" |
| `sistema/verificar_arquitectura.md` | 93 | Qué verifica y cómo leerlo | Sus "hallazgos previstos" cambian si se arregla H21 |
| `docker/pc3-administracion-infra/ldap/README.md` | 19 | Árbol LDAP y usuarios de prueba (LDIF: ACL 11 líneas, estructura 28, usuarios 41) | No hay un documento de seguridad que junte CA, ACL, cuentas de servicio y secretos |
| `diseno-red/*` | 103 + 159 + 66 | Diseño de 3 equipos (anexo) | Se queda como está |
| **No existe** | — | **Arquitectura de un host**: servicios, redes (Tabla 7), dependencias, flujos (login LDAP, DNS, NTP), puertos (Tabla 6) | Hueco principal |
| **No existe** | — | **Operación**: arrancar, detener, reiniciar tras reinicio del PC, borrar, logs, qué hacer si algo queda unhealthy, trampas de WSL (Anexo A) | Hueco principal: hoy está repartido entre el README y los handoffs borrados |
| **No existe** | — | **Seguridad y credenciales**: CA interna, LDAPS, ACL de servicio, dónde están las claves (`test.env`), H19, rotación | Hueco |
| **No existe** | — | **Guía por aplicación**: URL, usuario, qué hace cada app para su departamento, LDAP sí/no | Hueco (parte en el README) |

### Worktrees huérfanos (`git worktree list`, sin tocar)

```
D:/Proyectos/ProyectoFinak-docs                       703f5a6 [docs/consolidar-resultados-fase2]
D:/Proyectos/ProyectoFinak-juan                       9d3317c (detached HEAD)
D:/Proyectos/ProyectoFinak-ldap                       5b9af3e [feat/ldap-pretix-openvpms]
D:/Proyectos/ProyectoFinak-off                        9f58922 [feat/imagenes-offline]
D:/Proyectos/ProyectoFinak-pin                        8c602ce [chore/fijar-imagenes]
D:/Proyectos/ProyectoFinak-sim                        8797307 [feat/simulador-matriz-segmentacion]
D:/Proyectos/UD.RedesCorporativaa.ProyectoFinak-ldap  3fdea43 [feat/ldap-erpnext-inventree]
D:/Proyectos/UD.RedesCorporativaa.ProyectoFinak-red   9d3317c [feat/perfiles-l2-l3-red]
```

### Ficheros de datos de esta sesión (scratchpad, NO versionados)

Directorio: `C:\Users\jafet\AppData\Local\Temp\claude\D--Proyectos-UD-RedesCorporativaa-ProyectoFinak\dd3ee9cd-d282-4211-8aa6-837091517da9\scratchpad\`

- `verificar.log`: la pasada de 17:47 (92/0).
- `fase3-arrancar.log` y `fase3-verificar.log`: la regresión de la Fase 3 (leer con `tr -d '\000'`).
- `config-antes.yml` y `config-despues.yml`: el `docker compose config` resuelto antes y después del renombrado (869 líneas, idénticos). **Son la línea base para comparar cualquier cambio de configuración de la Fase 1 del plan nuevo.**
- `pr-body.md`, `pr-body-final.md` y `pr33.md`: cuerpos de los PR #32 y #33.
- Informes del guion (gitignorados): `sistema/resultados/verificacion-20260926-{171805,172430,174700,181713}.txt`.

## Code Analysis

- **`levantar-sistema.sh`** (400 líneas, LF, solo ASCII, `set -euo pipefail`).
  - Variables: `RAIZ`, `ARNES="${RAIZ}/sistema"`, `ENV_FILE=test.env`, `PROYECTO="reservaviva-smoke"` y `MARCA_SESION`.
  - Funciones: `dc()` = `docker compose --env-file "${ENV_FILE}"` (se ejecuta desde `ARNES`); `valor_env NAME DEFAULT` lee `${ARNES}/${ENV_FILE}`; `comprobar_requisitos`, `comprobar_memoria`, `preparar_certificados`.
  - **`generar_zona`** (~línea 137) usa `ip1=10.10.10.10 ip2=10.10.30.10 ip3=10.10.99.10` **fijos**, más `sed` sobre la plantilla. Es aquí donde se decide lo de la Tabla 7.
  - Otras: `validar_compose`, `preparar_imagen_openvpms`, `preparar`, `esperar_sano`, **`crear_admin_pretix`** (nueva) y `accesos` (con las etiquetas "PC-1 Medica"…).
  - Acciones: `accion_{arrancar,preparar,estado,verificar,detener,borrar}`.
- **`crear_admin_pretix()`:** `valor_env PRETIX_ADMIN_EMAIL`/`PRETIX_ADMIN_PASSWORD`. Bucle `for intento in 1..6` con `ADM_EMAIL=… ADM_PASS=… docker exec -i -e ADM_EMAIL -e ADM_PASS pretix-web python -m pretix shell <<'PY'`. Si falla del todo, `fallo`.
- **`sistema/docker-compose.yml`:** `name: reservaviva-smoke`, con tres `include: - path: [../docker/pcN-*/docker-compose.yml, override-pcN.yml]` y `env_file: test.env`.
- **`sistema/override-pc{1,2,3}.yml`:**
  - Redefinen `vlanXX_*: !override` como `driver: bridge` con su subred y gateway `.1`.
  - Conectan cada app a `vlan99_infra` con `ipv4_address` (.24/.21/.22/.23).
  - Requiere Compose ≥ 2.24.4, por el `!override`.
- **`sistema/verificar_arquitectura.py`** (609 líneas):
  - `AQUI = Path(__file__).resolve().parent`, `RAIZ = AQUI.parent` y `ZONA = RAIZ / "docker/pc3-administracion-infra/bind/zones/db.reservaviva.local"`.
  - `bloque_dns` compara la zona con las IP reales (línea ~403: `dif = [...]`).
  - El autotest (línea ~568) espera `["10.10.99.10"]`. **Si cambia la zona, revisar ese autotest y la expectativa del bloque DNS.**
- **`sistema/ldaplogin.py`:**
  - `esperar_apps(limite=1500)` tiene dos bucles: clave errónea primero y login correcto hasta 200 después.
  - `http()` devuelve `(None, texto)` si la primera palabra no es un número.
  - El caso 4 hace `docker compose down` + `up -d` **sin** `--env-file` (equivalente, porque cada `include:` carga `test.env`).
- **`scripts/generar-certificados.sh`:**
  - Salida en `docker/pc3-administracion-infra/certs/` (`ca.crt`, `ca.key`, `ldap.crt` y `ldap.key`).
  - Línea 99, `for pc in pc1-medica pc2-operaciones`, copia `ca.crt` solo si `cmp` dice que cambió.
  - Tiene variables `GENERADA_CA`/`GENERADO_LDAP` y aplica `chmod` solo a lo generado en esa ejecución (fix uid 911 del seq 5).
- **Compose de PC-2:**
  - Usa `PRETIX_PRETIX_URL: http://${IP_PC2}:${PRETIX_PORT}` en 3 servicios (web, worker y cron) y la sonda `Host: ${IP_PC2}`.
  - `INVENTREE_SITE_URL: http://${IP_PC2}:${INVENTREE_PORT}`.
  - `extra_hosts: ldap.reservaviva.local:${IP_PC3}`, porque los contenedores usan el DNS de Docker, no bind9.
  - Monta `./certs/ca.crt:/certs/ca.crt:ro`.
- **Compose de PC-1:** `LDAP_HOST`/`DNS_HOST`/`NTP_HOST: ${IP_PC3}`.
- **Compose de PC-3:** usa `${NET_INFRA:-10.10.99}.10` en `extra_hosts` (ya es "nativo de un host") y publica LDAP/LDAPS/DNS/NTP/ERPNext en `PUBLISH_IP`/`DNS_BIND_IP`.

## Files Changed

### En master (esta sesión, PR #32 y #33)
- `sistema/ldaplogin.py`: H18 y docstring "verificado".
- `levantar-sistema.sh`: `crear_admin_pretix()`, `ARNES=sistema` y comentarios.
- 29 ficheros borrados del grupo A. `scripts/ip-gestion.sh` → `diseno-red/comun/ip-gestion.sh`.
- `despliegue/**` → `diseno-red/**`; `diagramas/**` → `diseno-red/diagramas/**`; `docs/arquitectura-3-equipos-departamentos.md` → `diseno-red/`.
- Borrados (C/D): `scripts/{preparar,instalar}-paquete-offline.*`, `docs/paquete-offline-fase0.md`, `docs/prueba-smoke-test-resultados.md`, `docs/auditoria-coherencia-documental.md` y 9 handoffs/planes antiguos.
- `pruebas/smoke-test-3-pcs/**` → `sistema/**`: `docker-compose.yml` (include `../docker/`), `verificar_arquitectura.py` (`RAIZ`), `README.md` y `verificar_arquitectura.md`.
- `docker/pc{1,2,3}/docker-compose.yml`: cabeceras "SE ARRANCA EN UN SOLO HOST…" y `(ver test.env del arnés)`.
- `docker/pc3-administracion-infra/bind/zones/db.reservaviva.local.tpl`: comentario (lo genera `levantar-sistema.sh`).
- `docs/ldap-pretix-openvpms.md` y `docs/integracion-ldap-erpnext-inventree.md`: referencias.
- `README.md` (reescrito) y `docs/resultados-un-host.md` (nuevo).
- `.gitignore`: `sistema/resultados/`.

### En esta rama (`docs/consolidacion-un-host`, commit del traspaso)
- Borrados: `plans/handoffs/HANDOFF_…_un-host-plug-and-play-verificado_2026-09-26.md` y `PLAN_…` (petición del usuario).
- Nuevos: este handoff y `PLAN_standalone-9e6e8d31_consolidacion-un-host-documentacion_2026-09-26.md`.

### Fuera del repo
- Memoria `proyecto-consolidado-en-un-host.md`: añadido el párrafo de decisiones B-E (26/09).

## User Feedback & Preferences (REQUIRED)

- **Esta sesión:**
  - Pegó el paste prompt del seq 5 ("Build") y eligió **"Merge now"** para el PR #32.
  - Aceptó las 4 recomendaciones de B-E.
  - Pidió crear PR dos veces con el botón "Create PR" (listo para revisión, **no borrador**).
  - Fusionó los PR él mismo (o fuera de la sesión) antes de que yo lo hiciera.
- **Encargo vigente (argumento de `/handoffplan`):** *"Elimina el anterior handoff; el objetivo actual es consolidar todo lo de un host eliminando lo que no corresponda, y consolidarlo y crear los documentos de la documentación correspondiente"*.
- **De sesiones anteriores, siguen vigentes:**
  - *"usa los agentes, no operes"* y *"tú eres el cerebro de la operación pero debes ser detallado"* (memoria fijada). Esta sesión no había agentes peer y ejecuté yo.
  - *"sin tener que sacrificar nada del entregable"*: resolver con configuración, no quitando funciones.
  - *"si al día de mañana necesitamos algo lo restauramos y listo"*: borrar es aceptable si git lo conserva y se anota cómo recuperarlo.
  - *"minimizar la curva de aprendizaje del proyecto"*: es el motivo de todo el refactor, y de ahí el peso de la documentación.
  - *"clono repo ejecuto script y listo corriendo el sistema"*: el plug and play no se puede romper.
  - *"Busca alguna solución plug and play; si no existe, la última opción sería construir nosotros mismos"*.
  - El usuario pregunta a menudo *"¿qué nos hace falta?"*: quiere listas concretas de qué depende de él y qué de los agentes.
- **Restricciones de seguridad vigentes:**
  - Las contraseñas de `test.env` nunca van a informes, commits ni logs.
  - Rotarlas si el repositorio se hace público.
  - No usar `wsl --set-sparse --allow-unsafe`, `docker system prune -a` ni `Stop-Process` sobre Docker.
  - Ni `down -v` ni `levantar-sistema borrar` sin permiso: los volúmenes tienen el sistema inicializado.

## Anexo A: Trampas del entorno (vigentes; todas pagadas al menos una vez)

| # | Trampa | Qué hacer |
|---|---|---|
| 1 | `vmIdleTimeout` comentado en `.wslconfig` = 60 s: la VM se apaga | Ya está en `7200000`. Para aplicar cambios: `wsl --shutdown`, **con permiso** |
| 2 | Sin ninguna sesión WSL, `docker.service` se desactiva y **mata los contenedores** | `levantar-sistema.ps1` mantiene `reservaviva-keepalive` |
| 3 | Cada `wsl.exe` nuevo reactiva el demonio y contamina las mediciones | Medir desde una sesión persistente |
| 4 | `wsl.exe -d X -- cmd` pasa por el shell del usuario (expande `$var`) | `wsl.exe -d X --exec bash -c '…'` |
| 5 | Git Bash convierte los argumentos que empiezan por `/` | `MSYS_NO_PATHCONV=1`; o `--cd "D:\\…"` con ruta de Windows |
| 6 | `Start-Process wsl.exe -ArgumentList '-d "Ubuntu-24.04"'` (con comillas) sale con −1 | Sin comillas |
| 7 | PS 5.1 + `$ErrorActionPreference='Stop'` + stderr nativo = error terminante | `'Continue'` y `$LASTEXITCODE` |
| 8 | Logs mezclados UTF-8/UTF-16 | `tr -d '\000'` antes de `grep` |
| 9 | `up -d` no reconstruye la imagen `build:` de openvpms | `levantar-sistema.sh` hace `dc build openvpms-app` siempre |
| 10 | osixia/openldap se apropia (uid 911) de los certificados montados | Arreglado en `generar-certificados.sh` (`5c09945`) |
| 11 | El harness mata tareas de fondo con poca memoria | No relanzarlas sin permiso del usuario |
| 12 | **(nueva)** Copia de trabajo **CRLF** (`core.autocrlf=true`); `.sh`, Dockerfile, `.service` son LF por `.gitattributes`; `levantar-sistema.cmd` es CRLF | Editar con un helper que respete el fin de línea original; `assert count==N` antes de escribir |
| 13 | **(nueva)** `git mv <dir>` mueve también los ficheros sin versionar del directorio (p. ej. `resultados/`) | No hace falta `mv` aparte |
| 14 | **(nueva)** `Write` sobre un fichero modificado desde la última lectura falla | `Read` antes de `Write` |
| 15 | **(nueva)** `git grep` de rutas tras mover: los `.json`/`.html` de diagramas contienen rutas fijadas a una revisión | Excluirlos (`':!diseno-red/**/diagramas/*.json'`…) y no reescribirlos |
| 16 | **(nueva)** `verificar` y `arrancar` en segundo plano: el log puede parecer parado en `[00:07]` | Es normal: `erpnext-ldap-config` se reejecuta en cada `up` |

## Anexo B: Errores del coordinador en esta sesión (para no repetirlos)

| Qué hice mal | Cómo se detectó | Lección |
|---|---|---|
| El paste prompt decía "actualizar la descripción del PR #31 y preguntar si se fusiona", y lo di por abierto | `gh pr view 31` → MERGED | Comprobar el estado real de los PR antes de planear sobre ellos. Los PR de este proyecto los fusiona el usuario sin avisar (pasó con #31, #32 y #33) |
| El handoff del seq 5 decía que había cambios "sin commitear" | `git status` limpio: ya estaban en `10bac21` | El handoff describe el estado *antes* de su propio commit |
| Aceptar la lista del grupo A tal cual (incluía `scripts/ip-gestion.sh`) | `git grep` antes de borrar: lo usa el anexo | Buscar dependencias de cada ruta antes de `git rm`, aunque el plan diga que "no se discute" |
| Dar por hecho que el sistema de un host tenía el administrador de Pretix porque el script lo anunciaba | Leer `deploy.sh` antes de borrarlo y consultar `User.objects.all()` en vivo | Antes de borrar un script, leer **qué hacía** que nadie más haga (H19) |
| Editar ficheros CRLF con un reemplazo que asumía LF | `AssertionError … 0` (sin escritura parcial) | Helper con `newline=''` + `assert count==N` antes de escribir |
| Esperar 3 apariciones de un enlace y había 4 | `assert` → abortó sin escribir | Contar primero (`grep -c`) y luego reemplazar |
| Fila "resto" de la tabla de RAM: 137,6 (mal) | Repasar la suma: 127,7 | Recalcular siempre los totales que se escriben a mano |
| Escribir en `resultados-un-host.md` detalles no respaldados (causa de H12, "al pararse" en los SIGKILL) | Revisión propia antes de commitear | Solo lo que dice la evidencia; lo demás, "sin analizar" |
| `mv resultados` tras `git mv` del directorio | "cannot stat" (inofensivo) | `git mv <dir>` mueve también lo no versionado |

## Anexo C: Protocolo de validación (vigente)

- Toda la regresión va con **`levantar-sistema verificar`** (completo por defecto): referencia **92 PASS / 0 FAIL**, RC=0 y `ExecMainStartTimestamp` igual antes y después.
- Para cambios de configuración, comparar primero `docker compose --env-file test.env config` (desde `sistema/`) con `config-antes.yml` del scratchpad. **Solo deben cambiar las líneas que se pretenden.**
- `arrancar` sobre el sistema arriba tarda ~1 min. `verificar` tarda ~14 min (incluye `down` + `up -d`). Lanzarlos con la tarea de fondo de la herramienta, no con `&` ni `nohup`.
- No usar `down -v` ni `borrar`. `docker compose stop` (no `down`) libera memoria conservándolo todo.
- Memoria del host: umbral de 6,9 GB libres para arrancar en frío. Con el sistema ya arriba, el script no comprueba nada.
- Las suites sin Docker son `bash docker/pc1-medica/openvpms/test-reanudable.sh` y `bash docker/pc3-administracion-infra/test-create-site.sh`.

## Anexo D: `.wslconfig` (fuera del repo, `C:\Users\jafet\.wslconfig`)

```ini
[wsl2]
memory=8GB
processors=6
swap=4GB
swapFile=C:\\Users\\jafet\\WSL\\swap.vhdx
localhostForwarding=true
dnsTunneling=false    # Tailscale rompe el túnel DNS
firewall=true
vmIdleTimeout=7200000 # 2 h
[experimental]
autoMemoryReclaim=gradual
hostAddressLoopback=true
```

## Where We're Going

1. **Preguntar el alcance (bloqueante)** con AskUserQuestion:
   - ¿"consolidarlo" incluye ahora **fusionar los 3 compose + overrides** en uno? La decisión del 26/09 fue "no".
   - ¿Renombrar `docker/pcN-*` a nombres por departamento, o conservarlos?
   - ¿Qué juego de documentos quiere? La propuesta está en el plan.
   - ¿Se limpian los 8 worktrees huérfanos?
2. **Consolidar la configuración viva** para un host, sin cambiar el comportamiento. Todo se compara contra `config-antes.yml` y se valida con 92/0:
   - Quitar `IP_PC2`/`IP_PC3`/`IFACE` y usar las IP o nombres reales de cada servicio (H20).
   - Arreglar la zona (H21).
   - Una sola CA montada.
   - Etiquetas y comentarios sin "PC-x".
3. **Escribir la documentación de un host** en `docs/`: arquitectura, operación y resolución de problemas (Anexo A), seguridad y credenciales, y aplicaciones y accesos. Enlazarla desde el README.
4. **Opcional, según la respuesta 1:** fusionar los compose, con el mismo nombre de proyecto y de redes, y un diff de `config`.
5. **Pendientes que sobreviven:**
   - H12 (cita) y H17 (frío con volúmenes vacíos).
   - La rama de reintento de H18 sin ejercitar.
   - Simuladores del anexo sin reejecutar (pedir permiso para `nicolaka/netshoot`).
   - Modo Docker Desktop sin probar.
   - `performance_schema`, `mem_limit` y los SIGKILL 137.

## Risks & Blockers

- **Cambiar `IP_PC2`/`IP_PC3` y la zona toca LDAP, DNS y la URL de Pretix a la vez.** Si `extra_hosts ldap.reservaviva.local` apunta mal, el login LDAP de InvenTree falla (caso 1). Mitigación: un cambio por commit, `compose config` diff y `verificar` tras cada tanda.
- **H20 puede estar enmascarado:** hoy `verificar` da PASS porque las sondas usan `Host` explícito. Cambiar `PRETIX_PRETIX_URL` puede cambiar qué `Host` acepta Pretix y romper su healthcheck (ya pasó en el seq 3 con H3/H4). Mitigación: comprobar el healthcheck y el navegador en `http://localhost:18082` antes de dar por bueno el cambio.
- **Fusionar compose (si se aprueba)** es el cambio más arriesgado sobre algo verificado. Mitigación: rama propia, mismo `name:` y mismos nombres de red (`verificar_arquitectura.py` los usa), y `config` diff.
- **Memoria del host:** cada `verificar` con `down`/`up` cuesta unos 14 min y deja la máquina lenta. Con el sistema ya arriba no se reinicializa nada.
- **Mover la CA** (una sola copia) cambia rutas de bind mount; si la ruta no existe, Docker crea un **directorio** vacío y LDAPS falla sin error claro. Mitigación: `test -s` del fichero en `preparar`, como hacía `deploy.sh`.

## Open Questions

- ¿"Consolidarlo" = fusionar los compose (revierte la decisión E del 26/09) o = limpiar la configuración manteniendo los 3 compose por departamento?
- ¿Qué documentos espera el usuario? ¿Para el entregable del curso (informe) o para quien clone el repo? ¿En Markdown en `docs/` o como Artifact/Doc?
- ¿Funciona Pretix bien en el navegador en `http://localhost:18082` con `PRETIX_PRETIX_URL=http://10.10.30.10:18082` (H20)? Sin comprobar.
- ~~¿`IFACE` lo lee algún servicio?~~ **Respondida:** no. Aparece 0 veces en el `compose config` resuelto, así que se puede quitar de `test.env` sin cambiar nada.
- ¿Se regeneran los diagramas del anexo (Archify) o se crea un diagrama nuevo de un host para la documentación?

## Quick Start for Next Session

```bash
# Contexto
cat plans/handoffs/HANDOFF_standalone-9e6e8d31_consolidacion-un-host-documentacion_2026-09-26.md
cat plans/handoffs/PLAN_standalone-9e6e8d31_consolidacion-un-host-documentacion_2026-09-26.md

# Ficheros clave
levantar-sistema.sh            # generar_zona (ip1/ip2/ip3 fijos), accesos, crear_admin_pretix
sistema/test.env               # IP_PC2, IP_PC3, IFACE (valores no secretos en la Tabla 6)
docker/pc2-operaciones/docker-compose.yml   # PRETIX_PRETIX_URL, extra_hosts, certs
scripts/generar-certificados.sh             # copia de ca.crt a pc1/pc2 (línea 99)
sistema/verificar_arquitectura.py           # bloque_dns (~377-404), autotest (~568)

# Línea base de configuración
C:\Users\jafet\AppData\Local\Temp\claude\D--Proyectos-UD-RedesCorporativaa-ProyectoFinak\dd3ee9cd-d282-4211-8aa6-837091517da9\scratchpad\config-antes.yml

# Estado
git status -sb && gh pr list --state open
powershell -File .\levantar-sistema.ps1 estado

# Siguiente acción
# AskUserQuestion: alcance de "consolidar" (fusionar compose sí/no), documentos deseados, worktrees.
```
