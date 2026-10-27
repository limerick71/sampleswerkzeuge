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
  - Der Ordner "ModX" (Yamaha-Bibliotheken) wird komplett ausgespart.
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
    [switch]$Ausfuehren
)

$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'Gemeinsam.ps1')
$Zeitstempel  = Get-Date -Format 'yyyy-MM-dd_HHmmss'

$einst = Get-Einstellungen
if (-not $Quelle) { $Quelle = $einst.Quelle }
if (-not $Ziel)   { $Ziel   = $einst.Ziel }
Write-Host "Samples sortieren (Samples-Werkzeuge $ProgrammVersion)" -ForegroundColor Cyan
Write-Host "  Quelle: $Quelle"
Write-Host "  Ziel:   $Ziel"
Write-Host ""

if (-not (Test-Path -LiteralPath $Quelle)) { throw "Quellordner nicht gefunden: $Quelle  (in der Oberflaeche unter 'Einstellungen' aendern)" }
$Quelle = (Resolve-Path -LiteralPath $Quelle).ProviderPath.TrimEnd('\','/')
$Ziel   = $Ziel.TrimEnd('\','/')
$pruef = Test-QuelleZiel $Quelle $Ziel
if ($pruef) { throw $pruef }
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
    Keys      = '04 Keys & Synth'
    Guitar    = '05 Guitar'
    Brass     = '06 Brass & Sax'
    Vocals    = '07 Vocals'
    FX        = '08 FX & Noise'
    Atmos     = '09 Atmos & Field Recordings'
    Kits      = '10 Construction Kits'
    MIDI      = '11 MIDI'
    Songs     = '12 Songs & Playalongs'
    Infos     = '_Lizenzen & Infos'
    Sonstiges = '_Sonstiges'
    Unsortiert= '_Unsortiert'
}
# Kategorien mit Unterteilung One-Shots / Loops
$MitTyp = @('Kick','Snare','Clap','HiHat','Cymbals','Toms','Shaker','Conga','Perc','Foley','Bass')

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
    @('Foley',     'foley|stapler|coins'),
    @('Perc',      'perc|(?<![a-z])pc(?![a-z])|cowbell|(?<![a-z])cb\d*(?![a-z])|clave|(?<![a-z])wood|block'),
    @('FX',        'noise|(?<![a-z])fx(?![a-z])|riser|sweep|impact|transition'),
    @('Bass',      'bass|(?<![a-z])303(?![0-9])|(?<![a-z])acd'),
    @('Atmos',     'ambient|ambience|atmo|field'),
    @('DrumLoops', 'drum|beat|groove|full|top ?loop|brush|break|rhythm')
)
# Fallback je Pack, wenn weder Datei- noch Ordnername etwas hergeben
$PackFallback = @(,
    @('VOLTAGE REVELATIONS', 'DrumLoops')
)

$RxOneShot = 'one ?-?shot|oneshot|(?<![a-z])shots(?![a-z])'
$RxLoop    = 'loop|bpm|(?<![a-z])(groove|beat|fill)s?(?![a-z])'
$RxDoku    = '\.(pdf|txt|rtf|nfo|png|jpe?g|gif|bmp|html?|url|docx?)$'
$RxAudio   = '\.(wav|aiff?|mp3|flac|ogg|rx2|rex|m4a)$'

