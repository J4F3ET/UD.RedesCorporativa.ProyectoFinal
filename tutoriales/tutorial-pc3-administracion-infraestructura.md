# Tutorial PC-3 — Servidor de Administración e Infraestructura (RRHH + LDAP/DNS/NTP)

Este computador va a correr **ERPNext** (el módulo de Recursos Humanos) y los tres servicios de infraestructura de todo el laboratorio: **OpenLDAP** (cuentas de usuario), **DNS** y **NTP** (hora). Los otros dos PCs dependen de este para poder autenticar usuarios, así que conviene encenderlo primero. No necesitas saber nada de redes ni de programación para seguir estos pasos: solo copiar y pegar los comandos exactamente como aparecen.

## Antes de empezar

- [ ] El PC tiene Ubuntu Server ya instalado.
- [ ] Tienes la contraseña de administrador del PC.
- [ ] Tienes el cable de red a la mano.
- [ ] Tienes el **paquete de la Fase 0** (preparación previa, hecha en otra máquina con Internet: Docker, las imágenes y el proyecto). **El laboratorio no tiene Internet.** Ver [`despliegue/README.md`](../despliegue/README.md).
- [ ] **Pregúntale al equipo técnico si el switch del laboratorio es "L2" o "L3"** (esto define un valor, `PERFIL`, que vas a poner en el Paso 6, y es el mismo en los tres PCs). Si nadie lo sabe todavía, espera a saberlo antes de encender: el archivo trae `l3` por defecto y solo sirve si el switch es L3.

## Paso 1 — Conectar el cable de red

Conecta el cable de red de este PC al puerto del switch marcado como **"Administración" / "Infraestructura" / TRUNK**. Este puerto debe estar configurado por el compañero de redes como **trunk permitiendo las VLAN 40 y 99** (y además las VLAN 10, 20 y 30 si el switch es L2 — pregúntale al equipo técnico; en ese caso este PC hace de router de toda la red). Si tienes dudas de cuál es, pregunta antes de continuar.

## Paso 2 — Abrir una terminal

La terminal es la ventana negra donde se escriben comandos.

- Si el PC tiene pantalla de escritorio: busca una aplicación llamada **"Terminal"** (o presiona las teclas `Ctrl` + `Alt` + `T` al mismo tiempo).
- Si el PC solo muestra una pantalla de texto (sin íconos): ya estás en la terminal, solo inicia sesión con tu usuario y contraseña.

De aquí en adelante, cada bloque de texto gris es algo que debes **copiar y pegar** en esa ventana, presionando `Enter` después de cada bloque.

## Paso 3 — Instalar Docker

Docker es el programa que va a correr las aplicaciones. **En el laboratorio no hay Internet**, así que no se descarga aquí: se instala desde el paquete de la Fase 0.

> **HUECO: comandos pendientes.** Los está preparando pepe (paquete offline con `docker save` / `docker load`). Cuando estén comprobados se escribirán en [`despliegue/README.md`](../despliegue/README.md) y aquí. **No improvises otro procedimiento** y no intentes conseguir Internet para este PC: el laboratorio debe quedar aislado.

Al terminar, comprueba que quedó instalado:

```bash
docker --version
```

Debe mostrar un número de versión.

## Paso 4 — Dejar el proyecto en el PC

El proyecto no se descarga de GitHub (no hay Internet): llega dentro del paquete de la Fase 0.

> **HUECO: comandos pendientes.** Los está preparando pepe (paquete offline con `docker save` / `docker load`). Cuando estén comprobados se escribirán en [`despliegue/README.md`](../despliegue/README.md) y aquí. **No improvises otro procedimiento** y no intentes conseguir Internet para este PC: el laboratorio debe quedar aislado.

Cuando el proyecto esté en el PC, entra a la carpeta de este equipo:

```bash
cd UD.RedesCorporativaa.ProyectoFinak/docker/pc3-administracion-infra
```

