# Usuarios de PRUEBA (solo laboratorio). PLANTILLA: levantar-sistema.sh preparar la copia a servicios/openldap/generado/
# sustituyendo cada ${SSHA_<UID>} por el hash SSHA de LDAP_PRUEBA_<UID>_PASSWORD (sistema/test.env, unica fuente de
# las claves). Aqui no hay ninguna clave. Cambiar o borrar estos usuarios fuera del laboratorio.

# --- ou=medica ---
dn: uid=vet.prueba,ou=medica,dc=reservaviva,dc=local
objectClass: inetOrgPerson
uid: vet.prueba
cn: Vet Prueba
givenName: Vet
sn: Prueba
mail: vet.prueba@reservaviva.local
userPassword: ${SSHA_VET}

# --- ou=operaciones ---
dn: uid=logistica.prueba,ou=operaciones,dc=reservaviva,dc=local
objectClass: inetOrgPerson
uid: logistica.prueba
cn: Logistica Prueba
givenName: Logistica
sn: Prueba
mail: logistica.prueba@reservaviva.local
userPassword: ${SSHA_LOGISTICA}

dn: uid=taquilla.prueba,ou=operaciones,dc=reservaviva,dc=local
objectClass: inetOrgPerson
uid: taquilla.prueba
cn: Taquilla Prueba
givenName: Taquilla
sn: Prueba
mail: taquilla.prueba@reservaviva.local
userPassword: ${SSHA_TAQUILLA}

# --- ou=rrhh ---
dn: uid=rrhh.prueba,ou=rrhh,dc=reservaviva,dc=local
objectClass: inetOrgPerson
uid: rrhh.prueba
cn: RRHH Prueba
givenName: RRHH
sn: Prueba
mail: rrhh.prueba@reservaviva.local
userPassword: ${SSHA_RRHH}
