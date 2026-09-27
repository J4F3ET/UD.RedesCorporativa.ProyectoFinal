# Un host consolidado: un `docker-compose.yml` y `servicios/`, H20/H21/H22 corregidos, 4 documentos nuevos y PR #34 abierto (99 PASS / 0 FAIL)

**Date:** 2026-09-27 (la sesión empezó el 26/09 por la tarde y terminó pasada la medianoche)
**Status:** IN PROGRESS. El objetivo del seq 6 está **COMPLETADO** y publicado en el **PR #34** (abierto, MERGEABLE/CLEAN, sin CI), pero **sin fusionar**. Quedan decisiones del usuario, limpieza y pendientes de validación.
**Bead(s):** none (`bd` no está instalado)
**Epic:** Proyecto final Redes Corporativas (UD, grupo 678-302). Laboratorio "Reserva Viva"
**Chain:** `standalone-9e6e8d31` seq `7`
**Parent:** `HANDOFF_standalone-9e6e8d31_consolidacion-un-host-documentacion_2026-09-26.md`. Se borra del árbol en el commit de este traspaso (decisión D del usuario: "dejar solo el último"). Se lee con `git show 8c9efce:plans/handoffs/HANDOFF_standalone-9e6e8d31_consolidacion-un-host-documentacion_2026-09-26.md`; su PLAN, igual.
**Prior chain:** `…_lab-3pcs-pruebas-reales_2026-09-19` > `…_diagramas-y-ldap-en-master_2026-09-19` > `…_windows-docker-desktop-pivot_2026-09-20` > `…_arranque-arnes-ldaps-verificado_2026-09-20` > `…_un-host-plug-and-play-verificado_2026-09-26` > `…_consolidacion-un-host-documentacion_2026-09-26` > this.
- Los seq 1-4 se recuperan con `git show 95e0da4:plans/handoffs/<fichero>`.
- El seq 5 se recupera con `git show 93b106d:…`.
- El seq 6 se recupera con `git show 8c9efce:…`.

---

## Stale References

Identificadores del seq 6 que **ya no existen**. Es a propósito: los movió la Fase 3 (`9593b14`) según la decisión del usuario.

| Ya no existe | Ahora | Recuperar |
|---|---|---|
| `docker/pc1-medica/docker-compose.yml`, `docker/pc2-operaciones/docker-compose.yml`, `docker/pc3-administracion-infra/docker-compose.yml` | `docker-compose.yml` (raíz, único) | `git checkout 41d54ef -- docker` |
| `sistema/docker-compose.yml` (el `include:`) y `sistema/override-pc{1,2,3}.yml` | integrados en `docker-compose.yml` | `git checkout 41d54ef -- sistema/docker-compose.yml sistema/override-pc1.yml sistema/override-pc2.yml sistema/override-pc3.yml` |
| `docker/pc1-medica/openvpms/*` | `servicios/openvpms/*` | — |
| `docker/pc3-administracion-infra/ldap/*` | `servicios/openldap/*` | — |
| `docker/pc3-administracion-infra/bind/{named.conf,zones/}` | `servicios/bind9/{named.conf,zones/}` | — |
| `docker/pc3-administracion-infra/test-create-site.sh` | `servicios/erpnext/test-create-site.sh` | — |
| `scripts/generar-certificados.sh` | `servicios/ca/generar-certificados.sh` | `git checkout 41d54ef -- scripts` |
| `docker/pc3-administracion-infra/certs/` (y las copias en pc1/pc2) | `servicios/ca/certs/` (gitignorado; la misma CA, movida, no regenerada) | — |
| Variables `IP_PC2`, `IP_PC3`, `IFACE` en `sistema/test.env` | borradas; la zona usa `IP_DNS`, `IP_LDAP`, `IP_NTP`, `IP_OPENVPMS`, `IP_PRETIX`, `IP_INVENTREE` e `IP_RRHH`, derivadas de `NET_*` | — |
| El INFO "los nombres dns/ntp/ldap apuntan al contenedor que los sirve" | 7 comprobaciones PASS, una por nombre de la zona | — |
| Invocación "`docker compose` desde `sistema/`" | desde la **raíz**: `docker compose --env-file sistema/test.env …` | — |
| `ZONA = RAIZ / "docker/pc3-administracion-infra/bind/zones/db.reservaviva.local"` en `verificar_arquitectura.py` | `servicios/bind9/zones/db.reservaviva.local` | — |

`diseno-red/` todavía cita `docker/pc*` y `scripts/…` como **texto** (no como enlaces). Es el anexo de 3 equipos y no se tocó a propósito.

## Since Last Handoff

El seq 6 dejaba un plan de 6 fases (0-5). Esto es lo que pasó con cada una:

- **Fase 0 (alcance): HECHA, con un giro.**
  - Respuestas a la primera tanda de AskUserQuestion:
    - Compose: "Solo limpiar (Recomendado)".
    - **Carpetas: "Borrarlos y crear un solo docker pero lo mejor seria dividir todo por servicios, osea un docker compose y carpetas por servicios asi identificar que es de que cosa"**.
    - Documentos: los 4.
    - Worktrees: eliminar.
  - Las respuestas 1 y 2 se contradecían. Una segunda pregunta con vista previa lo resolvió: **"1 compose + carpetas (Recom.)"**. Es decir, la Fase 3 (fusión) pasó de condicional a obligatoria, y con otra forma: el compose va en la **raíz** en vez de en `sistema/`, y hay `servicios/<svc>/` en vez de `docker/pcN-*`.
  - Memoria `proyecto-consolidado-en-un-host.md` actualizada: la decisión E del 26/09 queda revocada.
- **Reparto:** ninguna de las 3 sesiones peer era de este repo:
  - "Migración n8n a Airflow DAGs": `C:\Users\jafet\Desktop\airflow\dags`.
  - "Consolidación de laboratorio": `D:\Proyectos\lab-free5gc`.
  - "Estructura codificación 7 bits…": apuntes de Teoría de la Información.

  Se repartió con la herramienta **Agent**, con 7 subagentes (Tabla 2), aplicando la memoria fijada "delegar con encargos exhaustivos".
- **Fases 1-2 (cosmética y semántica, H20/H21): HECHAS** por un solo agente de código, en 6 commits (Tabla 1). La Fase 2e (CA única) se hizo dentro de la Fase 3.
- **Fase 3 (un compose nativo): HECHA** (`9593b14`), con la estructura por servicios.
- **Fase 4 (documentos): HECHA.**
  - Documentos nuevos: `docs/arquitectura.md` (290 líneas), `docs/operacion.md` (168), `docs/seguridad.md` (261) y `docs/aplicaciones.md` (143).
  - Además, la sección "Documentación" del README y los 8 `servicios/*/README.md`.
- **Fase 5 (cierre): HECHA salvo la fusión.**
  - PR #34 abierto: https://github.com/J4F3ET/UD.RedesCorporativa.ProyectoFinal/pull/34.
  - Worktrees: 6 de 8 eliminados; 2 conservados porque tienen ficheros sin versionar.
- **Riesgo que se materializó y no estaba previsto: H22.** La interfaz web de InvenTree **nunca** había funcionado. Lo descubrió el coordinador al abrir `http://localhost:18083/web` en el navegador integrado, porque `verificar` solo prueba API y LDAP. Corregido en `afabb20`.
- **Preguntas abiertas del seq 6 resueltas:**
  - "¿Consolidarlo = fusionar?": sí, y por servicios.
  - "¿Qué documentos?": los 4, en Markdown en `docs/`.
  - "¿Funciona Pretix en `localhost:18082` (H20)?": sí. CSRF y `Host` pasan, y unas credenciales inventadas se rechazan por credenciales.
  - "¿Se regenera el diagrama?": se hizo un Mermaid dentro de `arquitectura.md`, no Archify.
