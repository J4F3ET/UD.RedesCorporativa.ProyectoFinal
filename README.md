# Reserva Viva: intranet segmentada del Zoológico

Proyecto final de Redes Corporativas (UD, grupo 678-302). Es la intranet del Zoológico "Reserva Viva", una empresa ficticia. Cuatro departamentos tienen cada uno su aplicación y su VLAN, y comparten un directorio central (OpenLDAP con LDAPS), DNS y NTP propios, sin depender de Internet.

| Departamento | Aplicación | VLAN | Subred |
|---|---|---|---|
| Unidad Médica Veterinaria | OpenVPMS | 10 | 10.10.10.0/24 |
| Taquilla y Boletería | Pretix | 20 | 10.10.20.0/24 |
| Logística y Almacén | InvenTree | 30 | 10.10.30.0/24 |
| Recursos Humanos | ERPNext (módulo HR) | 40 | 10.10.40.0/24 |
| Infraestructura (transversal) | OpenLDAP + CA interna, bind9, NTP | 99 | 10.10.99.0/24 |

Todo el sistema (25 servicios) corre **en un solo equipo**. Cada VLAN es una red bridge de Docker con su misma subred. Cada aplicación está en la VLAN de su departamento y además en la VLAN 99, para llegar a la infraestructura.

## Arranque rápido

| Sistema | Cómo |
|---|---|
| Windows | Doble clic en **`levantar-sistema.cmd`**, o `.\levantar-sistema.ps1` en PowerShell |
| Linux / WSL / macOS | `./levantar-sistema.sh` |

El script hace todo lo necesario y se puede volver a ejecutar sin riesgo: si un arranque se corta, retoma donde quedó.

1. Genera lo que no va en git: la CA interna, el certificado LDAPS y la zona DNS.
2. Construye la imagen de OpenVPMS.
3. Levanta los 25 servicios y **espera a que todos estén sanos**.
4. Crea el administrador de Pretix.
5. Muestra las direcciones de acceso.

| Aplicación | Dirección |
|---|---|
| OpenVPMS | http://localhost:18080/openvpms |
| ERPNext | http://localhost:18081 |
| Pretix | http://localhost:18082 |
| InvenTree | http://localhost:18083 |

Los usuarios aparecen al terminar el arranque. Las contraseñas de laboratorio, que son desechables, están en [`sistema/test.env`](sistema/test.env).

| Acción | Qué hace |
|---|---|
| `arrancar` (por defecto) | Prepara todo, levanta el sistema y espera a que esté sano |
| `verificar` | Comprueba la arquitectura contra el sistema en marcha (ver abajo); tarda unos 15 min. Con `--rapido` omite la prueba de persistencia |
| `estado` | Estado de cada servicio y direcciones de acceso |
| `detener` | Para los contenedores sin borrar datos |
| `borrar` | Borra contenedores **y datos**. Pide confirmación |

**Requisitos:** Docker Desktop (en Windows, con Git for Windows) o Docker Engine en Linux/WSL, con Compose 2.24.4 o superior, y unos **7 GB de RAM libre**. El primer arranque descarga varios GB de imágenes (la de ERPNext/hrms ocupa 3,2 GB). Los requisitos completos, el `.wslconfig` recomendado, qué hacer tras reiniciar el PC y las trampas de Windows/WSL están en [`docs/operacion.md`](docs/operacion.md). Las cifras medidas de memoria y de arranque, en [`docs/resultados-un-host.md`](docs/resultados-un-host.md).

## Qué demuestra `verificar`

[`sistema/verificar_arquitectura.py`](sistema/verificar_arquitectura.py) se ejecuta contra el sistema levantado. Lo que comprueba y cómo leer el resultado está en [`sistema/verificar_arquitectura.md`](sistema/verificar_arquitectura.md).

- **Segmentación:** cada departamento alcanza su propio servicio y no alcanza a los demás. Cada negativo se valida con controles positivos para que un timeout no pase por aislamiento.
- **DNS:** respuestas autoritativas de `reservaviva.local`, NXDOMAIN, rechazo de recursión, y alcance solo desde la VLAN 99.
- **NTP:** el servidor responde con un stratum válido, un cliente chrony real lo acepta, y solo es alcanzable desde la VLAN 99.
- **LDAP/LDAPS:** login LDAP real en ERPNext e InvenTree; clave errónea rechazada; `ldapsearch` por LDAPS que valida con la CA interna y falla con una CA ajena. También comprueba que todo sobrevive a un `down` + `up -d`.

