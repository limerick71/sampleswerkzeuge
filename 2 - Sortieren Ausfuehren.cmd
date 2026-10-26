@echo off
title Samples sortieren - Kopieren
set "SKRIPTE=%~dp0"
if not exist "%SKRIPTE%Samples-sortieren.ps1" set "SKRIPTE=E:\Sounds und Samples\_Sortier-Skript\"
if not exist "%SKRIPTE%Samples-sortieren.ps1" (
  echo Skript-Ordner nicht gefunden: E:\Sounds und Samples\_Sortier-Skript
  pause
  goto :eof
)
cd /d "%SKRIPTE%"
echo.
echo Die Samples werden jetzt nach E:\Samples kopiert (nichts wird geloescht oder ueberschrieben).
echo.
choice /C JN /M "Wirklich fortfahren? (J = Ja, N = Nein)"
if errorlevel 2 goto abbruch
powershell.exe -NoProfile -NoExit -ExecutionPolicy Bypass -File "%SKRIPTE%Samples-sortieren.ps1" -Ausfuehren
goto :eof
:abbruch
echo Abgebrochen - es wurde nichts veraendert.
pause
