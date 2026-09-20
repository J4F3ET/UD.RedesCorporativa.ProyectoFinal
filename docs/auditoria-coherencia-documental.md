# Auditoría de coherencia documental frente al código

**Fecha:** 2026-09-20 · **Base auditada:** `origin/master` @ `9f58922` (leído con `git show origin/master:…` y `git ls-tree`, no la copia local) · **Autor:** sesión «daniel» · **Solo lectura:** este informe es el único fichero tocado; no se corrigió nada.

**Fuentes de verdad usadas:** `docker/pc1-medica/docker-compose.yml`, `docker/pc2-operaciones/docker-compose.yml`, `docker/pc3-administracion-infra/docker-compose.yml`, `despliegue/comun/lib-topologia.sh` (`rv_gw`, `RV_VLANS`), `despliegue/l2-fallback/scripts/firewall-pc3-matriz.sh`, `despliegue/*/scripts/setup-vlans-pc*.sh`, `despliegue/*/switch/config-switch-*.txt`, `scripts/*.sh`.

## Resumen

- **5 hallazgos bloqueantes** (B1–B5) y **16 menores** (M1–M16).
- **Enlaces Markdown `[..](..)`:** ninguno roto en master. Los enlaces rotos que quedan son referencias en backticks (M3, M11).
- **Direcciones IP, VLAN y puertos:** todas las IP y puertos citados en tutoriales, recetas y `docs/` coinciden con los compose (ver «Lo comprobado sin discrepancias»). Las únicas desviaciones son M7 y M14.
- **Matriz:** confirmado que el firewall real es `policy accept` + 12 reglas `drop` con contador. **"policy drop" aparece en los diagramas L2** (B1), y en los simuladores, donde sí es cierto (M10).
- **Dato que corrige el encargo:** ERPNext no es hoy un stack de 10 servicios sino de **12** en el compose (ver M1). Ningún documento coincide con esa cifra.

## Hallazgos ordenados por gravedad

### Bloqueantes para la entrega

| # | Fichero:línea | Qué dice | Qué dice la realidad | Evidencia (fichero:línea) | Gravedad |
|---|---|---|---|---|---|
| B1 | `despliegue/l2-fallback/diagramas/flujo-l2.dataflow.json:40,168,279`; `…/topologia-l2.architecture.json:447`; los HTML generados `flujo-l2.html:5088,5299,5300,5309,5592` y `topologia-l2.html:5643` | PC-3 aplica «nftables (**policy drop**)»; el nodo de PC-3 lleva la etiqueta «policy drop»; «el forward de PC-3 cae en policy drop». | La cadena es `policy accept` con 12 `drop` explícitos con contador (una por pareja de VLAN de negocio, en los dos sentidos). Con `policy accept`, una interfaz `gwNN` mal casada deja pasar tráfico prohibido **sin avisar**: por eso importa. | `despliegue/l2-fallback/scripts/firewall-pc3-matriz.sh:5-7` (cabecera) y `:65` (`policy accept;`); bucle de 4×3 = 12 reglas en `:67-72`. | **Bloqueante** en master; **ya corregido en el PR #15** (rama docs/diagramas-perfiles-correcciones, sin fusionar): se cierra al fusionarlo. No corregirlo dos veces. |
| B2 | `despliegue/l2-fallback/README.md:228`; `despliegue/l3-switch/README.md:223`; `tutoriales/tutorial-pc3-administracion-infraestructura.md:116-118` | En PC-3 «todo `Up`, salvo `erpnext-configurator` y `erpnext-create-site`, que deben decir `Exited (0)`». El tutorial añade: si alguna dice `Exited`, ir a «Si algo sale mal» y avisar al equipo técnico. | Hay **tres** jobs de una sola ejecución con `restart: "no"`: `erpnext-configurator`, `erpnext-create-site` y **`erpnext-ldap-config`**. Este último terminará en `Exited (0)` y quien siga la receta lo verá como fallo. También `docs/prueba-smoke-test-resultados.md:59` y `:130` hablan de «2 que terminan por diseño». | `docker/pc3-administracion-infra/docker-compose.yml:85` (configurator), `:107` (create-site), `:139-142` (ldap-config, `restart: "no"`). | **Bloqueante** (falsa alarma a un operador no técnico en el paso de verificación de PC-3) |
| B3 | `despliegue/README.md:81-82`; `despliegue/l2-fallback/README.md:15-18`; `despliegue/l3-switch/README.md:15-16`; `tutoriales/tutorial-pc1-medica.md:94-96` | Las imágenes se guardan **por etiqueta, nunca por digest** («si no, Docker intenta descargarla») y la de OpenVPMS «llega ya construida». `deploy.sh` «no descarga ni construye nada». | Los compose referencian **todas** las imágenes como `nombre:etiqueta@sha256:…`: una imagen cargada con `docker load` por etiqueta puede no satisfacer esa referencia y Docker intentaría descargarla (**no verificado: Docker está caído**). Además `openvpms-app` no tiene `image:`, solo `build: ./openvpms`; `docker compose up -d` lo construye si no encuentra la imagen del proyecto, y el Dockerfile hace `apt-get` y `curl`. Sin Internet, ambos casos fallan en el laboratorio. | `docker/pc1-medica/docker-compose.yml:23` (digest), `:37` (`build:` sin `image:`); `docker/pc2-operaciones/docker-compose.yml:32,46,56,87,101,153`; `docker/pc3-administracion-infra/docker-compose.yml:46,66,73,83,291,323,334`; `docker/pc1-medica/openvpms/Dockerfile:14-18,26`; `docker/pc1-medica/deploy.sh:36` (`docker compose up -d` sin `--no-build`). | **Bloqueante, a verificar** con Docker en marcha: probar `docker load` + `docker compose up -d --pull never` con la red cortada |
| B4 | `despliegue/README.md:79,84`; `despliegue/l2-fallback/README.md:13-20,121,340`; `despliegue/l3-switch/README.md:11-18,127,315`; `tutoriales/tutorial-pc1-medica.md:29,43`; `tutoriales/tutorial-pc2-operaciones.md:29,43`; `tutoriales/tutorial-pc3-administracion-infraestructura.md:30,44`; `tutoriales/README.md:17` | «**HUECO: comandos de la Fase 0 pendientes**», «pendiente: saber cuál es [la versión de Ubuntu]», «cómo llega esa imagen ya compilada a PC-1 lo define el paquete offline (pendiente)». | Master no contiene ningún comando de la Fase 0. Sin ellos ninguna receta ni tutorial es ejecutable de principio a fin (ya lo dicen: «sin la preparación previa no arranca nada»). Es un hueco declarado, no una contradicción oculta. | `git ls-tree -r origin/master` no lista ningún script ni documento de paquete offline. (Existe `docs/paquete-offline-fase0.md` en la rama local `test/ldaplogin-revalidacion`, **no en master**; no auditado.) | **Bloqueante** (conocido; depende de la sesión que construye la Fase 0) |
| B5 | `despliegue/l3-switch/README.md:57`; `docs/arquitectura-3-equipos-departamentos.md:52-56` (celdas «Permitido (auth/DNS/NTP)» y «VLAN99 ✅ (responde)»); `despliegue/README.md:69` (resumen de la matriz) | «VLAN 99 **solo responde**»; negocio → VLAN 99 «permitido (auth/DNS/NTP)». | Ni el switch ni el firewall filtran por sentido ni por servicio. ACL L3: los `deny` solo cubren negocio↔negocio, seguidos de `permit ip any any`, y la SVI de la VLAN 99 **no lleva ACL**, así que VLAN 99 puede *iniciar* conexiones hacia cualquier VLAN y negocio→99 admite cualquier puerto. L2: la tabla `nft` no toca los pares con la VLAN 99. La matriz implementada es «negocio↔negocio bloqueado; todo lo demás abierto». Si se defiende «solo responde» en la sustentación, el propio `config-switch-l3.txt` lo contradice. | `despliegue/l3-switch/switch/config-switch-l3.txt:37-40` (comentarios), `:45` (primer `permit ip any any`), `:84-88` (`interface Vlan99` sin `ip access-group`); `despliegue/l2-fallback/scripts/firewall-pc3-matriz.sh:7`; `despliegue/l3-switch/switch/verificacion.md:43`. | **Bloqueante** (afirmación de seguridad que el código no cumple; basta ajustar el texto o endurecer la regla) |

