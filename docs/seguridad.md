# Seguridad y credenciales

Qué protege el sistema de un host, con qué mecanismos y qué deja sin cubrir (entre otras cosas, que **ya no hay aislamiento
de red entre departamentos**: sección 5). Se dirige a quien clona el repositorio.
Aquí no se repite la integración LDAP de cada aplicación, que está en [`directorio-activo.md`](directorio-activo.md). Las cifras de las pruebas
están en [`resultados-un-host.md`](resultados-un-host.md).

## 1. Alcance y advertencia

Reserva Viva es un **laboratorio académico**, no un despliegue de producción:

- Todas las contraseñas están en [`../sistema/test.env`](../sistema/test.env). Ese fichero **está versionado en git**,
  así que sus valores están en el historial del repositorio. Son claves **desechables** de laboratorio.
- `sistema/test.env` es la **única** fuente de claves, también las del directorio (Samba AD): ningún otro fichero versionado
  (README, scripts) contiene una clave. `samba-ad` las recibe por variables de entorno y las aplica al sembrar (sección 3).
- Hay que **rotar todas las claves** si el repositorio se hace público o si alguien usa este sistema fuera del laboratorio
  (ver la sección 6). Borrar `test.env` en un commit nuevo no basta: el historial conserva los valores.

## 2. CA interna y certificados

### Qué genera `servicios/ca/generar-certificados.sh`

[`../servicios/ca/generar-certificados.sh`](../servicios/ca/generar-certificados.sh) crea una CA propia del laboratorio y el
certificado LDAPS de Samba AD. `levantar-sistema.sh` lo ejecuta en cada `preparar` y en cada `arrancar`, siempre con
`--sin-instalar-ca`. Los ficheros quedan en `servicios/ca/certs/`, que está en `.gitignore`: cada clon genera los suyos.

| Fichero | Qué es | Parámetros | Permisos al generarse |
|---|---|---|---|
| `ca.crt` | Certificado público de la CA. Es lo que deben confiar los clientes de LDAPS | RSA 4096, SHA-256, 3650 días, `CA:TRUE` (crítica), `keyCertSign, cRLSign`; sujeto `O=Zoologico Reserva Viva, CN=Reserva Viva CA interna` | 644 |
| `ca.key` | Clave privada de la CA. **No se monta en ningún contenedor** | — | 600 |
| `ldap.crt` | Certificado de servidor de `samba-ad`, firmado por la CA | RSA 2048, SHA-256, 825 días, `serverAuth`; SAN `DNS:ldap.reservaviva.lan`, `DNS:dc1.ad.reservaviva.lan`, `DNS:samba-ad`, `DNS:localhost`, `IP:10.10.99.10`, `IP:127.0.0.1`, `IP:<HOST_IP>` | 644 |
| `ldap.key` | Clave privada del servidor LDAPS | — | 600 |

El script trabaja con `umask 077`. Opciones: `--forzar` lo regenera todo, y `--sin-instalar-ca` evita instalar `ca.crt` en
el almacén de confianza del equipo. Sin esa opción, la instalación se hace solo si el script corre como root y existe
`update-ca-certificates`.

### Cuándo se regenera y cuándo no

El script es idempotente. Si los certificados existen y son válidos, no toca nada. Regenera en estos casos:

- **La CA** (y con ella el certificado LDAPS), con `--forzar`, si falta `ca.key` o si a `ca.crt` le quedan menos de
  30 días de vigencia.
- **Solo el certificado LDAPS**, con `--forzar`, si falta `ldap.key`, si a `ldap.crt` le quedan menos de 30 días, si
  `ldap.crt` no lo firma la `ca.crt` actual o si su SAN no incluye `ldap.reservaviva.lan`, `dc1.ad.reservaviva.lan`, `samba-ad`, `10.10.99.10` y la `HOST_IP` actual (un `ldap.crt`
  anterior a la migración a Samba AD se regenera solo en el siguiente `arrancar`, con la misma CA). Así se
  regeneró el 27/09/2026, al pasar el dominio de `.local` a `.lan`: solo `ldap.crt`/`ldap.key`, con la misma CA, sin tocar
  a los clientes (que confían en `ca.crt`).