- **Trayectoria:** el sistema vivo y el repo ya son de un host de punta a punta. Lo que queda es fusión, decisiones y deuda de validación (Where We're Going).

## Reference Documents

- `README.md`: portada, arranque rápido, accesos y sección **Documentación** (nueva) con los 5 enlaces.
- `docs/arquitectura.md` (**nuevo**): la ÚNICA fuente de redes, IP, puertos y servicios. Incluye un diagrama Mermaid, los flujos LDAP/DNS/NTP y las diferencias con el diseño de 3 equipos.
- `docs/operacion.md` (**nuevo**): requisitos, `.wslconfig`, acciones de `levantar-sistema`, qué hacer tras reiniciar, diagnóstico, trampas de Windows/WSL y protocolo de validación.
- `docs/seguridad.md` (**nuevo**): CA, LDAPS, ACL, cuentas, credenciales iniciales, exposición de red y lo que un host no aísla (vlan99).
- `docs/aplicaciones.md` (**nuevo**): por app, departamento, URL, usuario, variable de la clave, LDAP sí/no, particularidades (H19, H20, H22, `/media`, `bad_origin`).
- `docs/resultados-un-host.md`: el ÚNICO documento de cifras (arranque, RAM, pasadas de `verificar`, pendientes y resueltos H18-H22).
- `sistema/verificar_arquitectura.md` y `sistema/README.md`: el arnés de verificación.
- `servicios/*/README.md`: 8 ficheros de 9 a 29 líneas; qué es cada servicio y qué ficheros tiene.
- Memorias en `C:\Users\jafet\.claude\projects\D--Proyectos-UD-RedesCorporativaa-ProyectoFinak\memory\`:
  - `delegacion-detallada-a-agentes.md` (**fijada**).
  - `no-sacrificar-el-entregable.md`.
  - `proyecto-consolidado-en-un-host.md`: **actualizada esta sesión** con la estructura por servicios.
- PDF de la Entrega 1: `C:\Users\jafet\Downloads\Entrega-1-Proyecto-RC-302-G6 (2).pdf`. Read falla por falta de `pdftoppm`; `pdftotext` sí funciona. La extracción está en `scratchpad/entrega1.txt` (scratchpad de esta sesión, ver Evidence).

## The Goal

El usuario está cerrando el proyecto final de Redes Corporativas: la intranet del Zoológico "Reserva Viva", con 4 aplicaciones (OpenVPMS para Médica, Pretix para Taquilla, InvenTree para Logística y ERPNext/HR para RRHH) más la infraestructura (OpenLDAP con LDAPS y CA interna, bind9 y NTP), segmentadas por VLAN.

El 26/09 decidió que se entrega y se explica **como un sistema de un solo host**, para reducir la curva de aprendizaje, y en esta sesión que el repositorio se organiza **por servicios**. El seq 6 pedía, en palabras del usuario, *"consolidar todo lo de un host eliminando lo que no corresponda, y consolidarlo y crear los documentos de la documentación correspondiente"*, y eso ya está hecho.

El estado final deseado es este: master con el PR #34 fusionado; plug-and-play intacto (clonar, ejecutar `levantar-sistema.ps1` y listo); las 4 apps usables en un navegador; y cada pendiente documentado, resuelto o decidido por el usuario.

## Where We Are

- **Rama `docs/consolidacion-un-host`**, igual a `origin` en `8c9efce`, con 16 commits sobre master `93b106d` más el del seq 6 (`06d6b4e`). Tabla 1.
- **PR #34** OPEN, `mergeable: MERGEABLE`, `mergeStateStatus: CLEAN`, sin checks de CI (el repo no tiene CI). Vinculado a la sesión con `ccd_pr`. Auto-merge desactivado. **El usuario fusiona los PR por su cuenta** (lo hizo con #31, #32 y #33): antes de nada, `gh pr view 34`.
- **El remoto de GitHub se renombró**: `J4F3ET/UD.RedesCorporativa.ProyectoFinal`. El push avisa de que "el repo se movió", pero funciona por redirección. El `origin` local no se ha actualizado.
- **Estructura** (75 ficheros versionados; antes 70):

  | Carpeta | Ficheros |
  |---|---:|
  | `diseno-red/` | 33 |
  | `servicios/` | 19 |
  | `sistema/` | 7 |
  | `docs/` | 7 |
  | `plans/` | 2 |
  | raíz | 7 (`.gitattributes`, `.gitignore`, `README.md`, `docker-compose.yml`, `levantar-sistema.{sh,ps1,cmd}`) |

- **`docker-compose.yml`** (raíz):
  - `name: reservaviva-smoke` y 25 servicios agrupados por departamento.
  - Redes `vlan10_medica`, `vlan20_…`, `vlan30_…`, `vlan40_…`, `vlan99_infra` y `erpnext_internal` (esta última, sin subred fija).
  - Montajes en `./servicios/…`. La CA se monta desde `./servicios/ca/certs/ca.crt` en openldap, inventree-app y erpnext-backend.
  - Los puertos se publican en `${PUBLISH_IP:-0.0.0.0}` / `${DNS_BIND_IP:-0.0.0.0}`: 9 entradas, y `test.env` fija 127.0.0.1.
  - `inventree-app` tiene `command: ["sh","-c","invoke static && exec gunicorn … $${INVENTREE_WEB_ADDR}…"]` (H22).
  - El requisito de Compose ≥ 2.24.4 se mantiene, explicado en un comentario, aunque ya no se usa `!override`.
- **`sistema/test.env`:**
  - Sin `IP_PC2`, `IP_PC3` ni `IFACE`.
  - Conserva `PUBLISH_IP`/`DNS_BIND_IP=127.0.0.1`, los puertos 18080-18083 y 1389/1636/1053/1123, y `PRETIX_ADMIN_EMAIL`.
  - Los secretos no se muestran.
  - **Sigue versionado en git** (`git ls-files`).
- **`levantar-sistema.sh`** (ASCII y LF; `bash -n` OK):
  - `dc()` se ejecuta desde la raíz con `--env-file sistema/test.env`.
  - `generar_zona` deriva las 7 `IP_*` de `NET_*`.
  - **Nueva `reiniciar_dns_si_zona_nueva`**: bind9 no relee la zona y `dns-interno` no se recrea si el `config` no cambia.
  - `preparar` hace `test -s` de `ca.crt`, `ldap.crt` y `ldap.key`, probado con los casos "falta", "es un directorio" y "ok".
  - `accesos()` sin "PC-x".
  - La cabecera sigue el orden real del `.ps1` (Docker Desktop si está en marcha y, si no, WSL).
  - El comentario de `MIN_VM_GIB` remite a resultados.
  - El mensaje de tiempo agotado añade "(desde PowerShell: -TimeoutMin 90)".
- **`sistema/verificar_arquitectura.py`:**
  - `bloque_dns` compara los **7 nombres** de la zona con `docker inspect` del contenedor. Si no coinciden, es FAIL.
  - `rrhh` se compara con **`erpnext-hr`** (10.10.40.10): es el nginx que escucha en 8080 y el único que publica 18081.
  - `ZONA` apunta a `servicios/bind9/zones/`.
  - Los `subprocess` de compose se ejecutan desde la raíz con `--env-file`.
- **`sistema/ldaplogin.py`:** el caso 4 hace `docker compose --env-file sistema/test.env down` y `up -d` desde la raíz. Verificado con rc=0.
- **`servicios/ca/generar-certificados.sh`:**
  - Salida en `servicios/ca/certs/`, sin el bucle de copia a pc1/pc2.
  - `REPO_ROOT` resuelto para la nueva profundidad.
  - Conserva el arreglo del uid 911.
- **`.gitignore`:**
  - `servicios/ca/certs/` y la zona generada `servicios/bind9/zones/db.reservaviva.local`.
  - `.claude/` (nuevo), para los worktrees de agentes.
  - `sistema/resultados/`.
- **Última pasada de `verificar`** (completa, 26/09 22:46): **PASS=99 FAIL=0 INFO=13, RC=0, "VEREDICTO GLOBAL: PASS"**. Informe: `sistema/resultados/verificacion-20260926-224652.txt`.
- **Sistema vivo:** 22 contenedores Up más 3 `Exited (0)` (erpnext-configurator, erpnext-create-site y erpnext-ldap-config); 0 unhealthy. Sesión keepalive `reservaviva-keepalive` activa.
- **`docker.service` `ExecMainStartTimestamp=Sat 2026-09-26 21:13:43 -05`**, igual antes y después del trabajo del agente de código. **No coincide con el 17:01:17 del seq 6**: el demonio se reinició entre sesiones, por causa desconocida y antes de que empezara el trabajo.
- **Volúmenes:**
  - Los 12 con nombre `reservaviva-smoke_*` son idénticos antes y después de la Fase 3.
  - Los anónimos pasaron de 65 a 74 durante la Fase 2 (recreaciones y el `down`/`up` del caso 4). No se borraron: está prohibido.
- **En el navegador integrado**, comprobado por el coordinador:
  - **Pretix** `http://localhost:18082/control/login` carga. Un POST con `prueba-inexistente@reservaviva.local` y una clave inventada responde "Nuestro sistema no reconoce esta combinación de credenciales". Por tanto, ni CSRF ni `Host` bloquean.
  - **InvenTree** `http://localhost:18083/web` redirige a `/web/login` y **renderiza** el formulario de login ("Login / Username / Password", versión 1.5.5 | 530). Antes de H22 mostraba "INVE-E1".
  - **El login real con las claves de laboratorio NO se ha hecho**: el clasificador de auto mode denegó leer `PRETIX_ADMIN_PASSWORD` de `test.env` ("Credential Materialization"). No se intentó sortearlo. Lo tiene que hacer el usuario.
- **Worktrees:**
  - 6 eliminados: `ProyectoFinak-docs`, `-juan`, `-pin`, `-sim`, `UD…-ldap` y `UD…-red`.
  - 2 conservados por tener ficheros sin versionar:
    - `D:/Proyectos/ProyectoFinak-ldap`: 2 handoffs antiguos del 19/09, que también están en git.
    - `D:/Proyectos/ProyectoFinak-off`: `scripts/preparar-imagenes-offline.sh`, **que NO está en git**.
  - 4 worktrees de agentes de esta sesión bajo `.claude/worktrees/` (`agent-a1782ec5…`, `agent-ac82ea4d…`, `agent-af479db2…` y `agent-afc28bc3…`), con sus ramas `worktree-agent-*`. Todo su contenido ya está integrado en la rama.
- **Suites sin Docker:** `bash servicios/openvpms/test-reanudable.sh` y `bash servicios/erpnext/test-create-site.sh` → "TODO PASA" (tras la Fase 3).
- **Enlaces:** todos los enlaces relativos de `README.md`, `docs/*.md`, `servicios/*/README.md` y `sistema/*.md` resuelven, comprobado por el coordinador con el bucle `grep -oE '\]\([^)#]+'` + `test -e`. Las anclas `#3-ldap-y-ldaps` y `#qué-no-aísla-un-solo-host-limitación-conocida` de `seguridad.md` coinciden con sus títulos.
- **Restos:** `git grep -nE "PC-[123]|IP_PC|IFACE|NO VERIFICADO" -- . ':!diseno-red' ':!plans'` = **0**.

## What We Tried (Chronological)

**Bloque temprano: Fase 0 y reparto**

1. **Estado de partida.**
   - `git status` limpio; `gh pr list --state open` vacío.
   - `levantar-sistema.ps1 estado` tardó más de 180 s, la herramienta lo pasó a segundo plano y terminó con RC=0: 22 en marcha más 3 `Exited (0)`.
   - `config-antes.yml` del scratchpad del seq 6 **no existía**. Se regeneró con `wsl.exe -d Ubuntu-24.04 --cd "…\sistema" --exec bash -c 'docker compose --env-file test.env config'` → 869 líneas, rc=0 (idéntica en tamaño a la del seq 6).
2. **AskUserQuestion con 4 preguntas.** La respuesta 2 (texto libre: "un docker compose y carpetas por servicios") contradecía la 1 ("Solo limpiar").
   - No se eligió por el usuario. Una segunda pregunta ofreció 3 opciones con vista previa: "1 compose + carpetas (Recom.)", "Compose por servicio" (un compose por carpeta unido con `include:`) y "Solo limpiar".
   - Respuesta: **"1 compose + carpetas"**.
3. **Memoria.** Se actualizó `proyecto-consolidado-en-un-host.md`: descripción, un párrafo nuevo sobre la estructura por servicios, la variante descartada y "no volver a la estructura por PC".
4. **Reparto.**
   - `ListAgents` → 3 peers. `list_sessions` mostró que todas trabajaban en otros directorios, así que no se les delegó nada.
   - Se escribió `scratchpad/mapa-rutas.md` (el mapa origen → destino vinculante para todos los agentes) antes de lanzar ninguno.
5. **Comprobación previa a los encargos.** `grep` de `cwd=AQUI` en `ldaplogin.py:72` y `verificar_arquitectura.py:211`, y de `docker compose down` sin `--env-file` en `ldaplogin.py:187`.
   - Hallazgo: al mover el compose a la raíz, el caso 4 se habría roto sin avisar (variables `:?` sin definir o compose no encontrado).
   - Se metió en el encargo como trampa explícita. El agente lo adaptó y el caso 4 dio rc=0.

**Bloque intermedio: ejecución en paralelo**

6. **Agente de código** (general-purpose, checkout principal, unos 70 min y 150 herramientas). Fases 1, 2a-2d, 3 y cierre en 7 commits (Tabla 1).
   - 2a en rojo antes del arreglo: 95 PASS / 5 FAIL / 13 INFO. Los 4 FAIL eran de la zona (`dns` .99.10≠.11, `ntp` .99.10≠.12, `pretix` .30.10≠.20.10, `rrhh` .99.10≠.40.10) y el quinto, el marcador de `--rapido`.
   - Tras el arreglo: 99/1(marcador)/13 en las rápidas y 99/0/13 en las completas.
   - **Errores propios que corrigió:**
     - Un `git add -A` metió `.claude/worktrees/*` como gitlinks en el commit de la Fase 1; lo arregló con `--amend` antes del push.
     - Un heredoc de Git Bash se comió una `\\` y dejó un `\n` literal en `levantar-sistema.sh`; lo corrigió antes del commit.
     - Creó un fichero vacío `REFUSED` en la raíz y lo borró.
   - **Descubrimientos:**
     - Pretix: `ALLOWED_HOSTS=['*']`, `CSRF_TRUSTED_ORIGINS=[esquema://host sin puerto]` y un `MultiDomainMiddleware` que responde 400 a un `Host` distinto del de la URL, salvo `localhost`/`testserver`.
     - InvenTree: `ALLOWED_HOSTS` de `config.yaml` (`'*'`) más el host de la URL; `CSRF_TRUSTED_ORIGINS` y `CORS` = `[SITE_URL]`.
     - **H20 rompía InvenTree de verdad**: `/web` daba 500 INVE-E7 antes de `41d54ef`.
7. **Agentes de `seguridad.md` y `aplicaciones.md`** (worktrees, en paralelo con el de código, unos 5 min cada uno).
   - Nacieron en `93b106d`, no en HEAD: el worktree del Agent parte de otra base. Se adelantaron con `git merge --ff-only 06d6b4e`.
   - Escribieron contra las rutas FINALES del mapa; en sus worktrees esos enlaces aún no resolvían, y era lo esperado.
   - Aplicaciones:
     - Leyó la Entrega 1 con `pdftotext`.
     - Eliminó 6 worktrees con `git worktree remove` sin `--force`; conservó 2 con ficheros sin versionar.
   - Seguridad descubrió:
     - Solo hay UNA cuenta de servicio de bind (`cn=svc-lectura,ou=servicios`), compartida por ERPNext e InvenTree.
     - No hay grupos LDAP, solo OU.
     - `10-estructura.ldif` tiene la clave de `svc-lectura` en un comentario.
     - Las claves de `test.env` solo se aplican al inicializar, así que cambiarlas no rota nada en un sistema ya levantado.
8. **Verificación de fugas por el coordinador** (sin mostrar valores). Se comparó cada valor de las 12 variables `*PASSWORD|SECRET|KEY*` de `test.env` y las cadenas del README de LDAP con `seguridad.md` y `aplicaciones.md`: **0 fugas**.
9. **Integración.** `git merge --no-edit` de las ramas `worktree-agent-*`. Todos fueron merges limpios, porque cada agente solo añadía su fichero.

**Bloque tardío: arquitectura/operación, H22 y PR**

10. **Agentes de `arquitectura.md` y `operacion.md`** (worktrees, en paralelo, tras el código). Arrancaron con `git merge --ff-only docs/consolidacion-un-host` y el ff funcionó.
    - Arquitectura contrastó CADA IP y puerto con `grep` sobre el compose y `test.env`: 0 diferencias.
    - Arquitectura descubrió que **ninguna app es cliente de `ntp-interno`**: `NTP_HOST`/`DNS_HOST`/`LDAP_HOST` de openvpms-app y `LDAP_HOST` de erpnext-backend son informativas, y solo las usa `verificar`.
    - Operación cambió README, `.gitignore` y la viñeta de H20 de `aplicaciones.md`, y listó 7 textos desfasados fuera de sus ficheros.
11. **Prueba del coordinador en el navegador integrado:**
    - Pretix, bien.
    - InvenTree `/web` mostró "If you see this text there might be an issue with your update. See INVE-E1".
    - La consola daba "Failed to load module script: … MIME type of text/html".
    - Un `fetch` desde la página: `/static/web/assets/index-C2rs8w4F.js`, `DesktopAppView-rfLxnOnv.js` y `MobileAppView-CusQqJQQ.js` → 200 `text/html`.
    - **Lección:** el `curl /web` = 200 del agente de código no probaba que la interfaz funcionara.
12. **Agente de diagnóstico** (solo lectura, unos 4 min). Causa raíz de H22 verificada:
    - `STATIC_ROOT=/home/inventree/data/static` estaba **vacío** (0K, fecha del 21/09).
    - Whitenoise está en `settings.py:378` pero solo indexa al arrancar (`autorefresh=DEBUG=False`).
    - `INVENTREE_AUTO_UPDATE=True` solo migra (`InvenTree/tasks.py:1041`); `invoke static` solo lo llama `invoke update` (`/home/inventree/tasks.py:1188`).
    - Sin fichero, la ruta cae en `re_path(r'^.*$', RedirectView('/web'))` → 302.
    - También explicó `bad_origin` (Problema 2) y detectó `/media`.
13. **Agente de arreglo final** (checkout principal, unos 19 min).
    - Leyó el CMD real con `docker image inspect`: `["sh","-c","exec gunicorn -c ./gunicorn.conf.py InvenTree.wsgi -b ${INVENTREE_WEB_ADDR}:${INVENTREE_WEB_PORT} --chdir ${INVENTREE_BACKEND_DIR}/InvenTree"]`, con ENTRYPOINT `["/bin/bash","./init.sh"]` (que termina en `exec "$@"`) y WorkingDir `/home/inventree`.
    - Antepuso `invoke static &&`, sin `--skip-plugins`: `ready.py` excluye `collectstatic`/`collectplugins` del acceso a la base.
    - Resultado: JS 200 `text/javascript` (1.024.061 bytes), favicon 200 `image/png`, `STATIC_ROOT` con 71M y el segundo `arrancar` idempotente.
    - `verificar` completo 99/0/13, RC=0.
    - Después hizo el commit de documentación (8 puntos) y el push.
    - **Anomalía:** el primer `arrancar` lanzado desde Git Bash devolvió **RC=2** aunque el log decía "Sistema en marcha: los 25 servicios estan sanos". El segundo, desde PowerShell, dio RC=0. Causa sin identificar.
14. **Comprobación final del coordinador:**
    - InvenTree `/web` → `/web/login` renderiza.
    - `git status` al día con origin.
    - `verificar` 224652 PASS=99 FAIL=0.
    - `gh pr create` → #34, y `ccd_pr get_status` → vinculado, CLEAN.

## Key Decisions

- **Estructura por servicios con UN compose en la raíz** (usuario). Se rechazó la opción "un compose por servicio unido con `include:`": 8 ficheros compose y más superficie. También se rechazó "Solo limpiar".
- **Se mantienen el nombre de proyecto, las claves de red, servicio y volumen y los `container_name`.** Cambiarlos crea volúmenes nuevos y obliga a reinicializar (unos 30 min). La Fase 3 se validó con `config` normalizado equivalente y con los mismos 12 volúmenes.
- **Orden: Fase 2 semántica sobre la estructura vieja y DESPUÉS la fusión**, para que el diff de la Fase 3 solo mostrara cambios de rutas. Se rechazó hacer la Fase 2 directamente en el compose nuevo, porque habría mezclado cambios semánticos y de estructura en un mismo diff.
- **La CA única se hizo en la Fase 3 (2e)**, no antes: la ruta final (`servicios/ca/certs/`) no existía en la estructura vieja. La CA se **movió** (mismo sha256 y huella), no se regeneró.
- **`rrhh` → `erpnext-hr` (el nginx, 10.10.40.10) y no `erpnext-backend`**: es lo que atiende HTTP a los usuarios y publica 18081.
- **H20: `http://localhost:<puerto>`** en `PRETIX_PRETIX_URL` e `INVENTREE_SITE_URL`. Pretix solo acepta ese `Host` o `localhost`: `127.0.0.1:18082` da 400, así que se documenta "entrar por localhost".
- **H22, opción "a"** (el `command` con `invoke static && exec <CMD original>`). Se descartaron:
  - "a'": `invoke static` más un reinicio en `levantar-sistema.sh` en cada arranque.
  - "b": un proxy Caddy/nginx. Es un contenedor nuevo, obliga a descargar una imagen que no está en local y **no bastaría sin a**.
  - "c": `INVENTREE_DEBUG=True`, que es el modo desarrollo en producción.
- **Los defaults de publicación `0.0.0.0` se conservan** (el coordinador se lo pidió explícitamente al agente de código, para que el `config` fuera equivalente). Queda como propuesta cambiarlos a `127.0.0.1`: es un cambio semántico que decide el usuario.
- **El montaje de la CA no se añadió a openvpms-app ni a pretix-web**: no usan LDAP.
- **El ancla YAML `erpnext_volumes`** se definió dentro de `erpnext-configurator` y no como `x-erpnext-volumes`, para que el `config` no ganara un campo de extensión.
- **No se tocó la clave de laboratorio del comentario de `10-estructura.ldif`**: la decide el usuario. Recomendación: dejarla, porque está documentada en `seguridad.md` y `test.env` ya está versionado.
- **No se hizo el login con las claves reales** tras la denegación del clasificador. No se buscó otra vía; se documentó como pendiente del usuario.

## Evidence & Data

### Tabla 1: Commits de la rama `docs/consolidacion-un-host` (sobre master `93b106d`)

| Commit | Qué | Autor |
|---|---|---|
| `06d6b4e` | handoff y plan del seq 6 | sesión anterior |
| `2a3d6fe` | Fase 1 cosmética: `test.env` sin `IFACE`; etiquetas y comentarios sin PC-x | agente de código |
| `de18b7a` | 2a: `verificar` compara los 7 nombres de la zona | agente de código |
| `4b7aadb` | 2b (H21): zona con `IP_*` por nombre; `reiniciar_dns_si_zona_nueva` | agente de código |
| `89927f0` | 2c: LDAP/DNS/NTP por la IP real; fuera `IP_PC3` | agente de código |
| `41d54ef` | 2d (H20): URL `http://localhost:<puerto>`; fuera `IP_PC2` | agente de código |
| `9593b14` | Fase 3: un `docker-compose.yml` en la raíz y `servicios/`; CA única. Lleva "COMO RECUPERARLO" | agente de código |
| `c7e4728` | cierre: resultados, H20/H21 resueltos | agente de código |
| `cf71089` | `docs/seguridad.md` | agente de seguridad |
| `06ff8ce` | `docs/aplicaciones.md` | agente de aplicaciones |
| `536e05a` / `ef65ea0` | merges de seguridad y aplicaciones | coordinador |
| `0563014` | `docs/arquitectura.md` | agente de arquitectura |
| `2db8eec` | `docs/operacion.md`, README (Documentación), `.gitignore` (`.claude/`) y H20 en aplicaciones | agente de operación |
| (merge) / `5fb3590` | merges de arquitectura y operación | coordinador |
| `afabb20` | H22: `invoke static` antes de gunicorn (+5 líneas en el compose) | agente de arreglo |
| `8c9efce` | documentación al día (H22, `/media`, `bad_origin` y 7 textos desfasados) | agente de arreglo |

PR #34: https://github.com/J4F3ET/UD.RedesCorporativa.ProyectoFinal/pull/34, abierto a las ~23:10 del 26/09 (hora de Bogotá). Cuerpo en `scratchpad/pr.md`.

### Tabla 2: Subagentes de esta sesión

| Agente | Tipo y aislamiento | Duración | Entregó | Verificado por el coordinador |
|---|---|---|---|---|
| Código (Fases 1-3) | general-purpose, checkout principal | ~69 min, 150 herramientas, 404K tokens | 7 commits, push | `git log`, `ls`, grep de restos = 0, informe 221919 99/0 |
| Seguridad | general-purpose, worktree | ~5 min | `seguridad.md` (261 líneas) | fugas = 0, anclas OK |
| Aplicaciones y worktrees | general-purpose, worktree | ~5 min | `aplicaciones.md` (139 líneas), 6 worktrees eliminados | fugas = 0, `git worktree list` |
| Arquitectura | general-purpose, worktree | ~3,5 min | `arquitectura.md` (290 líneas, Mermaid) | enlaces y anclas |
| Operación | general-purpose, worktree | ~5 min | `operacion.md` (168 líneas), README, `.gitignore`, H20 | enlaces (todos resuelven tras integrar) |
| Diagnóstico H22 y `bad_origin` | general-purpose, checkout principal, solo lectura | ~4 min | causa raíz y opciones a/a'/b/c | coherente con lo visto en el navegador |
| Arreglo H22 y documentación | general-purpose, checkout principal | ~19 min | `afabb20`, `8c9efce`, push | InvenTree `/web/login` renderiza; informe 224652 |

### Tabla 3: Pasadas de `verificar` de esta sesión (informes en `sistema/resultados/`)

| Informe | Tipo | Momento | PASS / FAIL / INFO | Nota |
|---|---|---|---|---|
| `…-212844.txt` | rápida | 2a, antes de arreglar la zona | 95 / 5 / 13 | 4 FAIL de zona más el marcador de `--rapido` (prueba de que el test detecta H21) |
| `…-213716.txt` | rápida | tras 2b | 99 / 1 / 13 | el FAIL es el marcador |
| `…-214552.txt` | rápida | tras 2c | 99 / 1 / 13 | ídem |
| `…-215448.txt` | rápida | tras 2d | 99 / 1 / 13 | ídem |
| `…-215946.txt` | **completa** | fin de la Fase 2 | **99 / 0 / 13, RC=0** | |
| `…-221919.txt` | **completa** | tras la Fase 3 | **99 / 0 / 13, RC=0** | caso 4 `down`/`up` con `--env-file` rc=0 |
| `…-224652.txt` | **completa** | tras H22 | **99 / 0 / 13, RC=0** | `/static` sigue en 200 tras el `down`/`up` |

Por qué 99 y no 92: el INFO "dns/ntp/ldap apuntan…" pasó a ser 7 PASS, uno por nombre. Los 13 INFO son 12 parejas app↔app por vlan99 (hallazgo previsto: vlan99 es un único dominio L2) más `chronyc sources` (contexto de H11).

### Tabla 4: Diffs de `docker compose config` por tanda (ficheros en el scratchpad)

| Tanda | Ficheros | Diff |
|---|---|---|
| línea base | `config-antes.yml` (869 líneas) | — |
| Fase 1 | `config-f1.yml` | **vacío** |
| 2b | `config-2b.yml` | **vacío** (la zona no está en el compose) |
| 2c | `config-2c.yml` | 2 líneas (`DNS_HOST` y `NTP_HOST` de openvpms-app) |
| 2d | `config-2d.yml` | 7 líneas (5 URL y 2 `Host` de sondas) |
| Fase 3 | `config-fase2-final.norm.yml` frente a `config-f3.norm.yml`; crudo en `config-f3-diff-crudo.txt` | normalizados: **ninguna diferencia**; en crudo, 8 orígenes de bind mount y el `build.context` de openvpms |
| H22 | `config-h22-antes.yml` frente a `config-h22-despues.yml` | solo añade el `command` de inventree-app |

### Tabla 5: Direcciones y zona tras la consolidación

| Nombre de la zona | IP | Contenedor | Antes (seq 6) |
|---|---|---|---|
| `dns` | 10.10.99.11 | dns-interno | 10.10.99.10 (openldap) |
| `ldap` | 10.10.99.10 | openldap | igual |
| `ntp` | 10.10.99.12 | ntp-interno | 10.10.99.10 |
| `openvpms` | 10.10.10.10 | openvpms-app | igual |
| `pretix` | 10.10.20.10 | pretix-web | 10.10.30.10 (inventree) |
| `inventree` | 10.10.30.10 | inventree-app | igual |
| `rrhh` | 10.10.40.10 | erpnext-hr (nginx) | 10.10.99.10 |

IP en vlan99 de las apps: openvpms-app .24, pretix-web .21, inventree-app .22 y erpnext-backend .23 (y 10.10.40.11 en vlan40). Detalle completo en `docs/arquitectura.md`.

### Tabla 6: H22, antes y después (InvenTree 1.5.5, `inventree/inventree:1.5.5@sha256:5dc64d7c…`, Python 3.14.7, whitenoise 6.12.0)

| Prueba | Antes | Después |
|---|---|---|
| `curl -sI …/static/web/assets/index-C2rs8w4F.js` | `302 Found`, `Location: /web` | `200`, `text/javascript`, 1.024.061 bytes |
| `…/static/img/favicon/favicon-32x32.png` | 302 | 200 `image/png` |
| `du -sh /home/inventree/data/static` | 0K (vacío desde el 21/09) | 71M |
| Navegador `/web` | "INVE-E1" y "Failed to load module script … text/html" | redirige a `/web/login` y muestra el formulario (1.5.5, API 530) |
| Segundo `arrancar` | — | RC=0, sin recrear inventree-app, sin tracebacks |
| Tras el `down`/`up` del caso 4 | — | "Static files collected successfully"; 200 |

### Tabla 7: Opciones evaluadas para H22 (del diagnóstico)

| Opción | ¿Contenedor nuevo? | ¿Cambia el `config`? | ¿Descarga? | Veredicto |
|---|---|---|---|---|
| a) `command` = `invoke static && exec <CMD>` | No | Sí, solo el `command` | No | **Elegida** |
| a') `exec invoke static` + `restart` en `levantar-sistema.sh` | No | No | No | Reinicio en cada arranque |
| b) Caddy o nginx delante | Sí (el 26.º) | Sí: puertos a otro servicio e IP nueva en vlan30 (.13) | **Sí** (no hay caddy ni nginx en local) | Sigue necesitando a; sería lo único que arregla `/media` |
| c) `INVENTREE_DEBUG=True` | No | Sí | No | Descartada: modo desarrollo |

