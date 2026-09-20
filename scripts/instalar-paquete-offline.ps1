<#
.SYNOPSIS
  Instala en un PC del LABORATORIO (Windows con Docker Desktop, SIN Internet) el paquete de la Fase 0 que armo
  scripts/preparar-paquete-offline.sh. Se ejecuta UNA vez en cada PC, con su perfil.

.DESCRIPTION
  ============================================================================================
  NO VERIFICADO - pendiente de ejecutar con el motor Docker sano.
  Este script se escribio sin poder ejecutarlo (ni Docker ni un PC del laboratorio disponibles). Nada de
  lo de abajo se ha probado de extremo a extremo. Antes de fiarse de el, ejecutarlo en un PC de prueba
  sin red y anotar el resultado en docs/paquete-offline-fase0.md.
  ============================================================================================

  Pasos (se detiene en el primer fallo):
    1. Comprueba que Docker Desktop responde y que la arquitectura coincide con la del paquete.
    2. Verifica con Get-FileHash los ficheros del paquete que este perfil necesita (MANIFEST.sha256).
    3. docker load de las imagenes de este perfil y comprueba que cada etiqueta quedo cargada.
    4. Extrae el proyecto en Destino, copia los certificados del perfil y el docker-compose.override.yml.

  NO hace: descargar nada, docker pull, curl, git clone. NO despliega las aplicaciones ni escribe el .env:
  eso lo define el tutorial del PC (el despliegue en Windows esta en revision).

  Por que el override: los compose fijan las imagenes por digest (nombre:tag@sha256:...). Con el almacen
  de imagenes clasico, docker load no conserva ese digest y Compose intentaria descargar la imagen. El
  override (generado al preparar el paquete) las sustituye por su etiqueta sin digest y pone
  pull_policy: never. Con el almacen containerd sobra, pero no estorba.

.PARAMETER Perfil
  pc1 (Medica), pc2 (Operaciones) o pc3 (Administracion e infraestructura).

.PARAMETER Paquete
  Carpeta del paquete. Por defecto, la carpeta donde esta este script.

.PARAMETER Destino
  Donde dejar el proyecto. Por defecto: <perfil de usuario>\UD.RedesCorporativaa.ProyectoFinak.

