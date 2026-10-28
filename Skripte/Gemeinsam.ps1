# (c) 2026 Herbert Stoecker. Kostenlos nutzbar. Bitte nur als Link auf die offizielle Download-Seite weitergeben; Verkauf und Veroeffentlichung geaenderter Fassungen nur mit Zustimmung.
# Gemeinsam.ps1 - gemeinsame Pfade, Einstellungen und Hilfsfunktionen der Samples-Werkzeuge (Version 2)
# Wird von allen Skripten der Samples-Werkzeuge per Dot-Sourcing geladen.
#
# Ordnerstruktur (wie bei den Plugin-Werkzeugen):
#   <Wurzel>\               nur Startdateien (*.cmd) und Dokumentation
#   <Wurzel>\Skripte\       Skripte, Einstellungen.json und Pack-Arten.csv (eigene Korrekturen)
#   <Wurzel>\Protokolle\    Vorschau-, Kopier- und Duplikat-Protokolle (CSV)
#   <Berichtsordner>\Inventuren\           Sample-Inventur_<Datum>.csv/.html/.json, Pack-Inventur_<Datum>.csv
#   <Berichtsordner>\Inventur-Vergleiche\  Inventur-Vergleich_<Datum>.csv
#   (<Berichtsordner> ist standardmaessig der Programmordner, einstellbar in der Oberflaeche)

$ProgrammVersion = '2.3.0'
$Urheberhinweis  = "$([char]0x00A9) 2026 Herbert St$([char]0x00F6)cker. Kostenlos nutzbar. Bitte nur als Link auf die offizielle Download-Seite weitergeben; Verkauf und Ver$([char]0x00F6)ffentlichung ge$([char]0x00E4)nderter Fassungen nur mit Zustimmung."
$UrheberKurz     = "$([char]0x00A9) 2026 Herbert St$([char]0x00F6)cker"
$DownloadSeite   = 'https://github.com/limerick71/sampleswerkzeuge/releases/latest'

$skriptOrdner = $PSScriptRoot
if ([string]::IsNullOrWhiteSpace($skriptOrdner)) { $skriptOrdner = (Get-Location).Path }
$wurzel           = Split-Path -Parent $skriptOrdner
$protokollOrdner  = Join-Path $wurzel 'Protokolle'
$einstellungsPfad = Join-Path $skriptOrdner 'Einstellungen.json'
$fehlerLog        = Join-Path $skriptOrdner 'Fehler.log'
$packArtenPfad    = Join-Path $skriptOrdner 'Pack-Arten.csv'

# Audiodateien und macOS-Reste (gemeinsam fuer Sortieren und Inventur)
$RxAudio    = '\.(wav|aiff?|mp3|flac|ogg|rx2|rex|m4a)$'
$RxRx2      = '\.(rx2|rex)$'
$PackArten  = @('Drum-Kit', 'One-Shot-Pack', 'Loop-Pack', 'Construction Kit', 'Melodie/Instrument', 'Vocal-Pack',
                'Atmos/Field Recording', 'FX-Pack', 'MIDI-Pack', 'Song/Playalong', 'gemischt')
# Kandidat nach Name: ._-Datei, .DS_Store oder Inhalt eines __MACOSX-Ordners
function Test-MacRestName([string]$pfad) {
    $n = [IO.Path]::GetFileName($pfad)
    return ($n -eq '.DS_Store' -or $n.StartsWith('._') -or $pfad -match '[\\/]__MACOSX([\\/]|$)')
}
# Pruefung ueber den Dateikopf: 'mac' (sicher ein macOS-Rest), 'unklar' (nur der Name passt) oder '' (kein Kandidat).
# AppleDouble 00 05 16 07, AppleSingle 00 05 16 00, .DS_Store: 00 00 00 01 "Bud1"
function Get-MacRestArt([string]$pfad) {
    if (-not (Test-MacRestName $pfad)) { return '' }
    $b = New-Object byte[] 8; $n = 0
    try { $fs = [IO.File]::OpenRead($pfad); try { $n = $fs.Read($b, 0, 8) } finally { $fs.Dispose() } } catch { return 'unklar' }
    if ($n -ge 4 -and $b[0] -eq 0 -and $b[1] -eq 5 -and $b[2] -eq 0x16 -and ($b[3] -eq 7 -or $b[3] -eq 0)) { return 'mac' }
    if ($n -ge 8 -and [Text.Encoding]::ASCII.GetString($b, 4, 4) -eq 'Bud1') { return 'mac' }
    return 'unklar'
}
# Zusaetzliche Formate neben der WAV (SRT-06): Dateiendung -> Einstellung "behalten"
$FormatEinstellung = @{ '.rx2' = 'RX2Beibehalten'; '.rex' = 'RX2Beibehalten'; '.mp3' = 'MP3Beibehalten'; '.aif' = 'AIFFBeibehalten'; '.aiff' = 'AIFFBeibehalten' }
$FormatName = @{ 'RX2Beibehalten' = 'RX2'; 'MP3Beibehalten' = 'MP3'; 'AIFFBeibehalten' = 'AIFF' }

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

