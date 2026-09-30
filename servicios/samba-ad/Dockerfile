# Samba AD DC sobre Debian trixie (Samba 4.22 en los repositorios de trixie), en sustitucion de OpenLDAP. Reemplaza
# al directorio simple inetOrgPerson por un Active Directory Domain Controller completo: Kerberos, DNS propio con
# SRV, grupos y administracion con samba-tool/RSAT (docs/directorio-activo.md tiene la justificacion y la guia de
# migracion). No existe imagen oficial de Samba para Docker (wiki.samba.org no tiene pagina "Samba en Docker"); esta
# imagen sigue el patron descrito en helgeklein.com/blog/samba-active-directory-in-a-docker-container-installation-guide.
FROM debian:trixie

ENV DEBIAN_FRONTEND=noninteractive

# samba-ad-dc: el rol de Domain Controller. krb5-user/krb5-config: Kerberos (autenticacion del realm). winbind:
# utilidades de dominio (id/getent contra AD). ldap-utils: ldapsearch, para el healthcheck y para depurar a mano.
# dnsutils: dig/host, para comprobar el DNS interno de Samba y el reenvio de bind9. acl/attr: Samba guarda las ACL de
# AD en atributos extendidos security.* del sistema de ficheros (por eso el servicio necesita "privileged: true" en
# compose). python3-setproctitle: lo pide samba-tool para nombrar sus procesos; sin el, algunos subcomandos avisan.
RUN apt-get update \
 && apt-get install -y --no-install-recommends \
      samba-ad-dc \
      krb5-user \
      krb5-config \
      winbind \
      ldap-utils \
      dnsutils \
      acl \
      attr \
      python3-setproctitle \
 && rm -rf /var/lib/apt/lists/*

# La CA propia del laboratorio (servicios/ca/) no esta en el almacen de confianza del sistema: sin esto, ldapsearch y
# samba-tool contra ldaps:// rechazarian el certificado como no confiable. El entrypoint copia ca.crt aqui.
ENV LDAPTLS_CACERT=/var/lib/samba/private/tls/ca.crt

COPY entrypoint.sh sembrar.sh /usr/local/bin/
RUN chmod +x /usr/local/bin/entrypoint.sh /usr/local/bin/sembrar.sh

ENTRYPOINT ["/usr/local/bin/entrypoint.sh"]
