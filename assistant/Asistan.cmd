@echo off
rem ETS2 Mod Asistanı (paket klasörünün kökünde durur)
start "" powershell.exe -NoProfile -ExecutionPolicy Bypass -STA -WindowStyle Hidden -File "%~dp0asistan\Start-Asistan.ps1"