function Get-StandardDokumente {
    try { $d = [Environment]::GetFolderPath('MyDocuments'); if ($d) { return $d } } catch { }
    if ($env:USERPROFILE) { return (Join-Path $env:USERPROFILE 'Documents') }
    return 'C:\'
}

# Standardordner ab 2.1: im Ordner Dokumente des angemeldeten Benutzers (erleichtert Tests auf
# beliebigen Rechnern). Bis 2.0 waren es E:\Sounds und Samples, E:\Samples, E:\Samples-Archiv\Downloads.
$AlteStandardOrdner = @{ Quelle = 'E:\Sounds und Samples'; Ziel = 'E:\Samples'; DownloadArchiv = 'E:\Samples-Archiv\Downloads' }

function Get-StandardEinstellungen {
    $dok = Get-StandardDokumente
    return [ordered]@{
        Quelle              = ([IO.Path]::Combine($dok, 'Quelle_Samples'))
        Ziel                = ([IO.Path]::Combine($dok, 'Ziel_Samples'))
        Downloads           = (Get-StandardDownloads)
        DownloadArchiv      = ([IO.Path]::Combine($dok, 'Z_Download_Archiv'))
        Berichtsordner      = $wurzel
        RX2Beibehalten      = $true
        MP3Beibehalten      = $true
        AIFFBeibehalten     = $true
        ErsterStartErledigt = $false
    }
}

