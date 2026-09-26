# Smoke test de los 3 compose reales en un solo host

> **Forma recomendada de usarlo:** `levantar-sistema.sh` / `levantar-sistema.ps1` en la raíz del repositorio, que hace todo lo de abajo (certificados, zona DNS, imagen de OpenVPMS, arranque y espera a que todo esté sano). Lo que sigue es el uso manual.

Usa `include:` de `docker/pc{1,2,3}-*/docker-compose.yml` y solo sobrescribe redes (macvlan -> bridge)
y publica el puerto 8080 de `openvpms-app` (18080 en el host) para sondearlo. Incluye los 3 PCs completos (25 servicios). Contraseñas de prueba en `test.env` (desechables).

Antes del primer `up`, genera la zona DNS (bind9 monta `db.reservaviva.local`, que sale de una plantilla y no esta en git):
`../../levantar-sistema.sh preparar` (sustituye en la plantilla IP_PC1=10.10.10.10, IP_PC2=10.10.30.10 e IP_PC3=10.10.99.10)

```bash
docker compose pull && docker compose up -d      # primer arranque ~10 min (migraciones)
# probe.py: sondeo HTTP desde un contenedor dentro de la red; ldapprobe.py: bind LDAP anónimo crudo
docker compose down -v                            # limpiar
```
Verificación de la arquitectura: `../../levantar-sistema.sh verificar` (qué comprueba, en `verificar_arquitectura.md`). Los informes quedan en `resultados/` (fuera de git).

Verificación de la arquitectura (segmentación, DNS, NTP; NO VERIFICADO contra el arnés): `verificar_arquitectura.md` y `verificar_arquitectura.py`.
