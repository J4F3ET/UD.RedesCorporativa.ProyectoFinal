# Receta L3 — el switch enruta y aplica la matriz

Usa esta receta si el switch tiene interfaces `VlanNN` con IP y enruta ([cómo saberlo](../README.md)). Síguela de arriba abajo. En cada paso hay una comprobación: **no pases al siguiente hasta que la tuya dé el resultado esperado.**

**Idea en una línea:** el switch es el router. Cada VLAN tiene su gateway `10.10.X.1` en el switch (una SVI) y las ACL de la matriz viven ahí. Los PCs solo crean sus VLANs y no enrutan nada.

> **Estado: pendiente de hardware.** Nada de esto se ha ejecutado aún contra un switch real. Los tiempos de arranque de las aplicaciones son medidos (en un solo host, ver la sección de tiempos); los de configurar el switch y cablear no están medidos. Si algo no coincide con lo que dice aquí, anótalo: es información valiosa.

> **OBLIGATORIO ANTES DE IR: el laboratorio NO tiene Internet** (confirmado por el usuario). Instalar necesita Internet: Docker, las imágenes de las aplicaciones y el build de OpenVPMS (~300 MB de descarga, una sola vez). **Sin la preparación previa no arranca nada.**
>
> **Fase 0 — preparación previa (otro día, otra máquina, con Internet).** Se construye y se guarda todo en un paquete que se lleva al laboratorio: Docker instalado en los 3 PCs, todas las imágenes (incluida la de OpenVPMS, que hay que compilar antes) y el repositorio. En el laboratorio se carga ese paquete en cada PC antes del paso 3.
>
> **HUECO: comandos de la Fase 0 pendientes.** Los está construyendo pepe (paquete offline con `docker save`/`docker load`); hay una duda abierta sobre si las imágenes fijadas por digest sobreviven a `save`/`load`, y de la respuesta depende el procedimiento. Aquí irán los comandos cuando estén comprobados. **No improvises otro procedimiento.**

## Lo que necesitas antes de empezar

- Los 3 PCs con Ubuntu Server, usuario con `sudo` y **sin Internet en el laboratorio**: todo lo que se instala llega en el paquete de la Fase 0 (recuadro de arriba).
- El switch, su cable de consola y sus credenciales.
- Un portátil con Linux y un cable de red (para las pruebas). Necesita `curl`, `dig`, `ldap-utils` y `ntpdate`.
- Un puerto libre del switch para el portátil (le llamaremos **puerto de pruebas**).
- Un USB (alternativa si `scp` no funciona, ver paso 5).
- Los nombres reales de los puertos del switch de cada PC. Anótalos: `PUERTO-PC1`, `PUERTO-PC2`, `PUERTO-PC3`, `PUERTO-PRUEBAS`.

## Resumen: qué pasa en cada paso y cuánto tarda

| # | Paso | Tiempo |
|---|---|---|
| 1 | Configurar el switch | sin medir |
| 2 | Cablear | sin medir |
| 3 | Preparar los 3 PCs (Docker, repo, `.env`) | sin medir |
| 4 | PC-3: `sudo ./deploy.sh` | **~13 min** el primer arranque completo (lo marca `erpnext-create-site`) |
| 5 | PC-2: `sudo ./deploy.sh`, copiar `ca.crt` con `scp` y relanzar | Pretix e InvenTree, **~10 min** de migraciones |
| 6 | PC-1: `sudo ./deploy.sh` | build de OpenVPMS **~2 min** y primer arranque **~5 min** |
| 7 | Pruebas por VLAN | sin medir |
| 8 | Evidencia | sin medir |
| 9 | Reinicio real | sin medir |

Los ~13 min son el primer arranque de los 3 PCs medido en **un solo host** con las tres pilas a la vez (22 contenedores); OpenVPMS corre en paralelo. En hardware real por separado puede variar. Los arranques posteriores son inmediatos. **No interrumpas** un arranque que "parece colgado" durante esos minutos: es normal.

---

## Paso 1 — Configurar el switch

Qué se configura:

- VLANs 10, 20, 30, 40 y 99.
- Una SVI por VLAN con IP `10.10.X.1/24` (X = número de VLAN).
- `ip routing` activado.
- Puerto de PC-1: **access** VLAN 10.
- Puerto de PC-2: **trunk** 802.1Q con VLAN 20 y 30.
- Puerto de PC-3: **trunk** 802.1Q con VLAN 40 y 99.
- Las ACL de la matriz: cada VLAN de negocio (10, 20, 30, 40) solo habla con VLAN 99; entre ellas, bloqueado; VLAN 99 solo responde.
- La VLAN 999 sin uso, como VLAN nativa de los trunks.
- El **puerto de pruebas** del portátil **no viene en el archivo**: lo añades tú justo después (ver abajo).

