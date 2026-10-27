# (c) 2026 Herbert Stoecker. Nur fuer Tests der Samples-Werkzeuge.
<#
.SYNOPSIS
  Stellt den Ausgangszustand fuer einen Test her:
    1. Inhalt des Zielordners (sortierte Bibliothek) entfernen; der Zielordner selbst bleibt
    2. in der Quelle das erste Sample-Pack entfernen, dessen Name mit "SINEE" beginnt
    3. in der Quelle den Ordner "Vocal Loops 120" entfernen (nur direkt in der Quelle, nicht in Unterordnern)
  Alles geht in den Windows-Papierkorb. Vorher Anzeige und Rueckfrage (Standard: Nein).

  Ordner: Standard E:\Sounds und Samples und E:\Samples. Liegt dieses Skript im Programmordner
  einer Version (oder daneben), werden die dort eingestellten Ordner genommen.
  Abweichend: -Quelle <Pfad> -Ziel <Pfad>
#>
[CmdletBinding()]
param([string]$Quelle, [string]$Ziel)

$ErrorActionPreference = 'Stop'
$Host.UI.RawUI.WindowTitle = 'Testvorbereitung Samples-Werkzeuge'
$hier = $PSScriptRoot

# Ordner bestimmen: Parameter > Einstellungen.json in der Naehe > Standard
$q = 'E:\Sounds und Samples'; $z = 'E:\Samples'; $herkunft = 'Standard'
$kandidaten = @(Join-Path $hier 'Skripte\Einstellungen.json'; Join-Path $hier '..\Skripte\Einstellungen.json')
foreach ($k in $kandidaten) {
    if (Test-Path -LiteralPath $k) {
        try {
            $e = Get-Content -LiteralPath $k -Raw -Encoding UTF8 | ConvertFrom-Json
            if ($e.Quelle) { $q = [string]$e.Quelle }
            if ($e.Ziel)   { $z = [string]$e.Ziel }
            $herkunft = (Resolve-Path -LiteralPath $k).Path
        } catch { }
        break
    }
}
if ($Quelle) { $q = $Quelle; $herkunft = 'Aufruf' }
if ($Ziel)   { $z = $Ziel;   $herkunft = 'Aufruf' }
$q = $q.TrimEnd('\', '/'); $z = $z.TrimEnd('\', '/')

Write-Host 'Testvorbereitung Samples-Werkzeuge' -ForegroundColor Cyan
Write-Host "  Quelle: $q"
Write-Host "  Ziel:   $z"
Write-Host "  (Ordner aus: $herkunft)"
Write-Host ''

# Sicherheitspruefungen
function Get-Voll([string]$p) { [IO.Path]::GetFullPath($p).TrimEnd('\', '/') }
if (-not (Test-Path -LiteralPath $q -PathType Container)) { throw "Quellordner nicht gefunden: $q" }
$qv = Get-Voll $q
$zv = if (Test-Path -LiteralPath $z) { Get-Voll $z } else { '' }
if ($zv) {
    if ($zv -eq $qv) { throw 'Quelle und Ziel sind gleich - abgebrochen.' }
    if ($qv.StartsWith($zv + '\') -or $qv.StartsWith($zv + '/')) { throw 'Die Quelle liegt im Ziel - abgebrochen.' }
    if ([IO.Path]::GetPathRoot($zv).TrimEnd('\', '/') -eq $zv) { throw "Das Ziel ist ein ganzes Laufwerk ($zv) - abgebrochen." }
    if ($hier -and (Get-Voll $hier).StartsWith($zv)) { throw 'Dieses Skript liegt im Ziel - abgebrochen.' }
}

$liste = New-Object System.Collections.Generic.List[object]
# 1. Inhalt des Ziels (der Zielordner selbst bleibt)
$zInhalt = if ($zv) { @(Get-ChildItem -LiteralPath $zv -Force) } else { @() }
foreach ($i in $zInhalt) { $liste.Add([pscustomobject]@{ Nr = 1; Was = 'Inhalt Ziel'; Pfad = $i.FullName }) }
if (-not $zInhalt.Count) { Write-Host "1. Zielordner leer oder nicht vorhanden - nichts zu tun." -ForegroundColor DarkGray }
# 2. erstes Pack "SINEE..." direkt in der Quelle (alphabetisch)
$sinee = Get-ChildItem -LiteralPath $q -Directory -Force | Where-Object { $_.Name -like 'SINEE*' } | Sort-Object Name | Select-Object -First 1
if ($sinee) { $liste.Add([pscustomobject]@{ Nr = 2; Was = 'Pack SINEE...'; Pfad = $sinee.FullName }) }
else { Write-Host "2. Kein Pack 'SINEE...' in der Quelle - nichts zu tun." -ForegroundColor DarkGray }
# 3. Ordner "Vocal Loops 120" direkt in der Quelle (erste Ebene)
$vocal = @(Get-ChildItem -LiteralPath $q -Directory -Force | Where-Object { $_.Name -eq 'Vocal Loops 120' })
foreach ($v in $vocal) { $liste.Add([pscustomobject]@{ Nr = 3; Was = 'Vocal Loops 120'; Pfad = $v.FullName }) }
if (-not $vocal.Count) { Write-Host "3. Ordner 'Vocal Loops 120' nicht gefunden - nichts zu tun." -ForegroundColor DarkGray }

if (-not $liste.Count) { Write-Host ''; Write-Host 'Es gibt nichts zu entfernen.' -ForegroundColor Green; return }

Write-Host ''
Write-Host 'Wird in den Papierkorb verschoben:' -ForegroundColor Yellow
foreach ($x in $liste) {
    $n = if (Test-Path -LiteralPath $x.Pfad -PathType Container) { @(Get-ChildItem -LiteralPath $x.Pfad -File -Recurse -Force -ErrorAction SilentlyContinue) } else { @(Get-Item -LiteralPath $x.Pfad -Force) }
    $mb = ($n | Measure-Object Length -Sum).Sum / 1MB
    Write-Host ("  {0}. {1,-16} {2}   ({3} Dateien, {4:N1} MB)" -f $x.Nr, $x.Was, $x.Pfad, $n.Count, [double]$mb)
}
Write-Host ''
Write-Host 'Hinweis: Ist der Papierkorb des Laufwerks zu klein, fragt Windows ggf., ob endgueltig geloescht werden soll.' -ForegroundColor DarkGray
$a = Read-Host 'Jetzt entfernen? (J/N, Standard N)'
if ($a -notmatch '^\s*[jJyY]') { Write-Host 'Abgebrochen. Es wurde nichts entfernt.' -ForegroundColor Yellow; return }

if (-not $env:SW_PAPIERKORB) { Add-Type -AssemblyName Microsoft.VisualBasic }
$ok = 0
foreach ($x in $liste) {
    try {
        if ($env:SW_PAPIERKORB) { Move-Item -LiteralPath $x.Pfad -Destination (Join-Path $env:SW_PAPIERKORB ([guid]::NewGuid().ToString('N') + '_' + (Split-Path -Leaf $x.Pfad))) -Force }
        elseif (Test-Path -LiteralPath $x.Pfad -PathType Container) { [Microsoft.VisualBasic.FileIO.FileSystem]::DeleteDirectory($x.Pfad, 'OnlyErrorDialogs', 'SendToRecycleBin') }
        else { [Microsoft.VisualBasic.FileIO.FileSystem]::DeleteFile($x.Pfad, 'OnlyErrorDialogs', 'SendToRecycleBin') }
        Write-Host "  entfernt: $($x.Pfad)" -ForegroundColor Green; $ok++
    } catch { Write-Host "  FEHLER bei $($x.Pfad): $($_.Exception.Message)" -ForegroundColor Red }
}
Write-Host ''
Write-Host "Fertig: $ok von $($liste.Count) Eintraegen im Papierkorb; der Zielordner selbst bleibt. Testausgangszustand hergestellt." -ForegroundColor Green
