; PLANTILLA de la zona reservaviva.local. NO se monta tal cual: levantar-sistema.sh (generar_zona) la convierte en
; db.reservaviva.local sustituyendo ${IP_PC1}, ${IP_PC2} e ${IP_PC3} por las IP de los contenedores del arnés
; y fija el serial. db.reservaviva.local esta en .gitignore. Editar SOLO esta plantilla.
$TTL 300
@       IN SOA  dns.reservaviva.local. admin.reservaviva.local. (
                ${SERIAL} ; serial
                3600       ; refresh
                600        ; retry
                86400      ; expire
                300 )      ; negative TTL
        IN NS   dns.reservaviva.local.

; --- PC-3: infraestructura (OpenLDAP, bind9, NTP) ---
dns         IN A ${IP_PC3}
ldap        IN A ${IP_PC3}
ntp         IN A ${IP_PC3}

; --- PC-1: Medica ---
openvpms    IN A ${IP_PC1}

; --- PC-2: Taquilla e Inventario ---
pretix      IN A ${IP_PC2}

inventree   IN A ${IP_PC2}

; --- PC-3: RRHH (ERPNext) ---
rrhh        IN A ${IP_PC3}
