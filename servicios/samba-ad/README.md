# Samba AD DC (Infraestructura)

Directorio central del zoológico: Active Directory Domain Controller (Samba 4.22 sobre Debian trixie), en
sustitución de OpenLDAP. Da LDAP/LDAPS (389/636, firmado por la CA interna de [`../ca/`](../ca/README.md)),
Kerberos y su propio DNS interno (solo de su zona; el resto lo resuelve bind9 por reenvío). No hay migración de
datos: el dominio se provisiona desde cero. La justificación del cambio y la guía de migración (por si algún día
hiciera falta partir de un OpenLDAP con datos reales) están en `docs/directorio-activo.md`.

- **Servicio de compose:** `samba-ad` (`container_name: samba-ad`; el nombre está escrito tal cual en
  `levantar-sistema.sh` y en los scripts de verificación: no cambiarlo).
- **Imagen propia** (`Dockerfile`): `debian:trixie` + `samba-ad-dc samba-ad-provision krb5-user krb5-config winbind
  ldap-utils dnsutils acl attr python3-setproctitle`. **Trampa:** en Debian trixie `samba-ad-provision` va separado
  de `samba-ad-dc` y trae los LDIF del esquema de AD; sin él, `samba-tool domain provision` falla con
  `File [...AD_DS_Attributes_Windows_Server_v1903.ldf] not found` y el contenedor queda en bucle de reinicio.
- **Realm:** `AD.RESERVAVIVA.LAN` (subdominio; Samba no admite `.local` ni renombrar el realm después).
  **Dominio/NetBIOS:** `RESERVAVIVA`. **DN base:** `DC=ad,DC=reservaviva,DC=lan`.
- **Hostname:** `dc1` (≤ 15 caracteres, lo exige Samba), **FQDN:** `dc1.ad.reservaviva.lan`.
- **IP:** `10.10.99.10` en la red `reservaviva` (`NET_INTERNA`), la única IP fija junto con la de `dns-interno` (`.11`): es la que
  el DC ve como suya y con la que se registra en su propio DNS (si viera otra, o `127.0.0.1`, los clientes no lo alcanzarían), y
  cambiarla obligaría a reprovisionar el directorio. Dentro de `entrypoint.sh` es la variable `DC_IP`.

## `entrypoint.sh`

Provisiona el dominio (`samba-tool domain provision --dns-backend=SAMBA_INTERNAL
--option="dns forwarder=10.10.99.11" --use-rfc2307 ...`) **solo la primera vez**, y solo si `private/` (en el
volumen `samba_data`) está realmente vacía.
Con datos ya existentes no reprovisiona: solo repite los pasos idempotentes y arranca `samba -F`.

**Trampa (real, ya la sufrimos):** `samba-tool domain provision` no es reanudable. Si el contenedor se reinicia a
medio provisionar (nos pasó con el motor de Docker inestable por memoria), puede quedar `sam.ldb` escrito pero
`secrets.ldb` de un intento distinto (o al revés), y `samba -F` muere en bucle con `Failed to obtain server
credentials... NT_STATUS_CANT_ACCESS_DOMAIN_INFO` — mientras `sembrar.sh` sigue "funcionando" porque `samba-tool`
escribe directo en `sam.ldb`, sin pasar por el proceso `samba`. Por eso NO se comprueba solo "existe sam.ldb": se usa
una marca propia, `private/.provisionado-reserva-viva`, que solo se escribe cuando `domain provision` termina con
éxito. Si `private/` tiene datos pero falta la marca, el entrypoint **para con un error explícito** en vez de
reprovisionar sobre restos o dejar que `samba` arranque con credenciales rotas; la solución es
`./levantar-sistema.sh borrar-directorio` (vacía `samba_data` y `samba_etc`) y dejar que reprovisione desde cero.

