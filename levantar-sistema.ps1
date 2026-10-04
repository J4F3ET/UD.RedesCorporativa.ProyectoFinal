# levantar-sistema.ps1 - Lanzador para Windows de levantar-sistema.sh (arquitectura completa en UN solo host).
#
#   .\levantar-sistema.ps1                  # prepara y levanta los 26 servicios (modo local)
#   .\levantar-sistema.ps1 estado           # estado y direcciones de acceso
#   .\levantar-sistema.ps1 verificar        # segmentacion, DNS, NTP y LDAP
#   .\levantar-sistema.ps1 detener          # para todo sin borrar datos
#   .\levantar-sistema.ps1 borrar           # borra contenedores Y datos (pide confirmacion)
#   .\levantar-sistema.ps1 borrar-directorio  # borra solo el contenedor y los volumenes de samba-ad (pide confirmacion)
#   .\levantar-sistema.ps1 -Intranet        # modo intranet: proxy web (80) y DNS (53) en la IP de la LAN
#                                           # (con WSL, el 53 lo atiende sistema\reenviador-dns.ps1: ver mas abajo)
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
#      Con -Intranet deja ademas el reenviador DNS de Windows (sistema\reenviador-dns.ps1, PID en
#      sistema\.reenviador-dns.pid); "detener", "borrar" y el arranque en modo local lo paran; "estado" dice si vive.
#
# Solo ASCII a proposito: PowerShell 5.1 lee mal UTF-8 sin BOM.

