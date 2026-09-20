# Genera bind/zones/db.reservaviva.local a partir de la plantilla db.reservaviva.local.tpl.
# Sustituye ${IP_PC1}, ${IP_PC2}, ${IP_PC3} y ${SERIAL}. Idempotente (siempre reescribe el archivo).
# Lo llama deploy.ps1; tambien se puede usar a mano (p. ej. en el arnes de pruebas):
#   powershell -ExecutionPolicy Bypass -File .\bind\generar-zona.ps1 -IpPc1 10.10.10.10 -IpPc2 10.10.30.10 -IpPc3 10.10.99.10
# NO VERIFICADO: escrito sin poder ejecutarlo. Solo ASCII a proposito (PowerShell 5.1 lee mal UTF-8 sin BOM).
param(
    [Parameter(Mandatory = $true)][string]$IpPc1,
    [Parameter(Mandatory = $true)][string]$IpPc2,
    [Parameter(Mandatory = $true)][string]$IpPc3
)
$ErrorActionPreference = 'Stop'
foreach ($ip in @($IpPc1, $IpPc2, $IpPc3)) {
    if ($ip -notmatch '^(\d{1,3})\.(\d{1,3})\.(\d{1,3})\.(\d{1,3})$' -or ($Matches[1..4] | Where-Object { [int]$_ -gt 255 })) {
        throw "IP no valida: '$ip'"
    }
}
$dir = Join-Path $PSScriptRoot 'zones'
$tpl = Join-Path $dir 'db.reservaviva.local.tpl'
$out = Join-Path $dir 'db.reservaviva.local'
if (-not (Test-Path -LiteralPath $tpl -PathType Leaf)) { throw "Falta la plantilla $tpl" }
# Serial = AAAAMMDDHH (cabe en 32 bits); cada despliegue en una hora distinta sube el serial.
$serial = (Get-Date).ToString('yyyyMMddHH')
$texto = [System.IO.File]::ReadAllText($tpl)
$texto = $texto.Replace('${IP_PC1}', $IpPc1).Replace('${IP_PC2}', $IpPc2).Replace('${IP_PC3}', $IpPc3).Replace('${SERIAL}', $serial)
if ($texto -match '\$\{[A-Z0-9_]+\}') { throw "Quedan marcadores sin sustituir en la zona: $($Matches[0])" }
# BIND lee bien LF; se normaliza y se escribe UTF-8 sin BOM.
$texto = $texto -replace "`r`n", "`n"
[System.IO.File]::WriteAllText($out, $texto, (New-Object System.Text.UTF8Encoding($false)))
Write-Host "Zona generada: $out (PC-1=$IpPc1 PC-2=$IpPc2 PC-3=$IpPc3, serial $serial)"