### Tabla 8: Pretix, `bad_origin` (Pretix 2026.7.0)

| Hecho | Evidencia |
|---|---|
| Origen esperado sin puerto | `control/views/auth.py:116` y `:167`: `good_origin = scheme + '://' + urlparse(SITE_URL).hostname` → `http://localhost` |
| El navegador compara con `http://localhost:18082` | `auth.js` → POST `/control/login/bad_origin` si no coinciden |
| Solo registra un aviso | vista `bad_origin_report`, `@csrf_exempt`: `logger.warning` y 200 |
| Log | `Received report of unexpected origin value. Origin sent from JavaScript: http://localhost:18082 / Expected origin from configuration: http://localhost / HTTP Host header: localhost:18082` |
| Conclusión | Inofensivo; desaparecería sirviendo en el puerto 80. Documentado en `aplicaciones.md` |

### Tabla 9: Decisiones del usuario de esta sesión

| Pregunta | Opciones | Respuesta |
|---|---|---|
| Compose | Solo limpiar (Rec.) / Limpiar y fusionar | Solo limpiar (luego contradicho) |
| Carpetas `docker/pcN-*` | Conservar (Rec.) / Renombrar por departamento | **Otro:** "Borrarlos y crear un solo docker pero lo mejor seria dividir todo por servicios…" |
| Documentos (múltiple) | arquitectura / operación / seguridad / aplicaciones | los 4 |
| Worktrees | Eliminarlos (Rec.) / Conservarlos | Eliminarlos |
| Estructura (repregunta) | 1 compose + carpetas (Rec.) / Compose por servicio / Solo limpiar | **1 compose + carpetas** |

