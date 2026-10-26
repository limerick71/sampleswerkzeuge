@echo off
title Duplikate - Vorschau
set "SKRIPTE=%~dp0"
if not exist "%SKRIPTE%Samples-sortieren.ps1" set "SKRIPTE=E:\Sounds und Samples\_Sortier-Skript\"
if not exist "%SKRIPTE%Samples-sortieren.ps1" (
  echo Skript-Ordner nicht gefunden: E:\Sounds und Samples\_Sortier-Skript
  pause
  goto :eof
)
cd /d "%SKRIPTE%"
powershell.exe -NoProfile -NoExit -ExecutionPolicy Bypass -File "%SKRIPTE%Duplikate-entfernen.ps1" 
goto :eof
:abbruch
echo Abgebrochen - es wurde nichts veraendert.
pause
