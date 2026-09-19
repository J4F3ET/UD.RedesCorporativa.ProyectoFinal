# Smoke test de los 3 compose reales en un solo host

Usa `include:` de `docker/pc{1,2,3}-*/docker-compose.yml` y solo sobrescribe redes (macvlan -> bridge)
y publica el puerto 8080 de `openvpms-app` (18080 en el host) para sondearlo. Incluye los 3 PCs completos (22 contenedores). Contraseñas de prueba en `test.env` (desechables).

```bash
docker compose pull && docker compose up -d      # primer arranque ~10 min (migraciones)
# probe.py: sondeo HTTP desde un contenedor dentro de la red; ldapprobe.py: bind LDAP anónimo crudo
docker compose down -v                            # limpiar
```
Resultados y hallazgos: `docs/prueba-smoke-test-resultados.md`.
