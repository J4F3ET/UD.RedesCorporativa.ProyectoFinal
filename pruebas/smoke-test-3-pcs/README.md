# Smoke test de los 3 compose reales en un solo host

Usa `include:` de `docker/pc{1,2,3}-*/docker-compose.yml` y solo sobrescribe redes (macvlan -> bridge)
y publica el puerto 8080 de `openvpms-app` (18080 en el host) para sondearlo. Incluye los 3 PCs completos (22 contenedores). Contraseñas de prueba en `test.env` (desechables).

Antes del primer `up`, genera la zona DNS (bind9 monta `db.reservaviva.local`, que sale de una plantilla y no esta en git):
`powershell -File ..\..\docker\pc3-administracion-infra\bind\generar-zona.ps1 -IpPc1 10.10.10.10 -IpPc2 10.10.30.10 -IpPc3 10.10.99.10`

```bash
docker compose pull && docker compose up -d      # primer arranque ~10 min (migraciones)
# probe.py: sondeo HTTP desde un contenedor dentro de la red; ldapprobe.py: bind LDAP anónimo crudo
docker compose down -v                            # limpiar
```
Resultados y hallazgos: `docs/prueba-smoke-test-resultados.md`.
