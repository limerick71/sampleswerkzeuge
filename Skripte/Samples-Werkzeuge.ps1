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
    $aktiv = @($e.Quellen | Where-Object { $_.Aktiv })
    if (-not $aktiv.Count) { Show-Meldung "Es ist keine Quelle aktiv.`n`nBitte über ⚙ Einstellungen eine Quelle hinzufügen oder anhaken." 'Warning'; return $false }
    $fehlt = @($aktiv | Where-Object { -not (Test-Path -LiteralPath $_.Pfad) } | ForEach-Object { $_.Pfad })
    if ($fehlt.Count) {
        Show-Meldung ("Diese Quelle(n) wurden nicht gefunden:`n" + ($fehlt -join "`n") + "`n`nBitte über ⚙ Einstellungen korrigieren oder den Haken entfernen.") 'Warning'
        return $false
    }
    if (-not $NurQuelle) {
        foreach ($q in $aktiv) {
            $f = Test-QuelleZiel $q.Pfad $e.Ziel (Get-QuellArtName $q.Art)
            if ($f) { Show-Meldung "$f`n($($q.Pfad))`n`nBitte über ⚙ Einstellungen korrigieren." 'Warning'; return $false }
        }
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
function New-Hinweis($eltern, [string]$text, [int]$x, [int]$y, [int]$breiteMax) {
    # GUI-06: Hinweistexte brechen selbst um (feste Breite statt fester Zeilenumbrueche)
    $l = New-Object System.Windows.Forms.Label
    $l.Text = $text; $l.Font = $schrift; $l.ForeColor = [System.Drawing.Color]::DimGray
    $l.AutoSize = $true; $l.MaximumSize = New-Object System.Drawing.Size($breiteMax, 0)
    $l.Location = New-Object System.Drawing.Point($x, $y)
    $eltern.Controls.Add($l)
    return $l
}

function Show-Einstellungen {
    $d = New-Object System.Windows.Forms.Form
    $d.Text = 'Einstellungen'
    $d.StartPosition = 'CenterParent'; $d.FormBorderStyle = 'FixedDialog'
    $d.MaximizeBox = $false; $d.MinimizeBox = $false
    $d.Font = $schrift; $d.BackColor = [System.Drawing.Color]::White
    $tt = New-Object System.Windows.Forms.ToolTip; $tt.AutoPopDelay = 15000
    $w = 640; $dy = 14; $gb = $w - 32

    # --- Quellen (QLN-04) ---
    $g0 = New-Object System.Windows.Forms.GroupBox
    $g0.Text = 'Quellen'; $g0.Font = $schriftFett
    $g0.Location = New-Object System.Drawing.Point(16, $dy); $g0.Width = $gb
    $d.Controls.Add($g0)
    $lv = New-Object System.Windows.Forms.ListView
    $lv.View = 'Details'; $lv.CheckBoxes = $true; $lv.FullRowSelect = $true; $lv.HideSelection = $false; $lv.MultiSelect = $false
    $lv.Font = $schrift; $lv.Location = New-Object System.Drawing.Point(12, 26); $lv.Size = New-Object System.Drawing.Size(($gb - 24), 132)
    [void]$lv.Columns.Add('Ordner', 270); [void]$lv.Columns.Add('Art', 110); [void]$lv.Columns.Add('Herkunft', 120); [void]$lv.Columns.Add('Zustand', ($gb - 24 - 270 - 110 - 120 - 24))
    $g0.Controls.Add($lv)
    $script:qLaedt = $false
    $fuelle = {
        $script:qLaedt = $true
        $lv.Items.Clear()
        foreach ($q in @((Get-Einstellungen).Quellen)) {
            $it = New-Object System.Windows.Forms.ListViewItem($q.Pfad)
            [void]$it.SubItems.Add($QuellArten[(Get-QuellArtName $q.Art)])
            [void]$it.SubItems.Add($q.Herkunft)
            $it.Tag = (Get-QuellArtName $q.Art)
            [void]$it.SubItems.Add($(if (Test-Path -LiteralPath $q.Pfad) { 'gefunden' } else { 'NICHT GEFUNDEN' }))
            $it.Checked = [bool]$q.Aktiv
            [void]$lv.Items.Add($it)
        }
        $script:qLaedt = $false
    }
    $speichern = {
        $liste = @(foreach ($it in $lv.Items) { [pscustomobject]@{ Pfad = $it.Text; Aktiv = $it.Checked; Herkunft = $it.SubItems[2].Text; Art = [string]$it.Tag } })
        try { Set-Quellen $liste } catch { Show-Meldung "Speichern fehlgeschlagen:`n$($_.Exception.Message)" 'Error' }
    }
    $lv.Add_ItemChecked({ if (-not $script:qLaedt) { & $speichern } })
    $lv.Add_DoubleClick({ if ($lv.SelectedItems.Count) { Open-Pfad $lv.SelectedItems[0].Text } })
    $tt.SetToolTip($lv, 'Haken = aktiv: Sortieren und Aufräumen lesen alle angehakten Quellen. Doppelklick öffnet den Ordner im Explorer.')
    $by = 26 + 132 + 8
    $bAdd = New-Object System.Windows.Forms.Button
    $bAdd.Text = 'Hinzufügen ...'; $bAdd.Font = $schrift; $bAdd.FlatStyle = 'System'
    $bAdd.Location = New-Object System.Drawing.Point(12, $by); $bAdd.Size = New-Object System.Drawing.Size(130, 30)
    $bAdd.Add_Click({
        $dlg = New-Object System.Windows.Forms.FolderBrowserDialog
        $dlg.Description = 'Ordner mit Sample-Packs als weitere Quelle hinzufügen'; $dlg.ShowNewFolderButton = $false
        if ($dlg.ShowDialog($d) -ne 'OK') { return }
        $neu = $dlg.SelectedPath.TrimEnd('\')
        $e = Get-Einstellungen
        $art = Get-QuellArtFuerOrdner $neu
        $f = Test-NeueQuelle $neu $e.Quellen $e.Ziel '' $art
        if ($f) { Show-Meldung "$f`n`nDie Quelle wurde nicht hinzugefügt." 'Warning'; return }
        Set-Quellen (@($e.Quellen) + [pscustomobject]@{ Pfad = $neu; Aktiv = $true; Herkunft = 'manuell'; Art = $art })
        & $fuelle
        Show-Meldung "Hinzugefügt als '$($QuellArten[$art])'.`n`nFalls das nicht passt: Quelle in der Liste anklicken und unten die Art ändern."
    })
    $g0.Controls.Add($bAdd)
    $bWeg = New-Object System.Windows.Forms.Button
    $bWeg.Text = 'Entfernen'; $bWeg.Font = $schrift; $bWeg.FlatStyle = 'System'
    $bWeg.Location = New-Object System.Drawing.Point(150, $by); $bWeg.Size = New-Object System.Drawing.Size(110, 30)
    $bWeg.Add_Click({
        if (-not $lv.SelectedItems.Count) { Show-Meldung 'Bitte zuerst eine Quelle in der Liste anklicken.' 'Warning'; return }
        $pf = $lv.SelectedItems[0].Text
        if (-not (Show-Frage "Diese Quelle aus der Liste nehmen?`n$pf`n`nDer Ordner selbst bleibt unverändert.")) { return }
        $lv.Items.Remove($lv.SelectedItems[0]); & $speichern
    })
    $tt.SetToolTip($bWeg, 'Nimmt die markierte Quelle aus der Liste. Am Ordner wird nichts geändert.')
    $g0.Controls.Add($bWeg)
    $bSuch = New-Object System.Windows.Forms.Button
    $bSuch.Text = 'Fundorte suchen ...'; $bSuch.Font = $schrift; $bSuch.FlatStyle = 'System'
    $bSuch.Location = New-Object System.Drawing.Point(268, $by); $bSuch.Size = New-Object System.Drawing.Size(150, 30)
    $bSuch.Add_Click({ Show-FundorteSuchen })
    $tt.SetToolTip($bSuch, 'Sucht auf Laufwerken und in Ordnern nach Sample-Packs und zeigt die Fundorte im Browser. Dort lassen sie sich als Quellen übernehmen.')
    $g0.Controls.Add($bSuch)
    $ay = $by + 40
    $la = New-Object System.Windows.Forms.Label
    $la.Text = 'Art der markierten Quelle:'; $la.Font = $schrift; $la.AutoSize = $true; $la.Location = New-Object System.Drawing.Point(12, ($ay + 4))
    $g0.Controls.Add($la)
    $cbArt = New-Object System.Windows.Forms.ComboBox
    $cbArt.DropDownStyle = 'DropDownList'; $cbArt.Font = $schrift; $cbArt.Location = New-Object System.Drawing.Point(190, $ay); $cbArt.Width = 180
    foreach ($k in $QuellArten.Keys) { [void]$cbArt.Items.Add($QuellArten[$k]) }
    $cbArt.Enabled = $false
    $g0.Controls.Add($cbArt)
    $tt.SetToolTip($cbArt, "Sammlung: jeder Unterordner ist ein Pack.`nEin Pack: alles darin gehört zu einem Pack (Name = Ordnername), auch wenn unsortiert.`nNur lose Dateien: nur die Dateien direkt im Ordner, ohne Unterordner.")
    $script:artSetzt = $false
    $lv.Add_SelectedIndexChanged({
        if (-not $lv.SelectedItems.Count) { $cbArt.Enabled = $false; return }
        $script:artSetzt = $true; $cbArt.SelectedItem = $QuellArten[[string]$lv.SelectedItems[0].Tag]; $cbArt.Enabled = $true; $script:artSetzt = $false
    })
    $cbArt.Add_SelectedIndexChanged({
        if ($script:artSetzt -or -not $lv.SelectedItems.Count) { return }
        $it = $lv.SelectedItems[0]
        $neuArt = @($QuellArten.Keys | Where-Object { $QuellArten[$_] -eq $cbArt.SelectedItem })[0]
        if ($neuArt -eq [string]$it.Tag) { return }
        $e = Get-Einstellungen
        $f = Test-NeueQuelle $it.Text $e.Quellen $e.Ziel $it.Text $neuArt
        if ($f) { Show-Meldung "$f`n`nDie Art wurde nicht geändert." 'Warning'; $script:artSetzt = $true; $cbArt.SelectedItem = $QuellArten[[string]$it.Tag]; $script:artSetzt = $false; return }
        $it.Tag = $neuArt; $it.SubItems[1].Text = $QuellArten[$neuArt]; & $speichern
    })
    $lq = New-Hinweis $g0 'Haken = aktiv. Sortieren und „Quelle aufräumen“ lesen alle aktiven Quellen. Art: Sammlung = jeder Unterordner ist ein Pack; Ein Pack = alles darin unter dem Ordnernamen; Nur lose Dateien = ohne Unterordner. Doppelklick öffnet einen Ordner.' 12 ($ay + 34) ($gb - 24)
    $g0.Height = $ay + 34 + $lq.PreferredHeight + 14
    $dy += $g0.Height + 10
    $d.Add_Activated({ & $fuelle })   # nach "Fundorte suchen" (Übernahme im Browser) neu einlesen

    # --- Ordner ---
    $g1 = New-Object System.Windows.Forms.GroupBox
    $g1.Text = 'Ordner'; $g1.Font = $schriftFett
    $g1.Location = New-Object System.Drawing.Point(16, $dy); $g1.Width = $gb
    $d.Controls.Add($g1)
    $gy = 26
    $felder = @{}
    foreach ($pe in @($PfadEinstellungen | Where-Object { $_.Name -ne 'Quelle' })) {
        $l = New-Object System.Windows.Forms.Label
        $l.Text = "$($pe.Text):"; $l.Font = $schrift; $l.AutoSize = $true
        $l.Location = New-Object System.Drawing.Point(12, ($gy + 4)); $tt.SetToolTip($l, $pe.Hinweis); $g1.Controls.Add($l)
        $tb = New-Object System.Windows.Forms.TextBox
        $tb.Font = $schrift; $tb.ReadOnly = $true; $tb.BackColor = [System.Drawing.Color]::White; $tb.TabStop = $false
        $tb.Location = New-Object System.Drawing.Point(124, $gy); $tb.Size = New-Object System.Drawing.Size(($gb - 124 - 98), 26)
        $tb.Text = [string](Get-Einstellungen)[$pe.Name]; $tt.SetToolTip($tb, $pe.Hinweis); $g1.Controls.Add($tb)
        $felder[$pe.Name] = $tb
        $b = New-Object System.Windows.Forms.Button
        $b.Text = 'Ändern ...'; $b.Font = $schrift; $b.FlatStyle = 'System'
        $b.Location = New-Object System.Drawing.Point(($gb - 92), ($gy - 2)); $b.Size = New-Object System.Drawing.Size(80, 28)
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
            $f = ''
            if ($pe.Name -eq 'Ziel') { foreach ($q in @($e.Quellen)) { if (-not $f) { $f = Test-QuelleZiel $q.Pfad $neu (Get-QuellArtName $q.Art) } } }
            if ($f) { Show-Meldung "$f`n`nDie Einstellung wurde nicht geändert." 'Warning'; return }
            try { Set-Einstellung $pe.Name $neu; $felder[$pe.Name].Text = $neu } catch { Show-Meldung "Speichern fehlgeschlagen:`n$($_.Exception.Message)" 'Error' }
        })
        $tt.SetToolTip($b, "Ordner für '$($pe.Text)' auswählen. Die Auswahl wird gespeichert.")
        $g1.Controls.Add($b)
        $gy += 32
    }
    $lh = New-Hinweis $g1 'Downloads und Download-Archiv werden ab Version 3 (Import) genutzt.' 12 ($gy + 2) ($gb - 24)
    $g1.Height = $gy + 2 + $lh.PreferredHeight + 14
    $dy += $g1.Height + 10

    # --- Formate ---
    $g2 = New-Object System.Windows.Forms.GroupBox
    $g2.Text = 'Formate beim Sortieren (WAV ist Standard)'; $g2.Font = $schriftFett
    $g2.Location = New-Object System.Drawing.Point(16, $dy); $g2.Width = $gb
    $d.Controls.Add($g2)
    $l2 = New-Object System.Windows.Forms.Label
    $l2.Text = 'Zusätzlich zur WAV behalten:'; $l2.Font = $schrift; $l2.AutoSize = $true
    $l2.Location = New-Object System.Drawing.Point(12, 30); $g2.Controls.Add($l2)
    $haken = @()
    $x = 210
    foreach ($fmt in @(@('RX2', 'RX2Beibehalten'), @('MP3', 'MP3Beibehalten'), @('AIFF', 'AIFFBeibehalten'))) {
        $cb = New-Object System.Windows.Forms.CheckBox
        $cb.Text = $fmt[0]; $cb.Font = $schrift; $cb.AutoSize = $true; $cb.Tag = $fmt[1]
        $cb.Location = New-Object System.Drawing.Point($x, 28); $cb.Checked = (Get-Einstellungen)[$fmt[1]]
        $cb.Add_CheckedChanged({ param($sender, $ev) try { Set-Einstellung $sender.Tag $sender.Checked } catch { } })
        $tt.SetToolTip($cb, "Haken: $($fmt[0])-Dateien werden mitsortiert.`nOhne Haken: Liegt im selben Pack eine WAV mit gleichem Namen (auch in einem anderen Unterordner, z. B. '...-Wav' neben '...-Rex2'), wird die $($fmt[0])-Datei nicht kopiert (sie bleibt in der Quelle). Ohne WAV-Gegenstück wird sie immer einsortiert.")
        $g2.Controls.Add($cb); $haken += $cb
        $x += 90
    }
    $bNur = New-Object System.Windows.Forms.Button
    $bNur.Text = 'Nur WAV'; $bNur.Font = $schrift; $bNur.FlatStyle = 'System'
    $bNur.Location = New-Object System.Drawing.Point(210, 60); $bNur.Size = New-Object System.Drawing.Size(110, 30)
    $bNur.Add_Click({ foreach ($c in $haken) { $c.Checked = $false } })
    $tt.SetToolTip($bNur, 'Entfernt alle drei Haken: Gibt es eine gleichnamige WAV, kommt nur die WAV in die Bibliothek.')
    $g2.Controls.Add($bNur)
    $bAlle = New-Object System.Windows.Forms.Button
    $bAlle.Text = 'Alle'; $bAlle.Font = $schrift; $bAlle.FlatStyle = 'System'
    $bAlle.Location = New-Object System.Drawing.Point(328, 60); $bAlle.Size = New-Object System.Drawing.Size(80, 30)
    $bAlle.Add_Click({ foreach ($c in $haken) { $c.Checked = $true } })
    $g2.Controls.Add($bAlle)
    $l3 = New-Hinweis $g2 'Die Haken gelten nur für das Sortieren. Nicht kopierte Dateien entfernt man mit „Quelle aufräumen …“.' 12 100 ($gb - 24)
    $g2.Height = 100 + $l3.PreferredHeight + 14
    $dy += $g2.Height + 14

    $ok = New-Object System.Windows.Forms.Button
    $ok.Text = 'Schließen'; $ok.FlatStyle = 'System'; $ok.DialogResult = 'OK'
    $ok.Location = New-Object System.Drawing.Point(($w - 16 - 110), $dy); $ok.Size = New-Object System.Drawing.Size(110, 32)
    $d.Controls.Add($ok); $d.AcceptButton = $ok; $d.CancelButton = $ok
    $d.ClientSize = New-Object System.Drawing.Size($w, ($dy + 48))
    $d.Add_Shown({ $ok.Focus() })   # GUI-06: kein markiertes Textfeld beim Öffnen
    [void]$d.ShowDialog($form)
    $d.Dispose()
    Update-Status
}

