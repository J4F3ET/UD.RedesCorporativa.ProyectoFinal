# Seguridad y credenciales

Qué protege el sistema de un host, con qué mecanismos y qué deja sin cubrir. Se dirige a quien clona el repositorio.
Aquí no se repite la integración LDAP de cada aplicación, que está en [`ldap.md`](ldap.md). Las cifras de las pruebas
están en [`resultados-un-host.md`](resultados-un-host.md).

## 1. Alcance y advertencia

Reserva Viva es un **laboratorio académico**, no un despliegue de producción:

- Todas las contraseñas están en [`../sistema/test.env`](../sistema/test.env). Ese fichero **está versionado en git**,
  así que sus valores están en el historial del repositorio. Son claves **desechables** de laboratorio.
- `sistema/test.env` es la **única** fuente de claves, también las del directorio LDAP: ningún otro fichero versionado
  (LDIF, README, scripts) contiene una clave. Los LDIF con los hash se generan en cada `preparar` (sección 3).
- Hay que **rotar todas las claves** si el repositorio se hace público o si alguien usa este sistema fuera del laboratorio
  (ver la sección 6). Borrar `test.env` en un commit nuevo no basta: el historial conserva los valores.

## 2. CA interna y certificados

### Qué genera `servicios/ca/generar-certificados.sh`

[`../servicios/ca/generar-certificados.sh`](../servicios/ca/generar-certificados.sh) crea una CA propia del laboratorio y el
certificado de OpenLDAP. `levantar-sistema.sh` lo ejecuta en cada `preparar` y en cada `arrancar`, siempre con
`--sin-instalar-ca`. Los ficheros quedan en `servicios/ca/certs/`, que está en `.gitignore`: cada clon genera los suyos.

| Fichero | Qué es | Parámetros | Permisos al generarse |
|---|---|---|---|
| `ca.crt` | Certificado público de la CA. Es lo que deben confiar los clientes de LDAPS | RSA 4096, SHA-256, 3650 días, `CA:TRUE` (crítica), `keyCertSign, cRLSign`; sujeto `O=Zoologico Reserva Viva, CN=Reserva Viva CA interna` | 644 |
| `ca.key` | Clave privada de la CA. **No se monta en ningún contenedor** | — | 600 |
| `ldap.crt` | Certificado de servidor de OpenLDAP, firmado por la CA | RSA 2048, SHA-256, 825 días, `serverAuth`; SAN `DNS:ldap.reservaviva.lan`, `DNS:openldap`, `DNS:localhost`, `IP:10.10.99.10`, `IP:127.0.0.1` | 644 |
| `ldap.key` | Clave privada de OpenLDAP | — | 600 |

El script trabaja con `umask 077`. Opciones: `--forzar` lo regenera todo, y `--sin-instalar-ca` evita instalar `ca.crt` en
el almacén de confianza del equipo. Sin esa opción, la instalación se hace solo si el script corre como root y existe
`update-ca-certificates`.

### Cuándo se regenera y cuándo no

El script es idempotente. Si los certificados existen y son válidos, no toca nada. Regenera en estos casos:

- **La CA** (y con ella el certificado de OpenLDAP), con `--forzar`, si falta `ca.key` o si a `ca.crt` le quedan menos de
  30 días de vigencia.
- **Solo el certificado de OpenLDAP**, con `--forzar`, si falta `ldap.key`, si a `ldap.crt` le quedan menos de 30 días, si
  `ldap.crt` no lo firma la `ca.crt` actual o si su SAN no incluye `ldap.reservaviva.lan` y `10.10.99.10`. Así se
  regeneró el 27/09/2026, al pasar el dominio de `.local` a `.lan`: solo `ldap.crt`/`ldap.key`, con la misma CA, sin tocar
  a los clientes (que confían en `ca.crt`).

Los permisos (`chmod`) se aplican **solo a lo generado en esa ejecución**. Al arrancar, la imagen de OpenLDAP
(`osixia/openldap`) se apropia de los certificados montados (uid 911), y desde entonces el usuario del equipo ya no puede
cambiarles los permisos. Por la misma razón, el script borra y crea los ficheros de nuevo en vez de sobrescribirlos, y
OpenLDAP los monta sin `:ro`.