### Tabla 10: Decisiones PENDIENTES del usuario (ofrecidas en el chat, sin respuesta)

| Tema | Recomendación del coordinador | Alternativa |
|---|---|---|
| `/media` de InvenTree | Dejarlo documentado como pendiente (ya lo está) | Proxy (contenedor 26.º y descarga de imagen, con permiso) |
| Clave de laboratorio en el comentario de `servicios/openldap/10-estructura.ldif` | Dejarla (documentada en `seguridad.md`; `test.env` ya está versionado) | Quitarla del comentario (el LDIF solo se carga con `ldap_data` vacío) |
| Worktree `D:/Proyectos/ProyectoFinak-ldap` (2 handoffs del 19/09 sin versionar; también en git) | Borrarlo | Conservarlo |
| Worktree `D:/Proyectos/ProyectoFinak-off` (`scripts/preparar-imagenes-offline.sh`, NO en git) | Conservarlo | Borrarlo (se pierde el fichero) |
| `PUBLISH_IP`/`DNS_BIND_IP` con valor por defecto `0.0.0.0` | Proponer `127.0.0.1` (más seguro si falta `test.env`) | Dejarlo igual |
| Fusionar el PR #34 | El usuario suele fusionar por su cuenta | — |

### Tabla 11: Pendientes vigentes (fuente: `docs/resultados-un-host.md` § Pendientes, 12 filas)

