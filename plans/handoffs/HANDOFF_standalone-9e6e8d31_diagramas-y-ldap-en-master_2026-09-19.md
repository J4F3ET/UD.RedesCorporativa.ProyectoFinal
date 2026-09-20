# Laboratorio Reserva Viva: diagramas recuperados y LDAPS real en las apps — 4 PRs mergeados a master coordinando 3 sesiones

**Date:** 2026-09-19
**Status:** IN PROGRESS (Fases 1 y 2 completas y en master; Fase 4 y la regeneración del diagrama delegadas y en curso; Fase 3 bloqueada por hardware)
**Bead(s):** none (bd no está instalado en esta máquina: `bd: command not found`)
**Epic:** Proyecto final Redes Corporativas (UD) — Laboratorio "Reserva Viva"
**Chain:** `standalone-9e6e8d31` seq `2`
**Parent:** `HANDOFF_standalone-9e6e8d31_lab-3pcs-pruebas-reales_2026-09-19.md`
**Prior chain:** `HANDOFF_standalone-9e6e8d31_lab-3pcs-pruebas-reales_2026-09-19.md` > this

---

## Related Handoffs

- `HANDOFF_standalone-cad62bb5_smoke-test-consolidacion_2026-09-19.md` — handoff de la sesión par "Consolidación y prueba del proyecto" (sesión 65a096). Flujo de trabajo separado, NO padre de este archivo. Es el único par que SÍ está en master.
- `PLAN_standalone-cad62bb5_smoke-test-consolidacion_2026-09-19.md` — plan de esa misma sesión par.

## Since Last Handoff

El padre (seq 1) dejó 7 puntos en "Where We're Going". Esta sesión cerró dos de ellos por completo y movió un tercero:

