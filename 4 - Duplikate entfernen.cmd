@echo off
title Duplikate entfernen
set "SKRIPTE=%~dp0"
if not exist "%SKRIPTE%Samples-sortieren.ps1" set "SKRIPTE=E:\Sounds und Samples\_Sortier-Skript\"
if not exist "%SKRIPTE%Samples-sortieren.ps1" (
  echo Skript-Ordner nicht gefunden: E:\Sounds und Samples\_Sortier-Skript
  pause
  goto :eof
)
cd /d "%SKRIPTE%"
echo.
echo Die doppelten Samples werden jetzt in den Papierkorb verschoben.
echo.
choice /C JN /M "Wirklich fortfahren? (J = Ja, N = Nein)"
if errorlevel 2 goto abbruch
powershell.exe -NoProfile -NoExit -ExecutionPolicy Bypass -File "%SKRIPTE%Duplikate-entfernen.ps1" -Ausfuehren
goto :eof
:abbruch
echo Abgebrochen - es wurde nichts veraendert.
pause
