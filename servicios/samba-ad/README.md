# Samba AD DC (Infraestructura, VLAN 99)

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
- **IP:** `10.10.99.10` en `vlan99_infra`, la misma que tenía `openldap`: es la que el DC ve como suya y con la que
  se registra en su propio DNS (si viera otra, o `127.0.0.1`, los clientes no lo alcanzarían).

## `entrypoint.sh`

Provisiona el dominio (`samba-tool domain provision --dns-backend=SAMBA_INTERNAL --use-rfc2307 ...`) **solo la
primera vez**, cuando el volumen `samba_data` (montado en `/var/lib/samba`) todavía no tiene `sam.ldb`. Con datos ya
existentes no reprovisiona: solo repite los pasos idempotentes y arranca `samba -F`.

En cada arranque (haya provisionado o no):
- copia `private/krb5.conf` a `/etc/krb5.conf` (lo primero no persiste entre arranques del contenedor, lo segundo sí,
  en `samba_data`);
- añade el FQDN a `/etc/hosts` si falta;
- copia `ca.crt`, `ldap.crt` y `ldap.key` (montados de solo lectura desde `../ca/certs/`, en `/certs`) a
  `/var/lib/samba/private/tls/` con `chmod 600`. **Trampa:** Samba rechaza la clave privada si no tiene permisos 0600
  exactos, y el montaje no se puede chmodear desde el host (queda con los permisos que le dio
  `generar-certificados.sh`, o los de otro dueño); por eso se copia en vez de usarse directamente. Si
  `generar-certificados.sh` regenera el certificado, hace falta recrear este contenedor para que lo recoja
  (`levantar-sistema.sh` ya lo hace, ver `recrear_ldap_si_cert_nuevo`);
- asegura en `smb.conf` (persiste en el volumen `samba_etc`, montado en `/etc/samba`): `dns forwarder = 10.10.99.11`
  (bind9/`dns-interno`; `SAMBA_INTERNAL` solo resuelve la zona AD), `tls enabled = yes` y las rutas del certificado,
  `interfaces = eth0` y `bind interfaces only = yes`, y `ldap server require strong auth = yes` (valor por defecto de
  Samba: el bind simple solo se acepta por TLS; InvenTree y ERPNext ya usan LDAPS, así que se deja así en vez de
  bajar la seguridad).

Arranca `samba -F` en segundo plano, siembra (ver abajo) y espera a ese proceso, reenviándole la señal de parada de
Docker.

## `sembrar.sh`

Idempotente: comprueba antes de crear (o interpreta un "ya existe" de `samba-tool` como éxito), así que repetirla en
cada arranque no duplica nada.

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

## Límites

`privileged: true` (Samba guarda las ACL de AD en atributos extendidos `security.*`); no se publican el 445 (SMB, lo
ocupa Windows en el host), el 88 (Kerberos, se prueba dentro de la red) ni el 53 (lo da bind9); no se une ningún
equipo Windows/Linux al dominio (fuera de alcance). Detalle completo: `docs/directorio-activo.md`.