| ID | Qué | Tipo |
|---|---|---|
| H12 | Cita de OpenLDAP 2.6 en la bibliografía de la Entrega 1 | documentación |
| H17 | Arranque en frío con volúmenes vacíos sin repetir desde el arreglo (`start_period` 600 s; se midieron 484 s) | validación |
| — | `erpnext-create-site` recibe contraseñas por argv | seguridad (laboratorio) |
| — | SIGKILL 137 en `inventree-worker` y `pretix-cron`, sin analizar | robustez |
| — | Ningún `mem_limit` | robustez |
| — | `performance_schema=1` en openvpms-db | memoria |
| — | Modo Docker Desktop + Git Bash sin probar | validación |
| — | Simuladores de `diseno-red/` sin reejecutar (`nicolaka/netshoot`) | validación |
| — | Switch L2/L3 sin hardware real | limitación |
| — | Rotar las claves si el repo se hace público | seguridad |
| — | `/media` de InvenTree | funcionalidad |
| — | Login real de Pretix con `admin@reservaviva.local` | validación (usuario) |

No están en esa tabla y son de esta sesión:
- el RC=2 de `arrancar` desde Git Bash;
- `verificar` no cubre la interfaz web (H22 pasó desapercibido);
- los volúmenes anónimos acumulados (74);
- el `origin` sin actualizar tras el renombrado del repo;
- los 4 worktrees de agentes bajo `.claude/worktrees/`;
- que ninguna app sincroniza con `ntp-interno`, algo solo informativo que conviene decidir si se documenta como limitación o se configura.