Si se regeneran con el sistema en marcha, los contenedores que los montan siguen viendo los ficheros anteriores hasta que
se recrean. Para OpenLDAP, un reinicio **no basta**: con `--copy-service`, la imagen copia sus certificados a
`/container/run/service` solo en el primer arranque de cada contenedor, y slapd usa esa copia. Se comprobó el 27/09/2026:
tras regenerar `ldap.crt` y reiniciar `openldap`, seguía sirviendo el certificado antiguo y el login LDAPS de ERPNext e
InvenTree fallaba. Por eso `arrancar` **recrea** `openldap` (con sus mismos volúmenes) cuando `ldap.crt` es más nuevo que
el contenedor (`recrear_ldap_si_cert_nuevo`), y después reinicia los dos clientes LDAPS, `inventree-app` y
`erpnext-backend`: el mismo día, con `openldap` ya sirviendo el certificado nuevo, InvenTree siguió rechazando el login LDAP
(401, sin ningún error en su log) hasta reiniciar `inventree-app`, mientras un proceso nuevo dentro del mismo contenedor
autenticaba bien. Queda estado TLS/LDAP en los procesos de gunicorn; la causa exacta no se identificó. Tras el reinicio,
`ldaplogin.py` pasó. También se reinicia `erpnext-hr`: al reiniciarse, `erpnext-backend` puede cambiar de IP en
`erpnext_internal` y el nginx de `erpnext-hr` seguía llamando a la antigua (502 en `rrhh`). Si se regenerase la CA, habría que recrear también `inventree-app` y `erpnext-backend` para que
monten la `ca.crt` nueva, y eso no está automatizado.

### Quién monta qué

| Contenedor | Ficheros montados desde `servicios/ca/certs/` | Para qué |
|---|---|---|
| `openldap` | `ca.crt`, `ldap.crt`, `ldap.key` | Servir LDAPS en el 636 (`LDAP_TLS: "true"`) |
| `erpnext-backend` | `ca.crt` → `/certs/ca.crt` (solo lectura) | Verificar el certificado de OpenLDAP |
| `inventree-app` | `ca.crt` → `/certs/ca.crt` (solo lectura) | Verificar el certificado de OpenLDAP |

OpenVPMS y Pretix no montan nada, porque no usan LDAP. Todo está definido en el compose único
[`../docker-compose.yml`](../docker-compose.yml).

**Por qué hay una sola CA.** Todos los servicios corren en el mismo motor Docker y salen del mismo clon del repositorio.
Basta con un único `ca.crt`, montado por todos desde `./servicios/ca/certs/ca.crt`, y no hay copias que mantener
sincronizadas. En el diseño de 3 equipos del anexo, cada equipo necesitaba su propia copia.

**Si falta `ca.crt`.** Cuando la ruta de origen de un montaje no existe, Docker crea en su lugar un **directorio vacío**.
El contenedor arranca, pero `/certs/ca.crt` es entonces un directorio: la verificación TLS falla y el login LDAPS de
ERPNext e InvenTree no funciona. Para evitarlo, el certificado debe existir antes de arrancar, y de eso se encarga la
comprobación en `preparar` de `levantar-sistema.sh`. Si ya se arrancó sin él, hay que borrar el directorio vacío que
creó Docker, volver a ejecutar `preparar` y recrear los contenedores afectados.

## 3. LDAP y LDAPS

### Qué aplicación usa LDAP

Solo ERPNext e InvenTree, las dos por LDAPS (`ldaps://ldap.reservaviva.lan:636`) y verificando el certificado de
OpenLDAP con la CA interna; OpenVPMS y Pretix no usan LDAP. Cómo lo configura cada aplicación, qué se comprueba y por
qué las otras dos no se integran: [`ldap.md`](ldap.md). El nombre `ldap.reservaviva.lan` se fija con `extra_hosts`
para que coincida con el SAN del certificado sin depender del DNS.

OpenLDAP tiene `LDAP_TLS_VERIFY_CLIENT: never`: no pide certificado a los clientes. También escucha en **389 sin
cifrar**, pero las dos aplicaciones integradas usan solo el 636.

### Árbol del directorio (DIT)

Base `dc=reservaviva,dc=local`, definido en la plantilla
[`10-estructura.ldif.tpl`](../servicios/openldap/10-estructura.ldif.tpl):

```
dc=reservaviva,dc=local
├── ou=medica        Veterinaria y Clínica (VLAN 10)
├── ou=operaciones   Taquilla y Logística (VLAN 20 y 30)
├── ou=rrhh          Recursos Humanos (VLAN 40)
└── ou=servicios     cuentas de servicio
    └── cn=svc-lectura
```

Los LDIF se cargan **solo en el primer arranque, con el volumen `ldap_data` vacío**. Cambiar el LDIF no modifica un
directorio que ya existe.