Los permisos (`chmod`) se aplican **solo a lo generado en esa ejecución**, para no fallar si algún fichero anterior quedó
con otro dueño. El script borra y crea los ficheros de nuevo en vez de sobrescribirlos.

Si se regeneran con el sistema en marcha, los contenedores que los montan siguen viendo los ficheros anteriores hasta que
se reinician. `samba-ad` monta los tres ficheros de solo lectura en `/certs` y su entrypoint los **copia** a
`/var/lib/samba/private/tls/` con `chmod 600` **en cada arranque** (Samba rechaza la clave privada si no tiene permisos 0600
exactos, y un montaje de solo lectura no se puede chmodear). Por eso, a diferencia del OpenLDAP anterior (que solo copiaba
sus certificados en el primer arranque de cada contenedor y había que recrearlo), basta con **reiniciar** `samba-ad`, sin
recrearlo: `arrancar` lo hace cuando `ldap.crt` es más nuevo que el último arranque del contenedor
(`reiniciar_directorio_si_cert_nuevo`), y después reinicia los dos clientes LDAPS, `inventree-app` y
`erpnext-backend`. Esto último se mantiene del stack anterior: el 27/09/2026, con el directorio ya sirviendo el certificado
nuevo, InvenTree siguió rechazando el login LDAP (401, sin ningún error en su log) hasta reiniciar `inventree-app`, mientras
un proceso nuevo dentro del mismo contenedor autenticaba bien. Queda estado TLS/LDAP en los procesos de gunicorn; la causa
exacta no se identificó. También se reinicia `erpnext-hr`: al reiniciarse, `erpnext-backend` puede cambiar de IP en
`erpnext_internal` y el nginx de `erpnext-hr` seguía llamando a la antigua (502 en `rrhh`). Si se regenerase la CA, habría
que recrear también `inventree-app` y `erpnext-backend` para que monten la `ca.crt` nueva, y eso no está automatizado.

### Quién monta qué

| Contenedor | Ficheros montados desde `servicios/ca/certs/` | Para qué |
|---|---|---|
| `samba-ad` | `ca.crt`, `ldap.crt`, `ldap.key` → `/certs/` (solo lectura; el entrypoint los copia con `chmod 600`) | Servir LDAPS en el 636 (`tls enabled = yes`) |
| `erpnext-backend` | `ca.crt` → `/certs/ca.crt` (solo lectura) | Verificar el certificado del DC |
| `inventree-app` | `ca.crt` → `/certs/ca.crt` (solo lectura) | Verificar el certificado del DC |

OpenVPMS y Pretix no montan nada, porque no usan LDAP. Todo está definido en el compose único
[`../docker-compose.yml`](../docker-compose.yml).

**Por qué hay una sola CA.** Todos los servicios corren en el mismo motor Docker y salen del mismo clon del repositorio.
Basta con un único `ca.crt`, montado por todos desde `./servicios/ca/certs/ca.crt`, y no hay copias que mantener
sincronizadas. En el diseño histórico de 3 equipos ([`diseno-red/`](../diseno-red/README.md)), cada equipo necesitaba su propia copia.

**Si falta `ca.crt`.** Cuando la ruta de origen de un montaje no existe, Docker crea en su lugar un **directorio vacío**.
El contenedor arranca, pero `/certs/ca.crt` es entonces un directorio: la verificación TLS falla y el login LDAPS de
ERPNext e InvenTree no funciona. Para evitarlo, el certificado debe existir antes de arrancar, y de eso se encarga la
comprobación en `preparar` de `levantar-sistema.sh`. Si ya se arrancó sin él, hay que borrar el directorio vacío que
creó Docker, volver a ejecutar `preparar` y recrear los contenedores afectados.

## 3. Directorio activo y LDAPS

### Qué aplicación usa LDAP

