# Estructura del directorio: una unidad organizativa (OU) por departamento + cuentas de servicio.
# Se carga UNA sola vez, en el primer arranque de OpenLDAP con el volumen ldap_data vacío.
# PLANTILLA: levantar-sistema.sh preparar la copia a servicios/openldap/generado/ sustituyendo ${SSHA_SVC_LECTURA} por el
# hash SSHA de LDAP_SVC_LECTURA_PASSWORD (sistema/test.env, unica fuente de la clave). Aqui no hay ninguna clave.
dn: ou=medica,dc=reservaviva,dc=local
objectClass: organizationalUnit
ou: medica
description: Veterinaria y Clinica (VLAN 10, OpenVPMS)

dn: ou=operaciones,dc=reservaviva,dc=local
objectClass: organizationalUnit
ou: operaciones
description: Taquilla y Logistica (VLAN 20 y 30, Pretix e InvenTree)

dn: ou=rrhh,dc=reservaviva,dc=local
objectClass: organizationalUnit
ou: rrhh
description: Recursos Humanos (VLAN 40, ERPNext)

dn: ou=servicios,dc=reservaviva,dc=local
objectClass: organizationalUnit
ou: servicios
description: Cuentas de servicio de solo lectura que usan las aplicaciones para buscar usuarios

dn: cn=svc-lectura,ou=servicios,dc=reservaviva,dc=local
objectClass: inetOrgPerson
cn: svc-lectura
sn: svc-lectura
description: Cuenta de busqueda (bind) de las aplicaciones. Su clave: LDAP_SVC_LECTURA_PASSWORD en sistema/test.env
userPassword: ${SSHA_SVC_LECTURA}
