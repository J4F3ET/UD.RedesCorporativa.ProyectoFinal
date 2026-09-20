# UD.RedesCorporativaa.ProyectoFinak

Arquitectura de red corporativa para el Zoológico Reserva Viva (empresa ficticia del entregable de Redes Corporativas). El diseño propone un switch administrable con VLANs 802.1Q + Docker (VLANs vía `macvlan`) para dar solución a las problemáticas de negocio de 4 departamentos, con un directorio centralizado (OpenLDAP) y sin conexión a Internet. **Los PCs del laboratorio son Windows con Docker Desktop**, que no permite `macvlan` ni 802.1Q sobre la tarjeta de red: por eso la segmentación por VLAN se valida por simulación y no sobre hardware (ver [Estado de validación](#estado-de-validación)).

## Estado actual: 3 equipos separados por departamento

El diseño propuesto distribuye las aplicaciones en **3 computadores físicos**, uno por grupo de departamentos (en el laboratorio, tres PCs Windows con Docker Desktop). En el diseño de red completo se conectarían a un switch con puertos access/trunk según corresponda. Esto reemplaza un diseño previo de 2 equipos.

Ver el documento completo: [`docs/arquitectura-3-equipos-departamentos.md`](docs/arquitectura-3-equipos-departamentos.md).

| PC | Departamento(s) | Aplicación(es) | VLAN(es) |
|---|---|---|---|
| PC-1 | Unidad Médica Veterinaria | OpenVPMS | 10 |
| PC-2 | Taquilla y Boletería + Logística y Almacén | Pretix + InvenTree | 20, 30 |
| PC-3 | Recursos Humanos + Infraestructura | ERPNext (HR) + OpenLDAP + DNS + NTP | 40, 99 |

## Estado de validación

No todo lo que describe este repositorio se ha demostrado de la misma manera. Hay tres niveles de evidencia:

| Nivel | Qué es | Dónde se demuestra |
|---|---|---|
| **Implementado y ejecutado** | Las 4 aplicaciones (OpenVPMS, Pretix, InvenTree, ERPNext), OpenLDAP con LDAPS (636) y CA interna, DNS (bind9), NTP, el direccionamiento `10.10.X.0/24` con sus IP y los healthchecks, sobre Docker Desktop con redes `bridge`. | `pruebas/smoke-test-3-pcs/`, [`docs/prueba-smoke-test-resultados.md`](docs/prueba-smoke-test-resultados.md), [`docs/integracion-ldap-erpnext-inventree.md`](docs/integracion-ldap-erpnext-inventree.md) |
| **Simulado en el kernel de Linux (Docker Desktop)** | La segmentación 802.1Q y la matriz de política: las 20 celdas, con un contador por regla. En el perfil L2 se ejecutan los scripts reales `setup-vlans-pc3.sh` y `firewall-pc3-matriz.sh`. Se puede repetir en vivo en la misma máquina Windows. | `despliegue/l3-switch/pruebas/` y `despliegue/l2-fallback/pruebas/` |
| **Diseñado, no validado en hardware** | Configuración del switch (Cisco IOS), trunk 802.1Q entre los PCs, `macvlan` real sobre la tarjeta física, copia de `ca.crt` con `scp` entre PCs, servicios systemd. | `despliegue/*/switch/`, `despliegue/*/README.md`, [`diagramas/`](diagramas/) |

**Por qué:** los PCs del laboratorio son Windows con Docker Desktop, que corre los contenedores en una máquina virtual Linux y no expone la tarjeta de red física a `macvlan` ni a sub-interfaces 802.1Q. El diseño con VLANs se conserva como diseño de red propuesto (con sus scripts, configuraciones de switch y diagramas como anexo) y su lógica se comprueba con los simuladores; lo que no se ha podido comprobar es el comportamiento sobre un switch físico.

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
  README.md              # ANEXO DE DISEÑO: ¿switch L2 o L3? cómo saberlo y a qué receta ir (no aplica al laboratorio Windows)
  l3-switch/             # receta completa si el switch enruta (SVIs + ACL en el switch); trae scripts/, switch/, pruebas/ y diagramas/
  l2-fallback/           # receta completa si el switch solo conmuta (PC-3 enruta con nftables); misma estructura
  comun/                 # biblioteca de los simuladores de la matriz (ejecutables en Docker Desktop)
scripts/
  generar-certificados.sh                   # CA interna + certificado de LDAPS (636); lo ejecuta el deploy.sh de PC-3
  perfil.sh, ip-gestion.sh                  # bibliotecas que hacen "source" los deploy.sh (validan PERFIL; IP de gestión opcional)
  systemd/reserva-viva-pc{1,2,3}.service    # persistencia al reiniciar cada PC
```

## Puesta en marcha

**Laboratorio (tres PCs Windows con Docker Desktop):** la guía paso a paso está **en preparación** y sustituirá a los `deploy.sh` y a los tutoriales de `tutoriales/`, que asumen Linux, `sudo`, un switch con VLANs y Ubuntu Server. Hasta que se publique, no sigas esos documentos en el laboratorio. Lo que sí se puede ejecutar hoy en Windows es la prueba de humo (siguiente sección) y los simuladores de segmentación (`despliegue/*/pruebas/`).

**Diseño con switch (anexo, Linux):** si algún día se dispusiera de un switch con VLANs y PCs Linux, la receta está en [`despliegue/README.md`](despliegue/README.md) (averigua antes si el switch es L2 o L3) y cada PC trae un `deploy.sh` que hace todo en el orden correcto (VLANs → firewall si aplica → `docker compose up -d`):

```bash
cd docker/pc1-medica && cp .env.example .env && nano .env && sudo ./deploy.sh
```

Detalle de ese camino (incluidos los servicios systemd) en la sección 8 de [`docs/arquitectura-3-equipos-departamentos.md`](docs/arquitectura-3-equipos-departamentos.md). Los tutoriales de [`tutoriales/`](tutoriales/) pertenecen a este mismo camino.

## Diagramas

- [`diagramas/topologia-red.html`](diagramas/topologia-red.html): topología física y lógica: los 3 PCs, el switch, las VLAN y qué servicio vive en cada una.
- [`diagramas/flujo-datos-segmentacion.html`](diagramas/flujo-datos-segmentacion.html): flujo de datos entre VLAN y matriz de segmentación (qué pasa y qué se bloquea).

## Prueba de humo en un solo host

`pruebas/smoke-test-3-pcs/` levanta los 3 compose juntos en una sola máquina (redes `bridge` en lugar de `macvlan`) para comprobar que los servicios arrancan sin configuración extra. Es hoy la referencia de lo que se ha **ejecutado** (nivel 1 de la tabla de validación). Resultados en [`docs/prueba-smoke-test-resultados.md`](docs/prueba-smoke-test-resultados.md). No valida el switch, el trunk 802.1Q ni la segmentación: de eso se encargan los simuladores.

## Pendientes clave

- Guía de puesta en marcha para Windows con Docker Desktop (sustituye a los `deploy.sh` y a los tutoriales), con puertos publicados y la IP de PC-3 parametrizada para que los tres PCs se vean entre sí. En preparación.
- Paquete de preparación previa (Fase 0) para un laboratorio sin Internet: instalador de Docker Desktop, imágenes de las aplicaciones y la de OpenVPMS ya construida; incluir `nicolaka/netshoot` si se van a demostrar los simuladores.
- Diseño con switch (L2/L3): sin validar contra hardware real. Queda documentado como limitación conocida.
- ~~Construir el Dockerfile propio de OpenVPMS~~ **Hecho** (`docker/pc1-medica/openvpms/Dockerfile`).
- Cerrar por escrito en el informe el alcance de ERPNext (solo módulo HR) y la diferencia entre Pretix (backend web) y "PretixPOS".

Detalle completo de decisiones, matriz de segmentación y plan de pruebas de fiabilidad en [`docs/arquitectura-3-equipos-departamentos.md`](docs/arquitectura-3-equipos-departamentos.md).
