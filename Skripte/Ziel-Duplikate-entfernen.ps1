# (c) 2026 Herbert Stoecker. Kostenlos nutzbar. Bitte nur als Link auf die offizielle Download-Seite weitergeben; Verkauf und Veroeffentlichung geaenderter Fassungen nur mit Zustimmung.
<#
.SYNOPSIS
  Entfernt Duplikate in der Bibliothek (Ziel). Grundlage ist die neueste Inventur:
  In jeder Duplikat-Gruppe bleibt ein Exemplar ("behalten"), die als "entfernbar" markierten
  Exemplare gehen in den Papierkorb.

  Sicherheit:
  - Unmittelbar vorher wird erneut geprueft, ob Datei und behaltenes Exemplar noch existieren
    und denselben Inhalt haben (Pruefsumme). Sonst bleibt die Datei liegen.
  - Exemplare in Drum-Kits und Construction Kits werden nie entfernt.
  - Vorschau und Rueckfrage (Standard: Nein). Leer gewordene Ordner werden mit entfernt.

.BENUTZUNG
    -Duplikate                 inhaltsgleiche Dateien (Standard, wenn keine Gruppe angegeben ist)
    -Formate -Formatliste "RX2,MP3,AIFF"
                               RX2/MP3/AIFF neben einer gleichnamigen WAV im selben Pack (2.3.3)
    -NurVorschau   nur Vorschau, keine Frage
    -Ausfuehren    ohne Frage entfernen
#>
[CmdletBinding()]
param(
    [switch]$Duplikate,
    [switch]$Formate,
    [string]$Formatliste = 'RX2,MP3,AIFF',
    [switch]$NurVorschau,
    [switch]$Ausfuehren
)

