# Tutorial PC-1 — Servidor Médico (Unidad Médica Veterinaria)

Este computador va a correr **OpenVPMS**, el programa de historias clínicas de los animales. No necesitas saber nada de redes ni de programación para seguir estos pasos: solo copiar y pegar los comandos exactamente como aparecen.

## Antes de empezar

- [ ] El PC tiene Ubuntu Server ya instalado.
- [ ] Tienes la contraseña de administrador del PC.
- [ ] Tienes el cable de red a la mano.
- [ ] Tienes el **paquete de la Fase 0** (preparación previa, hecha en otra máquina con Internet: Docker, las imágenes y el proyecto). **El laboratorio no tiene Internet.** Ver [`despliegue/README.md`](../despliegue/README.md).

## Paso 1 — Conectar el cable de red

Conecta el cable de red de este PC al puerto del switch marcado como **"Médica" / "VLAN 10" / ACCESS**. Si el switch no tiene etiquetas, pregúntale al compañero encargado de la red cuál es el puerto correcto para PC-1 antes de continuar.

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
cd UD.RedesCorporativaa.ProyectoFinak/docker/pc1-medica
```

(Si el paquete lo dejó en otra ruta, entra a esa carpeta y luego a `docker/pc1-medica`.)

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
OPENVPMS_DB_ROOT_PASSWORD=cambiar-esta-clave
OPENVPMS_DB_PASSWORD=cambiar-esta-clave-2
OPENVPMS_ADMIN_PASSWORD=Cambiar-Clave-3!
```

- Si el nombre que anotaste en el Paso 5 **no** era `eth0`, bórralo y escribe el nombre correcto después del `=`.
- `PERFIL`: pon `l3` o `l2`, **el mismo en los tres PCs**. Es el nombre de la receta del switch que el equipo técnico esté siguiendo: `l3` si usa la carpeta `despliegue/l3-switch/` y `l2` si usa `despliegue/l2-fallback/`. Si todavía nadie sabe cuál es, pregúntale al equipo técnico antes de encender: el archivo trae `l3` por defecto y solo sirve si el switch es de ese tipo.
- `IP_GESTION`: una dirección propia de este PC para poder hacerle `ping` o entrar por `ssh` cuando el equipo técnico lo necesite. Este PC **no** necesita el certificado, así que puedes dejarla **vacía** (`IP_GESTION=`). Si el equipo técnico te pide activarla, pon `10.10.10.250`.
- Cambia las tres contraseñas (`cambiar-esta-clave...`) por otras que tú elijas, sin espacios. La última, `OPENVPMS_ADMIN_PASSWORD`, es la que se usa para entrar a OpenVPMS con el usuario `admin`: anótala en un lugar seguro. **Esta debe tener mínimo 8 caracteres, con mayúscula, minúscula, número y un carácter especial** (por ejemplo `!`); si no cumple, OpenVPMS se niega a arrancar y lo dice en el mensaje de error.

Para guardar y salir: presiona `Ctrl` + `O`, luego `Enter`, luego `Ctrl` + `X`.

## Paso 7 — Ejecutar el instalador

```bash
sudo ./deploy.sh
```

Esto va a arrancar la aplicación con la imagen que ya viene construida en el paquete de la Fase 0 (aquí no se descarga ni se construye nada) y dejarla funcionando. **La primera vez, OpenVPMS además prepara su base de datos y carga los datos iniciales por su cuenta: puede tardar unos minutos más después de que la tabla del Paso 8 diga "Up".** No hace falta que hagas nada; es normal.

> La imagen de OpenVPMS (unos 300 MB) se construye **antes**, en otra máquina con Internet, y llega en el paquete. Si `deploy.sh` intenta descargar o construir algo y falla por falta de Internet, no lo repitas: avisa al equipo técnico (cómo se carga esa imagen lo define el paquete, todavía pendiente).

## Paso 8 — Verificar que quedó funcionando

Al final del paso anterior, el mismo comando muestra una tabla. Debe verse algo así:

```
NAME            IMAGE          STATUS
openvpms-db     mysql:8.0      Up
openvpms-app    ...            Up
```

Si ambas filas dicen **"Up"**, quedó funcionando correctamente. Si dice algo distinto (como "Restarting" o "Exited"), ve a la sección "Si algo sale mal" más abajo.

> Nota: que diga "Up" confirma que la aplicación está corriendo y conectada a la red del laboratorio. Para ver la pantalla de inicio, desde **otro** equipo conectado a la VLAN 10 abre `http://10.10.10.10:8080/openvpms/login` e ingresa con el usuario `admin` y la contraseña `OPENVPMS_ADMIN_PASSWORD` del Paso 6 (un PC con red `macvlan` no puede abrir sus propios contenedores desde sí mismo, así que no funcionará desde este mismo PC). Cargar los datos clínicos reales es un paso aparte del equipo técnico.

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

Si nada de esto resuelve el problema, avisa al equipo técnico indicando en qué paso te quedaste y adjuntando una foto de la pantalla.
