@echo off
rem (c) 2026 Herbert Stoecker. YAMNet-Prototyp fuer die Samples-Werkzeuge - nur zum Testen.
rem Startet das Fenster (ohne sichtbares Konsolenfenster).
if not exist "%~dp0Skripte\YAMNet-Analyse.ps1" (
  echo.
  echo   Der Ordner "Skripte" wurde nicht gefunden. Bitte die ZIP-Datei zuerst entpacken.
  echo.
  pause
  exit /b 1
)
if exist "%SystemRoot%\System32\conhost.exe" (
  start "" "%SystemRoot%\System32\conhost.exe" powershell.exe -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File "%~dp0Skripte\YAMNet-Analyse.ps1"
) else (
  start "" powershell.exe -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File "%~dp0Skripte\YAMNet-Analyse.ps1"
)