- **Punto 5 (traer `diagramas/` y `pruebas/software-un-host/` a master) — HECHO.** Era la Fase 1 del plan. Ambos directorios están en master desde el merge del PR #4 (`6378076`), y los diagramas además se regeneraron contra el stack real.
- **Punto 2 (integrar LDAP en las apps) — HECHO A MEDIAS, Y ESO ERA EL RESULTADO CORRECTO.** ERPNext e InvenTree autentican por LDAPS con cadena verificada (PR #7, `9a7dba7`). Pretix y OpenVPMS quedaron descartados con evidencia (PR #5, `87da3c8`), que es exactamente lo que el plan autorizaba ("si una app no lo soporta limpiamente, documentarlo como limitación en vez de forzarlo").
- **Punto 6 (reflejar resultados en la documentación central) — HECHO.** PR #6 (`31a2824`) añadió la §9 al documento de resultados y, sobre todo, los enlaces a `diagramas/` que NO existían en ningún sitio.
- **Se respondió una de las Open Questions del padre:** "¿Qué apps deben autenticarse contra LDAP y con qué esquema?" → ERPNext con LDAP Settings de Frappe (ldap3) e InvenTree con `django-auth-ldap`, ambas por `ldaps://` con verificación de cadena contra la CA interna. Pretix y OpenVPMS: ninguno, por imposibilidad técnica documentada.
- **Se respondió otra:** "¿Se acepta portar `diagramas/` y `pruebas/software-un-host/` a master?" → sí, y `software-un-host` se conservó congelado como evidencia histórica en vez de borrarse.
- **Un riesgo del padre se materializó tal cual:** "imágenes públicas con tags móviles… mitigación posible: fijar tags/digests". Sigue sin mitigar; es justo lo que se acaba de delegar como Fase 4.
- **Trayectoria:** el proyecto pasó de "software validado, cero autenticación real" a "autenticación centralizada demostrada con controles negativos". Lo único que no se movió es la Fase 3 (hardware), que sigue bloqueada exactamente por lo mismo que en el seq 1.
- **Cambio de método, no de rumbo:** esta sesión dejó de ser ejecutora y pasó a coordinar tres sesiones paralelas (juan, pepe, yobana) por instrucción explícita del usuario. Ver "User Feedback & Preferences".

## Reference Documents

- `docs/arquitectura-3-equipos-departamentos.md` — diseño vigente (VLANs, matriz de segmentación, plan de pruebas). Desde el PR #6 enlaza los dos diagramas en §2 y §4.
- `docs/prueba-smoke-test-resultados.md` — fuente de verdad de lo probado. Ahora con §9 (ronda 5, integración LDAP).
- `docs/integracion-ldap-erpnext-inventree.md` — **NUEVO** (PR #7). Detalle de la integración que sí funcionó.
- `docs/ldap-pretix-openvpms.md` — **NUEVO** (PR #5). Por qué Pretix y OpenVPMS no se integran, con evidencia.
- `docker/pc3-administracion-infra/ldap/README.md` — **NUEVO** (PR #7). Usuarios de prueba y claves del directorio.
- `diagramas/README.md` — cómo regenerar los diagramas y qué límites tiene Archify.
- No existe CLAUDE.md ni ningún archivo BIBLE en este repo (verificado).

## The Goal

Entregar el laboratorio de red corporativa del zoológico "Reserva Viva" (curso Redes Corporativas, Universidad Distrital) repartido en **3 PCs por departamento**: PC-1 Médica (OpenVPMS, VLAN 10), PC-2 Operaciones (Pretix VLAN 20 + InvenTree VLAN 30) y PC-3 Administración e Infraestructura (ERPNext-HR VLAN 40 + OpenLDAP/DNS/NTP VLAN 99). El objetivo del curso no es que las aplicaciones arranquen —eso ya estaba probado al cerrar el seq 1— sino **demostrar una red corporativa segmentada**: VLANs reales sobre 802.1Q, una matriz que impide que las VLAN de negocio se hablen entre sí, y autenticación centralizada contra un directorio. El estado final deseado por el usuario sigue siendo plug-and-play: copiar `.env.example` a `.env`, un solo `deploy.sh` por PC, tutoriales para personas no técnicas y evidencia real que lo respalde.

Esta sesión cerró dos de las cuatro brechas que separaban el software validado de ese objetivo: la evidencia visual del diseño (los diagramas) y la autenticación centralizada real.

## Where We Are

- **`master` está en `31a2824`** con los cuatro PRs de esta sesión mergeados en el orden #4 → #5 → #7 → #6. Working tree limpio. Los merges los hizo esta sesión por instrucción explícita del usuario ("mergea los 4 PRs en ese orden").
- **PR #4 (`6378076`)** — `diagramas/` (5 archivos) y `pruebas/software-un-host/` (4 archivos) recuperados de la rama `claude/project-handoff-departments-g266yp` y actualizados. Dos commits deliberadamente separados: `07a2932` trae los archivos intactos, `104c39e` aplica los cambios, para que el diff sea revisable.
- **PR #5 (`87da3c8`)** — `docs/ldap-pretix-openvpms.md` (98 líneas, archivo único). Pretix y OpenVPMS evaluados y descartados. Ningún compose modificado.
- **PR #7 (`9a7dba7`)** — 10 archivos: bootstrap LDIF de OpenLDAP, integración LDAPS en ERPNext e InvenTree, variables nuevas y `docs/integracion-ldap-erpnext-inventree.md`.
- **PR #6 (`31a2824`)** — consolidación en `docs/prueba-smoke-test-resultados.md` (§9 nueva, §7 actualizado), `README.md` y `docs/arquitectura-3-equipos-departamentos.md`.
- **Los cuatro PRs no comparten un solo archivo.** Verificado cruzando los cuatro conjuntos con `comm -12` y `sort | uniq -d`: cero duplicados. No hubo trabajo rehecho ni conflictos.
- **Los cuatro enlaces cruzados resuelven** tras el merge (`diagramas/topologia-red.html`, `diagramas/flujo-datos-segmentacion.html`, `docs/ldap-pretix-openvpms.md`, `docs/integracion-ldap-erpnext-inventree.md`). Ese era el riesgo del orden de merge y no se materializó.
- **`diagramas/topologia-red.architecture.json`**: viewBox `[1390, 500]`, 15 componentes, 3 filas (y=150, 262, 374), 13 conexiones, 4 tarjetas de 2 ítems, 4 vistas guiadas, 19 referencias a código verificadas contra el commit `752e41f`.
- **`diagramas/flujo-datos-segmentacion.dataflow.json`**: viewBox `[880, 500]`, 4 etapas, 9 nodos, 10 flujos, 3 vistas guiadas. No declara evidencia de código.
- **Los dos HTML pasan 9/9 artifact checks de Archify**, composición `showcase` con 0 errores y 0 avisos, y `visual-check` sin desbordes en 1440×900, 1600×1000, 1920×1080 y 2048×1320, en tema claro y oscuro.
- **`docker/pc3-administracion-infra/docker-compose.yml` pasó de 282 a 342 líneas** con el PR #7 (servicio nuevo `erpnext-ldap-config`, más `extra_hosts` y volumen de CA en `erpnext-backend`). PC-3 tiene ahora 15 servicios.
- **`docker/pc2-operaciones/docker-compose.yml` tiene 168 líneas** y 6 servicios; solo cambió la sección `inventree-app` (+19 líneas de variables LDAP).
- **CONSECUENCIA: 6 de las 8 referencias del diagrama de topología a PC-3 quedaron apuntando a líneas históricas** (más 2 de PC-2 que yo no había detectado). No estaban rotas (apuntaban a blobs de `752e41f`, que existe), pero señalaban sitios equivocados. **Ya resuelto en el PR #8, abierto y verificado pero NO mergeado al cierre de esta sesión.**
- **PR #8 (`docs/regenerar-diagrama-topologia`)** — `MERGEABLE/CLEAN`, merge-base `31a2824`, 3 archivos, +29/−29. Re-pina la revisión y los 19 rangos, mete `erpnext-ldap-config` en el nodo agrupado (tag 9 → 10 servicios) y corrige la nota de la vista (10 → 12). Verificado de forma independiente por esta sesión: ver Tabla 1b.
- **Tres sesiones trabajando en paralelo, todas idle al cierre:** juan (`a37d32`), pepe (`a62f40`), yobana (`488494`). Las ramas remotas de los 4 PRs NO se borraron porque los tres tienen worktrees hermanos montados sobre ellas.
- **HALLAZGO NO RESUELTO: el handoff y el plan padre de esta cadena NO están en master.** `git ls-tree origin/master -- plans/handoffs/` solo devuelve los dos archivos de la cadena `cad62bb5`. `HANDOFF_standalone-9e6e8d31_*` y `PLAN_standalone-9e6e8d31_*` viven únicamente en la rama `docs/handoff-plan-lab-3pcs`. Es **exactamente el mismo fallo** que motivó la Fase 1 con los diagramas, y nadie lo ha arreglado.
- **Nada de macvlan, 802.1Q, `deploy.sh` completo ni el switch se ha probado todavía.** La máquina sigue siendo Windows 11 con Docker Desktop. Toda la validación de LDAPS se hizo en el arnés de un solo host con redes bridge.

## What We Tried (Chronological)

1. **Verificar el estado de partida (Fase 1)** — Hipótesis del plan: los diagramas faltan en master y el documento de arquitectura los enlaza, así que hay enlaces rotos. Resultado: la primera mitad cierta (`git ls-tree -r origin/master | grep -cE '^(diagramas|pruebas/software-un-host)'` → **0**), la segunda **falsa**: `git grep -n 'diagramas/' origin/master` no devolvía nada. Los enlaces vivían en la versión vieja del documento, que quedó en la rama muerta. Consecuencia: no había enlaces rotos que arreglar, había enlaces que **crear**, y en archivos que no me pertenecían por reparto. Se escaló al usuario y acabó siendo el PR #6.

2. **Rama y recuperación** — `git checkout master && git pull --ff-only` avanzó 14 commits (`280ad21` → `752e41f`). Rama `docs/recuperar-diagramas`, y `git checkout claude/project-handoff-departments-g266yp -- diagramas pruebas/software-un-host` trajo los 9 archivos. Sin conflictos.

3. **Primer spec de topología: demasiado ancho** — 16 componentes, viewBox `[1560, 620]`. `validate` falló primero por `repository-evidence/root-required`: el diagrama declara `meta.repository` y `sources`, así que Archify exige `--repo-root <repo>` o se niega a renderizar. Con `--repo-root` aparecieron **10 errores `clean-flow/endpoint-side-direction`**, 3 `layout/constraint` de etiquetas encima de nodos y 1 de separación entre etiquetas.

4. **Diagnóstico del enrutado** — Cuando dos conexiones salen hacia abajo del mismo nodo, el reparto automático de puertos infiere lados `left`/`right` pero genera segmentos verticales, y el validador lo rechaza. **Arreglo que funciona:** declarar `fromSide: "bottom"` y `toSide: "top"` explícitos en cada par vertical (`switch-vlan30`, `pretix-sql`, `pretix-cache`, `inventree-sql`, `inventree-jobs`). Las etiquetas encima de nodos se resuelven con `labelDy: 24`. Se acortó "tareas en segundo plano" → "cola de tareas" por separación insuficiente (2.5px contra un mínimo de 4).

5. **`composition/desktop-readability`: el límite de ancho** — Con viewBox 1560, a un viewport de 1440 el diagrama se escala a `availableDiagramWidth` 930 → factor 0.596 → el texto de contexto de 9px proyecta **5.37px**, bajo el mínimo de 6px. **Regla derivada: viewBox[0] ≤ ~1394.** Se recalculó toda la geometría a `[1390, 620]` y validó 9/9 a la primera.

6. **Diagrama de flujo: geometría fija del renderer** — El primer intento (3 etapas) dio etiquetas amontonadas. Al inspeccionar `renderers/dataflow/render-dataflow.mjs` apareció la causa: la geometría es **fija** — `leftX: 100`, `colGap: 215`, `stageW: 168`, `nodeW: 112`, `rowYs: [128, 242, 356, 470, 584]`, `stageBottomPad: 74`. Con 3 etapas el contenido solo ocupa ~586px de ancho, deje el viewBox que deje. Se reestructuró a **4 etapas y 9 nodos** (los 3 PCs de origen separados, switch, los 3 servicios de VLAN99, permitido y bloqueado), que es además más fiel.

7. **Corredores de 75px entre etapas** — Los flujos rectos de la fila central chocaban con los codos de los diagonales. La aritmética: el codo superior termina en y=258, el inferior arranca en y=284, así que una etiqueta a y=263–279 deja 5px por cada lado. **Arreglo: `labelDy: 13`** en los tres flujos rectos (`uplink-vlan2030`, `permitido-dns`, `dns-ok`) más acortar las etiquetas a ≤11 caracteres, que es lo que cabe en 75px. Validó 9/9.

8. **`deliver` OK pero `visual-check` FALLÓ — el error de método de la sesión** — Ambos diagramas entregaron con 9/9 checks, pero `visual-check` reportó desbordes verticales: topología 1037px contra 900 (1440×900) y 1119 contra 1000; el de flujo mucho peor, 1351px, y **1506 incluso a 2048×1320**, o sea que no cabía en ningún tamaño. Lección: **`deliver` con 9/9 no garantiza que la página quepa**; son dos comprobaciones distintas y hay que correr las dos.

9. **Comparar contra los originales en vez de adivinar** — En lugar de seguir ajustando a ciegas, se extrajeron los HTML originales de la rama vieja y se les pasó `visual-check`: **cabían perfectamente en los cuatro tamaños**, con `scrollHeight == innerHeight` exacto (el visor se auto-ajusta estrechando el ancho de lectura cuando puede). Sus viewBox eran `1360×500` (aspecto 2.72) y `1060×480` (2.21), contra mis 2.24 y 1.42. **Diagnóstico: el problema era la relación de aspecto y la longitud de las tarjetas, no el contenido.**

10. **Reflujo de la topología a 3 filas** — Se eliminó la cuarta fila (y=512) fusionando `erpnext-data` y `erpnext-workers` en un nodo agrupado `erpnext-internals`, filas a 150/262/374, viewBox `[1390, 500]` (aspecto 2.78) y tarjetas recortadas a 2 ítems. Falló una vez más por legibilidad: el sublabel "MariaDB 10.6 · Redis x2 · 4 workers" en un nodo de 172px proyectaba 5.2px. Se acortó a "MariaDB · Redis · workers" con el recuento en el tag. Resultado: 9/9 y `visual-check` limpio en los cuatro tamaños.

11. **Reflujo del diagrama de flujo, con un callejón sin salida** — `bloqueado` de fila 3 a fila 2, viewBox `[880, 500]`, tarjetas recortadas. Quedó a 8px de caber (908 contra 900). Se intentó bajar el viewBox a 490 con `channelY: 444` → **nuevo fallo `artifact/legend-clearance`: "path 10 crosses legend"**, porque al encoger el lienzo la leyenda subió hasta el canal inferior. Se revirtió a `[880, 500]` con `channelY: 450` y se recortaron más las tarjetas. Resultado: cabe exacto en los cuatro tamaños.

12. **Congelar `pruebas/software-un-host/`** — El plan dejaba la decisión al usuario con "conservarlo" por defecto. Se tomó el default, pero el contenido contradecía el repo: usaba `frappe/erpnext:latest` (el defecto que esa misma ronda destapó) y afirmaba que el Dockerfile de OpenVPMS y la configuración de bind9 "todavía no existen", ya falso. Se le puso cabecera de "NO EJECUTAR" al compose y se reescribió el README como acta histórica con una tabla de qué se descubrió y dónde se arregló.

13. **Delegar la Fase 2 (instrucción del usuario)** — "Si es necesario reparte el trabajo con juan y pepe". Reparto por archivos para evitar colisiones: juan → LDIF + ERPNext + InvenTree (solo secciones `inventree-*` en el compose de PC-2); pepe → Pretix + OpenVPMS (solo secciones `pretix-*`). Resultado: cero conflictos entre ellos, confirmado después midiendo los conjuntos de archivos.

14. **juan: bootstrap LDAP (`d84c59e`)** — OUs por departamento, usuarios de prueba y cuenta de búsqueda. **Hallazgo real: la ACL por defecto de `osixia/openldap:1.5.0` no deja buscar a nadie salvo `admin`.** Sin `05-acl-servicio.ldif` ninguna aplicación podría resolver usuarios. Verificado en contenedor aislado: carga OK, bind bueno OK, bind malo devuelve 49, búsqueda con `svc-lectura` OK.

15. **pepe: Pretix y OpenVPMS no son viables (PR #5)** — Ver "Evidence & Data". Lo importante del método: **no tocó ningún compose**; documentó con evidencia y dejó el admin local. El plan lo autorizaba explícitamente.

16. **yobana: consolidación (PR #6), con dos rondas de corrección** — Primera entrega: escribió en §7 que LDAPS quedó "verificado con cadena y nombre **desde las apps**", lo que contradice al propio §8 que cita (ahí dice "cliente Python… desde otro segmento" y lista como "Sin cubrir" que las apps lo usen). Se corrigió. Segunda entrega, tras cerrar §9.3: el punto 3 de §7 seguía diciendo "lo que sigue pendiente es que las aplicaciones lo usen (punto 2)" cuando el punto 2 ya estaba marcado Resuelto — dos puntos consecutivos afirmando lo contrario. Además §8 "Sin cubrir" no llevaba remisión y se leía como estado actual. Se corrigieron las dos.

17. **juan: LDAPS real en ERPNext e InvenTree (PR #7)** — Ver la tabla en "Evidence & Data". Lo que da valor no son los 200 sino los controles negativos: clave errónea, usuario de otro departamento y **CA del sistema fallando**.

18. **Verificación del PR #4 a petición del usuario** — Se comprobó que las 19 referencias a código resuelven y que cada rango **empieza exactamente en el servicio que dice su `label`**, leyendo el blob de cada archivo en la revisión fijada. Lección: **Archify comprueba que el rango exista, no que apunte a lo correcto**; hace falta un verificador propio.

19. **Medir el desfase provocado por el PR #7** — Con el mismo método se comparó línea a línea: 6 de las 8 referencias a PC-3 quedaron apuntando a otro sitio (`erpnext-hr`, `erpnext-backend`, `erpnext-websocket`, `openldap`, `dns`, `ntp`); solo `erpnext-db` y `erpnext-configurator` siguen bien.

20. **Merge de los 4 PRs y verificación del resultado combinado** — En el orden pedido, comprobando entre cada uno. Después: que los 6 archivos clave estén en master y que los 4 enlaces cruzados resuelvan. Detalle operativo: GitHub reporta `UNKNOWN/UNKNOWN` unos segundos tras mover la base; se comprobó en local con `git merge-tree` antes del último merge en lugar de esperar.

21. **Delegar las dos tareas finales (instrucción del usuario)** — "usa los agentes no operes". Yobana → regenerar el diagrama; pepe → Fase 4. Ambos encargos incluyen las trampas de Archify del punto 3–11 para que no las redescubran.

## Key Decisions

- **Dos commits separados en el PR #4** (recuperación intacta + actualización) en vez de uno solo. Rechazado el commit único: el diff habría mezclado 30.000 líneas de HTML recuperado con los cambios reales y sería irrevisable.
- **`erpnext-data` + `erpnext-workers` fusionados en un solo nodo `erpnext-internals`.** El plan pedía dibujar ERPNext como diez nodos sueltos; con cuatro filas el diagrama dejaba de caber a 1440×900. Se priorizó que el diagrama sea legible y se compensó nombrando el contenido en el sublabel/tag y apuntando las tres entradas de `sources` a los rangos reales. **Es la única desviación deliberada respecto al plan.**
- **Etiquetas de IP abreviadas** (`.30.12`, `.99.11:53`) en dos nodos, por el mismo límite de 6px. Las IPs completas están en el diagrama de flujo y en el documento de arquitectura.
- **`pruebas/software-un-host/` se conserva congelado, no se borra.** Es el registro de cómo se descubrieron defectos que hoy están corregidos. Rechazado borrarlo (se pierde la trazabilidad) y rechazado actualizarlo (dejaría de ser un acta).
- **Se mantiene `frappe/erpnext:latest` en ese compose histórico**, con cabecera de "NO EJECUTAR". Rechazado cambiarlo a `:v15`: falsearía la evidencia de que ese tag era precisamente el defecto.
- **Los sidecars de `visual-check` (PNG, contact sheet, JSON) no se versionan.** Son evidencia regenerable y 1,4 MB de binarios.
- **No se tocó ningún archivo de la sesión par desde esta sesión.** Cuando hizo falta editarlos (los enlaces a los diagramas), se delegó a yobana con instrucción de coordinar primero. Verificado: el PR #4 no toca `README.md`, `docs/`, `tutoriales/` ni `docker/`.
- **Reparto por archivos como mecanismo anticolisión**, no por tarea. A juan y pepe se les dio la frontera dentro del mismo archivo (`inventree-*` vs `pretix-*` en el compose de PC-2). Funcionó: cero solapamiento entre los cuatro PRs.
- **Verificar lo que entregan los agentes en lugar de aceptarlo.** Se encontraron 3 errores reales que habrían llegado a master (el de §7.3, y las 2 inconsistencias residuales). Todos de precisión documental, ninguno de código.
- **Ramas remotas no borradas tras el merge**, porque juan, pepe y yobana tienen worktrees hermanos montados sobre ellas.
- **Orden de merge #4 → #5 → #7 → #6**, con #6 al final porque enlaza archivos que traen los otros tres.

## Evidence & Data

### Tabla 1 — Los cuatro PRs de esta sesión

| PR | Rama | Merge commit | Archivos | Autor | Qué aporta |
|---|---|---|---|---|---|
| #4 | `docs/recuperar-diagramas` | `6378076` | 9 (+31221/−0) | esta sesión | Diagramas recuperados y actualizados |
| #5 | `feat/ldap-pretix-openvpms` | `87da3c8` | 1 (+98/−0) | pepe | Pretix/OpenVPMS descartados con evidencia |
| #7 | `feat/ldap-erpnext-inventree` | `9a7dba7` | 10 (+219/−1) | juan | LDAPS real en ERPNext e InvenTree |
| #6 | `docs/consolidar-resultados-fase2` | `31a2824` | 3 (+82/−4) | yobana | Consolidación y enlaces |
| #8 | `docs/regenerar-diagrama-topologia` | **abierto** | 3 (+29/−29) | yobana | Re-pinar el diagrama a `31a2824` |

Cero archivos compartidos entre los cuatro conjuntos mergeados (verificado con `comm -12` por pares y `sort | uniq -d` global).

### Tabla 1b — PR #8, verificación independiente (no mergeado al cierre)

`MERGEABLE/CLEAN`, merge-base `31a2824`. Comprobado por esta sesión, no solo reportado por yobana:

| Comprobación | Resultado |
|---|---|
| `meta.repository.revision` == `origin/master` | `31a2824` en ambos — OK |
| Referencias que arrancan en una definición de servicio | **19 de 19** |
| `viewBox` | `[1390, 500]` sin cambios |
| Tag del nodo agrupado | "10 servicios, bridge privado" (antes 9) — correcto, con `erpnext-ldap-config` dentro |
| Nota de la vista `erpnext-stack` | "son 12 servicios" — correcto |
| `deliver` / `visual-check` (reportado por yobana) | 9/9, composición pass, sin desbordes en los 4 tamaños; texto mínimo proyectado 8.7px |

**Yobana encontró dos cosas que mi encargo no contemplaba y tenía razón en ambas:** (1) PC-2 también había cambiado —`inventree-app` pasó de 91–120 a 91–139 y el worker de 124–144 a 143–163—, así que el spec tenía dos rangos viejos más de los que yo había detectado; (2) la nota de la vista `erpnext-stack` decía "10 servicios" y ya era inconsistente con el "11" del README **antes** de esta sesión. Mi brief solo hablaba de PC-3 y del tag.

**Matiz honesto que ella misma declaró:** las métricas por viewport del JSON de `visual-check` solo salen con tema claro; el oscuro genera capturas PNG pero no entrada propia, así que "sin desbordes en oscuro" no está medido, solo visto.

### Tabla 2 — Resultados de la integración LDAPS (juan, PR #7)

Endpoints: ERPNext `/api/method/frappe.integrations.doctype.ldap_settings.ldap_settings.login`, InvenTree `/api/user/token/`.

| Prueba | ERPNext | InvenTree |
|---|---|---|
| Usuario de su departamento, clave correcta | 200 (`rrhh.prueba`) | 200 + token (`logistica.prueba`) |
| Clave errónea | 417 | 401 |
| Usuario de OTRO departamento, clave correcta | 417 (`logistica.prueba`, `vet.prueba`) | 401 (`rrhh.prueba`) |
| Administrador local (no LDAP) | sigue funcionando | 200 |
| Cadena TLS con `ca.crt` / con la CA del sistema | OK / **falla** | OK / **falla** (`self-signed certificate in certificate chain`) |
| `docker compose down` (sin `-v`) + `up -d` | 200 / 417 idénticos | 200 / 401 idénticos |

### Tabla 3 — Directorio LDAP creado (PR #7)

| Usuario | OU | Clave (laboratorio) |
|---|---|---|
| `vet.prueba` | `ou=medica` | `Medica-Prueba1` |
| `logistica.prueba` | `ou=operaciones` | `Oper-Prueba1` |
| `taquilla.prueba` | `ou=operaciones` | `Oper-Prueba1` |
| `rrhh.prueba` | `ou=rrhh` | `Rrhh-Prueba1` |
| `cn=svc-lectura` | `ou=servicios` | `Svc-Lectura1` |

`svc-lectura` puede leer pero NO ver `userPassword`. Montaje: `/container/service/slapd/assets/config/bootstrap/ldif/custom`, con `command: ["--copy-service"]` en el servicio `openldap`.

### Tabla 4 — Por qué Pretix y OpenVPMS no se integran (pepe, PR #5)

| App | Versión | Causa | Evidencia |
|---|---|---|---|
| OpenVPMS | 2.4.0.1 | Sin soporte LDAP | No hay `spring-security-ldap` entre los JAR del WAR; sin clases LDAP en `openvpms-web-security` ni `openvpms-framework`; usuarios son arquetipos en MySQL; `openvpms-auth-plugin` solo cubre el framework de plugins |
| Pretix | 2026.7.0 | Sin backend propio; el plugin comunitario no verifica TLS | `pretix-ldap` 0.2.5 crea `Server()` sin objeto `Tls` → `ldap3` usa `validate=CERT_NONE`. Demostrado: bind por `ldaps://` devuelve `success` con `validate=0`; con `Tls(CERT_REQUIRED)` y sin CA falla. Sin opción para pasar `ca.crt` sin parchear |

Agravantes de `pretix-ldap`: conexión compartida con `rebind` (carrera con varios workers) y autenticación por correo sin mapear OU a roles.

### Tabla 5 — Desfase de las referencias del diagrama tras el PR #7

`docker/pc3-administracion-infra/docker-compose.yml`: **282 → 342 líneas**.

| Componente | Línea fijada | Qué había en `752e41f` | Qué hay ahora | Estado |
|---|---|---|---|---|
| `erpnext-hr` | 200 | `erpnext-hr:` | `- erpnext_logs:…` | DESFASADA |
| `erpnext-backend` | 136 | `erpnext-backend:` | comentario de otro job | DESFASADA |
| `erpnext-internals` | 45 | `erpnext-db:` | `erpnext-db:` | OK |
| `erpnext-internals` | 151 | `erpnext-websocket:` | código Python | DESFASADA |
| `erpnext-internals` | 82 | `erpnext-configurator:` | `erpnext-configurator:` | OK |
| `openldap` | 226 | `openldap:` | `condition: service_completed…` | DESFASADA |
| `dns-interno` | 254 | `dns:` | `- erpnext_internal` | DESFASADA |
| `ntp-interno` | 265 | `ntp:` | `condition: service_started` | DESFASADA |

### Tabla 6 — Líneas de inicio reales en master (`31a2824`), para re-pinar

**PC-3** (`docker/pc3-administracion-infra/docker-compose.yml`, 342 líneas, 15 servicios):

| Línea | Servicio | Línea | Servicio | Línea | Servicio |
|---|---|---|---|---|---|
| 45 | `erpnext-db` | 139 | `erpnext-ldap-config` **(nuevo)** | 244 | `erpnext-queue-long` |
| 65 | `erpnext-redis-cache` | 185 | `erpnext-backend` | 257 | `erpnext-hr` |
| 72 | `erpnext-redis-queue` | 208 | `erpnext-websocket` | 283 | `openldap` |
| 82 | `erpnext-configurator` | 220 | `erpnext-scheduler` | 315 | `dns` |
| 104 | `erpnext-create-site` | 232 | `erpnext-queue-short` | 326 | `ntp` |

**PC-2** (`docker/pc2-operaciones/docker-compose.yml`, 168 líneas, 6 servicios): 31 `pretix-db`, 45 `pretix-redis`, 53 `pretix-web`, 77 `inventree-db`, 91 `inventree-app`, 143 `inventree-worker`.

### Tabla 7 — Iteraciones del diagrama de topología

| Intento | viewBox | Filas | `deliver` | `visual-check` 1440×900 | Diagnóstico |
|---|---|---|---|---|---|
| v1 | 1560×620 | 3 | FALLÓ | — | 10 `endpoint-side-direction` + 4 de etiquetas |
| v2 | 1560×620 | 3 | FALLÓ | — | `desktop-readability`: 5.37px < 6px |
| v3 | 1390×620 | 4 | 9/9 OK | **FALLÓ** 1037 > 900 | Aspecto 2.24 y tarjetas largas |
| v4 | 1390×500 | 3 | FALLÓ | — | sublabel de 35 caracteres → 5.2px |
| **v5** | **1390×500** | **3** | **9/9 OK** | **OK (900 exacto)** | Final |

### Tabla 8 — Iteraciones del diagrama de flujo

| Intento | Etapas | viewBox | Resultado |
|---|---|---|---|
| v1 | 3 | 1120×620 | 8 errores: micro-segmento de 4.3px y etiquetas a 0px |
| v2 | 4 | 880×620 | 5 errores de separación en el corredor de 75px |
| v3 | 4 | 880×620 | 9/9 OK, pero `visual-check` 1351px y **1506 a 2048×1320** |
| v4 | 4 | 880×500 | 9/9 OK; 908 > 900, se queda a 8px |
| v5 | 4 | 880×490 | **`artifact/legend-clearance`: "path 10 crosses legend"** |
| **v6** | **4** | **880×500** | **9/9 OK; 900 exacto** tras recortar tarjetas |

### Tabla 9 — Referencia: los originales SÍ cabían

| Diagrama | viewBox original | Aspecto | `visual-check` |
|---|---|---|---|
| Topología (rama vieja) | 1360×500 | 2.72 | OK en los 4 tamaños, `scrollH == innerH` |
| Flujo (rama vieja) | 1060×480 | 2.21 | OK en los 4 tamaños |
| Topología (mi v3, fallida) | 1390×620 | 2.24 | Desbordaba 137px |
| Flujo (mi v3, fallido) | 880×620 | 1.42 | Desbordaba en TODOS los tamaños |


### Tabla 10 — Fase 4: versiones fijadas por pepe (sin commitear, sin verificar)

Criterio que eligió: `tag@digest` en el propio `image:`, no un comentario, porque "un comentario no protege de un cambio". Los digests son los de las imágenes que ya tenía descargadas y probadas localmente.

| Imagen | Antes | Fijado a | Nota |
|---|---|---|---|
| `postgres` | `:15` | `:15.19@sha256:…` | |
| `redis` | `:7` | `:7.4.11@sha256:…` | |
| `mysql` | `:8.0` | `:8.0.46@sha256:…` | |
| `mariadb` | `:10.6` | `:10.6.28@sha256:…` | |
| `pretix/standalone` | `:stable` | `:2026.7.0@sha256:7f8c1b51…` | **El digest es el del `stable` probado; el tag `2026.7.0` apunta HOY a otro digest (`5df3b7aa…`).** Por eso el digest manda |
| `inventree/inventree` | `:stable` | `:1.5.5@sha256:…` | En `inventree-app` y en `inventree-worker`, misma versión |
| `frappe/erpnext` | `:v15` | `:v15.121.3@sha256:…` | En el ancla YAML `&erpnext_image`, no servicio a servicio |
| `osixia/openldap` | `:1.5.0` | `:1.5.0@sha256:…` | |
| `bind9` | `:9.18` | `:9.18@sha256:…` | ISC solo publica ese tag |
| `cturra/ntp` | `:latest` | `:latest@sha256:…` | Único tag existente |

También añadió healthcheck a `pretix-web` y a `erpnext-hr` (`start_period: 900s`). `restart: unless-stopped` ya estaba en todo salvo los tres jobs de un solo uso, correctamente.

**No fijado:** el `Dockerfile` de OpenVPMS usa `tomcat:9.0-jdk11-temurin` sin fijar; pepe no tenía la imagen local y **no inventó el digest**, que es la decisión correcta.

**Sin verificar:** que los healthchecks nuevos lleguen a `healthy` y la Tabla 5 completa del arnés.

### Historial de commits de esta sesión

| Commit | Autor | Qué |
|---|---|---|
| `07a2932` | esta sesión | Recuperar `diagramas/` y `pruebas/software-un-host/` intactos |
| `104c39e` | esta sesión | Actualizar diagramas al stack real y congelar la prueba de un host |
| `d84c59e` | juan | Bootstrap OpenLDAP con OUs, usuarios y cuenta de búsqueda |
| `5b9af3e` | pepe | Evaluación de LDAP en Pretix y OpenVPMS |
| `ca0d3eb` | yobana | Consolidar resultados de la Fase 2 y enlazar los diagramas |
| `60bb7dd` | yobana | Corregir §7 punto 3 (LDAPS se verificó con cliente externo) |
| `3fdea43` | juan | Autenticación LDAPS real en ERPNext e InvenTree |
| `1bce8e3` | yobana | Cerrar §9.3 con resultados de ERPNext e InvenTree |
| `703f5a6` | yobana | Remisiones a §9 en §7.3 y §8 |
| `6378076` `87da3c8` `9a7dba7` `31a2824` | esta sesión | Los cuatro merges |

### Comandos clave verificados

```bash
# Archify: validar, entregar y comprobar en navegador. --repo-root SOLO en el de topología.
cd C:/Users/jafet/.claude/skills/archify
node bin/archify.mjs validate architecture <repo>/diagramas/topologia-red.architecture.json \
  --quality showcase --repo-root <repo> --json
node bin/archify.mjs deliver  architecture <repo>/diagramas/topologia-red.architecture.json \
  <repo>/diagramas/topologia-red.html --quality showcase --repo-root <repo> --json
node bin/archify.mjs visual-check <repo>/diagramas/topologia-red.html --json

# Verificar que los rangos apuntan a lo correcto (Archify NO lo hace)
# Para cada sources[]: git show <revision>:<path> y comprobar que la línea `line` empieza en el servicio del `label`.

# Comprobar solapamiento entre ramas antes de mergear
comm -12 <(git diff --name-only origin/master...origin/A|sort) <(git diff --name-only origin/master...origin/B|sort)

# Mergeabilidad local cuando GitHub devuelve UNKNOWN tras mover la base
git merge-tree $(git merge-base origin/master origin/<rama>) origin/master origin/<rama>
```

### Rutas de datos

- Transcripción completa: `C:\Users\jafet\.claude\projects\D--Proyectos-UD-RedesCorporativaa-ProyectoFinak\a3e66077-787d-469d-b3f0-e4ba06bc9672.jsonl`
- Handoff padre (copia de trabajo): `%TEMP%\parent.md` — el original está en `origin/docs/handoff-plan-lab-3pcs:plans/handoffs/HANDOFF_standalone-9e6e8d31_lab-3pcs-pruebas-reales_2026-09-19.md`
- Skill de Archify: `C:\Users\jafet\.claude\skills\archify` (esquemas en `schemas/`, ejemplos en `examples/`, renderers en `renderers/`)

## Code Analysis

- **Geometría fija del renderer de dataflow** (`renderers/dataflow/render-dataflow.mjs`, líneas 52–64): `stageY: 46`, `stageH: 36`, `stageBottomPad: 74`, `leftX: 100`, `colGap: 215`, `stageW: 168`, `nodeW: 112`, `nodeH: 58`, `rowYs: [128, 242, 356, 470, 584]`, `labelH: 16`. Los centros de etapa salen de `leftX + index * colGap`, así que **el número de etapas determina el ancho útil**, no el viewBox. Validaciones: `node.x >= 24`, `node.x + width <= viewBox[0] - 24`, `node.y >= stageY + stageH + 22` (=104) y `node.y + height <= viewBox[1] - 74`.
- **Ancho de etiqueta de flujo**: `max(34, longestLine * 4.9 + 12)`. Para caber en el corredor de 75px entre etapas hace falta ≤ 11 caracteres.
- **Límite de legibilidad**: el texto de contexto de un nodo es 9px de origen; a un viewport de 1440 el ancho útil del diagrama es 930px, luego `viewBox[0] ≤ 930 * 9 / 6 ≈ 1394`. Si un sublabel no cabe en su nodo, el renderer encoge la fuente y el mínimo de 6px se incumple por esa vía (pasó con 7.8px → 5.2px).
- **`meta.repository.revision` exige sha de 40 caracteres** (`pattern: "^[a-fA-F0-9]{40}$"`). `sources` admite **máximo 3 entradas por componente** y cada una `path`, `line`, `end_line`, `label`.
- **`meta.viewBox`** en architecture: mínimos 320×240. En dataflow: 360×360.
- **`guidedViews`**: máximo 5 vistas, `label` ≤ 48 caracteres, `note` ≤ 140.
- **PC-3 tiene 15 servicios** tras el PR #7: 12 de ERPNext (incluido el nuevo `erpnext-ldap-config`) + `openldap` + `dns` + `ntp`. El nodo agrupado del diagrama cubre 10 de ellos, no 9: hay que actualizar el tag.
- **Filtro LDAP de InvenTree**: el valor por defecto de la imagen es `(uid= %(user)s)` — con un espacio de más — y no encuentra a nadie. Hay que sobrescribirlo con `(uid=%(user)s)`.
- **`erpnext-ldap-config`** guarda LDAP Settings con `ignore_mandatory`, es decir no valida contra el directorio al guardar; la única prueba real es el login.

## Files Changed

### Diagramas (PR #4, esta sesión)
- `diagramas/topologia-red.architecture.json` — reescrito: 15 componentes, viewBox `[1390,500]`, 19 `sources` fijadas a `752e41f`, 4 vistas, 4 tarjetas.
- `diagramas/topologia-red.html` — regenerado con Archify (`deliver`, 9/9, sha256 del artefacto en el recibo).
- `diagramas/flujo-datos-segmentacion.dataflow.json` — reescrito: 4 etapas, 9 nodos, 10 flujos, viewBox `[880,500]`.
- `diagramas/flujo-datos-segmentacion.html` — regenerado.
- `diagramas/README.md` — añadida la sección de estado real, los comandos de regeneración y la advertencia de que los sidecars de `visual-check` no se versionan.

### Prueba histórica (PR #4, esta sesión)
- `pruebas/software-un-host/README.md` — reescrito como acta histórica con tabla "hallazgo → dónde se arregló".
- `pruebas/software-un-host/docker-compose.yml` — cabecera de "ARCHIVO HISTÓRICO — NO EJECUTAR"; el contenido original intacto.
- `pruebas/software-un-host/.env.example`, `verificar.sh` — recuperados sin cambios.

### Integración LDAP (PR #7, juan)
- `docker/pc3-administracion-infra/ldap/05-acl-servicio.ldif`, `10-estructura.ldif`, `20-usuarios-prueba.ldif`, `README.md` — nuevos.
- `docker/pc3-administracion-infra/docker-compose.yml` — servicio `erpnext-ldap-config`; `extra_hosts` y volumen de CA en `erpnext-backend`; `command: ["--copy-service"]` y montaje de LDIF en `openldap`.
- `docker/pc2-operaciones/docker-compose.yml` — variables `INVENTREE_LDAP_*` en `inventree-app` (+19 líneas).
- `docker/pc2-operaciones/.env.example`, `docker/pc3-administracion-infra/.env.example` — `INVENTREE_LDAP_BIND_PASSWORD` y `ERPNEXT_LDAP_BIND_PASSWORD`.
- `pruebas/smoke-test-3-pcs/test.env` — las mismas dos variables.
- `docs/integracion-ldap-erpnext-inventree.md` — nuevo.

### Documentación (PR #5 pepe, PR #6 yobana)
- `docs/ldap-pretix-openvpms.md` — nuevo, 98 líneas, con el procedimiento de repro de la prueba de TLS.
- `docs/prueba-smoke-test-resultados.md` — §9 nueva (9.1 bootstrap, 9.2 descartes, 9.3 integración); §7 puntos 2 y 3 actualizados; remisiones en §5, §6 y §8.
- `README.md` — `diagramas/` y `pruebas/` en el árbol, sección "Diagramas", Dockerfile de OpenVPMS marcado como hecho.
- `docs/arquitectura-3-equipos-departamentos.md` — enlace a cada diagrama en §2 y §4.

### Memoria de sesión (fuera del repo)
- `C:\Users\jafet\.claude\projects\D--Proyectos-UD-RedesCorporativaa-ProyectoFinak\memory\delegacion-detallada-a-agentes.md` — creado y luego ampliado.

## User Feedback & Preferences (REQUIRED — never omit)

- **"Si es necesario reparte el trabajo con juan y pepe"** — autorización explícita para delegar en sesiones par. No era una sugerencia: marcó el cambio de modo de toda la sesión.
- **"si verificaste la rama master y ver que tu rama este actualizada?"** — pide confirmación explícita de que la rama está sincronizada con master ANTES de abrir un PR. No basta con haberlo hecho: hay que decirlo con la evidencia (`merge-base`, commits pendientes).
- **"que yobana cordine pero se muy detallado con el agente tu eres el cerebro de la operacion pero debes ser detallado"** — define el rol: coordinador, y los encargos a otros agentes deben ser exhaustivos, no telegráficos. **Guardado en memoria.**
- **"Quiero que hagas recap de que estamos haciendo por que y verifiques el pr actual #4 … si los cambios o seguimos bien el plan y nada se esta re haciendo o contradiciendo con el objetivo"** — quiere verificación real contra el plan y contra el objetivo, no un resumen de lo que dije que hice. Le importa especialmente que no haya trabajo duplicado ni contradicciones.
- **"mergea los 4 PRs en ese orden"** — autorización explícita de merge, respetando el orden propuesto.
- **"arranca con las dos cosas, usa los agentes no operes"** — corrección directa: aunque yo supiera hacer la tarea, mi sitio es delegar. **Guardado en memoria.**
- Preferencias heredadas del seq 1 y confirmadas en esta sesión: comunicación en español; nunca push a master; nunca `git add -A` (rutas explícitas); `git fetch` + `git pull --rebase` antes de cada push; PR siempre, nunca merge directo a master por parte de los agentes; no escribir `.sh` con `python open(..., 'w')` en Windows (CRLF).
- Observado en toda la sesión: el usuario no pide detalles de implementación pero sí quiere saber **qué se verificó y cómo**. Las respuestas con la evidencia concreta (números, comandos, conteos) funcionan mejor que las afirmaciones.

## Anexos de contexto adicional

### Anexo A — Catálogo de diagnósticos de Archify encontrados y cómo se resuelven

Esta tabla es lo más caro de re-derivar de toda la sesión: cada fila costó una ronda de validación.

| Código | Qué significa | Arreglo que funcionó |
|---|---|---|
| `repository-evidence/root-required` | El spec declara `meta.repository` + `sources` y no se pasó el checkout | Añadir `--repo-root <repo>` a `validate` y a `deliver` |
| `clean-flow/endpoint-side-direction` | El reparto automático de puertos infirió `left`/`right` pero el segmento sale vertical | Declarar `fromSide: "bottom"` + `toSide: "top"` explícitos en cada par vertical |
| `layout/constraint` (etiqueta sobre nodo) | La etiqueta cae encima del nodo origen o destino | `labelDy: 24` (hacia abajo) o negativo (hacia arriba); el diagnóstico sugiere el valor exacto |
| `composition/label-route-clearance` | Dos etiquetas o una etiqueta y una ruta a <4px | Acortar la etiqueta, o `labelDy` para sacarla del corredor |
| `composition/micro-segment` | Un tramo interior de la ruta mide <8px | Cambiar `route`/`via` o `channelX`/`channelY` |
| `composition/desktop-readability` | Texto proyecta <6px a 1440 de viewport | **Reducir `viewBox[0]`** (≤~1394) o acortar el texto del nodo |
| `artifact/legend-clearance` | Una ruta cruza la leyenda inferior | Subir el `channelY` o devolver altura al viewBox |
| `viewer/viewport-overflow` (solo `visual-check`) | La página no cabe en el viewport | Subir la relación de aspecto del viewBox y/o recortar las tarjetas |

**Regla de oro aprendida:** aplicar **un** arreglo por vuelta y revalidar. Cambiando tres cosas a la vez es imposible saber cuál funcionó, y varios de estos diagnósticos se enmascaran entre sí.

### Anexo B — Contenido final del diagrama de topología

15 componentes, viewBox `[1390, 500]`, filas en y=150 / 262 / 374, nodos de 58px de alto.

| Región (boundary) | Componentes |
|---|---|
| PC-1 · Servidor Médico · puerto ACCESS | `openvpms-app` (VLAN10 `10.10.10.10:8080`), `openvpms-db` (MySQL 8.0, `.10.11`) |
| PC-2 · Operaciones · TRUNK (VLAN 20+30) | `pretix-web` (`.20.10:80`), `pretix-db` (Postgres 15), `pretix-redis` (Redis 7), `inventree-app` (`.30.10:8000`), `inventree-db`, `inventree-worker` (`.30.12`) |
| PC-3 · Administración e Infraestructura · TRUNK (VLAN 40+99) | `erpnext-hr` (nginx `.40.10:8080`), `erpnext-backend` (gunicorn `.40.11:8000`), `erpnext-internals` (agrupado), `openldap` (`.99.10`, tag "389 + LDAPS 636"), `dns-interno` (bind9 `.99.11:53`), `ntp-interno` (`.99.12:123`) |

Más el nodo `switch` (tipo `cloud`, tag "802.1Q", sublabel "sin salida a Internet"), con 5 conexiones `emphasis` hacia ACCESS·VLAN10, TRUNK·VLAN20, TRUNK·VLAN30, TRUNK·VLAN40 y TRUNK·VLAN99.

Las 4 tarjetas: "3 PCs, 1 switch, sin Internet", "Redes macvlan por VLAN", "VLAN 99 transversal", "Enrutamiento entre VLANs". Las 4 vistas guiadas: `topologia-completa`, `pc2-operaciones`, `erpnext-stack`, `infraestructura-transversal`.

### Anexo C — Contenido final del diagrama de flujo

4 etapas: "Origen · VLANs de negocio", "Switch / política", "VLAN 99 · Infraestructura", "Resultado". 9 nodos, todos de 140px de ancho.

| Etapa | Nodos |
|---|---|
| 0 | `vlan10` (PC-1, access), `vlan2030` (PC-2, trunk), `vlan40` (PC-3, trunk) |
| 1 | `switch` (tag "L3, o L2 + PC-3") |
| 2 | `ldap` (`.99.10`, 389 y 636, tag "CA interna"), `dns` (bind9 `.99.11:53`), `ntp` (`.99.12:123`) |
| 3 | `permitido` (fila 1), `bloqueado` (fila 2, tag "sin respuesta") |

10 flujos. El de denegación (`denegado-cruzado`) usa `route: "bottom-channel"` con `channelY: 450` para pasar por debajo de la etapa 2. Los tres flujos rectos de la fila central llevan `labelDy: 13`. Tres vistas guiadas: `permitido`, `bloqueado`, `hairpin`.

### Anexo D — Los tres errores detectados verificando a los agentes

Justifica el coste de verificar en vez de aceptar. Ninguno era de código; los tres habrían llegado a master.

| # | Dónde | El error | Por qué importaba |
|---|---|---|---|
| 1 | yobana, §7 punto 3 | "LDAPS verificado con cadena y nombre **desde las apps**" | Contradecía al §8 que citaba (fue un cliente Python desde otro segmento) y afirmaba lo único que el proyecto todavía no podía demostrar. La propia frase se corregía a sí misma en su segunda mitad |
| 2 | yobana, §7 punto 3 (2ª ronda) | Seguía diciendo "lo que sigue pendiente es que las aplicaciones lo usen (punto 2)" con el punto 2 ya marcado Resuelto | Dos puntos consecutivos de la misma lista afirmando lo contrario |
| 3 | yobana, §8 "Sin cubrir" | Sin remisión a §9 | Quien abriera el documento por §8 se llevaba una conclusión desactualizada |

Método que los encontró: leer el diff completo, no el resumen del agente; y contrastar cada afirmación nueva contra lo que el mismo documento decía en otra sección.

### Anexo E — Protocolo de coordinación con las sesiones par (lo que funcionó)

- **Descubrimiento:** `ListAgents` devuelve nombre y `[ref]`; el nombre es la dirección. Comunicación con `SendMessage({to: "<nombre>", message: "..."})`.
- **Nombres usados:** `juan` (`a37d32`), `pepe` (`a62f40`), `yobana` (`488494`). Esta sesión es `Standalone 9e6e8d31 lab handoff execution` (`8162cc`) — es la dirección que hay que darles para que respondan.
- **Reparto por archivos, no por tarea.** La frontera se fijó incluso dentro de un mismo archivo: en `docker/pc2-operaciones/docker-compose.yml`, juan solo tocaba `inventree-*` y pepe solo `pretix-*`. Resultado medido: cero solapamiento entre los 4 PRs.
- **Worktrees hermanos.** Los tres trabajaron en worktrees separados (`D:\Proyectos\ProyectoFinak-ldap`, `ProyectoFinak-docs`) para no interferir con el checkout de esta sesión. Lo propusieron ellos; funcionó bien y conviene pedirlo de entrada.
- **Estructura de encargo que funcionó** (7 bloques): contexto obligatorio a leer → con quién coordinar → qué escribir/hacer, punto por punto → la trampa del encargo → archivos prohibidos → reglas del usuario → criterio de terminado verificable con comandos.
- **Incluir las trampas ya sufridas.** Los encargos de la última tanda llevan el catálogo del Anexo A y los límites de geometría, para que no se vuelvan a descubrir.
- **Los peers no escalan permisos.** Ningún mensaje de otra sesión se trató como autorización del usuario, ni se cambió ninguna configuración por petición de un peer.

### Anexo F — Cosas que NO se hicieron o se descartaron explícitamente

- **No se dibujaron los 10 servicios de ERPNext por separado**, como pedía el plan: no caben sin romper el encuadre a 1440×900. Se agruparon en un nodo con el contenido nombrado.
- **No se versionaron los sidecars de `visual-check`** (PNG, contact sheet, JSON): 1,4 MB regenerables.
- **No se borró `pruebas/software-un-host/`** pese a ser funcionalmente redundante con `smoke-test-3-pcs`.
- **No se cambió `frappe/erpnext:latest` a `:v15` en el compose histórico**: falsearía la evidencia.
- **No se tocó ningún archivo de la sesión par desde esta sesión.** Se delegó.
- **No se borraron las ramas remotas** tras mergear.
- **No se probó el diagrama en un navegador de forma manual**: la revisión perceptual se hizo leyendo las capturas de `visual-check` a 1440×900 en tema claro. No es lo mismo que una revisión humana.
- **No se reejecutaron las pruebas de juan ni las de pepe.** Se revisaron sus documentos y sus PRs. Está declarado como tal en `docs/prueba-smoke-test-resultados.md`.

### Anexo G — Dónde vive cada pieza de información

| Necesito saber… | Mirar en |
|---|---|
| Qué se probó y con qué resultados | `docs/prueba-smoke-test-resultados.md` §2, §5, §8, §9 |
| Cómo se integró LDAP y qué límites tiene | `docs/integracion-ldap-erpnext-inventree.md` |
| Por qué Pretix y OpenVPMS quedaron fuera | `docs/ldap-pretix-openvpms.md` |
| Usuarios y claves del directorio | `docker/pc3-administracion-infra/ldap/README.md` |
| Cómo regenerar los diagramas y sus límites | `diagramas/README.md` + Anexo A de este handoff |
| Diseño, direccionamiento y matriz | `docs/arquitectura-3-equipos-departamentos.md` |
| Checklist de la prueba en hardware | Anexo I del handoff padre (seq 1) |
| Cómo reproducir el arnés | `pruebas/smoke-test-3-pcs/README.md` |
| Qué se descubrió en la primera ronda | `pruebas/software-un-host/README.md` (histórico) |

### Anexo H — Métricas de la sesión

- 4 PRs abiertos, verificados y mergeados por esta sesión; 1 quinto (#8) abierto por yobana y pendiente.
- 9 commits de contenido + 4 merges en master.
- 3 sesiones par coordinadas, 9 mensajes enviados, 5 recibidos.
- 3 errores detectados verificando entregas ajenas, todos corregidos antes del merge.
- 2 errores del plan original detectados y corregidos ("10 servicios" → 11; "≥6 archivos" → 5).
- 5 iteraciones para dejar el diagrama de topología válido, 6 para el de flujo.
- 2 memorias guardadas (una creada y luego ampliada).
- `bd` no está instalado: no hay beads que actualizar.

### Anexo I — Detalle que conviene no volver a deducir

- **ERPNext devuelve 417** (Expectation Failed), no 401, cuando el login LDAP falla. Es el comportamiento de Frappe para una validación fallida en servidor. InvenTree sí devuelve 401.
- **`erpnext-backend` es el que habla LDAPS**, no `erpnext-hr`. El frontend es solo nginx.
- **El nombre `ldap.reservaviva.local` se fija con `extra_hosts` a `10.10.99.10`** para que coincida con el SAN del certificado sin depender de que bind9 esté arriba.
- **Los tres jobs de un solo uso** (`erpnext-configurator`, `erpnext-create-site`, `erpnext-ldap-config`) llevan `restart: "no"` a propósito. Ponerles `unless-stopped` los mete en bucle.
- **`docker/pc1-medica/docker-compose.yml` no cambió** en toda esta sesión: sigue con 58 líneas y 2 servicios.
- **GitHub reporta `UNKNOWN/UNKNOWN`** durante unos segundos tras mover la base de un PR. No es un error: se comprueba en local con `git merge-tree` en vez de esperar.

### Anexo J — Estado del entorno al cerrar la sesión (LIMPIAR ANTES DE SEGUIR)

Verificado por esta sesión con `docker ps -a`, no solo reportado: **quedan 10 contenedores sin limpiar** del intento fallido de pepe, porque su `docker compose down -v` murió con un 500 del engine de Docker Desktop.

```
erpnext-backend      erpnext-create-site   erpnext-configurator
erpnext-redis-cache  erpnext-redis-queue   erpnext-db
inventree-db         openvpms-db           pretix-db          pretix-redis
```

Son nombres de contenedor **fijos** (los compose los declaran con `container_name:`), así que cualquier nuevo `up` del arnés va a chocar con ellos. Antes de relanzar nada:

```bash
docker ps -aq | xargs -r docker rm -f      # o `docker compose -p rvpin down -v` si el engine responde
docker volume ls                            # comprobar si quedaron volúmenes huérfanos
```

Ojo con el volumen `ldap_data`: si sobrevive, el bootstrap LDIF **no se vuelve a cargar** y las pruebas de LDAP fallarán sin motivo aparente. Hace falta `down -v` de verdad.

**Además, la memoria del sistema estaba insuficiente al cierre.** El arnés completo pide ~7 GB y Claude Code mató el `up` de pepe a medio arranque. Hay que liberar memoria antes de intentar la verificación de la Fase 4.

## Where We're Going

1. **MERGEAR EL PR #8.** Ya entregado por yobana y verificado por esta sesión (Tabla 1b): re-pina el diagrama a `31a2824`, 19/19 referencias correctas, tag del nodo agrupado a 10 servicios y nota de la vista a 12. Está listo; solo falta el merge. **Ojo al punto 3 antes de mergear.**
2. **(PAUSADA, pepe — necesita intervención del usuario)** Fase 4. Los YAML están editados en el worktree `D:\Proyectos\ProyectoFinak-pin` (rama `chore/fijar-imagenes`, merge-base `31a2824`) pero **sin commit, sin push y sin PR**, porque no pudo verificar el arnés: Claude Code mató su `docker compose up` por falta de memoria del sistema a medio arranque (12 contenedores creados, ninguna app healthy) y le indicó que no lo relance por su cuenta. Hizo lo correcto al no abrir PR sin verificación. **Necesita que el usuario libere memoria y autorice relanzar el arnés.** Ver Tabla 10 para lo que ya dejó fijado. Pendiente original: fijar tags o digests de todas las imágenes móviles (`pretix/standalone:stable`, `inventree/inventree:stable` ×2, `cturra/ntp:latest`, `postgres:15`, `redis:7`, `mysql:8.0`, `mariadb:10.6`, `bind9:9.18`), añadir `restart: unless-stopped` donde falte —**nunca a los tres jobs de un solo uso**— y healthchecks en `pretix-web` y `erpnext-hr`. Verificar con el arnés completo desde cero.
3. **ARBITRAR EL CHOQUE ENTRE 1 Y 2.** Pepe va a cambiar el número de líneas de los `docker-compose.yml` (comentarios de digest, healthchecks, `restart`), lo que **volverá a desfasar** las referencias del diagrama de yobana. Se les dijo que se coordinen y decidan quién mergea primero; quien vaya segundo rehace lo suyo. Hay que vigilarlo.
4. **Portar `HANDOFF_standalone-9e6e8d31_*` y `PLAN_standalone-9e6e8d31_*` a master** desde la rama `docs/handoff-plan-lab-3pcs`. Hoy no están, exactamente como pasaba con los diagramas. Este handoff incluido.
5. **Fase 3 — prueba en hardware real.** Sigue siendo lo único que demuestra el objetivo del curso. Checklist completo en el Anexo I del handoff padre. Requiere los 3 PCs con Linux y root, el switch, y probar desde un equipo distinto (con macvlan el host no alcanza sus propios contenedores).
6. **Cerrar los pendientes de la sesión par:** los tutoriales necesitan las variables `ERPNEXT_LDAP_BIND_PASSWORD` e `INVENTREE_LDAP_BIND_PASSWORD` y la nota de `down -v`. Yobana lo dejó anotado pero no lo tocó por reparto.
7. **Mapear usuarios LDAP a roles.** Hoy entran sin permisos; en ERPNext el rol `Employee` se retira solo por no haber empleado mapeado. Es el siguiente paso natural si el curso lo exige.

## Risks & Blockers

- **Sin hardware ni Linux con root:** macvlan, 802.1Q, el switch y la matriz de segmentación siguen sin validar. Es el riesgo residual principal del proyecto y no ha cambiado desde el seq 1.
- **Colisión anunciada entre el PR #8 y el de pepe** (punto 3 de arriba). Probabilidad alta: pepe *va* a cambiar el tamaño de los compose al añadir comentarios de digest, healthchecks y `restart`. Yobana ya le avisó por SendMessage y lo dejó escrito en el cuerpo del #8; al cierre de la sesión pepe no había respondido.
- **Las referencias del diagrama son frágiles por diseño.** Cualquier PR que cambie el tamaño de un `docker-compose.yml` las desfasa. Se ha arreglado una vez y va a volver a pasar; considerar reducir la granularidad (apuntar al archivo sin `line`) si se vuelve una carga.
- **Claves de laboratorio en el repo:** las del LDIF (`Medica-Prueba1`, `Svc-Lectura1`, etc.) están en `docker/pc3-administracion-infra/ldap/README.md`. Están documentadas como desechables, pero si el repo se hace público hay que rotarlas.
- **El bootstrap LDIF solo carga con `ldap_data` vacío.** Cualquiera que repita la prueba sobre un entorno previo necesita `down -v`, que borra los datos de todo el compose.
- **Docker compartido inestable y ENTORNO SUCIO AL CIERRE:** juan reportó que algo borra contenedores con nombre fijo en esta máquina. Y más grave: el `down -v` de pepe falló con un **500 del engine de Docker Desktop**, dejando **~10 contenedores del proyecto `rvpin` sin limpiar**. Hay que limpiarlos a mano antes de volver a levantar el arnés, o la siguiente corrida competirá por memoria y puertos.
- **Memoria del sistema insuficiente para el arnés completo en este momento:** Claude Code mató el `docker compose up` de pepe a medio arranque. El arnés pide ~7 GB. Sin liberar memoria, la Fase 4 no se puede verificar.
- **Dependencia de Internet** en el build de OpenVPMS (~300 MB) y RAM de ~7 GB con ~13 min de primer arranque.

## Open Questions

- **¿El switch del laboratorio es L2 puro o L3 (SVI/ACL)?** Sin respuesta desde el seq 1. Determina `FALLBACK_L2` y si la matriz vive en el switch o en PC-3 como router-on-a-stick. **Bloquea el diseño final de la Fase 3.**
- **¿Los 3 PCs son Linux con root y una NIC con trunk 802.1Q en PC-2/PC-3?** Supuesto del diseño, sin confirmar.
- **¿Hace falta mapear los usuarios LDAP a roles/empleados para la entrega**, o basta con demostrar que la autenticación funciona?
- **¿Se quiere que los handoffs y planes vivan en master**, o el usuario prefiere mantenerlos en ramas? Hoy están a medias: los de `cad62bb5` sí, los de `9e6e8d31` no.
- **¿Se borran las ramas remotas ya mergeadas?** No se hizo porque las tres sesiones par tienen worktrees sobre ellas.

## Quick Start for Next Session

```bash
# Restore context (bd NO está instalado en esta máquina)
cat plans/handoffs/HANDOFF_standalone-9e6e8d31_diagramas-y-ldap-en-master_2026-09-19.md
git show origin/docs/handoff-plan-lab-3pcs:plans/handoffs/HANDOFF_standalone-9e6e8d31_lab-3pcs-pruebas-reales_2026-09-19.md
git show origin/docs/handoff-plan-lab-3pcs:plans/handoffs/PLAN_standalone-9e6e8d31_lab-3pcs-pruebas-reales_2026-09-19.md

# Reference docs
docs/arquitectura-3-equipos-departamentos.md      # diseño, direccionamiento, matriz (§4), plan de pruebas (§7)
docs/prueba-smoke-test-resultados.md              # §8 LDAPS, §9 integración LDAP
docs/integracion-ldap-erpnext-inventree.md        # lo que SÍ se integró
docs/ldap-pretix-openvpms.md                      # lo que NO, y por qué

# Key files to read first
docker/pc3-administracion-infra/docker-compose.yml     # 342 líneas, 15 servicios
docker/pc3-administracion-infra/ldap/README.md         # usuarios y claves del directorio
diagramas/topologia-red.architecture.json              # ojo: rangos fijados a 752e41f, desfasados
diagramas/README.md                                    # límites de Archify, comandos de regeneración
pruebas/smoke-test-3-pcs/README.md                     # cómo reproducir el arnés

# Verify current state
git checkout master && git pull                        # esperado: 31a2824 o posterior
gh pr list --state open                                # esperado: los de yobana y pepe, si ya los abrieron
git ls-tree -r --name-only origin/master | grep -c '^diagramas/'   # esperado 5

# Next action
Arbitrar el choque anunciado entre la regeneración del diagrama (yobana) y el fijado de imágenes
(pepe): ambos afectan al tamaño de los docker-compose.yml. Decidir quién mergea primero y hacer que
el segundo rehaga lo suyo. En paralelo, preguntar al usuario si el switch del laboratorio es L2 o L3,
que es lo único que bloquea el diseño final de la Fase 3.
```
