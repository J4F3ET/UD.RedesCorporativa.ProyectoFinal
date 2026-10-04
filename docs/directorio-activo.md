# Directorio activo: Samba AD DC

El directorio central de Reserva Viva es un Active Directory Domain Controller (Samba 4.22 sobre Debian trixie) que sustituyó a OpenLDAP. Este documento explica por qué, cómo está montado, cómo autentican contra él InvenTree y ERPNext, cómo se administra y cómo se migraría un OpenLDAP con datos reales. Todo sale del [`docker-compose.yml`](../docker-compose.yml) de la raíz y de [`servicios/samba-ad/`](../servicios/samba-ad/README.md); si algún día difieren de este documento, manda el código.

Otros documentos: la red y el recorrido de una conexión LDAPS en [arquitectura.md](arquitectura.md#6-flujos); la CA, la cuenta de servicio y dónde están las claves en [seguridad.md](seguridad.md#3-directorio-activo-y-ldaps); el uso diario de cada aplicación en [aplicaciones.md](aplicaciones.md); las pasadas de `verificar` que lo comprueban en [resultados-un-host.md](resultados-un-host.md).

## 1. Resumen y justificación

| Aplicación | ¿Directorio? | Cómo, o por qué no |
|---|---|---|
| ERPNext (RRHH) | Sí, LDAPS con la cadena verificada | "LDAP Settings" de Frappe (`Active Directory`), que escribe el trabajo `erpnext-ldap-config`. Entra quien sea miembro de `GG-RRHH` |
| InvenTree (Logística) | Sí, LDAPS con la cadena verificada | `django-auth-ldap`, con las variables `INVENTREE_LDAP_*` de `inventree-app`. Entra quien sea miembro de `GG-Operaciones` |
| OpenVPMS (Médica) | No | La versión 2.4.0.1 no tiene soporte LDAP (sección 9) |
| Pretix (Taquilla) | No | Solo existe un plugin de terceros que no verifica el certificado del servidor (sección 9) |

OpenVPMS y Pretix siguen con su administrador local ([aplicaciones.md](aplicaciones.md)).

**Qué aporta AD frente a OpenLDAP.** El directorio anterior era un árbol `inetOrgPerson` con cuatro OU, sin grupos. Samba AD da, con la misma IP y el mismo nombre para las aplicaciones:

- **Kerberos** (con tickets y SSO), además de LDAP/LDAPS, en el mismo servicio.
- **DNS propio con registros SRV** (`_ldap._tcp`, `_kerberos._tcp`) para la zona AD, que bind9 delega al DC (sección 2).
- **Grupos y `memberOf`**: el acceso a cada aplicación lo decide la pertenencia a un grupo, no la OU donde está la cuenta (sección 4). Era el pendiente de "grupos LDAP" de la lista de producción.
- **Políticas de contraseña** del dominio (complejidad, caducidad), que el directorio anterior no tenía configuradas.
- **Administración con `samba-tool`** (y RSAT/ADUC desde un Windows unido al dominio, aunque la unión de equipos queda fuera de alcance, sección 9).
- **Compatibilidad con cualquier aplicación que soporte "Active Directory"**: ERPNext lo trae como tipo de servidor LDAP propio.

## 2. Realm, DNS y delegación

| Dato | Valor |
|---|---|
| Realm Kerberos | `AD.RESERVAVIVA.LAN` |
| Dominio NetBIOS | `RESERVAVIVA` |
| DN base | `DC=ad,DC=reservaviva,DC=lan` |
| Controlador | `dc1`, FQDN `dc1.ad.reservaviva.lan`, contenedor `samba-ad`, `10.10.99.10` fija en la red `reservaviva` |
| Roles | `--server-role=dc`, DNS `SAMBA_INTERNAL`, `--use-rfc2307` |
| Volúmenes | `samba_data` (`/var/lib/samba`) y `samba_etc` (`/etc/samba`) |

El realm es un **subdominio** (`ad.`) porque Samba no admite `.local` ni renombrar el realm después. El sufijo antiguo desaparece del DN: el árbol ya no cuelga de `reservaviva.local`. El hostname `dc1` respeta el límite de 15 caracteres de Samba. La IP `10.10.99.10` es la que tenía `openldap`: es la que el DC ve como suya y registra en su propio DNS (se provisionó con ella), y por eso es una de las dos únicas IP fijas del sistema (la otra es `dns-interno`, `10.10.99.11`). Para las aplicaciones y los clientes, `ldap.reservaviva.lan` apunta a `HOST_IP`, donde se publica el 636.

**DNS: delegación real, no zona forward.** El plan preveía una zona `type forward` en bind9 hacia el DC. No funciona: `ad.reservaviva.lan` cuelga de `reservaviva.lan`, de la que bind9 es **autoritativo**, y una zona autoritativa responde ella misma (`NXDOMAIN` con `aa=1`) a cualquier nombre de su árbol; la zona forward nunca se llega a consultar. Lo que hay es la delegación estándar de DNS, en la única zona ([`db.reservaviva.lan.tpl`](../servicios/bind9/zones/db.reservaviva.lan.tpl)):

```
ad          IN NS   dc1.ad.reservaviva.lan.
dc1.ad      IN A    10.10.99.10          ; el glue (IP fija del DC)
```

Para seguir esa delegación, bind9 lleva `recursion yes` limitada a los contenedores de la red (`allow-recursion`, la subred sin el gateway `.1`; el anfitrión y la LAN no tienen recursión), y para que la recursión no sirva nada más, una raíz `"."` **autoritativa y vacía** (`zones/db.raiz-vacia`): cualquier nombre que no sea de `reservaviva.lan` (ni de su delegación) da NXDOMAIN a los contenedores por política, tenga o no salida la red. Detalle y razones en [`servicios/bind9/README.md`](../servicios/bind9/README.md).

Cuatro cosas más que conviene tener claras:

- **El DC usa a bind9 como resolver** (`dns: 10.10.99.11` en el compose): `kinit` y `samba_dnsupdate`, dentro del contenedor, resuelven por SRV y el DNS embebido de Docker no sabe nada de la zona AD. bind9 delega de vuelta al propio DC para esa zona. A la inversa, el `dns forwarder` del DNS interno de Samba es `10.10.99.11` (se fija con `--option` en `domain provision`): para todo lo que no es su zona, Samba pregunta a bind9.
- **La delegación solo sirve dentro de la red.** El glue apunta a `10.10.99.10`, una IP de contenedor que un equipo de la LAN no alcanza; los registros SRV de la zona AD los resuelve un contenedor de `reservaviva` consultando a `dns-interno` (`10.10.99.11`). Las aplicaciones no la necesitan: encuentran el DC por `extra_hosts` (`ldap.reservaviva.lan` → `HOST_IP` en `inventree-app` y `erpnext-backend`).
- **El certificado LDAPS** lo firma la CA del proyecto ([`servicios/ca/`](../servicios/ca/README.md)) con los SAN `ldap.reservaviva.lan`, `dc1.ad.reservaviva.lan`, `samba-ad`, `localhost`, `10.10.99.10`, `127.0.0.1` y la `HOST_IP`. Se conservan los nombres de archivo `ldap.crt`/`ldap.key` y la misma `/certs/ca.crt` en los clientes. Samba rechaza la clave privada si no tiene permisos 0600, y el montaje de solo lectura no se puede chmodear: el entrypoint copia los tres ficheros a `/var/lib/samba/private/tls/` con `chmod 600` **en cada arranque**. Un certificado nuevo exige por tanto **reiniciar** `samba-ad` (no recrearlo); el lanzador lo hace solo ([operacion.md](operacion.md#certificado-nuevo)).

## 3. Objetos del directorio

Los crea [`sembrar.sh`](../servicios/samba-ad/sembrar.sh) en cada arranque, de forma idempotente (comprueba antes de crear). Bajo `DC=ad,DC=reservaviva,DC=lan`:

```
DC=ad,DC=reservaviva,DC=lan
├── OU=Medica         vet.prueba                       (miembro de GG-Medica)
├── OU=Operaciones    logistica.prueba, taquilla.prueba (miembros de GG-Operaciones)
├── OU=RRHH           rrhh.prueba                      (miembro de GG-RRHH)
├── OU=Servicios      svc-lectura                      (cuenta de búsqueda; sin grupo)
└── OU=Grupos         GG-Medica, GG-Operaciones, GG-RRHH
```

| Cuenta | OU | Grupo | Aplicación en la que puede entrar |
|---|---|---|---|
| `vet.prueba` | `OU=Medica` | `GG-Medica` | Ninguna (OpenVPMS no usa LDAP; ni InvenTree ni ERPNext la aceptan) |
| `logistica.prueba` | `OU=Operaciones` | `GG-Operaciones` | InvenTree |
| `taquilla.prueba` | `OU=Operaciones` | `GG-Operaciones` | InvenTree, por configuración (**no verificado** con un login); Pretix no usa LDAP |
| `rrhh.prueba` | `OU=RRHH` | `GG-RRHH` | ERPNext |
| `svc-lectura` | `OU=Servicios` | — | Ninguna: es la cuenta con la que las dos aplicaciones buscan |

- **Los CN coinciden con el login** (`--use-username-as-cn`): sin esa opción el CN sería el nombre completo y el DN no sería previsible. Así, el DN de `vet.prueba` es `CN=vet.prueba,OU=Medica,DC=ad,DC=reservaviva,DC=lan`.
- Cada cuenta de prueba lleva `mail` (`<uid>@reservaviva.lan`), `givenName` y `sn` (apellido `Prueba`). `svc-lectura` lleva `mail` pero no nombre. **`givenName` y `sn` no son decorativos**: ERPNext los copia a `first_name`/`last_name` al crear el User, y `first_name` es obligatorio en el doctype; sin ellos el primer login fallaba con `MandatoryError`. `sembrar.sh` los reconcilia con `ldapmodify` en cada arranque, porque `samba-tool user create` no toca una cuenta que ya existía.
- **Los grupos no pueden llamarse igual que ningún usuario** (de ahí el prefijo `GG-`).
- **Claves.** Salen de [`sistema/test.env`](../sistema/test.env), la única fuente (`LDAP_PRUEBA_<UID>_PASSWORD`, `LDAP_SVC_LECTURA_PASSWORD` y `SAMBA_ADMIN_PASSWORD`; esta última se llamaba `LDAP_ADMIN_PASSWORD`). Tabla en [seguridad.md](seguridad.md#3-directorio-activo-y-ldaps). **Deben cumplir la complejidad de AD**; dos claves de `test.env` se cambiaron por no cumplirla (una contenía el nombre de la propia cuenta). Se cambió la clave, no la política del dominio.
- **Reconciliación.** `samba-tool user create` solo fija la clave al crear. Para que `test.env` siga siendo la fuente de verdad, cada arranque ejecuta además `samba-tool user setpassword` sobre las cuentas sembradas (y `Administrator`), sin tocar nada más. No se usa `--must-change-at-next-login`: rompería los logins automáticos de `verificar`.
- **Sin caducidad.** Las cuatro cuentas de prueba y `svc-lectura` llevan `samba-tool user setexpiry --noexpiry` en cada arranque. Es una decisión de laboratorio: la política del dominio (`maxPwdAge`) no se toca, pero sin esto la clave caducaría a los 41 días (el valor por defecto de Samba AD) y un login en una sesión de clase fallaría por caducidad. En UAC, el resultado es `66048` (`NORMAL_ACCOUNT` + `DONT_EXPIRE_PASSWORD`). `Administrator` no lleva `setexpiry`: no es una cuenta de demostración.
- **Healthcheck.** El servicio solo pasa a `healthy` cuando la siembra de **este** arranque terminó (marca `/run/samba-ad-sembrado.ok`, que el entrypoint borra al empezar) **y** el rootDSE responde. Sin la marca, LDAP respondería antes de que `sembrar.sh` reconcilie las claves y `inventree-app`, `erpnext-backend` y `erpnext-ldap-config` (que dependen de `samba-ad: service_healthy`) harían su primer bind con una clave vieja. AD no permite consultas anónimas salvo al rootDSE, que es lo único que puede consultar un healthcheck sin credenciales.

## 4. Cómo autentican InvenTree y ERPNext

### Lo común

- **Servidor:** `ldaps://ldap.reservaviva.lan:LDAPS_PORT` (1636 en `test.env`). El nombre lo fija `extra_hosts` hacia `HOST_IP`, donde se publica el 636 de `samba-ad`, para que coincida con el certificado sin depender del DNS ([arquitectura.md](arquitectura.md#6-flujos)).
- **Verificación TLS:** contra la CA interna, montada desde `servicios/ca/certs/ca.crt` en `/certs/ca.crt` (solo lectura) en `inventree-app` y `erpnext-backend`. Con la CA del sistema, o con otra CA, la conexión falla.
- **Solo LDAPS.** Samba lleva `ldap server require strong auth = yes` (el valor por defecto, [CVE-2016-2112](https://www.samba.org/samba/security/CVE-2016-2112.html)): un bind simple por el 389 sin cifrar se rechaza con "Strong(er) authentication required". Las dos aplicaciones usan LDAPS, así que se dejó en `yes` en vez de bajar la seguridad.
- **Flujo.** (1) La aplicación hace bind con `svc-lectura` (`CN=svc-lectura,OU=Servicios,DC=ad,DC=reservaviva,DC=lan`). (2) Busca al usuario por `sAMAccountName` en **toda la base del dominio**, con un filtro que exige además `memberOf` del grupo de su departamento. (3) Con el DN que encontró, hace bind con la clave del propio usuario. Si el usuario no existe, o no es miembro del grupo, la búsqueda no devuelve nada y recibe "clave inválida".
- **Clave de `svc-lectura`:** `LDAP_SVC_LECTURA_PASSWORD` en `sistema/test.env`, una sola cuenta compartida por las dos aplicaciones: el compose pasa la variable a InvenTree (`INVENTREE_LDAP_BIND_PASSWORD`), a `erpnext-ldap-config` y a `samba-ad` (que la siembra).
- **Arranque.** `inventree-app`, `erpnext-backend` y `erpnext-ldap-config` tienen `depends_on: samba-ad: condition: service_healthy`.

### El efecto del grupo

El filtro decide el acceso; la OU ya no. La base de búsqueda es la raíz del dominio y quien restringe es `memberOf`:

| Aplicación | Filtro |
|---|---|
| InvenTree | `(&(objectClass=user)(sAMAccountName=%(user)s)(memberOf=CN=GG-Operaciones,OU=Grupos,DC=ad,DC=reservaviva,DC=lan))` |
| ERPNext | `(&(sAMAccountName={0})(memberOf=CN=GG-RRHH,OU=Grupos,DC=ad,DC=reservaviva,DC=lan))` |

- Para dar o quitar el acceso a una aplicación hay que **añadir o quitar la cuenta del grupo** (sección 6); mover la cuenta de OU no cambia nada.
- La pertenencia debe ser **directa**: AD no expande grupos anidados con un `memberOf` simple (haría falta la regla de coincidencia `1.2.840.113556.1.4.1941`, que aquí no se usa porque `sembrar.sh` no anida grupos).
- `Administrator` y `svc-lectura` no están en ningún grupo `GG-*`, así que no entran en las aplicaciones por LDAP.
- `vet.prueba` (`GG-Medica`) no entra en ninguna de las dos: es la prueba negativa que hace `verificar`.

### InvenTree

- `django-auth-ldap`, configurado con `INVENTREE_LDAP_*` en `inventree-app`: `OPT_X_TLS_CACERTFILE=/certs/ca.crt` y `OPT_X_TLS_REQUIRE_CERT=OPT_X_TLS_DEMAND`; base `DC=ad,DC=reservaviva,DC=lan` y el filtro de arriba.
- El mapeo de atributos (`first_name`, `last_name`, `email` desde `givenName`, `sn`, `mail`) es el valor por defecto de InvenTree, sin cambios.

### ERPNext

- "LDAP Settings" de Frappe (`ldap3`), que escribe el trabajo idempotente `erpnext-ldap-config` en cada arranque: `ldap_directory_server: "Active Directory"`, `ldap_username_field: sAMAccountName`, `mail`/`givenName`/`sn` como campos de correo y nombre, `require_trusted_certificate: Yes` y `local_ca_certs_file: /certs/ca.crt`. Búsqueda de usuarios en la raíz del dominio y de grupos en `OU=Grupos`. El campo `base_dn` de Frappe **no es la base de búsqueda**: es el DN con el que se autentica la cuenta de servicio.
- `erpnext-ldap-config` guarda con `ignore_mandatory`: **no se conecta al DC** al guardar, y por eso no necesita llegar a la red `reservaviva`. La prueba real es el login. Quien habla LDAPS es `erpnext-backend`.
- El `ssl_tls_mode` es `Off` porque la conexión ya va por `ldaps://`.

## 5. Kerberos

El DC es también el KDC. Su `krb5.conf` lo genera `domain provision` en `private/krb5.conf` (volumen `samba_data`); el entrypoint lo copia a `/etc/krb5.conf` en cada arranque, porque `/etc` del contenedor no persiste. El 88 **no se publica** en el host: Kerberos se prueba dentro del contenedor, que tiene `krb5-user`.

```bash
docker exec -it samba-ad kinit vet.prueba@AD.RESERVAVIVA.LAN     # pide la clave; el realm va en mayúsculas
docker exec samba-ad klist                                       # el TGT: vet.prueba@AD.RESERVAVIVA.LAN
docker exec samba-ad kdestroy                                    # descarta el ticket
```

`kinit` encuentra el KDC por los registros SRV de `_kerberos._tcp.ad.reservaviva.lan`, que el contenedor resuelve por bind9 (sección 2). Desde otro contenedor de `reservaviva` se pueden consultar a mano:

```bash
dig @10.10.99.11 _ldap._tcp.ad.reservaviva.lan SRV +short
dig @10.10.99.11 _kerberos._tcp.ad.reservaviva.lan SRV +short
```

Una consulta LDAP autenticada (por UPN, que evita adivinar el DN) y la única anónima que AD admite:

```bash
docker exec -it samba-ad ldapsearch -H ldaps://ldap.reservaviva.lan -D vet.prueba@ad.reservaviva.lan -W \
  -b "DC=ad,DC=reservaviva,DC=lan" "(sAMAccountName=vet.prueba)" memberOf
docker exec samba-ad ldapsearch -x -H ldap://10.10.99.10 -b '' -s base      # rootDSE, sin autenticar
```

## 6. Administración con `samba-tool`

`samba-tool` se ejecuta dentro del contenedor. Sin la clave en la línea de comandos, `samba-tool` la pide por la terminal (`-it`):

```bash
# Alta de un usuario en OU=Operaciones (mismo patrón que sembrar.sh)
docker exec -it samba-ad samba-tool user create ana.perez \
  --userou="OU=Operaciones" --use-username-as-cn \
  --given-name=Ana --surname=Perez --mail-address=ana.perez@reservaviva.lan

# Alta en un grupo: es lo que le da acceso a InvenTree
docker exec samba-ad samba-tool group addmembers GG-Operaciones ana.perez
docker exec samba-ad samba-tool group listmembers GG-Operaciones

# Cambio de clave (la pide por la terminal)
docker exec -it samba-ad samba-tool user setpassword ana.perez

# Más
docker exec samba-ad samba-tool user list
docker exec samba-ad samba-tool group removemembers GG-Operaciones ana.perez
docker exec samba-ad samba-tool user setexpiry ana.perez --noexpiry
```

- Las cuentas que **no** están en `sembrar.sh` persisten en el volumen `samba_data` y solo desaparecen con `borrar-directorio` ([operacion.md](operacion.md#directorio-borrar-directorio)). Las que sí están se reconcilian: **cambiar a mano la clave de `vet.prueba` no sobrevive al siguiente arranque del contenedor**, que la devuelve a la de `test.env` (para rotarla, [seguridad.md](seguridad.md#cómo-rotar-las-claves)).
- La complejidad de AD aplica a toda clave nueva: `samba-tool` rechaza las que no la cumplen.
- Los usuarios entran en la aplicación **sin permisos** (ver los límites, sección 9): un administrador debe asignárselos dentro de InvenTree o ERPNext.

## 7. Qué se comprueba

`levantar-sistema.sh verificar` ([`sistema/verificar_arquitectura.md`](../sistema/verificar_arquitectura.md)) cubre el directorio en dos sitios; las cifras de cada pasada están solo en [resultados-un-host.md](resultados-un-host.md#verificación-de-la-arquitectura-levantar-sistema-verificar).

| Comprobación | Cómo |
|---|---|
| Login de un usuario de su departamento, con clave correcta | API de login LDAP de Frappe (ERPNext) y `/api/user/token/` (InvenTree), con `docker exec` desde sus contenedores |
| Clave errónea | Rechazada en las dos |
| `ldapsearch` por LDAPS desde `samba-ad` | Válido con la CA interna y fallido con una CA ajena |
| `docker compose down` (sin `-v`) + `up -d` | Los casos anteriores se repiten igual (con `--persistencia`; el modo `--rapido` lo omite) |
| Registros SRV `_ldap._tcp` y `_kerberos._tcp` de la zona AD | Consultados a bind9 desde un contenedor de la red: demuestra la delegación |
| `kinit vet.prueba@AD.RESERVAVIVA.LAN` y `klist` | Dentro de `samba-ad`, con la clave por stdin |
| Pertenencia a grupos | `samba-tool group listmembers` de cada `GG-*` |
| Prueba negativa de grupos | `vet.prueba` (`GG-Medica`) no entra ni en ERPNext ni en InvenTree |
| `rootDSE` anónimo | Bind anónimo y búsqueda al LDAP del DC desde un contenedor de la red (`ldapprobe.py`, `HOST_IP:LDAP_PORT`) |

`verificar` **no comprueba**: el rechazo de otros usuarios de otro departamento (por ejemplo `rrhh.prueba` en InvenTree), el login de `taquilla.prueba`, ni el botón "Login with LDAP" del formulario `/login` de ERPNext, que no se ha probado en un navegador ([pendientes](resultados-un-host.md#pendientes)).

## 8. Guía de migración OpenLDAP → Samba AD

Esta guía es para quien parta de un OpenLDAP **con datos reales**. En este proyecto no hubo migración de datos: el dominio se provisionó desde cero (ver abajo por qué). La guía sale de la investigación previa al cambio; el camino de exportar/transformar/recrear **no se ejecutó** aquí.

**Qué dice la wiki de Samba.** No existe una página "Migrating from OpenLDAP" (esa URL da 404). La única vía oficial es `samba-tool domain classicupgrade`, pensada para dominios NT4/Samba 3 con el backend `ldapsam`.

### Si el directorio tiene esquema Samba: `classicupgrade`

[Migrating a Samba NT4 Domain to Samba AD (Classic Upgrade)](https://wiki.samba.org/index.php/Migrating_a_Samba_NT4_Domain_to_Samba_AD_(Classic_Upgrade)) solo sirve si OpenLDAP guarda las cuentas con `sambaSamAccount` (`passdb` `ldapsam`). En ese caso migra usuarios, grupos y **contraseñas**, porque parte del hash NT que el esquema Samba ya almacena.

- Hay que subir el `sizelimit` de slapd a `unlimited` antes: por defecto trunca a 500 entradas, y la migración se haría con un directorio incompleto.
- Hay un bug conocido (#9908): no se migran todos los atributos. Hay que revisar el resultado.
- Reserva Viva **no** estaba en este caso: sus usuarios eran `inetOrgPerson` sin `sambaSamAccount`, así que `classicupgrade` no aplicaba.

### Si el directorio es posix/inetOrgPerson: exportar, transformar y recrear

Es el caso de Reserva Viva. No hay una herramienta que lo haga (no existe ningún script mantenido para esta migración). El camino:

1. **Exportar** con `ldapsearch -LLL` o con `slapcat`. Con `ldapsearch`, el límite de tamaño de slapd (`sizelimit`, 500 por defecto) trunca la salida si no se sube a `unlimited`; `slapcat` lee la base directamente, sin pasar por el servidor.
2. **Transformar** el LDIF:

   | OpenLDAP | Samba AD |
   |---|---|
   | `uid` | `sAMAccountName` (máximo 20 caracteres; no puede chocar con el nombre de un grupo) |
   | `homeDirectory` | `unixHomeDirectory` |
   | `memberUid` | miembros de un grupo, con `samba-tool group addmembers` |
   | `uidNumber`, `gidNumber`, `loginShell` | los mismos, con `--uid-number`, `--gid-number` y `--login-shell` (RFC 2307; el dominio se provisiona con `--use-rfc2307`) |
   | `ou=...` | `--userou` / `--groupou` |
   | `mail`, `givenName`, `sn` | `--mail-address`, `--given-name`, `--surname` |

3. **Recrear** los objetos con `samba-tool`: `ou create`, `group add --gid-number`, `user create --uid-number --gid-number --unix-home --login-shell` y `group addmembers` ([Setting up RFC2307 in AD](https://wiki.samba.org/index.php/Setting_up_RFC2307_in_AD), [User and Group management](https://wiki.samba.org/index.php/User_and_Group_management)). Hilo de referencia con el mismo camino: <https://lists.samba.org/archive/samba/2019-April/222221.html>.
4. **Repuntar los consumidores**: base, bind DN, filtro con `sAMAccountName` y `memberOf`, y tipo de servidor `Active Directory` en las aplicaciones (sección 4).

### Las contraseñas: por qué no se migran

Un hash `{SSHA}` (SHA-1 con sal) **no se puede convertir** al hash NT ni a las claves Kerberos que AD necesita: son funciones distintas y no reversibles ([explicación](https://samba.tranquil.it/doc/en/samba_fundamentals-about_password_hash.html)). Las opciones son:

- Crear la cuenta con una **clave temporal** y `--must-change-at-next-login`, para que cada usuario la cambie al entrar.
- Resetearla con `samba-tool user setpassword`.
- **Capturar la clave** en el siguiente login y fijarla en AD.
- Sincronizar con LSC-project.

### Por qué aquí se provisionó desde cero

El directorio viejo tenía **cuatro usuarios de prueba y una cuenta de servicio**, sin grupos, sin esquema Samba, y todas sus claves están en `sistema/test.env` (versionado, de laboratorio): no había nada que no se pudiera volver a crear, ni claves reales que preservar. Migrar con la guía anterior habría costado más que `sembrar.sh`, que recrea las OU, los grupos y las cuentas en cada arranque, y el `mail` de las cuentas viejas llevaba el sufijo `.local`, que Samba no admite en el realm. El árbol de AD no es un traslado del anterior: es uno nuevo, con grupos, `givenName`, `sn` y `mail` con `.lan`.

### Quien venía del stack viejo: limpiar los restos

El árbol de OpenLDAP vivía en dos volúmenes y un contenedor que el compose ya no define:

- **El contenedor `openldap`** queda huérfano. `./levantar-sistema.sh arrancar` usa `up -d --remove-orphans`, que lo elimina (Docker lo avisa, sin fallar).
- **Los volúmenes `ldap_data` y `ldap_config`** (con el prefijo del proyecto, `reservaviva-smoke_ldap_data` y `reservaviva-smoke_ldap_config`) **no se borran solos**: ni `borrar-directorio` (que borra solo `samba_data` y `samba_etc`) ni `borrar` los quitan, porque ya no están declarados en el compose. Con el contenedor `openldap` ya retirado, se borran a mano: `docker volume rm reservaviva-smoke_ldap_data reservaviva-smoke_ldap_config`. Se pierden los datos del directorio viejo.
- **`servicios/openldap/generado/`**, la carpeta de LDIF generados que el compose montaba, puede quedar vacía en el equipo; se puede borrar. El resto de `servicios/openldap/` ya no existe en el repositorio.
- **El certificado LDAPS** de un clon anterior `generar-certificados.sh` lo regenera solo, en el siguiente `arrancar`, si su SAN no incluye `dc1.ad.reservaviva.lan` y `samba-ad` además de `ldap.reservaviva.lan` y la IP: cambia únicamente `ldap.crt`/`ldap.key`, con la misma CA (los clientes no se tocan), y el lanzador reinicia entonces `samba-ad` y las aplicaciones. No hace falta ningún paso manual.
- **El usuario huérfano de ERPNext.** La base de ERPNext puede conservar un User `rrhh.prueba@reservaviva.local`, creado por el login con el correo antiguo del stack viejo. Es **inofensivo** y la limpieza es opcional: se borra a mano desde el escritorio de ERPNext (Usuario → eliminar). El User del correo nuevo (`@reservaviva.lan`) se crea en el primer login, como siempre.

## 9. Límites y decisiones

- **`privileged: true`.** Samba guarda las ACL de AD en atributos extendidos `security.*`, y el contenedor sin privilegios no puede escribirlos. Es una concesión de seguridad deliberada; se anota en [seguridad.md](seguridad.md#3-directorio-activo-y-ldaps).
- **Puertos.** Solo se publican el 389 y el 636 (`LDAP_PORT` y `LDAPS_PORT`, 1389 y 1636 en `test.env`, en `HOST_IP`), para las herramientas del host y, por `extra_hosts`, InvenTree y ERPNext. **No se publican** el 445 (SMB: lo ocupa Windows en el host), el 88 (Kerberos: se prueba dentro de la red) ni el 53 (el DNS llega por bind9). Con `interfaces = eth0` y `bind interfaces only = yes`, Samba no escucha en loopback: el healthcheck consulta por la IP fija.
- **Unión de equipos fuera de alcance.** No se une ningún equipo Windows o Linux al dominio, y por eso no hay GPO ni RSAT en el laboratorio; el SMB (445) no se expone. El dominio está provisionado para que se pueda hacer, pero no se prueba.
- **Un solo controlador.** No hay réplica ni segundo DC.
- **Cuentas de laboratorio sin caducidad** (sección 3): decisión de laboratorio, con la política del dominio intacta.
- **Cuenta de servicio compartida.** `svc-lectura` la usan las dos aplicaciones, igual que antes; separarla por aplicación sigue pendiente ([seguridad.md](seguridad.md#qué-faltaría-para-producción-no-existe-hoy)). El pendiente de **grupos** quedó resuelto.
- **Usuarios sin permisos.** Los usuarios LDAP entran **sin permisos**: un administrador debe asignarles roles o grupos. En ERPNext, el rol `Employee` por defecto se retira solo ("no hay empleado asignado"); el mapeo a empleados y roles de HR está pendiente.
- **Pertenencia directa.** El filtro no expande grupos anidados (sección 4).
- **ERPNext por navegador.** El login LDAP se prueba por la API; el botón "Login with LDAP" de `/login` no se ha probado en un navegador.

### OpenVPMS 2.4.0.1: sin soporte LDAP

Evidencia, sacada del release que construye [`servicios/openvpms/Dockerfile`](../servicios/openvpms/Dockerfile):

- `WEB-INF/openvpms-security.xml` solo define el proxy de seguridad del servicio de arquetipos (`OpenVPMSMethodSecurityInterceptor`) y el `ArchetypeAccessDecisionManager`. Los usuarios, sus roles y sus autorizaciones son arquetipos guardados **en la base MySQL** (`toolbox user --setpassword` guarda la clave allí; es lo que hace el `entrypoint.sh`).
- Los proveedores de autenticación de `openvpms-web-security-2.4.0.1.jar` son `FirewalledGuiUserAuthenticationProvider`, `FirewalledApiUserAuthenticationProvider` y `MfaAuthenticationProvider`. No hay ninguna clase LDAP/JNDI en ese jar ni en `openvpms-framework`.
- Entre los JAR de `WEB-INF/lib` **no está `spring-security-ldap`**. Las coincidencias con "ldap" son el analizador de espacio de nombres de `spring-security-config` y falsos positivos (`bcprov`, `castor-xml`, `milton`, `unoil`). Sin ese módulo no hay proveedor LDAP posible sin añadir código propio.
- `openvpms-auth-plugin` ([2.4.0.13](https://repository.openvpms.org/releases/org/openvpms/openvpms-auth-plugin/2.4.0.13/)) solo autentica el acceso al *framework de plugins* (Atlassian Seraph/SAL) contra el mismo gestor de usuarios de OpenVPMS; no es un punto de extensión para el login de la aplicación.
- La documentación no menciona LDAP. Las novedades de autenticación de la 2.4 son contraseñas robustas, cambio forzado, "olvidé mi contraseña", MFA para "Connect From Anywhere" y OAuth2 para el correo IMAP/SMTP ([OpenVPMS 2.4](https://openvpms.org/openvpms-2.4), [manual](https://openvpms.org/users-handbook)).

**Decisión:** administrador local. Integrarlo exigiría parchear OpenVPMS. Si el curso lo exigiera, la alternativa sería OpenID (la pantalla de login ya lo ofrece) contra un proveedor de identidad que a su vez use el directorio (Samba AD), por ejemplo Keycloak: un servicio más, fuera del alcance actual.

### Pretix: solo con un plugin de terceros que no verifica TLS

**Lo que existe.** Pretix (2026.7.0, imagen `pretix/standalone:stable`) tiene una API oficial de [backends de autenticación enchufables](https://docs.pretix.eu/en/latest/development/api/auth.html) (`auth_backends` en `pretix.cfg`), pero **no trae ningún backend LDAP propio**. El único plugin instalable es de la comunidad: [`pretix-ldap`](https://github.com/Sohalt/pretix-ldap) 0.2.5 ([PyPI](https://pypi.org/project/pretix-ldap/), abril de 2024, un mantenedor, Apache-2.0, `pretix>=2023.06.0`). Hay otro, [`pretix-ldap-auth`](https://github.com/freitagsrunde/pretix-ldap-auth), sin README ni releases. Instalarlo exigiría un Dockerfile derivado (`pip install pretix-ldap`, `auth_backends` y una sección `[ldap]` en `pretix.cfg`): la imagen dejaría de ser la oficial.

**Por qué no se integra** (código leído del plugin 0.2.5, `ldap_connector.py`):

1. **No verifica el certificado del servidor.** Crea `Server(bind_url)` sin objeto `Tls`, así que `ldap3` usa `validate=CERT_NONE`. Comprobado con la imagen de Pretix contra un OpenLDAP con la CA de este repositorio, sin darle la CA al cliente (comprobación **histórica**, hecha antes de la migración a Samba AD; la conclusión depende del plugin, no del servidor):
   - como lo hace el plugin, el `bind` por `ldaps://` da **`success` con `validate=0`**: acepta cualquier certificado;
   - con `Tls(validate=CERT_REQUIRED)` y sin la CA da `LDAPSocketOpenError`, que es lo esperado.

   La sección `[ldap]` no tiene opción para una CA ni para `validate`, así que `ca.crt` no se puede usar sin parchear el plugin. Cifra, pero no autentica al servidor.
2. **Una sola conexión compartida.** La cuenta de búsqueda hace `rebind` con la clave del usuario y luego vuelve a la cuenta de servicio. Con varios hilos o workers de Pretix es una condición de carrera: un login podría ejecutarse con la identidad de otro bind.
3. **Autentica por correo** (`search_filter` por defecto `mail={email}`) y crea el usuario al primer login. Las OU no se mapean a roles ni equipos de Pretix, y el plugin no lee grupos: habría que dar los permisos a mano.
4. Necesita una cuenta de búsqueda (`svc-lectura`).

**Decisión:** no incluir el plugin. Exigiría una imagen propia, depender de un plugin de un solo mantenedor y parchearlo para que verifique la CA. Pretix sigue con el superusuario que crea `levantar-sistema.sh`, y `admin@localhost` se borra ([aplicaciones.md](aplicaciones.md#pretix-taquilla-y-boletería)).

#### Cómo repetir la comprobación de TLS (histórica)

Se escribió contra un OpenLDAP de prueba aislado, con la imagen `osixia/openldap:1.5.0` que usaba el sistema antes de la migración; no se ha adaptado a Samba AD ni se ha vuelto a ejecutar. Sirve de referencia del método:

```bash
bash servicios/ca/generar-certificados.sh --sin-instalar-ca      # genera la CA y el certificado (ignorados por git)
docker network create ldaptest
docker run -d --name openldap --network ldaptest \
  -e LDAP_ORGANISATION=RV -e LDAP_DOMAIN=reservaviva.local -e LDAP_ADMIN_PASSWORD=adminpw \
  -e LDAP_TLS_CRT_FILENAME=ldap.crt -e LDAP_TLS_KEY_FILENAME=ldap.key -e LDAP_TLS_CA_CRT_FILENAME=ca.crt \
  -e LDAP_TLS_VERIFY_CLIENT=never \
  -v "$PWD/servicios/ca/certs/ldap.crt:/container/service/slapd/assets/certs/ldap.crt" \
  -v "$PWD/servicios/ca/certs/ldap.key:/container/service/slapd/assets/certs/ldap.key" \
  -v "$PWD/servicios/ca/certs/ca.crt:/container/service/slapd/assets/certs/ca.crt" \
  osixia/openldap:1.5.0
# (no montar los certificados con :ro: la imagen hace chown y slapd no arranca)
docker run --rm -u 0 --network ldaptest --entrypoint sh pretix/standalone:stable -c 'pip install -q ldap3 &&
  python -c "from ldap3 import Server,Connection,Tls; import ssl
s=Server(\"ldaps://openldap:636\"); c=Connection(s,\"cn=admin,dc=reservaviva,dc=local\",\"adminpw\",auto_bind=True)
print(c.result[\"description\"], s.tls.validate)"'      # success 0  -> sin verificación
```
