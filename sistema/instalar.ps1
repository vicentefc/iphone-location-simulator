# Instala o repara todo. Se puede ejecutar las veces que haga falta (no duplica nada).
# - Motor: Python 3.13 + pymobiledevice3 en AppData\Local\UbicacionIphone (fuera de OneDrive)
# - Arreglo para Windows en pymobiledevice3 (direcciones IPv6 del iPhone)
# - Tarea programada "Ubicacion iPhone": al encender la PC, al iniciar sesion, al volver de
#   suspension y cada 5 minutos, sin necesidad de iniciar sesion.
param([switch]$SinIniciar)
. (Join-Path $PSScriptRoot 'comun.ps1')

if (-not (Test-Admin)) {
    $args2 = @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', "`"$PSCommandPath`"")
    if ($SinIniciar) { $args2 += '-SinIniciar' }
    Start-Process powershell -Verb RunAs -ArgumentList $args2
    exit
}
$ErrorActionPreference = 'Stop'
New-Item -ItemType Directory -Force -Path $Runtime | Out-Null
Start-Transcript -LiteralPath (Join-Path $Runtime 'instalar.log') -Force | Out-Null
function Paso($t) { Write-Host "`n== $t" -ForegroundColor Cyan }

try {
    New-Item -ItemType Directory -Force -Path $Runtime | Out-Null

    # 1. Motor
    Paso 'Motor (Python 3.13 + pymobiledevice3)'
    $pyVenv = Join-Path $Runtime 'venv\Scripts\python.exe'
    if (-not (Test-Path $Exe)) {
        if (-not (Get-Command py -ErrorAction SilentlyContinue) -or -not (& py -3.13 --version 2>$null)) {
            throw 'Falta Python 3.13. Instalalo desde python.org (o con: winget install Python.Python.3.13) y vuelve a ejecutar.'
        }
        & py -3.13 -m venv (Join-Path $Runtime 'venv')
        & $pyVenv -m pip install --upgrade pip -q
    }
    # Version fija: el arreglo de abajo esta probado con esta version
    & $pyVenv -m pip install 'pymobiledevice3==11.43.1' -q
    Write-Host 'OK'

    # 2. Arreglo IPv6 para Windows
    Paso 'Arreglo de conexion por Wi-Fi'
    $ts = Join-Path $Runtime 'venv\Lib\site-packages\pymobiledevice3\remote\tunnel_service.py'
    $txt = [IO.File]::ReadAllText($ts)
    $viejo = 'except (ConnectionTerminatedError, asyncio.IncompleteReadError, asyncio.TimeoutError, OSError) as e:'
    $nuevo = 'except (ConnectionTerminatedError, asyncio.IncompleteReadError, asyncio.TimeoutError, OSError, UnicodeError) as e:'
    if ($txt.Contains($nuevo)) { Write-Host 'Ya aplicado' }
    elseif ($txt.Contains($viejo)) { [IO.File]::WriteAllText($ts, $txt.Replace($viejo, $nuevo)); Write-Host 'Aplicado' }
    else { Write-Host 'AVISO: no se encontro la linea a corregir; puede fallar al conectar' -ForegroundColor Yellow }

    # 3. Emparejamiento
    Paso 'Emparejamiento con el iPhone'
    $cfg = Get-Config
    $registro = Join-Path $env:USERPROFILE ".pymobiledevice3\remote_$($cfg.udid).plist"
    if (Test-Path $registro) { Write-Host 'OK' }
    else { Write-Host 'Falta emparejar: ejecuta "Pair iPhone.bat"' -ForegroundColor Yellow }

    # 4. Tarea programada
    Paso 'Tarea programada'
    $user = [Security.Principal.WindowsIdentity]::GetCurrent().Name
    $revisar = Join-Path $PSScriptRoot 'revisar.ps1'
    $action = New-ScheduledTaskAction -Execute 'powershell.exe' `
        -Argument "-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File `"$revisar`""
    $triggers = @(
        (New-ScheduledTaskTrigger -AtStartup),
        (New-ScheduledTaskTrigger -AtLogOn -User $user),
        (New-ScheduledTaskTrigger -Once -At (Get-Date) -RepetitionInterval (New-TimeSpan -Minutes 5))
    )
    # Al volver de suspension (evento 1 de Power-Troubleshooter)
    $cls = Get-CimClass -Namespace Root/Microsoft/Windows/TaskScheduler -ClassName MSFT_TaskEventTrigger
    $despertar = New-CimInstance -CimClass $cls -ClientOnly
    $despertar.Enabled = $true
    $despertar.Subscription = '<QueryList><Query Id="0" Path="System"><Select Path="System">*[System[Provider[@Name=''Microsoft-Windows-Power-Troubleshooter''] and EventID=1]]</Select></Query></QueryList>'
    $triggers += $despertar

    # S4U: corre aunque no hayas iniciado sesion, sin guardar tu contrasena
    $principal = New-ScheduledTaskPrincipal -UserId $user -LogonType S4U -RunLevel Highest
    $settings = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries `
        -StartWhenAvailable -MultipleInstances IgnoreNew -ExecutionTimeLimit (New-TimeSpan -Minutes 2) `
        -RestartCount 3 -RestartInterval (New-TimeSpan -Minutes 1)
    Register-ScheduledTask -TaskName $TaskName -Action $action -Trigger $triggers -Principal $principal `
        -Settings $settings -Description 'Mantiene la ubicacion simulada del iPhone (Documentos\Ubicacion iPhone)' -Force | Out-Null
    Write-Host 'OK'

    if (-not $SinIniciar) {
        Paso 'Iniciando'
        $cfg.activo = $true; Set-Config $cfg
        # Cierra el servicio actual y cualquier version vieja (vigilante.ps1) para que no compitan
        Get-CimInstance Win32_Process -Filter "Name='powershell.exe'" |
            Where-Object { $_.CommandLine -match 'servicio\.ps1|vigilante\.ps1' -and $_.ProcessId -ne $PID } |
            ForEach-Object { Stop-Process -Id $_.ProcessId -Force -ErrorAction SilentlyContinue }
        Stop-TodoPymobile
        Stop-Mantenedores
        Start-ScheduledTask -TaskName $TaskName
        Write-Host 'OK'
    }
    Write-Host "`nListo." -ForegroundColor Green
} catch {
    Write-Host "`nERROR: $($_.Exception.Message) (linea $($_.InvocationInfo.ScriptLineNumber))" -ForegroundColor Red
}
Stop-Transcript | Out-Null
Start-Sleep 4
