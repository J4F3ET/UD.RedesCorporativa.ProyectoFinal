# Receta L2 — el switch solo conmuta; PC-3 enruta y aplica la matriz

Usa esta receta si el switch **no** tiene interfaces `VlanNN` con IP y no acepta `ip routing` ([cómo saberlo](../README.md)). Síguela de arriba abajo. En cada paso hay una comprobación: **no pases al siguiente hasta que la tuya dé el resultado esperado.**

**Idea en una línea:** el switch solo reparte tramas por VLAN. Ningún PC toca las 5 VLANs por sí solo, así que **PC-3 se convierte en el router** (router-on-a-stick): su trunk lleva las 5 VLANs, tiene la IP `10.10.X.1` de cada una, y una tabla `nftables` aplica la matriz. El gateway de cada VLAN deja de ser el switch y pasa a ser PC-3.

> **Estado: pendiente de hardware.** Nada de esto se ha ejecutado aún contra un switch real. Los tiempos de arranque de las aplicaciones son medidos (en un solo host, ver la sección de tiempos); los de configurar el switch y cablear no están medidos. Si algo no coincide con lo que dice aquí, anótalo: es información valiosa.

**Consecuencia práctica:** PC-3 es el punto único de fallo. Si PC-3 está apagado o caído, **no hay tráfico entre VLANs** (y ni PC-1 ni PC-2 llegan a LDAP).

## Lo que necesitas antes de empezar

- Los 3 PCs con Ubuntu Server, usuario con `sudo` y **Internet solo para instalar** (Docker, imágenes y el build de OpenVPMS, ~300 MB). Si el puerto del laboratorio no da Internet, hazlo en otra red **antes** de conectar al switch. Que el laboratorio permita esto está **pendiente de confirmar**.
- El switch, su cable de consola y sus credenciales.
- Un portátil con Linux y un cable de red (para las pruebas). Necesita `curl`, `dig`, `ldap-utils` y `ntpdate`.
- Un puerto libre del switch para el portátil (le llamaremos **puerto de pruebas**).
- Un USB (por si `scp` entre PCs no funciona, ver paso 5).
- Los nombres reales de los puertos del switch de cada PC. Anótalos: `PUERTO-PC1`, `PUERTO-PC2`, `PUERTO-PC3`, `PUERTO-PRUEBAS`.

## Resumen: qué pasa en cada paso y cuánto tarda

| # | Paso | Tiempo |
|---|---|---|
| 1 | Configurar el switch | sin medir |
| 2 | Cablear | sin medir |
| 3 | Preparar los 3 PCs (Docker, repo, `.env`) | sin medir |
| 4 | PC-3 (router + LDAP/DNS/NTP + ERPNext): `sudo ./deploy.sh` | **~13 min** el primer arranque completo (lo marca `erpnext-create-site`) |
| 5 | Copiar `ca.crt` a PC-1 y PC-2 | sin medir |
| 6 | PC-2: `sudo ./deploy.sh` | Pretix e InvenTree, **~10 min** de migraciones |
| 7 | PC-1: `sudo ./deploy.sh` | build de OpenVPMS **~2 min** y primer arranque **~5 min** |
| 8 | Pruebas por VLAN | sin medir |
| 9 | Evidencia | sin medir |
| 10 | Reinicio real | sin medir |

Los ~13 min son el primer arranque de los 3 PCs medido en **un solo host** con las tres pilas a la vez (22 contenedores); OpenVPMS corre en paralelo. En hardware real por separado puede variar. Los arranques posteriores son inmediatos. **No interrumpas** un arranque que "parece colgado" durante esos minutos: es normal.

---

## Paso 1 — Configurar el switch

Aquí el switch **no** enruta ni filtra. Solo se configura:

- VLANs 10, 20, 30, 40 y 99.
- Puerto de PC-1: **access** VLAN 10.
- Puerto de PC-2: **trunk** 802.1Q con VLAN 20 y 30 (igual que en el perfil L3).
- Puerto de PC-3: **trunk** 802.1Q con **las 5 VLANs: 10, 20, 30, 40 y 99**. Es la diferencia clave.
- La VLAN 999 sin uso, como VLAN nativa de los trunks.
- El **puerto de pruebas** del portátil **no viene en el archivo**: lo añades tú justo después (ver abajo).
- **Sin** SVIs, **sin** `ip routing`, **sin** ACL.

