# Muestra si la ubicacion esta activa, que lugar tiene y los ultimos eventos.
. (Join-Path $PSScriptRoot 'comun.ps1')
$Host.UI.RawUI.WindowTitle = 'Estado - Ubicacion iPhone'

$cfg = Get-Config
$estado = Get-Estado
# Sin administrador no se ve la linea de comandos del servicio, asi que se usa el PID que anota en estado.json
$procs = @(if ($estado -and $estado.pid) { Get-Process -Id $estado.pid -ErrorAction SilentlyContinue | Where-Object ProcessName -eq 'powershell' })
$tarea = Get-ScheduledTask -TaskName $TaskName -ErrorAction SilentlyContinue

Write-Host ''
Write-Host '  UBICACION iPHONE' -ForegroundColor Cyan
Write-Host '  ----------------'
Write-Host "  Lugar configurado : $($cfg.nombre)"
Write-Host "  Coordenadas       : $($cfg.latitud), $($cfg.longitud)"
Write-Host "  Activado          : $(if ($cfg.activo) { 'Si' } else { 'No' })"
Write-Host "  Revision automatica (tarea): $(if ($tarea) { $tarea.State } else { 'NO INSTALADA - ejecuta Install or repair.bat' })"

$edad = if ($estado -and $estado.latido) { [int]((Get-Date) - [datetime]$estado.latido).TotalSeconds } else { $null }
Write-Host ''
if (-not $cfg.activo) {
    Write-Host '  ESTADO: DESACTIVADO (el iPhone usa su ubicacion real)' -ForegroundColor Yellow
} elseif ($procs.Count -eq 0) {
    Write-Host '  ESTADO: DETENIDO - la revision automatica lo reinicia en menos de 5 min,' -ForegroundColor Red
    Write-Host '          o usa Enable.bat para hacerlo ya.' -ForegroundColor Red
} elseif ($estado.fase -eq 'activo' -and $edad -lt 60) {
    $d = Get-DaemonEstado
    $conf = try { [int]((Get-Date) - [datetime]$d.confirmado).TotalSeconds } catch { $null }
    Write-Host '  ESTADO: ACTIVO - el iPhone esta recibiendo la ubicacion' -ForegroundColor Green
    if ($null -ne $conf) { Write-Host "          Ultima confirmacion del iPhone: hace $conf s (se reenvia cada 5 s)" }
    if ($d.ip) { Write-Host "          iPhone en $($d.ip) - reconexiones desde que arranco: $($d.reconexiones)" }
} else {
    Write-Host "  ESTADO: RECONECTANDO - $($estado.detalle)" -ForegroundColor Yellow
    Write-Host '          Revisa que el iPhone este desbloqueado al menos una vez y en el mismo Wi-Fi.'
}

Write-Host ''
Write-Host '  Ultimos eventos (conexion con el iPhone):' -ForegroundColor Cyan
Get-Content -LiteralPath $DaemonLog -Tail 10 -ErrorAction SilentlyContinue | ForEach-Object { "    $_" }
Write-Host ''
Write-Host '  Ultimos eventos (servicio):' -ForegroundColor Cyan
Get-Content -LiteralPath $LogFile -Tail 5 -ErrorAction SilentlyContinue | ForEach-Object { "    $_" }
Write-Host ''
Read-Host '  Presiona ENTER para cerrar'
