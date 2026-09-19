> **Nota:** la prueba se escribió para el escenario de 2 equipos; los hallazgos sobre la inicialización manual de Pretix, InvenTree y ERPNext siguen siendo válidos para el diseño de 3 equipos.

# Resultados de la Prueba de Humo — Un Solo Host (Docker)
Objetivo: verificar que el stack de servicios de Reserva Viva arranca con
`docker compose up -d` sin pasos manuales de configuración adicionales, como
paso previo al despliegue físico plug-and-play de 2 equipos.

## 1. Estado de la prueba: NO se pudo ejecutar en vivo en esta sesión

Docker Desktop no logró iniciar el motor en esta máquina durante la sesión de
hoy. Causa raíz encontrada en los logs (`%LOCALAPPDATA%\Docker\log\host\`):

```
initializing Ingest server: listening on unix://.../run/sailor-ingest.sock:
rename .../sailor-ingest.sock .../sailor-ingest.sock.stale:
The file cannot be accessed by the system.
```

Un socket (`sailor-ingest.sock`) quedó de una ejecución anterior y Windows no
permite renombrarlo ni borrarlo, ni siquiera después de detener todos los
procesos y el servicio `com.docker.service`. Esto hace que el backend de
Docker aborte el arranque cada vez.

**Solución recomendada (para ti, en tu máquina):**
1. Reinicia Windows por completo (esto libera el handle atascado del archivo).
2. Abre Docker Desktop y espera a que la ballena del ícono deje de animarse
   (motor listo).
3. Verifica con: `docker info` (no debe dar error).
4. Ejecuta la prueba con el paquete de la sección 3.

Si el problema persiste tras reiniciar, borra manualmente la carpeta
`%LOCALAPPDATA%\Docker\run\` con Docker Desktop cerrado, o reinstala Docker
Desktop.

## 2. Lo que sí se validó (análisis estático, sin ejecutar contenedores)

### 2.1. Sintaxis del compose
`docker compose config` valida correctamente el archivo consolidado
(`reserva-viva-test/docker-compose.yml`) — sin errores de sintaxis, redes,
volúmenes ni variables de entorno faltantes.

### 2.2. ¿Qué servicios son realmente "cero configuración"?

Basado en el comportamiento documentado de cada imagen oficial:

| Servicio | Imagen | ¿Arranca sin pasos manuales? | Detalle |
|---|---|---|---|
| LDAP | `osixia/openldap` | **Sí** | Se auto-inicializa con las variables de entorno (`LDAP_ORGANISATION`, `LDAP_DOMAIN`, `LDAP_ADMIN_PASSWORD`) en el primer arranque. |
| phpLDAPadmin | `osixia/phpldapadmin` | **Sí** | Solo necesita apuntar al host LDAP. |
| MySQL / MariaDB / PostgreSQL / Redis | oficiales | **Sí** | Se auto-inicializan con las variables `*_PASSWORD`/`*_DATABASE`. |
| **Pretix** | `pretix/standalone` | **No del todo** | El contenedor corre migraciones automáticamente, pero requiere crear el **usuario administrador la primera vez** con un comando de gestión (`manage.py createsuperuser` o equivalente) antes de poder iniciar sesión. |
| **InvenTree** | `inventree/inventree` | **No del todo** | El despliegue oficial usa comandos `invoke` de inicialización (migraciones + creación de superusuario) en el primer arranque; no es un simple "up -d" y ya. |
| **ERPNext** | `frappe/erpnext` | **No** | Esta imagen espera un *site* de Frappe ya creado. Sin un contenedor/job de "create-site" (`bench new-site ...`) ejecutado una vez, el contenedor no tiene nada que servir. El propio `docker-compose-preproyecto.yml` ya lo advertía: se recomienda usar el repo oficial `frappe/frappe_docker`, que sí incluye ese job de inicialización. |
| OpenVPMS | *(sin imagen oficial)* | N/A | Requiere Dockerfile propio (Tomcat + WAR); no evaluable con este compose. |

**Conclusión honesta:** el proyecto **no es 100% "plug-and-play" a nivel de
aplicación** con los compose actuales — el switch/red sí puede ser
plug-and-play (esa es la parte de infraestructura), pero **Pretix, InvenTree
y ERPNext necesitan un comando de inicialización una sola vez** (crear
usuario admin / crear site) antes de quedar operativos. Esto es normal y
esperado para este tipo de aplicaciones; lo importante para el informe es
dejarlo documentado como "configuración inicial de aplicación" (una vez),
separada de "arranque de infraestructura de red" (siempre plug-and-play).

## 3. Paquete de prueba listo para ejecutar (en cuanto Docker funcione)

Archivo: `reserva-viva-test/docker-compose.yml` (en esta misma carpeta de
trabajo). Pasos:

```bash
cd reserva-viva-test
docker compose pull      # descarga las imágenes (~3-5 GB, puede tardar)
docker compose up -d     # levanta los 4 servicios + LDAP
docker compose ps        # todos deben quedar "running" o "healthy"
docker compose logs -f   # revisar que ninguno entre en loop de reinicio
```

Pruebas de integración sugeridas una vez arriba:

```bash
# LDAP responde
docker exec ldap-reservaviva ldapsearch -x -H ldap://localhost -b "dc=reservaviva,dc=local" -D "cn=admin,dc=reservaviva,dc=local" -w CAMBIAR_ESTA_CLAVE

# Pretix responde en su puerto publicado
curl -I http://localhost:8020

# InvenTree responde
curl -I http://localhost:8030

# ERPNext (fallará hasta que exista un site — ver §2.2)
curl -I http://localhost:8040
```

Al terminar: `docker compose down -v` para limpiar los volúmenes de prueba.
