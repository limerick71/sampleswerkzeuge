# (c) 2026 Herbert Stoecker. Kostenlos nutzbar. Bitte nur als Link auf die offizielle Download-Seite weitergeben; Verkauf und Veroeffentlichung geaenderter Fassungen nur mit Zustimmung.
<#
.SYNOPSIS
  Quelle aufraeumen (ersetzt "Duplikate entfernen"). Bewusster Schritt fuer alles Entbehrliche in der
  Quelle - das Sortieren selbst veraendert die Quelle nie. Auswaehlbar:
    1  Duplikate      Dateien, die beim Kopieren als doppelt erkannt wurden (Pruefung gegen das behaltene Exemplar)
    2  macOS-Reste    ._-Dateien, .DS_Store, __MACOSX (erkannt am Dateikopf)
    3  Formate        RX2/MP3/AIFF neben einer gleichnamigen WAV im selben Pack, deren Kopie im Ziel bestaetigt ist
                      (welche Formate: frei waehlbar, vorbelegt mit den beim Sortieren abgewaehlten)
    4  Originale      Dateien, deren Kopie im Ziel laut Kopier-Protokoll vorhanden und per Pruefsumme bestaetigt ist
  Alles mit Vorschau und Rueckfrage (Standard: Nein). Die Dateien gehen in den Papierkorb.

.BENUTZUNG
    -Duplikate -MacReste -Formate -Originale   Gruppen waehlen (ohne Angabe: Auswahl in der Konsole)
    -Formatliste "RX2,MP3"          Formate fuer Gruppe 3 (ohne Angabe: die beim Sortieren abgewaehlten)
    -NurVorschau                    nur Vorschau, keine Frage
    -Ausfuehren                     ohne Frage entfernen