Todo eso está escrito para Cisco IOS en `despliegue/l2-fallback/switch/config-switch-l2.txt`. Ábrelo, cambia los nombres de puerto (`GigabitEthernet1/0/1`, `/2` y `/3` son solo **ejemplos**; el cableado propuesto es PC-1 → 1/0/1, PC-2 → 1/0/2, PC-3 → 1/0/3) por los reales (`show interfaces status` te los lista), y pégalo en la consola dentro de `configure terminal`. Al inicio del archivo hay un aviso: léelo. Al terminar, añade el puerto de pruebas (sustituye `PUERTO-PRUEBAS` por el puerto real; es un bloque de configuración, se pega entero):

```
interface PUERTO-PRUEBAS
 switchport mode access
 switchport access vlan 10
 no shutdown
end
```

Y guarda la configuración.

```
write memory
```

**Comprueba** (la guía larga está en `despliegue/l2-fallback/switch/verificacion.md`):

```
show vlan brief
```

Esperado: VLAN 10, 20, 30, 40 y 99 activas (más la 999, sin uso).

```
show interfaces trunk
```

Esperado: el puerto de PC-2 permite VLAN 20,30 y el de **PC-3 permite 10,20,30,40,99**. Si en PC-3 faltan la 10, 20 o 30, el router no verá esas VLANs.

```
show ip interface brief
```

Esperado: **ninguna** `Vlan10`…`Vlan99` con IP (como mucho `Vlan1` de gestión). Si aparecen, el switch es L3: cambia a [`../l3-switch/README.md`](../l3-switch/README.md).

Más comandos de evidencia en `despliegue/l2-fallback/switch/verificacion.md`.

**Evidencia a guardar:** captura o texto de estos tres comandos.

## Paso 2 — Cablear

| Cable | Puerto del switch |
|---|---|
| PC-1 | `PUERTO-PC1` (access VLAN 10) |
| PC-2 | `PUERTO-PC2` (trunk 20,30) |
| PC-3 | `PUERTO-PC3` (trunk 10,20,30,40,99) |

**Comprueba:** los tres puertos en `up`.

```
show interfaces status
```

Si alguno sale `notconnect`, revisa el cable y el nombre del puerto.

## Paso 3 — Preparar los 3 PCs

Repite esto en **cada PC**. Si ya tienen Docker y el repo, salta a "Crear el `.env`".

Instalar Docker (una vez, con Internet):

```
curl -fsSL https://get.docker.com | sudo sh
```

Descargar el proyecto:

```
git clone https://github.com/J4F3ET/UD.RedesCorporativaa.ProyectoFinak.git
```

Averiguar el nombre real de la tarjeta de red (no uses `lo`; suele ser `enp2s0`, `ens33`, `eth0`…):

```
ip -brief link show
```

**Comprueba:** tienes anotado el nombre de la NIC que va al switch en cada PC. `IFACE` ya no se asume `eth0`: pon el nombre real.

### Crear el `.env`

En cada PC, entra a su carpeta, copia el ejemplo y edítalo.

PC-1:

```
cd UD.RedesCorporativaa.ProyectoFinak/docker/pc1-medica
```

PC-2:

```
cd UD.RedesCorporativaa.ProyectoFinak/docker/pc2-operaciones
```

PC-3:

```
cd UD.RedesCorporativaa.ProyectoFinak/docker/pc3-administracion-infra
```

```
cp .env.example .env
```

```
nano .env
```

Valores (los que no aparecen, déjalos como están):

| Variable | PC-1 | PC-2 | PC-3 |
|---|---|---|---|
| `PERFIL` | `l2` | `l2` | `l2` |
| `IFACE` | NIC real de PC-1 | NIC real de PC-2 | NIC real de PC-3 |
| Contraseñas (`*_PASSWORD`) | cámbialas; anótalas | cámbialas; anótalas | cámbialas; anótalas |

`PERFIL=l2` va **igual en los tres PCs**.

Claves con reglas propias:

- PC-1: `OPENVPMS_ADMIN_PASSWORD` mínimo 8 caracteres con mayúscula, minúscula, número y un especial (por ejemplo `!`). Si no, OpenVPMS no arranca.
- PC-2 y PC-3: `INVENTREE_LDAP_BIND_PASSWORD` y `ERPNEXT_LDAP_BIND_PASSWORD` deben ser **`Svc-Lectura1`** (la del LDIF de laboratorio). Si las cambias, cámbialas también en `docker/pc3-administracion-infra/ldap/`.
- PC-3: `LDAP_ADMIN_PASSWORD`, `ERPNEXT_DB_ROOT_PASSWORD`, `ERPNEXT_ADMIN_PASSWORD`. Anótalas.

