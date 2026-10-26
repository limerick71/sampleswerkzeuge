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
    -NurVorschau   nur Vorschau, keine Frage
    -Ausfuehren    ohne Frage entfernen
#>
[CmdletBinding()]
param(
    [switch]$NurVorschau,
    [switch]$Ausfuehren
)

$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'Gemeinsam.ps1')
$Zeitstempel = Get-Date -Format 'yyyy-MM-dd_HHmmss'
$einst = Get-Einstellungen
$Ziel = $einst.Ziel.TrimEnd('\', '/')
Write-Host "Duplikate im Ziel entfernen (Samples-Werkzeuge $ProgrammVersion)" -ForegroundColor Cyan
Write-Host "  Bibliothek (Ziel): $Ziel"
Write-Host ""

$inv = Get-NeuesteInventur 'Sample'
if (-not $inv) { throw "Noch keine Inventur vorhanden. Bitte zuerst 'Inventur starten'." }
Write-Host "Grundlage: $($inv.Name)"
$alter = (Get-Date) - $inv.LastWriteTime
if ($alter.TotalHours -ge 24) { Write-Host ("Hinweis: Die Inventur ist {0:N0} Tage alt. Fuer ein genaues Ergebnis vorher eine neue Inventur starten." -f $alter.TotalDays) -ForegroundColor Yellow }

$zeilen = @(Import-Csv -LiteralPath $inv.FullName -Delimiter ';' -Encoding UTF8 | Where-Object { $_.'Duplikat-Gruppe' })
$gruppen = $zeilen | Group-Object 'Duplikat-Gruppe'
$ergebnis = New-Object System.Collections.Generic.List[object]
foreach ($g in $gruppen) {
    $behalten = @($g.Group | Where-Object { $_.'Duplikat-Rolle' -eq 'behalten' }) | Select-Object -First 1
    foreach ($x in ($g.Group | Where-Object { $_.'Duplikat-Rolle' -eq 'entfernbar' })) {
        $datei = Join-Path $Ziel $x.Pfad
        $orig  = if ($behalten) { Join-Path $Ziel $behalten.Pfad } else { '' }
        $status = ''
        if ($x.Typ -eq 'Kit') { $status = 'Uebersprungen: liegt in einem Kit' }
        elseif (-not (Test-Path -LiteralPath $datei)) { $status = 'Uebersprungen: Datei existiert nicht mehr' }
        elseif (-not $orig -or -not (Test-Path -LiteralPath $orig)) { $status = 'Uebersprungen: behaltenes Exemplar nicht gefunden' }
        else {
            $h1 = (Get-FileHash -LiteralPath $datei -Algorithm SHA256).Hash
            $h2 = (Get-FileHash -LiteralPath $orig -Algorithm SHA256).Hash
            $status = if ($h1 -eq $h2) { 'Wird entfernt' } else { 'Uebersprungen: Inhalt weicht inzwischen ab' }
        }
        $ergebnis.Add([pscustomobject]@{
            Status = $status; Gruppe = $g.Name; Datei = $x.Pfad; Pack = $x.Pack; 'Behalten wird' = $(if ($behalten) { $behalten.Pfad } else { '' })
            GroesseMB = [math]::Round([double]$x.GroesseBytes / 1MB, 2)
        })
    }
}

$weg = @($ergebnis | Where-Object { $_.Status -eq 'Wird entfernt' })
Write-Host ""
Write-Host "==================== Zusammenfassung ====================" -ForegroundColor Yellow
Write-Host ("Duplikat-Gruppen:                 {0,7}" -f @($gruppen).Count)
$ergebnis | Group-Object Status | ForEach-Object { "{0,-45} {1,7}" -f ($_.Name + ':'), $_.Count } | Write-Host
Write-Host ("Frei werdender Platz: {0:N1} MB" -f (($weg | Measure-Object GroesseMB -Sum).Sum))

$vorschauPfad = Join-Path $protokollOrdner "Ziel-Duplikate-Vorschau_$Zeitstempel.csv"
$ergebnis | Export-Csv -LiteralPath $vorschauPfad -NoTypeInformation -Delimiter ';' -Encoding UTF8
Write-Host ""
Write-Host "Vorschau gespeichert (zeigt nur, was passieren wuerde):" -ForegroundColor Green
Write-Host "  $vorschauPfad"

if ($weg.Count -eq 0) { Write-Host ""; Write-Host "Es gibt nichts zu entfernen." -ForegroundColor Green; return }
if (-not $Ausfuehren) {
    if ($NurVorschau) { Write-Host "Es wurde nichts entfernt."; return }
    Write-Host ""
    if (-not (Read-JaNein "Jetzt $($weg.Count) doppelte Dateien aus der Bibliothek in den Papierkorb verschieben?")) {
        Write-Host ""; Write-Host "Abgebrochen. Es wurde nichts entfernt." -ForegroundColor Yellow; return
    }
}

$ok = 0; $fehler = 0
$ordner = New-Object System.Collections.Generic.HashSet[string]
foreach ($x in $weg) {
    $datei = Join-Path $Ziel $x.Datei
    try {
        Send-Papierkorb $datei
        $asd = $datei + '.asd'
        if (Test-Path -LiteralPath $asd) { Send-Papierkorb $asd }
        $x.Status = 'In Papierkorb verschoben'; $ok++
        [void]$ordner.Add((Split-Path -Parent $datei))
    } catch { $x.Status = 'FEHLER: ' + $_.Exception.Message; $fehler++ }
}
# Leer gewordene Ordner entfernen (nie den Zielordner selbst)
$leer = 0
foreach ($o in ($ordner | Sort-Object { $_.Length } -Descending)) {
    $akt = $o
    while ($akt -and $akt.Length -gt $Ziel.Length -and (Test-Path -LiteralPath $akt)) {
        if (@(Get-ChildItem -LiteralPath $akt -Force).Count -gt 0) { break }
        try { Send-Papierkorb $akt; $leer++ } catch { break }
        $akt = Split-Path -Parent $akt
    }
}
$csvPfad = Join-Path $protokollOrdner "Ziel-Duplikate-entfernt_$Zeitstempel.csv"
$ergebnis | Export-Csv -LiteralPath $csvPfad -NoTypeInformation -Delimiter ';' -Encoding UTF8
Write-Host ""
Write-Host "Fertig. In den Papierkorb verschoben: $ok Dateien | leere Ordner entfernt: $leer | Fehler: $fehler" -ForegroundColor Green
Write-Host "Protokoll: $csvPfad"
Write-Host "Bitte danach 'Inventur starten', damit Liste und Bericht den neuen Stand zeigen."
