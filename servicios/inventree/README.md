# InvenTree (Logística y Almacén, VLAN 30)

Inventario y almacén, con la imagen oficial `inventree/inventree`.

- **Servicios de compose:** `inventree-app` (web y API), `inventree-worker` (tareas en segundo plano) e `inventree-db` (PostgreSQL).
- **Ficheros:** solo este README. Toda la configuración está en el `docker-compose.yml` de la raíz.
- Autentica contra OpenLDAP por LDAPS (solo `ou=operaciones`) y verifica el certificado con la CA de [`../ca/`](../ca/README.md): [`../../docs/integracion-ldap-erpnext-inventree.md`](../../docs/integracion-ldap-erpnext-inventree.md).
- `INVENTREE_SITE_URL` debe ser la URL que abre el navegador (`http://localhost:<puerto>`): con otra, la interfaz web `/web` responde 500.

Direcciones IP y puertos: [`../../docs/arquitectura.md`](../../docs/arquitectura.md).
