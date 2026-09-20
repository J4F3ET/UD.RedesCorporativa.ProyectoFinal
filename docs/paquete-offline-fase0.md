# Paquete offline de la Fase 0

> **NO VERIFICADO — pendiente de ejecutar con el motor Docker sano.**
> Los dos scripts y este documento se escribieron sin poder ejecutar Docker (el motor de la máquina de desarrollo estaba caído). Lo único comprobado: sintaxis de bash (`bash -n`), finales de línea LF y que el analizador de compose (`instalar-paquete-offline.sh --listar`) extrae bien las imágenes de los tres compose reales (tabla de abajo). **Todo lo demás está sin ejecutar**: la descarga de `.deb`, `docker pull/save/load`, el `build` de OpenVPMS, la instalación offline con `apt` y el comportamiento de los `docker-compose.override.yml`. Cuando se pruebe, anotar el resultado en la sección "Registro de verificación" al final.

El laboratorio **no tiene Internet**. Todo lo que hace falta llega en un USB armado antes, en otra máquina **con** Internet y Docker. Este documento define qué lleva ese USB y cómo se arma y se instala. Coherente con los commits `ed0e03c` y `abb14a9`: en el laboratorio no hay `curl`, `git clone`, `apt` desde red ni `docker pull`.

## 1. Qué hay que llevar

| # | Contenido | Dónde va en el paquete | Nota |
|---|---|---|---|
| 1 | `.deb` de Docker Engine: `docker-ce`, `docker-ce-cli`, `containerd.io`, `docker-buildx-plugin`, `docker-compose-plugin` **y todas sus dependencias** | `debs/` | Específicos de **versión de Ubuntu + arquitectura**. **Pendiente: confirmar qué Ubuntu tienen los PCs** (`lsb_release -a`, `dpkg --print-architecture`). |
| 2 | Imágenes de los tres compose, una por `.tar` | `imagenes/` | Guardadas **por etiqueta**, no por digest (ver §4). |
| 3 | Imagen de OpenVPMS **ya construida** | `imagenes/reservaviva_openvpms-app_fase0.tar` | El compose usa `build:`; construirla exige Internet (release de OpenVPMS + driver JDBC). |
| 4 | El proyecto (`git archive` del commit) | `proyecto.tar.gz` | Sin `.git`, sin `.env`, sin certificados. |
| — | `instalar.sh`, `PAQUETE.env`, `MANIFEST.sha256`, `INVENTARIO.md` | raíz | Generados por el script de preparación. |

Fuera del paquete, a propósito: `pruebas/smoke-test-3-pcs` usa `include:` de los tres compose (mismas imágenes, nada extra) y `pruebas/software-un-host` usa imágenes sin fijar (`postgres:15`, `frappe/erpnext:latest`…): es material de desarrollo, no del laboratorio.

## 2. Inventario de imágenes (leído de los compose)

Extraído de `docker/pc1-medica`, `docker/pc2-operaciones` y `docker/pc3-administracion-infra` con `scripts/instalar-paquete-offline.sh --listar <compose>` (esa orden **sí se ejecutó**). Referencias exactas, con el digest que fijan los compose. El digest es el checksum esperado **del origen** (lo que hay que descargar).

| Etiqueta (la que queda en el PC) | Digest fijado en el compose | Usada por |
|---|---|---|
| `mysql:8.0.46` | `sha256:7dcddc01f13bab2f15cde676d44d01f61fc9f99fe7785e86196dfc07d358ae2b` | PC-1 `openvpms-db` |
| `reservaviva/openvpms-app:fase0` | *(construida; no tiene digest de origen)* | PC-1 `openvpms-app` (`build: ./openvpms`) |
| `postgres:15.19` | `sha256:dfbbb0ad8cab91d41e99123664e37a9b25d0413426d4fb3154e4d668e5d35246` | PC-2 `pretix-db`, `inventree-db` |
| `redis:7.4.11` | `sha256:c6eabf748fc7a61dbb5a705c78bcf3d6377b1127a97d0ce965c11c44ba46896f` | PC-2 `pretix-redis`; PC-3 `erpnext-redis-cache`, `erpnext-redis-queue` |
| `pretix/standalone:stable` | `sha256:7f8c1b51f0b3e28f7c7a4245e85bcdfcd1e1bef76454dfc8314eda8f4ed596b3` | PC-2 `pretix-web` |
| `inventree/inventree:1.5.5` | `sha256:5dc64d7ceee39db7bd98bd4a8a2c6f95dcc7a3e0fc39c4c1ea1efe8ba1c83ea3` | PC-2 `inventree-app`, `inventree-worker` |
| `mariadb:10.6.28` | `sha256:40153feb479c0da88b5cfe3f50f44c91f7baf05a1b7bcc5beb7eb37a890a8f16` | PC-3 `erpnext-db` |
| `frappe/erpnext:v15.121.3` | `sha256:7b52acb52af9ac1721aa9922e06fab198e608bc748d3d3adae388aba364243fb` | PC-3 `erpnext-configurator`, `-create-site`, `-ldap-config`, `-backend`, `-websocket`, `-scheduler`, `-queue-short`, `-queue-long`, `-hr` |
| `osixia/openldap:1.5.0` | `sha256:18742e9c449c9c1afe129d3f2f3ee15fb34cc43e5f940a20f3399728f41d7c28` | PC-3 `openldap` |
| `internetsystemsconsortium/bind9:9.18` | `sha256:1ffb29c718ee2540c5643c1e8166629a07bbd505f99107baae535e9f86eb7eef` | PC-3 `dns` |
| `cturra/ntp:latest` | `sha256:7224d4e7c7833aabbcb7dd70c46c8a8dcccda365314c6db047b9b10403ace3bc` | PC-3 `ntp` |

