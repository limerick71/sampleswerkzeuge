# (c) 2026 Herbert Stoecker. Kostenlos nutzbar. Bitte nur als Link auf die offizielle Download-Seite weitergeben; Verkauf und Veroeffentlichung geaenderter Fassungen nur mit Zustimmung.
<#
.SYNOPSIS
  Inventur der sortierten Sample-Bibliothek (Zielordner). Erfasst jedes Sample und jedes Pack,
  liest Audio-Eigenschaften aus WAV/AIFF, BPM und Tonart aus dem Dateinamen, bestimmt die Pack-Art,
  findet Duplikate im Ziel und vergleicht mit der letzten Inventur.
  Die Quelle wird nicht benoetigt (Ursprungspfade kommen aus den Kopier-Protokollen).

  Ergebnis im Berichtsordner:
    Inventuren\Sample-Inventur_<Datum>.csv   eine Zeile je Sample
    Inventuren\Pack-Inventur_<Datum>.csv     eine Zeile je Pack
    Inventuren\Sample-Inventur_<Datum>.json  Einstellungen und Kennzahlen des Laufs
    Inventuren\Sample-Inventur_<Datum>.html  Bericht (siehe Bericht.ps1)
    Inventuren\Inventur-aktuell.html         immer der neueste Bericht
    Inventur-Vergleiche\Inventur-Vergleich_<Datum>.csv

.BENUTZUNG
    -NurBericht   nur den HTML-Bericht zur neuesten Inventur neu erzeugen
#>
[CmdletBinding()]
param(
    [switch]$NurBericht
)

$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'Gemeinsam.ps1')
. (Join-Path $PSScriptRoot 'Bericht.ps1')

