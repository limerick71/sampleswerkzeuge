# (c) 2026 Herbert Stoecker. Kostenlos nutzbar. Bitte nur als Link auf die offizielle Download-Seite weitergeben; Verkauf und Veroeffentlichung geaenderter Fassungen nur mit Zustimmung.
# Gemeinsam.ps1 - gemeinsame Pfade, Einstellungen und Hilfsfunktionen der Samples-Werkzeuge (Version 1)
# Wird von Samples-Werkzeuge.ps1, Samples-sortieren.ps1 und Duplikate-entfernen.ps1 per Dot-Sourcing geladen.
#
# Ordnerstruktur (wie bei den Plugin-Werkzeugen):
#   <Wurzel>\               nur Startdateien (*.cmd) und Dokumentation
#   <Wurzel>\Skripte\       Skripte und Einstellungen.json
#   <Wurzel>\Protokolle\    Vorschau-, Kopier- und Duplikat-Protokolle (CSV)
#   <Berichtsordner>\Inventuren\, \Inventur-Vergleiche\   ab Version 2 (Inventur und Bericht)

$ProgrammVersion = '1.0.0'
$Urheberhinweis  = "$([char]0x00A9) 2026 Herbert St$([char]0x00F6)cker. Kostenlos nutzbar. Bitte nur als Link auf die offizielle Download-Seite weitergeben; Verkauf und Ver$([char]0x00F6)ffentlichung ge$([char]0x00E4)nderter Fassungen nur mit Zustimmung."
$UrheberKurz     = "$([char]0x00A9) 2026 Herbert St$([char]0x00F6)cker"
$DownloadSeite   = 'https://github.com/limerick71/sampleswerkzeuge/releases/latest'

$skriptOrdner = $PSScriptRoot
if ([string]::IsNullOrWhiteSpace($skriptOrdner)) { $skriptOrdner = (Get-Location).Path }
$wurzel           = Split-Path -Parent $skriptOrdner
$protokollOrdner  = Join-Path $wurzel 'Protokolle'
$einstellungsPfad = Join-Path $skriptOrdner 'Einstellungen.json'
$fehlerLog        = Join-Path $skriptOrdner 'Fehler.log'

if (-not (Test-Path -LiteralPath $protokollOrdner)) { try { New-Item -ItemType Directory -Path $protokollOrdner -Force | Out-Null } catch { } }

function Write-FehlerLog([string]$text) {
    try { Add-Content -LiteralPath $fehlerLog -Value ("{0:yyyy-MM-dd HH:mm:ss}  {1}" -f (Get-Date), $text) -Encoding UTF8 } catch { }
}