Son **11 imágenes distintas** (10 descargadas + 1 construida) para 23 servicios. Solo hay que llevar cada una una vez.

### Lo que este documento NO puede dar todavía (y por qué)

- **Tamaños y sha256 de los `.tar`** y **versiones y sha256 de los `.deb`**: solo existen tras ejecutar `preparar-paquete-offline.sh`. No se inventan aquí: el script los escribe en `INVENTARIO.md` (legible) y `MANIFEST.sha256` (verificable) dentro del paquete, y el instalador comprueba el manifiesto antes de tocar nada.
- **Versiones de los `.deb`**: dependen de la fecha de preparación y de la versión de Ubuntu. Para reproducirlas, fijar `DOCKER_VERSION` (ver §5); la versión usada queda en `INVENTARIO.md`.
- Como orientación (no medido): `frappe/erpnext` y `pretix`/`inventree` son las más grandes (del orden de 1–2 GB cada una sin comprimir); OpenVPMS ronda los 300 MB según los runbooks. Cuenta con **varios GB** y con espacio para el paquete **y** para las imágenes cargadas en cada PC.

## 3. Cómo se usa

**En la máquina con Internet** (Docker sano, `git`, el repo con el commit que se va a llevar ya commiteado):

```bash
UBUNTU=22.04 ./scripts/preparar-paquete-offline.sh ./paquete-fase0
```

Descarga los `.deb` dentro de un contenedor `ubuntu:<UBUNTU>` (así se resuelven las dependencias de esa versión sin necesitar un Ubuntu igual), hace `pull` por digest de cada imagen, la etiqueta sin digest y la guarda con `docker save`; construye OpenVPMS; empaqueta el proyecto; escribe `PAQUETE.env`, `INVENTARIO.md` y `MANIFEST.sha256`. Copiar la carpeta `paquete-fase0/` entera al USB.

**En cada PC del laboratorio** (sin red):

```bash
cd /ruta/al/usb/paquete-fase0
sudo ./instalar.sh
```

Hace, y se detiene en el primer fallo: (1) compara Ubuntu y arquitectura con el paquete; (2) `sha256sum -c MANIFEST.sha256`; (3) instala Docker con `apt-get install --no-download ./debs/*.deb`; (4) `docker load` de cada imagen y comprueba su etiqueta; (5) extrae el proyecto en `~/UD.RedesCorporativaa.ProyectoFinak` (la ruta que asumen los tutoriales; `DESTINO=` la cambia) y escribe un `docker-compose.override.yml` en cada `docker/pcN-*/`.

Cada PC solo necesita las imágenes de su compose, pero el instalador carga **todas** (más simple, un solo USB, un solo procedimiento). Si el disco de un PC aprieta, ver "Mejoras posibles".

Después se sigue el tutorial del PC desde el paso de identificar la tarjeta de red. Los pasos "instalar Docker" y "dejar el proyecto en el PC" de los tutoriales pasan a ser este `sudo ./instalar.sh` (esa edición de `tutoriales/**` y `despliegue/**` corresponde a otra sesión: no está hecha aquí).

## 4. Decisiones y trampas (para no rehacer el análisis)

