# Acciones que necesitan administrador: activar, desactivar, reiniciar.
param([ValidateSet('activar', 'desactivar', 'reiniciar')][string]$Accion,
      [string]$Lat, [string]$Lon, [string]$Nombre)
. (Join-Path $PSScriptRoot 'comun.ps1')

if (-not (Test-Admin)) {
    $a = @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-WindowStyle', 'Hidden', '-File', "`"$PSCommandPath`"", '-Accion', $Accion)
    if ($Lat) { $a += @('-Lat', $Lat, '-Lon', $Lon, '-Nombre', "`"$Nombre`"") }
    Start-Process powershell -Verb RunAs -WindowStyle Hidden -ArgumentList $a
    exit
}

$cfg = Get-Config
if ($Lat) { $cfg.latitud = $Lat; $cfg.longitud = $Lon; $cfg.nombre = $Nombre }

switch ($Accion) {
    'desactivar' {
        $cfg.activo = $false; Set-Config $cfg
        # Al cerrarse el canal de simulacion, el iPhone vuelve a su ubicacion real en unos segundos
        Get-ServicioProcs | ForEach-Object { Stop-Process -Id $_.ProcessId -Force -ErrorAction SilentlyContinue }
        Stop-Mantenedores
        Stop-TodoPymobile
        Set-Estado 'desactivado'
        Write-Log 'Desactivado por el usuario; ubicacion real restaurada'
    }
    default {
        # activar / reiniciar: el servicio arranca desde la tarea, igual que al encender la PC
        $cfg.activo = $true; Set-Config $cfg
        Get-ServicioProcs | ForEach-Object { Stop-Process -Id $_.ProcessId -Force -ErrorAction SilentlyContinue }
        Stop-TodoPymobile
        Stop-Mantenedores
        Write-Log "Activado por el usuario: $($cfg.nombre)"
        Start-ScheduledTask -TaskName $TaskName
    }
}
