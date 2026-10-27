@echo off
rem Testvorbereitung Samples-Werkzeuge: Inhalt des Ziels, erstes Pack SINEE... und "Vocal Loops 120" in den Papierkorb.
title Testvorbereitung Samples-Werkzeuge
if not exist "%~dp0Testvorbereitung.ps1" (
  echo.
  echo   Testvorbereitung.ps1 fehlt. Beide Dateien in denselben Ordner legen.
  echo.
  pause
  exit /b 1
)
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0Testvorbereitung.ps1" %*
echo.
pause
