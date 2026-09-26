# Arquitectura vigente — 3 equipos separados por departamento

**Proyecto:** Intranet corporativa Zoológico Reserva Viva
**Curso:** Redes Corporativas, grupo 678-302 — Docente: Andrés Moncada Espitia
**Equipo:** Danna He Sepulveda Sánchez, Harold Sneyder Mendez Ramirez, Jafet Stiven Lopez Zuñiga, Sergio Andrés Bogotá Guzmán
**Estado:** Diseño vigente — reemplaza el modelo de 2 equipos (`plug-and-play-2-equipos.md`, no versionado en este repo) descrito en el handoff.

---

## 1. Qué cambió respecto al diseño de 2 equipos

El equipo definió que ahora se dispone de **3 computadores físicos** en lugar de 2, con el objetivo explícito de **separar las aplicaciones por departamento** en máquinas distintas.

Esto resuelve automáticamente el **gap #1** que quedó abierto en el handoff anterior: *"con el diseño de 2 PCs, las 4 áreas de negocio nunca se comunican entre sí a través del switch, porque todas viven en el mismo host, así que no hay forma de demostrar el bloqueo inter-VLAN."*

Con 3 equipos, ya no todas las áreas comparten el mismo host: hay tráfico real de VLAN a VLAN que **sí atraviesa el switch físico** entre máquinas separadas, y la política de firewall/ACL que bloquea o permite ese tráfico es demostrable con evidencia real (ping, `iperf3`, `mtr`, captura de Wireshark en el trunk).

## 2. Distribución de departamentos en los 3 equipos

Con 4 áreas de negocio + 1 capa de infraestructura transversal (LDAP/DNS/NTP) y solo 3 equipos, es inevitable agrupar 2 áreas en un mismo PC. El criterio usado para agrupar fue:

- **Aislar la Unidad Médica Veterinaria en su propio equipo**, porque maneja historias clínicas (dato sensible, equivalente al criterio de "core misional" que ya tenía el diseño original) y es el caso más fuerte para sustentar una política de aislamiento total frente al resto de la red.
- **Agrupar Taquilla + Logística** en el segundo equipo, porque operativamente están relacionadas (control de aforo y stock/insumos de la operación diaria) y ambas son de menor sensibilidad que datos clínicos o de personal.
- **Agrupar Recursos Humanos con la Infraestructura (LDAP/DNS/NTP)** en el tercer equipo, porque RRHH es back-office/administrativo igual que la infraestructura, y porque LDAP necesita estar accesible en su propia VLAN de gestión de todas formas.

| PC | Nombre | Departamento(s) | Aplicación(es) | VLAN(es) | Tipo de puerto en el switch |
|---|---|---|---|---|---|
| **PC-1** | Servidor Médico | Unidad Médica Veterinaria | OpenVPMS | VLAN 10 | **Access** (una sola VLAN, sin necesidad de trunk) |
| **PC-2** | Servidor de Operaciones | Taquilla y Boletería + Logística y Almacén | Pretix + InvenTree | VLAN 20, VLAN 30 | **Trunk** (802.1Q, VLANs 20 y 30 permitidas) |
| **PC-3** | Servidor de Administración e Infraestructura | Recursos Humanos + Infraestructura (todas las áreas) | ERPNext (módulo HR) + OpenLDAP + DNS + NTP | VLAN 40, VLAN 99 | **Trunk** (802.1Q, VLANs 40 y 99 permitidas) |

Ver el diagrama interactivo en [`diagramas/topologia-red.html`](diagramas/topologia-red.html).

> Si el equipo prefiere otra agrupación (p. ej. RRHH con Taquilla, o Médica con Logística), la tabla es el único punto que cambia — el resto del documento (switch, docker-compose, plan de pruebas) se ajusta reasignando VLANs/puertos.

## 3. Direccionamiento

| VLAN | Área | Subred | Gateway / SVI (si el switch es L3) | Host(s) del PC |
|---|---|---|---|---|
| 10 | Unidad Médica Veterinaria | 10.10.10.0/24 | 10.10.10.1 | PC-1 → 10.10.10.10 |
| 20 | Taquilla y Boletería | 10.10.20.0/24 | 10.10.20.1 | PC-2 (`eth0.20`) → 10.10.20.10 |
| 30 | Logística y Almacén | 10.10.30.0/24 | 10.10.30.1 | PC-2 (`eth0.30`) → 10.10.30.10 |
| 40 | Recursos Humanos | 10.10.40.0/24 | 10.10.40.1 | PC-3 (`eth0.40`) → 10.10.40.10 |
| 99 | Infraestructura (LDAP/DNS/NTP) | 10.10.99.0/24 | 10.10.99.1 | PC-3 (`eth0.99`) → 10.10.99.10 |