### Ficheros de datos (scratchpad de ESTA sesión, no versionados)

Directorio: `C:\Users\jafet\AppData\Local\Temp\claude\D--Proyectos-UD-RedesCorporativaa-ProyectoFinak\d2d22f9b-c4f1-4932-b9f6-fb4f5807a0b1\scratchpad\`
- `mapa-rutas.md`: el mapa origen → destino vinculante de la Fase 3.
- `config-antes.yml`, `config-f1.yml`, `config-2b.yml`, `config-2c.yml` y `config-2d.yml`; `config-fase2-final{,.norm}.yml`, `config-f3{,.norm}.yml` y `config-f3-diff-crudo.txt`; `config-h22-{antes,despues}.yml`.
- Logs: `f2a-verificar-rapido.log`, `f2b-*.log`, `f2c-*.log`, `f2d-*.log`, `f2-verificar-completo.log`, `f3-arrancar.log`, `f3-verificar-completo.log`, `arrancar1.log` y `arrancar2.log` (H22). Hay que leerlos con `tr -d '\000'`.
- HTTP y CSRF: `f2d-antes-http.txt`, `f2d-despues-http.txt`, `f2d-csrf.txt`, `csrf-check.sh` y `sondas-http.sh`.
- Volúmenes y demonio: `volumenes-antes.txt`, `volumenes-pre-f3.txt`, `volumenes-post-f3.txt`, `docker-ts-inicio.txt` y `estado-post-f3.txt`.
- `entrega1.txt`: el PDF de la Entrega 1 en texto.
- `pr.md`: el cuerpo del PR #34.
- Scripts de edición de los agentes: `e2b.py`, `e2c.py`, `e2d.py`, `e3-*.py`, `ed.py` y `ed2.py` (helpers que respetan CRLF/LF).

## Code Analysis

- **`docker-compose.yml`, `inventree-app`** (línea ~322): la imagen va fijada por digest. El comentario de H22 está en la línea ~330 y el `command` en la ~332. Los `$` del shell del contenedor van escapados como `$$`. `inventree-worker` sigue con `command: ["invoke", "worker"]` (línea ~401) y `depends_on inventree-app: service_healthy`.
- **Imagen de InvenTree:**
  - ENTRYPOINT `["/bin/bash","./init.sh"]`: `init.sh` crea los directorios, hace `cd ${INVENTREE_HOME}` y `exec "$@"`.
  - `settings.py:250-256`: `STATICFILES_DIRS` solo con DEBUG. `settings.py:378`: `WhiteNoiseMiddleware`.
  - `urls.py:171-176`: `static()` solo con DEBUG. El comodín final `RedirectView('/web')`.
  - `invoke static` lleva `--clear` por defecto, así que es idempotente.
  - Sin DEBUG no hay ruta para `/media` (`curl /media/x.png` sin sesión → 401).
- **Pretix 2026.7.0:** `control/views/auth.py:116/:167` (`good_origin` sin puerto); `MultiDomainMiddleware` → 400 si el `Host` no es el de `PRETIX_PRETIX_URL` o `localhost`. Por eso `127.0.0.1:18082` no sirve.
- **`levantar-sistema.sh`:**
  - `RAIZ`; `ARNES="${RAIZ}/sistema"`; `ENV_FILE`.
  - `dc()` = `docker compose --env-file sistema/test.env` desde la raíz.
  - `valor_env NAME DEFAULT`.
  - `preparar_certificados` llama a `servicios/ca/generar-certificados.sh --sin-instalar-ca`.
  - `generar_zona` hace `sed` sobre `servicios/bind9/zones/db.reservaviva.local.tpl` con las 7 `IP_*` derivadas de `NET_*` (mismos valores por defecto que el compose).
  - `reiniciar_dns_si_zona_nueva`, `esperar_sano`, `crear_admin_pretix` (H19) y `accesos`.
  - Acciones `arrancar`, `preparar`, `estado`, `verificar`, `detener` y `borrar`.
- **`levantar-sistema.ps1`:**
  - Prueba primero Docker Desktop (`docker info`) y si no, WSL (`wsl.exe -d Ubuntu-24.04 --cd $Repo -- bash ./levantar-sistema.sh`).
  - Umbral `$MinLibreGB` 6,9 GB, `-Forzar` y `-TimeoutMin`.
  - Keepalive `reservaviva-keepalive`.
  - El `.sh` exige `MIN_VM_GIB` 6 GiB y avisa por debajo de 5 GiB libres.
- **`sistema/verificar_arquitectura.py`:** `AQUI`/`RAIZ` y `ZONA` en `servicios/bind9/zones/db.reservaviva.local`. `bloque_dns` compara los 7 nombres con `docker inspect`. El autotest espera 10.10.99.10 para `ldap` y no cambió. **No hay ninguna sonda de la interfaz web (estáticos o JS).**
- **`sistema/ldaplogin.py`:** `esperar_apps(limite=1500)` y el caso 4 con `--env-file sistema/test.env` desde la raíz. La rama de reintento de H18 sigue sin ejercitarse.
- **LDAP:**
  - Una sola cuenta de servicio de bind, `cn=svc-lectura,ou=servicios`, más `cn=admin`.
  - Sin grupos, solo OU; `ldap_search_path_group` de ERPNext apunta a `ou=rrhh`.
  - Las reglas `{0}`/`{1}` de la ACL vienen de la imagen `osixia/openldap`.
- **Nombres de compose frente a contenedores:** los servicios `dns` y `ntp` corresponden a los contenedores `dns-interno` y `ntp-interno`. `docker compose logs dns` usa el nombre del servicio.

## Files Changed

### Estructura y código (agente de código, `2a3d6fe`..`c7e4728`, y de arreglo, `afabb20`)
- `docker-compose.yml` (**nuevo**, raíz): fusión de los 3 compose y los 3 overrides, más H20, 2c y H22.
- Borrados: `docker/pc{1,2,3}-*/docker-compose.yml`, `sistema/docker-compose.yml` y `sistema/override-pc{1,2,3}.yml`.
- `git mv` a `servicios/`:
  - `openvpms/{Dockerfile,entrypoint.sh,init-lib.sh,test-reanudable.sh}`;
  - `openldap/{05-acl-servicio,10-estructura,20-usuarios-prueba}.ldif` y `README.md`;
  - `bind9/named.conf` y `zones/db.reservaviva.local.tpl`;
  - `erpnext/test-create-site.sh`;
  - `ca/generar-certificados.sh`.
- Nuevos: `servicios/{bind9,ca,erpnext,inventree,ntp,openvpms,pretix}/README.md`.
- `levantar-sistema.sh`: invocación desde la raíz, zona por nombres, `reiniciar_dns_si_zona_nueva`, comprobación de certificados en `preparar`, etiquetas, cabecera, `MIN_VM_GIB` y mensaje de tiempo agotado.
- `sistema/verificar_arquitectura.py` (`bloque_dns` con 7 nombres, `ZONA`, cwd y `--env-file`) y `sistema/ldaplogin.py` (caso 4).
- `sistema/test.env`: sin `IFACE`, `IP_PC2` ni `IP_PC3`; comentarios.
- `.gitignore`: rutas de `servicios/`, `.claude/`.

### Documentación
- Nuevos: `docs/arquitectura.md`, `docs/operacion.md`, `docs/seguridad.md` y `docs/aplicaciones.md`.
- `README.md`: sección Documentación, requisitos condensados y mapa del repositorio.
- `docs/resultados-un-host.md`: pasadas 212844 a 224652, H20, H21 y H22 resueltos, y 2 pendientes nuevos.
- `sistema/README.md` y `sistema/verificar_arquitectura.md`: nueva invocación, hallazgos, caso 4 ejecutado y sin "~10 min".
- `docs/integracion-ldap-erpnext-inventree.md` y `docs/ldap-pretix-openvpms.md`: rutas actualizadas por el agente de código.

### Fuera del repo
- Memoria `proyecto-consolidado-en-un-host.md`: estructura por servicios; la decisión E queda revocada.
- Worktrees: 6 eliminados (`git worktree remove`).

## User Feedback & Preferences (REQUIRED)

- **Esta sesión:**
  - Pegó el paste prompt del seq 6 ("Build").
  - A la pregunta de las carpetas respondió con texto propio: *"Borrarlos y crear un solo docker pero lo mejor seria dividir todo por servicios, osea un docker compose y carpetas por servicios asi identificar que es de que cosa"*. Quiere que la estructura del repo **diga qué es cada cosa**.
  - En la repregunta eligió la opción recomendada con vista previa. Aceptó los 4 documentos y eliminar los worktrees.
  - Ejecutó `/usage`: sesión al 4 %, semana al 43 %, cache hit 97 %. Luego ejecutó `/handoffplan` sin argumentos.
  - **No ha respondido** a las decisiones de la Tabla 10.
- **Durante la sesión se alcanzó el límite de uso** y el usuario lo restableció ("Alcancé mi límite de uso mientras trabajabas, pero ya se restableció. Continúa donde lo dejaste").
- **De sesiones anteriores, siguen vigentes:**
  - *"usa los agentes, no operes"* y *"tú eres el cerebro de la operación pero debes ser detallado"* (memoria fijada). Esta sesión se aplicó con 7 subagentes y encargos largos, y el coordinador verificó cada entrega.
  - *"sin tener que sacrificar nada del entregable"*: por eso H22 se arregló, sin darlo por fuera de alcance.
  - *"si al día de mañana necesitamos algo lo restauramos y listo"*: borrar es aceptable si se anota cómo recuperarlo.
  - *"minimizar la curva de aprendizaje del proyecto"*.
  - *"clono repo ejecuto script y listo corriendo el sistema"*: el plug-and-play es innegociable.
  - D: "dejar solo el último" handoff y plan.
  - Los PR van listos para revisión, nunca en borrador; el usuario los fusiona él mismo.
  - Pregunta a menudo *"¿qué nos hace falta?"*: quiere listas de qué depende de él y qué de los agentes.
- **Restricciones de seguridad:**
  - Las claves de `test.env` nunca van a informes, commits, logs ni chat.
  - **Leer una clave de `test.env` en la sesión lo deniega el clasificador de auto mode**, así que los logins reales los hace el usuario.
  - No usar `down -v`, `borrar`, `docker pull`, `wsl --shutdown`, `system prune` ni `Stop-Process` sobre Docker sin permiso.

## Where We're Going

1. **Comprobar el PR #34** con `gh pr view 34 --json state,mergedAt`. Si ya está MERGED, trabajar desde `origin/master`. Si sigue abierto, no fusionarlo sin un "sí" del usuario.
2. **Recoger las decisiones de la Tabla 10** con un único AskUserQuestion: `/media`, la clave del LDIF, los 2 worktrees, el default `0.0.0.0` y la fusión del PR.
3. **Cerrar el hueco de verificación que dejó pasar H22:** añadir a `verificar_arquitectura.py` una sonda de la interfaz web de cada app, que compruebe:
   - que un asset estático referenciado en el HTML devuelve un `content-type` que no es HTML;
   - `/web/login` de InvenTree;
   - `/control/login` de Pretix con su CSRF;
   - `/openvpms/login` y el `/login` de ERPNext.
4. **Limpieza:**
   - `git remote set-url origin https://github.com/J4F3ET/UD.RedesCorporativa.ProyectoFinal.git`;
   - quitar los 4 worktrees de agentes y sus ramas `worktree-agent-*`;
   - los worktrees huérfanos, según la decisión del usuario.
