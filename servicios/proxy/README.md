# Proxy web por nombre: nginx (Infraestructura)

Punto de entrada HTTP único para las cuatro aplicaciones por su nombre en la intranet: `openvpms.reservaviva.lan`, `pretix.reservaviva.lan`, `inventree.reservaviva.lan` y `rrhh.reservaviva.lan`. Escucha en el puerto 80 del equipo anfitrión y reparte cada petición según el nombre pedido (cabecera `Host`).

- **Servicio de compose:** `proxy` (contenedor `proxy-web`), imagen oficial `nginx:1.30.5-alpine` fijada por digest.
- **Red:** `reservaviva`, sin IP fija. Llega a cada aplicación por la IP del equipo y el puerto en el que esta publicada: `openvpms-app` `${HOST_IP}:${OPENVPMS_PORT}`, `pretix-web` `${HOST_IP}:${PRETIX_PORT}`, `inventree-app` `${HOST_IP}:${INVENTREE_PORT}` y `erpnext-hr` `${HOST_IP}:${ERPNEXT_PORT}`.
- **Publicación:** `${HOST_IP}:${HTTP_PORT}` → 80 (valores de `sistema/test.env`; `levantar-sistema --ip X` o `--intranet` cambian `HOST_IP` solo para esa ejecución).
- **Ficheros:**
  - `reservaviva.conf.template`: la configuración. Es una plantilla porque la IP y los puertos son variables: el entrypoint de la imagen oficial sustituye `${HOST_IP}`, `${OPENVPMS_PORT}`, `${PRETIX_PORT}`, `${INVENTREE_PORT}` y `${ERPNEXT_PORT}` y la escribe en `/etc/nginx/conf.d/default.conf`, en lugar de la página de bienvenida de la imagen. El filtro `NGINX_ENVSUBST_FILTER` limita la sustitución a esas cinco variables, para no tocar las variables propias de nginx.

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

- **Por `HOST_IP:puerto`, no por la red de Docker.** El switch del laboratorio obliga a una sola IP y un puerto por servicio, así que el proxy trata a las aplicaciones como cualquier cliente de la LAN: va a donde están publicadas. Por eso no hay que conectarlo a más redes ni darles IP fijas.
- **RRHH por `erpnext-hr`.** El proxy no puede ir a `erpnext-backend` porque gunicorn no sirve `/assets` ni socket.io; `erpnext-hr` es un nginx sin estado que sí lo hace y reparte entre backend y websocket por `erpnext_internal`.
- **Sin `depends_on`.** Las direcciones son `HOST_IP` y puertos, así que nginx arranca aunque una aplicación aún no esté lista; esa aplicación responde 502 hasta que lo esté.
- **Solo HTTP.** Igual que el acceso directo: HTTPS queda fuera del laboratorio ([`../../docs/seguridad.md`](../../docs/seguridad.md)).

Para que los nombres resuelvan, el cliente debe usar el DNS del laboratorio (zona de [`../bind9/`](../bind9/README.md)). Cómo abrirlo a la LAN y cómo probarlo: [`../../docs/operacion.md`](../../docs/operacion.md#acceso-desde-la-lan). Direcciones IP y puertos: [`../../docs/arquitectura.md`](../../docs/arquitectura.md).
