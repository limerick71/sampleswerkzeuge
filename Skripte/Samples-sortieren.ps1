# (c) 2026 Herbert Stoecker. Kostenlos nutzbar. Bitte nur als Link auf die offizielle Download-Seite weitergeben; Verkauf und Veroeffentlichung geaenderter Fassungen nur mit Zustimmung.
<#
.SYNOPSIS
  Kopiert Sounds & Samples aus dem Quellordner in den Zielordner (Standard:
  "E:\Sounds und Samples" -> "E:\Samples"), sortiert nach Instrument
  (One-Shots / Loops). Es wird NICHTS geloescht und NICHTS ueberschrieben.
  Quelle und Ziel kommen aus Skripte\Einstellungen.json (in der Oberflaeche einstellbar).

.BENUTZUNG
  Ohne Schalter: Vorschau anzeigen, CSV in "Protokolle" schreiben und fragen,
  ob kopiert werden soll (Standard: Nein).
    -NurVorschau   nur Vorschau, keine Frage
    -Ausfuehren    ohne Frage kopieren
    -Quelle / -Ziel  abweichende Ordner fuer diesen Lauf

.REGELN
  - Unter jeder Kategorie bleibt der Pack-Name als Unterordner erhalten.
  - Dateinamen bleiben unveraendert.
  - Identische Dateien (gleicher Name + Groesse + Inhalt) werden nur einmal abgelegt.
  - Construction Kits und Ableton-Drum-Kits bleiben als Ganzes erhalten.
  - Hersteller-Bibliotheken direkt in der Quelle (z. B. "ModX", "Native Instruments") werden komplett ausgespart.
  - .asd (Ableton-Analyse) und .DS_Store / Thumbs.db werden nicht kopiert.
  - Bereits vorhandene Zieldateien werden nie ueberschrieben; sie erscheinen schon in der
    Vorschau als "bereits im Ziel".
  - Ordner-Verknuepfungen (Junctions) in der Quelle werden nicht verfolgt.
  - Liegt derselbe Inhalt schon irgendwo im Ziel (anderer Ordner oder anderer Name),
    wird die Datei nicht erneut kopiert (Vorfilter Groesse, dann Pruefsumme; Kits ausgenommen).
#>
[CmdletBinding()]
param(
    [string]$Quelle = '',
    [string]$Ziel   = '',
    [switch]$NurVorschau,
    [switch]$Ausfuehren,
    # Version 3 (Import): Quellen fuer diesen Lauf als "Pfad*Art|Pfad*Art", eigene Frage vor dem Kopieren,
    # Protokoll auch dann, wenn nichts Neues zu kopieren ist (der Import braucht es fuer die Originale)
    [string]$Quellen = '',
    [string]$Frage = '',
    [switch]$ImmerProtokoll
)

$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'Gemeinsam.ps1')
$Zeitstempel  = Get-Date -Format 'yyyy-MM-dd_HHmmss'

$einst = Get-Einstellungen
# Quellen (QLN-05): alle aktiven aus der Quellenliste, oder -Quelle fuer einen einzelnen Lauf
$QuellObjekte = if ($Quellen) { @($Quellen -split '\|' | Where-Object { $_ } | ForEach-Object { $t = $_ -split '\*'; [pscustomobject]@{ Pfad = $t[0]; Art = $(if ($t.Count -gt 1) { $t[1] } else { 'Pack' }); Einzeln = $(if ($t.Count -gt 2) { $t[2] } else { '' }) } }) }
                elseif ($Quelle) { @([pscustomobject]@{ Pfad = $Quelle; Art = 'Sammlung' }) } else { @(Get-AktiveQuellObjekte) }
$QuellListe = @($QuellObjekte | ForEach-Object { $_.Pfad })
if (-not $Ziel)   { $Ziel   = $einst.Ziel }
Write-Host "Samples sortieren (Samples-Werkzeuge $ProgrammVersion)" -ForegroundColor Cyan
foreach ($q in $QuellObjekte) { Write-Host "  Quelle: $($q.Pfad)  ($($QuellArten[(Get-QuellArtName $q.Art)]))" }
Write-Host "  Ziel:   $Ziel"
Write-Host ""

