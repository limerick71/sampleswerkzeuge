#Requires -Version 5.1
# (c) 2026 Herbert Stoecker. Kostenlos nutzbar. Bitte nur als Link auf die offizielle Download-Seite weitergeben; Verkauf und Veroeffentlichung geaenderter Fassungen nur mit Zustimmung.
<#
.SYNOPSIS
    Samples-Werkzeuge (Version 2.1): Oberfläche für Sortieren, Inventur mit Bericht, Aufräumen und Einstellungen (Zahnrad).

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

# Neuesten Bericht oeffnen: ueber den lokalen Bericht-Dienst (Loeschen aus dem Bericht, Abspielen);
# klappt das nicht, wird die HTML-Datei direkt geoeffnet
function Open-Bericht {
    $c = Get-NeuesteInventur 'Sample'
    if (-not $c) { Show-Meldung 'Noch keine Inventur vorhanden.' 'Warning'; return }
    try {
        Start-Process -FilePath $psExe -ArgumentList "-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File `"$(Join-Path $skriptOrdner 'Bericht-Dienst.ps1')`"" -WindowStyle Hidden -ErrorAction Stop
    } catch {
        $html = [IO.Path]::ChangeExtension($c.FullName, '.html')
        if (Test-Path -LiteralPath $html) { Open-Pfad $html } else { Show-Meldung 'Der Bericht konnte nicht geöffnet werden.' 'Error' }
    }
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
        Show-Meldung "Der Quellordner wurde nicht gefunden:`n$($e.Quelle)`n`nBitte über ⚙ Einstellungen den richtigen Ordner wählen." 'Warning'
        return $false
    }
    if (-not $NurQuelle) {
        $f = Test-QuelleZiel $e.Quelle $e.Ziel
        if ($f) { Show-Meldung "$f`n`nBitte über ⚙ Einstellungen korrigieren." 'Warning'; return $false }
        $zs = Get-OrdnerStatus $e.Ziel
        if ($zs.Fehlt) { Show-Meldung "Der Zielordner ist nicht erreichbar:`n$($e.Ziel)`n$($zs.Text)`n`nBitte über ⚙ Einstellungen den richtigen Ordner wählen." 'Warning'; return $false }
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
    $cb.Checked = $true   # Standard: anlegen bzw. auf diese Version erneuern (W-01, 27.10.)
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
# Dialog: Einstellungen (Zahnrad) - Ordner und zusaetzliche Formate
# ---------------------------------------------------------------------------
function Show-Einstellungen {
    $d = New-Object System.Windows.Forms.Form
    $d.Text = 'Einstellungen'
    $d.StartPosition = 'CenterParent'; $d.FormBorderStyle = 'FixedDialog'
    $d.MaximizeBox = $false; $d.MinimizeBox = $false
    $d.Font = $schrift; $d.BackColor = [System.Drawing.Color]::White
    $tt = New-Object System.Windows.Forms.ToolTip; $tt.AutoPopDelay = 15000
    $w = 560; $dy = 16
    $g1 = New-Object System.Windows.Forms.GroupBox
    $g1.Text = 'Ordner'; $g1.Font = $schriftFett
    $g1.Location = New-Object System.Drawing.Point(16, $dy); $g1.Width = $w - 32
    $d.Controls.Add($g1)
    $gy = 26
    $felder = @{}
    foreach ($pe in $PfadEinstellungen) {
        $l = New-Object System.Windows.Forms.Label
        $l.Text = "$($pe.Text):"; $l.Font = $schrift; $l.AutoSize = $true
        $l.Location = New-Object System.Drawing.Point(12, ($gy + 4)); $tt.SetToolTip($l, $pe.Hinweis); $g1.Controls.Add($l)
        $tb = New-Object System.Windows.Forms.TextBox
        $tb.Font = $schrift; $tb.ReadOnly = $true; $tb.BackColor = [System.Drawing.Color]::White
        $tb.Location = New-Object System.Drawing.Point(124, $gy); $tb.Size = New-Object System.Drawing.Size(($w - 32 - 124 - 98), 26)
        $tb.Text = [string](Get-Einstellungen)[$pe.Name]; $tt.SetToolTip($tb, $pe.Hinweis); $g1.Controls.Add($tb)
        $felder[$pe.Name] = $tb
        $b = New-Object System.Windows.Forms.Button
        $b.Text = 'Ändern ...'; $b.Font = $schrift; $b.FlatStyle = 'System'
        $b.Location = New-Object System.Drawing.Point(($w - 32 - 92), ($gy - 2)); $b.Size = New-Object System.Drawing.Size(80, 28)
        $b.Tag = $pe
        $b.Add_Click({
            param($sender, $ev)
            $pe = $sender.Tag
            $alt = (Get-Einstellungen)[$pe.Name]
            $dlg = New-Object System.Windows.Forms.FolderBrowserDialog
            $dlg.Description = "$($pe.Text): $($pe.Hinweis)"; $dlg.ShowNewFolderButton = $true
            if ($alt -and (Test-Path -LiteralPath $alt)) { $dlg.SelectedPath = $alt }
            if ($dlg.ShowDialog($d) -ne 'OK') { return }
            $neu = $dlg.SelectedPath.TrimEnd('\')
            $e = Get-Einstellungen
            $f = if ($pe.Name -eq 'Quelle') { Test-QuelleZiel $neu $e.Ziel } elseif ($pe.Name -eq 'Ziel') { Test-QuelleZiel $e.Quelle $neu } else { '' }
            if ($f) { Show-Meldung "$f`n`nDie Einstellung wurde nicht geändert." 'Warning'; return }
            try { Set-Einstellung $pe.Name $neu; $felder[$pe.Name].Text = $neu } catch { Show-Meldung "Speichern fehlgeschlagen:`n$($_.Exception.Message)" 'Error' }
        })
        $tt.SetToolTip($b, "Ordner für '$($pe.Text)' auswählen. Die Auswahl wird gespeichert.")
        $g1.Controls.Add($b)
        $gy += 32
    }
    $lh = New-Object System.Windows.Forms.Label
    $lh.Text = 'Downloads und Download-Archiv werden ab Version 3 (Import) genutzt.'
    $lh.Font = $schrift; $lh.ForeColor = [System.Drawing.Color]::DimGray; $lh.AutoSize = $true
    $lh.Location = New-Object System.Drawing.Point(12, ($gy + 2)); $g1.Controls.Add($lh)
    $g1.Height = $gy + 30
    $dy += $g1.Height + 12

    $g2 = New-Object System.Windows.Forms.GroupBox
    $g2.Text = 'Formate beim Sortieren (WAV ist Standard)'; $g2.Font = $schriftFett
    $g2.Location = New-Object System.Drawing.Point(16, $dy); $g2.Width = $w - 32
    $d.Controls.Add($g2)
    $l2 = New-Object System.Windows.Forms.Label
    $l2.Text = 'Zusätzlich zur WAV behalten:'; $l2.Font = $schrift; $l2.AutoSize = $true
    $l2.Location = New-Object System.Drawing.Point(12, 30); $g2.Controls.Add($l2)
    $haken = @()
    $x = 200
    foreach ($fmt in @(@('RX2', 'RX2Beibehalten'), @('MP3', 'MP3Beibehalten'), @('AIFF', 'AIFFBeibehalten'))) {
        $cb = New-Object System.Windows.Forms.CheckBox
        $cb.Text = $fmt[0]; $cb.Font = $schrift; $cb.AutoSize = $true; $cb.Tag = $fmt[1]
        $cb.Location = New-Object System.Drawing.Point($x, 28); $cb.Checked = (Get-Einstellungen)[$fmt[1]]
        $cb.Add_CheckedChanged({ param($sender, $ev) try { Set-Einstellung $sender.Tag $sender.Checked } catch { } })
        $tt.SetToolTip($cb, "Haken: $($fmt[0])-Dateien werden mitsortiert.`nOhne Haken: Liegt im selben Pack eine WAV mit gleichem Namen (auch in einem anderen Unterordner, z. B. '...-Wav' neben '...-Rex2'), wird die $($fmt[0])-Datei nicht kopiert (sie bleibt in der Quelle). Ohne WAV-Gegenstück wird sie immer einsortiert.")
        $g2.Controls.Add($cb); $haken += $cb
        $x += 80
    }
    $bNur = New-Object System.Windows.Forms.Button
    $bNur.Text = 'Nur WAV'; $bNur.Font = $schrift; $bNur.FlatStyle = 'System'
    $bNur.Location = New-Object System.Drawing.Point(200, 60); $bNur.Size = New-Object System.Drawing.Size(110, 30)
    $bNur.Add_Click({ foreach ($c in $haken) { $c.Checked = $false } })
    $tt.SetToolTip($bNur, 'Entfernt alle drei Haken: Gibt es eine gleichnamige WAV, kommt nur die WAV in die Bibliothek.')
    $g2.Controls.Add($bNur)
    $bAlle = New-Object System.Windows.Forms.Button
    $bAlle.Text = 'Alle'; $bAlle.Font = $schrift; $bAlle.FlatStyle = 'System'
    $bAlle.Location = New-Object System.Drawing.Point(318, 60); $bAlle.Size = New-Object System.Drawing.Size(80, 30)
    $bAlle.Add_Click({ foreach ($c in $haken) { $c.Checked = $true } })
    $g2.Controls.Add($bAlle)
    $l3 = New-Object System.Windows.Forms.Label
    $l3.Text = "Die Haken gelten nur für das Sortieren. Das Sortieren verändert die Quelle nie;`nnicht kopierte Dateien entfernt man mit 'Quelle aufräumen …' (Formate dort eigens wählbar)."
    $l3.Font = $schrift; $l3.ForeColor = [System.Drawing.Color]::DimGray; $l3.AutoSize = $true
    $l3.Location = New-Object System.Drawing.Point(12, 100); $g2.Controls.Add($l3)
    $g2.Height = 146
    $dy += $g2.Height + 14

    $ok = New-Object System.Windows.Forms.Button
    $ok.Text = 'Schließen'; $ok.FlatStyle = 'System'; $ok.DialogResult = 'OK'
    $ok.Location = New-Object System.Drawing.Point(($w - 16 - 110), $dy); $ok.Size = New-Object System.Drawing.Size(110, 32)
    $d.Controls.Add($ok); $d.AcceptButton = $ok; $d.CancelButton = $ok
    $d.ClientSize = New-Object System.Drawing.Size($w, ($dy + 48))
    [void]$d.ShowDialog($form)
    $d.Dispose()
    Update-Status
}

# ---------------------------------------------------------------------------
# Dialog: Quelle aufraeumen - Auswahl der Gruppen
# ---------------------------------------------------------------------------
function Show-QuelleAufraeumen {
    if (-not (Test-OrdnerBereit -NurQuelle)) { return }
    $e = Get-Einstellungen
    $aus = @(@('RX2', 'RX2Beibehalten'), @('MP3', 'MP3Beibehalten'), @('AIFF', 'AIFFBeibehalten') | Where-Object { -not $e[$_[1]] } | ForEach-Object { $_[0] })
    $d = New-Object System.Windows.Forms.Form
    $d.Text = 'Quelle aufräumen'
    $d.StartPosition = 'CenterParent'; $d.FormBorderStyle = 'FixedDialog'
    $d.MaximizeBox = $false; $d.MinimizeBox = $false
    $d.Font = $schrift; $d.BackColor = [System.Drawing.Color]::White
    $l = New-Object System.Windows.Forms.Label
    $l.Text = "Was soll aus der Quelle in den Papierkorb?`nDanach zeigt ein Fenster die Vorschau; entfernt wird erst nach 'J'."
    $l.Location = New-Object System.Drawing.Point(16, 14); $l.AutoSize = $true
    $d.Controls.Add($l)
    $c1 = New-Object System.Windows.Forms.CheckBox
    $c1.Text = 'Duplikate (beim Kopieren als doppelt erkannt, Prüfung gegen das behaltene Exemplar)'
    $c1.Location = New-Object System.Drawing.Point(18, 60); $c1.AutoSize = $true; $c1.Checked = $true
    $d.Controls.Add($c1)
    $c2 = New-Object System.Windows.Forms.CheckBox
    $c2.Text = 'macOS-Reste (._-Dateien, .DS_Store, __MACOSX – am Dateikopf erkannt)'
    $c2.Location = New-Object System.Drawing.Point(18, 88); $c2.AutoSize = $true; $c2.Checked = $true
    $d.Controls.Add($c2)
    $c3 = New-Object System.Windows.Forms.CheckBox
    $c3.Text = 'Formate neben gleichnamiger WAV im selben Pack, deren Kopie im Ziel bestätigt ist:'
    $c3.Location = New-Object System.Drawing.Point(18, 116); $c3.AutoSize = $true; $c3.Checked = [bool]$aus.Count
    $d.Controls.Add($c3)
    # CLN-12: eigene Format-Haken, vorbelegt mit den beim Sortieren abgewaehlten Formaten
    $fHaken = @(); $x = 40
    foreach ($fmt in 'RX2', 'MP3', 'AIFF') {
        $cb = New-Object System.Windows.Forms.CheckBox
        $cb.Text = $fmt; $cb.AutoSize = $true; $cb.Location = New-Object System.Drawing.Point($x, 142)
        $cb.Checked = ($aus -contains $fmt) -or (-not $aus.Count)
        $d.Controls.Add($cb); $fHaken += $cb; $x += 80
    }
    $lf = New-Object System.Windows.Forms.Label
    $lf.Text = 'unabhängig von den Haken unter ⚙ (die gelten nur fürs Sortieren)'
    $lf.ForeColor = [System.Drawing.Color]::DimGray; $lf.AutoSize = $true; $lf.Location = New-Object System.Drawing.Point(290, 144)
    $d.Controls.Add($lf)
    $c3.Add_CheckedChanged({ foreach ($cb in $fHaken) { $cb.Enabled = $c3.Checked } })
    foreach ($cb in $fHaken) { $cb.Enabled = $c3.Checked }
    $c4 = New-Object System.Windows.Forms.CheckBox
    $c4.Text = 'Originale, deren Kopie im Ziel per Prüfsumme bestätigt ist (leert die Quelle weitgehend)'
    $c4.Location = New-Object System.Drawing.Point(18, 174); $c4.AutoSize = $true; $c4.Checked = $false
    $d.Controls.Add($c4)
    $l4 = New-Object System.Windows.Forms.Label
    $l4.Text = 'Nie Kopiertes bleibt liegen (Hilfsdateien, ausgeschlossene Formate, ModX).'
    $l4.ForeColor = [System.Drawing.Color]::DimGray; $l4.AutoSize = $true; $l4.Location = New-Object System.Drawing.Point(36, 198)
    $d.Controls.Add($l4)
    $ok = New-Object System.Windows.Forms.Button
    $ok.Text = 'Weiter ...'; $ok.FlatStyle = 'System'; $ok.DialogResult = 'OK'
    $ok.Location = New-Object System.Drawing.Point(380, 234); $ok.Size = New-Object System.Drawing.Size(110, 32)
    $ab = New-Object System.Windows.Forms.Button
    $ab.Text = 'Abbrechen'; $ab.FlatStyle = 'System'; $ab.DialogResult = 'Cancel'
    $ab.Location = New-Object System.Drawing.Point(500, 234); $ab.Size = New-Object System.Drawing.Size(110, 32)
    $d.Controls.Add($ok); $d.Controls.Add($ab); $d.AcceptButton = $ok; $d.CancelButton = $ab
    $d.ClientSize = New-Object System.Drawing.Size(628, 282)
    $r = $d.ShowDialog($form)
    $arg = @()
    if ($c1.Checked) { $arg += '-Duplikate' }
    if ($c2.Checked) { $arg += '-MacReste' }
    $fl = @($fHaken | Where-Object { $_.Checked } | ForEach-Object { $_.Text })
    if ($c3.Checked -and $fl.Count) { $arg += '-Formate'; $arg += "-Formatliste '$($fl -join ',')'" }
    if ($c4.Checked) { $arg += '-Originale' }
    $d.Dispose()
    if ($r -ne 'OK') { return }
    if (-not $arg.Count) { Show-Meldung 'Es ist nichts ausgewählt.' 'Warning'; return }
    [void](Start-Skript 'Quelle-aufraeumen.ps1' ($arg -join ' ') 'Quelle aufräumen')
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
$lblStatus.Size = New-Object System.Drawing.Size(($breite - 36 - 28), 152)
$gStatus.Controls.Add($lblStatus)
Close-Gruppe $gStatus 184

# --- 1 Sortieren
$gSort = New-Gruppe '1  Sortieren'
$gy = 24
$null = New-Knopf $gSort 'Samples sortieren ...' 0 $gy `
    "Zeigt zuerst eine Vorschau (auch als CSV für Excel) und fragt dann, ob kopiert werden soll. Die Quelle bleibt unverändert; es wird nur kopiert, nichts überschrieben. Bereits vorhandener Inhalt wird übersprungen." `
    { if (Test-OrdnerBereit) { [void](Start-Skript 'Samples-sortieren.ps1' '' 'Samples sortieren') } }
$btnProt = New-Knopf $gSort 'Letztes Protokoll öffnen' 1 $gy `
    "Öffnet das Protokoll des letzten Kopierlaufs (CSV, z. B. in Excel)." `
    { $p = Get-NeuestesProtokoll 'Protokoll_*.csv'; if ($p) { Open-Pfad $p.FullName } else { Show-Meldung 'Noch kein Kopierlauf mit dieser Version.' 'Warning' } }
$gy += 44
$null = New-Knopf $gSort 'Ziel öffnen' 0 $gy "Öffnet die sortierte Sample-Bibliothek im Explorer." { Open-Pfad (Get-Einstellungen).Ziel }
$null = New-Knopf $gSort 'Quelle öffnen' 1 $gy "Öffnet den Quellordner im Explorer." { Open-Pfad (Get-Einstellungen).Quelle }
$gy += 44
Close-Gruppe $gSort ($gy + 2)

# --- 2 Inventur und Bericht
$gInv = New-Gruppe '2  Inventur und Bericht'
$gy = 24
$null = New-Knopf $gInv 'Inventur starten' 0 $gy `
    "Erfasst alle Samples und Packs im Ziel (Audio-Eigenschaften, BPM, Tonart, Pack-Art), sucht Duplikate, vergleicht mit der letzten Inventur und erstellt Liste und HTML-Bericht. Es wird nichts verändert." `
    {
        $zs = Get-OrdnerStatus (Get-Einstellungen).Ziel
        if ($zs.Fehlt -or $zs.Text -ne 'vorhanden') { Show-Meldung "Der Zielordner ist nicht vorhanden:`n$((Get-Einstellungen).Ziel)`n`nBitte zuerst sortieren oder über ⚙ Einstellungen den richtigen Ordner wählen." 'Warning'; return }
        [void](Start-Skript 'Inventur.ps1' '' 'Inventur')
    }
$btnBericht = New-Knopf $gInv 'Bericht öffnen' 1 $gy `
    "Öffnet den Bericht der neuesten Inventur im Browser: Samples, Packs und Duplikate mit Suche, Gliederung, Filtern, Abspielen. In der Ansicht Duplikate lassen sich Samples markieren und in den Papierkorb verschieben." `
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
    "Verschiebt alle als entfernbar markierten Duplikate der Bibliothek in den Papierkorb (Grundlage: neueste Inventur; je Gruppe bleibt ein Exemplar, Kits bleiben vollständig). Einzelne Duplikate lassen sich auch im Bericht markieren und entfernen." `
    { [void](Start-Skript 'Ziel-Duplikate-entfernen.ps1' '' 'Duplikate im Ziel entfernen') }
$gy += 44
Close-Gruppe $gInv ($gy + 2)

# --- 3 Quelle aufraeumen
$gDup = New-Gruppe '3  Quelle aufräumen'
$gy = 24
$null = New-Knopf $gDup 'Quelle aufräumen ...' 0 $gy `
    "Entfernt bewusst Entbehrliches aus der Quelle: Duplikate, macOS-Reste und – wenn unter ⚙ abgewählt – RX2/MP3/AIFF neben einer WAV, deren Kopie im Ziel bestätigt ist. Mit Auswahl, Vorschau und Rückfrage; Papierkorb." `
    { Show-QuelleAufraeumen }
$null = New-Knopf $gDup 'Papierkorb öffnen' 1 $gy `
    "Öffnet den Windows-Papierkorb. Dort lässt sich alles Entfernte wiederherstellen." `
    { try { Start-Process explorer.exe 'shell:RecycleBinFolder' } catch { } }
$gy += 44
$null = New-Knopf $gDup 'Protokolle öffnen' 0 $gy "Öffnet den Ordner mit allen Vorschauen und Protokollen." { Open-Pfad $protokollOrdner }
$null = New-Knopf $gDup 'Programmordner öffnen' 1 $gy "Öffnet den Programmordner im Explorer." { Open-Pfad $basis }
$gy += 44
Close-Gruppe $gDup ($gy + 2)

# --- Unten: Verknuepfung, Einstellungen (Zahnrad), Dokumentation, Schliessen
function New-UntenKnopf([string]$text, [int]$x, [int]$b, [string]$hinweis, [scriptblock]$aktion) {
    $k = New-Object System.Windows.Forms.Button
    $k.Text = $text; $k.Location = New-Object System.Drawing.Point($x, $script:y); $k.Size = New-Object System.Drawing.Size($b, 34)
    $k.FlatStyle = 'System'; $k.Add_Click($aktion)
    if ($hinweis) { $tipp.SetToolTip($k, $hinweis) }
    $form.Controls.Add($k)
    return $k
}
$btnLink = New-UntenKnopf '' 18 150 "Legt die Verknüpfung `"Samples-Werkzeuge`" auf dem Desktop an bzw. lässt sie auf diese Version zeigen." { New-DesktopVerknuepfung; Update-Status }
$btnEin = New-UntenKnopf "$([char]0x2699) Einstellungen" 176 136 'Ordner (Quelle, Ziel, Berichte …) und Formate (RX2, MP3, AIFF zusätzlich zur WAV) einstellen.' { Show-Einstellungen }
try { $btnEin.Font = New-Object System.Drawing.Font('Segoe UI Symbol', 9.5) } catch { }
$null = New-UntenKnopf 'Dokumentation' 320 116 'Öffnet die Dokumentation (RTF) mit allen Funktionen des Programms.' { Open-Pfad $dokuPfad }
$btnZu = New-UntenKnopf 'Schließen' 444 98 '' { $form.Close() }
$btnZu.Width = $breite - 18 - 444
$form.CancelButton = $btnZu
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
    $zeilen = @()
    $q = if (Test-Path -LiteralPath $e.Quelle) { 'gefunden' } else { "NICHT GEFUNDEN $([char]0x2013) über $([char]0x2699) Einstellungen ändern" }
    $zs = Get-OrdnerStatus $e.Ziel
    $z = if ($zs.Fehlt) { "$($zs.Text) $([char]0x2013) über $([char]0x2699) Einstellungen ändern" } else { $zs.Text }
    $zeilen += "Quelle:  $($e.Quelle)  $([char]0x2013)  $q"
    $zeilen += "Ziel:  $($e.Ziel)  $([char]0x2013)  $z"
    $zus = @(@('RX2', 'RX2Beibehalten'), @('MP3', 'MP3Beibehalten'), @('AIFF', 'AIFFBeibehalten') | Where-Object { $e[$_[1]] } | ForEach-Object { $_[0] })
    $zeilen += "Formate:  " + $(if ($zus.Count -eq 3) { 'alle (WAV, RX2, MP3, AIFF)' } elseif ($zus.Count -eq 0) { 'nur WAV, wenn vorhanden' } else { "WAV, zusätzlich $($zus -join ', ')" })

    $p = Get-NeuestesProtokoll 'Protokoll_*.csv'
    if ($p) { $zeilen += "Letzter Kopierlauf:  $((Get-Protokollzeit $p).ToString('dd.MM.yyyy HH:mm'))" }
    else    { $zeilen += 'Letzter Kopierlauf:  noch keiner mit dieser Version' }
    $btnProt.Enabled = [bool]$p

    $inv = Get-NeuesteInventur 'Sample'
    if ($inv) {
        $t = "Letzte Inventur:  $((Get-Protokollzeit $inv).ToString('dd.MM.yyyy HH:mm'))"
        try {
            $j = Get-Content -LiteralPath ([IO.Path]::ChangeExtension($inv.FullName, '.json')) -Raw -Encoding UTF8 | ConvertFrom-Json
            $t += " $([char]0x2013) $($j.Samples) Samples in $($j.Packs) Packs, $($j.GroesseGB) GB"
            if ([int]$j.DuplikatDateien -gt 0) { $t += ", $($j.DuplikatDateien) Duplikate" }
        } catch { }
        $zeilen += $t
    } else { $zeilen += 'Letzte Inventur:  noch keine - "Inventur starten"' }
    $btnBericht.Enabled = [bool]$inv
    $btnCsv.Enabled = [bool]$inv
    $btnVgl.Enabled = [bool](Get-NeuesterVergleich)
    $btnZielDup.Enabled = [bool]$inv

    $dp = Get-NeuestesProtokoll 'Quelle-aufgeraeumt_*.csv'
    if (-not $dp) { $dp = Get-NeuestesProtokoll 'Duplikate-entfernt_*.csv' }
    if ($dp) { $zeilen += "Quelle zuletzt aufgeräumt:  $((Get-Protokollzeit $dp).ToString('dd.MM.yyyy HH:mm'))" }

    $ziel = ''
    if (Test-Path -LiteralPath $verknuepfung) {
        try { $ziel = (New-Object -ComObject WScript.Shell).CreateShortcut($verknuepfung).Arguments } catch { }
    }
    if (-not (Test-Path -LiteralPath $verknuepfung)) {
        $zeilen += 'Desktop-Verknüpfung:  noch nicht angelegt'
        $btnLink.Text = 'Verknüpfung anlegen'
    } elseif ($ziel -like "*$skriptOrdner*") {
        $zeilen += 'Desktop-Verknüpfung:  vorhanden (öffnet diese Version)'
        $btnLink.Text = 'Verknüpfung erneuern'
    } else {
        $zeilen += 'Desktop-Verknüpfung:  zeigt auf eine andere Version'
        $btnLink.Text = "Verknüpfung auf $ProgrammVersion"
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
