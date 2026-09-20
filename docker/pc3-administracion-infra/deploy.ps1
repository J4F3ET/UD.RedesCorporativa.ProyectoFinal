# Un solo comando para dejar arriba PC-3 (Administracion e Infraestructura: ERPNext + OpenLDAP + bind9 + NTP) en
# Windows con Docker Desktop. Sustituye a deploy.sh (que es bash/sudo/VLAN y queda como anexo de diseno).
#
# Uso (PowerShell, desde esta carpeta):   powershell -ExecutionPolicy Bypass -File .\deploy.ps1
#   -TimeoutMinutos N   maximo de espera a que todo este sano (por defecto 30; el primer arranque tarda ~15 min)
# Idempotente: se puede repetir. Falla con codigo 1 y un mensaje claro si algo no esta bien.
# Hace: valida .env y certificados -> genera la zona DNS con las IP LAN -> docker compose up -d --pull never ->
#       espera a que todo este sano. No descarga nada (el laboratorio no tiene Internet): las imagenes vienen en el paquete.
# NO VERIFICADO: escrito sin poder ejecutarlo (Docker no disponible). Solo ASCII a proposito (PowerShell 5.1).
param([int]$TimeoutMinutos = 30)
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

try {
    $cfg = Leer-DotEnv (Join-Path $PSScriptRoot '.env')
    Exigir-Variables $cfg @('LDAP_ADMIN_PASSWORD', 'ERPNEXT_DB_ROOT_PASSWORD', 'ERPNEXT_ADMIN_PASSWORD', 'ERPNEXT_LDAP_BIND_PASSWORD', 'IP_PC1', 'IP_PC2', 'IP_PC3') @('IP_PC1', 'IP_PC2', 'IP_PC3')
    Docker-Listo
    # LDAPS: los tres archivos los monta el compose (los entrega el paquete de la Fase 0, ya generados).
    Exigir-Certificado 'certs\ca.crt' 'CERTIFICATE'
    Exigir-Certificado 'certs\ldap.crt' 'CERTIFICATE'
    Exigir-Certificado 'certs\ldap.key' '(RSA |EC )?PRIVATE KEY'

    # Zona DNS: la plantilla lleva marcadores; se sustituyen con las IP LAN de los tres PC.
    $zona = 'bind\zones\db.reservaviva.local'
    $antes = ''
    if (Test-Path -LiteralPath $zona) { $antes = (Get-Content -LiteralPath $zona | Where-Object { $_ -notmatch 'serial' }) -join "`n" }
    & (Join-Path $PSScriptRoot 'bind\generar-zona.ps1') -IpPc1 $cfg['IP_PC1'] -IpPc2 $cfg['IP_PC2'] -IpPc3 $cfg['IP_PC3']
    $despues = (Get-Content -LiteralPath $zona | Where-Object { $_ -notmatch 'serial' }) -join "`n"

    & docker compose up -d --pull never
    if ($LASTEXITCODE -ne 0) { Fallar "docker compose up -d fallo (codigo $LASTEXITCODE)." }
    # bind9 no relee la zona si el contenedor ya estaba en marcha: se reinicia solo si cambio el contenido.
    if ($antes -ne '' -and $antes -ne $despues) {
        Write-Host "La zona DNS cambio: reiniciando dns."
        & docker compose restart dns
        if ($LASTEXITCODE -ne 0) { Fallar "No se pudo reiniciar dns." }
    }

    Esperar-Contenedores `
        @('erpnext-db', 'erpnext-redis-cache', 'erpnext-redis-queue', 'erpnext-backend', 'erpnext-websocket', 'erpnext-scheduler',
          'erpnext-queue-short', 'erpnext-queue-long', 'erpnext-hr', 'openldap', 'dns-interno', 'ntp-interno') `
        @('erpnext-configurator', 'erpnext-create-site', 'erpnext-ldap-config') `
        $TimeoutMinutos
    & docker compose ps
    Write-Host ("PC-3 listo. ERPNext: http://{0}:{1}  |  LDAPS: {0}:636" -f $cfg['IP_PC3'], (Puerto $cfg 'ERPNEXT_PORT' '8080'))
    exit 0
} catch {
    Write-Host "ERROR: $($_.Exception.Message)" -ForegroundColor Red
    exit 1
}
