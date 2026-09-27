# Consolidar el sistema vivo en "un host" (sin restos de 3 PCs) y escribir su documentación

**Date:** 2026-09-26
**Status:** PLANNED
**Bead(s):** none (`bd` no está instalado)
**Epic:** Proyecto final Redes Corporativas (UD, 678-302). Laboratorio "Reserva Viva"
**Chain:** `standalone-9e6e8d31` seq `6` (copiado del handoff emparejado)
**Context:** See `HANDOFF_standalone-9e6e8d31_consolidacion-un-host-documentacion_2026-09-26.md` for session data, test results, and prior approaches.

---

## Problem Statement

El refactor del 26/09 ya está en master (`93b106d`): 112 → 70 ficheros, el diseño de red como anexo en `diseno-red/`, el arnés en `sistema/` y una regresión de **92 PASS / 0 FAIL**. Pero el **código que arranca el sistema** sigue pensando en 3 PCs:

- Los compose resuelven LDAP, DNS, NTP y las URL de las apps con "IP LAN de PC-2/PC-3" (`IP_PC2`, `IP_PC3`).
- `IP_PC2` es la IP de InvenTree y se usa como URL de Pretix (**H20**).
- La zona DNS apunta `dns`/`ntp` a openldap y `pretix` a inventree (**H21**).
- La CA se copia "a PC-1 y PC-2", `test.env` arrastra `IFACE` y la salida dice "PC-1 Medica".

El usuario pide *"consolidar todo lo de un host eliminando lo que no corresponda, y consolidarlo y crear los documentos de la documentación correspondiente"*. Hoy faltan los documentos de arquitectura, operación, seguridad y aplicaciones (Tabla 11 del handoff). Los datos están en las Tablas 5, 6, 7 y 11 del handoff.

## Key Findings

- **Hay regresión objetiva y línea base de configuración.** `levantar-sistema verificar` = 92 PASS / 0 FAIL / 14 INFO, y `config-antes.yml` (869 líneas) en el scratchpad del handoff. Todo cambio se mide contra ambos. → Fases 1-3.
- **Los restos de 3 PCs se dividen en dos clases.**
  - Cosméticos: comentarios, etiquetas, "NO VERIFICADO", `IFACE` (0 usos en la configuración resuelta). Su `config` diff debe salir **vacío**. → Fase 1.
  - Semánticos: `IP_PC2`, `IP_PC3`, la zona y la CA. Cambian la configuración y hay que validarlos en vivo. → Fase 2.
