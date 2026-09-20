# Tutoriales de instalación (sin conocimientos técnicos)

Elige el tutorial según el computador que estés configurando. Cada uno es independiente — no necesitas leer los otros dos para hacer el tuyo.

| Si tu computador es... | Abre este tutorial |
|---|---|
| **PC-1**, el que va conectado al puerto marcado como "Médica / VLAN10" en el switch | [`tutorial-pc1-medica.md`](tutorial-pc1-medica.md) |
| **PC-2**, el que va conectado al puerto marcado como "Operaciones / TRUNK" en el switch | [`tutorial-pc2-operaciones.md`](tutorial-pc2-operaciones.md) |
| **PC-3**, el que va conectado al puerto marcado como "Administración e Infraestructura / TRUNK" en el switch | [`tutorial-pc3-administracion-infraestructura.md`](tutorial-pc3-administracion-infraestructura.md) |

Si no sabes cuál PC te tocó, pregúntale al compañero encargado de la red antes de empezar — conectar el cable al puerto equivocado hace que la aplicación de ese PC no funcione.

## Antes de empezar (los 3 tutoriales lo piden)

- El PC debe tener **Ubuntu Server** (o similar) ya instalado por el equipo técnico — estos tutoriales no cubren instalar el sistema operativo, solo lo que va encima.
- Necesitas la **contraseña de administrador** de ese PC (la que te dio el equipo técnico).
- **El laboratorio no tiene Internet** (confirmado; así lo pide el profesor). Todo lo que hace falta instalar (Docker, las imágenes de las aplicaciones y el proyecto) llega en un **paquete de preparación previa (Fase 0)**, armado antes en otra máquina con Internet. Sin ese paquete no arranca nada. Los comandos para usarlo están **pendientes** (los prepara pepe) y se documentarán en [`../despliegue/README.md`](../despliegue/README.md). Pregunta al equipo técnico por el paquete antes de empezar.
- El **cable de red** conectado al puerto correcto del switch (cada tutorial dice cuál).

## Si algo no funciona

Cada tutorial tiene al final una sección "Si algo sale mal" con los problemas más comunes. Si ninguna solución de ahí funciona, avisa al equipo técnico con: (1) qué tutorial y qué paso estabas siguiendo, y (2) una foto o copia del mensaje de error que salió en la pantalla.