Todos los rangos son privados y **sin salida a Internet**, cumpliendo el requisito explícito del profesor de laboratorio on-premise.

## 4. Matriz de política de segmentación (a demostrar en la sustentación)

| Origen \ Destino | VLAN10 (Médica) | VLAN20 (Taquilla) | VLAN30 (Logística) | VLAN40 (RRHH) | VLAN99 (Infra) |
|---|---|---|---|---|---|
| **VLAN10 (Médica)** | — | ❌ Bloqueado | ❌ Bloqueado | ❌ Bloqueado | ✅ Permitido (auth/DNS/NTP) |
| **VLAN20 (Taquilla)** | ❌ Bloqueado | — | ❌ Bloqueado | ❌ Bloqueado | ✅ Permitido |
| **VLAN30 (Logística)** | ❌ Bloqueado | ❌ Bloqueado | — | ❌ Bloqueado | ✅ Permitido |
| **VLAN40 (RRHH)** | ❌ Bloqueado | ❌ Bloqueado | ❌ Bloqueado | — | ✅ Permitido |
| **VLAN99 (Infra)** | ✅ (responde) | ✅ (responde) | ✅ (responde) | ✅ (responde) | — |

Ver el diagrama interactivo en [`diagramas/flujo-datos-segmentacion.html`](diagramas/flujo-datos-segmentacion.html).

Esta matriz da **dos tipos de evidencia distintos**, que antes con 2 PCs no existían:

1. **Bloqueo inter-PC real:** VLAN10 (PC-1) vs. VLAN20/30 (PC-2) vs. VLAN40 (PC-3) — el tráfico sale físicamente por el cable de un equipo, entra al switch, y el switch/firewall decide si lo entrega al otro equipo.
2. **Bloqueo intra-PC vía switch (hairpin):** VLAN20 vs. VLAN30 viven en el mismo PC-2 pero en interfaces macvlan distintas — el tráfico igual sale por el trunk físico hacia el switch y regresa (hairpin) antes de llegar al otro contenedor, así que el switch sigue siendo el punto de aplicación de la política, no el host.

## 5. Routing/ACL: host vs. switch

Quién enruta entre VLANs y quién aplica la matriz de la sección 4 depende de si el switch del laboratorio es **L3** (tiene una SVI por VLAN) o **L2** (solo conmuta). **Falta confirmar con el laboratorio de la universidad cuál es.** Como ningún PC toca las 5 VLANs a la vez, en un switch L2 no basta con que cada PC enrute lo suyo: nadie podría enrutar, por ejemplo, VLAN10 (PC-1) hacia VLAN99 (PC-3).

Los dos caminos están preparados, cada uno como una carpeta autónoma con su receta paso a paso. El día de la instalación se mira el switch y se sigue una sola:

| Perfil | Cuándo | Quién enruta y aplica la matriz | Receta |
|---|---|---|---|
| **L3** | El switch tiene SVIs (`Vlan10`, `Vlan20`… con IP) | El switch: una SVI `10.10.X.1` por VLAN y las ACL de la matriz. Los PCs solo crean sus sub-interfaces/macvlan, sin `ip_forward` ni `nftables`. La evidencia de la demo queda en el propio switch. | [`l3-switch/`](l3-switch/README.md) |
| **L2** | El switch solo conmuta VLANs | **PC-3** como router-on-a-stick (ver abajo) | [`l2-fallback/`](l2-fallback/README.md) |

Para saber cuál es, [`README.md`](README.md) da el procedimiento de comprobación en la consola del switch.

**Qué cambia en el perfil L2:**

- El puerto trunk de PC-3 pasa de permitir VLAN 40/99 a permitir **las 5 VLANs (10, 20, 30, 40, 99)**.
- El trunk de PC-2 sigue permitiendo solo VLAN 20/30 y el puerto de PC-1 sigue siendo access VLAN 10; el switch puede repetir las mismas etiquetas VLAN en varios puertos, eso es normal en 802.1Q.
- PC-3 crea sub-interfaces adicionales `eth0.10`, `eth0.20`, `eth0.30` (solo para enrutar, sin contenedores enganchados), habilita `ip_forward` y aplica con `nftables` exactamente la matriz de la sección 4.
- El gateway de cada VLAN (`10.10.X.1`) pasa a ser la IP de PC-3 en la sub-interfaz correspondiente, en vez de una SVI del switch.
- PC-1 y PC-2 no enrutan: usan a PC-3 como gateway.

