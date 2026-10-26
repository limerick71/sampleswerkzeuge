<#
.SYNOPSIS
  Entfernt in "E:\Sounds und Samples" die doppelten Samples, also genau die Dateien,
  die Samples-sortieren.ps1 beim Kopieren als "Duplikat - uebersprungen" markiert hat.

  Sicherheit:
  - Grundlage ist das neueste Protokoll_*.csv (bzw. Vorschau_*.csv) im Skript-Ordner.
  - Vor jedem Loeschen wird geprueft, ob das behaltene Original noch existiert
    und per Hash denselben Inhalt hat. Sonst bleibt die Datei liegen.
  - Nur Audiodateien werden entfernt (Lizenztexte o. ae. bleiben in jedem Pack).
  - Die Dateien gehen in den PAPIERKORB, nicht endgueltig weg.
  - Die zugehoerige Ableton-Analysedatei (.asd) geht mit in den Papierkorb.
  - Ordner, die dadurch komplett leer werden, werden entfernt.

.BENUTZUNG
  1) Vorschau (loescht nichts):
       powershell -ExecutionPolicy Bypass -File "E:\Sounds und Samples\_Sortier-Skript\Duplikate-entfernen.ps1"
  2) Wirklich in den Papierkorb verschieben:
       powershell -ExecutionPolicy Bypass -File "E:\Sounds und Samples\_Sortier-Skript\Duplikate-entfernen.ps1" -Ausfuehren
#>
[CmdletBinding()]
param(
    [string]$Quelle = 'E:\Sounds und Samples',
    [string]$Protokoll = '',
    [switch]$Ausfuehren
)

