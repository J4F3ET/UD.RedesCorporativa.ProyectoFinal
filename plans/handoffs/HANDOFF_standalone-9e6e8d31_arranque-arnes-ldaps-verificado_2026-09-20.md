# Laboratorio Reserva Viva: LDAPS verificado de verdad, Docker Desktop desinstalado y cuatro defectos reales del entregable al descubierto

**Date:** 2026-09-20
**Status:** IN PROGRESS (LDAPS demostrado con evidencia literal; el criterio de "arranque sano" da FAIL por dos defectos de proyecto, ambos documentados y sin arreglar)
**Bead(s):** none (`bd` no está instalado en esta máquina: `bd: command not found`)
**Epic:** Proyecto final Redes Corporativas (UD) — Laboratorio "Reserva Viva"
**Chain:** `standalone-9e6e8d31` seq `4`
**Parent:** `HANDOFF_standalone-9e6e8d31_windows-docker-desktop-pivot_2026-09-20.md`
**Prior chain:** `…_lab-3pcs-pruebas-reales_2026-09-19` > `…_diagramas-y-ldap-en-master_2026-09-19` > `…_windows-docker-desktop-pivot_2026-09-20` > this

> **Nota (2026-09-20, posterior a H14):** las tablas de imágenes de este handoff (Tabla 2 y la de servicios, con `frappe/erpnext:v15.121.3`) describen el arnés tal como estaba entonces. Desde H14 todos los servicios de ERPNext usan `ghcr.io/frappe/hrms:v15.64.1@sha256:b7ba52bc9aeb288f47d0aea9dc94635843ea1a7a83c45df724449f613b2f6395` (ancla `&erpnext_image` de `docker/pc3-administracion-infra/docker-compose.yml`). No se reescribe el cuerpo: es el registro de aquella sesión.

---

## Since Last Handoff

El padre (seq 3) cerró con siete próximos pasos y un plan de cuatro fases. Esta sesión **ejecutó la Fase 1 completa** delegándola en pepe. Estado de cada punto del padre:

- **Punto 1 (repetir el arranque del arnés y ejecutar `ldaplogin.py`): HECHO, y es el resultado central de la sesión.** Los 3 jobs de ERPNext salieron `Exited (0)`, `create-site` tardó 8,6 minutos, y `ldaplogin.py` dio PASS con exit 0 tras corregir un defecto real del propio script. **La autenticación LDAPS está demostrada por primera vez con salida literal.**
- **Punto 2 (prueba sin red, B3): SIGUE SIN HACERSE.** Pero se desbloqueó: las 11 imágenes están en local, incluida la de OpenVPMS construida aquí, que es justo la que el paquete offline debe transportar.
- **Punto 3 (completar el traslado del almacén a D:): RESUELTO POR EL USUARIO, de forma inesperada.** No trasladó el almacén: **desinstaló Docker Desktop entero** y montó Docker Engine nativo dentro de WSL. Ver "Key Decisions".
- **Punto 4 (borrar los 8 worktrees huérfanos): SIGUE SIN HACERSE.** El clasificador de permisos me lo sigue bloqueando.
- **Punto 5 (decidir el aviso en los diagramas de VLAN): SIGUE SIN RESPONDER.** Es la segunda sesión consecutiva que esta pregunta se queda sin contestar. Conclusión práctica: el usuario no la considera importante; conviene decidirla por defecto y dejar de preguntarla.
- **Punto 6 (fusionar o archivar `docs/handoff-plan-lab-3pcs`): SIGUE PENDIENTE.** La rama sigue viva y sin fusionar desde el seq 1.
- **Punto 7 (mapear usuarios LDAP a roles): NO HECHO.** Sigue abierto desde el seq 2.

**Riesgos del padre que se materializaron:**

- *"Memoria del sistema insuficiente"* — **se materializó por tercera y cuarta vez.** Claude Code mató las dos tareas en segundo plano de pepe (`be7bzprrk`, el bucle de espera de healthchecks, y `byl6qtt09`, el de `ldaplogin.py`) por presión crítica de memoria, con el host a 0,9 GB libres. Es el bloqueo recurrente número uno del proyecto, y ya van cuatro.
- *"Docker compartido inestable"* — **se materializó de una forma nueva:** el servicio `docker.service` dentro de WSL se reinició seis veces en cuarenta minutos por activación de socket, matando contenedores a mitad de la prueba.
- *"El .vhdx sigue en C: con una copia sin usar en D:"* — **resuelto colateralmente.** Ambos .vhdx desaparecieron al desinstalar Docker Desktop.

**Preguntas abiertas del padre que esta sesión respondió:**

- *"¿Funciona de verdad la autenticación LDAPS contra ERPNext e InvenTree?"* — **SÍ, verificado.** Ver Tabla 6.
- *"¿Los tres supuestos sin verificar de juan sobre `ldaplogin.py` son ciertos?"* — **Los tres, sí.** Ver Tabla 7.
- *"¿El arranque parcial del arnés falló por un defecto o solo por falta de tiempo y RAM?"* — **Por un defecto**, y no el que se suponía. Ver H1.

---

## Reference Documents