function Get-WavSekunden([string]$Pfad, [long]$Groesse) {
    if ($Pfad -notmatch '\.wav$') { return -1 }
    try {
        $fs = [IO.File]::OpenRead($Pfad)
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

function Find-Instrument([string]$Text) {
    $t = $Text.ToLowerInvariant() -replace 'no ?kick', ' ' -replace 'stripped', ' '
    foreach ($i in $Instrumente) { if ($t -match $i[1]) { return $i[0] } }
    return $null
}

function Get-Typ([string]$Datei, [string[]]$Ordner, [string]$Pfad, [long]$Groesse, [string]$Instrument, [bool]$StandardLoop) {
    $d = $Datei.ToLowerInvariant()
    if ($d -match $RxOneShot) { return 'One-Shots' }
    if ($d -match $RxLoop -or $d -match '_\d{2,3}(\.\d+)?$') { return 'Loops' }
    for ($i = $Ordner.Count - 1; $i -ge 0; $i--) {
        $o = $Ordner[$i].ToLowerInvariant()
        if ($o -match $RxOneShot) { return 'One-Shots' }
        if ($o -match $RxLoop)    { return 'Loops' }
    }
    if ($StandardLoop) { return 'Loops' }
    if ($Instrument -eq 'Cymbals') { return 'One-Shots' }
    $sek = Get-WavSekunden $Pfad $Groesse
    if ($sek -ge 6) { return 'Loops' }
    return 'One-Shots'
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
Write-Host "Lese Dateien aus '$Quelle' ..." -ForegroundColor Cyan
# Eigene Rekursion: Ordner-Verknuepfungen (Junctions, z. B. "Anwendungsdaten") werden nicht verfolgt,
# nicht lesbare Ordner werden gezaehlt statt das Skript abzubrechen.
$nichtLesbar = 0
$alle = New-Object System.Collections.Generic.List[object]
$stapel = New-Object System.Collections.Generic.Stack[string]
$stapel.Push($Quelle)
while ($stapel.Count -gt 0) {
    $ordner = $stapel.Pop()
    try { $inhalt = @(Get-ChildItem -LiteralPath $ordner -Force -ErrorAction Stop) }
    catch { $nichtLesbar++; continue }
    foreach ($e in $inhalt) {
        if ($e.PSIsContainer) {
            if ($e.Attributes -band [IO.FileAttributes]::ReparsePoint) { continue }
            if ($ordner -eq $Quelle -and $e.Name -eq 'ModX') { continue }
            $stapel.Push($e.FullName)
        } else { $alle.Add($e) }
    }
}
if (Test-Path -LiteralPath (Join-Path $Quelle 'ModX')) { Write-Host "Hinweis: Der Ordner 'ModX' (Yamaha-Bibliotheken) wird ausgespart." -ForegroundColor DarkGray }
if ($nichtLesbar -gt 0) { Write-Host "Hinweis: $nichtLesbar Ordner waren nicht lesbar und wurden ausgelassen." -ForegroundColor Yellow }
$plan = New-Object System.Collections.Generic.List[object]

$alle = @($alle | Where-Object {
    $voll = $_.FullName
    -not @($Ausnahmen | Where-Object { $voll.StartsWith($_ + [IO.Path]::DirectorySeparatorChar, [StringComparison]::OrdinalIgnoreCase) }).Count
})
foreach ($f in $alle) {
    $rel   = $f.FullName.Substring($Quelle.Length).TrimStart('\','/')
    $teile = $rel -split '[\\/]'
    $name  = $f.Name
    $nameL = $name.ToLowerInvariant()
    $basis = [IO.Path]::GetFileNameWithoutExtension($name)

    $eintrag = [ordered]@{
        Aktion = 'Kopieren'; Kategorie = ''; Quelle = $f.FullName; Ziel = ''
        GroesseMB = [math]::Round($f.Length / 1MB, 2); Bytes = $f.Length
        Dedup = $true; ZielRel = ''; Hinweis = ''
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

    # --- Pack bestimmen (Sammelordner haben Packs eine Ebene tiefer) ------
    if (($teile[0] -in @('Drumloops','Lofi Sounds - Free Sample Pack','Vocals')) -and $teile.Count -gt 2) {
        $pack = $teile[1]; $packRel = $teile[2..($teile.Count - 1)]
    } elseif ($teile.Count -gt 1) {
        $pack = $teile[0]; $packRel = $teile[1..($teile.Count - 1)]
    } else {
        $pack = '_Einzeldateien'; $packRel = @($teile[0])
    }
    if ($teile[0] -eq 'Vocals' -and $teile.Count -eq 2) { $pack = 'Vocals (Einzeldateien)' }
    $packOrdner = @(); if ($packRel.Count -gt 1) { $packOrdner = $packRel[0..($packRel.Count - 2)] }
    $relImPack  = Join-Rel $packRel
    $alleOrdner = @(); if ($teile.Count -gt 1) { $alleOrdner = $teile[0..($teile.Count - 2)] }
    $ordnerText = ($alleOrdner -join ' ')

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
        $kat = 'Infos'; $zr = Join-Rel @($K.Infos, $pack, $name)
    } elseif ($nameL -match '\.midi?$') {
        $kat = 'MIDI'; $zr = Join-Rel @($K.MIDI, $pack, $name)
    } elseif ($nameL -notmatch $RxAudio) {
        $kat = 'Sonstiges'; $zr = Join-Rel @($K.Sonstiges, $pack, $name)
    }
    # --- Melodische / thematische Packs -----------------------------------
    elseif ($teile[0] -eq 'Vocals' -or $pack -match 'Vocal') {
        $kat = 'Vocals'; $zr = Join-Rel @($K.Vocals, $pack, $relImPack)
    } elseif ($teile[0] -eq 'Brass') {
        $kat = 'Brass'; $zr = Join-Rel @($K.Brass, 'Brass (Mugent)', $name)
    } elseif ($pack -match 'Melancholic Rhodes|Lofi Blessings') {
        $kat = 'Keys'; $zr = Join-Rel @($K.Keys, $pack, $name)
    } elseif ($pack -match 'Zen Guitar') {
        $kat = 'Guitar'; $zr = Join-Rel @($K.Guitar, $pack, $relImPack)
    } elseif ($pack -match 'Ambiences') {
        $kat = 'Atmos'; $zr = Join-Rel @($K.Atmos, $pack, $name)
    } elseif ($pack -match 'Riemann Techno Basslines' -or $rel -match 'Sub Bass Loops') {
        $kat = 'Bass'; $zr = Join-Rel @($K.Bass, 'Loops', $pack, $name)
    } elseif ($rel -match 'FX Kicks|Transition Kicks') {
        $kat = 'FX'; $zr = Join-Rel @($K.FX, $pack, $name)
    } elseif ($pack -match 'Warped Foley') {
        $kat = 'Foley'; $zr = Join-Rel @($K.Foley, 'Loops', $pack, $name)
    } elseif ($pack -match 'Lofi Forest') {
        if ($nameL -match 'atmo|forest|rain|creek|pad|bird') { $kat = 'Atmos'; $zr = Join-Rel @($K.Atmos, $pack, $name) }
        else {
            $typ = Get-Typ $basis $packOrdner $f.FullName $f.Length 'Foley' $false
            $kat = 'Foley'; $zr = Join-Rel @($K.Foley, $typ, $pack, $name)
        }
    }
    # --- Generisch: Instrument aus Dateiname, sonst Ordnern ---------------
    else {
        $inst = Find-Instrument $basis
        if (-not $inst) {
            for ($i = $alleOrdner.Count - 1; $i -ge 0 -and -not $inst; $i--) { $inst = Find-Instrument $alleOrdner[$i] }
        }
        if (-not $inst) { foreach ($pf in $PackFallback) { if ($pack -match $pf[0]) { $inst = $pf[1]; break } } }
        if (-not $inst) {
            $kat = 'Unsortiert'; $zr = Join-Rel @($K.Unsortiert, $pack, $name)
        } else {
            $kat = $inst
            $stdLoop = ($pack -match 'Hard Mechanical Rhythms') -or ($inst -eq 'DrumLoops')
            if ($MitTyp -contains $inst) {
                $typ = Get-Typ $basis $packOrdner $f.FullName $f.Length $inst $stdLoop
                $zr = Join-Rel @($K[$inst], $typ, $pack, $name)
            } else {
                $zr = Join-Rel @($K[$inst], $pack, $name)
            }
        }
    }

    $eintrag.Kategorie = $kat
    $eintrag.ZielRel   = $zr
    $plan.Add([pscustomobject]$eintrag)
}

# Zusaetzliche Formate (SRT-06): WAV ist Standard. Fuer RX2/MP3/AIFF ohne Haken "behalten" gilt:
# liegt im selben Pack eine WAV mit gleichem Namen (auch in einem anderen Unterordner, z. B. "...-Wav"
# neben "...-Rex2"), wird die Datei nicht kopiert (bleibt in der Quelle).
# Ohne WAV-Gegenstueck wird sie immer einsortiert.
$ausgeschlossen = @($FormatEinstellung.Keys | Where-Object { -not $einst[$FormatEinstellung[$_]] })
if ($ausgeschlossen.Count -gt 0) {
    $wavNamen = @{}
    foreach ($x in $plan) { if ($x.Quelle -match '\.wav$' -and $x.Aktion -notin 'Ignoriert', 'Mac-Rest') { $wavNamen[(Get-FormatSchluessel $x.Quelle $Quelle)] = $true } }
    foreach ($x in @($plan | Where-Object { $_.Aktion -eq 'Kopieren' })) {
        $ext = [IO.Path]::GetExtension($x.Quelle).ToLowerInvariant()
        if ($ausgeschlossen -notcontains $ext) { continue }
        $fmt = $FormatName[$FormatEinstellung[$ext]]
        $k = Get-FormatSchluessel $x.Quelle $Quelle
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
    $nachHash = $g.Group | Sort-Object { $_.Quelle.Length }, Quelle | Group-Object { (Get-FileHash -LiteralPath $_.Quelle -Algorithm MD5).Hash }
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
        if (Test-Path -LiteralPath $x.Ziel) { $x.Aktion = 'Bereits im Ziel'; $x.Hinweis = 'gleicher Pfad im Ziel' }
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
        try { $h = (Get-FileHash -LiteralPath $x.Quelle -Algorithm MD5 -ErrorAction Stop).Hash } catch { continue }
        foreach ($z in $nachGroesse[$k]) {
            if (-not $zielHash.ContainsKey($z.FullName)) {
                try { $zielHash[$z.FullName] = (Get-FileHash -LiteralPath $z.FullName -Algorithm MD5 -ErrorAction Stop).Hash } catch { $zielHash[$z.FullName] = '' }
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
}
$TextProtokoll = @{
    'Kopiert'                  = 'kopiert'
    'Kopieren'                 = 'nicht kopiert (Abbruch)'
    'Bereits im Ziel'          = "bereits im Ziel $([char]0x2013) nicht kopiert"
    'Duplikat - uebersprungen' = "Duplikat in der Quelle $([char]0x2013) nicht kopiert"
    'Ignoriert'                = 'ignoriert (Hilfsdatei)'
    'Mac-Rest'                 = "macOS-Rest $([char]0x2013) nicht kopiert"
    'Format ausgeschlossen'    = "WAV vorhanden $([char]0x2013) nicht kopiert"
}
function Export-Plan([string]$pfad, [hashtable]$texte) {
    $plan | Select-Object @{ n = 'Aktion'; e = { if ($texte.ContainsKey($_.Aktion)) { $texte[$_.Aktion] } else { $_.Aktion } } },
        Kategorie, Quelle, Ziel, ZielRel, GroesseMB, Hinweis |
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
$audioAnzahl = @($plan | Where-Object { $_.Aktion -notin 'Ignoriert', 'Mac-Rest' -and $_.Quelle -match $RxAudio }).Count

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
if ($ausgeschlossen.Count -gt 0) { Write-Host ("  RX2/MP3/AIFF neben gleichnamiger WAV:  {0,7}   werden nicht kopiert (Haken aus: {1})" -f $nFormat, ((@($ausgeschlossen | ForEach-Object { $FormatName[$FormatEinstellung[$_]] } | Select-Object -Unique)) -join ', ')) }
Write-Host "  Die Quelle bleibt beim Sortieren unveraendert." -ForegroundColor DarkGray
Write-Host ""
if ($kopieren.Count -gt 0) { Write-Host "Neue Dateien nach Kategorie:" }
$kopieren | Group-Object { ($_.ZielRel -split '[\\/]')[0] } | Sort-Object Name | ForEach-Object {
    "{0,-36} {1,7} Dateien {2,10:N1} MB" -f $_.Name, $_.Count, (($_.Group | Measure-Object Bytes -Sum).Sum / 1MB)
} | Write-Host
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

if ($kopieren.Count -eq 0) { Write-Host ""; Write-Host "Nichts Neues zu kopieren. Alles ist bereits im Ziel." -ForegroundColor Green; return }
if (-not $Ausfuehren) {
    if ($NurVorschau -or $zuWenigPlatz) {
        Write-Host "Es wurde nichts kopiert."
        return
    }
    Write-Host ""
    $frage = "Jetzt die $($kopieren.Count) neuen Dateien ($('{0:N2}' -f $summeGB) GB) nach '$Ziel' kopieren"
    if (-not (Read-JaNein "$($frage)?")) {
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
        if (Test-Path -LiteralPath $x.Ziel) { $x.Aktion = 'Bereits im Ziel'; $x.Hinweis = 'gleicher Pfad im Ziel'; $vorhanden++; continue }
        $zielDir = Split-Path -Parent $x.Ziel
        if (-not (Test-Path -LiteralPath $zielDir)) { New-Item -ItemType Directory -Path $zielDir -Force | Out-Null }
        Copy-Item -LiteralPath $x.Quelle -Destination $x.Ziel
        $x.Aktion = 'Kopiert'; $ok++
    } catch {
        $x.Aktion = 'FEHLER: ' + $_.Exception.Message; $fehler++
    }
}
Write-Progress -Activity 'Kopiere Samples' -Completed


Export-Plan $csvPfad $TextProtokoll
# Protokoll zusaetzlich im Zielordner ablegen
try { Copy-Item -LiteralPath $csvPfad -Destination (Join-Path $Ziel $csvName) } catch {}

Write-Host ""
Write-Host "Fertig." -ForegroundColor Green
Write-Host ("  neu kopiert:                            {0,7}" -f $ok) -ForegroundColor Green
Write-Host ("  schon im Ziel, uebersprungen:           {0,7}" -f ($nVorhanden + $vorhanden))
Write-Host ("  doppelt in der Quelle, nur 1x kopiert:  {0,7}" -f $dupAnzahl)
if ($fehler -gt 0) { Write-Host ("  Fehler:                                 {0,7}" -f $fehler) -ForegroundColor Red }
Write-Host "Protokoll: $csvPfad"
if ($fehler -gt 0) { Write-Host "Bitte die Zeilen mit 'FEHLER' in der CSV pruefen (z. B. zu lange Pfade)." -ForegroundColor Red }