**Estado de la validación:** ninguno de los dos perfiles se ha probado todavía contra un switch real (macvlan, 802.1Q y la matriz siguen pendientes de hardware). Lo que sí está probado es la capa de software en un solo host (ver `docs/prueba-smoke-test-resultados.md` (retirado; se lee con `git show 95e0da4:docs/prueba-smoke-test-resultados.md`)).

## 6. Aplicaciones y contenedores por PC

Ver `docker/pc1-medica/docker-compose.yml`, `docker/pc2-operaciones/docker-compose.yml` y `docker/pc3-administracion-infra/docker-compose.yml`.

Notas heredadas del handoff que siguen aplicando sin cambios por el split en 3 equipos:

- **OpenVPMS no tiene imagen Docker oficial** → se debe construir un Dockerfile propio (Tomcat + WAR + MySQL). Como ahora vive solo en PC-1, es el único contenedor de ese equipo — mayor riesgo pero menor superficie de configuración en esa máquina.
- **ERPNext trae todos los módulos activos**, aunque el informe solo pide el módulo HR → restringir acceso por roles dentro de ERPNext, o aclararlo explícitamente en el informe.
- **ERPNext no es un solo contenedor** (hallazgo de la prueba de humo, ya resuelto en PC-3): la imagen `frappe/erpnext` sola responde HTTP 404 porque no hay *site* ni MariaDB. El servicio en PC-3 se rediseña con el stack de `frappe_docker` (MariaDB, `redis-cache`, `redis-queue`, `configurator`, `create-site`, `backend`, `frontend`, `scheduler`, `websocket`). Ver `docs/prueba-smoke-test-resultados.md` (retirado; se lee con `git show 95e0da4:docs/prueba-smoke-test-resultados.md`) §4.
- **Primer arranque lento:** Pretix e InvenTree aplican cientos de migraciones y tardan unos 10 minutos en responder la primera vez; ERPNext suma varios minutos al crear el *site*. Es normal y no requiere intervención; los arranques posteriores son inmediatos. Hay que dar el margen antes de la demostración.
- **Pretix (backend web) vs. "PretixPOS"** (app de punto de venta) → aclarar en el informe cuál se usa como reemplazo funcional, o sumar el componente POS si el profesor lo exige.

## 7. Plan de pruebas de fiabilidad (adaptado a 3 equipos)

1. **Sin Internet:** desde cada PC, verificar ausencia de ruta por defecto a Internet (`ip route`, intento de `ping 8.8.8.8` debe fallar).
2. **LDAP/DNS/NTP alcanzable desde las 3 VLANs de negocio:** desde PC-1 (VLAN10), PC-2 (VLAN20 y VLAN30) y el propio PC-3 (VLAN40), probar autenticación contra OpenLDAP, resolución DNS y sincronización NTP — todas deben funcionar (fila/columna VLAN99 de la matriz).
3. **Bloqueo inter-PC:** desde PC-1 (VLAN10) intentar `ping`/`curl` contra Pretix (VLAN20, PC-2) e InvenTree (VLAN30, PC-2) — debe fallar. Repetir en ambos sentidos y contra PC-3 (VLAN40).
4. **Bloqueo intra-PC vía switch:** desde el contenedor de Pretix (VLAN20) intentar llegar a InvenTree (VLAN30), ambos en PC-2 — debe fallar aunque estén en el mismo hardware, confirmando que el filtrado ocurre en el switch/host-router y no por simple ausencia de ruta local.
5. **Captura de tráfico:** Wireshark en el puerto trunk de PC-2 o PC-3 durante las pruebas 3 y 4, mostrando las tramas 802.1Q etiquetadas y, si el switch es L3, los intentos denegados.
6. **Rendimiento/latencia:** `iperf3`/`mtr` entre PC-1↔PC-3 (o el par que se use para demostrar el flujo permitido hacia LDAP) para sustentar "comunicación fiable" entre switch y red interna.

## 8. Puesta en marcha (plug-and-play real)

Los `docker-compose.yml` por sí solos **no** son plug-and-play: hace falta que las sub-interfaces VLAN existan antes de que Docker cree las redes `macvlan`, que las contraseñas estén definidas, y que todo eso sobreviva a un reinicio del PC en pleno laboratorio. Para eso cada carpeta de `docker/pcN-*/` trae:

- `.env.example` → copiar a `.env` y definir ahí las contraseñas, el nombre de la tarjeta de red (`IFACE`) y `PERFIL` (`l3` o `l2`, según el switch; ver sección 5) (el `.env` real nunca se commitea, ver `.gitignore`). Es el **único** archivo que hay que editar — nada de tocar YAML ni scripts.
- `scripts/generar-certificados.sh` → crea la CA interna y el certificado de LDAPS (636) de OpenLDAP y los deja en `docker/pc3-administracion-infra/certs/`, donde el compose los monta. El `deploy.sh` de PC-3 lo ejecuta solo (idempotente); la `ca.crt` resultante se copia a PC-1 y PC-2 para que sus clientes confíen en ella.
- `deploy.sh` → un solo comando que lee ese `.env` y hace, en el orden correcto: validar `PERFIL` → crear las sub-interfaces VLAN con los scripts de `diseno-red/<perfil>/scripts/` → aplicar el firewall (solo PC-3 con `PERFIL=l2`) → `docker compose up -d`. Es **idempotente**: correrlo dos veces no rompe nada.

Los tutoriales paso a paso por PC (`tutoriales/`) se retiraron el 26/09/2026 junto con el despliegue en 3 PCs; se recuperan con `git checkout cceb54c -- tutoriales`.

### Primera vez, en cada PC

```bash
# PC-1
cd docker/pc1-medica && cp .env.example .env && nano .env
sudo ./deploy.sh

# PC-2
cd docker/pc2-operaciones && cp .env.example .env && nano .env
sudo ./deploy.sh

# PC-3 (PERFIL=l3 o PERFIL=l2 en .env, según el switch)
cd docker/pc3-administracion-infra && cp .env.example .env && nano .env
sudo ./deploy.sh
```

### Que sobreviva a un reinicio (recomendado para el día de la sustentación)

Las sub-interfaces 802.1Q creadas con `ip link add` son efímeras: si el PC se reinicia a mitad de la demo, desaparecen y hay que recrearlas a mano. Para que cada PC quede realmente "enchufar y listo" incluso después de apagar/prender, se instala el servicio systemd correspondiente (`scripts/systemd/reserva-viva-pcN.service`), que en cada arranque repite el mismo `deploy.sh`:

```bash
sudo mkdir -p /opt/reserva-viva
sudo cp -r . /opt/reserva-viva            # o clonar el repo directamente ahí
sudo cp scripts/systemd/reserva-viva-pc1.service /etc/systemd/system/   # el que corresponda a ese PC
sudo systemctl daemon-reload
sudo systemctl enable --now reserva-viva-pc1.service   # el que corresponda
```

`PERFIL` se lee del `.env` de cada carpeta — no hay que tocar el `.service`.

Con esto, apagar y prender cualquiera de los 3 equipos ya no requiere que alguien recuerde los pasos manuales — es la definición real de "plug-and-play" para este laboratorio.

## 9. Próximos pasos actualizados

1. Confirmar con el laboratorio si el switch es L2 o L3 y seguir la receta del perfil que toque (sección 5): [`diseno-red/l3-switch/`](l3-switch/README.md) o [`diseno-red/l2-fallback/`](l2-fallback/README.md). Ambos están preparados; solo falta saber cuál aplica.
2. ~~Validar en software puro (un solo host)~~ **Hecho** con `pruebas/smoke-test-3-pcs/` (resultados en `docs/prueba-smoke-test-resultados.md` (retirado; se lee con `git show 95e0da4:docs/prueba-smoke-test-resultados.md`)). Hallazgos que se están cerrando: compose de PC-2 corregido (Pretix e InvenTree responden 200), stack completo de ERPNext y configuración de bind9 en PC-3, superusuarios de Pretix/InvenTree automatizados en `deploy.sh`. **No cubre** macvlan, 802.1Q ni segmentación: eso solo se valida con el switch real.
3. Construir el Dockerfile custom de OpenVPMS para PC-1 (dejarlo con tiempo suficiente, es el mayor riesgo técnico). Ya construido y probado en un host (login HTTP 200, arranque idempotente); ver `docs/prueba-smoke-test-resultados.md` (retirado; se lee con `git show 95e0da4:docs/prueba-smoke-test-resultados.md`) §3.
4. Cablear los 3 equipos al switch (PC-1 access VLAN10; PC-2 y PC-3 trunk), configurar el switch según el perfil (`diseno-red/l3-switch/` o `diseno-red/l2-fallback/`) y correr el `deploy.sh` de cada equipo.
5. Comprobar que cada PC quedó arriba (el `deploy.sh` ya ejecuta `docker compose up -d` con su compose).
6. Ejecutar el plan de pruebas de la sección 7 y documentar evidencia (capturas, logs) para la sustentación.
7. Cerrar por escrito los gaps de alcance de ERPNext y Pretix vs. PretixPOS en el informe.