- `docs/prueba-smoke-test-resultados.md` §10 — **el acta de esta sesión**, con las tres ejecuciones de `ldaplogin.py` pegadas literales y los diez hallazgos H1-H10. Es el documento más importante que salió de aquí.
- `docs/puesta-en-marcha-windows.md` §5 — bloque "Estado de la verificación", actualizado.
- `plans/handoffs/HANDOFF_standalone-9e6e8d31_windows-docker-desktop-pivot_2026-09-20.md` — el padre; contiene el contexto del giro a Windows y las 12 tablas de evidencia previas.
- `C:\Users\jafet\Downloads\arquitectura-distribuida-multihost.md` — **la arquitectura técnica real** (fuera del repo). Define CINCO PCs, no tres. Ver "Open Questions".
- `C:\Users\jafet\evidencia-arnes-2026-09-20\` — logs completos de la sesión, fuera del repo, con el token sin recortar.

---

## The Goal

Cerrar el proyecto final de Redes Corporativas de la UD ("Reserva Viva") dejándolo entregable y honesto. El padre reformuló el objetivo en tres niveles de evidencia separados. Esta sesión tenía un objetivo concreto dentro de eso: **convertir la deuda de verificación más valiosa del proyecto —"¿funciona LDAPS de verdad?"— de una suposición marcada como NO VERIFICADO en un hecho con salida literal pegada**. Se consiguió, y por el camino apareció lo que resultó ser más valioso todavía: cuatro defectos reales del entregable que el laboratorio habría sufrido el día de la demostración.

---

## Where We Are

- **Master en `48475b6`, árbol limpio, 0 PRs abiertos.** PR #27 fusionado con squash.
- **Docker Desktop YA NO EXISTE en esta máquina.** Docker Engine **29.8.1** + Compose **v5.5.1** nativos dentro de la distro WSL `Ubuntu-24.04`, cuyo disco vive en `D:\WSL\distros\Ubuntu-24.04` (`ext4.vhdx` de 2,4 GB).
- **No hay `docker.exe` nativo en Windows.** Hay un atajo en `C:\Users\jafet\.local\bin\docker.cmd` que reenvía a `wsl.exe -d Ubuntu-24.04 -- docker %*`. Desde PowerShell funciona; **desde Git Bash NO está en el PATH**.
- **Espacio recuperado: ~104 GB.** C: de 11,2 a 71,5 GB libres; D: de 390,5 a 434,4 GB. Ambos `docker_data.vhdx` de 51,7 GB desaparecieron.
- **Se perdieron las 33 imágenes y los 45 volúmenes del almacén anterior**, incluidas las de Airflow que el usuario había pedido conservar explícitamente en la sesión previa. No hay copia de seguridad: un rastreo recursivo de `.vhdx` sobre `C:\...\AppData\Local\Docker` y `D:\Docker` devolvió cero resultados.
- **Las 11 imágenes del arnés están de nuevo en local** (9,108 GB), incluida `reservaviva-smoke-openvpms-app:latest` (817 MB) **construida en esta máquina**.
- **19 volúmenes conservados** tras el `down` sin `-v`: si hay que volver a levantar el arnés no se repiten los 8,6 minutos de `create-site`.
- **Entorno al cierre:** 0 contenedores, las 6 redes del arnés eliminadas, host con 5,4 GB libres, `vmmemWSL` en 496 MB.
- **`pruebas/smoke-test-3-pcs/ldaplogin.py` corregido y ejecutado**, con veredicto PASS y exit 0.
- **Cuatro defectos reales del entregable documentados y SIN ARREGLAR** (prohibido tocar los compose): ver H1, H2, H3 y H5.
- **Los 8 worktrees huérfanos siguen ahí**, y las ramas locales sin limpiar.
- **`docs/handoff-plan-lab-3pcs` sigue sin fusionar** desde el seq 1.

---

## What We Tried (Chronological)

### Segmento 1 — Descubrimiento del entorno nuevo (early)

1. **Status inicial del repositorio y de Docker.** Verificado que el PR #26 del padre se había fusionado a las 14:59Z y que master estaba en `d34f036` con 0 PRs abiertos. **Resultado: la cadena de handoffs llegó a master por primera vez**, cerrando un pendiente que venía del seq 1.

2. **Diagnóstico del espacio en disco.** Encontradas **dos copias del `docker_data.vhdx`, de 51,7 GB cada una**: la de C: modificada a las 10:46 (viva) y la de D: congelada a las 08:08. **Conclusión: el traslado del padre nunca se completó.**

3. **El usuario informa del cambio.** *"ahora vive en el otro disco todo vive dentro del wsl entonces ahora sera mas lento algunas cosas pero tenemos mas espacio"*. **No lo di por bueno: lo verifiqué**, y la realidad era más drástica que su descripción.

4. **Verificación del entorno nuevo.** `Test-Path` sobre ambos .vhdx: **AUSENTES los dos**. `wsl -l -v`: solo queda `Ubuntu-24.04` (desaparecieron `docker-desktop` y `Ubuntu`). Registro `HKCU:\...\Lxss`: `BasePath = D:\WSL\distros\Ubuntu-24.04`. **Resultado: Docker Desktop desinstalado por completo.**

5. **Lectura del atajo.** `Get-Content C:\Users\jafet\.local\bin\docker.cmd` reveló el mecanismo y su propia documentación: *"Atajo: reenvia docker a Docker Engine dentro de WSL (Ubuntu-24.04). No hay docker.exe nativo en Windows"*.

6. **Descubrimiento del almacén vacío.** `docker system df`: **0 imágenes, 0 contenedores, 0 volúmenes, 0 caché**. Verificado que el `ext4.vhdx` son 2,4 GB, o sea una Ubuntu recién instalada. **Resultado: pérdida total confirmada, sin posibilidad de recuperación.**

7. **Matización del "será más lento".** Analizado y desglosado en tres: más lento lo que cruce `/mnt/d` (bind mounts, `inotify`); igual la red bridge y los puertos publicados; **más rápido el almacén de Docker**, que ahora está sobre ext4 nativo con overlay2 y sin la capa de VM de Docker Desktop. **Regla práctica derivada: volúmenes con nombre sí, bind mounts desde `/mnt/d` los mínimos.**

### Segmento 2 — Delegación en pepe, descarga y construcción (mid)

8. **Encargo exhaustivo a pepe.** Enviado con: el cambio de entorno que contradice la documentación del repo, la invalidación de `--pull never` del plan, la causa real de los fallos anteriores (memoria, no disco), cinco trampas concretas, la lista de ficheros permitidos y prohibidos, los criterios de aceptación y la norma de honestidad del proyecto. **Resultado: pepe arrancó sin necesitar una sola ronda de aclaraciones.**

9. **Hallazgo propio antes de que pepe tropezara: `openvpms-app` no se descarga, se construye.** Leído `docker/pc1-medica/docker-compose.yml:40` (`build: ./openvpms`) y el Dockerfile. **Resultado: la lista de `compose config --images` engaña** — la undécima entrada no tiene registro ni digest, y su base `tomcat:9.0-jdk11-temurin` es una **duodécima imagen invisible** en esa lista. Además el build sale a tres sitios que no son Docker Hub: apt de Debian, `repository.openvpms.org` y `repo1.maven.org`.

10. **pepe reporta un bloqueo: `repository.openvpms.org` inalcanzable.** `curl` desde Windows exit 28 (timeout a los 21.276 ms), desde WSL exit 6 ("Could not resolve host"). Propuso tres opciones y pidió decisión.

11. **Verificación por capas del supuesto bloqueo. Resultado: NO existía.**
    - DNS local, 8.8.8.8 y 1.1.1.1: los tres resuelven igual (CNAME a `openvpms.org` → A `54.69.175.219`).
    - `Test-NetConnection` puerto 443: `TcpTestSucceeded=True`.
    - `Invoke-WebRequest -Method Head`: **200 OK**, `Server: Apache/2.4.18 (Ubuntu)`, `Last-Modified: Fri, 16 Aug 2024`.
    - `getent hosts` **dentro de WSL**: exit 0, resuelve.
    - `curl` con petición de rango **dentro de WSL**: **206 Partial Content en 0,81 s**, repetido dos veces.

12. **Identificación de la causa del falso bloqueo.** El `/etc/resolv.conf` de la distro es estático a propósito (`generateResolvConf=false`) y su comentario lo explica: *"con Tailscale activo en Windows, ni el túnel DNS de WSL ni el proxy del gateway NAT resuelven nada; el TCP sale bien pero las consultas caducan"*. Confirmados **tres procesos de Tailscale** vivos (`tailscaled` ×2, `tailscale-ipn`) y **Portmaster Core** (pid 5616). **Conclusión: fallo transitorio de DNS, no servidor caído.** El `--max-time` de 21 s de pepe se quedaba corto; con 45 s pasaba.

13. **Descarga y construcción.** pepe: `docker compose pull` EXIT 0 (10 imágenes, 8,29 GB) y `docker compose build openvpms-app` EXIT 0. El zip de OpenVPMS descargó en 54,3 s y el conector de MySQL en 3,8 s. **Verificado por mí: 11 imágenes, 9,108 GB.**

### Segmento 3 — El arranque, dos fallos y un descubrimiento incómodo (mid-late)

14. **Gestión de la memoria antes del arranque.** Medido el host: 13,9 GB totales, **6,1 GB libres**. Identificados los consumidores uno a uno y pedido al usuario que cerrara lo concreto. Tras su *"listo"*, verificado: **7,9 GB libres (+1,8)**. **Resultado: luz verde dada sobre un dato medido, no sobre una promesa.**

15. **Primer `docker compose up -d`: EXIT 1.** `dependency failed to start: container erpnext-db is unhealthy`. **Diagnóstico de pepe, verificado por mí en el código:** el healthcheck de `erpnext-db` (pc3 compose líneas 53-57) tiene `interval 5s`, `retries 40` y **ningún `start_period`** → 200 s de tolerancia. La base tardó **~300 s** en inicializarse (18:28:11 → 18:33:00 UTC), con el datadir cruzando `/mnt/d`. **Es el hallazgo H1.**

16. **Error propio de lectura.** Leí `docker ps` y vi 12 Up / 11 Created con el proceso `docker compose up` (pid 612) vivo, y teoricé que era serialización lenta. **Era una foto vieja: compose ya había salido.** pepe tenía razón y yo estaba mirando un instante previo. Corregido al verificar.

17. **Relanzamiento autorizado, con tres condiciones.** Antes de repetir exigí: (a) salvar la evidencia del fallo, porque al relanzar la base ya estaría inicializada y el rastro se enterraría; (b) registrar que el re-lanzamiento **no valida el arreglo**; (c) no tocar el compose. **Resultado: `erpnext-db` sano en 14 segundos** (el volumen persistía) y `up -d` EXIT 0.

18. **Los 3 jobs completados.** `erpnext-configurator`, `erpnext-create-site` y `erpnext-ldap-config`, los tres `Exited (0)`. `create-site` de 18:42:34Z a 18:51:12Z = **8,6 minutos**. **Criterio 1 cumplido.**

19. **Descubrimiento del ciclo de reinicios del demonio.** pepe detectó UN reinicio; al investigarlo resultaron ser **cinco arranques de containerd** (13:27:07, 13:39:44, 13:40:55, 13:52:37, 13:55:09) y seis `Starting docker.service` en cuarenta minutos. **Pero `NRestarts=0` y `Result=success`: no es un crash.** El servicio está activado por socket (`TriggeredBy: docker.socket`) y `uptime -s` = 13:26:58 sin cambios, o sea la VM nunca se reinició.

20. **Atribución honesta del ciclo, y su corrección posterior.** Las marcas de 13:39, 13:40 y 13:55 **coinciden exactamente con mis propios sondeos** (en la de 13:55 vi dockerd con 10 segundos de vida al ejecutar mi comando). Lo reconocí ante pepe y ante el usuario y dejé de sondear. **Pero el reinicio de 14:02:41 ocurrió conmigo en silencio total**, lo que refuta la atribución exclusiva: **nuestras llamadas desde Windows aceleran el ciclo, no son su única causa.** Se lo comuniqué a pepe porque cambiaba su modelo mental y podía hacerle firmar un resultado inválido.

### Segmento 4 — Crisis de memoria, mediciones y los cuatro defectos (late)

21. **Claude Code mata las tareas de pepe.** Las dos en segundo plano (`be7bzprrk`, bucle de espera de healthchecks; `byl6qtt09`, `ldaplogin.py`) por presión crítica de memoria. Host a **0,9 GB libres**, `vmmemWSL` a **7.395 MB**. **Lección operativa extraída y transmitida: ejecutar en primer plano, no en segundo, y acortar los bucles de espera de 10 a 3-4 minutos.**

22. **Interludio: el PDF de arquitectura.** El usuario adjuntó `RC302_Grupo6_ArquitecturaEmpresarial.pdf` preguntando si la implementación lo cumple. Sin `pdftoppm` ni librerías de PDF en Python, **escribí un extractor en Python puro** (zlib + regex sobre operadores `TJ`/`Tj`, con desescapado octal) en el scratchpad. 1.145 líneas extraídas. **Resultado: el documento es un ensayo TEÓRICO sobre Arquitectura Empresarial** (TOGAF, Zachman, DoDAF). `grep` de *docker*, *vlan*, *erpnext*, *contenedor*, *switch*, *reserva viva*: **cero coincidencias.** Ver "Open Questions".

23. **Explicación errónea del consumo de RAM.** Atribuí el problema a los nueve contenedores de ERPNext y al 1 GB de heap de OpenVPMS. **Las mediciones de pepe lo refutaron por completo** (Tabla 4): los nueve de ERPNext suman **672 MB, el 10%**, mientras **`pretix-web` solo consume 3,664 GiB, el 47%**. Me corregí ante el usuario explícitamente.

24. **`openvpms-app` en bucle de reinicio.** `Restarting (1)`, 40 reintentos, `oom=false`. **Mi hipótesis (la JVM no puede reservar su heap de 1 GB con 1.274 MB disponibles) fue REFUTADA por pepe con los logs:** no hay ningún "Could not reserve enough space", el entrypoint muere antes de llegar a Tomcat con `Cannot create openvpms as there are tables already present`. **Es el hallazgo H2.**

25. **Verificación del mecanismo de H2.** Autoricé listar el volumen. `/s/init` **VACÍO** (ninguna marca `schema`) y **49 tablas** en la base. **La explicación pasó de "compatible con los datos" a verificada.**

26. **`pretix-web` unhealthy.** No es memoria ni fuga: el healthcheck (pc2 línea 74) llama a `http://127.0.0.1/control/login/`, y Django responde **400 Bad Request** porque `PRETIX_PRETIX_URL` (línea 70) declara la URL como `http://${IP_PC2}:${PRETIX_PORT}`. **Es el hallazgo H3.**

