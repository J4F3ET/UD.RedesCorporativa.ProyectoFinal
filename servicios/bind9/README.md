# DNS interno: bind9 (Infraestructura, VLAN 99)

Servidor autoritativo de la zona `reservaviva.local`, sin recursión hacia Internet.

- **Servicio de compose:** `dns` (contenedor `dns-interno`).
- **Ficheros:**
  - `named.conf`: configuración de bind9 (solo la zona interna; `recursion no`).
  - `zones/db.reservaviva.local.tpl`: plantilla de la zona. Es lo único que se edita.
  - `zones/db.reservaviva.local`: la zona que monta el contenedor. **No está en git:** la genera `levantar-sistema.sh preparar` desde la plantilla, con la IP de cada contenedor, y el arranque reinicia `dns-interno` si cambió.
- Las aplicaciones no lo usan para encontrar LDAP (usan `extra_hosts`); `sistema/verificar_arquitectura.py` lo consulta de verdad y comprueba que cada nombre apunta al contenedor que da ese servicio.

Direcciones IP y puertos: [`../../docs/arquitectura.md`](../../docs/arquitectura.md).
