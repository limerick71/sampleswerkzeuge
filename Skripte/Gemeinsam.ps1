# (c) 2026 Herbert Stoecker. Kostenlos nutzbar. Bitte nur als Link auf die offizielle Download-Seite weitergeben; Verkauf und Veroeffentlichung geaenderter Fassungen nur mit Zustimmung.
# Gemeinsam.ps1 - gemeinsame Pfade, Einstellungen und Hilfsfunktionen der Samples-Werkzeuge (Version 2)
# Wird von allen Skripten der Samples-Werkzeuge per Dot-Sourcing geladen.
#
# Ordnerstruktur (ab 4.1 sind Programm und Daten getrennt, NFA-08):
#   <Wurzel>\               nur Startdateien (*.cmd), Dokumentation und Skripte - darf bei einem Versionswechsel weg
#   %LOCALAPPDATA%\Samples-Werkzeuge\   Einstellungen.json, Pack-Arten.csv, Fehler.log,
#                                        Protokolle\ (Vorschauen, Protokolle, Vorgang_*.txt), Fundorte\
#   <Ziel>\99_Protokolle\               Sortier-, Import- und Aufraeum-Protokolle, Bibliothek-Stand_<Datum>.json
#   <Ziel>\99_Protokolle\Bibliothek\   Liste, Bericht und Vergleich der Sample-Bibliothek (die letzten 10 Staende)

$ProgrammVersion = '4.1'
$Urheberhinweis  = "$([char]0x00A9) 2026 Herbert St$([char]0x00F6)cker. Kostenlos nutzbar. Bitte nur als Link auf die offizielle Download-Seite weitergeben; Verkauf und Ver$([char]0x00F6)ffentlichung ge$([char]0x00E4)nderter Fassungen nur mit Zustimmung."
$UrheberKurz     = "$([char]0x00A9) 2026 Herbert St$([char]0x00F6)cker"
$DownloadSeite   = 'https://github.com/limerick71/sampleswerkzeuge/releases/latest'
$WebSeite        = 'https://make-some-music.de'   # 4.0.2: Webseite neben dem Urheber

$skriptOrdner = $PSScriptRoot
if ([string]::IsNullOrWhiteSpace($skriptOrdner)) { $skriptOrdner = (Get-Location).Path }
$wurzel           = Split-Path -Parent $skriptOrdner
# 4.1 (NFA-08): Nutzerdaten ausserhalb des Programmordners (SW_DATEN nur fuer Tests)
$datenOrdner = if ($env:SW_DATEN) { $env:SW_DATEN } elseif ($env:LOCALAPPDATA) { Join-Path $env:LOCALAPPDATA 'Samples-Werkzeuge' } else { Join-Path $HOME '.samples-werkzeuge' }
try { [void][IO.Directory]::CreateDirectory($datenOrdner) } catch { }
$protokollOrdner  = Join-Path $datenOrdner 'Protokolle'
$einstellungsPfad = Join-Path $datenOrdner 'Einstellungen.json'
$fehlerLog        = Join-Path $datenOrdner 'Fehler.log'
$packArtenPfad    = Join-Path $datenOrdner 'Pack-Arten.csv'
$fundortOrdner    = Join-Path $datenOrdner 'Fundorte'

# Audiodateien und macOS-Reste (gemeinsam fuer Sortieren und Inventur)
$RxAudio    = '\.(wav|aiff?|mp3|flac|ogg|rx2|rex|m4a)$'
$RxRx2      = '\.(rx2|rex)$'
$PackArten  = @('Drum-Kit', 'One-Shot-Pack', 'Loop-Pack', 'Construction Kit', 'Melodie/Instrument', 'Vocal-Pack',
                'Atmos/Field Recording', 'FX-Pack', 'MIDI-Pack', 'Song/Playalong', 'gemischt')
