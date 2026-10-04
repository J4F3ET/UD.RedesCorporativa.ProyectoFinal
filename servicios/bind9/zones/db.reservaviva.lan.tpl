; PLANTILLA de la zona reservaviva.lan para la VISTA INTERNA (clientes de las VLAN 10.10.x). NO se monta tal cual:
; levantar-sistema.sh (generar_zona) la convierte en db.reservaviva.lan sustituyendo cada marcador IP_<NOMBRE> por la IP
; fija del contenedor que da ese servicio en el sistema de un host, y SERIAL por la fecha. db.reservaviva.lan esta en
; .gitignore. Editar SOLO esta plantilla. La vista "lan" (el host y los equipos de la LAN) usa db.reservaviva.lan.vista-lan.tpl.
$TTL 300
@       IN SOA  dns.reservaviva.lan. admin.reservaviva.lan. (
                ${SERIAL} ; serial
                3600       ; refresh
                600        ; retry
                86400      ; expire
                300 )      ; negative TTL
        IN NS   dns.reservaviva.lan.

; --- Infraestructura (vlan99): samba-ad, dns-interno (bind9), ntp-interno ---
dns         IN A ${IP_DNS}
ldap        IN A ${IP_LDAP}
ntp         IN A ${IP_NTP}

; --- Delegacion de ad.reservaviva.lan al Samba AD DC (samba-ad/dc1), SOLO en esta vista (ver named.conf, vista
; "interna"). Es una delegacion NS real (con su glue), no una zona "forward": dentro de una zona de la que bind9 es
; autoritativo (esta), una zona "type forward" para un subdominio NUNCA se llega a consultar, porque la zona
; autoritativa responde ella misma (NXDOMAIN con aa=1) para cualquier nombre bajo su propio arbol. La delegacion,
; en cambio, es el mecanismo estandar de DNS: bind9 devuelve el NS y, con "recursion yes" en esta vista, sigue la
; delegacion y reenvia la consulta a ${IP_LDAP}. NO va en db.reservaviva.lan.vista-lan.tpl: la vista "lan" no debe
; resolver ad.reservaviva.lan (sigue dando NXDOMAIN, como antes).
ad          IN NS   dc1.ad.reservaviva.lan.
dc1.ad      IN A    ${IP_LDAP}

; --- Medica (vlan10): openvpms-app ---
openvpms    IN A ${IP_OPENVPMS}

; --- Taquilla (vlan20): pretix-web ---
pretix      IN A ${IP_PRETIX}

; --- Logistica (vlan30): inventree-app ---
inventree   IN A ${IP_INVENTREE}

; --- RRHH (vlan40): erpnext-hr, el nginx de ERPNext que atiende a los usuarios ---
rrhh        IN A ${IP_RRHH}
