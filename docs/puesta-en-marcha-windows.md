# Puesta en marcha en el laboratorio: tres PCs Windows con Docker Desktop

> **Estado de este documento: borrador con huecos marcados.** Los huecos (`HUECO:`) son cosas que todavía no están decididas o probadas; **no los rellenes con suposiciones**. Está escrito sin poder ejecutar Docker (el almacén de Docker de la máquina de desarrollo está en migración), así que **nada de lo que aquí aparece como comando se ha probado en este documento**; lo probado se dice expresamente.

## 1. Qué es y qué no es esto

Cada uno de los tres PCs corre las aplicaciones de sus departamentos en contenedores. Los PCs son **Windows con Docker Desktop** (ya instalado, con WSL2), conectados a la misma red del laboratorio. Los contenedores se ven entre PCs porque cada PC **publica** los puertos que hacen falta en su dirección de la red (no hay VLANs, ni `macvlan`, ni switch configurado).

| PC | Departamentos | Aplicaciones | Puertos que publica (en `0.0.0.0`) |
|---|---|---|---|
| PC-1 | Unidad Médica Veterinaria | OpenVPMS | `8080` |
| PC-2 | Taquilla + Logística | Pretix, InvenTree | `80` (Pretix), `8000` (InvenTree) |
| PC-3 | RR. HH. + Infraestructura | ERPNext HR, OpenLDAP, bind9, NTP | `8080` (ERPNext), `389` y `636` (LDAP/LDAPS), `53/udp` (DNS), `123/udp` (NTP) |

El diseño de red con VLANs y switch **no se ejecuta en este laboratorio**: se presenta como diseño propuesto y su lógica se demuestra con el simulador (apartado 7). La tabla de qué está ejecutado, simulado y solo diseñado está en el [README raíz](../README.md).

## 2. Antes de ir

No hace falta instalar Docker Desktop ni activar WSL2: los PCs ya los tienen.

El primer día habrá Internet limitada, así que el paquete de preparación previa es una **red de seguridad**, no una condición imprescindible. Conviene llevarlo igualmente. El USB contiene:

- Las **imágenes** de las aplicaciones en ficheros `.tar`, guardadas **por etiqueta**.
- El **proyecto** (este repositorio) en un `.zip`.
- Los **certificados ya generados**: para PC-3, `ca.crt`, `ca.key`, `ldap.crt` y `ldap.key`; para PC-1 y PC-2, solo `ca.crt`. Los tres PCs usan **la misma CA**. **No hay que copiar `ca.crt` entre PCs por la red.**
- Los ficheros de *override* de Compose de cada PC, generados en la preparación.
- `MANIFEST.sha256` (para comprobar que nada se corrompió al copiar) e `INVENTARIO.tsv` (qué imagen va con qué perfil).
- La imagen **`nicolaka/netshoot`** (~900 MB), necesaria solo para la demostración del apartado 7.
- El instalador de PowerShell, que se invoca `.\instalar.ps1 -Perfil pc1|pc2|pc3` y **solo carga las imágenes de ese perfil**. Deja en disco el proyecto, las imágenes, los certificados y el override, y remite a este documento; **no arranca los contenedores** (eso lo hace el `deploy.ps1` de cada PC, apartado 4).

> **HUECO: nombres y parámetros exactos de `instalar.ps1` y de `deploy.ps1`.** Se copian aquí cuando estén cerrados y probados. Pendiente también: verificar que las imágenes cargadas con `docker load` satisfacen las referencias con digest (`nombre:etiqueta@sha256:…`) de los compose; si no, Docker intentaría descargarlas.

## 3. La red del laboratorio

**Averigua la dirección de cada PC en la red** (no la conocemos hasta estar allí). En cada PC, abre PowerShell y ejecuta:

```powershell
ipconfig
```

Busca el adaptador que está conectado a la red del laboratorio (el que tiene «Puerta de enlace predeterminada») y anota su **«Dirección IPv4»**. Rellena esta tabla en el laboratorio; **no copies direcciones de otros documentos**, las `10.10.X.X` que aparecen en el repositorio son direcciones **internas de Docker**, no las de la red:

| PC | IP en la red del laboratorio |
|---|---|
| PC-1 | `<IP-LAN-DE-PC-1>` = ______________ |
| PC-2 | `<IP-LAN-DE-PC-2>` = ______________ |
| PC-3 | `<IP-LAN-DE-PC-3>` = ______________ |

