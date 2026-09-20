# Arreglar los cuatro defectos que el arranque real destapó, y cerrar el paquete offline

**Date:** 2026-09-20
**Status:** PLANNED
**Bead(s):** none (`bd` no está instalado en esta máquina)
**Epic:** Proyecto final Redes Corporativas (UD) — Laboratorio "Reserva Viva"
**Chain:** `standalone-9e6e8d31` seq `4`
**Context:** Ver `HANDOFF_standalone-9e6e8d31_arranque-arnes-ldaps-verificado_2026-09-20.md` para los datos de la sesión, las trece tablas de evidencia y las salidas literales.

---

## Problem Statement

El arranque completo del arnés se ejecutó por fin y demostró lo que el proyecto llevaba semanas sin poder afirmar: **la autenticación LDAPS funciona de verdad** contra ERPNext (200 con `full_name "RRHH Prueba"`) e InvenTree (200 + token), con las claves erróneas rechazadas (417 y 401). Pero el mismo arranque destapó **cuatro defectos reales del entregable** que impiden cumplir el criterio de "20 contenedores arriba y sanos": un healthcheck sin margen que tumba todo ERPNext en el primer arranque en frío (H1), un entrypoint de OpenVPMS que promete por escrito una reanudabilidad que su código no implementa y entra en bucle infinito (H2), y un healthcheck de Pretix que consulta un nombre que su propia configuración rechaza, quedando enfermo para siempre (H3), con el mismo patrón latente en InvenTree (H4).

**Los tres primeros afectan al laboratorio directamente.** Con tres PCs arrancando en frío el día de la demostración, H1 y H3 se manifestarían con seguridad, y H2 ante cualquier interrupción. Ninguno se arregló en la sesión anterior porque tocar los compose estaba prohibido y porque **validarlos de verdad exige arrancar con volumen limpio**, que es justo lo que no había memoria ni tiempo para hacer.

Ver "Evidence & Data" (Tablas 5, 8 y 11) y "Code Analysis" en el handoff para las líneas exactas y las salidas literales.

## Key Findings

- **H1: `erpnext-db` tiene `retries: 40` × `interval: 5s` = 200 s de margen, sin `start_period`, contra ~300 s de inicialización real** (18:28:11 → 18:33:00 UTC) con el datadir cruzando `/mnt/d`. Compose aborta a la primera dependencia y ningún ERPNext arranca. → **Fase 1**
- **H3: el healthcheck de Pretix llama a `http://127.0.0.1/control/login/` mientras `PRETIX_PRETIX_URL` declara `http://${IP_PC2}:${PRETIX_PORT}`**; Django responde 400 y, pasado el `start_period` de 900 s, queda unhealthy para siempre. No tiene nada que ver con la memoria. → **Fase 1**
- **H4: InvenTree usa el mismo patrón** (línea 137 contra `INVENTREE_SITE_URL` de la 114) y hoy no muerde solo porque su manejo de hosts es más tolerante. Es una bomba de relojería. → **Fase 1**
- **H2: el entrypoint de OpenVPMS solo limpia las marcas de etapa si `tables -eq 0`** (línea 65). Si `toolbox database --create` creó tablas pero murió antes del `touch ${MARK}/schema`, el estado es irrecuperable: 49 tablas presentes, `/s/init` vacío, 40 reintentos. Las líneas 61-62 afirman lo contrario de lo que hace el código. → **Fase 2**
- **Un re-arranque con volúmenes existentes NO valida ninguno de estos arreglos.** En la sesión anterior `erpnext-db` pasó a healthy en 14 segundos precisamente porque el volumen persistía. **Solo un arranque en frío prueba algo.** → condiciona Fases 1 y 2
- **H10: los compose fijan las imágenes por `tag@sha256`; pedir la etiqueta a secas es otra referencia y provoca descarga.** Verificado por accidente con `mariadb:10.6.28`. Sin Internet, cualquier comando con etiqueta sin digest falla. → **Fase 3**
- **La Fase 2 del plan anterior (paquete offline) está desbloqueada:** las 11 imágenes están en local, incluida `reservaviva-smoke-openvpms-app` construida aquí, que es justo la que el paquete debe transportar. → **Fase 3**
- **La memoria es el bloqueo estructural: cuatro procesos muertos en dos sesiones.** `pretix-web` solo consume 3,664 GiB, el 47 % del límite de WSL; los nueve contenedores de ERPNext juntos, 672 MB. → condiciona todas las fases

