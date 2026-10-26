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
Write-Host "Hinweis: Der Ordner 'ModX' (Yamaha-Bibliotheken) wird ausgespart." -ForegroundColor DarkGray
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
        Dedup = $true; ZielRel = ''
    }

    # --- Ignorieren -------------------------------------------------------
    if ($teile[0] -eq '_Sortier-Skript' -or $teile[0] -like 'Samples-Werkzeuge*' -or $nameL -eq '.ds_store' -or $nameL -eq 'thumbs.db' -or
        $nameL -eq 'desktop.ini' -or $nameL.EndsWith('.asd') -or $nameL.StartsWith('._')) {
        $eintrag.Aktion = 'Ignoriert'; $eintrag.Kategorie = 'Hilfsdatei'
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
        if ($nameL.EndsWith('.xmp')) { $eintrag.Aktion = 'Ignoriert'; $eintrag.Kategorie = 'Hilfsdatei'; $plan.Add([pscustomobject]$eintrag); continue }
        $kat = 'Kits'; $zr = Join-Rel @($K.Kits, $pack, $relImPack); $eintrag.Dedup = $false
    } elseif (($idx = [array]::IndexOf(@($packOrdner | ForEach-Object { $_.ToUpperInvariant() }), 'DRUM KITS')) -ge 0) {
        $rest = $packRel[($idx + 1)..($packRel.Count - 1)]
        $kat = 'DrumKits'; $zr = Join-Rel @($K.DrumKits, $pack, (Join-Rel $rest)); $eintrag.Dedup = $false
    }
    # --- Ableton-Ordnerinfos, Doku, MIDI, Sonstiges -----------------------
    elseif ($nameL.EndsWith('.xmp') -or $ordnerText -match 'Ableton (Folder|Project) Info') {
        $eintrag.Aktion = 'Ignoriert'; $eintrag.Kategorie = 'Hilfsdatei'; $plan.Add([pscustomobject]$eintrag); continue
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

# ----------------------------------------------------------------------------
# 2) Doppelte Dateien erkennen (Name + Groesse, Bestaetigung per Hash)
# ----------------------------------------------------------------------------
Write-Host "Pruefe auf doppelte Dateien ..." -ForegroundColor Cyan
$kandidaten = $plan | Where-Object { $_.Aktion -eq 'Kopieren' -and $_.Dedup }
$gruppen = $kandidaten | Group-Object { ([IO.Path]::GetFileName($_.Quelle)).ToLowerInvariant() + '|' + $_.Bytes } | Where-Object { $_.Count -gt 1 }
$dupAnzahl = 0
foreach ($g in $gruppen) {
    $nachHash = $g.Group | Sort-Object { $_.Quelle.Length }, Quelle | Group-Object { (Get-FileHash -LiteralPath $_.Quelle -Algorithm MD5).Hash }
    foreach ($h in $nachHash) {
        $erster = $h.Group[0]
        foreach ($x in ($h.Group | Select-Object -Skip 1)) {
            $x.Aktion = 'Duplikat - uebersprungen'
            $x.ZielRel = "(identisch mit $($erster.Quelle))"
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
        if (Test-Path -LiteralPath $x.Ziel) { $x.Aktion = 'Bereits im Ziel' }
    }
}

# Anzeigetexte fuer Vorschau (was passieren wuerde) und Protokoll (was passiert ist)
$TextVorschau = @{
    'Kopieren'                 = 'wird kopiert'
    'Bereits im Ziel'          = "bereits im Ziel $([char]0x2013) wird nicht kopiert"
    'Duplikat - uebersprungen' = "Duplikat in der Quelle $([char]0x2013) wird nicht kopiert"
    'Ignoriert'                = 'ignoriert (Hilfsdatei)'
}
$TextProtokoll = @{
    'Kopiert'                  = 'kopiert'
    'Kopieren'                 = 'nicht kopiert (Abbruch)'
    'Bereits im Ziel'          = "bereits im Ziel $([char]0x2013) nicht kopiert"
    'Duplikat - uebersprungen' = "Duplikat in der Quelle $([char]0x2013) nicht kopiert"
    'Ignoriert'                = 'ignoriert (Hilfsdatei)'
}
function Export-Plan([string]$pfad, [hashtable]$texte) {
    $plan | Select-Object @{ n = 'Aktion'; e = { if ($texte.ContainsKey($_.Aktion)) { $texte[$_.Aktion] } else { $_.Aktion } } },
        Kategorie, Quelle, Ziel, ZielRel, GroesseMB |
        Export-Csv -LiteralPath $pfad -NoTypeInformation -Delimiter ';' -Encoding UTF8
}

# ----------------------------------------------------------------------------
# 4) Zusammenfassung + CSV
# ----------------------------------------------------------------------------
$kopieren = @($plan | Where-Object { $_.Aktion -eq 'Kopieren' })
$summeGB  = [math]::Round((($kopieren | Measure-Object Bytes -Sum).Sum) / 1GB, 2)
$nVorhanden = @($plan | Where-Object { $_.Aktion -eq 'Bereits im Ziel' }).Count
$nIgnoriert = @($plan | Where-Object { $_.Aktion -eq 'Ignoriert' }).Count
$audioAnzahl = @($plan | Where-Object { $_.Quelle -match $RxAudio }).Count

Write-Host ""
Write-Host "==================== Zusammenfassung ====================" -ForegroundColor Yellow
Write-Host ("Dateien in der Quelle:                    {0,7}" -f $plan.Count)
Write-Host ("  neu, werden kopiert:                    {0,7}   ({1:N2} GB)" -f $kopieren.Count, $summeGB) -ForegroundColor Green
Write-Host ("  schon im Ziel, werden uebersprungen:    {0,7}" -f $nVorhanden)
Write-Host ("  doppelt in der Quelle, nur 1x kopiert:  {0,7}" -f $dupAnzahl)
Write-Host ("  Hilfsdateien, werden ignoriert:         {0,7}" -f $nIgnoriert)
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

if ($audioAnzahl -eq 0) {
    Write-Host ""
    Write-Host "In der Quelle wurden keine Audiodateien gefunden. Ist der Quellordner richtig eingestellt?" -ForegroundColor Yellow
    Write-Host "Es wurde nichts kopiert."
    return
}
if ($kopieren.Count -eq 0) { Write-Host ""; Write-Host "Nichts Neues zu kopieren. Alles ist bereits im Ziel." -ForegroundColor Green; return }
if (-not $Ausfuehren) {
    if ($NurVorschau -or $zuWenigPlatz) {
        Write-Host "Es wurde nichts kopiert."
        return
    }
    Write-Host ""
    if (-not (Read-JaNein "Jetzt die $($kopieren.Count) neuen Dateien ($('{0:N2}' -f $summeGB) GB) nach '$Ziel' kopieren?")) {
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
        if (Test-Path -LiteralPath $x.Ziel) { $x.Aktion = 'Bereits im Ziel'; $vorhanden++; continue }
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