Comprueba que los tres se ven entre sí (desde cada PC hacia los otros dos):

```powershell
ping <IP-LAN-DE-PC-3>
```

Cada PC necesita conocer alguna de estas direcciones; se guardan en su `.env` (ver apartado 4):

| PC | Variables de IP que rellena | Para qué |
|---|---|---|
| PC-1 | `IP_PC3` | llegar al LDAP de PC-3 |
| PC-2 | `IP_PC3` y `IP_PC2` | `IP_PC3`: llegar al LDAP. `IP_PC2`: su **propia** IP, que Pretix e InvenTree usan para construir sus URL (`PRETIX_PRETIX_URL`, `INVENTREE_SITE_URL`); si no se rellena, el arranque **falla con un mensaje explícito** en vez de arrancar mal |
| PC-3 | `DNS_BIND_IP` (su **propia** IP) | publicar el puerto 53 (bind9) solo en esa dirección. Su valor por defecto es `0.0.0.0`, pero conviene poner la IP real: así el puerto 53 no choca con el servicio de «Conexión compartida a Internet» (ICS) de Windows |

PC-3 **no** lee `IP_PC3` (solo aparece en comentarios de su compose).

## 4. Preparar cada PC (orden recomendado: PC-3, PC-2, PC-1)

PC-3 va primero porque los otros dos dependen de su LDAP cuando arrancan las aplicaciones.

Pasos comunes a cada PC:

1. **Abre Docker Desktop** y espera a que indique que está en marcha.
2. **Copia el paquete** del USB a una carpeta del PC y abre PowerShell dentro de ella.
3. **Configura el `.env`** de tu PC (copia `.env.example` a `.env` y edítalo con el Bloc de notas: `notepad .env`):
   - Contraseñas: cámbialas por otras propias, sin espacios, y anótalas.
   - Las variables de IP de la tabla del apartado 3 que correspondan a tu PC, con las direcciones que anotaste (por ejemplo, `IP_PC3=<IP-LAN-DE-PC-3>`). Ahora mismo el `.env.example` trae `SUSTITUIR-POR-LA-IP-REAL-DE-PC2` como marcador: **sustitúyelo**.
   - Ya **no** se usan `IFACE`, `PERFIL` ni `IP_GESTION` (eran del diseño con VLANs).
   - Claves con reglas propias: `OPENVPMS_ADMIN_PASSWORD` (PC-1) mínimo 8 caracteres con mayúscula, minúscula, número y un carácter especial; `INVENTREE_LDAP_BIND_PASSWORD` y `ERPNEXT_LDAP_BIND_PASSWORD` deben quedar en **`Svc-Lectura1`** (es la del LDIF de laboratorio).
4. **Instala el paquete** (carga las imágenes de tu perfil y deja todo en disco):

```powershell
.\instalar.ps1 -Perfil pc3      # o pc2, o pc1
```

5. **Arranca los servicios** con el `deploy.ps1` de tu PC. Valida el `.env` y el `ca.crt`, arranca con `docker compose` y espera a que los contenedores estén sanos.

> **HUECO: nombre y parámetros exactos de `deploy.ps1`.** Cuando se cierren, se escribe aquí el comando.

> **MUY IMPORTANTE (solo PC-2): el administrador de Pretix.** Pretix trae por defecto un usuario `admin@localhost` con la clave `admin`. `deploy.sh` lo borraba y creaba el administrador propio; `deploy.ps1` replica ese paso (`init_admins`, incluido el borrado de `admin@localhost`). **Si ese paso no se completa, Pretix queda accesible con credenciales públicas desde toda la red**, porque ahora el puerto 80 se publica en `0.0.0.0`. Tras el arranque de PC-2, **comprueba que ese paso terminó bien** (el script debe decir que creó el administrador) y, si el aviso dice que Pretix no quedó listo a tiempo, **repítelo** antes de dejar el PC conectado a la red. Comprobación manual: intenta entrar en Pretix con `admin@localhost` / `admin`; **debe fallar**.

Tiempos de primer arranque medidos en la prueba de humo (un solo host): **PC-3 ~13 min** (lo marca `erpnext-create-site`), **PC-2 ~10 min** (migraciones de Pretix e InvenTree), **PC-1 ~5 min** (OpenVPMS prepara su base de datos). No lo interrumpas aunque parezca colgado.

## 5. Verificar cada PC

Desde la carpeta del PC, en PowerShell:

```powershell
docker compose ps
```

