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
scripts/
  setup-vlans-pc2.sh                        # sub-interfaces 802.1Q en PC-2 (idempotente)
  setup-vlans-pc3.sh                        # sub-interfaces 802.1Q en PC-3 (+ fallback L2 completo, idempotente)
  firewall-pc3-matriz.sh                    # nftables con la matriz de segmentación (fallback switch L2)
  systemd/reserva-viva-pc{1,2,3}.service    # persistencia al reiniciar cada PC
```

## Puesta en marcha rápida

Cada PC trae un `deploy.sh` que hace todo en el orden correcto (VLANs → firewall si aplica → `docker compose up -d`):

```bash
cd docker/pc1-medica && cp .env.example .env && nano .env && sudo ./deploy.sh
```

Detalle completo (incluida la instalación de los servicios systemd para que sobreviva a un reinicio) en la sección 8 de [`docs/arquitectura-3-equipos-departamentos.md`](docs/arquitectura-3-equipos-departamentos.md).

**¿Quien va a instalar esto en el laboratorio no es técnico?** Usa los tutoriales paso a paso en [`tutoriales/`](tutoriales/) — uno por PC, con cada comando explicado y qué hacer si algo sale mal.

## Pendientes clave

- Confirmar con el laboratorio de la universidad si el switch soporta L3 (SVIs/ACLs) o es puramente L2 (define quién aplica la matriz de segmentación: el switch o PC-3 como router-on-a-stick).
- Construir el Dockerfile propio de OpenVPMS (no tiene imagen oficial).
- Cerrar por escrito en el informe el alcance de ERPNext (solo módulo HR) y la diferencia entre Pretix (backend web) y "PretixPOS".

Detalle completo de decisiones, matriz de segmentación y plan de pruebas de fiabilidad en [`docs/arquitectura-3-equipos-departamentos.md`](docs/arquitectura-3-equipos-departamentos.md).
