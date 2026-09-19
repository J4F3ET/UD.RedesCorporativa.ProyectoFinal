# Diagramas de red

Diagramas interactivos (HTML autocontenido, con pan/zoom, temas claro/oscuro y vistas guiadas) generados con [Archify](https://github.com/tt-a1i/archify) a partir de los archivos reales del repo (`docs/arquitectura-3-equipos-departamentos.md` y los `docker-compose.yml` de `docker/`).

| Archivo | Qué muestra |
|---|---|
| [`topologia-red.html`](topologia-red.html) | Topología física: switch central, los 3 PCs, tipo de puerto (access/trunk), VLANs con sus subredes, y los contenedores de cada PC agrupados por VLAN (macvlan). Cada nodo referencia la línea exacta del `docker-compose.yml` de donde sale. |
| [`flujo-datos-segmentacion.html`](flujo-datos-segmentacion.html) | Flujo de datos y política de segmentación: qué tráfico está permitido (toda VLAN de negocio → VLAN99 para LDAP/DNS/NTP) y qué está bloqueado (VLANs de negocio entre sí, incluido el caso de hairpin cuando dos VLANs viven en el mismo PC físico, como VLAN20/VLAN30 en PC-2). |

Los `.architecture.json` / `.dataflow.json` junto a cada HTML son la especificación fuente — se pueden editar y volver a generar con Archify (`node bin/archify.mjs deliver <tipo> <especificación.json> <salida.html> --quality showcase`) si el diseño de red cambia.

Para verlos: abrir el `.html` directamente en el navegador (no requiere servidor).
