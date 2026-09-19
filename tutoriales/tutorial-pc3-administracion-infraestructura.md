# Tutorial PC-3 — Servidor de Administración e Infraestructura (RRHH + LDAP/DNS/NTP)

Este computador va a correr **ERPNext** (el módulo de Recursos Humanos) y los tres servicios de infraestructura de todo el laboratorio: **OpenLDAP** (cuentas de usuario), **DNS** y **NTP** (hora). Los otros dos PCs dependen de este para poder autenticar usuarios, así que conviene encenderlo primero. No necesitas saber nada de redes ni de programación para seguir estos pasos: solo copiar y pegar los comandos exactamente como aparecen.

## Antes de empezar

- [ ] El PC tiene Ubuntu Server ya instalado.
- [ ] Tienes la contraseña de administrador del PC.
- [ ] Tienes el cable de red a la mano.
- [ ] Hay Internet disponible (solo para esta instalación inicial).
- [ ] **Pregúntale al equipo técnico si el switch del laboratorio es "L2" o "L3"** (esto define un valor que vas a poner en el Paso 6). Si nadie lo sabe todavía, deja la opción por defecto (`false`) y sigue — se puede ajustar después.

## Paso 1 — Conectar el cable de red

Conecta el cable de red de este PC al puerto del switch marcado como **"Administración" / "Infraestructura" / TRUNK**. Este puerto debe estar configurado por el compañero de redes como **trunk permitiendo las VLAN 40 y 99** (y además las VLAN 10, 20 y 30 si el switch es L2 puro — pregúntale al equipo técnico). Si tienes dudas de cuál es, pregunta antes de continuar.

## Paso 2 — Abrir una terminal

La terminal es la ventana negra donde se escriben comandos.

- Si el PC tiene pantalla de escritorio: busca una aplicación llamada **"Terminal"** (o presiona las teclas `Ctrl` + `Alt` + `T` al mismo tiempo).
- Si el PC solo muestra una pantalla de texto (sin íconos): ya estás en la terminal, solo inicia sesión con tu usuario y contraseña.

De aquí en adelante, cada bloque de texto gris es algo que debes **copiar y pegar** en esa ventana, presionando `Enter` después de cada bloque.

## Paso 3 — Instalar Docker

Docker es el programa que va a correr las aplicaciones. Se instala una sola vez, copiando y pegando esto:

```bash
curl -fsSL https://get.docker.com | sudo sh
```

Te va a pedir la contraseña del PC (la del administrador) — escríbela y presiona `Enter`. No vas a ver los caracteres mientras escribes la contraseña, eso es normal, sigue escribiendo y da `Enter`.

Espera a que termine (puede tardar unos minutos). Al final debería decir algo como "Docker Engine v... is installed".

## Paso 4 — Descargar el proyecto

```bash
git clone https://github.com/J4F3ET/UD.RedesCorporativaa.ProyectoFinak.git
cd UD.RedesCorporativaa.ProyectoFinak/docker/pc3-administracion-infra
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
FALLBACK_L2=false
LDAP_ADMIN_PASSWORD=cambiar-esta-clave
ERPNEXT_DB_ROOT_PASSWORD=cambiar-esta-clave-db
ERPNEXT_ADMIN_PASSWORD=cambiar-esta-clave-erp
ERPNEXT_SITE=rrhh.reservaviva.local
```

- Si el nombre que anotaste en el Paso 5 **no** era `eth0`, bórralo y escribe el nombre correcto después del `=`.
- `FALLBACK_L2`: déjalo en `false` si el equipo técnico confirmó que el switch soporta VLANs con enrutamiento ("L3"), o si todavía no lo saben. Cámbialo a `true` **solo** si te confirmaron que el switch es "L2 puro" (sin esa capacidad).
- Cambia `cambiar-esta-clave` por una contraseña propia (sin espacios) — esta va a ser la contraseña de administrador del directorio de usuarios (LDAP) de todo el laboratorio, guárdala en un lugar seguro.
- Cambia también `ERPNEXT_DB_ROOT_PASSWORD` (base de datos de ERPNext) y `ERPNEXT_ADMIN_PASSWORD`. Esta última es la contraseña del usuario `Administrator` con el que se entra a ERPNext; anótala. `ERPNEXT_SITE` déjalo como está. El sitio de ERPNext se crea solo.

Para guardar y salir: presiona `Ctrl` + `O`, luego `Enter`, luego `Ctrl` + `X`.

