@echo off
:: Activa la ubicacion simulada (la de config.json). Pide permiso de administrador.
powershell -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File "%~dp0sistema\control.ps1" -Accion activar