#>
[CmdletBinding()]
param(
    [switch]$Duplikate,
    [switch]$MacReste,
    [switch]$Formate,
    [switch]$Originale,
    [string]$Formatliste,
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

# Formate fuer Gruppe 3 (CLN-12): eigene Auswahl, unabhaengig von den Sortier-Haken
function Get-FormatEndungen([string]$liste) {
    $namen = @($liste -split '[,; ]+' | Where-Object { $_ } | ForEach-Object { $_.Trim().ToUpperInvariant() })
    @($FormatEinstellung.Keys | Where-Object { $namen -contains $FormatName[$FormatEinstellung[$_]] })
}
$vorbelegt = (@($FormatEinstellung.Keys | Where-Object { -not $einst[$FormatEinstellung[$_]] } | ForEach-Object { $FormatName[$FormatEinstellung[$_]] } | Select-Object -Unique)) -join ','

if (-not ($Duplikate -or $MacReste -or $Formate -or $Originale)) {
    Write-Host "Was soll aus der Quelle in den Papierkorb?"
    Write-Host "  1  Duplikate (beim Kopieren als doppelt erkannt)"
    Write-Host "  2  macOS-Reste (._-Dateien, .DS_Store, __MACOSX)"
    Write-Host "  3  RX2/MP3/AIFF neben gleichnamiger WAV im selben Pack, deren Kopie im Ziel liegt"
    Write-Host "  4  Originale, deren Kopie im Ziel bestaetigt ist (die Quelle wird damit weitgehend geleert)"
    $a = Read-Host "Auswahl, z. B. 1,2 (Enter = abbrechen)"
    if (-not $a.Trim()) { Write-Host "Abgebrochen."; return }
    $Duplikate = $a -match '1'; $MacReste = $a -match '2'; $Formate = $a -match '3'; $Originale = $a -match '4'
    if ($Formate -and -not $Formatliste) {
        $f = Read-Host "Welche Formate? z. B. RX2,MP3,AIFF (Enter = $(if ($vorbelegt) { $vorbelegt } else { 'keine' }))"
        $Formatliste = if ($f.Trim()) { $f } else { $vorbelegt }
    }
    Write-Host ""
}
if ($Formate -and -not $PSBoundParameters.ContainsKey('Formatliste') -and -not $Formatliste) { $Formatliste = $vorbelegt }
$ausgeschlossen = if ($Formate) { @(Get-FormatEndungen $Formatliste) } else { @() }
$formatText = (@($ausgeschlossen | ForEach-Object { $FormatName[$FormatEinstellung[$_]] } | Select-Object -Unique)) -join ', '
if ($Formate -and -not $formatText) { Write-Host "Hinweis: Gruppe 3 entfaellt, es ist kein Format (RX2, MP3, AIFF) gewaehlt." -ForegroundColor Yellow; $Formate = $false }

$ergebnis = New-Object System.Collections.Generic.List[object]
function Add-Eintrag($gruppe, $status, $datei, $grund, $bytes) {
    $ergebnis.Add([pscustomobject]@{ Gruppe = $gruppe; Status = $status; Datei = $datei; 'Grund / Abgleich' = $grund; GroesseMB = [math]::Round([double]$bytes / 1MB, 2) })
}

# Pruefsummen nur einmal je Datei berechnen; vorher Groesse vergleichen (kostet nichts)
$hashCache = @{}
function Get-Pruefsumme([string]$pfad) {
    $k = $pfad.ToLowerInvariant()
    if (-not $hashCache.ContainsKey($k)) { $hashCache[$k] = (Get-FileHash -LiteralPath $pfad -Algorithm SHA256).Hash }
    return $hashCache[$k]
}
function Test-Gleich([string]$a, [string]$b) {
    if (([IO.FileInfo]$a).Length -ne ([IO.FileInfo]$b).Length) { return $false }   # auch versteckte Dateien
    return (Get-Pruefsumme $a) -eq (Get-Pruefsumme $b)
}
# Fortschritt: Balken oben im Fenster und alle paar Sekunden eine Zeile, damit man sieht, dass es laeuft
$script:fortschrittZeit = [DateTime]::MinValue
function Show-Fortschritt([string]$was, [int]$i, [int]$n) {
    if ($n -le 0) { return }
    if ($i % 20 -eq 0 -or $i -eq $n) { Write-Progress -Activity $was -Status "$i von $n" -PercentComplete ([Math]::Min(100, $i * 100 / $n)) }
    if (((Get-Date) - $script:fortschrittZeit).TotalSeconds -ge 5) { Write-Host ("  ... {0}: {1} von {2}" -f $was, $i, $n) -ForegroundColor DarkGray; $script:fortschrittZeit = Get-Date }
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
        $dupListe = @(Import-Csv -LiteralPath $p.FullName -Delimiter ';' -Encoding UTF8 | Where-Object { $_.Aktion -like 'Duplikat*' })
        $i = 0
        foreach ($d in $dupListe) {
            $i++; Show-Fortschritt 'Duplikate pruefen' $i $dupListe.Count
            $datei = $d.Quelle; $original = ''
            if ($d.ZielRel -match '^\(identisch mit (.+)\)$') { $original = $Matches[1] }
            $bytes = 0; try { $bytes = (Get-Item -LiteralPath $datei -ErrorAction Stop).Length } catch { }
            if (-not $datei.StartsWith($Quelle, [StringComparison]::OrdinalIgnoreCase)) { Add-Eintrag 'Duplikat' 'Uebersprungen: liegt nicht im Quellordner' $datei '' 0 }
            elseif ($datei -notmatch $RxAudio) { Add-Eintrag 'Duplikat' 'Uebersprungen: keine Audiodatei (bleibt im Pack)' $datei '' 0 }
            elseif (-not (Test-Path -LiteralPath $datei)) { Add-Eintrag 'Duplikat' 'Uebersprungen: Datei existiert nicht mehr' $datei '' 0 }
            elseif (-not $original -or -not (Test-Path -LiteralPath $original) -or $original -eq $datei) { Add-Eintrag 'Duplikat' 'Uebersprungen: behaltenes Exemplar nicht gefunden' $datei $original $bytes }
            elseif (-not (Test-Gleich $datei $original)) { Add-Eintrag 'Duplikat' 'Uebersprungen: Inhalt weicht ab' $datei $original $bytes }
            else { Add-Eintrag 'Duplikat' 'Wird entfernt' $datei "identisch mit $original" $bytes }
        }
    }
}

