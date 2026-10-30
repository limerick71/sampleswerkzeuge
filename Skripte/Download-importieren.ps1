# (c) 2026 Herbert Stoecker. Kostenlos nutzbar. Bitte nur als Link auf die offizielle Download-Seite weitergeben; Verkauf und Veroeffentlichung geaenderter Fassungen nur mit Zustimmung.
<#
.SYNOPSIS
  Download importieren (Version 3, IMP-01 bis IMP-10): frisch heruntergeladene Sample-Packs aus dem
  Download-Ordner in einem Schritt entpacken, nach den Regeln von "Samples sortieren" einsortieren und
  das Original danach ins Download-Archiv verschieben, im Download-Ordner lassen oder in den Papierkorb legen.

  Ablauf: ZIP in einen Arbeitsordner entpacken (Pruefsumme je Datei, ohne Programme, macOS-Reste und
  unsichere Pfade) -> Vorschau wie beim Sortieren -> Frage "J" -> kopieren -> jede Datei im Ziel per
  Pruefsumme bestaetigen -> erst dann das Original verschieben/loeschen -> Arbeitsordner entfernen.
  Ein Pack, bei dem etwas nicht stimmt, bleibt im Download-Ordner liegen.

.BENUTZUNG
    -Auswahl "Pack A.zip|Pack B"     Namen im Download-Ordner (Trennzeichen |)
    -Original Archiv|Behalten|Papierkorb
    -NurVorschau                       nur Vorschau, nichts kopieren
    -Ausfuehren                        ohne Frage ausfuehren
#>
[CmdletBinding()]
param(
    [string]$Auswahl = '',
    [ValidateSet('Archiv', 'Behalten', 'Papierkorb')][string]$Original = 'Archiv',
    [switch]$NurVorschau,
    [switch]$Ausfuehren
)

