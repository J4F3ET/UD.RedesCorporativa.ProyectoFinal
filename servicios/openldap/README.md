# OpenLDAP (Infraestructura, VLAN 99)

Directorio central del zoológico, con LDAPS (636) firmado por la CA interna de [`../ca/`](../ca/README.md).

- **Servicio de compose:** `openldap` (imagen `osixia/openldap`).
- **Ficheros:** `05-acl-servicio.ldif` (permisos de la cuenta de servicio) y las plantillas `10-estructura.ldif.tpl`
  (una OU por departamento y la cuenta `svc-lectura`) y `20-usuarios-prueba.ldif.tpl` (usuarios de prueba), más este
  README. Ninguno contiene claves.
- Lo usan ERPNext e InvenTree: [`../../docs/ldap.md`](../../docs/ldap.md).
  Direcciones IP y puertos: [`../../docs/arquitectura.md`](../../docs/arquitectura.md).

## Bootstrap

`levantar-sistema.sh preparar` (también dentro de `arrancar`) genera los LDIF definitivos en `generado/` (ignorada por
git): copia `05-acl-servicio.ldif` y sustituye en cada plantilla los marcadores `${SSHA_<CUENTA>}` por el hash `{SSHA}` de
la clave correspondiente de [`sistema/test.env`](../../sistema/test.env). Si falta una variable, se detiene con
`definir <VARIABLE> en sistema/test.env`.

Solo `generado/` se monta en `/container/service/slapd/assets/config/bootstrap/ldif/custom` (ver el `docker-compose.yml`
de la raíz), así que ni este README ni las plantillas llegan al contenedor. La imagen `osixia/openldap` carga los `*.ldif`
de esa carpeta en orden alfabético **solo en el primer arranque, con el directorio vacío** (volúmenes `ldap_data` y
`ldap_config`). Si el directorio ya existe, no se vuelven a aplicar: para recargarlos hay que borrar esos dos volúmenes
(se pierden los datos del directorio) o usar `ldapadd` a mano.

Base: `dc=reservaviva,dc=local`. Un usuario se busca por `uid` dentro de la OU de su departamento.

| Usuario (`uid`) | OU | Variable de su clave en `sistema/test.env` |
|---|---|---|
| `vet.prueba` | `ou=medica` | `LDAP_PRUEBA_VET_PASSWORD` |
| `logistica.prueba` | `ou=operaciones` | `LDAP_PRUEBA_LOGISTICA_PASSWORD` |
| `taquilla.prueba` | `ou=operaciones` | `LDAP_PRUEBA_TAQUILLA_PASSWORD` |
| `rrhh.prueba` | `ou=rrhh` | `LDAP_PRUEBA_RRHH_PASSWORD` |
| `cn=svc-lectura,ou=servicios` (cuenta de búsqueda de las apps) | `ou=servicios` | `LDAP_SVC_LECTURA_PASSWORD` |

Son claves de laboratorio; en el directorio quedan como hash SSHA. Cámbialas o borra estos usuarios fuera del
laboratorio (rotación: [`../../docs/seguridad.md`](../../docs/seguridad.md)).
Cada aplicación busca solo en la OU de su departamento (InvenTree en `ou=operaciones`, ERPNext en `ou=rrhh`),
así que un usuario de un departamento no entra en la aplicación de otro.
