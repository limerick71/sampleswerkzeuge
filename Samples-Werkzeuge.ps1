# Samples-Werkzeuge - kleine Oberflaeche zum Starten der Sortier- und Duplikat-Skripte.
# Jede Schaltflaeche oeffnet ein eigenes PowerShell-Fenster, das offen bleibt, bis du es schliesst.

$SkriptOrdner = Split-Path -Parent $MyInvocation.MyCommand.Path
$LogDatei = Join-Path $SkriptOrdner 'Samples-Werkzeuge-Fehler.log'
function Write-Log([string]$t) { try { Add-Content -LiteralPath $LogDatei -Value ("{0:yyyy-MM-dd HH:mm:ss}  {1}" -f (Get-Date), $t) -Encoding UTF8 } catch {} }

try {
Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing
[System.Windows.Forms.Application]::EnableVisualStyles()

$ZielOrdner   = 'E:\Samples'
$QuellOrdner  = Split-Path -Parent $SkriptOrdner

function Start-Skript([string]$Datei, [bool]$Ausfuehren, [string]$Titel) {
    $pfad = Join-Path $SkriptOrdner $Datei
    if (-not (Test-Path -LiteralPath $pfad)) {
        [System.Windows.Forms.MessageBox]::Show("Skript nicht gefunden:`n$pfad", 'Fehler', 'OK', 'Error') | Out-Null
        return
    }
    $befehl = "`$Host.UI.RawUI.WindowTitle = '$Titel'; & '$($pfad -replace "'", "''")'"
    if ($Ausfuehren) { $befehl += ' -Ausfuehren' }
    Start-Process -FilePath 'powershell.exe' -WorkingDirectory $SkriptOrdner `
        -ArgumentList @('-NoProfile', '-NoExit', '-ExecutionPolicy', 'Bypass', '-Command', "`"$befehl`"")
}

function Confirm-Aktion([string]$Text) {
    $r = [System.Windows.Forms.MessageBox]::Show($Text, 'Wirklich fortfahren?', 'YesNo', 'Question', 'Button2')
    return ($r -eq [System.Windows.Forms.DialogResult]::Yes)
}

# --- Fenster -----------------------------------------------------------------
$form = New-Object System.Windows.Forms.Form
$form.Text = 'Samples-Werkzeuge'
$form.StartPosition = 'CenterScreen'
$form.FormBorderStyle = 'FixedDialog'
$form.MaximizeBox = $false
$form.ClientSize = New-Object System.Drawing.Size(460, 470)
$form.Font = New-Object System.Drawing.Font('Segoe UI', 10)
$form.BackColor = [System.Drawing.Color]::White
try { $form.Icon = [System.Drawing.Icon]::ExtractAssociatedIcon("$env:SystemRoot\System32\WindowsPowerShell\v1.0\powershell.exe") } catch {}

$titel = New-Object System.Windows.Forms.Label
$titel.Text = 'Samples-Werkzeuge'
$titel.Font = New-Object System.Drawing.Font('Segoe UI Semibold', 14)
$titel.Location = New-Object System.Drawing.Point(20, 15)
$titel.AutoSize = $true
$form.Controls.Add($titel)

$y = 60
function Add-Gruppe([string]$Ueberschrift) {
    $l = New-Object System.Windows.Forms.Label
    $l.Text = $Ueberschrift
    $l.Font = New-Object System.Drawing.Font('Segoe UI Semibold', 10)
    $l.ForeColor = [System.Drawing.Color]::FromArgb(90, 90, 90)
    $l.Location = New-Object System.Drawing.Point(20, $script:y)
    $l.AutoSize = $true
    $form.Controls.Add($l)
    $script:y += 28
}
function Add-Knopf([string]$Text, [string]$Hinweis, [scriptblock]$Aktion, [bool]$Warnfarbe = $false) {
    $b = New-Object System.Windows.Forms.Button
    $b.Text = $Text
    $b.Location = New-Object System.Drawing.Point(20, $script:y)
    $b.Size = New-Object System.Drawing.Size(420, 38)
    $b.FlatStyle = 'System'
    $b.Add_Click($Aktion)
    $form.Controls.Add($b)
    $tip = New-Object System.Windows.Forms.ToolTip
    $tip.SetToolTip($b, $Hinweis)
    if ($Warnfarbe) { $b.Font = New-Object System.Drawing.Font('Segoe UI Semibold', 10) }
    $script:y += 46
}

Add-Gruppe 'Sortieren  (Quelle -> E:\Samples)'
Add-Knopf '1   Vorschau anzeigen' 'Erstellt nur eine CSV-Liste Quelle -> Ziel. Es wird nichts kopiert.' {
    Start-Skript 'Samples-sortieren.ps1' $false 'Samples sortieren - Vorschau'
}
Add-Knopf '2   Kopieren ausführen' 'Kopiert nach E:\Samples. Nichts wird gelöscht oder überschrieben.' {
    if (Confirm-Aktion "Die Samples werden jetzt nach $ZielOrdner kopiert.`nEs wird nichts gelöscht oder überschrieben.`n`nFortfahren?") {
        Start-Skript 'Samples-sortieren.ps1' $true 'Samples sortieren - Kopieren'
    }
} $true

$y += 8
Add-Gruppe 'Duplikate  (im Quellordner)'
Add-Knopf '3   Vorschau anzeigen' 'Zeigt, welche doppelten Samples entfernt würden. Es wird nichts gelöscht.' {
    Start-Skript 'Duplikate-entfernen.ps1' $false 'Duplikate - Vorschau'
}
Add-Knopf '4   Duplikate in den Papierkorb' 'Verschiebt die doppelten Samples in den Windows-Papierkorb.' {
    if (Confirm-Aktion "Die doppelten Samples werden jetzt in den Papierkorb verschoben.`nSie lassen sich von dort wiederherstellen.`n`nFortfahren?") {
        Start-Skript 'Duplikate-entfernen.ps1' $true 'Duplikate entfernen'
    }
} $true

# --- Ordner-Schnellzugriff ---------------------------------------------------
$y += 8
Add-Gruppe 'Ordner öffnen'
$ordnerKnoepfe = @(
    @('E:\Samples',        $ZielOrdner),
    @('Sounds und Samples', $QuellOrdner),
    @('Protokolle',         $SkriptOrdner)
)
$x = 20
foreach ($o in $ordnerKnoepfe) {
    $b = New-Object System.Windows.Forms.Button
    $b.Text = $o[0]
    $b.Tag = $o[1]
    $b.Location = New-Object System.Drawing.Point($x, $y)
    $b.Size = New-Object System.Drawing.Size(136, 32)
    $b.FlatStyle = 'System'
    $b.Add_Click({
        param($sender, $e)
        if (Test-Path -LiteralPath $sender.Tag) { Start-Process explorer.exe -ArgumentList "`"$($sender.Tag)`"" }
        else { [System.Windows.Forms.MessageBox]::Show("Ordner existiert (noch) nicht:`n$($sender.Tag)", 'Hinweis') | Out-Null }
    })
    $form.Controls.Add($b)
    $x += 142
}
$y += 44

$fuss = New-Object System.Windows.Forms.Label
$fuss.Text = 'Jede Aktion öffnet ein eigenes PowerShell-Fenster.'
$fuss.ForeColor = [System.Drawing.Color]::Gray
$fuss.Location = New-Object System.Drawing.Point(20, $y)
$fuss.AutoSize = $true
$form.Controls.Add($fuss)
$form.ClientSize = New-Object System.Drawing.Size(460, ($y + 35))

# Fenster beim Start sicher in den Vordergrund holen
$form.Add_Shown({ $form.TopMost = $true; $form.Activate(); $form.BringToFront(); $form.TopMost = $false })

[void]$form.ShowDialog()
}
catch {
    $msg = $_.Exception.Message + "`n`n" + $_.InvocationInfo.PositionMessage
    Write-Log ("FEHLER: " + ($msg -replace "`n", ' | '))
    try {
        Add-Type -AssemblyName System.Windows.Forms
        [System.Windows.Forms.MessageBox]::Show("Samples-Werkzeuge konnte nicht gestartet werden:`n`n$msg`n`nDetails stehen in:`n$LogDatei", 'Samples-Werkzeuge - Fehler', 'OK', 'Error') | Out-Null
    } catch {}
}
