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
  arquitectura-3-equipos-departamentos.md   # diseño vigente (VLANs, matriz de segmentación, plan de pruebas)
docker/
  pc1-medica/docker-compose.yml             # OpenVPMS (VLAN 10)
  pc2-operaciones/docker-compose.yml        # Pretix + InvenTree (VLAN 20/30)
  pc3-administracion-infra/docker-compose.yml  # ERPNext HR + OpenLDAP/DNS/NTP (VLAN 40/99)
scripts/
  setup-vlans-pc2.sh                        # sub-interfaces 802.1Q en PC-2
  setup-vlans-pc3.sh                        # sub-interfaces 802.1Q en PC-3 (+ fallback L2 completo)
  firewall-pc3-matriz.sh                    # nftables con la matriz de segmentación (fallback switch L2)
```

## Pendientes clave

- Confirmar con el laboratorio de la universidad si el switch soporta L3 (SVIs/ACLs) o es puramente L2 (define quién aplica la matriz de segmentación: el switch o PC-3 como router-on-a-stick).
- Construir el Dockerfile propio de OpenVPMS (no tiene imagen oficial).
- Cerrar por escrito en el informe el alcance de ERPNext (solo módulo HR) y la diferencia entre Pretix (backend web) y "PretixPOS".

Detalle completo de decisiones, matriz de segmentación y plan de pruebas de fiabilidad en [`docs/arquitectura-3-equipos-departamentos.md`](docs/arquitectura-3-equipos-departamentos.md).
