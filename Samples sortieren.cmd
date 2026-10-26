@echo off
rem (c) 2026 Herbert Stoecker. Kostenlos nutzbar. Bitte nur als Link auf die offizielle Download-Seite weitergeben; Verkauf und Veroeffentlichung geaenderter Fassungen nur mit Zustimmung.
title Samples sortieren
rem Zeigt eine Vorschau und fragt vor dem Kopieren nach.
if not exist "%~dp0Skripte\Samples-sortieren.ps1" (
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
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0Skripte\Samples-sortieren.ps1"
echo.
pause
