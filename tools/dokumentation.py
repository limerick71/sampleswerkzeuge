# Erzeugt "Dokumentation Samples-Werkzeuge.rtf" (Aufruf: python3 tools/dokumentation.py)
import os
V = "2.0.0"
D = [
("h1", f"Samples-Werkzeuge {V} – Dokumentation"),
("p", "Die Samples-Werkzeuge kopieren Sample-Packs aus einem Quellordner sortiert nach Instrument in eine Sample-Bibliothek, erstellen eine Inventur mit HTML-Bericht und entfernen auf Wunsch doppelte Samples in Quelle und Bibliothek. Sie laufen mit dem Windows PowerShell, das bei Windows 10 und 11 dabei ist. Eine Installation ist nicht nötig."),
("h2", "1. Ordnerstruktur"),
("li", "GUI_Samples-Werkzeuge.cmd – startet die Oberfläche."),
("li", "Samples sortieren.cmd, Inventur starten.cmd, Duplikate entfernen.cmd – starten die Funktionen direkt ohne Oberfläche."),
("li", "Erste Schritte.txt, Dokumentation Samples-Werkzeuge.rtf – Anleitungen."),
("li", "Skripte – die PowerShell-Skripte, Einstellungen.json (gewählte Ordner und Häkchen) und Pack-Arten.csv (eigene Korrekturen der Pack-Art)."),
("li", "Inventuren, Inventur-Vergleiche – Ergebnisse der Inventur (siehe 5). Sie liegen im Ordner „Berichte“, standardmäßig im Programmordner."),
("li", "Protokolle – Vorschauen und Protokolle aller Läufe als CSV (Semikolon-getrennt, für Excel)."),
("p", "Jede Version liegt in einem eigenen Ordner, z. B. Samples-Werkzeuge_1. Liegen die Versionen nebeneinander im selben Ordner, übernimmt eine neue Version beim ersten Start die Einstellungen und die Pack-Arten-Korrekturen der zuletzt genutzten Version. Die Ordner bitte trotzdem unter „Einstellungen“ prüfen."),
("h2", "2. Oberfläche"),
("p", "Status: zeigt, ob Quelle und Ziel gefunden werden, wann zuletzt kopiert wurde, die letzte Inventur mit Zahl der Samples, Packs und Duplikate, wann zuletzt Duplikate in der Quelle entfernt wurden, und ob die Desktop-Verknüpfung auf diese Version zeigt. Der Status wird jedes Mal aktualisiert, wenn das Fenster wieder in den Vordergrund kommt."),
("p", "1 Sortieren: „Samples sortieren …“ startet die Sortierung (siehe 4). „Letztes Protokoll öffnen“ öffnet das Protokoll des letzten Kopierlaufs. „Ziel öffnen“ und „Quelle öffnen“ zeigen die Ordner im Explorer. Das Häkchen „RX2 beibehalten“ (Standard: an) steuert den Umgang mit RX2-Dateien."),
("p", "2 Inventur und Bericht: „Inventur starten“ erfasst die Bibliothek (siehe 5), „Bericht öffnen“ zeigt den HTML-Bericht (siehe 6), „Liste öffnen (Excel)“ die Inventur als CSV, „Änderungen anzeigen“ den Vergleich mit der vorherigen Inventur. „Pack-Arten korrigieren“ öffnet Pack-Arten.csv, „Duplikate im Ziel entfernen …“ räumt die Bibliothek auf (siehe 7)."),
("p", "3 Duplikate in der Quelle: „Duplikate entfernen …“ (siehe 8). „Papierkorb öffnen“ zeigt den Windows-Papierkorb. Außerdem lassen sich der Protokoll- und der Programmordner öffnen."),
("p", "4 Einstellungen: Mit „Ändern …“ wird für jeden Ordner ein Ordner ausgewählt; die Auswahl wird sofort gespeichert. Quelle und Ziel dürfen nicht gleich sein und nicht ineinander liegen, sonst wird die Änderung abgelehnt."),
("p", "Unten: Desktop-Verknüpfung anlegen bzw. auf diese Version umstellen, Dokumentation öffnen, Schließen."),
("h2", "3. Einstellungen"),
("li", "Quelle (Standard E:\\Sounds und Samples): unsortierte Sample-Packs. Wird beim Sortieren nur gelesen."),
("li", "Ziel (Standard E:\\Samples): sortierte Bibliothek. Wird beim ersten Kopieren angelegt."),
("li", "Downloads (Standard: Download-Ordner des Benutzers): ab Version 3 für den Import neuer Packs."),
("li", "Download-Archiv (Standard E:\\Samples-Archiv\\Downloads): ab Version 3 für archivierte Original-Downloads."),
("li", "Berichte (Standard: Programmordner): hier entstehen die Unterordner Inventuren und Inventur-Vergleiche."),
("li", "RX2 beibehalten (Häkchen, Standard: an): siehe Abschnitt 4."),
("h2", "4. Samples sortieren"),
("p", "Das Skript liest alle Dateien der Quelle, ordnet jede Datei einer Kategorie zu und zeigt eine Zusammenfassung: wie viele Dateien neu sind und kopiert werden, wie viele schon im Ziel liegen und übersprungen werden, wie viele in der Quelle doppelt sind und wie viele Hilfsdateien ignoriert werden. Die vollständige Liste wird als Vorschau_<Datum>.csv im Ordner Protokolle gespeichert; sie zeigt nur, was passieren würde („wird kopiert“, „bereits im Ziel – wird nicht kopiert“ …). Danach fragt das Skript, ob die neuen Dateien kopiert werden sollen; Standard ist Nein. Bei Abbruch entsteht kein Protokoll. Nach dem Kopieren entsteht Protokoll_<Datum>.csv mit dem Ergebnis („kopiert“, „bereits im Ziel – nicht kopiert“ …); eine Kopie davon liegt im Zielordner. Gibt es nichts Neues, endet das Skript mit „Nichts Neues zu kopieren“."),
("p", "Regeln:"),
("li", "Zielstruktur: Kategorie\\Instrument\\One-Shots oder Loops\\Pack\\Datei, z. B. 01 Drums\\Kick\\One-Shots\\<Pack>\\BD 14.wav. Kategorien: 01 Drums, 02 Percussion, 03 Bass, 04 Keys & Synth, 05 Guitar, 06 Brass & Sax, 07 Vocals, 08 FX & Noise, 09 Atmos & Field Recordings, 10 Construction Kits, 11 MIDI, 12 Songs & Playalongs, _Lizenzen & Infos, _Sonstiges, _Unsortiert."),
("li", "Das Instrument wird aus dem Dateinamen erkannt, sonst aus den Ordnernamen. One-Shot oder Loop ergibt sich aus Namen, Ordnern oder der Länge der WAV-Datei (ab 6 Sekunden Loop)."),
("li", "Dateinamen bleiben unverändert. Identische Dateien (Name, Größe und Inhalt) werden nur einmal kopiert und als „Duplikat – übersprungen“ protokolliert."),
("li", "Construction Kits und Drum-Kits bleiben als Ganzes erhalten."),
("li", "Abgleich mit dem Ziel: Liegt derselbe Inhalt schon irgendwo im Ziel – in einem anderen Ordner oder unter einem anderen Namen –, wird die Datei nicht erneut kopiert. Dazu werden zuerst die Dateigrößen verglichen; nur bei gleicher Größe wird der Inhalt per Prüfsumme bestätigt. Die Vorschau zeigt in der Spalte „Hinweis“, ob es dieselbe Datei unter gleichem Namen oder eine umbenannte Kopie ist, und in „Ziel“ den Fundort. Dateien aus Drum-Kits und Construction Kits sind ausgenommen, damit die Kits vollständig bleiben."),
("li", "Der Ordner ModX (Yamaha-Bibliotheken) wird nicht kopiert. Liegt der Programmordner in der Quelle, wird er ebenfalls ausgelassen."),
("li", "Hilfsdateien werden nicht kopiert und bleiben in der Quelle. Das sind Dateien, die Programme oder Windows automatisch anlegen und die keinen Klang enthalten: Ableton-Analysedateien (.asd, legt Ableton bei Bedarf neu an), Ableton-Ordnerinformationen (Ableton Folder/Project Info), Metadaten-Dateien (.xmp), Windows-Dateien (Thumbs.db, desktop.ini) sowie Dateien der Samples-Werkzeuge selbst. Die Vorschau nennt in der Spalte „Hinweis“ für jede Hilfsdatei den Grund."),
("li", "macOS-Reste werden nicht kopiert und in der Quelle in den Papierkorb verschoben – zusammen mit dem Kopieren, nach derselben Rückfrage. Das sind Dateien, die mit „._“ beginnen (Finder-Zusatzinformationen, entstehen beim Packen auf einem Mac zu jeder Datei), .DS_Store-Dateien und der Inhalt von __MACOSX-Ordnern. Sie enthalten keinen Klang, auch wenn sie auf .wav enden."),
("li", "RX2/REX-Dateien: Mit Häkchen „RX2 beibehalten“ (Standard) werden sie wie andere Samples einsortiert. Ohne Häkchen werden RX2-Dateien, zu denen im selben Ordner eine WAV- oder AIFF-Datei mit gleichem Namen liegt, nicht kopiert und mit der Rückfrage in den Papierkorb verschoben. RX2-Dateien ohne solches Gegenstück werden trotzdem einsortiert, damit der Loop nicht verloren geht; die Vorschau vermerkt das im „Hinweis“."),
("li", "Vorhandene Dateien im Ziel werden nie überschrieben. Ein zweiter Lauf kopiert nur Neues."),
("li", "Vor dem Kopieren wird der freie Speicher geprüft. Reicht er nicht, wird nicht kopiert."),
("li", "Ordner-Verknüpfungen (Junctions) in der Quelle werden nicht verfolgt, nicht lesbare Ordner ausgelassen und gezählt. Enthält die Quelle keine einzige Audiodatei, wird nichts kopiert – meist ist dann der falsche Ordner eingestellt."),
("li", "Ist das Laufwerk des Ziels nicht vorhanden (z. B. E: auf einem anderen Rechner), zeigt der Status „NICHT GEFUNDEN“ und das Sortieren startet nicht."),
("h2", "5. Inventur"),
("p", "Die Inventur liest die ganze Bibliothek (Ziel) und verändert nichts. Die Quelle wird nicht gebraucht; woher eine Datei stammt, ergibt sich aus den Kopier-Protokollen. Je Sample werden erfasst: Kategorie, Instrument, One-Shot/Loop/Kit, Pack und Pack-Art, Format, Größe, Dauer, Abtastrate, Bittiefe und Kanäle (aus dem Dateikopf von WAV und AIFF), BPM und Tonart (aus dem Datei- bzw. Ordnernamen, z. B. „128bpm“, „Fmin“, „C#m“, „Eb maj“), Ursprungspfad und ob das Original noch in der Quelle liegt."),
("p", "Pack-Art: wird automatisch bestimmt (Drum-Kit, One-Shot-Pack, Loop-Pack, Construction Kit, Melodie/Instrument, Vocal-Pack, Atmos/Field Recording, FX-Pack, MIDI-Pack, Song/Playalong, gemischt). Korrekturen trägt man in Pack-Arten.csv ein (Knopf „Pack-Arten korrigieren“): je Zeile Packname;Pack-Art. Sie gelten ab der nächsten Inventur und werden in neue Versionen übernommen."),
("p", "Duplikate: Samples mit gleichem Inhalt an mehreren Stellen (gleiche Größe, bestätigt per Prüfsumme) werden zu Gruppen zusammengefasst. Je Gruppe wird ein Exemplar als „behalten“ markiert: zuerst eines in einem Drum-Kit oder Construction Kit, sonst eines außerhalb von „_Unsortiert“, sonst das mit dem kürzesten Pfad. Weitere Exemplare in Kits bleiben ebenfalls („behalten (Kit)“), alle anderen sind „entfernbar“."),
("p", "Vergleich: Ab der zweiten Inventur wird mit der vorherigen verglichen: neu, entfernt und verschoben (gleicher Name und gleiche Größe an anderer Stelle)."),
("p", "Ergebnis im Ordner Inventuren: Sample-Inventur_<Datum>.csv (eine Zeile je Sample), Pack-Inventur_<Datum>.csv (eine Zeile je Pack), Sample-Inventur_<Datum>.json (Kennzahlen des Laufs), Sample-Inventur_<Datum>.html (Bericht) und immer Inventur-aktuell.html mit dem neuesten Bericht. Im Ordner Inventur-Vergleiche: Inventur-Vergleich_<Datum>.csv. Prüfsummen werden gespeichert und bei unveränderten Dateien in der nächsten Inventur wiederverwendet."),
("p", "Der Ordner ModX wird als „ausgespart“ mit seiner Größe aufgeführt, wenn er in der Quelle liegt."),
("h2", "6. HTML-Bericht"),
("p", "Der Bericht ist eine einzelne Datei, die ohne Internet in Edge oder Chrome funktioniert. Oben stehen Kennzahlen (Samples, Packs, belegter und freier Platz, je Kategorie, Duplikate, neu/entfernt). Die Leiste bleibt beim Scrollen stehen."),
("li", "Ansichten: Samples, Packs und Duplikate."),
("li", "Gliedern nach: Kategorie → Instrument, Pack, Pack-Art, BPM (10er-Bereiche), Tonart oder nicht gliedern. Gruppen lassen sich auf- und zuklappen; bei vielen Samples sind sie zunächst zugeklappt."),
("li", "Suche und Filter nach Kategorie, Pack-Art, One-Shot/Loop/Kit, Tonart und Format, kombinierbar. „nur Auffälligkeiten“ zeigt Samples mit roten oder gelben Markierungen."),
("li", "Markierungen: rot = defekt oder leer, gelb = Duplikat (entfernbar) oder unsortiert, grün = neu, blau = verschoben, grau = Hinweis. Beim Überfahren mit der Maus erscheint der Grund."),
("li", "Ein Klick auf einen Packnamen zeigt nur die Samples dieses Packs; das × am Pack-Hinweis hebt den Filter auf."),
("li", "▶ spielt das Sample direkt im Browser ab (WAV, MP3, OGG, FLAC, M4A; AIFF und RX2 kann der Browser nicht abspielen). „Pfad kopieren“ legt den vollständigen Pfad in die Zwischenablage, z. B. zum Einfügen in die Adresszeile des Explorers."),
("li", "Unter den Samples steht, was seit der letzten Inventur entfernt wurde."),
("h2", "7. Duplikate im Ziel entfernen"),
("p", "Grundlage ist die neueste Inventur. Alle „entfernbar“ markierten Exemplare werden geprüft: Datei und behaltenes Exemplar existieren noch und haben denselben Inhalt (SHA-256). Exemplare in Kits werden nie entfernt. Nach der Vorschau (Ziel-Duplikate-Vorschau_<Datum>.csv) fragt das Skript nach; Standard ist Nein. Die Dateien und ihre .asd-Dateien gehen in den Papierkorb, leer gewordene Ordner ebenfalls. Danach bitte eine neue Inventur starten. Ist die Inventur älter als einen Tag, weist das Skript darauf hin."),
("h2", "8. Duplikate in der Quelle entfernen"),
("p", "Grundlage ist das neueste Protokoll eines Kopierlaufs (im Ordner Protokolle, ersatzweise im Zielordner oder im alten Skript-Ordner von Version 0). Für jede als Duplikat markierte Datei wird geprüft: Sie liegt in der Quelle, ist eine Audiodatei, existiert noch, und das behaltene Original existiert mit identischem Inhalt (SHA-256). Nur dann wird sie entfernt."),
("p", "Nach der Vorschau (Duplikate-Vorschau_<Datum>.csv) fragt das Skript nach; Standard ist Nein. Die Dateien und ihre .asd-Dateien gehen in den Windows-Papierkorb; leer gewordene Ordner ebenfalls. Ergebnis: Duplikate-entfernt_<Datum>.csv."),
("p", "Hinweis: Der Papierkorb hat je Laufwerk eine Größengrenze. Ist sie überschritten, kann Windows Dateien endgültig löschen statt sie in den Papierkorb zu legen. Eine Warnung davor folgt in einer späteren Version."),
("h2", "9. Start ohne Oberfläche"),
("p", "Die Skripte lassen sich auch über die .cmd-Dateien oder in PowerShell starten. Schalter: -NurVorschau (nur Vorschau, keine Frage), -Ausfuehren (ohne Frage ausführen), beim Sortieren -Quelle und -Ziel (abweichende Ordner für diesen Lauf), bei der Inventur -NurBericht (nur den Bericht zur neuesten Inventur neu erzeugen)."),
("h2", "10. Umstieg von Version 0"),
("li", "Version 0 lag im Ordner E:\\Sounds und Samples\\_Sortier-Skript. Sie kann bleiben; Version 1 liest dort bei Bedarf das alte Protokoll für die Duplikat-Bereinigung."),
("li", "Die Desktop-Verknüpfung „Samples-Werkzeuge“ wird beim ersten Start auf Version 1 umgestellt. Den alten Desktop-Ordner „Samples-Werkzeuge“ mit den Verknüpfungen 1–4 bitte von Hand löschen."),
("h2", "11. Versionen"),
("li", "2.0.0 (26.10.2026): Inventur mit Pack-Art, Audio-Eigenschaften, BPM, Tonart, Vergleich und Duplikaten im Ziel; HTML-Bericht mit Ansichten Samples/Packs/Duplikate, Gliederung, Filtern und Abspielen; Duplikate im Ziel entfernen; macOS-Reste beim Sortieren in den Papierkorb; Häkchen „RX2 beibehalten“."),
("li", "1.2.1 (26.10.2026): Quelle ohne Audiodateien zeigt nur noch einen Hinweis statt einer Kopier-Zusammenfassung; Hilfsdateien mit Grund in der Vorschau; Hinweis auf ModX nur, wenn der Ordner existiert."),
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
