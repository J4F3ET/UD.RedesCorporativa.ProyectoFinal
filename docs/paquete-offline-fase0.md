# Paquete offline de la Fase 0

> **NO VERIFICADO — pendiente de ejecutar con el motor Docker sano.**
> Los scripts y este documento se escribieron sin poder ejecutar Docker. Lo único comprobado: sintaxis de bash (`bash -n`) y de PowerShell (analizador del lenguaje), ASCII puro y LF, y que el analizador de compose (`preparar-paquete-offline.sh --listar`) extrae bien las imágenes de los tres compose reales (tabla de abajo). **Todo lo demás está sin ejecutar**: `docker pull/save/load`, el `build` de OpenVPMS, la generación de certificados dentro del script, `Expand-Archive`, y el comportamiento de los `docker-compose.override.yml`. Cuando se pruebe, anotar el resultado en "Registro de verificación".

**Situación (decidida por el usuario):** tres PCs **Windows físicos** con **Docker Desktop y WSL2 ya instalados**, cada uno con su propio motor Docker, y **sin Internet** en el laboratorio (habrá Internet limitado el primer día: el paquete completo es la hipótesis segura). Por eso el paquete **no lleva** `.deb`, ni instalador de Docker, ni `apt`. Se renuncia a VLAN 802.1Q y macvlan (Docker Desktop no las soporta); el despliegue en Windows lo define juan, y este paquete **no lo escribe**: deja el proyecto, las imágenes, los certificados y el override.

## 1. Qué contiene

Un **único paquete** para los tres PCs; en cada uno se ejecuta el instalador **con su perfil** y solo carga lo que ese PC necesita.

| Contenido | Ruta en el paquete | Nota |
|---|---|---|
| Imágenes, una por `.tar`, guardadas **por etiqueta** | `imagenes/*.tar`, `imagenes/INVENTARIO.tsv` | El TSV tiene una columna con los perfiles que usan cada imagen. |
| Imagen de OpenVPMS **ya construida** | `imagenes/reservaviva_openvpms-app_fase0.tar` | El compose usa `build:`; construirla exige Internet (release de OpenVPMS + driver JDBC). |
| Imagen de los simuladores | `imagenes/nicolaka_netshoot_fase0.tar` | Perfil `simuladores`, ~900 MB, solo con `-ConSimuladores`. |
| Override de cada PC | `overrides/pcN-<nombre>.yml` | Etiqueta sin digest + `pull_policy: never` (§4.1). |
| Certificados ya generados | `certs/pc1/`, `certs/pc2/`, `certs/pc3/` | CA **compartida** por los tres PCs; `ldap.crt/key` y `ca.key` solo en `pc3`. |
| El proyecto (`git archive` del commit) | `proyecto.zip` | Sin `.git`, sin `.env`, sin certs. |
| `instalar.ps1`, `PAQUETE.env`, `MANIFEST.sha256`, `INVENTARIO.md` | raíz | Los genera el script de preparación. |

## 2. Inventario de imágenes (leído de los compose y de los README de simuladores)

Extraído con `scripts/preparar-paquete-offline.sh --listar <compose>` (esa orden **sí se ejecutó**) y `git grep` de `nicolaka/netshoot@…` en `despliegue/`. El digest es el checksum esperado **del origen**.

| Etiqueta que queda en el PC | Digest fijado | PCs |
|---|---|---|
| `mysql:8.0.46` | `sha256:7dcddc01f13bab2f15cde676d44d01f61fc9f99fe7785e86196dfc07d358ae2b` | PC-1 |
| `reservaviva/openvpms-app:fase0` | *(construida; sin digest de origen)* | PC-1 |
| `postgres:15.19` | `sha256:dfbbb0ad8cab91d41e99123664e37a9b25d0413426d4fb3154e4d668e5d35246` | PC-2 |
| `redis:7.4.11` | `sha256:c6eabf748fc7a61dbb5a705c78bcf3d6377b1127a97d0ce965c11c44ba46896f` | PC-2, PC-3 |
| `pretix/standalone:stable` | `sha256:7f8c1b51f0b3e28f7c7a4245e85bcdfcd1e1bef76454dfc8314eda8f4ed596b3` | PC-2 |
| `inventree/inventree:1.5.5` | `sha256:5dc64d7ceee39db7bd98bd4a8a2c6f95dcc7a3e0fc39c4c1ea1efe8ba1c83ea3` | PC-2 |
| `mariadb:10.6.28` | `sha256:40153feb479c0da88b5cfe3f50f44c91f7baf05a1b7bcc5beb7eb37a890a8f16` | PC-3 |
| `frappe/erpnext:v15.121.3` | `sha256:7b52acb52af9ac1721aa9922e06fab198e608bc748d3d3adae388aba364243fb` | PC-3 |
| `osixia/openldap:1.5.0` | `sha256:18742e9c449c9c1afe129d3f2f3ee15fb34cc43e5f940a20f3399728f41d7c28` | PC-3 |
| `internetsystemsconsortium/bind9:9.18` | `sha256:1ffb29c718ee2540c5643c1e8166629a07bbd505f99107baae535e9f86eb7eef` | PC-3 |
| `cturra/ntp:latest` | `sha256:7224d4e7c7833aabbcb7dd70c46c8a8dcccda365314c6db047b9b10403ace3bc` | PC-3 |
| `nicolaka/netshoot:fase0` | `sha256:b09d9b21381f47a79b3cbcb30da25266dc17186ea00ae65e99fdc51396f48e70` | simuladores |