(Si el paquete lo dejó en otra ruta, entra a esa carpeta y luego a `docker/pc3-administracion-infra`.)

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
LDAP_ADMIN_PASSWORD=cambiar-esta-clave
ERPNEXT_DB_ROOT_PASSWORD=cambiar-esta-clave-db
ERPNEXT_ADMIN_PASSWORD=cambiar-esta-clave-erp
ERPNEXT_SITE=rrhh.reservaviva.local
```

- Si el nombre que anotaste en el Paso 5 **no** era `eth0`, bórralo y escribe el nombre correcto después del `=`.
- `PERFIL`: pon `l3` o `l2`, **el mismo en los tres PCs**. Es el nombre de la receta del switch que el equipo técnico esté siguiendo: `l3` si usa la carpeta `despliegue/l3-switch/` y `l2` si usa `despliegue/l2-fallback/`. Si todavía nadie sabe cuál es, pregunta antes de seguir; `l3` (el valor que trae el archivo) solo sirve si el switch es L3.
- Cambia `cambiar-esta-clave` por una contraseña propia (sin espacios) — esta va a ser la contraseña de administrador del directorio de usuarios (LDAP) de todo el laboratorio, guárdala en un lugar seguro.
- Cambia también `ERPNEXT_DB_ROOT_PASSWORD` (base de datos de ERPNext) y `ERPNEXT_ADMIN_PASSWORD`. Esta última es la contraseña del usuario `Administrator` con el que se entra a ERPNext; anótala. `ERPNEXT_SITE` déjalo como está. El sitio de ERPNext se crea solo.

Para guardar y salir: presiona `Ctrl` + `O`, luego `Enter`, luego `Ctrl` + `X`.

## Paso 7 — Ejecutar el instalador

```bash
sudo ./deploy.sh
```

Este comando hace automáticamente todo lo necesario: prepara la red para las VLANs (40 y 99, y además 10, 20 y 30 si pusiste `PERFIL=l2`, porque entonces este PC hace de router) y luego descarga y arranca las aplicaciones. La primera vez tarda varios minutos (las imágenes ya están cargadas desde el paquete; el tiempo depende del disco del PC). No necesitas hacer nada manual de redes — el script se encarga.

El instalador también genera solo los certificados de seguridad del directorio de usuarios (LDAPS); no tienes que hacer nada. Quedan en la carpeta `certs/` de este PC y **no se suben a GitHub**.

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

Listo. De ahora en adelante, cada vez que este PC se encienda, ERPNext (RRHH), LDAP, DNS y NTP van a quedar funcionando solos, sin que nadie tenga que hacer nada. Si más adelante el equipo técnico confirma que hay que cambiar `PERFIL`, solo hace falta editar el `.env` (Paso 6) y volver a correr `sudo ./deploy.sh` — no hay que tocar nada más.

## Si algo sale mal

| Lo que ves | Qué hacer |
|---|---|
| `sudo: command not found` o pide contraseña y no la acepta | Confirma que estás usando el usuario administrador correcto del PC. |
| `Cannot connect to the Docker daemon` | Docker no terminó de instalarse. Repite el Paso 3 y espera a que termine sin errores. |
| Al correr `sudo ./deploy.sh` dice `Falta .env` | Se te olvidó el Paso 6 (crear el archivo `.env`). Vuelve a hacerlo. |
| Aparece un error mencionando `eth0.40` o `eth0.99` que "no existe" o "invalid" | El nombre de tu tarjeta de red no es `eth0`. Repite el Paso 5 y corrige `IFACE` en el `.env` (Paso 6), luego vuelve a correr `sudo ./deploy.sh`. |
| Alguna fila de la tabla del Paso 8 dice `Exited` o `Restarting` | Copia el mensaje de error con: `docker compose logs` y muéstraselo al equipo técnico. |
| Los otros PCs (PC-1 o PC-2) dicen que no pueden autenticarse o resolver nombres | Confirma que este PC (PC-3) está encendido y con la tabla del Paso 8 en "Up" — todo el laboratorio depende de él para LDAP/DNS/NTP. |

Si nada de esto resuelve el problema, avisa al equipo técnico indicando en qué paso te quedaste y adjuntando una foto de la pantalla.
