# ¿Switch L2 o L3? Averígualo y sigue una sola receta

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

## Estado de validación

Ninguno de los dos perfiles se ha probado todavía contra un switch real: **pendiente de hardware**. Lo único probado es la capa de software en un solo host (ver [`../docs/prueba-smoke-test-resultados.md`](../docs/prueba-smoke-test-resultados.md)). Por eso cada receta dice, paso a paso, cómo comprobar que salió bien y qué guardar como evidencia.

El diseño completo (direccionamiento y matriz) está en [`../docs/arquitectura-3-equipos-departamentos.md`](../docs/arquitectura-3-equipos-departamentos.md); no lo necesitas para seguir las recetas.
