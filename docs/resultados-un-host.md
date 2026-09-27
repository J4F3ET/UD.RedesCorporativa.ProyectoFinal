# Resultados del sistema en un host

Documento vigente con las cifras medidas. Sustituye a las actas históricas (`docs/prueba-smoke-test-resultados.md` y `docs/auditoria-coherencia-documental.md`), retiradas el 26/09/2026. Se pueden leer con `git show 95e0da4:<ruta>`.

**Entorno de medida:** Windows 11 con 13,9 GB de RAM y Docker Engine 29.8.1 / Compose 5.5.1 dentro de WSL (`Ubuntu-24.04`), sin Docker Desktop. La VM de WSL tiene 8 GB de techo. Proyecto compose `reservaviva-smoke`.

## Arranque (`levantar-sistema.ps1 -Forzar`, 26/09/2026)

| Hecho | Valor |
|---|---|
| Resultado | **25/25 sanos, RC=0**: 22 en marcha + 3 trabajos de un solo disparo en `Exited (0)` |
| Duración total | **15 min 45 s** (17:01:13 → 17:16:58); la espera interna del script, 10 min 31 s |
| Punto crítico | OpenVPMS crea su esquema desde cero en 5 min 4 s y después carga los datos base |
| Reinicios / OOM | 0 / ninguno en los 25 |
| Peor momento de memoria del host | 157 MB disponibles y 647 páginas/s durante la inicialización de OpenVPMS; se recuperó solo |

Condición: imágenes ya descargadas y volúmenes de ERPNext existentes (el sitio se adoptó como completo; ver H16). El arranque en frío con todo vacío está en la sección siguiente.

## Arranque en frío desde un clon limpio (27/09/2026, primera pasada: falla)