27. **Hallazgo propio adicional (H4): el mismo patrón latente en InvenTree.** pc2 línea 137 usa `urlopen('http://127.0.0.1:8000/api/')` con `INVENTREE_SITE_URL` apuntando a `IP_PC2` (línea 114). **No muerde** porque InvenTree es más tolerante con los hosts permitidos, pero es la misma fragilidad esperando un cambio de configuración.

28. **`ldaplogin.py`: tres ejecuciones.** Ver Tabla 6. Las dos primeras con el script original dieron FAIL/exit 1; la tercera con el script corregido dio **PASS/exit 0**. `ExecMainStartTimestamp` constante en 14:02:41 durante las tres → **resultados válidos**.

29. **El defecto del script y su falso PASS (H5).** El script usaba `ldaps://localhost:636`; libldap canonicaliza el nombre al hostname del contenedor (`4f89b94c57b9`), que no está en el SAN del certificado. Diagnóstico con `ldapsearch -d1`: *"TLS: hostname (4f89b94c57b9) does not match common name in certificate (ldap.reservaviva.local)"*. **Y lo grave: el cuarto check "sin la CA debe fallar" daba PASS fallando por el motivo equivocado** — por `could not use CA certificate file /nonexistent` (fichero ilegible), no por validación de certificado.

30. **Decisión sobre el nombre del arreglo.** pepe proponía `ldaps://openldap:636`. **Le indiqué usar `ldaps://ldap.reservaviva.local:636`**, que es el nombre real del despliegue (pc2 línea 124) y el que resuelve bind9 en el laboratorio. `openldap` habría funcionado pero probado algo que en el laboratorio nadie usa. **Verificado: con la CA rc=0; clave mala rc=49; CA ajena `peer cert untrusted or revoked (0x42)` rc=255.**

31. **La trampa del digest.** Le dije a pepe que usara `mariadb:10.6.28` como imagen local. **Se descargó.** Causa: los compose fijan `mariadb:10.6.28@sha256:4015…`, y pedir la etiqueta a secas es pedir una **referencia distinta**. **Implicación de alcance mucho mayor: en el laboratorio sin Internet, cualquier comando con la etiqueta sin digest intentará descargar y fallará.** Afecta de lleno a la Fase 2.

32. **El token en el historial.** pepe recortó un token de InvenTree pegado en el acta, **y avisó honestamente de que el token completo seguía en el historial del commit `0cba610` ya empujado**. **Decisión: fusionar con `--squash`**, apartándome de la convención de merge del proyecto, para que ese commit no entre en el historial de master. **Verificado: `git log origin/master -S"<token>"` → 0 resultados.**

33. **Cierre del entorno.** `docker compose down` **sin `-v`**, EXIT 0 a las 15:09. 0 contenedores, 6 redes del arnés eliminadas, **19 volúmenes conservados**. Host de 0,9 a **5,4 GB libres**; `vmmemWSL` de 7.395 a **496 MB**.

---

## Key Decisions

