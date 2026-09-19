> **Borrador histórico.** Describe el escenario de 2 equipos, ya reemplazado por el diseño vigente de 3 equipos (`../arquitectura-3-equipos-departamentos.md`). Se conserva solo como referencia.

# Arquitectura Final Consolidada — Intranet Zoológico Reserva Viva
Proyecto: Redes Corporativas 678-302 — Universidad Distrital Francisco José de Caldas
Escenario físico definitivo: **Plug-and-play, 2 equipos**

> Este documento reemplaza y consolida los 5 borradores previos (`arquitectura-red-reserva-viva.xml`,
> `docker-compose-preproyecto.yml`, `arquitectura-hibrida-onpremise.md`,
> `arquitectura-distribuida-multihost.md`, `plug-and-play-2-equipos.md`) en una sola
> referencia, quedándose con el diseño lógico original (VLANs, servicios, LDAP) y el
> despliegue físico más simple y viable para el día del laboratorio.

---

## 1. Contexto (resumen de la Entrega N°1)

Zoológico Reserva Viva: institución privada, +150 especies, ~180.000 visitantes/año.
Plan piloto con 4 áreas críticas, cada una con una aplicación Open Source dedicada:

| Área | Categoría | Aplicación | Rol |
|---|---|---|---|
| Unidad Médica Veterinaria | Misional (Core) | **OpenVPMS** | Historias clínicas, vacunas, diagnósticos |
| Taquilla y Boletería | Comercial | **Pretix** | Venta de entradas, control de aforo |
| Logística y Almacén | Soporte | **InvenTree** | Inventario, lotes, vencimientos |
| Recursos Humanos | Administración | **ERPNext (módulo HR)** | Expedientes, turnos 24/7 |

Todas autentican contra un directorio central **OpenLDAP** en lugar de mantener usuarios locales.

---

## 2. Diseño lógico de red (sin cambios respecto al documento original)

### 2.1. Direccionamiento y VLANs

| VLAN | Nombre | Subred | Servicio |
|---|---|---|---|
| 10 | Unidad Médica Veterinaria | 192.168.10.0/24 | OpenVPMS |
| 20 | Taquilla y Boletería | 192.168.20.0/24 | Pretix |
| 30 | Logística y Almacén | 192.168.30.0/24 | InvenTree |
| 40 | Recursos Humanos | 192.168.40.0/24 | ERPNext (HR) |
| 99 | Infraestructura | 192.168.99.0/24 | LDAP, DNS, NTP |

- DHCP dinámico por VLAN, con reservas para servidores.
- LDAPS (636) para autenticación cifrada; DNS interno resuelve
  `veterinaria.reservaviva.local`, `taquilla.reservaviva.local`, etc.

### 2.2. Regla de oro de firewall (diseño original, 4+ equipos)

> Deny-all inter-VLAN por defecto. Excepción: VLANs 10/20/30/40 → VLAN 99 solo por
> 636 (LDAPS), 53 (DNS) y 443. Bloqueo explícito entre 10/20/30/40 entre sí.

**Esta regla aplica tal cual en los escenarios distribuido (5 PCs) e híbrido (1 host con
`macvlan` + `iptables`).** En el escenario final de **2 equipos**, las 4 áreas conviven en
el mismo PC-A, así que **no hay tráfico real inter-VLAN que enrutar/filtrar dentro de
PC-A** (ver §3.4 nota de aislamiento). El switch sigue haciendo su trabajo real:
reparte el trunk de PC-A en 4 VLANs y conmuta el tráfico de PC-B — que es el
requisito mínimo verificable por el docente (switch operando con VLANs 802.1Q,
sin salida a Internet).

---

## 3. Despliegue físico definitivo: Plug-and-play, 2 equipos

| Equipo | Rol | Servicios (Docker) | Puerto del switch | VLANs |
|---|---|---|---|---|
| **PC-A** — Servidor de Aplicaciones | Las 4 áreas de negocio | OpenVPMS, Pretix, InvenTree, ERPNext (+ sus DBs) | **Trunk** | 10, 20, 30, 40 |
| **PC-B** — Servidor de Infraestructura | Directorio central | LDAP, DNS, NTP | **Access** | 99 |

### 3.1. Switch (una sola vez)