$einst = Get-Einstellungen
$Ziel  = $einst.Ziel.TrimEnd('\', '/')
$invOrdner = Get-InventurOrdner
$vglOrdner = Get-VergleichOrdner
foreach ($o in $invOrdner, $vglOrdner) { if (-not (Test-Path -LiteralPath $o)) { New-Item -ItemType Directory -Path $o -Force | Out-Null } }

if ($NurBericht) {
    $c = Get-NeuesteInventur 'Sample'
    if (-not $c) { throw 'Noch keine Inventur vorhanden.' }
    $h = New-InventurBericht $c.FullName
    Write-Host "Bericht erzeugt: $h"
    return
}

Write-Host "Inventur (Samples-Werkzeuge $ProgrammVersion)" -ForegroundColor Cyan
Write-Host "  Bibliothek (Ziel): $Ziel"
Write-Host ""
$zs = Get-OrdnerStatus $Ziel
if ($zs.Fehlt -or -not (Test-Path -LiteralPath $Ziel)) { throw "Zielordner nicht gefunden: $Ziel  (in der Oberflaeche unter 'Einstellungen' aendern)" }
$start = Get-Date
$Zeitstempel = $start.ToString('yyyy-MM-dd_HHmm')
$sep = [IO.Path]::DirectorySeparatorChar

# ----------------------------------------------------------------------------
# Hilfsfunktionen
# ----------------------------------------------------------------------------
# Audio-Eigenschaften aus dem Dateikopf (WAV: RIFF-Chunks, AIFF: COMM-Chunk). Liefert Hashtable oder $null.
# MP3: Dauer, Abtastrate, Bitrate und Kanaele aus dem ersten Frame (mit Xing/Info/VBRI fuer variable Bitrate)
function Get-Mp3Info([string]$pfad) {
    $fs = $null
    try {
        $fs = [IO.File]::OpenRead($pfad)
        $laenge = $fs.Length
        $puffer = New-Object byte[] ([int][math]::Min(131072, $laenge))
        $n = $fs.Read($puffer, 0, $puffer.Length)
        $start = 0
        if ($n -ge 10 -and $puffer[0] -eq 0x49 -and $puffer[1] -eq 0x44 -and $puffer[2] -eq 0x33) {   # "ID3"
            $groesse = (([int]$puffer[6] -band 0x7F) -shl 21) -bor (([int]$puffer[7] -band 0x7F) -shl 14) -bor (([int]$puffer[8] -band 0x7F) -shl 7) -bor ([int]$puffer[9] -band 0x7F)
            $start = 10 + $groesse + $(if ($puffer[5] -band 0x10) { 10 } else { 0 })
            if ($start + 4 -gt $n) {
                $fs.Position = $start; $n = $fs.Read($puffer, 0, $puffer.Length); $basis = $start; $start = 0
            } else { $basis = 0 }
        } else { $basis = 0 }
        $br1 = @(0,32,40,48,56,64,80,96,112,128,160,192,224,256,320); $br1l2 = @(0,32,48,56,64,80,96,112,128,160,192,224,256,320,384)
        $br1l1 = @(0,32,64,96,128,160,192,224,256,288,320,352,384,416,448); $br2 = @(0,8,16,24,32,40,48,56,64,80,96,112,128,144,160)
        $br2l1 = @(0,32,48,56,64,80,96,112,128,144,160,176,192,224,256)
        for ($i = $start; $i -lt $n - 4; $i++) {
            if ($puffer[$i] -ne 0xFF -or ($puffer[$i + 1] -band 0xE0) -ne 0xE0) { continue }
            $ver = ($puffer[$i + 1] -shr 3) -band 3; $lay = ($puffer[$i + 1] -shr 1) -band 3
            $bi = $puffer[$i + 2] -shr 4; $si = ($puffer[$i + 2] -shr 2) -band 3
            if ($ver -eq 1 -or $lay -eq 0 -or $bi -eq 0 -or $bi -eq 15 -or $si -eq 3) { continue }
            $mpeg1 = $ver -eq 3
            $rate = @(@(11025,12000,8000), $null, @(22050,24000,16000), @(44100,48000,32000))[$ver][$si]
            $kbps = if ($mpeg1) { if ($lay -eq 1) { $br1[$bi] } elseif ($lay -eq 2) { $br1l2[$bi] } else { $br1l1[$bi] } } else { if ($lay -eq 3) { $br2l1[$bi] } else { $br2[$bi] } }
            $spf = if ($lay -eq 3) { 384 } elseif ($lay -eq 2 -or $mpeg1) { 1152 } else { 576 }
            $mono = ($puffer[$i + 3] -shr 6) -eq 3
            $daten = $laenge - ($basis + $i)
            $dauer = $daten * 8 / ($kbps * 1000)
            # Xing/Info bzw. VBRI: Anzahl der Frames fuer variable Bitrate
            $xo = $i + 4 + $(if ($mpeg1) { if ($mono) { 17 } else { 32 } } else { if ($mono) { 9 } else { 17 } })
            $frames = 0
            if ($xo + 12 -le $n) {
                $tag = [Text.Encoding]::ASCII.GetString($puffer, $xo, 4)
                if (($tag -eq 'Xing' -or $tag -eq 'Info') -and ($puffer[$xo + 7] -band 1)) { $frames = ([uint32]$puffer[$xo + 8] -shl 24) -bor ([uint32]$puffer[$xo + 9] -shl 16) -bor ([uint32]$puffer[$xo + 10] -shl 8) -bor [uint32]$puffer[$xo + 11] }
            }
            $vo = $i + 36
            if (-not $frames -and $vo + 18 -le $n -and [Text.Encoding]::ASCII.GetString($puffer, $vo, 4) -eq 'VBRI') { $frames = ([uint32]$puffer[$vo + 14] -shl 24) -bor ([uint32]$puffer[$vo + 15] -shl 16) -bor ([uint32]$puffer[$vo + 16] -shl 8) -bor [uint32]$puffer[$vo + 17] }
            if ($frames -gt 0) { $dauer = $frames * $spf / $rate; if ($dauer -gt 0) { $kbps = [math]::Round($daten * 8 / $dauer / 1000) } }
            return @{ Defekt = $false; Kanaele = $(if ($mono) { 1 } else { 2 }); Rate = $rate; Bits = $null; Dauer = $dauer; Bitrate = $kbps }
        }
        return @{ Defekt = $true }
    } catch { return @{ Defekt = $true } }
    finally { if ($fs) { $fs.Dispose() } }
}

function Get-AudioInfo([string]$pfad) {
    $ext = [IO.Path]::GetExtension($pfad).ToLowerInvariant()
    if ($ext -eq '.mp3') { return (Get-Mp3Info $pfad) }
    if ($ext -notin '.wav', '.aif', '.aiff') { return $null }
    $fs = $null
    try {
        $fs = [IO.File]::OpenRead($pfad)
        $br = New-Object IO.BinaryReader($fs)
        if ($fs.Length -lt 12) { return @{ Defekt = $true } }
        $id = [Text.Encoding]::ASCII.GetString($br.ReadBytes(4))
        if ($ext -eq '.wav') {
            if ($id -ne 'RIFF' -and $id -ne 'RF64') { return @{ Defekt = $true } }
            [void]$br.ReadUInt32(); [void]$br.ReadBytes(4)   # Groesse, "WAVE"
            $kan = 0; $rate = 0; $bits = 0; $byteRate = 0; $daten = -1
            while ($fs.Position + 8 -le $fs.Length) {
                $cid = [Text.Encoding]::ASCII.GetString($br.ReadBytes(4))
                $clen = [long]$br.ReadUInt32()
                $naechst = $fs.Position + $clen + ($clen % 2)
                if ($cid -eq 'fmt ') {
                    [void]$br.ReadUInt16(); $kan = $br.ReadUInt16(); $rate = $br.ReadUInt32(); $byteRate = $br.ReadUInt32()
                    [void]$br.ReadUInt16(); $bits = $br.ReadUInt16()
                } elseif ($cid -eq 'data') {
                    $daten = [math]::Min($clen, $fs.Length - $fs.Position)
                    if ($rate -gt 0) { break }
                }
                if ($naechst -gt $fs.Length) { break }
                $fs.Position = $naechst
            }
            if ($rate -le 0) { return @{ Defekt = $true } }
            $dauer = if ($byteRate -gt 0 -and $daten -ge 0) { $daten / $byteRate } else { -1 }
            return @{ Defekt = $false; Kanaele = $kan; Rate = $rate; Bits = $bits; Dauer = $dauer }
        } else {
            if ($id -ne 'FORM') { return @{ Defekt = $true } }
            [void]$br.ReadBytes(8)   # Groesse, AIFF/AIFC
            while ($fs.Position + 8 -le $fs.Length) {
                $cid = [Text.Encoding]::ASCII.GetString($br.ReadBytes(4))
                $b = $br.ReadBytes(4); [array]::Reverse($b); $clen = [long][BitConverter]::ToUInt32($b, 0)
                $naechst = $fs.Position + $clen + ($clen % 2)
                if ($cid -eq 'COMM') {
                    $b = $br.ReadBytes(2); [array]::Reverse($b); $kan = [BitConverter]::ToUInt16($b, 0)
                    $b = $br.ReadBytes(4); [array]::Reverse($b); $frames = [BitConverter]::ToUInt32($b, 0)
                    $b = $br.ReadBytes(2); [array]::Reverse($b); $bits = [BitConverter]::ToUInt16($b, 0)
                    $e = $br.ReadBytes(10)   # 80-Bit-Gleitkommazahl (big endian)
                    $exp = (([int]$e[0] -band 0x7F) -shl 8) -bor $e[1]
                    $mant = [uint64]0
                    for ($i = 2; $i -lt 10; $i++) { $mant = ($mant -shl 8) -bor [uint64]$e[$i] }
                    $rate = [math]::Round($mant * [math]::Pow(2, $exp - 16383 - 63))
                    $dauer = if ($rate -gt 0) { $frames / $rate } else { -1 }
                    return @{ Defekt = $false; Kanaele = $kan; Rate = $rate; Bits = $bits; Dauer = $dauer }
                }
                if ($naechst -gt $fs.Length) { break }
                $fs.Position = $naechst
            }
            return @{ Defekt = $true }
        }
    } catch { return @{ Defekt = $true } }
    finally { if ($fs) { $fs.Dispose() } }
}

# BPM aus Datei- oder Ordnername: "130bpm", "130 BPM", "bpm130", sonst bei Loops eine alleinstehende Zahl 60-200
function Get-Bpm([string]$name, [string]$ordner, [bool]$istLoop) {
    foreach ($t in @($name, $ordner)) {
        if (-not $t) { continue }
        if ($t -match '(?i)(?<![\d.])(\d{2,3}(?:[.,]\d+)?)\s*[-_]?\s*bpm') { $v = [double]($Matches[1] -replace ',', '.'); if ($v -ge 40 -and $v -le 250) { return [math]::Round($v, 1) } }
        if ($t -match '(?i)bpm\s*[-_]?\s*(\d{2,3})(?!\d)') { $v = [double]$Matches[1]; if ($v -ge 40 -and $v -le 250) { return $v } }
    }
    if ($istLoop -and $name -match '(?:^|[\s_\-])(\d{2,3})(?=$|[\s_\-])') {
        $v = [double]$Matches[1]; if ($v -ge 60 -and $v -le 200) { return $v }
    }
    return $null
}

# Tonart aus dem Dateinamen: "Cmin", "C#m", "Eb maj", "A minor", "F#_Major". Ergebnis z. B. "C#m" oder "Eb".
function Get-Tonart([string]$name) {
    $t = $name -replace '[_\-.]', ' '
    $m = [regex]::Match($t, '(?<![A-Za-z#])([A-Ga-g])(#|b|sharp|flat)?\s?(major|minor|maj|min|moll|dur)(?![A-Za-z])', 'IgnoreCase')
    if (-not $m.Success) { $m = [regex]::Match($t, '(?<![A-Za-z#])([A-G])(#|b)?(m)(?![A-Za-z])') }
    if (-not $m.Success) { return '' }
    $grund = $m.Groups[1].Value.ToUpperInvariant()
    $vz = $m.Groups[2].Value.ToLowerInvariant()
    if ($vz -eq 'sharp') { $vz = '#' } elseif ($vz -eq 'flat') { $vz = 'b' }
    $q = $m.Groups[3].Value.ToLowerInvariant()
    $moll = $q -in 'm', 'min', 'minor', 'moll'
    return "$grund$vz$(if ($moll) { 'm' } else { '' })"
}

# Zerlegt den relativen Pfad im Ziel in Kategorie, Instrument, Typ und Pack (Struktur aus Samples-sortieren.ps1)
function Get-Einordnung([string[]]$teile) {
    $katOrdner = $teile[0]
    $kat = $katOrdner -replace '^\d+\s+', '' -replace '^_', ''
    $i = 1
    $inst = $kat
    if ($katOrdner -match '^0[12] ' -and $teile.Count -gt 2) { $inst = $teile[1]; $i = 2 }
    $typ = ''
    if ($teile.Count -gt $i + 1 -and $teile[$i] -in 'One-Shots', 'Loops') { $typ = $teile[$i].TrimEnd('s'); $i++ }
    $pack = if ($teile.Count -gt $i + 1) { $teile[$i] } else { '(ohne Pack)' }
    if (-not $typ) {
        if ($inst -eq 'Drum-Loops') { $typ = 'Loop' }
        elseif ($inst -eq 'Drum-Kits' -or $kat -eq 'Construction Kits') { $typ = 'Kit' }
    }
    return @{ KatOrdner = $katOrdner; Kategorie = $kat; Instrument = $inst; Typ = $typ; Pack = $pack }
}

# ----------------------------------------------------------------------------
# 1) Dateien im Ziel einlesen
# ----------------------------------------------------------------------------
Write-Host "Lese die Bibliothek ein ..." -ForegroundColor Cyan
$dateien = New-Object System.Collections.Generic.List[object]
$stapel = New-Object System.Collections.Generic.Stack[string]
$stapel.Push($Ziel)
$nichtLesbar = 0
while ($stapel.Count -gt 0) {
    $o = $stapel.Pop()
    try { $inh = @(Get-ChildItem -LiteralPath $o -Force -ErrorAction Stop) } catch { $nichtLesbar++; continue }
    foreach ($e in $inh) {
        if ($e.PSIsContainer) {
            if (-not ($e.Attributes -band [IO.FileAttributes]::ReparsePoint)) { $stapel.Push($e.FullName) }
        } elseif ($o -ne $Ziel) { $dateien.Add($e) }   # Dateien direkt im Ziel sind Protokolle
    }
}
Write-Host "  $($dateien.Count) Dateien gefunden."

# Ursprungspfade aus allen Kopier-Protokollen (im Ziel und im Ordner Protokolle)
$ursprung = @{}
$protos = @()
foreach ($o in @($Ziel, $protokollOrdner)) { if (Test-Path -LiteralPath $o) { $protos += @(Get-ChildItem -LiteralPath $o -Filter 'Protokoll_*.csv' -File -ErrorAction SilentlyContinue) } }
foreach ($p in ($protos | Sort-Object Name)) {
    try {
        foreach ($z in (Import-Csv -LiteralPath $p.FullName -Delimiter ';' -Encoding UTF8)) {
            if ($z.Ziel -and $z.Quelle -and $z.Aktion -match '^(kopiert|Kopiert)$') { $ursprung[$z.Ziel.ToLowerInvariant()] = $z.Quelle }
        }
    } catch { }
}

# Vorherige Inventur (fuer Vergleich und um Pruefsummen nicht neu zu berechnen)
$vorher = Get-NeuesteInventur 'Sample'
$alt = @{}
if ($vorher) {
    try { foreach ($z in (Import-Csv -LiteralPath $vorher.FullName -Delimiter ';' -Encoding UTF8)) { $alt[$z.Pfad.ToLowerInvariant()] = $z } } catch { $alt = @{} }
}

# Lizenzen & Infos: welche Packs haben Begleittexte
$lizenzPacks = @{}
foreach ($d in $dateien) {
    $rel = $d.FullName.Substring($Ziel.Length).TrimStart('\', '/')
    $t = $rel -split '[\\/]'
    if ($t[0] -eq '_Lizenzen & Infos' -and $t.Count -ge 3) { $lizenzPacks[$t[1].ToLowerInvariant()] = $true }
}

# ----------------------------------------------------------------------------
# 2) Samples erfassen
# ----------------------------------------------------------------------------
Write-Host "Lese Audio-Eigenschaften, BPM und Tonart ..." -ForegroundColor Cyan
$samples = New-Object System.Collections.Generic.List[object]
$i = 0
foreach ($d in $dateien) {
    $i++
    if ($i % 100 -eq 0) { Write-Progress -Activity 'Inventur' -Status "$i / $($dateien.Count)" -PercentComplete ($i * 100 / $dateien.Count) }
    $rel = $d.FullName.Substring($Ziel.Length).TrimStart('\', '/')
    $teile = @($rel -split '[\\/]')
    $istAudio = $d.Name -match $RxAudio
    if (-not $istAudio -and $teile[0] -ne '11 MIDI') { continue }   # Lizenztexte usw. zaehlen nicht als Sample
    if ((Get-MacRestArt $d.FullName) -eq 'mac') { continue }
    $ein = Get-Einordnung $teile
    $basis = [IO.Path]::GetFileNameWithoutExtension($d.Name)
    $ordnerName = if ($teile.Count -ge 2) { $teile[$teile.Count - 2] } else { '' }
    $info = if ($istAudio) { Get-AudioInfo $d.FullName } else { $null }
    $istLoop = $ein.Typ -eq 'Loop'
    $dauer = if ($info -and -not $info.Defekt -and $info.Dauer -ge 0) { [math]::Round($info.Dauer, 2) } else { $null }
    if (-not $ein.Typ -and $null -ne $dauer) { $ein.Typ = if ($dauer -ge 6) { 'Loop' } else { 'One-Shot' }; $istLoop = $ein.Typ -eq 'Loop' }
    $hinweis = @()
    if ($d.Length -eq 0) { $hinweis += 'leere Datei (0 Byte)' }
    elseif ($info -and $info.Defekt) { $hinweis += 'Dateikopf nicht lesbar (defekt?)' }
    if ($ein.KatOrdner -eq '_Unsortiert') { $hinweis += 'unsortiert' }
    $u = $ursprung[$d.FullName.ToLowerInvariant()]
    $orig = if (-not $u) { 'unbekannt' } elseif (Test-Path -LiteralPath $u) { 'ja' } else { 'nein' }
    $geaendert = $d.LastWriteTime.ToString('yyyy-MM-dd HH:mm:ss')
    $a = $alt[$rel.ToLowerInvariant()]
    $hash = if ($a -and $a.Hash -and [string]$a.GroesseBytes -eq [string]$d.Length -and $a.Geaendert -eq $geaendert) { $a.Hash } else { '' }
    $samples.Add([pscustomobject][ordered]@{
        Datei = $d.Name; Kategorie = $ein.Kategorie; Instrument = $ein.Instrument; Typ = $ein.Typ; Pack = $ein.Pack; 'Pack-Art' = ''
        Format = $d.Extension.TrimStart('.').ToUpperInvariant(); GroesseBytes = $d.Length
        Dauer = $dauer
        Abtastrate = $(if ($info -and -not $info.Defekt) { $info.Rate } else { $null })
        Bittiefe   = $(if ($info -and -not $info.Defekt) { $info.Bits } else { $null })
        Bitrate    = $(if ($info -and -not $info.Defekt -and $info.Bitrate) { $info.Bitrate } else { $null })
        Kanaele    = $(if ($info -and -not $info.Defekt) { if ($info.Kanaele -eq 1) { 'mono' } elseif ($info.Kanaele -eq 2) { 'stereo' } else { [string]$info.Kanaele } } else { '' })
        BPM = (Get-Bpm $basis $ordnerName $istLoop); Tonart = (Get-Tonart $basis)
        Pfad = $rel; Ursprung = $u; 'Original in Quelle' = $orig
        Hash = $hash; 'Duplikat-Gruppe' = ''; 'Duplikat-Rolle' = ''; 'Seit letzter Inventur' = ''
        Geaendert = $geaendert; Hinweis = ($hinweis -join ', ')
    })
}
Write-Progress -Activity 'Inventur' -Completed
Write-Host "  $($samples.Count) Samples erfasst."

# ----------------------------------------------------------------------------
# 3) Duplikate im Ziel: Vorfilter Groesse, dann Pruefsumme
#    Behalten wird: Exemplar in einem Kit > nicht in "_Unsortiert" > kuerzester Pfad
# ----------------------------------------------------------------------------
Write-Host "Suche Duplikate in der Bibliothek ..." -ForegroundColor Cyan
$gruppenNr = 0
$dupDateien = 0; $dupBytes = 0
$kandidaten = @($samples | Where-Object { $_.GroesseBytes -gt 0 } | Group-Object GroesseBytes | Where-Object { $_.Count -gt 1 })
foreach ($g in $kandidaten) {
    foreach ($s in $g.Group) {
        if (-not $s.Hash) { try { $s.Hash = (Get-FileHash -LiteralPath (Join-Path $Ziel $s.Pfad) -Algorithm MD5).Hash } catch { $s.Hash = '' } }
    }
    foreach ($h in ($g.Group | Where-Object { $_.Hash } | Group-Object Hash | Where-Object { $_.Count -gt 1 })) {
        $gruppenNr++
        $sortiert = @($h.Group | Sort-Object @{ e = { if ($_.Typ -eq 'Kit') { 0 } else { 1 } } }, @{ e = { if ($_.Hinweis -like '*unsortiert*') { 1 } else { 0 } } }, @{ e = { $_.Pfad.Length } }, Pfad)
        for ($k = 0; $k -lt $sortiert.Count; $k++) {
            $sortiert[$k].'Duplikat-Gruppe' = $gruppenNr
            if ($k -eq 0) { $sortiert[$k].'Duplikat-Rolle' = 'behalten' }
            elseif ($sortiert[$k].Typ -eq 'Kit') { $sortiert[$k].'Duplikat-Rolle' = 'behalten (Kit)' }
            else { $sortiert[$k].'Duplikat-Rolle' = 'entfernbar'; $dupDateien++; $dupBytes += $sortiert[$k].GroesseBytes }
        }
    }
}
Write-Host "  $gruppenNr Duplikat-Gruppen, $dupDateien entfernbare Dateien ($('{0:N1}' -f ($dupBytes / 1MB)) MB)."

# ----------------------------------------------------------------------------
# 4) Packs: Kennzahlen und Pack-Art (automatisch, Korrektur ueber Pack-Arten.csv)
# ----------------------------------------------------------------------------
$korrektur = @{}
if (Test-Path -LiteralPath $packArtenPfad) {
    try { foreach ($z in (Import-Csv -LiteralPath $packArtenPfad -Delimiter ';' -Encoding UTF8)) { if ($z.Pack -and $z.'Pack-Art') { $korrektur[$z.Pack.Trim().ToLowerInvariant()] = $z.'Pack-Art'.Trim() } } } catch { }
}
function Get-PackArt($liste) {
    $n = $liste.Count
    $anteil = { param($bed) (@($liste | Where-Object $bed).Count) / [math]::Max(1, $n) }
    if ((& $anteil { $_.Kategorie -eq 'Construction Kits' }) -ge 0.5) { return 'Construction Kit' }
    if ((& $anteil { $_.Instrument -eq 'Drum-Kits' }) -ge 0.5) { return 'Drum-Kit' }
    if ((& $anteil { $_.Kategorie -eq 'Vocals' }) -ge 0.5) { return 'Vocal-Pack' }
    if ((& $anteil { $_.Kategorie -eq 'Atmos & Field Recordings' }) -ge 0.5) { return 'Atmos/Field Recording' }
    if ((& $anteil { $_.Kategorie -eq 'FX & Noise' }) -ge 0.5) { return 'FX-Pack' }
    if ((& $anteil { $_.Kategorie -eq 'MIDI' }) -ge 0.5) { return 'MIDI-Pack' }
    if ((& $anteil { $_.Kategorie -eq 'Songs & Playalongs' }) -ge 0.5) { return 'Song/Playalong' }
    if ((& $anteil { $_.Typ -eq 'Loop' }) -ge 0.6) { return 'Loop-Pack' }
    $drums = & $anteil { $_.Kategorie -in 'Drums', 'Percussion' }
    if ($drums -ge 0.6) { return 'One-Shot-Pack' }
    if ((& $anteil { $_.Kategorie -in 'Bass', 'Keys & Synth', 'Guitar', 'Brass & Sax' }) -ge 0.5) { return 'Melodie/Instrument' }
    return 'gemischt'
}
$packs = New-Object System.Collections.Generic.List[object]
foreach ($g in ($samples | Group-Object Pack | Sort-Object Name)) {
    $liste = @($g.Group)
    $art = $korrektur[$g.Name.ToLowerInvariant()]
    $artQuelle = 'manuell'
    if (-not $art) { $art = Get-PackArt $liste; $artQuelle = 'automatisch' }
    foreach ($s in $liste) { $s.'Pack-Art' = $art }
    $bpms = @($liste | Where-Object { $null -ne $_.BPM } | ForEach-Object { [double]$_.BPM } | Sort-Object)
    $orig = @($liste | Group-Object 'Original in Quelle' | ForEach-Object { $_.Name })
    $packs.Add([pscustomobject][ordered]@{
        Pack = $g.Name; 'Pack-Art' = $art; 'Pack-Art Herkunft' = $artQuelle
        Samples = $liste.Count; GroesseMB = [math]::Round((($liste | Measure-Object GroesseBytes -Sum).Sum) / 1MB, 1)
        Instrumente = (($liste | Group-Object Instrument | Sort-Object Count -Descending | ForEach-Object { "$($_.Name) $($_.Count)" }) -join ', ')
        'Anteil Loops' = [math]::Round(100 * @($liste | Where-Object { $_.Typ -eq 'Loop' }).Count / $liste.Count)
        Formate = (($liste | Group-Object Format | ForEach-Object { $_.Name }) -join ', ')
        'BPM-Bereich' = $(if ($bpms.Count) { if ($bpms[0] -eq $bpms[-1]) { "$($bpms[0])" } else { "$($bpms[0])-$($bpms[-1])" } } else { '' })
        Tonarten = (($liste | Where-Object { $_.Tonart } | Group-Object Tonart | Sort-Object Count -Descending | ForEach-Object { $_.Name }) -join ', ')
        Lizenz = $(if ($lizenzPacks[$g.Name.ToLowerInvariant()]) { 'ja' } else { 'nein' })
        'Original in Quelle' = $(if ($orig.Count -eq 1) { $orig[0] } else { 'teilweise' })
        Duplikate = @($liste | Where-Object { $_.'Duplikat-Rolle' -eq 'entfernbar' }).Count
        'Seit letzter Inventur' = ''
    })
}

# Ausgesparte Bereiche der Quelle (z. B. ModX) als eigener Eintrag
$modx = @(Get-AktiveQuellen | ForEach-Object { Join-Path $_ 'ModX' } | Where-Object { Test-Path -LiteralPath $_ }) | Select-Object -First 1
if (-not $modx) { $modx = Join-Path $einst.Quelle 'ModX' }
if (Test-Path -LiteralPath $modx) {
    $mb = 0; try { $mb = [math]::Round(((Get-ChildItem -LiteralPath $modx -Recurse -File -Force -ErrorAction SilentlyContinue | Measure-Object Length -Sum).Sum) / 1MB, 1) } catch { }
    $packs.Add([pscustomobject][ordered]@{
        Pack = 'ModX (Yamaha-Bibliotheken)'; 'Pack-Art' = 'ausgespart'; 'Pack-Art Herkunft' = 'automatisch'; Samples = 0; GroesseMB = $mb
        Instrumente = ''; 'Anteil Loops' = 0; Formate = ''; 'BPM-Bereich' = ''; Tonarten = ''; Lizenz = ''
        'Original in Quelle' = 'ja (nicht kopiert)'; Duplikate = 0; 'Seit letzter Inventur' = ''
    })
}

# ----------------------------------------------------------------------------
# 5) Vergleich mit der letzten Inventur
# ----------------------------------------------------------------------------
$vergleich = New-Object System.Collections.Generic.List[object]
if ($vorher) {
    $jetzt = @{}; foreach ($s in $samples) { $jetzt[$s.Pfad.ToLowerInvariant()] = $s }
    $weg = @($alt.Keys | Where-Object { -not $jetzt.ContainsKey($_) } | ForEach-Object { $alt[$_] })
    $neu = @($samples | Where-Object { -not $alt.ContainsKey($_.Pfad.ToLowerInvariant()) })
    # verschoben: gleicher Name und gleiche Groesse
    $wegNach = @{}; foreach ($w in $weg) { $k = "$($w.Datei)|$($w.GroesseBytes)".ToLowerInvariant(); if (-not $wegNach.ContainsKey($k)) { $wegNach[$k] = New-Object System.Collections.Generic.List[object] }; $wegNach[$k].Add($w) }
    $wegVerschoben = @{}
    foreach ($n in $neu) {
        $k = "$($n.Datei)|$($n.GroesseBytes)".ToLowerInvariant()
        if ($wegNach.ContainsKey($k) -and $wegNach[$k].Count -gt 0) {
            $w = $wegNach[$k][0]; $wegNach[$k].RemoveAt(0); $wegVerschoben[$w.Pfad.ToLowerInvariant()] = $true
            $n.'Seit letzter Inventur' = "verschoben (vorher $($w.Pfad))"
            $vergleich.Add([pscustomobject]@{ Vergleich = 'verschoben'; Datei = $n.Datei; Pack = $n.Pack; Pfad = $n.Pfad; 'Pfad vorher' = $w.Pfad; 'Verglichen mit' = $vorher.Name })
        } else {
            $n.'Seit letzter Inventur' = 'neu'
            $vergleich.Add([pscustomobject]@{ Vergleich = 'neu'; Datei = $n.Datei; Pack = $n.Pack; Pfad = $n.Pfad; 'Pfad vorher' = ''; 'Verglichen mit' = $vorher.Name })
        }
    }
    foreach ($w in $weg) {
        if ($wegVerschoben.ContainsKey($w.Pfad.ToLowerInvariant())) { continue }
        $vergleich.Add([pscustomobject]@{ Vergleich = 'entfernt'; Datei = $w.Datei; Pack = $w.Pack; Pfad = ''; 'Pfad vorher' = $w.Pfad; 'Verglichen mit' = $vorher.Name })
    }
    # Packs neu / entfernt
    $altPacks = @{}; foreach ($w in $alt.Values) { $altPacks[$w.Pack.ToLowerInvariant()] = $true }
    foreach ($p in $packs) { if ($p.'Pack-Art' -ne 'ausgespart' -and -not $altPacks.ContainsKey($p.Pack.ToLowerInvariant())) { $p.'Seit letzter Inventur' = 'neu' } }
}

# ----------------------------------------------------------------------------
# 6) Speichern
# ----------------------------------------------------------------------------
if (Test-Path -LiteralPath (Join-Path $invOrdner "Sample-Inventur_$Zeitstempel.csv")) { $Zeitstempel = $start.ToString('yyyy-MM-dd_HHmmss') }   # zweiter Lauf in derselben Minute
$basisName = "Sample-Inventur_$Zeitstempel"
$csvSamples = Join-Path $invOrdner "$basisName.csv"
$csvPacks   = Join-Path $invOrdner "Pack-Inventur_$Zeitstempel.csv"
$samples | Export-Csv -LiteralPath $csvSamples -NoTypeInformation -Delimiter ';' -Encoding UTF8
$packs   | Export-Csv -LiteralPath $csvPacks   -NoTypeInformation -Delimiter ';' -Encoding UTF8
if ($vorher) {
    $vglPfad = Join-Path $vglOrdner "Inventur-Vergleich_$Zeitstempel.csv"
    if ($vergleich.Count -gt 0) { $vergleich | Export-Csv -LiteralPath $vglPfad -NoTypeInformation -Delimiter ';' -Encoding UTF8 }
    else { Set-Content -LiteralPath $vglPfad -Value '"Vergleich";"Datei";"Pack";"Pfad";"Pfad vorher";"Verglichen mit"' -Encoding UTF8 }
}
$frei = $null
try { $lw = [IO.DriveInfo]::new([IO.Path]::GetPathRoot($Ziel)); if ($lw.IsReady) { $frei = [math]::Round($lw.AvailableFreeSpace / 1GB, 1) } } catch { }
$lauf = [ordered]@{
    Version = $ProgrammVersion; Zeit = $start.ToString('dd.MM.yyyy HH:mm'); Rechner = $env:COMPUTERNAME
    Ziel = $Ziel; Quelle = $einst.Quelle; Dauer = [math]::Round(((Get-Date) - $start).TotalSeconds)
    Samples = $samples.Count; Packs = @($packs | Where-Object { $_.'Pack-Art' -ne 'ausgespart' }).Count
    GroesseGB = [math]::Round((($samples | Measure-Object GroesseBytes -Sum).Sum) / 1GB, 2); FreiGB = $frei
    DuplikatGruppen = $gruppenNr; DuplikatDateien = $dupDateien; DuplikatMB = [math]::Round($dupBytes / 1MB, 1)
    VerglichenMit = $(if ($vorher) { $vorher.Name } else { '' }); NichtLesbareOrdner = $nichtLesbar
}
ConvertTo-Json -InputObject $lauf | Set-Content -LiteralPath (Join-Path $invOrdner "$basisName.json") -Encoding UTF8

Write-Host "Erzeuge den HTML-Bericht ..." -ForegroundColor Cyan
$html = New-InventurBericht $csvSamples

Write-Host ""
Write-Host "==================== Ergebnis ====================" -ForegroundColor Yellow
Write-Host ("Samples:            {0,8}   ({1:N2} GB)" -f $samples.Count, $lauf.GroesseGB)
Write-Host ("Packs:              {0,8}" -f $lauf.Packs)
Write-Host ("Duplikate im Ziel:  {0,8}   entfernbar, {1:N1} MB" -f $dupDateien, ($dupBytes / 1MB))
if ($vorher) {
    $n = @($vergleich | Where-Object { $_.Vergleich -eq 'neu' }).Count
    $e = @($vergleich | Where-Object { $_.Vergleich -eq 'entfernt' }).Count
    $v = @($vergleich | Where-Object { $_.Vergleich -eq 'verschoben' }).Count
    Write-Host ("Seit letzter Inventur: {0} neu, {1} entfernt, {2} verschoben" -f $n, $e, $v)
} else { Write-Host "Erste Inventur - ab der naechsten gibt es einen Vergleich." }
if ($nichtLesbar -gt 0) { Write-Host "Hinweis: $nichtLesbar Ordner waren nicht lesbar." -ForegroundColor Yellow }
Write-Host ""
Write-Host "Liste (Excel):  $csvSamples"
Write-Host "Bericht:        $html" -ForegroundColor Green
if ([Environment]::UserInteractive -and -not $env:SW_PAPIERKORB) {
    if (Read-JaNein 'Bericht jetzt im Browser oeffnen?') {
        $psExe = Join-Path $PSHOME 'powershell.exe'; if (-not (Test-Path -LiteralPath $psExe)) { $psExe = 'powershell.exe' }
        try { Start-Process -FilePath $psExe -ArgumentList "-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File `"$(Join-Path $PSScriptRoot 'Bericht-Dienst.ps1')`"" -WindowStyle Hidden -ErrorAction Stop }
        catch { try { Invoke-Item -LiteralPath $html } catch { } }
    }
}