- **Fusionar el PR #27 con `--squash` en vez de merge normal.** Apartarse de la convención del proyecto estaba justificado: el commit `0cba610` contenía un token de API en texto y el squash lo deja fuera del historial de master. *Alternativas rechazadas:* (a) merge normal — habría dejado el token en master para siempre; (b) reescribir la rama con force-push — más invasivo y requería decisión del usuario.
- **Probar el arreglo del caso 3 con `ldap.reservaviva.local` y no con `openldap`.** El primero es el nombre que usan los despliegues reales y el que resuelve bind9; el segundo es un nombre de servicio interno de Docker que en el laboratorio nadie usa. La evidencia debía valer para el laboratorio, no solo para el arnés.
- **Autorizar tocar `ldaplogin.py` pero NO los compose.** La norma del proyecto permite corregir el script solo ante un defecto real, y el falso PASS lo era. Los cuatro defectos de los compose quedan como hallazgos documentados: arreglarlos exige validación con volumen limpio, que es otra sesión.
- **Exigir salvar la evidencia ANTES de relanzar el arnés.** Al relanzar, `erpnext-db` ya estaba inicializada y el fallo no se reproduciría: el rastro se habría enterrado. Esta decisión es la razón por la que H1 está documentado con salida literal.
- **Registrar que el re-lanzamiento NO valida el arreglo de H1.** Arrancó porque la base ya existía, no porque el defecto esté resuelto. Un "arrancó correctamente" a secas habría sido engañoso.
- **Dejar de sondear el daemon al descubrir que mis propias llamadas lo reiniciaban**, y depender de los reportes de pepe. *Alternativa rechazada:* seguir verificando por mi cuenta — habría seguido contaminando la medición que intentaba tomar.
- **NO parar Pretix pese a que habría liberado 3,7 GB.** El usuario eligió cerrar aplicaciones de Windows, y mantener los 23 contenedores arriba hacía que un PASS de `ldaplogin.py` valiera para el arnés completo, que es evidencia más fuerte. Se le ofreció la alternativa con los números medidos delante.
- **`docker compose down` SIN `-v` al cerrar.** Conserva los 19 volúmenes: un futuro arranque no repite los 8,6 minutos de `create-site` ni la inicialización de las cuatro bases.
- **Dejar la carpeta de evidencia fuera del repositorio.** `C:\Users\jafet\evidencia-arnes-2026-09-20\` contiene el token completo en los logs; es del usuario y la decisión sobre ella es suya.

---

## Evidence & Data

### Tabla 1 — El entorno antes y después de la migración

| Concepto | Antes (seq 3) | Ahora |
|---|---|---|
| Motor | Docker Desktop 29.8.0 | **Docker Engine 29.8.1 nativo en WSL** |
| Compose | incluido en Desktop | **v5.5.1** |
| Almacén | `containerd` snapshotter | **overlay2** (`/var/lib/docker`) |
| Ubicación | `C:\...\Docker\wsl\disk\docker_data.vhdx` (51,7 GB) | `D:\WSL\distros\Ubuntu-24.04\ext4.vhdx` (2,4 GB) |
| Distros WSL | `docker-desktop`, `Ubuntu`, `Ubuntu-24.04` | **solo `Ubuntu-24.04`** |
| Cliente en Windows | `docker.exe` nativo | atajo `.cmd` → `wsl.exe -d Ubuntu-24.04 -- docker` |
| C: libre | 11,2 GB | **71,5 GB** |
| D: libre | 390,5 GB | **434,4 GB** |
| Imágenes | 33 (30,09 GB) | 0 → **11 (9,108 GB)** tras redescargar |
| Volúmenes | 45 | 0 → **19** (del arnés) |

**Total recuperado: ~104 GB.** Coste: la pérdida completa del almacén anterior, incluidas las imágenes de Airflow que el usuario había protegido explícitamente.

### Tabla 2 — Las 11 imágenes del arnés (10 descargadas + 1 construida)

| Imagen | Origen |
|---|---|
| `cturra/ntp:latest@sha256:7224d4e7…` | registro |
| `frappe/erpnext:v15.121.3@sha256:7b52acb5…` | registro |
| `internetsystemsconsortium/bind9:9.18@sha256:1ffb29c7…` | registro |
| `inventree/inventree:1.5.5@sha256:5dc64d7c…` | registro |
| `mariadb:10.6.28@sha256:40153feb…` | registro |
| `mysql:8.0.46@sha256:7dcddc01…` | registro |
| `osixia/openldap:1.5.0@sha256:18742e9c…` | registro |
| `postgres:15.19@sha256:dfbbb0ad…` | registro |
| `pretix/standalone:stable@sha256:7f8c1b51…` | registro |
| `redis:7.4.11@sha256:c6eabf74…` | registro |
| **`reservaviva-smoke-openvpms-app`** (817 MB) | **construida aquí** |

**Duodécima imagen invisible:** `tomcat:9.0-jdk11-temurin`, base del Dockerfile de OpenVPMS. No aparece en `docker compose config --images` porque ahí solo sale la imagen resultante.

### Tabla 3 — Verificación por capas del falso bloqueo de `repository.openvpms.org`

| Capa | Comprobación | Resultado |
|---|---|---|
| DNS local | `Resolve-DnsName` | CNAME → `openvpms.org` → A `54.69.175.219` |
| DNS 8.8.8.8 | `Resolve-DnsName -Server 8.8.8.8` | idéntico |
| DNS 1.1.1.1 | `Resolve-DnsName -Server 1.1.1.1` | idéntico |
| TCP | `Test-NetConnection … -Port 443` | `TcpTestSucceeded=True` (ping falla: ICMP filtrado) |
| HTTP desde Windows | `Invoke-WebRequest -Method Head` | **200 OK**, `Apache/2.4.18 (Ubuntu)` |
| HTTP desde Windows | `curl.exe -sSI --max-time 45` | **200 OK**, `Last-Modified: Fri, 16 Aug 2024 07:55:14` |
| DNS dentro de WSL | `getent hosts repository.openvpms.org` | `54.69.175.219`, exit 0 |
| Descarga dentro de WSL | `curl -r 0-0` | **206 Partial Content, 0,81 s** (×2) |

**Causa del falso positivo:** DNS transitorio con Tailscale activo (3 procesos) y Portmaster Core (pid 5616). El `--max-time 21` de pepe se quedaba corto.

### Tabla 4 — Consumo real por contenedor (medido 14:34:34, límite WSL 7,757 GiB)

| Contenedor | Memoria | % | Familia |
|---|---:|---:|---|
| **pretix-web** | **3,664 GiB** | **47,24 %** | Pretix |
| **inventree-worker** | **1,053 GiB** | 13,57 % | InvenTree |
| openvpms-db | 424,9 MiB | 5,35 % | OpenVPMS |
| inventree-app | 321,5 MiB | 4,05 % | InvenTree |
| erpnext-db | 213 MiB | 2,68 % | ERPNext |
| erpnext-backend | 140,8 MiB | 1,77 % | ERPNext |
| erpnext-scheduler | 105,8 MiB | 1,33 % | ERPNext |
| erpnext-queue-short | 76,11 MiB | 0,96 % | ERPNext |
| erpnext-queue-long | 71,14 MiB | 0,90 % | ERPNext |
| inventree-db | 55,13 MiB | 0,69 % | InvenTree |
| pretix-db | 50,91 MiB | 0,64 % | Pretix |
| erpnext-websocket | 43,96 MiB | 0,55 % | ERPNext |
| dns-interno | 28,87 MiB | 0,36 % | infra |
| openldap | 22,18 MiB | 0,28 % | infra |
| erpnext-hr | 11,59 MiB | 0,15 % | ERPNext |
| pretix-redis | 7,855 MiB | 0,10 % | Pretix |
| erpnext-redis-queue | 5,492 MiB | 0,07 % | ERPNext |
| erpnext-redis-cache | 4,082 MiB | 0,05 % | ERPNext |
| ntp-interno | 3,332 MiB | 0,04 % | infra |

**Por familias:** Pretix **3,81 GB** · InvenTree **1,46 GB** · ERPNext **0,67 GB** · OpenVPMS 0,42 GB (sin la app) · infraestructura 54 MB.

**Dato que desmiente la intuición:** los **nueve** contenedores de ERPNext, que son el bloque más numeroso, suman el **10 %** del consumo. Un solo contenedor de Pretix consume **cinco veces y media más que todo ERPNext junto**. `docker stats` no lista `openvpms-app` porque estaba reiniciándose en ese instante; pepe lo señaló en vez de rellenarlo.

### Tabla 5 — Los criterios de aceptación, uno a uno

| # | Criterio | Estado | Evidencia |
|---|---|---|---|
| 1 | Los 3 jobs de ERPNext en `Exited (0)` | ✅ **CUMPLE** | `configurator`, `create-site` (8,6 min) y `ldap-config` |
| 2 | ~20 contenedores `Up` y los healthcheck en `healthy` | ❌ **NO CUMPLE** | `openvpms-app` en bucle (H2), `pretix-web` unhealthy (H3) |
| 3 | `ldaplogin.py` PASS y exit 0 | ⚠️ **Solo con el script corregido** | ejec. 1 y 2 FAIL/exit 1; ejec. 3 PASS/exit 0 |
| 4 | Clave errónea rechazada | ✅ **CUMPLE** | ERPNext 417, InvenTree 401 |

### Tabla 6 — Las tres ejecuciones de `ldaplogin.py`

| Ejec. | Script | Caso 1 (login OK) | Caso 2 (clave mala) | Caso 3 (LDAPS+CA) | Veredicto |
|---|---|---|---|---|---|
| 1 (14:38) | original | **FAIL** solo ERPNext (`status=None Traceback`, recortado a 200 chars); InvenTree PASS 200+token | PASS (417 / 401) | FAIL | **FAIL, exit 1** |
| 2 (14:40) | original | **PASS** — ERPNext 200 `full_name "RRHH Prueba"`; InvenTree 200+token | PASS (417 / 401) | FAIL | **FAIL, exit 1** |
| 3 | corregido (`73b3dd6`) | PASS | PASS | **PASS** | **PASS, exit 0** |

`ExecMainStartTimestamp` = 14:02:41 **constante en las tres** → el daemon no se reinició durante ninguna: resultados válidos.

**El fallo de ERPNext de la ejecución 1 fue intermitente y su causa NO está determinada** (sospecha no verificada: timeout en el primer login, que es el que crea el usuario). pepe repitió el login a mano con el mismo fragmento y dio 200.

### Tabla 7 — Los tres supuestos sin verificar de juan, resueltos

| # | Supuesto | Resultado |
|---|---|---|
| 1 | InvenTree acepta GET con Basic auth en `/api/user/token/` | ✅ **CIERTO** — 200 con token |
| 2 | Hay `python3` dentro de ambos contenedores | ✅ **CIERTO** — `erpnext-backend` 3.11.16, `inventree-app` 3.14.7 |
| 3 | Los hashes del LDIF corresponden a las claves del README | ✅ **CIERTO** — `rrhh.prueba`/`Rrhh-Prueba1` y `logistica.prueba`/`Oper-Prueba1` autentican |

### Tabla 8 — Los diez hallazgos documentados (H1-H10)

| ID | Hallazgo | Tipo | ¿Afecta al laboratorio? |
|---|---|---|---|
| **H1** | Healthcheck de `erpnext-db` sin `start_period`: 200 s de margen contra ~300 s de inicialización real | **Defecto de proyecto** | **SÍ** — tres PCs arrancando en frío |
| **H2** | Entrypoint de OpenVPMS no reanudable: tablas presentes + sin marca `schema` = bucle infinito. El comentario promete una reanudabilidad que el código no da | **Defecto de proyecto** | **SÍ** — cualquier corte en el primer arranque |
| **H3** | Healthcheck de Pretix con Host `127.0.0.1` contra `PRETIX_PRETIX_URL` = `IP_PC2` → 400 → unhealthy para siempre tras 900 s | **Defecto de proyecto** | **SÍ** |
| **H4** | Mismo patrón latente en el healthcheck de InvenTree (línea 137). No muerde hoy | **Fragilidad latente** | potencialmente |
| **H5** | `ldaplogin.py` usaba `ldaps://localhost` → falla por nombre; **y el check "sin CA" daba falso PASS** | **Defecto del script** | **CORREGIDO** |
| **H6** | Fallo intermitente de ERPNext en el primer login | Sin determinar | desconocido |
| **H7** | `docker.service` ciclando por activación de socket | Entorno de esta máquina | no (el lab usa Docker Desktop) |
| **H8** | `repository.openvpms.org` intermitente por DNS con Tailscale | Entorno de esta máquina | no |
| **H9** | Carácter de control `\b` incrustado en la ruta del README del arnés | Documentación | **CORREGIDO** |
| **H10** | Imágenes fijadas por digest: la etiqueta sin digest es otra referencia y **descarga** | **Aviso para la Fase 2** | **SÍ — crítico sin Internet** |

