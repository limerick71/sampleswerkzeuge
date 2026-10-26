@echo off
rem (c) 2026 Herbert Stoecker. Kostenlos nutzbar. Bitte nur als Link auf die offizielle Download-Seite weitergeben; Verkauf und Veroeffentlichung geaenderter Fassungen nur mit Zustimmung.
rem Startet die Oberflaeche Samples-Werkzeuge (ohne sichtbares Konsolenfenster).
if not exist "%~dp0Skripte\Samples-Werkzeuge.ps1" (
  echo.
  echo   Der Ordner "Skripte" wurde nicht gefunden.
  echo   Wahrscheinlich wurde die Datei direkt aus der ZIP-Datei gestartet.
  echo   Bitte die ZIP-Datei zuerst entpacken: Rechtsklick ^> "Alle extrahieren ..."
  echo   und dann die Datei im entpackten Ordner starten.
  echo.
  pause
  exit /b 1
)
rem conhost: klassische Konsole, damit -WindowStyle Hidden auch mit Windows Terminal wirkt
if exist "%SystemRoot%\System32\conhost.exe" (
  start "" "%SystemRoot%\System32\conhost.exe" powershell.exe -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File "%~dp0Skripte\Samples-Werkzeuge.ps1"
) else (
  start "" powershell.exe -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File "%~dp0Skripte\Samples-Werkzeuge.ps1"
)