$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'Gemeinsam.ps1')
. (Join-Path $PSScriptRoot 'Import.ps1')
$start = Get-Date
$Zeitstempel = $start.ToString('yyyy-MM-dd_HHmmss')
$einst = Get-Einstellungen
$dl = ([string]$einst.Downloads).TrimEnd('\', '/')
$archiv = ([string]$einst.DownloadArchiv).TrimEnd('\', '/')
$Ziel = ([string]$einst.Ziel).TrimEnd('\', '/')
Write-Host "Download importieren (Samples-Werkzeuge $ProgrammVersion)" -ForegroundColor Cyan
Write-Host "  Download-Ordner: $dl"
Write-Host "  Ziel:            $Ziel"
$OriginalText = @{ Archiv = "ins Download-Archiv verschieben ($archiv)"; Behalten = 'im Download-Ordner lassen'; Papierkorb = 'in den Papierkorb legen' }
Write-Host "  Danach mit dem Original: $($OriginalText[$Original])"
Write-Host ""

if (-not (Test-Path -LiteralPath $dl -PathType Container)) { throw "Download-Ordner nicht gefunden: $dl (unter Einstellungen aendern)" }
$zs = Get-OrdnerStatus $Ziel
if ($zs.Fehlt) { throw "Ziel nicht erreichbar: $($zs.Text)" }

# Kandidaten bestimmen und Auswahl pruefen
$namen = @($Auswahl -split '\|' | Where-Object { $_ })
$alle = @(Get-ImportKandidaten)
$packs = @(foreach ($n in $namen) {
    $k = $alle | Where-Object { $_.Name -eq $n } | Select-Object -First 1
    if (-not $k) { Write-Host "  nicht gefunden oder kein Sample-Pack, wird ausgelassen: $n" -ForegroundColor Yellow; continue }
    if (-not $k.Anhakbar) { Write-Host "  wird ausgelassen: $n ($($k.Hinweis))" -ForegroundColor Yellow; continue }
    $k
})
if (-not $packs.Count) { Write-Host "Es ist kein importierbares Pack ausgewaehlt." -ForegroundColor Yellow; return }

# Arbeitsordner neben dem Ziel (gleiches Laufwerk, nicht im Ziel); ist das Ziel ein ganzes Laufwerk, im TEMP-Ordner
$zielEltern = [IO.Path]::GetDirectoryName($Ziel)
$arbeitBasis = if ($zielEltern) { $zielEltern } else { [IO.Path]::GetTempPath() }
$arbeit = Join-Path $arbeitBasis "_Samples-Werkzeuge_Import_$Zeitstempel"

# Speicherplatz (IMP-10): entpackte Groesse im Arbeitsordner, dazu die Kopie im Ziel
$bedarf = [long](($packs | Where-Object { $_.Art -eq 'ZIP' } | Measure-Object Bytes -Sum).Sum)
try {
    $lwA = [IO.DriveInfo]::new([IO.Path]::GetPathRoot($arbeit)); $lwZ = [IO.DriveInfo]::new([IO.Path]::GetPathRoot($Ziel))
    $noetig = $bedarf * 1.05; if ($lwA.Name -eq $lwZ.Name) { $noetig = ($bedarf + ($packs | Measure-Object Bytes -Sum).Sum) * 1.05 }
    if ($lwA.AvailableFreeSpace -lt $noetig) {
        throw ("Zu wenig Speicher auf {0}: frei {1:N1} GB, noetig etwa {2:N1} GB (Entpacken und Kopieren)." -f $lwA.Name, ($lwA.AvailableFreeSpace / 1GB), ($noetig / 1GB))
    }
} catch [System.Management.Automation.RuntimeException] { throw } catch { }

$protokoll = New-Object System.Collections.Generic.List[object]
function Add-Zeile($p, [string]$ergebnis, [string]$orig, [string]$hinweis) {
    $protokoll.Add([pscustomobject][ordered]@{ Download = $p.Name; Art = $p.Art; Pack = $p.PackName; Audiodateien = $p.Audio; Ergebnis = $ergebnis; Original = $orig; Hinweis = $hinweis })
}

try {
    # -----------------------------------------------------------------------
    # 1) Entpacken (IMP-04, IMP-05)
    # -----------------------------------------------------------------------
    $belegt = @{}
    foreach ($p in $packs) {
        $pn = Get-ImportPackName $p.Name; $z = 2; $basisName = $pn
        while ($belegt.ContainsKey($pn.ToLowerInvariant())) { $pn = "$basisName ($z)"; $z++ }
        $belegt[$pn.ToLowerInvariant()] = $true
        $p | Add-Member NoteProperty PackName $pn -Force
        $p | Add-Member NoteProperty Quelle $(if ($p.Art -eq 'ZIP') { Join-Path $arbeit $pn } else { $p.Pfad }) -Force
        $p | Add-Member NoteProperty Fehler '' -Force
    }
    $zips = @($packs | Where-Object { $_.Art -eq 'ZIP' })
    if ($zips.Count) {
        Write-Host "Entpacke $($zips.Count) Archiv(e) in den Arbeitsordner ..." -ForegroundColor Cyan
        Write-Host "  $arbeit" -ForegroundColor DarkGray
        [void][IO.Directory]::CreateDirectory((Get-LangPfad $arbeit))
    }
    $i = 0
    foreach ($p in $zips) {
        $i++
        Write-Progress -Activity 'Entpacken' -Status "$i / $($zips.Count): $($p.Name)" -PercentComplete ($i * 100 / $zips.Count)
        $r = [SamplesWerkzeuge.ZipWerkzeug300]::Entpacken($p.Pfad, $p.Quelle, 200GB)
        if ($r.Fehler) { $p.Fehler = $r.Fehler; Write-Host "  $($p.Name): nicht entpackt - $($r.Fehler)" -ForegroundColor Red; continue }
        $anz = $r.Dateien
        # ZIP im ZIP: daneben in einen gleichnamigen Ordner entpacken (hoechstens 3 Ebenen), dann die innere ZIP-Datei entfernen
        $offen = New-Object System.Collections.Generic.Queue[object]
        foreach ($a in $r.Archive) { $offen.Enqueue(@($a, 1)) }
        while ($offen.Count -and -not $p.Fehler) {
            $e = $offen.Dequeue(); $innen = [string]$e[0]
            if ([int]$e[1] -gt 3) { continue }
            $zielInnen = Join-Path ([IO.Path]::GetDirectoryName($innen)) ([IO.Path]::GetFileNameWithoutExtension($innen))
            $r2 = [SamplesWerkzeuge.ZipWerkzeug300]::Entpacken($innen, $zielInnen, 200GB)
            if ($r2.Fehler) { Write-Host "  $($p.Name): inneres Archiv $([IO.Path]::GetFileName($innen)) nicht entpackt - $($r2.Fehler)" -ForegroundColor Yellow; continue }
            foreach ($u in $r2.Uebersprungen) { $r.Uebersprungen.Add($u) }
            $anz += $r2.Dateien - 1
            [IO.File]::Delete((Get-LangPfad $innen))
            foreach ($a in $r2.Archive) { $offen.Enqueue(@($a, ([int]$e[1] + 1))) }
        }
        $txt = "  $($p.Name): $anz Dateien entpackt"
        if ($r.Uebersprungen.Count) { $txt += ", nicht uebernommen: " + (($r.Uebersprungen | Select-Object -First 5) -join '; ') + $(if ($r.Uebersprungen.Count -gt 5) { " und $($r.Uebersprungen.Count - 5) weitere" } else { '' }) }
        Write-Host $txt
    }
    Write-Progress -Activity 'Entpacken' -Completed
    foreach ($p in @($packs | Where-Object { $_.Fehler })) { Add-Zeile $p 'nicht importiert' 'bleibt im Download-Ordner' $p.Fehler }
    $gut = @($packs | Where-Object { -not $_.Fehler })
    if (-not $gut.Count) { Write-Host "Kein Pack konnte entpackt werden." -ForegroundColor Red; return }

    # -----------------------------------------------------------------------
    # 2) Vorschau und Sortieren mit den Regeln von "Samples sortieren" (IMP-06, IMP-07)
    # -----------------------------------------------------------------------
    Write-Host ""
    Write-Host "Danach mit den Originalen ($($OriginalText[$Original])), nur wenn alles im Ziel bestaetigt ist:" -ForegroundColor Cyan
    foreach ($p in $gut) { Write-Host "  $($p.Name)  ->  Pack '$($p.PackName)'" }
    Write-Host ""
    $quellText = ($gut | ForEach-Object { "$($_.Quelle)*Pack" }) -join '|'
    $frageZusatz = switch ($Original) { 'Archiv' { 'die Originale ins Download-Archiv verschieben' } 'Papierkorb' { 'die Originale in den Papierkorb legen' } default { 'die Originale im Download-Ordner lassen' } }
    $sArg = @{ Quellen = $quellText; Frage = $frageZusatz; ImmerProtokoll = $true }
    if ($NurVorschau) { $sArg.NurVorschau = $true }
    if ($Ausfuehren) { $sArg.Ausfuehren = $true }
    & (Join-Path $PSScriptRoot 'Samples-sortieren.ps1') @sArg

    $prot = @(Get-ChildItem -LiteralPath $protokollOrdner -Filter 'Protokoll_*.csv' -File -ErrorAction SilentlyContinue | Where-Object { $_.LastWriteTime -ge $start } | Sort-Object LastWriteTime -Descending) | Select-Object -First 1
    if (-not $prot) {
        Write-Host ""
        Write-Host "Es wurde nichts importiert; die Downloads bleiben unveraendert." -ForegroundColor Yellow
        return
    }

    # -----------------------------------------------------------------------
    # 3) Jede Datei im Ziel per Pruefsumme bestaetigen, dann das Original behandeln (IMP-08)
    # -----------------------------------------------------------------------
    Write-Host ""
    Write-Host "Pruefe die Kopien im Ziel (Pruefsumme) ..." -ForegroundColor Cyan
    $zeilen = @(Import-Csv -LiteralPath $prot.FullName -Delimiter ';' -Encoding UTF8)
    $nachQuelle = @{}; foreach ($z in $zeilen) { $nachQuelle[$z.Quelle] = $z }
    $status = @{}
    $pruefe = { param($z)
        $a = [string]$z.Aktion
        if ($a -like 'kopiert*' -or $a -like 'bereits im Ziel*') {
            if (-not $z.Ziel -or -not (Test-Datei $z.Ziel)) { return 'Kopie fehlt im Ziel' }
            if ((Get-DateiPruefsumme $z.Quelle) -ne (Get-DateiPruefsumme $z.Ziel)) { return 'Inhalt im Ziel abweichend' }
            return ''
        }
        if ($a -like 'Duplikat in der Quelle*') { return 'DUP' }
        if ($a -like 'ignoriert*' -or $a -like 'macOS-Rest*' -or $a -like 'WAV vorhanden*' -or $a -like 'kein Sample*') { return '' }
        return $a
    }
    $n = 0
    foreach ($z in $zeilen) { $n++; if ($n % 25 -eq 0) { Write-Progress -Activity 'Pruefe Kopien' -Status "$n / $($zeilen.Count)" -PercentComplete ($n * 100 / $zeilen.Count) }
        try { $status[$z.Quelle] = & $pruefe $z } catch { $status[$z.Quelle] = $_.Exception.Message } }
    Write-Progress -Activity 'Pruefe Kopien' -Completed
    # Duplikate in der Quelle: gilt, wenn das behaltene Exemplar bestaetigt ist
    foreach ($z in $zeilen) {
        if ($status[$z.Quelle] -ne 'DUP') { continue }
        $erster = if ($z.ZielRel -match '^\(identisch mit (.+)\)$') { $Matches[1] } else { '' }
        $status[$z.Quelle] = if ($erster -and $status.ContainsKey($erster) -and $status[$erster] -eq '') { '' } elseif ($erster -and (Test-Datei $erster) -and -not $nachQuelle.ContainsKey($erster)) { 'Gegenstueck nicht im Import' } else { 'Gegenstueck nicht bestaetigt' }
    }

    $sep = [IO.Path]::DirectorySeparatorChar
    foreach ($p in $gut) {
        $basisQ = $p.Quelle.TrimEnd('\', '/') + $sep
        $eigene = @($zeilen | Where-Object { $_.Quelle.StartsWith($basisQ, [StringComparison]::OrdinalIgnoreCase) })
        $falsch = @($eigene | Where-Object { $status[$_.Quelle] })
        $neuKopiert = @($eigene | Where-Object { $_.Aktion -like 'kopiert*' }).Count
        $schon = @($eigene | Where-Object { $_.Aktion -like 'bereits im Ziel*' }).Count
        if (-not $eigene.Count) { Add-Zeile $p 'nicht importiert' 'bleibt im Download-Ordner' 'keine Dateien gefunden'; continue }
        if ($falsch.Count) {
            $grund = ($falsch | Select-Object -First 3 | ForEach-Object { [IO.Path]::GetFileName($_.Quelle) + ': ' + $status[$_.Quelle] }) -join '; '
            Write-Host "  $($p.Name): $($falsch.Count) Datei(en) nicht bestaetigt - Original bleibt liegen" -ForegroundColor Red
            Add-Zeile $p 'unvollstaendig' 'bleibt im Download-Ordner' $grund; continue
        }
        $info = "$neuKopiert neu kopiert, $schon schon im Ziel"
        $orig = 'im Download-Ordner gelassen'
        try {
            if ($Original -eq 'Archiv') {
                [void][IO.Directory]::CreateDirectory($archiv)
                $nach = Join-Path $archiv ([IO.Path]::GetFileName($p.Pfad)); $z = 2
                while ((Test-Path -LiteralPath $nach)) { $nach = Join-Path $archiv ("{0} ({1}){2}" -f [IO.Path]::GetFileNameWithoutExtension($p.Pfad), $z, $(if ($p.Art -eq 'ZIP') { '.zip' } else { '' })); $z++ }
                if ($p.Art -eq 'ZIP' -or [IO.Path]::GetPathRoot($p.Pfad) -ieq [IO.Path]::GetPathRoot($nach)) {
                    Move-Item -LiteralPath $p.Pfad -Destination $nach
                } else {
                    # Ordner auf ein anderes Laufwerk: kopieren, Groesse pruefen, dann das Original in den Papierkorb
                    Copy-Item -LiteralPath $p.Pfad -Destination $nach -Recurse
                    $a1 = [SamplesWerkzeuge.ZipWerkzeug300]::Ordner($p.Pfad); $a2 = [SamplesWerkzeuge.ZipWerkzeug300]::Ordner($nach)
                    if ($a1.Bytes -ne $a2.Bytes) { throw "Kopie ins Download-Archiv unvollstaendig" }
                    Send-Papierkorb $p.Pfad
                }
                $orig = "verschoben nach $nach"
            } elseif ($Original -eq 'Papierkorb') {
                Send-Papierkorb $p.Pfad
                $orig = 'in den Papierkorb gelegt'
            }
            Write-Host "  $($p.Name): importiert ($info); Original $orig" -ForegroundColor Green
            Add-Zeile $p 'importiert' $orig $info
        } catch {
            Write-Host "  $($p.Name): importiert ($info), Original konnte nicht behandelt werden: $($_.Exception.Message)" -ForegroundColor Yellow
            Add-Zeile $p 'importiert' "bleibt im Download-Ordner ($($_.Exception.Message))" $info
        }
    }
} finally {
    # Arbeitsordner immer entfernen (IMP-09) - er enthaelt nur die entpackten Kopien
    if ($arbeit -and (Test-Path -LiteralPath $arbeit)) {
        try { [IO.Directory]::Delete((Get-LangPfad $arbeit), $true) }
        catch { try { Remove-Item -LiteralPath $arbeit -Recurse -Force -ErrorAction Stop } catch { Write-Host "Arbeitsordner konnte nicht entfernt werden: $arbeit" -ForegroundColor Yellow } }
    }
    if ($protokoll.Count) {
        $pp = Join-Path $protokollOrdner "Import-Protokoll_$Zeitstempel.csv"
        $protokoll | Export-Csv -LiteralPath $pp -NoTypeInformation -Delimiter ';' -Encoding UTF8
        Write-Host ""
        Write-Host "Import-Protokoll: $pp"
    }
}