# ---------------------------------------------------------------------------
# Lange Pfade (2.3.3): Windows PowerShell 5.1 oeffnet ohne Zusatz nur Pfade bis 259 Zeichen.
# Mit dem Vorsatz \\?\ (bzw. \\?\UNC\ fuer Netzwerkpfade) geht es bis etwa 32.000 Zeichen.
# ---------------------------------------------------------------------------
$LangerPfad = 240
function Get-LangPfad([string]$p) {
    if (-not $p -or $p.StartsWith('\\?\') -or [IO.Path]::DirectorySeparatorChar -ne [char]92 -or $p.Length -lt $LangerPfad) { return $p }
    if ($p.StartsWith('\\')) { return '\\?\UNC\' + $p.Substring(2) }
    return '\\?\' + $p
}
function Test-Datei([string]$p) { return [IO.File]::Exists((Get-LangPfad $p)) }
function Test-Ordner([string]$p) { return [IO.Directory]::Exists((Get-LangPfad $p)) }
# Pruefsumme wie Get-FileHash (Hex, Grossbuchstaben), auch fuer lange Pfade
function Get-DateiPruefsumme([string]$p, [string]$algo = 'MD5') {
    $s = [IO.File]::Open((Get-LangPfad $p), [IO.FileMode]::Open, [IO.FileAccess]::Read, [IO.FileShare]::ReadWrite)
    try {
        $h = if ($algo -eq 'SHA256') { [Security.Cryptography.SHA256]::Create() } else { [Security.Cryptography.MD5]::Create() }
        try { return ([BitConverter]::ToString($h.ComputeHash($s))).Replace('-', '') } finally { $h.Dispose() }
    } finally { $s.Dispose() }
}
# Kopieren ohne Ueberschreiben; legt den Zielordner an
function Copy-Datei([string]$von, [string]$nach) {
    [void][IO.Directory]::CreateDirectory((Get-LangPfad ([IO.Path]::GetDirectoryName($nach))))
    [IO.File]::Copy((Get-LangPfad $von), (Get-LangPfad $nach), $false)
}

# Kandidat nach Name: ._-Datei, .DS_Store oder Inhalt eines __MACOSX-Ordners
function Test-MacRestName([string]$pfad) {
    $n = [IO.Path]::GetFileName($pfad)
    return ($n -eq '.DS_Store' -or $n.StartsWith('._') -or $pfad -match '[\\/]__MACOSX([\\/]|$)')
}
# Pruefung ueber den Dateikopf: 'mac' (sicher ein macOS-Rest), 'unklar' (nur der Name passt) oder '' (kein Kandidat).
# AppleDouble 00 05 16 07, AppleSingle 00 05 16 00, .DS_Store: 00 00 00 01 "Bud1"
function Get-MacRestArt([string]$pfad) {
    if (-not (Test-MacRestName $pfad)) { return '' }
    $b = New-Object byte[] 8; $n = 0
    try { $fs = [IO.File]::OpenRead((Get-LangPfad $pfad)); try { $n = $fs.Read($b, 0, 8) } finally { $fs.Dispose() } } catch { return 'unklar' }
    if ($n -ge 4 -and $b[0] -eq 0 -and $b[1] -eq 5 -and $b[2] -eq 0x16 -and ($b[3] -eq 7 -or $b[3] -eq 0)) { return 'mac' }
    if ($n -ge 8 -and [Text.Encoding]::ASCII.GetString($b, 4, 4) -eq 'Bud1') { return 'mac' }
    return 'unklar'
}
# Zusaetzliche Formate neben der WAV (SRT-06): Dateiendung -> Einstellung "behalten"
$FormatEinstellung = @{ '.rx2' = 'RX2Beibehalten'; '.rex' = 'RX2Beibehalten'; '.mp3' = 'MP3Beibehalten'; '.aif' = 'AIFFBeibehalten'; '.aiff' = 'AIFFBeibehalten' }
$FormatName = @{ 'RX2Beibehalten' = 'RX2'; 'MP3Beibehalten' = 'MP3'; 'AIFFBeibehalten' = 'AIFF' }

if (-not (Test-Path -LiteralPath $protokollOrdner)) { try { New-Item -ItemType Directory -Path $protokollOrdner -Force | Out-Null } catch { } }

function Write-FehlerLog([string]$text) {
    try { Add-Content -LiteralPath $fehlerLog -Value ("{0:yyyy-MM-dd HH:mm:ss}  {1}" -f (Get-Date), $text) -Encoding UTF8 } catch { }
}

# ---------------------------------------------------------------------------
# Einstellungen (Skripte\Einstellungen.json)
# ---------------------------------------------------------------------------
# Download-Ordner des Benutzers (auch wenn er verschoben wurde)
function Get-StandardDownloads {
    try {
        $p = (Get-ItemProperty -Path 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\User Shell Folders' -ErrorAction Stop).'{374DE290-123F-4565-9164-39C4925E467B}'
        if ($p) { return [Environment]::ExpandEnvironmentVariables($p) }
    } catch { }
    if ($env:USERPROFILE) { return (Join-Path $env:USERPROFILE 'Downloads') }
    return ''
}

# Beschreibung aller Pfad-Einstellungen: Schluessel, Anzeigename, Erklaerung
$PfadEinstellungen = @(
    @{ Name = 'Quelle';         Text = 'Quelle';           Hinweis = 'Ordner mit den unsortierten Sample-Packs. Wird beim Sortieren nur gelesen.' }
    @{ Name = 'Ziel';           Text = 'Ziel';             Hinweis = 'Sortierte Sample-Bibliothek. Hierhin wird kopiert.' }
    @{ Name = 'Downloads';      Text = 'Downloads';        Hinweis = "Hier sucht 'Download importieren' nach neuen Sample-Packs (ZIP-Dateien und Ordner)." }
    @{ Name = 'DownloadArchiv'; Text = 'Download-Archiv';  Hinweis = "Hierhin verschiebt 'Download importieren' auf Wunsch die Original-Downloads." }
)

function Get-StandardDokumente {
    try { $d = [Environment]::GetFolderPath('MyDocuments'); if ($d) { return $d } } catch { }
    if ($env:USERPROFILE) { return (Join-Path $env:USERPROFILE 'Documents') }
    return 'C:\'
}

# 4.1 (GUI-08): Vorschlag fuer das Ziel beim ersten Start: "Samples" auf dem lokalen Laufwerk mit dem meisten
# freien Platz (keine Netzlaufwerke oder USB-Sticks). Gibt es den Ordner schon mit fremdem Inhalt, ein anderer Name.
function Get-ZielVorschlag {
    if ($script:zielVorschlag) { return $script:zielVorschlag }
    $best = $null
    try {
        foreach ($d in [IO.DriveInfo]::GetDrives()) {
            try { if ($d.DriveType -ne 'Fixed' -or -not $d.IsReady) { continue }; if (-not $best -or $d.AvailableFreeSpace -gt $best.AvailableFreeSpace) { $best = $d } } catch { }
        }
    } catch { }
    $root = if ($best) { $best.RootDirectory.FullName } else { [IO.Path]::GetPathRoot((Get-StandardDokumente)) }
    $vorschlag = Join-Path $root 'Sample-Bibliothek-Neu'
    foreach ($n in 'Samples', 'Sample-Bibliothek', 'Samples-Bibliothek') {
        $p = Join-Path $root $n
        if (-not (Test-Path -LiteralPath $p)) { $vorschlag = $p; break }
        if (Test-Path -LiteralPath (Join-Path $p '99_Protokolle')) { $vorschlag = $p; break }   # schon eine Bibliothek der Samples-Werkzeuge
        if (-not @(Get-ChildItem -LiteralPath $p -Force -ErrorAction SilentlyContinue | Select-Object -First 1).Count) { $vorschlag = $p; break }   # leer
    }
    $script:zielVorschlag = $vorschlag
    return $vorschlag
}
# 4.1 (GUI-08): liegt ein Ordner in OneDrive (dann wuerden viele Gigabyte Samples in die Cloud geladen)?
function Test-OneDrivePfad([string]$pfad) {
    if (-not $pfad) { return $false }
    $p = $pfad.TrimEnd('\', '/') + '\'
    foreach ($od in @($env:OneDrive, $env:OneDriveConsumer, $env:OneDriveCommercial) | Where-Object { $_ }) {
        if ($p.StartsWith($od.TrimEnd('\', '/') + '\', [StringComparison]::OrdinalIgnoreCase)) { return $true }
    }
    return ($p -match '\\OneDrive( - [^\\]+)?\\')
}
# Download-Archiv neben dem Ziel (4.1)
function Get-ArchivVorschlag([string]$ziel) {
    $eltern = Split-Path -Parent $ziel.TrimEnd('\', '/')
    if (-not $eltern) { $eltern = [IO.Path]::GetPathRoot($ziel) }
    return [IO.Path]::Combine($eltern, 'Samples-Download-Archiv')   # Join-Path scheitert, wenn das Laufwerk (noch) fehlt
}

function Get-StandardEinstellungen {
    $dok = Get-StandardDokumente
    return [ordered]@{
        Quelle              = ''   # 4.1 (GUI-08): keine erfundene Quelle - Einstieg ueber "Fundorte suchen"
        Ziel                = (Get-ZielVorschlag)
        Downloads           = (Get-StandardDownloads)
        DownloadArchiv      = ([IO.Path]::Combine($dok, 'Z_Download_Archiv'))
        RX2Beibehalten      = $true
        MP3Beibehalten      = $true
        AIFFBeibehalten     = $true
        ErsterStartErledigt = $false
        # 2.3.5: Auswahl im Fenster "Fundorte suchen" (Pfade mit | getrennt; leer = Vorauswahl des Programms)
        FundortAn           = ''
        FundortZusatz       = ''
        FundortZip          = $true
        ImportOriginal      = 'Archiv'   # Version 3: Archiv, Behalten oder Papierkorb
        BibliothekAutomatisch = $false   # 4.1 (INV-11): nach Sortieren, Import und Duplikate-Entfernen automatisch neu einlesen
    }
}

function Get-Einstellungen {
    $e = Get-StandardEinstellungen
    $cfg = $null
    if (Test-Path -LiteralPath $einstellungsPfad) {
        try {
            $cfg = Get-Content -LiteralPath $einstellungsPfad -Raw -Encoding UTF8 | ConvertFrom-Json
            foreach ($p in $cfg.PSObject.Properties) {
                if ($e.Contains($p.Name) -and $null -ne $p.Value -and [string]$p.Value -ne '') { $e[$p.Name] = $p.Value }
            }
        } catch { Write-FehlerLog "Einstellungen nicht lesbar: $($_.Exception.Message)" }
    }
    foreach ($k in @($e.Keys)) {
        if ($k -in 'ErsterStartErledigt', 'RX2Beibehalten', 'MP3Beibehalten', 'AIFFBeibehalten', 'FundortZip', 'BibliothekAutomatisch') { $e[$k] = ([string]$e[$k]) -notin 'False', '0', '' }
        elseif ($k -in 'FundortAn', 'FundortZusatz') { $e[$k] = ([string]$e[$k]).Trim() }   # Pfadlisten: "C:\" behaelt den \
        else { $e[$k] = ([string]$e[$k]).Trim().TrimEnd('\', '/') }
    }
    # Quellenliste (QLN-04, ab 2.3): je Eintrag Pfad, Aktiv, Herkunft. Fehlt sie (Einstellungen bis 2.2),
    # wird die bisherige einzelne Quelle zur ersten Zeile.
    $liste = New-Object System.Collections.Generic.List[object]
    if ($cfg -and $cfg.PSObject.Properties['Quellen'] -and $cfg.Quellen) {
        foreach ($q in @($cfg.Quellen)) {
            $pf = ([string]$q.Pfad).Trim().TrimEnd('\', '/')
            if (-not $pf) { continue }
            $liste.Add([pscustomobject]@{ Pfad = $pf; Aktiv = (([string]$q.Aktiv) -notin 'False', '0', ''); Herkunft = $(if ($q.Herkunft) { [string]$q.Herkunft } else { 'manuell' }); Art = (Get-QuellArtName ([string]$q.Art)) })
        }
    }
    # Nur wenn es noch gar keine Quellenliste gibt (Einstellungen bis 2.2): bisherige Quelle uebernehmen.
    # Eine bewusst geleerte Liste bleibt leer.
    if ($liste.Count -eq 0 -and $e.Quelle -and -not ($cfg -and $cfg.PSObject.Properties['Quellen'])) { $liste.Add([pscustomobject]@{ Pfad = $e.Quelle; Aktiv = $true; Herkunft = 'manuell'; Art = 'Sammlung' }) }
    $e.Add('Quellen', [object[]]$liste.ToArray())
    # "Quelle" bleibt fuer aeltere Stellen: erste aktive Quelle
    $erste = @($liste | Where-Object { $_.Aktiv }) | Select-Object -First 1
    if ($erste) { $e.Quelle = $erste.Pfad }
    return $e
}

# Art einer Quelle (2.3.1):
#   Sammlung = jeder Unterordner ist ein Pack (Pack-Name = Unterordner)
#   Pack     = alles darin ist ein Pack (Pack-Name = Name des Quellordners), auch wenn unsortiert
#   Lose     = nur die Dateien direkt im Ordner, ohne Unterordner (Pack-Name = Name des Ordners)
$QuellArten = [ordered]@{ Sammlung = 'Sammlung'; Pack = 'Ein Pack'; Lose = 'Nur lose Dateien' }
function Get-QuellArtName([string]$art) { if ($QuellArten.Contains($art)) { return $art } else { return 'Sammlung' } }

# Typische Ordner im Inneren eines Packs ("Loops", "One Shots", "Kick", "...-WAV" ...)
$RxPackInnen = '^(samples?|sounds|demo|wav|wave|waves|aiff?|rex2?|rx2|acid|midi|stems|presets?|patches|full ?mix|kits?)$|^(loops?|one[ -]?shots?|oneshots|drums?|drum ?loops|kicks?|snares?|hats?|hi[ -]?hats?|claps?|percs?|percussion|toms?|cymbals?|crash(es)?|rides?|shakers?|bass|basslines?|bass ?loops|synths?|synth ?loops|keys|pads?|leads?|plucks?|chords?|arps?|vocals?|vox|vocal ?loops|fx|sfx|risers?|impacts?|sweeps?|atmos(pheres?)?|textures?|construction ?kits?|drum ?kits?|top ?loops|music ?loops|melod(y|ic|ies)( ?loops)?|guitars?|piano|strings|brass|apple ?loops)\b|[-_ ](wav|rex2?|rx2|aiff?|midi|apple ?loops|ableton|presets?)$'
$RxPackNeutral = '^(licen[cs]es?|readme|info|infos|artwork|cover|documentation|docs?|__macosx|license & files)\b'
# 3.0.1: Namen von Instrument-Bibliotheken (Fundorte und Import) und Ordner mit den Sortier-Protokollen im Ziel
# 4.1 (NFA-09): Hersteller-Bibliotheken direkt in einer Quelle (eigene Formate fuer Instrumente/Synthesizer) werden beim
# Sortieren ausgespart und beim Aufraeumen nicht angeruehrt - frueher nur der Ordner "ModX"
$RxHerstellerOrdner = '^(?i:modx|montage|yamaha( .*)?|native instruments|kontakt( libraries| bibliotheken)?|spitfire audio|halion( content)?)$'
$RxInstrNamen = 'Native Instruments|Kontakt|Spitfire|Sonokinetic|Muse ?Hub|Arturia|\bUVI\b|Vienna|\bVSL\b|EastWest|East West|Toontrack|Superior Drummer|EZdrummer|Steinberg|HALion|Komplete|Heavyocity|8Dio|Orchestral Tools|Cinesamples|XLN Audio|Addictive|Spectrasonics|Omnisphere|Keyscape|Trilian|Factory Packs|Core Library|Output Arcade|Soundiron|Impact Soundworks|Best Service|Garritan|Embertone'
$ZielProtokolle = '99_Protokolle'
function Get-ZielProtokollOrdner([string]$ziel) { return (Join-Path $ziel.TrimEnd('\', '/') $ZielProtokolle) }
# Protokolle, die frueher direkt im Ziel lagen, in den Unterordner verschieben (beim Sortieren nach "J")
function Move-ZielProtokolle([string]$ziel) {
    $zp = Get-ZielProtokollOrdner $ziel
    foreach ($f in @(Get-ChildItem -LiteralPath $ziel -File -Filter '*Protokoll_*.csv' -ErrorAction SilentlyContinue)) {
        try { [void][IO.Directory]::CreateDirectory($zp); $nach = Join-Path $zp $f.Name; if (-not (Test-Path -LiteralPath $nach)) { Move-Item -LiteralPath $f.FullName -Destination $nach } } catch { }
    }
}
# Vorschlag fuer die Art aus den Namen der Unterordner und der Zahl der Dateien direkt im Ordner
# 2.3.4: weitere Innenordner - "Bonus ...", "<Name> - Loops/Drums/Noise ..." und Ordner, die den Namen des
# Packs selbst tragen (z. B. "Neon Nights - DRUMS" in "Neon Nights")
$RxPackInnenWort = 'loops?|one ?shots?|oneshots|drums?|drum ?loops|drum ?kits?|kicks?|snares?|hats?|percs?|percussion|bass|basslines?|synths?|keys|pads?|leads?|plucks?|chords?|arps?|vocals?|vox|fx|sfx|noises?|textures?|atmos(pheres?)?|construction ?kits?|kits?|stems|midi|presets?|samples?|melod(y|ic|ies)|music|instruments?|tops?|grooves?|fills?|breaks?|wav|aiff?|rex2?|rx2'
$RxPackInnenEnde = '\s[-_–]\s*(' + $RxPackInnenWort + ')( ?(loops?|samples?|kits?|one ?shots?|\d+))?$'
function Get-NormName([string]$n) { return (($n.ToLowerInvariant() -replace '[_\-–.,()\[\]]+', ' ') -replace '\s+', ' ').Trim() }
function Test-PackInnenName([string]$name, [string]$eltern = '') {
    $l = $name.ToLowerInvariant().Trim()
    # 3.0.1: nummerierte Namen ("Vol 1", "Volume 2") sind eigenstaendige Packs
    if ($l -match '\bvol(ume)?\.?\s*\d') { return $false }
    if ($l -match $RxPackInnen) { return $true }
    # 3.0.1: typische Innenordner von Vocal-Packs ("Female Vocals", "Ad Libs", "Hooks", "Vocal Stacks" ...)
    if ($l -match '^((female|male|lead|backing|dry|wet|processed|chopped|main|solo|ensemble|vocal)\s+)?(vocals?|vox|ad ?-?libs?|stacks?|hooks?|phrases?|chops?|harmon(y|ies)|chants?|shouts?|whispers?|spoken)$') { return $true }
    # 3.0.1: kurze Namen mit einem Instrument ("Alto Sax", "Trumpet", "Sax Solo", "Piano Chords") sind Innenordner
    if (@($l -split '\s+').Count -le 3 -and $l -match '\b(sax(ophone)?s?|alto|tenor|baritone|soprano|trumpets?|trombones?|flutes?|clarinets?|horns?|brass|pianos?|keys|rhodes|organs?|guitars?|bass|strings?|violins?|cellos?|violas?|harps?|synths?|pads?|plucks?|leads?|arps?|chords?|bells?|choirs?|drums?|kicks?|snares?|hats?|percs?|percussion|fx|vocals?|vox|solo|ensemble|section)\b') { return $true }
    if ($l -match '^bonus') { return $true }
    if ($l -match $RxPackInnenEnde) { return $true }
    if ($eltern) {
        $e = Get-NormName $eltern; $k = Get-NormName $name
        if ($e.Length -ge 4 -and $k -ne $e -and $k.Contains($e)) { return $true }
    }
    return $false
}
function Get-QuellArtVorschlag([string[]]$kinder, [int]$eigeneDateien = 0, [string]$eltern = '') {
    $relevant = @($kinder | Where-Object { $_ -and $_.ToLowerInvariant() -notmatch $RxPackNeutral })
    if (-not $relevant.Count) { return 'Pack' }
    if ($eigeneDateien -gt 0 -and $relevant.Count -eq 1) { return 'Pack' }   # 2.3.3: eigene Dateien plus ein Unterordner = ein Pack
    $innen = @($relevant | Where-Object { Test-PackInnenName $_ $eltern }).Count
    if ($innen * 2 -ge $relevant.Count) { return 'Pack' }
    return 'Sammlung'
}
# Vorschlag direkt fuer einen vorhandenen Ordner
# Sammelordner (2.3.3): Laufwerke, Benutzerordner, Dokumente, Downloads, Desktop, Musik, Bilder, Videos,
# OneDrive. Darin liegt Verschiedenes - als Quelle passt nur "Nur lose Dateien" (Packs einzeln eintragen).
function Test-Sammelordner([string]$p) {
    if (-not $p) { return $false }
    $n = $p.TrimEnd('\', '/')
    if ([IO.Path]::GetPathRoot($p) -ieq $p -or $n.Length -le 2) { return $true }
    foreach ($v in @($env:USERPROFILE, [Environment]::GetFolderPath('MyDocuments'), [Environment]::GetFolderPath('Desktop'), [Environment]::GetFolderPath('MyMusic'),
                     [Environment]::GetFolderPath('MyPictures'), [Environment]::GetFolderPath('MyVideos'), (Get-StandardDownloads), $env:OneDrive, $env:OneDriveConsumer, $env:OneDriveCommercial)) {
        if ($v -and $v.TrimEnd('\', '/') -ieq $n) { return $true }
    }
    return $false
}
# Ordner mit Audiodateien (irgendwo darin)? Bricht beim ersten Treffer ab.
function Test-HatAudio([string]$p) {
    $stapel = New-Object System.Collections.Generic.Stack[string]; $stapel.Push($p); $n = 0
    while ($stapel.Count -and $n -lt 5000) {
        $o = $stapel.Pop(); $n++
        try {
            foreach ($f in [IO.Directory]::EnumerateFiles((Get-LangPfad $o))) { if ($f -match $RxAudio) { return $true } }
            foreach ($u in [IO.Directory]::EnumerateDirectories((Get-LangPfad $o))) { $stapel.Push(($u -replace '^\\\\\?\\', '')) }
        } catch { }
    }
    return $false
}
# Ebene, auf der die Packs liegen (2.3.3): durch Ordner mit nur einem Unterordner (mit Audio) hinab bis zur
# Verzweigung, z. B. Splice -> Samples -> packs. Sind die Ordner dort eigenstaendige Pack-Namen (nicht
# Loops, One Shots, ...-WAV), liefert sie diesen Pfad, sonst $null (der Ordner selbst ist dann ein Pack).
function Get-PackEbene([string]$pfad) {
    $w = $pfad.TrimEnd('\', '/')
    for ($i = 0; $i -lt 6; $i++) {
        $kinder = @(); $eigen = 0
        try { $kinder = @([IO.Directory]::EnumerateDirectories($w) | Where-Object { [IO.Path]::GetFileName($_).ToLowerInvariant() -notmatch $RxPackNeutral -and (Test-HatAudio $_) }) } catch { break }
        try { $eigen = @([IO.Directory]::EnumerateFiles($w) | Where-Object { $_ -match $RxAudio }).Count } catch { }
        if ($eigen -gt 0 -or $kinder.Count -ne 1) { break }
        $w = $kinder[0]
    }
    if ($w -eq $pfad.TrimEnd('\', '/')) { return $null }
    $namen = @(); try { $namen = @([IO.Directory]::EnumerateDirectories($w) | ForEach-Object { [IO.Path]::GetFileName($_) }) } catch { }
    if ($namen.Count -ge 2 -and (Get-QuellArtVorschlag $namen 0 ([IO.Path]::GetFileName($w))) -eq 'Sammlung') { return $w }
    return $null
}
function Get-QuellArtFuerOrdner([string]$pfad) {
    if (Test-Sammelordner $pfad) { return 'Lose' }   # 2.3.3
    $k = @(); $n = 0
    try { $k = @(Get-ChildItem -LiteralPath $pfad -Directory -Force -ErrorAction Stop | ForEach-Object { $_.Name }) } catch { }
    try { $n = @(Get-ChildItem -LiteralPath $pfad -File -Force -ErrorAction Stop | Where-Object { $_.Name -match $RxAudio }).Count } catch { }
    return Get-QuellArtVorschlag $k $n ([IO.Path]::GetFileName($pfad.TrimEnd('\', '/')))
}

# Vorschau fuer die Infobox "Art" (2.3.2): was jede Art mit diesem Ordner machen wuerde.
# Liest nur Namen (keine Cloud-Dateien herunterladen), hoechstens etwa 50.000 Dateien.
function Get-ArtVorschau([string]$pfad) {
    $name = [IO.Path]::GetFileName($pfad.TrimEnd('\', '/'))
    $direkt = @(); $packs = New-Object System.Collections.Generic.List[object]; $kinder = @()
    try { $direkt = @([IO.Directory]::EnumerateFiles($pfad) | Where-Object { [IO.Path]::GetFileName($_) -match $RxAudio -and -not [IO.Path]::GetFileName($_).StartsWith('._') } | ForEach-Object { [IO.Path]::GetFileName($_) }) } catch { }
    $gezaehlt = 0
    try { $unter = @([IO.Directory]::EnumerateDirectories($pfad)) } catch { $unter = @() }
    foreach ($u in ($unter | Sort-Object)) {
        $kn = [IO.Path]::GetFileName($u); $kinder += $kn
        try { if (([IO.File]::GetAttributes($u) -band [IO.FileAttributes]::ReparsePoint)) { continue } } catch { continue }
        $zahl = 0; $bsp = ''
        $stapel = New-Object System.Collections.Generic.Stack[string]; $stapel.Push($u)
        while ($stapel.Count -and $gezaehlt -lt 50000) {
            $o = $stapel.Pop()
            try {
                foreach ($f in [IO.Directory]::EnumerateFiles($o)) {
                    $fn = [IO.Path]::GetFileName($f)
                    if ($fn -match $RxAudio -and -not $fn.StartsWith('._')) { $zahl++; $gezaehlt++; if (-not $bsp) { $bsp = $f.Substring($u.Length).TrimStart('\', '/') } }
                }
                foreach ($x in [IO.Directory]::EnumerateDirectories($o)) { try { if (-not ([IO.File]::GetAttributes($x) -band [IO.FileAttributes]::ReparsePoint)) { $stapel.Push($x) } } catch { } }
            } catch { }
        }
        if ($zahl) { $packs.Add([pscustomobject]@{ Name = $kn; Audio = $zahl; Beispiel = $bsp }) }
    }
    $inUnter = 0; foreach ($p in $packs) { $inUnter += $p.Audio }
    $erg = New-Object PSObject
    $erg | Add-Member NoteProperty Name $name
    $erg | Add-Member NoteProperty Direkt ([object[]]$direkt)
    $erg | Add-Member NoteProperty Packs ([object[]]$packs.ToArray())
    $erg | Add-Member NoteProperty InUnterordnern $inUnter
    $erg | Add-Member NoteProperty Gesamt ($direkt.Count + $inUnter)
    $erg | Add-Member NoteProperty Empfehlung $(if (Test-Sammelordner $pfad) { 'Lose' } else { Get-QuellArtVorschlag $kinder $direkt.Count ([IO.Path]::GetFileName($pfad.TrimEnd('\', '/'))) })
    $erg | Add-Member NoteProperty Sammelordner (Test-Sammelordner $pfad)
    $erg | Add-Member NoteProperty PackEbene $(if (Test-Sammelordner $pfad) { $null } else { Get-PackEbene $pfad })
    $erg | Add-Member NoteProperty Unvollstaendig ($gezaehlt -ge 50000)
    return $erg
}
# Text der Infobox: je Art Titel und Zeilen ("..." steht fuer den Instrument-Ordner im Ziel)
function Get-ArtVorschauAbschnitte($v) {
    $nz = { param($z) $z.ToString('N0', [Globalization.CultureInfo]'de-DE') }
    $blatt = { param($r) [IO.Path]::GetFileName(([string]$r).Replace('\', '/')) }
    $s = New-Object System.Collections.Generic.List[string]
    if ($v.Packs.Count) {
        $liste = (@($v.Packs | Select-Object -First 4 | ForEach-Object { '„' + $_.Name + '“ (' + (& $nz $_.Audio) + ')' }) -join ', ')
        if ($v.Packs.Count -gt 4) { $liste += ' und ' + ($v.Packs.Count - 4) + ' weitere' }
        $s.Add("$($v.Packs.Count) Pack$(if ($v.Packs.Count -ne 1) { 's' }) (= Unterordner mit Audiodateien): $liste")
    } else { $s.Add('keine Unterordner mit Audiodateien') }
    if ($v.Direkt.Count) { $s.Add((& $nz $v.Direkt.Count) + ' Dateien direkt im Ordner kommen in den Pack „_Einzeldateien“') }
    if ($v.Packs.Count) { $s.Add('z. B. …\' + $v.Packs[0].Name + '\' + (& $blatt $v.Packs[0].Beispiel)) }
    $samm = @{ Art = 'Sammlung'; Titel = 'Sammlung – jeder Unterordner ist ein eigener Pack'; Zeilen = @($s) }

    $s = New-Object System.Collections.Generic.List[string]
    $s.Add('alle ' + (& $nz $v.Gesamt) + ' Audiodateien (auch in Unterordnern) als Pack „' + $v.Name + '“')
    $b = if ($v.Direkt.Count) { $v.Direkt[0] } elseif ($v.Packs.Count) { & $blatt $v.Packs[0].Beispiel } else { '' }
    if ($b) { $s.Add('z. B. …\' + $v.Name + '\' + $b) }
    $pack = @{ Art = 'Pack'; Titel = 'Ein Pack – alles im Ordner gehört zu einem Pack'; Zeilen = @($s) }

    $s = New-Object System.Collections.Generic.List[string]
    $t = (& $nz $v.Direkt.Count) + ' Audiodateien direkt im Ordner als Pack „Einzeldateien (' + $v.Name + ')“'
    if ($v.InUnterordnern) { $t += "; $(& $nz $v.InUnterordnern) Dateien in Unterordnern werden übergangen" }
    $s.Add($t)
    if ($v.Direkt.Count) { $s.Add('z. B. …\Einzeldateien (' + $v.Name + ')\' + $v.Direkt[0]) }
    $lose = @{ Art = 'Lose'; Titel = 'Nur lose Dateien – nur die Dateien direkt im Ordner'; Zeilen = @($s) }
    return @($samm, $pack, $lose)
}

# Aktive Quellen als Pfadliste bzw. als Objekte (Pfad, Art ...)
function Get-AktiveQuellen { @((Get-Einstellungen).Quellen | Where-Object { $_.Aktiv } | ForEach-Object { $_.Pfad }) }
function Get-AktiveQuellObjekte { @((Get-Einstellungen).Quellen | Where-Object { $_.Aktiv }) }

# Quellenliste speichern (Liste von Objekten mit Pfad, Aktiv, Herkunft, Art)
function Set-Quellen($liste) {
    $sauber = @($liste | ForEach-Object { [ordered]@{ Pfad = [string]$_.Pfad; Aktiv = [bool]$_.Aktiv; Herkunft = [string]$_.Herkunft; Art = (Get-QuellArtName ([string]$_.Art)) } })
    Set-Einstellung 'Quellen' $sauber
}

# Prueft einen neuen Quellordner gegen Ziel und vorhandene Quellen. Liefert Fehlertext oder ''.
# "Nur lose Dateien" liest keine Unterordner: darf daher ueber anderen Quellen (oder dem Ziel) liegen.
function Test-NeueQuelle([string]$pfad, $quellen, [string]$ziel, [string]$ausser = '', [string]$art = 'Sammlung') {
    $f = Test-QuelleZiel $pfad $ziel $art
    if ($f) { return $f }
    $n = $pfad.Replace('/', '\').TrimEnd('\') + '\'
    foreach ($q in @($quellen)) {
        if ($ausser -and $q.Pfad -ieq $ausser) { continue }
        $a = ([string]$q.Pfad).Replace('/', '\').TrimEnd('\') + '\'
        $qArt = Get-QuellArtName ([string]$q.Art)
        if ($a -ieq $n) { return "Dieser Ordner ist schon als Quelle eingetragen." }
        if ($n.StartsWith($a, [StringComparison]::OrdinalIgnoreCase) -and $qArt -ne 'Lose') { return "Der Ordner liegt innerhalb der Quelle $($q.Pfad) und wird dort schon mitgelesen." }
        if ($a.StartsWith($n, [StringComparison]::OrdinalIgnoreCase) -and $art -ne 'Lose') { return "Die Quelle $($q.Pfad) liegt innerhalb dieses Ordners. Bitte zuerst diese Quelle entfernen oder als Art 'Nur lose Dateien' waehlen." }
    }
    return ''
}

function Set-Einstellung([string]$name, $wert) {
    $e = Get-Einstellungen
    $e[$name] = $wert
    # Nur Abweichungen vom Standard speichern: so zeigt z. B. "Berichte" in einer neuen
    # Version weiter auf deren eigenen Programmordner und nicht auf den der alten Version.
    $std = Get-StandardEinstellungen
    if ($name -eq 'Quellen') {
        $erste = @($wert | Where-Object { $_.Aktiv }) | Select-Object -First 1
        if ($erste) { $e.Quelle = [string]$erste.Pfad }
    }
    $obj = [ordered]@{ Standard21 = $true }
    foreach ($k in @($e.Keys)) {
        # Quelle, Ziel und Quellen immer speichern, alles andere nur, wenn es vom Standard abweicht
        if ($k -in 'ErsterStartErledigt', 'Quelle', 'Ziel', 'Quellen', 'DownloadArchiv' -or [string]$e[$k] -ne [string]$std[$k]) { $obj[$k] = $e[$k] }
    }
    if ($obj.Contains('Quellen')) { $obj['Quellen'] = @($obj['Quellen'] | ForEach-Object { [ordered]@{ Pfad = [string]$_.Pfad; Aktiv = [bool]$_.Aktiv; Herkunft = [string]$_.Herkunft; Art = (Get-QuellArtName ([string]$_.Art)) } }) }
    ConvertTo-Json -InputObject $obj -Depth 5 | Set-Content -LiteralPath $einstellungsPfad -Encoding UTF8
}

# Prueft, ob Quelle und Ziel zueinander passen. Liefert eine Fehlermeldung oder ''.
function Test-QuelleZiel([string]$quelle, [string]$ziel, [string]$art = 'Sammlung') {
    if (-not $quelle) { return 'Es ist keine Quelle eingestellt.' }
    if (-not $ziel)   { return 'Es ist kein Ziel eingestellt.' }
    $q = $quelle.Replace('/', '\').TrimEnd('\') + '\'
    $z = $ziel.Replace('/', '\').TrimEnd('\') + '\'
    if ($q -ieq $z) { return 'Quelle und Ziel sind derselbe Ordner.' }
    if ($z.StartsWith($q, [StringComparison]::OrdinalIgnoreCase) -and $art -ne 'Lose') { return 'Das Ziel darf nicht innerhalb der Quelle liegen.' }
    if ($q.StartsWith($z, [StringComparison]::OrdinalIgnoreCase)) { return 'Die Quelle darf nicht innerhalb des Ziels liegen.' }
    return ''
}

# Zustand eines Ordners fuer Status und Pruefung: Text und ob er unerreichbar ist
# (Laufwerk fehlt). Ein fehlender Ordner auf vorhandenem Laufwerk gilt als "wird angelegt".
function Get-OrdnerStatus([string]$pfad) {
    if (-not $pfad) { return @{ Text = 'nicht eingestellt'; Fehlt = $true } }
    if (Test-Path -LiteralPath $pfad) { return @{ Text = 'vorhanden'; Fehlt = $false } }
    $root = ''
    try { $root = [IO.Path]::GetPathRoot($pfad) } catch { }
    if (-not $root -or -not (Test-Path -LiteralPath $root)) {
        $lw = if ($root) { $root.TrimEnd('\', '/') } else { $pfad }
        return @{ Text = "NICHT GEFUNDEN (Laufwerk $lw nicht vorhanden)"; Fehlt = $true }
    }
    return @{ Text = 'noch nicht vorhanden (wird beim Sortieren angelegt)'; Fehlt = $false }
}

# ---------------------------------------------------------------------------
# Protokolle
# ---------------------------------------------------------------------------
# Neueste Datei nach Dateinamen (enthaelt Datum und Uhrzeit)
function Get-NeuestesProtokoll([string]$filter, [string[]]$ordner = @($protokollOrdner)) {
    @(foreach ($o in $ordner) {
        if ($o -and (Test-Path -LiteralPath $o)) { Get-ChildItem -LiteralPath $o -Filter $filter -File -ErrorAction SilentlyContinue }
    }) | Sort-Object Name -Descending | Select-Object -First 1
}

function Get-Protokollzeit($datei) {
    if ($datei.Name -match '_(\d{4}-\d{2}-\d{2})_(\d{2})(\d{2})(\d{2})?\.(csv|json)$') {
        try { return [datetime]::ParseExact("$($Matches[1]) $($Matches[2]):$($Matches[3])", 'yyyy-MM-dd HH:mm', $null) } catch { }
    }
    return $datei.LastWriteTime
}

# ---------------------------------------------------------------------------
# Inventur-Dateien
# ---------------------------------------------------------------------------
# 4.1 (NFA-08): Liste, Bericht und Vergleich der Sample-Bibliothek gehoeren zum Ziel
function Get-InventurOrdner  { Join-Path (Get-ZielProtokollOrdner ([string](Get-Einstellungen).Ziel)) 'Bibliothek' }
function Get-VergleichOrdner { Get-InventurOrdner }
# 4.0.1: Stand der Sample-Bibliothek im Ziel (99_Protokolle\Bibliothek-Stand_<Datum>.json, schreibt Inventur.ps1).
# Gehoert zum tatsaechlichen Ziel: nach einem Versionswechsel noch da, nach dem Loeschen des Ziels weg.
function Get-BibliothekStand {
    $z = [string](Get-Einstellungen).Ziel
    if (-not $z) { return $null }
    $f = Get-NeuestesProtokoll 'Bibliothek-Stand_*.json' @(Get-ZielProtokollOrdner $z)
    if (-not $f) { return $null }
    try { $d = Get-Content -LiteralPath $f.FullName -Raw -Encoding UTF8 | ConvertFrom-Json } catch { return $null }
    return [pscustomobject]@{ Datei = $f; Zeit = (Get-Protokollzeit $f); Daten = $d; Csv = [string]$d.Csv }
}
function Get-NeuesteInventur([string]$art = 'Sample') {
    $kand = @()
    $o = Get-InventurOrdner
    if (Test-Path -LiteralPath $o) { $kand += @(Get-ChildItem -LiteralPath $o -Filter "$art-Inventur_*.csv" -File -ErrorAction SilentlyContinue) }
    # 4.0.1: auch die Liste zum Stand im Ziel (z. B. im Ordner einer frueheren Version)
    $st = Get-BibliothekStand
    if ($st -and $st.Csv) {
        $p = if ($art -eq 'Sample') { $st.Csv } else { Join-Path (Split-Path -Parent $st.Csv) ((Split-Path -Leaf $st.Csv) -replace '^Sample-Inventur_', "$art-Inventur_") }
        if (Test-Path -LiteralPath $p) { $kand += @(Get-Item -LiteralPath $p) }
    }
    $kand | Sort-Object Name -Descending | Select-Object -First 1
}
function Get-NeuesterVergleich {
    $ordner = @(Get-VergleichOrdner)
    # 4.0.1: auch neben der Liste zum Stand im Ziel (z. B. im Ordner einer frueheren Version)
    $st = Get-BibliothekStand
    if ($st -and $st.Csv) { $ordner += Join-Path (Split-Path -Parent (Split-Path -Parent $st.Csv)) 'Inventur-Vergleiche' }
    @(foreach ($o in ($ordner | Select-Object -Unique)) { if (Test-Path -LiteralPath $o) { Get-ChildItem -LiteralPath $o -Filter 'Inventur-Vergleich_*.csv' -File -ErrorAction SilentlyContinue } }) |
        Sort-Object Name -Descending | Select-Object -First 1
}

# ---------------------------------------------------------------------------
# Papierkorb (unter Windows), im Testmodus (Umgebungsvariable SW_PAPIERKORB) ein Ordner
# ---------------------------------------------------------------------------
function Send-Papierkorb([string]$pfad) {
    if ($env:SW_PAPIERKORB) {
        $ziel = Join-Path $env:SW_PAPIERKORB ([guid]::NewGuid().ToString('N') + '_' + [IO.Path]::GetFileName($pfad))
        Move-Item -LiteralPath $pfad -Destination $ziel -Force
        return
    }
    Add-Type -AssemblyName Microsoft.VisualBasic
    if ($pfad.Length -ge $LangerPfad -and [IO.Path]::DirectorySeparatorChar -eq [char]92) {
        # 2.3.3: Der Papierkorb nimmt keine langen Pfade an. Datei zuerst auf demselben Laufwerk in einen
        # kurzen Hilfsordner verschieben (kein Kopieren, nichts geht verloren), dann in den Papierkorb.
        # Leere Ordner mit langem Pfad werden direkt entfernt (sie enthalten nichts).
        $lang = Get-LangPfad $pfad
        if ([IO.Directory]::Exists($lang)) { [IO.Directory]::Delete($lang, $false); return }
        $hilf = Join-Path ([IO.Path]::GetPathRoot($pfad)) '_Samples-Werkzeuge_Papierkorb'
        [void][IO.Directory]::CreateDirectory($hilf)
        $name = [IO.Path]::GetFileName($pfad); if ($name.Length -gt 120) { $name = $name.Substring(0, 110) + [IO.Path]::GetExtension($name) }
        $kurz = Join-Path $hilf ([guid]::NewGuid().ToString('N').Substring(0, 8) + '_' + $name)
        [IO.File]::Move($lang, $kurz)
        [Microsoft.VisualBasic.FileIO.FileSystem]::DeleteFile($kurz, 'OnlyErrorDialogs', 'SendToRecycleBin')
        try { if (-not @([IO.Directory]::EnumerateFileSystemEntries($hilf)).Count) { [IO.Directory]::Delete($hilf) } } catch { }
        return
    }
    if (Test-Path -LiteralPath $pfad -PathType Container) {
        [Microsoft.VisualBasic.FileIO.FileSystem]::DeleteDirectory($pfad, 'OnlyErrorDialogs', 'SendToRecycleBin')
    } else {
        [Microsoft.VisualBasic.FileIO.FileSystem]::DeleteFile($pfad, 'OnlyErrorDialogs', 'SendToRecycleBin')
    }
}

# Sammelordner in einer Sammlung: ein Ordner, dessen Name eine Gattung bezeichnet statt eines Packs (z. B. "Vocals",
# "Drumloops"); darin liegen die Packs eine Ebene tiefer. 4.1 (NFA-09): allgemeine Regel statt fester Namensliste.
$RxGattungsOrdner = '^(?i:(drum ?)?loops|drum ?loops|vocals?|vox|one[ -]?shots?|samples|sounds|sample ?packs|packs|drums|percussions?|bass|basslines|synths?|keys|pads|guitars?|brass|strings|fx|sfx|atmos(pheres)?|ambiences?|textures|foley|construction ?kits|drum ?kits|midi)$'

# Schluessel "Pack|Dateiname ohne Endung" fuer den Formatabgleich (RX2/MP3/AIFF neben WAV):
# gleichnamige Dateien gelten als Gegenstueck, wenn sie im selben Pack liegen - auch wenn das Pack
# WAV und RX2 in getrennten Unterordnern liefert (z. B. "...-Wav" und "...-Rex2").
function Get-FormatSchluessel([string]$datei, [string]$quelle) {
    $rel = $datei.Substring([Math]::Min($quelle.TrimEnd([char]92, '/').Length, $datei.Length)).TrimStart([char]92, '/')
    $t = @($rel -split '[\\/]')
    $pack = if ($t[0] -match $RxGattungsOrdner -and $t.Count -gt 2) { $t[0] + '\' + $t[1] } elseif ($t.Count -gt 1) { $t[0] } else { '' }
    return ($pack + '|' + [IO.Path]::GetFileNameWithoutExtension($datei)).ToLowerInvariant()
}

# CLN-04: Passt die Menge in den Papierkorb des Laufwerks? Liefert eine Warnung (Text) oder ''.
#   - Wechseldatentraeger und Netzlaufwerke haben keinen Papierkorb: Windows loescht dort endgueltig.
#   - "Dateien sofort loeschen" im Papierkorb eingestellt (NukeOnDelete): ebenso.
#   - Groesse: eingestellte Hoechstgroesse (MaxCapacity) bzw. Windows-Standard (ca. 10 % der ersten
#     40 GB + 5 % des Rests). Der schon belegte Teil des Papierkorbs ist nicht beruecksichtigt.
function Get-PapierkorbWarnung([string]$pfad, [long]$bytes) {
    if ($env:SW_PAPIERKORB -or -not $pfad -or $bytes -le 0) { return '' }
    try {
        $wurzelLw = [IO.Path]::GetPathRoot($pfad)
        if (-not $wurzelLw -or $wurzelLw.StartsWith('\\')) { return "Der Ordner liegt auf einem Netzlaufwerk ($wurzelLw). Dort gibt es keinen Papierkorb - Windows loescht die Dateien endgueltig." }
        $lw = $wurzelLw.Substring(0, 2)
        $vol = Get-CimInstance -ClassName Win32_Volume -Filter "DriveLetter='$lw'" -ErrorAction Stop | Select-Object -First 1
        if (-not $vol) {
            # Verbundene Netzlaufwerke (z. B. Z:) stehen nicht in Win32_Volume
            $ld = Get-CimInstance -ClassName Win32_LogicalDisk -Filter "DeviceID='$lw'" -ErrorAction SilentlyContinue | Select-Object -First 1
            if ($ld -and $ld.DriveType -eq 4) { return "Laufwerk $lw ist ein Netzlaufwerk. Dort gibt es keinen Papierkorb - Windows loescht die Dateien endgueltig." }
            if ($ld -and $ld.DriveType -eq 2) { return "Laufwerk $lw ist ein Wechseldatentraeger (z. B. USB-Stick). Dort gibt es keinen Papierkorb - Windows loescht die Dateien endgueltig." }
            return ''
        }
        if ($vol.DriveType -eq 2) { return "Laufwerk $lw ist ein Wechseldatentraeger (z. B. USB-Stick). Dort gibt es keinen Papierkorb - Windows loescht die Dateien endgueltig." }
        if ($vol.DriveType -eq 4) { return "Laufwerk $lw ist ein Netzlaufwerk. Dort gibt es keinen Papierkorb - Windows loescht die Dateien endgueltig." }
        $grenze = $null
        if ($vol.DeviceID -match '(\{[0-9A-Fa-f-]+\})') {
            $schl = "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\BitBucket\Volume\$($Matches[1])"
            if (Test-Path $schl) {
                $w = Get-ItemProperty -Path $schl -ErrorAction SilentlyContinue
                if ($w.NukeOnDelete -eq 1) { return "Fuer Laufwerk $lw ist im Papierkorb 'Dateien sofort loeschen' eingestellt. Die Dateien wuerden endgueltig geloescht." }
                if ($w.MaxCapacity) { $grenze = [long]$w.MaxCapacity * 1MB }
            }
        }
        if (-not $grenze -and $vol.Capacity) {
            $kap = [double]$vol.Capacity
            $grenze = [long]([Math]::Min($kap, 40GB) * 0.10 + [Math]::Max(0, $kap - 40GB) * 0.05)
        }
        if ($grenze -and $bytes -gt $grenze) {
            return ("Es sollen {0:N1} GB entfernt werden, der Papierkorb von Laufwerk {1} fasst nur etwa {2:N1} GB. Windows kann Dateien dann endgueltig loeschen statt sie in den Papierkorb zu legen. Tipp: in mehreren Schritten aufraeumen oder die Groesse des Papierkorbs erhoehen (Rechtsklick auf Papierkorb > Eigenschaften)." -f ($bytes / 1GB), $lw, ($grenze / 1GB))
        }
    } catch { }
    return ''
}

# Ja/Nein-Abfrage in der Konsole, Standard ist Nein
# 4.0: Laeuft das Skript im Hauptfenster (SW_GUI=1), kommt die Frage dort als Knopfleiste.
function Read-JaNein([string]$frage) {
    if ($env:SW_GUI -eq '1') {
        [Console]::Out.WriteLine('##FRAGE##' + $frage); [Console]::Out.Flush()
        $a = [Console]::In.ReadLine()
        return ([string]$a -match '^\s*[jJyY]')
    }
    $a = Read-Host "$frage (J/N, Standard N)"
    return ($a -match '^\s*[jJyY]')
}

# 4.1 (INV-11): dem Hauptfenster melden, dass sich die Sample-Bibliothek geaendert hat (Dateien kopiert oder entfernt)
function Send-BibliothekGeaendert {
    if ($env:SW_GUI -eq '1') { [Console]::Out.WriteLine('##BIB##'); [Console]::Out.Flush() }
}

# ---------------------------------------------------------------------------
# 4.0 (GUI-04): Ausgabe fuer das Hauptfenster. Die Skripte laufen dort ohne eigenes Konsolenfenster;
# Write-Host und Write-Progress werden als Zeilen mit Kennung ausgegeben, die das Fenster auswertet:
#   ##T##<Farbe>##<Text>     Textzeile (Farbe leer = normal)
#   ##P##<Prozent>##<Aktivitaet>##<Status>   Fortschritt; Prozent '-' = fertig
#   ##FRAGE##<Text>          Ja/Nein-Frage (Antwort kommt als Zeile J oder N)
# ---------------------------------------------------------------------------
if ($env:SW_GUI -eq '1') {
    try { [Console]::OutputEncoding = New-Object System.Text.UTF8Encoding($false) } catch { }
    $script:GuiZeile = ''
    function Write-Host {
        param([Parameter(Position = 0, ValueFromPipeline = $true)]$Object, $ForegroundColor, $BackgroundColor, [switch]$NoNewline, $Separator = ' ')
        process {
            $t = if ($null -eq $Object) { '' } elseif ($Object -is [array]) { ($Object | ForEach-Object { [string]$_ }) -join $Separator } else { [string]$Object }
            $script:GuiZeile += $t
            if ($NoNewline) { return }
            foreach ($z in ($script:GuiZeile -split "`r?`n")) { [Console]::Out.WriteLine('##T##' + [string]$ForegroundColor + '##' + $z) }
            $script:GuiZeile = ''
        }
    }
    function Write-Progress {
        param([Parameter(Position = 0)]$Activity, [Parameter(Position = 1)]$Status, $PercentComplete = -1, [switch]$Completed, $Id, $ParentId, $CurrentOperation, $SecondsRemaining)
        if ($Completed) { [Console]::Out.WriteLine('##P##-##' + $Activity + '##') }
        else { [Console]::Out.WriteLine('##P##' + [int]$PercentComplete + '##' + $Activity + '##' + $Status) }
    }
}

# ---------------------------------------------------------------------------
# 4.1 (NFA-08): Einmalige Uebernahme aus einer frueheren Version. Bis 4.0.2 lagen Einstellungen, Pack-Arten,
# Protokolle und Berichte im Programmordner. Beim ersten Start ohne eigene Daten werden sie aus dem neuesten
# Programmordner (dieser oder ein Nachbarordner) uebernommen; danach darf jede alte Version geloescht werden.
# ---------------------------------------------------------------------------
$uebernahmeMarke = Join-Path $datenOrdner 'Uebernahme.txt'
if (-not (Test-Path -LiteralPath $einstellungsPfad) -and -not (Test-Path -LiteralPath $uebernahmeMarke)) {
    $notiz = @("Samples-Werkzeuge $ProgrammVersion - Uebernahme $(Get-Date -Format 'dd.MM.yyyy HH:mm')")
    try {
        $kand = @($wurzel) + @(Get-ChildItem -LiteralPath (Split-Path -Parent $wurzel) -Directory -ErrorAction SilentlyContinue | ForEach-Object { $_.FullName })
        $alt = @($kand | Select-Object -Unique | ForEach-Object { Join-Path (Join-Path $_ 'Skripte') 'Einstellungen.json' } |
            Where-Object { Test-Path -LiteralPath $_ } | ForEach-Object { Get-Item -LiteralPath $_ } | Sort-Object LastWriteTime -Descending) | Select-Object -First 1
        if ($alt) {
            $altWurzel = Split-Path -Parent (Split-Path -Parent $alt.FullName)
            $notiz += "aus: $altWurzel"
            Copy-Item -LiteralPath $alt.FullName -Destination $einstellungsPfad -ErrorAction Stop
            Set-Einstellung 'ErsterStartErledigt' $false   # Begruessung (Desktop-Verknuepfung) auch in der neuen Version
            $pa = Join-Path (Join-Path $altWurzel 'Skripte') 'Pack-Arten.csv'
            if (Test-Path -LiteralPath $pa) { Copy-Item -LiteralPath $pa -Destination $packArtenPfad -ErrorAction SilentlyContinue; $notiz += 'Pack-Arten.csv' }
            $kopiere = { param($von, $nach, $filter)
                $n = 0
                if (Test-Path -LiteralPath $von) {
                    [void][IO.Directory]::CreateDirectory($nach)
                    foreach ($f in @(Get-ChildItem -LiteralPath $von -File -Filter $filter -ErrorAction SilentlyContinue)) {
                        $z = Join-Path $nach $f.Name
                        if (-not (Test-Path -LiteralPath $z)) { try { Copy-Item -LiteralPath $f.FullName -Destination $z -ErrorAction Stop; $n++ } catch { } }
                    }
                }
                return $n
            }
            $notiz += "Protokolle: $(& $kopiere (Join-Path $altWurzel 'Protokolle') $protokollOrdner '*')"
            # Alte Einstellung "Berichtsordner" (Standard: der Programmordner)
            $cfgAlt = $null; try { $cfgAlt = Get-Content -LiteralPath $alt.FullName -Raw -Encoding UTF8 | ConvertFrom-Json } catch { }
            $bo = if ($cfgAlt -and $cfgAlt.Berichtsordner) { [string]$cfgAlt.Berichtsordner } else { $altWurzel }
            $notiz += "Fundorte: $(& $kopiere (Join-Path $bo 'Fundorte') $fundortOrdner 'Fundorte_*')"
            # Berichte der Bibliothek: die letzten 10 Staende ins Ziel
            $zielNeu = if ($cfgAlt -and $cfgAlt.Ziel) { [string]$cfgAlt.Ziel } else { '' }
            if ($zielNeu -and (Test-Path -LiteralPath $zielNeu)) {
                $bib = Join-Path (Get-ZielProtokollOrdner $zielNeu) 'Bibliothek'
                $inv = Join-Path $bo 'Inventuren'; $vgl = Join-Path $bo 'Inventur-Vergleiche'
                $stempel = @(Get-ChildItem -LiteralPath $inv -Filter 'Sample-Inventur_*.csv' -File -ErrorAction SilentlyContinue | Sort-Object Name -Descending | Select-Object -First 10 |
                    ForEach-Object { $_.BaseName -replace '^Sample-Inventur_', '' })
                $n = 0
                foreach ($st in $stempel) {
                    $n += & $kopiere $inv $bib "Sample-Inventur_$st.*"
                    $n += & $kopiere $inv $bib "Pack-Inventur_$st.*"
                    $n += & $kopiere $vgl $bib "Inventur-Vergleich_$st.*"
                }
                $notiz += "Bibliothek: $n Dateien nach $bib"
            }
        } else { $notiz += 'keine fruehere Version gefunden' }
    } catch { $notiz += "Fehler: $($_.Exception.Message)"; Write-FehlerLog "Uebernahme: $($_.Exception.Message)" }
    try { Set-Content -LiteralPath $uebernahmeMarke -Value $notiz -Encoding UTF8 } catch { }
}
