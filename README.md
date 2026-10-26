# Samples-Werkzeuge

PowerShell-Werkzeuge zum Sortieren und Verwalten einer Audio-Sample-Bibliothek unter Windows
(ohne Installation, Windows PowerShell 5.1). Aufbau und Bedienung wie die
[Plugin-Werkzeuge](https://github.com/limerick71/plugininventur).

Download: [neueste Version](https://github.com/limerick71/sampleswerkzeuge/releases/latest)

## Ordnerstruktur

| Pfad | Inhalt |
|---|---|
| `GUI_Samples-Werkzeuge.cmd` | Startet die Oberfläche |
| `Samples sortieren.cmd`, `Duplikate entfernen.cmd` | Starten die Funktionen ohne Oberfläche |
| `Erste Schritte.txt`, `Dokumentation Samples-Werkzeuge.rtf` | Anleitungen |
| `Skripte/` | `Gemeinsam.ps1` (Pfade, Einstellungen), `Samples-Werkzeuge.ps1` (Oberfläche), `Samples-sortieren.ps1`, `Duplikate-entfernen.ps1`; zur Laufzeit `Einstellungen.json` |
| `Protokolle/` | entsteht zur Laufzeit: Vorschauen und Protokolle (CSV) |
| `tools/` | nur im Repository: erzeugt die RTF-Dokumentation (`python3 tools/dokumentation.py`) |

## Versionen

| Version | Datum | Inhalt |
|---|---|---|
| 1.0.0 | 26.10.2026 | Ordnerstruktur wie Plugin-Werkzeuge, einstellbare Ordner (Quelle, Ziel, Downloads, Download-Archiv, Berichte), neue Oberfläche mit Status, Begrüßung und Desktop-Verknüpfung, Vorschau mit Rückfrage, Protokolle in eigenem Ordner, Einstellungen werden von der Vorversion übernommen |
| 0 | 21.10.2026 | Ausgangsstand: Sortieren, Duplikate entfernen, einfache Oberfläche, feste Pfade |

Geplant: Version 2 Inventur und HTML-Bericht, Version 3 Import aus Downloads, danach Bereinigung am Ursprungsort.

© 2026 Herbert Stöcker. Kostenlos nutzbar. Bitte nur als Link auf die offizielle Download-Seite
weitergeben; Verkauf und Veröffentlichung geänderter Fassungen nur mit Zustimmung.
