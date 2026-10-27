@echo off
rem (c) 2026 Herbert Stoecker. Kostenlos nutzbar. Bitte nur als Link auf die offizielle Download-Seite weitergeben; Verkauf und Veroeffentlichung geaenderter Fassungen nur mit Zustimmung.
title Quelle aufraeumen
rem Entfernt Entbehrliches aus der Quelle (Auswahl, Vorschau, Rueckfrage, Papierkorb).
if not exist "%~dp0Skripte\Quelle-aufraeumen.ps1" (
  echo.
  echo   Der Ordner "Skripte" wurde nicht gefunden.
  echo   Wahrscheinlich wurde die Datei direkt aus der ZIP-Datei gestartet.
  echo   Bitte die ZIP-Datei zuerst entpacken: Rechtsklick ^> "Alle extrahieren ..."
  echo   und dann die Datei im entpackten Ordner starten.
  echo.
  pause
  exit /b 1
)
cd /d "%~dp0"
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0Skripte\Quelle-aufraeumen.ps1"
echo.
pause
