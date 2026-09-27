# levantar-sistema.ps1 - Lanzador para Windows de levantar-sistema.sh (arquitectura completa en UN solo host).
#
#   .\levantar-sistema.ps1                  # prepara y levanta los 26 servicios (modo local)
#   .\levantar-sistema.ps1 estado           # estado y direcciones de acceso
#   .\levantar-sistema.ps1 verificar        # segmentacion, DNS, NTP y LDAP
#   .\levantar-sistema.ps1 detener          # para todo sin borrar datos
#   .\levantar-sistema.ps1 borrar           # borra contenedores Y datos (pide confirmacion)
#   .\levantar-sistema.ps1 -Intranet        # modo intranet: proxy web (80) y DNS (53) en la IP de la LAN
#   Opciones: -Distro <nombre WSL>  -Forzar  -Rapido  -Si  -TimeoutMin <min>  -Intranet  -IP <X.X.X.X>
#   El modo intranet necesita preparar Windows UNA vez (como administrador): sistema\habilitar-intranet-windows.ps1.
#   Sin -Intranet, "arrancar" vuelve al modo local (todo en 127.0.0.1). Detalle: docs\operacion.md, "Acceso desde la LAN".
#
# Si PowerShell no deja ejecutar scripts, usa levantar-sistema.cmd (doble clic) o:
#   powershell -ExecutionPolicy Bypass -File .\levantar-sistema.ps1
#
# Elige solo donde ejecutar levantar-sistema.sh:
#   1. Docker Desktop en marcha -> con el bash de Git for Windows (el que viene con git).
#   2. Si no, una distro de WSL con Docker Engine -> dentro de WSL. En este modo deja un proceso en segundo plano
#      ("reservaviva-keepalive") que mantiene abierta la sesion de WSL: sin el, al cerrarse la ultima sesion Docker se
#      detiene y se lleva los contenedores (medido el 20/09/2026). "detener" y "borrar" lo terminan.
#
# Solo ASCII a proposito: PowerShell 5.1 lee mal UTF-8 sin BOM.

param(
    [Parameter(Position = 0)]
    [ValidateSet('arrancar', 'preparar', 'estado', 'verificar', 'detener', 'borrar', 'ayuda')]
    [string]$Accion = 'arrancar',
    [string]$Distro = '',
    [switch]$Forzar,
    [switch]$Rapido,
    [switch]$Si,
    [int]$TimeoutMin = 45,
    [switch]$Intranet,
    [string]$IP = ''
)

# 'Continue' y no 'Stop': en PowerShell 5.1 cualquier linea que un ejecutable nativo escriba en stderr (wsl.exe avisa, por
# ejemplo, "Failed to start the systemd user session") se convertiria en error terminante. Los fallos se miran por codigo.
$ErrorActionPreference = 'Continue'
$Repo = $PSScriptRoot
$Marca = 'reservaviva-keepalive'
# Coste medido en el host: ~5,7 GB para los 25 servicios previos al proxy web (nginx, unos MB), mas 1,2 GB de margen para que Windows siga respondiendo.
$MinLibreGB = 6.9

function Paso([string]$t) { Write-Host ''; Write-Host "==> $t" }
function Info([string]$t) { Write-Host "    $t" }
function Fallo([string]$t) { Write-Host ''; Write-Host "ERROR: $t" -ForegroundColor Red; exit 1 }

if ($Accion -eq 'ayuda') { Get-Content -LiteralPath $PSCommandPath -TotalCount 22 | ForEach-Object { $_ -replace '^# ?', '' }; exit 0 }

# Argumentos para levantar-sistema.sh
$ArgsSh = @($Accion)
if ($Forzar) { $ArgsSh += '--forzar' }
if ($Rapido) { $ArgsSh += '--rapido' }
if ($Si) { $ArgsSh += '--si' }
if ($TimeoutMin -ne 45) { $ArgsSh += @('--timeout', "$TimeoutMin") }
if ($IP -and -not $Intranet) { Fallo '-IP solo tiene sentido con -Intranet.' }
if ($Intranet -and $Accion -notin @('arrancar', 'preparar')) { Fallo "-Intranet solo se usa con arrancar o preparar; $Accion detecta solo el modo en que esta publicado el sistema." }