## Anti-Goals (What NOT To Do)

- **No validar los arreglos con los volúmenes actuales.** Los 19 volúmenes conservados hacen que `erpnext-db` arranque en segundos y que OpenVPMS no reproduzca su bucle. Un PASS así no prueba nada y sería un falso PASS, exactamente el error que esta cadena acaba de cazar en `ldaplogin.py`.
- **No levantar el arnés completo cuando no haga falta.** Para validar H1 y H2 basta con los servicios implicados. Levantar los 23 lleva el host a 0,9 GB libres y mata procesos.
- **No ejecutar nada largo en segundo plano.** Claude Code mató así dos tareas. Primer plano, y bucles de espera de 3-4 minutos, no de 10.
- **No sondear el daemon con llamadas sueltas `wsl.exe` desde Windows durante una prueba.** Acelera el ciclo de reinicios de `docker.service` y contamina la medición. Usar una sesión WSL persistente.
- **No subir el límite de memoria en `.wslconfig` ni tocar `/etc/docker/daemon.json`** sin decisión explícita del usuario.
- **No tomar `RC302_Grupo6_ArquitecturaEmpresarial.pdf` como la arquitectura técnica.** Es un ensayo teórico sobre TOGAF/Zachman/DoDAF, con cero contenido técnico. La arquitectura real está en `C:\Users\jafet\Downloads\arquitectura-distribuida-multihost.md`.

## Plan

### Fase 1: Arreglar los tres defectos de healthcheck y validarlos en frío

**Goal:** Que un arranque desde cero de PC-2 y PC-3 llegue a todos los servicios `healthy` sin intervención, que es lo que ocurrirá el día de la demostración.

**Why this approach:** H1, H3 y H4 son el mismo tipo de defecto (healthchecks mal calibrados o mal dirigidos) y **comparten la validación cara**: un arranque en frío. Agruparlos hace que se pague una sola vez. La evidencia es inequívoca: H1 tiene la cronología medida (200 s de margen contra 300 s reales) y H3 tiene la causa confirmada en los logs (`Bad Request: /control/login/` cada 15 s).

- **H1** — en `docker/pc3-administracion-infra/docker-compose.yml:53-57`, añadir `start_period: 420s` al healthcheck de `erpnext-db`. **420 y no 300** porque la medición de 300 s se tomó con el datadir sobre `/mnt/d`; un PC del laboratorio con disco lento puede tardar más, y `start_period` no penaliza si se cumple antes (los fallos dentro de ese periodo no cuentan y el primer éxito lo cierra).
- **H1 (refuerzo)** — revisar si `erpnext-db` es el único con este problema: `mysql`, los dos `postgres` y `openldap` también inicializan en frío. Añadir `start_period` donde falte, con el mismo criterio.
- **H3** — en `docker/pc2-operaciones/docker-compose.yml:73-78`, cambiar el test para que la petición lleve un `Host` que Pretix acepte. Dos opciones: (a) usar `urllib.request.Request(url, headers={'Host': …})` con el valor de `IP_PC2`, o (b) añadir `127.0.0.1` a los hosts permitidos de Pretix por variable de entorno. **Preferir (a)**: no relaja la configuración de seguridad de la aplicación.
- **H3 (secundario)** — bajar el `start_period` de 900 s. Quince minutos enmascaran el fallo tanto que la sesión anterior lo tomó por "arrancando". Con la medida real de arranque de Pretix, 300 s deberían sobrar; medirlo antes de fijarlo.
- **H4** — aplicar el mismo arreglo a `inventree-app` (línea 137), aunque hoy no falle. Es el mismo defecto latente y cuesta una línea.
- **Validación en frío, que es el punto de la fase:** `docker compose down -v` (aquí **sí** con `-v`, es el objetivo) y `up -d` de nuevo, con los 23 contenedores. Cerrar antes navegadores y sesiones de Claude sobrantes; el host necesita ≥7 GB libres.
- **Antes y después de la prueba**, registrar `systemctl show docker -p ExecMainStartTimestamp`. Si cambia, el resultado no vale y se repite.