$ErrorActionPreference = 'Stop'
$SkriptOrdner = Split-Path -Parent $MyInvocation.MyCommand.Path
$Zeitstempel  = Get-Date -Format 'yyyy-MM-dd_HHmmss'
$Quelle = $Quelle.TrimEnd('\','/')
$RxAudio = '\.(wav|aiff?|mp3|flac|ogg|rx2|rex|m4a)$'

# --- Protokoll finden --------------------------------------------------------
if (-not $Protokoll) {
    $p = Get-ChildItem -LiteralPath $SkriptOrdner -Filter 'Protokoll_*.csv' | Sort-Object Name | Select-Object -Last 1
    if (-not $p) { $p = Get-ChildItem -LiteralPath $SkriptOrdner -Filter 'Vorschau_*.csv' | Sort-Object Name | Select-Object -Last 1 }
    if (-not $p) { throw "Kein Protokoll_*.csv oder Vorschau_*.csv im Ordner '$SkriptOrdner' gefunden. Bitte zuerst Samples-sortieren.ps1 ausfuehren." }
    $Protokoll = $p.FullName
}
Write-Host "Verwende Protokoll: $Protokoll" -ForegroundColor Cyan
$zeilen = Import-Csv -LiteralPath $Protokoll -Delimiter ';' -Encoding UTF8
$dups = @($zeilen | Where-Object { $_.Aktion -like 'Duplikat*' })
Write-Host "Im Protokoll als Duplikat markiert: $($dups.Count) Dateien"

# --- Pruefen -----------------------------------------------------------------
$ergebnis = New-Object System.Collections.Generic.List[object]
foreach ($d in $dups) {
    $datei = $d.Quelle
    $original = ''
    if ($d.ZielRel -match '^\(identisch mit (.+)\)$') { $original = $Matches[1] }
    $status = ''
    if (-not $datei.StartsWith($Quelle, [StringComparison]::OrdinalIgnoreCase)) { $status = 'Uebersprungen: liegt nicht im Quellordner' }
    elseif ($datei -notmatch $RxAudio)                 { $status = 'Uebersprungen: keine Audiodatei (bleibt im Pack)' }
    elseif (-not (Test-Path -LiteralPath $datei))      { $status = 'Uebersprungen: Datei existiert nicht mehr' }
    elseif (-not $original -or -not (Test-Path -LiteralPath $original)) { $status = 'Uebersprungen: Original nicht gefunden' }
    elseif ($original -eq $datei)                      { $status = 'Uebersprungen: Original = Datei' }
    else {
        $h1 = (Get-FileHash -LiteralPath $datei -Algorithm SHA256).Hash
        $h2 = (Get-FileHash -LiteralPath $original -Algorithm SHA256).Hash
        if ($h1 -ne $h2) { $status = 'Uebersprungen: Inhalt weicht vom Original ab' }
        else { $status = 'Wird entfernt' }
    }
    $ergebnis.Add([pscustomobject]@{ Status = $status; Datei = $datei; BehaltenesOriginal = $original; GroesseMB = $d.GroesseMB })
}

$weg = @($ergebnis | Where-Object { $_.Status -eq 'Wird entfernt' })
Write-Host ""
Write-Host "==================== Zusammenfassung ====================" -ForegroundColor Yellow
$ergebnis | Group-Object Status | ForEach-Object { "{0,-50} {1,5} Dateien" -f $_.Name, $_.Count } | Write-Host
$mb = ($weg | ForEach-Object { [double]($_.GroesseMB -replace ',', '.') } | Measure-Object -Sum).Sum
Write-Host ("Frei werdender Platz: {0:N1} MB" -f $mb)

$csvName = if ($Ausfuehren) { "Duplikate-entfernt_$Zeitstempel.csv" } else { "Duplikate-Vorschau_$Zeitstempel.csv" }
$csvPfad = [IO.Path]::Combine($SkriptOrdner, $csvName)

if (-not $Ausfuehren) {
    $ergebnis | Export-Csv -LiteralPath $csvPfad -NoTypeInformation -Delimiter ';' -Encoding UTF8
    Write-Host ""
    Write-Host "VORSCHAU erstellt (es wurde nichts geloescht):" -ForegroundColor Green
    Write-Host "  $csvPfad"
    Write-Host "Zum Entfernen das Skript mit dem Schalter -Ausfuehren starten."
    return
}

# --- In den Papierkorb verschieben -------------------------------------------
Add-Type -AssemblyName Microsoft.VisualBasic
function Send-Papierkorb([string]$Pfad) {
    [Microsoft.VisualBasic.FileIO.FileSystem]::DeleteFile($Pfad,
        [Microsoft.VisualBasic.FileIO.UIOption]::OnlyErrorDialogs,
        [Microsoft.VisualBasic.FileIO.RecycleOption]::SendToRecycleBin)
}

$ok = 0; $fehler = 0
$ordner = New-Object System.Collections.Generic.HashSet[string]
foreach ($x in $weg) {
    try {
        Send-Papierkorb $x.Datei
        $asd = $x.Datei + '.asd'
        if (Test-Path -LiteralPath $asd) { Send-Papierkorb $asd }
        $x.Status = 'In Papierkorb verschoben'; $ok++
        [void]$ordner.Add((Split-Path -Parent $x.Datei))
    } catch {
        $x.Status = 'FEHLER: ' + $_.Exception.Message; $fehler++
    }
}

# Leer gewordene Ordner entfernen (nur wenn wirklich leer, ggf. bis auf .DS_Store)
$leer = 0
foreach ($o in ($ordner | Sort-Object { $_.Length } -Descending)) {
    $akt = $o
    while ($akt -and $akt.Length -gt $Quelle.Length -and (Test-Path -LiteralPath $akt)) {
        $inhalt = @(Get-ChildItem -LiteralPath $akt -Force | Where-Object { $_.Name -ne '.DS_Store' })
        if ($inhalt.Count -gt 0) { break }
        try { Send-Papierkorb (Join-Path $akt '.DS_Store') } catch {}
        try {
            [Microsoft.VisualBasic.FileIO.FileSystem]::DeleteDirectory($akt,
                [Microsoft.VisualBasic.FileIO.UIOption]::OnlyErrorDialogs,
                [Microsoft.VisualBasic.FileIO.RecycleOption]::SendToRecycleBin)
            $leer++
        } catch { break }
        $akt = Split-Path -Parent $akt
    }
}

$ergebnis | Export-Csv -LiteralPath $csvPfad -NoTypeInformation -Delimiter ';' -Encoding UTF8
Write-Host ""
Write-Host "Fertig. In den Papierkorb verschoben: $ok Dateien | leere Ordner entfernt: $leer | Fehler: $fehler" -ForegroundColor Green
Write-Host "Protokoll: $csvPfad"
Write-Host "Wiederherstellen ist ueber den Windows-Papierkorb moeglich."