# ---------------------------------------------------------------------------
# Dialog: Fundorte suchen (QLN-01) - wo gesucht wird
# ---------------------------------------------------------------------------
function Show-FundorteSuchen {
    $w = 600; $innen = $w - 32
    $d = New-Object System.Windows.Forms.Form
    $d.Text = 'Fundorte suchen'
    $d.StartPosition = 'CenterParent'; $d.FormBorderStyle = 'FixedDialog'
    $d.MaximizeBox = $false; $d.MinimizeBox = $false
    $d.Font = $schrift; $d.BackColor = [System.Drawing.Color]::White
    $l = New-Hinweis $d 'Wo soll nach Sample-Packs gesucht werden? Es werden nur Ordner- und Dateinamen gelesen, nichts verändert und keine Cloud-Dateien heruntergeladen. Windows-, Programm- und Anwendungsordner sowie das Ziel werden ausgelassen.' 16 14 $innen
    $l.ForeColor = [System.Drawing.Color]::Black
    $y = 14 + $l.PreferredHeight + 12
    $clb = New-Object System.Windows.Forms.CheckedListBox
    $clb.CheckOnClick = $true; $clb.IntegralHeight = $false
    $clb.Location = New-Object System.Drawing.Point(16, $y); $clb.Size = New-Object System.Drawing.Size($innen, 200)
    $d.Controls.Add($clb)
    $orte = New-Object System.Collections.Generic.List[string]
    $add = { param($pfad, $text, $an) if ($pfad -and (Test-Path -LiteralPath $pfad) -and -not ($orte -contains $pfad)) { $orte.Add($pfad); [void]$clb.Items.Add($text, [bool]$an) } }
    & $add (Get-StandardDownloads) "Downloads  ($(Get-StandardDownloads))" $true
    & $add ([Environment]::GetFolderPath('MyDocuments')) "Dokumente  ($([Environment]::GetFolderPath('MyDocuments')))" $true
    & $add ([Environment]::GetFolderPath('Desktop')) "Desktop  ($([Environment]::GetFolderPath('Desktop')))" $true
    & $add ([Environment]::GetFolderPath('MyMusic')) "Musik  ($([Environment]::GetFolderPath('MyMusic')))" $true
    $sys = "$env:SystemDrive\"
    foreach ($lw in [IO.DriveInfo]::GetDrives()) {
        try {
            if (-not $lw.IsReady -or $lw.DriveType -notin 'Fixed', 'Removable') { continue }
            $frei = '{0:N0} GB belegt' -f (($lw.TotalSize - $lw.TotalFreeSpace) / 1GB)
            $name = if ($lw.VolumeLabel) { " $($lw.VolumeLabel)" } else { '' }
            if ($lw.RootDirectory.FullName -ieq $sys) { & $add $lw.RootDirectory.FullName "Laufwerk $($lw.Name)$name ganz  ($frei, Systemlaufwerk – dauert länger)" $false }
            elseif ($lw.DriveType -eq 'Removable') { & $add $lw.RootDirectory.FullName "Laufwerk $($lw.Name)$name ganz  ($frei, Wechseldatenträger)" $false }
            else { & $add $lw.RootDirectory.FullName "Laufwerk $($lw.Name)$name ganz  ($frei)" $true }
        } catch { }
    }
    $y += 200 + 8
    $bOrd = New-Object System.Windows.Forms.Button
    $bOrd.Text = 'Ordner hinzufügen ...'; $bOrd.FlatStyle = 'System'
    $bOrd.Location = New-Object System.Drawing.Point(16, $y); $bOrd.Size = New-Object System.Drawing.Size(170, 30)
    $bOrd.Add_Click({
        $dlg = New-Object System.Windows.Forms.FolderBrowserDialog
        $dlg.Description = 'Zusätzlichen Ordner durchsuchen'; $dlg.ShowNewFolderButton = $false
        if ($dlg.ShowDialog($d) -eq 'OK') { & $add $dlg.SelectedPath $dlg.SelectedPath $true }
    })
    $d.Controls.Add($bOrd)
    $y += 44
    $ok = New-Object System.Windows.Forms.Button
    $ok.Text = 'Suchen'; $ok.FlatStyle = 'System'; $ok.DialogResult = 'OK'
    $ok.Location = New-Object System.Drawing.Point(($w - 16 - 230), $y); $ok.Size = New-Object System.Drawing.Size(110, 32)
    $ab = New-Object System.Windows.Forms.Button
    $ab.Text = 'Abbrechen'; $ab.FlatStyle = 'System'; $ab.DialogResult = 'Cancel'
    $ab.Location = New-Object System.Drawing.Point(($w - 16 - 110), $y); $ab.Size = New-Object System.Drawing.Size(110, 32)
    $d.Controls.Add($ok); $d.Controls.Add($ab); $d.AcceptButton = $ok; $d.CancelButton = $ab
    $d.ClientSize = New-Object System.Drawing.Size($w, ($y + 48))
    $d.Add_Shown({ $ok.Focus() })
    $besitzer = [System.Windows.Forms.Form]::ActiveForm; if (-not $besitzer) { $besitzer = $form }
    $r = $d.ShowDialog($besitzer)
    $gewaehlt = @(for ($i = 0; $i -lt $clb.Items.Count; $i++) { if ($clb.GetItemChecked($i)) { $orte[$i] } })
    $d.Dispose()
    if ($r -ne 'OK') { return }
    if (-not $gewaehlt.Count) { Show-Meldung 'Es ist kein Ort ausgewählt.' 'Warning'; return }
    [void](Start-Skript 'Fundorte-suchen.ps1' "-Orte '$(($gewaehlt -join '|').Replace("'", "''"))'" 'Fundorte suchen')
}

# ---------------------------------------------------------------------------
# Dialog: Quelle aufraeumen - Auswahl der Gruppen
# ---------------------------------------------------------------------------
function Show-QuelleAufraeumen {
    if (-not (Test-OrdnerBereit -NurQuelle)) { return }
    $e = Get-Einstellungen
    $aus = @(@('RX2', 'RX2Beibehalten'), @('MP3', 'MP3Beibehalten'), @('AIFF', 'AIFFBeibehalten') | Where-Object { -not $e[$_[1]] } | ForEach-Object { $_[0] })
    $aktiv = @($e.Quellen | Where-Object { $_.Aktiv })
    $w = 640; $innen = $w - 32
    $d = New-Object System.Windows.Forms.Form
    $d.Text = 'Quelle aufräumen'
    $d.StartPosition = 'CenterParent'; $d.FormBorderStyle = 'FixedDialog'
    $d.MaximizeBox = $false; $d.MinimizeBox = $false
    $d.Font = $schrift; $d.BackColor = [System.Drawing.Color]::White
    $y = 14
    $l = New-Hinweis $d "Was soll aus der Quelle in den Papierkorb? Danach zeigt ein Fenster die Vorschau; entfernt wird erst nach 'J'." 16 $y $innen
    $l.ForeColor = [System.Drawing.Color]::Black
    $y += $l.PreferredHeight + 14
    function New-Haken([string]$text, [int]$x, [bool]$an) {
        $c = New-Object System.Windows.Forms.CheckBox
        $c.Text = $text; $c.AutoSize = $true; $c.Location = New-Object System.Drawing.Point($x, $script:hy); $c.Checked = $an
        $d.Controls.Add($c); return $c
    }
    $script:hy = $y
    $c1 = New-Haken 'Duplikate (beim Kopieren als doppelt erkannt, Prüfung gegen das behaltene Exemplar)' 18 $true; $script:hy += 28
    $c2 = New-Haken 'macOS-Reste (._-Dateien, .DS_Store, __MACOSX – am Dateikopf erkannt)' 18 $true; $script:hy += 28
    # GUI-06: verständlicher Text; CLN-12: eigene Format-Haken
    $c3 = New-Haken 'Formate (nur wenn die gleichnamige WAV aus demselben Pack im Ziel liegt):' 18 ([bool]$aus.Count); $script:hy += 26
    $fHaken = @(); $x = 40
    foreach ($fmt in 'RX2', 'MP3', 'AIFF') { $fHaken += New-Haken $fmt $x (($aus -contains $fmt) -or (-not $aus.Count)); $x += 90 }
    $script:hy += 26
    $lf = New-Hinweis $d 'Unabhängig von den Haken unter ⚙ Einstellungen – die gelten nur für das Sortieren.' 40 $script:hy ($innen - 30)
    $script:hy += $lf.PreferredHeight + 10
    $c3.Add_CheckedChanged({ foreach ($cb in $fHaken) { $cb.Enabled = $c3.Checked } })
    foreach ($cb in $fHaken) { $cb.Enabled = $c3.Checked }
    $c4 = New-Haken 'Originale, deren Kopie im Ziel per Prüfsumme bestätigt ist (leert die Quelle weitgehend)' 18 $false; $script:hy += 26
    $l4 = New-Hinweis $d 'Nie Kopiertes bleibt liegen (Hilfsdateien, ausgeschlossene Formate, ModX).' 40 $script:hy ($innen - 30)
    $script:hy += $l4.PreferredHeight + 12
    # QLN-05: bei mehreren aktiven Quellen wählen, welche aufgeräumt werden
    $qHaken = @()
    if ($aktiv.Count -gt 1) {
        $lq = New-Object System.Windows.Forms.Label
        $lq.Text = 'Welche Quellen?'; $lq.Font = $schriftFett; $lq.AutoSize = $true; $lq.Location = New-Object System.Drawing.Point(16, $script:hy)
        $d.Controls.Add($lq); $script:hy += 26
        foreach ($q in $aktiv) { $c = New-Haken $q.Pfad 18 $true; $c.AutoSize = $false; $c.Width = $innen; $qHaken += $c; $script:hy += 26 }
        $script:hy += 6
    }
    $y = $script:hy + 6
    $ok = New-Object System.Windows.Forms.Button
    $ok.Text = 'Weiter ...'; $ok.FlatStyle = 'System'; $ok.DialogResult = 'OK'
    $ok.Location = New-Object System.Drawing.Point(($w - 16 - 230), $y); $ok.Size = New-Object System.Drawing.Size(110, 32)
    $ab = New-Object System.Windows.Forms.Button
    $ab.Text = 'Abbrechen'; $ab.FlatStyle = 'System'; $ab.DialogResult = 'Cancel'
    $ab.Location = New-Object System.Drawing.Point(($w - 16 - 110), $y); $ab.Size = New-Object System.Drawing.Size(110, 32)
    $d.Controls.Add($ok); $d.Controls.Add($ab); $d.AcceptButton = $ok; $d.CancelButton = $ab
    $d.ClientSize = New-Object System.Drawing.Size($w, ($y + 48))
    $d.Add_Shown({ $ok.Focus() })
    $r = $d.ShowDialog($form)
    $arg = @()
    if ($c1.Checked) { $arg += '-Duplikate' }
    if ($c2.Checked) { $arg += '-MacReste' }
    $fl = @($fHaken | Where-Object { $_.Checked } | ForEach-Object { $_.Text })
    if ($c3.Checked -and $fl.Count) { $arg += '-Formate'; $arg += "-Formatliste '$($fl -join ',')'" }
    if ($c4.Checked) { $arg += '-Originale' }
    $qWahl = @($qHaken | Where-Object { $_.Checked } | ForEach-Object { $_.Text })
    $d.Dispose()
    if ($r -ne 'OK') { return }
    if (-not $arg.Count) { Show-Meldung 'Es ist nichts ausgewählt.' 'Warning'; return }
    if ($qHaken.Count) {
        if (-not $qWahl.Count) { Show-Meldung 'Es ist keine Quelle ausgewählt.' 'Warning'; return }
        $arg += "-Quellen '$(($qWahl -join '|').Replace("'", "''"))'"
    }
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
$lblStatus.Size = New-Object System.Drawing.Size(($breite - 36 - 28), 190)
$gStatus.Controls.Add($lblStatus)
Close-Gruppe $gStatus 222

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
$null = New-Knopf $gSort 'Fundorte suchen ...' 1 $gy "Sucht auf Laufwerken und in Ordnern nach Sample-Packs und zeigt die Fundorte im Browser; dort lassen sie sich als Quellen übernehmen. Es wird nichts verändert." { Show-FundorteSuchen }
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
    $zs = Get-OrdnerStatus $e.Ziel
    $z = if ($zs.Fehlt) { "$($zs.Text) $([char]0x2013) über $([char]0x2699) Einstellungen ändern" } else { $zs.Text }
    # Quellen (QLN-04): bis zu drei aktive einzeln, sonst zusammengefasst
    $aktiv = @($e.Quellen | Where-Object { $_.Aktiv })
    $fehlen = @($aktiv | Where-Object { -not (Test-Path -LiteralPath $_.Pfad) })
    if (-not $aktiv.Count) { $zeilen += "Quelle:  keine aktiv $([char]0x2013) über $([char]0x2699) Einstellungen hinzufügen" }
    elseif ($aktiv.Count -le 3) {
        foreach ($q in $aktiv) {
            $t = if (Test-Path -LiteralPath $q.Pfad) { 'gefunden' } else { "NICHT GEFUNDEN $([char]0x2013) über $([char]0x2699) Einstellungen ändern" }
            $artText = if ((Get-QuellArtName $q.Art) -ne 'Sammlung') { "  ($($QuellArten[(Get-QuellArtName $q.Art)]))" } else { '' }
            $zeilen += "Quelle:  $($q.Pfad)$artText  $([char]0x2013)  $t"
        }
    } else {
        $zeilen += "Quellen:  $($aktiv.Count) aktiv $([char]0x2013) " + $(if ($fehlen.Count) { "$($fehlen.Count) NICHT GEFUNDEN (siehe $([char]0x2699) Einstellungen)" } else { 'alle gefunden' })
    }
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
