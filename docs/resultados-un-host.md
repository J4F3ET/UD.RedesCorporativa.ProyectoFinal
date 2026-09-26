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
| 26/09 17:18, rápida (sin persistencia) | 192 PASS, 28 INFO. El único FAIL era el marcador deliberado "caso 4 no ejecutado", que ya no existe: `verificar` es completo por defecto |
| 26/09 17:22, completa, antes de H18 | 91 PASS, 1 FAIL. El FAIL fue el caso 4a: carrera de arranque del test, no pérdida de datos |
| 26/09 17:47, completa, con H18 corregido | **92 PASS, 0 FAIL, 14 INFO, RC=0** |
| 26/09 18:17, completa, tras renombrar el arnés a `sistema/` | **92 PASS, 0 FAIL, 14 INFO, RC=0** (misma configuración resuelta de compose antes y después del renombrado) |

En todas las pasadas válidas, `ExecMainStartTimestamp` de `docker.service` es el mismo antes y después: el demonio no se reinició durante la prueba.

Qué cubre cada bloque (detalle en [`../sistema/verificar_arquitectura.md`](../sistema/verificar_arquitectura.md)):

- **Prerrequisitos:** las 4 apps en su VLAN y en la 99. OpenVPMS 10.10.10.10/.99.24, Pretix .20.10/.99.21, InvenTree .30.10/.99.22, ERPNext .40.11/.99.23. OpenLDAP .99.10, DNS .99.11, NTP .99.12.
- **Segmentación:** controles positivos, negativos entre departamentos, y alcance de LDAP solo desde las apps dual-homed.
  - Los **12 INFO** de la pasada rápida son el tráfico de una app a otra por la VLAN 99. Es un hallazgo previsto: la VLAN 99 es un único dominio L2.
- **DNS:** registros autoritativos, NXDOMAIN, `REFUSED` para nombres externos, y solo responde a las apps dual-homed.
- **NTP:** stratum 10 (fuente local, H11), SNTP válido, un cliente `chronyd -Q` real acepta la fuente, y aislamiento por VLAN.
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

Resuelto el 26/09/2026:

- **H18:** carrera de arranque en el caso 4 de `ldaplogin.py`.
- **H19:** el arranque de un host no creaba el administrador de Pretix y dejaba `admin@localhost` con la clave `admin`. Ahora lo hace `levantar-sistema.sh`.
