# habilitar-intranet-windows.ps1 - Prepara Windows para que otros equipos de la LAN lleguen a Reserva Viva (HOST_IP).
#
# Ejecutar UNA vez, en PowerShell COMO ADMINISTRADOR, desde la raiz del repositorio:
#   powershell -ExecutionPolicy Bypass -File .\sistema\habilitar-intranet-windows.ps1              # aplicar
#   powershell -ExecutionPolicy Bypass -File .\sistema\habilitar-intranet-windows.ps1 -Comprobar   # solo informar
#   powershell -ExecutionPolicy Bypass -File .\sistema\habilitar-intranet-windows.ps1 -Deshacer    # volver atras
#   Opciones: -IP X.X.X.X (IP de la LAN; por defecto la de la ruta por defecto)  -Si (no pedir confirmacion)
#
# Que hace (idempotente: ejecutarlo dos veces deja lo mismo):
#   1. .wslconfig: copia de seguridad y networkingMode=mirrored en [wsl2], sin tocar el resto ni los comentarios. Con la
#      red NAT de WSL, la distro (y Docker dentro) tiene una IP 172.x que los demas equipos no alcanzan; en modo mirrored
#      la distro comparte las interfaces de Windows y Docker puede publicar en la IP de la LAN.
#   2. Cortafuegos de Windows: reglas de ENTRADA para todo lo que el sistema publica en HOST_IP: 80/tcp (proxy web),
#      53/udp+tcp (DNS, lo atiende el reenviador de Windows), las cuatro aplicaciones (18080-18083/tcp), LDAP y LDAPS
#      (1389 y 1636/tcp) y NTP (1123/udp; los puertos salen de sistema\test.env), solo desde la subred local y en todos
#      los perfiles (la Wi-Fi de este equipo esta en perfil Publico).
#   3. Cortafuegos de Hyper-V para la VM de WSL (en modo mirrored es el que filtra lo que entra a WSL): las mismas reglas.
#   4. Informa de quien ocupa el puerto 53 en Windows (ICS / Portmaster) y de los pasos para Portmaster. NO detiene
#      servicios ni cambia Portmaster: solo muestra los comandos.
# Que NO hace: no ejecuta "wsl --shutdown" (pararia los contenedores; lo decides tu), no toca test.env ni el sistema.
#
# Despues: wsl --shutdown, y .\levantar-sistema.ps1 -Forzar. Pasos y pruebas: docs\operacion.md,
# "Acceso desde la LAN". Riesgo (claves de laboratorio publicas en git): docs\seguridad.md.
#
# Solo ASCII a proposito: PowerShell 5.1 lee mal UTF-8 sin BOM.

param(
    [switch]$Deshacer,
    [switch]$Comprobar,
    [switch]$Si,
    [string]$IP = ''
)

$ErrorActionPreference = 'Stop'
$Prefijo = 'ReservaViva'
$Grupo = 'Reserva Viva (intranet)'
# VMCreatorId de WSL para el cortafuegos de Hyper-V (documentado por Microsoft: learn.microsoft.com/windows/wsl/networking).
$WslVmCreatorId = '{40E0AC32-46A5-438A-A0B2-2B479E8F2E90}'
$WslConfig = Join-Path $env:USERPROFILE '.wslconfig'
$MarcaWsl = '# reservaviva-intranet: networkingMode anterior ='

function Paso([string]$t) { Write-Host ''; Write-Host "==> $t" }
function Info([string]$t) { Write-Host "    $t" }
function Aviso([string]$t) { Write-Host "    AVISO: $t" -ForegroundColor Yellow }
function Fallo([string]$t) { Write-Host ''; Write-Host "ERROR: $t" -ForegroundColor Red; exit 1 }