**12 imágenes** (10 descargadas de los compose + OpenVPMS construida + netshoot). Por PC: PC-1 = 2 servicios / 2 imágenes; PC-2 = 6 servicios / 4 imágenes; PC-3 = 15 servicios / 6 imágenes. Se cargan una sola vez por PC aunque varios servicios la compartan.

**No están aquí y por qué:** tamaños y sha256 de los `.tar` solo existen tras ejecutar la preparación; el script los escribe en `INVENTARIO.md` y `MANIFEST.sha256`, y el instalador los comprueba antes de cargar. Orientación no medida: `frappe/erpnext`, `pretix` e `inventree` son las mayores (~1–2 GB); OpenVPMS ~300 MB; netshoot ~900 MB.

## 3. Cómo se usa

**Máquina con Internet** (Git Bash o Linux, Docker sano, `git`, `openssl`, commit ya hecho):

```bash
./scripts/preparar-paquete-offline.sh ./paquete-fase0      # ARQ=amd64 por defecto
```

Lee las imágenes de los compose, hace `pull` por digest, las etiqueta sin digest y las guarda; construye OpenVPMS; genera los certificados (en una copia temporal del commit, sin tocar tus `certs/`); empaqueta el proyecto y escribe `INVENTARIO.md` y `MANIFEST.sha256`. Copiar `paquete-fase0/` entera al USB.

**En cada PC** (PowerShell, sin red):

```powershell
powershell -ExecutionPolicy Bypass -File .\instalar.ps1 -Perfil pc1      # o pc2, pc3; -ConSimuladores si hace falta netshoot
```

