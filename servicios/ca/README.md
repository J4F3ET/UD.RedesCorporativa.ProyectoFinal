# CA interna y certificado LDAPS (Infraestructura)

Autoridad de certificación propia del laboratorio y el certificado de OpenLDAP que firma. No es un servicio de compose: son ficheros que montan otros servicios.

- **Ficheros:**
  - `generar-certificados.sh`: genera la CA y el certificado de `ldap.reservaviva.lan` en `certs/`. Es idempotente: conserva lo que siga vigente, y si el SAN del certificado existente no cubre `ldap.reservaviva.lan` (uno anterior con `.local`) regenera solo `ldap.crt`/`ldap.key`, con la misma CA; `arrancar` recrea entonces `openldap` para que lo cargue. `levantar-sistema.sh preparar` lo ejecuta y después comprueba que `certs/ca.crt` existe. Opciones: `--forzar` (regenera) y `--sin-instalar-ca`.
  - `certs/` (**no está en git**; cada instalación genera los suyos): `ca.crt` (CA pública), `ca.key` (clave de la CA; nunca se monta en un contenedor), `ldap.crt` y `ldap.key`.
- **Quién monta qué:** `openldap` monta `ca.crt`, `ldap.crt` y `ldap.key`; `inventree-app` y `erpnext-backend` montan `ca.crt` en `/certs/ca.crt` para verificar LDAPS.
- Si falta un fichero montado, Docker crea un directorio vacío en su lugar y LDAPS falla sin un error claro.

Direcciones IP y puertos: [`../../docs/arquitectura.md`](../../docs/arquitectura.md).