function Probar-DockerDesktop {
    if (-not (Get-Command docker -ErrorAction SilentlyContinue)) { return $false }
    try { $so = & docker info --format '{{.OperatingSystem}}' 2>$null } catch { return $false }
    return ($LASTEXITCODE -eq 0 -and "$so" -match 'Docker Desktop')
}

function Buscar-GitBash {
    $candidatos = @()
    $git = Get-Command git -ErrorAction SilentlyContinue
    if ($git) {
        # ...\Git\cmd\git.exe o ...\Git\mingw64\bin\git.exe -> ...\Git\bin\bash.exe
        $d = Split-Path -Parent $git.Source
        $candidatos += (Join-Path (Split-Path -Parent $d) 'bin\bash.exe')
        $candidatos += (Join-Path (Split-Path -Parent (Split-Path -Parent $d)) 'bin\bash.exe')
    }
    $candidatos += (Join-Path $env:ProgramFiles 'Git\bin\bash.exe')
    foreach ($c in $candidatos) { if ($c -and (Test-Path -LiteralPath $c -PathType Leaf)) { return $c } }
    return $null
}

function Listar-Distros {
    # wsl.exe -l -q escribe en UTF-16 con caracteres nulos: se limpian.
    $l = & wsl.exe -l -q 2>$null
    if ($LASTEXITCODE -ne 0) { return @() }
    return @($l | ForEach-Object { ($_ -replace "`0", '').Trim() } | Where-Object { $_ -and $_ -notmatch '^docker-desktop' })
}

function Probar-DockerEnWsl([string]$d) {
    $so = & wsl.exe -d $d -- docker info --format '{{.OperatingSystem}}' 2>$null
    return ($LASTEXITCODE -eq 0 -and "$so".Trim() -ne '')
}

function Sesion-Viva([string]$d) {
    & wsl.exe -d $d -- pgrep -f $Marca 2>$null | Out-Null
    return ($LASTEXITCODE -eq 0)
}

