@echo off
:: Vuelve el iPhone a su ubicacion real. Queda desactivado hasta usar Enable.bat,
:: aunque se reinicie la PC.
powershell -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File "%~dp0sistema\control.ps1" -Accion desactivar
