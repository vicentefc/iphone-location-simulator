# Empareja el iPhone con esta PC por Wi-Fi (iOS 27 o superior). Solo hace falta una vez,
# o de nuevo si el iPhone borra la PC de "Mac emparejados".
. (Join-Path $PSScriptRoot 'comun.ps1')
$Host.UI.RawUI.WindowTitle = 'Emparejar iPhone'

Write-Host ''
Write-Host '  En el iPhone (mismo Wi-Fi que esta PC):' -ForegroundColor Cyan
Write-Host '   1. Ajustes > Privacidad y seguridad > Modo de desarrollador: activado'
Write-Host '   2. Ajustes > Desarrollador > Mac emparejados'
Write-Host "   3. En 'Otros dispositivos' toca '$env:COMPUTERNAME' > Emparejar"
Write-Host '   4. Escribe el codigo de 6 digitos que aparece aqui abajo'
Write-Host ''
& $Exe remote pair-host --name $env:COMPUTERNAME --timeout 600
Write-Host ''
if ($LASTEXITCODE -eq 0) {
    # El udid nuevo queda en config.json por si se empareja otro iPhone
    $rec = Get-ChildItem (Join-Path $env:USERPROFILE '.pymobiledevice3') -Filter 'remote_*.plist' |
        Sort-Object LastWriteTime -Descending | Select-Object -First 1
    if ($rec) {
        $cfg = Get-Config
        $cfg.udid = $rec.BaseName -replace '^remote_', ''
        Set-Config $cfg
    }
    Write-Host '  Emparejado. Ahora usa Enable.bat' -ForegroundColor Green
} else {
    Write-Host '  No se completo el emparejamiento. Vuelve a intentarlo.' -ForegroundColor Red
}
Read-Host '  Presiona ENTER para cerrar'
