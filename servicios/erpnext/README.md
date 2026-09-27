# ERPNext HR (Recursos Humanos, VLAN 40)

Gestión de personal y turnos 24/7, con la imagen oficial `ghcr.io/frappe/hrms` (ERPNext + app hrms).

- **Servicios de compose:** `erpnext-hr` (nginx, el que atiende a los usuarios), `erpnext-backend` (gunicorn; el único que habla LDAPS), `erpnext-websocket`, `erpnext-scheduler`, `erpnext-queue-short`, `erpnext-queue-long`, `erpnext-db` (MariaDB), `erpnext-redis-cache`, `erpnext-redis-queue` y tres trabajos de un solo disparo: `erpnext-configurator`, `erpnext-create-site` (crea el sitio `rrhh.reservaviva.local`, idempotente; el nombre del sitio es un identificador interno y conserva el sufijo antiguo) y `erpnext-ldap-config` (en cada `up` vuelve a escribir "LDAP Settings", con `ldaps://ldap.reservaviva.lan:636`). `erpnext-hr` tiene además una pata en `vlan99_infra` (`10.10.99.25`) por la que le llega el proxy web para `rrhh.reservaviva.lan`.
- **Ficheros:** `test-create-site.sh`, prueba sin Docker del script de `erpnext-create-site`: lo extrae del `docker-compose.yml` de la raíz y lo ejecuta contra un `bench` simulado (`bash servicios/erpnext/test-create-site.sh`; necesita python3 con PyYAML).
- Autentica contra OpenLDAP por LDAPS (solo `ou=rrhh`): [`../../docs/ldap.md`](../../docs/ldap.md).

Direcciones IP y puertos: [`../../docs/arquitectura.md`](../../docs/arquitectura.md).