Todo eso está escrito para Cisco IOS en [`despliegue/l3-switch/switch/config-switch-l3.txt`](switch/config-switch-l3.txt). Ábrelo, cambia los nombres de puerto (`GigabitEthernet1/0/1`, `/2` y `/3` son solo **ejemplos**; el cableado propuesto es PC-1 → 1/0/1, PC-2 → 1/0/2, PC-3 → 1/0/3) por los reales (`show interfaces status` te los lista), y pégalo en la consola dentro de `configure terminal`. Al inicio del archivo hay un aviso: léelo. Al terminar, añade el puerto de pruebas (sustituye `PUERTO-PRUEBAS` por el puerto real; es un bloque de configuración, se pega entero):

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

**Comprueba** (deben salir estas cosas; la guía larga está en [`switch/verificacion.md`](switch/verificacion.md)):

```
show vlan brief
```

Esperado: VLAN 10, 20, 30, 40 y 99 activas (más la 999, sin uso).

```
show ip interface brief
```

Esperado: `Vlan10`, `Vlan20`, `Vlan30`, `Vlan40`, `Vlan99` con IP `10.10.X.1`.

```
show interfaces trunk
```

Esperado: el puerto de PC-2 permite VLAN 20,30 y el de PC-3 permite VLAN 40,99.

```
show access-lists
```

Esperado: las ACL de la matriz, con sus contadores en 0.

Más comandos de evidencia en [`switch/verificacion.md`](switch/verificacion.md).

**Evidencia a guardar:** captura o texto de estos cuatro comandos.

## Paso 2 — Cablear

| Cable | Puerto del switch |
|---|---|
| PC-1 | `PUERTO-PC1` (access VLAN 10) |
| PC-2 | `PUERTO-PC2` (trunk 20,30) |
| PC-3 | `PUERTO-PC3` (trunk 40,99) |

**Comprueba:** los tres puertos en `up`.

```
show interfaces status
```

Si alguno sale `notconnect`, revisa el cable y el nombre del puerto.

## Paso 3 — Preparar los 3 PCs

Repite esto en **cada PC**. Si ya tienen Docker y el repo, salta a "Crear el `.env`".

Instalar Docker. **En el laboratorio no hay Internet:** Docker y el repositorio llegan en el paquete de la Fase 0 (comandos pendientes, ver recuadro del inicio). El comando siguiente es el de la máquina **con Internet**, solo para saber qué se prepara; no lo ejecutes en el laboratorio:

```
curl -fsSL https://get.docker.com | sudo sh
```

Descargar el proyecto (igual: solo en la máquina con Internet; en el laboratorio el repositorio viene en el paquete):

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
| `PERFIL` | `l3` | `l3` | `l3` |
| `IFACE` | NIC real de PC-1 | NIC real de PC-2 | NIC real de PC-3 |
| `IP_GESTION` | `10.10.10.250` | `10.10.20.250` (**o** `10.10.30.250`, nunca las dos) | `10.10.99.250` |
| Contraseñas (`*_PASSWORD`) | cámbialas; anótalas | cámbialas; anótalas | cámbialas; anótalas |

`IP_GESTION` es una dirección propia de cada PC, para poder copiar el certificado con `scp` y hacer `ping`/`ssh` de diagnóstico. Sin ella el PC no tiene ninguna dirección alcanzable. Reglas (el script las valida y se niega si no se cumplen):

- Una sola dirección por PC, con el último número entre 16 y 254 (`.250` es seguro: los contenedores usan de `.1` a `.14`).
- **PC-2: en una sola de sus dos VLANs (20 o 30), nunca en las dos.** Docker activa `ip_forward` por su cuenta: con IP en las dos VLANs, PC-2 enrutaría entre VLAN 20 y VLAN 30 él mismo, el tráfico ya no saldría al switch y se perdería el *hairpin*, una de las dos evidencias centrales de la segmentación. No es un capricho: no busques cómo saltarlo.

Claves con reglas propias:

- PC-1: `OPENVPMS_ADMIN_PASSWORD` mínimo 8 caracteres con mayúscula, minúscula, número y un especial (por ejemplo `!`). Si no, OpenVPMS no arranca.
- PC-2 y PC-3: `INVENTREE_LDAP_BIND_PASSWORD` y `ERPNEXT_LDAP_BIND_PASSWORD` deben ser **`Svc-Lectura1`** (la del LDIF de laboratorio). Si las cambias, cámbialas también en `docker/pc3-administracion-infra/ldap/`.
- PC-3: `LDAP_ADMIN_PASSWORD`, `ERPNEXT_DB_ROOT_PASSWORD`, `ERPNEXT_ADMIN_PASSWORD`. Anótalas.