function Abrir-Sesion([string]$d) {
    if (Sesion-Viva $d) { Info "Sesion de WSL ya mantenida ($Marca)."; return }
    # El nombre de la distro va SIN comillas: con -d "Ubuntu-24.04" el wsl.exe oculto sale al instante con -1 (probado).
    # Los nombres de distro de WSL no admiten espacios, asi que no hacen falta.
    $p = Start-Process -FilePath 'wsl.exe' -WindowStyle Hidden -PassThru -ArgumentList "-d $d -- bash -c `"exec -a $Marca sleep infinity`""
    $viva = $false
    for ($i = 0; $i -lt 10 -and -not $viva; $i++) { Start-Sleep -Seconds 1; $viva = Sesion-Viva $d }
    if (-not $viva) { Fallo "No se pudo abrir la sesion de WSL que mantiene Docker vivo (wsl.exe salio con $(if ($p.HasExited) { $p.ExitCode } else { 'nada' }))." }
    Info "Sesion de WSL mantenida en segundo plano ($Marca): los contenedores siguen vivos aunque cierres esta ventana."
}

function Cerrar-Sesion([string]$d) {
    if (Sesion-Viva $d) {
        & wsl.exe -d $d -- pkill -f $Marca 2>$null | Out-Null
        Info "Sesion de WSL en segundo plano terminada."
    }
}

function Comprobar-MemoriaHost {
    $os = Get-CimInstance Win32_OperatingSystem
    $libre = [math]::Round($os.FreePhysicalMemory / 1MB, 2)
    Info "Memoria libre en Windows: $libre GB (recomendado: $MinLibreGB GB o mas)"
    if ($libre -lt $MinLibreGB) {
        $msg = "Solo hay $libre GB libres. Los servicios consumen ~5,7 GB en el host; con menos, Windows empieza a paginar y el arranque puede fallar. Cierra navegadores y aplicaciones y repite."
        if ($Forzar) { Write-Host "    AVISO: $msg Se continua por -Forzar." -ForegroundColor Yellow }
        else { Fallo "$msg O usa -Forzar para intentarlo igualmente." }
    }
}

# --- Modo intranet: lo que solo se ve desde Windows -----------------------------------------------------------------

# IP de la LAN: la de la interfaz con la ruta por defecto de menor metrica (la de Windows, no la de WSL con red NAT).
function Detectar-IPLan {
    $r = Get-NetRoute -AddressFamily IPv4 -DestinationPrefix '0.0.0.0/0' -ErrorAction SilentlyContinue | ForEach-Object {
        $i = Get-NetIPInterface -AddressFamily IPv4 -InterfaceIndex $_.ifIndex -ErrorAction SilentlyContinue
        [pscustomobject]@{ Idx = $_.ifIndex; Alias = $_.InterfaceAlias; M = $_.RouteMetric + $i.InterfaceMetric }
    } | Sort-Object M | Select-Object -First 1
    if (-not $r) { return $null }
    $a = Get-NetIPAddress -AddressFamily IPv4 -InterfaceIndex $r.Idx -ErrorAction SilentlyContinue | Where-Object { $_.IPAddress -notlike '169.254.*' } | Select-Object -First 1
    if ($a) { return [pscustomobject]@{ IP = $a.IPAddress; Alias = $r.Alias } }
    return $null
}

# Quien tiene un puerto en Windows en esa IP o en todas (0.0.0.0 / ::). Con WSL en modo mirrored, Linux no puede tomar
# un puerto que ya tiene Windows: es la causa mas probable de que el DNS no pueda publicarse en el 53.
function Describir-Proceso([int]$ProcId) {
    $p = Get-Process -Id $ProcId -ErrorAction SilentlyContinue
    $n = if ($p) { $p.ProcessName } else { "pid $ProcId" }
    $svc = @(Get-CimInstance Win32_Service -Filter "ProcessId=$ProcId" -ErrorAction SilentlyContinue | ForEach-Object { $_.Name })
    if ($svc.Count -gt 0) { $n += " (servicio: $($svc -join ', '))" }
    return "$n"
}

function Comprobar-PuertosWindows([string]$Ip) {
    $hallazgos = @()
    $comodines = @($Ip, '0.0.0.0', '::')
    foreach ($e in @(Get-NetUDPEndpoint -LocalPort 53 -ErrorAction SilentlyContinue)) {
        if ($comodines -contains $e.LocalAddress) { $hallazgos += "53/udp en $($e.LocalAddress): $(Describir-Proceso $e.OwningProcess)" }
    }
    foreach ($puerto in @(53, 80)) {
        foreach ($c in @(Get-NetTCPConnection -LocalPort $puerto -State Listen -ErrorAction SilentlyContinue)) {
            if ($comodines -contains $c.LocalAddress) { $hallazgos += "$puerto/tcp en $($c.LocalAddress): $(Describir-Proceso $c.OwningProcess)" }
        }
    }
    return $hallazgos
}

function Modo-RedWslconfig {
    $f = Join-Path $env:USERPROFILE '.wslconfig'
    if (-not (Test-Path -LiteralPath $f)) { return 'nat (no hay .wslconfig)' }
    $seccion = ''
    foreach ($l in Get-Content -LiteralPath $f) {
        $t = $l.Trim()
        if ($t -match '^\[(.+)\]$') { $seccion = $Matches[1].ToLower(); continue }
        if ($seccion -eq 'wsl2' -and $t -match '^networkingMode\s*=\s*(\S+)') { return $Matches[1] }
    }
    return 'nat (networkingMode sin definir en .wslconfig)'
}

if ($Intranet) {
    Paso 'Modo intranet: comprobaciones del lado de Windows'
    if (-not $IP) {
        $d = Detectar-IPLan
        if (-not $d) { Fallo 'No se pudo detectar la IP de la LAN. Indicala a mano: .\levantar-sistema.ps1 -Intranet -IP X.X.X.X (la IPv4 del adaptador Wi-Fi o Ethernet en ipconfig).' }
        $IP = $d.IP
        Info "IP de la LAN detectada: $IP (interfaz '$($d.Alias)', la de la ruta por defecto). Otra IP: -IP X.X.X.X"
    } else {
        Info "IP de la LAN indicada: $IP"
    }
    if ($IP -notmatch '^(\d{1,3})\.(\d{1,3})\.(\d{1,3})\.(\d{1,3})$') { Fallo "-IP necesita una direccion IPv4 (recibido: $IP)." }
    $ArgsSh += @('--intranet', '--ip', $IP)
    $mr = Modo-RedWslconfig
    Info ".wslconfig: networkingMode = $mr"
    if ($mr -ne 'mirrored') {
        Write-Host '    AVISO: sin networkingMode=mirrored los demas equipos no llegan a los contenedores de WSL. Ejecuta una vez,' -ForegroundColor Yellow
        Write-Host '    como administrador: sistema\habilitar-intranet-windows.ps1  (y despues wsl --shutdown).' -ForegroundColor Yellow
    }
    $h = @(Comprobar-PuertosWindows $IP)
    if ($h.Count -gt 0) {
        Write-Host '    AVISO: puertos que Windows ya tiene en esa IP (o en todas). En modo mirrored chocan con el proxy (80) o el DNS (53):' -ForegroundColor Yellow
        foreach ($x in $h) { Write-Host "      - $x" -ForegroundColor Yellow }
        Write-Host '    SharedAccess es "Conexion compartida a Internet" (ICS); portmaster-core es Portmaster. Que hacer con cada uno:' -ForegroundColor Yellow
        Write-Host '    sistema\habilitar-intranet-windows.ps1 lo detecta y da los comandos (no los ejecuta por su cuenta).' -ForegroundColor Yellow
    } else {
        Info 'Puertos 80/tcp y 53/udp+tcp libres en Windows para esa IP.'
    }
}

# --- Elegir donde ejecutar ------------------------------------------------------------------------------------------

Paso 'Buscando Docker'
$modo = $null
if (Probar-DockerDesktop) {
    $bash = Buscar-GitBash
    if (-not $bash) { Fallo 'Docker Desktop esta en marcha pero no se encuentra Git Bash (viene con Git for Windows: https://git-scm.com).' }
    $modo = 'desktop'
    Info "Docker Desktop + Git Bash ($bash)"
} else {
    if (-not (Get-Command wsl.exe -ErrorAction SilentlyContinue)) {
        Fallo 'No hay Docker Desktop en marcha ni WSL. Instala y arranca Docker Desktop, o Docker Engine dentro de WSL.'
    }
    $distros = if ($Distro) { @($Distro) } else { Listar-Distros }
    foreach ($d in $distros) { if (Probar-DockerEnWsl $d) { $Distro = $d; $modo = 'wsl'; break } }
    if (-not $modo) {
        Fallo 'No se encontro Docker: ni Docker Desktop en marcha ni una distro de WSL con Docker Engine. Si usas Docker Desktop, arrancalo y repite.'
    }
    Info "Docker Engine en WSL (distro $Distro)"
}

if ($Accion -eq 'arrancar') {
    # Si el sistema ya esta levantado su memoria ya esta asignada: no tiene sentido exigir memoria libre.
    if ($modo -eq 'wsl') { $n = & wsl.exe -d $Distro -- docker ps -q --filter 'label=com.docker.compose.project=reservaviva-smoke' 2>$null }
    else { $n = & docker ps -q --filter 'label=com.docker.compose.project=reservaviva-smoke' 2>$null }
    if (-not $n) { Paso 'Comprobando memoria del equipo'; Comprobar-MemoriaHost }
}

# --- Ejecutar -------------------------------------------------------------------------------------------------------

if ($modo -eq 'wsl') {
    if ($Accion -in @('arrancar', 'preparar', 'estado', 'verificar')) { Paso 'Sesion de WSL'; Abrir-Sesion $Distro }
    & wsl.exe -d $Distro --cd $Repo -- bash ./levantar-sistema.sh @ArgsSh
    $rc = $LASTEXITCODE
    if ($Accion -in @('detener', 'borrar') -and $rc -eq 0) { Cerrar-Sesion $Distro }
} else {
    $sh = ($Repo -replace '\\', '/') + '/levantar-sistema.sh'
    & $bash $sh @ArgsSh
    $rc = $LASTEXITCODE
}

if ($rc -eq 0 -and $Accion -eq 'arrancar' -and $modo -eq 'wsl') {
    Write-Host ''
    Info 'Los contenedores siguen vivos mientras dure la sesion de WSL en segundo plano (tambien si cierras esta ventana).'
    Info 'Tras reiniciar el equipo, vuelve a ejecutar este script. Para apagarlo todo: .\levantar-sistema.ps1 detener'
}
exit $rc
