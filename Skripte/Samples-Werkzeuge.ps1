#Requires -Version 5.1
# (c) 2026 Herbert Stoecker. Kostenlos nutzbar. Bitte nur als Link auf die offizielle Download-Seite weitergeben; Verkauf und Veroeffentlichung geaenderter Fassungen nur mit Zustimmung.
<#
.SYNOPSIS
    Samples-Werkzeuge (Version 2): Oberfläche für Sortieren, Inventur mit Bericht, Duplikate und Einstellungen.

.DESCRIPTION
    Start per Doppelklick auf "GUI_Samples-Werkzeuge.cmd" im Programmordner oder über die
    Desktop-Verknüpfung. Die Skripte laufen jeweils in einem eigenen Fenster, zeigen zuerst
    eine Vorschau und fragen vor jeder Änderung nach.
#>
$ErrorActionPreference = 'Continue'

# Eigenes Konsolenfenster ausblenden (falls Windows es trotz -WindowStyle Hidden anzeigt)
try {
    Add-Type -Namespace SW -Name Fenster -MemberDefinition '[DllImport("kernel32.dll")] public static extern IntPtr GetConsoleWindow(); [DllImport("user32.dll")] public static extern bool ShowWindow(IntPtr h, int n);' -ErrorAction Stop
    $kf = [SW.Fenster]::GetConsoleWindow()
    if ($kf -ne [IntPtr]::Zero) { [void][SW.Fenster]::ShowWindow($kf, 0) }
} catch { }

try {
    Add-Type -AssemblyName System.Windows.Forms
    Add-Type -AssemblyName System.Drawing
    [System.Windows.Forms.Application]::EnableVisualStyles()
} catch {
    Write-Host "Die Oberfläche kann nicht geladen werden: $($_.Exception.Message)"
    exit 1
}

# Gemeinsame Pfade und Einstellungen (siehe Gemeinsam.ps1)
. (Join-Path $PSScriptRoot 'Gemeinsam.ps1')
$basis = $wurzel

# Internet-Markierung (heruntergeladene ZIP-Datei) von allen Dateien entfernen
try { Get-ChildItem -LiteralPath $wurzel -Recurse -File -ErrorAction SilentlyContinue | Unblock-File -ErrorAction SilentlyContinue } catch { }

$psExe = Join-Path $PSHOME 'powershell.exe'
if (-not (Test-Path -LiteralPath $psExe)) { $psExe = 'powershell.exe' }
# Klassische Konsole: dort wirkt -WindowStyle Hidden auch, wenn Windows Terminal Standard ist
$conhost      = Join-Path $env:SystemRoot 'System32\conhost.exe'
$verknuepfung = Join-Path ([Environment]::GetFolderPath('Desktop')) 'Samples-Werkzeuge.lnk'
$symbolQuelle = $psExe
$dokuPfad     = Join-Path $wurzel 'Dokumentation Samples-Werkzeuge.rtf'

# ---------------------------------------------------------------------------
# Hilfsfunktionen
# ---------------------------------------------------------------------------
function Show-Meldung([string]$text, [string]$art = 'Information') {
    [void][System.Windows.Forms.MessageBox]::Show($text, 'Samples-Werkzeuge', 'OK', $art)
}
function Show-Frage([string]$text) {
    return ([System.Windows.Forms.MessageBox]::Show($text, 'Samples-Werkzeuge', 'YesNo', 'Question', 'Button2') -eq 'Yes')
}

# Skript in eigenem Fenster starten; das Fenster bleibt bis Enter offen
function Start-Skript([string]$datei, [string]$argumente = '', [string]$titel = 'Samples-Werkzeuge') {
    $pfad = Join-Path $skriptOrdner $datei
    if (-not (Test-Path -LiteralPath $pfad)) { Show-Meldung "Datei nicht gefunden:`n$pfad" 'Error'; return $false }
    $p = $pfad.Replace("'", "''")
    $t = $titel.Replace("'", "''")
    $befehl = "`$Host.UI.RawUI.WindowTitle = '$t'; try { & '$p' $argumente } catch { Write-Host ''; Write-Host ('FEHLER: ' + `$_.Exception.Message) -ForegroundColor Red }; Write-Host ''; `$null = Read-Host '  Fertig. Fenster mit Enter schliessen'"
    $kodiert = [Convert]::ToBase64String([Text.Encoding]::Unicode.GetBytes($befehl))
    try {
        Start-Process -FilePath $psExe -ArgumentList "-NoProfile -ExecutionPolicy Bypass -EncodedCommand $kodiert" -WorkingDirectory $basis -ErrorAction Stop
        return $true
    } catch {
        Show-Meldung "Start fehlgeschlagen:`n$($_.Exception.Message)" 'Error'
        return $false
    }
}

