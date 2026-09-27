# Pretix (Taquilla y Boletería, VLAN 20)

Venta de entradas del zoológico, con la imagen oficial `pretix/standalone`.

- **Servicios de compose:** `pretix-web` (web; migra la base en el primer arranque), `pretix-worker` (celery), `pretix-cron` (tareas periódicas), `pretix-db` (PostgreSQL) y `pretix-redis`.
- **Ficheros:** solo este README. Toda la configuración está en el `docker-compose.yml` de la raíz; el administrador (`PRETIX_ADMIN_EMAIL` de `sistema/test.env`) lo crea `levantar-sistema.sh` tras el arranque.
- `PRETIX_PRETIX_URL` debe ser la URL que abre el navegador (`http://localhost:<puerto>`): Pretix responde 400 a otro nombre de host.
- No usa LDAP; el motivo está en [`../../docs/ldap.md`](../../docs/ldap.md#7-pretix-solo-con-un-plugin-de-terceros-que-no-verifica-tls).

Direcciones IP y puertos: [`../../docs/arquitectura.md`](../../docs/arquitectura.md).
