# CA interna y certificado LDAPS (Infraestructura)

Autoridad de certificación propia del laboratorio y el certificado de OpenLDAP que firma. No es un servicio de compose: son ficheros que montan otros servicios.

- **Ficheros:**
  - `generar-certificados.sh`: genera la CA y el certificado de `ldap.reservaviva.local` en `certs/`. Es idempotente: conserva lo que siga vigente. `levantar-sistema.sh preparar` lo ejecuta y después comprueba que `certs/ca.crt` existe. Opciones: `--forzar` (regenera) y `--sin-instalar-ca`.
  - `certs/` (**no está en git**; cada instalación genera los suyos): `ca.crt` (CA pública), `ca.key` (clave de la CA; nunca se monta en un contenedor), `ldap.crt` y `ldap.key`.
- **Quién monta qué:** `openldap` monta `ca.crt`, `ldap.crt` y `ldap.key`; `inventree-app` y `erpnext-backend` montan `ca.crt` en `/certs/ca.crt` para verificar LDAPS.
- Si falta un fichero montado, Docker crea un directorio vacío en su lugar y LDAPS falla sin un error claro.

Direcciones IP y puertos: [`../../docs/arquitectura.md`](../../docs/arquitectura.md).
