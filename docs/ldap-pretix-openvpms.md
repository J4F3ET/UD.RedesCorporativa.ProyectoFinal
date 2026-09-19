# LDAP/LDAPS en Pretix y OpenVPMS — evaluación (Fase 2b)

> **Conclusión:** ninguna de las dos aplicaciones se integra con `ldaps://ldap.reservaviva.local:636`
> de forma limpia y con la cadena de la CA verificada. Siguiendo el plan (Fase 2, "si una app no lo
> soporta limpiamente, documentarlo como limitación en vez de forzarlo"), **no se modificó ningún
> compose ni imagen**: ambas siguen con el administrador local que crea `deploy.sh`
> (Pretix: `PRETIX_ADMIN_*`; OpenVPMS: `OPENVPMS_ADMIN_PASSWORD`).
> Fecha de la evaluación: 2026-09-19. Imágenes: `pretix/standalone:stable` (pretix 2026.7.0),
> OpenVPMS 2.4.0.1 (Dockerfile de `docker/pc1-medica/openvpms`).

## 1. OpenVPMS 2.4.0.1 — sin soporte LDAP

**Evidencia (inspección del release que construye el Dockerfile):**
- `WEB-INF/openvpms-security.xml` solo define el proxy de seguridad del servicio de arquetipos
  (`OpenVPMSMethodSecurityInterceptor`) y el `ArchetypeAccessDecisionManager`: los usuarios y sus
  roles/autorizaciones son arquetipos guardados **en la base MySQL** (`toolbox user --setpassword`
  guarda la clave allí, es lo que hace el `entrypoint.sh`).
- Los proveedores de autenticación del módulo `openvpms-web-security-2.4.0.1.jar` son
  `FirewalledGuiUserAuthenticationProvider`, `FirewalledApiUserAuthenticationProvider` y
  `MfaAuthenticationProvider`; ninguna clase LDAP/JNDI en ese jar ni en `openvpms-framework`.
- Entre los JAR de `WEB-INF/lib` **no está `spring-security-ldap`**; las coincidencias con
  "ldap" son solo el analizador de espacio de nombres de `spring-security-config` y falsos positivos
  (`bcprov`, `castor-xml`, `milton`, `unoil`). Sin ese módulo no existe proveedor LDAP posible sin
  añadir código propio.
- `openvpms-auth-plugin` (repositorio oficial, [2.4.0.13](https://repository.openvpms.org/releases/org/openvpms/openvpms-auth-plugin/2.4.0.13/))
  solo autentica el acceso al *framework de plugins* (Atlassian Seraph/SAL) contra el mismo gestor de
  usuarios de OpenVPMS; no es un punto de extensión para el login de la aplicación.
- La documentación no menciona LDAP. Las novedades de la 2.4 en autenticación son contraseñas
  robustas, cambio forzado, "olvidé mi contraseña", MFA para "Connect From Anywhere" y OAuth2 para
  correo IMAP/SMTP ([OpenVPMS 2.4](https://openvpms.org/openvpms-2.4), [manual](https://openvpms.org/users-handbook)).

**Decisión:** dejar el admin local. Integrarlo exigiría parchear OpenVPMS (fuera de alcance).
Alternativa a valorar si el curso lo exige: OpenID (la pantalla de login ya lo ofrece) contra un
IdP que a su vez use OpenLDAP; añade un servicio (p. ej. Keycloak) y queda fuera de este alcance.

## 2. Pretix — solo con un plugin de terceros que no verifica TLS

**Lo que sí existe.** Pretix tiene una API oficial de
[backends de autenticación enchufables](https://docs.pretix.eu/en/latest/development/api/auth.html)
(`auth_backends` en `pretix.cfg`) pensada, según su documentación, para LDAP/OAuth. Pretix **no trae
ningún backend LDAP propio**. El único plugin instalable es la comunidad:
[`pretix-ldap`](https://github.com/Sohalt/pretix-ldap) 0.2.5 ([PyPI](https://pypi.org/project/pretix-ldap/),
abril de 2024, un mantenedor, Apache-2.0, declara `pretix>=2023.06.0`; hay otro,
[`pretix-ldap-auth`](https://github.com/freitagsrunde/pretix-ldap-auth), sin README ni releases).
Se instalaría con un Dockerfile derivado (`pip install pretix-ldap` + `auth_backends` y sección
`[ldap]` en `pretix.cfg`), es decir, la imagen dejaría de ser la oficial.

**Por qué no se integra (código del plugin leído, 0.2.5, `ldap_connector.py`):**
1. **No verifica el certificado del servidor.** Crea `Server(bind_url)` sin objeto `Tls`; `ldap3`
   usa entonces `validate=CERT_NONE`. Comprobado contra el OpenLDAP de este repo (CA de
   `scripts/generar-certificados.sh`, sin darle la CA al cliente, con la imagen de Pretix):
   - como lo hace el plugin: `bind` por `ldaps://` → **`success`, `validate=0`** (acepta cualquier certificado);
   - con `Tls(validate=CERT_REQUIRED)` y sin la CA → `LDAPSocketOpenError` (lo esperado).
   No hay opción en `[ldap]` para una CA ni para `validate`, así que `ca.crt` no se puede usar sin
   parchear el plugin. Cifra pero no autentica al servidor: no cumple "LDAPS con cadena verificada".
2. **Una sola conexión compartida** de la cuenta de búsqueda que hace `rebind` con la clave del
   usuario y luego vuelve a la cuenta de servicio; con varios hilos/workers de Pretix es una
   condición de carrera (un login podría ejecutarse con la identidad de otro bind).
3. **Se autentica por correo** (`search_filter` por defecto `mail={email}`) y el usuario se crea
   al primer login; los usuarios de prueba y las OU (`ou=operaciones`) no se mapean a roles/equipos
   de Pretix: habría que dar permisos a mano después. El plugin no lee grupos.
4. Requiere cuenta de búsqueda (`svc-lectura`) con la ACL de `05-acl-servicio.ldif` (rama de Juan).

**Decisión:** no incluir el plugin. Añadirlo exigiría (a) una imagen propia, (b) un plugin de un
solo mantenedor y (c) parchearlo para verificar la CA: exactamente lo que el plan pide no hacer.
Pretix sigue con el superusuario de `deploy.sh` (y `admin@localhost` borrado; no se reintroduce).

## 3. Qué queda probado y qué no

| Comprobación | Resultado |
|---|---|
| OpenVPMS con LDAP | No soportado (sin `spring-security-ldap`, sin clases LDAP, usuarios en MySQL) |
| Pretix con LDAP | Solo plugin de terceros; sin verificación TLS (demostrado); no integrado |
| Login real con clave errónea/correcta vía LDAP en estas dos apps | **No aplicable** (no hay integración); el login local ya está cubierto en `docs/prueba-smoke-test-resultados.md` §8 |
| Verificación de `ldaps://` con `Tls(CERT_REQUIRED)` y `ca.crt` desde el contenedor de Pretix | Falla sin la CA, como debe |

Las apps que sí pueden integrarse limpiamente (ERPNext e InvenTree) las lleva otra sesión
(rama `feat/ldap-erpnext-inventree`).

## 4. Cómo repetir la comprobación de TLS

```bash
bash scripts/generar-certificados.sh --sin-instalar-ca      # genera la CA y el certificado (ignorados por git)
docker network create ldaptest
docker run -d --name openldap --network ldaptest \
  -e LDAP_ORGANISATION=RV -e LDAP_DOMAIN=reservaviva.local -e LDAP_ADMIN_PASSWORD=adminpw \
  -e LDAP_TLS_CRT_FILENAME=ldap.crt -e LDAP_TLS_KEY_FILENAME=ldap.key -e LDAP_TLS_CA_CRT_FILENAME=ca.crt \
  -e LDAP_TLS_VERIFY_CLIENT=never \
  -v "$PWD/docker/pc3-administracion-infra/certs/ldap.crt:/container/service/slapd/assets/certs/ldap.crt" \
  -v "$PWD/docker/pc3-administracion-infra/certs/ldap.key:/container/service/slapd/assets/certs/ldap.key" \
  -v "$PWD/docker/pc3-administracion-infra/certs/ca.crt:/container/service/slapd/assets/certs/ca.crt" \
  osixia/openldap:1.5.0
# (no montar los certificados con :ro: la imagen hace chown y slapd no arranca)
docker run --rm -u 0 --network ldaptest --entrypoint sh pretix/standalone:stable -c 'pip install -q ldap3 &&
  python -c "from ldap3 import Server,Connection,Tls; import ssl
s=Server(\"ldaps://openldap:636\"); c=Connection(s,\"cn=admin,dc=reservaviva,dc=local\",\"adminpw\",auto_bind=True)
print(c.result[\"description\"], s.tls.validate)"'      # success 0  -> sin verificación
```
