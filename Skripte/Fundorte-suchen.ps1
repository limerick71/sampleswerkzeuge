# (c) 2026 Herbert Stoecker. Kostenlos nutzbar. Bitte nur als Link auf die offizielle Download-Seite weitergeben; Verkauf und Veroeffentlichung geaenderter Fassungen nur mit Zustimmung.
<#
.SYNOPSIS
  Fundorte suchen (QLN-01 bis QLN-03): findet auf Laufwerken und in Ordnern alle Stellen mit
  Audiodateien, fasst sie zu Fundorten zusammen, schaetzt ein, worum es sich handelt, und zeigt das
  Ergebnis als Bericht im Browser. Dort lassen sich Fundorte als Quellen uebernehmen.

  Es wird nichts veraendert und keine Datei geoeffnet: gelesen werden nur Ordnernamen, Dateinamen,
  Groessen und Datum. Dateien, die nur in der Cloud liegen (OneDrive "bei Bedarf"), werden nicht
  heruntergeladen, sondern gezaehlt. Ordner-Verknuepfungen werden nicht verfolgt.

.BENUTZUNG
    -Orte "C:\Users\HS\Downloads|E:\"   Wo gesucht wird (Trennzeichen |)
    -KeinBrowser                        Bericht nicht oeffnen
#>
[CmdletBinding()]
param(
    [string]$Orte,
    [switch]$KeinBrowser
)

$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'Gemeinsam.ps1')
$Zeitstempel = Get-Date -Format 'yyyy-MM-dd_HHmmss'
$einst = Get-Einstellungen
$start = Get-Date
Write-Host "Fundorte suchen (Samples-Werkzeuge $ProgrammVersion)" -ForegroundColor Cyan