Solo ERPNext e InvenTree, las dos por LDAPS (`ldaps://ldap.reservaviva.lan:LDAPS_PORT`, el 1636 del equipo) y verificando el certificado del DC con la
CA interna; OpenVPMS y Pretix no usan LDAP. Cómo lo configura cada aplicación, qué se comprueba y por qué las otras dos no
se integran: [`directorio-activo.md`](directorio-activo.md). El nombre `ldap.reservaviva.lan` se fija con `extra_hosts` a
`HOST_IP` para que coincida con el SAN del certificado sin depender del DNS.

### Controles del directorio

- **Solo LDAPS para el bind simple.** Samba lleva `ldap server require strong auth = yes` (el valor por defecto, que cierra
  [CVE-2016-2112](https://www.samba.org/samba/security/CVE-2016-2112.html)): un bind simple por el 389 sin cifrar se rechaza
  con "Strong(er) authentication required". Las dos aplicaciones ya usan el 636, así que no se relajó. El 389 está
  publicado en `HOST_IP:1389`, pero no admite credenciales; AD tampoco admite consultas anónimas salvo al rootDSE.
- **Complejidad de contraseñas de AD.** Toda clave del dominio debe cumplirla (longitud mínima, tres de cuatro categorías y no
  contener el nombre de la cuenta). Dos claves de `test.env` no la cumplían y se cambió **la clave, no la política**. Con ello,
  `samba-tool` rechaza cualquier clave nueva débil.
- **`privileged: true`.** Samba guarda las ACL de AD en atributos extendidos `security.*` del sistema de ficheros y el
  contenedor sin privilegios no puede escribirlas. Es la mayor concesión de este servicio: un contenedor privilegiado tiene
  acceso casi total al kernel del host. Se acepta en el laboratorio; en producción habría que acotar las capacidades
  necesarias en lugar de `privileged`.
- **Puertos acotados.** De Samba AD solo se publican el 389 y el 636, en `HOST_IP`. No se publican el 445 (SMB; además lo
  ocupa Windows), el 88 (Kerberos) ni el 53. Con `interfaces = eth0` y `bind interfaces only = yes`, Samba solo escucha en
  su interfaz de la red `reservaviva`.
- **Recursión limitada en bind9.** Para seguir la delegación de `ad.reservaviva.lan` hizo falta `recursion yes`, limitada
  a los contenedores de la red `reservaviva` (ACL de la subred **sin el gateway `.1`**, que es el origen de las consultas del
  anfitrión y de la LAN). Fuera de esa ACL, `recursion no`. Para que la recursión no se convierta en un resolvedor de
  Internet, hay una raíz `"."` **autoritativa y vacía** (`zones/db.raiz-vacia`, con `allow-query { red-interna; }`): todo nombre que
  no sea de `reservaviva.lan` da NXDOMAIN a los contenedores, tenga o no salida el host, y REFUSED al anfitrión y a la LAN. Una zona
  `"."` de reenvío con `forwarders { }` **no** lo evita (BIND recursiona con sus root hints; se midió el 04/10/2026: `example.com`
  resolvía a IP reales). Detalle en [`servicios/bind9/README.md`](../servicios/bind9/README.md).
- **Cuentas de laboratorio sin caducidad.** Las cuatro cuentas de prueba y `svc-lectura` llevan `--noexpiry` (UAC `66048`)
  en cada arranque, para que un login de prueba no falle por caducidad a los 41 días. La política del dominio (`maxPwdAge`)
  no se toca, y `Administrator` sí caduca. Con claves públicas en git, en producción esto no se admitiría.

### Árbol del directorio

Base `DC=ad,DC=reservaviva,DC=lan`, que crea [`sembrar.sh`](../servicios/samba-ad/sembrar.sh):

```
DC=ad,DC=reservaviva,DC=lan
├── OU=Medica         vet.prueba        (GG-Medica)
├── OU=Operaciones    logistica.prueba, taquilla.prueba  (GG-Operaciones)
├── OU=RRHH           rrhh.prueba       (GG-RRHH)
├── OU=Servicios      svc-lectura       (cuenta de búsqueda)
└── OU=Grupos         GG-Medica, GG-Operaciones, GG-RRHH
```

El dominio se provisiona **solo la primera vez**, con `private/` vacía (marca `private/.provisionado-reserva-viva`); la siembra
se repite en cada arranque y es idempotente. Cambiar `sembrar.sh` añade lo que falte, pero no borra nada del dominio ya
creado. Si el volumen queda a medias (un `domain provision` interrumpido), el entrypoint se detiene con un error explícito:
la solución es `./levantar-sistema.sh borrar-directorio` ([operacion.md](operacion.md#directorio-borrar-directorio)).

### Cuentas con privilegios en el directorio

Solo hay **una** cuenta de servicio para las búsquedas (bind), y la comparten las dos aplicaciones:

| Cuenta | Qué puede hacer | Quién la usa |
|---|---|---|
| `Administrator` | Administrar el dominio (`samba-tool`, `ldapmodify`). La crea `domain provision` con `SAMBA_ADMIN_PASSWORD` | Administración manual y `sembrar.sh` (`ldapmodify` de `givenName`/`sn`). No está en ningún grupo `GG-*` |
| `svc-lectura` (`CN=svc-lectura,OU=Servicios,DC=ad,DC=reservaviva,DC=lan`) | Buscar usuarios para autenticarlos. No tiene ninguna ACL a medida: lee con los permisos por defecto de un usuario del dominio | ERPNext e InvenTree |
| Cada usuario | Hacer bind con su propia clave | Las aplicaciones, al autenticarlo |

La ACL a medida de slapd (`05-acl-servicio.ldif`) desapareció con OpenLDAP: en AD, los permisos de lectura de los objetos son
los del dominio, y lo que decide quién entra en cada aplicación es el **grupo** (`memberOf`), no una regla del servidor.

Cada aplicación busca en **toda la base del dominio** y exige la pertenencia **directa** a su grupo: `GG-RRHH` en ERPNext y
`GG-Operaciones` en InvenTree. Por eso `vet.prueba` (`GG-Medica`) no entra en ninguna, y la prueba negativa de `verificar` lo
comprueba. Quedó resuelto el pendiente de grupos LDAP; sigue pendiente la cuenta de servicio por aplicación (sección 6).

### Usuarios de prueba

Qué usuario entra en qué aplicación está en [`directorio-activo.md`](directorio-activo.md#3-objetos-del-directorio). Los
usuarios LDAP se crean en la aplicación al primer login y **sin permisos**: se los asigna un administrador.

**Dónde están las claves:**

Todas en [`../sistema/test.env`](../sistema/test.env), y solo ahí:

| Cuenta | Variable |
|---|---|
| `svc-lectura` (la usan InvenTree y ERPNext para buscar) | `LDAP_SVC_LECTURA_PASSWORD` |
| `vet.prueba` | `LDAP_PRUEBA_VET_PASSWORD` |
| `logistica.prueba` | `LDAP_PRUEBA_LOGISTICA_PASSWORD` |
| `taquilla.prueba` | `LDAP_PRUEBA_TAQUILLA_PASSWORD` |
| `rrhh.prueba` | `LDAP_PRUEBA_RRHH_PASSWORD` |
| `Administrator` (administrador del dominio) | `SAMBA_ADMIN_PASSWORD` (antes `LDAP_ADMIN_PASSWORD`) |

La misma variable alimenta la siembra de `svc-lectura` y la configuración de las dos aplicaciones (`docker-compose.yml`), así
que no pueden desincronizarse. En cada arranque, `sembrar.sh` **reconcilia** la clave real de cada cuenta con la de
`test.env` (`samba-tool user setpassword`), incluida la de `Administrator`. `sistema/ldaplogin.py` lee las de `rrhh.prueba`
y `logistica.prueba` del mismo fichero.

## 4. Credenciales iniciales por aplicación

Solo los nombres de usuario y la variable que guarda cada clave. Los valores están en `sistema/test.env`.

| Servicio | Usuario inicial | Variable de la clave | Cuándo se aplica |
|---|---|---|---|
| OpenVPMS | `admin` | `OPENVPMS_ADMIN_PASSWORD` | Una vez, en la etapa `adminpass` de la inicialización (queda marcada como hecha) |
| Pretix | el valor de `PRETIX_ADMIN_EMAIL` (`admin@reservaviva.local`) | `PRETIX_ADMIN_PASSWORD` | La crea `levantar-sistema.sh` si no existe (ver abajo) |
| InvenTree | `INVENTREE_ADMIN_USER` (`admin` por defecto; `test.env` no lo define) | `INVENTREE_ADMIN_PASSWORD` | La imagen crea el superusuario solo si no existe |
| ERPNext | `Administrator` | `ERPNEXT_ADMIN_PASSWORD` | Una vez, al crear el sitio (`erpnext-create-site`) |
| Samba AD | `Administrator` (realm `AD.RESERVAVIVA.LAN`) | `SAMBA_ADMIN_PASSWORD` | Al provisionar el dominio, con `private/` vacía; después, `sembrar.sh` la reconcilia en cada arranque |
| Bases de datos | usuarios internos de MySQL, MariaDB y PostgreSQL | `OPENVPMS_DB_ROOT_PASSWORD`, `OPENVPMS_DB_PASSWORD`, `PRETIX_DB_PASSWORD`, `INVENTREE_DB_PASSWORD`, `ERPNEXT_DB_ROOT_PASSWORD` | Al inicializar cada volumen de datos |

El entrypoint de OpenVPMS rechaza una clave de administrador que no tenga al menos 8 caracteres con mayúscula, minúscula,
número y un carácter especial.

**H19: administrador de Pretix.** La imagen de Pretix trae de fábrica el usuario `admin@localhost` con una clave conocida,
y no crea administradores a partir de variables de entorno. En cada `arrancar`, la función `crear_admin_pretix` de
[`../levantar-sistema.sh`](../levantar-sistema.sh) hace tres cosas:

1. Crea el superusuario `PRETIX_ADMIN_EMAIL` si no existe.
2. **Borra `admin@localhost`**.
3. Comprueba ambas cosas con `assert`.

La clave se pasa por el entorno de `docker exec`, no por la línea de comandos. Si la función no lo consigue tras 6
intentos, el arranque termina con error.

## 5. Exposición de red

### Sin aislamiento de red entre departamentos

**El sistema ya no segmenta la red por departamento.** El switch del laboratorio obliga a una sola IP (la del equipo,
`HOST_IP`) y un puerto distinto por servicio, así que el 04/10/2026 se eliminaron las cinco redes que emulaban VLAN y se
sustituyeron por una única red de Docker, `reservaviva`. Consecuencias, sin matices:

- **Todos los contenedores comparten una red.** Cualquier contenedor alcanza a cualquier otro por su IP o su nombre. Un
  compromiso de, por ejemplo, la aplicación de Taquilla permite llegar a las bases de datos y a las aplicaciones de los demás
  departamentos. Ya no existe una barrera de red entre Médica, Taquilla, Logística y RRHH.
- **Todo lo publicado es accesible desde la LAN en `HOST_IP`:** las cuatro aplicaciones (18080-18083), el proxy web (80),
  LDAP y LDAPS (1389, 1636), el DNS (1053, y 53 por el reenviador de Windows) y el NTP (1123/udp). Ya no hay un "modo local"
  que limite el acceso al propio equipo.
- Las contraseñas de laboratorio están **públicas en git** y todo viaja por HTTP sin cifrar (salvo LDAPS): cualquier equipo de
  la misma red puede entrar como administrador en OpenVPMS, Pretix, InvenTree y ERPNext. El sistema solo debe usarse en
  una red de laboratorio.

Es una decisión impuesta por el switch del laboratorio, no una mejora de diseño. El diseño anterior, con una VLAN por
departamento, está en [`diseno-red/`](../diseno-red/README.md) como registro histórico.

**Lo que se conserva:**

- **Bases de datos y Redis sin publicar.** Ninguno tiene puerto en el equipo (`verificar` comprueba que no tienen
  `PortBindings` y que 5432, 3306 y 6379 están cerrados en `HOST_IP`). Siguen siendo alcanzables desde la red `reservaviva`
  por nombre de servicio, pero no desde la LAN.
- **`erpnext_internal`:** la MariaDB, los Redis y los workers de ERPNext están en una red privada a la que solo se unen
  `erpnext-backend` y `erpnext-hr` (además de `reservaviva`).
- **LDAPS con CA propia:** el bind simple solo se admite cifrado y las aplicaciones verifican el certificado del DC.
- **Control de acceso por grupos de AD dentro de cada aplicación:** solo entra en ERPNext quien está en `GG-RRHH` y en
  InvenTree quien está en `GG-Operaciones`.

Lo que ya no existe: la prueba negativa de segmentación de `verificar` (qué departamento alcanza a cuál) y la matriz entre
departamentos. `verificar` demuestra ahora que cada servicio está abierto donde se publica y que las bases de datos no
lo están ([`../sistema/verificar_arquitectura.md`](../sistema/verificar_arquitectura.md)).

### Qué se publica

Todos los puertos se publican en `HOST_IP` (variable de `sistema/test.env`; `192.168.1.26` en el laboratorio) y, además, las
cuatro aplicaciones en `127.0.0.1` con el mismo puerto. La lista está en
[`arquitectura.md`, "Puertos publicados"](arquitectura.md#7-puertos-publicados). `HOST_IP` es obligatoria: sin ella el compose
no arranca. Nada se publica en `0.0.0.0`. `--ip X` cambia `HOST_IP` solo en esa ejecución y `--intranet` autodetecta la IP de la
LAN.

Con Docker Engine en WSL, el 53 de la LAN lo atiende un reenviador de Windows (`sistema/reenviador-dns.ps1`, sin
privilegios de administrador) que pasa las consultas tal cual a bind9, publicado en `HOST_IP:1053`. Para el 1053 no se
crea ninguna regla de entrada: los clientes solo deben usar el 53 (no se ha medido desde otro equipo si el 1053 queda
filtrado).

El DNS expuesto no amplía la superficie: es autoritativo solo de `reservaviva.lan` y a la LAN no le hace recursión, así que
no sirve como resolvedor abierto ni para ataques de amplificación. Un cliente de fuera de la red de contenedores recibe
`REFUSED` para cualquier nombre ajeno a la zona. Hoy sí anuncia `ldap`, `ntp` y la delegación `ad.reservaviva.lan`, porque
sus puertos también están publicados en `HOST_IP`.

**Reglas de cortafuegos** que crea `sistema/habilitar-intranet-windows.ps1` (y que `-Deshacer` quita): reglas de **entrada**
solo desde la **subred local** de la interfaz elegida (por ejemplo `192.168.1.0/24`), en todos los perfiles (la Wi-Fi del
equipo de medida está en perfil "Pública", y una regla solo para "Privada" no aplicaría), tanto en el Firewall de Windows
como en el de Hyper-V para la VM de WSL. Cubren los puertos publicados: 80/tcp, 53 udp y tcp, 18080-18083/tcp, 1389 y
1636/tcp y el puerto NTP/udp. No cambia la acción por defecto de ningún perfil y no toca ICS ni Portmaster.

`networkingMode=mirrored` cambia la red de **toda** la distro de WSL, no solo la de Docker: cualquier servicio que escuche
dentro de WSL queda en las interfaces de Windows, aunque sin las reglas de entrada anteriores el cortafuegos lo filtra.

### Qué comprueba `verificar` sobre la exposición

`levantar-sistema.sh verificar` ([`../sistema/verificar_arquitectura.md`](../sistema/verificar_arquitectura.md)) comprueba:

- Cada servicio publicado está abierto en `HOST_IP:puerto`, desde el host y desde un contenedor de la red.
- Las bases de datos y los Redis no tienen puertos publicados y sus puertos están cerrados en `HOST_IP`.
- bind9 responde con autoridad a su zona y no resuelve nombres externos (NXDOMAIN para los contenedores, `REFUSED` para el anfitrión y la LAN).
- La delegación de `ad.reservaviva.lan` se sigue desde un contenedor de la red (registros SRV de `_ldap._tcp` y
  `_kerberos._tcp`).
- Los logins LDAPS funcionan con la CA interna y fallan con una CA ajena o con una clave errónea, y un usuario de otro
  grupo (`vet.prueba`) no entra.

Lo que no se prueba: el acceso desde otros equipos (los pasos están en [`operacion.md`](operacion.md#acceso-desde-la-lan)) ni el
switch físico.

## 6. Buenas prácticas y pendientes

### Cómo rotar las claves

Cambiar `sistema/test.env` **no basta** en un sistema ya inicializado. Casi todas las claves se aplican una sola vez: al
crear el volumen, el sitio o el usuario (tabla de la sección 4). Hay dos caminos:

- **Laboratorio desechable:** cambiar los valores de `test.env` y reinicializar con `levantar-sistema.sh borrar`
  (**borra todos los datos**: bases de datos, sitio de ERPNext y directorio). Si solo cambian claves del directorio, basta con
  `levantar-sistema.sh borrar-directorio`, que borra solo el contenedor `samba-ad` y sus volúmenes (`samba_data` y
  `samba_etc`), y un `arrancar`, que reprovisiona el dominio con las claves nuevas.
- **Conservando los datos, claves del directorio:** cambiar el valor en `test.env` y ejecutar `arrancar`. Las claves llegan a
  `samba-ad` por variables de entorno, y un simple `docker restart` **no las relee**; `arrancar` (`up -d`) recrea el
  contenedor porque su entorno cambió, con los mismos volúmenes. En cada arranque, `sembrar.sh` ejecuta `samba-tool user
  setpassword` con el valor de `test.env` sobre `Administrator`, `svc-lectura` y las cuatro cuentas de prueba, sin tocar nada
  más de las cuentas. La clave de `svc-lectura` también está en la configuración de las aplicaciones: `erpnext-ldap-config` la
  vuelve a escribir en cada `up` e `inventree-app` la lee del entorno. Este camino **no se ha ejecutado** como procedimiento
  de rotación. Una cuenta creada a mano con `samba-tool` (no sembrada) se cambia con `samba-tool user setpassword`.
- **Conservando los datos, el resto de claves:**
  1. Cambiar cada clave dentro de su servicio: en la aplicación o en la base de datos.
  2. Poner el mismo valor en `test.env`, para que los arranques siguientes y `verificar` sigan funcionando.

  Ningún script automatiza este camino y **no se ha probado**.

Si el repositorio se hizo público con las claves de laboratorio, hay que considerarlas comprometidas aunque se cambien
después: siguen en el historial de git.

### Qué faltaría para producción (no existe hoy)

- Sacar los secretos del repositorio: un `test.env` fuera de git o los *secrets* de Docker. Hoy `erpnext-create-site` recibe
  las claves por la línea de comandos (pendiente anotado en [`resultados-un-host.md`](resultados-un-host.md)).
- Segmentación de red entre departamentos (una red por departamento y reglas entre ellas), que el switch del laboratorio
  hoy impide, y limitar qué equipos de la LAN pueden alcanzar cada puerto publicado.
- Quitar la publicación del 389 si nadie la necesita (hoy solo admite bind seguro, pero sigue abierto en `HOST_IP`).
- Usuarios de prueba borrados, mapeo de roles en cada aplicación y una cuenta de servicio por aplicación en lugar de una
  compartida (**los grupos ya están resueltos**: el acceso lo decide `GG-RRHH` o `GG-Operaciones`). Cuentas de laboratorio sin
  la excepción de no caducar.
- Sustituir `privileged: true` de `samba-ad` por las capacidades concretas que necesite, y valorar un segundo controlador de
  dominio.
- Custodia de `ca.key` fuera del equipo que sirve los servicios, y un procedimiento de renovación de certificados con la
  recreación de los contenedores.
- HTTPS en las cuatro aplicaciones: hoy se sirven por HTTP, en `HOST_IP` (directo y por el proxy web) y en 127.0.0.1.
  El sitio natural para TLS sería ese proxy, con un certificado de la CA interna.