5. **Investigar el RC=2 de `arrancar` lanzado desde Git Bash** cuando el log dice 25/25 sanos.
6. **Deuda de validación**, en orden de valor: el login real de las 4 apps (lo hace el usuario); H17 (frío con volúmenes vacíos, solo con permiso explícito para `borrar`); el modo Docker Desktop; los SIGKILL 137 y `mem_limit`.
7. **Si el usuario aprueba el proxy de `/media`:** un contenedor nuevo con la imagen descargada con permiso. Hay que actualizar `arquitectura.md`, `aplicaciones.md`, `verificar` y los conteos.

## Risks & Blockers

- **El usuario puede haber fusionado el PR #34** entre sesiones (lo hizo con #31-#33): planear sobre master y no sobre la rama.
- **Descargar imágenes y borrar volúmenes requieren permiso explícito.** Bloquean el proxy de `/media` y H17.
- **Los logins reales no los puede hacer un agente**: el clasificador deniega leer las claves de `test.env`. Dependen del usuario.
- **Memoria del host:** cada `verificar` completo cuesta unos 14 min con `down`/`up`. Usar `--rapido` entre tandas.
- **El `ExecMainStartTimestamp` cambió entre sesiones** (17:01:17 → 21:13:43) por causa desconocida. Si vuelve a pasar a mitad de una prueba, invalida la regresión.

