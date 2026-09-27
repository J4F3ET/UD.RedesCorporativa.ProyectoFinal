; PLANTILLA de la zona reservaviva.lan para la VISTA "lan": cualquier cliente que NO sea un contenedor de las VLAN (el
; propio equipo anfitrion y, en modo intranet, los equipos de la LAN). levantar-sistema.sh (generar_zona) la convierte en
; db.reservaviva.lan.vista-lan (fuera de git) sustituyendo IP_ANFITRION por la IP en la que se publican el proxy web y el
; DNS (INTRANET_IP: 127.0.0.1 en modo local, la IP de la LAN en modo intranet) y SERIAL por la fecha.
;
; Solo se anuncian las cuatro aplicaciones (las sirve el proxy web en el puerto 80 de esa IP) y el propio DNS.
; ldap y ntp NO estan en esta vista a proposito: OpenLDAP y NTP se publican solo en 127.0.0.1 y en puertos desplazados
; (1389/1636/1123), asi que un nombre que apuntara a la IP de la LAN llevaria a un puerto cerrado. Un cliente de la LAN
; recibe NXDOMAIN para ellos, que es lo honesto.
$TTL 300
@       IN SOA  dns.reservaviva.lan. admin.reservaviva.lan. (
                ${SERIAL} ; serial
                3600       ; refresh
                600        ; retry
                86400      ; expire
                300 )      ; negative TTL
        IN NS   dns.reservaviva.lan.

; --- El DNS: dns-interno, publicado en la IP del anfitrion ---
dns         IN A ${IP_ANFITRION}

; --- Las cuatro aplicaciones: el proxy web (proxy-web) en el puerto 80 de la IP del anfitrion ---
openvpms    IN A ${IP_ANFITRION}
pretix      IN A ${IP_ANFITRION}
inventree   IN A ${IP_ANFITRION}
rrhh        IN A ${IP_ANFITRION}
