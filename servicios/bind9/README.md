# DNS interno: bind9 (Infraestructura, VLAN 99)

Servidor autoritativo de la zona `reservaviva.lan`, sin recursión hacia Internet. Sirve la misma zona con dos contenidos (split horizon), según quién pregunte.

- **Servicio de compose:** `dns` (contenedor `dns-interno`).
- **Vistas** (en `named.conf`):
  - `interna`: los contenedores de las VLAN (subredes `10.10.x.0/24` sin su gateway `.1`). Cada nombre apunta a la IP del contenedor que da el servicio, como en el diseño. Además reenvía el subdominio `ad.reservaviva.lan` al Samba AD DC (`samba-ad`, `10.10.99.10`): una zona `type forward` necesita recursión, así que esta vista tiene `recursion yes; allow-recursion { red-interna; }`, **solo para ella**. Las `options` globales siguen en `recursion no` y la vista `lan` no lleva ese reenvío: sin la recursión limitada a esta vista, bind9 seguiría siendo autoritativo puro (sin forward) o, si se pusiera `recursion yes` en las `options` globales, este DNS dejaría de ser un resolutor cerrado a su propia zona.
  - `lan`: cualquier otro cliente, es decir, el propio equipo anfitrión y, en modo intranet, los equipos de la LAN. `openvpms`, `pretix`, `inventree`, `rrhh` y `dns` apuntan a la IP del anfitrión (`INTRANET_IP`: `127.0.0.1` en modo local, la IP de la LAN en modo intranet), donde escuchan el proxy web y el DNS. `ldap` y `ntp` no están en esta vista a propósito: Samba AD y NTP solo se publican en `127.0.0.1` y en puertos desplazados, así que un nombre que llevara a la IP de la LAN llevaría a un puerto cerrado. Tampoco lleva el reenvío de `ad.reservaviva.lan`: un cliente de la LAN no puede llegar a `10.10.99.10` de todos modos.
- **Por qué se excluye el gateway `.1`.** Una consulta del anfitrión al puerto publicado llega a bind9 con el gateway del bridge como origen (Docker la reenvía así). Ese cliente es el anfitrión, no un contenedor, y debe recibir la vista `lan`.
- **Ficheros:**
  - `named.conf`: configuración de bind9 (las dos vistas, `recursion no`).
  - `zones/db.reservaviva.lan.tpl`: plantilla de la vista interna.
  - `zones/db.reservaviva.lan.vista-lan.tpl`: plantilla de la vista lan.
  - Generados, **no están en git:** `zones/db.reservaviva.lan`, `zones/db.reservaviva.lan.vista-lan` y `zones/acl-interna.conf` (las subredes de la vista interna). Los genera `levantar-sistema.sh preparar` (también `arrancar`) desde las plantillas y las subredes `NET_*`; solo reescribe un fichero si cambió algo más que el serial, y el arranque reinicia `dns-interno` si alguno (o `named.conf`) es más nuevo que el contenedor.
- **Publicación:** modo local, `127.0.0.1:1053` udp y tcp (`DNS_BIND_IP` y `DNS_PORT` de `sistema/test.env`); modo intranet, `<IP de la LAN>:53` (el lanzador exporta las dos variables solo para esa ejecución).
- Las aplicaciones no lo usan para encontrar LDAP (usan `extra_hosts`). `sistema/verificar_arquitectura.py` lo consulta de verdad por las dos vistas: desde `vlan99_infra` (cada nombre apunta al contenedor que da ese servicio) y desde el anfitrión por el puerto publicado (cada aplicación apunta a la IP del proxy web).

El dominio antes era `reservaviva.local`. Se cambió porque `.local` está reservado a mDNS (RFC 6762): macOS, Linux con Avahi y los móviles lo resuelven por multicast y no preguntan a este DNS. Direcciones IP y puertos: [`../../docs/arquitectura.md`](../../docs/arquitectura.md).
