# InvenTree (Logística y Almacén, VLAN 30)

Inventario y almacén, con la imagen oficial `inventree/inventree`.

- **Servicios de compose:** `inventree-app` (web y API), `inventree-worker` (tareas en segundo plano) e `inventree-db` (PostgreSQL).
- **Ficheros:** solo este README. Toda la configuración está en el `docker-compose.yml` de la raíz.
- Autentica contra Samba AD por LDAPS (`django-auth-ldap`) y verifica el certificado con la CA de [`../ca/`](../ca/README.md). El login es por `sAMAccountName`, con la búsqueda de usuarios en toda la base del dominio (`DC=ad,DC=reservaviva,DC=lan`) filtrada por pertenencia **directa** a `GG-Operaciones` (`OU=Grupos,DC=ad,DC=reservaviva,DC=lan`): `(&(objectClass=user)(sAMAccountName=%(user)s)(memberOf=CN=GG-Operaciones,OU=Grupos,DC=ad,DC=reservaviva,DC=lan))`. El bind DN del servicio es `CN=svc-lectura,OU=Servicios,DC=ad,DC=reservaviva,DC=lan` (sembrado con `--use-username-as-cn`, ver `servicios/samba-ad/sembrar.sh`); el mapeo de atributos (`first_name`/`last_name`/`email` desde `givenName`/`sn`/`mail`) es el valor por defecto de InvenTree, sin cambios. Detalle y pruebas: [`../../docs/directorio-activo.md`](../../docs/directorio-activo.md#4-cómo-autentican-inventree-y-erpnext).
- `INVENTREE_SITE_URL` es `http://inventree.reservaviva.lan` (la URL por nombre, a través del proxy web) e `INVENTREE_TRUSTED_ORIGINS` añade `http://localhost:<puerto>` (el acceso directo). La interfaz web `/web` responde 500 (INVE-E7) a una URL que no sea una de esas dos: con un solo origen, solo funcionaría uno de los accesos.

Direcciones IP y puertos: [`../../docs/arquitectura.md`](../../docs/arquitectura.md).
