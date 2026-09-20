# Despliegue oficial: tres PC Windows con Docker Desktop (redes bridge)

> **Estado: NO VERIFICADO.** Los tres `docker-compose.yml` se adaptaron sin poder ejecutarlos (el motor Docker no estaba
> disponible). Nada de lo que sigue se ha probado en los PC del laboratorio. Los comandos de Windows son de referencia y
> hay que comprobarlos en el primer despliegue.

## Decisión y límite conocido

Los PC del laboratorio son tres equipos **Windows físicos**, cada uno con Docker Desktop (WSL2). Ahí no arrancan ni
`macvlan` ni las sub-interfaces 802.1Q, así que **se renuncia a VLAN, macvlan y matriz de segmentación**. Es una
limitación conocida y decidida: el laboratorio ya no demuestra segmentación L2/L3. Los scripts `setup-vlans-*.sh`,
`firewall-pc3-matriz.sh` y `despliegue/*/` se conservan **como anexo de diseño** (cómo se habría segmentado con hardware
real); no se ejecutan en Windows.

## Cómo queda la red

- Cada `docker-compose.yml` crea redes **bridge locales** a su motor (mismos nombres y subredes 10.10.NN.0/24 que antes).
  Un contenedor de PC-1 **no** alcanza el `10.10.99.10` de PC-3: esas redes no existen fuera de cada PC.
- Entre PC y desde otros equipos se usa la **IP LAN real** del PC y **puertos publicados** en `0.0.0.0`:

| PC | Puertos publicados (por defecto) |
|---|---|
| PC-1 | 8080 (OpenVPMS, `/openvpms/login`) |
| PC-2 | 80 (Pretix), 8000 (InvenTree) |
| PC-3 | 8080 (ERPNext), 389 y 636 (OpenLDAP), 53 tcp/udp (bind9), 123/udp (NTP) |

- PC-1 y PC-2 llevan en su `.env` **`IP_PC3`** (IP LAN de PC-3). PC-2 lleva además **`IP_PC2`** (su propia IP, para las URL
  de Pretix e InvenTree). El `.env.example` trae un valor que **no es una IP** a propósito, para que `docker compose`
  falle en vez de arrancar mal si no se sustituye.
- Puertos y direcciones se parametrizan (`*_PORT`, `PUBLISH_IP`, `DNS_BIND_IP`). Si `10.10.NN.x` choca con la LAN del
  laboratorio, `NET_MEDICA`, `NET_TAQUILLA`, `NET_LOGISTICA`, `NET_RRHH` y `NET_INFRA` cambian el prefijo de cada bridge.
  Comprobar la LAN con `ipconfig` antes del primer arranque.
- **LDAPS debe seguir en el 636** de PC-3 (`ldaps://ldap.reservaviva.local:636`); no cambies `LDAPS_PORT` salvo en el arnés.
- `erpnext-backend` (PC-3) se conecta también al bridge `vlan99_infra` para llegar a OpenLDAP, porque sin gateway entre
  redes ya no hay otro camino dentro del mismo motor.

## Choques de puertos con Windows (a comprobar, no asumidos)

Antes de `docker compose up` en PC-3, en PowerShell **como administrador**:

```powershell
Get-NetUDPEndpoint -LocalPort 53,123 | Select LocalAddress,LocalPort,OwningProcess
Get-NetTCPConnection -LocalPort 53,389,636,8080 -State Listen -ErrorAction SilentlyContinue
Get-Process -Id <OwningProcess>          # quién es
```

- **123/udp**: lo suele ocupar el servicio de hora de Windows (`w32time`). Opciones: `NTP_PORT=1123` en el `.env` (pero
  es probable que `w32tm` no admita un puerto distinto del 123: sin verificar) o parar el servicio en PC-3:
  `Stop-Service w32time; Set-Service w32time -StartupType Disabled`. **Decisión pendiente:** se recomienda parar
  `w32time` solo en PC-3 y anotarlo; hay que confirmarlo en el laboratorio.