function Get-Einstellungen {
    $e = Get-StandardEinstellungen
    $cfg = $null
    if (Test-Path -LiteralPath $einstellungsPfad) {
        try {
            $cfg = Get-Content -LiteralPath $einstellungsPfad -Raw -Encoding UTF8 | ConvertFrom-Json
            foreach ($p in $cfg.PSObject.Properties) {
                if ($e.Contains($p.Name) -and $null -ne $p.Value -and [string]$p.Value -ne '') { $e[$p.Name] = $p.Value }
            }
            # Einstellungen aus einer Version bis 2.0: Ordner, die dort dem alten Standard (E:) entsprachen,
            # sind nicht gespeichert - fuer sie gilt weiter der alte Standard
            if (-not $cfg.PSObject.Properties['Standard21']) {
                foreach ($k in $AlteStandardOrdner.Keys) { if (-not $cfg.PSObject.Properties[$k]) { $e[$k] = $AlteStandardOrdner[$k] } }
            }
        } catch { Write-FehlerLog "Einstellungen nicht lesbar: $($_.Exception.Message)" }
    }
    foreach ($k in @($e.Keys)) {
        if ($k -in 'ErsterStartErledigt', 'RX2Beibehalten', 'MP3Beibehalten', 'AIFFBeibehalten') { $e[$k] = ([string]$e[$k]) -notin 'False', '0', '' }
        else { $e[$k] = ([string]$e[$k]).Trim().TrimEnd('\', '/') }
    }
    # Quellenliste (QLN-04, ab 2.3): je Eintrag Pfad, Aktiv, Herkunft. Fehlt sie (Einstellungen bis 2.2),
    # wird die bisherige einzelne Quelle zur ersten Zeile.
    $liste = New-Object System.Collections.Generic.List[object]
    if ($cfg -and $cfg.PSObject.Properties['Quellen'] -and $cfg.Quellen) {
        foreach ($q in @($cfg.Quellen)) {
            $pf = ([string]$q.Pfad).Trim().TrimEnd('\', '/')
            if (-not $pf) { continue }
            $liste.Add([pscustomobject]@{ Pfad = $pf; Aktiv = (([string]$q.Aktiv) -notin 'False', '0', ''); Herkunft = $(if ($q.Herkunft) { [string]$q.Herkunft } else { 'manuell' }) })
        }
    }
    if ($liste.Count -eq 0 -and $e.Quelle) { $liste.Add([pscustomobject]@{ Pfad = $e.Quelle; Aktiv = $true; Herkunft = 'manuell' }) }
    $e.Add('Quellen', [object[]]$liste.ToArray())
    # "Quelle" bleibt fuer aeltere Stellen: erste aktive Quelle
    $erste = @($liste | Where-Object { $_.Aktiv }) | Select-Object -First 1
    if ($erste) { $e.Quelle = $erste.Pfad }
    return $e
}

# Aktive Quellen als Pfadliste
function Get-AktiveQuellen { @((Get-Einstellungen).Quellen | Where-Object { $_.Aktiv } | ForEach-Object { $_.Pfad }) }

# Quellenliste speichern (Liste von Objekten mit Pfad, Aktiv, Herkunft)
function Set-Quellen($liste) {
    $sauber = @($liste | ForEach-Object { [ordered]@{ Pfad = [string]$_.Pfad; Aktiv = [bool]$_.Aktiv; Herkunft = [string]$_.Herkunft } })
    Set-Einstellung 'Quellen' $sauber
}

# Prueft einen neuen Quellordner gegen Ziel und vorhandene Quellen. Liefert Fehlertext oder ''.
function Test-NeueQuelle([string]$pfad, $quellen, [string]$ziel, [string]$ausser = '') {
    $f = Test-QuelleZiel $pfad $ziel
    if ($f) { return $f }
    $n = $pfad.Replace('/', '\').TrimEnd('\') + '\'
    foreach ($q in @($quellen)) {
        if ($ausser -and $q.Pfad -ieq $ausser) { continue }
        $a = ([string]$q.Pfad).Replace('/', '\').TrimEnd('\') + '\'
        if ($a -ieq $n) { return "Dieser Ordner ist schon als Quelle eingetragen." }
        if ($n.StartsWith($a, [StringComparison]::OrdinalIgnoreCase)) { return "Der Ordner liegt innerhalb der Quelle $($q.Pfad) und wird dort schon mitgelesen." }
        if ($a.StartsWith($n, [StringComparison]::OrdinalIgnoreCase)) { return "Die Quelle $($q.Pfad) liegt innerhalb dieses Ordners. Bitte zuerst diese Quelle entfernen." }
    }
    return ''
}

function Set-Einstellung([string]$name, $wert) {
    $e = Get-Einstellungen
    $e[$name] = $wert
    # Nur Abweichungen vom Standard speichern: so zeigt z. B. "Berichte" in einer neuen
    # Version weiter auf deren eigenen Programmordner und nicht auf den der alten Version.
    $std = Get-StandardEinstellungen
    if ($name -eq 'Quellen') {
        $erste = @($wert | Where-Object { $_.Aktiv }) | Select-Object -First 1
        if ($erste) { $e.Quelle = [string]$erste.Pfad }
    }
    $obj = [ordered]@{ Standard21 = $true }
    foreach ($k in @($e.Keys)) {
        # Quelle, Ziel und Quellen immer speichern, alles andere nur, wenn es vom Standard abweicht
        if ($k -in 'ErsterStartErledigt', 'Quelle', 'Ziel', 'Quellen' -or [string]$e[$k] -ne [string]$std[$k]) { $obj[$k] = $e[$k] }
    }
    if ($obj.Contains('Quellen')) { $obj['Quellen'] = @($obj['Quellen'] | ForEach-Object { [ordered]@{ Pfad = [string]$_.Pfad; Aktiv = [bool]$_.Aktiv; Herkunft = [string]$_.Herkunft } }) }
    ConvertTo-Json -InputObject $obj -Depth 5 | Set-Content -LiteralPath $einstellungsPfad -Encoding UTF8
}

# Neue Version ohne eigene Pack-Arten-Korrekturen: die der neuesten Nachbar-Version uebernehmen
if (-not (Test-Path -LiteralPath $packArtenPfad)) {
    try {
        $alt = @(Get-ChildItem -LiteralPath (Split-Path -Parent $wurzel) -Directory -ErrorAction SilentlyContinue |
            Where-Object { $_.FullName -ne $wurzel } |
            ForEach-Object { Join-Path (Join-Path $_.FullName 'Skripte') 'Pack-Arten.csv' } |
            Where-Object { Test-Path -LiteralPath $_ } | ForEach-Object { Get-Item -LiteralPath $_ } |
            Sort-Object LastWriteTime -Descending) | Select-Object -First 1
        if ($alt) { Copy-Item -LiteralPath $alt.FullName -Destination $packArtenPfad -ErrorAction Stop }
    } catch { }
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

# Zustand eines Ordners fuer Status und Pruefung: Text und ob er unerreichbar ist
# (Laufwerk fehlt). Ein fehlender Ordner auf vorhandenem Laufwerk gilt als "wird angelegt".
function Get-OrdnerStatus([string]$pfad) {
    if (-not $pfad) { return @{ Text = 'nicht eingestellt'; Fehlt = $true } }
    if (Test-Path -LiteralPath $pfad) { return @{ Text = 'vorhanden'; Fehlt = $false } }
    $root = ''
    try { $root = [IO.Path]::GetPathRoot($pfad) } catch { }
    if (-not $root -or -not (Test-Path -LiteralPath $root)) {
        $lw = if ($root) { $root.TrimEnd('\', '/') } else { $pfad }
        return @{ Text = "NICHT GEFUNDEN (Laufwerk $lw nicht vorhanden)"; Fehlt = $true }
    }
    return @{ Text = 'noch nicht vorhanden (wird beim Kopieren angelegt)'; Fehlt = $false }
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

# ---------------------------------------------------------------------------
# Inventur-Dateien
# ---------------------------------------------------------------------------
function Get-InventurOrdner  { Join-Path (Get-Einstellungen).Berichtsordner 'Inventuren' }
function Get-VergleichOrdner { Join-Path (Get-Einstellungen).Berichtsordner 'Inventur-Vergleiche' }
function Get-NeuesteInventur([string]$art = 'Sample') {
    $o = Get-InventurOrdner
    if (-not (Test-Path -LiteralPath $o)) { return $null }
    Get-ChildItem -LiteralPath $o -Filter "$art-Inventur_*.csv" -File -ErrorAction SilentlyContinue |
        Sort-Object Name -Descending | Select-Object -First 1
}
function Get-NeuesterVergleich {
    $o = Get-VergleichOrdner
    if (-not (Test-Path -LiteralPath $o)) { return $null }
    Get-ChildItem -LiteralPath $o -Filter 'Inventur-Vergleich_*.csv' -File -ErrorAction SilentlyContinue |
        Sort-Object Name -Descending | Select-Object -First 1
}

# ---------------------------------------------------------------------------
# Papierkorb (unter Windows), im Testmodus (Umgebungsvariable SW_PAPIERKORB) ein Ordner
# ---------------------------------------------------------------------------
function Send-Papierkorb([string]$pfad) {
    if ($env:SW_PAPIERKORB) {
        $ziel = Join-Path $env:SW_PAPIERKORB ([guid]::NewGuid().ToString('N') + '_' + [IO.Path]::GetFileName($pfad))
        Move-Item -LiteralPath $pfad -Destination $ziel -Force
        return
    }
    Add-Type -AssemblyName Microsoft.VisualBasic
    if (Test-Path -LiteralPath $pfad -PathType Container) {
        [Microsoft.VisualBasic.FileIO.FileSystem]::DeleteDirectory($pfad, 'OnlyErrorDialogs', 'SendToRecycleBin')
    } else {
        [Microsoft.VisualBasic.FileIO.FileSystem]::DeleteFile($pfad, 'OnlyErrorDialogs', 'SendToRecycleBin')
    }
}

# Sammelordner in der Quelle: darin liegen die Packs eine Ebene tiefer
$SammelOrdner = @('Drumloops', 'Lofi Sounds - Free Sample Pack', 'Vocals')

# Schluessel "Pack|Dateiname ohne Endung" fuer den Formatabgleich (RX2/MP3/AIFF neben WAV):
# gleichnamige Dateien gelten als Gegenstueck, wenn sie im selben Pack liegen - auch wenn das Pack
# WAV und RX2 in getrennten Unterordnern liefert (z. B. "...-Wav" und "...-Rex2").
function Get-FormatSchluessel([string]$datei, [string]$quelle) {
    $rel = $datei.Substring([Math]::Min($quelle.TrimEnd([char]92, '/').Length, $datei.Length)).TrimStart([char]92, '/')
    $t = @($rel -split '[\\/]')
    $pack = if ($t[0] -in $SammelOrdner -and $t.Count -gt 2) { $t[0] + '\' + $t[1] } elseif ($t.Count -gt 1) { $t[0] } else { '' }
    return ($pack + '|' + [IO.Path]::GetFileNameWithoutExtension($datei)).ToLowerInvariant()
}

# CLN-04: Passt die Menge in den Papierkorb des Laufwerks? Liefert eine Warnung (Text) oder ''.
#   - Wechseldatentraeger und Netzlaufwerke haben keinen Papierkorb: Windows loescht dort endgueltig.
#   - "Dateien sofort loeschen" im Papierkorb eingestellt (NukeOnDelete): ebenso.
#   - Groesse: eingestellte Hoechstgroesse (MaxCapacity) bzw. Windows-Standard (ca. 10 % der ersten
#     40 GB + 5 % des Rests). Der schon belegte Teil des Papierkorbs ist nicht beruecksichtigt.
function Get-PapierkorbWarnung([string]$pfad, [long]$bytes) {
    if ($env:SW_PAPIERKORB -or -not $pfad -or $bytes -le 0) { return '' }
    try {
        $wurzelLw = [IO.Path]::GetPathRoot($pfad)
        if (-not $wurzelLw -or $wurzelLw.StartsWith('\\')) { return "Der Ordner liegt auf einem Netzlaufwerk ($wurzelLw). Dort gibt es keinen Papierkorb - Windows loescht die Dateien endgueltig." }
        $lw = $wurzelLw.Substring(0, 2)
        $vol = Get-CimInstance -ClassName Win32_Volume -Filter "DriveLetter='$lw'" -ErrorAction Stop | Select-Object -First 1
        if (-not $vol) {
            # Verbundene Netzlaufwerke (z. B. Z:) stehen nicht in Win32_Volume
            $ld = Get-CimInstance -ClassName Win32_LogicalDisk -Filter "DeviceID='$lw'" -ErrorAction SilentlyContinue | Select-Object -First 1
            if ($ld -and $ld.DriveType -eq 4) { return "Laufwerk $lw ist ein Netzlaufwerk. Dort gibt es keinen Papierkorb - Windows loescht die Dateien endgueltig." }
            if ($ld -and $ld.DriveType -eq 2) { return "Laufwerk $lw ist ein Wechseldatentraeger (z. B. USB-Stick). Dort gibt es keinen Papierkorb - Windows loescht die Dateien endgueltig." }
            return ''
        }
        if ($vol.DriveType -eq 2) { return "Laufwerk $lw ist ein Wechseldatentraeger (z. B. USB-Stick). Dort gibt es keinen Papierkorb - Windows loescht die Dateien endgueltig." }
        if ($vol.DriveType -eq 4) { return "Laufwerk $lw ist ein Netzlaufwerk. Dort gibt es keinen Papierkorb - Windows loescht die Dateien endgueltig." }
        $grenze = $null
        if ($vol.DeviceID -match '(\{[0-9A-Fa-f-]+\})') {
            $schl = "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\BitBucket\Volume\$($Matches[1])"
            if (Test-Path $schl) {
                $w = Get-ItemProperty -Path $schl -ErrorAction SilentlyContinue
                if ($w.NukeOnDelete -eq 1) { return "Fuer Laufwerk $lw ist im Papierkorb 'Dateien sofort loeschen' eingestellt. Die Dateien wuerden endgueltig geloescht." }
                if ($w.MaxCapacity) { $grenze = [long]$w.MaxCapacity * 1MB }
            }
        }
        if (-not $grenze -and $vol.Capacity) {
            $kap = [double]$vol.Capacity
            $grenze = [long]([Math]::Min($kap, 40GB) * 0.10 + [Math]::Max(0, $kap - 40GB) * 0.05)
        }
        if ($grenze -and $bytes -gt $grenze) {
            return ("Es sollen {0:N1} GB entfernt werden, der Papierkorb von Laufwerk {1} fasst nur etwa {2:N1} GB. Windows kann Dateien dann endgueltig loeschen statt sie in den Papierkorb zu legen. Tipp: in mehreren Schritten aufraeumen oder die Groesse des Papierkorbs erhoehen (Rechtsklick auf Papierkorb > Eigenschaften)." -f ($bytes / 1GB), $lw, ($grenze / 1GB))
        }
    } catch { }
    return ''
}

# Ja/Nein-Abfrage in der Konsole, Standard ist Nein
function Read-JaNein([string]$frage) {
    $a = Read-Host "$frage (J/N, Standard N)"
    return ($a -match '^\s*[jJyY]')
}
