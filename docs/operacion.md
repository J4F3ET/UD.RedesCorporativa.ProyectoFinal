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

Esta configuración usa la red NAT de WSL, que basta para el modo local. El modo intranet necesita además
`networkingMode=mirrored`, que añade el script de la sección "Acceso desde la LAN".

## 2. Arranque rápido y acciones

| Desde | Comando |
|---|---|
| Explorador de Windows | Doble clic en `levantar-sistema.cmd` (al terminar espera una tecla) |
| PowerShell | `.\levantar-sistema.ps1 [acción] [-Forzar] [-Rapido] [-Si] [-TimeoutMin <min>] [-Distro <distro>] [-Intranet [-IP <X.X.X.X>]]` |
| `cmd.exe` | `levantar-sistema.cmd [acción] [opciones del .ps1]` |
| bash (WSL, Linux) | `./levantar-sistema.sh [acción] [--forzar] [--rapido] [--si] [--timeout <min>] [--intranet [--ip <X.X.X.X>]]` |

Sin acción se ejecuta `arrancar`. Si PowerShell bloquea el script, usa el `.cmd` o `powershell -ExecutionPolicy Bypass -File .\levantar-sistema.ps1`. La ayuda sale con `.\levantar-sistema.ps1 ayuda` o `./levantar-sistema.sh --help`.

| Acción | Qué hace | Cuánto tarda (orientativo) | ¿Borra datos? |
|---|---|---|---|
| `arrancar` | Requisitos, memoria, `preparar`, `up -d`, espera a que todo esté sano y crea el administrador de Pretix | Primer arranque: más de media hora con las imágenes ya descargadas, y la primera vez hay que sumar su descarga (varios GB). Con el sistema ya arriba, alrededor de un minuto | No |
| `preparar` | Solo lo previo: certificados, zonas DNS, LDIF de LDAP, validación del compose e imagen de OpenVPMS. No arranca nada | Segundos, salvo la primera construcción de la imagen | No |
| `estado` | Tabla de servicios (servicio, estado, detalle), **modo de publicación** (local o intranet, con la IP y el puerto del proxy y del DNS) y direcciones de acceso | De segundos a varios minutos (desde Windows, a través de WSL, es cuando más tarda) | No |
| `verificar` | Ejecuta [`sistema/verificar_arquitectura.py`](../sistema/verificar_arquitectura.py) y guarda un informe. Con `-Rapido` / `--rapido` omite la prueba de persistencia | Completo: un cuarto de hora aproximadamente (incluye `down` + `up -d`). Rápido: bastante menos | No (el completo para y levanta los contenedores sin `-v`) |
| `detener` | `docker compose stop`: para los contenedores y conserva todo | Segundos | No |
| `borrar` | `docker compose down -v --remove-orphans`: contenedores, redes **y volúmenes**. Pide escribir `borrar` (o `-Si` / `--si`) | Segundos, pero el siguiente arranque reinicializa todo (el script avisa de unos 30 min) | **Sí, todos** |

Las cifras medidas están en [`resultados-un-host.md`](resultados-un-host.md). Al terminar, `arrancar` y `estado` muestran las direcciones de acceso. Las contraseñas de laboratorio están en [`sistema/test.env`](../sistema/test.env).

**Modo local y modo intranet.** Por defecto (`arrancar` sin opciones) el sistema está en **modo local**: todo se publica
en `127.0.0.1` y solo se entra desde el propio equipo. Con `-Intranet` / `--intranet` pasa a **modo intranet**: el proxy
web (80) y el DNS (53 para los clientes; con Docker Engine en WSL, a través de un reenviador de Windows) se publican en
la IP de la LAN y otros equipos entran por nombre (siguiente apartado). El modo no
se guarda en ningún fichero: un `arrancar` sin la opción vuelve al modo local, y `estado`, `preparar` y `verificar`
detectan el modo en que está el sistema y lo conservan.

### Acceso desde la LAN

Sirve para que cualquier equipo de la LAN abra las cuatro aplicaciones por su nombre, resuelto por el DNS del
laboratorio:

| Aplicación | Dirección desde otro equipo |
|---|---|
| OpenVPMS | http://openvpms.reservaviva.lan (lleva a `/openvpms/`) |
| Pretix | http://pretix.reservaviva.lan |
| InvenTree | http://inventree.reservaviva.lan |
| ERPNext (RRHH) | http://rrhh.reservaviva.lan |

**Antes de nada: el riesgo.** Las contraseñas de laboratorio están **públicas en git** ([`sistema/test.env`](../sistema/test.env)).
En modo intranet cualquiera en la misma red puede entrar como administrador en las cuatro aplicaciones. Úsalo solo en una
red de laboratorio y vuelve al modo local al terminar ([`seguridad.md`](seguridad.md#modo-intranet-qué-se-expone-y-por-qué-es-opcional)).

**Qué hace falta en Windows (una vez).** Docker corre dentro de la VM de WSL. Con la red NAT de WSL (la de por defecto)
la distro tiene una IP `172.x` que los demás equipos no alcanzan, y Docker ni siquiera puede publicar en la IP de la LAN.
Hacen falta tres cosas, que prepara [`sistema/habilitar-intranet-windows.ps1`](../sistema/habilitar-intranet-windows.ps1):

1. `networkingMode=mirrored` en `%UserProfile%\.wslconfig`: la distro comparte las interfaces de Windows. El script hace
   copia de seguridad y solo añade o cambia esa clave, con un comentario, sin tocar el resto. Requiere Windows 11 22H2 o
   posterior.
2. Reglas de entrada del **Firewall de Windows** para 80/tcp y 53/udp+tcp, solo desde la subred local y en todos los
   perfiles (una Wi-Fi en perfil "Pública" también cuenta).
3. Las mismas reglas en el **firewall de Hyper-V** para la VM de WSL (`New-NetFirewallHyperVRule`, con el `VMCreatorId`
   de WSL), que en modo mirrored es el que filtra lo que entra a la distro.

El script también informa de quién tiene el puerto 53 en Windows. En el equipo de medida lo tienen el servicio
**SharedAccess** (Conexión compartida a Internet, ICS, en `0.0.0.0:53/udp`) y **Portmaster** (`portmaster-core`, en
`[::]:53`, un cortafuegos de aplicaciones que además filtra conexiones entrantes). El script no detiene ni reconfigura
ninguno: muestra los comandos para ICS y los pasos para Portmaster.

**Pasos del usuario:**

1. En PowerShell **como administrador**, desde la raíz del repositorio:
   `powershell -ExecutionPolicy Bypass -File .\sistema\habilitar-intranet-windows.ps1`
   (con `-Comprobar` solo informa, sin cambiar nada y sin ser administrador).
2. Si el script cambió `.wslconfig`: `wsl --shutdown`. Para la VM de WSL y todos los contenedores (los datos se
   conservan). Después, comprueba dentro de WSL que la distro sigue resolviendo nombres (`apt update`): con Tailscale en
   Windows, el DNS de WSL ya dio problemas en este equipo (ver los comentarios de `.wslconfig`).
3. Si el script avisó de ICS o de Portmaster en el 53, sigue sus indicaciones.
4. `.\levantar-sistema.ps1 -Intranet -Forzar`. Detecta la IP de la LAN (la de la ruta por defecto de Windows); otra se
   indica con `-IP X.X.X.X`. Antes de tocar nada comprueba que WSL está en mirrored, que la IP está en la distro, que el
   80 y el 1053 están libres en ella dentro de WSL y que el 53 de Windows está libre para el reenviador (siguiente
   apartado); si algo falla dice quién ocupa el puerto y qué hacer, y no cambia nada. Si Docker no puede publicar,
   explica la causa y vuelve a dejar el proxy y el DNS en `127.0.0.1`.
5. Al terminar, el lanzador arranca el reenviador DNS, comprueba que responde y muestra las cuatro URL, la IP del DNS y
   cómo configurarla en los clientes.

**El reenviador DNS de Windows (Docker Engine en WSL).** Con WSL en `networkingMode=mirrored`, **Windows no entrega a
Linux el tráfico que llega a su puerto 53**. Se comprobó con un servidor mínimo dentro de WSL, ligado a la IP de la LAN:
recibe UDP y TCP desde Windows en el puerto 54, en el 1053 o en el 5453, pero en el 53 Windows responde "puerto
inalcanzable" por UDP y rechaza la conexión TCP, sin que nada escuche en ese puerto en Windows; el 80 del proxy sí llega.
Por eso, en modo intranet con Docker Engine en WSL:

- `dns-interno` se publica en `<IP de la LAN>:1053` (no en el 53);
- [`sistema/reenviador-dns.ps1`](../sistema/reenviador-dns.ps1), un proceso de Windows sin ventana, escucha en
  `<IP de la LAN>:53` (UDP y TCP) y pasa cada consulta tal cual a `<IP de la LAN>:1053`, y la respuesta de vuelta. Los
  clientes siguen usando el 53 y no notan nada.

Lo gestiona el lanzador de Windows, sin pasos a mano:

- `.\levantar-sistema.ps1 -Intranet` lo arranca tras el arranque, guarda su PID en `sistema\.reenviador-dns.pid`
  (ignorado por git) y hace una consulta A de `pretix.reservaviva.lan` a `<IP>:53`, que debe devolver la IP. Si ya hay
  uno vivo para la misma IP no lanza otro; si hay uno de otra IP, lo sustituye. Si el 53 de Windows está ocupado
  (ICS/`SharedAccess`, Portmaster…), dice quién lo tiene y remite a `habilitar-intranet-windows.ps1`.
- `detener`, `borrar` y un `arrancar` en modo local lo paran. Sobrevive al cierre de la ventana, pero no a un reinicio:
  tras reiniciar el PC basta con volver a ejecutar `.\levantar-sistema.ps1 -Intranet`.
- **Cómo ver que está vivo:** `.\levantar-sistema.ps1 estado` termina con el apartado "Reenviador DNS de Windows": PID,
  `<IP>:53 -> <IP>:1053` y el resultado de una consulta de prueba. `verificar` (bloque 4) consulta la ruta completa por
  el 53, por UDP y por TCP, además del 1053. A mano: `nslookup pretix.reservaviva.lan <IP>` desde Windows.
- No necesita administrador: las reglas de entrada de 53/udp y 53/tcp que crea `habilitar-intranet-windows.ps1` son por
  puerto, no por programa, y le sirven.
- Si se lanza `./levantar-sistema.sh --intranet` directamente dentro de WSL, el DNS queda en el 1053 y nadie arranca el
  reenviador: el script lo avisa. Se arranca con `.\levantar-sistema.ps1 -Intranet` o a mano:
  `powershell -ExecutionPolicy Bypass -File .\sistema\reenviador-dns.ps1 -IP <IP>` (con `-Registro <archivo>` anota el
  origen de cada consulta UDP, para diagnóstico).
- Con Docker Desktop (publica desde Windows) o en Linux nativo no hace falta: el DNS se publica directamente en el 53.

Las cifras de la prueba (ráfaga de consultas, tiempos) están en
[`resultados-un-host.md`](resultados-un-host.md#dns-desde-la-lan-con-wsl-mirrored-reenviador-27092026).

**Configurar el DNS de los clientes.** Los nombres `*.reservaviva.lan` solo los conoce el DNS del laboratorio, que
escucha en la IP de la LAN del equipo anfitrión, puerto 53. Dos formas:

- **En cada cliente**, a mano: DNS preferido = la IP del anfitrión (Windows: Configuración > Red e Internet > propiedades
  del adaptador > Asignación de servidor DNS > Manual). Ese DNS **no hace recursión**: con él como único DNS, el cliente
  solo resuelve `reservaviva.lan`. Pon un segundo DNS (el del router o uno público) para Internet; ten en cuenta que
  algunos sistemas preguntan al segundo sin esperar al primero, y entonces `reservaviva.lan` puede fallar de forma
  intermitente.
- **Para toda la LAN**, en el DHCP del router: DNS primario = la IP del anfitrión. Misma advertencia sobre la recursión.
  Conviene además reservar esa IP para el anfitrión en el router, porque si cambia hay que volver a arrancar con
  `-Intranet`.

**Lista de comprobación por tipo de cliente** (aprendida probando con el iPhone y los navegadores del usuario):

- **iPhone** (Ajustes > Wi-Fi > (i) de la red > Configurar DNS > Manual): **solo** la IP del anfitrión, sin otros
  servidores. Desactivar el **Relay privado** de iCloud y **Limitar rastreo de dirección IP** en esa Wi-Fi: los dos
  hacen que Safari no use el DNS de la Wi-Fi. Probar en **Safari**.
- **Brave y Chrome** (en cualquier sistema) tienen su propio **DNS seguro** (DNS sobre HTTPS) que se salta el DNS de la
  Wi-Fi: desactivarlo (Configuración > Privacidad y seguridad > Seguridad > "Usar DNS seguro") o probar con otro
  navegador.
- **Android**: Ajustes > Red > **DNS privado** = desactivado; si no, el DNS de la Wi-Fi no se usa.
- Con este DNS como **único** servidor, el cliente **no resuelve Internet** (no hace recursión): es lo esperado. Al
  terminar, volver a DNS automático.

**El propio anfitrión no es un buen cliente del DNS.** El equipo que aloja el sistema no puede usarse a sí mismo como
servidor DNS de forma fiable: su Wi-Fi recibe del router un DNS IPv6 (`fe80::1`, "gpon.net" en el equipo de medida) que
Windows prefiere al IPv4 manual, así que `*.reservaviva.lan` falla aunque se ponga la IP a mano. En el anfitrión, usa el
archivo `hosts` (`<IP> pretix.reservaviva.lan`, una línea por nombre; siguiente párrafo) o prueba desde otro equipo.
`nslookup <nombre> <IP>` sí sirve en el anfitrión para comprobar el servidor, porque pregunta directamente a esa IP.

**Pruebas desde otro equipo de la LAN** (sustituye `192.168.1.13` por la IP del anfitrión):

1. `ping 192.168.1.13` (puede fallar sin que sea un problema: las reglas solo abren 80 y 53, no ICMP).
2. `nslookup pretix.reservaviva.lan 192.168.1.13` → debe responder `192.168.1.13`. Igual con `openvpms`, `inventree`,
   `rrhh` y `dns`. `nslookup ldap.reservaviva.lan 192.168.1.13` debe dar "Non-existent domain" (a propósito).
3. `nslookup example.com 192.168.1.13` → "Query refused": el DNS no hace recursión.
4. Sin tocar el DNS del cliente, `Test-NetConnection 192.168.1.13 -Port 80` (Windows) y `curl.exe -H "Host:
   pretix.reservaviva.lan" http://192.168.1.13/control/login` → deben responder (el segundo, con el HTML del login).
   Aísla el proxy del DNS.
5. Con el DNS del cliente apuntando al anfitrión, abrir en el navegador las cuatro URL de la tabla y llegar a la página
   de login de cada aplicación, con su aspecto normal (hojas de estilo cargadas).
6. `http://192.168.1.13` a secas → página 404 del proxy que lista los nombres válidos.

Si falla el paso 2 o el 4, el orden de sospechosos es: el reenviador DNS no está vivo (solo afecta al paso 2; ver
`estado`), WSL no está en mirrored (`wsl.exe --exec wslinfo --networking-mode` debe decir `mirrored`), el firewall de
Hyper-V, Portmaster y el Firewall de Windows. En el propio anfitrión, `.\levantar-sistema.ps1 estado` muestra en qué IP
y puerto publica cada uno y si el reenviador está vivo y responde.

**Probar el DNS desde el propio anfitrión con Portmaster activo da un falso negativo.** Medido el 27/09: con el DNS
publicado en la IP de WSL, `nslookup pretix.reservaviva.lan <IP>` desde Windows devolvió NXDOMAIN con la marca de
recursión activa y resolvió `example.com`, cosas que nuestro bind9 nunca hace: Portmaster intercepta las consultas DNS
salientes del equipo y responde él. La misma consulta hecha desde dentro de WSL dio la respuesta correcta. El DNS se
prueba desde otro equipo de la LAN (o con Portmaster en pausa); el proxy web no se ve afectado. Con Docker Engine en WSL,
preguntar a `<IP>:53` sin el reenviador vivo también engaña: la consulta no llega a bind9 (Windows no entrega el 53 a
WSL). Mira primero `estado`.

**Volver al modo local:** `.\levantar-sistema.ps1 -Forzar` (sin `-Intranet`). Recrea solo el proxy y el DNS en
`127.0.0.1` y para el reenviador DNS. Para deshacer también la preparación de Windows: el script con `-Deshacer` (quita las reglas y restaura
`networkingMode`) y después `wsl --shutdown`.

**Acceso por nombre desde el propio anfitrión.** En modo local el proxy también funciona, en `127.0.0.1:80`, pero
Windows no puede usar un DNS en el puerto 1053. Para probar los nombres en el anfitrión basta con una línea por nombre en
`C:\Windows\System32\drivers\etc\hosts` (`127.0.0.1 pretix.reservaviva.lan`), o `curl -H "Host: pretix.reservaviva.lan"
http://127.0.0.1/`. El acceso directo `http://localhost:1808x` no cambia en ningún modo.

## 3. Qué pasa en un arranque

`arrancar` ejecuta, en este orden:

1. **Requisitos** (`comprobar_requisitos`): `docker` responde, Compose ≥ 2.24.4 y `openssl` presente.
2. **Modo** (`resolver_modo`): local, o intranet con `--intranet`. En modo intranet, además, las comprobaciones previas (`comprobar_intranet`): WSL en mirrored, la IP presente en la distro y los puertos 80 y del DNS libres en ella (el 1053 con Docker Engine en WSL, el 53 en los demás casos; el 53 de Windows lo comprueba antes el `.ps1`). Si algo falla, se detiene sin tocar ningún contenedor.
3. **Memoria** (`comprobar_memoria`). En Windows, el `.ps1` ya ha comprobado antes la memoria libre del equipo.
4. **`preparar`**:
   1. **Certificados** (`preparar_certificados`): ejecuta [`servicios/ca/generar-certificados.sh`](../servicios/ca/generar-certificados.sh) `--sin-instalar-ca`, que solo genera la CA interna y el certificado LDAPS si faltan, van a caducar o su SAN no cubre `ldap.reservaviva.lan`. Después comprueba que `ca.crt`, `ldap.crt` y `ldap.key` existan en `servicios/ca/certs/` como **ficheros no vacíos**.
   2. **Zonas DNS** (`generar_zona`): genera las dos zonas de `reservaviva.lan` (vista interna, con la IP fija de cada contenedor, y vista lan, con la IP del anfitrión del modo elegido) y la ACL de la vista interna, desde las plantillas de `servicios/bind9/zones/`. Si solo cambia el serial, conserva el fichero anterior.
   3. **LDIF de LDAP** (`generar_ldif`): genera en `servicios/openldap/generado/` (fuera de git) los LDIF del primer arranque del directorio, a partir de las plantillas `servicios/openldap/*.ldif.tpl` y de las claves de `sistema/test.env` (`LDAP_SVC_LECTURA_PASSWORD` y `LDAP_PRUEBA_<UID>_PASSWORD`), que guarda como hash `{SSHA}`. Si falta una de esas variables se detiene con `definir <VARIABLE> en sistema/test.env`. Se regenera en cada `preparar`, pero OpenLDAP solo lo carga con el directorio vacío: en un sistema ya inicializado no cambia nada ([`seguridad.md`](seguridad.md#3-ldap-y-ldaps)).
   4. **Validación** del compose (`docker compose config -q`).
   5. **Imagen de OpenVPMS**: se reconstruye siempre (con caché tarda segundos). Sin red, solo acepta la imagen existente si su `entrypoint.sh` e `init-lib.sh` son idénticos a los del repositorio.
5. **Publicación en la LAN** (solo en modo intranet, `publicar_intranet`): `up -d` solo de `proxy` y `dns`. Si Docker no puede publicar en la IP de la LAN, explica la causa (puerto 53 ocupado por ICS o Portmaster, IP ausente…), vuelve a publicarlos en `127.0.0.1` y termina con error.
6. **`up -d`** de los 26 servicios. Antes reinicia los contenedores que un arranque anterior dejó `unhealthy` (`reiniciar_unhealthy`), porque `up -d` no los recrearía y abortaría enseguida. `up -d` respeta los `depends_on` con `service_healthy`: en un primer arranque casi toda la espera ocurre aquí, sin el progreso del paso 7 ni su límite de tiempo. Si `named.conf`, una zona o la ACL son más nuevos que el contenedor `dns-interno`, lo reinicia para que bind9 los lea (`reiniciar_dns_si_zona_nueva`); si el certificado de OpenLDAP es más nuevo que el contenedor `openldap`, lo recrea con los mismos volúmenes y reinicia sus dos clientes LDAPS, `inventree-app` y `erpnext-backend`, y después `erpnext-hr`, cuyo nginx resuelve la IP del backend solo al arrancar (`recrear_ldap_si_cert_nuevo`): la imagen solo copia sus certificados en el primer arranque de cada contenedor, así que reiniciarlo no bastaría, y los procesos de InvenTree siguieron fallando hasta reiniciarlos ([`seguridad.md`](seguridad.md#cuándo-se-regenera-y-cuándo-no)).
7. **Espera a que todo esté sano** (`esperar_sano`). Cada 20 s imprime `[mm:ss] sanos N/26 - esperando: …`. Los tres trabajos de un solo disparo (`erpnext-configurator`, `erpnext-create-site` y `erpnext-ldap-config`) cuentan como sanos cuando terminan con código 0. El límite es de 45 min (`-TimeoutMin` / `--timeout`).
8. **Administrador de Pretix** (`crear_admin_pretix`): crea el de `PRETIX_ADMIN_EMAIL` y borra el `admin@localhost` que trae la imagen.
9. **Accesos**: imprime el modo, las URL y los usuarios; en modo intranet, también la IP del DNS para los clientes y el aviso de las claves públicas.
10. **Reenviador DNS** (solo el `.ps1`, en modo intranet con Docker Engine en WSL): lo arranca o reutiliza y comprueba que responde; en modo local lo para ([Acceso desde la LAN](#acceso-desde-la-lan)).

**Primer arranque y siguientes.** El primero descarga imágenes e inicializa los volúmenes: OpenVPMS crea su esquema y carga los datos base, ERPNext crea su sitio, OpenLDAP carga los LDIF de `generado/`, y Pretix e InvenTree migran. Es el lento. Con los volúmenes ya inicializados, los siguientes solo arrancan los contenedores y tardan unos minutos.

**Si se corta es reanudable.** Volver a ejecutar `arrancar` es seguro y retoma donde quedó: la inicialización de OpenVPMS y la creación del sitio de ERPNext se reanudan, un contenedor que quedó `unhealthy` se reinicia, y los demás pasos son idempotentes. No hace falta `borrar` para "empezar limpio".

## 4. Tras reiniciar el PC

Al reiniciar Windows se apaga la VM de WSL y con ella Docker y los contenedores. Basta con **volver a ejecutar `levantar-sistema.cmd` o `.\levantar-sistema.ps1`**: como los volúmenes ya están inicializados, es un arranque de los "siguientes".

Por qué hay que hacerlo desde Windows con Docker Engine en WSL: si no queda ninguna sesión de WSL abierta, Docker se detiene y se lleva los contenedores. Por eso el `.ps1` deja en segundo plano un proceso llamado **`reservaviva-keepalive`**, que mantiene viva la sesión aunque cierres la ventana:

- Lo abren `arrancar`, `preparar`, `estado` y `verificar`. Lo cierran `detener` y `borrar` cuando terminan bien.
- Si arrancas con `./levantar-sistema.sh` desde una terminal de WSL, no hay keepalive: el script avisa de que no cierres esa terminal.
- Con Docker Desktop no hace falta, porque no se usa.

En modo intranet, el reenviador DNS de Windows tampoco sobrevive al reinicio: se vuelve a ejecutar
`.\levantar-sistema.ps1 -Intranet` (sin `-Intranet` el sistema vuelve al modo local). Tras el reinicio, Docker tarda unos
minutos en responder dentro de WSL mientras restaura los contenedores; el lanzador se queda en "Buscando Docker" y es
normal.

## 5. Diagnóstico

**Leer `estado`.** Lo normal con el sistema sano son 23 servicios `running` (`Up …`, con `(healthy)` los que tienen sonda de salud) y los tres trabajos de ERPNext en `exited` con `Exited (0)`. Debajo, el modo de publicación y dónde publican `proxy-web` y `dns-interno`. Un `Exited` con código distinto de 0, `(unhealthy)` o un contador de reinicios que sube indican un problema.

**Diagnóstico automático.** Si durante la espera un servicio falla (unhealthy, terminado, más de 3 reinicios o un trabajo con código ≠ 0) o se agota el tiempo, `arrancar` muestra `docker compose ps -a` y las **últimas 40 líneas de log** de cada servicio implicado, y termina con error. No hay una acción `diagnostico` aparte: es parte de `arrancar`.

**Logs a mano.** Dentro de WSL (`wsl -d <distro>`), desde la raíz del repositorio (por ejemplo `/mnt/d/…`):

```bash
docker compose --env-file sistema/test.env ps -a
docker compose --env-file sistema/test.env logs --tail 100 <servicio>
```

`<servicio>` es el nombre del compose, que no siempre coincide con el del contenedor: `dns` (contenedor `dns-interno`), `ntp` (`ntp-interno`) y `proxy` (`proxy-web`).

**Un servicio lleva mucho en `starting`.** En el primer arranque es normal: la base de OpenVPMS tiene un `start_period` de 10 min, y el sitio de ERPNext tarda. Mira sus logs. Si avanzan, espera, o relanza con más margen (`.\levantar-sistema.ps1 -TimeoutMin 90` / `./levantar-sistema.sh --timeout 90`). Relanzar no pierde lo hecho.

**Un servicio `unhealthy`.** Lee sus logs y vuelve a ejecutar `arrancar`. Si es una app que depende de LDAP (`inventree-app` o `erpnext-backend`), revisa también `openldap` y los certificados (siguiente punto).

**Falta `ca.crt` o es un directorio.** Si un fichero de un montaje no existe, Docker crea en su lugar un **directorio vacío**, y LDAPS falla sin avisar. `preparar` lo detecta y aborta con `Falta servicios/ca/certs/<fichero> (o esta vacio)`. Pasa si alguien lanzó `docker compose up` sin `preparar`. Borra ese directorio desde WSL (lo creó Docker como root, así que puede hacer falta `sudo`) y vuelve a ejecutar `preparar` o `arrancar`.

## 6. Liberar memoria y apagar

- **`detener`** es la forma normal de apagar y de liberar la RAM. Para los contenedores (`stop`), conserva volúmenes y contenedores, y en modo WSL cierra el keepalive y el reenviador DNS. `arrancar` lo vuelve a levantar en minutos.
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
| `estado` no termina y parece colgado | Consultar los 26 servicios a través de `wsl.exe` puede llevar varios minutos | Espera. Si lo lanzas desde otra herramienta con límite de tiempo, dale más margen o ejecútalo en segundo plano |
| `-Intranet` se detiene con "WSL esta en modo de red 'nat'" | La red NAT de WSL no tiene la IP de la LAN | `sistema\habilitar-intranet-windows.ps1` como administrador y `wsl --shutdown` (sección "Acceso desde la LAN") |
| Tras volver a arrancar sin `-Intranet`, los otros equipos ya no entran | `arrancar` sin la opción es el modo local: recrea el proxy y el DNS en `127.0.0.1` | Es lo previsto. Para seguir en la LAN, arranca siempre con `-Intranet` |

### Al comprobar las aplicaciones

| Síntoma | Causa | Qué hacer |
|---|---|---|
| Pretix responde **400** en `http://127.0.0.1:18082` | Pretix solo acepta el `Host` de su URL propia (`PRETIX_PRETIX_URL`, que es `pretix.reservaviva.lan`) o `localhost` | Entra por `http://localhost:18082` o por `http://pretix.reservaviva.lan` ([aplicaciones.md](aplicaciones.md#pretix-taquilla-y-boletería)) |
| `curl` a la página de una aplicación da 200 y aun así la interfaz no carga | En una SPA (como `/web` de InvenTree) el HTML llega aunque sus JS o CSS fallen; así pasó H22 | Abre la página en el navegador y mira su consola, o pide un asset referenciado por el HTML y comprueba que su `content-type` no sea `text/html`. `verificar` lo hace para las cuatro aplicaciones, por nombre y por `localhost` (bloque 4) |
| Un nombre `*.reservaviva.lan` responde **502** | La aplicación todavía está arrancando: el proxy no espera a nadie | Espera a que `estado` la muestre sana |
| Un nombre responde con la página 404 del proxy | El nombre está mal escrito o se entró por la IP | Usa uno de los cuatro nombres de la tabla de "Acceso desde la LAN" |

## 8. Validación

**Ejecutar `verificar`** con el sistema arriba y sano:

```text
.\levantar-sistema.ps1 verificar            ./levantar-sistema.sh verificar
.\levantar-sistema.ps1 verificar -Rapido    ./levantar-sistema.sh verificar --rapido
```

- **Completo** (por defecto): segmentación, DNS, NTP, acceso por nombre (vista lan del DNS, proxy web con página y estático de cada aplicación, acceso directo por `localhost`) y LDAP/LDAPS, e incluye la prueba de persistencia (caso 4 de `ldaplogin.py`: `down` sin `-v` + `up -d`, y se repiten los logins). Respeta el modo en que esté el sistema: en modo intranet, el `up -d` de la persistencia lo deja en modo intranet.
- **Rápido**: omite la persistencia y deja **siempre un FAIL deliberado**, "caso 4 … NO EJECUTADO", así que termina con código ≠ 0. Sirve para iterar, no como validación final.

**Resultados.** Cada comprobación imprime `[PASS]`, `[FAIL]` o `[INFO]` con la salida en la que se apoya. `INFO` son hallazgos que hay que leer y no cuentan como fallo, como el tráfico entre apps por la VLAN 99. El resultado es válido solo si `ExecMainStartTimestamp` de Docker es el mismo antes y después; si cambia, repite. El script termina con `Verificacion superada` solo si no hay ningún FAIL. Cómo interpretar cada bloque se explica en [`sistema/verificar_arquitectura.md`](../sistema/verificar_arquitectura.md).

**Informe:** `sistema/resultados/verificacion-AAAAMMDD-HHMMSS.txt` (fuera de git). La referencia vigente (número de PASS e INFO) está en [`resultados-un-host.md`](resultados-un-host.md#verificación-de-la-arquitectura-levantar-sistema-verificar).

**Protocolo para quien cambie la configuración** (compose, `test.env` o ficheros de `servicios/`):

1. Antes de tocar nada, dentro de WSL y desde la raíz, guarda la configuración resuelta **fuera del repositorio**: `docker compose --env-file sistema/test.env config > /tmp/config-antes.yml`. Contiene las contraseñas resueltas: no la subas ni la compartas.
2. Haz el cambio, repite el comando en `/tmp/config-despues.yml` y ejecuta `diff /tmp/config-antes.yml /tmp/config-despues.yml`. **Solo deben cambiar las líneas que pretendías cambiar.**
3. `arrancar` (con el sistema arriba, aplica el cambio en poco tiempo) y después `verificar` **completo**: 0 FAIL, código 0 y el mismo `ExecMainStartTimestamp`, con el mismo número de PASS que la referencia salvo que el cambio añada comprobaciones.
4. Para liberar memoria entre pruebas usa `detener`, nunca `borrar`.
5. Si tocas la inicialización de OpenVPMS o el bloque `erpnext-create-site`, ejecuta también sus pruebas sin Docker: `bash servicios/openvpms/test-reanudable.sh` y `bash servicios/erpnext/test-create-site.sh`.