# Neuesten Bericht oeffnen (fehlt die HTML-Datei, wird sie aus der Liste neu erzeugt)
function Open-Bericht {
    $c = Get-NeuesteInventur 'Sample'
    if (-not $c) { Show-Meldung 'Noch keine Inventur vorhanden.' 'Warning'; return }
    $html = [IO.Path]::ChangeExtension($c.FullName, '.html')
    if (-not (Test-Path -LiteralPath $html)) {
        $form.Cursor = 'WaitCursor'
        try { Start-Process -FilePath $psExe -ArgumentList "-NoProfile -ExecutionPolicy Bypass -File `"$(Join-Path $skriptOrdner 'Inventur.ps1')`" -NurBericht" -WindowStyle Hidden -Wait } catch { }
        $form.Cursor = 'Default'
    }
    if (Test-Path -LiteralPath $html) { Open-Pfad $html } else { Show-Meldung 'Der Bericht konnte nicht erzeugt werden.' 'Error' }
}

function Open-Pfad([string]$pfad) {
    if (-not $pfad -or -not (Test-Path -LiteralPath $pfad)) { Show-Meldung "Nicht vorhanden:`n$pfad" 'Warning'; return }
    try { Invoke-Item -LiteralPath $pfad } catch { Show-Meldung "Öffnen fehlgeschlagen:`n$($_.Exception.Message)" 'Error' }
}

function New-DesktopVerknuepfung([switch]$Still) {
    try {
        $sh = New-Object -ComObject WScript.Shell
        $s = $sh.CreateShortcut($verknuepfung)
        $psArg = "-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File `"$(Join-Path $skriptOrdner 'Samples-Werkzeuge.ps1')`""
        if (Test-Path -LiteralPath $conhost) { $s.TargetPath = $conhost; $s.Arguments = "`"$psExe`" $psArg" }
        else { $s.TargetPath = $psExe; $s.Arguments = $psArg }
        $s.WorkingDirectory = $basis
        if (Test-Path -LiteralPath $symbolQuelle) { $s.IconLocation = "$symbolQuelle,0" }
        $s.Description = "Samples sortieren und verwalten (Version $ProgrammVersion)"
        $s.WindowStyle = 7
        $s.Save()
        if (-not $Still) { Show-Meldung "Die Verknüpfung 'Samples-Werkzeuge' auf dem Desktop öffnet jetzt diese Version." }
    } catch {
        Show-Meldung "Verknüpfung konnte nicht angelegt werden:`n$($_.Exception.Message)" 'Error'
    }
}

# Vor Sortieren/Duplikaten: Ordner pruefen und verstaendlich melden
function Test-OrdnerBereit([switch]$NurQuelle) {
    $e = Get-Einstellungen
    if (-not (Test-Path -LiteralPath $e.Quelle)) {
        Show-Meldung "Der Quellordner wurde nicht gefunden:`n$($e.Quelle)`n`nBitte unter 'Einstellungen' den richtigen Ordner wählen." 'Warning'
        return $false
    }
    if (-not $NurQuelle) {
        $f = Test-QuelleZiel $e.Quelle $e.Ziel
        if ($f) { Show-Meldung "$f`n`nBitte unter 'Einstellungen' korrigieren." 'Warning'; return $false }
        $zs = Get-OrdnerStatus $e.Ziel
        if ($zs.Fehlt) { Show-Meldung "Der Zielordner ist nicht erreichbar:`n$($e.Ziel)`n$($zs.Text)`n`nBitte unter 'Einstellungen' den richtigen Ordner wählen." 'Warning'; return $false }
    }
    return $true
}

# ---------------------------------------------------------------------------
# Dialog: Begruessung beim ersten Start
# ---------------------------------------------------------------------------
function Show-Begruessung {
    $d = New-Object System.Windows.Forms.Form
    $d.Text = 'Willkommen'
    $d.StartPosition = 'CenterParent'
    $d.FormBorderStyle = 'FixedDialog'
    $d.MaximizeBox = $false; $d.MinimizeBox = $false
    $d.ClientSize = New-Object System.Drawing.Size(520, 418)
    $d.Font = $schrift
    $d.BackColor = [System.Drawing.Color]::White

    $t = New-Object System.Windows.Forms.Label
    $t.Text = "Samples-Werkzeuge $ProgrammVersion"
    $t.Font = $schriftTitel
    $t.Location = New-Object System.Drawing.Point(18, 14); $t.AutoSize = $true
    $d.Controls.Add($t)

    $txt = "Dieses Programm kopiert Sample-Packs aus einem Quellordner sortiert nach Instrument in eine " +
           "Sample-Bibliothek und entfernt auf Wunsch doppelte Samples im Quellordner.`n`n" +
           "Bitte zuerst unter 'Einstellungen' prüfen, ob Quelle und Ziel stimmen.`n`n" +
           "Vor jeder Änderung zeigt das Programm eine Vorschau und fragt nach. Beim Sortieren wird nur kopiert, " +
           "nichts gelöscht oder überschrieben. Doppelte Samples gehen in den Windows-Papierkorb. " +
           "Die Nutzung erfolgt auf eigene Verantwortung.`n`n" +
           $Urheberhinweis
    $l = New-Object System.Windows.Forms.Label
    $l.Text = $txt
    $l.Location = New-Object System.Drawing.Point(20, 56)
    $l.Size = New-Object System.Drawing.Size(480, 250)
    $d.Controls.Add($l)

    $dl = New-Object System.Windows.Forms.LinkLabel
    $dl.Text = "Download-Seite: $DownloadSeite"
    $dl.Location = New-Object System.Drawing.Point(20, 310); $dl.AutoSize = $true
    $dl.Add_LinkClicked({ try { Start-Process $DownloadSeite } catch { } })
    $d.Controls.Add($dl)

    $cb = New-Object System.Windows.Forms.CheckBox
    $cb.Text = 'Verknüpfung auf dem Desktop anlegen'
    $lnkZiel = ''
    if (Test-Path -LiteralPath $verknuepfung) { try { $lnkZiel = (New-Object -ComObject WScript.Shell).CreateShortcut($verknuepfung).Arguments } catch { } }
    $cb.Checked = -not ($lnkZiel -like "*$skriptOrdner*")
    $cb.Location = New-Object System.Drawing.Point(20, 340); $cb.AutoSize = $true
    $d.Controls.Add($cb)

    $ok = New-Object System.Windows.Forms.Button
    $ok.Text = 'Los geht''s'; $ok.FlatStyle = 'System'
    $ok.Location = New-Object System.Drawing.Point(390, 372); $ok.Size = New-Object System.Drawing.Size(110, 32)
    $ok.DialogResult = 'OK'
    $d.Controls.Add($ok)
    $d.AcceptButton = $ok

    [void]$d.ShowDialog($form)
    if ($cb.Checked) { New-DesktopVerknuepfung -Still }
    $d.Dispose()
    try { Set-Einstellung 'ErsterStartErledigt' $true } catch { }
    Update-Status
}

# ---------------------------------------------------------------------------
# Hauptfenster (Aufbau von oben nach unten, Hoehen ergeben sich automatisch)
# ---------------------------------------------------------------------------
$schrift      = New-Object System.Drawing.Font('Segoe UI', 9.5)
$schriftFett  = New-Object System.Drawing.Font('Segoe UI', 9.5, [System.Drawing.FontStyle]::Bold)
$schriftTitel = New-Object System.Drawing.Font('Segoe UI Semibold', 14)
$breite = 560

$form = New-Object System.Windows.Forms.Form
$form.Text = "Samples-Werkzeuge $ProgrammVersion"
$form.StartPosition = 'CenterScreen'
$form.FormBorderStyle = 'FixedDialog'
$form.MaximizeBox = $false
$form.Font = $schrift
$form.BackColor = [System.Drawing.Color]::White
try { if (Test-Path -LiteralPath $symbolQuelle) { $form.Icon = [System.Drawing.Icon]::ExtractAssociatedIcon($symbolQuelle) } } catch { }

$tipp = New-Object System.Windows.Forms.ToolTip
$tipp.AutoPopDelay = 15000

$titel = New-Object System.Windows.Forms.Label
$titel.Text = 'Samples-Werkzeuge'
$titel.Font = $schriftTitel
$titel.Location = New-Object System.Drawing.Point(20, 14)
$titel.AutoSize = $true
$form.Controls.Add($titel)

$unter = New-Object System.Windows.Forms.Label
$unter.Text = "Version $ProgrammVersion - Sortieren, Inventur, Bericht und Bereinigung"
$unter.ForeColor = [System.Drawing.Color]::DimGray
$unter.Location = New-Object System.Drawing.Point(22, 46)
$unter.AutoSize = $true
$form.Controls.Add($unter)

$y = 78
function New-Gruppe([string]$text) {
    $g = New-Object System.Windows.Forms.GroupBox
    $g.Text = $text
    $g.Font = $schriftFett
    $g.Location = New-Object System.Drawing.Point(18, $script:y)
    $g.Width = $breite - 36
    $form.Controls.Add($g)
    return $g
}
function Close-Gruppe($g, [int]$innenHoehe) {
    $g.Height = $innenHoehe
    $script:y += $innenHoehe + 10
}
function New-Knopf($gruppe, [string]$text, [int]$spalte, [int]$gy, [string]$hinweis, [scriptblock]$aktion) {
    $b = New-Object System.Windows.Forms.Button
    $b.Text = $text
    $b.Font = $schrift
    $bw = [int](($breite - 36 - 42) / 2)
    $b.Location = New-Object System.Drawing.Point((14 + $spalte * ($bw + 14)), $gy)
    $b.Size = New-Object System.Drawing.Size($bw, 34)
    $b.FlatStyle = 'System'
    $b.Add_Click($aktion)
    if ($hinweis) { $tipp.SetToolTip($b, $hinweis) }
    $gruppe.Controls.Add($b)
    return $b
}

# --- Status
$gStatus = New-Gruppe 'Status'
$lblStatus = New-Object System.Windows.Forms.Label
$lblStatus.Font = $schrift
$lblStatus.Location = New-Object System.Drawing.Point(14, 24)
$lblStatus.Size = New-Object System.Drawing.Size(($breite - 36 - 28), 112)
$gStatus.Controls.Add($lblStatus)
Close-Gruppe $gStatus 144

# --- 1 Sortieren
$gSort = New-Gruppe '1  Sortieren'
$gy = 24
$null = New-Knopf $gSort 'Samples sortieren ...' 0 $gy `
    "Zeigt zuerst eine Vorschau (auch als CSV für Excel) und fragt dann, ob kopiert werden soll. Es wird nur kopiert, nichts gelöscht oder überschrieben. Bereits kopierte Dateien werden übersprungen." `
    { if (Test-OrdnerBereit) { [void](Start-Skript 'Samples-sortieren.ps1' '' 'Samples sortieren') } }
$btnProt = New-Knopf $gSort 'Letztes Protokoll öffnen' 1 $gy `
    "Öffnet das Protokoll des letzten Kopierlaufs (CSV, z. B. in Excel)." `
    { $p = Get-NeuestesProtokoll 'Protokoll_*.csv'; if ($p) { Open-Pfad $p.FullName } else { Show-Meldung 'Noch kein Kopierlauf mit dieser Version.' 'Warning' } }
$gy += 44
$null = New-Knopf $gSort 'Ziel öffnen' 0 $gy "Öffnet die sortierte Sample-Bibliothek im Explorer." { Open-Pfad (Get-Einstellungen).Ziel }
$null = New-Knopf $gSort 'Quelle öffnen' 1 $gy "Öffnet den Quellordner im Explorer." { Open-Pfad (Get-Einstellungen).Quelle }
$gy += 42
$cbRx2 = New-Object System.Windows.Forms.CheckBox
$cbRx2.Text = 'RX2 beibehalten'; $cbRx2.Font = $schrift; $cbRx2.AutoSize = $true
$cbRx2.Location = New-Object System.Drawing.Point(16, $gy)
$cbRx2.Checked = (Get-Einstellungen).RX2Beibehalten
$cbRx2.Add_CheckedChanged({ try { Set-Einstellung 'RX2Beibehalten' $cbRx2.Checked } catch { } })
$tipp.SetToolTip($cbRx2, "Haken (Standard): RX2/REX-Dateien werden mitsortiert.`nOhne Haken: RX2-Dateien, zu denen es eine WAV mit gleichem Namen gibt, werden nicht kopiert und beim Sortieren in den Papierkorb verschoben. RX2 ohne WAV-Gegenstück bleiben erhalten.")
$gSort.Controls.Add($cbRx2)
$lMac = New-Object System.Windows.Forms.Label
$lMac.Text = 'macOS-Reste gehen beim Sortieren in den Papierkorb.'
$lMac.Font = $schrift; $lMac.ForeColor = [System.Drawing.Color]::DimGray; $lMac.AutoSize = $true
$lMac.Location = New-Object System.Drawing.Point(150, ($gy + 3))
$gSort.Controls.Add($lMac)
$gy += 30
Close-Gruppe $gSort ($gy + 2)

# --- 2 Inventur und Bericht
$gInv = New-Gruppe '2  Inventur und Bericht'
$gy = 24
$null = New-Knopf $gInv 'Inventur starten' 0 $gy `
    "Erfasst alle Samples und Packs im Ziel (Audio-Eigenschaften, BPM, Tonart, Pack-Art), sucht Duplikate, vergleicht mit der letzten Inventur und erstellt Liste und HTML-Bericht. Es wird nichts verändert." `
    {
        $zs = Get-OrdnerStatus (Get-Einstellungen).Ziel
        if ($zs.Fehlt -or $zs.Text -ne 'vorhanden') { Show-Meldung "Der Zielordner ist nicht vorhanden:`n$((Get-Einstellungen).Ziel)`n`nBitte zuerst sortieren oder unter 'Einstellungen' den richtigen Ordner wählen." 'Warning'; return }
        [void](Start-Skript 'Inventur.ps1' '' 'Inventur')
    }
$btnBericht = New-Knopf $gInv 'Bericht öffnen' 1 $gy `
    "Öffnet den HTML-Bericht der neuesten Inventur im Browser: Samples, Packs und Duplikate mit Suche, Gliederung, Filtern und Abspielen." `
    { Open-Bericht }
$gy += 44
$btnCsv = New-Knopf $gInv 'Liste öffnen (Excel)' 0 $gy `
    "Öffnet die neueste Inventur als CSV-Datei (eine Zeile je Sample), z. B. in Excel." `
    { $c = Get-NeuesteInventur 'Sample'; if ($c) { Open-Pfad $c.FullName } else { Show-Meldung 'Noch keine Inventur vorhanden.' 'Warning' } }
$btnVgl = New-Knopf $gInv 'Änderungen anzeigen' 1 $gy `
    "Öffnet den Vergleich der letzten mit der vorherigen Inventur: neu, entfernt, verschoben." `
    { $c = Get-NeuesterVergleich; if ($c) { Open-Pfad $c.FullName } else { Show-Meldung 'Noch kein Vergleich vorhanden (entsteht ab der zweiten Inventur).' 'Warning' } }
$gy += 44
$null = New-Knopf $gInv 'Pack-Arten korrigieren' 0 $gy `
    "Öffnet Pack-Arten.csv. Dort lässt sich die automatisch bestimmte Pack-Art einzelner Packs überschreiben; gilt ab der nächsten Inventur." `
    {
        if (-not (Test-Path -LiteralPath $packArtenPfad)) { Set-Content -LiteralPath $packArtenPfad -Value 'Pack;Pack-Art' -Encoding UTF8 }
        Show-Meldung ("Eine Zeile je Pack: Name des Packs (wie im Bericht), Semikolon, Pack-Art.`nBeispiel:  Lofi Forest;Atmos/Field Recording`n`nMögliche Pack-Arten:`n" + ($PackArten -join ', ') + "`n`nDie Korrektur gilt ab der nächsten Inventur.")
        Open-Pfad $packArtenPfad
    }
$btnZielDup = New-Knopf $gInv 'Duplikate im Ziel entfernen ...' 1 $gy `
    "Verschiebt doppelte Samples in der Bibliothek in den Papierkorb. Grundlage ist die neueste Inventur. Je Gruppe bleibt ein Exemplar, Kits bleiben vollständig. Vorher Prüfung, Vorschau und Rückfrage." `
    { [void](Start-Skript 'Ziel-Duplikate-entfernen.ps1' '' 'Duplikate im Ziel entfernen') }
$gy += 44
Close-Gruppe $gInv ($gy + 2)

# --- 2 Duplikate
$gDup = New-Gruppe '3  Duplikate in der Quelle'
$gy = 24
$null = New-Knopf $gDup 'Duplikate entfernen ...' 0 $gy `
    "Entfernt im Quellordner die Samples, die beim Kopieren als doppelt erkannt wurden. Vorher Prüfung per Hash, Vorschau und Rückfrage. Die Dateien gehen in den Papierkorb." `
    { if (Test-OrdnerBereit -NurQuelle) { [void](Start-Skript 'Duplikate-entfernen.ps1' '' 'Duplikate entfernen') } }
$null = New-Knopf $gDup 'Papierkorb öffnen' 1 $gy `
    "Öffnet den Windows-Papierkorb. Dort lassen sich entfernte Duplikate wiederherstellen." `
    { try { Start-Process explorer.exe 'shell:RecycleBinFolder' } catch { } }
$gy += 44
$null = New-Knopf $gDup 'Protokolle öffnen' 0 $gy "Öffnet den Ordner mit allen Vorschauen und Protokollen." { Open-Pfad $protokollOrdner }
$null = New-Knopf $gDup 'Programmordner öffnen' 1 $gy "Öffnet den Programmordner im Explorer." { Open-Pfad $basis }
$gy += 44
Close-Gruppe $gDup ($gy + 2)

# --- 3 Einstellungen (Ordner)
$gEin = New-Gruppe '4  Einstellungen'
$gy = 24
$pfadFelder = @{}
foreach ($pe in $PfadEinstellungen) {
    $l = New-Object System.Windows.Forms.Label
    $l.Text = "$($pe.Text):"; $l.Font = $schrift
    $l.Location = New-Object System.Drawing.Point(14, ($gy + 4)); $l.AutoSize = $true
    $tipp.SetToolTip($l, $pe.Hinweis)
    $gEin.Controls.Add($l)

    $tb = New-Object System.Windows.Forms.TextBox
    $tb.Font = $schrift; $tb.ReadOnly = $true; $tb.BackColor = [System.Drawing.Color]::White
    $tb.Location = New-Object System.Drawing.Point(130, $gy)
    $tb.Size = New-Object System.Drawing.Size(($breite - 36 - 130 - 100), 26)
    $tipp.SetToolTip($tb, $pe.Hinweis)
    $gEin.Controls.Add($tb)
    $pfadFelder[$pe.Name] = $tb

    $b = New-Object System.Windows.Forms.Button
    $b.Text = 'Ändern ...'; $b.Font = $schrift; $b.FlatStyle = 'System'
    $b.Location = New-Object System.Drawing.Point(($breite - 36 - 94), ($gy - 2))
    $b.Size = New-Object System.Drawing.Size(80, 28)
    $b.Tag = $pe
    $b.Add_Click({
        param($sender, $ev)
        $pe = $sender.Tag
        $alt = (Get-Einstellungen)[$pe.Name]
        $dlg = New-Object System.Windows.Forms.FolderBrowserDialog
        $dlg.Description = "$($pe.Text): $($pe.Hinweis)"
        $dlg.ShowNewFolderButton = $true
        if ($alt -and (Test-Path -LiteralPath $alt)) { $dlg.SelectedPath = $alt }
        if ($dlg.ShowDialog($form) -ne 'OK') { return }
        $neu = $dlg.SelectedPath.TrimEnd('\')
        $e = Get-Einstellungen
        if ($pe.Name -eq 'Quelle') { $f = Test-QuelleZiel $neu $e.Ziel }
        elseif ($pe.Name -eq 'Ziel') { $f = Test-QuelleZiel $e.Quelle $neu }
        else { $f = '' }
        if ($f) { Show-Meldung "$f`n`nDie Einstellung wurde nicht geändert." 'Warning'; return }
        try { Set-Einstellung $pe.Name $neu } catch { Show-Meldung "Speichern fehlgeschlagen:`n$($_.Exception.Message)" 'Error' }
        Update-Status
    })
    $tipp.SetToolTip($b, "Ordner für '$($pe.Text)' auswählen. Die Auswahl wird gespeichert.")
    $gEin.Controls.Add($b)
    $gy += 32
}
$lHinweis = New-Object System.Windows.Forms.Label
$lHinweis.Text = 'Downloads und Download-Archiv werden ab Version 3 (Import) genutzt.'
$lHinweis.Font = $schrift; $lHinweis.ForeColor = [System.Drawing.Color]::DimGray
$lHinweis.Location = New-Object System.Drawing.Point(14, ($gy + 2)); $lHinweis.AutoSize = $true
$gEin.Controls.Add($lHinweis)
$gy += 28
Close-Gruppe $gEin ($gy + 4)

# --- Unten
$btnLink = New-Object System.Windows.Forms.Button
$btnLink.Location = New-Object System.Drawing.Point(18, $y)
$btnLink.Size = New-Object System.Drawing.Size(250, 34)
$btnLink.FlatStyle = 'System'
$btnLink.Add_Click({ New-DesktopVerknuepfung; Update-Status })
$tipp.SetToolTip($btnLink, "Legt die Verknüpfung `"Samples-Werkzeuge`" auf dem Desktop an bzw. lässt sie auf diese Version zeigen.")
$form.Controls.Add($btnLink)

$btnDoku = New-Object System.Windows.Forms.Button
$btnDoku.Text = 'Dokumentation'
$btnDoku.Location = New-Object System.Drawing.Point(278, $y)
$btnDoku.Size = New-Object System.Drawing.Size(144, 34)
$btnDoku.FlatStyle = 'System'
$btnDoku.Add_Click({ Open-Pfad $dokuPfad })
$tipp.SetToolTip($btnDoku, 'Öffnet die Dokumentation (RTF) mit allen Funktionen des Programms.')
$form.Controls.Add($btnDoku)

$btnZu = New-Object System.Windows.Forms.Button
$btnZu.Text = 'Schließen'
$btnZu.Location = New-Object System.Drawing.Point(($breite - 18 - 110), $y)
$btnZu.Size = New-Object System.Drawing.Size(110, 34)
$btnZu.FlatStyle = 'System'
$btnZu.Add_Click({ $form.Close() })
$form.CancelButton = $btnZu
$form.Controls.Add($btnZu)
$y += 46

# Fusszeile: Urheberhinweis und Programmordner
$fuss = New-Object System.Windows.Forms.Label
$fuss.Text = $UrheberKurz
$tipp.SetToolTip($fuss, $Urheberhinweis)
$fuss.ForeColor = [System.Drawing.Color]::Gray
$fuss.Location = New-Object System.Drawing.Point(20, $y)
$fuss.Size = New-Object System.Drawing.Size(($breite - 40), 20)
$form.Controls.Add($fuss)
$y += 20
$pfadLabel = New-Object System.Windows.Forms.Label
$pfadLabel.Text = $basis
$pfadLabel.AutoEllipsis = $true
$tipp.SetToolTip($pfadLabel, $basis)
$pfadLabel.ForeColor = [System.Drawing.Color]::Gray
$pfadLabel.Location = New-Object System.Drawing.Point(20, $y)
$pfadLabel.Size = New-Object System.Drawing.Size(($breite - 40), 20)
$form.Controls.Add($pfadLabel)
$y += 28
# Kleiner Bildschirm: Fenster begrenzen und scrollbar machen
$maxH = 0
try { $maxH = [System.Windows.Forms.Screen]::PrimaryScreen.WorkingArea.Height - 60 } catch { }
if ($maxH -gt 300 -and $y -gt $maxH) {
    $form.AutoScroll = $true
    $form.ClientSize = New-Object System.Drawing.Size(($breite + [System.Windows.Forms.SystemInformation]::VerticalScrollBarWidth), $maxH)
} else {
    $form.ClientSize = New-Object System.Drawing.Size($breite, $y)
}

# ---------------------------------------------------------------------------
# Status aktualisieren (beim Start und immer, wenn das Fenster wieder aktiv wird)
# ---------------------------------------------------------------------------
function Update-Status {
    $e = Get-Einstellungen
    foreach ($k in @($pfadFelder.Keys)) { $pfadFelder[$k].Text = [string]$e[$k] }

    $zeilen = @()
    $q = if (Test-Path -LiteralPath $e.Quelle) { 'gefunden' } else { 'NICHT GEFUNDEN - bitte unter Einstellungen wählen' }
    $zs = Get-OrdnerStatus $e.Ziel
    $z = if ($zs.Fehlt) { "$($zs.Text) - bitte unter Einstellungen wählen" } else { $zs.Text }
    $zeilen += "Quelle:  $q"
    $zeilen += "Ziel:  $z"

    $p = Get-NeuestesProtokoll 'Protokoll_*.csv'
    if ($p) { $zeilen += "Letzter Kopierlauf:  $((Get-Protokollzeit $p).ToString('dd.MM.yyyy HH:mm'))" }
    else    { $zeilen += 'Letzter Kopierlauf:  noch keiner mit dieser Version' }
    $btnProt.Enabled = [bool]$p

    $inv = Get-NeuesteInventur 'Sample'
    if ($inv) {
        $t = "Letzte Inventur:  $((Get-Protokollzeit $inv).ToString('dd.MM.yyyy HH:mm'))"
        try {
            $j = Get-Content -LiteralPath ([IO.Path]::ChangeExtension($inv.FullName, '.json')) -Raw -Encoding UTF8 | ConvertFrom-Json
            $t += " - $($j.Samples) Samples in $($j.Packs) Packs, $($j.GroesseGB) GB"
            if ([int]$j.DuplikatDateien -gt 0) { $t += ", $($j.DuplikatDateien) Duplikate" }
        } catch { }
        $zeilen += $t
    } else { $zeilen += 'Letzte Inventur:  noch keine - "Inventur starten"' }
    $btnBericht.Enabled = [bool]$inv
    $btnCsv.Enabled = [bool]$inv
    $btnVgl.Enabled = [bool](Get-NeuesterVergleich)
    $btnZielDup.Enabled = [bool]$inv
    $cbRx2.Checked = $e.RX2Beibehalten

    $dp = Get-NeuestesProtokoll 'Duplikate-entfernt_*.csv'
    if ($dp) { $zeilen += "Duplikate in der Quelle zuletzt entfernt:  $((Get-Protokollzeit $dp).ToString('dd.MM.yyyy HH:mm'))" }

    $ziel = ''
    if (Test-Path -LiteralPath $verknuepfung) {
        try { $ziel = (New-Object -ComObject WScript.Shell).CreateShortcut($verknuepfung).Arguments } catch { }
    }
    if (-not (Test-Path -LiteralPath $verknuepfung)) {
        $zeilen += 'Desktop-Verknüpfung:  noch nicht angelegt'
        $btnLink.Text = 'Desktop-Verknüpfung anlegen'
    } elseif ($ziel -like "*$skriptOrdner*") {
        $zeilen += 'Desktop-Verknüpfung:  vorhanden (öffnet diese Version)'
        $btnLink.Text = 'Desktop-Verknüpfung erneuern'
    } else {
        $zeilen += 'Desktop-Verknüpfung:  zeigt auf eine andere Version'
        $btnLink.Text = "Verknüpfung auf Version $ProgrammVersion umstellen"
    }
    $lblStatus.Text = $zeilen -join "`n"
}

$einst = Get-Einstellungen
$form.Add_Activated({ Update-Status })
$form.Add_Shown({
    $form.TopMost = $true; $form.Activate(); $form.BringToFront(); $form.TopMost = $false
    if (-not $einst.ErsterStartErledigt) { Show-Begruessung }
})

try {
    Update-Status
    [void]$form.ShowDialog()
} catch {
    Write-FehlerLog ("FEHLER: " + $_.Exception.Message + ' | ' + ($_.InvocationInfo.PositionMessage -replace "`r?`n", ' '))
    Show-Meldung "Unerwarteter Fehler:`n$($_.Exception.Message)`n`nDetails stehen in:`n$fehlerLog" 'Error'
} finally {
    $form.Dispose()
}