$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'Gemeinsam.ps1')
$Zeitstempel = Get-Date -Format 'yyyy-MM-dd_HHmmss'
$einst = Get-Einstellungen
$Ziel = $einst.Ziel.TrimEnd('\', '/')
Write-Host "Ziel aufraeumen: Duplikate und Formate (Samples-Werkzeuge $ProgrammVersion)" -ForegroundColor Cyan
Write-Host "  Bibliothek (Ziel): $Ziel"
Write-Host ""

$inv = Get-NeuesteInventur 'Sample'
if (-not $inv) { throw "Die Sample-Bibliothek wurde noch nicht eingelesen. Bitte zuerst 'Bibliothek oeffnen' und neu einlesen." }
Write-Host "Grundlage: $($inv.Name)"
$alter = (Get-Date) - $inv.LastWriteTime
if ($alter.TotalHours -ge 24) { Write-Host ("Hinweis: Der Stand der Sample-Bibliothek ist {0:N0} Tage alt. Fuer ein genaues Ergebnis vorher neu einlesen (Bibliothek oeffnen)." -f $alter.TotalDays) -ForegroundColor Yellow }

if (-not $Duplikate -and -not $Formate) { $Duplikate = $true }
$alleZeilen = @(Import-Csv -LiteralPath $inv.FullName -Delimiter ';' -Encoding UTF8)
$zeilen = @($alleZeilen | Where-Object { $_.'Duplikat-Gruppe' })
$gruppen = @(); if ($Duplikate) { $gruppen = @($zeilen | Group-Object 'Duplikat-Gruppe') }
$ergebnis = New-Object System.Collections.Generic.List[object]
$gNr = 0; $zeit = Get-Date
foreach ($g in $gruppen) {
    $gNr++
    if (((Get-Date) - $zeit).TotalSeconds -ge 5) { Write-Host "  ... pruefe Gruppe $gNr von $(@($gruppen).Count)" -ForegroundColor DarkGray; $zeit = Get-Date }
    $behalten = @($g.Group | Where-Object { $_.'Duplikat-Rolle' -eq 'behalten' }) | Select-Object -First 1
    foreach ($x in ($g.Group | Where-Object { $_.'Duplikat-Rolle' -eq 'entfernbar' })) {
        $datei = Join-Path $Ziel $x.Pfad
        $orig  = if ($behalten) { Join-Path $Ziel $behalten.Pfad } else { '' }
        $status = ''
        if ($x.Typ -eq 'Kit') { $status = 'Uebersprungen: liegt in einem Kit' }
        elseif (-not (Test-Datei $datei)) { $status = 'Uebersprungen: Datei existiert nicht mehr' }
        elseif (-not $orig -or -not (Test-Datei $orig)) { $status = 'Uebersprungen: behaltenes Exemplar nicht gefunden' }
        else {
            $h1 = Get-DateiPruefsumme $datei 'SHA256'
            $h2 = Get-DateiPruefsumme $orig 'SHA256'
            $status = if ($h1 -eq $h2) { 'Wird entfernt' } else { 'Uebersprungen: Inhalt weicht inzwischen ab' }
        }
        $ergebnis.Add([pscustomobject]@{
            Status = $status; Art = 'Duplikat'; Gruppe = $g.Name; Datei = $x.Pfad; Pack = $x.Pack; 'Behalten wird' = $(if ($behalten) { $behalten.Pfad } else { '' })
            GroesseMB = [math]::Round([double]$x.GroesseBytes / 1MB, 2)
        })
    }
}

# 2.3.3: Formate - RX2/MP3/AIFF neben einer gleichnamigen WAV im selben Pack (Kits ausgenommen)
$fmtEndungen = @()
if ($Formate) {
    foreach ($f in ($Formatliste -split '[,; ]+' | Where-Object { $_ })) {
        switch ($f.ToUpperInvariant()) { 'RX2' { $fmtEndungen += 'RX2', 'REX' } 'MP3' { $fmtEndungen += 'MP3' } 'AIFF' { $fmtEndungen += 'AIF', 'AIFF' } }
    }
    $wavs = @{}
    foreach ($z in $alleZeilen) { if ($z.Format -eq 'WAV') { $wavs[($z.Pack + '|' + [IO.Path]::GetFileNameWithoutExtension($z.Datei)).ToLowerInvariant()] = $z } }
    foreach ($z in $alleZeilen) {
        if ($fmtEndungen -notcontains ([string]$z.Format).ToUpperInvariant()) { continue }
        $w = $wavs[($z.Pack + '|' + [IO.Path]::GetFileNameWithoutExtension($z.Datei)).ToLowerInvariant()]
        if (-not $w) { continue }
        $datei = Join-Path $Ziel $z.Pfad; $wav = Join-Path $Ziel $w.Pfad
        $status = if ($z.Typ -eq 'Kit') { 'Uebersprungen: liegt in einem Kit' }
                  elseif (-not (Test-Datei $datei)) { 'Uebersprungen: Datei existiert nicht mehr' }
                  elseif (-not (Test-Datei $wav)) { 'Uebersprungen: WAV nicht (mehr) vorhanden' }
                  else { 'Wird entfernt' }
        $ergebnis.Add([pscustomobject]@{
            Status = $status; Art = 'Format'; Gruppe = $z.Format; Datei = $z.Pfad; Pack = $z.Pack; 'Behalten wird' = $w.Pfad
            GroesseMB = [math]::Round([double]$z.GroesseBytes / 1MB, 2)
        })
    }
}

$weg = @($ergebnis | Where-Object { $_.Status -eq 'Wird entfernt' })
Write-Host ""
Write-Host "==================== Zusammenfassung ====================" -ForegroundColor Yellow
if ($Duplikate) { Write-Host ("Duplikat-Gruppen:                 {0,7}" -f @($gruppen).Count) }
if ($Formate) { Write-Host ("Formate neben gleichnamiger WAV:  {0,7}   ({1})" -f @($ergebnis | Where-Object { $_.Art -eq 'Format' }).Count, $Formatliste) }
if (-not $ergebnis.Count) { Write-Host "  0 - nichts gefunden" }
$ergebnis | Group-Object Art, Status | Sort-Object Name | ForEach-Object { "{0,-55} {1,7}" -f ($_.Name.Replace(', ', ': ') + ':'), $_.Count } | Write-Host
Write-Host ("Frei werdender Platz: {0:N1} MB" -f [double](($weg | Measure-Object GroesseMB -Sum).Sum))

$vorschauPfad = Join-Path $protokollOrdner "Ziel-Duplikate-Vorschau_$Zeitstempel.csv"
$ergebnis | Export-Csv -LiteralPath $vorschauPfad -NoTypeInformation -Delimiter ';' -Encoding UTF8
Write-Host ""
Write-Host "Vorschau gespeichert (zeigt nur, was passieren wuerde):" -ForegroundColor Green
Write-Host "  $vorschauPfad"

if ($weg.Count -eq 0) { Write-Host ""; Write-Host "Es gibt nichts zu entfernen." -ForegroundColor Green; return }
$warnung = Get-PapierkorbWarnung $Ziel ([long](($weg | Measure-Object GroesseMB -Sum).Sum * 1MB))
if ($warnung) { Write-Host ""; Write-Host "ACHTUNG: $warnung" -ForegroundColor Red }
if ($Ausfuehren -and $warnung) { Write-Host "Ohne Rueckfrage wird in diesem Fall nichts entfernt." -ForegroundColor Yellow; return }
if (-not $Ausfuehren) {
    if ($NurVorschau) { Write-Host "Es wurde nichts entfernt."; return }
    Write-Host ""
    $nD = @($weg | Where-Object { $_.Art -eq 'Duplikat' }).Count; $nF = @($weg | Where-Object { $_.Art -eq 'Format' }).Count
    if (-not (Read-JaNein "Jetzt $($weg.Count) Dateien ($nD Duplikate, $nF Formate neben WAV) aus der Bibliothek in den Papierkorb verschieben?")) {
        Write-Host ""; Write-Host "Abgebrochen. Es wurde nichts entfernt." -ForegroundColor Yellow; return
    }
}

$ok = 0; $fehler = 0
$ordner = New-Object System.Collections.Generic.HashSet[string]
Write-Host ""
Write-Host "Verschiebe $($weg.Count) Dateien in den Papierkorb ..." -ForegroundColor Cyan
$i = 0; $zeit = Get-Date
foreach ($x in $weg) {
    $i++
    if ($i % 20 -eq 0 -or $i -eq $weg.Count) { Write-Progress -Activity 'In den Papierkorb' -Status "$i von $($weg.Count)" -PercentComplete ($i * 100 / $weg.Count) }
    if (((Get-Date) - $zeit).TotalSeconds -ge 5) { Write-Host "  ... $i von $($weg.Count)" -ForegroundColor DarkGray; $zeit = Get-Date }
    $datei = Join-Path $Ziel $x.Datei
    try {
        Send-Papierkorb $datei
        $asd = $datei + '.asd'
        if (Test-Datei $asd) { Send-Papierkorb $asd }
        $x.Status = 'In Papierkorb verschoben'; $ok++
        [void]$ordner.Add((Split-Path -Parent $datei))
    } catch { $x.Status = 'FEHLER: ' + $_.Exception.Message; $fehler++ }
}
Write-Progress -Activity 'In den Papierkorb' -Completed
Write-Host "Entferne leer gewordene Ordner ..." -ForegroundColor Cyan
# Leer gewordene Ordner entfernen (nie den Zielordner selbst)
$leer = 0
$ordnerListe = @($ordner | Sort-Object { $_.Length } -Descending)
$i = 0; $zeit = Get-Date
foreach ($o in $ordnerListe) {
    $i++
    if ($i % 20 -eq 0 -or $i -eq $ordnerListe.Count) { Write-Progress -Activity 'Leere Ordner pruefen' -Status "$i von $($ordnerListe.Count)" -PercentComplete ($i * 100 / $ordnerListe.Count) }
    if (((Get-Date) - $zeit).TotalSeconds -ge 5) { Write-Host "  ... Leere Ordner pruefen: $i von $($ordnerListe.Count)" -ForegroundColor DarkGray; $zeit = Get-Date }
    $akt = $o
    while ($akt -and $akt.Length -gt $Ziel.Length -and (Test-Ordner $akt)) {
        try { if (@([IO.Directory]::EnumerateFileSystemEntries((Get-LangPfad $akt))).Count -gt 0) { break } } catch { break }
        try { Send-Papierkorb $akt; $leer++ } catch { break }
        $akt = Split-Path -Parent $akt
    }
}
Write-Progress -Activity 'Leere Ordner pruefen' -Completed
$csvPfad = Join-Path $protokollOrdner "Ziel-Duplikate-entfernt_$Zeitstempel.csv"
$ergebnis | Export-Csv -LiteralPath $csvPfad -NoTypeInformation -Delimiter ';' -Encoding UTF8
try { $zp = Get-ZielProtokollOrdner $Ziel; [void][IO.Directory]::CreateDirectory($zp); Copy-Item -LiteralPath $csvPfad -Destination $zp } catch { }   # 4.0.1: auch im Ziel (Stand im Hauptfenster)
Write-Host ""
Write-Host "Fertig. In den Papierkorb verschoben: $ok Dateien | leere Ordner entfernt: $leer | Fehler: $fehler" -ForegroundColor Green
Write-Host "Protokoll: $csvPfad"
Write-Host "Bitte danach die Sample-Bibliothek neu einlesen, damit Liste und Bericht den neuen Stand zeigen."
