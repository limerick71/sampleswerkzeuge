# Samples-Werkzeuge

PowerShell-Werkzeuge zum Sortieren und Verwalten einer Audio-Sample-Bibliothek unter Windows
(ohne Installation, Windows PowerShell 5.1). Aufbau und Bedienung wie die
[Plugin-Werkzeuge](https://github.com/limerick71/plugininventur).

Download: [neueste Version](https://github.com/limerick71/sampleswerkzeuge/releases/latest)

## Ordnerstruktur

| Pfad | Inhalt |
|---|---|
| `GUI_Samples-Werkzeuge.cmd` | Startet die Oberfläche |
| `Samples sortieren.cmd`, `Inventur starten.cmd`, `Quelle aufraeumen.cmd` | Starten die Funktionen ohne Oberfläche |
| `Erste Schritte.txt`, `Dokumentation Samples-Werkzeuge.rtf` | Anleitungen |
| `Test/` | `Testvorbereitung.cmd/.ps1` – nur für Tests: Ziel leeren, erstes Pack „SINEE…“ und „Vocal Loops 120“ in der Quelle in den Papierkorb |
| `Skripte/` | `Gemeinsam.ps1` (Pfade, Einstellungen), `Samples-Werkzeuge.ps1` (Oberfläche), `Samples-sortieren.ps1`, `Inventur.ps1`, `Bericht.ps1` (HTML-Bericht), `Bericht-Dienst.ps1` (lokaler Dienst für Abspielen, Löschen und Ordner öffnen aus dem Bericht sowie für den Fundort-Bericht), `Fundorte-suchen.ps1` (Suchlauf nach Sample-Packs), `Fundorte-Bericht.ps1` (Seite des Fundort-Berichts), `Ziel-Duplikate-entfernen.ps1`, `Quelle-aufraeumen.ps1`; zur Laufzeit `Einstellungen.json` und `Pack-Arten.csv` |
| `Inventuren/`, `Inventur-Vergleiche/` | entstehen zur Laufzeit im Berichtsordner: Inventur (CSV, JSON), HTML-Bericht, Vergleiche |
| `Protokolle/` | entsteht zur Laufzeit: Vorschauen und Protokolle (CSV) |
| `tools/` | nur im Repository: erzeugt die RTF-Dokumentation (`python3 tools/dokumentation.py`) |

## Versionen

| Version | Datum | Inhalt |
|---|---|---|
| 2.3.3 | 28.10.2026 | Befunde aus dem Test der 2.3.2: keine Installer, Plugin-Inhalte und Archive kopieren; Sammelordner nur als „Nur lose Dateien“; Pack-Ebene (z. B. Splice); lange Pfade; neue Instrumente und Kategorie 13 Strings & Orchestra; RX2 als Loop neben der WAV; Formate im Ziel entfernen |
| 2.3.2 | 28.10.2026 | Befunde aus dem Test der 2.3.1: Entfernen in den Einstellungen, Art in der Liste mit Erklärung ⓘ, Vocals über Ordnernamen, „Einzeldateien (…)“ bei losen Dateien; Fundort-Bericht mit ZIP-Inhalt, Ableton-Erkennung, „Letzten Bericht öffnen“, Abgleich mit dem Ziel-Ordner auch für Quellen |
| 2.3.1 | 28.10.2026 | Art einer Quelle (Sammlung, Ein Pack, Nur lose Dateien); richtiger Pack-Name bei einzelnen Packs; lose Dateien in Downloads übernehmbar |
| 2.3.0 | 28.10.2026 | Fundorte suchen (Suchlauf, Bericht, Übernahme als Quellen); Quellenliste statt einer Quelle; Sortieren und Aufräumen über mehrere Quellen; Befunde aus dem Test der 2.2 |
| 2.2.0 | 27.10.2026 | „Ordner öffnen“ im Bericht; Formate in „Quelle aufräumen“ eigens wählbar; Gruppe „Originale“ (Kopie im Ziel per Prüfsumme bestätigt); Warnung, wenn die Menge nicht in den Papierkorb passt |
| 2.1.0 | 27.10.2026 | Sortieren verändert die Quelle nie; „Quelle aufräumen“ (Duplikate, macOS-Reste, Formate) ersetzt „Duplikate entfernen“; Häkchen RX2/MP3/AIFF neben gleichnamiger WAV; macOS-Reste per Dateikopf; MP3-Eigenschaften; Löschen von Duplikaten aus dem Bericht; Packs-Ansicht nach Packname; Einstellungen im eigenen Fenster (⚙), Status mit Pfaden |
| 2.0.0 | 26.10.2026 | Inventur der Bibliothek (Pack-Art, Audio-Eigenschaften, BPM, Tonart, Duplikate, Vergleich), HTML-Bericht im Stil der Plugin-Werkzeuge (Samples/Packs/Duplikate, Gliederung, Filter, Abspielen), Duplikate im Ziel entfernen, macOS-Reste beim Sortieren in den Papierkorb, Häkchen „RX2 beibehalten“ |
| 1.2.1 | 26.10.2026 | W-07b: Quelle ohne Audiodateien zeigt nur einen Hinweis; Hilfsdateien mit Grund in Vorschau und Dokumentation; ModX-Hinweis nur bei vorhandenem Ordner |
| 1.2.0 | 26.10.2026 | Abgleich neuer Dateien mit dem ganzen Ziel nach Inhalt (Vorfilter Größe, dann Prüfsumme): gleicher Inhalt in anderem Ordner oder unter anderem Namen wird nicht erneut kopiert; Kits ausgenommen; Spalte „Hinweis“ in Vorschau und Protokoll |
| 1.1.0 | 26.10.2026 | Befunde aus dem Windows-Test: ZIP ohne doppelten Ordner, fehlendes Ziel-Laufwerk wird gemeldet, verständliche Zusammenfassung, Vorschau und Protokoll, bereits vorhandene Dateien schon in der Vorschau erkannt, Junctions übersprungen, Quelle ohne Audiodateien wird abgewiesen |
| 1.0.0 | 26.10.2026 | Ordnerstruktur wie Plugin-Werkzeuge, einstellbare Ordner (Quelle, Ziel, Downloads, Download-Archiv, Berichte), neue Oberfläche mit Status, Begrüßung und Desktop-Verknüpfung, Vorschau mit Rückfrage, Protokolle in eigenem Ordner, Einstellungen werden von der Vorversion übernommen |
| 0 | 21.10.2026 | Ausgangsstand: Sortieren, Duplikate entfernen, einfache Oberfläche, feste Pfade |

Geplant: Version 3 Import aus Downloads, danach Bereinigung am Ursprungsort.

© 2026 Herbert Stöcker. Kostenlos nutzbar. Bitte nur als Link auf die offizielle Download-Seite
weitergeben; Verkauf und Veröffentlichung geänderter Fassungen nur mit Zustimmung.