**Files:** `docker/pc3-administracion-infra/docker-compose.yml` (healthcheck de `erpnext-db`, y los demás que lo necesiten), `docker/pc2-operaciones/docker-compose.yml` (healthchecks de `pretix-web` e `inventree-app`), `docs/prueba-smoke-test-resultados.md` (nueva sección con el resultado del arranque en frío).
**Validates with:** `docker compose up -d` con **EXIT 0 a la primera** sobre volúmenes borrados; los 3 jobs en `Exited (0)`; **20 contenedores `Up` y todos los que tienen healthcheck en `healthy`**, incluido `pretix-web`; `ldaplogin.py` con PASS y exit 0.
**Rollback:** `git revert` de los cambios en los compose. Los healthchecks vuelven a su estado actual, que arranca igual de mal pero es el estado conocido.

### Fase 2: Hacer el entrypoint de OpenVPMS realmente reanudable

**Goal:** Que una interrupción a mitad del primer arranque de OpenVPMS no deje el contenedor en bucle infinito sin recuperación posible.

**Why this approach:** El mecanismo está verificado, no supuesto: `/s/init` vacío con 49 tablas en la base y 40 reintentos. La causa es que `step()` hace `touch` **después** de ejecutar el comando, y las marcas solo se limpian cuando la base está vacía. No es una hipótesis: se listó el volumen.

- En `docker/pc1-medica/openvpms/entrypoint.sh`, hacer que `step schema` sea **tolerante a que el esquema ya exista**: si `toolbox database --create` falla con `there are tables already present`, tratarlo como etapa cumplida y marcarla, en vez de abortar.
- **Alternativa más limpia si encaja:** detectar la condición *antes* de llamar al comando — si `tables > 0` y no hay marca `schema`, escribir la marca y continuar, porque las tablas demuestran que el esquema se creó.
- **Cuidado con el caso intermedio:** que haya tablas no garantiza que el esquema esté completo. Si `dataload.sh setup` también quedó a medias, la siguiente etapa fallará. Documentar el límite en el propio script en vez de fingir que cubre todo.
- **Corregir el comentario de las líneas 61-62.** Ahora mismo afirma una reanudabilidad que el código no implementa; ese comentario es parte del defecto, porque hizo que nadie lo revisara.
- Considerar registrar la marca **antes** del comando y borrarla si falla, en vez de al revés. Cambia la semántica de "esto terminó" a "esto empezó", que es lo que hace falta para detectar interrupciones.
- **Validación en frío obligatoria**, y además **con interrupción provocada**: arrancar, matar el contenedor a mitad de la creación del esquema, y comprobar que el siguiente arranque se recupera solo.

**Files:** `docker/pc1-medica/openvpms/entrypoint.sh`, `docs/prueba-smoke-test-resultados.md`.
**Validates with:** tras `down -v` y `up -d`, matar `openvpms-app` durante la creación del esquema; el arranque siguiente debe **completar sin intervención** y dejar el contenedor `Up`, sin `Restarting`.
**Rollback:** `git revert`. El entrypoint vuelve al estado actual, que funciona en el camino feliz.

### Fase 3: Cerrar el paquete offline con la red cortada (B3)

**Goal:** Demostrar que los tres PCs del laboratorio pueden desplegarse sin Internet, que es un requisito explícito del profesor.

**Why this approach:** Es la deuda que lleva abierta desde el seq 2 y ahora está desbloqueada: las 11 imágenes están en local, incluida la de OpenVPMS **construida aquí**, que el Dockerfile dice expresamente que hay que transportar con `docker save`/`docker load`. Lo único que faltaba era tenerla.

