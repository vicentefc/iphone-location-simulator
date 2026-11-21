# Supervisor. Corre oculto como administrador (lo lanza la tarea "Ubicacion iPhone").
# Todo el trabajo con el iPhone lo hace ubicacion_daemon.py (conexion, tunel, imagen de
# desarrollador y reenvio de la ubicacion). Este script solo:
#   - lo mantiene vivo y lo relanza si termina o se cuelga,
#   - aplica cambios de config.json (otro lugar, o desactivar),
#   - publica el estado en estado.json para Status.bat y para el guardian (revisar.ps1).
. (Join-Path $PSScriptRoot 'comun.ps1')

# Un solo supervisor y un solo daemon a la vez
Get-ServicioProcs | ForEach-Object { Stop-Process -Id $_.ProcessId -Force -ErrorAction SilentlyContinue }
Stop-TodoPymobile
Stop-Mantenedores

# Pide a Windows no suspenderse por inactividad mientras el servicio corre (como un reproductor de video).
# No evita la suspension al cerrar la tapa: eso depende de la configuracion de energia.
Add-Type -Namespace Win32 -Name Power -MemberDefinition @'
[DllImport("kernel32.dll")] public static extern uint SetThreadExecutionState(uint esFlags);
'@
$ES_CONTINUOUS = [uint32]'0x80000000'
$ES_SYSTEM_REQUIRED = [uint32]'0x00000001'

$cfg = Get-Config
Write-Log "Servicio iniciado: $($cfg.nombre) ($($cfg.latitud), $($cfg.longitud))"
$daemon = $null
$ultimaRevisionConfig = Get-Date

function Start-Daemon {
    Remove-Item -LiteralPath $DaemonEstadoFile -ErrorAction SilentlyContinue
    $script:inicioDaemon = Get-Date
    # radio en metros: 0 o ausente = quieto; mayor que 0 = camina alrededor del punto
    $radio = if ($cfg.radio) { $cfg.radio } else { '0' }
    Start-Process -FilePath $Py -PassThru -WindowStyle Hidden `
        -ArgumentList @("`"$DaemonScript`"", $cfg.udid, $cfg.latitud, $cfg.longitud, "`"$Runtime`"", $radio) `
        -RedirectStandardError (Join-Path $Runtime 'daemon-errores.log')
}

while ($true) {
    try {
        [Win32.Power]::SetThreadExecutionState($ES_CONTINUOUS -bor $ES_SYSTEM_REQUIRED) | Out-Null

        if (-not $daemon -or $daemon.HasExited) {
            if ($daemon) {
                $err = Get-Content -LiteralPath (Join-Path $Runtime 'daemon-errores.log') -Tail 1 -ErrorAction SilentlyContinue
                Write-Log "El daemon termino (codigo $($daemon.ExitCode)) $err; relanzandolo"
                Start-Sleep 2
            }
            $daemon = Start-Daemon
        }

        # Estado para Status.bat y el guardian
        $d = Get-DaemonEstado
        if ($d) {
            Set-Estado $d.fase $(if ($d.fase -eq 'activo') { "$($cfg.nombre) ($($cfg.latitud), $($cfg.longitud))" } else { $d.detalle })
            # Daemon colgado: su latido se actualiza al menos cada pocos segundos mientras trabaja
            $edadLatido = ((Get-Date) - [datetime]$d.latido).TotalSeconds
            if ($edadLatido -gt 180) {
                Write-Log "El daemon no da senales hace $([int]$edadLatido) s; reiniciandolo"
                Stop-Tree $daemon
                Stop-TodoPymobile
            }
        } else {
            Set-Estado 'iniciando' 'Iniciando la conexion'
            if (((Get-Date) - $inicioDaemon).TotalSeconds -gt 180) {
                Write-Log 'El daemon no arranco en 3 min; reiniciandolo'
                Stop-Tree $daemon
            }
        }

        # Cada 15 s: si cambiaron la ubicacion o la desactivaron en config.json, aplica el cambio.
        # (OneDrive puede bloquear el archivo un instante: si falla la lectura, se ignora.)
        if (((Get-Date) - $ultimaRevisionConfig).TotalSeconds -ge 15) {
            $ultimaRevisionConfig = Get-Date
            $nuevo = try { Get-Config } catch { $null }
            if ($nuevo -and -not $nuevo.activo) {
                Write-Log 'Desactivado en config.json; el servicio se detiene'
                Stop-Tree $daemon
                Set-Estado 'desactivado'
                break
            }
            if ($nuevo -and ($nuevo.latitud -ne $cfg.latitud -or $nuevo.longitud -ne $cfg.longitud -or $nuevo.udid -ne $cfg.udid -or $nuevo.radio -ne $cfg.radio)) {
                $cfg = $nuevo
                Write-Log "Nueva ubicacion: $($cfg.nombre) ($($cfg.latitud), $($cfg.longitud))"
                Stop-Tree $daemon
                $daemon = $null
                continue
            }
        }
    } catch {
        Write-Log "Error en el supervisor: $($_.Exception.Message)"
        Start-Sleep 5
    }
    Start-Sleep 2
}
[Win32.Power]::SetThreadExecutionState($ES_CONTINUOUS) | Out-Null