if (-not $QuellListe.Count) { throw "Es ist keine Quelle aktiv (in der Oberflaeche unter Einstellungen hinzufuegen oder anhaken)." }
$artVon = @{}; $einzelnVon = @{}
$QuellListe = @(foreach ($qo in $QuellObjekte) {
    $q = $qo.Pfad
    if (-not (Test-Path -LiteralPath $q)) { throw "Quellordner nicht gefunden: $q  (in der Oberflaeche unter Einstellungen aendern)" }
    $v = (Resolve-Path -LiteralPath $q).ProviderPath; if ($v.Length -gt 3) { $v = $v.TrimEnd('\','/') }
    $artVon[$v] = Get-QuellArtName $qo.Art
    # 3.0.1 (Import): Pack-Name fuer Dateien direkt in einer Sammlung (sonst "_Einzeldateien"), z. B. der Name des Bundles
    if ($qo.PSObject.Properties['Einzeln'] -and $qo.Einzeln) { $einzelnVon[$v] = [string]$qo.Einzeln }
    $v
})
$Ziel   = $Ziel.TrimEnd('\','/')
foreach ($q in $QuellListe) { $pruef = Test-QuelleZiel $q $Ziel $artVon[$q]; if ($pruef) { throw "$pruef ($q)" } }
# 2.3.4: Sammlung, deren Packs erst tiefer liegen (z. B. Splice -> Samples -> packs): sonst wird "Samples" zum Pack-Namen
$PackTiefer = @(foreach ($q in $QuellListe) { if ($artVon[$q] -eq 'Sammlung') { $eb = Get-PackEbene $q; if ($eb) { [pscustomobject]@{ Quelle = $q; Ebene = $eb; Name = ($eb.Substring($q.Length).TrimStart('\','/') -split '[\\/]')[0] } } } })
foreach ($t in $PackTiefer) {
    Write-Host "ACHTUNG: In der Quelle $($t.Quelle) liegen die Packs erst in $($t.Ebene)." -ForegroundColor Yellow
    Write-Host "  Beim Sortieren wuerde '$($t.Name)' zum Pack-Namen. Bitte unter Einstellungen umstellen (Klick in der Spalte Zustand)." -ForegroundColor Yellow
}
if ($PackTiefer.Count) { Write-Host "" }
# Bezugsordner fuer Pack-Namen: bei "Ein Pack" und "Nur lose Dateien" der Elternordner, damit der
# Quellordner selbst die erste Ebene (= Pack-Name) ist
function Get-PackWurzel([string]$q) {
    if ($artVon[$q] -eq 'Sammlung') { return $q }
    $e = [IO.Path]::GetDirectoryName($q)
    if ($e) { return $e.TrimEnd('\','/') } else { return $q }
}
$Quelle = $QuellListe[0]
$zielStatus = Get-OrdnerStatus $Ziel
if ($zielStatus.Fehlt) { throw "Ziel nicht erreichbar: $($zielStatus.Text)  (in der Oberflaeche unter 'Einstellungen' aendern)" }
# Programmordner und Protokolle nie mitkopieren, falls sie in der Quelle liegen
$Ausnahmen = @($wurzel, $protokollOrdner) | Where-Object { $_ } | ForEach-Object { $_.TrimEnd('\','/') }

# ----------------------------------------------------------------------------
# Kategorien
# ----------------------------------------------------------------------------
$K = @{
    Kick      = '01 Drums\Kick'
    Snare     = '01 Drums\Snare'
    Clap      = '01 Drums\Clap'
    HiHat     = '01 Drums\HiHat'
    Cymbals   = '01 Drums\Cymbals'
    Toms      = '01 Drums\Toms'
    DrumLoops = '01 Drums\Drum-Loops'
    DrumKits  = '01 Drums\Drum-Kits'
    Shaker    = '02 Percussion\Shaker & Tambourine'
    Conga     = '02 Percussion\Conga & Bongo'
    Perc      = '02 Percussion\Diverse Percs'
    Foley     = '02 Percussion\Foley'
    Bass      = '03 Bass'
    Keys      = '04 Keys & Synth\Keys'
    Synth     = '04 Keys & Synth\Synth'
    Melodic   = '04 Keys & Synth\Melodic'
    Guitar    = '05 Guitar'
    Brass     = '06 Brass & Sax'
    Vocals    = '07 Vocals'
    FX        = '08 FX & Noise'
    Atmos     = '09 Atmos & Field Recordings'
    Kits      = '10 Construction Kits'
    MIDI      = '11 MIDI'
    Songs     = '12 Songs & Playalongs'
    Strings   = '13 Strings & Orchestra'
    Infos     = '_Lizenzen & Infos'
    Sonstiges = '_Sonstiges'
    Unsortiert= '_Unsortiert'
}
# Kategorien mit Unterteilung One-Shots / Loops
$MitTyp = @('Kick','Snare','Clap','HiHat','Cymbals','Toms','Shaker','Conga','Perc','Foley','Bass','Guitar','Keys','Synth','Melodic','Strings','Brass')

# Instrument-Erkennung: Reihenfolge = Prioritaet (erster Treffer gewinnt)
$Instrumente = @(
    @('Clap',      'clap|(?<![a-z])cp(?![a-z])'),
    @('HiHat',     'hi-?hat|hats?(?![a-z])|(?<![a-z])(hh|ch|oh)(?![a-z])'),
    @('Cymbals',   'cymbal|crash|(?<![a-z])ride(?![a-z])|(?<![a-z])(cc|rc)(?![a-z])|china'),
    @('Snare',     'snare|(?<![a-z])rim|(?<![a-z])(sd|rs)(?![a-z])'),
    @('Toms',      '(?<![a-z])toms?(?![a-z])|(?<![a-z])(lt|mt|ht)(?![a-z])'),
    @('Kick',      'kick|(?<![a-z])bd(?![a-z])|bassdrum'),
    @('Shaker',    'shak|tamb|(?<![a-z])sh(?![a-z])'),
    @('Conga',     'conga|bongo|(?<![a-z])cong(?![a-z])|djemb|timbal'),
    @('Foley',     'foley|stapler|coins|door|knock|footstep'),
    @('Perc',      'perc|(?<![a-z])pc(?![a-z])|cowbell|(?<![a-z])cb\d*(?![a-z])|clave|(?<![a-z])wood(?!wind)|block'),
    @('FX',        'noise|(?<![a-z])fx(?![a-z])|riser|sweep|impact|transition|gunshot|explosion|whoosh|swoosh|applause|crowd|laser'),
    @('Bass',      'bass|(?<![a-z])303(?![0-9])|(?<![a-z])acd'),
    # 2.3.3: melodische Instrumente und Vocals aus dem Dateinamen (vorher nur ueber einzelne Packs)
    @('Vocals',    'vocal|(?<![a-z])vox(?![a-z])|acapella|a ?cappella|adlib|ad-lib|choir|chant|(?<![a-z])vocs?(?![a-z])'),
    @('Brass',     'trumpet|(?<![a-z])sax|brass|(?<![a-z])horns?(?![a-z])|trombone|tuba|flute|clarinet|woodwind|flugel|oboe'),
    @('Strings',   '(?<![a-z])strings?(?![a-z])|violin|viola|cello|orchestr|ensemble|pizz|(?<![a-z])harp(?![a-z])|staccato|spiccato|legato|tremolo'),
    @('Guitar',    'guitar|(?<![a-z])gtr|strum|nylon|ukulele|banjo|sitar|(?<![a-z])oud(?![a-z])|baglama|bou?zou?ki|buzuki|tumbi|gayageum|koto|mandolin|dobro'),
    @('Keys',      'piano|(?<![a-z])keys(?![a-z])|rhodes|e-?piano|organ(?!ic)|wurli|clavinet|kalimba|mallet|marimba|vibraphone|xylophone|glockenspiel|celesta|music ?box|(?<![a-z])bells?(?![a-z])'),
    @('Synth',     'synth|(?<![a-z])leads?(?![a-z])|(?<![a-z])arps?(?![a-z])|arpegg|(?<![a-z])pads?(?![a-z])|chords?|(?<![a-z])stabs?(?![a-z])|pluck|moog'),
    @('Melodic',   'melod|song ?[_-]?starter|music ?[_-]?loop'),
    @('Atmos',     'ambient|ambience|atmo|field|(?<![a-z])rain(?![a-z])|street|nature|forest|(?<![a-z])birds?(?![a-z])'),
    @('DrumLoops', 'drum|beat|groove|full|top ?loop|brush|break|rhythm')
)
# Fallback je Pack, wenn weder Datei- noch Ordnername etwas hergeben
$PackFallback = @(,
    @('VOLTAGE REVELATIONS', 'DrumLoops')
)

$RxOneShot = 'one[ _-]?shot|(?<![a-z])shots(?![a-z])'   # 2.3.5: auch one_shots
$RxLoop    = 'loop|bpm|(?<![a-z])(groove|beat|fill)s?(?![a-z])'
$RxDoku    = '\.(pdf|txt|rtf|nfo|png|jpe?g|gif|bmp|html?|url|docx?)$'
$RxAudio   = '\.(wav|aiff?|mp3|flac|ogg|rx2|rex|m4a)$'
# 2.3.3: werden nie kopiert
$ExtProgramm = @('.exe', '.msi', '.dmg', '.pkg', '.app', '.bat', '.cmd', '.ps1', '.iso', '.appx', '.msix', '.apk', '.jar', '.deb', '.dll', '.vst3', '.component', '.aaxplugin', '.clap')
$ExtPlugin   = @('.vstsound', '.nki', '.nkx', '.nkc', '.nkr', '.nicnt', '.ncw', '.nkm', '.nkb', '.nksn', '.ens', '.exs', '.gig', '.sf2', '.ufs', '.zmulti', '.hsb', '.vstpreset', '.fxp', '.fxb', '.h2p', '.nmsv')
$ExtArchiv   = @('.zip', '.rar', '.7z', '.alp', '.tar', '.gz', '.tgz', '.bz2', '.xz')

function Get-WavSekunden([string]$Pfad, [long]$Groesse) {
    if ($Pfad -notmatch '\.wav$') { return -1 }
    try {
        $fs = [IO.File]::OpenRead((Get-LangPfad $Pfad))
        try {
            $buf = New-Object byte[] 64
            $n = $fs.Read($buf, 0, 64)
        } finally { $fs.Close() }
        if ($n -lt 32) { return -1 }
        if ([Text.Encoding]::ASCII.GetString($buf, 0, 4) -ne 'RIFF') { return -1 }
        $byteRate = [BitConverter]::ToInt32($buf, 28)
        if ($byteRate -le 0) { return -1 }
        return ($Groesse - 44) / $byteRate
    } catch { return -1 }
}

# Version 3 (QLN-11): zuerst ganze Woerter (harp, piano ...), erst danach Kuerzel (BD, SD, RS, HH ...).
# Kuerzel, die den Anfangsbuchstaben des Pack-Namens entsprechen, zaehlen nicht (Boogie Down -> BD).
$RxKuerzel = '(?<![a-z])(cp|hh|ch|oh|cc|rc|sd|rs|lt|mt|ht|bd|sh|pc|cb)(?![a-z])'
function Get-PackInitialen([string]$Pack) {
    $w = @(($Pack.ToLowerInvariant() -split '[^a-z0-9]+') | Where-Object { $_ -match '^[a-z]' })
    if ($w.Count -ge 2) { return $w[0].Substring(0, 1) + $w[1].Substring(0, 1) }
    return ''
}
function Find-Instrument([string]$Text, [string]$Pack = '') {
    $t = $Text.ToLowerInvariant() -replace 'no ?kick', ' ' -replace 'stripped', ' '
    $ohneKuerzel = $t -replace $RxKuerzel, ' '
    foreach ($i in $Instrumente) { if ($ohneKuerzel -match $i[1]) { return $i[0] } }
    $ini = Get-PackInitialen $Pack
    if ($ini) { $t = $t -replace "(?<![a-z])$ini(?![a-z])", ' ' }
    foreach ($i in $Instrumente) { if ($t -match $i[1]) { return $i[0] } }
    return $null
}

# 4.0.2: Dateiname nennt ein Instrument, aber kein Vocal-Wort (dann geht er einem Pack-/Ordnernamen "Vocal" vor)
function Test-AnderesInstrument([string]$Datei, [string]$Pack) {
    $d = $Datei.ToLowerInvariant()
    if ($d -match $RxVocalWort) { return $false }
    $i = Find-Instrument $Datei $Pack
    return ($i -and $i -ne 'Vocals')
}
$RxVocalWort = 'vocal|(?<![a-z])vox(?![a-z])|acapella|a ?cappella|adlib|ad-lib|choir|chant|(?<![a-z])vocs?(?![a-z])'

function Get-Typ([string]$Datei, [string[]]$Ordner, [string]$Pfad, [long]$Groesse, [string]$Instrument, [bool]$StandardLoop) {
    $d = $Datei.ToLowerInvariant()
    if ($d -match $RxOneShot) { return 'One-Shots' }
    if ($d -match $RxLoop) { return 'Loops' }
    for ($i = $Ordner.Count - 1; $i -ge 0; $i--) {
        $o = $Ordner[$i].ToLowerInvariant()
        if ($o -match $RxOneShot) { return 'One-Shots' }
        if ($o -match $RxLoop)    { return 'Loops' }
    }
    # 2.3.5: Zahl am Ende nur als Tempo, wenn sie wie eines aussieht (60-200, ohne fuehrende Null) - "kick_01" ist eine Laufnummer
    if ($d -match '_([1-9]\d{1,2})(\.\d+)?$' -and [int]$Matches[1] -ge 60 -and [int]$Matches[1] -le 200) { return 'Loops' }
    if ($StandardLoop) { return 'Loops' }
    if ($Instrument -eq 'Cymbals') { return 'One-Shots' }
    if ($Pfad -match '\.(rx2|rex)$') { return 'Loops' }   # 2.3.3: REX/RX2 sind geschnittene Loops
    $sek = Get-WavSekunden $Pfad $Groesse
    if ($sek -ge 6) { return 'Loops' }
    return 'One-Shots'
}

# 3.0.1: Ordner, die nur Typ, Format oder eine Huelle beschreiben, zaehlen nicht als Unterordner des Packs
$RxTypOrdner = '^(loops?|one[ _-]?shots?|oneshots|samples?|sounds|wav|wave|waves|aiff?|rex2?|rx2|audio|audio files|files|content|stems?|kicks?|snares?|hats?|hi[ -]?hats?|claps?|percs?|percussion|toms?|cymbals?|drums?|drum ?loops|drum ?hits|bass|basslines?|bass ?loops|synths?|synth ?loops|keys|pads?|leads?|fx|sfx|midi|music ?loops|top ?loops|\d+)$|[-_ ](wav|rex2?|rx2|aiff?|24 ?bit|16 ?bit|midi)$'
function Get-UnterOrdner([string[]]$Ordner, [string]$Pack) {
    $p = Get-NormName $Pack
    foreach ($o in $Ordner) {
        $l = $o.ToLowerInvariant().Trim(); $n = Get-NormName $o
        if ($l -match $RxTypOrdner) { continue }
        if ($n -eq $p -or ($p.Length -ge 4 -and $n.Contains($p)) -or ($n.Length -ge 6 -and $p.Contains($n))) { continue }   # Huelle mit dem Pack-Namen
        return $o
    }
    return ''
}

function Join-Rel([string[]]$Teile) {
    $t = @($Teile | Where-Object { $_ -and $_.Trim() -ne '' })
    if ($t.Count -eq 0) { return '' }
    $sep = [string][IO.Path]::DirectorySeparatorChar
    return (($t -join $sep) -replace '[\\/]+', $sep)
}

# ----------------------------------------------------------------------------
# 1) Einlesen und klassifizieren
# ----------------------------------------------------------------------------
# Eigene Rekursion: Ordner-Verknuepfungen (Junctions, z. B. "Anwendungsdaten") werden nicht verfolgt,
# nicht lesbare Ordner werden gezaehlt statt das Skript abzubrechen. Je Datei wird ihre Quelle gemerkt.
$nichtLesbar = 0
$alle = New-Object System.Collections.Generic.List[object]
$wurzelVon = @{}
$ausgespart = @{}
foreach ($QWurzel in $QuellListe) {
    Write-Host "Lese Dateien aus '$QWurzel' ..." -ForegroundColor Cyan
    $stapel = New-Object System.Collections.Generic.Stack[string]
    $stapel.Push($QWurzel)
    while ($stapel.Count -gt 0) {
        $ordner = $stapel.Pop()
        try { $inhalt = @(Get-ChildItem -LiteralPath $ordner -Force -ErrorAction Stop) }
        catch { $nichtLesbar++; continue }
        foreach ($e in $inhalt) {
            if ($e.PSIsContainer) {
                if ($artVon[$QWurzel] -eq 'Lose') { continue }   # nur Dateien direkt im Ordner
                if ($e.Attributes -band [IO.FileAttributes]::ReparsePoint) { continue }
                if ($ordner -eq $QWurzel -and $e.Name -match $RxHerstellerOrdner) { $ausgespart[$e.FullName] = $true; continue }
                $stapel.Push($e.FullName)
            } else { $alle.Add($e); $wurzelVon[$e.FullName] = $QWurzel }
        }
    }
}
foreach ($a in @($ausgespart.Keys | Sort-Object)) { Write-Host "Hinweis: Hersteller-Bibliothek '$a' wird ausgespart." -ForegroundColor DarkGray }
if ($nichtLesbar -gt 0) { Write-Host "Hinweis: $nichtLesbar Ordner waren nicht lesbar und wurden ausgelassen." -ForegroundColor Yellow }
$plan = New-Object System.Collections.Generic.List[object]

$alle = @($alle | Where-Object {
    $voll = $_.FullName
    -not @($Ausnahmen | Where-Object { $voll.StartsWith($_ + [IO.Path]::DirectorySeparatorChar, [StringComparison]::OrdinalIgnoreCase) }).Count
})
foreach ($f in $alle) {
    $QWurzel = $wurzelVon[$f.FullName]
    $PWurzel = Get-PackWurzel $QWurzel
    $rel   = $f.FullName.Substring($PWurzel.Length).TrimStart('\','/')
    $teile = $rel -split '[\\/]'
    $name  = $f.Name
    $nameL = $name.ToLowerInvariant()
    $basis = [IO.Path]::GetFileNameWithoutExtension($name)

    $eintrag = [ordered]@{
        Aktion = 'Kopieren'; Kategorie = ''; Quelle = $f.FullName; Ziel = ''
        GroesseMB = [math]::Round($f.Length / 1MB, 2); Bytes = $f.Length
        Dedup = $true; ZielRel = ''; Hinweis = ''; Quellordner = $QWurzel; PackWurzel = $PWurzel
    }

    # --- macOS-Reste (CLN-10): werden nicht kopiert, bleiben in der Quelle (Grundsatz: Sortieren liest die Quelle nur).
    #     Erkennung ueber Name und Dateikopf; passt nur der Name, wird normal einsortiert und "unklar" vermerkt.
    $macArt = Get-MacRestArt $f.FullName
    if ($macArt -eq 'mac') {
        $eintrag.Aktion = 'Mac-Rest'; $eintrag.Kategorie = 'macOS-Rest'
        $eintrag.Hinweis = if ($nameL -eq '.ds_store') { 'Finder-Ansichtseinstellungen (.DS_Store)' } elseif ($f.FullName -match '[\\/]__MACOSX[\\/]') { 'Inhalt eines __MACOSX-Ordners (AppleDouble)' } else { 'Finder-Zusatzinformationen zu einer Datei (AppleDouble)' }
        $plan.Add([pscustomobject]$eintrag); continue
    }
    if ($macArt -eq 'unklar') { $eintrag.Hinweis = 'Name wie ein macOS-Rest, Inhalt aber nicht - unklar, wird einsortiert' }

    # --- Ignorieren -------------------------------------------------------
    # Hilfsdateien: entstehen automatisch durch Programme oder Betriebssysteme, enthalten keinen Klang
    $grund = ''
    if ($teile[0] -eq '_Sortier-Skript' -or $teile[0] -like 'Samples-Werkzeuge*') { $grund = 'Datei der Samples-Werkzeuge' }
    elseif ($nameL.EndsWith('.asd'))    { $grund = 'Ableton-Analysedatei (.asd), legt Ableton bei Bedarf neu an' }
    elseif ($nameL -eq 'thumbs.db')     { $grund = 'Windows-Vorschaubilder-Zwischenspeicher' }
    elseif ($nameL -eq 'desktop.ini')   { $grund = 'Windows-Ordnereinstellungen' }
    if ($grund) {
        $eintrag.Aktion = 'Ignoriert'; $eintrag.Kategorie = 'Hilfsdatei'; $eintrag.Hinweis = $grund
        $plan.Add([pscustomobject]$eintrag); continue
    }
    # 2.3.3: Programme, Installer, Plugin-Inhalte und Archive werden nie kopiert (bleiben in der Quelle);
    # bei "Nur lose Dateien" nur Audio- und MIDI-Dateien
    $endung = [IO.Path]::GetExtension($nameL)
    if ($endung -in $ExtProgramm) { $grund = 'Programm oder Installer' }
    elseif ($endung -in $ExtPlugin) { $grund = 'Plugin- oder Instrument-Inhalt (gehoert zum Plugin)' }
    elseif ($endung -in $ExtArchiv) { $grund = 'Archiv - vorher entpacken (im Download-Ordner: Download importieren)' }
    elseif ($artVon[$QWurzel] -eq 'Lose' -and $nameL -notmatch $RxAudio -and $nameL -notmatch '\.midi?$') { $grund = 'keine Audio- oder MIDI-Datei (bei Nur lose Dateien werden nur diese uebernommen)' }
    if ($grund) {
        $eintrag.Aktion = 'Kein Sample'; $eintrag.Kategorie = 'kein Sample'; $eintrag.Hinweis = $grund
        $plan.Add([pscustomobject]$eintrag); continue
    }

    # --- Pack bestimmen (Sammelordner haben Packs eine Ebene tiefer) ------
    if ($artVon[$QWurzel] -eq 'Sammlung' -and ($teile[0] -in @('Drumloops','Lofi Sounds - Free Sample Pack','Vocals')) -and $teile.Count -gt 2) {
        $pack = $teile[1]; $packRel = $teile[2..($teile.Count - 1)]
    } elseif ($teile.Count -gt 1) {
        $pack = $teile[0]; $packRel = $teile[1..($teile.Count - 1)]
    } else {
        $pack = $(if ($einzelnVon.ContainsKey($QWurzel)) { $einzelnVon[$QWurzel] } else { '_Einzeldateien' }); $packRel = @($teile[0])
    }
    if ($artVon[$QWurzel] -eq 'Sammlung' -and $teile[0] -eq 'Vocals' -and $teile.Count -eq 2) { $pack = 'Vocals (Einzeldateien)' }
    # 2.3.2: lose Dateien eines Ordners (z. B. Downloads) als Pack "Einzeldateien (Ordnername)"
    if ($artVon[$QWurzel] -eq 'Lose') { $pack = "Einzeldateien ($($teile[0]))" }
    $packOrdner = @(); if ($packRel.Count -gt 1) { $packOrdner = $packRel[0..($packRel.Count - 2)] }
    $relImPack  = Join-Rel $packRel
    $alleOrdner = @(); if ($teile.Count -gt 1) { $alleOrdner = $teile[0..($teile.Count - 2)] }
    $ordnerText = ($alleOrdner -join ' ')
    # 3.0.1: erste aussagekraeftige Ordnerebene unter dem Pack bleibt erhalten (z. B. "Alto Sax", "Female Vocals")
    $unter = Get-UnterOrdner $packOrdner $pack

    $zr = $null; $kat = $null

    # --- Ganze Bibliotheken / Kits 1:1 ------------------------------------
    if ($pack -match 'BSH126') {
        $kat = 'Kits'; $zr = Join-Rel @($K.Kits, 'BSH126 Midnight Synth Funk', $relImPack); $eintrag.Dedup = $false
    } elseif ($pack -match 'Tape Stacks') {
        if ($nameL.EndsWith('.xmp')) { $eintrag.Aktion = 'Ignoriert'; $eintrag.Kategorie = 'Hilfsdatei'; $eintrag.Hinweis = 'Metadaten-Datei (.xmp)'; $plan.Add([pscustomobject]$eintrag); continue }
        $kat = 'Kits'; $zr = Join-Rel @($K.Kits, $pack, $relImPack); $eintrag.Dedup = $false
    } elseif (($idx = [array]::IndexOf(@($packOrdner | ForEach-Object { $_.ToUpperInvariant() }), 'DRUM KITS')) -ge 0) {
        $rest = $packRel[($idx + 1)..($packRel.Count - 1)]
        $kat = 'DrumKits'; $zr = Join-Rel @($K.DrumKits, $pack, (Join-Rel $rest)); $eintrag.Dedup = $false
    }
    # --- Ableton-Ordnerinfos, Doku, MIDI, Sonstiges -----------------------
    elseif ($nameL.EndsWith('.xmp') -or $ordnerText -match 'Ableton (Folder|Project) Info') {
        $eintrag.Aktion = 'Ignoriert'; $eintrag.Kategorie = 'Hilfsdatei'
        $eintrag.Hinweis = if ($nameL.EndsWith('.xmp')) { 'Metadaten-Datei (.xmp)' } else { 'Ableton-Ordnerinformation (Ableton Folder/Project Info)' }
        $plan.Add([pscustomobject]$eintrag); continue
    } elseif ($teile[0] -match '^Komplette St') {
        $kat = 'Songs'; $zr = Join-Rel @($K.Songs, $teile[0], $relImPack)
    } elseif ($teile[0] -match '100ufgrooves') {
        $kat = 'Songs'; $zr = Join-Rel @($K.Songs, $teile[0], $relImPack)
    } elseif ($nameL -match $RxDoku) {
        $kat = 'Infos'; $zr = Join-Rel @($K.Infos, $pack, $unter, $name)
    } elseif ($nameL -match '\.midi?$') {
        $kat = 'MIDI'; $zr = Join-Rel @($K.MIDI, $pack, $unter, $name)
    } elseif ($nameL -notmatch $RxAudio) {
        $kat = 'Sonstiges'; $zr = Join-Rel @($K.Sonstiges, $pack, $unter, $name)
    }
    # --- Melodische / thematische Packs -----------------------------------
    # 2.3.2: Vocals auch ueber Ordnernamen im Pack erkennen (z. B. "Pack\Vocal Loops\...")
    # 4.0.2: Nennt der Dateiname ein anderes Instrument (z. B. "brass_saxophone_loop", "bass_synth_loop") und
    # kein Vocal-Wort, geht er dem Pack- bzw. Ordnernamen "Vocal" vor (Splice-Packs wie "Vocal Sessions ...").
    elseif ($teile[0] -eq 'Vocals' -or (($pack -match 'Vocal' -or @($packOrdner | Where-Object { $_ -match '\bVocals?\b|\bVox\b|Acapella|A cappella' }).Count) -and -not (Test-AnderesInstrument $basis $pack))) {
        # 2.3.4: wie die anderen Kategorien ohne den inneren Ordnerweg (gleichnamige Dateien bekommen unten ihren Unterordner)
        $kat = 'Vocals'; $zr = Join-Rel @($K.Vocals, $pack, $unter, $name)
    } elseif ($teile[0] -eq 'Brass') {
        $kat = 'Brass'; $zr = Join-Rel @($K.Brass, 'Brass (Mugent)', $name)
    } elseif ($pack -match 'Melancholic Rhodes|Lofi Blessings') {
        $kat = 'Keys'; $zr = Join-Rel @($K.Keys, $pack, $unter, $name)
    } elseif ($pack -match 'Zen Guitar') {
        $kat = 'Guitar'; $zr = Join-Rel @($K.Guitar, $pack, $relImPack)
    } elseif ($pack -match 'Ambiences') {
        $kat = 'Atmos'; $zr = Join-Rel @($K.Atmos, $pack, $unter, $name)
    } elseif ($pack -match 'Riemann Techno Basslines' -or $rel -match 'Sub Bass Loops') {
        $kat = 'Bass'; $zr = Join-Rel @($K.Bass, 'Loops', $pack, $unter, $name)
    } elseif ($rel -match 'FX Kicks|Transition Kicks') {
        $kat = 'FX'; $zr = Join-Rel @($K.FX, $pack, $unter, $name)
    } elseif ($pack -match 'Warped Foley') {
        $kat = 'Foley'; $zr = Join-Rel @($K.Foley, 'Loops', $pack, $unter, $name)
    } elseif ($pack -match 'Lofi Forest') {
        if ($nameL -match 'atmo|forest|rain|creek|pad|bird') { $kat = 'Atmos'; $zr = Join-Rel @($K.Atmos, $pack, $unter, $name) }
        else {
            $typ = Get-Typ $basis $packOrdner $f.FullName $f.Length 'Foley' $false
            $kat = 'Foley'; $zr = Join-Rel @($K.Foley, $typ, $pack, $unter, $name)
        }
    }
    # --- Generisch: Instrument aus Dateiname, sonst Ordnern ---------------
    else {
        $inst = Find-Instrument $basis $pack
        if (-not $inst) {
            for ($i = $alleOrdner.Count - 1; $i -ge 0 -and -not $inst; $i--) { $inst = Find-Instrument $alleOrdner[$i] $pack }
        }
        if (-not $inst) { foreach ($pf in $PackFallback) { if ($pack -match $pf[0]) { $inst = $pf[1]; break } } }
        if (-not $inst) {
            $kat = 'Unsortiert'; $zr = Join-Rel @($K.Unsortiert, $pack, $unter, $name)
        } else {
            $kat = $inst
            $stdLoop = ($pack -match 'Hard Mechanical Rhythms') -or ($inst -in 'DrumLoops', 'Melodic')
            if ($MitTyp -contains $inst) {
                $typ = Get-Typ $basis $packOrdner $f.FullName $f.Length $inst $stdLoop
                $zr = Join-Rel @($K[$inst], $typ, $pack, $unter, $name)
            } else {
                $zr = Join-Rel @($K[$inst], $pack, $unter, $name)
            }
        }
    }

    $eintrag.Kategorie = $kat
    $eintrag.ZielRel   = $zr
    $plan.Add([pscustomobject]$eintrag)
}

# 2.3.3: RX2/MP3/AIFF mit gleichnamiger WAV im selben Pack kommen in denselben Zielordner wie die WAV
# (Construction Kits und Drum-Kits ausgenommen: dort bleibt der Aufbau des Packs erhalten)
$wavZiel = @{}
foreach ($x in $plan) {
    if ($x.Aktion -eq 'Kopieren' -and $x.Quelle -match '\.wav$' -and $x.ZielRel -and $x.Kategorie -notin 'Kits', 'DrumKits') {
        $k = Get-FormatSchluessel $x.Quelle $x.PackWurzel; if (-not $wavZiel.ContainsKey($k)) { $wavZiel[$k] = $x }
    }
}
foreach ($x in $plan) {
    if ($x.Aktion -ne 'Kopieren' -or $x.Quelle -notmatch '\.(rx2|rex|mp3|aiff?)$' -or $x.Kategorie -in 'Kits', 'DrumKits') { continue }
    $w = $wavZiel[(Get-FormatSchluessel $x.Quelle $x.PackWurzel)]
    if (-not $w) { continue }
    $neu = Join-Rel @([IO.Path]::GetDirectoryName($w.ZielRel), [IO.Path]::GetFileName($x.Quelle))
    if ($neu -ne $x.ZielRel) {
        $x.ZielRel = $neu; $x.Kategorie = $w.Kategorie
        $x.Hinweis = (@($x.Hinweis, 'wie die gleichnamige WAV einsortiert') | Where-Object { $_ }) -join '; '
    }
}

# Zusaetzliche Formate (SRT-06): WAV ist Standard. Fuer RX2/MP3/AIFF ohne Haken "behalten" gilt:
# liegt im selben Pack eine WAV mit gleichem Namen (auch in einem anderen Unterordner, z. B. "...-Wav"
# neben "...-Rex2"), wird die Datei nicht kopiert (bleibt in der Quelle).
# Ohne WAV-Gegenstueck wird sie immer einsortiert.
$ausgeschlossen = @($FormatEinstellung.Keys | Where-Object { -not $einst[$FormatEinstellung[$_]] })
if ($ausgeschlossen.Count -gt 0) {
    $wavNamen = @{}
    foreach ($x in $plan) { if ($x.Quelle -match '\.wav$' -and $x.Aktion -notin 'Ignoriert', 'Mac-Rest') { $wavNamen[(Get-FormatSchluessel $x.Quelle $x.PackWurzel)] = $true } }
    foreach ($x in @($plan | Where-Object { $_.Aktion -eq 'Kopieren' })) {
        $ext = [IO.Path]::GetExtension($x.Quelle).ToLowerInvariant()
        if ($ausgeschlossen -notcontains $ext) { continue }
        $fmt = $FormatName[$FormatEinstellung[$ext]]
        $k = Get-FormatSchluessel $x.Quelle $x.PackWurzel
        if ($wavNamen.ContainsKey($k)) { $x.Aktion = 'Format ausgeschlossen'; $x.Kategorie = $fmt; $x.Hinweis = "WAV mit gleichem Namen im selben Pack vorhanden, Haken '$fmt' ist aus" }
        else { $x.Hinweis = "$fmt ohne WAV mit gleichem Namen im Pack - wird einsortiert" }
    }
}

# ----------------------------------------------------------------------------
# 2) Doppelte Dateien erkennen: gleiche Groesse, Bestaetigung per Pruefsumme (Name egal)
# ----------------------------------------------------------------------------
Write-Host "Pruefe auf doppelte Dateien ..." -ForegroundColor Cyan
# "Format ausgeschlossen" zaehlt mit: eine umbenannte Kopie einer ausgeschlossenen RX2 wird dann ebenfalls nicht kopiert
$kandidaten = $plan | Where-Object { $_.Aktion -in 'Kopieren', 'Format ausgeschlossen' -and $_.Dedup }
# Audiodateien: nur Groesse + Pruefsumme (auch umbenannte Kopien wie "Loop - Kopie.wav");
# andere Dateien (Lizenzen, Infos) wie bisher nur bei gleichem Namen; leere Dateien nie
$gruppen = $kandidaten | Where-Object { $_.Bytes -gt 0 } |
    Group-Object { if ($_.Quelle -match $RxAudio) { 'a|' + $_.Bytes } else { 'n|' + ([IO.Path]::GetFileName($_.Quelle)).ToLowerInvariant() + '|' + $_.Bytes } } |
    Where-Object { $_.Count -gt 1 }
$dupAnzahl = 0
foreach ($g in $gruppen) {
    $nachHash = $g.Group | Sort-Object { $_.Quelle.Length }, Quelle | Group-Object { Get-DateiPruefsumme $_.Quelle }
    foreach ($h in $nachHash) {
        $erster = $h.Group[0]
        foreach ($x in ($h.Group | Select-Object -Skip 1)) {
            if ($x.Aktion -ne 'Kopieren') { continue }
            $x.Aktion = 'Duplikat - uebersprungen'
            $x.ZielRel = "(identisch mit $($erster.Quelle))"
            $x.Hinweis = if ($erster.Aktion -eq 'Format ausgeschlossen') { "gleicher Inhalt wie $([IO.Path]::GetFileName($erster.Quelle)); diese ist ausgeschlossen, weil es dazu eine WAV gibt" } else { "gleicher Inhalt wie $([IO.Path]::GetFileName($erster.Quelle))" }
            $dupAnzahl++
        }
    }
}

# ----------------------------------------------------------------------------
# 3) Namenskollisionen im Ziel aufloesen (Quell-Unterordner anhaengen)
# ----------------------------------------------------------------------------
for ($runde = 1; $runde -le 2; $runde++) {
    $koll = $plan | Where-Object { $_.Aktion -eq 'Kopieren' } | Group-Object { $_.ZielRel.ToLowerInvariant() } | Where-Object { $_.Count -gt 1 }
    foreach ($g in $koll) {
        $n = 0
        foreach ($x in $g.Group) {
            $n++
            $dir  = Split-Path -Parent $x.ZielRel
            $file = Split-Path -Leaf   $x.ZielRel
            if ($runde -eq 1) {
                $parent = Split-Path -Leaf (Split-Path -Parent $x.Quelle)
                $x.ZielRel = Join-Rel @($dir, $parent, $file)
            } elseif ($n -gt 1) {
                $x.ZielRel = Join-Rel @($dir, ([IO.Path]::GetFileNameWithoutExtension($file) + "_$n" + [IO.Path]::GetExtension($file)))
            }
        }
    }
}
foreach ($x in $plan) {
    if ($x.Aktion -eq 'Kopieren') {
        $x.Ziel = [IO.Path]::Combine($Ziel, $x.ZielRel)
        if (Test-Datei $x.Ziel) { $x.Aktion = 'Bereits im Ziel'; $x.Hinweis = 'gleicher Pfad im Ziel' }
    }
}

# ----------------------------------------------------------------------------
# 3b) Inhaltsabgleich mit dem ganzen Ziel (Version 1.2)
#     Gleicher Inhalt an anderer Stelle oder unter anderem Namen wird nicht erneut kopiert.
#     Vorfilter Dateigroesse (kostet nichts), Bestaetigung per Pruefsumme nur bei gleicher Groesse.
#     Drum-Kits und Construction Kits sind ausgenommen, damit sie vollstaendig bleiben.
# ----------------------------------------------------------------------------
$imZielAnzahl = 0
$pruefKandidaten = @($plan | Where-Object { $_.Aktion -eq 'Kopieren' -and $_.Dedup })
if ($pruefKandidaten.Count -gt 0 -and (Test-Path -LiteralPath $Ziel)) {
    Write-Host "Gleiche den Inhalt mit dem Ziel ab ..." -ForegroundColor Cyan
    $nachGroesse = @{}
    $zstapel = New-Object System.Collections.Generic.Stack[string]
    $zstapel.Push($Ziel)
    while ($zstapel.Count -gt 0) {
        $o = $zstapel.Pop()
        try { $inh = @(Get-ChildItem -LiteralPath $o -Force -ErrorAction Stop) } catch { continue }
        foreach ($e in $inh) {
            if ($e.PSIsContainer) {
                if (-not ($e.Attributes -band [IO.FileAttributes]::ReparsePoint)) { $zstapel.Push($e.FullName) }
            } elseif ($e.Name -match $RxAudio) {
                $k = [string]$e.Length
                if (-not $nachGroesse.ContainsKey($k)) { $nachGroesse[$k] = New-Object System.Collections.Generic.List[object] }
                $nachGroesse[$k].Add($e)
            }
        }
    }
    $zielHash = @{}
    $i = 0
    foreach ($x in $pruefKandidaten) {
        $i++
        $k = [string]$x.Bytes
        if (-not $nachGroesse.ContainsKey($k)) { continue }
        if ($i % 20 -eq 0) { Write-Progress -Activity 'Inhaltsabgleich mit dem Ziel' -Status "$i / $($pruefKandidaten.Count)" -PercentComplete ($i * 100 / $pruefKandidaten.Count) }
        try { $h = Get-DateiPruefsumme $x.Quelle } catch { continue }
        foreach ($z in $nachGroesse[$k]) {
            if (-not $zielHash.ContainsKey($z.FullName)) {
                try { $zielHash[$z.FullName] = Get-DateiPruefsumme $z.FullName } catch { $zielHash[$z.FullName] = '' }
            }
            if ($zielHash[$z.FullName] -eq $h) {
                $x.Aktion = 'Bereits im Ziel'
                $gleicherName = ($z.Name -ieq [IO.Path]::GetFileName($x.Quelle))
                $x.Hinweis = if ($gleicherName) { 'gleicher Inhalt, gleicher Name, anderer Ordner' } else { "gleicher Inhalt, anderer Name ($($z.Name))" }
                $x.Ziel = $z.FullName
                $x.ZielRel = "(identisch mit $($z.FullName))"
                $imZielAnzahl++
                break
            }
        }
    }
    Write-Progress -Activity 'Inhaltsabgleich mit dem Ziel' -Completed
}

# Anzeigetexte fuer Vorschau (was passieren wuerde) und Protokoll (was passiert ist)
$TextVorschau = @{
    'Kopieren'                 = 'wird kopiert'
    'Bereits im Ziel'          = "bereits im Ziel $([char]0x2013) wird nicht kopiert"
    'Duplikat - uebersprungen' = "Duplikat in der Quelle $([char]0x2013) wird nicht kopiert"
    'Ignoriert'                = 'ignoriert (Hilfsdatei)'
    'Mac-Rest'                 = "macOS-Rest $([char]0x2013) wird nicht kopiert"
    'Format ausgeschlossen'    = "WAV vorhanden $([char]0x2013) wird nicht kopiert"
    'Kein Sample'              = "kein Sample $([char]0x2013) wird nicht kopiert"
}
$TextProtokoll = @{
    'Kopiert'                  = 'kopiert'
    'Kopieren'                 = 'nicht kopiert (Abbruch)'
    'Bereits im Ziel'          = "bereits im Ziel $([char]0x2013) nicht kopiert"
    'Duplikat - uebersprungen' = "Duplikat in der Quelle $([char]0x2013) nicht kopiert"
    'Ignoriert'                = 'ignoriert (Hilfsdatei)'
    'Mac-Rest'                 = "macOS-Rest $([char]0x2013) nicht kopiert"
    'Format ausgeschlossen'    = "WAV vorhanden $([char]0x2013) nicht kopiert"
    'Kein Sample'              = "kein Sample $([char]0x2013) nicht kopiert"
}
function Export-Plan([string]$pfad, [hashtable]$texte) {
    $plan | Select-Object @{ n = 'Aktion'; e = { if ($texte.ContainsKey($_.Aktion)) { $texte[$_.Aktion] } else { $_.Aktion } } },
        Kategorie, Quelle, Ziel, ZielRel, GroesseMB, Hinweis, Quellordner |
        Export-Csv -LiteralPath $pfad -NoTypeInformation -Delimiter ';' -Encoding UTF8
}

# ----------------------------------------------------------------------------
# 4) Zusammenfassung + CSV
# ----------------------------------------------------------------------------
$kopieren = @($plan | Where-Object { $_.Aktion -eq 'Kopieren' })
$summeGB  = [math]::Round((($kopieren | Measure-Object Bytes -Sum).Sum) / 1GB, 2)
$nVorhanden = @($plan | Where-Object { $_.Aktion -eq 'Bereits im Ziel' }).Count
$nIgnoriert = @($plan | Where-Object { $_.Aktion -eq 'Ignoriert' }).Count
$nMac = @($plan | Where-Object { $_.Aktion -eq 'Mac-Rest' }).Count
$nFormat = @($plan | Where-Object { $_.Aktion -eq 'Format ausgeschlossen' }).Count
$nKein = @($plan | Where-Object { $_.Aktion -eq 'Kein Sample' }).Count
$audioAnzahl = @($plan | Where-Object { $_.Aktion -notin 'Ignoriert', 'Mac-Rest', 'Kein Sample' -and $_.Quelle -match $RxAudio }).Count

if ($audioAnzahl -eq 0) {
    Write-Host ""
    Write-Host ("In der Quelle wurden {0} Datei(en) gefunden, aber keine einzige Audiodatei." -f $plan.Count) -ForegroundColor Yellow
    Write-Host "Ist der Quellordner richtig eingestellt? Es wird nichts kopiert und keine Vorschau angelegt." -ForegroundColor Yellow
    return
}

Write-Host ""
Write-Host "==================== Zusammenfassung ====================" -ForegroundColor Yellow
Write-Host ("Dateien in der Quelle:                    {0,7}" -f $plan.Count)
Write-Host ("  neu, werden kopiert:                    {0,7}   ({1:N2} GB)" -f $kopieren.Count, $summeGB) -ForegroundColor Green
Write-Host ("  schon im Ziel, werden uebersprungen:    {0,7}" -f $nVorhanden)
if ($imZielAnzahl -gt 0) {
    $umbenannt = @($plan | Where-Object { $_.Hinweis -like '*anderer Name*' }).Count
    Write-Host ("    davon an anderer Stelle im Ziel:      {0,7}   (unter anderem Namen: {1})" -f $imZielAnzahl, $umbenannt) -ForegroundColor DarkGray
}
Write-Host ("  doppelt in der Quelle, nur 1x kopiert:  {0,7}" -f $dupAnzahl)
Write-Host ("  Hilfsdateien, werden ignoriert:         {0,7}   (z. B. .asd, Thumbs.db - Grund in der Vorschau)" -f $nIgnoriert)
Write-Host ("  macOS-Reste, werden nicht kopiert:     {0,7}   (._-Dateien, .DS_Store, __MACOSX)" -f $nMac)
Write-Host ("  kein Sample, bleibt liegen:             {0,7}   (Programme, Installer, Plugin-Inhalte, Archive - Grund in der Vorschau)" -f $nKein)
if ($ausgeschlossen.Count -gt 0) { Write-Host ("  RX2/MP3/AIFF neben gleichnamiger WAV:  {0,7}   werden nicht kopiert (Haken aus: {1})" -f $nFormat, ((@($ausgeschlossen | ForEach-Object { $FormatName[$FormatEinstellung[$_]] } | Select-Object -Unique)) -join ', ')) }
Write-Host "  Die Quelle bleibt beim Sortieren unveraendert." -ForegroundColor DarkGray
Write-Host ""
if ($kopieren.Count -gt 0) { Write-Host "Neue Dateien nach Kategorie:" }
$kopieren | Group-Object { ($_.ZielRel -split '[\\/]')[0] } | Sort-Object Name | ForEach-Object {
    "{0,-36} {1,7} Dateien {2,10:N1} MB" -f $_.Name, $_.Count, (($_.Group | Measure-Object Bytes -Sum).Sum / 1MB)
} | Write-Host
$lange = @($kopieren | Where-Object { $_.Ziel.Length -ge 260 }).Count
if ($lange -gt 0) { Write-Host "Hinweis: $lange Zielpfad(e) sind laenger als 259 Zeichen. Sie werden kopiert, manche Programme (z. B. DAW, Explorer) koennen damit aber Probleme haben." -ForegroundColor Yellow }
foreach ($t in $PackTiefer) { Write-Host "ACHTUNG: Packs von $($t.Quelle) liegen erst in $($t.Ebene) - Pack-Name waere '$($t.Name)'. Unter Einstellungen umstellen (Spalte Zustand)." -ForegroundColor Yellow }
$unsort = @($kopieren | Where-Object { $_.Kategorie -eq 'Unsortiert' }).Count
if ($unsort -gt 0) { Write-Host "Hinweis: $unsort Datei(en) landen in '_Unsortiert' (bitte in der CSV pruefen)." -ForegroundColor Yellow }

$zuWenigPlatz = $false
try {
    $lw = (Split-Path -Qualifier $Ziel).TrimEnd(':')
    $frei = (Get-PSDrive -Name $lw).Free
    Write-Host ("Freier Speicher auf {0}: {1:N1} GB" -f $lw, ($frei / 1GB))
    if ($frei -lt (($kopieren | Measure-Object Bytes -Sum).Sum * 1.05)) {
        Write-Host "ACHTUNG: Nicht genug freier Speicher fuer die Kopie!" -ForegroundColor Red
        $zuWenigPlatz = $true
    }
} catch { Write-Host "Freier Speicher konnte nicht ermittelt werden." }
if ($Ausfuehren -and $zuWenigPlatz) { throw "Abbruch wegen zu wenig Speicherplatz." }

$vorschauPfad = [IO.Path]::Combine($protokollOrdner, "Vorschau_$Zeitstempel.csv")
Export-Plan $vorschauPfad $TextVorschau
Write-Host ""
Write-Host "Vorschau gespeichert (zeigt nur, was passieren wuerde):" -ForegroundColor Green
Write-Host "  $vorschauPfad"

if ($kopieren.Count -eq 0 -and -not $ImmerProtokoll) { Write-Host ""; Write-Host "Nichts Neues zu kopieren. Alles ist bereits im Ziel." -ForegroundColor Green; return }
if ($kopieren.Count -eq 0) { Write-Host ""; Write-Host "Nichts Neues zu kopieren. Alles ist bereits im Ziel." -ForegroundColor Green }
if (-not $Ausfuehren) {
    if ($NurVorschau -or $zuWenigPlatz) {
        Write-Host "Es wurde nichts kopiert."
        return
    }
    Write-Host ""
    $frageText = "Jetzt die $($kopieren.Count) neuen Dateien ($('{0:N2}' -f $summeGB) GB) nach '$Ziel' kopieren"
    if ($Frage) { $frageText = $(if ($kopieren.Count) { "Jetzt die $($kopieren.Count) neuen Dateien ($('{0:N2}' -f $summeGB) GB) kopieren und $Frage" } else { "Jetzt $Frage" }) }
    if (-not (Read-JaNein "$($frageText)?")) {
        Write-Host ""
        Write-Host "Abgebrochen. Es wurde nichts kopiert." -ForegroundColor Yellow
        Write-Host "Die Vorschau-Datei zeigt nur, was kopiert worden waere. Es gibt kein Protokoll, weil nichts passiert ist."
        return
    }
}
$csvName = "Protokoll_$Zeitstempel.csv"
$csvPfad = [IO.Path]::Combine($protokollOrdner, $csvName)

# ----------------------------------------------------------------------------
# 5) Kopieren (nie ueberschreiben, nie loeschen)
# ----------------------------------------------------------------------------
Write-Host ""
Write-Host "Kopiere $($kopieren.Count) Dateien nach '$Ziel' ..." -ForegroundColor Cyan
$ok = 0; $vorhanden = 0; $fehler = 0; $i = 0
foreach ($x in $kopieren) {
    $i++
    if ($i % 50 -eq 0) { Write-Progress -Activity 'Kopiere Samples' -Status "$i / $($kopieren.Count)" -PercentComplete ($i * 100 / $kopieren.Count) }
    try {
        if (Test-Datei $x.Ziel) { $x.Aktion = 'Bereits im Ziel'; $x.Hinweis = 'gleicher Pfad im Ziel'; $vorhanden++; continue }
        Copy-Datei $x.Quelle $x.Ziel   # 2.3.3: auch Pfade ueber 259 Zeichen
        $x.Aktion = 'Kopiert'; $ok++
    } catch {
        $x.Aktion = 'FEHLER: ' + $_.Exception.Message; $fehler++
    }
}
Write-Progress -Activity 'Kopiere Samples' -Completed


Export-Plan $csvPfad $TextProtokoll
# Protokoll zusaetzlich im Zielordner ablegen
# 3.0.1: im Ziel im Unterordner 99_Protokolle (aeltere Protokolle direkt im Ziel werden dorthin verschoben)
try { Move-ZielProtokolle $Ziel; $zp = Get-ZielProtokollOrdner $Ziel; [void][IO.Directory]::CreateDirectory($zp); Copy-Item -LiteralPath $csvPfad -Destination (Join-Path $zp $csvName) } catch {}

Write-Host ""
Write-Host "Fertig." -ForegroundColor Green
Write-Host ("  neu kopiert:                            {0,7}" -f $ok) -ForegroundColor Green
if ($ok -gt 0) { Send-BibliothekGeaendert }
Write-Host ("  schon im Ziel, uebersprungen:           {0,7}" -f ($nVorhanden + $vorhanden))
Write-Host ("  doppelt in der Quelle, nur 1x kopiert:  {0,7}" -f $dupAnzahl)
if ($fehler -gt 0) { Write-Host ("  Fehler:                                 {0,7}" -f $fehler) -ForegroundColor Red }
Write-Host "Protokoll: $csvPfad"
if ($fehler -gt 0) { Write-Host "Bitte die Zeilen mit 'FEHLER' in der CSV pruefen (z. B. zu lange Pfade)." -ForegroundColor Red }