## Paso 7 — Ejecutar el instalador

```bash
sudo ./deploy.sh
```

Este comando hace automáticamente todo lo necesario: prepara la red para las VLANs (40, 99, y las adicionales si pusiste `FALLBACK_L2=true`) y luego descarga y arranca las aplicaciones. La primera vez tarda varios minutos, depende de la velocidad de Internet. No necesitas hacer nada manual de redes — el script se encarga.

**Importante:** en el primer arranque, ERPNext crea su sitio y tarda **unos 10 minutos** en responder. Es normal.

## Paso 8 — Verificar que quedó funcionando

Al final del paso anterior, el mismo comando muestra una tabla. Debe verse algo así:

```
NAME           IMAGE                  STATUS
erpnext-hr     nginx                  Up
openldap       osixia/openldap        Up
dns-interno    ...bind9               Up
ntp-interno    cturra/ntp             Up
...            (más filas erpnext-*)
```

Verás además varias filas `erpnext-*` (base de datos, colas, backend, etc.). Todas deben decir **"Up"**, salvo `erpnext-configurator` y `erpnext-create-site`, que **deben** decir `Exited (0)`: son tareas que corren una vez, terminan y es lo esperado.

Si todas las demás dicen **"Up"**, quedó funcionando correctamente. Si alguna dice algo distinto (como "Restarting" o "Exited"), ve a la sección "Si algo sale mal" más abajo.

> Nota: que digan "Up" confirma que los servicios están corriendo y conectados a la red del laboratorio. Para ver ERPNext, desde **otro** equipo de la VLAN 40 abre `http://10.10.40.10:8080` (el puerto es 8080) e ingresa con `Administrator` y `ERPNEXT_ADMIN_PASSWORD`. Cargar usuarios en LDAP es un paso aparte del equipo técnico.

## Paso 9 — Dejarlo funcionando aunque el PC se reinicie (recomendado)

Como este PC sostiene el inicio de sesión y la hora de todo el laboratorio, es especialmente importante que se recupere solo si se reinicia:

```bash
cd ~/UD.RedesCorporativaa.ProyectoFinak
sudo mkdir -p /opt/reserva-viva
sudo cp -r . /opt/reserva-viva
sudo cp scripts/systemd/reserva-viva-pc3.service /etc/systemd/system/
sudo systemctl daemon-reload
sudo systemctl enable --now reserva-viva-pc3.service
```

Listo. De ahora en adelante, cada vez que este PC se encienda, ERPNext (RRHH), LDAP, DNS y NTP van a quedar funcionando solos, sin que nadie tenga que hacer nada. Si más adelante el equipo técnico confirma que hay que cambiar `FALLBACK_L2`, solo hace falta editar el `.env` (Paso 6) y volver a correr `sudo ./deploy.sh` — no hay que tocar nada más.

## Si algo sale mal

| Lo que ves | Qué hacer |
|---|---|
| `sudo: command not found` o pide contraseña y no la acepta | Confirma que estás usando el usuario administrador correcto del PC. |
| `Cannot connect to the Docker daemon` | Docker no terminó de instalarse. Repite el Paso 3 y espera a que termine sin errores. |
| Al correr `sudo ./deploy.sh` dice `Falta .env` | Se te olvidó el Paso 6 (crear el archivo `.env`). Vuelve a hacerlo. |
| Aparece un error mencionando `eth0.40` o `eth0.99` que "no existe" o "invalid" | El nombre de tu tarjeta de red no es `eth0`. Repite el Paso 5 y corrige `IFACE` en el `.env` (Paso 6), luego vuelve a correr `sudo ./deploy.sh`. |
| Alguna fila de la tabla del Paso 8 dice `Exited` o `Restarting` | Copia el mensaje de error con: `docker compose logs` y muéstraselo al equipo técnico. |
| Los otros PCs (PC-1 o PC-2) dicen que no pueden autenticarse o resolver nombres | Confirma que este PC (PC-3) está encendido y con la tabla del Paso 8 en "Up" — todo el laboratorio depende de él para LDAP/DNS/NTP. |
| No hay Internet para el Paso 3 o el Paso 4 | Conéctate temporalmente a una red con Internet (Wi-Fi u otro cable) solo para instalar, y luego vuelve a conectar el cable del switch para el Paso 1. |

Si nada de esto resuelve el problema, avisa al equipo técnico indicando en qué paso te quedaste y adjuntando una foto de la pantalla.
