# (c) 2026 Herbert Stoecker. Prototyp fuer die Samples-Werkzeuge - nur zum Testen.
<#
.SYNOPSIS
  YAMNet-Prototyp: hoert sich Samples an und schlaegt eine grobe Einordnung vor
  (z. B. Kick, Snare, Vocals, Keys, Atmos), wenn der Dateiname nichts hergibt.
  Gedacht fuer Dateien in "_Unsortiert". Es wird nichts verschoben oder veraendert;
  Ergebnis ist ein CSV-Bericht.

  Modell: YAMNet (Google, AudioSet, 521 Klassen) als ONNX-Datei von Qualcomm AI Hub
  (Ordner "Modell": yamnet.onnx, yamnet.data, labels.txt). Das Netz wird ohne
  zusaetzliche Software in C# nachgerechnet.

.BENUTZUNG
  Ohne Schalter: kleines Fenster mit Ordnerauswahl.
    -Quelle "C:\...\_Unsortiert"   Ordner (ohne Fenster)
    -MaxSekunden 10                 je Datei hoechstens so viele Sekunden anhoeren
    -OhneUnterordner                nur Dateien direkt im Ordner
    -Modellordner "..."             anderer Ort fuer yamnet.onnx, yamnet.data, labels.txt
#>
[CmdletBinding()]
param(
    [string]$Quelle,
    [double]$MaxSekunden = 10,
    [switch]$OhneUnterordner,
    [string]$Modellordner
)
$ErrorActionPreference = 'Stop'
$Version = '0.1'
$wurzel = Split-Path -Parent $PSScriptRoot
if (-not $Modellordner) { $Modellordner = Join-Path $wurzel 'Modell' }
$berichtOrdner = Join-Path $wurzel 'Berichte'
$merkDatei = Join-Path $PSScriptRoot 'Letzter-Ordner.txt'
$de = [Globalization.CultureInfo]'de-DE'

# ---------------------------------------------------------------------------
# Kern laden (C#)
# ---------------------------------------------------------------------------
if (-not ('SamplesWerkzeuge.Yamnet.Modell' -as [type])) {
    $cs = [IO.File]::ReadAllText((Join-Path $PSScriptRoot 'YamnetKern.cs'))
    if ($PSVersionTable.PSEdition -ne 'Core') {
        # Windows PowerShell 5.1: mit Optimierung uebersetzen (deutlich schneller)
        $cp = New-Object System.CodeDom.Compiler.CompilerParameters
        $cp.CompilerOptions = '/optimize+'; $cp.GenerateInMemory = $true
        [void]$cp.ReferencedAssemblies.Add('System.dll')
        Add-Type -TypeDefinition $cs -CompilerParameters $cp
    } else { Add-Type -TypeDefinition $cs -Language CSharp }
}

