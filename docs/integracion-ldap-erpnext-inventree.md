# Integración LDAPS: ERPNext e InvenTree

Probada en el arnés `sistema/` (un solo host, redes `bridge`) el 2026-09-19. No valida macvlan ni el switch.

## Diseño
- Directorio: `dc=reservaviva,dc=local`, con una OU por departamento (`ou=medica`, `ou=operaciones`, `ou=rrhh`), `ou=servicios` con la cuenta de solo lectura `cn=svc-lectura` y usuarios de prueba. Definición en [`servicios/openldap/`](../servicios/openldap/README.md) (ver su README para usuarios y claves).
- Conexión: `ldaps://ldap.reservaviva.local:636` con verificación de cadena y nombre contra la CA de `servicios/ca/generar-certificados.sh` (`servicios/ca/certs/ca.crt`), montada como `/certs/ca.crt` (solo lectura). El nombre se fija con `extra_hosts` a `10.10.99.10` para coincidir con el certificado sin depender del DNS.
- Flujo: la app hace bind con `svc-lectura`, busca `uid=<usuario>` **solo en la OU de su departamento** y hace bind con el DN encontrado y la clave del usuario. Un usuario de otro departamento recibe "clave inválida".
- **InvenTree** (Logística, VLAN 30): `django-auth-ldap` con variables `INVENTREE_LDAP_*` en `inventree-app`; búsqueda en `ou=operaciones`. El filtro por defecto de la imagen es `(uid= %(user)s)` (con espacio) y no encuentra a nadie, por lo que se fija `(uid=%(user)s)`.
- **ERPNext** (RRHH, VLAN 40): "LDAP Settings" de Frappe (`ldap3`), configurado por el job idempotente `erpnext-ldap-config`; búsqueda en `ou=rrhh`. El que habla LDAPS es `erpnext-backend`.
- Nuevas variables: `INVENTREE_LDAP_BIND_PASSWORD` y `ERPNEXT_LDAP_BIND_PASSWORD` (en `sistema/test.env`), ambas la clave de `svc-lectura`.

## Resultados
| Prueba | ERPNext (`/api/method/frappe.integrations.doctype.ldap_settings.ldap_settings.login`) | InvenTree (`/api/user/token/`) |
|---|---|---|
| Usuario de su departamento, clave correcta | 200 (`rrhh.prueba`; el usuario se crea al primer login) | 200 + token (`logistica.prueba`) |
| Clave errónea | 417 "Invalid username or password" | 401 |
| Usuario de otro departamento con su clave correcta | 417 (`logistica.prueba`, `vet.prueba`) | 401 (`rrhh.prueba`) |
| Administrador local (no LDAP) | sigue funcionando | 200 |
| Cadena TLS: con `ca.crt` / con la CA del sistema | OK / falla | OK / falla (`self-signed certificate in certificate chain`) |
| `docker compose down` (sin `-v`) + `up -d` | login correcto 200 y clave errónea 417 | login correcto 200 y clave errónea 401 |

## Límites y notas
- Los usuarios LDAP entran **sin permisos**: un administrador debe asignarles roles/grupos. En ERPNext el rol `Employee` por defecto se retira solo ("no hay empleado asignado"); el mapeo a empleados y roles de HR queda pendiente.
- El directorio y los usuarios de prueba se cargan solo con `ldap_data` vacío; con un volumen existente hay que `down -v` o aplicar los LDIF con `ldapadd`.
- `erpnext-ldap-config` guarda la configuración con `ignore_mandatory` (no valida contra LDAP al guardar); la prueba real es el login.
- En ERPNext el login LDAP se prueba por el endpoint de la API; el formulario web `/login` muestra el botón "Login with LDAP" cuando está habilitado (no probado por navegador).
- La búsqueda no filtra por grupos: cualquier entrada con `uid` dentro de la OU puede autenticar.
- OpenVPMS y Pretix no están cubiertos aquí.
