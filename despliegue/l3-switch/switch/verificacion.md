# Verificación del perfil L3 (el switch enruta y aplica las ACL)

Comandos para dejar evidencia en la sustentación. Todos en modo privilegiado del switch (`enable`), salvo los de los PC.
Esta guía **no se ha ejecutado** contra un switch real: la sintaxis es Cisco IOS.

## 1. El switch tiene VLANs, SVIs y puertos como se diseñó
```
show vlan brief                  ! VLAN 10 (MEDICA), 20, 30, 40, 99 activas; Gi1/0/1 en la 10
show interfaces trunk            ! Gi1/0/2 permite 20,30 y Gi1/0/3 permite 40,99
show ip interface brief          ! Vlan10/20/30/40/99 con 10.10.X.1 y estado up/up
show ip route connected          ! las cinco subredes 10.10.X.0/24 conectadas
```
Una SVI aparece `up/up` solo si la VLAN existe y hay al menos un puerto activo en ella.

## 2. Las ACL implementan la matriz (contadores = evidencia)
```
clear access-list counters
show access-lists                ! todos los "deny" en 0
```
Desde un contenedor de cada VLAN, intenta llegar a otra VLAN de negocio, por ejemplo desde PC-2 (VLAN 20):
`ping 10.10.30.10` (Logística) y `ping 10.10.10.10` (Médica). Repite `show access-lists`: el contador del
`deny ip 10.10.20.0 ... 10.10.30.0 ...` y del que apunta a 10.10.10.0 sube; los demás siguen en 0.

Permitido (debe responder): desde cualquier VLAN de negocio, `ping 10.10.99.10` (LDAP) y `ping 10.10.99.11` (DNS).
Ese tráfico cae en el `permit ip any any` y su contador sube.

```
show ip interface Vlan20 | include access list   ! muestra ACL-VLAN20-IN en "Inbound access list"
```

## 3. Sin direcciones duplicadas
En PC-2 y PC-3 las sub-interfaces no llevan IP (salvo la `IP_GESTION` opcional, .250, en una sola VLAN); el gateway es solo el switch:
```
ip -brief addr show | grep '\.'      ! (en cada PC) <IFACE>.20/.30 (PC-2) y <IFACE>.40/.99 (PC-3) sin IPv4
arp -n | grep 10.10.20.1             ! (desde un contenedor) una sola MAC: la de la SVI del switch
```

## 4. Tabla de resultados esperados
| Origen -> destino | Resultado | Dónde queda la evidencia |
|---|---|---|
| VLAN de negocio -> otra VLAN de negocio | sin respuesta | contador del `deny` en `show access-lists` |
| VLAN de negocio -> VLAN 99 | responde | contador del `permit ip any any` |
| VLAN 99 -> VLAN de negocio | responde | (sin ACL en Vlan99) |