### Tabla 9 — El ciclo de reinicios de `docker.service`

| Hora local | Evento | ¿Coincide con sondeo mío? |
|---|---|---|
| 13:26:58 | Arranque de la VM (`uptime -s`) | — |
| 13:27:07 | containerd #1 | legítimo |
| 13:39:44 | containerd #2 | **sí** |
| 13:40:55 | containerd #3 | **sí** |
| 13:52:37 | containerd #4 | no determinado |
| 13:55:09 | containerd #5 | **sí** (dockerd con 10 s de vida al ejecutar) |
| 14:02:41 | containerd #6 | **NO — yo estaba en silencio** |
| 14:02:41 → 15:09 | **estable, sin reinicios** | sesión WSL persistente abierta |

`systemctl show docker`: `NRestarts=0`, `Result=success`, `TriggeredBy: docker.socket`. **No es un crash: es activación por socket.** Mis llamadas lo aceleraban; el entorno cicla solo.

### Tabla 10 — Evolución de la memoria durante la sesión

| Momento | Host libre | `vmmemWSL` | Disponible en WSL |
|---|---:|---:|---:|
| Antes del arranque | 6,1 GB | 1.093 MB | 7,4 GB |
| Tras cerrar aplicaciones (1.ª vez) | **7,9 GB** | — | — |
| Con el arnés completo arriba | **0,9 GB** | **7.395 MB** | 1.274 MB |
| Tras `docker compose down` | **5,4 GB** | **496 MB** | 7.276 MB |

### Tabla 11 — Inventario de los 23 servicios (extraído de los compose, no de memoria)

| PC | Contenedor | Imagen | Tipo |
|---|---|---|---|
| **PC-1** | `openvpms-db` | `mysql:8.0.46` | permanente |
| | `openvpms-app` | **construida** (Tomcat 9 + Java 11) | permanente |
| **PC-2** | `pretix-db` | `postgres:15.19` | permanente |
| | `pretix-redis` | `redis:7.4.11` | permanente |
| | `pretix-web` | `pretix/standalone:stable` | permanente |
| | `inventree-db` | `postgres:15.19` | permanente |
| | `inventree-app` | `inventree/inventree:1.5.5` | permanente |
| | `inventree-worker` | `inventree/inventree:1.5.5` | permanente |
| **PC-3** | `erpnext-db` | `mariadb:10.6.28` | permanente |
| | `erpnext-redis-cache` | `redis:7.4.11` | permanente |
| | `erpnext-redis-queue` | `redis:7.4.11` | permanente |
| | `erpnext-configurator` | `frappe/erpnext:v15.121.3` | **job** |
| | `erpnext-create-site` | `frappe/erpnext:v15.121.3` | **job** |
| | `erpnext-ldap-config` | `frappe/erpnext:v15.121.3` | **job** |
| | `erpnext-backend` | `frappe/erpnext:v15.121.3` | permanente |
| | `erpnext-websocket` | `frappe/erpnext:v15.121.3` | permanente |
| | `erpnext-scheduler` | `frappe/erpnext:v15.121.3` | permanente |
| | `erpnext-queue-short` | `frappe/erpnext:v15.121.3` | permanente |
| | `erpnext-queue-long` | `frappe/erpnext:v15.121.3` | permanente |
| | `erpnext-hr` | `frappe/erpnext:v15.121.3` | permanente |
| | `openldap` | `osixia/openldap:1.5.0` | permanente |
| | `dns` (bind9) | `internetsystemsconsortium/bind9:9.18` | permanente |
| | `ntp` | `cturra/ntp:latest` | permanente |

**23 definiciones = 20 permanentes + 3 jobs** (`restart: "no"`). Reparto: 2 en PC-1, 6 en PC-2, **15 en PC-3**.

**Por qué el arnés no cabe en un portátil:** mete en una sola máquina lo que la arquitectura reparte entre tres. Ninguna máquina del laboratorio aguantaría esta carga; aquí las aguanta todas juntas. **Que no quepa no significa que el diseño esté mal dimensionado.**

### Tabla 12 — Divergencia entre la arquitectura documentada y lo implementado

| `arquitectura-distribuida-multihost.md` | Rol | Servicios | Implementado como |
|---|---|---|---|
| PC-1 | Veterinaria | OpenVPMS + DB | `pc1-medica` ✅ |
| PC-2 | Taquilla | Pretix + DB + Redis | **fusionado** en `pc2-operaciones` |
| PC-3 | Logística | InvenTree + DB | **fusionado** en `pc2-operaciones` |
| PC-4 | RRHH | ERPNext + DB + Redis | **fusionado** en `pc3-administracion-infra` |
| PC-5 | Router/Infra | LDAP, DNS, NTP | **fusionado** en `pc3-administracion-infra` |

**El diseño define CINCO PCs, uno por área; lo implementado son TRES.** La consolidación explica directamente la presión de memoria: PC-3 concentra 15 de los 23 contenedores. **Divergencia detectada, no analizada** (ver Open Questions).

El PDF que el usuario adjuntó (`RC302_Grupo6_ArquitecturaEmpresarial.pdf`) **no sirve para este contraste**: es un ensayo teórico sobre TOGAF, Zachman y DoDAF, con cero contenido técnico. 1.145 líneas extraídas, `grep` de *docker*, *vlan*, *erpnext*, *contenedor*, *switch* y *reserva viva* → **cero coincidencias**. Las únicas menciones a "servidores" son genéricas ("servidores físicos o instancias en la nube como AWS").

### Tabla 13 — Cronología de la sesión (hora local, -05)

