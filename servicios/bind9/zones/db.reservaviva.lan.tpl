; PLANTILLA de la zona reservaviva.lan. NO se monta tal cual: levantar-sistema.sh (generar_zona) la convierte en
; db.reservaviva.lan sustituyendo ${IP_ANFITRION} por HOST_IP (la IP del equipo, donde estan publicados el proxy web, el DNS,
; LDAP/LDAPS y NTP), ${IP_DC} por la IP fija de samba-ad en la red del sistema y ${SERIAL} por la fecha. db.reservaviva.lan
; esta en .gitignore. Editar SOLO esta plantilla.
;
; Una sola zona para todos los clientes: los contenedores, el propio equipo y los equipos de la LAN. Todos los nombres de
; servicio llevan a la IP del equipo: los servicios se hablan por HOST_IP y el puerto publicado, no por la red de Docker.
; Las aplicaciones se sirven por el proxy web (puerto 80 de esa IP, por nombre); ldap y ntp llevan a la misma IP, con sus
; puertos (LDAP_PORT, LDAPS_PORT, NTP_PORT).
$TTL 300
@       IN SOA  dns.reservaviva.lan. admin.reservaviva.lan. (
                ${SERIAL} ; serial
                3600       ; refresh
                600        ; retry
                86400      ; expire
                300 )      ; negative TTL
        IN NS   dns.reservaviva.lan.

; --- Infraestructura: dns-interno (bind9), samba-ad (LDAP/LDAPS) y ntp-interno ---
dns         IN A ${IP_ANFITRION}
ldap        IN A ${IP_ANFITRION}
ntp         IN A ${IP_ANFITRION}

; --- Delegacion de ad.reservaviva.lan al Samba AD DC (samba-ad/dc1). Es una delegacion NS real (con su glue), no una zona
; "forward": dentro de una zona de la que bind9 es autoritativo (esta), una zona "type forward" para un subdominio NUNCA se
; llega a consultar, porque la zona autoritativa responde ella misma (NXDOMAIN con aa=1) para cualquier nombre bajo su
; propio arbol. La delegacion, en cambio, es el mecanismo estandar de DNS: bind9 devuelve el NS y, con "recursion yes" para
; los contenedores (ver named.conf), sigue la delegacion y reenvia la consulta a ${IP_DC}. Una delegacion no admite puerto:
; por eso el DC conserva su IP fija en la red del sistema (es la unica IP que no es HOST_IP).
ad          IN NS   dc1.ad.reservaviva.lan.
dc1.ad      IN A    ${IP_DC}

; --- Las cuatro aplicaciones, por nombre, a traves del proxy web (proxy-web) en el puerto 80 de la IP del equipo ---
openvpms    IN A ${IP_ANFITRION}
pretix      IN A ${IP_ANFITRION}
inventree   IN A ${IP_ANFITRION}
rrhh        IN A ${IP_ANFITRION}