Guardar y salir de nano: `Ctrl+O`, `Enter`, `Ctrl+X`.

**Comprueba:** en cada PC, que `PERFIL=l3` esté escrito y sin espacios.

```
grep -E '^(PERFIL|IFACE)=' .env
```

## Paso 4 — PC-3 primero (LDAP, DNS, NTP y ERPNext)

PC-3 va primero porque los otros dos dependen de su LDAP y de su `ca.crt`. Desde `docker/pc3-administracion-infra`:

```
sudo ./deploy.sh
```

**Tiempo: ~13 min.** El script hace, en orden: valida `PERFIL`, crea las sub-interfaces `IFACE.40` y `IFACE.99` (sin IP), genera los certificados de LDAPS y arranca los contenedores. Casi todo el tiempo es `erpnext-create-site`. No hace falta que hagas nada.

**Comprueba:**

```
docker compose ps
```

Esperado: todo `Up`, salvo `erpnext-configurator` y `erpnext-create-site`, que **deben** decir `Exited (0)`.

```
ip -brief addr show
```

Esperado: `IFACE.40` y `IFACE.99` en `UP`, y ninguna dirección IP salvo `10.10.99.250` en `IFACE.99` (la de gestión).

```
ls certs/ca.crt
```

Esperado: el archivo existe.

**Evidencia:** salida de `docker compose ps` y de `ip -brief addr show`.

## Paso 5 — PC-2 (Pretix + InvenTree), con el certificado

PC-2 necesita `certs/ca.crt` (la CA interna de LDAPS, que nace en PC-3) antes de arrancar. `deploy.sh` lo sabe: **la primera vez se detiene a pedírtelo, sin error**, y lo relanzas después de copiarlo.

### 5a — Primer lanzamiento (se detiene a pedir el certificado)

Desde `docker/pc2-operaciones`:

```
sudo ./deploy.sh
```

Crea las sub-interfaces `IFACE.20` e `IFACE.30` y la IP de gestión, y **antes** de arrancar los contenedores comprueba `certs/ca.crt`. Como falta, imprime `PASO PENDIENTE (no es un error)` con el `scp` exacto y **termina con código 0**. Es lo esperado.

### 5b — Copiar el certificado con `scp`

**El sentido importa.** La matriz sigue en vigor para los PCs, no solo para los contenedores: una VLAN de negocio solo alcanza la VLAN 99. Por eso el `scp` lo **inicia PC-2** contra PC-3, en su dirección de la VLAN 99, que en este perfil es `10.10.99.250` (la `IP_GESTION` de PC-3). Empujar el certificado desde PC-3 hacia los otros PCs choca con la matriz: la red funciona bien, no es un fallo.

Primero comprueba que PC-2 llega a PC-3:

```
ping -c 2 10.10.99.250
```

Esperado: responde. Si no, revisa `IP_GESTION` en los `.env` de PC-2 y PC-3 y la ruta (`ip route`).

Ejecuta el comando `scp` que imprimió `deploy.sh` (cambia `<usuario>` y `<ruta-del-repo-en-PC-3>` por los reales). PC-3 debe tener el servicio SSH activo (`sudo systemctl status ssh`). Si el `scp` no es posible, copia `ca.crt` de PC-3 con un USB a `docker/pc2-operaciones/certs/ca.crt`.

**Comprueba:** el archivo es idéntico al de PC-3. Ejecútalo en PC-2 y en PC-3 (carpetas `docker/pc2-operaciones` y `docker/pc3-administracion-infra`).

```
sha256sum certs/ca.crt
```

Esperado: el mismo valor en los dos PCs.

> **Pendiente de comprobar en hardware:** el `scp` real contra la red del laboratorio no se ha ejecutado.

### 5c — Segundo lanzamiento (arranca todo)

```
sudo ./deploy.sh
```

**Tiempo: ~10 min** (cientos de migraciones de Pretix e InvenTree). Al final crea el administrador de Pretix. Si esa parte falla, se repite sola con:

```
sudo ./deploy.sh --solo-admins
```

PC-2 crea `IFACE.20` e `IFACE.30`. **No** le pongas gateway a mano: el gateway `10.10.X.1` de sus contenedores lo fija el compose.

**Comprueba:**

```
docker compose ps
```

Esperado: todo `Up`.

```
ip -brief addr show
```

Esperado: `IFACE.20` e `IFACE.30` en `UP`, y solo la IP de gestión en una de ellas.

**Evidencia:** las dos salidas.

## Paso 6 — PC-1 (OpenVPMS)

