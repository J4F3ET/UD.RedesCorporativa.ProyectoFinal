# Proxy web por nombre: nginx (Infraestructura, VLAN 99)

Punto de entrada HTTP único para las cuatro aplicaciones por su nombre en la intranet: `openvpms.reservaviva.lan`, `pretix.reservaviva.lan`, `inventree.reservaviva.lan` y `rrhh.reservaviva.lan`. Escucha en el puerto 80 del equipo anfitrión y reparte cada petición según el nombre pedido (cabecera `Host`).

- **Servicio de compose:** `proxy` (contenedor `proxy-web`), imagen oficial `nginx:1.30.5-alpine` fijada por digest.
- **Red:** solo `vlan99_infra`, con IP fija `10.10.99.13`. Llega a cada aplicación por la IP que esta tiene en esa red: `openvpms-app` `.24:8080`, `pretix-web` `.21:80`, `inventree-app` `.22:8000` y `erpnext-hr` `.25:8080`.
- **Publicación:** `${INTRANET_IP}:${HTTP_PORT}` → 80. En modo local es `127.0.0.1:80` (valores de `sistema/test.env`). En modo intranet (`levantar-sistema --intranet`) el lanzador exporta `INTRANET_IP=<IP de la LAN>` solo para esa ejecución.
- **Ficheros:**
  - `reservaviva.conf.template`: la configuración. Es una plantilla porque las IP dependen de `NET_INFRA`: el entrypoint de la imagen oficial sustituye `${NET_INFRA}` y la escribe en `/etc/nginx/conf.d/default.conf`, en lugar de la página de bienvenida de la imagen. El filtro `NGINX_ENVSUBST_FILTER` limita la sustitución a esa variable, para no tocar las variables propias de nginx.

## Qué hace

| Nombre | Destino | Particularidad |
|---|---|---|
| `openvpms.reservaviva.lan` | `openvpms-app` | La raíz redirige a `/openvpms/`, donde vive la aplicación |
| `pretix.reservaviva.lan` | `pretix-web` | Es la URL propia de Pretix (`PRETIX_PRETIX_URL`) |
| `inventree.reservaviva.lan` | `inventree-app` | Es la URL propia de InvenTree (`INVENTREE_SITE_URL`) |
| `rrhh.reservaviva.lan` | `erpnext-hr` | El nginx de ERPNext: sirve `/assets`, el WebSocket de socket.io y pasa el resto al backend |
| cualquier otro nombre, o una IP | `default_server` | Responde 404 con un texto que lista los nombres válidos |

A todas les pasa el `Host` original (con el puerto, si no es el 80) y las cabeceras `X-Forwarded-For`, `X-Forwarded-Proto` y `X-Forwarded-Host`. Admite WebSocket (`Upgrade`/`Connection`), subidas de hasta 50 MB (lo mismo que admite el nginx de ERPNext) y 120 s de espera de respuesta. Las redirecciones propias son relativas (`absolute_redirect off`), para que sigan siendo correctas si `HTTP_PORT` no es 80. `/salud` responde `ok` para el healthcheck del contenedor.

## Decisiones

- **Solo en `vlan99_infra`.** Conectado a `vlan10`…`vlan40` sería un router entre departamentos y rompería la segmentación que demuestra `verificar`. En `vlan99_infra` ya están las cuatro aplicaciones, y es la misma red por la que ellas llegan a OpenLDAP, DNS y NTP. `verificar` comprueba que el proxy no tiene ninguna otra red.
- **RRHH por `erpnext-hr`, con una pata nueva en `vlan99_infra` (`.25`).** El proxy no puede ir a `erpnext-backend` (ya en `vlan99_infra`), porque gunicorn no sirve `/assets` ni socket.io; tampoco entrar en `vlan40_rrhh` ni en `erpnext_internal` (la red de la base de datos y Redis de ERPNext). La doble conexión de `erpnext-hr` es la opción menos invasiva: es un nginx sin estado, y es la misma doble conexión que ya tienen `openvpms-app`, `pretix-web` e `inventree-app`.
- **Sin `depends_on`.** Las direcciones son IP literales, así que nginx arranca aunque una aplicación aún no esté lista; esa aplicación responde 502 hasta que lo esté.
- **Solo HTTP.** Igual que el acceso directo: HTTPS queda fuera del laboratorio ([`../../docs/seguridad.md`](../../docs/seguridad.md)).

Para que los nombres resuelvan, el cliente debe usar el DNS del laboratorio (vista `lan` de [`../bind9/`](../bind9/README.md)). Cómo abrirlo a la LAN y cómo probarlo: [`../../docs/operacion.md`](../../docs/operacion.md#acceso-desde-la-lan). Direcciones IP y puertos: [`../../docs/arquitectura.md`](../../docs/arquitectura.md).