- **53/udp**: lo suele ocupar la Conexión compartida a Internet (ICS, servicio `SharedAccess`), sobre todo en la red
  "Default Switch" de Hyper-V/WSL. Solución sin parar nada: `DNS_BIND_IP=<IP LAN de PC-3>` para publicar el 53 solo en esa
  dirección. Si aun así choca: `Stop-Service SharedAccess`.

## Firewall de Windows

En el PC que publica cada puerto, PowerShell como administrador (ajusta `-RemoteAddress` a la LAN del laboratorio):

```powershell
# PC-3
New-NetFirewallRule -DisplayName "RV LDAP/LDAPS" -Direction Inbound -Protocol TCP -LocalPort 389,636 -Action Allow -RemoteAddress LocalSubnet
New-NetFirewallRule -DisplayName "RV ERPNext"    -Direction Inbound -Protocol TCP -LocalPort 8080    -Action Allow -RemoteAddress LocalSubnet
New-NetFirewallRule -DisplayName "RV DNS tcp"    -Direction Inbound -Protocol TCP -LocalPort 53      -Action Allow -RemoteAddress LocalSubnet
New-NetFirewallRule -DisplayName "RV DNS udp"    -Direction Inbound -Protocol UDP -LocalPort 53      -Action Allow -RemoteAddress LocalSubnet
New-NetFirewallRule -DisplayName "RV NTP"        -Direction Inbound -Protocol UDP -LocalPort 123     -Action Allow -RemoteAddress LocalSubnet
# PC-2
New-NetFirewallRule -DisplayName "RV Pretix/InvenTree" -Direction Inbound -Protocol TCP -LocalPort 80,8000 -Action Allow -RemoteAddress LocalSubnet
# PC-1
New-NetFirewallRule -DisplayName "RV OpenVPMS" -Direction Inbound -Protocol TCP -LocalPort 8080 -Action Allow -RemoteAddress LocalSubnet
```

## Certificados (agujero de la Fase 0)

`docker/*/certs/` está en `.gitignore`: **no viene con el repositorio**. Sin `ca.crt` y `ldap.crt/key` no hay LDAPS.
`scripts/generar-certificados.sh` necesita `bash` y `openssl`; en Windows, **Git Bash**. Se ejecuta **una vez, en PC-3**;
después hay que copiar `ca.crt` (nunca `ca.key`) a `docker/pc2-operaciones/certs/ca.crt`. PC-1 no lo necesita (OpenVPMS no
usa LDAP). Si falta el archivo, Docker crea un *directorio* con ese nombre y InvenTree arranca sin verificar nada.

## Datos que contradicen la documentación anterior

- **`ldap.reservaviva.local` lo resuelven los `extra_hosts`, no bind9.** Los contenedores usan el DNS de Docker; bind9
  solo sirve a clientes externos. En PC-2 apunta a `IP_PC3`; en PC-3 (mismo motor que OpenLDAP) va directo al bridge.
- **`openvpms-app` no usa LDAP** (OpenVPMS 2.4.0.1 no lo soporta) y sus `LDAP_HOST`/`DNS_HOST`/`NTP_HOST` son variables
  que nada lee. Ahora valen `IP_PC3` los tres.
- **`bind9` sigue sirviendo IP 10.10.NN.M** en `docker/pc3-administracion-infra/bind/zones/db.reservaviva.local`, que en
  este modelo no son alcanzables desde otros equipos. **Pendiente:** cambiarlas a las IP LAN reales (la zona no admite
  variables de entorno).

## Pendiente (no incluido en este cambio)

- **Entrada de despliegue para Windows.** Los `deploy.sh` son bash con `sudo` e `ip link`. Falta el equivalente (`.ps1` o
  instrucciones de `docker compose up`) y debe **replicar `init_admins` de `docker/pc2-operaciones/deploy.sh`**: crea el
  administrador de Pretix y **elimina el `admin@localhost` con clave `admin`** que trae por defecto. Sin ese paso, Pretix
  queda con credenciales conocidas.
- Validar todo en Docker: `docker compose config`, arranque de cada PC, `ldaplogin.py` (rama `test/ldaplogin-revalidacion`) y
  el arnés de `pruebas/smoke-test-3-pcs/` (su `test.env` fija `IP_PC3=10.10.99.10` y desplaza los puertos a localhost).
