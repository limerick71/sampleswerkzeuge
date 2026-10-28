# (c) 2026 Herbert Stoecker. Kostenlos nutzbar. Bitte nur als Link auf die offizielle Download-Seite weitergeben; Verkauf und Veroeffentlichung geaenderter Fassungen nur mit Zustimmung.
<#
.SYNOPSIS
  Kleiner lokaler Dienst fuer den HTML-Bericht (Samples-Werkzeuge 2.1).
  - Nur auf diesem Rechner erreichbar (127.0.0.1, zufaelliger Port), jede Anfrage braucht einen
    zufaelligen Schluessel aus der Adresse. Andere Webseiten koennen den Dienst nicht ansprechen.
  - Liefert den Bericht der neuesten Inventur und die Audiodateien zum Abspielen.
  - Entfernt im Bericht markierte Duplikate: Pruefung (liegt im Ziel, ein identisches Exemplar bleibt
    erhalten), dann Papierkorb; Inventur-Liste und Bericht werden angepasst, Protokoll in "Protokolle".
  - Mit -Fundorte <json>: liefert den Fundort-Bericht (QLN-03) und uebernimmt angehakte Fundorte als
    Quellen, oeffnet Fundorte im Explorer und gleicht sie mit der Bibliothek ab.
  - Beendet sich, wenn der Bericht etwa 2 Minuten lang geschlossen ist.
#>
[CmdletBinding()]
param([string]$Fundorte)

$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'Gemeinsam.ps1')
. (Join-Path $PSScriptRoot 'Bericht.ps1')

