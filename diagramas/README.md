# Diagramas de red

Diagramas interactivos (HTML autocontenido, con pan/zoom, temas claro/oscuro y vistas guiadas) generados con [Archify](https://github.com/tt-a1i/archify) a partir de los archivos reales del repo (`docs/arquitectura-3-equipos-departamentos.md` y los `docker-compose.yml` de `docker/`).

| Archivo | Qué muestra |
|---|---|
| [`topologia-red.html`](topologia-red.html) | Topología física: switch central, los 3 PCs, tipo de puerto (access/trunk), VLANs con sus subredes, y los contenedores de cada PC agrupados por VLAN (macvlan). Cada nodo referencia la línea exacta del `docker-compose.yml` de donde sale. |
| [`flujo-datos-segmentacion.html`](flujo-datos-segmentacion.html) | Flujo de datos y política de segmentación: qué tráfico está permitido (toda VLAN de negocio → VLAN99 para LDAP/LDAPS, DNS y NTP) y qué está bloqueado (VLANs de negocio entre sí, incluido el caso de hairpin cuando dos VLANs viven en el mismo PC físico, como VLAN20/VLAN30 en PC-2). |

Los `.architecture.json` / `.dataflow.json` junto a cada HTML son la especificación fuente.

Para verlos: abrir el `.html` directamente en el navegador (no requiere servidor).

## Estado: regenerados contra el stack real

Ambos diagramas se rehicieron después de las pruebas reales documentadas en
[`../docs/prueba-smoke-test-resultados.md`](../docs/prueba-smoke-test-resultados.md), así que ya
reflejan lo que de verdad levanta `docker compose up`:

- **ERPNext no es un contenedor, son 11 servicios.** El diagrama muestra los dos que salen a
  VLAN40 (`erpnext-hr`, el nginx que escucha en **:8080**, y `erpnext-backend` en :8000) y agrupa
  los nueve restantes — MariaDB 10.6, los dos Redis, los cuatro workers y los dos jobs de
  arranque (`configurator`, `create-site`) — en un solo nodo "ERPNext interno", porque viven en un
  bridge privado (`erpnext_internal`) y nunca salen al switch.
- **DNS interno con bind9** (`10.10.99.11:53`, zona `reservaviva.local`), que antes no aparecía.
- **`inventree-worker`** (`10.10.30.12`), el worker de tareas en segundo plano de InvenTree.
- **LDAPS en el 636 con CA interna**: los certificados los crea `scripts/generar-certificados.sh`
  (los que trae la imagen `osixia/openldap` usan una CA caducada) y su `ca.crt` se copia a PC-1 y
  PC-2 para que verifiquen la cadena.

Las referencias a código de `topologia-red.architecture.json` están fijadas al commit
`752e41f`. Si los `docker-compose.yml` cambian de tamaño, hay que actualizar los rangos
`line`/`end_line` y la `revision` antes de regenerar, o Archify rechazará la evidencia.

## Cómo regenerarlos

Con el [Skill de Archify](https://github.com/tt-a1i/archify) instalado, desde su directorio:

```bash
node bin/archify.mjs deliver architecture <repo>/diagramas/topologia-red.architecture.json <repo>/diagramas/topologia-red.html --quality showcase --repo-root <repo>
```

```bash
node bin/archify.mjs deliver dataflow <repo>/diagramas/flujo-datos-segmentacion.dataflow.json <repo>/diagramas/flujo-datos-segmentacion.html --quality showcase
```

`--repo-root` solo hace falta en el de topología, que es el que declara evidencia de código
(`meta.repository` + `sources`). Después conviene comprobar el resultado en un navegador real:

```bash
node bin/archify.mjs visual-check <repo>/diagramas/topologia-red.html --json
```

Ese comando deja PNGs y un `*.visual-check.json` junto al HTML; son evidencia desechable y **no**
se versionan. La última corrida dejó ambos diagramas con los 9 artifact checks en verde, la
composición en `showcase` sin errores ni avisos, y sin desbordes a 1440×900, 1600×1000,
1920×1080 y 2048×1320 en tema claro y oscuro.
