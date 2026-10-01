# Pretix (Taquilla y Boletería, VLAN 20)

Venta de entradas del zoológico, con la imagen oficial `pretix/standalone`.

- **Servicios de compose:** `pretix-web` (web; migra la base en el primer arranque), `pretix-worker` (celery), `pretix-cron` (tareas periódicas), `pretix-db` (PostgreSQL) y `pretix-redis`.
- **Ficheros:** solo este README. Toda la configuración está en el `docker-compose.yml` de la raíz; el administrador (`PRETIX_ADMIN_EMAIL` de `sistema/test.env`) lo crea `levantar-sistema.sh` tras el arranque.
- `PRETIX_PRETIX_URL` es `http://pretix.reservaviva.lan` (la URL por nombre, a través del proxy web). Pretix responde 400 a cualquier otro nombre de host salvo `localhost`, así que el acceso directo `http://localhost:<puerto>` sigue funcionando y `127.0.0.1` no.
- No usa LDAP; el motivo está en [`../../docs/directorio-activo.md`](../../docs/directorio-activo.md#pretix-solo-con-un-plugin-de-terceros-que-no-verifica-tls).

Direcciones IP y puertos: [`../../docs/arquitectura.md`](../../docs/arquitectura.md).
