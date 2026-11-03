@echo off
rem ETS2 Konvoy Indirme Asistani (paket klasorunun kokunde durur)
start "" powershell.exe -NoProfile -ExecutionPolicy Bypass -STA -WindowStyle Hidden -File "%~dp0asistan\Start-Asistan.ps1"
