# Rutas, configuracion y utilidades compartidas por todos los scripts.

$script:Raiz = Split-Path $PSScriptRoot -Parent                    # Documentos\Ubicacion iPhone
$script:ConfigFile = Join-Path $Raiz 'config.json'
# Fuera de OneDrive. GetFolderPath tambien funciona cuando la tarea corre sin sesion iniciada.
$script:Runtime = Join-Path ([Environment]::GetFolderPath('LocalApplicationData')) 'UbicacionIphone'
$script:Exe = Join-Path $Runtime 'venv\Scripts\pymobiledevice3.exe'
$script:Py = Join-Path $Runtime 'venv\Scripts\python.exe'
$script:DaemonScript = Join-Path $PSScriptRoot 'ubicacion_daemon.py'
$script:DaemonEstadoFile = Join-Path $Runtime 'daemon-estado.json'   # lo escribe ubicacion_daemon.py
$script:DaemonLog = Join-Path $Runtime 'daemon.log'
$script:LogFile = Join-Path $Runtime 'servicio.log'
$script:EstadoFile = Join-Path $Runtime 'estado.json'
$script:RsdFile = Join-Path $Runtime 'tunel-rsd.txt'
$script:TaskName = 'Ubicacion iPhone'

$env:PYTHONIOENCODING = 'utf-8'
$env:PYTHONUNBUFFERED = '1'

function Get-Config {
    # La primera vez (repo recien clonado) parte desde la configuracion de ejemplo
    if (-not (Test-Path -LiteralPath $ConfigFile)) {
        Copy-Item -LiteralPath (Join-Path $Raiz 'config.ejemplo.json') -Destination $ConfigFile
    }
    Get-Content -LiteralPath $ConfigFile -Raw -Encoding UTF8 | ConvertFrom-Json
}

# Lugares favoritos para Change location.bat (lugares.json es personal y no va al repo)
function Get-Lugares {
    $archivo = Join-Path $Raiz 'lugares.json'
    if (-not (Test-Path -LiteralPath $archivo)) { $archivo = Join-Path $Raiz 'lugares.ejemplo.json' }
    # En PowerShell 5.1 ConvertFrom-Json entrega la lista entera como un solo objeto; se desarma con el pipeline
    try { $datos = Get-Content -LiteralPath $archivo -Raw -Encoding UTF8 | ConvertFrom-Json; @($datos | ForEach-Object { $_ }) } catch { @() }
}

function Set-Config($cfg) {
    $cfg | ConvertTo-Json | Set-Content -LiteralPath $ConfigFile -Encoding UTF8
}

function Write-Log($msg) {
    try {
        # Rota el registro al pasar 1 MB para que no crezca sin limite
        if ((Test-Path $LogFile) -and (Get-Item $LogFile).Length -gt 1MB) {
            Move-Item -LiteralPath $LogFile -Destination "$LogFile.anterior" -Force
        }
        "$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') $msg" | Add-Content -LiteralPath $LogFile -Encoding UTF8
    } catch {}
}

function Set-Estado([string]$fase, [string]$detalle = '') {
    try {
        @{ fase = $fase; detalle = $detalle; latido = (Get-Date).ToString('o'); pid = $PID } |
            ConvertTo-Json | Set-Content -LiteralPath $EstadoFile -Encoding UTF8
    } catch {}
}

function Get-Estado {
    try { Get-Content -LiteralPath $EstadoFile -Raw -Encoding UTF8 | ConvertFrom-Json } catch { $null }
}

function Test-Admin {
    ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole(
        [Security.Principal.WindowsBuiltInRole]::Administrator)
}

# Procesos powershell que estan corriendo el servicio
function Get-ServicioProcs {
    Get-CimInstance Win32_Process -Filter "Name='powershell.exe'" |
        Where-Object { $_.CommandLine -match 'servicio\.ps1' -and $_.ProcessId -ne $PID }
}

# pymobiledevice3.exe lanza un python.exe hijo: hay que cerrar el arbol entero
function Stop-Tree($proc) {
    if ($proc -and -not $proc.HasExited) { taskkill /f /t /pid $proc.Id 2>&1 | Out-Null }
}

function Stop-TodoPymobile {
    taskkill /f /t /im pymobiledevice3.exe 2>&1 | Out-Null
}

function Get-DaemonEstado {
    try { Get-Content -LiteralPath $DaemonEstadoFile -Raw -Encoding UTF8 | ConvertFrom-Json } catch { $null }
}

# Procesos python del daemon (solo estos, no otros python del usuario)
function Stop-Mantenedores {
    Get-CimInstance Win32_Process -Filter "Name='python.exe'" |
        Where-Object { $_.CommandLine -match 'ubicacion_daemon\.py|mantener_ubicacion\.py' } |
        ForEach-Object { taskkill /f /t /pid $_.ProcessId 2>&1 | Out-Null }
}
