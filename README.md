# Samples-Werkzeuge

PowerShell-Werkzeuge zum Sortieren und Verwalten einer Audio-Sample-Bibliothek unter Windows
(ohne Installation, Windows PowerShell 5.1).

## Version 0 – Ausgangsstand

Übernommener Stand aus `E:\Sounds und Samples\_Sortier-Skript` vom 21.10.2026, unverändert.

| Datei | Zweck |
|---|---|
| `Samples-sortieren.ps1` | Kopiert Samples aus `E:\Sounds und Samples` nach `E:\Samples`, gegliedert nach Kategorie, Instrument, One-Shots/Loops und Pack. Ohne `-Ausfuehren` nur Vorschau (CSV). |
| `Duplikate-entfernen.ps1` | Verschiebt beim Kopieren übersprungene Duplikate nach Hash-Prüfung in den Papierkorb. Ohne `-Ausfuehren` nur Vorschau. |
| `Samples-Werkzeuge.ps1` | Kleine Oberfläche (Windows Forms) zum Starten der Skripte. |
| `*.cmd` | Starter zum Doppelklicken. |
| `Sortier-Skript How-To.txt` | Kurzanleitung. |

Bekannte Einschränkungen von Version 0:
- Pfade sind fest auf `E:\Sounds und Samples` und `E:\Samples` eingestellt.
- `0 - Desktop-Verknuepfungen anlegen.cmd` ruft `Verknuepfungen-anlegen.ps1` auf, die im Ausgangsordner fehlt.

Die Weiterentwicklung (Inventur, HTML-Bericht, Import aus Downloads, Bereinigung) folgt ab Version 1.

© 2026 Herbert Stöcker