Desde `docker/pc1-medica`:

```
sudo ./deploy.sh
```

**Tiempo:** primer arranque ~5 min. El build de OpenVPMS (~2 min medido con Internet, ~300 MB de descarga) **se hace en la Fase 0**, no en el laboratorio. *Pendiente:* cómo llega esa imagen ya compilada a PC-1 (lo define el paquete offline de pepe). PC-1 es puerto access: no crea sub-interfaz. Si pusiste `IP_GESTION`, la lleva la propia tarjeta (`IFACE`), con `10.10.10.250`.

**Comprueba:**

```
docker compose ps
```

Esperado: todo `Up`. Si `openvpms-app` reinicia, espera: está inicializando la base.

## Paso 7 — Pruebas por VLAN (desde el portátil)

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

**Comprueba que llegas a tu gateway** (la SVI del switch):

```
ping -c 2 10.10.N.1
```

Esperado: responde. Si no, el puerto no quedó en la VLAN N o la SVI no está arriba.

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

Esperado: **100% packet loss** (o `unreachable`). Si responde, la matriz **no** se está cumpliendo.

Repite la ronda para las 4 VLANs. Además, prueba el bloqueo entre las dos VLANs de un mismo PC (20 ↔ 30 en PC-2): es la más interesante, porque el tráfico sale por el trunk, llega al switch y allí se corta. Ya la cubre la ronda de VLAN 20 (`ping` a `10.10.30.10`).

**Evidencia por ronda:** texto o captura de los `curl`, `ldapsearch`, `dig`, `ntpdate` y de cada `ping` fallido.

**Después de las 4 rondas**, en el switch:

```
show access-lists
```

Esperado: los contadores de las líneas `deny` **subieron**. Es la prueba de que el switch aplicó la matriz. **Guárdala.**

## Paso 8 — Evidencia para la sustentación

Ya reunida durante los pasos anteriores. Falta la captura en el trunk:

1. Conecta el portátil con Wireshark a un puerto espejo (SPAN) del trunk de PC-2 o PC-3, o a la línea del trunk si tu equipo lo permite.
2. Repite un `ping` bloqueado (20 → 30) y un `curl` permitido.
3. Filtra por VLAN:

```
vlan
```

Esperado: tramas con la etiqueta 802.1Q (VLAN 20 y 30). Captura pantalla o guarda el `.pcap`.

**Lista de evidencia:**

- [ ] `show vlan brief`, `show ip interface brief`, `show interfaces trunk` (paso 1).
- [ ] `docker compose ps` de cada PC.
- [ ] `ip -brief addr show` de PC-2 y PC-3 (sub-interfaces sin IP).
- [ ] Rondas de la matriz (positivas y negativas).
- [ ] `show access-lists` con contadores de `deny` subidos.
- [ ] Captura Wireshark con etiquetas 802.1Q.
- [ ] Tiempos reales de cada primer arranque (anota cuánto tardó cada `deploy.sh`).

## Paso 9 — Que sobreviva a un reinicio

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

**Comprueba** al volver:

```
systemctl status reserva-viva-pc3
```

```
docker ps
```

Esperado: servicio activo y contenedores `Up`, **sin** repetir los ~13 min. Haz lo mismo en PC-2 y PC-1 con su servicio (`reserva-viva-pc2`, `reserva-viva-pc1`).

---

## Si algo sale mal

| Síntoma | Qué mirar |
|---|---|
| `deploy.sh` dice `PERFIL='' no es válido` | Falta `PERFIL=l3` en el `.env` de esa carpeta. |
| `deploy.sh` dice `Falta .env` | No copiaste `.env.example` a `.env` (paso 3). |
| Una sub-interfaz no aparece | `IFACE` mal escrito: compáralo con `ip -brief link show`. |
| No hay ping a `10.10.N.1` desde el portátil | Puerto de pruebas en otra VLAN, o SVI caída (`show ip interface brief`). |
| Todo funciona, pero **los `ping` entre VLANs también** | La ACL no está aplicada en las SVI: revisa `show access-lists` y `show running-config interface VlanN`. |
| Nada llega a nada entre VLANs, ni a la 99 | Falta `ip routing` o falta la SVI de esa VLAN. |
| `ldapsearch` falla pero LDAP está `Up` | Confirma que el puerto de PC-3 permite VLAN 99 y que estás en una VLAN 10/20/30/40 con ruta al gateway. |
| Una app da `Restarting` | Espera unos minutos si es primer arranque; luego `docker compose logs NOMBRE-SERVICIO`. |
| El PC no ve sus propios contenedores | Es normal con `macvlan`: prueba desde el portátil. |

Para repetir un `deploy.sh` no hay problema: es idempotente.