- Ejecutar `scripts/preparar-paquete-offline.sh` de punta a punta. **Recordar que se niega a correr si la carpeta de salida existe o si hay cambios sin commitear** (salvo `PERMITIR_SUCIO=1`).
- **Verificar que se genera `overrides/`**, que es justo lo que no se pudo confirmar en el seq 3 porque la salida se perdió.
- **Atención a H10, que es el riesgo principal:** los compose fijan por `tag@sha256` y el paquete guarda por etiqueta. Comprobar que al cargar con `docker load` las imágenes satisfacen las referencias con digest de los compose. Si no, el `up --pull never` fallará **en el laboratorio, sin red, el día de la demostración**.
- Ejecutar `scripts/instalar-paquete-offline.ps1` con `-Perfil pc1|pc2|pc3`. **Nunca se ha ejecutado**; es de esperar que aparezcan fallos triviales de ruta o codificación.
- **La prueba sin red de verdad:** cortar la salida a Internet (o usar un motor `docker:dind` aislado) y hacer `docker load` + `up --pull never`.
- Registrar el resultado tal cual, incluido el fallo si lo hay. Marcar explícitamente lo que quede sin probar.

**Files:** `docs/paquete-offline-fase0.md` (registro de verificación), `scripts/instalar-paquete-offline.ps1` (si aparecen defectos), `scripts/preparar-paquete-offline.sh` (ídem).
**Validates with:** `docker load` de todas las imágenes del paquete y `docker compose up -d --pull never` **con la red cortada**, llegando a los mismos criterios de la Fase 1.
**Rollback:** ninguno necesario; la fase no modifica el despliegue. Si el paquete sale mal, se borra la carpeta de salida y se repite.

### Fase 4: Saneamiento y cierre documental

**Goal:** Dejar el repositorio y la máquina en un estado que no arrastre deuda a la siguiente sesión.

**Why this approach:** Son pendientes acumulados, ninguno difícil, varios arrastrados desde el seq 1. Van al final porque ninguno bloquea a los demás.

