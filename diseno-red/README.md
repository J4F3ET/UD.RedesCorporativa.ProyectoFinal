# ¿Switch L2 o L3? Averígualo y sigue una sola receta

> **HISTÓRICO. Diseño sustituido el 04/10/2026.** Esta carpeta describe el diseño con VLAN 802.1Q (switch L2/L3, matriz de segmentación y diagramas) que se propuso en la Entrega 1. El switch del laboratorio obliga a **una sola IP y un puerto por servicio**, así que el sistema vigente no usa VLAN: corre en un solo host, en una única red de Docker, y los servicios se hablan por `HOST_IP:puerto` (ver el [README raíz](../README.md) y [`docs/arquitectura.md`](../docs/arquitectura.md)). La carpeta se conserva como registro del diseño y no describe el sistema que se despliega. Los simuladores (`l3-switch/pruebas/simular-l3.sh`, `l2-fallback/pruebas/simular-l2.sh`) reproducen la segmentación sobre el kernel de Linux y necesitan la imagen `nicolaka/netshoot`.
>
> Las recetas citan piezas del despliegue en 3 PCs que se retiraron el 26/09/2026 (`docker/pc*/deploy.sh`, `.env.example`, `scripts/perfil.sh`, `scripts/systemd/`, `tutoriales/`, el paquete offline). Si algún día se despliega sobre un switch real, se recuperan con `git checkout cceb54c -- <ruta>`.

Tienes dos recetas listas. Cuál te toca depende del switch del laboratorio. Nadie ha confirmado todavía cuál es: esta página te dice cómo saberlo en un minuto.

## Paso 1 — Entra a la consola del switch

Conéctate por el cable de consola (o SSH/telnet si ya tiene IP) y entra a modo privilegiado.

```
enable
```

## Paso 2 — Mira si tiene interfaces por VLAN

```
show ip interface brief
```

Lee la salida:

| Qué ves | Qué significa |
|---|---|
| Interfaces llamadas `Vlan10`, `Vlan20`… **con una dirección IP** | **L3** |
| Solo puertos físicos (`GigabitEthernet…`) y, como mucho, una `Vlan1` de gestión | **L2** |

Si no estás seguro, pasa al paso 3.

## Paso 3 — Prueba definitiva

Entra a modo configuración.

```
configure terminal
```

Intenta activar el enrutamiento.

```
ip routing
```

| Respuesta | Significa |
|---|---|
| Lo acepta y no dice nada | **L3** |
| `% Invalid input detected` | **L2** |

Si lo aceptó, **no lo dejes puesto sin querer**: la receta L3 lo configura de todos modos. Sal con `end`.

```
end
```

> Estos comandos son de Cisco IOS. Si el switch es de otra marca, busca el equivalente: "¿tiene interfaces virtuales por VLAN con IP y enruta entre ellas?".

## Paso 4 — Ve a la carpeta que toque

| Resultado | Receta |
|---|---|
| **L3** | [`l3-switch/README.md`](l3-switch/README.md) |
| **L2** | [`l2-fallback/README.md`](l2-fallback/README.md) |

Las dos son completas y se siguen de arriba abajo, sin saltar a otros documentos.

## Qué cambia entre las dos (resumen)

| | L3 | L2 |
|---|---|---|
| Quién enruta entre VLANs | El switch (una SVI `10.10.X.1` por VLAN) | PC-3, como router-on-a-stick |
| Dónde se aplica la matriz de segmentación | ACL en el switch | `nftables` en PC-3 |
| Trunk de PC-3 | VLAN 40 y 99 | Las 5 VLANs: 10, 20, 30, 40 y 99 |
| Valor de `PERFIL` en cada `.env` | `l3` | `l2` |

`PERFIL` va **igual en los tres PCs**. Si lo pones distinto en uno, la red queda a medias.

## Obligatorio antes de ir: el laboratorio NO tiene Internet

Confirmado por el usuario. Sin Internet no falta solo la descarga de imágenes: **faltan Docker mismo y el repositorio**. **Sin una preparación previa no arranca nada.** Esa preparación (Fase 0) se hace otro día, en otra máquina con Internet, y el USB debe llevar cuatro cosas:

1. Los `.deb` de Docker Engine **para la versión exacta de Ubuntu Server** de los PCs (pendiente: saber cuál es).
2. El repositorio entero.
3. Las imágenes de todas las aplicaciones, guardadas **por etiqueta**, nunca por digest (si no, la imagen queda sin nombre al cargarla y Docker intenta descargarla).
4. La imagen de OpenVPMS ya construida (~300 MB, se compila antes).

**Comandos de la Fase 0: pendientes** (los construye pepe con `docker save`/`docker load`). Cada receta marca el hueco.

## Ensaya antes en tu portátil (sin hardware)

Cada perfil trae un simulador que ejercita la matriz de segmentación completa (las 20 celdas) en un solo host, sin el switch y sin levantar las aplicaciones. Es la forma de llegar al laboratorio sabiendo que la lógica de la receta funciona.

- L3: [`l3-switch/pruebas/README.md`](l3-switch/pruebas/README.md)
- L2: [`l2-fallback/pruebas/README.md`](l2-fallback/pruebas/README.md)

Prueba el **kernel de Linux**, no el switch del laboratorio (no valida la sintaxis del switch ni macvlan sobre una NIC real).

## Estado de validación

Ninguno de los dos perfiles se ha probado todavía contra un switch real: **pendiente de hardware**. Lo probado es la capa de software en un solo host y, con los simuladores de arriba, el comportamiento de la matriz sobre el kernel de Linux (ver [`../sistema/verificar_arquitectura.md`](../sistema/verificar_arquitectura.md)). Por eso cada receta dice, paso a paso, cómo comprobar que salió bien y qué guardar como evidencia.

El diseño completo (direccionamiento y matriz) está en [`arquitectura-3-equipos-departamentos.md`](arquitectura-3-equipos-departamentos.md); no lo necesitas para seguir las recetas.