# Quelle einmal durchgehen (fuer macOS-Reste, Formate und Originale)
$quellDateien = New-Object System.Collections.Generic.List[object]
if ($MacReste -or $Formate -or $Originale) {
    Write-Host "Lese den Quellordner ..." -ForegroundColor Cyan
    $stapel = New-Object System.Collections.Generic.Stack[string]; $stapel.Push($Quelle)
    while ($stapel.Count -gt 0) {
        $o = $stapel.Pop()
        try { $inh = @(Get-ChildItem -LiteralPath $o -Force -ErrorAction Stop) } catch { continue }
        foreach ($e in $inh) {
            if ($e.PSIsContainer) {
                if ($e.Attributes -band [IO.FileAttributes]::ReparsePoint) { continue }
                if ($o -eq $Quelle -and ($e.Name -eq 'ModX' -or $e.Name -eq '_Sortier-Skript' -or $e.Name -like 'Samples-Werkzeuge*')) { continue }
                $stapel.Push($e.FullName)
            } else { $quellDateien.Add($e); if ($quellDateien.Count % 2000 -eq 0) { Write-Host "  ... $($quellDateien.Count) Dateien gelesen" -ForegroundColor DarkGray } }
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
# Kopier-Protokolle: wohin wurde welche Quelldatei kopiert (fuer Formate und Originale)
$zielVon = @{}; $dupVon = @{}
if ($Formate -or $Originale) {
    foreach ($p in $protos) {
        try {
            foreach ($z in (Import-Csv -LiteralPath $p.FullName -Delimiter ';' -Encoding UTF8)) {
                if ($z.Quelle -and $z.Ziel -and ($z.Aktion -match '^(kopiert|Kopiert)$' -or $z.Aktion -like 'bereits im Ziel*')) { $zielVon[$z.Quelle.ToLowerInvariant()] = $z.Ziel }
                elseif ($z.Quelle -and $z.Aktion -like 'Duplikat*' -and $z.ZielRel -match '^\(identisch mit (.+)\)$') { $dupVon[$z.Quelle.ToLowerInvariant()] = $Matches[1] }
            }
        } catch { }
    }
}

if ($Formate) {
    Write-Host "Formate ($formatText): pruefe WAV-Gegenstuecke im Ziel ..." -ForegroundColor Cyan
    $wavs = @{}
    foreach ($f in $quellDateien) { if ($f.Extension -ieq '.wav' -and (Get-MacRestArt $f.FullName) -ne 'mac') { $wavs[(Get-FormatSchluessel $f.FullName $Quelle)] = $f.FullName } }
    $kandidaten = @($quellDateien | Where-Object { $ausgeschlossen -contains $_.Extension.ToLowerInvariant() })
    $i = 0
    foreach ($f in $kandidaten) {
        $i++; Show-Fortschritt 'Formate pruefen' $i $kandidaten.Count
        if ((Get-MacRestArt $f.FullName) -eq 'mac') { continue }
        $wav = $wavs[(Get-FormatSchluessel $f.FullName $Quelle)]
        if (-not $wav) { continue }   # ohne WAV-Gegenstueck: bleibt immer
        $zw = $zielVon[$wav.ToLowerInvariant()]
        # WAV war beim Kopieren ein Duplikat: dann zaehlt die Ziel-Kopie des behaltenen Exemplars
        if (-not $zw -and $dupVon.ContainsKey($wav.ToLowerInvariant())) { $zw = $zielVon[$dupVon[$wav.ToLowerInvariant()].ToLowerInvariant()] }
        if (-not $zw -or -not (Test-Path -LiteralPath $zw)) { Add-Eintrag 'Format' 'Uebersprungen: WAV ist (noch) nicht im Ziel' $f.FullName $wav $f.Length; continue }
        if (-not (Test-Gleich $wav $zw)) { Add-Eintrag 'Format' 'Uebersprungen: WAV im Ziel weicht ab' $f.FullName $zw $f.Length; continue }
        Add-Eintrag 'Format' 'Wird entfernt' $f.FullName "WAV im Ziel bestaetigt: $zw" $f.Length
    }
}

# ---------------------------------------------------------------------------
# 4) Originale, deren Kopie im Ziel bestaetigt ist (CLN-01)
#    Nur Dateien aus einem Kopier-Protokoll; Ziel-Datei muss existieren und inhaltsgleich sein.
#    Was nie kopiert wurde (Hilfsdateien, ausgeschlossene Formate, ModX ...), bleibt liegen.
# ---------------------------------------------------------------------------
if ($Originale) {
    Write-Host "Originale: pruefe Kopien im Ziel ..." -ForegroundColor Cyan
    if (-not $protos.Count) { Write-Host "Originale: kein Kopier-Protokoll gefunden - bitte zuerst 'Samples sortieren'." -ForegroundColor Yellow }
    $kandidaten = @($quellDateien | Where-Object { $zielVon.ContainsKey($_.FullName.ToLowerInvariant()) })
    $i = 0
    foreach ($f in $kandidaten) {
        $i++; Show-Fortschritt 'Originale pruefen' $i $kandidaten.Count
        $zw = $zielVon[$f.FullName.ToLowerInvariant()]
        if (-not $zw.StartsWith($Ziel, [StringComparison]::OrdinalIgnoreCase)) { Add-Eintrag 'Original' 'Uebersprungen: Kopie liegt nicht im eingestellten Ziel' $f.FullName $zw $f.Length; continue }
        if (-not (Test-Path -LiteralPath $zw -PathType Leaf)) { Add-Eintrag 'Original' 'Uebersprungen: Kopie im Ziel nicht (mehr) vorhanden' $f.FullName $zw $f.Length; continue }
        if (-not (Test-Gleich $f.FullName $zw)) { Add-Eintrag 'Original' 'Uebersprungen: Kopie im Ziel weicht ab' $f.FullName $zw $f.Length; continue }
        Add-Eintrag 'Original' 'Wird entfernt' $f.FullName "Kopie im Ziel bestaetigt: $zw" $f.Length
    }
    $nie = @($quellDateien | Where-Object { -not $zielVon.ContainsKey($_.FullName.ToLowerInvariant()) }).Count
    if ($nie) { Write-Host "  $nie Dateien der Quelle wurden nie kopiert und bleiben liegen (Hilfsdateien, ausgeschlossene Formate, Duplikate ...)." -ForegroundColor DarkGray }
}

# ---------------------------------------------------------------------------
# Zusammenfassung, Vorschau, Rueckfrage
# ---------------------------------------------------------------------------
Write-Progress -Activity 'Quelle aufraeumen' -Completed
# Eine Datei kann in zwei Gruppen auftauchen (z. B. Duplikat und Format) - nur einmal entfernen
$gesehen = @{}
foreach ($x in @($ergebnis | Where-Object { $_.Status -eq 'Wird entfernt' })) {
    $k = $x.Datei.ToLowerInvariant()
    if ($gesehen.ContainsKey($k)) { $x.Status = 'Uebersprungen: schon in anderer Gruppe enthalten' } else { $gesehen[$k] = $true }
}
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
$warnung = Get-PapierkorbWarnung $Quelle ([long](($weg | Measure-Object GroesseMB -Sum).Sum * 1MB))
if ($warnung) { Write-Host ""; Write-Host "ACHTUNG: $warnung" -ForegroundColor Red }
if ($Ausfuehren -and $warnung) { Write-Host "Ohne Rueckfrage wird in diesem Fall nichts entfernt." -ForegroundColor Yellow; return }
if (-not $Ausfuehren) {
    if ($NurVorschau) { Write-Host "Es wurde nichts entfernt."; return }
    Write-Host ""
    if (-not (Read-JaNein "Jetzt $($weg.Count) Dateien aus der Quelle in den Papierkorb verschieben?")) {
        Write-Host ""; Write-Host "Abgebrochen. Es wurde nichts entfernt." -ForegroundColor Yellow; return
    }
}

$ok = 0; $fehler = 0
$ordner = New-Object System.Collections.Generic.HashSet[string]
Write-Host ""
Write-Host "Verschiebe $($weg.Count) Dateien in den Papierkorb ..." -ForegroundColor Cyan
$script:fortschrittZeit = Get-Date
$i = 0
foreach ($x in $weg) {
    $i++; Show-Fortschritt 'In den Papierkorb' $i $weg.Count
    try {
        Send-Papierkorb $x.Datei
        $asd = $x.Datei + '.asd'
        if ($x.Gruppe -ne 'macOS-Rest' -and (Test-Path -LiteralPath $asd)) { Send-Papierkorb $asd }
        $x.Status = 'In Papierkorb verschoben'; $ok++
        [void]$ordner.Add((Split-Path -Parent $x.Datei))
    } catch { $x.Status = 'FEHLER: ' + $_.Exception.Message; $fehler++ }
}
Write-Progress -Activity 'In den Papierkorb' -Completed
# Leer gewordene Ordner entfernen (nie die Quelle selbst; .DS_Store zaehlt als leer, wenn macOS-Reste gewaehlt)
Write-Host "Entferne leer gewordene Ordner ..." -ForegroundColor Cyan
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
