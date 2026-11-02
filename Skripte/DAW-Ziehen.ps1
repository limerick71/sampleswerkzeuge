# (c) 2026 Herbert Stoecker. Kostenlos nutzbar. Bitte nur als Link auf die offizielle Download-Seite weitergeben; Verkauf und Veroeffentlichung geaenderter Fassungen nur mit Zustimmung.
<#
.SYNOPSIS
  "In DAW ziehen" (REP-17, Version 4.1): kleines Fenster, das immer oben bleibt. Das Sample darin laesst sich
  mit der Maus in die DAW (oder jedes andere Programm, das Dateien annimmt) ziehen.
  - Gestartet vom Bericht-Dienst, wenn im Bericht bei einem Sample "In DAW ziehen" geklickt wird.
  - Die gewuenschte Datei steht in Ziehen.txt im Datenordner. Laeuft das Fenster schon, uebernimmt es
    das naechste Sample von dort (es gibt immer nur ein Fenster).
  - Nur Dateien im Ziel (prueft der Bericht-Dienst, hier noch einmal).
  - Schliesst sich nach 60 Minuten ohne Benutzung von selbst.
#>
[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'Gemeinsam.ps1')
Add-Type -AssemblyName PresentationFramework, PresentationCore, WindowsBase

# Nur ein Fenster
$neu = $false
$mutex = New-Object System.Threading.Mutex($true, 'SamplesWerkzeuge-DAW-Ziehen', [ref]$neu)
if (-not $neu) { exit 0 }