$einst = Get-Einstellungen
$Ziel = $einst.Ziel.TrimEnd('\', '/')
$ZielVoll = [IO.Path]::GetFullPath($Ziel).TrimEnd('\', '/')
if ($Fundorte) {
    if (-not (Test-Path -LiteralPath $Fundorte)) { Write-FehlerLog "Bericht-Dienst: Fundorte nicht gefunden: $Fundorte"; exit 1 }
    $html = [IO.Path]::ChangeExtension($Fundorte, '.html')
    $fundDaten = [IO.File]::ReadAllText($Fundorte, [Text.Encoding]::UTF8) | ConvertFrom-Json
    $fundPfade = @{}
    foreach ($f in @($fundDaten.f)) { $fundPfade[([string]$f.p).ToLowerInvariant()] = [string]$f.p }
} else {
    $csv = Get-NeuesteInventur 'Sample'
    if (-not $csv) { Write-FehlerLog 'Bericht-Dienst: keine Inventur vorhanden'; exit 1 }
    $html = [IO.Path]::ChangeExtension($csv.FullName, '.html')
    if (-not (Test-Path -LiteralPath $html)) { $html = New-InventurBericht $csv.FullName }
}

# GUI-06: Explorer-Fenster in den Vordergrund holen (Windows erlaubt das einem Hintergrund-Prozess
# nur eingeschraenkt; der kurze Alt-Tastendruck ist der uebliche, zulaessige Weg). Klappt es nicht,
# blinkt das Fenster in der Taskleiste.
function Open-ExplorerVorne([string]$argument, [string]$ordner) {
    if ($env:SW_KEIN_BROWSER) { Add-Content -LiteralPath (Join-Path $protokollOrdner 'oeffnen-test.txt') -Value $argument -Encoding UTF8; return }
    Start-Process -FilePath 'explorer.exe' -ArgumentList $argument
    try {
        if (-not ('SamplesWerkzeuge.Fenster' -as [type])) {
            Add-Type -Namespace SamplesWerkzeuge -Name Fenster -MemberDefinition @'
[DllImport("user32.dll")] public static extern bool SetForegroundWindow(IntPtr h);
[DllImport("user32.dll")] public static extern bool ShowWindow(IntPtr h, int n);
[DllImport("user32.dll")] public static extern bool IsIconic(IntPtr h);
[DllImport("user32.dll")] public static extern void keybd_event(byte vk, byte scan, uint flags, UIntPtr extra);
'@
        }
        $shell = New-Object -ComObject Shell.Application
        $ziel = $ordner.TrimEnd('\')
        for ($v = 0; $v -lt 30; $v++) {
            Start-Sleep -Milliseconds 150
            foreach ($fen in @($shell.Windows())) {
                try { $pf = $fen.Document.Folder.Self.Path } catch { continue }
                if ($pf -and $pf.TrimEnd('\') -ieq $ziel) {
                    $h = [IntPtr]$fen.HWND
                    if ([SamplesWerkzeuge.Fenster]::IsIconic($h)) { [void][SamplesWerkzeuge.Fenster]::ShowWindow($h, 9) }
                    [SamplesWerkzeuge.Fenster]::keybd_event(0x12, 0, 0, [UIntPtr]::Zero)
                    [SamplesWerkzeuge.Fenster]::keybd_event(0x12, 0, 2, [UIntPtr]::Zero)
                    [void][SamplesWerkzeuge.Fenster]::SetForegroundWindow($h)
                    return
                }
            }
        }
    } catch { Write-FehlerLog "Bericht-Dienst: Explorer nicht nach vorne: $($_.Exception.Message)" }
}

# Abgleich eines Fundorts mit der Bibliothek: Anteil der Audiodateien, die schon im Ziel liegen
$zielIndex = $null; $hashCache = @{}
function Get-Md5([string]$p) { $k = $p.ToLowerInvariant(); if (-not $hashCache.ContainsKey($k)) { $hashCache[$k] = (Get-FileHash -LiteralPath $p -Algorithm MD5).Hash }; $hashCache[$k] }
function Get-Abgleich([string]$ort) {
    if (-not $script:zielIndex) {
        $script:zielIndex = @{}
        if (Test-Path -LiteralPath $Ziel) {
            foreach ($z in [IO.Directory]::EnumerateFiles($Ziel, '*', 'AllDirectories')) {
                if ($z -notmatch $RxAudio) { continue }
                $l = ([IO.FileInfo]$z).Length
                if (-not $script:zielIndex.ContainsKey($l)) { $script:zielIndex[$l] = New-Object System.Collections.Generic.List[string] }
                $script:zielIndex[$l].Add($z)
            }
        }
    }
    $geprueft = 0; $vorhanden = 0; $cloud = 0
    $stapel = New-Object System.Collections.Generic.Stack[string]; $stapel.Push($ort)
    while ($stapel.Count) {
        $o = $stapel.Pop()
        try { $eintr = @((New-Object IO.DirectoryInfo $o).EnumerateFileSystemInfos()) } catch { continue }
        foreach ($e in $eintr) {
            if ($e.Attributes -band [IO.FileAttributes]::Directory) { if (-not ($e.Attributes -band [IO.FileAttributes]::ReparsePoint)) { $stapel.Push($e.FullName) }; continue }
            if ($e.Name -notmatch $RxAudio -or $e.Name.StartsWith('._')) { continue }
            if ([int]$e.Attributes -band (0x400000 -bor 0x40000 -bor 0x1000)) { $cloud++; continue }   # nicht herunterladen
            $geprueft++
            $kand = $script:zielIndex[$e.Length]
            if (-not $kand) { continue }
            $h = Get-Md5 $e.FullName
            foreach ($z in $kand) { if ((Get-Md5 $z) -eq $h) { $vorhanden++; break } }
        }
    }
    return @{ geprueft = $geprueft; vorhanden = $vorhanden; cloud = $cloud }
}

$token = [guid]::NewGuid().ToString('N')
$listener = New-Object System.Net.Sockets.TcpListener([System.Net.IPAddress]::Loopback, 0)
$listener.Start()
$port = ([System.Net.IPEndPoint]$listener.LocalEndpoint).Port
$url = "http://127.0.0.1:$port/?t=$token"
Write-Host "Bericht-Dienst laeuft: $url"
if ($env:SW_URLDATEI) { Set-Content -LiteralPath $env:SW_URLDATEI -Value $url -Encoding ASCII }
if (-not $env:SW_KEIN_BROWSER) { try { Start-Process $url } catch { Write-FehlerLog "Bericht-Dienst: Browser nicht startbar: $($_.Exception.Message)" } }

$typen = @{ '.wav' = 'audio/wav'; '.mp3' = 'audio/mpeg'; '.ogg' = 'audio/ogg'; '.flac' = 'audio/flac'; '.m4a' = 'audio/mp4'; '.aif' = 'audio/aiff'; '.aiff' = 'audio/aiff' }
$utf8 = New-Object System.Text.UTF8Encoding($false)
$geloescht = New-Object System.Collections.Generic.List[object]

function Send-Antwort($strom, [int]$code, [string]$text, [string]$typ, [byte[]]$daten, [hashtable]$extra = @{}) {
    $kopf = "HTTP/1.1 $code $text`r`nContent-Type: $typ`r`nContent-Length: $($daten.Length)`r`nCache-Control: no-store`r`nConnection: close`r`n"
    foreach ($k in $extra.Keys) { $kopf += "${k}: $($extra[$k])`r`n" }
    $b = [Text.Encoding]::ASCII.GetBytes($kopf + "`r`n")
    $strom.Write($b, 0, $b.Length)
    if ($daten.Length) { $strom.Write($daten, 0, $daten.Length) }
}
function Send-Text($strom, [int]$code, [string]$text, [string]$inhalt, [string]$typ = 'text/plain; charset=utf-8') {
    Send-Antwort $strom $code $text $typ ($utf8.GetBytes($inhalt))
}

# Relativen Pfad pruefen: muss innerhalb des Ziels liegen
function Get-ZielPfad([string]$rel) {
    if (-not $rel) { return $null }
    $voll = [IO.Path]::GetFullPath((Join-Path $ZielVoll $rel))
    if (-not $voll.StartsWith($ZielVoll + [IO.Path]::DirectorySeparatorChar, [StringComparison]::OrdinalIgnoreCase)) { return $null }
    return $voll
}

# Duplikate entfernen: jede Datei nur, wenn danach noch ein identisches Exemplar existiert
function Remove-Markierte([string[]]$pfade) {
    $zeilen = @(Import-Csv -LiteralPath $csv.FullName -Delimiter ';' -Encoding UTF8)
    $nachPfad = @{}; foreach ($z in $zeilen) { $nachPfad[$z.Pfad.ToLowerInvariant()] = $z }
    $ergebnis = @()
    $weg = @{}
    foreach ($rel in $pfade) {
        $status = ''; $ok = $false
        $z = $nachPfad[([string]$rel).ToLowerInvariant()]
        $voll = Get-ZielPfad $rel
        if (-not $voll) { $status = 'abgelehnt: liegt nicht im Ziel' }
        elseif (-not $z -or -not $z.'Duplikat-Gruppe') { $status = 'abgelehnt: kein Duplikat laut Inventur' }
        elseif ($z.Typ -eq 'Kit') { $status = 'abgelehnt: liegt in einem Kit' }
        elseif (-not (Test-Path -LiteralPath $voll)) { $status = 'nicht mehr vorhanden'; $ok = $true; $weg[$rel.ToLowerInvariant()] = $true }
        else {
            $h = (Get-FileHash -LiteralPath $voll -Algorithm SHA256).Hash
            $bleibt = $null
            foreach ($a in ($zeilen | Where-Object { $_.'Duplikat-Gruppe' -eq $z.'Duplikat-Gruppe' -and $_.Pfad -ne $z.Pfad -and -not $weg.ContainsKey($_.Pfad.ToLowerInvariant()) })) {
                $av = Get-ZielPfad $a.Pfad
                if ($av -and (Test-Path -LiteralPath $av) -and (Get-FileHash -LiteralPath $av -Algorithm SHA256).Hash -eq $h) { $bleibt = $a.Pfad; break }
            }
            if (-not $bleibt) { $status = 'abgelehnt: waere das letzte Exemplar' }
            else {
                try {
                    Send-Papierkorb $voll
                    if (Test-Path -LiteralPath ($voll + '.asd')) { Send-Papierkorb ($voll + '.asd') }
                    $status = 'in den Papierkorb verschoben'; $ok = $true; $weg[$rel.ToLowerInvariant()] = $true
                    # leer gewordene Ordner entfernen
                    $o = Split-Path -Parent $voll
                    while ($o.Length -gt $ZielVoll.Length -and (Test-Path -LiteralPath $o) -and @(Get-ChildItem -LiteralPath $o -Force).Count -eq 0) { try { Send-Papierkorb $o } catch { break }; $o = Split-Path -Parent $o }
                } catch { $status = 'FEHLER: ' + $_.Exception.Message }
            }
        }
        $ergebnis += [ordered]@{ pfad = $rel; ok = $ok; status = $status }
        $geloescht.Add([pscustomobject]@{ Zeit = (Get-Date).ToString('yyyy-MM-dd HH:mm:ss'); Datei = $rel; Ergebnis = $status })
    }
    # Inventur-Liste anpassen: entfernte Zeilen raus, Gruppen mit nur noch einem Exemplar aufloesen
    if ($weg.Count) {
        $rest = @($zeilen | Where-Object { -not $weg.ContainsKey($_.Pfad.ToLowerInvariant()) })
        foreach ($g in ($rest | Where-Object { $_.'Duplikat-Gruppe' } | Group-Object 'Duplikat-Gruppe')) {
            if ($g.Count -lt 2) { foreach ($x in $g.Group) { $x.'Duplikat-Gruppe' = ''; $x.'Duplikat-Rolle' = '' } }
            elseif (-not @($g.Group | Where-Object { $_.'Duplikat-Rolle' -like 'behalten*' }).Count) { $g.Group[0].'Duplikat-Rolle' = 'behalten' }
        }
        $rest | Export-Csv -LiteralPath $csv.FullName -NoTypeInformation -Delimiter ';' -Encoding UTF8
        # Pack-Liste: Duplikat-Zahlen neu
        $packPfad = Join-Path $csv.DirectoryName ($csv.Name -replace '^Sample-', 'Pack-')
        if (Test-Path -LiteralPath $packPfad) {
            try {
                $packs = @(Import-Csv -LiteralPath $packPfad -Delimiter ';' -Encoding UTF8)
                foreach ($p in $packs) { $p.Duplikate = @($rest | Where-Object { $_.Pack -eq $p.Pack -and $_.'Duplikat-Rolle' -eq 'entfernbar' }).Count; $p.Samples = @($rest | Where-Object { $_.Pack -eq $p.Pack }).Count }
                $packs | Export-Csv -LiteralPath $packPfad -NoTypeInformation -Delimiter ';' -Encoding UTF8
            } catch { }
        }
        $jsonPfad = [IO.Path]::ChangeExtension($csv.FullName, '.json')
        if (Test-Path -LiteralPath $jsonPfad) {
            try {
                $j = Get-Content -LiteralPath $jsonPfad -Raw -Encoding UTF8 | ConvertFrom-Json
                $e = @($rest | Where-Object { $_.'Duplikat-Rolle' -eq 'entfernbar' })
                $j.Samples = $rest.Count; $j.DuplikatDateien = $e.Count
                $j.DuplikatMB = [math]::Round((($e | ForEach-Object { [double]$_.GroesseBytes } | Measure-Object -Sum).Sum) / 1MB, 1)
                $j.DuplikatGruppen = @($rest | Where-Object { $_.'Duplikat-Gruppe' } | Group-Object 'Duplikat-Gruppe').Count
                ConvertTo-Json -InputObject $j | Set-Content -LiteralPath $jsonPfad -Encoding UTF8
            } catch { }
        }
        [void](New-InventurBericht $csv.FullName)
    }
    $protokoll = Join-Path $protokollOrdner ("Bericht-entfernt_{0:yyyy-MM-dd}.csv" -f (Get-Date))
    $geloescht | Export-Csv -LiteralPath $protokoll -NoTypeInformation -Delimiter ';' -Encoding UTF8 -Append:(Test-Path -LiteralPath $protokoll)
    $geloescht.Clear()
    return $ergebnis
}

function Read-Anfrage($strom) {
    $kopf = New-Object System.Collections.Generic.List[byte]
    $b = New-Object byte[] 1
    while ($kopf.Count -lt 65536) {
        $n = $strom.Read($b, 0, 1); if ($n -le 0) { break }
        $kopf.Add($b[0])
        $c = $kopf.Count
        if ($c -ge 4 -and $kopf[$c - 4] -eq 13 -and $kopf[$c - 3] -eq 10 -and $kopf[$c - 2] -eq 13 -and $kopf[$c - 1] -eq 10) { break }
    }
    $text = [Text.Encoding]::ASCII.GetString($kopf.ToArray())
    $zeilen = $text -split "`r`n"
    $teile = $zeilen[0] -split ' '
    $h = @{}
    foreach ($z in $zeilen[1..($zeilen.Count - 1)]) { if ($z -match '^([^:]+):\s*(.*)$') { $h[$Matches[1].ToLowerInvariant()] = $Matches[2] } }
    $body = ''
    if ($h['content-length']) {
        $len = [int]$h['content-length']; $buf = New-Object byte[] $len; $gelesen = 0
        while ($gelesen -lt $len) { $n = $strom.Read($buf, $gelesen, $len - $gelesen); if ($n -le 0) { break }; $gelesen += $n }
        $body = $utf8.GetString($buf, 0, $gelesen)
    }
    $pfad = if ($teile.Count -ge 2) { $teile[1] } else { '/' }
    $abfrage = @{}
    $q = ''
    if ($pfad.Contains('?')) { $q = $pfad.Substring($pfad.IndexOf('?') + 1); $pfad = $pfad.Substring(0, $pfad.IndexOf('?')) }
    foreach ($paar in ($q -split '&')) { if ($paar -match '^([^=]+)=(.*)$') { $abfrage[$Matches[1]] = [Uri]::UnescapeDataString(($Matches[2] -replace '\+', ' ')) } }
    return @{ Methode = $teile[0]; Pfad = $pfad; Abfrage = $abfrage; Kopf = $h; Body = $body }
}

$letzter = Get-Date
$erstKontakt = $false
try {
    while ($true) {
        if (-not $listener.Pending()) {
            Start-Sleep -Milliseconds 100
            $ruhe = ((Get-Date) - $letzter).TotalSeconds
            if (($erstKontakt -and $ruhe -gt 120) -or (-not $erstKontakt -and $ruhe -gt 600)) { break }
            continue
        }
        $client = $listener.AcceptTcpClient()
        try {
            $client.ReceiveTimeout = 10000
            $strom = $client.GetStream()
            $a = Read-Anfrage $strom
            $letzter = Get-Date
            # Nur Anfragen an genau diese Adresse und mit Schluessel (Schutz vor fremden Webseiten)
            if ($a.Kopf['host'] -ne "127.0.0.1:$port" -or $a.Abfrage['t'] -ne $token) { Send-Text $strom 403 'Forbidden' 'Kein Zugriff.'; continue }
            $erstKontakt = $true
            switch ($a.Pfad) {
                '/' {
                    $inhalt = [IO.File]::ReadAllText($html, [Text.Encoding]::UTF8)
                    $inhalt = $inhalt.Replace('<script id="daten"', "<script>window.SW_DIENST={token:'$token'};</script><script id=""daten""")
                    Send-Text $strom 200 'OK' $inhalt 'text/html; charset=utf-8'
                }
                '/ping' { Send-Text $strom 200 'OK' 'ok' }
                '/datei' {
                    if ($Fundorte) { Send-Text $strom 404 'Not Found' 'Im Fundort-Bericht nicht verfügbar.'; break }
                    $voll = Get-ZielPfad $a.Abfrage['p']
                    if (-not $voll -or -not (Test-Path -LiteralPath $voll -PathType Leaf)) { Send-Text $strom 404 'Not Found' 'Datei nicht gefunden.'; break }
                    $typ = $typen[[IO.Path]::GetExtension($voll).ToLowerInvariant()]; if (-not $typ) { $typ = 'application/octet-stream' }
                    $alle = [IO.File]::ReadAllBytes($voll)
                    $bereich = $a.Kopf['range']
                    if ($bereich -match '^bytes=(\d*)-(\d*)$' -and $alle.Length -gt 0) {
                        $von = if ($Matches[1]) { [long]$Matches[1] } else { 0 }
                        $bis = if ($Matches[2]) { [math]::Min([long]$Matches[2], $alle.Length - 1) } else { $alle.Length - 1 }
                        $teil = New-Object byte[] ($bis - $von + 1); [Array]::Copy($alle, $von, $teil, 0, $teil.Length)
                        Send-Antwort $strom 206 'Partial Content' $typ $teil @{ 'Content-Range' = "bytes $von-$bis/$($alle.Length)"; 'Accept-Ranges' = 'bytes' }
                    } else { Send-Antwort $strom 200 'OK' $typ $alle @{ 'Accept-Ranges' = 'bytes' } }
                }
                '/entfernen' {
                    if ($Fundorte) { Send-Text $strom 404 'Not Found' 'Im Fundort-Bericht nicht verfügbar.'; break }
                    if ($a.Methode -ne 'POST') { Send-Text $strom 405 'Method Not Allowed' 'Nur POST.'; break }
                    $daten = $a.Body | ConvertFrom-Json
                    $erg = Remove-Markierte @($daten.pfade)
                    Send-Text $strom 200 'OK' (ConvertTo-Json -InputObject @{ ergebnisse = @($erg) } -Depth 4 -Compress) 'application/json; charset=utf-8'
                }
                '/oeffnen' {
                    # REP-09: Explorer im Ordner des Samples oeffnen und die Datei markieren (nur innerhalb des Ziels)
                    if ($a.Methode -ne 'POST') { Send-Text $strom 405 'Method Not Allowed' 'Nur POST.'; break }
                    $daten = $a.Body | ConvertFrom-Json
                    $voll = Get-ZielPfad ([string]$daten.pfad)
                    if (-not $voll) { Send-Text $strom 404 'Not Found' 'Pfad liegt nicht im Ziel.'; break }
                    if (Test-Path -LiteralPath $voll -PathType Leaf) { $arg = "/select,`"$voll`"" }
                    elseif (Test-Path -LiteralPath (Split-Path -Parent $voll)) { $arg = "`"$(Split-Path -Parent $voll)`"" }
                    else { Send-Text $strom 404 'Not Found' 'Datei und Ordner gibt es nicht mehr. Bitte neue Inventur starten.'; break }
                    Send-Text $strom 200 'OK' 'ok'
                    Open-ExplorerVorne $arg (Split-Path -Parent $voll)
                }
                '/oeffnen-ort' {
                    if ($a.Methode -ne 'POST' -or -not $Fundorte) { Send-Text $strom 405 'Method Not Allowed' 'Nicht erlaubt.'; break }
                    $pf = [string]($a.Body | ConvertFrom-Json).pfad
                    if (-not $fundPfade.ContainsKey($pf.ToLowerInvariant()) -or -not (Test-Path -LiteralPath $pf -PathType Container)) { Send-Text $strom 404 'Not Found' 'Fundort nicht gefunden.'; break }
                    Send-Text $strom 200 'OK' '{}' 'application/json; charset=utf-8'
                    Open-ExplorerVorne "`"$pf`"" $pf
                }
                '/quellen' {
                    if ($a.Methode -ne 'POST') { Send-Text $strom 405 'Method Not Allowed' 'Nur POST.'; break }
                    $ql = @((Get-Einstellungen).Quellen | ForEach-Object { @{ pfad = [string]$_.Pfad; art = (Get-QuellArtName ([string]$_.Art)) } })
                    Send-Text $strom 200 'OK' (ConvertTo-Json -InputObject @{ quellen = $ql } -Depth 4 -Compress) 'application/json; charset=utf-8'
                }
                '/uebernehmen' {
                    # QLN-03/04: angehakte Fundorte als Quellen eintragen (nur Fundorte aus diesem Bericht)
                    if ($a.Methode -ne 'POST' -or -not $Fundorte) { Send-Text $strom 405 'Method Not Allowed' 'Nicht erlaubt.'; break }
                    $erg = @()
                    $herkunft = 'aus Suchlauf ' + (Get-Date).ToString('dd.MM.yyyy')
                    foreach ($eintrag in @(($a.Body | ConvertFrom-Json).pfade)) {
                        if ($eintrag -is [string]) { $pf = $eintrag; $art = 'Sammlung' } else { $pf = [string]$eintrag.pfad; $art = Get-QuellArtName ([string]$eintrag.art) }
                        if (-not $fundPfade.ContainsKey($pf.ToLowerInvariant())) { $erg += @{ pfad = $pf; ok = $false; grund = 'kein Fundort aus diesem Bericht' }; continue }
                        if (-not (Test-Path -LiteralPath $pf -PathType Container)) { $erg += @{ pfad = $pf; ok = $false; grund = 'Ordner gibt es nicht mehr' }; continue }
                        $e2 = Get-Einstellungen
                        $f = Test-NeueQuelle $pf $e2.Quellen $e2.Ziel '' $art
                        if ($f) { $erg += @{ pfad = $pf; ok = $false; grund = $f }; continue }
                        Set-Quellen (@($e2.Quellen) + [pscustomobject]@{ Pfad = $pf; Aktiv = $true; Herkunft = $herkunft; Art = $art })
                        $erg += @{ pfad = $pf; ok = $true; grund = '' }
                    }
                    Send-Text $strom 200 'OK' (ConvertTo-Json -InputObject @{ ergebnisse = @($erg) } -Depth 4 -Compress) 'application/json; charset=utf-8'
                }
                '/abgleich' {
                    if ($a.Methode -ne 'POST' -or -not $Fundorte) { Send-Text $strom 405 'Method Not Allowed' 'Nicht erlaubt.'; break }
                    $pf = [string]($a.Body | ConvertFrom-Json).pfad
                    if (-not $fundPfade.ContainsKey($pf.ToLowerInvariant())) { Send-Text $strom 404 'Not Found' 'Fundort nicht gefunden.'; break }
                    $r = Get-Abgleich $pf
                    Send-Text $strom 200 'OK' (ConvertTo-Json -InputObject $r -Compress) 'application/json; charset=utf-8'
                }
                default { Send-Text $strom 404 'Not Found' 'Unbekannt.' }
            }
        } catch {
            Write-FehlerLog "Bericht-Dienst: $($_.Exception.Message)"
            try { Send-Text $strom 500 'Internal Server Error' ('Fehler: ' + $_.Exception.Message) } catch { }
        } finally { $client.Close() }
    }
} finally { $listener.Stop() }
