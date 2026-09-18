# Tutorial PC-1 — Servidor Médico (Unidad Médica Veterinaria)

Este computador va a correr **OpenVPMS**, el programa de historias clínicas de los animales. No necesitas saber nada de redes ni de programación para seguir estos pasos: solo copiar y pegar los comandos exactamente como aparecen.

## Antes de empezar

- [ ] El PC tiene Ubuntu Server ya instalado.
- [ ] Tienes la contraseña de administrador del PC.
- [ ] Tienes el cable de red a la mano.
- [ ] Hay Internet disponible (solo para esta instalación inicial).

## Paso 1 — Conectar el cable de red

Conecta el cable de red de este PC al puerto del switch marcado como **"Médica" / "VLAN 10" / ACCESS**. Si el switch no tiene etiquetas, pregúntale al compañero encargado de la red cuál es el puerto correcto para PC-1 antes de continuar.

## Paso 2 — Abrir una terminal

La terminal es la ventana negra donde se escriben comandos.

- Si el PC tiene pantalla de escritorio: busca una aplicación llamada **"Terminal"** (o presiona las teclas `Ctrl` + `Alt` + `T` al mismo tiempo).
- Si el PC solo muestra una pantalla de texto (sin íconos): ya estás en la terminal, solo inicia sesión con tu usuario y contraseña.

De aquí en adelante, cada bloque de texto gris es algo que debes **copiar y pegar** en esa ventana, presionando `Enter` después de cada bloque.

## Paso 3 — Instalar Docker

Docker es el programa que va a correr la aplicación. Se instala una sola vez, copiando y pegando esto:

```bash
curl -fsSL https://get.docker.com | sudo sh
```

Te va a pedir la contraseña del PC (la del administrador) — escríbela y presiona `Enter`. No vas a ver los caracteres mientras escribes la contraseña, eso es normal, sigue escribiendo y da `Enter`.

Espera a que termine (puede tardar unos minutos). Al final debería decir algo como "Docker Engine v... is installed".

## Paso 4 — Descargar el proyecto

```bash
git clone https://github.com/J4F3ET/UD.RedesCorporativaa.ProyectoFinak.git
cd UD.RedesCorporativaa.ProyectoFinak/docker/pc1-medica
```

Si tu equipo te indicó una rama de trabajo distinta a la principal, después del `git clone` ejecuta también:

```bash
git checkout NOMBRE-DE-LA-RAMA
```

(reemplaza `NOMBRE-DE-LA-RAMA` por el nombre real que te dieron).

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
OPENVPMS_DB_ROOT_PASSWORD=cambiar-esta-clave
```

- Si el nombre que anotaste en el Paso 5 **no** era `eth0`, bórralo y escribe el nombre correcto después del `=`.
- Cambia `cambiar-esta-clave` por una contraseña que tú elijas (sin espacios).

Para guardar y salir: presiona `Ctrl` + `O`, luego `Enter`, luego `Ctrl` + `X`.

## Paso 7 — Ejecutar el instalador

```bash
sudo ./deploy.sh
```

Esto va a descargar las imágenes de la aplicación (tarda varios minutos la primera vez, depende de la velocidad de Internet) y dejarlas funcionando.

## Paso 8 — Verificar que quedó funcionando

Al final del paso anterior, el mismo comando muestra una tabla. Debe verse algo así:

```
NAME            IMAGE          STATUS
openvpms-db     mysql:8.0      Up
openvpms-app    ...            Up
```

Si ambas filas dicen **"Up"**, quedó funcionando correctamente. Si dice algo distinto (como "Restarting" o "Exited"), ve a la sección "Si algo sale mal" más abajo.

> Nota: que diga "Up" confirma que la aplicación está corriendo y conectada a la red del laboratorio. Terminar de configurar OpenVPMS por dentro (crear usuarios, cargar datos clínicos) es un paso aparte que hace el equipo técnico — no hace falta que lo hagas tú aquí.

## Paso 9 — Dejarlo funcionando aunque el PC se reinicie (recomendado)

Sin este paso, si el PC se apaga o se reinicia, alguien tendría que repetir el Paso 7 a mano. Con este paso, arranca solo:

```bash
cd ~/UD.RedesCorporativaa.ProyectoFinak
sudo mkdir -p /opt/reserva-viva
sudo cp -r . /opt/reserva-viva
sudo cp scripts/systemd/reserva-viva-pc1.service /etc/systemd/system/
sudo systemctl daemon-reload
sudo systemctl enable --now reserva-viva-pc1.service
```

Listo. De ahora en adelante, cada vez que este PC se encienda, OpenVPMS va a quedar funcionando solo, sin que nadie tenga que hacer nada.

## Si algo sale mal

| Lo que ves | Qué hacer |
|---|---|
| `sudo: command not found` o pide contraseña y no la acepta | Confirma que estás usando el usuario administrador correcto del PC. |
| `Cannot connect to the Docker daemon` | Docker no terminó de instalarse. Repite el Paso 3 y espera a que termine sin errores. |
| Al correr `sudo ./deploy.sh` dice `Falta .env` | Se te olvidó el Paso 6 (crear el archivo `.env`). Vuelve a hacerlo. |
| Alguna fila de la tabla del Paso 8 dice `Exited` o `Restarting` | Copia el mensaje de error con: `docker compose logs` y muéstraselo al equipo técnico. |
| No hay Internet para el Paso 3 o el Paso 4 | Conéctate temporalmente a una red con Internet (Wi-Fi u otro cable) solo para instalar, y luego vuelve a conectar el cable del switch para el Paso 1. |

Si nada de esto resuelve el problema, avisa al equipo técnico indicando en qué paso te quedaste y adjuntando una foto de la pantalla.
