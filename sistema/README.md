# Variables y verificación del sistema (`sistema/`)

> **Forma recomendada de usarlo:** `levantar-sistema.sh` / `levantar-sistema.ps1` en la raíz del repositorio, que hace todo lo de abajo (certificados, zona DNS, imagen de OpenVPMS, arranque y espera a que todo esté sano). Lo que sigue es el uso manual.

Qué hay aquí:

| Fichero | Para qué |
|---|---|
| `test.env` | Variables del laboratorio (puertos publicados, `HOST_IP` —la IP en la que se publica todo— y contraseñas de prueba, desechables). Es el `--env-file` de todo `docker compose` |
| `verificar_arquitectura.py` / `.md` | La verificación de la arquitectura y qué comprueba |
| `ldaplogin.py`, `ldapprobe.py`, `probe.py` | Pruebas que invoca la verificación (login LDAP, bind LDAP crudo, sondeo HTTP) |
| `resultados/` | Informes de `verificar` (fuera de git) |

El compose es el `docker-compose.yml` de la raíz (26 servicios) y se usa **desde la raíz** con este fichero de variables:

```bash
./levantar-sistema.sh preparar                                  # CA, certificado LDAPS y zona DNS (no están en git)
docker compose --env-file sistema/test.env up -d                # primer arranque: el lento (migraciones)
docker compose --env-file sistema/test.env ps                   # estado
docker compose --env-file sistema/test.env down -v              # BORRA todo, datos incluidos
```

Los tiempos medidos del arranque están en [`../docs/resultados-un-host.md`](../docs/resultados-un-host.md).

`preparar` genera la zona DNS de `reservaviva.lan` y la ACL de recursión (bind9 monta `servicios/bind9/zones/`): en la zona pone `HOST_IP` en todos los nombres de servicio.

`HOST_IP` es la IP del equipo (`192.168.1.26` en el laboratorio). `./levantar-sistema.sh --ip X.X.X.X` la sustituye en esa ejecución y `--intranet` autodetecta la IP de la LAN; si llamas a `docker compose` a mano, exporta `HOST_IP` antes si no es la de `test.env`.

Verificación de la arquitectura: `./levantar-sistema.sh verificar` (qué comprueba, en [`verificar_arquitectura.md`](verificar_arquitectura.md)).

El nombre del proyecto compose sigue siendo `reservaviva-smoke` (de cuando esto era una prueba de humo): cambiarlo crearía volúmenes nuevos y obligaría a reinicializar todo.