Guardar y salir de nano: `Ctrl+O`, `Enter`, `Ctrl+X`.

**Comprueba:** en cada PC, que `PERFIL=l2` esté escrito y sin espacios.

```
grep -E '^(PERFIL|IFACE)=' .env
```

## Paso 4 — PC-3 primero (router, LDAP, DNS, NTP y ERPNext)

PC-3 va primero: es el router de todo y los otros dos dependen de su LDAP y de su `ca.crt`. Desde `docker/pc3-administracion-infra`:

```
sudo ./deploy.sh
```

**Tiempo: ~13 min.** El script hace, en orden:

1. Valida `PERFIL`.
2. Crea las sub-interfaces `IFACE.10`, `.20` y `.30` con IP `10.10.X.1` (solo para enrutar).
3. Crea `IFACE.40` y `IFACE.99` (sin IP) y, colgadas de ellas, las interfaces `gw40` y `gw99` con `10.10.40.1` y `10.10.99.1`. (Existen porque, con macvlan, el propio PC no alcanza a sus contenedores por la interfaz padre.)
4. Activa `ip_forward`.
5. Aplica la tabla `nftables` con la matriz.
6. Genera los certificados de LDAPS y arranca los contenedores.

Casi todo el tiempo es `erpnext-create-site`. No hace falta que hagas nada.

**Comprueba:**

```
docker compose ps
```

Esperado: todo `Up`, salvo `erpnext-configurator` y `erpnext-create-site`, que **deben** decir `Exited (0)`.

```
ip -brief addr show
```

Esperado: `IFACE.10`, `IFACE.20`, `IFACE.30` con `10.10.X.1/24`, más `gw40` con `10.10.40.1/24` y `gw99` con `10.10.99.1/24`.

```
sysctl net.ipv4.ip_forward
```

Esperado: `net.ipv4.ip_forward = 1`.

```
sudo nft -a list ruleset
```

Esperado: una tabla `inet reservaviva` con 12 reglas `drop`, cada una con su contador (`counter packets 0 bytes 0` por ahora). Ojo: la opción `-a` va **antes** de `list`.

```
ls certs/ca.crt
```

Esperado: el archivo existe.

**Evidencia:** salida de `docker compose ps`, `ip -brief addr show` y `nft -a list ruleset` (con los contadores en 0).

## Paso 5 — Copiar `ca.crt` a PC-1 y PC-2

PC-1 y PC-2 necesitan la CA para confiar en LDAPS. El archivo es `docker/pc3-administracion-infra/certs/ca.crt`; hay que dejarlo en:

- PC-1: `docker/pc1-medica/certs/ca.crt`
- PC-2: `docker/pc2-operaciones/certs/ca.crt`

Opción rápida, desde PC-3, **solo si PC-2 tiene una IP en su NIC alcanzable** (ojo: en este diseño las sub-interfaces de PC-2 no llevan IP, así que puede no haberla):

```
scp certs/ca.crt USUARIO@IP-DE-PC2:UD.RedesCorporativaa.ProyectoFinak/docker/pc2-operaciones/certs/ca.crt
```

Opción segura: USB. Cópialo a un USB en PC-3 y luego a las dos carpetas. Si la carpeta `certs/` no existe en PC-1 o PC-2, créala dentro de la carpeta del PC (`docker/pc1-medica` o `docker/pc2-operaciones`).

```
mkdir -p certs
```

**Comprueba:** en PC-1 y PC-2 el archivo existe y es idéntico al de PC-3. Compara el hash en los tres.

```
sha256sum certs/ca.crt
```

Esperado: el mismo valor en los tres PCs.

## Paso 6 — PC-2 (Pretix + InvenTree)

Desde `docker/pc2-operaciones`:

```
sudo ./deploy.sh
```

**Tiempo: ~10 min** (cientos de migraciones de Pretix e InvenTree). Al final el script crea el administrador de Pretix. Si esa parte falla, se repite sola con:

```
sudo ./deploy.sh --solo-admins
```

PC-2 crea `IFACE.20` y `IFACE.30` sin IP. **No** le pongas gateway a mano: el gateway `10.10.X.1` de sus contenedores es PC-3 y lo fija el compose.

**Comprueba:**

```
docker compose ps
```

Esperado: todo `Up`.

```
ip -brief addr show
```

Esperado: `IFACE.20` y `IFACE.30` en `UP` y **sin** IP.

**Evidencia:** las dos salidas.

## Paso 7 — PC-1 (OpenVPMS)

Desde `docker/pc1-medica`:

```
sudo ./deploy.sh
```

**Tiempo:** build ~2 min (necesita Internet, ~300 MB) y primer arranque ~5 min. PC-1 es puerto access: no crea sub-interfaz.

**Comprueba:**

```
docker compose ps
```

Esperado: todo `Up`. Si `openvpms-app` reinicia, espera: está inicializando la base.

## Paso 8 — Pruebas por VLAN (desde el portátil)

**Regla importante:** con `macvlan`, un PC **no alcanza a sus propios contenedores**. Todas las pruebas se hacen **desde el portátil**, nunca desde el PC que aloja el servicio.

El portátil se enchufa al **puerto de pruebas**. Para cada VLAN N de negocio (10, 20, 30, 40) haces la misma ronda: cambiar el puerto a esa VLAN, ponerle IP al portátil, y probar.

**Cambiar el puerto de pruebas de VLAN** (en el switch, `configure terminal`):

```
interface PUERTO-PRUEBAS
```

```
switchport access vlan N
```

**En el portátil** (`NIC-PORTATIL` es su tarjeta de red; usa una IP libre como `.50`):

```
sudo ip addr flush dev NIC-PORTATIL
```

```
sudo ip addr add 10.10.N.50/24 dev NIC-PORTATIL
```

```
sudo ip route add 10.10.0.0/16 via 10.10.N.1
```

**Comprueba que llegas a tu gateway.** Aquí el gateway `10.10.N.1` es **PC-3**, no el switch:

```
ping -c 2 10.10.N.1
```

Esperado: responde. Si no, el puerto no quedó en la VLAN N, el trunk de PC-3 no permite esa VLAN, o PC-3 no creó la sub-interfaz (revisa el paso 4).

### Qué esperar en cada ronda

| Desde VLAN | Debe funcionar ✅ | Debe fallar ❌ |
|---|---|---|
| **10** | OpenVPMS `http://10.10.10.10:8080/openvpms/login`; LDAP, DNS y NTP de VLAN 99 | `ping` a `10.10.20.10`, `10.10.30.10` y `10.10.40.10` |
| **20** | Pretix `http://10.10.20.10/`; VLAN 99 | `ping` a `10.10.10.10`, `10.10.30.10`, `10.10.40.10` |
| **30** | InvenTree `http://10.10.30.10:8000/api/`; VLAN 99 | `ping` a `10.10.10.10`, `10.10.20.10`, `10.10.40.10` |
| **40** | ERPNext `http://10.10.40.10:8080/api/method/ping`; VLAN 99 | `ping` a `10.10.10.10`, `10.10.20.10`, `10.10.30.10` |

Comandos de la parte ✅ (cambia N y la URL según la fila). Aplicación de esa VLAN:

```
curl -s -o /dev/null -w '%{http_code}\n' http://10.10.20.10/
```

Esperado: `200` (Pretix puede dar `302`, también vale).

LDAP en VLAN 99 (con la cuenta de búsqueda):

```
ldapsearch -x -H ldap://10.10.99.10 -D "cn=svc-lectura,ou=servicios,dc=reservaviva,dc=local" -w Svc-Lectura1 -b "dc=reservaviva,dc=local" "(uid=rrhh.prueba)"
```

Esperado: devuelve una entrada `uid=rrhh.prueba`.

DNS:

```
dig @10.10.99.11 ldap.reservaviva.local +short
```

Esperado: `10.10.99.10`.

NTP:

```
ntpdate -q 10.10.99.12
```

Esperado: una línea con `offset` y sin error.

Comandos de la parte ❌ (uno por destino):

```
ping -c 2 -W 2 10.10.30.10
```

Esperado: **100% packet loss**. Si responde, la matriz **no** se está cumpliendo.

Repite la ronda para las 4 VLANs. Además, la ronda de VLAN 20 (`ping` a `10.10.30.10`) prueba el bloqueo entre las dos VLANs de un mismo PC (PC-2): el tráfico sale por el trunk, llega a PC-3 y allí se corta.

**Evidencia por ronda:** texto o captura de los `curl`, `ldapsearch`, `dig`, `ntpdate` y de cada `ping` fallido.

**Después de las 4 rondas**, en **PC-3**:

```
sudo nft -a list ruleset
```

Esperado: los contadores de las reglas `drop` **subieron** (las de VLAN de negocio contra VLAN de negocio). Es la prueba de que PC-3 aplicó la matriz, y no solo que "no hay ruta". **Guárdala** junto con la salida anterior de contadores en 0.

