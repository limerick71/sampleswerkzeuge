# (c) 2026 Herbert Stoecker. Kostenlos nutzbar. Bitte nur als Link auf die offizielle Download-Seite weitergeben; Verkauf und Veroeffentlichung geaenderter Fassungen nur mit Zustimmung.
<#
.SYNOPSIS
  Quelle aufraeumen (ersetzt "Duplikate entfernen"). Bewusster Schritt fuer alles Entbehrliche in der
  Quelle - das Sortieren selbst veraendert die Quelle nie. Auswaehlbar:
    1  Duplikate      Dateien, die beim Kopieren als doppelt erkannt wurden (Pruefung gegen das behaltene Exemplar)
    2  macOS-Reste    ._-Dateien, .DS_Store, __MACOSX (erkannt am Dateikopf)
    3  Formate        RX2/MP3/AIFF neben einer gleichnamigen WAV, deren Kopie im Ziel bestaetigt ist
                      (nur Formate, deren Haken "zusaetzlich behalten" aus ist)
  Alles mit Vorschau und Rueckfrage (Standard: Nein). Die Dateien gehen in den Papierkorb.

.BENUTZUNG
    -Duplikate -MacReste -Formate   Gruppen waehlen (ohne Angabe: Auswahl in der Konsole)
    -NurVorschau                    nur Vorschau, keine Frage
    -Ausfuehren                     ohne Frage entfernen
#>
[CmdletBinding()]
param(
    [switch]$Duplikate,
    [switch]$MacReste,
    [switch]$Formate,
    [switch]$NurVorschau,
    [switch]$Ausfuehren
)