**Cómo se generan los LDIF.** Las plantillas versionadas `servicios/openldap/*.ldif.tpl` no llevan claves, sino
marcadores `${SSHA_<CUENTA>}`. `levantar-sistema.sh preparar` (también dentro de `arrancar`) los sustituye por el hash
`{SSHA}` (SHA-1 con 8 bytes de sal aleatoria, calculado con `openssl`; la clave no pasa por la línea de comandos de ningún
proceso) de la variable correspondiente de `test.env`, y escribe el resultado en `servicios/openldap/generado/`, que está
ignorada por git y es la carpeta que el compose monta como bootstrap de la imagen. Si falta una variable, `preparar`
se detiene con `definir <VARIABLE> en sistema/test.env`. El README y las plantillas no llegan al contenedor.

### Cuentas con privilegios en el directorio y sus ACL

Solo hay **una** cuenta de servicio para las búsquedas (bind), y la comparten las dos aplicaciones. La regla está en
[`05-acl-servicio.ldif`](../servicios/openldap/05-acl-servicio.ldif) y sustituye la regla `{2}` de la configuración:

| Cuenta | Qué puede hacer | Quién la usa |
|---|---|---|
| `cn=admin,dc=reservaviva,dc=local` | Escribir en todo el directorio | Administración manual. La crea la imagen con `LDAP_ADMIN_PASSWORD` |
| `cn=svc-lectura,ou=servicios,dc=reservaviva,dc=local` | Leer todo el directorio **excepto `userPassword`** (según el comentario del LDIF, la regla `{1}` de la imagen le impide leer las claves y solo le permite autenticarse con ellas) | ERPNext e InvenTree, para buscar al usuario antes de autenticarlo |
| Cada usuario (`self`) | Leer su propia entrada | — |
| Resto, incluido el acceso anónimo | Nada, según la regla `{2}` | — |

Las reglas `{0}` y `{1}` vienen de la imagen `osixia/openldap` y no están en el repositorio. Su contenido exacto está
**no verificado** aquí.

Cada aplicación busca **solo en la OU de su departamento**: ERPNext en `ou=rrhh` e InvenTree en `ou=operaciones`. Por
eso un usuario de otro departamento no entra. La búsqueda no filtra por grupos, porque el directorio no define ninguno.

### Usuarios de prueba