# ---------------------------------------------------------------------------
# Einstellungen (Skripte\Einstellungen.json)
# ---------------------------------------------------------------------------
# Download-Ordner des Benutzers (auch wenn er verschoben wurde)
function Get-StandardDownloads {
    try {
        $p = (Get-ItemProperty -Path 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\User Shell Folders' -ErrorAction Stop).'{374DE290-123F-4565-9164-39C4925E467B}'
        if ($p) { return [Environment]::ExpandEnvironmentVariables($p) }
    } catch { }
    if ($env:USERPROFILE) { return (Join-Path $env:USERPROFILE 'Downloads') }
    return ''
}

# Beschreibung aller Pfad-Einstellungen: Schluessel, Anzeigename, Erklaerung
$PfadEinstellungen = @(
    @{ Name = 'Quelle';         Text = 'Quelle';           Hinweis = 'Ordner mit den unsortierten Sample-Packs. Wird beim Sortieren nur gelesen.' }
    @{ Name = 'Ziel';           Text = 'Ziel';             Hinweis = 'Sortierte Sample-Bibliothek. Hierhin wird kopiert.' }
    @{ Name = 'Downloads';      Text = 'Downloads';        Hinweis = "Hier sucht der Import (ab Version 3) nach neuen Sample-Packs." }
    @{ Name = 'DownloadArchiv'; Text = 'Download-Archiv';  Hinweis = "Hierhin verschiebt der Import (ab Version 3) auf Wunsch die Original-Downloads." }
    @{ Name = 'Berichtsordner'; Text = 'Berichte';         Hinweis = "Hier legt die Inventur (ab Version 2) die Unterordner Inventuren und Inventur-Vergleiche an." }
)

function Get-StandardEinstellungen {
    return [ordered]@{
        Quelle              = 'E:\Sounds und Samples'
        Ziel                = 'E:\Samples'
        Downloads           = (Get-StandardDownloads)
        DownloadArchiv      = 'E:\Samples-Archiv\Downloads'
        Berichtsordner      = $wurzel
        ErsterStartErledigt = $false
    }
}

function Get-Einstellungen {
    $e = Get-StandardEinstellungen
    if (Test-Path -LiteralPath $einstellungsPfad) {
        try {
            $cfg = Get-Content -LiteralPath $einstellungsPfad -Raw -Encoding UTF8 | ConvertFrom-Json
            foreach ($p in $cfg.PSObject.Properties) {
                if ($e.Contains($p.Name) -and $null -ne $p.Value -and [string]$p.Value -ne '') { $e[$p.Name] = $p.Value }
            }
        } catch { Write-FehlerLog "Einstellungen nicht lesbar: $($_.Exception.Message)" }
    }
    foreach ($k in @($e.Keys)) {
        if ($k -eq 'ErsterStartErledigt') { $e[$k] = [bool]$e[$k] }
        else { $e[$k] = ([string]$e[$k]).Trim().TrimEnd('\', '/') }
    }
    return $e
}

function Set-Einstellung([string]$name, $wert) {
    $e = Get-Einstellungen
    $e[$name] = $wert
    # Nur Abweichungen vom Standard speichern: so zeigt z. B. "Berichte" in einer neuen
    # Version weiter auf deren eigenen Programmordner und nicht auf den der alten Version.
    $std = Get-StandardEinstellungen
    $obj = [ordered]@{}
    foreach ($k in @($e.Keys)) {
        if ($k -eq 'ErsterStartErledigt' -or [string]$e[$k] -ne [string]$std[$k]) { $obj[$k] = $e[$k] }
    }
    ConvertTo-Json -InputObject $obj | Set-Content -LiteralPath $einstellungsPfad -Encoding UTF8
}

# Neue Version ohne eigene Einstellungen: die der neuesten Nachbar-Version uebernehmen
# (z. B. ...\Samples-Werkzeuge_1\Skripte\Einstellungen.json fuer Samples-Werkzeuge_2)
if (-not (Test-Path -LiteralPath $einstellungsPfad)) {
    try {
        $eltern = Split-Path -Parent $wurzel
        $alt = @(Get-ChildItem -LiteralPath $eltern -Directory -ErrorAction SilentlyContinue |
            Where-Object { $_.FullName -ne $wurzel } |
            ForEach-Object { Join-Path (Join-Path $_.FullName 'Skripte') 'Einstellungen.json' } |
            Where-Object { Test-Path -LiteralPath $_ } |
            ForEach-Object { Get-Item -LiteralPath $_ } |
            Sort-Object LastWriteTime -Descending) | Select-Object -First 1
        if ($alt) {
            Copy-Item -LiteralPath $alt.FullName -Destination $einstellungsPfad -ErrorAction Stop
            Set-Einstellung 'ErsterStartErledigt' $false   # Begruessung (mit Desktop-Verknuepfung) auch in der neuen Version
        }
    } catch { }
}

# Prueft, ob Quelle und Ziel zueinander passen. Liefert eine Fehlermeldung oder ''.
function Test-QuelleZiel([string]$quelle, [string]$ziel) {
    if (-not $quelle) { return 'Es ist keine Quelle eingestellt.' }
    if (-not $ziel)   { return 'Es ist kein Ziel eingestellt.' }
    $q = $quelle.Replace('/', '\').TrimEnd('\') + '\'
    $z = $ziel.Replace('/', '\').TrimEnd('\') + '\'
    if ($q -ieq $z) { return 'Quelle und Ziel sind derselbe Ordner.' }
    if ($z.StartsWith($q, [StringComparison]::OrdinalIgnoreCase)) { return 'Das Ziel darf nicht innerhalb der Quelle liegen.' }
    if ($q.StartsWith($z, [StringComparison]::OrdinalIgnoreCase)) { return 'Die Quelle darf nicht innerhalb des Ziels liegen.' }
    return ''
}

# ---------------------------------------------------------------------------
# Protokolle
# ---------------------------------------------------------------------------
# Neueste Datei nach Dateinamen (enthaelt Datum und Uhrzeit)
function Get-NeuestesProtokoll([string]$filter, [string[]]$ordner = @($protokollOrdner)) {
    @(foreach ($o in $ordner) {
        if ($o -and (Test-Path -LiteralPath $o)) { Get-ChildItem -LiteralPath $o -Filter $filter -File -ErrorAction SilentlyContinue }
    }) | Sort-Object Name -Descending | Select-Object -First 1
}

function Get-Protokollzeit($datei) {
    if ($datei.Name -match '_(\d{4}-\d{2}-\d{2})_(\d{2})(\d{2})(\d{2})?\.csv$') {
        try { return [datetime]::ParseExact("$($Matches[1]) $($Matches[2]):$($Matches[3])", 'yyyy-MM-dd HH:mm', $null) } catch { }
    }
    return $datei.LastWriteTime
}

# Ja/Nein-Abfrage in der Konsole, Standard ist Nein
function Read-JaNein([string]$frage) {
    $a = Read-Host "$frage (J/N, Standard N)"
    return ($a -match '^\s*[jJyY]')
}
