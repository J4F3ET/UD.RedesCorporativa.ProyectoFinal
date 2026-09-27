# InvenTree (Logística y Almacén, VLAN 30)

Inventario y almacén, con la imagen oficial `inventree/inventree`.

- **Servicios de compose:** `inventree-app` (web y API), `inventree-worker` (tareas en segundo plano) e `inventree-db` (PostgreSQL).
- **Ficheros:** solo este README. Toda la configuración está en el `docker-compose.yml` de la raíz.
- Autentica contra OpenLDAP por LDAPS (solo `ou=operaciones`) y verifica el certificado con la CA de [`../ca/`](../ca/README.md): [`../../docs/ldap.md`](../../docs/ldap.md).
- `INVENTREE_SITE_URL` es `http://inventree.reservaviva.lan` (la URL por nombre, a través del proxy web) e `INVENTREE_TRUSTED_ORIGINS` añade `http://localhost:<puerto>` (el acceso directo). La interfaz web `/web` responde 500 (INVE-E7) a una URL que no sea una de esas dos: con un solo origen, solo funcionaría uno de los accesos.

Direcciones IP y puertos: [`../../docs/arquitectura.md`](../../docs/arquitectura.md).