- **Borrar los 8 worktrees huérfanos** de `D:\Proyectos\ProyectoFinak-*` y las ramas locales ya fusionadas. **El comando debe ejecutarlo el usuario**: el clasificador de permisos lo bloquea desde hace tres sesiones.
- **Fusionar o archivar `docs/handoff-plan-lab-3pcs`**, que arrastra dos handoffs sin llegar a master desde el seq 1.
- **Decidir por defecto el aviso de "diseño propuesto" en los diagramas de VLAN** y comunicarlo. Lleva **dos sesiones sin respuesta**: preguntarlo otra vez es perder el tiempo.
- **Cerrar el caso 4 de `ldaplogin.py`** (`--persistencia`), que necesita el arnés vivo. Encaja naturalmente al final de la Fase 1, aprovechando que estará levantado.
- **Decidir qué hacer con `C:\Users\jafet\evidencia-arnes-2026-09-20\`**, que contiene el token de InvenTree sin recortar.
- **Revisar si procede rotar las claves de laboratorio** de `docker/pc3-administracion-infra/ldap/README.md` antes de hacer público el repositorio.

**Files:** `docs/` varios, diagramas de VLAN.
**Validates with:** `git worktree list` con una sola entrada; `git branch -a` sin ramas muertas; 0 PRs abiertos.
**Rollback:** no aplica.

## Dependencies & Order

- **Fase 1 antes que Fase 2.** Ambas necesitan arranque en frío; si se hacen a la vez y algo falla, no se sabrá cuál lo rompió. Además la Fase 1 deja el arnés levantado y sano, que es el punto de partida limpio de la Fase 2.
- **Fase 3 depende de que la Fase 1 esté cerrada**, porque el paquete debe llevar los compose ya corregidos. Empaquetar los defectuosos sería trasladar H1 y H3 al laboratorio.
- **Fase 4 es independiente** y puede hacerse en cualquier momento o en paralelo por otro agente; solo toca documentación y limpieza.
- **El caso 4 de `ldaplogin.py`** se engancha al final de la Fase 1, sin arranque adicional.

## Risks & Mitigations

- **La memoria vuelve a matar el proceso (muy probable: cuatro veces en dos sesiones).** Mitigación: cerrar navegadores y sesiones de Claude sobrantes antes de empezar; ejecutar en primer plano; para las fases que no necesiten el arnés completo, levantar solo los servicios implicados. Parar `pretix-web` libera 3,7 GB.
- **`docker.service` cicla y invalida la medición (ocurrió seis veces).** Mitigación: sesión WSL persistente abierta durante toda la prueba, y comparar `ExecMainStartTimestamp` antes y después. Si cambió, repetir.
- **El arranque en frío tarda mucho (≈9 min solo `create-site`, más las bases).** Mitigación: contar con 20-25 minutos por validación y no interrumpir. No es un fallo, es el coste de la prueba.
- **`instalar-paquete-offline.ps1` nunca se ha ejecutado** y es PowerShell 5.1 en ASCII: probable que falle a la primera. Mitigación: tratar el primer fallo como esperado y presupuestar una iteración.
- **Los arreglos de healthcheck pueden enmascarar un problema real en vez de resolverlo.** Si Pretix tarda de verdad más de 300 s en estar listo, bajar el `start_period` lo dejaría unhealthy por un motivo legítimo. Mitigación: **medir el arranque real antes de fijar el valor**, no elegirlo por intuición.
- **Riesgo de falso PASS, que es el patrón que esta cadena ya cazó una vez.** Mitigación: cada comprobación debe fallar por la razón correcta. Verificar explícitamente el mensaje de error, no solo el código de salida.

## Success Criteria

- **Mínimo viable:** `docker compose up -d` sobre volúmenes borrados termina con **EXIT 0 a la primera**, sin el `dependency failed to start` que hoy obliga a relanzar.
- **Los 20 contenedores permanentes en `Up`** y todos los que tienen healthcheck en `healthy`, **incluido `pretix-web`**, que hoy nunca lo consigue. Es el criterio 2, el único de los cuatro que hoy no se cumple.
- **`openvpms-app` sobrevive a una interrupción provocada** durante la creación del esquema y se recupera solo en el arranque siguiente, sin `Restarting`.
- **`ldaplogin.py` con PASS y exit 0 en un arranque en frío**, no solo sobre volúmenes preexistentes. Referencia: hoy pasa, pero sobre una base ya inicializada.
- **Éxito completo:** además, `docker load` + `up --pull never` **con la red cortada** llega a los mismos criterios, cerrando B3 y demostrando el requisito de "sin Internet" del profesor.
- **Cada resultado registrado con salida literal**, y lo no probado marcado como NO VERIFICADO. La norma del proyecto no se relaja porque los arreglos sean nuestros.

## Quick Start

```bash
# Contexto completo
cat plans/handoffs/HANDOFF_standalone-9e6e8d31_arranque-arnes-ldaps-verificado_2026-09-20.md
cat docs/prueba-smoke-test-resultados.md        # sección 10: hallazgos H1-H10

# Estado de partida esperado: master 48475b6, limpio, 0 PRs
git log --oneline -1 && git status -s && gh pr list --state open

# Ficheros de la Fase 1
docker/pc3-administracion-infra/docker-compose.yml   # líneas 53-57  -> H1
docker/pc2-operaciones/docker-compose.yml            # líneas 73-78  -> H3
docker/pc2-operaciones/docker-compose.yml            # líneas 136-141 -> H4
docker/pc1-medica/openvpms/entrypoint.sh             # líneas 61-74  -> H2 (Fase 2)

# Verificar el estado antes de tocar nada (desde PowerShell; en Git Bash docker NO está en el PATH)
docker system df                                      # esperado: 11 imágenes, 19 volúmenes, 0 contenedores
Get-CimInstance Win32_OperatingSystem | Select FreePhysicalMemory

# Criterio de validez de toda medición: comparar antes y después
wsl -d Ubuntu-24.04 -- systemctl show docker -p ExecMainStartTimestamp

# PRIMERA ACCIÓN CONCRETA: añadir start_period al healthcheck de erpnext-db
#   en docker/pc3-administracion-infra/docker-compose.yml, tras "retries: 40" (línea 57):
#       start_period: 420s
#   y después, la validación que es el punto de la fase:
cd pruebas/smoke-test-3-pcs
docker compose down -v        # SÍ con -v: el arranque en frío es el objetivo
docker compose up -d          # debe dar EXIT 0 a la primera, sin relanzar
```