$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'Gemeinsam.ps1')
$Zeitstempel = Get-Date -Format 'yyyy-MM-dd_HHmmss'
$einst = Get-Einstellungen
$Quelle = $einst.Quelle.TrimEnd('\', '/')
$Ziel   = $einst.Ziel.TrimEnd('\', '/')
Write-Host "Quelle aufraeumen (Samples-Werkzeuge $ProgrammVersion)" -ForegroundColor Cyan
Write-Host "  Quelle: $Quelle"
Write-Host ""
if (-not (Test-Path -LiteralPath $Quelle)) { throw "Quellordner nicht gefunden: $Quelle" }

$ausgeschlossen = @($FormatEinstellung.Keys | Where-Object { -not $einst[$FormatEinstellung[$_]] })
$formatText = if ($ausgeschlossen.Count) { (@($ausgeschlossen | ForEach-Object { $FormatName[$FormatEinstellung[$_]] } | Select-Object -Unique)) -join ', ' } else { '' }

if (-not ($Duplikate -or $MacReste -or $Formate)) {
    Write-Host "Was soll aus der Quelle in den Papierkorb?"
    Write-Host "  1  Duplikate (beim Kopieren als doppelt erkannt)"
    Write-Host "  2  macOS-Reste (._-Dateien, .DS_Store, __MACOSX)"
    if ($formatText) { Write-Host "  3  $formatText neben gleichnamiger WAV, deren Kopie im Ziel liegt" }
    else { Write-Host "  3  (nicht verfuegbar: alle Haken 'zusaetzlich behalten' sind gesetzt)" -ForegroundColor DarkGray }
    $a = Read-Host "Auswahl, z. B. 1,2 (Enter = abbrechen)"
    if (-not $a.Trim()) { Write-Host "Abgebrochen."; return }
    $Duplikate = $a -match '1'; $MacReste = $a -match '2'; $Formate = $a -match '3'
    Write-Host ""
}
if ($Formate -and -not $formatText) { Write-Host "Hinweis: Gruppe 3 entfaellt, alle Haken 'zusaetzlich behalten' sind gesetzt." -ForegroundColor Yellow; $Formate = $false }

$ergebnis = New-Object System.Collections.Generic.List[object]
function Add-Eintrag($gruppe, $status, $datei, $grund, $bytes) {
    $ergebnis.Add([pscustomobject]@{ Gruppe = $gruppe; Status = $status; Datei = $datei; 'Grund / Abgleich' = $grund; GroesseMB = [math]::Round([double]$bytes / 1MB, 2) })
}

# Alle Kopier-Protokolle: Quelle -> Ziel (fuer Duplikate und Formate)
$orte = @($protokollOrdner, $Ziel, (Join-Path $Quelle '_Sortier-Skript'))
$protos = @(foreach ($o in $orte) { if ($o -and (Test-Path -LiteralPath $o)) { Get-ChildItem -LiteralPath $o -Filter 'Protokoll_*.csv' -File -ErrorAction SilentlyContinue } }) | Sort-Object Name

# ---------------------------------------------------------------------------
# 1) Duplikate (wie bisher "Duplikate entfernen")
# ---------------------------------------------------------------------------
if ($Duplikate) {
    $p = $protos | Select-Object -Last 1
    if (-not $p) { $p = Get-NeuestesProtokoll 'Vorschau_*.csv' $orte }
    if (-not $p) { Write-Host "Duplikate: kein Kopier-Protokoll gefunden - bitte zuerst 'Samples sortieren'." -ForegroundColor Yellow }
    else {
        Write-Host "Duplikate: pruefe anhand $($p.Name) ..." -ForegroundColor Cyan
        foreach ($d in @(Import-Csv -LiteralPath $p.FullName -Delimiter ';' -Encoding UTF8 | Where-Object { $_.Aktion -like 'Duplikat*' })) {
            $datei = $d.Quelle; $original = ''
            if ($d.ZielRel -match '^\(identisch mit (.+)\)$') { $original = $Matches[1] }
            $bytes = 0; try { $bytes = (Get-Item -LiteralPath $datei -ErrorAction Stop).Length } catch { }
            if (-not $datei.StartsWith($Quelle, [StringComparison]::OrdinalIgnoreCase)) { Add-Eintrag 'Duplikat' 'Uebersprungen: liegt nicht im Quellordner' $datei '' 0 }
            elseif ($datei -notmatch $RxAudio) { Add-Eintrag 'Duplikat' 'Uebersprungen: keine Audiodatei (bleibt im Pack)' $datei '' 0 }
            elseif (-not (Test-Path -LiteralPath $datei)) { Add-Eintrag 'Duplikat' 'Uebersprungen: Datei existiert nicht mehr' $datei '' 0 }
            elseif (-not $original -or -not (Test-Path -LiteralPath $original) -or $original -eq $datei) { Add-Eintrag 'Duplikat' 'Uebersprungen: behaltenes Exemplar nicht gefunden' $datei $original $bytes }
            elseif ((Get-FileHash -LiteralPath $datei -Algorithm SHA256).Hash -ne (Get-FileHash -LiteralPath $original -Algorithm SHA256).Hash) { Add-Eintrag 'Duplikat' 'Uebersprungen: Inhalt weicht ab' $datei $original $bytes }
            else { Add-Eintrag 'Duplikat' 'Wird entfernt' $datei "identisch mit $original" $bytes }
        }
    }
}

# Quelle einmal durchgehen (fuer macOS-Reste und Formate)
$quellDateien = New-Object System.Collections.Generic.List[object]
if ($MacReste -or $Formate) {
    $stapel = New-Object System.Collections.Generic.Stack[string]; $stapel.Push($Quelle)
    while ($stapel.Count -gt 0) {
        $o = $stapel.Pop()
        try { $inh = @(Get-ChildItem -LiteralPath $o -Force -ErrorAction Stop) } catch { continue }
        foreach ($e in $inh) {
            if ($e.PSIsContainer) {
                if ($e.Attributes -band [IO.FileAttributes]::ReparsePoint) { continue }
                if ($o -eq $Quelle -and ($e.Name -eq 'ModX' -or $e.Name -eq '_Sortier-Skript' -or $e.Name -like 'Samples-Werkzeuge*')) { continue }
                $stapel.Push($e.FullName)
            } else { $quellDateien.Add($e) }
        }
    }
}

# ---------------------------------------------------------------------------
# 2) macOS-Reste
# ---------------------------------------------------------------------------
if ($MacReste) {
    Write-Host "macOS-Reste: pruefe Dateikopf ..." -ForegroundColor Cyan
    foreach ($f in $quellDateien) {
        $art = Get-MacRestArt $f.FullName
        if ($art -eq 'mac') { Add-Eintrag 'macOS-Rest' 'Wird entfernt' $f.FullName 'AppleDouble/AppleSingle bzw. .DS_Store' $f.Length }
        elseif ($art -eq 'unklar') { Add-Eintrag 'macOS-Rest' 'Uebersprungen: Name wie macOS-Rest, Inhalt nicht (unklar)' $f.FullName '' $f.Length }
    }
}

# ---------------------------------------------------------------------------
# 3) RX2/MP3/AIFF neben gleichnamiger WAV, deren Kopie im Ziel bestaetigt ist
# ---------------------------------------------------------------------------
if ($Formate) {
    Write-Host "Formate ($formatText): pruefe WAV-Gegenstuecke im Ziel ..." -ForegroundColor Cyan
    $zielVon = @{}
    foreach ($p in $protos) {
        try {
            foreach ($z in (Import-Csv -LiteralPath $p.FullName -Delimiter ';' -Encoding UTF8)) {
                if ($z.Quelle -and $z.Ziel -and ($z.Aktion -match '^(kopiert|Kopiert)$' -or $z.Aktion -like 'bereits im Ziel*')) { $zielVon[$z.Quelle.ToLowerInvariant()] = $z.Ziel }
            }
        } catch { }
    }
    $wavs = @{}
    foreach ($f in $quellDateien) { if ($f.Extension -ieq '.wav') { $wavs[(Join-Path $f.DirectoryName $f.BaseName).ToLowerInvariant()] = $f.FullName } }
    foreach ($f in $quellDateien) {
        $ext = $f.Extension.ToLowerInvariant()
        if ($ausgeschlossen -notcontains $ext) { continue }
        if ((Get-MacRestArt $f.FullName) -eq 'mac') { continue }
        $wav = $wavs[(Join-Path $f.DirectoryName $f.BaseName).ToLowerInvariant()]
        if (-not $wav) { continue }   # ohne WAV-Gegenstueck: bleibt immer
        $zw = $zielVon[$wav.ToLowerInvariant()]
        if (-not $zw -or -not (Test-Path -LiteralPath $zw)) { Add-Eintrag 'Format' 'Uebersprungen: WAV ist (noch) nicht im Ziel' $f.FullName $wav $f.Length; continue }
        if ((Get-FileHash -LiteralPath $wav -Algorithm SHA256).Hash -ne (Get-FileHash -LiteralPath $zw -Algorithm SHA256).Hash) { Add-Eintrag 'Format' 'Uebersprungen: WAV im Ziel weicht ab' $f.FullName $zw $f.Length; continue }
        Add-Eintrag 'Format' 'Wird entfernt' $f.FullName "WAV im Ziel bestaetigt: $zw" $f.Length
    }
}

# ---------------------------------------------------------------------------
# Zusammenfassung, Vorschau, Rueckfrage
# ---------------------------------------------------------------------------
$weg = @($ergebnis | Where-Object { $_.Status -eq 'Wird entfernt' })
Write-Host ""
Write-Host "==================== Zusammenfassung ====================" -ForegroundColor Yellow
foreach ($g in ($ergebnis | Group-Object Gruppe)) {
    Write-Host ("{0}:" -f $g.Name)
    $g.Group | Group-Object Status | ForEach-Object { "  {0,-55} {1,6}" -f $_.Name, $_.Count } | Write-Host
}
if (-not $ergebnis.Count) { Write-Host "Nichts gefunden." }
Write-Host ("Frei werdender Platz: {0:N1} MB" -f [double](($weg | Measure-Object GroesseMB -Sum).Sum))
$vorschauPfad = Join-Path $protokollOrdner "Quelle-aufraeumen-Vorschau_$Zeitstempel.csv"
if ($ergebnis.Count) {
    $ergebnis | Export-Csv -LiteralPath $vorschauPfad -NoTypeInformation -Delimiter ';' -Encoding UTF8
    Write-Host ""
    Write-Host "Vorschau gespeichert (zeigt nur, was passieren wuerde):" -ForegroundColor Green
    Write-Host "  $vorschauPfad"
}
if ($weg.Count -eq 0) { Write-Host ""; Write-Host "Es gibt nichts zu entfernen." -ForegroundColor Green; return }
if (-not $Ausfuehren) {
    if ($NurVorschau) { Write-Host "Es wurde nichts entfernt."; return }
    Write-Host ""
    if (-not (Read-JaNein "Jetzt $($weg.Count) Dateien aus der Quelle in den Papierkorb verschieben?")) {
        Write-Host ""; Write-Host "Abgebrochen. Es wurde nichts entfernt." -ForegroundColor Yellow; return
    }
}

$ok = 0; $fehler = 0
$ordner = New-Object System.Collections.Generic.HashSet[string]
foreach ($x in $weg) {
    try {
        Send-Papierkorb $x.Datei
        $asd = $x.Datei + '.asd'
        if ($x.Gruppe -ne 'macOS-Rest' -and (Test-Path -LiteralPath $asd)) { Send-Papierkorb $asd }
        $x.Status = 'In Papierkorb verschoben'; $ok++
        [void]$ordner.Add((Split-Path -Parent $x.Datei))
    } catch { $x.Status = 'FEHLER: ' + $_.Exception.Message; $fehler++ }
}
# Leer gewordene Ordner entfernen (nie die Quelle selbst; .DS_Store zaehlt als leer, wenn macOS-Reste gewaehlt)
$leer = 0
foreach ($o in ($ordner | Sort-Object { $_.Length } -Descending)) {
    $akt = $o
    while ($akt -and $akt.Length -gt $Quelle.Length -and (Test-Path -LiteralPath $akt)) {
        $rest = @(Get-ChildItem -LiteralPath $akt -Force | Where-Object { -not ($MacReste -and $_.Name -eq '.DS_Store') })
        if ($rest.Count -gt 0) { break }
        try { Send-Papierkorb $akt; $leer++ } catch { break }
        $akt = Split-Path -Parent $akt
    }
}
$csvPfad = Join-Path $protokollOrdner "Quelle-aufgeraeumt_$Zeitstempel.csv"
$ergebnis | Export-Csv -LiteralPath $csvPfad -NoTypeInformation -Delimiter ';' -Encoding UTF8
Write-Host ""
Write-Host "Fertig. In den Papierkorb verschoben: $ok Dateien | leere Ordner entfernt: $leer | Fehler: $fehler" -ForegroundColor Green
Write-Host "Protokoll: $csvPfad"
Write-Host "Wiederherstellen ist ueber den Windows-Papierkorb moeglich."
