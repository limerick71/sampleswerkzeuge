# Erzeugt "Dokumentation Samples-Werkzeuge.rtf" (Aufruf: python3 tools/dokumentation.py)
import os
V = "1.2.0"
D = [
("h1", f"Samples-Werkzeuge {V} – Dokumentation"),
("p", "Die Samples-Werkzeuge kopieren Sample-Packs aus einem Quellordner sortiert nach Instrument in eine Sample-Bibliothek und entfernen auf Wunsch doppelte Samples im Quellordner. Sie laufen mit dem Windows PowerShell, das bei Windows 10 und 11 dabei ist. Eine Installation ist nicht nötig."),
("h2", "1. Ordnerstruktur"),
("li", "GUI_Samples-Werkzeuge.cmd – startet die Oberfläche."),
("li", "Samples sortieren.cmd, Duplikate entfernen.cmd – starten die Funktionen direkt ohne Oberfläche."),
("li", "Erste Schritte.txt, Dokumentation Samples-Werkzeuge.rtf – Anleitungen."),
("li", "Skripte – die PowerShell-Skripte und die Datei Einstellungen.json mit den gewählten Ordnern."),
("li", "Protokolle – Vorschauen und Protokolle aller Läufe als CSV (Semikolon-getrennt, für Excel)."),
("p", "Jede Version liegt in einem eigenen Ordner, z. B. Samples-Werkzeuge_1. Liegen die Versionen nebeneinander im selben Ordner, übernimmt eine neue Version beim ersten Start die Einstellungen der zuletzt genutzten Version. Die Ordner bitte trotzdem unter „Einstellungen“ prüfen."),
("h2", "2. Oberfläche"),
("p", "Status: zeigt, ob Quelle und Ziel gefunden werden, wann zuletzt kopiert und wann zuletzt Duplikate entfernt wurden, und ob die Desktop-Verknüpfung auf diese Version zeigt. Der Status wird jedes Mal aktualisiert, wenn das Fenster wieder in den Vordergrund kommt."),
("p", "1 Sortieren: „Samples sortieren …“ startet die Sortierung (siehe 4). „Letztes Protokoll öffnen“ öffnet das Protokoll des letzten Kopierlaufs. „Ziel öffnen“ und „Quelle öffnen“ zeigen die Ordner im Explorer."),
("p", "2 Duplikate: „Duplikate entfernen …“ startet die Bereinigung (siehe 5). „Papierkorb öffnen“ zeigt den Windows-Papierkorb. Außerdem lassen sich der Protokoll- und der Programmordner öffnen."),
("p", "3 Einstellungen: Mit „Ändern …“ wird für jeden Ordner ein Ordner ausgewählt; die Auswahl wird sofort gespeichert. Quelle und Ziel dürfen nicht gleich sein und nicht ineinander liegen, sonst wird die Änderung abgelehnt."),
("p", "Unten: Desktop-Verknüpfung anlegen bzw. auf diese Version umstellen, Dokumentation öffnen, Schließen."),
("h2", "3. Einstellungen"),
("li", "Quelle (Standard E:\\Sounds und Samples): unsortierte Sample-Packs. Wird beim Sortieren nur gelesen."),
("li", "Ziel (Standard E:\\Samples): sortierte Bibliothek. Wird beim ersten Kopieren angelegt."),
("li", "Downloads (Standard: Download-Ordner des Benutzers): ab Version 3 für den Import neuer Packs."),
("li", "Download-Archiv (Standard E:\\Samples-Archiv\\Downloads): ab Version 3 für archivierte Original-Downloads."),
("li", "Berichte (Standard: Programmordner): ab Version 2 für Inventuren und Inventur-Vergleiche."),
("h2", "4. Samples sortieren"),
("p", "Das Skript liest alle Dateien der Quelle, ordnet jede Datei einer Kategorie zu und zeigt eine Zusammenfassung: wie viele Dateien neu sind und kopiert werden, wie viele schon im Ziel liegen und übersprungen werden, wie viele in der Quelle doppelt sind und wie viele Hilfsdateien ignoriert werden. Die vollständige Liste wird als Vorschau_<Datum>.csv im Ordner Protokolle gespeichert; sie zeigt nur, was passieren würde („wird kopiert“, „bereits im Ziel – wird nicht kopiert“ …). Danach fragt das Skript, ob die neuen Dateien kopiert werden sollen; Standard ist Nein. Bei Abbruch entsteht kein Protokoll. Nach dem Kopieren entsteht Protokoll_<Datum>.csv mit dem Ergebnis („kopiert“, „bereits im Ziel – nicht kopiert“ …); eine Kopie davon liegt im Zielordner. Gibt es nichts Neues, endet das Skript mit „Nichts Neues zu kopieren“."),
("p", "Regeln:"),
("li", "Zielstruktur: Kategorie\\Instrument\\One-Shots oder Loops\\Pack\\Datei, z. B. 01 Drums\\Kick\\One-Shots\\<Pack>\\BD 14.wav. Kategorien: 01 Drums, 02 Percussion, 03 Bass, 04 Keys & Synth, 05 Guitar, 06 Brass & Sax, 07 Vocals, 08 FX & Noise, 09 Atmos & Field Recordings, 10 Construction Kits, 11 MIDI, 12 Songs & Playalongs, _Lizenzen & Infos, _Sonstiges, _Unsortiert."),
("li", "Das Instrument wird aus dem Dateinamen erkannt, sonst aus den Ordnernamen. One-Shot oder Loop ergibt sich aus Namen, Ordnern oder der Länge der WAV-Datei (ab 6 Sekunden Loop)."),
("li", "Dateinamen bleiben unverändert. Identische Dateien (Name, Größe und Inhalt) werden nur einmal kopiert und als „Duplikat – übersprungen“ protokolliert."),
("li", "Construction Kits und Drum-Kits bleiben als Ganzes erhalten."),
("li", "Abgleich mit dem Ziel: Liegt derselbe Inhalt schon irgendwo im Ziel – in einem anderen Ordner oder unter einem anderen Namen –, wird die Datei nicht erneut kopiert. Dazu werden zuerst die Dateigrößen verglichen; nur bei gleicher Größe wird der Inhalt per Prüfsumme bestätigt. Die Vorschau zeigt in der Spalte „Hinweis“, ob es dieselbe Datei unter gleichem Namen oder eine umbenannte Kopie ist, und in „Ziel“ den Fundort. Dateien aus Drum-Kits und Construction Kits sind ausgenommen, damit die Kits vollständig bleiben."),
("li", "Der Ordner ModX (Yamaha-Bibliotheken), Ableton-Analysedateien (.asd) und Systemdateien werden nicht kopiert. Liegt der Programmordner in der Quelle, wird er ebenfalls ausgelassen."),
("li", "Vorhandene Dateien im Ziel werden nie überschrieben. Ein zweiter Lauf kopiert nur Neues."),
("li", "Vor dem Kopieren wird der freie Speicher geprüft. Reicht er nicht, wird nicht kopiert."),
("li", "Ordner-Verknüpfungen (Junctions) in der Quelle werden nicht verfolgt, nicht lesbare Ordner ausgelassen und gezählt. Enthält die Quelle keine einzige Audiodatei, wird nichts kopiert – meist ist dann der falsche Ordner eingestellt."),
("li", "Ist das Laufwerk des Ziels nicht vorhanden (z. B. E: auf einem anderen Rechner), zeigt der Status „NICHT GEFUNDEN“ und das Sortieren startet nicht."),
("h2", "5. Duplikate entfernen"),
("p", "Grundlage ist das neueste Protokoll eines Kopierlaufs (im Ordner Protokolle, ersatzweise im Zielordner oder im alten Skript-Ordner von Version 0). Für jede als Duplikat markierte Datei wird geprüft: Sie liegt in der Quelle, ist eine Audiodatei, existiert noch, und das behaltene Original existiert mit identischem Inhalt (SHA-256). Nur dann wird sie entfernt."),
("p", "Nach der Vorschau (Duplikate-Vorschau_<Datum>.csv) fragt das Skript nach; Standard ist Nein. Die Dateien und ihre .asd-Dateien gehen in den Windows-Papierkorb; leer gewordene Ordner ebenfalls. Ergebnis: Duplikate-entfernt_<Datum>.csv."),
("p", "Hinweis: Der Papierkorb hat je Laufwerk eine Größengrenze. Ist sie überschritten, kann Windows Dateien endgültig löschen statt sie in den Papierkorb zu legen. Eine Warnung davor folgt in einer späteren Version."),
("h2", "6. Start ohne Oberfläche"),
("p", "Die Skripte lassen sich auch über die .cmd-Dateien oder in PowerShell starten. Schalter: -NurVorschau (nur Vorschau, keine Frage), -Ausfuehren (ohne Frage ausführen), -Quelle und -Ziel (abweichende Ordner für diesen Lauf)."),
("h2", "7. Umstieg von Version 0"),
("li", "Version 0 lag im Ordner E:\\Sounds und Samples\\_Sortier-Skript. Sie kann bleiben; Version 1 liest dort bei Bedarf das alte Protokoll für die Duplikat-Bereinigung."),
("li", "Die Desktop-Verknüpfung „Samples-Werkzeuge“ wird beim ersten Start auf Version 1 umgestellt. Den alten Desktop-Ordner „Samples-Werkzeuge“ mit den Verknüpfungen 1–4 bitte von Hand löschen."),
("h2", "8. Versionen"),
("li", "1.2.0 (26.10.2026): Abgleich neuer Dateien mit dem ganzen Ziel nach Inhalt (Größe, dann Prüfsumme); gleicher Inhalt in anderem Ordner oder unter anderem Namen wird nicht erneut kopiert."),
("li", "1.1.0 (26.10.2026): Befunde aus dem ersten Windows-Test behoben: ZIP ohne doppelten Ordner, fehlendes Ziel-Laufwerk wird gemeldet, verständliche Zusammenfassung und Vorschau, bereits vorhandene Dateien schon in der Vorschau erkannt, Junctions werden übersprungen."),
("li", "1.0.0 (26.10.2026): Ordnerstruktur wie die Plugin-Werkzeuge, einstellbare Ordner, neue Oberfläche mit Status, Begrüßung und Desktop-Verknüpfung, Vorschau mit Rückfrage statt getrennter Starter, Protokolle in eigenem Ordner."),
("li", "0 (21.10.2026): Sortieren, Duplikate entfernen, einfache Oberfläche, feste Pfade."),
("h2", "Download und Urheberrecht"),
("p", "Neueste Version: https://github.com/limerick71/sampleswerkzeuge/releases/latest"),
("p", "© 2026 Herbert Stöcker. Kostenlos nutzbar. Bitte nur als Link auf die offizielle Download-Seite weitergeben; Verkauf und Veröffentlichung geänderter Fassungen nur mit Zustimmung. Die Nutzung erfolgt auf eigene Verantwortung."),
]
def esc(t):
    o=[]
    for ch in t:
        c=ord(ch)
        if ch in '\\{}': o.append('\\'+ch)
        elif c>127: o.append('\\u%d?' % (c if c<32768 else c-65536))
        else: o.append(ch)
    return ''.join(o)
r=[r"{\rtf1\ansi\ansicpg1252\deff0{\fonttbl{\f0\fswiss Segoe UI;}}{\colortbl;\red31\green78\blue121;}\viewkind4\uc1\f0\fs20"]
for k,t in D:
    if k=="h1": r.append(r"\pard\sa200\cf1\b\fs32 "+esc(t)+r"\b0\cf0\fs20\par")
    elif k=="h2": r.append(r"\pard\sb240\sa100\cf1\b\fs24 "+esc(t)+r"\b0\cf0\fs20\par")
    elif k=="li": r.append(r"\pard\fi-280\li560\sa60\bullet\tab "+esc(t)+r"\par")
    else: r.append(r"\pard\sa120 "+esc(t)+r"\par")
r.append("}")
out=os.path.join(os.path.dirname(os.path.abspath(__file__)),"..","Dokumentation Samples-Werkzeuge.rtf")
open(out,"w",encoding="ascii",newline="\r\n").write("\n".join(r)+"\n")
print(out)
