# LDAP y LDAPS por aplicación

Qué aplicaciones autentican contra el directorio central (OpenLDAP), cómo lo hacen, cuáles no y por qué. Todo sale del
[`docker-compose.yml`](../docker-compose.yml) de la raíz y de [`servicios/openldap/`](../servicios/openldap/README.md);
si algún día difieren de este documento, manda el código.

Otros documentos: la red y el recorrido de una conexión LDAPS en [arquitectura.md](arquitectura.md#6-flujos); la CA, las
ACL, la cuenta de servicio y dónde están las claves en [seguridad.md](seguridad.md#3-ldap-y-ldaps); el uso diario de cada
aplicación en [aplicaciones.md](aplicaciones.md); las pasadas de `verificar` que lo comprueban en
[resultados-un-host.md](resultados-un-host.md).

## 1. Resumen

| Aplicación | ¿LDAP? | Cómo, o por qué no |
|---|---|---|
| ERPNext (RRHH) | Sí, LDAPS con la cadena verificada | "LDAP Settings" de Frappe, que escribe el trabajo `erpnext-ldap-config`. Busca en `ou=rrhh` |
| InvenTree (Logística) | Sí, LDAPS con la cadena verificada | `django-auth-ldap`, con las variables `INVENTREE_LDAP_*` de `inventree-app`. Busca en `ou=operaciones` |
| OpenVPMS (Médica) | No | La versión 2.4.0.1 no tiene soporte LDAP (sección 6) |
| Pretix (Taquilla) | No | Solo existe un plugin de terceros que no verifica el certificado del servidor (sección 7) |

OpenVPMS y Pretix siguen con su administrador local ([aplicaciones.md](aplicaciones.md)).

## 2. El directorio

Base `dc=reservaviva,dc=local`, con una OU por departamento (`ou=medica`, `ou=operaciones`, `ou=rrhh`) y `ou=servicios`
para la cuenta de búsqueda `cn=svc-lectura`. No hay grupos, solo OU. Las plantillas LDIF de
[`servicios/openldap/`](../servicios/openldap/README.md) no llevan claves: `levantar-sistema.sh preparar` genera los LDIF
definitivos con los hash de las claves de `sistema/test.env` en `servicios/openldap/generado/` (fuera de git). La imagen
los carga **solo con el directorio vacío** (volúmenes `ldap_data` y `ldap_config`): con un directorio ya existente hay que
borrar esos dos volúmenes (se pierden los datos del directorio) o aplicar los cambios con `ldapadd`.

| `uid` | OU | Aplicación en la que puede entrar |
|---|---|---|
| `vet.prueba` | `ou=medica` | Ninguna (OpenVPMS no usa LDAP) |
| `taquilla.prueba` | `ou=operaciones` | InvenTree, por configuración (**no verificado** con un login); Pretix no usa LDAP |
| `logistica.prueba` | `ou=operaciones` | InvenTree |
| `rrhh.prueba` | `ou=rrhh` | ERPNext |

Las claves de estos usuarios y de `svc-lectura` están solo en `sistema/test.env`, una variable por cuenta
(`LDAP_PRUEBA_<UID>_PASSWORD` y `LDAP_SVC_LECTURA_PASSWORD`); la tabla completa, en
[seguridad.md](seguridad.md#3-ldap-y-ldaps).

## 3. ERPNext e InvenTree

### Lo común

- **Servidor:** `ldaps://ldap.reservaviva.local:636`. El nombre lo fija `extra_hosts` hacia la IP de `openldap`, para que
  coincida con el certificado sin depender del DNS ([arquitectura.md](arquitectura.md#6-flujos)).
- **Verificación TLS:** contra la CA interna, montada desde `servicios/ca/certs/ca.crt` en `/certs/ca.crt` (solo lectura)
  en `inventree-app` y `erpnext-backend`. Con la CA del sistema, o con otra CA, la conexión falla.
- **Flujo:** la aplicación hace bind con `svc-lectura`, busca `uid=<usuario>` **solo en la OU de su departamento** y hace
  bind con el DN encontrado y la clave del usuario. Un usuario de otro departamento recibe "clave inválida".
- **Clave de `svc-lectura`:** `LDAP_SVC_LECTURA_PASSWORD` en `sistema/test.env`. Es una sola cuenta compartida por las dos
  aplicaciones: el compose pasa esa variable a InvenTree (`INVENTREE_LDAP_BIND_PASSWORD`) y a `erpnext-ldap-config`, y la
  misma variable genera el hash del LDIF.

### InvenTree

- `django-auth-ldap`, configurado con `INVENTREE_LDAP_*` en `inventree-app`: `OPT_X_TLS_CACERTFILE=/certs/ca.crt` y
  `OPT_X_TLS_REQUIRE_CERT=OPT_X_TLS_DEMAND`; búsqueda en `ou=operaciones`.
- El filtro por defecto de la imagen es `(uid= %(user)s)`, con un espacio, y no encuentra a nadie. Por eso el compose fija
  `(uid=%(user)s)`.

### ERPNext

- "LDAP Settings" de Frappe (`ldap3`). Lo escribe el trabajo idempotente `erpnext-ldap-config` en cada arranque:
  `require_trusted_certificate: Yes`, `local_ca_certs_file: /certs/ca.crt` y búsqueda de usuarios en `ou=rrhh`.
- `erpnext-ldap-config` guarda con `ignore_mandatory`: **no se conecta a OpenLDAP** al guardar, y por eso no necesita
  `vlan99_infra`. La prueba real es el login. Quien habla LDAPS es `erpnext-backend`.

## 4. Qué se comprueba

| Caso | ERPNext (API de login LDAP de Frappe) | InvenTree (`/api/user/token/`) | Cómo se comprobó |
|---|---|---|---|
| Usuario de su departamento, clave correcta | Aceptado (`rrhh.prueba`; el usuario se crea al primer login) | Aceptado, con token (`logistica.prueba`) | `verificar`, en cada pasada |
| Clave errónea | Rechazado | Rechazado | `verificar`, en cada pasada |
| `docker compose down` (sin `-v`) + `up -d` | Los dos casos anteriores se repiten igual | Ídem | `verificar` completo (caso 4) |
| Usuario de otro departamento con su clave correcta | Rechazado (`logistica.prueba`, `vet.prueba`) | Rechazado (`rrhh.prueba`) | Prueba manual durante la integración; `verificar` no la repite |
| Administrador local (no LDAP) | Sigue funcionando | Sigue funcionando | Prueba manual durante la integración |
| Cliente con la CA del sistema en lugar de `ca.crt` | Falla | Falla (`self-signed certificate in certificate chain`) | Prueba manual durante la integración |

Además, `verificar` hace un `ldapsearch` por LDAPS contra OpenLDAP que debe funcionar con la CA interna y fallar con una CA
ajena o con una clave errónea. Los códigos HTTP y el resultado de cada pasada están en
[resultados-un-host.md](resultados-un-host.md#verificación-de-la-arquitectura-levantar-sistema-verificar).

## 5. Límites

- Los usuarios LDAP entran **sin permisos**: un administrador debe asignarles roles o grupos. En ERPNext, el rol
  `Employee` por defecto se retira solo ("no hay empleado asignado"); el mapeo a empleados y roles de HR está pendiente.
- La búsqueda no filtra por grupos: cualquier entrada con `uid` dentro de la OU puede autenticarse. Por eso
  `taquilla.prueba` entraría en InvenTree.
- En ERPNext el login LDAP se prueba por la API. El botón "Login with LDAP" del formulario `/login` no se ha probado en
  un navegador (ver los pendientes de [resultados-un-host.md](resultados-un-host.md#pendientes)).

## 6. OpenVPMS 2.4.0.1: sin soporte LDAP

Evidencia, sacada del release que construye [`servicios/openvpms/Dockerfile`](../servicios/openvpms/Dockerfile):

- `WEB-INF/openvpms-security.xml` solo define el proxy de seguridad del servicio de arquetipos
  (`OpenVPMSMethodSecurityInterceptor`) y el `ArchetypeAccessDecisionManager`. Los usuarios, sus roles y sus
  autorizaciones son arquetipos guardados **en la base MySQL** (`toolbox user --setpassword` guarda la clave allí; es lo
  que hace el `entrypoint.sh`).
- Los proveedores de autenticación de `openvpms-web-security-2.4.0.1.jar` son `FirewalledGuiUserAuthenticationProvider`,
  `FirewalledApiUserAuthenticationProvider` y `MfaAuthenticationProvider`. No hay ninguna clase LDAP/JNDI en ese jar ni en
  `openvpms-framework`.
- Entre los JAR de `WEB-INF/lib` **no está `spring-security-ldap`**. Las coincidencias con "ldap" son el analizador de
  espacio de nombres de `spring-security-config` y falsos positivos (`bcprov`, `castor-xml`, `milton`, `unoil`). Sin ese
  módulo no hay proveedor LDAP posible sin añadir código propio.
- `openvpms-auth-plugin` ([2.4.0.13](https://repository.openvpms.org/releases/org/openvpms/openvpms-auth-plugin/2.4.0.13/))
  solo autentica el acceso al *framework de plugins* (Atlassian Seraph/SAL) contra el mismo gestor de usuarios de
  OpenVPMS; no es un punto de extensión para el login de la aplicación.
- La documentación no menciona LDAP. Las novedades de autenticación de la 2.4 son contraseñas robustas, cambio forzado,
  "olvidé mi contraseña", MFA para "Connect From Anywhere" y OAuth2 para el correo IMAP/SMTP
  ([OpenVPMS 2.4](https://openvpms.org/openvpms-2.4), [manual](https://openvpms.org/users-handbook)).

**Decisión:** administrador local. Integrarlo exigiría parchear OpenVPMS. Si el curso lo exigiera, la alternativa sería
OpenID (la pantalla de login ya lo ofrece) contra un proveedor de identidad que a su vez use OpenLDAP, por ejemplo
Keycloak: un servicio más, fuera del alcance actual.

## 7. Pretix: solo con un plugin de terceros que no verifica TLS

**Lo que existe.** Pretix (2026.7.0, imagen `pretix/standalone:stable`) tiene una API oficial de
[backends de autenticación enchufables](https://docs.pretix.eu/en/latest/development/api/auth.html) (`auth_backends` en
`pretix.cfg`), pero **no trae ningún backend LDAP propio**. El único plugin instalable es de la comunidad:
[`pretix-ldap`](https://github.com/Sohalt/pretix-ldap) 0.2.5 ([PyPI](https://pypi.org/project/pretix-ldap/), abril de
2024, un mantenedor, Apache-2.0, `pretix>=2023.06.0`). Hay otro,
[`pretix-ldap-auth`](https://github.com/freitagsrunde/pretix-ldap-auth), sin README ni releases. Instalarlo exigiría un
Dockerfile derivado (`pip install pretix-ldap`, `auth_backends` y una sección `[ldap]` en `pretix.cfg`): la imagen dejaría
de ser la oficial.

**Por qué no se integra** (código leído del plugin 0.2.5, `ldap_connector.py`):

1. **No verifica el certificado del servidor.** Crea `Server(bind_url)` sin objeto `Tls`, así que `ldap3` usa
   `validate=CERT_NONE`. Comprobado con la imagen de Pretix contra un OpenLDAP con la CA de este repositorio, sin darle la
   CA al cliente:
   - como lo hace el plugin, el `bind` por `ldaps://` da **`success` con `validate=0`**: acepta cualquier certificado;
   - con `Tls(validate=CERT_REQUIRED)` y sin la CA da `LDAPSocketOpenError`, que es lo esperado.

   La sección `[ldap]` no tiene opción para una CA ni para `validate`, así que `ca.crt` no se puede usar sin parchear el
   plugin. Cifra, pero no autentica al servidor.
2. **Una sola conexión compartida.** La cuenta de búsqueda hace `rebind` con la clave del usuario y luego vuelve a la
   cuenta de servicio. Con varios hilos o workers de Pretix es una condición de carrera: un login podría ejecutarse con la
   identidad de otro bind.
3. **Autentica por correo** (`search_filter` por defecto `mail={email}`) y crea el usuario al primer login. Las OU no se
   mapean a roles ni equipos de Pretix, y el plugin no lee grupos: habría que dar los permisos a mano.
4. Necesita una cuenta de búsqueda (`svc-lectura`) con la ACL de
   [`05-acl-servicio.ldif`](../servicios/openldap/05-acl-servicio.ldif).

**Decisión:** no incluir el plugin. Exigiría una imagen propia, depender de un plugin de un solo mantenedor y parchearlo
para que verifique la CA. Pretix sigue con el superusuario que crea `levantar-sistema.sh`, y `admin@localhost` se borra
([aplicaciones.md](aplicaciones.md#pretix-taquilla-y-boletería)).

### Cómo repetir la comprobación de TLS

Con un OpenLDAP de prueba aislado, no el del sistema:

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