Lo que haría una persona externa: `git clone` + el lanzador, sin nada del proyecto en Docker. Antes se borró todo lo del proyecto en este PC: `levantar-sistema.ps1 borrar -Si` (25 contenedores, 12 volúmenes con nombre, 6 redes), los 92 volúmenes anónimos que quedaban y las 14 imágenes del proyecto (incluidas 2 construcciones viejas de OpenVPMS y la antigua `frappe/erpnext`). Quedó la caché de build de BuildKit (787,6 MB), que no se borró porque es global. Clon de `https://github.com/J4F3ET/UD.RedesCorporativa.ProyectoFinal.git` en el commit `045c81d` (mismo árbol que `master` tras fusionar el PR #37), con `core.autocrlf=true`. Lanzado desde PowerShell: `levantar-sistema.ps1 -TimeoutMin 90`.

**Resultado: FALLA.** El arranque en frío no termina: `pretix-web` queda `unhealthy` para siempre y `docker compose up -d` aborta. Volver a lanzar no lo arregla. Corregido en `58f39df` y `1b01e0a`; ver la segunda pasada y "Resuelto el 27/09/2026".

| Hito | Hora | Tiempo |
|---|---|---|
| `levantar-sistema.ps1 -TimeoutMin 90`, sin `-Forzar` | 07:41:04 | Se niega a los 22 s, RC=1: "Solo hay 5.56 GB libres. Los 25 servicios consumen ~5,7 GB en el host; […] O usa -Forzar para intentarlo igualmente." (con 0 contenedores del proyecto en marcha) |
| Relanzado con `-Forzar` | 07:41:56 | 6,1 GB libres en Windows; 7,2 GiB libres en WSL |
| `preparar` (CA, certificado LDAPS, zona DNS, LDIF) | 07:42:28 → 07:42:35 | 7 s |
| Imagen de OpenVPMS | 07:42:36 → 07:42:41 | 5 s: **toda la construcción salió de la caché de build** (`#7 … openvpms.zip … CACHED`) |
| Descarga de imágenes (`up -d`) | 07:42:43 → 08:10:05 | **27 min 22 s** |
| `openvpms-db` en marcha → healthy | 08:10:38 → 08:19:25 | **527 s** (su `start_period` es 600 s) |
| `erpnext-create-site` (crea el sitio de ERPNext) | 08:17:07 → 08:42:13 | **25 min 6 s**, Exited (0) |
| OpenVPMS: esquema / datos base / Tomcat arriba | 08:20:08 → 08:26:54 / → 08:30:31 / 08:34:22 | 6 min 46 s / 3 min 37 s / 3 min 51 s; `openvpms-app` healthy |
| `inventree-app` healthy | 08:29:13 | 17 min 48 s desde su arranque (incluye `invoke static`) |
| `pretix-web` unhealthy | 08:31:11 | `start_period` 900 s + 20 reintentos |
| `up -d` aborta: "dependency failed to start: container pretix-web is unhealthy" | 08:42:33 | El lanzador muestra el diagnóstico y termina con RC=1 a las 08:42:42 (**60 min 46 s** en total). No llega a `esperar_sano`, así que `-TimeoutMin` no interviene |
| Segundo lanzamiento (reanudar), `-Forzar` | 08:44:34 → 08:45:33 | RC=1 a los 59 s con el mismo error: `up -d` no recrea `pretix-web` y lo encuentra `unhealthy` |

Estado final: 18 contenedores en marcha y sanos, `pretix-web` en marcha pero `unhealthy`, `pretix-worker`, `pretix-cron` y `erpnext-hr` en `Created` (nunca arrancaron) y los 3 trabajos de ERPNext en `Exited (0)`.

| Comprobación desde WSL | Resultado |
|---|---|
| `http://localhost:18080/openvpms/login` | 200 |
| `http://localhost:18081/login` (ERPNext) | 000: `erpnext-hr`, el nginx que publica el puerto, no llegó a arrancar |
| `http://localhost:18082/control/login` (Pretix) | 500: la base de Pretix está vacía (`relation "pretixbase_globalsettingsobject_settingsstore" does not exist`) |
| `http://localhost:18083/web/login` (InvenTree) | 200; su asset `/static/web/assets/index-C2rs8w4F.js` 200 `text/javascript` (H22 sigue resuelto en frío) |
| `verificar` | **No se ejecutó**: el sistema no llegó a estar sano |

**Disco (lo que ocupa el proyecto en Docker).** 11 imágenes con 9,73 GB en disco (descomprimidas; 825 MB son la de OpenVPMS, que se construye localmente), 790 MB de volúmenes y 555 MB de capas de contenedor. La descarga comprimida es menor y no se midió.

**Memoria.** `docker stats` de los 19 contenedores en marcha: 4.156 MiB. Durante el arranque la memoria disponible de WSL bajó a 3,37 GB y la memoria libre de Windows a 0,30 GB (`vmmemWSL` con 7,3 GB). A las 08:37, dos llamadas a `wsl.exe` fallaron con `Wsl/Service/0x8007274c` (tiempo de espera agotado).

**OpenVPMS sin caché.** Como la construcción del arranque salió entera de la caché, después se construyó aparte `docker build --no-cache servicios/openvpms` con una etiqueta desechable, borrada al terminar: RC=0 en 133 s. El `curl` del zip de OpenVPMS 2.4.0.1 se ejecutó de verdad (73,5 s, junto con el `unzip`) y el conector de MySQL también. La imagen base `tomcat:9.0-jdk11-temurin` salió de la caché también con `--no-cache`.

**Limitaciones de la prueba.** Este PC tiene un `%UserProfile%\.wslconfig` que no es el de por defecto (`memory=8GB`, `swap=4GB`, `vmIdleTimeout=2h`, el de [`operacion.md`](operacion.md#wslconfig-recomendado)). Una persona externa tendría los valores por defecto. La caché de build de BuildKit no se borró. Las cifras son de un solo intento.

## Arranque en frío con el arreglo (27/09/2026, segunda pasada)

Mismo clon, en la rama `docs/arranque-en-frio` con `58f39df` (healthchecks de las bases y `depends_on` con `service_healthy`) y `1b01e0a` (`arrancar` reinicia los contenedores `unhealthy`). Se borraron los contenedores, las redes y **todos los volúmenes** del proyecto (`borrar -Si` y los 2 anónimos que quedaban). Se **conservaron las imágenes**: la descarga ya se midió en la primera pasada (27 min 22 s). Lanzado desde PowerShell con `levantar-sistema.ps1 -Forzar -TimeoutMin 90`; hubo que usar `-Forzar` porque solo había 3,56 GB libres en Windows.

**Resultado: RC=0, 25/25 sanos (22 en marcha + 3 `Exited (0)`), sin intervención manual.**

| Hito | Hora | Tiempo |
|---|---|---|
| Lanzamiento → `up -d` | 09:11:51 → 09:13:06 | 1 min 15 s (requisitos, `preparar`, imagen de OpenVPMS desde caché) |
| `pretix-db` e `inventree-db` healthy (`pg_isready`) | 09:15:17 | 1 min 31 s tras arrancar Postgres (`initdb`) |
| `pretix-web` arranca | 09:15:23 | **después** de `pretix-db` healthy: 0 `Connection refused` en su log |
| Migraciones de Pretix | 09:18:39 → 09:31:43 | 13 min 4 s; `pretix-web` healthy a las 09:32:55 |
| `openvpms-db` en marcha → healthy | 09:13:53 → 09:21:13 | **440 s** (`start_period` 600 s) |
| OpenVPMS: esquema / datos base / Tomcat arriba | 09:21:49 → 09:28:28 / → 09:31:47 / 09:36:59 | 6 min 39 s / 3 min 19 s / 5 min 12 s |
| `inventree-app` healthy | 09:31:56 | 16 min 38 s desde su arranque |
| `erpnext-create-site` | 09:18:44 → 09:46:59 | **28 min 15 s**, Exited (0) |
| `esperar_sano` | 09:47:29 → 09:47:55 | `[00:26] sanos 25/25` |
| Administrador de Pretix y fin | 09:48:07 | **36 min 16 s en total, RC=0** |

Con la descarga de imágenes de la primera pasada, un primer arranque real desde cero ronda **1 h 4 min** en este equipo (27 min 22 s + 36 min 16 s).

| Comprobación | Resultado |
|---|---|
| `http://localhost:18080/openvpms/login` | 200 |
| `http://localhost:18081/login` (ERPNext) | 200 |
| `http://localhost:18082/control/login` (Pretix) | 200 |
| `http://localhost:18083/web/login` (InvenTree) | 200; `/static/web/assets/index-C2rs8w4F.js` 200 `text/javascript` |
| `verificar` completo | **99 PASS, 0 FAIL, 13 INFO, RC=0** en 14 min 15 s (`sistema/resultados/verificacion-20260927-094944.txt`); `ExecMainStartTimestamp` 09:12:15 antes y después |
| Disco | 12 imágenes con 10,13 GB (incluye la base de Tomcat que quedó del `--no-cache`), 819 MB de volúmenes y 552 MB de contenedores |
| Memoria | `docker stats` de los 22 en marcha: 5.200 MiB; `MemAvailable` en WSL 2,7 GB |

**Reanudar tras el fallo de la primera pasada (misma mañana, antes de esta pasada).** Con los arreglos aplicados sobre el sistema que dejó la primera pasada (`pretix-web` `unhealthy`), `arrancar` reinició `pretix-web` (`reiniciar_unhealthy`), Pretix migró su base (295 migraciones) y el lanzador terminó con RC=0 y 25/25 en 13 min 58 s. Es la prueba de que el arranque vuelve a retomarse.

## Memoria por contenedor (`docker stats`, sistema completo, 26/09/2026)

| Contenedor | MiB |
|---|---:|
| inventree-worker | 998,4 |
| openvpms-app | 829,8 |
| pretix-web | 651,5 |
| openvpms-db | 437,2 |
| pretix-worker | 431,7 |
| inventree-app | 423,9 |
| erpnext-backend | 192,3 |
| erpnext-db | 176,7 |
| erpnext-queue-long / -short / scheduler | 90,7 / 83,5 / 72,2 |
| pretix-db / inventree-db | 48,7 / 36,6 |
| resto (websocket, openldap, dns, cron, redis ×3, nginx, ntp) | 127,7 |
| **Total (22 permanentes)** | **4.600,8** |

En el host cuesta unos 5,7 GB: cada GiB de `docker stats` equivale a unos 1,23 GB libres menos en Windows. De ahí sale el umbral de 6,9 GB libres que comprueba el lanzador (`-Forzar` lo salta).

Ajustes que llevaron a esta cifra, sin quitar ninguna función:

- **Pretix:** separado en `web`, `taskworker` y `cron`, siguiendo la topología oficial de la imagen. Pasó de 3.751,9 a unos 1.083 MiB.
- **InvenTree:** gunicorn con 2 workers.
- **openvpms-db:** buffer pool de 128 MiB.
- **openvpms-app:** heap `-Xmx768m`.

## Verificación de la arquitectura (`levantar-sistema verificar`)

| Pasada | Resultado |
|---|---|
| 26/09 17:18, rápida (sin persistencia) | 192 PASS, 28 INFO. El único FAIL era el marcador deliberado "caso 4 no ejecutado", que `--rapido` deja siempre (por eso `verificar` es completo por defecto) |
| 26/09 17:22, completa, antes de H18 | 91 PASS, 1 FAIL. El FAIL fue el caso 4a: carrera de arranque del test, no pérdida de datos |
| 26/09 17:47, completa, con H18 corregido | **92 PASS, 0 FAIL, 14 INFO, RC=0** |
| 26/09 18:17, completa, tras renombrar el arnés a `sistema/` | **92 PASS, 0 FAIL, 14 INFO, RC=0** (misma configuración resuelta de compose antes y después del renombrado) |
| 26/09 21:28, rápida, con la comprobación de la zona ampliada a sus 7 nombres y **antes** de corregirla | 95 PASS, 5 FAIL, 13 INFO. Cuatro FAIL de la zona (`dns`, `ntp`, `pretix` y `rrhh` no apuntaban a su contenedor: H21) y el marcador de `--rapido`. Es la prueba de que el test detecta H21 (`sistema/resultados/verificacion-20260926-212844.txt`) |
| 26/09 21:59, completa, tras corregir la zona (H21), LDAP/DNS/NTP de las apps y las URL de Pretix e InvenTree (H20) | **99 PASS, 0 FAIL, 13 INFO, RC=0** (`sistema/resultados/verificacion-20260926-215946.txt`) |
| 26/09 22:19, completa, con el `docker-compose.yml` único en la raíz y los ficheros en `servicios/` | **99 PASS, 0 FAIL, 13 INFO, RC=0** (`sistema/resultados/verificacion-20260926-221919.txt`). Configuración resuelta de compose igual a la de la pasada anterior salvo las rutas de origen de los montajes |
| 26/09 22:46, completa, con H22 corregido | **99 PASS, 0 FAIL, 13 INFO, RC=0** (`sistema/resultados/verificacion-20260926-224652.txt`). Tras el `down`/`up` del caso 4, `/static` de InvenTree sigue respondiendo 200 |

| 27/09 07:03, completa, tras reinicializar el directorio LDAP con los LDIF generados desde `test.env` (ver "Primer arranque de LDAP") | **99 PASS, 0 FAIL, 13 INFO, RC=0** (`sistema/resultados/verificacion-20260927-070340.txt`). Login LDAP de `rrhh.prueba` en ERPNext y de `logistica.prueba` en InvenTree en PASS, también tras el `down`/`up` del caso 4 |
| 27/09 09:49, completa, tras el segundo arranque en frío con los volúmenes vacíos (Pretix corregido) | **99 PASS, 0 FAIL, 13 INFO, RC=0** (`sistema/resultados/verificacion-20260927-094944.txt`). `ExecMainStartTimestamp` 09:12:15 antes y después |

Desde el 26/09 21:59 hay 99 PASS y no 92: la comprobación "los nombres dns/ntp/ldap apuntan al contenedor que los sirve", que era 1 INFO, pasó a ser una comprobación por cada uno de los 7 nombres de la zona (7 PASS). De ahí también 13 INFO en vez de 14.

En todas las pasadas válidas, `ExecMainStartTimestamp` de `docker.service` es el mismo antes y después: el demonio no se reinició durante la prueba.

Qué cubre cada bloque (detalle en [`../sistema/verificar_arquitectura.md`](../sistema/verificar_arquitectura.md)):

- **Prerrequisitos:** las 4 apps en su VLAN y en la 99, y OpenLDAP, DNS y NTP en la 99, cada uno con la IP fija de [`arquitectura.md`](arquitectura.md#4-servicios).
- **Segmentación:** controles positivos, negativos entre departamentos, y alcance de LDAP solo desde las apps dual-homed.
  - **12 de los 13 INFO** son el tráfico de una app a otra por la VLAN 99. Es un hallazgo previsto: la VLAN 99 es un único dominio L2.
- **DNS:** registros autoritativos, NXDOMAIN, `REFUSED` para nombres externos, y solo responde a las apps dual-homed. Cada uno de los 7 nombres de la zona apunta al contenedor que da ese servicio (`rrhh` → `erpnext-hr`, el nginx de ERPNext).
- **NTP:** stratum 10 (fuente local, H11), SNTP válido, un cliente `chronyd -Q` real acepta la fuente, y aislamiento por VLAN. El INFO restante es `chronyc sources`, que se muestra como contexto.
- **LDAP/LDAPS:**
  - Login LDAP de `rrhh.prueba` en ERPNext (200) y de `logistica.prueba` en InvenTree (200 con token).
  - Clave errónea: 417 en ERPNext y 401 en InvenTree.
  - `ldapsearch` por LDAPS con la CA interna rc=0; con clave errónea rc=49; con una CA ajena rc≠0 ("untrusted").
  - Caso 4: `down` sin `-v` + `up -d`, y todo lo anterior se repite en PASS.

## Primer arranque de LDAP (27/09/2026)

Prueba de que el directorio nace bien solo con `sistema/test.env`, sin claves en ningún otro fichero:

| Paso | Resultado |
|---|---|
| `levantar-sistema.ps1 preparar` | RC=0. `servicios/openldap/generado/` con 3 LDIF; 5 `userPassword: {SSHA}` (sal de 8 bytes), 0 claves en claro; cada hash comprobado contra su variable de `test.env` |
| `docker compose config` antes y después del cambio | Solo cambia el origen del montaje del bootstrap de `openldap` (`servicios/openldap` → `servicios/openldap/generado`); los valores resueltos de las claves de InvenTree y ERPNext son idénticos |
| Borrado | `stop` + `rm -f` de `openldap` y `docker volume rm reservaviva-smoke_ldap_data reservaviva-smoke_ldap_config`. Ningún otro volumen |
| `levantar-sistema.ps1 arrancar` | RC=0, 25/25 sanos (22 en marcha + 3 `Exited (0)`) en 25 s de espera. El log de `openldap` muestra `Add custom bootstrap ldif...` y el contenedor ve los 3 `.ldif` en la carpeta de bootstrap |
| `ldapsearch` por LDAPS como `svc-lectura` (clave leída de `test.env` por un fichero temporal, no en la línea de comandos) | rc=0 y los 4 usuarios de prueba; con una clave errónea, rc=49 |
| `verificar` completo | 99 PASS, 0 FAIL, 13 INFO, RC=0 (tabla anterior). No hizo falta tocar ERPNext ni InvenTree: sus usuarios LDAP ya existentes tienen el mismo DN |
| `ExecMainStartTimestamp` de `docker.service` | Sat 2026-09-26 21:13:43 -05 antes y después |

## Acceso por nombre y modo intranet (27/09/2026)

Cambio: dominio `reservaviva.lan`, servicio 26 `proxy-web` (nginx, solo en `vlan99_infra`), `erpnext-hr` con pata en la
VLAN 99, DNS con vista interna y vista lan, y modo intranet opcional del lanzador. Detalle en
[`arquitectura.md`](arquitectura.md#acceso-por-nombre-el-proxy-web) y [`operacion.md`](operacion.md#acceso-desde-la-lan).

| Paso | Resultado |
|---|---|
| `preparar` con el certificado antiguo (SAN `ldap.reservaviva.local`) | Regenera solo `ldap.crt`/`ldap.key` con SAN `ldap.reservaviva.lan`, con la misma CA; caduca el 30/12/2028 |
| Primer `arrancar` con el cambio (modo local) | RC=0, **26/26** sanos en **403 s** (6 min 43 s). Solo se recrean `pretix-web`, `-worker`, `-cron`, `inventree-app`, `-worker`, `erpnext-backend`, `erpnext-hr` y `erpnext-ldap-config`, y se crea `proxy-web`; `dns-interno` se reinicia porque `named.conf` es más nuevo |
| Login LDAPS tras regenerar el certificado | **Falló** (ERPNext 417 por SSL, InvenTree 401): `openldap` reiniciado seguía sirviendo el certificado viejo. Arreglo: el lanzador **recrea** `openldap` si `ldap.crt` es más nuevo que el contenedor ([`seguridad.md`](seguridad.md#cuándo-se-regenera-y-cuándo-no)) |
| InvenTree tras recrear `openldap` | Sus workers de gunicorn siguieron dando 401 (sin error en el log) mientras un proceso nuevo en el mismo contenedor autenticaba; al reiniciar `inventree-app`, `ldaplogin.py` dio PASS. El lanzador reinicia ahora los clientes LDAPS |
| `touch ldap.crt` + `arrancar` (prueba de ese camino) | RC=0, 26/26 en 211 s: `openldap` recreado y clientes reiniciados. **Efecto no previsto:** `erpnext-backend` volvió con otra IP en `erpnext_internal` (10.201.0.10 → .9) y el nginx de `erpnext-hr` siguió llamando a la vieja: `rrhh` dio 502 (lo detectó `verificar`, ver abajo). Arreglo: se reinicia también `erpnext-hr` |
| Sondas del proxy (127.0.0.1:80, cabecera `Host`) | `openvpms` `/` → 302 a `/openvpms/`; `/openvpms/login` 200 y `bootstrap.min.css` 200 `text/css`. `pretix` `/control/login` 200 y su CSS 200 `text/css`. `inventree` `/web/` 200 y `index-*.js` 200 `text/javascript`. `rrhh` `/login` 200 y `website.bundle.*.css` 200 `text/css`. WebSocket de socket.io por `rrhh` → 101. Nombre desconocido y la IP a secas → 404 del proxy |
| Acceso directo `localhost:18080-18083` | Mismo HTML y estáticos 200: los `SITE_URL` por nombre no rompen el acceso de administración |
| CSRF | Un POST de login con credenciales inventadas, por el nombre y por `localhost`, se rechaza por credenciales (Pretix 200 con error, InvenTree 400 `username_password_mismatch`), no por CSRF |
| DNS, vista lan (desde el anfitrión, 127.0.0.1:1053/tcp) | `openvpms`, `pretix`, `inventree`, `rrhh`, `dns` → 127.0.0.1; `ldap`, `ntp` → NXDOMAIN; `example.com` → REFUSED. La vista interna sigue dando la IP del contenedor (`pretix` 10.10.20.10, `rrhh` 10.10.40.10) |
| `-Intranet` con WSL en NAT (IP detectada 192.168.1.13, Wi-Fi) | El `.ps1` avisa de `networkingMode = nat` y de quién tiene el 53/udp en Windows (`portmaster-core` y `svchost`/`SharedAccess`). El `.sh` se niega antes de tocar nada: "WSL esta en modo de red 'nat', no 'mirrored' … Nada se ha cambiado". RC=1 |
| Copia temporal del lanzador sin la comprobación de mirrored, con la IP de WSL (172.19.125.136) | Puerto ocupado: la comprobación previa lo detecta. Sin ella, compose falla con "address already in use", el lanzador lo explica y vuelve al modo local (así se encontró que la vuelta conservaba un `HTTP_PORT` del usuario; corregido). Modo intranet completo: RC=0 en 96 s, solo se recrean `proxy-web` y `dns-interno`; `verificar --rapido` con el bloque 4 en PASS contra esa IP |
| Desde Windows contra 172.19.125.136 | Proxy correcto (openvpms 302, pretix 200, inventree 302, rrhh 200, CSS 200). DNS: NXDOMAIN con recursión activa y `example.com` resuelto, respuestas que nuestro bind9 no da: Portmaster intercepta el DNS saliente del anfitrión. Desde WSL, correcto |
| Vuelta al modo local (`-Forzar` sin `-Intranet`) | RC=0 en 79 s; solo se recrean `proxy-web` y `dns-interno`, de nuevo en 127.0.0.1 |

`verificar` con el bloque 4 (acceso por nombre):

| Pasada | Resultado |
|---|---|
| 27/09 13:47, rápida, modo local | 131 PASS, 2 FAIL, 14 INFO (`verificacion-20260927-134740.txt`). Bloque 4 entero en PASS. FAIL: `ldaplogin` (el certificado viejo aún cargado en `openldap`) y el marcador de `--rapido` |
| 27/09 14:08, rápida, modo intranet con la IP de WSL | Bloque 4 entero en PASS contra 172.19.125.136 (`verificacion-20260927-140844.txt`). FAIL: login LDAP de InvenTree (sus workers, antes de reiniciarlos) y el marcador de `--rapido` |
| 27/09 14:38, completa, modo local | 128 PASS, **2 FAIL**, 14 INFO, RC=1 (`verificacion-20260927-143812.txt`). Los dos FAIL: `rrhh` `/login` 502 por el proxy y por `localhost:18081`. Causa: el efecto de la fila "`touch ldap.crt` + `arrancar`" de arriba (nginx de `erpnext-hr` con la IP vieja del backend). Tras el `down`/`up` del caso 4, `rrhh` volvió a dar 200. Es la sonda nueva de interfaz web detectando un fallo real |
| 27/09 14:59, completa, modo local, tras `touch ldap.crt` + `arrancar` con el arreglo (RC=0, 26/26 en 258 s; `openldap` recreado y `inventree-app`, `erpnext-backend` y `erpnext-hr` reiniciados) | **132 PASS, 0 FAIL, 14 INFO, RC=0** (`sistema/resultados/verificacion-20260927-145944.txt`), 820 s. `ExecMainStartTimestamp` 12:29:58 antes y después |

De 99 a 132 PASS: el bloque 4 añade 33 comprobaciones (proxy solo en `vlan99_infra`, vista lan, proxy y acceso directo con HTML y estático, WebSocket, 404). El INFO nuevo, 14 en vez de 13, es el modo de publicación detectado ("local: proxy en 127.0.0.1:80, DNS en 127.0.0.1:1053").

## Pendientes

| ID | Qué | Tipo |
|---|---|---|
| H12 | La cita de OpenLDAP 2.6 en la bibliografía de la Entrega 1 está pendiente de corregir (opción conservadora: corregir la cita, no cambiar la imagen) | documentación |
| — | En un arranque en frío casi toda la espera ocurre dentro de `docker compose up -d`, que respeta los `depends_on: service_healthy` (35 min en la segunda pasada). Por eso no aparece el progreso `[mm:ss] sanos N/25`, `-TimeoutMin` no interviene, y un fallo de salud se ve como "docker compose up fallo". Documentado en [`operacion.md`](operacion.md#3-qué-pasa-en-un-arranque); falta decidir si el lanzador debe mostrar progreso durante esa espera | robustez |
| — | La comprobación de memoria del `.ps1` se negó en este PC con 0 contenedores del proyecto (5,56 GB libres, umbral 6,9 GB). Con `-Forzar`, Windows bajó a 0,30 GB libres y `wsl.exe` agotó el tiempo de espera (`Wsl/Service/0x8007274c`) | validación |
| — | Los volúmenes anónimos del proyecto no llevan la etiqueta `com.docker.compose.project`, solo `com.docker.volume.anonymous`, así que no se pueden filtrar por proyecto (el 27/09 se borraron 92, identificados por fecha y contenido) | mantenimiento |
| — | `docker build --no-cache` de OpenVPMS reutiliza la imagen base `tomcat` de la caché de BuildKit. La descarga de la imagen base no se ha comprobado desde cero | validación |
| — | `erpnext-create-site` recibe contraseñas por la línea de comandos | seguridad (laboratorio) |
| — | `inventree-worker` y `pretix-cron` han terminado con código 137 (SIGKILL); causa sin analizar | robustez |
| — | Ningún servicio tiene `mem_limit` | robustez |
| — | `openvpms-db` corre con `performance_schema=1`: es instrumentación y el ahorro al apagarlo no está medido | memoria |
| — | Modo Docker Desktop + Git Bash del lanzador de Windows sin probar (solo se ha probado Docker Engine en WSL) | validación |
| — | Los simuladores de `diseno-red/` no se han vuelto a ejecutar tras moverlos (necesitan `nicolaka/netshoot`) | validación |
| — | Diseño con switch L2/L3 sin probar contra hardware real | limitación conocida |
| — | Rotar las contraseñas de laboratorio de `sistema/test.env` si el repositorio se hace público | seguridad |
| — | InvenTree no sirve `/media` sin `DEBUG`: las imágenes de artículos y los adjuntos que se suban no se verán. Hoy solo existe `media/report`, así que no se pierde nada. Ya existe un proxy (`proxy-web`), pero no sirve `/media`: haría falta montarle el volumen `inventree_data` en solo lectura y una `location /media/`, además de decidir si esos ficheros pueden verse sin autenticación | decisión del usuario |
| — | Modo intranet sin probar de extremo a extremo: no se ha ejecutado `sistema/habilitar-intranet-windows.ps1`, WSL no ha estado en `mirrored` y ningún otro equipo de la LAN ha resuelto ni abierto los nombres. Pasos en [`operacion.md`](operacion.md#acceso-desde-la-lan) | validación |
| — | En este PC, el 53/udp de Windows lo ocupan ICS (`SharedAccess`) y Portmaster, y Portmaster intercepta las consultas DNS salientes del anfitrión. Con WSL en mirrored, Docker no podrá publicar el DNS en el 53 hasta que el usuario libere ese puerto (el script de Windows informa, no toca nada) | decisión del usuario |
| — | `arrancar` lanzado desde Git Bash devolvió RC=2 aunque el log decía "los 25 servicios estan sanos"; el siguiente, desde PowerShell, dio RC=0. Causa sin identificar (el envoltorio o el script) | robustez |
| — | Ninguna aplicación es cliente de `ntp-interno`: solo lo consulta `verificar` (ver [`arquitectura.md`](arquitectura.md#ntp)). Falta decidir si se documenta como limitación o se configura un cliente en las apps | decisión del usuario |
| — | Los volúmenes anónimos del proyecto se acumulan con las recreaciones y los `down`/`up` de `verificar` (74 el 26/09; 101 el 27/09, borrados en la prueba en frío) | mantenimiento |
| — | `docker.service` se reinició entre dos sesiones de trabajo del 26/09 (`ExecMainStartTimestamp` pasó de 17:01:17 a 21:13:43), fuera de cualquier prueba y por causa desconocida | robustez |
| — | El login real en un navegador con las claves de laboratorio no lo ha hecho ningún agente (la clave no se puede leer desde la sesión): administrador de Pretix `admin@reservaviva.local`, botón "Login with LDAP" de ERPNext y `taquilla.prueba` en InvenTree, tanto por su nombre `.lan` como por `localhost:<puerto>`. Lo comprueba el usuario | validación |
Resuelto el 27/09/2026:

- **`verificar` no comprobaba la interfaz web** (el hueco por el que H22 pasó 7 pasadas en verde). El bloque 4 pide, por el proxy y por `localhost:<puerto>`, la página de login de cada aplicación y el primer CSS o JS que referencia, y exige 200 con un `Content-Type` que no sea HTML (ver "Acceso por nombre").
- **Acceso por nombre desde la LAN:** proxy web, vistas del DNS y modo intranet del lanzador (sección "Acceso por nombre y modo intranet").

- **H17:** en el arranque en frío desde un clon limpio, `openvpms-db` quedó healthy **527 s** después de arrancar en la primera pasada y **440 s** en la segunda, dentro de su `start_period` de 600 s. Después OpenVPMS creó su esquema y `openvpms-app` quedó healthy.
- **Pretix no arrancaba en frío** (`58f39df`). `pretix-web` dependía de `pretix-db` sin `condition`, y `pretix-db` no tenía healthcheck. En el primer arranque, Postgres ejecuta `initdb` y se reinicia, y `pretix-web` lanzaba su `migrate` antes de que aceptara conexiones ("Connection refused"). El script de la imagen no se detiene: arrancaba la web contra una base vacía (`relation "pretixbase_globalsettingsobject_settingsstore" does not exist`), la web quedaba `unhealthy` para siempre y `up -d` abortaba a los 60 min. Arreglo: healthcheck `pg_isready -h 127.0.0.1` en `pretix-db` e `inventree-db` (con `-h`, el servidor temporal de `initdb`, que solo escucha en el socket local, no cuenta como listo), `redis-cli ping` en los tres redis, y `condition: service_healthy` en `pretix-web`, `inventree-app` y `erpnext-create-site`. En `docker compose config` solo cambian los healthchecks y las condiciones.
- **El arranque no se podía reanudar tras ese fallo** (`1b01e0a`). `up -d` no recrea un contenedor cuya configuración no cambió, así que cada relanzamiento abortaba en segundos. Ahora `arrancar` reinicia antes los contenedores `unhealthy`. Probado sobre el sistema fallido: RC=0 y 25/25.
- **Tiempos documentados:** el script y [`operacion.md`](operacion.md) decían ~15 min para el sitio de ERPNext y "un cuarto de hora" para el primer arranque. Ahora dicen ~25-30 min y "más de media hora con las imágenes descargadas, más la descarga", como se midió (28 min 15 s y 36 min 16 s).

Resuelto el 26/09/2026:

- **H18:** carrera de arranque en el caso 4 de `ldaplogin.py`.
- **H19:** el arranque de un host no creaba el administrador de Pretix y dejaba `admin@localhost` con la clave `admin`. Ahora lo hace `levantar-sistema.sh`.
- **H20** (`41d54ef`): Pretix e InvenTree tenían como URL propia `http://10.10.30.10:<puerto>`, que es la IP de `inventree-app` en la VLAN 30 (resto del diseño de 3 equipos). Efecto medido antes del arreglo: la interfaz web de InvenTree (`http://localhost:18083/web`) respondía 500 ("INVE-E7: the visited path does not match the SITE_URL"). Pretix servía el login solo porque admite `localhost` como excepción. Ahora ambas usan `http://localhost:<puerto>`. Comprobado desde el host: `/web` de InvenTree 200; `/control/login` de Pretix 200 con token CSRF; un POST de login con credenciales inventadas se rechaza por credenciales, no por CSRF. El login real en un navegador no se ha probado en esta pasada.
- **H21** (`4b7aadb`; la comprobación que lo detecta, `de18b7a`): la zona DNS ponía `dns`, `ntp` y `rrhh` en la IP de `openldap` y `pretix` en la de `inventree-app`. Ahora cada nombre apunta al contenedor que da ese servicio, y `verificar` lo comprueba nombre por nombre.
- **H22** (`afabb20`): la interfaz web de InvenTree (`/web`) no cargaba ("INVE-E1"). Causa: whitenoise sirve `/static` desde `STATIC_ROOT` (`/home/inventree/data/static`, en el volumen `inventree_data`) y solo lo indexa al arrancar, pero ese directorio estaba vacío porque `INVENTREE_AUTO_UPDATE` solo migra y nunca se ejecutó `invoke static`; `/static/web/assets/*.js` respondía 302 hacia `/web`. Arreglo: el `command` de `inventree-app` ejecuta `invoke static` y después, con `exec`, el mismo CMD de la imagen (gunicorn). Comprobado desde el host: `/static/web/assets/index-C2rs8w4F.js` 200 `text/javascript`, `/static/img/favicon/favicon-32x32.png` 200, `STATIC_ROOT` con 71 MB; un segundo `arrancar` RC=0 sin recrear el contenedor, y la pasada completa de `verificar` del 26/09 22:46 en verde (también tras su `down`/`up`).
