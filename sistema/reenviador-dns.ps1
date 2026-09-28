# reenviador-dns.ps1 - Reenvia el DNS de la LAN (IP:53, UDP y TCP) al DNS de Reserva Viva publicado en IP:PuertoDestino.
#
# Por que existe: con WSL en modo mirrored, Windows NO entrega a Linux el trafico que llega a su puerto 53 (comprobado:
# un servidor en WSL recibe en el 54 pero no en el 53; Windows responde "puerto inalcanzable"). Por eso en modo intranet
# el contenedor dns-interno se publica en IP:1053 y este proceso de Windows escucha en IP:53 y reenvia cada consulta.
#
# Lo arranca levantar-sistema.ps1 -Intranet (proceso oculto, sin ventana); "levantar-sistema.ps1 detener" y el modo
# local lo paran. Uso manual:
#   powershell -ExecutionPolicy Bypass -File .\sistema\reenviador-dns.ps1 -IP 192.168.1.13 [-PuertoDestino 1053]
# No necesita administrador. El cortafuegos para 53/udp+tcp lo abre sistema\habilitar-intranet-windows.ps1.
#
# Solo ASCII a proposito: PowerShell 5.1 lee mal UTF-8 sin BOM.

param(
    [Parameter(Mandatory = $true)][string]$IP,
    [int]$PuertoDestino = 1053,
    [string]$Registro = ''   # opcional: archivo donde anotar el origen de cada consulta (diagnostico)
)

$ErrorActionPreference = 'Stop'
$escucha = [Net.IPEndPoint]::new([Net.IPAddress]::Parse($IP), 53)
$destino = [Net.IPEndPoint]::new([Net.IPAddress]::Parse($IP), $PuertoDestino)

# TCP en un runspace aparte: cada conexion lleva consultas con prefijo de longitud; se pasan tal cual en ambos sentidos.
$tcp = [PowerShell]::Create()
[void]$tcp.AddScript({
    param($escucha, $destino)
    $l = [Net.Sockets.TcpListener]::new($escucha)
    $l.Start()
    while ($true) {
        $c = $l.AcceptTcpClient()
        try {
            $c.ReceiveTimeout = 5000
            $u = [Net.Sockets.TcpClient]::new()
            $u.ReceiveTimeout = 5000
            $u.Connect($destino)
            $a = $c.GetStream(); $b = $u.GetStream()
            $buf = New-Object byte[] 65537
            while ($true) {
                $n = $a.Read($buf, 0, 2); if ($n -lt 2) { break }
                $len = $buf[0] * 256 + $buf[1]; $got = 0
                while ($got -lt $len) { $r = $a.Read($buf, 2 + $got, $len - $got); if ($r -le 0) { break }; $got += $r }
                $b.Write($buf, 0, 2 + $len)
                $n = $b.Read($buf, 0, 2); if ($n -lt 2) { break }
                $len = $buf[0] * 256 + $buf[1]; $got = 0
                while ($got -lt $len) { $r = $b.Read($buf, 2 + $got, $len - $got); if ($r -le 0) { break }; $got += $r }
                $a.Write($buf, 0, 2 + $len)
            }
        } catch { } finally { if ($u) { $u.Close() }; $c.Close() }
    }
}).AddArgument($escucha).AddArgument($destino)
[void]$tcp.BeginInvoke()

# "nombre tipo" de una consulta DNS, para el registro de diagnostico.
function Describir([byte[]]$m) {
    $i = 12; $partes = @()
    while ($i -lt $m.Length -and $m[$i] -ne 0) { $n = $m[$i]; $partes += [Text.Encoding]::ASCII.GetString($m, $i + 1, $n); $i += $n + 1 }
    $tipo = if ($i + 2 -lt $m.Length) { $m[$i + 1] * 256 + $m[$i + 2] } else { 0 }
    return "$($partes -join '.') tipo $tipo"
}

# UDP: una consulta, una respuesta. Secuencial: el DNS del laboratorio responde en milisegundos.
$udp = [Net.Sockets.UdpClient]::new($escucha)
# Sin esto, un ICMP "puerto inalcanzable" de un cliente que ya se fue rompe el siguiente Receive (WSAECONNRESET).
$udp.Client.IOControl(-1744830452, [byte[]](0, 0, 0, 0), $null) | Out-Null
while ($true) {
    $cliente = [Net.IPEndPoint]::new([Net.IPAddress]::Any, 0)
    try { $q = $udp.Receive([ref]$cliente) } catch { continue }
    $u = [Net.Sockets.UdpClient]::new()
    try {
        $u.Client.ReceiveTimeout = 3000
        [void]$u.Send($q, $q.Length, $destino)
        $origen = [Net.IPEndPoint]::new([Net.IPAddress]::Any, 0)
        $r = $u.Receive([ref]$origen)
        [void]$udp.Send($r, $r.Length, $cliente)
        if ($Registro) { Add-Content -Path $Registro -Encoding ascii -Value "$(Get-Date -Format 'HH:mm:ss') $($cliente.Address) $(Describir $q) -> rcode $($r[3] -band 15), $($r[6] * 256 + $r[7]) respuestas" }
    } catch { } finally { $u.Close() }
}