También por eso se pasa `--option="dns forwarder=..."` explícito a `domain provision` (no existe un flag dedicado
`--dns-forwarder`, comprobado con `samba-tool domain provision --help`): sin fijarlo, autodetecta el `resolv.conf`
del propio contenedor (el DNS interno de Docker, `127.0.0.11`) y lo escribe en `smb.conf`; si luego el entrypoint
"asegurara" la línea correcta con un simple `grep`, no vería el valor distinto ya presente y añadiría una SEGUNDA
línea `dns forwarder` duplicada (Samba se queda con la última, que sería la incorrecta).

En cada arranque (haya provisionado o no):
- copia `private/krb5.conf` a `/etc/krb5.conf` (lo primero no persiste entre arranques del contenedor, lo segundo sí,
  en `samba_data`);
- añade el FQDN a `/etc/hosts` si falta;
- copia `ca.crt`, `ldap.crt` y `ldap.key` (montados de solo lectura desde `../ca/certs/`, en `/certs`) a
  `/var/lib/samba/private/tls/` con `chmod 600`. **Trampa:** Samba rechaza la clave privada si no tiene permisos 0600
  exactos, y el montaje no se puede chmodear desde el host (queda con los permisos que le dio
  `generar-certificados.sh`, o los de otro dueño); por eso se copia en vez de usarse directamente. Si
  `generar-certificados.sh` regenera el certificado, hace falta **reiniciar** este contenedor (no recrearlo) para que lo
  recoja (`levantar-sistema.sh` ya lo hace, en la función `reiniciar_directorio_si_cert_nuevo`);
- asegura en `smb.conf` (persiste en el volumen `samba_etc`, montado en `/etc/samba`): `tls enabled = yes` y las
  rutas del certificado, `interfaces = eth0` y `bind interfaces only = yes`, y `ldap server require strong auth =
  yes` (valor por defecto de Samba: el bind simple solo se acepta por TLS; InvenTree y ERPNext ya usan LDAPS, así que
  se deja así en vez de bajar la seguridad). `dns forwarder` no se asegura aquí: ya la fija `domain provision` (ver
  arriba), y repetirla con el mismo patrón `grep`/`sed` volvería a exponerse a la duplicidad.

Arranca `samba -F --debug-stdout` en segundo plano (el log va a `docker logs`, no a `/var/log/samba/log.samba`:
así se vio el error real de credenciales), siembra (ver abajo) y espera a ese proceso, reenviándole la señal de
parada de Docker. Si `samba` muere mientras se está sembrando, el entrypoint no sigue reintentando la siembra: para
y deja que el código de salida real de `samba` llegue al contenedor (para que `docker ps`/`docker inspect` lo
reflejen con claridad en vez de quedarse "sembrando" indefinidamente sobre un proceso ya muerto).

## `sembrar.sh`

Idempotente: comprueba antes de crear (o interpreta un "ya existe" de `samba-tool` como éxito), así que repetirla en
cada arranque no duplica nada.

**Trampa (real, ya la sufrimos):** `samba-tool user create` no toca la clave de una cuenta que ya existía — solo la
fija al crearla. Como la siembra es idempotente y se repite en cada arranque, una cuenta creada en un arranque o una
provisión anterior se queda con la clave de entonces aunque `sistema/test.env` cambie después; `kinit`/el bind LDAPS
fallan con "contraseña incorrecta" sin que nada avise. Por eso cada cuenta (`vet.prueba`, `logistica.prueba`,
`taquilla.prueba`, `rrhh.prueba`, `svc-lectura` y también `Administrator`, cuya clave normalmente solo fija `domain
provision` la primera vez) lleva además un `samba-tool user setpassword` en cada arranque, que **reconcilia** la
clave real con la de `test.env` sin tocar nada más de la cuenta. No se usa `--must-change-at-next-login`: rompería
los logins automáticos de `levantar-sistema.sh verificar`.

