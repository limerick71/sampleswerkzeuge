#Requires -Version 5.1
# (c) 2026 Herbert Stoecker. Kostenlos nutzbar. Bitte nur als Link auf die offizielle Download-Seite weitergeben; Verkauf und Veroeffentlichung geaenderter Fassungen nur mit Zustimmung.
# Dialoge der Oberflaeche (WinForms). Seit 4.0 eigene Datei; das Hauptfenster (WPF) steht in Samples-Werkzeuge.ps1.
# Erwartet vom Hauptfenster: $form (Besitzer der Dialoge), Update-Status, Set-Wartezeiger und Start-Skript
# (startet ein Skript und zeigt Fortschritt und Ausgabe im Hauptfenster; wird dort nach diesem Skript definiert).

$schrift      = New-Object System.Drawing.Font('Segoe UI', 9.5)
$schriftFett  = New-Object System.Drawing.Font('Segoe UI', 9.5, [System.Drawing.FontStyle]::Bold)
$schriftTitel = New-Object System.Drawing.Font('Segoe UI Semibold', 14)

# ---------------------------------------------------------------------------
# Hilfsfunktionen
# ---------------------------------------------------------------------------
function Show-Meldung([string]$text, [string]$art = 'Information') {
    [void][System.Windows.Forms.MessageBox]::Show($text, 'Samples-Werkzeuge', 'OK', $art)
}
function Show-Frage([string]$text) {
    return ([System.Windows.Forms.MessageBox]::Show($text, 'Samples-Werkzeuge', 'YesNo', 'Question', 'Button2') -eq 'Yes')
}

# Start-Skript steht seit 4.0 im Hauptfenster (Ausgabe und Fortschritt im Fenster statt eigener Konsole)

