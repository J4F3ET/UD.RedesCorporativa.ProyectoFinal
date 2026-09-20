# Verificación del perfil L2 (el switch conmuta; PC-3 enruta y filtra)

Comandos para dejar evidencia en la sustentación. Esta guía **no se ha ejecutado** contra un switch real: la
parte del switch es sintaxis Cisco IOS y la de PC-3 espera validación (simulador de red / laboratorio).

## 1. En el switch (modo privilegiado, `enable`)
```
show vlan brief                  ! VLAN 10 (MEDICA), 20, 30, 40, 99 activas; Gi1/0/1 en la 10
show interfaces trunk            ! Gi1/0/2 permite 20,30 y Gi1/0/3 permite 10,20,30,40,99
show ip interface brief          ! NO debe haber interfaces Vlan con IP (el switch no enruta)
show mac address-table           ! MAC de PC-3 vista en las VLAN 10,20,30,40,99 (mismo puerto)
```

## 2. En PC-3 (el router)
```
ip -brief addr show                          # <IFACE>.10/.20/.30/.40/.99 SIN IPv4; gw10/gw20/gw30/gw40/gw99 con 10.10.X.1
cat /proc/sys/net/ipv4/ip_forward            # 1
sysctl net.ipv4.conf.all.arp_ignore net.ipv4.conf.all.arp_announce   # 1 y 2
sudo nft -a list table inet reservaviva      # 12 reglas "drop" con contador (-a va antes de list)
sudo iptables -S DOCKER-USER                 # incluye: -s 10.10.0.0/16 -d 10.10.0.0/16 -j ACCEPT
```
(`<IFACE>` es el valor de `IFACE` del `.env`, p. ej. `enp2s0`.)

## 3. Contadores de nftables = evidencia de la matriz
```
sudo ./firewall-pc3-matriz.sh                        # (en despliegue/l2-fallback/scripts) recrea la tabla: contadores a cero
sudo nft -a list table inet reservaviva
```
Desde un contenedor de PC-2 (VLAN 20): `ping 10.10.30.10` y `ping 10.10.10.10`. Repite el `list`: suben los
contadores `VLAN20 -> VLAN30 bloqueado` y `VLAN20 -> VLAN10 bloqueado`; los demás siguen en 0. Para verlo en vivo:
`watch -n1 'nft list table inet reservaviva'`.

Permitido (debe responder): desde cualquier VLAN de negocio, `ping 10.10.99.10` (LDAP) y `ping 10.10.99.11` (DNS);
esos paquetes no pasan por ninguna regla `drop`.

## 4. Sin direcciones duplicadas
```
arp -n | grep 10.10.20.1        # (desde un contenedor de PC-2) una sola MAC: la de PC-3
```
PC-2 no debe tener ninguna IPv4 en `<IFACE>.20`/`<IFACE>.30`, salvo la `IP_GESTION` opcional (.250) en una sola de las dos.

## 5. Tabla de resultados esperados
| Origen -> destino | Resultado | Dónde queda la evidencia |
|---|---|---|
| VLAN de negocio -> otra VLAN de negocio | sin respuesta | contador de la regla `drop` en `nft -a list table inet reservaviva` |
| VLAN de negocio -> VLAN 99 | responde | ninguna regla `drop` sube |
| VLAN 99 -> VLAN de negocio | responde | ninguna regla `drop` sube |
| Tráfico interno de ERPNext (bridge `erpnext_internal`) | funciona | no pasa por ninguna regla de la tabla |