| Hora | Evento |
|---|---|
| ~12:55 | Status inicial; se descubre que el PR #26 se fusionó y que hay dos .vhdx |
| ~13:05 | El usuario informa de la migración; se verifica que Docker Desktop **ya no existe** |
| 13:26:58 | Arranque de la VM de WSL (`uptime -s`) |
| ~13:10 | Encargo a pepe; empieza `docker compose pull` |
| ~13:20 | pepe reporta el falso bloqueo de `repository.openvpms.org`; se refuta |
| ~13:30 | `pull` EXIT 0 (10 img, 8,29 GB) y `build` EXIT 0 |
| ~13:35 | Gestión de memoria: 6,1 → 7,9 GB libres tras cerrar aplicaciones |
| 13:39-13:55 | **Ciclo de reinicios de `docker.service`** (coincide con mis sondeos) |
| 18:28:11-18:33:00 UTC | Inicialización de `erpnext-db` (~300 s) → **supera los 200 s del healthcheck** |
| — | **1.er `up -d`: EXIT 1** por dependencia no sana (H1) |
| 14:02:41 | Último reinicio del daemon; **a partir de aquí, estable** |
| 18:42:34-18:51:12 UTC | `erpnext-create-site` (**8,6 min**) |
| — | **2.º `up -d`: EXIT 0**, los 3 jobs `Exited (0)` |
| ~14:20 | Claude Code mata las dos tareas de pepe por memoria (host a 0,9 GB) |
| 14:34:34 | `docker stats`: **pretix-web 3,664 GiB**, refuta mi explicación |
| ~14:35 | Diagnóstico de H2 (bucle de OpenVPMS) y H3 (unhealthy de Pretix) |
| 14:38 / 14:40 | Ejecuciones 1 y 2 de `ldaplogin.py`: FAIL |
| ~14:45 | Ejecución 3 con el script corregido: **PASS, exit 0** |
| ~14:55 | PR #27 abierto; verificado que `docker/` está intacto |
| ~15:00 | Fusión con `--squash`; master en `48475b6` |
| 15:09 | `docker compose down` sin `-v`: EXIT 0. Host a 5,4 GB libres |

### Salida literal del primer fallo (H1)

```
 Container erpnext-db  Waiting
 Container erpnext-db  Error dependency erpnext-db failed to start
dependency failed to start: container erpnext-db is unhealthy
EXIT 1
```

### Salida literal del bucle de OpenVPMS (H2)

```
[openvpms] Esperando a MySQL en 10.10.10.11:3306...
[openvpms] Creando esquema...
Cannot create openvpms as there are tables already present
```

`status=restarting`, `exit=1`, `oom=false`, `restarts=40`. `/s/init` vacío, 49 tablas en la base.

### Salida literal del diagnóstico TLS (H5)

```
TLS: hostname (4f89b94c57b9) does not match common name in certificate (ldap.reservaviva.local).
TLS: can't connect
```

SAN del certificado: `DNS:ldap.reservaviva.local, DNS:openldap, DNS:localhost, IP:10.10.99.10, IP:127.0.0.1`.

### Commits de esta sesión

```
48475b6  Registro real del arranque completo del arnes: LDAPS verificado, arranque sano NO VERIFICADO (#27)   [squash de:]
  ea7df9c  README del arnes: corrige la ruta de generar-zona.ps1
  73b3dd6  ldaplogin.py: caso 3 por nombre real y CA ajena
  0cba610  docs: seccion 10 con los resultados y H1-H10
  593aa85  docs: recorta el token de InvenTree
```

### Comandos clave verificados

```bash
# Invocar Docker en el entorno nuevo (desde PowerShell)
docker system df
# Desde Git Bash: NO está en el PATH. Usar docker.cmd o:
MSYS_NO_PATHCONV=1 wsl.exe -d Ubuntu-24.04 -- docker ps -a

# Comprobar si el daemon se reinició durante una prueba (criterio de validez)
wsl -d Ubuntu-24.04 -- systemctl show docker -p ExecMainStartTimestamp

# Consumo por contenedor, UNA lectura (nunca en bucle)
docker stats --no-stream --format "{{.Name}}\t{{.MemUsage}}\t{{.MemPerc}}"

# Verificar que un token no entró en el historial de master
git log origin/master -S"<cadena>" --oneline

# Extraer texto de un PDF sin librerías (el extractor está en el scratchpad)
python pdftxt.py fichero.pdf
```

### Rutas de datos