$wurzeln = @($Orte -split '\|' | Where-Object { $_.Trim() } | ForEach-Object { $_.Trim() })
if (-not $wurzeln.Count) { throw 'Es ist kein Ort zum Durchsuchen angegeben.' }
$wurzeln = @(foreach ($w in $wurzeln) {
    if (Test-Path -LiteralPath $w) { $v = (Resolve-Path -LiteralPath $w).ProviderPath; if ($v.Length -gt 3) { $v.TrimEnd('\', '/') } else { $v } }
    else { Write-Host "  nicht gefunden, wird ausgelassen: $w" -ForegroundColor Yellow }
})
if (-not $wurzeln.Count) { throw 'Keiner der angegebenen Orte wurde gefunden.' }
# Orte, die in einem anderen gewaehlten Ort liegen, nicht doppelt durchsuchen
$wurzeln = @($wurzeln | Where-Object { $w = $_.TrimEnd('\', '/') + [IO.Path]::DirectorySeparatorChar
    -not @($wurzeln | Where-Object { $a = $_.TrimEnd('\', '/') + [IO.Path]::DirectorySeparatorChar; $a -ne $w -and $w.StartsWith($a, [StringComparison]::OrdinalIgnoreCase) }).Count } | Select-Object -Unique)
foreach ($w in $wurzeln) { Write-Host "  durchsuche: $w" }
Write-Host ""

# ---------------------------------------------------------------------------
# Ausgeschlossen: System- und Programmordner, Anwendungsdaten, Ziel, Programmordner
# ---------------------------------------------------------------------------
$aus = New-Object System.Collections.Generic.List[string]
foreach ($v in @($env:windir, $env:ProgramFiles, ${env:ProgramFiles(x86)}, $env:ProgramData, $env:APPDATA, $env:LOCALAPPDATA)) { if ($v) { $aus.Add($v.TrimEnd('\')) } }
foreach ($lw in [IO.DriveInfo]::GetDrives()) {
    foreach ($n in '$Recycle.Bin', 'System Volume Information', 'Recovery', 'PerfLogs', 'Config.Msi', 'MSOCache', 'Windows', 'Program Files', 'Program Files (x86)', 'ProgramData') {
        $aus.Add((Join-Path $lw.RootDirectory.FullName $n))
    }
}
if ($env:USERPROFILE) { $aus.Add((Join-Path $env:USERPROFILE 'AppData')) }
$aus.Add($einst.Ziel.TrimEnd('\', '/'))
$aus.Add($wurzel.TrimEnd('\', '/'))
# Ausschluesse, die selbst Suchort sind, gelten nicht (wer C:\Program Files ausdruecklich waehlt, bekommt es)
$aus = @($aus | Where-Object { $a = $_; -not @($wurzeln | Where-Object { $_ -ieq $a }).Count } | Select-Object -Unique)

# ---------------------------------------------------------------------------
# Schneller Suchlauf (C#): je Ordner Zahl und Groesse der Audiodateien, Formate, Datum,
# Merkmale fuer Projekte und Instrument-Bibliotheken, Archive, Cloud-Dateien
# ---------------------------------------------------------------------------
if (-not ('SamplesWerkzeuge.FundortScanner' -as [type])) {
    Add-Type -Language CSharp -TypeDefinition @'
using System;
using System.IO;
using System.Collections.Generic;
namespace SamplesWerkzeuge {
    public class OrdnerInfo {
        public string Pfad; public int Audio; public long Bytes; public int Archive; public int Projekt; public int Instrument;
        public int Cloud; public DateTime Neu; public string Formate; public string Beispiele;
    }
    public static class FundortScanner {
        public static int Ordner; public static int NichtLesbar;
        static readonly HashSet<string> AudioExt = new HashSet<string>(new string[] { ".wav", ".aif", ".aiff", ".mp3", ".flac", ".ogg", ".rx2", ".rex", ".m4a" }, StringComparer.OrdinalIgnoreCase);
        static readonly HashSet<string> ProjektExt = new HashSet<string>(new string[] { ".als", ".flp", ".cpr", ".ptx", ".ptf", ".song", ".rpp", ".bwproject", ".aup", ".aup3", ".npr", ".reason", ".logicx" }, StringComparer.OrdinalIgnoreCase);
        static readonly HashSet<string> InstrExt = new HashSet<string>(new string[] { ".nki", ".nkx", ".nkc", ".nkr", ".nicnt", ".ncw", ".nkm", ".nkb", ".ens", ".exs", ".gig", ".sf2", ".ufs", ".zmulti", ".nksn", ".hsb", ".vstpreset" }, StringComparer.OrdinalIgnoreCase);
        static readonly HashSet<string> ArchivExt = new HashSet<string>(new string[] { ".zip", ".rar", ".7z" }, StringComparer.OrdinalIgnoreCase);
        const FileAttributes CloudBits = (FileAttributes)0x400000 | (FileAttributes)0x40000 | FileAttributes.Offline;

        static bool Ausgeschlossen(string pfad, string[] aus) {
            foreach (string a in aus) {
                if (string.Equals(pfad, a, StringComparison.OrdinalIgnoreCase)) return true;
            }
            return false;
        }

        public static List<OrdnerInfo> Suche(string[] wurzeln, string[] aus) {
            List<OrdnerInfo> erg = new List<OrdnerInfo>();
            Ordner = 0; NichtLesbar = 0;
            Stack<string> stapel = new Stack<string>();
            foreach (string w in wurzeln) stapel.Push(w);
            DateTime letzte = DateTime.Now;
            while (stapel.Count > 0) {
                string d = stapel.Pop();
                Ordner++;
                if ((DateTime.Now - letzte).TotalSeconds >= 5) { Console.WriteLine("  ... " + Ordner.ToString("N0") + " Ordner durchsucht"); letzte = DateTime.Now; }
                OrdnerInfo oi = null;
                SortedSet<string> formate = new SortedSet<string>();
                List<string> beisp = new List<string>();
                try {
                    foreach (FileSystemInfo e in new DirectoryInfo(d).EnumerateFileSystemInfos()) {
                        FileAttributes at = e.Attributes;
                        if ((at & FileAttributes.Directory) != 0) {
                            if ((at & FileAttributes.ReparsePoint) != 0) continue;
                            if (Ausgeschlossen(e.FullName, aus)) continue;
                            stapel.Push(e.FullName);
                            continue;
                        }
                        string ext = Path.GetExtension(e.Name);
                        if (string.IsNullOrEmpty(ext)) continue;
                        bool audio = AudioExt.Contains(ext) && !e.Name.StartsWith("._");
                        bool proj = ProjektExt.Contains(ext);
                        bool instr = InstrExt.Contains(ext);
                        bool arch = ArchivExt.Contains(ext);
                        if (!(audio || proj || instr || arch)) continue;
                        if (oi == null) { oi = new OrdnerInfo(); oi.Pfad = d; oi.Neu = DateTime.MinValue; }
                        if (audio) {
                            oi.Audio++;
                            oi.Bytes += ((FileInfo)e).Length;
                            formate.Add(ext.TrimStart('.').ToUpperInvariant());
                            if (beisp.Count < 5) beisp.Add(e.Name);
                            if ((at & CloudBits) != 0) oi.Cloud++;
                            if (e.LastWriteTime > oi.Neu) oi.Neu = e.LastWriteTime;
                        }
                        if (proj) oi.Projekt++;
                        if (instr) oi.Instrument++;
                        if (arch) oi.Archive++;
                    }
                } catch (Exception) { NichtLesbar++; }
                if (oi != null) { oi.Formate = string.Join(",", formate); oi.Beispiele = string.Join("|", beisp); erg.Add(oi); }
            }
            return erg;
        }
    }
}
'@
}
Write-Host "Durchsuche Ordner (es werden nur Namen und Groessen gelesen) ..." -ForegroundColor Cyan
$treffer = [SamplesWerkzeuge.FundortScanner]::Suche([string[]]$wurzeln, [string[]]$aus)
$ordnerZahl = [SamplesWerkzeuge.FundortScanner]::Ordner
$nichtLesbar = [SamplesWerkzeuge.FundortScanner]::NichtLesbar
Write-Host ("  {0:N0} Ordner durchsucht, {1:N0} mit Audiodateien, Projekten oder Archiven" -f $ordnerZahl, $treffer.Count)
if ($nichtLesbar) { Write-Host "  $nichtLesbar Ordner waren nicht lesbar und wurden ausgelassen." -ForegroundColor DarkGray }

# ---------------------------------------------------------------------------
# Zusammenfassen: Summen fuer jeden Ordner und alle Elternordner bis zum Suchort
# ---------------------------------------------------------------------------
$sep = [IO.Path]::DirectorySeparatorChar
function Get-Eltern([string]$p) { $e = [IO.Path]::GetDirectoryName($p); if ($e -and $e -ne $p) { return $e } else { return '' } }
function Get-Suchwurzel([string]$p) {
    $t = ''
    foreach ($w in $wurzeln) { $wn = $w.TrimEnd('\', '/'); if (($p -ieq $wn -or $p -ieq $w -or $p.StartsWith($wn + $sep, [StringComparison]::OrdinalIgnoreCase)) -and $w.Length -gt $t.Length) { $t = $w } }
    return $t
}
$knoten = @{}
function Get-Knoten([string]$p) {
    $k = $p.ToLowerInvariant()
    if (-not $knoten.ContainsKey($k)) {
        $knoten[$k] = @{ Pfad = $p; Audio = 0; Bytes = [long]0; Archive = 0; Projekt = 0; Instrument = 0; Cloud = 0; Neu = [DateTime]::MinValue
                        Formate = @{}; EigeneAudio = 0; EigeneBytes = [long]0; EigeneArchive = 0; Kinder = @{}; Beispiele = New-Object System.Collections.Generic.List[string] }
    }
    return $knoten[$k]
}
foreach ($t in $treffer) {
    $sw = Get-Suchwurzel $t.Pfad
    $n = Get-Knoten $t.Pfad
    $n.EigeneAudio += $t.Audio; $n.EigeneBytes += $t.Bytes; $n.EigeneArchive += $t.Archive
    $p = $t.Pfad; $kind = ''
    while ($p) {
        $n = Get-Knoten $p
        $n.Audio += $t.Audio; $n.Bytes += $t.Bytes; $n.Archive += $t.Archive; $n.Projekt += $t.Projekt; $n.Instrument += $t.Instrument; $n.Cloud += $t.Cloud
        if ($t.Neu -gt $n.Neu) { $n.Neu = $t.Neu }
        foreach ($f in ($t.Formate -split ',')) { if ($f) { $n.Formate[$f] = $true } }
        if ($t.Beispiele -and $n.Beispiele.Count -lt 5) { foreach ($b in ($t.Beispiele -split '\|')) { if ($n.Beispiele.Count -lt 5) { $n.Beispiele.Add($b) } } }
        if ($kind) { $n.Kinder[$kind.ToLowerInvariant()] = $kind }
        if (-not $sw -or $p -ieq $sw -or $p -ieq $sw.TrimEnd('\', '/')) { break }
        $kind = $p; $p = Get-Eltern $p
    }
}

# ---------------------------------------------------------------------------
# Einschaetzen (QLN-02)
# ---------------------------------------------------------------------------
$InstrNamen = 'Native Instruments|Kontakt|Spitfire|Sonokinetic|Muse ?Hub|Arturia|\bUVI\b|Vienna|\bVSL\b|EastWest|East West|Toontrack|Superior Drummer|EZdrummer|Steinberg|HALion|Komplete|Heavyocity|8Dio|Orchestral Tools|Cinesamples|XLN Audio|Addictive|Spectrasonics|Omnisphere|Keyscape|Trilian|Factory Packs|Core Library|Output Arcade|Soundiron|Impact Soundworks|Best Service|Garritan|Embertone'
$SystemPfade = @($env:windir, $env:ProgramFiles, ${env:ProgramFiles(x86)}, $env:ProgramData) | Where-Object { $_ }
function Get-Einschaetzung($n) {
    $p = $n.Pfad
    foreach ($s in $SystemPfade) { if ($p.StartsWith($s, [StringComparison]::OrdinalIgnoreCase)) { return 'System/Programm' } }
    if ($n.Instrument -gt 0 -or $p -match $InstrNamen) { return 'Instrument-Bibliothek' }
    if ($n.Projekt -gt 0 -or $p -match '[\\/](Samples[\\/]Recorded|Audio Files|Bounces?|Freeze Files)([\\/]|$)') { return 'DAW-Projekt' }
    if ($n.Audio -eq 0 -and $n.Archive -gt 0) { return 'Nur Archive (ZIP)' }
    return 'Sample-Packs'
}
# Ordner, die nur Behaelter sind (Laufwerk, Benutzerordner, Dokumente ...): nie selbst Fundort
$behaelter = @{}
$benutzerEltern = if ($env:USERPROFILE) { Split-Path -Parent $env:USERPROFILE } else { '' }
foreach ($v in @($env:USERPROFILE, [Environment]::GetFolderPath('MyDocuments'), [Environment]::GetFolderPath('Desktop'), [Environment]::GetFolderPath('MyMusic'), (Get-StandardDownloads), $env:OneDrive, $env:OneDriveConsumer, $env:OneDriveCommercial, $benutzerEltern)) {
    if ($v) { $behaelter[$v.TrimEnd('\', '/').ToLowerInvariant()] = $true }
}
function Test-Behaelter([string]$p) {
    if ([IO.Path]::GetPathRoot($p) -ieq $p -or $p.Length -le 3) { return $true }
    # Gewaehlte Suchorte sind nie selbst Fundort ("dort suchen" heisst nicht "das ist eine Quelle")
    foreach ($w in $wurzeln) { if ($w.TrimEnd('\', '/') -ieq $p.TrimEnd('\', '/')) { return $true } }
    return $behaelter.ContainsKey($p.TrimEnd('\', '/').ToLowerInvariant())
}

# Fundorte von oben nach unten bestimmen
$fundorte = New-Object System.Collections.Generic.List[object]
function Add-Fundort($n) { $fundorte.Add($n) }
function Find-Fundorte([string]$p, [bool]$unterBehaelter = $false) {
    $n = $knoten[$p.ToLowerInvariant()]
    if (-not $n) { return }
    $kinder = @($n.Kinder.Values | ForEach-Object { $knoten[$_.ToLowerInvariant()] } | Where-Object { $_ })
    if (Test-Behaelter $p) {
        # Behaelter (Laufwerk, Downloads, Dokumente ...) ist nie als Ganzes Fundort. Lose Audiodateien direkt
        # darin erscheinen als eigene Zeile mit der Art "Nur lose Dateien" (ohne Unterordner).
        if ($n.EigeneAudio -gt 0 -or $n.EigeneArchive -gt 0) {
            $fundorte.Add(@{ Pfad = $p; Audio = $n.EigeneAudio; Bytes = $n.EigeneBytes; Archive = $n.EigeneArchive; Projekt = 0; Instrument = 0; Cloud = 0; Neu = $n.Neu
                             Formate = $n.Formate; EigeneAudio = $n.EigeneAudio; Kinder = @{}; Beispiele = $n.Beispiele; Lose = $true })
        }
        foreach ($k in $kinder) { Find-Fundorte $k.Pfad $true }
        return
    }
    # Direkt unter einem Behaelter ist jeder Ordner ein Fundort (z. B. Downloads\BSH092_...), auch wenn er
    # nur einen Unterordner hat - sonst wuerde ein innerer Ordner zum Pack-Namen.
    if ($unterBehaelter -and @($kinder | ForEach-Object { Get-Einschaetzung $_ } | Select-Object -Unique).Count -le 1) { Add-Fundort $n; return }
    # Nur ein Unterordner mit Inhalt und hier selbst nichts (auch keine Projekt-, Instrument- oder Archivdateien): tiefer gehen
    if ($n.EigeneAudio -eq 0 -and $kinder.Count -eq 1 -and $n.Archive -eq $kinder[0].Archive -and $n.Projekt -eq $kinder[0].Projekt -and $n.Instrument -eq $kinder[0].Instrument) { Find-Fundorte $kinder[0].Pfad; return }
    $arten = @($kinder | ForEach-Object { Get-Einschaetzung $_ } | Select-Object -Unique)
    if ($n.EigeneAudio -eq 0 -and $arten.Count -gt 1) { foreach ($k in $kinder) { Find-Fundorte $k.Pfad }; return }
    Add-Fundort $n
}
foreach ($w in $wurzeln) { Find-Fundorte $w.TrimEnd('\', '/'); if ($w.Length -le 3) { Find-Fundorte $w } }

# Bereits eingetragene Quellen
$quellen = @($einst.Quellen)
function Get-QuellStatus([string]$p, [string]$art = 'Sammlung') {
    $pn = $p.TrimEnd('\') + '\'
    foreach ($q in $quellen) {
        $qn = ([string]$q.Pfad).TrimEnd('\') + '\'
        $qArt = Get-QuellArtName ([string]$q.Art)
        if ($qn -ieq $pn) { return 'ist bereits Quelle' }
        if ($pn.StartsWith($qn, [StringComparison]::OrdinalIgnoreCase) -and $qArt -ne 'Lose') { return "liegt in der Quelle $($q.Pfad)" }
        if ($qn.StartsWith($pn, [StringComparison]::OrdinalIgnoreCase) -and $art -ne 'Lose') { return "enthält die Quelle $($q.Pfad)" }
    }
    return ''
}

$liste = @(foreach ($n in $fundorte) {
    $art = Get-Einschaetzung $n
    $kinder = @($n.Kinder.Values | ForEach-Object { $knoten[$_.ToLowerInvariant()] } | Where-Object { $_ } | Sort-Object { $_.Audio } -Descending)
    $packs = @($kinder | Where-Object { $_.Audio -gt 0 }).Count
    $qArt = if ($n.Lose) { 'Lose' } else { Get-QuellArtVorschlag @($kinder | ForEach-Object { [IO.Path]::GetFileName($_.Pfad) }) $n.EigeneAudio }
    $status = if ($n.Lose -and $n.Audio -eq 0) { 'nur Archive direkt in diesem Ordner – vor dem Übernehmen entpacken (ab Version 3 übernimmt das der Import)' } else { Get-QuellStatus $n.Pfad $qArt }
    [pscustomobject][ordered]@{
        p   = $n.Pfad
        art = $art
        a   = $n.Audio
        b   = $n.Bytes
        f   = (@($n.Formate.Keys | Sort-Object) -join ', ')
        neu = $(if ($n.Neu -gt [DateTime]::MinValue) { $n.Neu.ToString('yyyy-MM-dd') } else { '' })
        zip = $n.Archive
        cl  = $n.Cloud
        pk  = $packs
        lose = $n.EigeneAudio
        nl  = [bool]$n.Lose
        qa  = $qArt
        st  = $status
        vor = ($art -eq 'Sample-Packs' -and -not $n.Lose -and -not $status -and $n.Audio -ge 5 -and $n.Cloud -eq 0)
        u   = @($kinder | Select-Object -First 30 | ForEach-Object { [pscustomobject]@{ n = [IO.Path]::GetFileName($_.Pfad); a = $_.Audio; b = $_.Bytes; art = (Get-Einschaetzung $_) } })
        bsp = @($n.Beispiele)
    }
}) | Sort-Object @{ e = { $_.art -ne 'Sample-Packs' } }, @{ e = { $_.b }; Descending = $true }

# ---------------------------------------------------------------------------
# Ergebnis: JSON, CSV, HTML
# ---------------------------------------------------------------------------
$ablage = Join-Path $einst.Berichtsordner 'Fundorte'
if (-not (Test-Path -LiteralPath $ablage)) { New-Item -ItemType Directory -Path $ablage -Force | Out-Null }
$basisName = Join-Path $ablage "Fundorte_$Zeitstempel"
$meta = [ordered]@{
    Version = $ProgrammVersion; Erstellt = (Get-Date).ToString('dd.MM.yyyy HH:mm'); Orte = @($wurzeln); Ordner = $ordnerZahl
    NichtLesbar = $nichtLesbar; Dauer = [math]::Round(((Get-Date) - $start).TotalSeconds); Ziel = $einst.Ziel
}
$daten = [ordered]@{ meta = $meta; f = @($liste) }
$json = ConvertTo-Json -InputObject $daten -Depth 6 -Compress
[IO.File]::WriteAllText("$basisName.json", $json, (New-Object System.Text.UTF8Encoding($false)))
$liste | Select-Object @{ n = 'Fundort'; e = { $_.p } }, @{ n = 'Einschaetzung'; e = { $_.art } }, @{ n = 'Audiodateien'; e = { $_.a } },
    @{ n = 'GroesseMB'; e = { [math]::Round($_.b / 1MB, 1) } }, @{ n = 'Formate'; e = { $_.f } }, @{ n = 'Letzte Aenderung'; e = { $_.neu } },
    @{ n = 'Archive'; e = { $_.zip } }, @{ n = 'Nur in der Cloud'; e = { $_.cl } }, @{ n = 'Unterordner mit Audio'; e = { $_.pk } }, @{ n = 'Status'; e = { $_.st } } |
    Export-Csv -LiteralPath "$basisName.csv" -NoTypeInformation -Delimiter ';' -Encoding UTF8

$vorlage = @'
<!DOCTYPE html>
<html lang="de"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width, initial-scale=1">
<title>Fundorte – Samples-Werkzeuge</title>
<style>
:root{--bg:#f6f7f9;--karte:#fff;--text:#1d2433;--leise:#5f6b7a;--linie:#e2e6ec;--kopf:#eef1f5;--akzent:#1f4e79;--rot:#b42318;--rot-bg:#fde8e7;--gelb:#8a5a00;--gelb-bg:#fff4d6;--gruen:#1a7f37;--gruen-bg:#e3f5e8;--blau:#1f4e79;--blau-bg:#e4eef8;--grau-bg:#eef0f3}
@media (prefers-color-scheme: dark){:root{--bg:#14171c;--karte:#1c2027;--text:#e6e9ee;--leise:#9aa4b2;--linie:#2c323c;--kopf:#232831;--akzent:#8bb8e8;--rot:#ff8a80;--rot-bg:#3a1f1f;--gelb:#ffd27a;--gelb-bg:#3a2f14;--gruen:#7ee2a0;--gruen-bg:#163322;--blau:#8bb8e8;--blau-bg:#1b2a3c;--grau-bg:#262b33}}
*{box-sizing:border-box}body{margin:0;background:var(--bg);color:var(--text);font:14px/1.45 "Segoe UI",system-ui,sans-serif}
header{padding:22px 28px 6px}h1{margin:0;font-size:22px;color:var(--akzent)}.unter{color:var(--leise);font-size:13px;margin-top:2px}
.karten{display:flex;flex-wrap:wrap;gap:10px;padding:14px 28px}.karte{background:var(--karte);border:1px solid var(--linie);border-radius:8px;padding:10px 14px;min-width:120px}
.karte b{display:block;font-size:20px}.karte span{color:var(--leise);font-size:12px}
.werkzeuge{display:flex;flex-wrap:wrap;gap:10px;align-items:center;padding:8px 28px 12px;position:sticky;top:0;background:var(--bg);z-index:2;border-bottom:1px solid var(--linie)}
label.ck{display:flex;gap:6px;align-items:center;color:var(--leise)}
button.k{font:inherit;border:1px solid var(--linie);background:var(--karte);color:var(--text);border-radius:6px;padding:6px 12px;cursor:pointer}
button.haupt{background:var(--akzent);color:var(--karte);border-color:var(--akzent)}button:disabled{opacity:.5;cursor:default}
main{padding:12px 28px 40px}table{width:100%;border-collapse:collapse;background:var(--karte);border:1px solid var(--linie)}
th,td{text-align:left;padding:7px 10px;border-bottom:1px solid var(--linie);vertical-align:top}th{background:var(--kopf);font-size:12px;color:var(--leise);font-weight:600}
td.z{text-align:right;white-space:nowrap}tr.f{cursor:pointer}button.oe{white-space:nowrap}tr.f:hover td{background:var(--kopf)}td.pfad{word-break:break-all;font-weight:600}
.art{display:inline-block;border-radius:10px;padding:1px 8px;font-size:12px;white-space:nowrap}
.a-sp{background:var(--gruen-bg);color:var(--gruen)}.a-ib{background:var(--gelb-bg);color:var(--gelb)}.a-dp{background:var(--blau-bg);color:var(--blau)}.a-sy,.a-ar{background:var(--grau-bg);color:var(--leise)}
.hw{display:block;font-size:12px;color:var(--leise)}.hw.rot{color:var(--rot)}.hw.gruen{color:var(--gruen)}
tr.detail td{background:var(--bg);font-size:13px}tr.detail table{margin:4px 0 6px;border:0}tr.detail td,tr.detail th{padding:3px 8px}
.leise{color:var(--leise)}#meldung{position:fixed;bottom:18px;left:50%;transform:translateX(-50%);background:var(--akzent);color:var(--karte);padding:8px 16px;border-radius:6px;display:none;z-index:9}
.hinweis{margin:0 28px 10px;padding:8px 12px;border-radius:6px;background:var(--gelb-bg);color:var(--gelb);font-size:13px}
</style></head><body>
<header><h1>Fundorte</h1><div class="unter" id="unter"></div></header>
<div class="karten" id="karten"></div>
<div class="hinweis" id="ohneDienst" style="display:none">Dieser Bericht wurde direkt geöffnet. Zum Übernehmen als Quelle, „Ordner öffnen“ und Abgleich bitte über „Fundorte suchen …“ in den Samples-Werkzeugen öffnen.</div>
<div class="werkzeuge">
 <button class="k haupt" id="uebernehmen">In Quellenliste übernehmen (0)</button>
 <button class="k" id="abgleich" title="Prüft für die angehakten Fundorte, wie viele Audiodateien schon in der Bibliothek liegen (Größe, dann Prüfsumme). Kann bei großen Fundorten dauern.">Angehakte mit Bibliothek abgleichen</button>
 <label class="ck"><input type="checkbox" id="klein"> kleine Fundorte (unter 5 Audiodateien) zeigen</label>
 <label class="ck"><input type="checkbox" id="andere" checked> Instrument-Bibliotheken, Projekte, System zeigen</label>
</div>
<main><table><thead><tr><th></th><th>Fundort</th><th>Einschätzung</th><th class="z">Audiodateien</th><th class="z">Größe</th><th>Formate</th><th>Letzte Änderung</th><th></th></tr></thead><tbody id="liste"></tbody></table>
<p class="leise" style="font-size:12px">Ein Klick auf eine Zeile zeigt Unterordner und Beispieldateien. Vorausgewählt sind Sample-Packs, die noch keine Quelle sind. Instrument-Bibliotheken gehören zu Plugins (z. B. Kontakt, Spitfire) und sollten nicht einsortiert werden; DAW-Projekte enthalten eigene Aufnahmen.</p></main>
<div id="meldung"></div>
<script id="daten" type="application/json">__DATEN__</script>
<script>
(function(){
  var D = JSON.parse(document.getElementById('daten').textContent), F = D.f, M = D.meta, DIENST = window.SW_DIENST;
  var $ = function(id){ return document.getElementById(id); };
  var wahl = {}, offen = {}, abgl = {};
  F.forEach(function(f, i){ f.i = i; if (f.vor) wahl[i] = true; });
  function esc(s){ return String(s == null ? '' : s).replace(/[&<>"]/g, function(c){ return {'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;'}[c]; }); }
  function mb(b){ b = b / 1048576; return b >= 1024 ? (b/1024).toFixed(1).replace('.', ',') + ' GB' : (b >= 10 ? Math.round(b) : b.toFixed(1).replace('.', ',')) + ' MB'; }
  function n(z){ return Number(z).toLocaleString('de-DE'); }
  function meldung(t){ var m = $('meldung'); m.textContent = t; m.style.display = 'block'; clearTimeout(m._t); m._t = setTimeout(function(){ m.style.display = 'none'; }, 3500); }
  var KL = {'Sample-Packs':'a-sp','Instrument-Bibliothek':'a-ib','DAW-Projekt':'a-dp','System/Programm':'a-sy','Nur Archive (ZIP)':'a-ar'};
  function waehlbar(f){ return !f.st && f.a > 0 && f.cl < f.a; }
  var ARTEN = [['Sammlung','Sammlung'],['Pack','Ein Pack'],['Lose','Nur lose Dateien']];
  $('unter').textContent = 'Suchlauf vom ' + M.Erstellt + ' · durchsucht: ' + M.Orte.join(', ') + ' · ' + n(M.Ordner) + ' Ordner in ' + M.Dauer + ' s' + (M.NichtLesbar ? ' · ' + M.NichtLesbar + ' Ordner nicht lesbar' : '');
  function karten(){
    var sp = F.filter(function(f){ return f.art === 'Sample-Packs'; }), a = 0, b = 0; sp.forEach(function(f){ a += f.a; b += f.b; });
    $('karten').innerHTML = '<div class="karte"><b>' + F.length + '</b><span>Fundorte</span></div><div class="karte"><b>' + sp.length + '</b><span>davon Sample-Packs</span></div>' +
      '<div class="karte"><b>' + n(a) + '</b><span>Audiodateien in Sample-Packs</span></div><div class="karte"><b>' + mb(b) + '</b><span>Größe Sample-Packs</span></div>';
  }
  function zeichnen(){
    var klein = $('klein').checked, andere = $('andere').checked, h = [], z = 0;
    F.forEach(function(f){
      if (!klein && f.a < 5 && f.zip === 0 && !f.nl) return;
      if (!andere && f.art !== 'Sample-Packs' && f.art !== 'Nur Archive (ZIP)') return;
      var w = waehlbar(f), hw = [];
      if (f.st) hw.push('<span class="hw' + (f.st.indexOf('jetzt') === 0 || f.st.indexOf('ist') === 0 ? ' gruen' : '') + '">' + esc(f.st) + '</span>');
      if (f.pk > 1 && f.qa === 'Sammlung') hw.push('<span class="hw">' + f.pk + ' Packs (Unterordner mit Audio)</span>');
      if (f.lose && f.pk) hw.push('<span class="hw">' + n(f.lose) + ' Dateien direkt im Ordner</span>');
      if (f.nl && f.a) hw.push('<span class="hw">nur die Dateien direkt in diesem Ordner, ohne Unterordner</span>');
      if (f.zip) hw.push('<span class="hw rot">' + f.zip + ' Archiv(e) nicht entpackt</span>');
      if (f.cl) hw.push('<span class="hw rot">' + n(f.cl) + ' Dateien nur in der Cloud (werden nicht heruntergeladen)</span>');
      if (abgl[f.i]) hw.push('<span class="hw">' + abgl[f.i] + '</span>');
      h.push('<tr class="f" data-i="' + f.i + '"><td><input type="checkbox" class="w" data-i="' + f.i + '"' + (wahl[f.i] && w ? ' checked' : '') + (w ? '' : ' disabled') + '></td>' +
        '<td class="pfad">' + esc(f.p) + hw.join('') + '</td><td><span class="art ' + (KL[f.art] || '') + '">' + esc(f.art) + '</span>' +
        (w ? '<br><select class="qa" data-i="' + f.i + '" title="Art als Quelle: Sammlung = jeder Unterordner ist ein Pack; Ein Pack = alles darin unter dem Ordnernamen; Nur lose Dateien = ohne Unterordner">' +
          ARTEN.map(function(a){ return '<option value="' + a[0] + '"' + (f.qa === a[0] ? ' selected' : '') + '>' + a[1] + '</option>'; }).join('') + '</select>' : '') + '</td>' +
        '<td class="z">' + n(f.a) + '</td><td class="z">' + mb(f.b) + '</td><td>' + esc(f.f) + '</td><td>' + esc(f.neu) + '</td>' +
        '<td><button class="k oe" data-i="' + f.i + '"' + (DIENST ? '' : ' disabled') + '>Ordner öffnen</button></td></tr>');
      if (offen[f.i]) {
        var u = (f.u || []).map(function(x){ return '<tr><td>' + esc(x.n) + '</td><td class="z">' + n(x.a) + '</td><td class="z">' + mb(x.b) + '</td><td>' + esc(x.art) + '</td></tr>'; }).join('');
        h.push('<tr class="detail"><td></td><td colspan="7">' + (u ? '<table><tr><th>Unterordner</th><th class="z">Audiodateien</th><th class="z">Größe</th><th>Einschätzung</th></tr>' + u + '</table>' : '') +
          '<span class="leise">Beispiele: ' + esc((f.bsp || []).join(' · ') || '–') + '</span></td></tr>');
      }
      z++;
    });
    $('liste').innerHTML = h.join('') || '<tr><td colspan="8" class="leise">Keine Fundorte für diese Auswahl.</td></tr>';
    var c = Object.keys(wahl).filter(function(i){ return wahl[i] && waehlbar(F[i]); }).length;
    $('uebernehmen').textContent = 'In Quellenliste übernehmen (' + c + ')';
    $('uebernehmen').disabled = !DIENST || !c; $('abgleich').disabled = !DIENST || !c;
  }
  document.addEventListener('click', function(e){
    var cb = e.target.closest('input.w'); if (cb) { wahl[cb.getAttribute('data-i')] = cb.checked; zeichnen(); return; }
    if (e.target.closest('select.qa')) return;
    var oe = e.target.closest('button.oe'); if (oe) { post('/oeffnen-ort', { pfad: F[oe.getAttribute('data-i')].p }).then(function(){ meldung('Explorer wird geöffnet …'); }); return; }
    var tr = e.target.closest('tr.f'); if (tr) { var i = tr.getAttribute('data-i'); offen[i] = !offen[i]; zeichnen(); }
  });
  $('klein').addEventListener('change', zeichnen); $('andere').addEventListener('change', zeichnen);
  document.addEventListener('change', function(e){ var s = e.target.closest('select.qa'); if (s) F[s.getAttribute('data-i')].qa = s.value; });
  function post(pfad, daten){
    return fetch(pfad + '?t=' + DIENST.token, { method: 'POST', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify(daten) })
      .then(function(r){ return r.text().then(function(t){ if (!r.ok) { meldung(t); throw new Error(t); } return t ? JSON.parse(t) : {}; }); });
  }
  $('uebernehmen').addEventListener('click', function(){
    var wa = Object.keys(wahl).filter(function(i){ return wahl[i] && waehlbar(F[i]); }).map(function(i){ return F[i]; });
    if (!wa.length) return;
    var NAME = {}; ARTEN.forEach(function(a){ NAME[a[0]] = a[1]; });
    if (!confirm(wa.length + ' Fundort(e) als Quelle übernehmen?\n\n' + wa.map(function(f){ return f.p + '  (' + NAME[f.qa] + ')'; }).join('\n') + '\n\nEs wird nichts kopiert oder verändert; die Quellen erscheinen unter ⚙ Einstellungen.')) return;
    post('/uebernehmen', { pfade: wa.map(function(f){ return { pfad: f.p, art: f.qa }; }) }).then(function(r){
      var ok = 0, nein = [];
      (r.ergebnisse || []).forEach(function(x){ F.forEach(function(f){ if (f.p === x.pfad) { if (x.ok) { f.st = 'jetzt Quelle'; ok++; } else { nein.push(x.pfad + ': ' + x.grund); } } }); });
      zeichnen(); meldung(ok + ' Quelle(n) übernommen.');
      if (nein.length) alert('Nicht übernommen:\n\n' + nein.join('\n'));
    });
  });
  $('abgleich').addEventListener('click', function(){
    var ix = Object.keys(wahl).filter(function(i){ return wahl[i] && waehlbar(F[i]); });
    var lauf = function(k){
      if (k >= ix.length) { meldung('Abgleich fertig.'); return; }
      var f = F[ix[k]]; abgl[f.i] = 'Abgleich läuft …'; zeichnen();
      post('/abgleich', { pfad: f.p }).then(function(r){
        abgl[f.i] = 'Schon in der Bibliothek: ' + n(r.vorhanden) + ' von ' + n(r.geprueft) + ' (' + (r.geprueft ? Math.round(100 * r.vorhanden / r.geprueft) : 0) + ' %)' + (r.cloud ? ', ' + n(r.cloud) + ' nur in der Cloud nicht geprüft' : '');
        zeichnen(); lauf(k + 1);
      }).catch(function(){ abgl[f.i] = 'Abgleich nicht möglich'; zeichnen(); lauf(k + 1); });
    };
    lauf(0);
  });
  if (DIENST) {
    setInterval(function(){ fetch('/ping?t=' + DIENST.token).catch(function(){}); }, 20000);
    // Status gegen die aktuelle Quellenliste neu bestimmen (Bericht kann älter sein)
    post('/quellen', {}).then(function(r){
      var Q = (r.quellen || []).map(function(q){ return { p: String(q.pfad).replace(/[\\\/]+$/, '').toLowerCase() + '\\', lose: q.art === 'Lose' }; });
      F.forEach(function(f){
        if (f.nl && !f.a) return;
        var p = f.p.replace(/[\\\/]+$/, '').toLowerCase() + '\\', st = '';
        Q.forEach(function(q){ if (st) return; if (q.p === p) st = 'ist bereits Quelle'; else if (p.indexOf(q.p) === 0 && !q.lose) st = 'liegt in einer Quelle'; else if (q.p.indexOf(p) === 0 && f.qa !== 'Lose') st = 'enthält eine Quelle'; });
        f.st = st;
      });
      zeichnen();
    }).catch(function(){});
  } else { $('ohneDienst').style.display = 'block'; }
  karten(); zeichnen();
})();
</script></body></html>
'@
$html = $vorlage.Replace('__DATEN__', $json.Replace('</', '<\/'))
[IO.File]::WriteAllText("$basisName.html", $html, (New-Object System.Text.UTF8Encoding($false)))

# ---------------------------------------------------------------------------
# Zusammenfassung und Bericht oeffnen
# ---------------------------------------------------------------------------
Write-Host ""
Write-Host "==================== Zusammenfassung ====================" -ForegroundColor Yellow
Write-Host ("Fundorte:            {0,6}" -f $liste.Count)
$liste | Group-Object art | Sort-Object Name | ForEach-Object { Write-Host ("  {0,-22} {1,6}" -f $_.Name, $_.Count) }
Write-Host ("Dauer: {0} s" -f $meta.Dauer)
Write-Host ""
Write-Host "Bericht: $basisName.html"
Write-Host "Liste (Excel): $basisName.csv"
if (-not $KeinBrowser) {
    Write-Host ""
    Write-Host "Der Bericht wird im Browser geoeffnet. Dort Fundorte anhaken und 'In Quellenliste uebernehmen'." -ForegroundColor Green
    $psExe = Join-Path $PSHOME 'powershell.exe'; if (-not (Test-Path -LiteralPath $psExe)) { $psExe = 'powershell.exe' }
    try { Start-Process -FilePath $psExe -ArgumentList "-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File `"$(Join-Path $PSScriptRoot 'Bericht-Dienst.ps1')`" -Fundorte `"$basisName.json`"" -WindowStyle Hidden -ErrorAction Stop }
    catch { try { Invoke-Item -LiteralPath "$basisName.html" } catch { } }
}