1. **Digest vs `docker load`.** Los compose fijan `imagen:tag@sha256:…`. Una imagen cargada con `docker load` no conserva el digest de origen, y Compose, al no encontrarla con ese digest, intenta descargarla → falla sin Internet. Por eso las imágenes se guardan **por etiqueta** y el instalador escribe un `docker-compose.override.yml` que sustituye `image:` por la etiqueta sin digest. Compose lee ese fichero solo, así que `deploy.sh` (que hace `docker compose up -d` a secas) no necesita cambios y `docker/**` tampoco. *Sin verificar:* si con el almacén `containerd` de Docker 29 el digest sí se resolviera solo, el override sobraría pero no estorba.
2. **`pull_policy: never`** en el override de todos los servicios descargados: si falta una imagen, el error es inmediato y claro en vez de un intento de red que cuelga. En `openvpms-app` **no** se pone (Compose lo trataría como imagen a construir y no se ha comprobado la interacción con `build:`); ahí basta con que la imagen exista con la etiqueta `reservaviva/openvpms-app:fase0`.
3. **OpenVPMS.** El servicio tiene `build:`; con `image:` añadido en el override, `docker compose up` usa la imagen local si existe y solo construye si falta. Si por cualquier motivo intentara construir, fallaría en `curl` del Dockerfile (sin Internet): la señal de que la imagen no se cargó.
4. **Plataforma.** Se descarga con `--platform linux/<ARQ>`. Los digests de los compose son (previsiblemente) de índices multi-arquitectura; si alguno fuera de otra plataforma, `docker pull` fallará con un mensaje claro. Suponer `amd64` **hasta confirmar** qué hardware tienen los PCs.
5. **Superconjunto de dependencias.** Los `.deb` se resuelven en un contenedor `ubuntu:<versión>` mínimo, que trae *menos* paquetes que un Ubuntu Server, así que se descarga de sobra (bien). El riesgo inverso: que el contenedor tenga una librería más nueva que la del PC y por eso no la incluya. Ver "Si falla".
6. **Descargas del build de OpenVPMS sin verificar.** `docker/pc1-medica/openvpms/Dockerfile` baja el zip de OpenVPMS y el driver JDBC con `curl` sin comprobar checksum. Recomendación para quien tenga `docker/**` (juan): añadir `sha256sum -c` a esas dos descargas. Aquí no se ha tocado.
7. **El `.tar` no es un digest.** El sha256 del `.tar` (en el manifiesto) garantiza que el USB no corrompió el fichero, no que la imagen sea la de origen; eso lo garantiza el `pull` por digest en el paso de preparación.

## 5. Variables del script de preparación

`UBUNTU` (obligatoria), `ARQ` (`amd64` por defecto), `DOCKER_VERSION` (opcional; p. ej. `5:27.5.1-1~ubuntu.22.04~jammy`, la cadena de `apt-cache madison docker-ce`), `PERMITIR_SUCIO=1` (permite armar con cambios sin commitear; el `proyecto.tar.gz` lleva solo lo commiteado).

## 6. Si falla (previsible, sin verificar)

| Síntoma | Causa probable | Qué hacer |
|---|---|---|
| Paso 1: "Este PC es Ubuntu X y el paquete es para Y" | `UBUNTU=` no coincidía con los PCs | Rehacer el paquete con la versión correcta. |
| Paso 2: falla el checksum | Copia incompleta al USB | Recopiar. No seguir. |
| Paso 3: `apt` protesta por dependencias/versiones | El PC ya trae una librería distinta a la del contenedor | Anotar el nombre exacto del paquete que pide; rehacer el paquete en un Ubuntu igual al PC (`ARQ`/`UBUNTU`) o añadir ese `.deb`. Último recurso: `sudo dpkg -i debs/*.deb`. **No** ejecutar `apt update`. |
| `docker compose up` intenta descargar | Falta el override o la etiqueta no coincide | `docker images` y comparar con la tabla del §2; revisar `docker-compose.override.yml`. |
| Paso 5: "ya existe" | Instalación previa | Moverla o usar `DESTINO=`. El script no borra nada. |

## 7. Mejoras posibles (no hechas)

- Cargar solo las imágenes del PC (argumento `pc1|pc2|pc3`) para ahorrar disco.
- `docker-compose.override.yml` no está en `.gitignore`; en el laboratorio no importa, pero en un clon de desarrollo aparecería como fichero sin seguir.
- Fijar por checksum las dos descargas del Dockerfile de OpenVPMS (ver §4.6).

## Registro de verificación

| Fecha | Quién | Qué se ejecutó | Resultado |
|---|---|---|---|
| — | — | *Nada aún: pendiente de Docker sano.* | — |

Lista mínima para cerrar la verificación: (a) ejecutar `preparar-paquete-offline.sh` de punta a punta; (b) VM Ubuntu Server de la versión real, **sin red** (`ip link set … down` o sin adaptador), `sudo ./instalar.sh`; (c) en cada `docker/pcN-*/`, `docker compose config --quiet` y `docker compose up -d` sin que aparezca ninguna descarga; (d) actualizar los tutoriales y los runbooks (los huecos "HUECO: comandos pendientes") con los comandos ya comprobados.
