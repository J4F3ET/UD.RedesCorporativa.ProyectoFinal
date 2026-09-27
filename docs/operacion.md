# Operación del sistema en un host

Cómo arrancar, vigilar, parar y validar Reserva Viva en un solo equipo. Todo pasa por el lanzador `levantar-sistema` (`.ps1`, `.cmd` o `.sh`), cuya lógica está en [`levantar-sistema.sh`](../levantar-sistema.sh). Las cifras medidas (tiempos, memoria, pasadas de `verificar`) están solo en [`resultados-un-host.md`](resultados-un-host.md). Aquí se enlazan, no se copian.

Documentos relacionados: [`arquitectura.md`](arquitectura.md) (servicios, redes e IP), [`seguridad.md`](seguridad.md) y [`aplicaciones.md`](aplicaciones.md).

## 1. Requisitos

- **Windows 11 con WSL2** y una distro con **Docker Engine** (el entorno medido es `Ubuntu-24.04`), o bien **Docker Desktop** con Git for Windows. El lanzador de Windows usa Docker Desktop si está en marcha. Si no lo está, busca una distro de WSL en la que `docker info` responda. El modo Docker Desktop no se ha probado (ver los pendientes de [`resultados-un-host.md`](resultados-un-host.md#pendientes)).
- **Docker Compose 2.24.4 o superior** y **openssl** en el entorno donde corre el `.sh`. `verificar` necesita además `python3`.
- **Memoria.** Hay dos comprobaciones y `-Forzar` / `--forzar` salta las dos:
  - `levantar-sistema.ps1`: al arrancar en frío exige **6,9 GB de memoria libre en Windows** (`$MinLibreGB`).
  - `levantar-sistema.sh`: exige que Docker disponga de **al menos 6 GiB** (`MIN_VM_GIB`), y avisa sin abortar si en Linux/WSL quedan menos de 5 GiB libres.
  - Si ya hay contenedores del sistema en marcha, ninguna de las dos se comprueba, porque su memoria ya está asignada.
- **Internet la primera vez.** Hace falta para descargar las imágenes (varios GB) y para construir la de OpenVPMS.

### `.wslconfig` recomendado

Va en `%UserProfile%\.wslconfig`, fuera del repositorio. Es la configuración con la que se midió el sistema:

```ini
[wsl2]
memory=8GB
processors=6
swap=4GB
swapFile=C:\\Users\\<usuario>\\WSL\\swap.vhdx
localhostForwarding=true
dnsTunneling=false
firewall=true
vmIdleTimeout=7200000
[experimental]
autoMemoryReclaim=gradual
hostAddressLoopback=true
```

| Clave | Por qué |
|---|---|
| `memory=8GB` | Techo de RAM de la VM. Con menos, Docker no llega a los 6 GiB que exige el script |
| `processors=6` | Núcleos para la VM; el primer arranque inicializa varias bases de datos a la vez |
| `swap=4GB` / `swapFile=…` | Margen durante la inicialización de OpenVPMS, el momento de más memoria |
| `localhostForwarding=true` | Hace que `http://localhost:<puerto>` en el navegador de Windows llegue a los puertos publicados dentro de WSL |
| `dnsTunneling=false` | En el equipo de medida, el túnel DNS de WSL chocaba con Tailscale. Sin VPN puede quedar en `true` |
| `firewall=true` | Aplica el firewall de Windows a la VM |
| `vmIdleTimeout=7200000` | La VM espera 2 h sin actividad antes de apagarse. Por defecto son 60 s, y al apagarse se lleva los contenedores (trampa 1) |
| `autoMemoryReclaim=gradual` | Devuelve a Windows poco a poco la memoria que la VM ya no usa |
| `hostAddressLoopback=true` | Permite que Windows y la VM se alcancen por la dirección del host (solo tiene efecto en el modo de red `mirrored`) |

Los cambios en `.wslconfig` se aplican con `wsl --shutdown`, que **apaga todos los contenedores**. Hazlo con el sistema detenido.

## 2. Arranque rápido y acciones

| Desde | Comando |
|---|---|
| Explorador de Windows | Doble clic en `levantar-sistema.cmd` (al terminar espera una tecla) |
| PowerShell | `.\levantar-sistema.ps1 [acción] [-Forzar] [-Rapido] [-Si] [-TimeoutMin <min>] [-Distro <distro>]` |
| `cmd.exe` | `levantar-sistema.cmd [acción] [opciones del .ps1]` |
| bash (WSL, Linux) | `./levantar-sistema.sh [acción] [--forzar] [--rapido] [--si] [--timeout <min>]` |

Sin acción se ejecuta `arrancar`. Si PowerShell bloquea el script, usa el `.cmd` o `powershell -ExecutionPolicy Bypass -File .\levantar-sistema.ps1`. La ayuda sale con `.\levantar-sistema.ps1 ayuda` o `./levantar-sistema.sh --help`.

| Acción | Qué hace | Cuánto tarda (orientativo) | ¿Borra datos? |
|---|---|---|---|
| `arrancar` | Requisitos, memoria, `preparar`, `up -d`, espera a que todo esté sano y crea el administrador de Pretix | Primer arranque: del orden de un cuarto de hora con las imágenes ya descargadas. Con el sistema ya arriba, alrededor de un minuto | No |
| `preparar` | Solo lo previo: certificados, zona DNS, validación del compose e imagen de OpenVPMS. No arranca nada | Segundos, salvo la primera construcción de la imagen | No |
| `estado` | Tabla de servicios (servicio, estado, detalle) y direcciones de acceso | De segundos a varios minutos (desde Windows, a través de WSL, es cuando más tarda) | No |
| `verificar` | Ejecuta [`sistema/verificar_arquitectura.py`](../sistema/verificar_arquitectura.py) y guarda un informe. Con `-Rapido` / `--rapido` omite la prueba de persistencia | Completo: un cuarto de hora aproximadamente (incluye `down` + `up -d`). Rápido: bastante menos | No (el completo para y levanta los contenedores sin `-v`) |
| `detener` | `docker compose stop`: para los contenedores y conserva todo | Segundos | No |
| `borrar` | `docker compose down -v --remove-orphans`: contenedores, redes **y volúmenes**. Pide escribir `borrar` (o `-Si` / `--si`) | Segundos, pero el siguiente arranque reinicializa todo (el script avisa de unos 30 min) | **Sí, todos** |

Las cifras medidas están en [`resultados-un-host.md`](resultados-un-host.md). Al terminar, `arrancar` y `estado` muestran las direcciones de acceso. Las contraseñas de laboratorio están en [`sistema/test.env`](../sistema/test.env).

## 3. Qué pasa en un arranque

`arrancar` ejecuta, en este orden:

1. **Requisitos** (`comprobar_requisitos`): `docker` responde, Compose ≥ 2.24.4 y `openssl` presente.
2. **Memoria** (`comprobar_memoria`). En Windows, el `.ps1` ya ha comprobado antes la memoria libre del equipo.
3. **`preparar`**:
   1. **Certificados** (`preparar_certificados`): ejecuta [`servicios/ca/generar-certificados.sh`](../servicios/ca/generar-certificados.sh) `--sin-instalar-ca`, que solo genera la CA interna y el certificado LDAPS si faltan o van a caducar. Después comprueba que `ca.crt`, `ldap.crt` y `ldap.key` existan en `servicios/ca/certs/` como **ficheros no vacíos**.
   2. **Zona DNS** (`generar_zona`): genera `servicios/bind9/zones/db.reservaviva.local` desde la plantilla `.tpl`, con la IP fija de cada contenedor. Si solo cambia el serial, conserva el fichero anterior.
   3. **Validación** del compose (`docker compose config -q`).
   4. **Imagen de OpenVPMS**: se reconstruye siempre (con caché tarda segundos). Sin red, solo acepta la imagen existente si su `entrypoint.sh` e `init-lib.sh` son idénticos a los del repositorio.
4. **`up -d`** de los 25 servicios. Si la zona es más nueva que el contenedor `dns-interno`, lo reinicia para que bind9 la lea (`reiniciar_dns_si_zona_nueva`).
5. **Espera a que todo esté sano** (`esperar_sano`). Cada 20 s imprime `[mm:ss] sanos N/25 - esperando: …`. Los tres trabajos de un solo disparo (`erpnext-configurator`, `erpnext-create-site` y `erpnext-ldap-config`) cuentan como sanos cuando terminan con código 0. El límite es de 45 min (`-TimeoutMin` / `--timeout`).
6. **Administrador de Pretix** (`crear_admin_pretix`): crea el de `PRETIX_ADMIN_EMAIL` y borra el `admin@localhost` que trae la imagen.
7. **Accesos**: imprime las URL y los usuarios.

**Primer arranque y siguientes.** El primero descarga imágenes e inicializa los volúmenes: OpenVPMS crea su esquema y carga los datos base, ERPNext crea su sitio, y Pretix e InvenTree migran. Es el lento. Con los volúmenes ya inicializados, los siguientes solo arrancan los contenedores y tardan unos minutos.

**Si se corta es reanudable.** Volver a ejecutar `arrancar` es seguro y retoma donde quedó: la inicialización de OpenVPMS y la creación del sitio de ERPNext se reanudan, y los demás pasos son idempotentes. No hace falta `borrar` para "empezar limpio".

## 4. Tras reiniciar el PC

Al reiniciar Windows se apaga la VM de WSL y con ella Docker y los contenedores. Basta con **volver a ejecutar `levantar-sistema.cmd` o `.\levantar-sistema.ps1`**: como los volúmenes ya están inicializados, es un arranque de los "siguientes".

Por qué hay que hacerlo desde Windows con Docker Engine en WSL: si no queda ninguna sesión de WSL abierta, Docker se detiene y se lleva los contenedores. Por eso el `.ps1` deja en segundo plano un proceso llamado **`reservaviva-keepalive`**, que mantiene viva la sesión aunque cierres la ventana:

- Lo abren `arrancar`, `preparar`, `estado` y `verificar`. Lo cierran `detener` y `borrar` cuando terminan bien.
- Si arrancas con `./levantar-sistema.sh` desde una terminal de WSL, no hay keepalive: el script avisa de que no cierres esa terminal.
- Con Docker Desktop no hace falta, porque no se usa.

## 5. Diagnóstico

**Leer `estado`.** Lo normal con el sistema sano son 22 servicios `running` (`Up …`, con `(healthy)` los que tienen sonda de salud) y los tres trabajos de ERPNext en `exited` con `Exited (0)`. Un `Exited` con código distinto de 0, `(unhealthy)` o un contador de reinicios que sube indican un problema.

**Diagnóstico automático.** Si durante la espera un servicio falla (unhealthy, terminado, más de 3 reinicios o un trabajo con código ≠ 0) o se agota el tiempo, `arrancar` muestra `docker compose ps -a` y las **últimas 40 líneas de log** de cada servicio implicado, y termina con error. No hay una acción `diagnostico` aparte: es parte de `arrancar`.

**Logs a mano.** Dentro de WSL (`wsl -d <distro>`), desde la raíz del repositorio (por ejemplo `/mnt/d/…`):

```bash
docker compose --env-file sistema/test.env ps -a
docker compose --env-file sistema/test.env logs --tail 100 <servicio>
```

`<servicio>` es el nombre del compose, que no siempre coincide con el del contenedor: `dns` (contenedor `dns-interno`) y `ntp` (`ntp-interno`).

**Un servicio lleva mucho en `starting`.** En el primer arranque es normal: la base de OpenVPMS tiene un `start_period` de 10 min, y el sitio de ERPNext tarda. Mira sus logs. Si avanzan, espera, o relanza con más margen (`.\levantar-sistema.ps1 -TimeoutMin 90` / `./levantar-sistema.sh --timeout 90`). Relanzar no pierde lo hecho.

**Un servicio `unhealthy`.** Lee sus logs y vuelve a ejecutar `arrancar`. Si es una app que depende de LDAP (`inventree-app` o `erpnext-backend`), revisa también `openldap` y los certificados (siguiente punto).

**Falta `ca.crt` o es un directorio.** Si un fichero de un montaje no existe, Docker crea en su lugar un **directorio vacío**, y LDAPS falla sin avisar. `preparar` lo detecta y aborta con `Falta servicios/ca/certs/<fichero> (o esta vacio)`. Pasa si alguien lanzó `docker compose up` sin `preparar`. Borra ese directorio desde WSL (lo creó Docker como root, así que puede hacer falta `sudo`) y vuelve a ejecutar `preparar` o `arrancar`.

## 6. Liberar memoria y apagar

- **`detener`** es la forma normal de apagar y de liberar la RAM. Para los contenedores (`stop`), conserva volúmenes y contenedores, y en modo WSL cierra el keepalive. `arrancar` lo vuelve a levantar en minutos.
- **`borrar`** ejecuta `down -v`: **destruye los volúmenes**, es decir, las bases de datos, el sitio de ERPNext, el directorio LDAP y los datos de Pretix e InvenTree. El siguiente arranque vuelve a inicializarlo todo, como el primero. Úsalo solo si de verdad quieres partir de cero. **No existe un `down -v` "seguro"**, y `-Si` / `--si` quita incluso la confirmación.
- `docker compose down` **sin** `-v` borra los contenedores pero conserva los datos: es lo que hace la prueba de persistencia de `verificar`.

## 7. Trampas conocidas de Windows/WSL

| Síntoma | Causa | Qué hacer |
|---|---|---|
| Los contenedores desaparecen al rato de cerrar todas las terminales | La VM de WSL se apaga tras `vmIdleTimeout` (60 s por defecto) | `vmIdleTimeout=7200000` en `.wslconfig` (sección 1) y `wsl --shutdown` con el sistema detenido |
| Los contenedores se paran al cerrar la última terminal de WSL | Sin ninguna sesión de WSL, `docker.service` se desactiva y los mata | Arranca con el `.ps1` / `.cmd`, que mantiene `reservaviva-keepalive`, o deja una terminal de WSL abierta |
| Mediciones de memoria o de arranque incoherentes | Cada `wsl.exe` nuevo puede reactivar el demonio de Docker | Mide desde una sola sesión de WSL que siga abierta |
| Un comando lanzado con `wsl.exe -d <distro> -- …` se comporta distinto que dentro de WSL | Pasa por el shell del usuario, que expande `$variables` | `wsl.exe -d <distro> --exec bash -c '…'` con comillas simples |
| En Git Bash, un argumento que empieza por `/` llega convertido en ruta de Windows | Conversión automática de rutas de MSYS | `MSYS_NO_PATHCONV=1` delante del comando |
| (Si modificas el `.ps1`) `Start-Process wsl.exe` sale al instante con −1 | El nombre de la distro va entre comillas en `-d "…"` | Pásalo sin comillas; los nombres de distro no tienen espacios |
| (Si modificas el `.ps1`) cualquier aviso de `wsl.exe` corta el script | PowerShell 5.1 con `$ErrorActionPreference='Stop'` trata el stderr nativo como error | Deja `'Continue'` y comprueba `$LASTEXITCODE` |
| `grep` no encuentra en un log texto que se ve a simple vista | Salida mezclada UTF-8/UTF-16 (`wsl.exe` escribe UTF-16) | `tr -d '\000'` antes de `grep` |
| Un cambio en `servicios/openvpms/` no tiene efecto tras `docker compose up -d` | `up -d` no reconstruye una imagen con `build:` | Usa `levantar-sistema` (`preparar` o `arrancar`), que siempre reconstruye `openvpms-app` |
| `generar-certificados.sh` fallaba con "Operation not permitted" en la segunda ejecución | OpenLDAP (osixia) se apropia de los certificados montados (uid 911) | Ya resuelto: el script solo cambia permisos de lo que genera. Para regenerarlos, `--forzar` |
| Un `.sh` falla con `$'\r': command not found` | La copia de trabajo de Windows es CRLF (`core.autocrlf=true`) | `.gitattributes` fuerza LF en `*.sh`, `Dockerfile` y `*.service`. Al editarlos en Windows, conserva LF |
| El progreso de `arrancar` o `verificar` parece parado en `[00:07]` | `erpnext-ldap-config` se vuelve a ejecutar en cada `up` y hay que esperarlo | Es normal. Espera; el contador sigue cada 20 s |
| `estado` no termina y parece colgado | Consultar los 25 servicios a través de `wsl.exe` puede llevar varios minutos | Espera. Si lo lanzas desde otra herramienta con límite de tiempo, dale más margen o ejecútalo en segundo plano |

### Al comprobar las aplicaciones

| Síntoma | Causa | Qué hacer |
|---|---|---|
| Pretix responde **400** en `http://127.0.0.1:18082` | Pretix solo acepta el `Host` de su URL propia (`PRETIX_PRETIX_URL`, que es `localhost`) | Entra siempre por `http://localhost:18082` ([aplicaciones.md](aplicaciones.md#pretix-taquilla-y-boletería)) |
| `curl` a la página de una aplicación da 200 y aun así la interfaz no carga | En una SPA (como `/web` de InvenTree) el HTML llega aunque sus JS o CSS fallen; así pasó H22 | Abre la página en el navegador y mira su consola, o pide un asset referenciado por el HTML y comprueba que su `content-type` no sea `text/html`. `verificar` no lo comprueba (ver los pendientes de [`resultados-un-host.md`](resultados-un-host.md#pendientes)) |

## 8. Validación

**Ejecutar `verificar`** con el sistema arriba y sano:

```text
.\levantar-sistema.ps1 verificar            ./levantar-sistema.sh verificar
.\levantar-sistema.ps1 verificar -Rapido    ./levantar-sistema.sh verificar --rapido
```

- **Completo** (por defecto): segmentación, DNS, NTP y LDAP/LDAPS, e incluye la prueba de persistencia (caso 4 de `ldaplogin.py`: `down` sin `-v` + `up -d`, y se repiten los logins).
- **Rápido**: omite la persistencia y deja **siempre un FAIL deliberado**, "caso 4 … NO EJECUTADO", así que termina con código ≠ 0. Sirve para iterar, no como validación final.

**Resultados.** Cada comprobación imprime `[PASS]`, `[FAIL]` o `[INFO]` con la salida en la que se apoya. `INFO` son hallazgos que hay que leer y no cuentan como fallo, como el tráfico entre apps por la VLAN 99. El resultado es válido solo si `ExecMainStartTimestamp` de Docker es el mismo antes y después; si cambia, repite. El script termina con `Verificacion superada` solo si no hay ningún FAIL. Cómo interpretar cada bloque se explica en [`sistema/verificar_arquitectura.md`](../sistema/verificar_arquitectura.md).

**Informe:** `sistema/resultados/verificacion-AAAAMMDD-HHMMSS.txt` (fuera de git). La referencia vigente (número de PASS e INFO) está en [`resultados-un-host.md`](resultados-un-host.md#verificación-de-la-arquitectura-levantar-sistema-verificar).

**Protocolo para quien cambie la configuración** (compose, `test.env` o ficheros de `servicios/`):

1. Antes de tocar nada, dentro de WSL y desde la raíz, guarda la configuración resuelta **fuera del repositorio**: `docker compose --env-file sistema/test.env config > /tmp/config-antes.yml`. Contiene las contraseñas resueltas: no la subas ni la compartas.
2. Haz el cambio, repite el comando en `/tmp/config-despues.yml` y ejecuta `diff /tmp/config-antes.yml /tmp/config-despues.yml`. **Solo deben cambiar las líneas que pretendías cambiar.**
3. `arrancar` (con el sistema arriba, aplica el cambio en poco tiempo) y después `verificar` **completo**: 0 FAIL, código 0 y el mismo `ExecMainStartTimestamp`, con el mismo número de PASS que la referencia salvo que el cambio añada comprobaciones.
4. Para liberar memoria entre pruebas usa `detener`, nunca `borrar`.
5. Si tocas la inicialización de OpenVPMS o el bloque `erpnext-create-site`, ejecuta también sus pruebas sin Docker: `bash servicios/openvpms/test-reanudable.sh` y `bash servicios/erpnext/test-create-site.sh`.