# ---------------------------------------------------------------------------
# Zuordnung AudioSet-Klassen (Nummer in labels.txt) -> Kategorien der Samples-Werkzeuge
# Wert einer Kategorie = hoechster Mittelwert ihrer Klassen. Achtung: Schluessel "Keys" -> immer get_Keys() verwenden
# ---------------------------------------------------------------------------
function Get-Bereich([int]$von, [int]$bis) { $von..$bis }
$Kategorien = [ordered]@{
    'Kick'          = @{ Ziel = '01 Drums\Kick';                 K = @(163) }
    'Snare'         = @{ Ziel = '01 Drums\Snare';                K = @(160, 161) }
    'HiHat'         = @{ Ziel = '01 Drums\HiHat';                K = @(167) }
    'Cymbals'       = @{ Ziel = '01 Drums\Cymbals';              K = @(166, 172) }
    'Clap'          = @{ Ziel = '01 Drums\Clap';                 K = @(56, 57, 58) }
    'Drums'         = @{ Ziel = '01 Drums';                      K = @(157, 158, 159, 162) }
    'Percussion'    = @{ Ziel = '02 Percussion\Diverse Percs';   K = @(87, 156, 164, 165, 168, 178) }
    'Shaker'        = @{ Ziel = '02 Percussion\Shaker & Tambourine'; K = @(169, 170, 171) }
    'Foley'         = @{ Ziel = '02 Percussion\Foley';           K = @((Get-Bereich 46 55) + (Get-Bereich 348 381) + (Get-Bereich 398 419) + (Get-Bereich 431 452) + (Get-Bereich 454 455) + (Get-Bereich 459 474)) }
    'Bass'          = @{ Ziel = '03 Bass';                       K = @(137, 189) }
    'Keys'          = @{ Ziel = '04 Keys & Synth\Keys';          K = @(147, 148, 149, 150, 151, 152, 155, 173, 174, 175, 176, 177) + (Get-Bereich 195 202) + @(204, 209) }
    'Synth'         = @{ Ziel = '04 Keys & Synth\Synth';         K = @(153, 154, 208) }
    'Guitar'        = @{ Ziel = '05 Guitar';                     K = @(134, 135, 136) + (Get-Bereich 138 146) }
    'Brass'         = @{ Ziel = '06 Brass & Sax';                K = @(180, 181, 182, 183, 190, 191, 192, 193, 203, 205, 206, 207) }
    'Vocals'        = @{ Ziel = '07 Vocals';                     K = @((Get-Bereich 0 35) + @(213, 249, 250)) }
    'FX'            = @{ Ziel = '08 FX & Noise';                 K = @(210) + (Get-Bereich 382 397) + (Get-Bereich 420 430) + @(453, 456, 457, 458) + (Get-Bereich 475 493) + (Get-Bereich 495 499) + @(507) + (Get-Bereich 509 517) }
    'Atmos'         = @{ Ziel = '09 Atmos & Field Recordings';   K = @((Get-Bereich 61 131) + (Get-Bereich 277 347) + (Get-Bereich 500 506) + @(508, 518, 519, 520)) }
    'Strings'       = @{ Ziel = '13 Strings & Orchestra';        K = @(179, 184, 185, 186, 187, 188, 194) }
}
$Stile = @(Get-Bereich 211 276)          # Musikstile (nur Information)
$Sicherheit = { param($w) if ($w -ge 0.5) { 'hoch' } elseif ($w -ge 0.2) { 'mittel' } elseif ($w -ge 0.08) { 'gering' } else { 'unklar' } }
$AudioEndungen = '\.(wav|aif|aiff|aifc|mp3|flac|ogg|m4a|rx2|rex)$'
$Lesbar = '\.(wav|aif|aiff|aifc)$'

function Format-Wert([double]$w) { $w.ToString('0.000', $de) }

