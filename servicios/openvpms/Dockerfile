# OpenVPMS 2.4.0.1 sobre Tomcat 9 + Java 11 (combinación soportada por la documentación oficial de 2.4).
# OpenVPMS no publica imagen Docker: este Dockerfile descarga el release oficial y el driver JDBC en
# tiempo de build (necesita Internet UNA vez, en una máquina con acceso; el laboratorio no tiene salida).
# Construir en un equipo con Internet y llevar la imagen: `docker save` / `docker load`.
#
# La base de datos (MySQL 8) va en otro contenedor del mismo host (servicio openvpms-db de ../../docker-compose.yml).
FROM tomcat:9.0-jdk11-temurin

ARG OPENVPMS_VERSION=2.4.0.1
ARG CONNECTOR_VERSION=8.0.33

ENV OPENVPMS_HOME=/opt/openvpms

RUN apt-get update \
 && apt-get install -y --no-install-recommends unzip curl ca-certificates default-mysql-client \
 && rm -rf /var/lib/apt/lists/*

RUN curl -fsSL -o /tmp/openvpms.zip \
      "https://repository.openvpms.org/releases/org/openvpms/openvpms-release/${OPENVPMS_VERSION}/openvpms-release-${OPENVPMS_VERSION}.zip" \
 && unzip -q /tmp/openvpms.zip -d /opt \
 && mv "/opt/openvpms-release-${OPENVPMS_VERSION}" "${OPENVPMS_HOME}" \
 && rm /tmp/openvpms.zip \
 && chmod +x "${OPENVPMS_HOME}"/bin/*.sh "${OPENVPMS_HOME}/bin/toolbox"

# El release no incluye el driver de MySQL: hace falta en el classpath de las herramientas y en Tomcat.
RUN curl -fsSL -o "${OPENVPMS_HOME}/lib/mysql-connector-j-${CONNECTOR_VERSION}.jar" \
      "https://repo1.maven.org/maven2/com/mysql/mysql-connector-j/${CONNECTOR_VERSION}/mysql-connector-j-${CONNECTOR_VERSION}.jar" \
 && cp "${OPENVPMS_HOME}/lib/mysql-connector-j-${CONNECTOR_VERSION}.jar" "${CATALINA_HOME}/lib/"

# init-lib.sh: lógica de inicialización reanudable que entrypoint.sh carga con `source` (probada por test-reanudable.sh).
COPY entrypoint.sh init-lib.sh /
RUN chmod +x /entrypoint.sh

# Recomendación oficial: al menos 1 GB de heap para Tomcat.
ENV CATALINA_OPTS="-Xms512m -Xmx1024m"

EXPOSE 8080
ENTRYPOINT ["/entrypoint.sh"]
CMD ["catalina.sh", "run"]
