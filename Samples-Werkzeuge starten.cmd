@echo off
set "SKRIPTE=%~dp0"
if not exist "%SKRIPTE%Samples-sortieren.ps1" set "SKRIPTE=E:\Sounds und Samples\_Sortier-Skript\"
if not exist "%SKRIPTE%Samples-sortieren.ps1" (
  echo Skript-Ordner nicht gefunden: E:\Sounds und Samples\_Sortier-Skript
  pause
  goto :eof
)
start "" powershell.exe -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -STA -File "%SKRIPTE%Samples-Werkzeuge.ps1"
