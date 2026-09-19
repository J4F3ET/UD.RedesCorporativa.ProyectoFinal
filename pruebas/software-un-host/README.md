# Prueba real #1 — Software en un solo equipo (tu laptop)

Esta es la primera prueba real del proyecto: valida que **Pretix, InvenTree, ERPNext y OpenLDAP arrancan y responden juntos**, sin necesitar switch, VLANs ni los 3 PCs físicos todavía. Es exactamente el paso 3 que ya proponía el handoff original: *"Correr el docker-compose en un solo equipo para validar que las apps + LDAP funcionan bien juntas (fase de software puro, sin tocar el switch aún)"*.

## Qué NO prueba esto

- **No prueba VLANs, segmentación ni el switch** — eso solo se puede probar con los 3 PCs físicos y el hardware real (ver `docker/pc1-medica/`, `docker/pc2-operaciones/`, `docker/pc3-administracion-infra/`).
- **No incluye OpenVPMS** — no tiene imagen oficial y su Dockerfile (`docker/pc1-medica/openvpms/`) todavía no existe en el repo.
- **No incluye DNS ni NTP** — el compose de producción los referencia con archivos de configuración (`bind/named.conf`, `bind/zones/`) que tampoco existen todavía.
- **ERPNext puede fallar** — la imagen `frappe/erpnext:latest` sola, sin el resto del stack de `frappe_docker` (mariadb, redis-queue, redis-cache, bench init), es una simplificación conocida. Si falla al arrancar, es un hallazgo esperado de esta prueba, no algo que tengas que arreglar en tu laptop.

## Requisitos

- Docker Desktop (o Docker Engine) instalado y corriendo en tu computador.
- Puertos libres en tu máquina: `18080`, `18090`, `18095`, `1389`.

## Cómo correrla

```bash
cd pruebas/software-un-host
cp .env.example .env
# editar .env y poner contraseñas propias

docker compose up -d
```

La primera vez tarda varios minutos (descarga las imágenes). Cuando termine:

```bash
./verificar.sh
```

Esto te muestra el estado de cada contenedor y prueba que cada aplicación responde. Si algo falló, te dice qué comando correr para ver el log de ese servicio.

## Qué mirar manualmente

- **Pretix:** abrir http://localhost:18080 en el navegador — debería verse la pantalla de configuración inicial.
- **InvenTree:** abrir http://localhost:18090 — igual, pantalla inicial o de login.
- **ERPNext:** abrir http://localhost:18095 — si no carga nada, es el hallazgo conocido de la sección anterior, no te detengas ahí.
- **OpenLDAP:** si tienes `ldapsearch` instalado:
  ```bash
  ldapsearch -x -H ldap://localhost:1389 -D "cn=admin,dc=reservaviva,dc=local" -w <la contraseña que pusiste en .env> -b "dc=reservaviva,dc=local"
  ```

## Cuando termines

```bash
docker compose down       # apaga todo, conserva los datos
docker compose down -v    # apaga todo y borra los datos (para empezar de cero)
```

## Siguiente prueba real

Una vez esto funcione (o se documenten los hallazgos de lo que falló), el siguiente paso real es construir el Dockerfile de OpenVPMS y la configuración de bind9 — ver los pendientes en el `README.md` de la raíz del repo — y recién después pasar a las pruebas con los 3 PCs físicos y el switch (sección 7 de `docs/arquitectura-3-equipos-departamentos.md`).
