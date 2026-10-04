# NTP interno (Infraestructura)

Servidor de hora del laboratorio, sin salida a Internet: sirve su propio reloj con stratum 10.

- **Servicio de compose:** `ntp` (contenedor `ntp-interno`, imagen `cturra/ntp`).
- **Ficheros:** solo este README. La configuración es la variable `NTP_SERVERS` del `docker-compose.yml` de la raíz, donde se explica por qué `127.127.1.1` hace que chrony sirva el reloj local.
- **Publicación:** `${HOST_IP}:${NTP_PORT}` → 123/udp.
- `sistema/verificar_arquitectura.py` comprueba el stratum, un cliente SNTP y un cliente chrony real.

Direcciones IP y puertos: [`../../docs/arquitectura.md`](../../docs/arquitectura.md).
