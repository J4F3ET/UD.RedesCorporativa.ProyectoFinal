# ERPNext HR (Recursos Humanos, VLAN 40)

Gestión de personal y turnos 24/7, con la imagen oficial `ghcr.io/frappe/hrms` (ERPNext + app hrms).

- **Servicios de compose:** `erpnext-hr` (nginx, el que atiende a los usuarios), `erpnext-backend` (gunicorn; el único que habla LDAPS), `erpnext-websocket`, `erpnext-scheduler`, `erpnext-queue-short`, `erpnext-queue-long`, `erpnext-db` (MariaDB), `erpnext-redis-cache`, `erpnext-redis-queue` y tres trabajos de un solo disparo: `erpnext-configurator`, `erpnext-create-site` (crea el sitio `rrhh.reservaviva.local`, idempotente) y `erpnext-ldap-config`.
- **Ficheros:** `test-create-site.sh`, prueba sin Docker del script de `erpnext-create-site`: lo extrae del `docker-compose.yml` de la raíz y lo ejecuta contra un `bench` simulado (`bash servicios/erpnext/test-create-site.sh`; necesita python3 con PyYAML).
- Autentica contra OpenLDAP por LDAPS (solo `ou=rrhh`): [`../../docs/ldap.md`](../../docs/ldap.md).

Direcciones IP y puertos: [`../../docs/arquitectura.md`](../../docs/arquitectura.md).
