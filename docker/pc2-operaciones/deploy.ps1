# Un solo comando para dejar arriba PC-2 (Operaciones: Pretix + InvenTree) en Windows con Docker Desktop.
# Sustituye a deploy.sh (bash/sudo/VLAN, que queda como anexo de diseno).
#
# Uso (PowerShell, desde esta carpeta):   powershell -ExecutionPolicy Bypass -File .\deploy.ps1
#   -SoloAdmins         solo reintenta crear el administrador de Pretix (no toca contenedores)
#   -TimeoutMinutos N   maximo de espera a que todo este sano (por defecto 30; el primer arranque tarda ~15 min)
# Idempotente: se puede repetir. Falla con codigo 1 y un mensaje claro si algo no esta bien.
# Hace: valida .env y ca.crt -> docker compose up -d --pull never -> espera a que este sano -> crea el administrador de
# Pretix y ELIMINA el admin@localhost con clave "admin" que Pretix trae por defecto (credenciales publicas). Si ese
# paso falla, el script FALLA: no se deja Pretix con credenciales conocidas publicado en la LAN.
# No descarga nada (el laboratorio no tiene Internet): las imagenes vienen en el paquete.
# NO VERIFICADO: escrito sin poder ejecutarlo (Docker no disponible). Solo ASCII a proposito (PowerShell 5.1).
param([switch]$SoloAdmins, [int]$TimeoutMinutos = 30)
$ErrorActionPreference = 'Stop'
Set-Location -LiteralPath $PSScriptRoot

# ---- Funciones comunes (copia identica en los deploy.ps1 de los tres PC; se duplican para que cada PC sea autonomo) ----
function Fallar([string]$msg) { throw $msg }

function Leer-DotEnv([string]$ruta) {
    if (-not (Test-Path -LiteralPath $ruta -PathType Leaf)) {
        Fallar "Falta .env en $(Split-Path $ruta -Parent). Copia .env.example a .env y sustituye los valores (IP reales y contrasenas)."
    }
    $h = @{}
    foreach ($linea in Get-Content -LiteralPath $ruta -Encoding UTF8) {
        $l = $linea.Trim()
        if ($l -eq '' -or $l.StartsWith('#')) { continue }
        $i = $l.IndexOf('=')
        if ($i -lt 1) { continue }
        $h[$l.Substring(0, $i).Trim()] = $l.Substring($i + 1).Trim().Trim('"').Trim("'")
    }
    return $h
}

function Exigir-Variables($env_, [string[]]$nombres, [string[]]$ips) {
    $errores = @()
    foreach ($n in $nombres) {
        $v = $env_[$n]
        if ([string]::IsNullOrWhiteSpace($v)) { $errores += "$n esta vacia o no existe en .env" }
        elseif ($v -match 'SUSTITUIR') { $errores += "$n todavia tiene el valor de ejemplo ($v): sustituyelo" }
    }
    foreach ($n in $ips) {
        $v = $env_[$n]
        if ($v -and $v -notmatch 'SUSTITUIR' -and ($v -notmatch '^(\d{1,3})\.(\d{1,3})\.(\d{1,3})\.(\d{1,3})$' -or ($Matches[1..4] | Where-Object { [int]$_ -gt 255 }))) {
            $errores += "$n no es una IPv4 valida: '$v'"
        }
    }
    if ($errores.Count -gt 0) { Fallar ("Configuracion invalida en .env:`n  - " + ($errores -join "`n  - ")) }
}

function Docker-Listo {
    & docker info *> $null
    if ($LASTEXITCODE -ne 0) { Fallar "Docker no responde. Abre Docker Desktop, espera a que diga 'running' y vuelve a lanzar este script." }
}

# Un archivo montado por el compose debe existir como ARCHIVO con contenido. Si Docker ya lo creo como directorio
# (resto de un arranque anterior sin el archivo), se elimina si esta vacio.
function Exigir-Certificado([string]$ruta, [string]$tipo) {
    if (Test-Path -LiteralPath $ruta -PathType Container) {
        if ((Get-ChildItem -LiteralPath $ruta -Force | Measure-Object).Count -eq 0) { Remove-Item -LiteralPath $ruta -Force }
        else { Fallar "$ruta es un directorio con contenido; deberia ser un archivo." }
    }
    if (-not (Test-Path -LiteralPath $ruta -PathType Leaf) -or (Get-Item -LiteralPath $ruta).Length -eq 0) {
        Fallar "Falta $ruta. Lo entrega el paquete de instalacion (Fase 0); sin el no hay LDAPS y Docker crearia un directorio vacio en su lugar."
    }
    $txt = Get-Content -LiteralPath $ruta -Raw
    if ($txt -notmatch "BEGIN $tipo") { Fallar "$ruta no parece un PEM de tipo '$tipo'." }
}