- **H20 puede estar enmascarado.** `verificar` pasa porque las sondas mandan `Host` explícito, pero nadie ha probado Pretix en un navegador en `http://localhost:18082`. Cambiar `PRETIX_PRETIX_URL` puede romper su healthcheck (ya pasó con H3/H4). → Fase 2, paso a paso.
- **`verificar` no ve H21 entero.** `bloque_dns` solo compara `dns`/`ntp`/`ldap` con las IP reales, así que la zona puede estar mal para `pretix` sin ningún aviso. → Fase 2 amplía el test **antes** de arreglar la zona.
- **La decisión E del 26/09 fue "no fusionar los compose"**, y el encargo nuevo dice "consolidarlo". Es ambiguo y la memoria exige no volver a proponerlo por mi cuenta. → Fase 0 (pregunta) y Fase 3 (condicional).
- **El hueco documental** es de 4 documentos: arquitectura, operación, seguridad y aplicaciones. El conocimiento operativo (trampas de WSL, protocolo de validación) solo vive en handoffs, que no son documentación del proyecto. → Fase 4.
- **Los PR los fusiona el usuario por su cuenta** (#31, #32 y #33). Hay que consultar `gh pr view` antes de planear sobre un PR. → Fase 5.

## Anti-Goals (What NOT To Do)

- **No fusionar los compose ni renombrar `docker/pcN-*`** sin un "sí" explícito en la Fase 0. La decisión vigente (memoria `proyecto-consolidado-en-un-host`) es no hacerlo.
- **No cambiar `name: reservaviva-smoke` ni los nombres de red `vlanXX_*`**: son volúmenes inicializados (~30 min para rehacerlos) y los usa `verificar_arquitectura.py`.
- **No usar `down -v` ni `levantar-sistema borrar`**, no descargar imágenes (`nicolaka/netshoot`) y no hacer `wsl --shutdown` sin permiso.
- **No mezclar cambios cosméticos y semánticos en un commit.** Si la regresión falla, hay que saber qué la rompió.
- **No escribir documentación que duplique cifras:** los números viven en `docs/resultados-un-host.md` y el resto enlaza. No reintroducir guías de 3 PCs.

## Plan

### Phase 0: Alcance (bloqueante) y reparto

**Goal:** fijar qué significa "consolidar" y qué documentos se escriben, antes de tocar nada.

**Why this approach:** la última vez, la pregunta B-E evitó borrar material evaluable. "Consolidarlo" puede revertir la decisión E, y eso lo decide el usuario, no el plan.

- `git status -sb`, `gh pr list --state open` y `powershell -File .\levantar-sistema.ps1 estado`. Esperado: 25 servicios, 22 en marcha.
- AskUserQuestion con 4 preguntas, cada una con su recomendación:
  1. **Compose:** (a) solo limpiar la configuración y conservar los 3 compose por departamento (recomendado, por la decisión E y el riesgo); (b) además, fusionarlos en uno con overrides integrados.
  2. **Carpetas `docker/pcN-*`:** conservarlas (recomendado, porque es la agrupación de la Entrega 1) o renombrarlas por departamento.
  3. **Documentos**, multiselección: arquitectura, operación, seguridad y aplicaciones (los 4 recomendados), y un diagrama de un host.
  4. **Los 8 worktrees huérfanos:** eliminarlos (recomendado; ramas ya fusionadas o abandonadas) o conservarlos.
- Si la respuesta 1 es (b), actualizar la memoria `proyecto-consolidado-en-un-host.md`: el usuario cambió la decisión E.
- **Reparto** (memoria fijada: delegar con encargos exhaustivos). Llamar a `ListAgents`.
  - Si hay sesiones peer, las Fases 1-2 las lleva **una sola** sesión, porque tocan los mismos compose.
  - La Fase 4 se reparte **un documento por agente**, con propiedad de ficheros explícita.
  - Cada encargo lleva: objetivo, ficheros permitidos y prohibidos, contexto que leer (este plan, el handoff y sus Tablas 6, 7 y 11), trampas (Anexo A del handoff), cómo se verifica y a quién se reporta.
  - Si no hay peers, ejecutar yo.

**Files:** ninguno (solo memoria si cambia E).
**Validates with:** respuestas registradas; `estado` 25/25.
**Rollback:** n/a.

### Phase 1: Limpieza cosmética del sistema vivo (sin cambio de configuración)

**Goal:** que lo que lee quien llega nuevo en el código vivo diga "un host". La configuración resuelta no cambia **ni una línea**.

**Why this approach:** son la mayoría de los restos (Tabla 5) y no tienen riesgo si el `config` diff sale vacío. Separarlos de la Fase 2 aísla la regresión.

- `sistema/test.env`: quitar `IFACE=eth0` (0 usos). Reescribir los comentarios de las líneas 15-19 ("Compose oficiales en bridge (Windows + Docker Desktop)…") para describir un host. **No tocar los valores de las claves.**
- Los 3 `docker/pcN-*/docker-compose.yml`:
  - Quitar "NO VERIFICADO" (pc1 y pc3).
  - Comentarios "PC-3", "IP LAN" y "choca con ICS de Windows" → describir el bridge local.
  - Los mensajes `:?definir X en .env` → `en sistema/test.env`. Solo cambia el texto del mensaje de error; comprobar que `config` sigue idéntico.
- `levantar-sistema.sh`:
  - `accesos()`: etiquetas por departamento ("Medica", "Taquilla", "Logistica", "RRHH", "Infra") sin "PC-x".
  - `generar_zona`: el mensaje "Generada (PC-1=… PC-2=… PC-3=…)" pasa a hablar de servicios.
  - Mantener ASCII y LF.
- `scripts/generar-certificados.sh`: solo los comentarios de las líneas 6-9 y 121. El bucle de copia se trata en la Fase 2.
- `sistema/README.md`: quitar "macvlan -> bridge" y describir qué es cada `override-pcN.yml` (IP fijas en vlan99).
- Editar con un helper que respete CRLF/LF y con `assert count==N` (Anexo A #12 del handoff).

**Files:** `sistema/test.env`, `docker/pc{1,2,3}-*/docker-compose.yml`, `levantar-sistema.sh`, `scripts/generar-certificados.sh`, `sistema/README.md`.
**Validates with:**
- `cd sistema && docker compose --env-file test.env config > /tmp/c1.yml && diff <scratchpad>/config-antes.yml /tmp/c1.yml` **vacío**. Correr dentro de WSL con `--exec bash -c`.
- `bash -n levantar-sistema.sh`.
- `levantar-sistema.ps1 preparar` RC=0.
- `git grep -cE "IFACE|NO VERIFICADO"` en el sistema vivo = 0.

**Rollback:** `git revert` del commit, que no toca el comportamiento.

### Phase 2: Consolidación semántica: direcciones reales de cada servicio, zona correcta y una sola CA (H20, H21)

**Goal:** que cada servicio se encuentre por su dirección real en el host y que la zona DNS diga la verdad, manteniendo 92+ PASS / 0 FAIL.

**Why this approach:** `IP_PC2`/`IP_PC3` solo tenían sentido con una IP LAN por PC (Tabla 7). El compose de PC-3 ya usa `${NET_INFRA:-10.10.99}.10`, un patrón nativo de un host que se puede copiar. Se hace en tandas, porque H20 puede romper healthchecks.

- **2a. Ampliar el test primero.**
  - `sistema/verificar_arquitectura.py`, `bloque_dns` (~líneas 377-404): comparar **los 7 nombres** de la zona (`dns`, `ldap`, `ntp`, `openvpms`, `pretix`, `inventree`, `rrhh`) con su contenedor real (Tabla 7). `rrhh` debe apuntar a erpnext-hr/erpnext-backend; comprobar cuál publica HTTP.
  - Ejecutar `verificar --rapido`. Esperado: nuevos INFO/FAIL que **confirman H21** (pretix → .30.10). Es el "rojo" antes del arreglo.
  - Revisar el `--autotest` (~línea 568), que espera `10.10.99.10`.
- **2b. Zona.** En `generar_zona` de `levantar-sistema.sh`, sustituir `ip1/ip2/ip3` por una variable por nombre, y en `db.reservaviva.local.tpl` sustituir `${IP_PC1..3}` por `${IP_DNS}`, `${IP_LDAP}`, `${IP_NTP}`, `${IP_OPENVPMS}`, `${IP_PRETIX}`, `${IP_INVENTREE}` e `${IP_RRHH}`. Las IP salen de la Tabla 7 (no inventarlas). Actualizar "Hallazgos previstos" en `verificar_arquitectura.md`: la discrepancia desaparece.
- **2c. LDAP, DNS y NTP de las apps.**
  - `docker/pc1-medica/docker-compose.yml`: `LDAP_HOST`/`DNS_HOST`/`NTP_HOST: ${IP_PC3}` → `${NET_INFRA:-10.10.99}.10`, `.11` y `.12`, con el mismo patrón que pc3.
  - `docker/pc2-operaciones/docker-compose.yml`: `extra_hosts ldap.reservaviva.local:${IP_PC3}` → `${NET_INFRA:-10.10.99}.10`.
  - Quitar `IP_PC3` de `test.env`.
- **2d. URL de Pretix e InvenTree (H20), en una tanda aparte.**
  - `PRETIX_PRETIX_URL` y `INVENTREE_SITE_URL` → `http://localhost:${PRETIX_PORT}` y `http://localhost:${INVENTREE_PORT}`, que es lo que usa el navegador.
  - Las sondas: `Host` coherente con esa URL.
  - **Antes**, leer en la imagen cómo Pretix deriva `ALLOWED_HOSTS`/CSRF de `PRETIX_PRETIX_URL`, con `docker exec pretix-web python -c …` o leyendo su `settings.py`. No suponerlo.
  - Si `localhost` no es aceptable dentro del contenedor para la sonda, usar `Host: localhost:${PRETIX_PORT}` explícito.
  - Quitar `IP_PC2` de `test.env`.
- **2e. Una sola CA.**
  - pc1 y pc2 montan `../pc3-administracion-infra/certs/ca.crt` (ruta relativa al compose incluido) en vez de `./certs/ca.crt`.
  - `generar-certificados.sh` deja de copiar (se quita el bucle de la línea 99).
  - `preparar` añade `test -s docker/pc3-administracion-infra/certs/ca.crt`, porque, si falta, Docker crea un directorio vacío.
  - Quitar `docker/pc{1,2}-*/certs/` del `.gitignore` si ya no se usan.
- **Validación tras cada tanda (2b-2e):**
  - `config` diff: solo cambian las líneas previstas.
  - `levantar-sistema arrancar`: se recrean los contenedores cuyo entorno cambió; los volúmenes se conservan.
  - Después, `verificar`.

**Files:** `sistema/verificar_arquitectura.{py,md}`, `levantar-sistema.sh`, `docker/pc3-administracion-infra/bind/zones/db.reservaviva.local.tpl`, `docker/pc{1,2}-*/docker-compose.yml`, `sistema/test.env`, `scripts/generar-certificados.sh`, `.gitignore`.
**Validates with:**
- `verificar` completo con **≥ 92 PASS** (sube por los nombres nuevos), **0 FAIL** y RC=0.
- El INFO "los nombres dns/ntp/ldap apuntan…" desaparece: se esperan **13 INFO** (12 app↔app + chronyc).
- `ExecMainStartTimestamp` igual antes y después.
- Pretix en el navegador integrado: `http://localhost:18082/control/login/` carga y el login con `admin@reservaviva.local` funciona. No escribir la clave en el chat: leerla de `test.env` dentro del flujo de prueba de la app local.
- `git grep -c "IP_PC"` en el sistema vivo = 0.

**Rollback:** `git revert` de la tanda y `levantar-sistema arrancar` (recrea con la configuración anterior; los volúmenes siguen).

### Phase 3 (CONDICIONAL: solo si la Fase 0 dijo "fusionar"): un compose nativo

**Goal:** un único `sistema/docker-compose.yml` con las redes y las IP de vlan99 nativas, sin `include:` ni `override-pcN.yml`.

**Why this approach:** es lo que "consolidarlo" podría significar. Es el cambio más arriesgado, así que va después de que la Fase 2 deje la configuración limpia.

- Partir de `docker compose config` (ya resuelto) como borrador y rehacer las variables `${…}` en vez de copiar valores literales.
- Mantener `name: reservaviva-smoke`, los nombres de red `vlan10_medica`… y los nombres de servicio y de volumen.
- Si la Fase 0 dijo "conservar carpetas", los servicios pueden seguir agrupados por comentarios de departamento. La imagen de OpenVPMS sigue en `docker/pc1-medica/openvpms/`.
- Borrar `sistema/override-pc*.yml` y los 3 `docker/pcN-*/docker-compose.yml`, con "COMO RECUPERARLO" en el commit.
- Actualizar las rutas de `verificar_arquitectura.py` (`ZONA`), `levantar-sistema.sh` y la documentación.

**Files:** `sistema/docker-compose.yml`, los overrides, `docker/pc*/docker-compose.yml`, `levantar-sistema.sh` y las rutas de los guiones.
**Validates with:** `config` normalizado **equivalente** al de la Fase 2 (mismos servicios, IP, volúmenes y redes); `arrancar` 25/25; `verificar` sin cambios respecto a la Fase 2.
**Rollback:** `git revert`, porque los volúmenes no cambian al mantener el nombre de proyecto.

### Phase 4: Documentación de un host

**Goal:** que quien clone el repo entienda qué es, cómo funciona, cómo se opera y qué garantías de seguridad tiene, sin leer handoffs.

**Why this approach:** la Tabla 11 del handoff muestra 4 huecos. El conocimiento operativo más caro (Anexos A y C) solo está en handoffs.

- `docs/arquitectura.md`:
  - Los 25 servicios por departamento, las redes y sus IP (Tabla 7), qué app está dual-homed y por qué.
  - Los flujos: login LDAP de ERPNext/InvenTree, resolución de nombres (DNS de Docker frente a bind9 y `extra_hosts`), NTP.
  - Los puertos publicados (Tabla 6) y un diagrama de un host en Mermaid (o Archify si se pidió).
  - La diferencia con el diseño de 3 equipos: enlace a `diseno-red/`.
- `docs/operacion.md`:
  - Acciones de `levantar-sistema` y qué hace cada una.
  - Qué hacer tras reiniciar el PC; cómo leer `estado`, `diagnostico` y los logs.
  - Recuperar un arranque cortado (es reanudable) y liberar memoria (`detener`).
  - Trampas de Windows/WSL (Anexo A #1-11, redactadas para usuario, no para agente).
  - El protocolo de validación (Anexo C).
- `docs/seguridad.md`:
  - La CA interna y `generar-certificados.sh`, LDAPS con verificación, las ACL (`05-acl-servicio.ldif`), las cuentas de servicio de bind y los usuarios de prueba.
  - Dónde están los secretos (`sistema/test.env`), que son de laboratorio, y la obligación de rotarlos si el repo se hace público.
  - H19 (el administrador de Pretix por defecto se borra).
  - Lo que un host no aísla: vlan99 es un dominio L2 (los 12 INFO).
- `docs/aplicaciones.md`: por aplicación, el departamento, la URL, el usuario inicial, LDAP sí o no (con enlace a los dos documentos LDAP) y para qué la usa el departamento.
- Actualizar el `README.md`: una sección "Documentación" con los 4 enlaces, sin duplicar contenido. Actualizar `sistema/README.md` y `docs/integracion-ldap-erpnext-inventree.md`, que todavía dice "arnés" y la fecha 19/09.
- Reglas: las cifras solo en `docs/resultados-un-host.md` (el resto enlaza), y ninguna clave copiada de `test.env`.
- Si se delega, un agente por documento con propiedad exclusiva del fichero; el coordinador revisa contra el código real (nombres, IP y puertos).

**Files:** `docs/{arquitectura,operacion,seguridad,aplicaciones}.md` (nuevos), `README.md`, `sistema/README.md` y `docs/integracion-ldap-erpnext-inventree.md`.
**Validates with:**
- Todos los enlaces relativos resuelven (bucle `grep -oE '\]\([^)]+\)'` + `test -e` del handoff).
- `grep -rn` de cada IP, puerto y nombre de servicio citado contra el `compose config`.
- `git grep -nE "PC-[123]"` en `docs/` solo en contexto de anexo.

**Rollback:** `git revert` (solo documentación).

### Phase 5: Cierre

**Goal:** dejar master con todo validado y la documentación de resultados al día.

- `docs/resultados-un-host.md`: añadir la pasada final de `verificar`, marcar H20/H21 como resueltos y actualizar los pendientes.
- `sistema/verificar_arquitectura.md`: estado y hallazgos al día.
- Worktrees: si la Fase 0 dijo "eliminar", comprobar primero con `git -C <wt> status -s` que no tienen cambios; con cambios, preguntar. Después, `git worktree remove <ruta>` uno a uno. Nunca `--force` sin permiso.
- Push y PR a master, **listo para revisión (no borrador)**. Antes de fusionar, `gh pr view` para ver si el usuario ya lo fusionó.

**Validates with:** `verificar` final ≥ 92 PASS / 0 FAIL; `git worktree list` según la decisión; el PR abierto o fusionado.
**Rollback:** n/a.

## Dependencies & Order

- La Fase 0 bloquea todo: la respuesta 1 decide si la Fase 3 existe, y la 3 decide el alcance de la Fase 4.
- Fase 1 → Fase 2: la Fase 1 deja el `config` diff vacío como punto de partida limpio. Dentro de la Fase 2, **2a antes de 2b** (test en rojo antes del arreglo) y 2d en su propio commit.
- Fase 2 → Fase 3: no se fusiona una configuración que aún tiene `IP_PC*`.
- La Fase 4 puede empezar en paralelo con la Fase 2 **solo** para `seguridad.md` y `aplicaciones.md`. `arquitectura.md` y `operacion.md` describen el resultado de las Fases 2-3 y van después.
- La Fase 5 va al final.

## Risks & Mitigations

- **Pretix rechaza el nuevo `Host`/URL (H20) y queda unhealthy.** Probabilidad media: ya pasó con H3/H4. Mitigación: leer primero cómo deriva `ALLOWED_HOSTS`; tanda 2d aislada; `diagnostico` de `levantar-sistema` muestra los logs; revert inmediato.
- **Montar la CA desde `../pc3-administracion-infra/certs/` con `include:`**: las rutas relativas se resuelven respecto al compose incluido. Si se resuelve mal, Docker crea un directorio vacío y LDAPS de InvenTree falla (caso 1 de `ldaplogin`). Mitigación: `config` diff (se ve la ruta absoluta), `test -s` en `preparar` y `verificar`.
- **La ampliación de `bloque_dns` introduce falsos FAIL** (p. ej. `rrhh` → ¿nginx o backend?). Mitigación: mirar la Tabla 7 y `docker inspect` antes de fijar la expectativa, y documentar la elección.
- **Memoria del host:** cada `verificar` cuesta ~14 min con `down`/`up`. Usar `--rapido` entre tandas y el completo al cerrar cada fase.
- **Documentación que se desfasa:** una fuente por dato (cifras en resultados, IP en arquitectura) y el resto enlaza.

## Success Criteria

- **Mínimo:**
  - Fase 1 con `config` diff vacío.
  - Fase 2 con `git grep -c "IP_PC"` = 0 en el sistema vivo, zona correcta para los 7 nombres y `verificar` ≥ 92 PASS / 0 FAIL / 13 INFO.
  - Pretix funcionando en el navegador en `localhost:18082`.
- **Completo:** lo anterior más los 4 documentos de la Fase 4 enlazados desde el README, con todos los enlaces resolviendo, y (si se aprobó) la Fase 3 con `verificar` sin cambios.
- La regla de "un host" se cumple: fuera de `diseno-red/` y `plans/`, "PC-1/2/3" solo aparece como nombre de carpeta `docker/pcN-*` (si se conservan).
- Cada commit que borra algo dice cómo recuperarlo.

## Quick Start

```bash
# Contexto completo
cat plans/handoffs/HANDOFF_standalone-9e6e8d31_consolidacion-un-host-documentacion_2026-09-26.md

# Ficheros clave de las Fases 1-2
cat sistema/test.env | sed 's/PASSWORD=.*/PASSWORD=***/'
sed -n 60,120p docker/pc2-operaciones/docker-compose.yml     # PRETIX_PRETIX_URL, sonda
sed -n 90,115p docker/pc1-medica/docker-compose.yml          # LDAP_HOST/DNS_HOST/NTP_HOST
sed -n 130,160p levantar-sistema.sh                           # generar_zona
sed -n 370,410p sistema/verificar_arquitectura.py             # bloque_dns

# Línea base de configuración (scratchpad de la sesión anterior)
# C:\Users\jafet\AppData\Local\Temp\claude\D--Proyectos-UD-RedesCorporativaa-ProyectoFinak\dd3ee9cd-d282-4211-8aa6-837091517da9\scratchpad\config-antes.yml
# Si no existe, regenerarla ANTES de tocar nada:
#   wsl.exe -d Ubuntu-24.04 --cd "D:\Proyectos\UD.RedesCorporativaa.ProyectoFinak\sistema" --exec bash -c 'docker compose --env-file test.env config' > config-antes.yml

# Verificar el estado de partida
git status -sb && gh pr list --state open
powershell -File .\levantar-sistema.ps1 estado

# Primera acción concreta
# Fase 0: AskUserQuestion con las 4 preguntas (compose, carpetas, documentos, worktrees).
```
