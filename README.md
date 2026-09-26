# UD.RedesCorporativaa.ProyectoFinak

Arquitectura de red corporativa para el Zoológico Reserva Viva (empresa ficticia del entregable de Redes Corporativas). El diseño propone un switch administrable con VLANs 802.1Q + Docker (VLANs vía `macvlan`) para dar solución a las problemáticas de negocio de 4 departamentos, con un directorio centralizado (OpenLDAP) y sin conexión a Internet. **Los PCs del laboratorio son Windows con Docker Desktop**, que no permite `macvlan` ni 802.1Q sobre la tarjeta de red: por eso la segmentación por VLAN se valida por simulación y no sobre hardware (ver [Estado de validación](#estado-de-validación)).

## Arranque rápido: todo el sistema en un solo equipo

Clonar y ejecutar un solo script levanta la arquitectura completa (los 3 PCs, 25 servicios) en una sola máquina:

| Sistema | Cómo |
|---|---|
| Windows | Doble clic en **`levantar-sistema.cmd`**, o `.\levantar-sistema.ps1` en PowerShell |
| Linux / WSL / macOS | `./levantar-sistema.sh` |

Genera lo que no va en git (CA interna y certificado LDAPS, zona DNS), construye la imagen de OpenVPMS, levanta los 25 servicios, **espera a que todos estén sanos** y muestra las direcciones de acceso (`http://localhost:18080/openvpms`, `:18081` ERPNext, `:18082` Pretix, `:18083` InvenTree). Se puede volver a ejecutar sin riesgo: si un arranque se corta, retoma donde quedó. Otras acciones: `estado`, `verificar` (segmentación, DNS, NTP y LDAP), `detener` (sin borrar datos) y `borrar` (borra también los datos; pide confirmación).

**Requisitos:** Docker Desktop (con Git for Windows en Windows) o Docker Engine en Linux/WSL, con Compose 2.24.4 o superior. Al menos **~7 GB de RAM libre**: los 25 servicios consumen unos 5,7 GB en el equipo. El primer arranque descarga varios GB de imágenes (solo la de ERPNext/hrms ocupa 3,2 GB). A eso se suma la inicialización: medido por separado, unos 13 min la cadena de OpenVPMS y unos 15 min el sitio de ERPNext, que corren en paralelo. Los siguientes arranques tardan unos minutos. Medido el 26/09/2026 en un equipo de 14 GB: **25/25 sanos en 15 min 45 s** (con las imágenes ya descargadas e inicializando OpenVPMS desde cero). Las contraseñas de laboratorio (desechables) están en `pruebas/smoke-test-3-pcs/test.env`.

En Windows con Docker Engine dentro de WSL (sin Docker Desktop), el lanzador deja una sesión de WSL abierta en segundo plano. Sin ella, al cerrarse la última terminal Docker se detiene y se lleva los contenedores. `detener` la cierra.

Un equipo demuestra que la arquitectura funciona, pero no demuestra el switch físico ni el etiquetado 802.1Q (ver [Estado de validación](#estado-de-validación)).

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
  pc1-medica/            # OpenVPMS (VLAN 10): docker-compose.yml + imagen propia (openvpms/)
  pc2-operaciones/       # Pretix + InvenTree (VLAN 20/30): docker-compose.yml
  pc3-administracion-infra/  # ERPNext HR + OpenLDAP/DNS/NTP (VLAN 40/99): docker-compose.yml, ldap/, bind/
diagramas/               # topología y flujo de datos (HTML interactivo, generados con Archify)
pruebas/
  smoke-test-3-pcs/      # arnés vigente: los 3 compose reales en un solo host (lo usa levantar-sistema.sh)
despliegue/
  README.md              # ANEXO DE DISEÑO: ¿switch L2 o L3? cómo saberlo y a qué receta ir (no aplica al laboratorio Windows)
  l3-switch/             # receta completa si el switch enruta (SVIs + ACL en el switch); trae scripts/, switch/, pruebas/ y diagramas/
  l2-fallback/           # receta completa si el switch solo conmuta (PC-3 enruta con nftables); misma estructura
  comun/                 # biblioteca de los simuladores de la matriz y de los scripts de VLAN (ip-gestion.sh)
scripts/
  generar-certificados.sh                   # CA interna + certificado de LDAPS (636); lo ejecuta levantar-sistema.sh
levantar-sistema.sh / .ps1 / .cmd           # arranque plug and play de todo el sistema en un host
```

## Puesta en marcha

El sistema se despliega en **un solo equipo** con `levantar-sistema` (ver [Arranque rápido](#arranque-rápido-todo-el-sistema-en-un-solo-equipo)). El despliegue en 3 PCs (scripts `deploy.sh`/`deploy.ps1`, `.env.example` por PC, servicios systemd, tutoriales y guías de Windows) se retiró del repositorio el 26/09/2026 para reducir la curva de aprendizaje. Se puede recuperar del historial de git (ver el commit que lo retiró).

**Diseño con switch (anexo):** la receta con VLANs 802.1Q y switch L2/L3 se conserva como diseño de red en [`despliegue/README.md`](despliegue/README.md), con sus simuladores de segmentación. No se despliega.

## Diagramas

- [`diagramas/topologia-red.html`](diagramas/topologia-red.html): topología física y lógica: los 3 PCs, el switch, las VLAN y qué servicio vive en cada una.
- [`diagramas/flujo-datos-segmentacion.html`](diagramas/flujo-datos-segmentacion.html): flujo de datos entre VLAN y matriz de segmentación (qué pasa y qué se bloquea).

## Prueba de humo en un solo host

`pruebas/smoke-test-3-pcs/` levanta los 3 compose juntos en una sola máquina (redes `bridge` en lugar de `macvlan`) para comprobar que los servicios arrancan sin configuración extra. Es hoy la referencia de lo que se ha **ejecutado** (nivel 1 de la tabla de validación). Resultados en [`docs/prueba-smoke-test-resultados.md`](docs/prueba-smoke-test-resultados.md). No valida el switch, el trunk 802.1Q ni la segmentación: de eso se encargan los simuladores.

## Pendientes clave

- Paquete de preparación previa (Fase 0) para un laboratorio con Internet limitada: imágenes de las aplicaciones por etiqueta, la de OpenVPMS ya construida, certificados ya generados y `nicolaka/netshoot` si se van a demostrar los simuladores. En verificación.
- Diseño con switch (L2/L3): sin validar contra hardware real. Queda documentado como limitación conocida.
- ~~Construir el Dockerfile propio de OpenVPMS~~ **Hecho** (`docker/pc1-medica/openvpms/Dockerfile`).
- Cerrar por escrito en el informe el alcance de ERPNext (solo módulo HR) y la diferencia entre Pretix (backend web) y "PretixPOS".

Detalle completo de decisiones, matriz de segmentación y plan de pruebas de fiabilidad en [`docs/arquitectura-3-equipos-departamentos.md`](docs/arquitectura-3-equipos-departamentos.md).
