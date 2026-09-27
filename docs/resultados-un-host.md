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

Condición: imágenes ya descargadas y volúmenes de ERPNext existentes (el sitio se adoptó como completo; ver H16). **No se ha repetido un arranque en frío con volúmenes vacíos** (ver Pendientes, H17).

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

## Pendientes

| ID | Qué | Tipo |
|---|---|---|
| H12 | La cita de OpenLDAP 2.6 en la bibliografía de la Entrega 1 está pendiente de corregir (opción conservadora: corregir la cita, no cambiar la imagen) | documentación |
| H17 | `openvpms-db` tiene `start_period` 600 s (se midieron 484 s en frío), pero **el arranque en frío con volúmenes vacíos no se ha repetido** desde el arreglo | validación |
| — | `erpnext-create-site` recibe contraseñas por la línea de comandos | seguridad (laboratorio) |
| — | `inventree-worker` y `pretix-cron` han terminado con código 137 (SIGKILL); causa sin analizar | robustez |
| — | Ningún servicio tiene `mem_limit` | robustez |
| — | `openvpms-db` corre con `performance_schema=1`: es instrumentación y el ahorro al apagarlo no está medido | memoria |
| — | Modo Docker Desktop + Git Bash del lanzador de Windows sin probar (solo se ha probado Docker Engine en WSL) | validación |
| — | Los simuladores de `diseno-red/` no se han vuelto a ejecutar tras moverlos (necesitan `nicolaka/netshoot`) | validación |
| — | Diseño con switch L2/L3 sin probar contra hardware real | limitación conocida |
| — | Rotar las contraseñas de laboratorio de `sistema/test.env` si el repositorio se hace público | seguridad |
| — | InvenTree no sirve `/media` sin `DEBUG`: las imágenes de artículos y los adjuntos que se suban no se verán. Hoy solo existe `media/report`, así que no se pierde nada. Arreglarlo exige un proxy (contenedor nuevo y descarga de su imagen), que seguiría necesitando el arreglo de H22 | decisión del usuario |
| — | Los `ports:` del compose publican por defecto en `0.0.0.0` (`${PUBLISH_IP:-0.0.0.0}`, `${DNS_BIND_IP:-0.0.0.0}`); `test.env` fija `127.0.0.1`. Propuesta: que el valor por defecto sea `127.0.0.1`, más seguro si falta `test.env` | decisión del usuario |
| — | El comentario de `servicios/openldap/10-estructura.ldif` contiene la clave de laboratorio de `svc-lectura`. Recomendación: dejarla, porque ya está en `test.env` y en el README de `servicios/openldap/`; quitarla no afecta a un sistema ya inicializado (el LDIF solo se carga con `ldap_data` vacío) | decisión del usuario |
| — | `verificar` no comprueba la interfaz web de las aplicaciones: H22 pasó 7 pasadas en verde porque solo se probaban API y LDAP. Falta una sonda que pida un asset referenciado por el HTML de cada app y exija un `content-type` que no sea HTML | validación |
| — | `arrancar` lanzado desde Git Bash devolvió RC=2 aunque el log decía "los 25 servicios estan sanos"; el siguiente, desde PowerShell, dio RC=0. Causa sin identificar (el envoltorio o el script) | robustez |
| — | Ninguna aplicación es cliente de `ntp-interno`: solo lo consulta `verificar` (ver [`arquitectura.md`](arquitectura.md#ntp)). Falta decidir si se documenta como limitación o se configura un cliente en las apps | decisión del usuario |
| — | Los volúmenes anónimos del proyecto se acumulan con las recreaciones y los `down`/`up` de `verificar` (74 el 26/09) y no se han limpiado | mantenimiento |
| — | `docker.service` se reinició entre dos sesiones de trabajo del 26/09 (`ExecMainStartTimestamp` pasó de 17:01:17 a 21:13:43), fuera de cualquier prueba y por causa desconocida | robustez |
| — | El login real en un navegador con las claves de laboratorio no lo ha hecho ningún agente (la clave no se puede leer desde la sesión): administrador de Pretix `admin@reservaviva.local`, botón "Login with LDAP" de ERPNext y `taquilla.prueba` en InvenTree. Lo comprueba el usuario | validación |

Resuelto el 26/09/2026:

- **H18:** carrera de arranque en el caso 4 de `ldaplogin.py`.
- **H19:** el arranque de un host no creaba el administrador de Pretix y dejaba `admin@localhost` con la clave `admin`. Ahora lo hace `levantar-sistema.sh`.
- **H20** (`41d54ef`): Pretix e InvenTree tenían como URL propia `http://10.10.30.10:<puerto>`, que es la IP de `inventree-app` en la VLAN 30 (resto del diseño de 3 equipos). Efecto medido antes del arreglo: la interfaz web de InvenTree (`http://localhost:18083/web`) respondía 500 ("INVE-E7: the visited path does not match the SITE_URL"). Pretix servía el login solo porque admite `localhost` como excepción. Ahora ambas usan `http://localhost:<puerto>`. Comprobado desde el host: `/web` de InvenTree 200; `/control/login` de Pretix 200 con token CSRF; un POST de login con credenciales inventadas se rechaza por credenciales, no por CSRF. El login real en un navegador no se ha probado en esta pasada.
- **H21** (`4b7aadb`; la comprobación que lo detecta, `de18b7a`): la zona DNS ponía `dns`, `ntp` y `rrhh` en la IP de `openldap` y `pretix` en la de `inventree-app`. Ahora cada nombre apunta al contenedor que da ese servicio, y `verificar` lo comprueba nombre por nombre.
- **H22** (`afabb20`): la interfaz web de InvenTree (`/web`) no cargaba ("INVE-E1"). Causa: whitenoise sirve `/static` desde `STATIC_ROOT` (`/home/inventree/data/static`, en el volumen `inventree_data`) y solo lo indexa al arrancar, pero ese directorio estaba vacío porque `INVENTREE_AUTO_UPDATE` solo migra y nunca se ejecutó `invoke static`; `/static/web/assets/*.js` respondía 302 hacia `/web`. Arreglo: el `command` de `inventree-app` ejecuta `invoke static` y después, con `exec`, el mismo CMD de la imagen (gunicorn). Comprobado desde el host: `/static/web/assets/index-C2rs8w4F.js` 200 `text/javascript`, `/static/img/favicon/favicon-32x32.png` 200, `STATIC_ROOT` con 71 MB; un segundo `arrancar` RC=0 sin recrear el contenedor, y la pasada completa de `verificar` del 26/09 22:46 en verde (también tras su `down`/`up`).