function Es-Administrador {
    $id = [Security.Principal.WindowsIdentity]::GetCurrent()
    return (New-Object Security.Principal.WindowsPrincipal($id)).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

function Detectar-IPLan {
    $r = Get-NetRoute -AddressFamily IPv4 -DestinationPrefix '0.0.0.0/0' -ErrorAction SilentlyContinue | ForEach-Object {
        $i = Get-NetIPInterface -AddressFamily IPv4 -InterfaceIndex $_.ifIndex -ErrorAction SilentlyContinue
        [pscustomobject]@{ Idx = $_.ifIndex; M = $_.RouteMetric + $i.InterfaceMetric }
    } | Sort-Object M | Select-Object -First 1
    if (-not $r) { return $null }
    return Get-NetIPAddress -AddressFamily IPv4 -InterfaceIndex $r.Idx -ErrorAction SilentlyContinue |
        Where-Object { $_.IPAddress -notlike '169.254.*' } | Select-Object -First 1
}

# 192.168.1.13 con prefijo 24 -> 192.168.1.0/24
function Subred-De([string]$Ip, [int]$Prefijo) {
    $b = [Net.IPAddress]::Parse($Ip).GetAddressBytes()
    $red = for ($i = 0; $i -lt 4; $i++) {
        $bits = [math]::Max(0, [math]::Min(8, $Prefijo - 8 * $i))
        $b[$i] -band [int](256 - [math]::Pow(2, 8 - $bits))
    }
    return "$($red -join '.')/$Prefijo"
}

function Describir-Proceso([int]$ProcId) {
    $p = Get-Process -Id $ProcId -ErrorAction SilentlyContinue
    $n = if ($p) { $p.ProcessName } else { "pid $ProcId" }
    $svc = @(Get-CimInstance Win32_Service -Filter "ProcessId=$ProcId" -ErrorAction SilentlyContinue | ForEach-Object { $_.Name })
    if ($svc.Count -gt 0) { $n += " (servicio: $($svc -join ', '))" }
    return "$n"
}

# --- .wslconfig ----------------------------------------------------------------------------------------------------

# Devuelve @{ Lineas; InicioWsl2; FinWsl2; LineaModo; Valor }
function Leer-Wslconfig {
    $lineas = @()
    if (Test-Path -LiteralPath $WslConfig) { $lineas = @([IO.File]::ReadAllLines($WslConfig)) }
    $ini = -1; $fin = $lineas.Count; $lm = -1; $val = $null; $sec = ''
    for ($i = 0; $i -lt $lineas.Count; $i++) {
        $t = $lineas[$i].Trim()
        if ($t -match '^\[(.+)\]$') {
            if ($sec -eq 'wsl2' -and $fin -eq $lineas.Count) { $fin = $i }
            $sec = $Matches[1].ToLower()
            if ($sec -eq 'wsl2') { $ini = $i }
            continue
        }
        if ($sec -eq 'wsl2' -and $t -match '^networkingMode\s*=\s*(\S+)') { $lm = $i; $val = $Matches[1] }
    }
    return @{ Lineas = $lineas; InicioWsl2 = $ini; FinWsl2 = $fin; LineaModo = $lm; Valor = $val }
}

function Guardar-Wslconfig([string[]]$Lineas) {
    if (Test-Path -LiteralPath $WslConfig) {
        $copia = "$WslConfig.reservaviva-$(Get-Date -Format 'yyyyMMdd-HHmmss').bak"
        Copy-Item -LiteralPath $WslConfig -Destination $copia
        Info "Copia de seguridad: $copia"
    }
    # UTF-8 sin BOM: lo que lee WSL, y conserva cualquier caracter que ya tuviera el fichero.
    [IO.File]::WriteAllLines($WslConfig, $Lineas, (New-Object Text.UTF8Encoding($false)))
}

function Aplicar-Mirrored {
    Paso ".wslconfig: networkingMode=mirrored ($WslConfig)"
    $w = Leer-Wslconfig
    if ($w.Valor -eq 'mirrored') { Info 'Ya esta en mirrored: no se cambia nada.'; return $false }
    $l = [System.Collections.Generic.List[string]]::new()
    foreach ($x in $w.Lineas) { $l.Add($x) }
    $anterior = if ($w.Valor) { $w.Valor } else { 'ninguno' }
    $nuevas = @(
        "$MarcaWsl $anterior",
        '# Red en modo espejo: la distro comparte las interfaces de Windows y los demas equipos de la LAN llegan a los',
        '# contenedores (Reserva Viva, acceso desde la LAN). Lo puso sistema\habilitar-intranet-windows.ps1; -Deshacer lo quita.',
        'networkingMode=mirrored'
    )
    if ($w.LineaModo -ge 0) {
        # Se sustituye la linea existente (se conserva lo demas, comentarios incluidos).
        $l.RemoveAt($w.LineaModo)
        $l.InsertRange($w.LineaModo, [string[]]$nuevas)
    } elseif ($w.InicioWsl2 -ge 0) {
        $l.InsertRange($w.FinWsl2, [string[]](@('') + $nuevas + @('')))
    } else {
        $l.Add(''); $l.Add('[wsl2]'); foreach ($x in $nuevas) { $l.Add($x) }
    }
    Guardar-Wslconfig $l.ToArray()
    Info "networkingMode: $anterior -> mirrored"
    return $true
}

function Deshacer-Mirrored {
    Paso ".wslconfig: se restaura networkingMode ($WslConfig)"
    $w = Leer-Wslconfig
    $im = -1
    for ($i = 0; $i -lt $w.Lineas.Count; $i++) { if ($w.Lineas[$i].StartsWith($MarcaWsl)) { $im = $i; break } }
    if ($im -lt 0) { Info 'No hay cambios de este script en .wslconfig: no se toca.'; return $false }
    $anterior = $w.Lineas[$im].Substring($MarcaWsl.Length).Trim()
    $l = [System.Collections.Generic.List[string]]::new()
    for ($i = 0; $i -lt $w.Lineas.Count; $i++) {
        if ($i -eq $im) { continue }
        if ($i -eq $im + 1 -or $i -eq $im + 2) { if ($w.Lineas[$i].TrimStart().StartsWith('#')) { continue } }
        if ($i -eq $w.LineaModo) {
            if ($anterior -ne 'ninguno') { $l.Add("networkingMode=$anterior") }
            continue
        }
        $l.Add($w.Lineas[$i])
    }
    Guardar-Wslconfig $l.ToArray()
    Info "networkingMode: mirrored -> $anterior"
    return $true
}

# --- Cortafuegos -----------------------------------------------------------------------------------------------------

# Lee un puerto de sistema\test.env (el mismo fichero que usa el lanzador); si falta, el valor por defecto.
function Puerto-Env([string]$Clave, [string]$Defecto) {
    $f = Join-Path (Split-Path -Parent $PSScriptRoot) 'sistema\test.env'
    if (Test-Path -LiteralPath $f) {
        foreach ($l in Get-Content -LiteralPath $f) {
            if ($l -match ('^' + [regex]::Escape($Clave) + '=(\d+)\s*$')) { return $Matches[1] }
        }
    }
    return $Defecto
}
$pOvp = Puerto-Env 'OPENVPMS_PORT' '18080'; $pErp = Puerto-Env 'ERPNEXT_PORT' '18081'
$pPtx = Puerto-Env 'PRETIX_PORT' '18082';   $pInv = Puerto-Env 'INVENTREE_PORT' '18083'
$pLdap = Puerto-Env 'LDAP_PORT' '1389';     $pLdaps = Puerto-Env 'LDAPS_PORT' '1636'
$pNtp = Puerto-Env 'NTP_PORT' '1123';       $pHttp = Puerto-Env 'HTTP_PORT' '80'
$Reglas = @(
    @{ Nombre = "$Prefijo-HTTP-TCP-80"; Protocolo = 'TCP'; Puerto = $pHttp; Texto = "proxy web (TCP $pHttp)" },
    @{ Nombre = "$Prefijo-DNS-UDP-53"; Protocolo = 'UDP'; Puerto = '53'; Texto = 'DNS (UDP 53)' },
    @{ Nombre = "$Prefijo-DNS-TCP-53"; Protocolo = 'TCP'; Puerto = '53'; Texto = 'DNS (TCP 53)' },
    @{ Nombre = "$Prefijo-OPENVPMS-TCP"; Protocolo = 'TCP'; Puerto = $pOvp; Texto = "OpenVPMS (TCP $pOvp)" },
    @{ Nombre = "$Prefijo-ERPNEXT-TCP"; Protocolo = 'TCP'; Puerto = $pErp; Texto = "ERPNext (TCP $pErp)" },
    @{ Nombre = "$Prefijo-PRETIX-TCP"; Protocolo = 'TCP'; Puerto = $pPtx; Texto = "Pretix (TCP $pPtx)" },
    @{ Nombre = "$Prefijo-INVENTREE-TCP"; Protocolo = 'TCP'; Puerto = $pInv; Texto = "InvenTree (TCP $pInv)" },
    @{ Nombre = "$Prefijo-LDAP-TCP"; Protocolo = 'TCP'; Puerto = $pLdap; Texto = "LDAP (TCP $pLdap)" },
    @{ Nombre = "$Prefijo-LDAPS-TCP"; Protocolo = 'TCP'; Puerto = $pLdaps; Texto = "LDAPS (TCP $pLdaps)" },
    @{ Nombre = "$Prefijo-NTP-UDP"; Protocolo = 'UDP'; Puerto = $pNtp; Texto = "NTP (UDP $pNtp)" }
)

function Aplicar-Cortafuegos([string]$Subred) {
    Paso "Cortafuegos de Windows: entrada a $(($Reglas | ForEach-Object { "$($_.Puerto)/$($_.Protocolo.ToLower())" }) -join ', ') solo desde $Subred (todos los perfiles)"
    foreach ($r in $Reglas) {
        Get-NetFirewallRule -Name $r.Nombre -ErrorAction SilentlyContinue | Remove-NetFirewallRule
        New-NetFirewallRule -Name $r.Nombre -DisplayName "Reserva Viva - $($r.Texto)" -Group $Grupo -Direction Inbound `
            -Action Allow -Protocol $r.Protocolo -LocalPort $r.Puerto -RemoteAddress $Subred -Profile Any | Out-Null
        Info "Regla $($r.Nombre): permitir $($r.Texto) desde $Subred"
    }
    Paso "Cortafuegos de Hyper-V para la VM de WSL ($WslVmCreatorId): las mismas reglas"
    if (-not (Get-Command New-NetFirewallHyperVRule -ErrorAction SilentlyContinue)) {
        Aviso 'Este Windows no tiene New-NetFirewallHyperVRule (hace falta Windows 11 22H2 o posterior). Sin el, en modo mirrored'
        Aviso 'la entrada a WSL depende de la configuracion por defecto del cortafuegos de Hyper-V.'
        return
    }
    foreach ($r in $Reglas) {
        $n = "$($r.Nombre)-HyperV"
        Get-NetFirewallHyperVRule -Name $n -ErrorAction SilentlyContinue | Remove-NetFirewallHyperVRule
        New-NetFirewallHyperVRule -Name $n -DisplayName "Reserva Viva - $($r.Texto) hacia WSL" -Direction Inbound `
            -VMCreatorId $WslVmCreatorId -Protocol $r.Protocolo -LocalPorts $r.Puerto -RemoteAddresses $Subred -Action Allow | Out-Null
        Info "Regla Hyper-V ${n}: permitir $($r.Texto) desde $Subred hacia WSL"
    }
}

function Deshacer-Cortafuegos {
    Paso 'Cortafuegos: se quitan las reglas de este script'
    foreach ($r in $Reglas) {
        if (Get-NetFirewallRule -Name $r.Nombre -ErrorAction SilentlyContinue) {
            Remove-NetFirewallRule -Name $r.Nombre; Info "Quitada $($r.Nombre)"
        }
        if ((Get-Command Get-NetFirewallHyperVRule -ErrorAction SilentlyContinue) -and
            (Get-NetFirewallHyperVRule -Name "$($r.Nombre)-HyperV" -ErrorAction SilentlyContinue)) {
            Remove-NetFirewallHyperVRule -Name "$($r.Nombre)-HyperV"; Info "Quitada $($r.Nombre)-HyperV"
        }
    }
}

# --- Quien ocupa los puertos -----------------------------------------------------------------------------------------

function Informar-Puertos([string]$Ip) {
    Paso "Puertos 53 y 80 en Windows (en $Ip o en todas las direcciones)"
    $comodines = @($Ip, '0.0.0.0', '::')
    $ics = $false; $pm = $false; $otros = @()
    $ep = @()
    foreach ($e in @(Get-NetUDPEndpoint -LocalPort 53 -ErrorAction SilentlyContinue)) { $ep += [pscustomobject]@{ P = '53/udp'; A = $e.LocalAddress; Pid = $e.OwningProcess } }
    foreach ($pt in @(53, 80)) {
        foreach ($c in @(Get-NetTCPConnection -LocalPort $pt -State Listen -ErrorAction SilentlyContinue)) { $ep += [pscustomobject]@{ P = "$pt/tcp"; A = $c.LocalAddress; Pid = $c.OwningProcess } }
    }
    $ep = @($ep | Where-Object { $comodines -contains $_.A })
    if ($ep.Count -eq 0) { Info 'Libres: nada de Windows escucha en 53 ni en 80 para esa IP.'; return }
    foreach ($e in $ep) {
        $d = Describir-Proceso $e.Pid
        Info "$($e.P) en $($e.A): $d"
        if ($d -match 'SharedAccess') { $ics = $true } elseif ($d -match 'portmaster') { $pm = $true } else { $otros += $d }
    }
    if ($ics) {
        Write-Host ''
        Aviso 'El servicio SharedAccess ("Conexion compartida a Internet", ICS) escucha en 0.0.0.0:53/udp. Con WSL en modo'
        Aviso 'mirrored puede impedir que Docker publique el DNS en el 53. Lo usan la "Zona con cobertura inalambrica movil"'
        Aviso 'y el conmutador "Default Switch" de Hyper-V; tras pasar WSL a mirrored, WSL ya no lo necesita. Si el DNS no'
        Aviso 'puede publicarse, puedes pararlo mientras uses el sistema (este script NO lo hace):'
        Info '    Stop-Service SharedAccess            # hasta el proximo reinicio'
        Info '    Set-Service SharedAccess -StartupType Manual   # opcional: que no arranque solo al iniciar Windows'
        Info '  Para volver: Set-Service SharedAccess -StartupType Automatic; Start-Service SharedAccess'
    }
    if ($pm) {
        Write-Host ''
        Aviso 'Portmaster (portmaster-core) escucha en [::]:53: intercepta el DNS de este equipo y filtra conexiones por'
        Aviso 'aplicacion, tambien las ENTRANTES. Este script no cambia su configuracion. Pasos (los nombres exactos de las'
        Aviso 'opciones pueden variar segun la version de Portmaster):'
        Info '  1. Abre Portmaster > Settings (ajustes globales) > busca "Incoming" / "Block Inbound Connections" y permite'
        Info '     las conexiones entrantes desde la LAN (o, mejor, solo para la aplicacion de abajo).'
        Info '  2. En la lista de aplicaciones, busca la que recibe el trafico de WSL (en mirrored suele aparecer como'
        Info '     "System", "wslservice" o "vmmem"/"vmmemWSL") y anade reglas de entrada: permitir TCP 80 y UDP/TCP 53'
        Info '     desde la subred local.'
        Info '  3. Si el DNS no puede publicarse en el 53 porque Portmaster lo ocupa, en sus ajustes de DNS/"Secure DNS" se'
        Info '     puede limitar a 127.0.0.1/::1; o, para probar, pausa Portmaster y comprueba si ese era el bloqueo.'
        Info '  Prueba de que Portmaster es el problema: desde otro equipo, Test-NetConnection <IP> -Port 80 falla con'
        Info '  Portmaster activo y funciona con Portmaster en pausa.'
    }
    foreach ($o in $otros) { Aviso "Otro programa ocupa el puerto: $o. Paralo o usa otro puerto para el proxy (HTTP_PORT)." }
}

# --- Principal -------------------------------------------------------------------------------------------------------

$build = [Environment]::OSVersion.Version.Build
Paso 'Comprobando el equipo'
Info "Windows build $build (el modo mirrored de WSL necesita Windows 11 22H2, build 22621, o posterior)"
if ($build -lt 22621) { Fallo 'Este Windows no admite networkingMode=mirrored. Publicar en la LAN no es posible aqui sin Docker Desktop.' }

$dir = $null
if ($IP) {
    $dir = Get-NetIPAddress -AddressFamily IPv4 -IPAddress $IP -ErrorAction SilentlyContinue | Select-Object -First 1
    if (-not $dir) { Fallo "La IP $IP no esta en ninguna interfaz de este equipo (ipconfig)." }
} else {
    $dir = Detectar-IPLan
    if (-not $dir) { Fallo 'No se pudo detectar la IP de la LAN. Indicala con -IP X.X.X.X (ipconfig).' }
}
$IP = $dir.IPAddress
$Subred = Subred-De $IP $dir.PrefixLength
$perfil = (Get-NetConnectionProfile -InterfaceIndex $dir.InterfaceIndex -ErrorAction SilentlyContinue).NetworkCategory
Info "IP de la LAN: $IP (interfaz '$($dir.InterfaceAlias)', subred $Subred, perfil de red: $perfil)"
$w = Leer-Wslconfig
Info ".wslconfig: networkingMode = $(if ($w.Valor) { $w.Valor } else { 'sin definir (nat)' })"
$red = $null
try {
    $ErrorActionPreference = 'Continue'
    $red = (& wsl.exe --exec wslinfo --networking-mode 2>$null | Select-Object -First 1)
} catch { $red = $null } finally { $ErrorActionPreference = 'Stop' }
if ($red) { $red = "$red".Trim(); Info "Modo de red de WSL ahora mismo (distro por defecto): $red" }

if ($Comprobar) {
    Informar-Puertos $IP
    foreach ($r in $Reglas) {
        $f = if (Get-NetFirewallRule -Name $r.Nombre -ErrorAction SilentlyContinue) { 'presente' } else { 'ausente' }
        Info "Regla $($r.Nombre): $f"
    }
    Write-Host ''
    Info 'Solo comprobacion: no se ha cambiado nada.'
    exit 0
}

if (-not (Es-Administrador)) {
    Fallo 'Hace falta PowerShell como administrador (clic derecho > Ejecutar como administrador). Para solo informar: -Comprobar.'
}

if ($Deshacer) {
    if (-not $Si) {
        $x = Read-Host 'Se quitan las reglas de cortafuegos de Reserva Viva y se restaura networkingMode en .wslconfig. Escribe "si" para seguir'
        if ($x -ne 'si') { Write-Host 'Cancelado.'; exit 0 }
    }
    Deshacer-Cortafuegos
    $cambio = Deshacer-Mirrored
    Write-Host ''
    if ($cambio) { Aviso 'Para que WSL vuelva a la red anterior: wsl --shutdown (PARA los contenedores) y .\levantar-sistema.ps1 -Forzar' }
    Info 'Listo. Arranca con: .\levantar-sistema.ps1 -Forzar'
    exit 0
}

Write-Host ''
Aviso 'Esto deja el sistema accesible desde la LAN: las cuatro aplicaciones, LDAP, DNS y NTP, con claves de laboratorio PUBLICAS en git (sistema\test.env).'
Aviso 'Usalo solo en una red de laboratorio. Las reglas se limitan a la subred local, pero cualquiera en ella puede entrar.'
Aviso 'networkingMode=mirrored cambia la red de TODA la distro de WSL, no solo de Docker. Segun los comentarios de tu .wslconfig,'
Aviso 'con Tailscale en Windows el DNS de la distro ya dio problemas (por eso dnsTunneling=false y resolv.conf estatico):'
Aviso 'tras el cambio comprueba que "apt update" dentro de WSL sigue resolviendo nombres. En mirrored, localhostForwarding'
Aviso 'se ignora (localhost ya es compartido) y hostAddressLoopback=true sigue aplicando.'
if (-not $Si) {
    $x = Read-Host 'Escribe "si" para aplicar los cambios'
    if ($x -ne 'si') { Write-Host 'Cancelado.'; exit 0 }
}

$cambio = Aplicar-Mirrored
Aplicar-Cortafuegos $Subred
Informar-Puertos $IP

Paso 'Siguientes pasos'
if ($cambio -or ("$red" -ne 'mirrored')) {
    Info '1. wsl --shutdown        (PARA la VM de WSL y todos los contenedores; los datos se conservan)'
    Info '2. .\levantar-sistema.ps1 -Forzar   (o con -IP X.X.X.X / -Intranet si este equipo no tiene la IP de sistema\test.env)'
} else {
    Info '1. .\levantar-sistema.ps1 -Forzar   (o con -IP X.X.X.X / -Intranet si este equipo no tiene la IP de sistema\test.env)'
}
Info "Despues, desde OTRO equipo de la LAN: nslookup pretix.reservaviva.lan $IP  y abrir http://pretix.reservaviva.lan"
Info 'Lista completa de pruebas: docs\operacion.md, "Acceso desde la LAN". Para volver atras: este script con -Deshacer.'