Hace, y se detiene en el primer fallo: (1) Docker Desktop responde y la arquitectura coincide; (2) `Get-FileHash` de lo que necesita ese perfil contra `MANIFEST.sha256`; (3) `docker load` de sus imágenes y comprobación de etiquetas; (4) extrae el proyecto en `%USERPROFILE%\UD.RedesCorporativaa.ProyectoFinak` (`-Destino` lo cambia), copia los certificados del perfil y el `docker-compose.override.yml` en `docker\pcN-*\`. **No despliega ni escribe `.env`.**

**Un paquete y no tres:** un USB, un manifiesto, una preparación (lo caro y lo que hay que verificar), imágenes compartidas guardadas una vez; el coste (algo más de USB) es irrelevante.

## 4. Decisiones y trampas

1. **Digest vs `docker load`.** Los compose fijan `imagen:tag@sha256:…`. Con el almacén **clásico**, `docker load` no conserva el digest y Compose intentaría descargar. Con el almacén **containerd** (el de la máquina de preparación: Docker 29.8.0) el digest del manifiesto sí se conserva y la referencia debería resolverse sola. No se sabe cuál usan los PCs del laboratorio (un Docker Desktop antiguo usa el clásico), así que **se mantiene el override**: cubre ambos casos y no estorba.
2. **El override no llega al arnés.** `pruebas/smoke-test-3-pcs` carga los compose con `include:` y una lista explícita de ficheros; ese `include` **no lee** el `docker-compose.override.yml` automático. Si el despliegue en Windows usa el arnés, hay que añadir `overrides/<pc>.yml` a la lista del `include` (o generar un override propio del arnés). **Pendiente de la decisión de juan.**
3. **Simuladores con `docker run nicolaka/netshoot@sha256:…`.** Los README de `despliegue/*/pruebas/` citan la imagen **por digest**. Con el almacén containerd resuelve; con el clásico no y `docker run` intentaría descargar: usar entonces `nicolaka/netshoot:fase0` (la etiqueta local). No se tocan esos README (`despliegue/**` no es de esta sesión).
4. **Certificados: condición de la que depende que valgan.** El `ldap.crt` lleva en el SAN `DNS:ldap.reservaviva.local`, `openldap`, `localhost` y `IP:<LDAP_IP>` (por defecto 10.10.99.10). Los clientes (InvenTree y ERPNext) se conectan a `ldaps://ldap.reservaviva.local:636`, que resuelven con `extra_hosts`: la verificación TLS valida el **nombre**, no la IP, así que el certificado vale para **cualquier IP** que acabe teniendo PC-3. **Requisito explícito: los clientes deben seguir conectándose por nombre.** Si alguien cambia un cliente a `ldaps://<ip>`, la verificación falla salvo que esa IP sea la del SAN; habría que preparar el paquete con `LDAP_IP=<ip>`. Como la CA es la misma en los tres PCs, ya no hace falta el `scp` de `ca.crt` entre PCs.
5. **`pull_policy: never`** en el override de todos los servicios descargados: si falta una imagen, error inmediato en vez de intento de red. En `openvpms-app` no se pone (no se ha comprobado su interacción con `build:`); ahí basta con que exista `reservaviva/openvpms-app:fase0`.
6. **OpenVPMS.** Con `image:` + `build:` en el override, `docker compose up` usa la imagen local y solo construye si falta. Si intentara construir, fallaría en el `curl` del Dockerfile (sin Internet): señal de que la imagen no se cargó.
7. **Descargas del build de OpenVPMS sin verificar.** El Dockerfile baja el zip de OpenVPMS y el driver JDBC con `curl` sin checksum. Recomendación para quien tenga `docker/**` (juan): añadir `sha256sum -c`.
8. **Plataforma.** `--platform linux/amd64` por defecto; el motor de Docker Desktop es Linux (WSL2). El instalador falla si la arquitectura del PC no coincide con la del paquete.
9. **`git archive` y finales de línea.** Se ejecuta con `core.autocrlf=false` para que los `.sh` del zip conserven LF (si no, fallarían con `\r` en Git Bash/WSL). Sin verificar.
10. **El `.tar` no es un digest.** El sha256 del `.tar` protege del USB, no del origen; el origen lo protege el `pull` por digest de la preparación.
11. **PowerShell 5.1.** El instalador está en ASCII puro (sin acentos) para que la codificación no importe y usa `ErrorActionPreference=Continue` para los programas nativos, porque con `Stop` el stderr de `docker` aborta antes de mirar el código de salida.

## 5. Si falla (previsible, sin verificar)

| Síntoma | Causa probable | Qué hacer |
|---|---|---|
| "Este Docker es X y el paquete es Y" | Arquitectura distinta | Rehacer con `ARQ=`. |
| "Checksum incorrecto" / "Falta …" | Copia incompleta al USB | Recopiar. No seguir. |
| `docker load` falla | Disco lleno (Docker Desktop guarda en su disco virtual) | Liberar espacio; ver tamaños en `INVENTARIO.md`. |
| `docker compose up` intenta descargar | Falta el override o la etiqueta no coincide | `docker images`, comparar con §2; revisar `docker-compose.override.yml`. |
| "ya existe" en el paso 4 | Instalación previa | Moverla o `-Destino`. El script no borra nada. |
| `Expand-Archive` con rutas raras | Zip con `/` en PowerShell 5.1 | Extraer con `tar -xf proyecto.zip` (Windows 10+). |

## 6. Mejoras posibles (no hechas)

- `docker-compose.override.yml` no está en `.gitignore` (irrelevante en el laboratorio).
- Checksums para las dos descargas del Dockerfile de OpenVPMS (ver 4.7).
- Escribir el `.env` de cada PC (IP de PC-3, contraseñas) desde el instalador, cuando juan cierre cómo se parametriza.

## Registro de verificación

| Fecha | Quién | Qué se ejecutó | Resultado |
|---|---|---|---|
| — | — | *Nada aún: pendiente de Docker sano.* | — |

Lista mínima para cerrar la verificación: (a) `docker info -f '{{.DriverStatus}}'` en los PCs para saber el almacén; (b) ejecutar `preparar-paquete-offline.sh` de punta a punta; (c) en un PC **sin red**, `instalar.ps1 -Perfil pcN`, luego `docker compose config --quiet` y `up -d` sin ninguna descarga; (d) repetir en un Docker Desktop con almacén clásico si existe uno; (e) actualizar tutoriales y runbooks (los "HUECO: comandos pendientes", hoy escritos para Ubuntu) con los comandos comprobados.
