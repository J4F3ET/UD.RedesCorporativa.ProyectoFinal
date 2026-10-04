# OpenVPMS (Unidad Médica Veterinaria, VLAN 10)

Historia clínica y gestión de la unidad veterinaria. OpenVPMS no publica imagen Docker, así que se construye aquí.

- **Servicios de compose:** `openvpms-app` (Tomcat + OpenVPMS 2.4.0.1, imagen construida con este `Dockerfile`) y `openvpms-db` (MySQL 8).
- **Ficheros:**
  - `Dockerfile`: descarga el release oficial y el driver JDBC (necesita Internet la primera vez).
  - `entrypoint.sh` e `init-lib.sh`: inicialización reanudable (esquema, datos base, clave de administrador); si se corta, el siguiente arranque retoma donde quedó.
  - `test-reanudable.sh`: prueba sin Docker de esa lógica (`bash servicios/openvpms/test-reanudable.sh`).
- No usa LDAP; el motivo está en [`../../docs/directorio-activo.md`](../../docs/directorio-activo.md#openvpms-2401-sin-soporte-ldap).

Direcciones IP y puertos: [`../../docs/arquitectura.md`](../../docs/arquitectura.md).
