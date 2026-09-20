# UD.RedesCorporativaa.ProyectoFinak

Arquitectura de red corporativa para el Zoológico Reserva Viva (empresa ficticia del entregable de Redes Corporativas). El laboratorio usa un switch administrable físico + Docker (VLANs vía `macvlan`) para dar solución a las problemáticas de negocio de 4 departamentos, con un directorio centralizado (OpenLDAP) y sin conexión a Internet.

## Estado actual: 3 equipos separados por departamento

El diseño vigente distribuye las aplicaciones en **3 computadores físicos**, uno por grupo de departamentos, conectados al switch con puertos access/trunk según corresponda. Esto reemplaza un diseño previo de 2 equipos y resuelve el problema de que antes ningún tráfico inter-departamental cruzaba realmente el switch.

Ver el documento completo: [`docs/arquitectura-3-equipos-departamentos.md`](docs/arquitectura-3-equipos-departamentos.md).

| PC | Departamento(s) | Aplicación(es) | VLAN(es) |
|---|---|---|---|
| PC-1 | Unidad Médica Veterinaria | OpenVPMS | 10 |
| PC-2 | Taquilla y Boletería + Logística y Almacén | Pretix + InvenTree | 20, 30 |
| PC-3 | Recursos Humanos + Infraestructura | ERPNext (HR) + OpenLDAP + DNS + NTP | 40, 99 |

## Estructura del repositorio

```
docs/
  arquitectura-3-equipos-departamentos.md   # diseño vigente (VLANs, matriz de segmentación, plan de pruebas, puesta en marcha)
docker/
  pc1-medica/            # OpenVPMS (VLAN 10) — docker-compose.yml, deploy.sh, .env.example
  pc2-operaciones/       # Pretix + InvenTree (VLAN 20/30) — docker-compose.yml, deploy.sh, .env.example
  pc3-administracion-infra/  # ERPNext HR + OpenLDAP/DNS/NTP (VLAN 40/99) — docker-compose.yml, deploy.sh, .env.example
diagramas/               # topología y flujo de datos (HTML interactivo, generados con Archify)
pruebas/
  smoke-test-3-pcs/      # arnés vigente: los 3 compose reales en un solo host
  software-un-host/      # HISTÓRICO, no ejecutar (evidencia de la primera ronda)
despliegue/
  README.md              # ¿switch L2 o L3? cómo saberlo y a qué receta ir
  l3-switch/             # receta completa si el switch enruta (SVIs + ACL en el switch)
  l2-fallback/           # receta completa si el switch solo conmuta (PC-3 enruta con nftables)
scripts/
  generar-certificados.sh                   # CA interna + certificado de LDAPS (636); lo ejecuta el deploy.sh de PC-3
  systemd/reserva-viva-pc{1,2,3}.service    # persistencia al reiniciar cada PC
```

## Puesta en marcha rápida

**Antes que nada, averigua si el switch es L2 o L3** y sigue la receta que corresponda: [`despliegue/README.md`](despliegue/README.md). Cada PC trae un `deploy.sh` que hace todo en el orden correcto (VLANs → firewall si aplica → `docker compose up -d`):

```bash
cd docker/pc1-medica && cp .env.example .env && nano .env && sudo ./deploy.sh
```

Detalle completo (incluida la instalación de los servicios systemd para que sobreviva a un reinicio) en la sección 8 de [`docs/arquitectura-3-equipos-departamentos.md`](docs/arquitectura-3-equipos-departamentos.md).

**¿Quien va a instalar esto en el laboratorio no es técnico?** Usa los tutoriales paso a paso en [`tutoriales/`](tutoriales/) — uno por PC, con cada comando explicado y qué hacer si algo sale mal.

## Diagramas

- [`diagramas/topologia-red.html`](diagramas/topologia-red.html): topología física y lógica: los 3 PCs, el switch, las VLAN y qué servicio vive en cada una.
- [`diagramas/flujo-datos-segmentacion.html`](diagramas/flujo-datos-segmentacion.html): flujo de datos entre VLAN y matriz de segmentación (qué pasa y qué se bloquea).

## Prueba de humo en un solo host

`pruebas/smoke-test-3-pcs/` levanta los 3 compose juntos en una sola máquina (redes `bridge` en lugar de `macvlan`) para comprobar que los servicios arrancan sin configuración extra. Resultados en [`docs/prueba-smoke-test-resultados.md`](docs/prueba-smoke-test-resultados.md). No valida el switch, el trunk 802.1Q ni la segmentación.

## Pendientes clave

- Confirmar con el laboratorio de la universidad si el switch soporta L3 (SVIs/ACLs) o es puramente L2. Los dos caminos están preparados (`despliegue/l3-switch/` y `despliegue/l2-fallback/`); falta saber cuál aplica y probarlo con hardware real.
- ~~Construir el Dockerfile propio de OpenVPMS~~ **Hecho** (`docker/pc1-medica/openvpms/Dockerfile`).
- Cerrar por escrito en el informe el alcance de ERPNext (solo módulo HR) y la diferencia entre Pretix (backend web) y "PretixPOS".

Detalle completo de decisiones, matriz de segmentación y plan de pruebas de fiabilidad en [`docs/arquitectura-3-equipos-departamentos.md`](docs/arquitectura-3-equipos-departamentos.md).