```
vlan 10
 name VETERINARIA
vlan 20
 name TAQUILLA
vlan 30
 name LOGISTICA
vlan 40
 name RRHH
vlan 99
 name INFRAESTRUCTURA

interface GigabitEthernet0/1
 switchport mode trunk
 switchport trunk allowed vlan 10,20,30,40
 description LINK-TO-PC-A-APPS

interface GigabitEthernet0/2
 switchport mode access
 switchport access vlan 99
 description LINK-TO-PC-B-INFRA

! Sin puertos de uplink hacia Internet
```

### 3.2. PC-A — script de preparación (una sola vez)

Ver `setup-vlans-pcA.sh` (documento `plug-and-play-2-equipos.md`, §3): crea
sub-interfaces 802.1Q (`eth0.10`…`eth0.40`) y las redes Docker `macvlan`
correspondientes. Es idempotente. Después de correrlo una vez, PC-A queda en modo
`docker compose up -d`.

### 3.3. PC-B — sin script, plug-and-play desde el día 1

Un único puerto access en VLAN 99; solo necesita crear la red `macvlan` una vez.

### 3.4. Nota de aislamiento (limitación reconocida del escenario de 2 equipos)

Como las 4 apps de negocio corren en el mismo PC-A, **no se puede demostrar el
bloqueo inter-VLAN (10↔20↔30↔40) con este montaje**, porque nunca sale tráfico
de un área hacia otra a través del switch. Si el docente pide ver también esa
prueba de aislamiento, la opción más barata es mover **una sola área** (p. ej.
Taquilla) a un tercer equipo — remitirse a `arquitectura-distribuida-multihost.md`
para ese caso puntual, sin migrar todo el proyecto a 5 equipos.

---

## 4. Prueba de humo en un solo host (esta sesión, previa al laboratorio físico)

Antes de ir al laboratorio con el switch real, se validó que el stack de
servicios **arranca sin configuración manual adicional** más allá de las
variables de entorno ya declaradas en el compose, usando redes `bridge`
(no `macvlan`, que requiere una interfaz física parent real) en un solo host.

Ver resultados en **`prueba-smoke-test-resultados.md`** (se genera al terminar
la prueba en esta misma sesión).

Esta prueba cubre: arranque de contenedores, conectividad de cada app hacia LDAP
(VLAN 99 simulada), y ausencia de errores fatales en logs. **No cubre**: la
conmutación 802.1Q real, el aislamiento inter-VLAN físico, ni `macvlan` — eso
solo se valida con el switch y los 2 PCs reales (checklist de §5).

---

## 5. Checklist de pruebas para el día del laboratorio físico

| Prueba | Comando | Qué demuestra |
|---|---|---|
| PC-A ve las 4 VLANs por el trunk | `ip link show \| grep eth0\.` | Sub-interfaces 802.1Q activas |
| Contenedor de cada área responde en su subred | `ping 192.168.X0.10` desde PC-A | `macvlan` entrega IP real dentro de la VLAN |
| App → LDAP (PC-B) | `ldapsearch -x -H ldap://192.168.99.10 -b "dc=reservaviva,dc=local"` desde un contenedor de PC-A | Autenticación centralizada funcional |
| Captura en el puerto trunk | `tcpdump -i eth0.10 -e` en PC-A | Evidencia visual de etiquetas 802.1Q |
| Sin ruta a Internet | `traceroute 8.8.8.8` (debe fallar) en ambos PCs | Laboratorio 100% aislado, según requisito del docente |
| Apagar PC-B | — | Las 4 apps siguen respondiendo localmente, pero fallan los logins nuevos (dependencia real del directorio central) |

Documentar cada resultado con captura de pantalla para el informe final.

---

## 6. Archivos de referencia (no se eliminan, quedan como historial de diseño)

- `arquitectura-red-reserva-viva.xml` — diseño lógico original detallado
- `plug-and-play-2-equipos.md` — detalle completo del escenario elegido (scripts, compose)
- `arquitectura-distribuida-multihost.md` — alternativa si se necesita demostrar aislamiento inter-VLAN real
- `arquitectura-hibrida-onpremise.md` — alternativa de 1 solo host con `macvlan` + `iptables`
- `plan-implementacion-reserva-viva.md` — checklist de recursos y reparto de tareas por integrante