Definidos en la plantilla [`20-usuarios-prueba.ldif.tpl`](../servicios/openldap/20-usuarios-prueba.ldif.tpl); en el
directorio sus claves quedan como hash SSHA. Están organizados por OU, no por grupos. Qué usuario entra en qué aplicación está en
[`ldap.md`](ldap.md#2-el-directorio). Los usuarios LDAP se crean en la aplicación al primer login y **sin permisos**: se
los asigna un administrador.

**Dónde están las claves:**

Todas en [`../sistema/test.env`](../sistema/test.env), y solo ahí:

| Cuenta | Variable |
|---|---|
| `cn=svc-lectura,ou=servicios` (la usan InvenTree y ERPNext para buscar) | `LDAP_SVC_LECTURA_PASSWORD` |
| `vet.prueba` | `LDAP_PRUEBA_VET_PASSWORD` |
| `logistica.prueba` | `LDAP_PRUEBA_LOGISTICA_PASSWORD` |
| `taquilla.prueba` | `LDAP_PRUEBA_TAQUILLA_PASSWORD` |
| `rrhh.prueba` | `LDAP_PRUEBA_RRHH_PASSWORD` |
| `cn=admin` (administrador del directorio) | `LDAP_ADMIN_PASSWORD` (la aplica la propia imagen) |

La misma variable alimenta el hash del LDIF de `svc-lectura` y la configuración de las dos aplicaciones
(`docker-compose.yml`), así que no pueden desincronizarse en un primer arranque. `sistema/ldaplogin.py` lee las de
`rrhh.prueba` y `logistica.prueba` del mismo fichero.

## 4. Credenciales iniciales por aplicación

Solo los nombres de usuario y la variable que guarda cada clave. Los valores están en `sistema/test.env`.

| Servicio | Usuario inicial | Variable de la clave | Cuándo se aplica |
|---|---|---|---|
| OpenVPMS | `admin` | `OPENVPMS_ADMIN_PASSWORD` | Una vez, en la etapa `adminpass` de la inicialización (queda marcada como hecha) |
| Pretix | el valor de `PRETIX_ADMIN_EMAIL` (`admin@reservaviva.local`) | `PRETIX_ADMIN_PASSWORD` | La crea `levantar-sistema.sh` si no existe (ver abajo) |
| InvenTree | `INVENTREE_ADMIN_USER` (`admin` por defecto; `test.env` no lo define) | `INVENTREE_ADMIN_PASSWORD` | La imagen crea el superusuario solo si no existe |
| ERPNext | `Administrator` | `ERPNEXT_ADMIN_PASSWORD` | Una vez, al crear el sitio (`erpnext-create-site`) |
| OpenLDAP | `cn=admin,dc=reservaviva,dc=local` | `LDAP_ADMIN_PASSWORD` | Con el volumen `ldap_data` vacío |
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

### Qué se publica

En **modo local** (el de por defecto) todos los puertos se publican en `127.0.0.1` (`PUBLISH_IP`, `DNS_BIND_IP` e
`INTRANET_IP` en `sistema/test.env`). **Solo se accede desde el propio equipo**, no desde la red local. La lista de puertos
está en [`arquitectura.md`, "Puertos publicados"](arquitectura.md#7-puertos-publicados); OpenLDAP publica también el
puerto sin cifrar.

Si alguna de esas variables faltara en `test.env`, el compose publica igualmente en `127.0.0.1`: todos los `ports:` del
`docker-compose.yml` único usan `${PUBLISH_IP:-127.0.0.1}`, `${DNS_BIND_IP:-127.0.0.1}` o `${INTRANET_IP:-127.0.0.1}`
(hasta el 27/09/2026 el valor por defecto era `0.0.0.0`, todas las interfaces). Nada se publica nunca en `0.0.0.0`.

### Modo intranet: qué se expone y por qué es opcional

El **modo intranet** (`levantar-sistema --intranet`) publica **solo dos puertos** en la IP de la LAN del equipo: el proxy
web (80/tcp), que da acceso a las cuatro aplicaciones por su nombre, y el DNS (53/udp y tcp). OpenLDAP, NTP y el acceso
directo 1808x siguen en `127.0.0.1`. Es **opcional y no persistente** (un `arrancar` sin la opción vuelve al modo local)
por una razón concreta: las contraseñas de laboratorio están **públicas en git**. Con el modo intranet activo, cualquier
equipo de la misma red puede entrar como administrador en OpenVPMS, Pretix, InvenTree y ERPNext, y todo viaja por HTTP
sin cifrar. Solo debe usarse en una red de laboratorio, y lo razonable es volver al modo local al terminar.

El DNS expuesto no amplía la superficie: es autoritativo solo de `reservaviva.lan` y no hace recursión, así que no sirve
como resolvedor abierto ni para ataques de amplificación. A la LAN no le anuncia `ldap` ni `ntp`, y a un cliente de la
LAN nunca le da una IP de contenedor (vista `lan`, [arquitectura.md](arquitectura.md#la-zona-reservavivalan-y-sus-dos-vistas)).

**Alcance de las reglas de cortafuegos** que crea `sistema/habilitar-intranet-windows.ps1` (y que `-Deshacer` quita):

- Firewall de Windows: tres reglas de **entrada** (`ReservaViva-HTTP-TCP-80`, `ReservaViva-DNS-UDP-53`,
  `ReservaViva-DNS-TCP-53`), solo desde la **subred local** de la interfaz elegida (por ejemplo `192.168.1.0/24`), en todos
  los perfiles: la Wi-Fi del equipo de medida está en perfil "Pública", y una regla solo para "Privada" no aplicaría.
- Firewall de Hyper-V: las mismas tres reglas para la VM de WSL (`VMCreatorId` de WSL), también limitadas a la subred.
- Nada más: no abre otros puertos, no cambia la acción por defecto de ningún perfil y no toca ICS ni Portmaster.

`networkingMode=mirrored` cambia la red de **toda** la distro de WSL, no solo la de Docker: cualquier servicio que escuche
dentro de WSL queda en las interfaces de Windows, aunque sin las reglas de entrada anteriores el cortafuegos lo filtra.

### Qué aísla el sistema

Cada VLAN es una **red bridge de Docker** con la subred de su VLAN (10.10.10/24, .20, .30, .40 y .99). Dos bridges no se
enrutan entre sí. Cada aplicación está en la red de su departamento y además en `vlan99_infra` con IP fija, para llegar a
OpenLDAP, DNS y NTP. Las direcciones están en [`arquitectura.md`](arquitectura.md).

`levantar-sistema.sh verificar` ([`../sistema/verificar_arquitectura.md`](../sistema/verificar_arquitectura.md)) comprueba:

- Un cliente que solo está en la VLAN de un departamento no alcanza otro departamento ni `vlan99_infra`.
- Una aplicación alcanza `openldap` (389 y 636) y no alcanza otros departamentos.
- bind9 responde con autoridad a su zona y rechaza (`REFUSED`) los nombres externos, porque no hace recursión.
- Los logins LDAPS funcionan con la CA interna y fallan con una CA ajena o con una clave errónea.

### Qué no aísla un solo host (limitación conocida)

- **Las aplicaciones se ven entre sí por `vlan99_infra`.** Esa red es un único dominio L2 compartido por las cuatro
  aplicaciones, así que una puede conectar con otra por su IP de infraestructura. `verificar` lo informa con los **12 INFO
  app↔app** previstos: es una limitación del diseño en un host, no un fallo oculto. En el diseño de 3 equipos del anexo,
  el tráfico entre VLAN lo decide la matriz de segmentación, aplicada por el switch L3 o por el firewall de PC-3
  ([`firewall-pc3-matriz.sh`](../diseno-red/l2-fallback/scripts/firewall-pc3-matriz.sh)). Ver
  [`../diseno-red/README.md`](../diseno-red/README.md) y
  [`arquitectura-3-equipos-departamentos.md`](../diseno-red/arquitectura-3-equipos-departamentos.md), sección 4.
- **El equipo anfitrión no está en ninguna VLAN.** Cualquier proceso del equipo llega a todos los puertos publicados en
  127.0.0.1, sea del departamento que sea. Además, en Linux/WSL el anfitrión suele poder alcanzar directamente las IP de
  los bridges; es un comportamiento general de Docker que `verificar` no comprueba.
- Tampoco se prueban el etiquetado 802.1Q, el switch físico ni el acceso desde otros equipos (los pasos para probarlo
  están en [`operacion.md`](operacion.md#acceso-desde-la-lan)). La lista completa está en
  "Qué NO puede demostrar un solo host" de `verificar_arquitectura.md`.

## 6. Buenas prácticas y pendientes

### Cómo rotar las claves

Cambiar `sistema/test.env` **no basta** en un sistema ya inicializado. Casi todas las claves se aplican una sola vez: al
crear el volumen, el sitio o el usuario (tabla de la sección 4). Hay dos caminos:

- **Laboratorio desechable:** cambiar los valores de `test.env` y reinicializar con `levantar-sistema.sh borrar`; el
  siguiente `arrancar` genera los LDIF con los hash nuevos. **Esto borra todos los datos**: bases de datos, sitio de
  ERPNext y directorio LDAP. Si solo cambian claves de LDAP, basta con reinicializar el directorio: parar y quitar
  `openldap`, borrar sus dos volúmenes (`ldap_data` y `ldap_config`) y `arrancar` (procedimiento probado en
  [`resultados-un-host.md`](resultados-un-host.md)).
- **Conservando los datos:**
  1. Cambiar cada clave dentro de su servicio: en la aplicación, en la base de datos, o con `ldappasswd` en el directorio.
  2. Poner el mismo valor en `test.env`, para que los arranques siguientes y `verificar` sigan funcionando.
  3. Para `svc-lectura`, actualizar a la vez la entrada del directorio y `LDAP_SVC_LECTURA_PASSWORD`, y recrear
     `erpnext-ldap-config` e `inventree-app`.

  Ningún script automatiza este camino y **no se ha probado**.

Si el repositorio se hizo público con las claves de laboratorio, hay que considerarlas comprometidas aunque se cambien
después: siguen en el historial de git.

### Qué faltaría para producción (no existe hoy)

- Sacar los secretos del repositorio: un `test.env` fuera de git o los *secrets* de Docker. Hoy `erpnext-create-site` recibe
  las claves por la línea de comandos (pendiente anotado en [`resultados-un-host.md`](resultados-un-host.md)).
- Reglas de filtrado dentro de `vlan99_infra` para que cada aplicación solo alcance OpenLDAP, DNS y NTP, y no a las demás
  aplicaciones.
- Quitar la publicación del 389 sin cifrar si nadie la necesita.
- Usuarios de prueba borrados, grupos LDAP y mapeo de roles en cada aplicación, y una cuenta de servicio por aplicación en
  lugar de una compartida.
- Custodia de `ca.key` fuera del equipo que sirve los servicios, y un procedimiento de renovación de certificados con la
  recreación de los contenedores.
- HTTPS en las cuatro aplicaciones: hoy se sirven por HTTP, en 127.0.0.1 y, en modo intranet, en la LAN por el proxy web.
  El sitio natural para TLS sería ese proxy, con un certificado de la CA interna.