> **HUECO: comando exacto de `docker compose`.** Si el paquete exige un fichero de *override*, hay que añadirlo con `-f` (lo indicará el instalador).

Esperado:

- **PC-1:** `openvpms-db` y `openvpms-app` en `Up`. `openvpms-app` puede reiniciarse los primeros minutos mientras inicializa la base.
- **PC-2:** `pretix-db`, `pretix-redis`, `pretix-web`, `inventree-db`, `inventree-app` e `inventree-worker` en `Up`.
- **PC-3:** todo en `Up`, **salvo tres** contenedores que **deben** decir `Exited (0)`: `erpnext-configurator`, `erpnext-create-site` y `erpnext-ldap-config`. Son tareas que corren una sola vez y terminan; que aparezcan así es lo normal. (Las recetas antiguas solo mencionaban dos.)

Comprobación de acceso **desde otro PC de la red** (es la prueba que importa; desde el propio PC también debería abrir con `http://localhost:PUERTO`, pero eso no demuestra que los demás lleguen):

| Servicio | Dirección | Esperado |
|---|---|---|
| OpenVPMS | `http://<IP-LAN-DE-PC-1>:8080/openvpms/login` | pantalla de inicio de sesión |
| Pretix | `http://<IP-LAN-DE-PC-2>/` | responde (200 o 302) |
| InvenTree | `http://<IP-LAN-DE-PC-2>:8000/api/` | responde |
| ERPNext | `http://<IP-LAN-DE-PC-3>:8080/api/method/ping` | responde tras ~10 min del primer arranque |

Para ver el código de respuesta desde PowerShell:

```powershell
(Invoke-WebRequest -UseBasicParsing http://<IP-LAN-DE-PC-3>:8080/api/method/ping).StatusCode
```

> **Nota (Pretix e InvenTree):** las URL que usan estas dos aplicaciones para enlaces, redirecciones y orígenes de confianza CSRF se construyen con `IP_PC2` (`PRETIX_PRETIX_URL: http://${IP_PC2}:${PRETIX_PORT:-80}`, `INVENTREE_SITE_URL: http://${IP_PC2}:${INVENTREE_PORT:-8000}`). Por eso hay que rellenar `IP_PC2` en el `.env` de PC-2 (apartado 4); sin ella el compose se niega a arrancar. **HUECO: confirmar en el laboratorio que el inicio de sesión de InvenTree y las redirecciones de Pretix funcionan entrando por esa IP.**

## 6. Comprobaciones entre PCs (desde fuera de los contenedores)

Hazlas desde **otro equipo de la red**, o desde un PC distinto del que corre el servicio, apuntando a `<IP-LAN-DE-PC-3>`. Los contenedores **no usan bind9** para resolverse entre ellos (usan el DNS interno de Docker y `extra_hosts`); bind9 atiende solo a clientes externos, así que **se prueba desde fuera**, nunca desde dentro de un contenedor.

**Puertos de PC-3 abiertos** (TCP):

```powershell
Test-NetConnection <IP-LAN-DE-PC-3> -Port 636
Test-NetConnection <IP-LAN-DE-PC-3> -Port 389
```

Esperado: `TcpTestSucceeded : True`.

**DNS** (bind9, zona `reservaviva.local`):

```powershell
nslookup ldap.reservaviva.local <IP-LAN-DE-PC-3>
```

Esperado: responde con una dirección. **Ojo:** la zona contiene las direcciones internas `10.10.X.X`, no las de la red; la prueba solo demuestra que bind9 contesta.

**NTP:**

```powershell
w32tm /stripchart /computer:<IP-LAN-DE-PC-3> /samples:1 /dataonly
```

Esperado: una línea con el desfase, sin error.

**LDAP autenticado** (usa la imagen de OpenLDAP que ya está cargada como herramienta, con la cuenta de búsqueda; ejecutar en la carpeta del paquete):

```powershell
docker run --rm --entrypoint ldapsearch osixia/openldap:1.5.0 -x -H ldap://<IP-LAN-DE-PC-3>:389 -D "cn=svc-lectura,ou=servicios,dc=reservaviva,dc=local" -w Svc-Lectura1 -b "dc=reservaviva,dc=local" "(uid=rrhh.prueba)"
```

Esperado: devuelve una entrada `uid=rrhh.prueba`.

**LDAPS con la CA interna** (comprueba también la cadena de certificados; la ruta a `ca.crt` es la del paquete):