# Neuesten Bericht oeffnen: ueber den lokalen Bericht-Dienst (Loeschen aus dem Bericht, Abspielen);
# klappt das nicht, wird die HTML-Datei direkt geoeffnet
function Open-Bericht {
    $c = Get-NeuesteInventur 'Sample'
    if (-not $c) { Show-Meldung 'Die Sample-Bibliothek wurde noch nicht eingelesen.' 'Warning'; return }
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

# ---------------------------------------------------------------------------
# Infobox "Art einer Quelle" (2.3.2): erklaert die drei Arten am markierten Ordner
# ---------------------------------------------------------------------------
function Show-ArtInfo($zeile) {
    $w = 640
    $d = New-Object System.Windows.Forms.Form
    $d.Text = 'Art einer Quelle'
    $d.StartPosition = 'CenterParent'; $d.FormBorderStyle = 'FixedDialog'
    $d.MaximizeBox = $false; $d.MinimizeBox = $false
    $d.Font = $schrift; $d.BackColor = [System.Drawing.Color]::White
    $rt = New-Object System.Windows.Forms.RichTextBox
    $rt.ReadOnly = $true; $rt.BorderStyle = 'None'; $rt.BackColor = [System.Drawing.Color]::White; $rt.Font = $schrift
    $rt.Location = New-Object System.Drawing.Point(16, 14); $rt.Size = New-Object System.Drawing.Size(($w - 32), 380)
    $rt.DetectUrls = $false; $rt.TabStop = $false; $rt.ScrollBars = 'Vertical'
    $d.Controls.Add($rt)
    $fett = New-Object System.Drawing.Font($schrift, [System.Drawing.FontStyle]::Bold)
    $schreibe = { param($text, $istFett, $farbe)
        $rt.SelectionStart = $rt.TextLength; $rt.SelectionLength = 0
        $rt.SelectionFont = $(if ($istFett) { $fett } else { $schrift })
        $rt.SelectionColor = $(if ($farbe) { $farbe } else { [System.Drawing.Color]::Black })
        $rt.AppendText($text)
    }
    & $schreibe ('Die Art legt fest, wie beim Sortieren die Packs im Ordner erkannt werden. Der Packname wird im Ziel zum Unterordner unter dem Instrument, z. B. 01 Drums\Kick\One-Shots\<Packname>\Datei.wav.' + "`n`n") $false ([System.Drawing.Color]::DimGray)
    if (-not $zeile) {
        & $schreibe ("Sammlung – jeder Unterordner ist ein eigener Pack (z. B. Quelle_Samples).`nEin Pack – alles im Ordner gehört zu einem Pack, Packname = Ordnername (z. B. ein heruntergeladenes Pack).`nNur lose Dateien – nur die Dateien direkt im Ordner, Unterordner werden übergangen (z. B. Downloads).`n`n") $false $null
        & $schreibe 'Tipp: Eine Quelle in der Liste anklicken und dann ⓘ wählen – dann zeigt diese Box am Ordner selbst, was jede Art bewirkt.' $false ([System.Drawing.Color]::DimGray)
    } elseif (-not (Test-Path -LiteralPath $zeile.Text -PathType Container)) {
        & $schreibe "Der Ordner $($zeile.Text) wurde nicht gefunden." $true ([System.Drawing.Color]::Firebrick)
    } else {
        $d.Cursor = 'WaitCursor'
        $v = Get-ArtVorschau $zeile.Text
        $empf = $v.Empfehlung; $jetzt = [string]$zeile.Tag
        & $schreibe ('So würde der Ordner „' + $v.Name + '“ gelesen' + "`n") $true $null
        & $schreibe ('(… steht für den Instrument-Ordner im Ziel, z. B. 07 Vocals oder 01 Drums\Kick\One-Shots)' + "`n`n") $false ([System.Drawing.Color]::DimGray)
        foreach ($a in (Get-ArtVorschauAbschnitte $v)) {
            $marke = @(); if ($a.Art -eq $jetzt) { $marke += 'eingestellt' }; if ($a.Art -eq $empf) { $marke += 'empfohlen' }
            & $schreibe $a.Titel $true $(if ($a.Art -eq $jetzt) { [System.Drawing.Color]::FromArgb(31, 78, 121) } else { $null })
            if ($marke.Count) { & $schreibe ('   ◀ ' + ($marke -join ', ')) $true ([System.Drawing.Color]::FromArgb(26, 127, 55)) }
            & $schreibe "`n" $false $null
            foreach ($z in $a.Zeilen) { & $schreibe ("     $z`n") $false $null }
            & $schreibe "`n" $false $null
        }
        if ($v.Sammelordner) { & $schreibe "Das ist ein Sammelordner (z. B. Downloads, Dokumente): Hier passt nur 'Nur lose Dateien'. Packs darin bitte einzeln als 'Ein Pack' eintragen – oder über 'Fundorte suchen ...', das macht es in einem Schritt.`n" $true ([System.Drawing.Color]::FromArgb(138, 90, 0)) }
        if ($v.PackEbene) { & $schreibe ("Tipp: Die Packs liegen erst in " + $v.PackEbene + ". Diesen Ordner als 'Sammlung' eintragen, dann behält jedes Pack seinen Namen.`n") $true ([System.Drawing.Color]::FromArgb(138, 90, 0)) }
        if ($v.Unvollstaendig) { & $schreibe "Sehr großer Ordner: gezählt wurden die ersten 50.000 Audiodateien.`n" $false ([System.Drawing.Color]::DimGray) }
        $d.Cursor = 'Default'
    }
    $rt.SelectionStart = 0
    $h = [Math]::Min(540, [Math]::Max(300, $rt.GetPositionFromCharIndex([Math]::Max(0, $rt.TextLength - 1)).Y + 40))
    $rt.Height = $h
    $ok = New-Object System.Windows.Forms.Button
    $ok.Text = 'Schließen'; $ok.FlatStyle = 'System'; $ok.DialogResult = 'OK'
    $ok.Location = New-Object System.Drawing.Point(($w - 16 - 110), (14 + $h + 10)); $ok.Size = New-Object System.Drawing.Size(110, 32)
    $d.Controls.Add($ok); $d.AcceptButton = $ok; $d.CancelButton = $ok
    $d.ClientSize = New-Object System.Drawing.Size($w, (14 + $h + 10 + 48))
    $d.Add_Shown({ $ok.Focus() })
    $besitzer = [System.Windows.Forms.Form]::ActiveForm; if (-not $besitzer) { $besitzer = $form }
    [void]$d.ShowDialog($besitzer)
    $d.Dispose()
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
    $script:qLaedt = $false; $script:qStand = -1   # -1: beim ersten Aktivieren (Fenster sichtbar) einlesen
    $lWarn = New-Object System.Windows.Forms.LinkLabel
    $lWarn.Font = $schriftFett; $lWarn.ForeColor = [System.Drawing.Color]::FromArgb(160, 70, 0); $lWarn.AutoEllipsis = $true; $lWarn.Visible = $false
    $lWarn.Add_LinkClicked({ foreach ($it in @($lv.Items)) { if ($script:tiefer -contains $it.Text) { & $umstellen $it.Text ([string]$it.Tag); break } } })
    # Stand der Einstellungsdatei: neu eingelesen wird nur, wenn sie sich geaendert hat (2.3.2)
    $stand = { try { (Get-Item -LiteralPath $einstellungsPfad -ErrorAction Stop).LastWriteTimeUtc.Ticks } catch { 0 } }
    $artText = { param($k) $QuellArten[$k] + '  ▾' }
    # 2.3.4: Ebene, auf der die Packs einer Sammlung liegen (z. B. Splice -> Samples\packs); je Pfad einmal ermittelt
    $script:ebenen = @{}
    $ebeneVon = { param($p, $art)
        if ($art -eq 'Lose') { return $null }   # 2.3.5: auch bei "Ein Pack" (sonst landet alles unter einem Pack-Namen)
        $k = $p.ToLowerInvariant()
        if (-not $script:ebenen.ContainsKey($k)) { $script:ebenen[$k] = $(try { Get-PackEbene $p } catch { $null }) }
        return $script:ebenen[$k]
    }
    $fuelle = {
        $script:qLaedt = $true
        $markiert = if ($lv.SelectedItems.Count) { $lv.SelectedItems[0].Text } else { '' }
        $lv.BeginUpdate(); $lv.Items.Clear(); $script:tiefer = @()
        foreach ($q in @((Get-Einstellungen).Quellen)) {
            $it = New-Object System.Windows.Forms.ListViewItem($q.Pfad)
            [void]$it.SubItems.Add((& $artText (Get-QuellArtName $q.Art)))
            [void]$it.SubItems.Add($q.Herkunft)
            $it.Tag = (Get-QuellArtName $q.Art)
            $da = Test-Path -LiteralPath $q.Pfad
            $eb = if ($da) { & $ebeneVon $q.Pfad (Get-QuellArtName $q.Art) } else { $null }
            $zst = $it.SubItems.Add($(if (-not $da) { 'NICHT GEFUNDEN' } elseif ($eb) { 'Packs liegen tiefer ▸ umstellen' } else { 'gefunden' }))
            # 2.3.5: ganze Zeile hervorheben und unter der Liste darauf hinweisen
            if ($eb) { $it.BackColor = [System.Drawing.Color]::FromArgb(255, 232, 200); $it.ForeColor = [System.Drawing.Color]::FromArgb(140, 60, 0); $script:tiefer += $q.Pfad }
            $it.Checked = [bool]$q.Aktiv
            [void]$lv.Items.Add($it)
            if ($markiert -and $q.Pfad -eq $markiert) { $it.Selected = $true }
        }
        $lv.EndUpdate()
        if ($script:tiefer.Count) {
            $link = 'Jetzt umstellen …'
            $lWarn.Text = $link + '   ⚠ Packs liegen tiefer bei ' + $(if ($script:tiefer.Count -eq 1) { $script:tiefer[0] } else { "$($script:tiefer.Count) Quellen (orange Zeilen)" })
            $lWarn.LinkArea = New-Object System.Windows.Forms.LinkArea(0, $link.Length)
            $lWarn.Visible = $true
        } else { $lWarn.Visible = $false }
        $script:qStand = & $stand
        $script:qLaedt = $false
    }
    $speichern = {
        # Liste nur speichern, wenn alle Zeilen vollstaendig gelesen werden koennen - sonst lieber nichts aendern
        $zeilen = @($lv.Items | Where-Object { $_ -and $_.SubItems.Count -ge 3 })
        if ($zeilen.Count -ne $lv.Items.Count) { Write-FehlerLog 'Einstellungen: Quellenliste unvollständig gelesen, nicht gespeichert'; return }
        $liste = @(foreach ($it in $zeilen) { [pscustomobject]@{ Pfad = $it.Text; Aktiv = $it.Checked; Herkunft = $it.SubItems[2].Text; Art = [string]$it.Tag } })
        try { Set-Quellen $liste } catch { Show-Meldung "Speichern fehlgeschlagen:`n$($_.Exception.Message)" 'Error' }
        $script:qStand = & $stand
    }
    # Nur echte Klicks speichern: beim Anlegen der Liste meldet Windows die Haken ebenfalls (2.3.2)
    $lv.Add_ItemChecked({ if (-not $script:qLaedt -and $script:qStand -ne -1 -and $lv.IsHandleCreated) { & $speichern } })
    $lv.Add_DoubleClick({ if ($lv.SelectedItems.Count) { Open-Pfad $lv.SelectedItems[0].Text } })
    $tt.SetToolTip($lv, 'Haken = aktiv: Sortieren und Aufräumen lesen alle angehakten Quellen. Klick auf die Art: Art ändern. Zustand „Packs liegen tiefer“: anklicken, um die Quelle auf die Ebene der Packs umzustellen. Doppelklick öffnet den Ordner im Explorer.')
    # Art direkt in der Liste waehlen (2.3.2): Klick auf die Spalte "Art" oeffnet die Auswahl
    $artMenue = New-Object System.Windows.Forms.ContextMenuStrip
    $artMenue.Font = $schrift
    foreach ($k in $QuellArten.Keys) { $mi = $artMenue.Items.Add($QuellArten[$k]); $mi.Tag = $k }
    $script:artZeile = $null
    $artMenue.Add_ItemClicked({
        param($sender, $ev)
        $it = $script:artZeile; if (-not $it) { return }
        $neuArt = [string]$ev.ClickedItem.Tag
        if ($neuArt -eq [string]$it.Tag) { return }
        if ($neuArt -ne 'Lose' -and (Test-Sammelordner $it.Text)) {
            $artMenue.Close()
            if (-not (Show-Frage ("$($it.Text) ist ein Sammelordner (z. B. Downloads, Dokumente).`n`nAls '$($QuellArten[$neuArt])' würde das Sortieren alles darin lesen - auch Programme, Dokumente und fremde Unterordner - und unter einem Namen einsortieren. Richtig ist 'Nur lose Dateien'; Packs darin bitte einzeln hinzufügen.`n`nTrotzdem ändern?"))) { return }
        }
        $e = Get-Einstellungen
        $f = Test-NeueQuelle $it.Text $e.Quellen $e.Ziel $it.Text $neuArt
        if ($f) { $artMenue.Close(); Show-Meldung "$f`n`nDie Art wurde nicht geändert." 'Warning'; return }
        $it.Tag = $neuArt; $it.SubItems[1].Text = (& $artText $neuArt); & $speichern; & $fuelle   # 2.3.5: Zustand neu bestimmen
    })
    $lv.Add_MouseClick({
        param($sender, $ev)
        $h = $lv.HitTest($ev.Location)
        if (-not $h.Item -or -not $h.SubItem) { return }
        $spalte = $h.Item.SubItems.IndexOf($h.SubItem)
        # 2.3.4: Klick auf "Packs liegen tiefer" bietet an, die Quelle auf die Pack-Ebene umzustellen
        if ($spalte -eq 3) { & $umstellen $h.Item.Text ([string]$h.Item.Tag); return }
        if ($spalte -ne 1) { return }
        $script:artZeile = $h.Item
        foreach ($mi in $artMenue.Items) { $mi.Checked = ([string]$mi.Tag -eq [string]$h.Item.Tag) }
        $artMenue.Show($lv, $ev.Location)
    })
    $umstellen = { param($alt, $art)
            $eb = & $ebeneVon $alt $art
            if (-not $eb) { return }
            $name = ($eb.Substring($alt.TrimEnd('\').Length).TrimStart('\') -split '\\')[0]
            if (-not (Show-Frage "Die Packs dieser Quelle liegen erst in`n$eb`n`nSo wie eingetragen würde beim Sortieren '$name' zum Pack-Namen, statt der Namen der einzelnen Packs.`n`nQuelle auf diesen Ordner umstellen (Art 'Sammlung')?`nAm Ordner selbst wird nichts geändert. Schon Einsortiertes bleibt, wie es ist.")) { return }
            $e = Get-Einstellungen
            $f = Test-NeueQuelle $eb $e.Quellen $e.Ziel $alt 'Sammlung'
            if ($f) { Show-Meldung "$f`n`nDie Quelle wurde nicht umgestellt." 'Warning'; return }
            $neu = @(foreach ($q in @($e.Quellen)) { if ($q.Pfad -eq $alt) { [pscustomobject]@{ Pfad = $eb; Aktiv = [bool]$q.Aktiv; Herkunft = $q.Herkunft; Art = 'Sammlung' } } else { $q } })
            try { Set-Quellen $neu } catch { Show-Meldung "Speichern fehlgeschlagen:`n$($_.Exception.Message)" 'Error'; return }
            & $fuelle
    }
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
        # 2.3.3: Liegen die Packs erst tiefer (z. B. Splice\Samples\packs), diese Ebene als Sammlung vorschlagen
        if ($art -ne 'Lose') {
            $ebene = Get-PackEbene $neu
            if ($ebene -and (Show-Frage "Die Packs in diesem Ordner liegen erst in`n$ebene`n`nDiesen Ordner als 'Sammlung' eintragen (empfohlen)? Dann behält jedes Pack im Ziel seinen Namen.`n`nNein: $neu wird so eingetragen, wie gewählt.")) { $neu = $ebene; $art = 'Sammlung' }
        }
        $f = Test-NeueQuelle $neu $e.Quellen $e.Ziel '' $art
        if ($f) { Show-Meldung "$f`n`nDie Quelle wurde nicht hinzugefügt." 'Warning'; return }
        Set-Quellen (@($e.Quellen) + [pscustomobject]@{ Pfad = $neu; Aktiv = $true; Herkunft = 'manuell'; Art = $art })
        & $fuelle
        Show-Meldung "Hinzugefügt als '$($QuellArten[$art])'.`n`nFalls das nicht passt: in der Liste auf die Art klicken und ändern (Erklärung unter ⓘ)."
    })
    $g0.Controls.Add($bAdd)
    $bWeg = New-Object System.Windows.Forms.Button
    $bWeg.Text = 'Entfernen'; $bWeg.Font = $schrift; $bWeg.FlatStyle = 'System'
    $bWeg.Location = New-Object System.Drawing.Point(150, $by); $bWeg.Size = New-Object System.Drawing.Size(110, 30)
    $bWeg.Add_Click({
        if (-not $lv.SelectedItems.Count) { Show-Meldung 'Bitte zuerst eine Quelle in der Liste anklicken.' 'Warning'; return }
        # Quelle vor der Rueckfrage merken: beim Schliessen der Rueckfrage kann die Markierung verloren gehen (2.3.2)
        $pf = $lv.SelectedItems[0].Text
        if (-not (Show-Frage "Diese Quelle aus der Liste nehmen?`n$pf`n`nDer Ordner selbst bleibt unverändert.")) { return }
        foreach ($x in @($lv.Items)) { if ($x.Text -eq $pf) { $lv.Items.Remove($x) } }
        & $speichern; & $fuelle
    })
    $tt.SetToolTip($bWeg, 'Nimmt die markierte Quelle aus der Liste. Am Ordner wird nichts geändert.')
    $g0.Controls.Add($bWeg)
    $bSuch = New-Object System.Windows.Forms.Button
    $bSuch.Text = 'Fundorte suchen ...'; $bSuch.Font = $schrift; $bSuch.FlatStyle = 'System'
    $bSuch.Location = New-Object System.Drawing.Point(268, $by); $bSuch.Size = New-Object System.Drawing.Size(150, 30)
    $bSuch.Add_Click({ Show-FundorteSuchen })
    $tt.SetToolTip($bSuch, 'Sucht auf Laufwerken und in Ordnern nach Sample-Packs und zeigt die Fundorte im Browser. Dort lassen sie sich als Quellen übernehmen.')
    $g0.Controls.Add($bSuch)
    $bInfo = New-Object System.Windows.Forms.Button
    $bInfo.Text = 'ⓘ'; $bInfo.Font = New-Object System.Drawing.Font('Segoe UI Symbol', 11); $bInfo.FlatStyle = 'System'
    $bInfo.Location = New-Object System.Drawing.Point(426, $by); $bInfo.Size = New-Object System.Drawing.Size(34, 30)
    $bInfo.Add_Click({ Show-ArtInfo $(if ($lv.SelectedItems.Count) { $lv.SelectedItems[0] } else { $null }) })
    $tt.SetToolTip($bInfo, 'Was bedeutet die Art? Zeigt am markierten Ordner, was jede Art bewirkt.')
    $g0.Controls.Add($bInfo)
    $ay = $by + 40
    # 2.3.5: deutlicher Hinweis, wenn bei einer Quelle die Packs tiefer liegen
    $lWarn.Location = New-Object System.Drawing.Point(12, $ay); $lWarn.Size = New-Object System.Drawing.Size(($gb - 24), 22)
    $g0.Controls.Add($lWarn)
    $ay += 26
    $lq = New-Hinweis $g0 'Haken = aktiv: Sortieren und „Quelle aufräumen“ lesen alle aktiven Quellen. Art = wie die Packs im Ordner erkannt werden – zum Ändern auf die Art klicken, Erklärung unter ⓘ. Doppelklick öffnet einen Ordner.' 12 $ay ($gb - 24)
    $g0.Height = $ay + $lq.PreferredHeight + 14
    $dy += $g0.Height + 10
    # Nach "Fundorte suchen" (Uebernahme im Browser) neu einlesen - nur wenn sich die Einstellungen geaendert haben
    $d.Add_Activated({ if ((& $stand) -ne $script:qStand) { & $fuelle } })

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
    $lh = New-Hinweis $g1 'Downloads und Download-Archiv nutzt „Download importieren …“: dort wird nach neuen Packs gesucht, ins Download-Archiv kommen auf Wunsch die Originale.' 12 ($gy + 2) ($gb - 24)
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
    $l = New-Hinweis $d 'Wo soll nach Sample-Packs gesucht werden? Es werden nur Ordner- und Dateinamen gelesen (bei Archiven das Inhaltsverzeichnis), nichts verändert, nichts entpackt und keine Cloud-Dateien heruntergeladen. Windows-, Programm- und Anwendungsordner sowie das Ziel werden ausgelassen.' 16 14 $innen
    $l.ForeColor = [System.Drawing.Color]::Black
    $y = 14 + $l.PreferredHeight + 12
    $clb = New-Object System.Windows.Forms.CheckedListBox
    $clb.CheckOnClick = $true; $clb.IntegralHeight = $false
    $clb.Location = New-Object System.Drawing.Point(16, $y); $clb.Size = New-Object System.Drawing.Size($innen, 200)
    $d.Controls.Add($clb)
    $orte = New-Object System.Collections.Generic.List[string]
    # 2.3.5: Auswahl merken - angehakte Orte und selbst hinzugefuegte Ordner stehen in den Einstellungen
    $einstF = Get-Einstellungen
    $gemerkt = @(([string]$einstF.FundortAn) -split '\|' | Where-Object { $_ })
    $zusatz = @(([string]$einstF.FundortZusatz) -split '\|' | Where-Object { $_ })
    $standard = New-Object System.Collections.Generic.List[string]
    $add = { param($pfad, $text, $an, $istStandard)
        if ($pfad -and (Test-Path -LiteralPath $pfad) -and -not ($orte -contains $pfad)) {
            if ($gemerkt.Count) { $an = ($gemerkt -contains $pfad) }
            $orte.Add($pfad); [void]$clb.Items.Add($text, [bool]$an)
            if ($istStandard) { $standard.Add($pfad) }
        } }
    & $add (Get-StandardDownloads) "Downloads  ($(Get-StandardDownloads))" $true $true
    & $add ([Environment]::GetFolderPath('MyDocuments')) "Dokumente  ($([Environment]::GetFolderPath('MyDocuments')))" $true $true
    & $add ([Environment]::GetFolderPath('Desktop')) "Desktop  ($([Environment]::GetFolderPath('Desktop')))" $true $true
    & $add ([Environment]::GetFolderPath('MyMusic')) "Musik  ($([Environment]::GetFolderPath('MyMusic')))" $true $true
    $sys = "$env:SystemDrive\"
    foreach ($lw in [IO.DriveInfo]::GetDrives()) {
        try {
            if (-not $lw.IsReady -or $lw.DriveType -notin 'Fixed', 'Removable') { continue }
            $frei = '{0:N0} GB belegt' -f (($lw.TotalSize - $lw.TotalFreeSpace) / 1GB)
            $name = if ($lw.VolumeLabel) { " $($lw.VolumeLabel)" } else { '' }
            if ($lw.RootDirectory.FullName -ieq $sys) { & $add $lw.RootDirectory.FullName "Laufwerk $($lw.Name)$name ganz  ($frei, Systemlaufwerk – dauert länger)" $false $true }
            elseif ($lw.DriveType -eq 'Removable') { & $add $lw.RootDirectory.FullName "Laufwerk $($lw.Name)$name ganz  ($frei, Wechseldatenträger)" $false $true }
            else { & $add $lw.RootDirectory.FullName "Laufwerk $($lw.Name)$name ganz  ($frei)" $true $true }
        } catch { }
    }
    foreach ($z in $zusatz) { & $add $z $z $true $false }
    $y += 200 + 8
    $bOrd = New-Object System.Windows.Forms.Button
    $bOrd.Text = 'Ordner hinzufügen ...'; $bOrd.FlatStyle = 'System'
    $bOrd.Location = New-Object System.Drawing.Point(16, $y); $bOrd.Size = New-Object System.Drawing.Size(170, 30)
    $bOrd.Add_Click({
        $dlg = New-Object System.Windows.Forms.FolderBrowserDialog
        $dlg.Description = 'Zusätzlichen Ordner durchsuchen'; $dlg.ShowNewFolderButton = $false
        if ($dlg.ShowDialog($d) -eq 'OK') { $sp = $dlg.SelectedPath; if ($sp.Length -gt 3) { $sp = $sp.TrimEnd('\') }; $gemerkt = @(); & $add $sp $sp $true $false }
    })
    $d.Controls.Add($bOrd)
    # 2.3.5: selbst hinzugefuegte Ordner wieder entfernen; die Standardorte lassen sich nur abhaken
    $bWegO = New-Object System.Windows.Forms.Button
    $bWegO.Text = 'Entfernen'; $bWegO.FlatStyle = 'System'; $bWegO.Enabled = $false
    $bWegO.Location = New-Object System.Drawing.Point(16, ($y + 38)); $bWegO.Size = New-Object System.Drawing.Size(170, 30)
    $clb.Add_SelectedIndexChanged({ $i = $clb.SelectedIndex; $bWegO.Enabled = ($i -ge 0 -and -not ($standard -contains $orte[$i])) })
    $bWegO.Add_Click({
        $i = $clb.SelectedIndex
        if ($i -lt 0 -or ($standard -contains $orte[$i])) { return }
        $orte.RemoveAt($i); $clb.Items.RemoveAt($i); $bWegO.Enabled = $false
    })
    $d.Controls.Add($bWegO)
    # 2.3.2: in ZIP-Archive hineinschauen (nur Inhaltsverzeichnis)
    $cbZip = New-Object System.Windows.Forms.CheckBox
    $cbZip.Text = 'In ZIP-Archive hineinschauen (dauert etwas länger)'; $cbZip.AutoSize = $true; $cbZip.Checked = [bool]$einstF.FundortZip
    $cbZip.Location = New-Object System.Drawing.Point(200, ($y + 5))
    $tt2 = New-Object System.Windows.Forms.ToolTip; $tt2.AutoPopDelay = 15000
    $tt2.SetToolTip($cbZip, "Liest bei ZIP-Archiven (mit Windows 11 auch RAR und 7z) das Inhaltsverzeichnis: Wie viele Audiodateien sind darin?`nArchive ohne Audiodateien werden dann nicht mehr gezeigt. Es wird nichts entpackt; Archive, die nur in der Cloud liegen, werden nicht geöffnet.")
    $d.Controls.Add($cbZip)
    $tt2.SetToolTip($bWegO, 'Nimmt einen selbst hinzugefügten Ordner wieder aus der Liste. Downloads, Dokumente, Desktop, Musik und Laufwerke lassen sich nur abhaken.')
    $y += 38 + 44
    # 2.3.2: letzten Bericht ohne neuen Suchlauf oeffnen
    $letzter = $null; try { $letzter = Get-LetzterFundortBericht } catch { }
    $bLetzt = New-Object System.Windows.Forms.Button
    $bLetzt.FlatStyle = 'System'
    $bLetzt.Text = $(if ($letzter) { 'Letzten Bericht öffnen (' + $letzter.LastWriteTime.ToString('dd.MM.yyyy HH:mm') + ')' } else { 'Letzten Bericht öffnen' })
    $bLetzt.Enabled = [bool]$letzter
    $bLetzt.Location = New-Object System.Drawing.Point(16, $y); $bLetzt.Size = New-Object System.Drawing.Size(320, 32)
    $tt2.SetToolTip($bLetzt, $(if ($letzter) { "Öffnet den Bericht des letzten Suchlaufs ohne neue Suche.`n$($letzter.FullName)" } else { 'Es gibt noch keinen Bericht – bitte zuerst suchen.' }))
    $bLetzt.DialogResult = 'Retry'
    $d.Controls.Add($bLetzt)
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
    $mitZip = $cbZip.Checked
    $d.Dispose()
    # 2.3.5: Auswahl fuer das naechste Mal merken (nur wenn etwas angehakt ist)
    try {
        $zus = @($orte | Where-Object { -not ($standard -contains $_) })
        if ($gewaehlt.Count) { Set-Einstellung 'FundortAn' ($gewaehlt -join '|') }
        Set-Einstellung 'FundortZusatz' ($zus -join '|')
        Set-Einstellung 'FundortZip' $mitZip
    } catch { Write-FehlerLog "Fundorte-Auswahl nicht gespeichert: $($_.Exception.Message)" }
    if ($r -eq 'Retry' -and $letzter) {
        if (-not (Start-FundortBericht $letzter.FullName)) { Show-Meldung "Der Bericht konnte nicht geöffnet werden.`n$($letzter.FullName)" 'Warning' }
        return
    }
    if ($r -ne 'OK') { return }
    if (-not $gewaehlt.Count) { Show-Meldung 'Es ist kein Ort ausgewählt.' 'Warning'; return }
    $zusatz = if ($mitZip) { '' } else { ' -OhneArchivinhalt' }
    [void](Start-Skript 'Fundorte-suchen.ps1' "-Orte '$(($gewaehlt -join '|').Replace("'", "''"))'$zusatz" 'Fundorte suchen')
}

# ---------------------------------------------------------------------------
# Dialog: Download importieren (Version 3, IMP-01 bis IMP-10)
# ---------------------------------------------------------------------------
function Show-DownloadImport {
    $e = Get-Einstellungen
    $zs = Get-OrdnerStatus $e.Ziel
    if ($zs.Fehlt) { Show-Meldung "Der Zielordner ist nicht erreichbar:`n$($e.Ziel)`n$($zs.Text)`n`nBitte über ⚙ Einstellungen den richtigen Ordner wählen." 'Warning'; return }
    if (-not $e.Downloads -or -not (Test-Path -LiteralPath $e.Downloads -PathType Container)) { Show-Meldung "Der Download-Ordner wurde nicht gefunden:`n$($e.Downloads)`n`nBitte über ⚙ Einstellungen einstellen." 'Warning'; return }
    Set-Wartezeiger $true
    try { . (Join-Path $skriptOrdner 'Import.ps1'); $kand = @(Get-ImportKandidaten) } finally { Set-Wartezeiger $false }
    if (-not $kand.Count) { Show-Meldung "Im Download-Ordner wurden keine Sample-Packs gefunden:`n$($e.Downloads)`n`nGesucht wird nach ZIP-Dateien und Ordnern mit Audiodateien direkt im Download-Ordner."; return }
    $w = 900; $innen = $w - 32
    $d = New-Object System.Windows.Forms.Form
    $d.Text = 'Download importieren'
    $d.StartPosition = 'CenterParent'; $d.FormBorderStyle = 'FixedDialog'
    $d.MaximizeBox = $false; $d.MinimizeBox = $false
    $d.Font = $schrift; $d.BackColor = [System.Drawing.Color]::White
    $y = 14
    # Typografische Anfuehrungszeichen nur in einfachen Anfuehrungszeichen (in doppelten beenden sie den Text)
    $l = New-Hinweis $d ('Neue Sample-Packs in ' + $e.Downloads + '. Die angehakten werden entpackt und nach den Regeln von „Samples sortieren“ einsortiert. Im Hauptfenster erscheint zuerst die Vorschau; kopiert wird erst, wenn du dort bestätigst.') 16 $y $innen
    $l.ForeColor = [System.Drawing.Color]::Black
    $y += $l.PreferredHeight + 10
    $lv = New-Object System.Windows.Forms.ListView
    $lv.View = 'Details'; $lv.CheckBoxes = $true; $lv.FullRowSelect = $true; $lv.MultiSelect = $false; $lv.Font = $schrift
    $lv.Location = New-Object System.Drawing.Point(16, $y); $lv.Size = New-Object System.Drawing.Size($innen, 220)
    [void]$lv.Columns.Add('Download', 280); [void]$lv.Columns.Add('Typ', 55); [void]$lv.Columns.Add('Pack-Art', 130); [void]$lv.Columns.Add('Größe', 70, 'Right'); [void]$lv.Columns.Add('Audio', 55, 'Right'); [void]$lv.Columns.Add('Datum', 80); [void]$lv.Columns.Add('Hinweis', ($innen - 280 - 55 - 130 - 70 - 55 - 80 - 24))
    # 3.0.1: Pack-Art je Download (erkannt wie bei Fundorten), per Klick änderbar
    $artText = { param($k) if ($k.Wahl -eq 'Sammlung') { "Sammlung ($(@($k.Packs).Count)) ▾" } else { 'Ein Pack  ▾' } }
    foreach ($k in $kand) {
        $k | Add-Member NoteProperty Wahl $k.PackArt -Force
        $it = New-Object System.Windows.Forms.ListViewItem($k.Name)
        [void]$it.SubItems.Add($k.Art)
        [void]$it.SubItems.Add($(if ($k.Anhakbar) { & $artText $k } else { '' }))
        [void]$it.SubItems.Add($(if ($k.Bytes -ge 1GB) { '{0:N1} GB' -f ($k.Bytes / 1GB) } elseif ($k.Bytes) { '{0:N0} MB' -f [Math]::Max(1, $k.Bytes / 1MB) } else { '' }))
        [void]$it.SubItems.Add($(if ($k.Audio) { '{0:N0}' -f $k.Audio } else { '' }))
        [void]$it.SubItems.Add($k.Datum.ToString('dd.MM.yyyy'))
        [void]$it.SubItems.Add($k.Hinweis)
        $it.Tag = $k
        if (-not $k.Anhakbar) { $it.ForeColor = [System.Drawing.Color]::Gray }
        [void]$lv.Items.Add($it)
        $it.Checked = $k.Anhakbar
    }
    # Nicht importierbare Zeilen (schon vollständig im Ziel, RAR/7z, nicht lesbar) lassen sich nicht anhaken
    $lv.Add_ItemCheck({ param($s, $ev) if (-not $lv.Items[$ev.Index].Tag.Anhakbar) { $ev.NewValue = 'Unchecked' } })
    $artMenue = New-Object System.Windows.Forms.ContextMenuStrip; $artMenue.Font = $schrift
    foreach ($a in @(@('Pack', 'Ein Pack – alles unter dem Namen des Downloads'), @('Sammlung', 'Sammlung – jeder Unterordner ist ein eigenes Pack'))) { $mi = $artMenue.Items.Add($a[1]); $mi.Tag = $a[0] }
    $script:importZeile = $null
    $artMenue.Add_ItemClicked({ param($s, $ev) $it = $script:importZeile; if (-not $it) { return }; $it.Tag.Wahl = [string]$ev.ClickedItem.Tag; $it.SubItems[2].Text = (& $artText $it.Tag) })
    $lv.Add_MouseClick({ param($s, $ev)
        $h = $lv.HitTest($ev.Location)
        if (-not $h.Item -or -not $h.SubItem -or -not $h.Item.Tag.Anhakbar) { return }
        if ($h.Item.SubItems.IndexOf($h.SubItem) -ne 2) { return }
        $script:importZeile = $h.Item
        foreach ($mi in $artMenue.Items) { $mi.Checked = ([string]$mi.Tag -eq [string]$h.Item.Tag.Wahl) }
        $artMenue.Show($lv, $ev.Location) })
    $tt3 = New-Object System.Windows.Forms.ToolTip; $tt3.AutoPopDelay = 15000
    $tt3.SetToolTip($lv, 'Klick auf die Pack-Art: ändern. Sammlung = der Download enthält mehrere eigenständige Packs (z. B. „Vol 1“, „Vol 2“); jedes wird unter seinem eigenen Namen einsortiert.')
    $d.Controls.Add($lv)
    $y += 220 + 12
    $lo = New-Object System.Windows.Forms.Label
    $lo.Text = 'Danach mit dem Original:'; $lo.Font = $schriftFett; $lo.AutoSize = $true; $lo.Location = New-Object System.Drawing.Point(16, $y)
    $d.Controls.Add($lo); $y += 26
    $wahl = [string]$e.ImportOriginal; if ($wahl -notin 'Archiv', 'Behalten', 'Papierkorb') { $wahl = 'Archiv' }
    $radios = @{}
    foreach ($o in @(@('Archiv', "ins Download-Archiv verschieben  ($($e.DownloadArchiv))"), @('Behalten', 'im Download-Ordner lassen'), @('Papierkorb', 'in den Papierkorb'))) {
        $rb = New-Object System.Windows.Forms.RadioButton
        $rb.Text = $o[1]; $rb.Tag = $o[0]; $rb.AutoSize = $true; $rb.Checked = ($o[0] -eq $wahl)
        $rb.Location = New-Object System.Drawing.Point(24, $y); $d.Controls.Add($rb); $radios[$o[0]] = $rb; $y += 26
    }
    $lh = New-Hinweis $d 'Verschoben oder gelöscht wird ein Original nur, wenn alle seine Dateien per Prüfsumme bestätigt im Ziel liegen; sonst bleibt es im Download-Ordner. Der Arbeitsordner zum Entpacken wird danach immer entfernt.' 24 ($y + 2) ($innen - 10)
    $y += $lh.PreferredHeight + 16
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
    $gewaehlt = @($lv.Items | Where-Object { $_.Checked -and $_.Tag.Anhakbar } | ForEach-Object { $_.Tag.Name })
    $arten = @($lv.Items | Where-Object { $_.Checked -and $_.Tag.Anhakbar } | ForEach-Object { "$($_.Tag.Name)*$($_.Tag.Wahl)" }) -join '|'
    $orig = @($radios.Keys | Where-Object { $radios[$_].Checked }) | Select-Object -First 1
    $d.Dispose()
    if ($r -ne 'OK') { return }
    if (-not $gewaehlt.Count) { Show-Meldung 'Es ist kein Pack angehakt.' 'Warning'; return }
    try { Set-Einstellung 'ImportOriginal' $orig } catch { }
    [void](Start-Skript 'Download-importieren.ps1' "-Auswahl '$(($gewaehlt -join '|').Replace("'", "''"))' -Arten '$($arten.Replace("'", "''"))' -Original $orig" 'Download importieren')
}

# ---------------------------------------------------------------------------
# Dialog: Ziel aufraeumen (2.3.3) - Duplikate und Formate neben gleichnamiger WAV
# ---------------------------------------------------------------------------
function Show-ZielAufraeumen {
    $w = 640; $innen = $w - 32
    $d = New-Object System.Windows.Forms.Form
    $d.Text = 'Duplikate und Formate im Ziel entfernen'
    $d.StartPosition = 'CenterParent'; $d.FormBorderStyle = 'FixedDialog'
    $d.MaximizeBox = $false; $d.MinimizeBox = $false
    $d.Font = $schrift; $d.BackColor = [System.Drawing.Color]::White
    $y = 14
    $l = New-Hinweis $d "Was soll aus der Bibliothek (Ziel) in den Papierkorb? Grundlage ist der letzte Stand der Sample-Bibliothek. Im Hauptfenster erscheint zuerst die Vorschau; entfernt wird erst, wenn du dort bestätigst." 16 $y $innen
    $l.ForeColor = [System.Drawing.Color]::Black
    $y += $l.PreferredHeight + 14
    $c1 = New-Object System.Windows.Forms.CheckBox
    $c1.Text = 'Duplikate (inhaltsgleich; je Gruppe bleibt ein Exemplar, Kits bleiben vollständig)'; $c1.AutoSize = $true; $c1.Checked = $true
    $c1.Location = New-Object System.Drawing.Point(18, $y); $d.Controls.Add($c1); $y += 28
    $c2 = New-Object System.Windows.Forms.CheckBox
    $c2.Text = 'Formate neben einer gleichnamigen WAV aus demselben Pack:'; $c2.AutoSize = $true; $c2.Checked = $false
    $c2.Location = New-Object System.Drawing.Point(18, $y); $d.Controls.Add($c2); $y += 26
    $fHaken = @(); $x = 40
    foreach ($fmt in 'RX2', 'MP3', 'AIFF') {
        $c = New-Object System.Windows.Forms.CheckBox
        $c.Text = $fmt; $c.AutoSize = $true; $c.Checked = $true; $c.Enabled = $false
        $c.Location = New-Object System.Drawing.Point($x, $y); $d.Controls.Add($c); $fHaken += $c; $x += 90
    }
    $y += 28
    $lf = New-Hinweis $d 'Entfernt wird nur, wenn die WAV wirklich da ist. Nützlich, wenn beim Sortieren der Haken „Zusätzlich zur WAV behalten“ noch gesetzt war.' 40 $y ($innen - 30)
    $y += $lf.PreferredHeight + 14
    $c2.Add_CheckedChanged({ foreach ($cb in $fHaken) { $cb.Enabled = $c2.Checked } })
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
    $fl = @($fHaken | Where-Object { $_.Checked } | ForEach-Object { $_.Text })
    if ($c2.Checked -and $fl.Count) { $arg += '-Formate'; $arg += "-Formatliste '$($fl -join ',')'" }
    $d.Dispose()
    if ($r -ne 'OK') { return }
    if (-not $arg.Count) { Show-Meldung 'Es ist nichts ausgewählt.' 'Warning'; return }
    [void](Start-Skript 'Ziel-Duplikate-entfernen.ps1' ($arg -join ' ') 'Duplikate und Formate im Ziel entfernen')
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
    $l = New-Hinweis $d "Was soll aus welcher Quelle in den Papierkorb? Im Hauptfenster erscheint zuerst die Vorschau; entfernt wird erst, wenn du dort bestätigst." 16 $y $innen
    $l.ForeColor = [System.Drawing.Color]::Black
    $y += $l.PreferredHeight + 14
    function New-Haken([string]$text, [int]$x, [bool]$an) {
        $c = New-Object System.Windows.Forms.CheckBox
        $c.Text = $text; $c.AutoSize = $true; $c.Location = New-Object System.Drawing.Point($x, $script:hy); $c.Checked = $an
        $d.Controls.Add($c); return $c
    }
    $script:hy = $y
    # QLN-05, 2.3.5: zuerst waehlen, welche Quellen aufgeraeumt werden - immer sichtbar, auch bei nur einer aktiven Quelle
    $qHaken = @()
    $lq = New-Object System.Windows.Forms.Label
    $lq.Text = 'Welche Quellen?'; $lq.Font = $schriftFett; $lq.AutoSize = $true; $lq.Location = New-Object System.Drawing.Point(16, $script:hy)
    $d.Controls.Add($lq); $script:hy += 26
    foreach ($q in $aktiv) { $c = New-Haken $q.Pfad 18 $true; $c.AutoSize = $false; $c.Width = $innen; $qHaken += $c; $script:hy += 26 }
    $script:hy += 8
    $lw = New-Object System.Windows.Forms.Label
    $lw.Text = 'Was soll entfernt werden?'; $lw.Font = $schriftFett; $lw.AutoSize = $true; $lw.Location = New-Object System.Drawing.Point(16, $script:hy)
    $d.Controls.Add($lw); $script:hy += 26
    $c1 = New-Haken 'Duplikate (beim Sortieren als doppelt erkannt, Prüfung gegen das behaltene Exemplar)' 18 $true; $script:hy += 28
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
