# Tutorial PC-2 — Servidor de Operaciones (Taquilla + Logística)

> **Documento de diseño: no aplica al laboratorio Windows.** Los PCs del laboratorio son Windows con Docker Desktop, que no permite VLAN 802.1Q ni `macvlan` sobre la tarjeta de red. Este documento describe el diseño de red propuesto (switch con VLANs, PCs Linux): su lógica se validó por simulación (`despliegue/*/pruebas/`), no sobre un switch real. No sigas estos pasos tal cual en el laboratorio: la guía para Windows está en preparación. Para saber qué está validado y cómo, ver el [README raíz](../README.md#estado-de-validación).

Este computador va a correr **dos** aplicaciones: **Pretix** (venta de entradas) y **InvenTree** (inventario y almacén). No necesitas saber nada de redes ni de programación para seguir estos pasos: solo copiar y pegar los comandos exactamente como aparecen.

## Antes de empezar

- [ ] El PC tiene Ubuntu Server ya instalado.
- [ ] Tienes la contraseña de administrador del PC.
- [ ] Tienes el cable de red a la mano.
- [ ] Tienes el **paquete de la Fase 0** (preparación previa, hecha en otra máquina con Internet: Docker, las imágenes y el proyecto). **El laboratorio no tiene Internet.** Ver [`despliegue/README.md`](../despliegue/README.md).

## Paso 1 — Conectar el cable de red

Conecta el cable de red de este PC al puerto del switch marcado como **"Operaciones" / TRUNK**. Este puerto es distinto a los de PC-1 y PC-3: debe estar configurado por el compañero de redes como **trunk permitiendo las VLAN 20 y 30**. Si tienes dudas de cuál es, pregunta antes de continuar — conectar este PC a un puerto access (de una sola VLAN) hace que una de las dos aplicaciones no funcione.

## Paso 2 — Abrir una terminal

La terminal es la ventana negra donde se escriben comandos.

- Si el PC tiene pantalla de escritorio: busca una aplicación llamada **"Terminal"** (o presiona las teclas `Ctrl` + `Alt` + `T` al mismo tiempo).
- Si el PC solo muestra una pantalla de texto (sin íconos): ya estás en la terminal, solo inicia sesión con tu usuario y contraseña.

De aquí en adelante, cada bloque de texto gris es algo que debes **copiar y pegar** en esa ventana, presionando `Enter` después de cada bloque.

## Paso 3 — Instalar Docker

Docker es el programa que va a correr las aplicaciones. **En el laboratorio no hay Internet**, así que no se descarga aquí: se instala desde el paquete de la Fase 0.

> **HUECO: comandos pendientes.** Los está preparando pepe (`docker save` / `docker load`). El USB de la Fase 0 lleva cuatro cosas: los paquetes de Docker para la versión exacta de Ubuntu Server, el proyecto entero, las imágenes de las aplicaciones y la de OpenVPMS ya construida. Cuando estén comprobados se escribirán en [`despliegue/README.md`](../despliegue/README.md) y aquí. **No improvises otro procedimiento** y no intentes conseguir Internet para este PC: el laboratorio debe quedar aislado.

Al terminar, comprueba que quedó instalado:

```bash
docker --version
```

Debe mostrar un número de versión.

## Paso 4 — Dejar el proyecto en el PC

El proyecto no se descarga de GitHub (no hay Internet): llega dentro del paquete de la Fase 0.

> **HUECO: comandos pendientes.** Los está preparando pepe (`docker save` / `docker load`). El USB de la Fase 0 lleva cuatro cosas: los paquetes de Docker para la versión exacta de Ubuntu Server, el proyecto entero, las imágenes de las aplicaciones y la de OpenVPMS ya construida. Cuando estén comprobados se escribirán en [`despliegue/README.md`](../despliegue/README.md) y aquí. **No improvises otro procedimiento** y no intentes conseguir Internet para este PC: el laboratorio debe quedar aislado.

Cuando el proyecto esté en el PC, entra a la carpeta de este equipo:

```bash
cd UD.RedesCorporativaa.ProyectoFinak/docker/pc2-operaciones
```

(Si el paquete lo dejó en otra ruta, entra a esa carpeta y luego a `docker/pc2-operaciones`.)

## Paso 5 — Identificar el nombre de tu tarjeta de red

Copia y pega esto:

```bash
ip -brief link show
```

Vas a ver una lista de nombres. Busca el que **no** sea `lo` (ese es interno del PC, ignóralo) — normalmente se llama `eth0`, pero a veces es algo como `enp2s0` o `ens33`. Anota ese nombre, lo vas a usar en el siguiente paso.

## Paso 6 — Crear el archivo de configuración

```bash
cp .env.example .env
nano .env
```

Se abre un editor de texto simple. Vas a ver algo así:

```
IFACE=eth0
PERFIL=l3
IP_GESTION=
PRETIX_DB_PASSWORD=cambiar-esta-clave
INVENTREE_DB_PASSWORD=cambiar-esta-clave
INVENTREE_ADMIN_USER=admin
INVENTREE_ADMIN_PASSWORD=cambiar-esta-clave
INVENTREE_ADMIN_EMAIL=admin@reservaviva.local
PRETIX_ADMIN_EMAIL=admin@reservaviva.local
PRETIX_ADMIN_PASSWORD=cambiar-esta-clave
```

- Si el nombre que anotaste en el Paso 5 **no** era `eth0`, bórralo y escribe el nombre correcto después del `=`.
- `PERFIL`: pon `l3` o `l2`, **el mismo en los tres PCs**. Es el nombre de la receta del switch que el equipo técnico esté siguiendo: `l3` si usa la carpeta `despliegue/l3-switch/` y `l2` si usa `despliegue/l2-fallback/`. Si todavía nadie sabe cuál es, pregúntale al equipo técnico antes de encender: el archivo trae `l3` por defecto y solo sirve si el switch es de ese tipo.
- `IP_GESTION`: una dirección propia de este PC, necesaria para copiarle el certificado de seguridad desde el PC-3 por la red (si no, hay que llevarlo en un USB). Pon `10.10.20.250` **o** `10.10.30.250`: **una sola, nunca las dos**. Si la pones en las dos redes, este PC empezaría a pasar tráfico entre ellas por sí mismo y se perdería justo lo que el laboratorio quiere demostrar (que ese paso lo decide el switch o el PC-3). El instalador se niega a seguir si la pones en las dos.
- Cambia cada `cambiar-esta-clave` por una contraseña propia (sin espacios). Pueden ser distintas entre sí.
- `INVENTREE_ADMIN_PASSWORD` y `PRETIX_ADMIN_PASSWORD` son las contraseñas con las que se entra a InvenTree y a Pretix por primera vez (usuario `admin` en InvenTree, y el correo `PRETIX_ADMIN_EMAIL` en Pretix). Anótalas en un lugar seguro. Los usuarios se crean solos: no hay que crear ningún administrador a mano.

Para guardar y salir: presiona `Ctrl` + `O`, luego `Enter`, luego `Ctrl` + `X`.

## Paso 7 — Ejecutar el instalador

```bash
sudo ./deploy.sh
```

Este comando hace automáticamente todo lo necesario: prepara la red para las dos VLANs (20 y 30) y luego descarga y arranca las aplicaciones. La primera vez tarda varios minutos (las imágenes ya están cargadas desde el paquete; el tiempo depende del disco del PC). No necesitas hacer nada manual de redes — el script se encarga.

**Si la primera vez el instalador se detiene** con el mensaje `PASO PENDIENTE (no es un error)`: falta el certificado `ca.crt`, que viene del PC-3. El mensaje trae el comando exacto para copiarlo; cópialo y vuelve a ejecutar `sudo ./deploy.sh`. Los detalles (y la dirección `IP_GESTION` que se necesita para copiarlo) están en el paso 5 de la receta del switch que esté siguiendo el equipo técnico: [`despliegue/README.md`](../despliegue/README.md).

**Importante:** en el primer arranque, Pretix e InvenTree preparan sus bases de datos y tardan **unos 10 minutos** en responder. El script espera y, cuando Pretix está listo, crea su administrador. Si al final ves el aviso `Pretix no quedo listo a tiempo`, espera unos minutos y ejecuta `sudo ./deploy.sh --solo-admins`. Es normal y no significa que algo esté roto.

## Paso 8 — Verificar que quedó funcionando

Al final del paso anterior, el mismo comando muestra una tabla. Debe verse algo así:

```
NAME              IMAGE                   STATUS
pretix-db         postgres:15             Up
pretix-redis      redis:7                 Up
pretix-web        pretix/standalone       Up
inventree-db      postgres:15             Up
inventree-app     inventree/inventree     Up
inventree-worker  inventree/inventree     Up
```

Si **todas** las filas dicen **"Up"**, quedó funcionando correctamente. Si alguna dice algo distinto (como "Restarting" o "Exited"), ve a la sección "Si algo sale mal" más abajo.

> Nota: que digan "Up" confirma que las aplicaciones están corriendo y conectadas a la red del laboratorio. Para ver que responden, desde **otro** equipo de la VLAN correspondiente abre `http://10.10.20.10` (Pretix, VLAN 20) o `http://10.10.30.10:8000` (InvenTree, VLAN 30); un PC con red `macvlan` no puede abrir sus propios contenedores desde sí mismo. Crear el evento en Pretix y cargar el catálogo en InvenTree es un paso aparte que hace el equipo técnico.

## Paso 9 — Dejarlo funcionando aunque el PC se reinicie (recomendado)

Sin este paso, si el PC se apaga o se reinicia, las sub-redes de VLAN 20/30 que se crearon en el Paso 7 desaparecen y alguien tendría que repetirlo a mano. Con este paso, todo vuelve a arrancar solo:

```bash
cd ~/UD.RedesCorporativaa.ProyectoFinak
sudo mkdir -p /opt/reserva-viva
sudo cp -r . /opt/reserva-viva
sudo cp scripts/systemd/reserva-viva-pc2.service /etc/systemd/system/
sudo systemctl daemon-reload
sudo systemctl enable --now reserva-viva-pc2.service
```

Listo. De ahora en adelante, cada vez que este PC se encienda, Pretix e InvenTree van a quedar funcionando solos, sin que nadie tenga que hacer nada.

## Si algo sale mal

| Lo que ves | Qué hacer |
|---|---|
| `sudo: command not found` o pide contraseña y no la acepta | Confirma que estás usando el usuario administrador correcto del PC. |
| `Cannot connect to the Docker daemon` | Docker no terminó de instalarse. Repite el Paso 3 y espera a que termine sin errores. |
| Al correr `sudo ./deploy.sh` dice `Falta .env` | Se te olvidó el Paso 6 (crear el archivo `.env`). Vuelve a hacerlo. |
| Aparece un error mencionando `eth0.20` o `eth0.30` que "no existe" o "invalid" | El nombre de tu tarjeta de red no es `eth0`. Repite el Paso 5 y corrige `IFACE` en el `.env` (Paso 6), luego vuelve a correr `sudo ./deploy.sh`. |
| Alguna fila de la tabla del Paso 8 dice `Exited` o `Restarting` | Copia el mensaje de error con: `docker compose logs` y muéstraselo al equipo técnico. |
| Solo una de las dos aplicaciones (Pretix o InvenTree) funciona | Puede ser que el puerto del switch no esté permitiendo las dos VLANs (20 y 30) como trunk. Avisa al compañero encargado del switch. |

Si nada de esto resuelve el problema, avisa al equipo técnico indicando en qué paso te quedaste y adjuntando una foto de la pantalla.