```powershell
docker run --rm --add-host ldap.reservaviva.local:<IP-LAN-DE-PC-3> -v "${PWD}\docker\pc3-administracion-infra\certs\ca.crt:/ca.crt:ro" -e LDAPTLS_CACERT=/ca.crt --entrypoint ldapsearch osixia/openldap:1.5.0 -x -H ldaps://ldap.reservaviva.local:636 -D "cn=svc-lectura,ou=servicios,dc=reservaviva,dc=local" -w Svc-Lectura1 -b "dc=reservaviva,dc=local" "(uid=rrhh.prueba)"
```

Esperado: la misma entrada. **No se ha probado este comando** (los dos anteriores de `ldapsearch` tampoco desde Windows); el certificado de OpenLDAP incluye el nombre `ldap.reservaviva.local`, por eso se usa ese nombre con `--add-host`. Si falla con un error de certificado, revisa que `ca.crt` sea el mismo del USB en los tres PCs.

## 7. Demostración de la segmentación: el simulador

Este es el apartado que demuestra en directo el diseño de red con VLANs. El simulador monta, dentro de **un solo contenedor** sin red (`--privileged --network none`), una réplica de la topología con *namespaces* de red de Linux: un *bridge* con `vlan_filtering` hace de switch 802.1Q; PC-1 va en puerto *access* (VLAN 10), PC-2 y PC-3 en *trunk*; hay un contenedor de servicio por VLAN (10, 20, 30, 40 y 99). Después aplica la matriz de segmentación y comprueba **las 20 celdas** (5 VLANs × 4 destinos). No toca la red del PC ni levanta las aplicaciones. Se ejecutó en Docker Desktop sobre Windows (WSL2, kernel 6.6.87) y funcionó.

**Qué demuestra y qué no** (dilo así al evaluador):

- Demuestra que la política de la matriz es **realizable** y que se aplica: las **12 combinaciones negocio ↔ negocio** se **descartan** y **cada bloqueo sube el contador de su propia regla**; la comunicación con la VLAN 99 (LDAPS 636) funciona.
- La matriz que se implementa hoy es «negocio ↔ negocio bloqueado; el resto (incluido negocio ↔ VLAN 99) abierto». **No** implementa «VLAN 99 solo responde» ni restringe por servicio.
- Prueba el **kernel de Linux**, no un switch físico ni `macvlan` sobre una tarjeta real. Solo se prueba TCP.

**Requisitos:** Docker Desktop en marcha y la imagen `nicolaka/netshoot` cargada (viene en el paquete). Comprueba su nombre con `docker image ls`.

**Perfil L3** (el switch enruta y aplica las reglas; en el simulador, las reglas `nftables` van en el «switch»). Desde la carpeta raíz del proyecto, en PowerShell:

```powershell
docker run --rm --privileged --network none -v "${PWD}:/repo:ro" nicolaka/netshoot bash /repo/despliegue/l3-switch/pruebas/simular-l3.sh
```

**Perfil L2** (el switch solo conmuta; PC-3 enruta y filtra). Con los **scripts reales** del repositorio (`setup-vlans-pc3.sh` y `firewall-pc3-matriz.sh`), que es la versión que conviene enseñar:

```powershell
docker run --rm --privileged --network none -v "${PWD}:/repo:ro" -e RV_SETUP_PC3=/repo/despliegue/l2-fallback/scripts/setup-vlans-pc3.sh -e RV_FIREWALL_PC3=/repo/despliegue/l2-fallback/scripts/firewall-pc3-matriz.sh nicolaka/netshoot bash /repo/despliegue/l2-fallback/pruebas/simular-l2.sh
```

> Los README de los simuladores citan la imagen con `@sha256:…`. Si la imagen llegó por `docker load` (por etiqueta), usa el nombre que muestre `docker image ls`, como arriba. En Git Bash de Windows añade `MSYS_NO_PATHCONV=1` delante y usa `"$PWD:/repo:ro"`. Tarda unos 30 segundos.

**Cómo leer la salida** (de arriba abajo):

