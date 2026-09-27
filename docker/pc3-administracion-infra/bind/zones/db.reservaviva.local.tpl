; PLANTILLA de la zona reservaviva.local. NO se monta tal cual: levantar-sistema.sh (generar_zona) la convierte en
; db.reservaviva.local sustituyendo cada marcador IP_<NOMBRE> por la IP fija del contenedor que da ese servicio en el
; sistema de un host, y SERIAL por la fecha. db.reservaviva.local esta en .gitignore. Editar SOLO esta plantilla.
$TTL 300
@       IN SOA  dns.reservaviva.local. admin.reservaviva.local. (
                ${SERIAL} ; serial
                3600       ; refresh
                600        ; retry
                86400      ; expire
                300 )      ; negative TTL
        IN NS   dns.reservaviva.local.

; --- Infraestructura (vlan99): openldap, dns-interno (bind9), ntp-interno ---
dns         IN A ${IP_DNS}
ldap        IN A ${IP_LDAP}
ntp         IN A ${IP_NTP}

; --- Medica (vlan10): openvpms-app ---
openvpms    IN A ${IP_OPENVPMS}

; --- Taquilla (vlan20): pretix-web ---
pretix      IN A ${IP_PRETIX}

; --- Logistica (vlan30): inventree-app ---
inventree   IN A ${IP_INVENTREE}

; --- RRHH (vlan40): erpnext-hr, el nginx de ERPNext que atiende a los usuarios ---
rrhh        IN A ${IP_RRHH}