# ---------------------------------------------------------------------------
# Analyse
# ---------------------------------------------------------------------------
function Invoke-Analyse([string]$ordner, [double]$maxSek, [bool]$unter, [scriptblock]$fortschritt) {
    foreach ($d in 'yamnet.onnx', 'yamnet.data', 'labels.txt') {
        if (-not (Test-Path -LiteralPath (Join-Path $Modellordner $d))) { throw "Modelldatei fehlt: $(Join-Path $Modellordner $d)`nBitte yamnet.onnx, yamnet.data und labels.txt in den Ordner 'Modell' legen." }
    }
    $modell = New-Object SamplesWerkzeuge.Yamnet.Modell (Join-Path $Modellordner 'yamnet.onnx'), (Join-Path $Modellordner 'labels.txt')
    $kl = $modell.Klassen
    $opt = @{ LiteralPath = $ordner; File = $true; ErrorAction = 'SilentlyContinue' }
    if ($unter) { $opt.Recurse = $true }
    $dateien = @(Get-ChildItem @opt | Where-Object { $_.Name -match $AudioEndungen -and -not $_.Name.StartsWith('._') -and $_.FullName -notmatch '[\\/]__MACOSX[\\/]' } | Sort-Object FullName)
    if (-not $dateien.Count) { throw "Im Ordner wurden keine Audiodateien gefunden:`n$ordner" }
    if (-not (Test-Path -LiteralPath $berichtOrdner)) { New-Item -ItemType Directory -Path $berichtOrdner -Force | Out-Null }
    $ts = Get-Date -Format 'yyyy-MM-dd_HHmmss'
    $csvPfad = Join-Path $berichtOrdner "YAMNet-Analyse_$ts.csv"
    $klPfad = Join-Path $berichtOrdner "YAMNet-Klassen_$ts.csv"
    $zeilen = New-Object System.Collections.Generic.List[object]
    $klZeilen = New-Object System.Collections.Generic.List[string]
    $klZeilen.Add('Datei;Ordner;' + (($kl | ForEach-Object { '"' + $_.Replace('"', '""') + '"' }) -join ';'))
    $basis = $ordner.TrimEnd('\', '/')
    $i = 0
    foreach ($f in $dateien) {
        $i++
        & $fortschritt $i $dateien.Count $f.Name
        $uhr = [Diagnostics.Stopwatch]::StartNew()
        $rel = $f.DirectoryName.Substring([Math]::Min($basis.Length, $f.DirectoryName.Length)).TrimStart('\', '/')
        $z = [ordered]@{
            'Datei' = $f.Name; 'Unterordner' = $rel; 'Format' = $f.Extension.TrimStart('.').ToUpperInvariant(); 'Dauer s' = ''; 'Abtastrate' = ''; 'Kanaele' = ''; 'Bit' = ''
            'Pegel RMS dBFS' = ''; 'Spitze dBFS' = ''; 'Analysiert s' = ''; 'Ausschnitte' = ''
            'Vorschlag Kategorie' = ''; 'Vorschlag Zielordner' = ''; 'Typ (nach Dauer)' = ''; 'Sicherheit' = ''; 'Wert' = ''
            'Zweite Kategorie' = ''; 'Wert 2' = ''
            'Top 1' = ''; 'Top 2' = ''; 'Top 3' = ''; 'Top 4' = ''; 'Top 5' = ''
            'Spitze 1' = ''; 'Spitze 2' = ''; 'Spitze 3' = ''
            'Musikstil' = ''; 'Musik' = ''; 'Stille' = ''
        }
        foreach ($k in $Kategorien.get_Keys()) { $z["Wert $k"] = '' }
        $z['Hinweis'] = ''; $z['Rechenzeit ms'] = ''; $z['Pfad'] = $f.FullName
        if ($f.Name -notmatch $Lesbar) {
            $z['Hinweis'] = 'Format im Prototyp nicht lesbar (nur WAV und AIFF)'
        } else {
            try {
                $a = [SamplesWerkzeuge.Yamnet.Audio]::Lese($f.FullName, $maxSek)
                $pg = [SamplesWerkzeuge.Yamnet.Vorverarbeitung]::Pegel($a.Mono)
                $y = [SamplesWerkzeuge.Yamnet.Vorverarbeitung]::Resample($a.Mono, $a.Rate)
                $n = 0
                $erg = $modell.BewerteSignal($y, [ref]$n)
                $mittel = $erg[0]; $spitze = $erg[1]
                $z['Dauer s'] = $a.Dauer.ToString('0.00', $de); $z['Abtastrate'] = $a.Rate; $z['Kanaele'] = $a.Kanaele; $z['Bit'] = $a.Bits
                $z['Pegel RMS dBFS'] = $pg[0].ToString('0.0', $de); $z['Spitze dBFS'] = $pg[1].ToString('0.0', $de)
                $z['Analysiert s'] = ([Math]::Min($a.Dauer, $maxSek)).ToString('0.00', $de); $z['Ausschnitte'] = $n
                $top = @(0..($kl.Count - 1) | Sort-Object { - $mittel[$_] } | Select-Object -First 5)
                for ($t = 0; $t -lt 5; $t++) { $z["Top $($t + 1)"] = '{0} ({1})' -f $kl[$top[$t]], (Format-Wert $mittel[$top[$t]]) }
                $topS = @(0..($kl.Count - 1) | Sort-Object { - $spitze[$_] } | Select-Object -First 3)
                for ($t = 0; $t -lt 3; $t++) { $z["Spitze $($t + 1)"] = '{0} ({1})' -f $kl[$topS[$t]], (Format-Wert $spitze[$topS[$t]]) }
                $stil = $Stile | Sort-Object { - $mittel[$_] } | Select-Object -First 1
                $z['Musikstil'] = '{0} ({1})' -f $kl[$stil], (Format-Wert $mittel[$stil]); $z['Musik'] = Format-Wert $mittel[132]; $z['Stille'] = Format-Wert $mittel[494]
                $werte = @{}
                foreach ($k in $Kategorien.get_Keys()) {
                    $m = 0.0; foreach ($idx in $Kategorien[$k].K) { if ($idx -lt $mittel.Length -and $mittel[$idx] -gt $m) { $m = $mittel[$idx] } }
                    $werte[$k] = $m; $z["Wert $k"] = Format-Wert $m
                }
                $rang = @($werte.get_Keys() | Sort-Object { - $werte[$_] })
                $best = $rang[0]; $w = $werte[$best]
                $z['Sicherheit'] = & $Sicherheit $w; $z['Wert'] = Format-Wert $w
                if ($z['Sicherheit'] -ne 'unklar') { $z['Vorschlag Kategorie'] = $best; $z['Vorschlag Zielordner'] = $Kategorien[$best].Ziel }
                $z['Zweite Kategorie'] = $rang[1]; $z['Wert 2'] = Format-Wert $werte[$rang[1]]
                $z['Typ (nach Dauer)'] = if ($a.Dauer -ge 6) { 'Loop' } else { 'One-Shot' }
                $hw = @()
                if ($a.Dauer -gt $maxSek) { $hw += "nur die ersten $maxSek s angehoert" }
                if ($pg[1] -lt -50) { $hw += 'sehr leise oder stumm' }
                if ($mittel[494] -ge 0.5) { $hw += 'ueberwiegend Stille' }
                $z['Hinweis'] = $hw -join '; '
                $klZeilen.Add(('"{0}";"{1}";' -f $f.Name.Replace('"', '""'), $rel.Replace('"', '""')) + (($mittel | ForEach-Object { ([double]$_).ToString('0.0000', $de) }) -join ';'))
            } catch {
                $ex = $_.Exception; while ($ex.InnerException) { $ex = $ex.InnerException }
                $z['Hinweis'] = 'FEHLER: ' + $ex.Message
            }
        }
        $z['Rechenzeit ms'] = $uhr.ElapsedMilliseconds
        $zeilen.Add([pscustomobject]$z)
    }
    $zeilen | Export-Csv -LiteralPath $csvPfad -NoTypeInformation -Delimiter ';' -Encoding UTF8
    [IO.File]::WriteAllLines($klPfad, $klZeilen, (New-Object System.Text.UTF8Encoding($true)))
    return [pscustomobject]@{ Bericht = $csvPfad; Klassen = $klPfad; Dateien = $dateien.Count; Zeilen = $zeilen }
}

function Get-Zusammenfassung($erg) {
    $g = @($erg.Zeilen | Group-Object 'Vorschlag Kategorie' | Sort-Object Count -Descending | ForEach-Object { '{0}: {1}' -f $(if ($_.Name) { $_.Name } else { 'unklar/nicht lesbar' }), $_.Count })
    return "$($erg.Dateien) Dateien analysiert.`n" + ($g -join "`n")
}

# ---------------------------------------------------------------------------
# Ohne Fenster
# ---------------------------------------------------------------------------
if ($Quelle) {
    Write-Host "YAMNet-Prototyp $Version - analysiere $Quelle" -ForegroundColor Cyan
    $e = Invoke-Analyse $Quelle $MaxSekunden (-not $OhneUnterordner) { param($i, $n, $name) Write-Host ("  {0}/{1}  {2}" -f $i, $n, $name) }
    Write-Host ""
    Write-Host (Get-Zusammenfassung $e)
    Write-Host ""
    Write-Host "Bericht: $($e.Bericht)" -ForegroundColor Green
    Write-Host "Alle 521 Klassen: $($e.Klassen)"
    return
}

# ---------------------------------------------------------------------------
# Fenster
# ---------------------------------------------------------------------------
Add-Type -AssemblyName System.Windows.Forms, System.Drawing
[System.Windows.Forms.Application]::EnableVisualStyles()
$schrift = New-Object System.Drawing.Font('Segoe UI', 10)
$fenster = New-Object System.Windows.Forms.Form
$fenster.Text = "YAMNet-Prototyp $Version - Samples einordnen"
$fenster.StartPosition = 'CenterScreen'; $fenster.FormBorderStyle = 'FixedDialog'; $fenster.MaximizeBox = $false
$fenster.Font = $schrift; $fenster.BackColor = [System.Drawing.Color]::White
$w = 640
$l1 = New-Object System.Windows.Forms.Label
$l1.Text = 'Hört sich die Samples eines Ordners an (z. B. „_Unsortiert“) und schlägt eine grobe Einordnung vor. Es wird nichts verschoben oder verändert; das Ergebnis ist ein CSV-Bericht.'
$l1.AutoSize = $true; $l1.MaximumSize = New-Object System.Drawing.Size(($w - 32), 0); $l1.Location = New-Object System.Drawing.Point(16, 14)
$fenster.Controls.Add($l1)
$y = 14 + $l1.PreferredHeight + 14
$lq = New-Object System.Windows.Forms.Label; $lq.Text = 'Ordner:'; $lq.AutoSize = $true; $lq.Location = New-Object System.Drawing.Point(16, ($y + 4)); $fenster.Controls.Add($lq)
$tb = New-Object System.Windows.Forms.TextBox; $tb.Location = New-Object System.Drawing.Point(80, $y); $tb.Size = New-Object System.Drawing.Size(($w - 80 - 126), 26)
try { if (Test-Path -LiteralPath $merkDatei) { $tb.Text = (Get-Content -LiteralPath $merkDatei -Raw).Trim() } } catch { }
$fenster.Controls.Add($tb)
$bw = New-Object System.Windows.Forms.Button; $bw.Text = 'Wählen ...'; $bw.FlatStyle = 'System'; $bw.Location = New-Object System.Drawing.Point(($w - 16 - 100), ($y - 2)); $bw.Size = New-Object System.Drawing.Size(100, 30)
$bw.Add_Click({ $d = New-Object System.Windows.Forms.FolderBrowserDialog; $d.Description = 'Ordner mit Samples (z. B. _Unsortiert im Ziel)'; if ($tb.Text -and (Test-Path -LiteralPath $tb.Text)) { $d.SelectedPath = $tb.Text }; if ($d.ShowDialog($fenster) -eq 'OK') { $tb.Text = $d.SelectedPath } })
$fenster.Controls.Add($bw)
$y += 40
$cb = New-Object System.Windows.Forms.CheckBox; $cb.Text = 'Unterordner einbeziehen'; $cb.Checked = $true; $cb.AutoSize = $true; $cb.Location = New-Object System.Drawing.Point(80, $y); $fenster.Controls.Add($cb)
$ls = New-Object System.Windows.Forms.Label; $ls.Text = 'je Datei höchstens (Sekunden):'; $ls.AutoSize = $true; $ls.Location = New-Object System.Drawing.Point(300, ($y + 2)); $fenster.Controls.Add($ls)
$nu = New-Object System.Windows.Forms.NumericUpDown; $nu.Minimum = 1; $nu.Maximum = 120; $nu.Value = [decimal]$MaxSekunden; $nu.Location = New-Object System.Drawing.Point(510, $y); $nu.Width = 60; $fenster.Controls.Add($nu)
$y += 40
$pb = New-Object System.Windows.Forms.ProgressBar; $pb.Location = New-Object System.Drawing.Point(16, $y); $pb.Size = New-Object System.Drawing.Size(($w - 32), 22); $fenster.Controls.Add($pb)
$y += 30
$lst = New-Object System.Windows.Forms.Label; $lst.Text = 'Bereit.'; $lst.AutoSize = $true; $lst.MaximumSize = New-Object System.Drawing.Size(($w - 32), 0); $lst.Location = New-Object System.Drawing.Point(16, $y); $fenster.Controls.Add($lst)
$y += 70
$bs = New-Object System.Windows.Forms.Button; $bs.Text = 'Analyse starten'; $bs.FlatStyle = 'System'; $bs.Location = New-Object System.Drawing.Point(16, $y); $bs.Size = New-Object System.Drawing.Size(150, 32); $fenster.Controls.Add($bs)
$bo = New-Object System.Windows.Forms.Button; $bo.Text = 'Bericht öffnen'; $bo.FlatStyle = 'System'; $bo.Enabled = $false; $bo.Location = New-Object System.Drawing.Point(176, $y); $bo.Size = New-Object System.Drawing.Size(140, 32); $fenster.Controls.Add($bo)
$bf = New-Object System.Windows.Forms.Button; $bf.Text = 'Berichte-Ordner'; $bf.FlatStyle = 'System'; $bf.Location = New-Object System.Drawing.Point(326, $y); $bf.Size = New-Object System.Drawing.Size(140, 32); $fenster.Controls.Add($bf)
$bx = New-Object System.Windows.Forms.Button; $bx.Text = 'Schließen'; $bx.FlatStyle = 'System'; $bx.DialogResult = 'Cancel'; $bx.Location = New-Object System.Drawing.Point(($w - 16 - 110), $y); $bx.Size = New-Object System.Drawing.Size(110, 32); $fenster.Controls.Add($bx)
$fenster.CancelButton = $bx
$fenster.ClientSize = New-Object System.Drawing.Size($w, ($y + 48))
$script:letzter = $null
$bf.Add_Click({ if (-not (Test-Path -LiteralPath $berichtOrdner)) { New-Item -ItemType Directory -Path $berichtOrdner -Force | Out-Null }; Start-Process explorer.exe "`"$berichtOrdner`"" })
$bo.Add_Click({ if ($script:letzter) { Invoke-Item -LiteralPath $script:letzter } })
$bs.Add_Click({
    $q = $tb.Text.Trim()
    if (-not $q -or -not (Test-Path -LiteralPath $q -PathType Container)) { [void][System.Windows.Forms.MessageBox]::Show($fenster, 'Bitte einen vorhandenen Ordner wählen.', 'YAMNet-Prototyp', 'OK', 'Warning'); return }
    try { Set-Content -LiteralPath $merkDatei -Value $q -Encoding UTF8 } catch { }
    $bs.Enabled = $false; $bo.Enabled = $false; $fenster.Cursor = 'WaitCursor'
    try {
        $e = Invoke-Analyse $q ([double]$nu.Value) $cb.Checked {
            param($i, $n, $name)
            $pb.Maximum = $n; $pb.Value = [Math]::Min($i, $n)
            $lst.Text = "$i von $n`n$name"
            [System.Windows.Forms.Application]::DoEvents()
        }
        $script:letzter = $e.Bericht; $bo.Enabled = $true
        $lst.Text = (Get-Zusammenfassung $e) -replace "`n", ' · '
        $lst.Text = "Fertig: " + $lst.Text + "`nBericht: $($e.Bericht)"
    } catch {
        $lst.Text = 'Fehler: ' + $_.Exception.Message
        [void][System.Windows.Forms.MessageBox]::Show($fenster, $_.Exception.Message, 'YAMNet-Prototyp', 'OK', 'Error')
    } finally { $bs.Enabled = $true; $fenster.Cursor = 'Default' }
})
[void]$fenster.ShowDialog()