1. **Comprobaciones previas:** una línea por VLAN con `escucha :8080` (o `:636` en la 99) y `gateway 10.10.X.1 alcanza`. Todas deben salir bien; así, un fallo posterior significa «bloqueado por la red» y no «no había nadie».
2. **Matriz de segmentación:** una tabla 5×5 con `✅ Permitido` y `❌ Bloqueado`. **Esperado:** `❌ Bloqueado` en las 12 celdas negocio ↔ negocio (10, 20, 30, 40 entre sí) y `✅ Permitido` en las que tocan la VLAN 99. Una celda con `⚠️ FALLA` es un resultado inesperado.
3. **Contadores de las reglas:** una tabla `regla / paquetes / bytes`. **Cada regla `drop-ORIGEN-DESTINO` debe tener paquetes > 0** (en la verificación documentada, 4 paquetes cada una: el SYN y sus reintentos) y **`drop-resto` debe valer 0**. Esa es la evidencia de que el bloqueo lo hizo **su** regla y no otra causa.
4. **Última línea:** `RESULTADO: las 20 celdas dan lo esperado.` (código de salida 0).

En el perfil L2 con los scripts reales, al final se imprime además la tabla `nft` real (`nft list table inet reservaviva`): 12 reglas con comentarios `VLAN20 -> VLAN30 bloqueado`, etc., cada una con su `counter packets N bytes M`. Se puede enseñar que cada pareja de VLAN tiene **su** contador.

## 8. Que sobreviva a un reinicio

- En Docker Desktop, activa **«Start Docker Desktop when you sign in»** (Configuración → General). Los contenedores llevan `restart: unless-stopped`, así que vuelven a arrancar solos cuando Docker arranca.
- Docker Desktop arranca al **iniciar sesión** de Windows, no al encender el PC. **Tras un reinicio, alguien debe iniciar sesión** para que los contenedores vuelvan; si el PC se queda en la pantalla de inicio de sesión, no arrancan. Es una decisión deliberada: no se configura inicio de sesión automático en equipos compartidos del laboratorio, porque sería un problema de seguridad mayor que la molestia que evita. Avisa al operador.
- Tras un apagón general, enciende **primero PC-3** (LDAP, DNS y NTP), luego PC-2 y PC-1.
- Los servicios `systemd` del repositorio (`scripts/systemd/`) son del diseño Linux y **no se usan aquí**.

## 9. Problemas típicos de Windows

| Síntoma | Qué mirar |
|---|---|
| Desde el propio PC no abre `http://10.10.X.X…` | Es normal: las direcciones `10.10.X.X` son internas de Docker y no se alcanzan desde Windows. Usa `http://localhost:PUERTO` en el propio PC, o la IP de la red desde otro PC. |
| Otro PC no llega al servicio | El **Firewall de Windows Defender** puede bloquear el puerto publicado. Comprueba la regla de entrada de Docker Desktop; si hace falta, crea una regla de entrada para ese puerto (requiere administrador). |
| `docker compose` dice que el puerto `53` o `123` ya está en uso (PC-3) | Otro programa de Windows ocupa el puerto UDP (el servicio de «Conexión compartida a Internet» suele ocupar el 53). Comprueba que en el `.env` de PC-3 `DNS_BIND_IP` es la **IP real de PC-3** y no `0.0.0.0`. Averigua qué lo ocupa con `Get-NetUDPEndpoint -LocalPort 53,123` y avisa al equipo técnico antes de parar nada. |
| Un contenedor aparece `Restarting` | Espera unos minutos si es primer arranque; luego `docker compose logs NOMBRE-DEL-SERVICIO`. |
| Falla algo relacionado con saltos de línea en un script | El repositorio fuerza `LF` en `*.sh`, `Dockerfile` y `*.service` (`.gitattributes`); si copiaste los ficheros por otra vía (p. ej. editándolos con el Bloc de notas), pueden haberse convertido a `CRLF`. |
| Docker Desktop va lento o se queda sin memoria | La prueba de humo con los tres PCs en **un solo host** usó ~7 GB de RAM para Docker; cada PC por separado necesita menos. Revisa la memoria asignada en Docker Desktop (Configuración → Resources). |

## 10. Limitaciones conocidas

Estas cosas **no** forman parte del laboratorio y están documentadas como diseño:

- VLANs 802.1Q, `macvlan`, el switch físico (perfiles L2 y L3) y su configuración Cisco.
- La copia de `ca.crt` con `scp` entre PCs (aquí viene en el USB).
- `IP_GESTION`, `PERFIL` e `IFACE`.
- Los servicios `systemd`.
- La captura de tramas 802.1Q con Wireshark en un trunk.

Lo que se ha ejecutado y lo que solo se ha simulado está en el [README raíz](../README.md#estado-de-validación) y en [`prueba-smoke-test-resultados.md`](prueba-smoke-test-resultados.md).
