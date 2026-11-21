# Guardian. Lo ejecuta la tarea "Ubicacion iPhone" al encender la PC, al iniciar sesion,
# al volver de suspension y cada 5 minutos. Si el servicio no corre o se colgo, lo relanza.
. (Join-Path $PSScriptRoot 'comun.ps1')

$cfg = try { Get-Config } catch { $null }
if (-not $cfg -or -not $cfg.activo) { exit }

$procs = @(Get-ServicioProcs)
$estado = Get-Estado
$colgado = $false
if ($procs.Count -gt 0 -and $estado -and $estado.latido) {
    # El servicio actualiza el latido como maximo cada ~75 s (60 s buscando + pulso de 15 s)
    $colgado = ((Get-Date) - [datetime]$estado.latido).TotalMinutes -gt 4
}

if ($procs.Count -gt 0 -and -not $colgado) { exit }

if ($colgado) {
    Write-Log 'Guardian: el servicio no da senales hace mas de 4 min; reiniciandolo'
    $procs | ForEach-Object { Stop-Process -Id $_.ProcessId -Force -ErrorAction SilentlyContinue }
    Stop-TodoPymobile
} else {
    Write-Log 'Guardian: el servicio no estaba corriendo; iniciandolo'
}
Start-Process powershell -WindowStyle Hidden -ArgumentList @(
    '-NoProfile', '-ExecutionPolicy', 'Bypass', '-WindowStyle', 'Hidden',
    '-File', "`"$(Join-Path $PSScriptRoot 'servicio.ps1')`"")
