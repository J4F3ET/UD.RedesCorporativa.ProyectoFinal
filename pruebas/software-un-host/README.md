# Prueba real #1 — Software en un solo equipo (HISTÓRICA, ya superada)

> **Esta prueba está congelada como evidencia de la primera ronda. No la ejecutes.**
> La reemplaza [`../smoke-test-3-pcs/`](../smoke-test-3-pcs/), que levanta los **tres**
> `docker-compose.yml` reales (22 contenedores, incluido OpenVPMS) en un solo host, usando
> `include:` y sobrescribiendo únicamente las redes macvlan por bridge. Los resultados vigentes
> están en [`../../docs/prueba-smoke-test-resultados.md`](../../docs/prueba-smoke-test-resultados.md).

Se conserva porque es el registro de cómo se descubrieron varios de los defectos que hoy ya
están corregidos en `docker/pc*/docker-compose.yml`. Su `docker-compose.yml` refleja el estado
del repo en ese momento, **no** el diseño actual.

## Qué se descubrió aquí (y dónde se arregló)

| Hallazgo de esta ronda | Estado hoy |
|---|---|
| `frappe/erpnext:latest` sola responde HTTP 404: no hay *site* ni MariaDB | Resuelto: PC-3 usa el stack completo de `frappe_docker` con `frappe/erpnext:v15` (11 servicios). **`latest` resultó ser `17.0.0-dev`: no volver a usarlo.** |
| OpenVPMS quedó fuera por no tener imagen oficial | Resuelto: `docker/pc1-medica/openvpms/Dockerfile` construye Tomcat 9 + el WAR oficial |
| DNS y NTP quedaron fuera por faltar la configuración de bind9 | Resuelto: `docker/pc3-administracion-infra/bind/named.conf` y `bind/zones/` |
| Pretix e InvenTree tardan ~10 min en la primera arrancada (migraciones) | Confirmado y documentado; el primer arranque completo de los 3 PCs es de ~13 min |

## Qué nunca probó, ni entonces ni ahora

- **No prueba VLANs, segmentación ni el switch.** Eso solo se puede demostrar con los 3 PCs
  físicos y el hardware real: ver la sección 7 de
  [`../../docs/arquitectura-3-equipos-departamentos.md`](../../docs/arquitectura-3-equipos-departamentos.md).
  El arnés `smoke-test-3-pcs` tampoco lo prueba, porque une todas las apps a una misma red
  bridge y por tanto no ejerce la matriz de segmentación.

## Si necesitas correr algo en un solo equipo

Usa el arnés vigente, no este:

```bash
cd pruebas/smoke-test-3-pcs
docker compose pull && docker compose up -d
```