param(
    [Parameter(Position = 0)]
    [ValidateSet('arrancar', 'preparar', 'estado', 'verificar', 'detener', 'borrar', 'borrar-directorio', 'ayuda')]
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

if ($Accion -eq 'ayuda') { Get-Content -LiteralPath $PSCommandPath -TotalCount 26 | ForEach-Object { $_ -replace '^# ?', '' }; exit 0 }

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

# Lista de "puerto/proto en IP: proceso". Se excluyen los PID de $Excluir (el reenviador DNS de este proyecto).
function Comprobar-PuertosWindows([string]$Ip, [int[]]$Puertos = @(53, 80), [int[]]$Excluir = @()) {
    $hallazgos = @()
    $comodines = @($Ip, '0.0.0.0', '::')
    if ($Puertos -contains 53) {
        foreach ($e in @(Get-NetUDPEndpoint -LocalPort 53 -ErrorAction SilentlyContinue)) {
            if ($comodines -contains $e.LocalAddress -and $Excluir -notcontains $e.OwningProcess) { $hallazgos += "53/udp en $($e.LocalAddress): $(Describir-Proceso $e.OwningProcess)" }
        }
    }
    foreach ($puerto in $Puertos) {
        foreach ($c in @(Get-NetTCPConnection -LocalPort $puerto -State Listen -ErrorAction SilentlyContinue)) {
            if ($comodines -contains $c.LocalAddress -and $Excluir -notcontains $c.OwningProcess) { $hallazgos += "$puerto/tcp en $($c.LocalAddress): $(Describir-Proceso $c.OwningProcess)" }
        }
    }
    return $hallazgos
}

# --- Reenviador DNS de Windows (modo intranet con Docker Engine en WSL) ----------------------------------------------
#
# Con WSL en networkingMode=mirrored, Windows NO entrega a Linux el trafico que llega a su puerto 53 (medido el
# 27/09/2026; detalle en docs\operacion.md, "Acceso desde la LAN"). Por eso levantar-sistema.sh publica dns-interno en
# <IP>:1053 y aqui se arranca sistema\reenviador-dns.ps1, un proceso de Windows oculto que escucha en <IP>:53 (UDP y
# TCP) y reenvia cada consulta a <IP>:1053. Su PID queda en sistema\.reenviador-dns.pid (ignorado por git). "detener",
# "borrar" y el arranque en modo local lo paran. No necesita administrador.

$ScriptReenviador = Join-Path $Repo 'sistema\reenviador-dns.ps1'
$ArchivoPid = Join-Path $Repo 'sistema\.reenviador-dns.pid'
$NombrePrueba = 'pretix.reservaviva.lan'

# Procesos que ejecutan ESTE reenviador (por su linea de comandos), con la IP y el puerto destino con que se lanzaron.
# Solo esos: nunca se toca otro proceso de PowerShell.
function Buscar-Reenviadores {
    $patron = '-File\s+"?[^"]*\\reenviador-dns\.ps1"?\s+-IP\s+(\S+)(?:\s+-PuertoDestino\s+(\d+))?'
    foreach ($p in @(Get-CimInstance Win32_Process -Filter "Name='powershell.exe' OR Name='pwsh.exe'" -ErrorAction SilentlyContinue)) {
        if ($p.CommandLine -and $p.CommandLine -match $patron) {
            [pscustomobject]@{ Id = [int]$p.ProcessId; IP = $Matches[1]; Puerto = $(if ($Matches[2]) { [int]$Matches[2] } else { 1053 }) }
        }
    }
}

function Detener-Reenviador {
    $r = @(Buscar-Reenviadores)
    foreach ($x in $r) {
        Stop-Process -Id $x.Id -Force -ErrorAction SilentlyContinue
        Info "Reenviador DNS de Windows parado (PID $($x.Id), $($x.IP):53 -> $($x.IP):$($x.Puerto))."
    }
    if (Test-Path -LiteralPath $ArchivoPid) { Remove-Item -LiteralPath $ArchivoPid -Force -ErrorAction SilentlyContinue }
}

# Consulta A por UDP con un paquete hecho a mano (sin depender del resolutor de Windows ni de Resolve-DnsName, que
# pueden pasar por Portmaster o NRPT). Devuelve la IP de la respuesta, "rcode N" o $null si no hay respuesta.
function Consultar-DNS([string]$Servidor, [string]$Nombre, [int]$Puerto = 53) {
    $id = Get-Random -Maximum 65535
    $q = New-Object 'System.Collections.Generic.List[byte]'
    $q.AddRange([byte[]](($id -shr 8), ($id -band 255), 1, 0, 0, 1, 0, 0, 0, 0, 0, 0))
    foreach ($p in $Nombre.Split('.')) { $q.Add([byte]$p.Length); $q.AddRange([Text.Encoding]::ASCII.GetBytes($p)) }
    $q.AddRange([byte[]](0, 0, 1, 0, 1))
    $u = New-Object Net.Sockets.UdpClient
    try {
        $u.Client.ReceiveTimeout = 2000
        [void]$u.Send($q.ToArray(), $q.Count, $Servidor, $Puerto)
        $ep = New-Object Net.IPEndPoint ([Net.IPAddress]::Any), 0
        $r = $u.Receive([ref]$ep)
        $rcode = $r[3] -band 15
        if ($rcode -ne 0 -or ($r[6] * 256 + $r[7]) -lt 1) { return "rcode $rcode" }
        return "$($r[-4]).$($r[-3]).$($r[-2]).$($r[-1])"
    } catch { return $null } finally { $u.Close() }
}

# "IP" y puerto en que Docker publica el DNS (dns-interno 53/udp), o $null si no existe o no publica.
function Publicacion-DNS {
    if ($modo -eq 'wsl') { $s = & wsl.exe -d $Distro -- docker port dns-interno 53/udp 2>$null }
    else { $s = & docker port dns-interno 53/udp 2>$null }
    foreach ($l in @($s)) {
        if ("$l".Trim() -match '^(\d{1,3}(?:\.\d{1,3}){3}):(\d+)$') { return [pscustomobject]@{ IP = $Matches[1]; Puerto = [int]$Matches[2] } }
    }
    return $null
}

# Deja UN reenviador vivo para <Ip>:53 -> <Ip>:<Puerto> y comprueba que responde. Devuelve $true si responde.
function Asegurar-Reenviador([string]$Ip, [int]$Puerto) {
    Paso "Reenviador DNS de Windows ($($Ip):53 -> $($Ip):$Puerto)"
    Info 'Con WSL en modo mirrored, Windows no entrega su puerto 53 a Linux: este proceso de Windows lo atiende y reenvia.'
    $vivo = $null
    foreach ($x in @(Buscar-Reenviadores)) {
        if (-not $vivo -and $x.IP -eq $Ip -and $x.Puerto -eq $Puerto) { $vivo = $x; continue }
        Stop-Process -Id $x.Id -Force -ErrorAction SilentlyContinue
        Info "Parado un reenviador con otra configuracion (PID $($x.Id), $($x.IP):53 -> $($x.IP):$($x.Puerto))."
    }
    if ($vivo) {
        Info "Ya estaba en marcha (PID $($vivo.Id)): no se lanza otro."
    } else {
        Start-Sleep -Milliseconds 500   # que Windows suelte el puerto de un reenviador recien parado
        $h = @(Comprobar-PuertosWindows $Ip @(53))
        if ($h.Count -gt 0) {
            Write-Host '    ERROR: el puerto 53 de Windows ya esta ocupado en esa IP (o en todas), y el reenviador lo necesita:' -ForegroundColor Red
            foreach ($x in $h) { Write-Host "      - $x" -ForegroundColor Red }
            Write-Host '    SharedAccess es "Conexion compartida a Internet" (ICS); portmaster-core es Portmaster. Ejecuta, como' -ForegroundColor Red
            Write-Host '    administrador, sistema\habilitar-intranet-windows.ps1: detecta quien lo ocupa y da los comandos para liberarlo.' -ForegroundColor Red
            Write-Host '    Despues repite: .\levantar-sistema.ps1 -Intranet. Los contenedores siguen en marcha.' -ForegroundColor Red
            return $false
        }
        $argumentos = "-NoProfile -NonInteractive -ExecutionPolicy Bypass -WindowStyle Hidden -File `"$ScriptReenviador`" -IP $Ip -PuertoDestino $Puerto"
        $p = Start-Process -FilePath 'powershell.exe' -WindowStyle Hidden -PassThru -ArgumentList $argumentos
        $vivo = [pscustomobject]@{ Id = $p.Id; IP = $Ip; Puerto = $Puerto }
        Info "Lanzado en segundo plano, sin ventana (PID $($p.Id)); sigue vivo aunque cierres esta ventana."
    }
    Set-Content -LiteralPath $ArchivoPid -Value $vivo.Id -Encoding ascii
    $resp = $null
    for ($i = 0; $i -lt 10; $i++) {
        if (-not (Get-Process -Id $vivo.Id -ErrorAction SilentlyContinue)) { break }
        $resp = Consultar-DNS $Ip $NombrePrueba
        if ($resp -eq $Ip) { break }
        Start-Sleep -Seconds 1
    }
    if ($resp -eq $Ip) {
        Info "Responde: $NombrePrueba -> $resp (consulta A por UDP a $($Ip):53). PID en sistema\.reenviador-dns.pid"
        return $true
    }
    $motivo = if (-not (Get-Process -Id $vivo.Id -ErrorAction SilentlyContinue)) { 'el proceso termino al arrancar (pruebalo a mano, abajo, para ver el error)' }
              elseif ($resp) { "respuesta inesperada: $resp" } else { 'sin respuesta en 10 s' }
    Write-Host "    AVISO: el reenviador DNS no responde bien ($motivo)." -ForegroundColor Yellow
    Write-Host "    Prueba a mano: powershell -ExecutionPolicy Bypass -File .\sistema\reenviador-dns.ps1 -IP $Ip -PuertoDestino $Puerto" -ForegroundColor Yellow
    Write-Host "    y en otra ventana: nslookup $NombrePrueba $Ip   (dns-interno debe responder en $($Ip):$Puerto)" -ForegroundColor Yellow
    return $false
}

# Estado del reenviador para "estado": vivo o no, y si responde.
function Informar-Reenviador {
    $pub = Publicacion-DNS
    $necesario = $pub -and $pub.IP -notlike '127.*' -and $pub.Puerto -ne 53
    $r = @(Buscar-Reenviadores)
    Paso 'Reenviador DNS de Windows (puerto 53 de la LAN)'
    if ($r.Count -eq 0) {
        if ($necesario) {
            Write-Host "    AVISO: NO esta en marcha y hace falta (dns-interno esta en $($pub.IP):$($pub.Puerto)): los equipos de la LAN" -ForegroundColor Yellow
            Write-Host '    no resuelven los nombres. Vuelve a ejecutar: .\levantar-sistema.ps1 -Intranet' -ForegroundColor Yellow
        } else {
            Info 'No esta en marcha (no hace falta: el DNS no esta en modo intranet detras de WSL).'
        }
        return
    }
    $guardado = if (Test-Path -LiteralPath $ArchivoPid) { "$(Get-Content -LiteralPath $ArchivoPid -TotalCount 1)".Trim() } else { '' }
    foreach ($x in $r) {
        $resp = Consultar-DNS $x.IP $NombrePrueba
        $nota = if ("$($x.Id)" -eq $guardado) { 'PID en sistema\.reenviador-dns.pid' } else { 'OJO: su PID no es el de sistema\.reenviador-dns.pid' }
        Info "Vivo: PID $($x.Id), $($x.IP):53 -> $($x.IP):$($x.Puerto) ($nota)"
        if ($resp -eq $x.IP) { Info "Responde: $NombrePrueba -> $resp" }
        else { Write-Host "    AVISO: no responde bien ($(if ($resp) { $resp } else { 'sin respuesta' })). Repite: .\levantar-sistema.ps1 -Intranet" -ForegroundColor Yellow }
    }
    if (-not $necesario) {
        Write-Host '    AVISO: el DNS no esta publicado para el reenviador (modo local?). Se para con: .\levantar-sistema.ps1 detener, o arrancando en modo local.' -ForegroundColor Yellow
    }
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
    # El 53 de Windows lo necesita el reenviador DNS (o Docker Desktop); el 80, el proxy web. Un reenviador de este
    # proyecto ya en marcha no cuenta como ocupante: se reutiliza o se reemplaza despues.
    $propios = @(Buscar-Reenviadores | ForEach-Object { $_.Id })
    $h = @(Comprobar-PuertosWindows $IP @(53, 80) $propios)
    $Ocupado53 = @($h | Where-Object { $_ -like '53/*' })
    if ($h.Count -gt 0) {
        Write-Host '    AVISO: puertos que Windows ya tiene en esa IP (o en todas). Chocan con el proxy (80) o con el DNS (53, que en' -ForegroundColor Yellow
        Write-Host '    WSL atiende el reenviador de Windows):' -ForegroundColor Yellow
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

if ($Intranet -and $Accion -eq 'arrancar' -and $modo -eq 'wsl' -and $Ocupado53.Count -gt 0) {
    Fallo "El puerto 53 de Windows esta ocupado ($($Ocupado53 -join '; ')). Con Docker Engine en WSL, el DNS de la LAN lo atiende en ese puerto un reenviador de Windows (sistema\reenviador-dns.ps1), que no podria arrancar. Ejecuta como administrador sistema\habilitar-intranet-windows.ps1: detecta quien lo ocupa y da los comandos para liberarlo. Nada se ha cambiado."
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

# Reenviador DNS: tras "arrancar" se ajusta a como quedo publicado el DNS (intranet detras de WSL -> uno vivo y
# comprobado; cualquier otro caso -> ninguno), aunque el arranque haya fallado mas adelante: el DNS ya esta publicado.
if ($Accion -eq 'arrancar') {
    $pub = Publicacion-DNS
    if ($pub -and $pub.IP -notlike '127.*' -and $pub.Puerto -ne 53) {
        if (-not (Asegurar-Reenviador $pub.IP $pub.Puerto) -and $rc -eq 0) {
            Write-Host ''
            Write-Host 'ERROR: el sistema esta en marcha, pero sin el reenviador los equipos de la LAN no resuelven los nombres (ver arriba).' -ForegroundColor Red
            $rc = 1
        }
    } elseif (@(Buscar-Reenviadores).Count -gt 0) {
        Paso 'Reenviador DNS de Windows'
        Detener-Reenviador
    }
} elseif ($Accion -in @('detener', 'borrar') -and $rc -eq 0) {
    if (@(Buscar-Reenviadores).Count -gt 0) { Paso 'Reenviador DNS de Windows'; Detener-Reenviador }
} elseif ($Accion -eq 'estado') {
    Informar-Reenviador
}

if ($rc -eq 0 -and $Accion -eq 'arrancar' -and $modo -eq 'wsl') {
    Write-Host ''
    Info 'Los contenedores siguen vivos mientras dure la sesion de WSL en segundo plano (tambien si cierras esta ventana).'
    Info 'Tras reiniciar el equipo, vuelve a ejecutar este script. Para apagarlo todo: .\levantar-sistema.ps1 detener'
}
exit $rc
