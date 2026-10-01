# CA interna y certificado LDAPS (Infraestructura)

Autoridad de certificación propia del laboratorio y el certificado LDAPS de Samba AD (`samba-ad`) que firma. No es un servicio de compose: son ficheros que montan otros servicios.

- **Ficheros:**
  - `generar-certificados.sh`: genera la CA y el certificado de `ldap.reservaviva.lan` en `certs/`, con los SAN `ldap.reservaviva.lan`, `dc1.ad.reservaviva.lan`, `samba-ad`, `localhost`, `10.10.99.10` y `127.0.0.1`. Es idempotente: conserva lo que siga vigente, y si el SAN del certificado existente no cubre `ldap.reservaviva.lan` y la IP regenera solo `ldap.crt`/`ldap.key`, con la misma CA; `arrancar` **reinicia** entonces `samba-ad` (no hace falta recrearlo) para que lo cargue. Un `ldap.crt` anterior a la migración a Samba AD (sin los SAN nuevos) se regenera solo. `levantar-sistema.sh preparar` lo ejecuta y después comprueba que `certs/ca.crt` existe. Opciones: `--forzar` (regenera) y `--sin-instalar-ca`.
  - `certs/` (**no está en git**; cada instalación genera los suyos): `ca.crt` (CA pública), `ca.key` (clave de la CA; nunca se monta en un contenedor), `ldap.crt` y `ldap.key`.
- **Quién monta qué:** `samba-ad` monta `ca.crt`, `ldap.crt` y `ldap.key` de solo lectura y su entrypoint los copia con permisos 0600 (Samba rechaza la clave si no los tiene); `inventree-app` y `erpnext-backend` montan `ca.crt` en `/certs/ca.crt` para verificar LDAPS.
- Si falta un fichero montado, Docker crea un directorio vacío en su lugar y LDAPS falla sin un error claro.

Direcciones IP y puertos: [`../../docs/arquitectura.md`](../../docs/arquitectura.md).
