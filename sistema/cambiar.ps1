# Cambia el lugar simulado. Ofrece los lugares guardados en lugares.json y acepta coordenadas
# copiadas de Google Maps ("-33.43778, -70.65045").
. (Join-Path $PSScriptRoot 'comun.ps1')
$Host.UI.RawUI.WindowTitle = 'Cambiar ubicacion - iPhone'

$lugares = [ordered]@{}
$n = 1
foreach ($l in (Get-Lugares)) {
    $lugares["$n"] = @{ nombre = $l.nombre; lat = $l.latitud; lon = $l.longitud }
    $n++
}
$cfg = Get-Config
Write-Host ''
Write-Host "  Ubicacion actual: $($cfg.nombre) ($($cfg.latitud), $($cfg.longitud))" -ForegroundColor Cyan
Write-Host ''
foreach ($k in $lugares.Keys) { Write-Host "  $k) $($lugares[$k].nombre)" }
Write-Host '  O pega coordenadas de Google Maps (clic derecho en el punto > copiar).'
Write-Host ''
$r = (Read-Host '  Opcion o coordenadas').Trim()

if ($lugares.Contains($r)) {
    $l = $lugares[$r]; $lat = $l.lat; $lon = $l.lon; $nombre = $l.nombre
} elseif ($r -match '^\s*(-?\d+(?:\.\d+)?)\s*[,; ]\s*(-?\d+(?:\.\d+)?)\s*$') {
    $lat = $Matches[1]; $lon = $Matches[2]
    if ([double]$lat -lt -90 -or [double]$lat -gt 90 -or [double]$lon -lt -180 -or [double]$lon -gt 180) {
        Write-Host '  Coordenadas fuera de rango.' -ForegroundColor Red; Start-Sleep 3; exit
    }
    $nombre = (Read-Host '  Nombre para este lugar (opcional)').Trim()
    if (-not $nombre) { $nombre = "$lat, $lon" }
} else {
    Write-Host '  No entendi la opcion.' -ForegroundColor Red; Start-Sleep 3; exit
}

& (Join-Path $PSScriptRoot 'control.ps1') -Accion activar -Lat $lat -Lon $lon -Nombre $nombre
Write-Host ''
Write-Host "  Listo: $nombre. Acepta el permiso de administrador si aparece." -ForegroundColor Green
Write-Host '  En unos segundos el iPhone tendra la nueva ubicacion.'
Start-Sleep 4