El último resultado y las cifras de cada pasada están en [`docs/resultados-un-host.md`](docs/resultados-un-host.md).

**Lo que un solo equipo no puede demostrar:**

- El etiquetado 802.1Q y los puertos troncales.
- El switch físico.
- La matriz de firewall sobre interfaces reales.

Además, la VLAN 99 es un único dominio L2 compartido por las 4 aplicaciones. `verificar` lo reporta como `INFO`, porque es un hallazgo previsto del diseño.

## Documentación

- [`docs/arquitectura.md`](docs/arquitectura.md): los 25 servicios por departamento, las redes y sus IP, y los flujos de LDAP, DNS y NTP.
- [`docs/operacion.md`](docs/operacion.md): cómo arrancar, vigilar, detener y validar el sistema, y las trampas de Windows/WSL.
- [`docs/seguridad.md`](docs/seguridad.md): la CA interna, LDAPS, las ACL y cuentas de servicio, los secretos de laboratorio y lo que un host no aísla.
- [`docs/aplicaciones.md`](docs/aplicaciones.md): cada aplicación con su departamento, URL, usuario inicial e integración LDAP.
- [`docs/resultados-un-host.md`](docs/resultados-un-host.md): las cifras medidas (arranque, memoria, pasadas de `verificar`) y los pendientes.

## Mapa del repositorio

```
levantar-sistema.sh / .ps1 / .cmd   # arranque plug and play (la lógica está en el .sh)
docker-compose.yml                  # el ÚNICO compose: los 25 servicios, agrupados por departamento
servicios/                          # una carpeta por servicio, con su README
  openvpms/                         # Médica (VLAN 10): Dockerfile, inicialización reanudable y su prueba
  pretix/                           # Taquilla (VLAN 20)
  inventree/                        # Logística (VLAN 30)
  erpnext/                          # RRHH (VLAN 40): prueba de erpnext-create-site
  openldap/                         # Infraestructura (VLAN 99): LDIF de estructura, ACL y usuarios de prueba
  bind9/                            # Infraestructura: named.conf y plantilla de la zona DNS
  ntp/                              # Infraestructura: servidor de hora
  ca/                               # CA interna + certificado LDAPS (lo ejecuta levantar-sistema.sh)
sistema/                            # test.env (variables y claves de laboratorio) y la verificación
docs/                               # resultados vigentes e integración LDAP de cada aplicación
diseno-red/                         # ANEXO: diseño con switch L2/L3, VLANs 802.1Q, matriz y diagramas (no se despliega)
plans/handoffs/                     # último traspaso de trabajo y su plan
```

Todo `docker compose` se ejecuta desde la raíz con `--env-file sistema/test.env`. En `docker-compose.yml` los servicios se agrupan por departamento, igual que en el diseño de la Entrega 1 (3 equipos), y cada VLAN es una red bridge.

## Diseño de red (anexo)

El diseño propuesto reparte los servicios en 3 equipos conectados a un switch con VLANs 802.1Q. La carpeta [`diseno-red/`](diseno-red/README.md) lo conserva:

- La matriz de segmentación: [`arquitectura-3-equipos-departamentos.md`](diseno-red/arquitectura-3-equipos-departamentos.md).
- Las recetas para un switch L3 (SVIs + ACL) o L2 (el equipo de infraestructura como router con nftables).
- Los simuladores que reproducen la matriz sobre el kernel de Linux (necesitan la imagen `nicolaka/netshoot`).
- Los diagramas de topología y de flujo: [`topologia-red.html`](diseno-red/diagramas/topologia-red.html) y [`flujo-datos-segmentacion.html`](diseno-red/diagramas/flujo-datos-segmentacion.html).

No se ha probado contra un switch real.

El despliegue en 3 PCs se retiró del repositorio el 26/09/2026 para reducir la curva de aprendizaje. Incluía los scripts `deploy.sh` por PC, los servicios systemd, los tutoriales, las guías de Windows y el paquete offline. Todo se puede recuperar del historial de git: cada commit que lo retiró indica cómo.

## Integración LDAP por aplicación

- **ERPNext e InvenTree** autentican contra OpenLDAP por LDAPS con la CA interna: [`docs/integracion-ldap-erpnext-inventree.md`](docs/integracion-ldap-erpnext-inventree.md).
- **Pretix y OpenVPMS** no se integran de forma limpia y usan administradores locales. Es una limitación documentada: [`docs/ldap-pretix-openvpms.md`](docs/ldap-pretix-openvpms.md).

## Pendientes

La lista con su contexto está en [`docs/resultados-un-host.md`](docs/resultados-un-host.md#pendientes).
