# OpenLDAP (Infraestructura, VLAN 99)

Directorio central del zoológico, con LDAPS (636) firmado por la CA interna de [`../ca/`](../ca/README.md).

- **Servicio de compose:** `openldap` (imagen `osixia/openldap`).
- **Ficheros:** `05-acl-servicio.ldif` (permisos de la cuenta de servicio), `10-estructura.ldif` (una OU por departamento)
  y `20-usuarios-prueba.ldif` (usuarios de prueba), más este README.
- Lo usan ERPNext e InvenTree: [`../../docs/ldap.md`](../../docs/ldap.md).
  Direcciones IP y puertos: [`../../docs/arquitectura.md`](../../docs/arquitectura.md).

## Bootstrap

Los `*.ldif` de esta carpeta se montan en `/container/service/slapd/assets/config/bootstrap/ldif/custom`
(ver el `docker-compose.yml` de la raíz) y la imagen `osixia/openldap` los carga en orden alfabético **solo en el primer
arranque, con el volumen `ldap_data` vacío**. Si el directorio ya existe, no se vuelven a aplicar: para
recargarlos, `docker compose down -v` (borra los datos) o `ldapadd` a mano.

Base: `dc=reservaviva,dc=local`. Un usuario se busca por `uid` dentro de la OU de su departamento.

| Usuario (`uid`) | OU | Clave de laboratorio |
|---|---|---|
| `vet.prueba` | `ou=medica` | `Medica-Prueba1` |
| `logistica.prueba`, `taquilla.prueba` | `ou=operaciones` | `Oper-Prueba1` |
| `rrhh.prueba` | `ou=rrhh` | `Rrhh-Prueba1` |
| `cn=svc-lectura,ou=servicios` (cuenta de búsqueda de las apps) | `ou=servicios` | `Svc-Lectura1` |

Son claves de laboratorio, guardadas como hash SSHA. Cámbialas o borra estos usuarios fuera del laboratorio.
Cada aplicación busca solo en la OU de su departamento (InvenTree en `ou=operaciones`, ERPNext en `ou=rrhh`),
así que un usuario de un departamento no entra en la aplicación de otro.
