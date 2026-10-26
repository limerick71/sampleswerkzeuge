@echo off
title Verknuepfungen anlegen
set "SKRIPTE=%~dp0"
if not exist "%SKRIPTE%Samples-sortieren.ps1" set "SKRIPTE=E:\Sounds und Samples\_Sortier-Skript\"
if not exist "%SKRIPTE%Samples-sortieren.ps1" (
  echo Skript-Ordner nicht gefunden: E:\Sounds und Samples\_Sortier-Skript
  pause
  goto :eof
)
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%SKRIPTE%Verknuepfungen-anlegen.ps1"
pause