.PARAMETER ConSimuladores
  Carga tambien la imagen nicolaka/netshoot (~900 MB) que usan los simuladores de despliegue/*/pruebas.

.EXAMPLE
  powershell -ExecutionPolicy Bypass -File .\instalar.ps1 -Perfil pc3
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)][ValidateSet('pc1', 'pc2', 'pc3')][string]$Perfil,
    [string]$Paquete = $PSScriptRoot,
    [string]$Destino = '',
    [switch]$ConSimuladores
)

# Los cmdlets abortan ante un error; los programas nativos (docker) no: en PowerShell 5.1, con
# ErrorActionPreference=Stop el stderr de un programa nativo se convierte en excepcion antes de poder mirar
# $LASTEXITCODE, que es lo que se comprueba despues de cada llamada a docker.
$ErrorActionPreference = 'Continue'
$PSDefaultParameterValues['*:ErrorAction'] = 'Stop'

function Paso($t)   { Write-Host ''; Write-Host "== $t ==" }
function Ok($t)     { Write-Host "  [OK]  $t" }
function Aviso($t)  { Write-Warning $t }
function Fallo($t)  { Write-Host "  [FALLO] $t" -ForegroundColor Red; exit 1 }

# Lee PAQUETE.env (CLAVE=valor)
$envFile = Join-Path $Paquete 'PAQUETE.env'
if (-not (Test-Path $envFile)) { Fallo "No encuentro ${envFile}: -Paquete no apunta a la carpeta del paquete." }
$cfg = @{}
Get-Content $envFile | ForEach-Object { if ($_ -match '^\s*([A-Za-z_]+)=(.*)$') { $cfg[$Matches[1]] = $Matches[2].Trim() } }
if ($Destino -eq '') { $Destino = Join-Path $HOME $cfg['NOMBRE_PROYECTO'] }

# --- 1. Docker y arquitectura ------------------------------------------------------------------
Paso "1/4 Comprobando Docker Desktop y el paquete (perfil $Perfil)"
& docker info *> $null
if ($LASTEXITCODE -ne 0) { Fallo "'docker info' falla: abre Docker Desktop, espera a que diga 'running' y repite." }
$arqDocker = (& docker info --format '{{.Architecture}}').Trim()
$arqNorm = switch ($arqDocker) { 'x86_64' { 'amd64' } 'aarch64' { 'arm64' } default { $arqDocker } }
if ($arqNorm -ne $cfg['ARQ_PAQUETE']) { Fallo "Este Docker es $arqNorm y el paquete es $($cfg['ARQ_PAQUETE']): hay que rehacer el paquete." }
Ok "Docker $(& docker --version); arquitectura $arqNorm; paquete del $($cfg['FECHA_PAQUETE']), commit $($cfg['COMMIT_PAQUETE'])"

# Imagenes de este perfil (INVENTARIO.tsv: etiqueta, origen, id, fichero, bytes, sha256, perfiles)
$imagenes = @()
foreach ($linea in Get-Content (Join-Path $Paquete 'imagenes\INVENTARIO.tsv')) {
    if ($linea -match '^\s*#' -or $linea.Trim() -eq '') { continue }
    $c = $linea -split "`t"
    $perfiles = $c[6] -split '\s+'
    if (($perfiles -contains $Perfil) -or ($ConSimuladores -and ($perfiles -contains 'simuladores'))) {
        $imagenes += [pscustomobject]@{ Etiqueta = $c[0]; Id = $c[2]; Fichero = $c[3] }
    }
}
if ($imagenes.Count -eq 0) { Fallo "El inventario no lista imagenes para $Perfil." }

# --- 2. Integridad (solo lo que este perfil necesita) ------------------------------------------
Paso "2/4 Verificando checksums de lo que necesita $Perfil (puede tardar: son varios GB)"
$necesarios = @('proyecto.zip', "overrides/", "certs/$Perfil/", 'imagenes/INVENTARIO.tsv', 'PAQUETE.env', 'instalar.ps1', 'INVENTARIO.md')
$ficherosImg = $imagenes | ForEach-Object { "imagenes/$($_.Fichero)" }
foreach ($linea in Get-Content (Join-Path $Paquete 'MANIFEST.sha256')) {
    if ($linea -notmatch '^([0-9a-f]{64})\s+\*?(.+)$') { continue }
    $esperado = $Matches[1]; $rel = $Matches[2]
    $quiero = ($ficherosImg -contains $rel) -or ($necesarios | Where-Object { $rel -eq $_ -or ($_.EndsWith('/') -and $rel.StartsWith($_)) })
    if (-not $quiero) { continue }
    $ruta = Join-Path $Paquete ($rel -replace '/', '\')
    if (-not (Test-Path $ruta)) { Fallo "Falta $rel en el paquete (copia incompleta del USB)." }
    $real = (Get-FileHash -Algorithm SHA256 -Path $ruta).Hash.ToLower()
    if ($real -ne $esperado) { Fallo "Checksum incorrecto en $rel (fichero corrupto): vuelve a copiarlo del origen." }
}
foreach ($f in $ficherosImg) { if (-not (Select-String -Path (Join-Path $Paquete 'MANIFEST.sha256') -SimpleMatch $f -Quiet)) { Fallo "$f no figura en MANIFEST.sha256." } }
Ok 'todos los ficheros coinciden con MANIFEST.sha256'

# --- 3. Imagenes -------------------------------------------------------------------------------
Paso "3/4 Cargando $($imagenes.Count) imagenes (docker load)"
foreach ($i in $imagenes) {
    Write-Host "  -> $($i.Etiqueta)"
    & docker load -i (Join-Path $Paquete "imagenes\$($i.Fichero)") | Out-Null
    if ($LASTEXITCODE -ne 0) { Fallo "docker load fallo con $($i.Fichero)." }
    & docker image inspect $i.Etiqueta *> $null
    if ($LASTEXITCODE -ne 0) { Fallo "Tras cargar $($i.Fichero) no existe la etiqueta $($i.Etiqueta)." }
    $idActual = (& docker image inspect --format '{{.Id}}' $i.Etiqueta).Trim()
    if ($idActual -ne $i.Id) { Aviso "$($i.Etiqueta): el ID ($idActual) difiere del registrado ($($i.Id)). Normal si el almacen de imagenes de este Docker no es el de la maquina que armo el paquete; los checksums del paso 2 ya validaron el contenido." }
}
Ok 'imagenes cargadas'

# --- 4. Proyecto, certificados y override ------------------------------------------------------
Paso "4/4 Dejando el proyecto en $Destino"
if (Test-Path $Destino) { Fallo "$Destino ya existe. No lo piso: muevelo o usa -Destino (si es una instalacion previa y quieres rehacerla, borrala tu a mano)." }
$padre = Split-Path $Destino -Parent
if (-not (Test-Path $padre)) { New-Item -ItemType Directory -Path $padre | Out-Null }
Expand-Archive -Path (Join-Path $Paquete 'proyecto.zip') -DestinationPath $padre
$extraido = Join-Path $padre $cfg['NOMBRE_PROYECTO']
if ($extraido -ne $Destino) { Move-Item $extraido $Destino }
$carpetaPc = Get-ChildItem (Join-Path $Destino 'docker') -Directory -Filter "$Perfil-*" | Select-Object -First 1
if (-not $carpetaPc) { Fallo "El proyecto no contiene docker\$Perfil-*." }

$certsDestino = Join-Path $carpetaPc.FullName 'certs'
New-Item -ItemType Directory -Path $certsDestino -Force | Out-Null
Copy-Item (Join-Path $Paquete "certs\$Perfil\*") $certsDestino -Force
Ok "certificados copiados a docker\$($carpetaPc.Name)\certs"

$overrideOrigen = Join-Path $Paquete "overrides\$($carpetaPc.Name).yml"
if (-not (Test-Path $overrideOrigen)) { Fallo "El paquete no trae overrides\$($carpetaPc.Name).yml." }
Copy-Item $overrideOrigen (Join-Path $carpetaPc.FullName 'docker-compose.override.yml')
Ok "docker-compose.override.yml escrito en docker\$($carpetaPc.Name)"

Paso 'Listo'
Write-Host "Proyecto en: $Destino"
Write-Host "Siguiente: el tutorial de este PC (despliegue en revision). Comprobacion sin red, en docker\$($carpetaPc.Name):"
Write-Host '   docker compose config --quiet; if ($?) { "compose-ok" }'