### Menores

| # | Fichero:línea | Qué dice | Qué dice la realidad | Evidencia (fichero:línea) | Gravedad |
|---|---|---|---|---|---|
| M1 | `docs/arquitectura-3-equipos-departamentos.md:96` (9 servicios, con `frontend`); `diagramas/README.md:20-22` (11 servicios, «dos jobs»); `diagramas/topologia-red.architecture.json:63,338` y `topologia-red.html:5088,5319-5329` (10 en total / «9, bridge privado»); `pruebas/software-un-host/README.md:17` (11) | Cuatro cifras distintas para «el stack de ERPNext» (9, 10, 11 y 12 según el documento). | Son **12** servicios: `erpnext-db`, `-redis-cache`, `-redis-queue`, `-configurator`, `-create-site`, `-ldap-config`, `-backend`, `-websocket`, `-scheduler`, `-queue-short`, `-queue-long` y `-hr` (nginx, el «frontend»). 10 van en el bridge privado y solo `-hr` y `-backend` salen a VLAN 40. Los diagramas L3 (`topologia-l3.architecture.json:58,248`: 12 / 10) y L2 (`topologia-l2.architecture.json:206`: 12) sí son correctos; el diagrama general no. | `docker/pc3-administracion-infra/docker-compose.yml:45,65,72,82,104,139,185,208,220,232,244,257` (12 servicios `erpnext-*`). | Menor |
| M2 | `docs/arquitectura-3-equipos-departamentos.md:83`; `despliegue/l2-fallback/pruebas/README.md:8` | En L2 el gateway `.1` es «la IP de PC-3 en la sub-interfaz correspondiente» / «PC-3 crea `eth0.10/20/30/40/99` con la IP `.1`». | Las sub-interfaces `IFACE.NN` **no llevan IP**; el gateway va en una macvlan hermana `gwNN`. Está bien explicado en la receta L2 (`README.md:214-215`) pero no aquí. | `despliegue/l2-fallback/scripts/setup-vlans-pc3.sh:5-9,37-46`. | Menor |
| M3 | `despliegue/l3-switch/pruebas/README.md:55` (`scripts/firewall-pc3-matriz.sh`); `despliegue/l2-fallback/pruebas/README.md:20,55` (`scripts/setup-vlans-pc3.sh`); `despliegue/comun/lib-topologia.sh:14-15` (comentario, mismo error) | Rutas que ya no existen y descripción del script como «como hace hoy» con la IP en `eth0.NN`. | Los scripts están en `despliegue/l2-fallback/scripts/` y hoy usan `gwNN`. La «falla, ver abajo» del README L2 describe un diseño anterior que ya se corrigió. | `git ls-tree origin/master`: `despliegue/l2-fallback/scripts/{setup-vlans-pc3,firewall-pc3-matriz}.sh`; ningún `scripts/setup-vlans-*`. | Menor |
| M4 | `despliegue/l2-fallback/pruebas/README.md:28,31-33,37`; `docs/ldap-pretix-openvpms.md:62,66,78`; `docs/prueba-smoke-test-resultados.md:170,201,223` | Verificación «con los scripts reales de la rama `feat/perfiles-l2-l3-red` (commit `9d3317c`)», ejemplo con una copia `..\otra-copia`; ERPNext/InvenTree «los lleva otra sesión (rama `feat/ldap-erpnext-inventree`)»; «rama de Juan». | Todo eso ya está en master (PR #10 fusionó los perfiles; LDAPS de ERPNext e InvenTree está en los compose). Los ejemplos con `otra-copia` ya no hacen falta: los scripts viven en el mismo repo. | `docker/pc3-administracion-infra/docker-compose.yml:139-184`; `docker/pc2-operaciones/docker-compose.yml:124-144`; `docker/pc3-administracion-infra/ldap/05-acl-servicio.ldif`; `git log`: `bef05a5` (PR #10). | Menor |
| M5 | `docs/arquitectura-3-equipos-departamentos.md:114`; `diagramas/README.md:29-31` | `ca.crt` «se copia a PC-1 y PC-2 para que sus clientes confíen en ella». | PC-1 no consume la CA: `openvpms-app` no usa LDAPS y `deploy.sh` de PC-1 no la comprueba; `tutorial-pc1-medica.md:83` dice «este PC no necesita el certificado». El script sí la copia a `docker/pc1-medica/certs/` (inofensivo). Dos documentos se contradicen. | `docker/pc1-medica/docker-compose.yml:36-54` (sin volumen de certs); `docker/pc1-medica/deploy.sh:1-37`; `scripts/generar-certificados.sh:90-95`; `docs/ldap-pretix-openvpms.md:14-24` (OpenVPMS sin soporte LDAP). | Menor |
| M6 | `despliegue/l2-fallback/README.md:45`; `despliegue/l3-switch/README.md:43`; `pruebas/smoke-test-3-pcs/README.md:4`; `pruebas/software-un-host/README.md:5` | «22 contenedores» en los 3 PCs. | Hoy son 23 (2 + 6 + 15). La cifra de 22 era cierta antes de añadir `erpnext-ldap-config` (`docs/prueba-smoke-test-resultados.md:115` es histórico y no cuenta). | `docker/pc1-medica/docker-compose.yml`, `pc2-…`, `pc3-…`: 2, 6 y 15 `container_name`. | Menor |
| M7 | (no documentado; contradice a los documentos) `docker/pc1-medica/docker-compose.yml:48-49` | `DNS_HOST: 10.10.99.10` y `NTP_HOST: 10.10.99.10`. | En VLAN 99 el DNS es `10.10.99.11` y el NTP `10.10.99.12` (así lo dicen todos los documentos). Las variables no se usan en ningún otro fichero de `docker/pc1-medica/`, por lo que hoy no rompe nada, pero es un dato equivocado y engañoso. | `docker/pc3-administracion-infra/docker-compose.yml:331,341`; `docker/pc3-administracion-infra/bind/zones/db.reservaviva.local:12,14`. | Menor (es un fallo de código, no de documentación: decide quién lo arregla) |
| M8 | `diagramas/topologia-red.architecture.json:304,327,356,385,413,441` (evidencias con `line`); `diagramas/README.md:32` | Las referencias a código están «fijadas al commit `752e41f`». Ejemplos: «erpnext-hr (frontend)» → `pc3-…/docker-compose.yml:200`; «openldap» → `:226`; «dns-interno» → `:254`; «ntp-interno» → `:265`. | Desde `752e41f` cambiaron los compose (7 commits en `docker/`). Hoy `:226-252` es el scheduler/colas, `:254-263` es el comentario de `erpnext-hr` y `:265-273` es `erpnext-hr`; el openldap está en `:290-320`, el DNS en `:322-331` y el NTP en `:333-341`. Quien pulse la evidencia de código del diagrama verá otro servicio. El propio README lo advierte, pero no está regenerado. | `docker/pc3-administracion-infra/docker-compose.yml:257,290,322,333`; `git log 752e41f..origin/master -- docker`. | Menor |
| M9 | `tutoriales/tutorial-pc2-operaciones.md:99`; `tutoriales/tutorial-pc3-administracion-infraestructura.md:97`; `docs/arquitectura-3-equipos-departamentos.md:141`; `docs/prueba-smoke-test-resultados.md:21`; `pruebas/smoke-test-3-pcs/README.md:7`; `pruebas/software-un-host/README.md:36`; `docs/ldap-pretix-openvpms.md:45,94`; `despliegue/l3-switch/pruebas/README.md:29-30` | «…y luego **descarga** y arranca las aplicaciones»; «o **clonar** el repo directamente ahí»; `docker compose pull`; `pip install`; imagen `nicolaka/netshoot` (~900 MB) «ya descargada una vez». | El laboratorio no tiene Internet. Los tutoriales dicen a la vez «las imágenes ya están cargadas», así que «descarga» es solo una palabra mal elegida. Los `pull`/`pip`/`netshoot` son de máquinas de desarrollo con Internet y no están marcados como tales; `netshoot` no figura en la lista de la Fase 0 por si se ensaya en el laboratorio. `scripts/generar-certificados.sh:36` sugiere `sudo apt install openssl` (openssl debe venir en el paquete Fase 0). | Sin `curl`/`wget`/`git clone`/`apt` en los `deploy.sh` (`docker/pc*/deploy.sh`); únicos accesos a red: `docker/pc1-medica/openvpms/Dockerfile:14-18,26` (véase B3). | Menor |
| M10 | `despliegue/l3-switch/pruebas/README.md:14`; `despliegue/comun/lib-topologia.sh:165` | El simulador aplica la matriz con `policy drop` y una regla `drop-resto`, con reglas `accept` explícitas para VLAN 99. | Es cierto **del simulador**, pero es una lógica distinta de las dos implementaciones reales: ACL de Cisco (`deny` + `permit ip any any`) y `policy accept` + 12 `drop` en PC-3. Además `simular-l2.sh`, sin `RV_FIREWALL_PC3`, prueba las reglas de la biblioteca y no `firewall-pc3-matriz.sh`. Conviene aclararlo para que nadie use la evidencia del simulador como si fuera la del firewall real. | `despliegue/l2-fallback/scripts/firewall-pc3-matriz.sh:65`; `despliegue/l2-fallback/pruebas/simular-l2.sh:11,30-33`; `despliegue/l3-switch/switch/config-switch-l3.txt:45`. | Menor |
| M11 | `docs/borradores/arquitectura-2-equipos.md:7-9,49,98,113,152-156`; `docs/arquitectura-3-equipos-departamentos.md:6` | Cita `arquitectura-red-reserva-viva.xml`, `docker-compose-preproyecto.yml`, `arquitectura-hibrida-onpremise.md`, `arquitectura-distribuida-multihost.md`, `plug-and-play-2-equipos.md`, `plan-implementacion-reserva-viva.md`, `setup-vlans-pcA.sh` («no se eliminan»); en `:49` habla de «Deny-all inter-VLAN por defecto». | Ninguno de esos ficheros existe en master. El documento se declara «borrador histórico» (y `arquitectura-3-equipos…:6` avisa «no versionado en este repo»), pero el «deny-all por defecto» tampoco describe la matriz vigente. | `git ls-tree -r origin/master` (sin esos nombres). | Menor |
| M12 | `docs/arquitectura-3-equipos-departamentos.md:117` | Los tutoriales están «con capturas de lo que debe ver en pantalla». | No hay imágenes en master (ningún `.png/.jpg/.gif/.svg`); los tutoriales solo llevan tablas de texto. | `git ls-tree -r origin/master` sin extensiones de imagen. | Menor |
| M13 | `docs/arquitectura-3-equipos-departamentos.md:44,63,105` | VLAN 99 con host `10.10.99.10` únicamente; el bloqueo intra-PC «lo aplica el switch, no el host». | La VLAN 99 tiene además DNS `.11` y NTP `.12`. Y en el perfil L2 quien aplica el filtrado es **PC-3** (el switch no filtra); la afirmación solo vale para L3 (`:105` sí dice «switch/host-router»). | `docker/pc3-administracion-infra/docker-compose.yml:331,341`; `despliegue/l2-fallback/scripts/firewall-pc3-matriz.sh:1-3`. | Menor |
| M14 | `tutoriales/tutorial-pc2-operaciones.md:72-83`; `tutoriales/tutorial-pc3-administracion-infraestructura.md:73-81` | El bloque «Vas a ver algo así» del `.env` omite `INVENTREE_LDAP_BIND_PASSWORD` (PC-2) y `ERPNEXT_LDAP_BIND_PASSWORD` (PC-3). | Ambas variables están en los `.env.example` con valor por defecto `Svc-Lectura1`, así que no rompe nada, pero el operador ve un fichero más largo de lo que el tutorial le muestra. La receta L2 sí las explica (`README.md:192`). | `docker/pc2-operaciones/.env.example:36`; `docker/pc3-administracion-infra/.env.example:36`. | Menor |
| M15 | `README.md:19-39` | «Estructura del repositorio» lista un único documento en `docs/` y omite `docs/borradores/`, `docs/integracion-ldap-erpnext-inventree.md`, `docs/ldap-pretix-openvpms.md`, `docs/prueba-smoke-test-resultados.md` y `plans/`. | Existen todos en master. | `git ls-tree -r origin/master`. | Menor |
| M16 | `docs/prueba-smoke-test-resultados.md:58-59,130`; `despliegue/l3-switch/README.md:36`, `despliegue/l2-fallback/README.md:37` | Tiempos y recuentos del stack de PC-3 («~13 min», «2 que terminan por diseño») medidos antes de añadir `erpnext-ldap-config`. | Las cifras son de un momento anterior; no se ha vuelto a medir con el compose actual. | `docker/pc3-administracion-infra/docker-compose.yml:139-184`. | Menor (revalidar cuando se pueda arrancar Docker) |

## B5 en profundidad: diagnóstico y propuesta (sin aplicar)

**Qué promete la documentación.** «VLAN 99 solo responde» (`despliegue/l3-switch/README.md:57`); matriz con «✅ Permitido (auth/DNS/NTP)» de negocio a VLAN 99 y «✅ (responde)» de VLAN 99 a negocio (`docs/arquitectura-3-equipos-departamentos.md:52-56`).

**Qué implementa cada perfil.**

| | L3 (switch) | L2 (PC-3) |
|---|---|---|
| Negocio↔negocio | 12 `deny` (3 por ACL de entrada), `config-switch-l3.txt:41-60` | 12 `drop` con contador, `firewall-pc3-matriz.sh:67-72` |
| Negocio → VLAN 99 | Cae en `permit ip any any` (`:45,50,55,60`): **cualquier protocolo y puerto** | No hay regla; `policy accept` (`:65`): **cualquier protocolo y puerto** |
| VLAN 99 → negocio | `interface Vlan99` sin `ip access-group` (`:84-88`): **puede iniciar** cualquier conexión | Sin regla: **puede iniciar** cualquier conexión |

**Conclusión:** la brecha es **la misma en L2 y en L3**. En ambos perfiles la matriz implementada es «negocio↔negocio bloqueado; todo lo demás abierto». Los comentarios del propio `config-switch-l3.txt:37-40` y de `firewall-pc3-matriz.sh:7` lo reconocen («queda permitido», «no se toca»); lo que no cuadra es la promesa de las recetas y de la matriz.

**Restricciones que la propuesta debe respetar** (si no, rompe pasos documentados):
- Las pruebas de las recetas usan `ping` a `10.10.99.10/.11` (`verificacion.md`), `ldapsearch -H ldap://…` en **389** en claro (`despliegue/l3-switch/README.md:408`; la L2 igual), `dig @10.10.99.11` (UDP 53) y `ntpdate -q 10.10.99.12` (UDP 123). Las apps usan LDAPS **636** (compose de PC-2 y PC-3).
- El `scp` de `ca.crt` lo inicia PC-2 hacia `10.10.99.250` (`despliegue/l3-switch/README.md:255,265`): necesita **TCP 22** hacia esa dirección en L3. En L2 va a `10.10.99.1` (tráfico local de PC-3, no pasa por `forward`), así que no necesita regla.
- `ping 10.10.N.1` al gateway (`README.md:358`) es tráfico hacia la propia SVI y también pasa por la ACL de entrada.
- El simulador (`despliegue/comun/probar-matriz.sh:5,28,36`) exige que VLAN 99 → negocio **abra conexiones nuevas** (puerto 8080); con la propuesta esa celda pasaría a fallar y habría que cambiarla a «solo respuestas».

**Propuesta L3 (`config-switch-l3.txt`).** Sustituir el `permit ip any any` final de cada ACL de negocio (ejemplo para VLAN 10; repetir con su subred en 20, 30 y 40) y añadir una ACL a la SVI de VLAN 99:

```
ip access-list extended ACL-VLAN10-IN
 deny   ip 10.10.10.0 0.0.0.255 10.10.20.0 0.0.0.255      ! (los 3 deny actuales, sin cambios)
 deny   ip 10.10.10.0 0.0.0.255 10.10.30.0 0.0.0.255
 deny   ip 10.10.10.0 0.0.0.255 10.10.40.0 0.0.0.255
 permit icmp 10.10.10.0 0.0.0.255 host 10.10.10.1          ! ping al gateway
 permit icmp 10.10.10.0 0.0.0.255 10.10.99.0 0.0.0.255 echo
 permit tcp  10.10.10.0 0.0.0.255 10.10.99.0 0.0.0.255 eq 636   ! LDAPS
 permit tcp  10.10.10.0 0.0.0.255 10.10.99.0 0.0.0.255 eq 389   ! LDAP (o quitar y cambiar la prueba a ldaps)
 permit tcp  10.10.10.0 0.0.0.255 10.10.99.0 0.0.0.255 eq 53
 permit udp  10.10.10.0 0.0.0.255 10.10.99.0 0.0.0.255 eq 53
 permit udp  10.10.10.0 0.0.0.255 10.10.99.0 0.0.0.255 eq 123   ! NTP
 permit tcp  10.10.10.0 0.0.0.255 host 10.10.99.250 eq 22       ! solo scp de ca.crt (PC-1/PC-2)
 deny   ip any any                                              ! explícito, con su contador
ip access-list extended ACL-VLAN99-IN
 permit tcp  10.10.99.0 0.0.0.255 any established              ! respuestas TCP
 permit udp  10.10.99.0 0.0.0.255 eq 53  any                   ! respuestas DNS
 permit udp  10.10.99.0 0.0.0.255 eq 123 any                   ! respuestas NTP
 permit icmp 10.10.99.0 0.0.0.255 any echo-reply
 permit icmp 10.10.99.0 0.0.0.255 host 10.10.99.1
 deny   ip any any
interface Vlan99
 ip access-group ACL-VLAN99-IN in
```

Notas: las ACL de IOS no guardan estado; por eso VLAN 99 solo puede devolver respuestas (`established`, puertos de origen 53/123, `echo-reply`). Para demostrar que VLAN 99 no inicia nada, un `nc`/`curl` desde un contenedor de VLAN 99 hacia negocio debe fallar y subir el contador del `deny ip any any` de `ACL-VLAN99-IN`. Habría que actualizar `verificacion.md:24-25,43` («sin ACL en Vlan99») y la comprobación de `show access-lists`.

**Propuesta L2 (`firewall-pc3-matriz.sh`).** Dentro de la misma cadena `forward`, **antes** de los 12 `drop` actuales, en la misma tabla `inet reservaviva` (ya casan por `gwNN`):

```
ct state established,related counter accept comment "est-rel"
iifname { "gw10","gw20","gw30","gw40" } oifname "gw99" ip protocol icmp icmp type echo-request counter accept
iifname { "gw10","gw20","gw30","gw40" } oifname "gw99" tcp dport { 53, 389, 636 } counter accept
iifname { "gw10","gw20","gw30","gw40" } oifname "gw99" udp dport { 53, 123 } counter accept
iifname { "gw10","gw20","gw30","gw40" } oifname "gw99" counter drop comment "negocio -> 99 fuera de auth/DNS/NTP"
iifname "gw99" oifname { "gw10","gw20","gw30","gw40" } counter drop comment "99 no inicia"
```

Efectos a asumir: el «12 reglas `drop`» que citan `despliegue/l2-fallback/README.md:252` y `verificacion.md:19` pasaría a 14; el simulador y `probar-matriz.sh` habría que adaptarlos (VLAN 99 → negocio solo respuestas); y **ninguna de las dos propuestas se ha probado** (Docker y el switch no disponibles). La política sigue en `accept`: solo se añaden reglas entre interfaces de VLAN, así que el tráfico interno de Docker no se toca (lo que busca el diseño actual, `firewall-pc3-matriz.sh:5-9`).

**Alternativa barata (solo texto).** Reescribir la documentación para que diga lo que hay: «se bloquea el tráfico entre VLAN de negocio; el acceso a la VLAN 99 (LDAP/DNS/NTP) no se restringe por servicio». Cambia `despliegue/l3-switch/README.md:57`, `docs/arquitectura-3-equipos-departamentos.md:52-56` y el diagrama de flujo de segmentación. Es la única opción que no exige probar nada en hardware.

## Recomendación de corte inicial (sustituida por la lista de la sección «Cambio de rumbo», §5)

**Arreglar antes de entregar (por este orden):**
1. **B3, verificar y arreglar** (imágenes por digest y `build:` de OpenVPMS): es lo único que puede impedir que arranque nada en el laboratorio. Cuando Docker esté libre: `docker load` + `docker compose up -d --pull never` con la red cortada.
2. **B4, comandos de la Fase 0**, integrados en master y coherentes con B3 (mismo trabajo).
3. **B2**: una frase en tres sitios; evita una falsa alarma en el paso de verificación de PC-3.
4. **B1**: fusionar el PR #15 (ya arreglado).
5. **B5**: decidir entre implementar la propuesta o reescribir el texto. Recomendación: **reescribir el texto ahora** (coste mínimo, sin riesgo) y dejar la propuesta como mejora documentada; implementar ACL más estrictas sin poder probarlas contra el switch real arriesga romper el `scp` o el LDAP el día de la práctica. Si hay tiempo de ensayar con los simuladores, implementar L2 primero (es el único que se puede probar en software).
6. **M7** (`DNS_HOST`/`NTP_HOST`, ya asignado): dos líneas en el compose de PC-1.
7. **M2, M3, M4, M6, M12**: correcciones de una línea cada una en texto; hacerlas al tocar esos ficheros por otro motivo.

**Puede quedarse como limitación conocida (documentada):** M1 (recuentos de servicios, salvo el diagrama general si se regenera), M5, M8 (evidencias de línea de los diagramas: regenerar solo si sobra tiempo), M9 (redacción «descarga»; los `pull`/`pip` son de desarrollo), M10, M11 (borrador histórico), M13–M16 y `plans/`.

## Cambio de rumbo: laboratorio en Windows con Docker Desktop, sin VLANs

**Decisión recibida:** los PCs serán Windows con Docker Desktop; se renuncia a VLANs, macvlan y matriz de segmentación y se documenta como limitación conocida. Esta sección diagnostica qué queda desalineado. **No se ha corregido nada.**

### 0. Por qué no basta con quitar la matriz: tres cosas que rompe el cambio

1. **Los compose reales dejan de arrancar en Windows.** Declaran redes `driver: macvlan` con `parent: ${IFACE:-eth0}[.NN]` (`docker/pc1-medica/docker-compose.yml:12-14`, `docker/pc2-operaciones/docker-compose.yml:10-12,20-22`, `docker/pc3-administracion-infra/docker-compose.yml:10-12,20-22`). Docker Desktop corre en una máquina virtual Linux: esas interfaces padre no existen. Solo funcionan con los `override-pc*.yml` de `pruebas/smoke-test-3-pcs/`, que las cambian a `bridge`.
2. **No hay `ports:` publicados.** Los servicios solo son alcanzables por su IP `10.10.x.x` (`ipv4_address`), y en Docker Desktop las IP de un `bridge` **no son alcanzables desde el host Windows** (ya lo dice `docs/prueba-smoke-test-resultados.md:19-20`). El único puerto publicado es `18080:8080` de OpenVPMS, y solo en el arnés (`pruebas/smoke-test-3-pcs/override-pc1.yml:10`). Para abrir Pretix, InvenTree o ERPNext desde el navegador de Windows hace falta publicar puertos (o usar un contenedor auxiliar); hoy no está resuelto en ningún fichero.
3. **Tres PCs Windows separados no se ven entre sí a nivel de contenedor.** El diseño mete IP fijas entre PCs en el código: PC-1 y PC-2 llegan al LDAP en `10.10.99.10` (`docker/pc1-medica/docker-compose.yml:47`; `docker/pc2-operaciones/docker-compose.yml:133-134`, `extra_hosts`) y PC-2 a sus bases en `10.10.20.11/.12`, `10.10.30.11`. Con redes `bridge` locales, esas IP solo existen dentro del mismo host Docker. **Decisión de arquitectura pendiente para el usuario:** ¿el laboratorio es **un solo PC** que corre los tres compose juntos (lo único validado: 23 contenedores, ~13 min, ~7 GB de RAM para Docker, `docs/prueba-smoke-test-resultados.md:14,115`), o **tres PCs** que deben hablarse por LAN? La segunda opción exige rediseñar (publicar 636/389/53/123 de PC-3, parametrizar `LDAP_HOST` y `extra_hosts` con la IP real de PC-3) y no está diseñada ni probada. La recomendación de esta auditoría es **un solo PC**, salvo que el curso exija tres máquinas físicas.

### 1. Documentos que prometen segmentación, VLAN, macvlan, 802.1Q, matriz o switch

| Fichero:línea | Qué dice exactamente | Estado tras el cambio |
|---|---|---|
| `README.md:3` | «El laboratorio usa un switch administrable físico + Docker (VLANs vía `macvlan`)… y sin conexión a Internet.» | **Falso.** Reescribir la frase inicial. |
| `README.md:7` | «3 computadores físicos… conectados al switch con puertos access/trunk.» | Falso como estado del laboratorio; válido como diseño propuesto. |
| `README.md:11-15`, `:21-25` | Tabla de PCs con columna VLAN; «diseño vigente (VLANs, matriz de segmentación…)». | Reetiquetar como diseño propuesto. |
| `README.md:31-34` | `despliegue/` = «¿switch L2 o L3?», recetas L3 y L2, simuladores. | Pasa a anexo. |
| `README.md:43-49` | «Antes que nada, averigua si el switch es L2 o L3»; `sudo ./deploy.sh`; servicios systemd. | Falso en Windows (ver §2). |
| `README.md:55-56` | Diagramas de topología física y de «matriz de segmentación (qué pasa y qué se bloquea)». | Válidos como diseño; aclarar que no se ejecutan. |
| `README.md:60,64,68` | Prueba de humo «no valida el switch…»; pendiente «confirmar si el switch es L3». | El pendiente desaparece; la prueba de humo pasa a ser la validación principal. |
| `despliegue/README.md:1-99` (toda la página) | Cómo saber si el switch es L2/L3 con comandos Cisco (`:5-53`), tabla de perfiles (`:66-71`), «Ensaya antes en tu portátil» (`:88-93`), «Estado de validación… pendiente de hardware» (`:95-99`). | Página entera pasa a anexo; `:79` (`.deb` de Docker para Ubuntu Server) queda sin sentido (ver §5). |
| `despliegue/l2-fallback/README.md` y `despliegue/l3-switch/README.md` (≈510-550 líneas cada uno; los números de línea siguientes son los de L3, en L2 van desplazados ~2) | Recetas de 9 pasos: configurar el switch (`:47-105`), cablear (`:107-121`), `.env` con `PERFIL`/`IP_GESTION` (`:149-205`), `deploy.sh` con `sudo` en Ubuntu, pruebas por VLAN con portátil (`:325-422`), captura 802.1Q (`:424-446`), systemd (`:448-495`). | Todo el contenido presupone switch físico y Ubuntu. Anexo de diseño. |
| `despliegue/{l2-fallback,l3-switch}/switch/verificacion.md` | Comandos de verificación del switch y de PC-3. | Anexo, no ejecutable. |
| `docs/arquitectura-3-equipos-departamentos.md:6,14-16` | «Diseño vigente»; «tráfico real de VLAN a VLAN que sí atraviesa el switch físico… evidencia real (ping, iperf3, mtr, captura de Wireshark en el trunk)». | Falso como capacidad del laboratorio. |
| `…arquitectura…md:26-30` | Tabla PC/VLAN/«Tipo de puerto en el switch» (Access/Trunk 802.1Q). | Diseño propuesto. |
| `…arquitectura…md:36-46` | Direccionamiento por VLAN y gateway/SVI. | Válido como plan de direccionamiento; coincide con los `subnet` de los compose y de los bridges del arnés. |
| `…arquitectura…md:48-63` | «Matriz de política de segmentación (a demostrar en la sustentación)», «bloqueo inter-PC real», «hairpin». | Solo demostrable en simulación (§2). Cambiar «a demostrar» por «diseñada; validada en simulador». |
| `…arquitectura…md:65-86` | Perfiles L2/L3, «Falta confirmar con el laboratorio…», «Estado de la validación». | Anexo; la pregunta L2/L3 ya no aplica. |
| `…arquitectura…md:100-107` | Plan de pruebas: bloqueo inter-PC e intra-PC, Wireshark en el trunk, `iperf3`/`mtr` entre PCs. | No ejecutable. Reemplazar por el plan realmente ejecutable (LDAPS, DNS, NTP, HTTP por servicio). |
| `…arquitectura…md:109-149` | Puesta en marcha: `sudo ./deploy.sh`, sub-interfaces 802.1Q, `PERFIL`, systemd. | Falso en Windows. |
| `…arquitectura…md:151-159` | «Próximos pasos»: confirmar L2/L3, cablear al switch, correr `deploy.sh`. | Obsoletos. |
| `tutoriales/README.md:7-9,15,18` | PC-1/2/3 identificados por «puerto marcado como Médica/VLAN10… TRUNK en el switch»; «Ubuntu Server»; «cable de red conectado al puerto correcto del switch». | Obsoleto. |
| `tutoriales/tutorial-pc1-medica.md:7,14,29,43,82,110,116-122` | Ubuntu Server; puerto access VLAN 10; `PERFIL`; «desde otro equipo conectado a la VLAN 10»; `systemctl`. | Obsoleto en su totalidad salvo `.env` de contraseñas. |
| `tutoriales/tutorial-pc2-operaciones.md:7,14,29,43,86-87,99,101,121,125,145,147` | Ídem, más `IP_GESTION`, «dos VLANs (20 y 30)», «puerto del switch no permite las dos VLANs». | Obsoleto. |
| `tutoriales/tutorial-pc3-administracion-infraestructura.md:7,11,15,30,84,97,120,135,144` | Ídem, más «pregunta si el switch es L2 o L3», «PC-3 hace de router». | Obsoleto. |
| `diagramas/README.md:7-8` y los cinco HTML/JSON de `diagramas/` y `despliegue/*/diagramas/` | Topología con switch central, access/trunk, contenedores «por VLAN (macvlan)»; flujo de segmentación. | Válidos como diseño de red propuesto; hay que rotularlos así (el diagrama general ya está entre los que corrige el PR #15). |
| `docs/prueba-smoke-test-resultados.md:16,62,93-98,109,162,264` | Ya dice «no valida macvlan, 802.1Q ni el switch», «probar desde otro equipo». | **Ya es honesto**; solo `:109` («Repetir con macvlan real… confirmar si es L2 o L3») y `:162` se actualizan. |
| `docs/integracion-ldap-erpnext-inventree.md:3` | «Probada en el arnés (un solo host, redes `bridge`). No valida macvlan ni el switch.» | **Ya es honesto y válido tal cual.** |

### 2. Qué deja de ser ejecutable y pasa a diseño teórico

| Elemento | Motivo | Destino |
|---|---|---|
| `despliegue/l2-fallback/switch/config-switch-l2.txt`, `despliegue/l3-switch/switch/config-switch-l3.txt`, ambos `verificacion.md` | Requieren un switch Cisco físico. | Anexo (diseño). |
| `despliegue/*/scripts/setup-vlans-pc2.sh`, `…pc3.sh` | Crean sub-interfaces 802.1Q con `ip link` en un Linux con root. | Diseño; **sí** siguen ejecutables dentro del simulador (ver abajo). |
| `despliegue/l2-fallback/scripts/firewall-pc3-matriz.sh` | `nft` + `iptables DOCKER-USER` sobre interfaces `gwNN`. | Íd. |
| `docker/pc{1,2,3}-*/deploy.sh` | Exigen root real (`id -u`, `docker/pc1-medica/deploy.sh:11-13`, `pc2:50-52`, `pc3:14-16`), crean interfaces y llaman a `scripts/perfil.sh` y `scripts/ip-gestion.sh` (`ip addr replace`, `ip route`). No corren en Windows. | **Hacen falta sustituir.** Ver §3-B: hoy nada más crea el administrador de Pretix (`pc2-operaciones/deploy.sh:13-31`) ni genera los certificados antes del `up` (`pc3-…/deploy.sh:41-47`). |
| `scripts/perfil.sh`, `scripts/ip-gestion.sh`, `.env`: variables `PERFIL`, `IP_GESTION`, `IFACE` | Sin VLANs no significan nada. | Diseño. |
| `scripts/systemd/reserva-viva-pc{1,2,3}.service` | Windows no usa systemd. | Diseño (en Docker Desktop: «Start when you sign in» + `restart: unless-stopped`, que ya está en los compose). |
| Redes `macvlan` de los tres `docker-compose.yml` | Ver §0-1. | Diseño; en Windows se usa el arnés (`bridge`). |
| Test plan de `docs/arquitectura…:100-107` y evidencia con Wireshark/`show access-lists` | Requieren switch. | Diseño. |

**Sí siguen siendo ejecutables en Windows, y son la mejor evidencia de la segmentación:** los simuladores `despliegue/{l3-switch,l2-fallback}/pruebas/simular-l{3,2}.sh` junto con `despliegue/comun/lib-topologia.sh` y `probar-matriz.sh`. Se ejecutan dentro de un contenedor `--privileged` (`nicolaka/netshoot`) y sus README documentan que se corrieron en **Docker Desktop en Windows** (`despliegue/l3-switch/pruebas/README.md:45`, `despliegue/l2-fallback/pruebas/README.md:39`): las 20 celdas de la matriz, con un contador por regla, y con `RV_SETUP_PC3`/`RV_FIREWALL_PC3` ejecutan los **scripts reales** `setup-vlans-pc3.sh` y `firewall-pc3-matriz.sh` (`simular-l2.sh:11,30-33`). Es decir: los scripts de VLAN y de firewall **no son teoría pura**: están validados en el kernel de Linux de Docker Desktop, aunque no en hardware. Este matiz cambia el tono de la entrega (ver §4). Salvedad: la imagen `nicolaka/netshoot` (~900 MB) debe estar en el paquete offline.

### 3. Qué sigue siendo válido tal cual

**A. Documentación y diseño**

| Fichero | Por qué vale |
|---|---|
| `docs/integracion-ldap-erpnext-inventree.md`, `docker/pc3-administracion-infra/ldap/README.md`, `docker/pc3-administracion-infra/ldap/*.ldif` | LDAPS 636 con CA interna, OU por departamento, `svc-lectura`: probado en el arnés, independiente de las VLAN. |
| `docs/ldap-pretix-openvpms.md` | Evaluación de OpenVPMS/Pretix sin LDAP; solo afecta M4 (referencias a ramas). |
| `docs/prueba-smoke-test-resultados.md` | Ya declara sus límites; es la validación principal. |
| `pruebas/smoke-test-3-pcs/**` | Es **el** modo de ejecución en Windows (bridge, mismas subredes e IP). Necesita ampliarse (ver §3-B). |
| `docker/**/docker-compose.yml` salvo las redes; healthchecks; `docker/pc3-administracion-infra/bind/`; `.env.example` salvo `IFACE`/`PERFIL`/`IP_GESTION` | Definición de servicios, imágenes, variables, LDAP/DNS/NTP: no dependen de VLAN. |
| `scripts/generar-certificados.sh` | Es Bash + `openssl`; corre en Git Bash/WSL (la instalación en el almacén de confianza solo actúa con root Linux, `:99`). `.gitattributes` fuerza LF en `*.sh`, `Dockerfile` y `*.service`, así que el clon en Windows no rompe los scripts. |
| `docs/arquitectura…:36-46` (direccionamiento), `:88-98` (aplicaciones por PC) | Coinciden con los compose y el arnés. |

**B. Lo que falta para que Windows sea ejecutable (no existe hoy):**
1. Un **runbook de Windows**: instalación de Docker Desktop offline (WSL2 o Hyper-V), carga de imágenes, generar certificados, `docker compose -f … up -d` del arnés, creación del administrador de Pretix (lo que hoy hace `deploy.sh`), y las URLs de acceso. Sustituye a los tres tutoriales.
2. **Puertos publicados** para acceder a las aplicaciones desde el navegador de Windows (§0-2).
3. Aclarar si el arnés se usa tal cual (un PC) o se rediseña para tres (§0-3).
4. Riesgos propios de Windows a probar: puertos 53 y 123 UDP ya usados por el sistema, licencia y requisitos de virtualización, ≥ 7 GB de RAM para Docker.

### 4. Cómo contarlo en la entrega (propuesta, con una mejora)

Coincido con el planteamiento: el diseño con VLANs como **diseño de red propuesto**, scripts y diagramas como anexo, y validación sobre Docker Desktop con redes `bridge`. Propongo tres ajustes:

1. **No hablar de «renuncia». Hablar de tres niveles de evidencia**, con una tabla en el README raíz y en la sección de validación de `docs/arquitectura…`:

   | Nivel | Qué es | Dónde se demuestra |
   |---|---|---|
   | **Implementado y ejecutado** | Las 4 aplicaciones, LDAPS 636 con CA interna, DNS, NTP, direccionamiento `10.10.X.0/24` y sus IP, healthchecks; todo en Docker Desktop con redes `bridge`. | `pruebas/smoke-test-3-pcs/`, `docs/prueba-smoke-test-resultados.md`, `docs/integracion-ldap-erpnext-inventree.md` |
   | **Simulado en kernel Linux (Docker Desktop)** | Segmentación 802.1Q y matriz: 20 celdas, un contador por regla; perfil L2 con los scripts reales. | `despliegue/*/pruebas/`, ejecutable en vivo en la sustentación |
   | **Diseñado, no validado en hardware** | Configuración del switch Cisco, trunk 802.1Q entre PCs, macvlan real, `scp` entre PCs. | `despliegue/*/switch/`, diagramas |

2. **Explicar el motivo, no esconderlo:** «los PCs del laboratorio son Windows con Docker Desktop, que no permite macvlan ni 802.1Q sobre la tarjeta física; por eso la segmentación se validó por simulación».
3. **Tratar el simulador como la demostración central de la segmentación**, no como material secundario: es lo único que muestra en vivo el bloqueo con contadores, y funciona en la misma máquina Windows.

Además, **sin cambiar la estructura de carpetas** (evita romper 60+ enlaces): basta un aviso al inicio de `despliegue/README.md`, de las dos recetas y de los tres tutoriales («documento de diseño; no aplica al laboratorio en Windows») y un tutorial/runbook nuevo. Y una advertencia sobre el alcance: la matriz que se presente debe ser la implementada (B5: hoy «negocio↔negocio bloqueado; el resto abierto»), o no habrá coherencia ni siquiera en la simulación.

### 5. Lista de corte actualizada

**Antes de entregar, por este orden:**
1. **Decidir un PC o tres** (§0-3). Todo lo demás depende de esto.
2. **Runbook de Windows + puertos publicados + sustituto de `deploy.sh`** (§3-B) y probarlo con el arnés cuando Docker esté libre. Sustituye a B4 y a los tres tutoriales.
3. **B3 cambia de naturaleza:** ya no hay `.deb` de Ubuntu (`despliegue/README.md:79`, recetas `:13-15`, tutoriales `:29,43`); pasa a ser el instalador de Docker Desktop offline y las imágenes. **Se mantiene** el problema de fondo: los compose fijan `nombre:tag@sha256:…` (`docker/pc1-medica/docker-compose.yml:23`, etc.), que un `docker load` por etiqueta puede no satisfacer, y `openvpms-app` sigue teniendo solo `build:` (`:37`) con `apt`/`curl` en el Dockerfile. Verificar con `docker load` + `up --pull never` sin red. Añadir la plataforma (`linux/amd64`) y `nicolaka/netshoot` si se ensaya el simulador.
4. **B5 se integra en este cambio:** ya no hay que endurecer ACL ni reescribir solo esa frase; la matriz pasa a ser «diseñada y simulada». Aun así, `despliegue/l3-switch/README.md:57` y `arquitectura…:52-56` deben decir lo que el diseño implementa realmente («VLAN 99 solo responde» no es cierto), y no conviene tocar `config-switch-l3.txt` ni el firewall.
5. **Reescribir el aviso de estado** de `README.md:3-7,43-49,60-64` y añadir la tabla de tres niveles (§4).
6. **B2** (`erpnext-ldap-config` en `Exited (0)`): sigue vigente si se usa `docker compose ps` en el runbook.
7. **B1**: fusionar el PR #15 (diagramas L2 ya corregidos) — más razón para no editarlos aparte.
8. **M7** (`DNS_HOST`/`NTP_HOST` en el compose de PC-1) y las correcciones de una línea (M2, M3, M4, M6, M12).

**Se queda como limitación conocida y documentada:** VLANs, macvlan, 802.1Q entre PCs, switch físico (L2/L3), `scp` entre PCs, `IP_GESTION`, systemd, Wireshark en el trunk, y todo M1, M5, M8, M9, M10, M11, M13–M16 y `plans/`.

## Lo comprobado sin discrepancias

- **Enlaces `[..](..)`:** los 12 documentos con enlaces relativos resuelven contra master, incluidos `diagramas/*.html`, `despliegue/*/diagramas/*.html` y `despliegue/comun/probar-matriz.sh`.
- **Direcciones:** `10.10.10/20/30/40/99.0/24`, gateways `.1`, contenedores `.10` (aplicación), `.11` (bases de datos y `erpnext-backend`), `.12` (`pretix-redis`, `inventree-worker`, NTP), `10.10.99.10` LDAP, `.11` DNS y `.12` NTP; `IP_GESTION` en `.250` (rango 16-254 frente a `ip_range …/28`). Coinciden en `README.md`, `docs/`, recetas L2/L3, `verificacion.md` y tutoriales.
- **Puertos:** OpenVPMS `:8080/openvpms/login`, Pretix `:80`, InvenTree `:8000/api/`, ERPNext `:8080` (nginx `erpnext-hr`, backend `:8000`, websocket `:9000`), LDAPS `:636` con CA de `scripts/generar-certificados.sh`, DNS `:53`, NTP `:123`.
- **VLAN por puerto:** PC-1 access 10; PC-2 trunk 20,30; PC-3 trunk 40,99 (L3) o 10,20,30,40,99 (L2); VLAN nativa 999. Coincide con `config-switch-l3.txt` / `config-switch-l2.txt` y con `lib-topologia.sh`.
- **Servicios nuevos:** bind9 en `.99.11` (zona con 7 nombres, igual que el smoke test), `inventree-worker` en `.30.12`, `pretix-redis` en `.20.12`, `deploy.sh --solo-admins` y `PASO PENDIENTE` de PC-2 existen tal como los describen los tutoriales.
- **Firewall L2:** 12 reglas `drop` con contador, tabla `inet reservaviva`, casan por `gwNN`, `arp_ignore=1`/`arp_announce=2`, regla en `DOCKER-USER`: descrito correctamente en `despliegue/l2-fallback/README.md:214-252` y `verificacion.md`.

## Fuera de alcance / advertencias

- **`plans/handoffs/**`:** son notas de traspaso históricas y citan ramas, rutas y stacks que ya no existen en master; no se auditaron línea a línea.
- **Árbol de trabajo compartido:** durante la auditoría el directorio del proyecto pasó a la rama `test/ldaplogin-revalidacion` (otra sesión); por eso este informe se redactó en un `git worktree` aparte, partiendo de `origin/master`.
- **Docker no se usó** (está caído), así que B3 y M16 quedan como hipótesis a verificar y no como hecho comprobado.