## Open Questions

- ¿Por qué `arrancar` lanzado desde Git Bash devolvió RC=2 con el sistema 25/25 sano? ¿El envoltorio de la herramienta o el script?
- ¿Proxy para `/media` sí o no? ¿`0.0.0.0` → `127.0.0.1` sí o no?
- ¿Debe `ntp-interno` tener clientes reales (chrony en los contenedores de las apps) o basta con documentarlo como servicio que solo comprueba `verificar`?
- ¿Por qué se reinició `docker.service` entre el seq 6 y esta sesión?
- ¿Funcionan con las claves reales el login de `taquilla.prueba` en InvenTree (por configuración debería, porque busca en toda `ou=operaciones`) y el botón LDAP de ERPNext en el navegador?

## Anexo A: Trampas nuevas de esta sesión

Se suman a las 16 del seq 6, que siguen vigentes. Están en `git show 8c9efce:plans/handoffs/HANDOFF_…consolidacion-un-host-documentacion_2026-09-26.md` y, redactadas para una persona, en `docs/operacion.md` §7.

| # | Trampa | Qué hacer |
|---|---|---|
| 17 | `git add -A` dentro del checkout principal mete `.claude/worktrees/*` (los worktrees de los agentes) como **gitlinks** | `git add <ficheros concretos>`. Ya hay `.claude/` en `.gitignore` (`2db8eec`) |
| 18 | En Git Bash, los heredocs pueden comerse una `\\` y dejar un `\n` literal | Revisar el diff antes de commitear; usar helpers Python (`scratchpad/e*.py`) |
| 19 | El worktree de la herramienta Agent (`isolation: worktree`) nace en `93b106d` (el master de origin), no en HEAD | El encargo debe empezar con `git merge --ff-only docs/consolidacion-un-host` (o la rama vigente) |
| 20 | Los fines de línea del repo están **mezclados**: `docker-compose.yml`, `sistema/*.md` y `docs/resultados-un-host.md` son LF en la copia de trabajo; otros son CRLF; `*.sh` es LF por `.gitattributes` | Contar con Python (`newline=''`), no con `grep -c $'\r$'`, que da recuentos falsos en Git Bash |
| 21 | Leer una clave de `sistema/test.env` en la sesión → **denegado** por el clasificador de auto mode ("Credential Materialization") | No sortearlo. Los logins reales los hace el usuario. Para pruebas: credenciales inventadas (comprueban CSRF y `Host`) |
| 22 | `curl /web` = 200 **no** demuestra que una SPA funcione (H22: el HTML llegaba y los JS eran HTML) | Comprobar un asset referenciado y su `content-type`, o abrirlo en el navegador integrado y leer la consola |
| 23 | `Read` de un PDF falla sin `pdftoppm` | `pdftotext` sí está instalado |
| 24 | `levantar-sistema.ps1 estado` puede superar los 180 s de la herramienta | `timeout` mayor o `run_in_background` |
| 25 | `arrancar` lanzado desde Git Bash como tarea de fondo devolvió RC=2 con el sistema 25/25 sano | Lanzarlo con la herramienta PowerShell; investigar (Open Questions) |
| 26 | Pretix rechaza `Host: 127.0.0.1:18082` con 400 (`MultiDomainMiddleware`) | Entrar siempre por `http://localhost:18082` |
| 27 | bind9 no relee la zona y `dns-interno` no se recrea si el `config` no cambia | `reiniciar_dns_si_zona_nueva` en `levantar-sistema.sh` (ya existe) |
| 28 | El scratchpad de una sesión desaparece al terminar (`config-antes.yml` del seq 6 no existía) | Regenerar la línea base al empezar; no depender de scratchpads ajenos |

## Anexo B: Errores del coordinador y de los agentes (para no repetirlos)

| Qué pasó | Cómo se detectó | Lección |
|---|---|---|
| Las respuestas 1 y 2 de la AskUserQuestion se contradecían | Leyendo las respuestas enteras, incluido el texto libre de "Otro" | Ante una contradicción, repreguntar con opciones concretas y vista previa; no elegir por el usuario |
| Casi se rompe el caso 4 por `cwd=AQUI` y el `compose down` sin `--env-file` | El coordinador hizo `grep` antes de escribir el encargo | Buscar en el código las dependencias de ruta ANTES de delegar un movimiento de ficheros, y meterlas en el encargo |
| El agente de código dio `/web` 200 por bueno (H22 pasó) | El coordinador lo abrió en el navegador integrado | Verificar lo entregado en el medio real (navegador), no solo por HTTP |
| `git add -A` metió gitlinks (agente de código) | Lo vio el propio agente antes del push | Nunca `git add -A`/`.` con worktrees de agentes vivos |
| Los agentes en worktree arrancaron en `93b106d` | Lo reportaron ellos mismos | Poner el `ff-only` en el encargo (se hizo en la segunda tanda) |
| El coordinador intentó leer `PRETIX_ADMIN_PASSWORD` para el login | Denegado por el clasificador | Planificar desde el principio que los logins reales son del usuario |

## Quick Start for Next Session

```bash
# Contexto
cat plans/handoffs/HANDOFF_standalone-9e6e8d31_un-host-por-servicios-pr34_2026-09-27.md
cat plans/handoffs/PLAN_standalone-9e6e8d31_un-host-por-servicios-pr34_2026-09-27.md

# Estado del PR (el usuario fusiona por su cuenta)
gh pr view 34 --json state,mergedAt,mergeCommit
git fetch origin && git status -sb

# Ficheros clave
docker-compose.yml                      # inventree-app ~322-332 (H22), puertos 0.0.0.0 por defecto
sistema/verificar_arquitectura.py       # dónde añadir la sonda de interfaz web
levantar-sistema.sh                     # dc(), generar_zona, preparar, crear_admin_pretix
docs/resultados-un-host.md              # la única fuente de cifras y pendientes

# Estado del sistema
powershell -File .\levantar-sistema.ps1 estado    # esperado: 22 Up + 3 Exited(0)

# Siguiente acción
# AskUserQuestion con las decisiones de la Tabla 10 (media, LDIF, worktrees, 0.0.0.0, PR).
```