- `C:\Users\jafet\evidencia-arnes-2026-09-20\` — **fuera del repo**: `up-intento1.log`, `tres-pasos-salida.txt`, `diagnostico-fallo-ldaplogin.txt`, `diagnostico2-y-reintento.txt`, health json, logs completos. **Contiene el token de InvenTree sin recortar.**
- `C:\Users\jafet\.local\bin\docker.cmd` — el atajo de Docker hacia WSL.
- `D:\WSL\distros\Ubuntu-24.04\ext4.vhdx` — el disco de la distro (2,4 GB).
- `C:\Users\jafet\Downloads\arquitectura-distribuida-multihost.md` — la arquitectura técnica real, con CINCO PCs.
- Scratchpad: `…\scratchpad\pdftxt.py` y `arq.txt` (1.145 líneas extraídas del PDF).

---

## Code Analysis

- **`docker/pc3-administracion-infra/docker-compose.yml:53-57`** — healthcheck de `erpnext-db`: `mysqladmin ping -h 127.0.0.1 -uroot -p$$MARIADB_ROOT_PASSWORD --silent`, `interval: 5s`, `timeout: 5s`, `retries: 40`. **Sin `start_period`.** 40 × 5 s = 200 s de margen. **H1.**
- **`docker/pc3-administracion-infra/docker-compose.yml:84-86`** — `erpnext-configurator` depende de UNA sola condición: `erpnext-db: condition: service_healthy`. Por eso H1 tumba toda la cadena.
- **`docker/pc3-administracion-infra/docker-compose.yml:106-112`** — `erpnext-create-site` depende de `configurator` con `service_completed_successfully` y de los dos Redis con `service_started`.
- **`docker/pc1-medica/openvpms/entrypoint.sh:63-74`** — `MARK="${STATE_DIR}/init"`; línea 65 `[ "${tables}" -eq 0 ] && rm -f "${MARK}"/*`; `step()` salta si existe la marca y hace `touch` **después** de ejecutar. **Si el comando crea tablas y muere antes del `touch`, el estado es irrecuperable.** Las líneas 61-62 afirman por escrito una reanudabilidad que el código no implementa. **H2.**
- **`docker/pc1-medica/openvpms/Dockerfile`** — `FROM tomcat:9.0-jdk11-temurin`, `ARG OPENVPMS_VERSION=2.4.0.1`, `ARG CONNECTOR_VERSION=8.0.33`. Descarga de `repository.openvpms.org` y `repo1.maven.org`, más `apt-get` de Debian. `ENV CATALINA_OPTS="-Xms512m -Xmx1024m"`.
- **`docker/pc2-operaciones/docker-compose.yml:70`** — `PRETIX_PRETIX_URL: http://${IP_PC2:?…}:${PRETIX_PORT:-80}`.
- **`docker/pc2-operaciones/docker-compose.yml:73-78`** — healthcheck de `pretix-web`: `urlopen('http://127.0.0.1/control/login/', timeout=5)`, `start_period: 900s`, `retries: 20`. **El Host no coincide con la URL declarada → 400. H3.**
- **`docker/pc2-operaciones/docker-compose.yml:136-141`** — healthcheck de `inventree-app`: `urlopen('http://127.0.0.1:8000/api/')` con `INVENTREE_SITE_URL` en la línea 114 apuntando a `IP_PC2`. **Mismo patrón, no muerde. H4.**
- **`pruebas/smoke-test-3-pcs/ldaplogin.py`** — antes: `LDAP_URI = "ldaps://localhost:636"` con el comentario *"el certificado incluye SAN localhost, asi que la verificacion de nombre es real"* (falso). Ahora: `ldaps://ldap.reservaviva.local:636`, `ldapsearch` en contenedor efímero unido a la red del arnés con el DNS del laboratorio, y la CA ajena generada con `openssl req -x509` para que el fallo sea `untrusted` y no "fichero ilegible".
- **`/etc/wsl.conf` de `Ubuntu-24.04`** — `generateResolvConf=false`; `/etc/resolv.conf` estático con `nameserver 1.1.1.1` y `8.8.8.8`, `options timeout:2 attempts:2`. El comentario documenta la incompatibilidad con Tailscale.
- **`/etc/docker/daemon.json`** — `overlay2`, `bip: 10.200.0.1/24`, `default-address-pools: 10.201.0.0/16 /24`, buildkit activado, gc a 10 GB. **Sin clave `dns`** (los builds heredan el resolv.conf de WSL). Las subredes están deliberadamente lejos del `10.10.x.x` del proyecto: no hay colisión.

---

## Files Changed

- `docs/prueba-smoke-test-resultados.md` — **+228 líneas**: sección 10 completa con entorno, cronología, criterios uno a uno, las tres ejecuciones literales y los hallazgos H1-H10.
- `docs/puesta-en-marcha-windows.md` — **+4/-4**: bloque "Estado de la verificación" del §5 actualizado.
- `pruebas/smoke-test-3-pcs/README.md` — **+1/-1**: ruta de `generar-zona.ps1` corregida (llevaba un carácter de control `\b`).
- `pruebas/smoke-test-3-pcs/ldaplogin.py` — **+39/-12**: `LDAP_URI` al nombre real, `ldapsearch` en contenedor efímero, CA ajena generada con openssl, docstring corregido.

**Verificado: `git diff origin/master...origin/test/arranque-completo-arnes -- docker/` devuelve VACÍO.** Los tres compose oficiales quedaron intactos, como estaba mandado.

---

## User Feedback & Preferences (REQUIRED)

- **"dile a pepe que ejecute la prueba"** — orden directa de delegación. Confirma una vez más el rol de coordinador: el usuario no pide que yo ejecute, pide que reparta.
- **"listo"** — respuesta a la petición de cerrar aplicaciones. **Patrón consolidado: el usuario responde a peticiones concretas y accionables, no a explicaciones largas.** Cuando se le dio una lista exacta de qué cerrar con los megas de cada cosa, actuó en minutos.
- **"Esta es la acrquitectura que definimos en este documento requiero ver algo, lo que actualmente se intenta implementar cumple con esto?"** — adjuntó el PDF equivocado. **Lección: verificar el contenido del documento antes de responder sobre él.** Responder "sí cumple" o "no cumple" sobre un ensayo teórico habría sido inventar.
- **"ahora tambien quiero que me des un listado de todos los servicios docker que sacar y su comsumo y poer que no da la ram"** — pidió datos medidos. **Le di una explicación teórica equivocada antes de tener las mediciones, y tuve que corregirme.** Lección: cuando se piden números, conseguir los números antes de explicar.
- **Eligió "Cerrar más aplicaciones de Windows"** sobre parar contenedores, aun cuando parar Pretix habría liberado cuatro veces más. Decisión legítima: mantiene el arnés completo y hace más fuerte la evidencia.
- **Eligió "Sí, fusionar"** y **"Bajarlo (down sin -v)"** en el cierre.
- **La pregunta del aviso en los diagramas lleva DOS sesiones sin respuesta.** Ya no conviene volver a preguntarla: decidir por defecto y comunicarlo.
- **Patrón sobre el entorno:** el usuario hace cambios grandes en su máquina por su cuenta y los comunica después, de forma resumida e imprecisa (*"ahora vive en el otro disco"* describía en realidad una desinstalación completa de Docker Desktop). **Regla: verificar siempre el entorno al empezar, nunca asumir continuidad con la sesión anterior.**

---

## Anexos

### Anexo A — El protocolo de coordinación, segunda iteración

Lo que funcionó con pepe, y que conviene repetir:

1. **Encargo exhaustivo de entrada.** Objetivo, ficheros permitidos y prohibidos, documentos a leer, trampas conocidas, criterios de aceptación, norma de honestidad y protocolo de reporte. pepe arrancó sin una sola ronda de aclaraciones.
2. **Corregir el plan antes de que lo siguiera a ciegas.** El plan del padre decía `--pull never`; con el almacén vacío eso fallaba al instante. Avisarlo de entrada ahorró una ronda.
3. **Adelantarse a las trampas.** Le avisé de que `openvpms-app` se construye y de los tres servidores externos del build antes de que llegara a ese paso.
4. **Verificar sus reportes en vez de creerlos.** Encontró un bloqueo que no existía (§11) y yo encontré que su lista de 11 imágenes escondía una duodécima.
5. **Aceptar sus correcciones.** Me refutó dos veces con evidencia (el falso negativo de `system df` y la hipótesis del heap) y en las dos tenía razón.
6. **Autorizaciones explícitas y acotadas.** Nunca "haz lo que veas": siempre "haz X, no hagas Y, repórtame Z".

### Anexo B — Los dos errores propios de esta sesión

1. **Sondear el daemon mientras la prueba corría.** Anuncié que dejaría de comprobar cada minuto y volví a hacerlo tres veces. Mis llamadas contribuyeron a reiniciar `docker.service`, que mató contenedores a mitad de la prueba. **Lección: cuando se anuncia una restricción operativa, cumplirla.**
2. **Explicar el consumo de RAM sin haberlo medido.** Atribuí el problema a ERPNext por tener nueve contenedores. Las mediciones dijeron que ERPNext era el 10 % y Pretix el 47 %. **Lección: cuando el usuario pide números, conseguir los números primero.**

Ambos se reconocieron ante el usuario en cuanto se detectaron, sin rodeos.

### Anexo C — Por qué el falso PASS era el hallazgo más peligroso

El cuarto check del caso 3 comprobaba que "sin la CA, la conexión debe fallar". Fallaba, y daba PASS. Pero fallaba por `could not use CA certificate file /nonexistent` —el fichero no existía y libldap no podía leerlo—, no por validación de certificado. **Con el certificado correcto y sin CA válida habría dado PASS igual.**

Un FAIL se investiga. Un PASS se firma sin mirar. Por eso el arreglo no consistió solo en cambiar el URI: ahora se genera con `openssl` una CA **válida pero ajena**, de modo que el fallo esperado sea `peer cert untrusted or revoked (0x42)` y la comprobación verifique lo que dice verificar.

### Anexo D — Estado del entorno al cerrar

```
Contenedores      0
Redes             solo bridge/host/none (las 6 del arnés eliminadas)
Volúmenes        19 conservados (down SIN -v)
Imágenes         11 (9,108 GB)
Host libre        5,4 GB de 13,9 GB
vmmemWSL          496 MB
master            48475b6, árbol limpio, 0 PRs abiertos
Sesión WSL        cerrada (los dos `sleep infinity` terminados)
```

### Anexo E — Métricas de la sesión

| Métrica | Valor |
|---|---|
| Duración aproximada | ~2 h 15 min (12:55 → 15:09) |
| Mensajes intercambiados con pepe | 11 |
| Reportes de pepe | 6 |
| Hallazgos documentados | 10 (H1-H10) |
| Defectos de proyecto encontrados | 4 |
| Correcciones aceptadas de pepe | 2 |
| Errores propios reconocidos | 2 |
| PRs fusionados | 1 (#27, con squash) |
| Imágenes descargadas | 10 (8,29 GB) + 1 construida (817 MB) |
| Espacio recuperado en disco | ~104 GB |

### Anexo F — Lo que NO se hizo, y por qué

- **Arreglar H1, H2, H3 y H4.** Prohibido tocar los compose sin decisión del usuario, y validarlos de verdad exige volumen limpio y arranque en frío.
- **El caso 4 de `ldaplogin.py` (`--persistencia`).** Necesitaba el arnés vivo y otro ciclo completo; se ofreció al usuario y eligió bajar el arnés.
- **La Fase 2 (paquete offline sin red).** Desbloqueada pero no ejecutada: la memoria no daba para más hoy.
- **Borrar los 8 worktrees huérfanos.** El clasificador de permisos lo bloquea; el usuario tiene el comando.
- **Contrastar la implementación contra `arquitectura-distribuida-multihost.md`.** Se ofreció dos veces y no se pidió.

### Anexo G — Trampas operativas del entorno nuevo (cuestan tiempo si no se saben)

1. **El atajo `docker.cmd` es un fichero por lotes, y cmd interpreta la barra vertical.** Un `docker ps --format "{{.Names}}|{{.Status}}"` **falla** con *"{{.Status}}" no se reconoce como un comando*. Usar tabulador, `>>` u otro separador, o invocar `wsl -d Ubuntu-24.04 -- docker …` directamente.
2. **`subprocess` sin shell no resuelve un `.cmd`.** Por eso `ldaplogin.py` hay que ejecutarlo **dentro de WSL**, con el `python3` de la distro.
3. **Git Bash reescribe las rutas tipo `/mnt/d`.** `wsl.exe -- ls /mnt/d/...` se convierte en `D:/Git/mnt/d/...` y falla. Anteponer `MSYS_NO_PATHCONV=1`.
4. **Git Bash mezcla `$_` de PowerShell con su propia expansión.** Los bloques de PowerShell con `$_` dentro de la herramienta Bash se destrozan; usar la herramienta de PowerShell directamente.
5. **`wsl` imprime `your 131072x1 screen size is bogus` por stderr.** Es ruido inocuo, no un error; puede hacer que una llamada devuelva código distinto de cero.
6. **`docker system df` da falsos ceros durante una descarga.** El almacén clásico no registra una imagen hasta que **todas** sus capas terminan; las capas parciales no aparecen. Una lectura a 0 durante un `pull` no significa que no esté avanzando.
7. **Pedir una imagen por etiqueta cuando el compose la fija por digest provoca una descarga** (H10). Comprobar siempre con la referencia completa.
8. **Los escaneos recursivos sobre `AppData\Local\Docker` tardan minutos.** Usar `Test-Path` sobre rutas concretas en lugar de `Get-ChildItem -Recurse`.

### Anexo H — Lo que hace falta saber para la Fase 2 (paquete offline)

- **El script es `scripts/preparar-paquete-offline.sh`**, en bash. Salida por defecto `./paquete-fase0`, configurable por argumento.
- **Se niega a ejecutarse si la carpeta de salida ya existe** (*"Borralo o indica otra carpeta: no mezclo paquetes"*) y **si hay cambios sin commitear** (salvo `PERMITIR_SUCIO=1`), porque el paquete lleva el commit, no la carpeta de trabajo.
- **Genera `imagenes/`, `overrides/` y `certs/`**, más `instalar.ps1`, `PAQUETE.env`, `MANIFEST.sha256` e `INVENTARIO.md`. Falla si no se generó `certs/pc3/ldap.crt`.
- **Usa `docker save --platform linux/${ARQ}`** con caída a `docker save` sin plataforma.
- **La ejecución del seq 3 dio EXIT 0 con 3,4 GB de salida**, pero la confirmación de `overrides/` se perdió y `instalar.ps1` **nunca se ha ejecutado**.
- **Ahora mismo NO hay ningún paquete en disco.** Se buscó en `D:\paquete-offline`, `D:\Proyectos\paquete-offline`, `D:\Docker` y `Descargas`: no existe.
- **El desbloqueo de esta sesión:** las 11 imágenes están en local, incluida `reservaviva-smoke-openvpms-app` **construida aquí**. El Dockerfile dice explícitamente que el laboratorio no tiene salida a Internet y que esa imagen hay que construirla en una máquina conectada y llevarla con `docker save`/`docker load`. **Es exactamente lo que el paquete debe transportar, y ya existe.**
- **El riesgo mayor sigue siendo H10:** si el paquete se arma o se consume con etiquetas sin digest, fallará en una máquina sin red.

### Anexo I — Riesgo de coordinación: directorio de trabajo compartido

pepe **no trabajó en un worktree aparte**: usó el mismo directorio que esta sesión (`D:\Proyectos\UD.RedesCorporativaa.ProyectoFinak`). Durante buena parte de la sesión la rama `test/arranque-completo-arnes` estuvo checkouteada ahí con ficheros modificados sin commitear, mientras yo leía el mismo árbol.

**No dio problemas porque solo éramos dos y el reparto era claro** (él editaba, yo leía). **Pero no escala:** con juan o yobana en paralelo se habrían pisado. Se lo advertí y le pedí que commiteara pronto para no perder el trabajo.

**Regla para la próxima vez:** si se reparte trabajo entre más de un agente sobre el mismo repositorio, cada uno en su worktree. Los 8 worktrees huérfanos de `D:\Proyectos\ProyectoFinak-*` son precisamente el residuo de haberlo hecho bien en sesiones anteriores.

### Anexo J — Las decisiones que el usuario tomó por menú

| Pregunta | Opciones ofrecidas | Elegida |
|---|---|---|
| Presión de memoria con el arnés arriba | (a) parar OpenVPMS y Pretix, (b) cerrar aplicaciones de Windows, (c) parar y documentar | **(b) cerrar aplicaciones** |
| ¿Fusionar el PR #27? | (a) sí, (b) revisarlo antes | **(a) sí** |
| ¿Qué hacer con el arnés? | (a) bajarlo sin `-v`, (b) aprovechar y cerrar el caso 4, (c) dejarlo arriba | **(a) bajarlo** |

**Patrón confirmado:** con opciones concretas y consecuencias explicadas, responde en segundos. La opción (b) de la primera pregunta se eligió **con una explicación mía equivocada delante** (yo culpaba a ERPNext); cuando llegaron las mediciones reales se le ofreció rectificar y ya no hizo falta, porque el problema no era la memoria.

---

## Where We're Going

1. **Arreglar H1 y validarlo de verdad.** Añadir `start_period` al healthcheck de `erpnext-db` y probarlo con volumen limpio: es la única forma de demostrar que funciona.
2. **Arreglar H3 (y H4 de paso).** Cambiar el Host de los healthchecks de Pretix e InvenTree, o declarar `127.0.0.1` como host permitido.
3. **Arreglar H2.** Hacer el entrypoint de OpenVPMS realmente reanudable, o retirar del comentario la promesa que no cumple.
4. **Ejecutar la Fase 2: el paquete offline sin red (B3).** Desbloqueada: las 11 imágenes están en local, incluida la construida.
5. **Cerrar el caso 4 de `ldaplogin.py`** (`--persistencia`), que necesita el arnés vivo.
6. **Sanear el entorno:** 8 worktrees huérfanos y las ramas locales sin limpiar.
7. **Decidir por defecto el aviso en los diagramas de VLAN** y dejar de preguntarlo.
8. **Fusionar o archivar `docs/handoff-plan-lab-3pcs`**, pendiente desde el seq 1.

---

## Risks & Blockers

- **La memoria del sistema es el bloqueo estructural del proyecto.** Cuatro procesos muertos en dos sesiones. 13,9 GB de RAM no bastan para los 23 contenedores más Windows. **Mitigación obligatoria en adelante: primer plano en vez de segundo plano, bucles de espera cortos, y parar Pretix (3,7 GB) cuando no haga falta.**
- **`docker.service` cicla por activación de socket.** Mitigado con una sesión WSL persistente, pero no eliminado: ocurrió una vez sin intervención nuestra. **Todo resultado debe validarse comparando `ExecMainStartTimestamp` antes y después.**
- **El entorno de esta máquina ya NO es el del laboratorio.** Aquí hay Docker Engine en WSL; allí, Docker Desktop. Lo que se verifique aquí no es automáticamente trasladable.
- **H10, el digest, es el riesgo mayor para la Fase 2.** Sin Internet, cualquier comando con etiqueta sin digest falla. El paquete offline debe usar digests de punta a punta.
- **El token completo sigue en `C:\Users\jafet\evidencia-arnes-2026-09-20\`.** Fuera del repo y sin decisión del usuario.
- **Las claves de laboratorio siguen en texto** en `docker/pc3-administracion-infra/ldap/README.md`. Hay que rotarlas si el repositorio se hace público.

---

## Open Questions

1. **¿La implementación de tres PCs cumple la arquitectura de cinco?** `arquitectura-distribuida-multihost.md` define PC-1 Veterinaria, PC-2 Taquilla, PC-3 Logística, PC-4 RRHH y PC-5 Router/Infra. Lo implementado fusiona Taquilla+Logística en `pc2-operaciones` y RRHH+Infra en `pc3-administracion-infra`. **Divergencia real, detectada y no analizada.** Se ofreció el análisis dos veces y no se pidió.
2. **¿Se arreglan los cuatro defectos antes de entregar, o se entregan documentados?** Arreglarlos sin validar sería repetir el error que los creó.
3. **¿Qué se hace con la carpeta de evidencia** y el token completo que contiene?
4. **¿Cuál fue la causa del fallo intermitente de ERPNext (H6)?** Sin determinar.
5. **El aviso en los diagramas de VLAN** — dos sesiones sin respuesta.

---

## Quick Start for Next Session

```bash
# Contexto completo
cat plans/handoffs/HANDOFF_standalone-9e6e8d31_arranque-arnes-ldaps-verificado_2026-09-20.md
cat docs/prueba-smoke-test-resultados.md   # sección 10: los hallazgos H1-H10

# Estado de partida (debe dar: master 48475b6, limpio, 0 PRs)
git log --oneline -1 && git status -s && gh pr list --state open

# Docker vive en WSL: desde PowerShell funciona, desde Git Bash NO está en el PATH
docker system df        # esperado: 11 imágenes (9,108 GB), 19 volúmenes, 0 contenedores

# ANTES de cualquier prueba larga: comprobar memoria
Get-CimInstance Win32_OperatingSystem | Select FreePhysicalMemory

# Criterio de validez de cualquier medición
wsl -d Ubuntu-24.04 -- systemctl show docker -p ExecMainStartTimestamp

# Ficheros clave para la Fase 1 del plan
docker/pc3-administracion-infra/docker-compose.yml   # líneas 53-57 (H1)
docker/pc2-operaciones/docker-compose.yml            # líneas 73-78 (H3), 136-141 (H4)
docker/pc1-medica/openvpms/entrypoint.sh             # líneas 63-74 (H2)
```