$wunschDatei = Join-Path $datenOrdner 'Ziehen.txt'
$zielVoll = [IO.Path]::GetFullPath((Get-Einstellungen).Ziel).TrimEnd('\', '/')

$xaml = @'
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        Title="In DAW ziehen – Samples-Werkzeuge" Width="400" SizeToContent="Height" ResizeMode="NoResize"
        WindowStyle="ToolWindow" Topmost="True" ShowInTaskbar="True" Background="White"
        FontFamily="Segoe UI" FontSize="13">
  <StackPanel Margin="14,12,14,12">
    <Border x:Name="Feld" BorderBrush="#2F5597" BorderThickness="1.5" CornerRadius="8" Background="#E6EDF8" Padding="12,10" Cursor="Hand"
            ToolTip="Mit gedrückter linker Maustaste in die Spur der DAW ziehen.">
      <DockPanel>
        <TextBlock DockPanel.Dock="Left" Text="&#x2630;" FontSize="22" Foreground="#2F5597" VerticalAlignment="Center" Margin="0,0,12,0"/>
        <StackPanel>
          <TextBlock x:Name="Name" FontWeight="SemiBold" FontSize="14" Foreground="#1F3F74" TextTrimming="CharacterEllipsis"/>
          <TextBlock x:Name="Ort" Foreground="#5B6B82" FontSize="11.5" TextTrimming="CharacterEllipsis" Margin="0,2,0,0"/>
        </StackPanel>
      </DockPanel>
    </Border>
    <DockPanel Margin="0,10,0,0">
      <Button x:Name="BtnSpiel" DockPanel.Dock="Left" Content="&#x25B6;  Anhören" Padding="10,3" Margin="0,0,8,0" Background="White" BorderBrush="#C9D3E3"/>
      <Button x:Name="BtnZu" DockPanel.Dock="Right" Content="Schließen" Padding="10,3" Background="White" BorderBrush="#C9D3E3"/>
      <TextBlock x:Name="Hinweis" Foreground="#5B6B82" FontSize="11.5" TextWrapping="Wrap" VerticalAlignment="Center" Margin="0,0,8,0"
                 Text="Bleibt oben. Ein anderes Sample im Bericht ersetzt dieses."/>
    </DockPanel>
  </StackPanel>
</Window>
'@
$win = [Windows.Markup.XamlReader]::Parse($xaml)
$feld = $win.FindName('Feld'); $tName = $win.FindName('Name'); $tOrt = $win.FindName('Ort')
$bSpiel = $win.FindName('BtnSpiel'); $bZu = $win.FindName('BtnZu'); $tHinweis = $win.FindName('Hinweis')

$script:datei = ''
$script:stand = [datetime]::MinValue
$script:benutzt = Get-Date
$player = New-Object System.Windows.Media.MediaPlayer
$script:spielt = $false

function Set-Spielknopf([bool]$an) { $script:spielt = $an; $bSpiel.Content = $(if ($an) { "$([char]0x25A0)  Stopp" } else { "$([char]0x25B6)  Anhören" }) }

function Read-Wunsch {
    if (-not (Test-Path -LiteralPath $wunschDatei)) { return }
    $t = (Get-Item -LiteralPath $wunschDatei).LastWriteTimeUtc
    if ($t -le $script:stand) { return }
    $script:stand = $t
    $p = ''
    try { $p = ([IO.File]::ReadAllText($wunschDatei, [Text.Encoding]::UTF8)).Trim() } catch { return }
    if (-not $p) { return }
    try { $voll = [IO.Path]::GetFullPath($p) } catch { return }
    if (-not $voll.StartsWith($zielVoll + [IO.Path]::DirectorySeparatorChar, [StringComparison]::OrdinalIgnoreCase)) { return }   # nur Dateien im Ziel
    if (-not (Test-Datei $voll)) { $tHinweis.Text = 'Datei nicht gefunden – bitte die Bibliothek neu einlesen.'; return }
    $player.Stop(); Set-Spielknopf $false
    $script:datei = $voll
    $script:benutzt = Get-Date
    $tName.Text = [IO.Path]::GetFileName($voll)
    $tOrt.Text = $voll.Substring($zielVoll.Length + 1)
    $feld.ToolTip = "$voll`n`nMit gedrückter linker Maustaste in die Spur der DAW ziehen."
    $ext = [IO.Path]::GetExtension($voll).ToLowerInvariant()
    $bSpiel.IsEnabled = ($ext -in '.wav', '.mp3', '.m4a', '.wma')
    $tHinweis.Text = 'Bleibt oben. Ein anderes Sample im Bericht ersetzt dieses.'
    if ($win.WindowState -eq 'Minimized') { $win.WindowState = 'Normal' }
    [void]$win.Activate()
}

# Ziehen: ab einer kleinen Mausbewegung mit gedrueckter Taste
$script:start = $null
$feld.Add_PreviewMouseLeftButtonDown({ param($s, $ev) $script:start = $ev.GetPosition($feld) })
$feld.Add_PreviewMouseLeftButtonUp({ $script:start = $null })
$feld.Add_PreviewMouseMove({ param($s, $ev)
    try {
        if ($null -eq $script:start -or $ev.LeftButton -ne 'Pressed' -or -not $script:datei) { return }
        $p = $ev.GetPosition($feld)
        if ([Math]::Abs($p.X - $script:start.X) -lt 4 -and [Math]::Abs($p.Y - $script:start.Y) -lt 4) { return }
        $script:start = $null
        if (-not (Test-Datei $script:datei)) { $tHinweis.Text = 'Datei nicht gefunden – bitte die Bibliothek neu einlesen.'; return }
        $script:benutzt = Get-Date
        $daten = New-Object System.Windows.DataObject
        $daten.SetData([System.Windows.DataFormats]::FileDrop, [string[]]@($script:datei))
        [void][System.Windows.DragDrop]::DoDragDrop($feld, $daten, [System.Windows.DragDropEffects]::Copy)
    } catch { Write-FehlerLog "DAW-Ziehen: $($_.Exception.Message)" }
})

$bSpiel.Add_Click({
    try {
        $script:benutzt = Get-Date
        if ($script:spielt) { $player.Stop(); Set-Spielknopf $false; return }
        if (-not $script:datei) { return }
        $player.Open([Uri]$script:datei); $player.Play(); Set-Spielknopf $true
    } catch { Set-Spielknopf $false; $tHinweis.Text = 'Abspielen nicht möglich.' }
})
$player.Add_MediaEnded({ Set-Spielknopf $false })
$player.Add_MediaFailed({ Set-Spielknopf $false; $tHinweis.Text = 'Abspielen nicht möglich (Format).' })
$bZu.Add_Click({ $win.Close() })

# Rechts unten auf dem Bildschirm
$win.Add_Loaded({
    try {
        $wa = [System.Windows.SystemParameters]::WorkArea
        $win.Left = $wa.Right - $win.ActualWidth - 24
        $win.Top = $wa.Bottom - $win.ActualHeight - 24
    } catch { }
})

$zeit = New-Object System.Windows.Threading.DispatcherTimer
$zeit.Interval = [TimeSpan]::FromMilliseconds(300)
$zeit.Add_Tick({
    try {
        Read-Wunsch
        if (((Get-Date) - $script:benutzt).TotalMinutes -gt 60) { $win.Close() }
    } catch { }
})
Read-Wunsch
$zeit.Start()
try { [void]$win.ShowDialog() } finally {
    $zeit.Stop(); try { $player.Close() } catch { }
    try { $mutex.ReleaseMutex() } catch { }; $mutex.Dispose()
}