# Espera a que cada contenedor este listo: "running" (y "healthy" si tiene healthcheck). Los jobs de un solo uso
# deben haber terminado con codigo 0. Falla si uno sale con error, se reinicia en bucle o se agota el tiempo.
function Esperar-Contenedores([string[]]$servicios, [string[]]$jobs, [int]$minutos) {
    $fin = (Get-Date).AddMinutes($minutos)
    $pendientes = @($servicios + $jobs)
    Write-Host "Esperando a que arranquen: $($pendientes -join ', ') (maximo $minutos min; el primer arranque puede tardar ~15 min)"
    while ($true) {
        $faltan = @()
        foreach ($c in $pendientes) {
            $r = & docker inspect -f '{{.State.Status}}|{{.State.ExitCode}}|{{if .State.Health}}{{.State.Health.Status}}{{end}}' $c 2>$null
            if ($LASTEXITCODE -ne 0) { $faltan += "$c (no existe)"; continue }
            $estado, $codigo, $salud = $r.Trim().Split('|')
            if ($jobs -contains $c) {
                if ($estado -eq 'exited' -and $codigo -eq '0') { continue }
                if ($estado -eq 'exited') { Fallar "El job $c termino con error (codigo $codigo). Mira: docker logs $c" }
                $faltan += "$c ($estado)"
            } else {
                if ($estado -eq 'exited' -or $estado -eq 'dead') { Fallar "$c se ha detenido (codigo $codigo). Mira: docker logs $c" }
                if ($estado -eq 'restarting') { $faltan += "$c (reiniciando)"; continue }
                if ($estado -ne 'running') { $faltan += "$c ($estado)"; continue }
                if ($salud -eq 'unhealthy') { $faltan += "$c (unhealthy)"; continue }
                if ($salud -eq 'starting') { $faltan += "$c (arrancando)"; continue }
            }
        }
        if ($faltan.Count -eq 0) { Write-Host "Todos los contenedores estan listos."; return }
        if ((Get-Date) -gt $fin) { Fallar "Tiempo agotado. Aun no estan listos: $($faltan -join ', ')" }
        Start-Sleep -Seconds 10
    }
}


function Puerto($cfg, [string]$nombre, [string]$defecto) {
    if ($cfg[$nombre]) { return $cfg[$nombre] } else { return $defecto }
}

# Equivale a init_admins de deploy.sh. Pretix no permite crear el superusuario por variables de entorno, asi que se
# espera a que su primer arranque termine las migraciones y se hace por "pretix shell". InvenTree crea el suyo solo
# (INVENTREE_ADMIN_* en el compose).
function Crear-AdminPretix($cfg) {
    $email = $cfg['PRETIX_ADMIN_EMAIL']
    if ($email.ToLower() -eq 'admin@localhost') { Fallar "PRETIX_ADMIN_EMAIL no puede ser admin@localhost: es el usuario por defecto de Pretix, con clave publica." }
    $py = @'
import os
from pretix.base.models import User
email = os.environ["ADM_EMAIL"]
if not User.objects.filter(email__iexact=email).exists():
    User.objects.create_superuser(email, os.environ["ADM_PASS"])
    print("ADMIN_CREADO")
# Pretix trae por defecto admin@localhost con clave "admin": se elimina.
User.objects.filter(email="admin@localhost").delete()
# Comprobacion final: el usuario existe y el de por defecto ya no.
if User.objects.filter(email__iexact=email).exists() and not User.objects.filter(email="admin@localhost").exists():
    print("ADMIN_OK")
'@
    Write-Host "Esperando a Pretix para crear su administrador (primer arranque: ~10 min)..."
    for ($i = 0; $i -lt 120; $i++) {
        $salida = $py | & docker exec -i -e "ADM_EMAIL=$email" -e "ADM_PASS=$($cfg['PRETIX_ADMIN_PASSWORD'])" pretix-web python -m pretix shell 2>$null
        if ($LASTEXITCODE -eq 0 -and ($salida -join "`n") -match 'ADMIN_OK') {
            Write-Host "Administrador de Pretix listo: $email (admin@localhost eliminado)."
            return
        }
        Start-Sleep -Seconds 10
    }
    Fallar "Pretix no quedo listo o no se pudo crear el administrador / eliminar admin@localhost. Reintenta: .\deploy.ps1 -SoloAdmins. NO dejes Pretix expuesto hasta entonces."
}

try {
    $cfg = Leer-DotEnv (Join-Path $PSScriptRoot '.env')
    Exigir-Variables $cfg @('PRETIX_DB_PASSWORD', 'INVENTREE_DB_PASSWORD', 'INVENTREE_ADMIN_PASSWORD', 'INVENTREE_LDAP_BIND_PASSWORD', 'PRETIX_ADMIN_EMAIL', 'PRETIX_ADMIN_PASSWORD', 'IP_PC2', 'IP_PC3') @('IP_PC2', 'IP_PC3')
    Docker-Listo
    if ($SoloAdmins) { Crear-AdminPretix $cfg; exit 0 }

    # ca.crt (CA interna de LDAPS) lo entrega el paquete; el compose lo monta como ARCHIVO.
    Exigir-Certificado 'certs\ca.crt' 'CERTIFICATE'

    & docker compose up -d --pull never
    if ($LASTEXITCODE -ne 0) { Fallar "docker compose up -d fallo (codigo $LASTEXITCODE)." }
    Esperar-Contenedores @('pretix-db', 'pretix-redis', 'pretix-web', 'inventree-db', 'inventree-app', 'inventree-worker') @() $TimeoutMinutos
    Crear-AdminPretix $cfg
    & docker compose ps
    Write-Host ("PC-2 listo. Pretix: http://{0}:{1}  |  InvenTree: http://{0}:{2}" -f $cfg['IP_PC2'], (Puerto $cfg 'PRETIX_PORT' '80'), (Puerto $cfg 'INVENTREE_PORT' '8000'))
    exit 0
} catch {
    Write-Host "ERROR: $($_.Exception.Message)" -ForegroundColor Red
    exit 1
}