**Decisión de laboratorio: las claves de las 4 cuentas de prueba y de `svc-lectura` no caducan** (`samba-tool user
setexpiry --noexpiry`, en cada arranque, igual que la reconciliación de arriba). La política del dominio
(`maxPwdAge`) sigue intacta — no se toca —, pero sin esto la clave de una cuenta caduca a los 41 días (valor por
defecto de Samba AD) y un login de prueba en una sesión de clase fallaría por caducidad, no por credenciales.
`Administrator` no lleva `setexpiry`: no es una cuenta de demostración.

| Objeto | OU / grupo |
|---|---|
| `OU=Medica`, `OU=Operaciones`, `OU=RRHH`, `OU=Servicios`, `OU=Grupos` | bajo `DC=ad,DC=reservaviva,DC=lan` |
| Grupos `GG-Medica`, `GG-Operaciones`, `GG-RRHH` | `OU=Grupos` |
| `vet.prueba` | `OU=Medica`, grupo `GG-Medica` |
| `logistica.prueba`, `taquilla.prueba` | `OU=Operaciones`, grupo `GG-Operaciones` |
| `rrhh.prueba` | `OU=RRHH`, grupo `GG-RRHH` |
| `svc-lectura` (cuenta de búsqueda de InvenTree y ERPNext) | `OU=Servicios`, sin grupo, clave sin caducidad |

Cada usuario se crea con `--use-username-as-cn` (si no, el CN sería el nombre completo) y
`--mail-address=<uid>@reservaviva.lan`. Las claves son las variables de siempre de
[`sistema/test.env`](../../sistema/test.env) (`LDAP_SVC_LECTURA_PASSWORD`, `LDAP_PRUEBA_{VET,LOGISTICA,TAQUILLA,
RRHH}_PASSWORD`), más `SAMBA_ADMIN_PASSWORD` (antes `LDAP_ADMIN_PASSWORD`) para el administrador del dominio, creado
por `domain provision`. **Deben cumplir la complejidad de contraseñas de AD** (longitud mínima, al menos 3 de las 4
categorías de caracteres, y no contener el nombre de la cuenta): si `samba-tool` rechaza alguna, se cambia su valor
en `test.env`, nunca la política del dominio.

## Consultarlo

AD no permite búsquedas anónimas salvo al rootDSE (por eso el healthcheck de compose consulta solo eso). Para todo
lo demás hace falta autenticarse, por UPN (`usuario@ad.reservaviva.lan`) o por el DN completo. Kerberos:
`kinit vet.prueba@AD.RESERVAVIVA.LAN` (dentro del contenedor `samba-ad`, que tiene `krb5-user`).

## Compose

- **Healthcheck:** `test -f /run/samba-ad-sembrado.ok` y un `ldapsearch` anónimo al rootDSE por `10.10.99.10` (Samba no escucha en
  loopback). La marca la crea el entrypoint al terminar la siembra de cada arranque: sin ella, un consumidor podría hacer su
  primer bind con una clave todavía vieja. `inventree-app`, `erpnext-backend` y `erpnext-ldap-config` dependen de
  `samba-ad: service_healthy`.
- **Resolver:** `dns: 10.10.99.11` (bind9), que delega `ad.reservaviva.lan` de vuelta a este contenedor.
- **Volúmenes:** `samba_data` (`/var/lib/samba`) y `samba_etc` (`/etc/samba`). `./levantar-sistema.sh borrar-directorio` borra
  solo estos dos y el contenedor.
- **Puertos:** se publican el 389 y el 636 en `${HOST_IP}` (`LDAP_PORT` y `LDAPS_PORT`; 1389 y 1636 en `test.env`).

## Límites

`privileged: true` (Samba guarda las ACL de AD en atributos extendidos `security.*`); no se publican el 445 (SMB, lo
ocupa Windows en el host), el 88 (Kerberos, se prueba dentro de la red) ni el 53 (lo da bind9); no se une ningún
equipo Windows/Linux al dominio (fuera de alcance). Detalle completo: `docs/directorio-activo.md`.
