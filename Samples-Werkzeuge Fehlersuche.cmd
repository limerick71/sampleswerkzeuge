@echo off
title Samples-Werkzeuge - Fehlersuche
set "SKRIPTE=%~dp0"
if not exist "%SKRIPTE%Samples-sortieren.ps1" set "SKRIPTE=E:\Sounds und Samples\_Sortier-Skript\"
if not exist "%SKRIPTE%Samples-sortieren.ps1" (
  echo Skript-Ordner nicht gefunden: E:\Sounds und Samples\_Sortier-Skript
  pause
  goto :eof
)
echo Startet die Oberflaeche mit sichtbarem PowerShell-Fenster.
echo Eventuelle Fehlermeldungen erscheinen hier.
echo.
powershell.exe -NoProfile -NoExit -ExecutionPolicy Bypass -STA -File "%SKRIPTE%Samples-Werkzeuge.ps1"