## Paso 9 — Evidencia para la sustentación

Ya reunida durante los pasos anteriores. Falta la captura en el trunk de PC-3:

1. Conecta el portátil con Wireshark a un puerto espejo (SPAN) del trunk de PC-3, o a la línea del trunk si tu equipo lo permite.
2. Repite un `ping` bloqueado (20 → 30) y un `curl` permitido.
3. Filtra por VLAN:

```
vlan
```

Esperado: tramas con la etiqueta 802.1Q. Aquí verás el tráfico **entrar y salir por el mismo trunk de PC-3**: es el "router-on-a-stick". Captura pantalla o guarda el `.pcap`.

**Lista de evidencia:**

- [ ] `show vlan brief`, `show interfaces trunk` y `show ip interface brief` (paso 1).
- [ ] `docker compose ps` de cada PC.
- [ ] `ip -brief addr show` de PC-2 y PC-3, y `sysctl net.ipv4.ip_forward` de PC-3.
- [ ] `nft -a list ruleset` de PC-3, antes y después de las pruebas (contadores).
- [ ] Rondas de la matriz (positivas y negativas).
- [ ] Captura Wireshark con etiquetas 802.1Q.
- [ ] Tiempos reales de cada primer arranque (anota cuánto tardó cada `deploy.sh`).

## Paso 10 — Que sobreviva a un reinicio

En cada PC, con el número que corresponda (`pc1`, `pc2` o `pc3`; abajo el ejemplo es PC-3). Primero, ve a la raíz del repo.

```
cd ~/UD.RedesCorporativaa.ProyectoFinak
```

```
sudo mkdir -p /opt/reserva-viva
```

```
sudo cp -r . /opt/reserva-viva
```

```
sudo cp scripts/systemd/reserva-viva-pc3.service /etc/systemd/system/
```

```
sudo systemctl daemon-reload
```

```
sudo systemctl enable --now reserva-viva-pc3.service
```

Ahora reinicia el PC.

```
sudo reboot
```

**Comprueba** al volver. En PC-3 esto incluye que el router y el firewall se recrearon solos:

```
systemctl status reserva-viva-pc3
```

```
docker ps
```

```
sysctl net.ipv4.ip_forward
```

```
sudo nft -a list ruleset
```

Esperado: servicio activo, contenedores `Up`, `ip_forward = 1` y la tabla `inet reservaviva` presente, **sin** repetir los ~13 min. Haz lo mismo en PC-2 y PC-1 con su servicio (`reserva-viva-pc2`, `reserva-viva-pc1`); en ellos solo aplica `systemctl status` y `docker ps`.

**Orden de encendido tras un apagón general:** primero PC-3 (es el router y el LDAP), luego PC-2 y PC-1.

---

## Si algo sale mal

| Síntoma | Qué mirar |
|---|---|
| `deploy.sh` dice `PERFIL='' no es válido` | Falta `PERFIL=l2` en el `.env` de esa carpeta. |
| `deploy.sh` dice `Falta .env` | No copiaste `.env.example` a `.env` (paso 3). |
| Una sub-interfaz no aparece | `IFACE` mal escrito: compáralo con `ip -brief link show`. |
| No hay ping a `10.10.N.1` desde el portátil | Puerto de pruebas en otra VLAN, o el trunk de PC-3 no permite la VLAN N (`show interfaces trunk`), o PC-3 apagado. |
| Ni siquiera llega a VLAN 99 | `sysctl net.ipv4.ip_forward` en PC-3 debe dar `1`; revisa `sudo nft -a list ruleset`. |
| Los `ping` entre VLANs de negocio **responden** (deberían fallar) | La tabla `inet reservaviva` no está cargada en PC-3. Repite `sudo ./deploy.sh` en PC-3. |
| Todo se bloquea, incluso VLAN → 99 | Los contadores de `nft` te dicen qué regla corta. No uses `--quitar` para "descartar" el firewall: también retira la regla de `DOCKER-USER` que deja pasar el tráfico entre VLANs, y el reenvío dejaría de funcionar. |
| `ldapsearch` falla pero LDAP está `Up` | Confirma que estás en una VLAN 10/20/30/40 con ruta a `10.10.N.1` (PC-3) y que el trunk de PC-3 permite la 99. |
| Una app da `Restarting` | Espera unos minutos si es primer arranque; luego `docker compose logs NOMBRE-SERVICIO`. |
| El PC no ve sus propios contenedores | Es normal con `macvlan`: prueba desde el portátil. |

Para repetir un `deploy.sh` no hay problema: es idempotente.
