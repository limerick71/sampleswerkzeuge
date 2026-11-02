#Requires -Version 5.1
# (c) 2026 Herbert Stoecker. Kostenlos nutzbar. Bitte nur als Link auf die offizielle Download-Seite weitergeben; Verkauf und Veroeffentlichung geaenderter Fassungen nur mit Zustimmung.
<#
.SYNOPSIS
    Samples-Werkzeuge (Version 4): Hauptfenster mit gefuehrtem Ablauf (Quellen, Sortieren, Aufraeumen)
    und der Sample-Bibliothek zum Durchhoeren.

.DESCRIPTION
    Start per Doppelklick auf "GUI_Samples-Werkzeuge.cmd" im Programmordner oder ueber die
    Desktop-Verknuepfung. Das Hauptfenster ist seit 4.0 in WPF gebaut (GUI-07); die Dialoge
    (Einstellungen, Import, Aufraeumen ...) stehen in Dialoge.ps1 (WinForms).
    Die Skripte laufen ohne eigenes Konsolenfenster; Fortschritt, Ausgabe und Rueckfragen
    erscheinen im Hauptfenster (GUI-04).
#>
$ErrorActionPreference = 'Continue'

$psExe = Join-Path $PSHOME 'powershell.exe'
if (-not (Test-Path -LiteralPath $psExe)) { $psExe = 'powershell.exe' }

# WPF braucht einen STA-Thread (Windows PowerShell 5.1 startet normalerweise so)
if ([Threading.Thread]::CurrentThread.ApartmentState -ne 'STA') {
    Start-Process -FilePath $psExe -ArgumentList "-STA -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File `"$PSCommandPath`"" -WindowStyle Hidden
    exit
}

# Eigenes Konsolenfenster ausblenden (falls Windows es trotz -WindowStyle Hidden anzeigt)
try {
    Add-Type -Namespace SW -Name Fenster -MemberDefinition '[DllImport("kernel32.dll")] public static extern IntPtr GetConsoleWindow(); [DllImport("user32.dll")] public static extern bool ShowWindow(IntPtr h, int n);' -ErrorAction Stop
    $kf = [SW.Fenster]::GetConsoleWindow()
    if ($kf -ne [IntPtr]::Zero) { [void][SW.Fenster]::ShowWindow($kf, 0) }
} catch { }

try {
    Add-Type -AssemblyName PresentationFramework, PresentationCore, WindowsBase
    Add-Type -AssemblyName System.Windows.Forms
    Add-Type -AssemblyName System.Drawing
    [System.Windows.Forms.Application]::EnableVisualStyles()
} catch {
    Write-Host "Die Oberfläche kann nicht geladen werden: $($_.Exception.Message)"
    exit 1
}

# Gemeinsame Pfade und Einstellungen (siehe Gemeinsam.ps1), Dialoge (WinForms)
. (Join-Path $PSScriptRoot 'Gemeinsam.ps1')
. (Join-Path $PSScriptRoot 'Fundorte-Bericht.ps1')
. (Join-Path $PSScriptRoot 'Dialoge.ps1')
. (Join-Path $PSScriptRoot 'Import.ps1')      # 4.0.1: ZIP-Inhaltsverzeichnis fuer den Import-Kasten
$basis = $wurzel

# Internet-Markierung (heruntergeladene ZIP-Datei) von allen Dateien entfernen
try { Get-ChildItem -LiteralPath $wurzel -Recurse -File -ErrorAction SilentlyContinue | Unblock-File -ErrorAction SilentlyContinue } catch { }

# Klassische Konsole: dort wirkt -WindowStyle Hidden auch, wenn Windows Terminal Standard ist
$conhost      = Join-Path $env:SystemRoot 'System32\conhost.exe'
$verknuepfung = Join-Path ([Environment]::GetFolderPath('Desktop')) 'Samples-Werkzeuge.lnk'
$symbolQuelle = $psExe
$dokuPfad     = Join-Path $wurzel 'Dokumentation Samples-Werkzeuge.rtf'

# ---------------------------------------------------------------------------
# Skriptlauf im Hintergrund (GUI-04): liest die Ausgabe zeilenweise in eine Warteschlange,
# die das Fenster per Zeitgeber abholt (kein Skriptcode auf fremden Threads).
# ---------------------------------------------------------------------------
if (-not ('SamplesWerkzeuge.SkriptLauf400' -as [type])) {
  try {
    Add-Type -ErrorAction Stop -TypeDefinition @'
using System;
using System.Collections.Concurrent;
using System.Collections.Generic;
using System.Diagnostics;
using System.Text;
namespace SamplesWerkzeuge {
    public class SkriptLauf400 {
        private Process p;
        private ConcurrentQueue<string> q = new ConcurrentQueue<string>();
        public void Start(string exe, string args, string wd) {
            ProcessStartInfo si = new ProcessStartInfo(exe, args);
            si.UseShellExecute = false; si.CreateNoWindow = true; si.WorkingDirectory = wd;
            si.RedirectStandardOutput = true; si.RedirectStandardError = true; si.RedirectStandardInput = true;
            si.StandardOutputEncoding = new UTF8Encoding(false); si.StandardErrorEncoding = new UTF8Encoding(false);
            si.EnvironmentVariables["SW_GUI"] = "1";
            p = new Process(); p.StartInfo = si;
            p.OutputDataReceived += (s, e) => { if (e.Data != null) q.Enqueue(e.Data); };
            p.ErrorDataReceived += (s, e) => { if (e.Data != null) q.Enqueue("##E##" + e.Data); };
            p.Start(); p.BeginOutputReadLine(); p.BeginErrorReadLine();
        }
        public string[] Hole() {
            List<string> l = new List<string>(); string s;
            while (l.Count < 400 && q.TryDequeue(out s)) l.Add(s.TrimStart('﻿'));
            return l.ToArray();
        }
        public bool Leer { get { return q.IsEmpty; } }
        public bool Beendet { get { try { return p == null || p.HasExited; } catch { return true; } } }
        public int Code { get { try { return p.ExitCode; } catch { return -1; } } }
        public void Antwort(string a) { try { p.StandardInput.WriteLine(a); p.StandardInput.Flush(); } catch { } }
        public void Beenden() { try { if (!p.HasExited) p.Kill(); } catch { } }
    }
}
'@
  } catch {
    Write-FehlerLog "Oberfläche (SkriptLauf): $($_.Exception.Message)"
    [void][System.Windows.Forms.MessageBox]::Show("Die Oberfläche kann nicht gestartet werden:`n$($_.Exception.Message)", 'Samples-Werkzeuge', 'OK', 'Error')
    exit 1
  }
}

# Besitzer fuer die WinForms-Dialoge: das Hauptfenster (macht sie modal und zentriert sie darueber)
if (-not ('SamplesWerkzeuge.Besitzer400' -as [type])) {
    try { Add-Type -ReferencedAssemblies ([System.Windows.Forms.Form].Assembly.Location) -TypeDefinition 'namespace SamplesWerkzeuge { public class Besitzer400 : System.Windows.Forms.IWin32Window { public System.IntPtr Handle { get; set; } } }' -ErrorAction Stop }
    catch { Write-FehlerLog "Oberfläche (Besitzer): $($_.Exception.Message)" }
}

# ---------------------------------------------------------------------------
# Oberflaeche (XAML)
# ---------------------------------------------------------------------------
$xaml = @'
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        Title="Samples-Werkzeuge" Width="1000" Height="920" MinWidth="820" MinHeight="560"
        WindowStartupLocation="CenterScreen" Background="#E9EDF2"
        FontFamily="Segoe UI" FontSize="13.5" Foreground="#1D2430"
        UseLayoutRounding="True" TextOptions.TextFormattingMode="Display">
  <Window.Resources>
    <SolidColorBrush x:Key="Akzent" Color="#2C5AA0"/>
    <SolidColorBrush x:Key="Linie" Color="#D6DCE4"/>
    <SolidColorBrush x:Key="Leise" Color="#5E6A7A"/>
    <Style x:Key="Knopf" TargetType="Button">
      <Setter Property="Foreground" Value="#1D2430"/>
      <Setter Property="Background" Value="#F3F5F8"/>
      <Setter Property="BorderBrush" Value="#C9D1DC"/>
      <Setter Property="Padding" Value="14,7"/>
      <Setter Property="Margin" Value="0,0,10,0"/>
      <Setter Property="Cursor" Value="Hand"/>
      <Setter Property="Template">
        <Setter.Value>
          <ControlTemplate TargetType="Button">
            <Border x:Name="R" Background="{TemplateBinding Background}" BorderBrush="{TemplateBinding BorderBrush}" BorderThickness="1" CornerRadius="5" Padding="{TemplateBinding Padding}">
              <ContentPresenter HorizontalAlignment="Center" VerticalAlignment="Center"/>
            </Border>
            <ControlTemplate.Triggers>
              <Trigger Property="IsMouseOver" Value="True"><Setter TargetName="R" Property="BorderBrush" Value="#2C5AA0"/></Trigger>
              <Trigger Property="IsEnabled" Value="False"><Setter TargetName="R" Property="Opacity" Value="0.45"/></Trigger>
            </ControlTemplate.Triggers>
          </ControlTemplate>
        </Setter.Value>
      </Setter>
    </Style>
    <Style x:Key="KnopfHaupt" TargetType="Button" BasedOn="{StaticResource Knopf}">
      <Setter Property="Background" Value="#2C5AA0"/>
      <Setter Property="BorderBrush" Value="#2C5AA0"/>
      <Setter Property="Foreground" Value="White"/>
      <Setter Property="FontWeight" Value="SemiBold"/>
    </Style>
    <Style x:Key="Link" TargetType="Button">
      <Setter Property="Foreground" Value="#2C5AA0"/>
      <Setter Property="Margin" Value="0,0,14,0"/>
      <Setter Property="Cursor" Value="Hand"/>
      <Setter Property="VerticalAlignment" Value="Center"/>
      <Setter Property="Template">
        <Setter.Value>
          <ControlTemplate TargetType="Button">
            <TextBlock x:Name="T" Text="{Binding Content, RelativeSource={RelativeSource TemplatedParent}}" Padding="2,4"/>
            <ControlTemplate.Triggers>
              <Trigger Property="IsMouseOver" Value="True"><Setter TargetName="T" Property="TextDecorations" Value="Underline"/></Trigger>
              <Trigger Property="IsEnabled" Value="False"><Setter TargetName="T" Property="Opacity" Value="0.4"/></Trigger>
            </ControlTemplate.Triggers>
          </ControlTemplate>
        </Setter.Value>
      </Setter>
    </Style>
    <Style x:Key="Titel2" TargetType="TextBlock">
      <Setter Property="FontSize" Value="16"/>
      <Setter Property="FontWeight" Value="SemiBold"/>
      <Setter Property="Margin" Value="0,0,0,3"/>
    </Style>
    <Style x:Key="Lead" TargetType="TextBlock">
      <Setter Property="Foreground" Value="#5E6A7A"/>
      <Setter Property="TextWrapping" Value="Wrap"/>
      <Setter Property="Margin" Value="0,0,0,12"/>
    </Style>
  </Window.Resources>

  <DockPanel>
    <!-- Fusszeile -->
    <Border DockPanel.Dock="Bottom" Background="#F3F5F8" BorderBrush="{StaticResource Linie}" BorderThickness="0,1,0,0" Padding="24,12">
      <DockPanel LastChildFill="False">
        <Button x:Name="BtnEinstellungen" DockPanel.Dock="Left" Style="{StaticResource Knopf}" Content="⚙  Einstellungen" ToolTip="Quellen, Ordner (Ziel, Downloads, Berichte …) und Formate einstellen."/>
        <Button x:Name="BtnDoku" DockPanel.Dock="Left" Style="{StaticResource Knopf}" Content="Dokumentation" ToolTip="Öffnet die Dokumentation (RTF) mit allen Funktionen des Programms."/>
        <Button x:Name="LnkProtokolle" DockPanel.Dock="Left" Style="{StaticResource Link}" Content="Protokolle" ToolTip="Öffnet den Ordner mit allen Vorschauen und Protokollen."/>
        <Button x:Name="LnkProgramm" DockPanel.Dock="Left" Style="{StaticResource Link}" Content="Programmordner"/>
        <Button x:Name="LnkVerknuepfung" DockPanel.Dock="Left" Style="{StaticResource Link}" Content="Desktop-Verknüpfung anlegen" ToolTip="Legt die Verknüpfung „Samples-Werkzeuge“ auf dem Desktop an bzw. lässt sie auf diese Version zeigen."/>
        <Button x:Name="BtnSchliessen" DockPanel.Dock="Right" Style="{StaticResource Knopf}" Content="Schließen" Margin="0" IsCancel="True"/>
        <TextBlock x:Name="TxtUrheber" DockPanel.Dock="Right" Foreground="{StaticResource Leise}" FontSize="12" VerticalAlignment="Center" Margin="0,0,14,0"><Run x:Name="TxtUrheberName"/><Run Text="  ·  "/><Hyperlink x:Name="LnkWebseite" NavigateUri="https://make-some-music.de" Foreground="#2C5AA0">make-some-music.de</Hyperlink></TextBlock>
      </DockPanel>
    </Border>

    <ScrollViewer x:Name="Haupt" VerticalScrollBarVisibility="Auto" Background="White">
      <StackPanel x:Name="Inhalt" Margin="24,16,24,22" VerticalAlignment="Top">
        <!-- Kopf -->
        <DockPanel Margin="0,0,0,10" LastChildFill="True">
          <Image x:Name="Logo" DockPanel.Dock="Right" Height="54" Margin="16,-4,0,0" VerticalAlignment="Center" Cursor="Hand" Visibility="Collapsed" ToolTip="make-some-music.de"/>
          <WrapPanel VerticalAlignment="Center">
            <TextBlock Text="Samples-Werkzeuge" FontSize="24" FontWeight="SemiBold" Foreground="#1F3F74" Margin="0,0,14,0"/>
            <TextBlock x:Name="TxtUnter" Foreground="{StaticResource Leise}" VerticalAlignment="Bottom" Margin="0,0,0,4" TextWrapping="Wrap"/>
          </WrapPanel>
        </DockPanel>

        <!-- Abkuerzung: Download importieren -->
        <Grid Margin="0,4,0,0">
          <Rectangle x:Name="ImportRahmen" RadiusX="8" RadiusY="8" Stroke="#2C5AA0" StrokeThickness="1.2" StrokeDashArray="4 3" Fill="#E6EDF8"/>
          <DockPanel Margin="18,20" MinHeight="40">
            <Button x:Name="BtnImport" DockPanel.Dock="Right" Style="{StaticResource KnopfHaupt}" Content="Download importieren …" Margin="0" VerticalAlignment="Center"
                    ToolTip="Frisch heruntergeladene Sample-Packs (ZIP oder Ordner im Download-Ordner) in einem Schritt entpacken, einsortieren und das Original ins Download-Archiv verschieben, liegen lassen oder in den Papierkorb legen. Mit Vorschau und Rückfrage."/>
            <TextBlock Text="⬇" FontSize="22" VerticalAlignment="Center" Margin="0,0,12,0" Foreground="#2C5AA0"/>
            <StackPanel VerticalAlignment="Center">
              <TextBlock x:Name="TxtImport1" FontWeight="SemiBold" FontSize="17" TextWrapping="Wrap"/>
              <TextBlock Text="Abkürzung durch alle drei Schritte: entpacken, einsortieren, Original ins Download-Archiv." Foreground="{StaticResource Leise}" FontSize="13.5" TextWrapping="Wrap" Margin="0,2,0,0"/>
            </StackPanel>
          </DockPanel>
        </Grid>

        <!-- Der Ablauf -->
        <Border Margin="0,18,0,0" BorderBrush="#2C5AA0" BorderThickness="2" CornerRadius="12" Background="#EEF3FB">
          <StackPanel>
            <Border Background="#2C5AA0" CornerRadius="9,9,0,0" Padding="16,9">
              <TextBlock Foreground="White"><Run Text="▶  Der Ablauf" FontWeight="SemiBold"/><Run Text="   ·  in drei Schritten von den Quellen zur sortierten Bibliothek" Foreground="#DCE6F5"/></TextBlock>
            </Border>
            <Grid Margin="16,16,16,0">
              <Grid.ColumnDefinitions>
                <ColumnDefinition Width="*"/><ColumnDefinition Width="34"/><ColumnDefinition Width="*"/><ColumnDefinition Width="34"/><ColumnDefinition Width="*"/>
              </Grid.ColumnDefinitions>
              <Grid.RowDefinitions><RowDefinition Height="Auto"/><RowDefinition Height="12"/></Grid.RowDefinitions>
              <Border x:Name="Schritt1" Grid.Column="0" CornerRadius="10" BorderThickness="2" Padding="14,12" Cursor="Hand">
                <StackPanel>
                  <StackPanel Orientation="Horizontal">
                    <Border x:Name="Num1" Width="34" Height="34" CornerRadius="17"><TextBlock x:Name="NumT1" Text="1" FontWeight="Bold" FontSize="16" HorizontalAlignment="Center" VerticalAlignment="Center"/></Border>
                    <TextBlock x:Name="Name1" Text="Quellen" FontSize="17" FontWeight="Bold" VerticalAlignment="Center" Margin="10,0,0,0"/>
                  </StackPanel>
                  <TextBlock x:Name="Stand1" Margin="0,8,0,0" FontSize="12.5" TextWrapping="Wrap"/>
                  <Border x:Name="Pille1" HorizontalAlignment="Left" CornerRadius="10" Padding="8,1" Margin="0,6,0,0"><TextBlock x:Name="PilleT1" FontSize="11.5"/></Border>
                </StackPanel>
              </Border>
              <TextBlock Grid.Column="1" Text="➜" FontSize="22" FontWeight="Bold" Foreground="#2C5AA0" HorizontalAlignment="Center" VerticalAlignment="Center" FontFamily="Segoe UI Symbol"/>
              <Border x:Name="Schritt2" Grid.Column="2" CornerRadius="10" BorderThickness="2" Padding="14,12" Cursor="Hand">
                <StackPanel>
                  <StackPanel Orientation="Horizontal">
                    <Border x:Name="Num2" Width="34" Height="34" CornerRadius="17"><TextBlock x:Name="NumT2" Text="2" FontWeight="Bold" FontSize="16" HorizontalAlignment="Center" VerticalAlignment="Center"/></Border>
                    <TextBlock x:Name="Name2" Text="Sortieren" FontSize="17" FontWeight="Bold" VerticalAlignment="Center" Margin="10,0,0,0"/>
                  </StackPanel>
                  <TextBlock x:Name="Stand2" Margin="0,8,0,0" FontSize="12.5" TextWrapping="Wrap"/>
                  <Border x:Name="Pille2" HorizontalAlignment="Left" CornerRadius="10" Padding="8,1" Margin="0,6,0,0"><TextBlock x:Name="PilleT2" FontSize="11.5"/></Border>
                </StackPanel>
              </Border>
              <TextBlock Grid.Column="3" Text="➜" FontSize="22" FontWeight="Bold" Foreground="#2C5AA0" HorizontalAlignment="Center" VerticalAlignment="Center" FontFamily="Segoe UI Symbol"/>
              <Border x:Name="Schritt3" Grid.Column="4" CornerRadius="10" BorderThickness="2" Padding="14,12" Cursor="Hand">
                <StackPanel>
                  <StackPanel Orientation="Horizontal">
                    <Border x:Name="Num3" Width="34" Height="34" CornerRadius="17"><TextBlock x:Name="NumT3" Text="3" FontWeight="Bold" FontSize="16" HorizontalAlignment="Center" VerticalAlignment="Center"/></Border>
                    <TextBlock x:Name="Name3" Text="Aufräumen" FontSize="17" FontWeight="Bold" VerticalAlignment="Center" Margin="10,0,0,0"/>
                  </StackPanel>
                  <TextBlock x:Name="Stand3" Margin="0,8,0,0" FontSize="12.5" TextWrapping="Wrap"/>
                  <Border x:Name="Pille3" HorizontalAlignment="Left" CornerRadius="10" Padding="8,1" Margin="0,6,0,0"><TextBlock x:Name="PilleT3" FontSize="11.5"/></Border>
                </StackPanel>
              </Border>
              <Polygon x:Name="Spitze" Grid.Row="1" Grid.Column="2" Points="0,0 18,0 9,10" Fill="#2C5AA0" HorizontalAlignment="Center" VerticalAlignment="Top"/>
            </Grid>

            <!-- Inhalt des gewaehlten Schritts -->
            <Border Margin="16,2,16,0" BorderBrush="#2C5AA0" BorderThickness="2" CornerRadius="10" Background="White" Padding="18,16">
              <Grid>
                <StackPanel x:Name="Feld1">
                  <TextBlock Style="{StaticResource Titel2}" Text="1 · Woher kommen die Samples?"/>
                  <TextBlock Style="{StaticResource Lead}" Text="Alle Ordner, aus denen sortiert wird. Neue Orte findet der Suchlauf „Fundorte suchen“; übernommen werden sie im Bericht oder in den Einstellungen."/>
                  <Border BorderBrush="{StaticResource Linie}" BorderThickness="1" CornerRadius="6" Margin="0,0,0,12"><StackPanel x:Name="QuellListe"/></Border>
                  <WrapPanel>
                    <Button x:Name="BtnFundorte" Style="{StaticResource KnopfHaupt}" Content="Fundorte suchen …" ToolTip="Sucht auf Laufwerken und in Ordnern nach Sample-Packs und zeigt die Fundorte im Browser; dort lassen sie sich als Quellen übernehmen. Es wird nichts verändert."/>
                    <Button x:Name="BtnQuellen" Style="{StaticResource Knopf}" Content="Quellen bearbeiten …" ToolTip="Quellen hinzufügen, entfernen, an- und abhaken, Art ändern (in den Einstellungen)."/>
                  </WrapPanel>
                </StackPanel>
                <StackPanel x:Name="Feld2" Visibility="Collapsed">
                  <TextBlock Style="{StaticResource Titel2}" Text="2 · Einsortieren nach Instrument"/>
                  <TextBlock Style="{StaticResource Lead}" Text="Kopiert neue Samples aus den aktiven Quellen ins Ziel. Die Quellen bleiben unverändert. Erst Vorschau, dann die Rückfrage hier im Fenster."/>
                  <WrapPanel x:Name="Fakten2" Margin="0,0,0,14"/>
                  <WrapPanel>
                    <Button x:Name="BtnSortieren" Style="{StaticResource KnopfHaupt}" Content="Vorschau und sortieren …" ToolTip="Zeigt zuerst eine Vorschau (auch als CSV für Excel) und fragt dann, ob kopiert werden soll. Es wird nur kopiert, nichts überschrieben; vorhandener Inhalt wird übersprungen."/>
                    <Button x:Name="BtnZielOeffnen" Style="{StaticResource Knopf}" Content="Ziel öffnen" ToolTip="Öffnet die sortierte Sample-Bibliothek im Explorer."/>
                    <Button x:Name="LnkSortProt" Style="{StaticResource Link}" Content="Letztes Sortier-Protokoll"/>
                    <Button x:Name="LnkImportProt" Style="{StaticResource Link}" Content="Letztes Import-Protokoll"/>
                  </WrapPanel>
                </StackPanel>
                <StackPanel x:Name="Feld3" Visibility="Collapsed">
                  <TextBlock Style="{StaticResource Titel2}" Text="3 · Aufräumen"/>
                  <TextBlock Style="{StaticResource Lead}" Text="Entfernt nur, was im Ziel per Prüfsumme bestätigt ist, und nur nach Vorschau und Rückfrage. Alles geht in den Windows-Papierkorb."/>
                  <WrapPanel x:Name="Fakten3" Margin="0,0,0,14"/>
                  <WrapPanel>
                    <Button x:Name="BtnQuelleAuf" Style="{StaticResource KnopfHaupt}" Content="Quellen aufräumen …" ToolTip="Entfernt Entbehrliches aus den Quellen: Duplikate, macOS-Reste, RX2/MP3/AIFF neben einer WAV oder Originale, deren Kopie im Ziel bestätigt ist."/>
                    <Button x:Name="BtnZielDup" Style="{StaticResource Knopf}" Content="Duplikate im Ziel …" ToolTip="Duplikate der Bibliothek (je Gruppe bleibt ein Exemplar, Kits bleiben vollständig) und auf Wunsch RX2/MP3/AIFF neben einer gleichnamigen WAV in den Papierkorb. Grundlage: der letzte Stand der Sample-Bibliothek."/>
                    <Button x:Name="LnkPapierkorb" Style="{StaticResource Link}" Content="Papierkorb öffnen"/>
                  </WrapPanel>
                </StackPanel>
              </Grid>
            </Border>

            <!-- Vorgangsmonitor (GUI-04): Fortschritt, Rueckfrage, Ausgabe. Geschlossen bleibt eine Zeile zum Einblenden. -->
            <Border x:Name="MonitorZeile" Visibility="Collapsed" Margin="16,12,16,0" BorderBrush="{StaticResource Linie}" BorderThickness="1" CornerRadius="8" Background="#F3F5F8" Padding="12,7">
              <DockPanel>
                <Button x:Name="LnkEinblenden" DockPanel.Dock="Right" Style="{StaticResource Link}" Content="Einblenden" Margin="10,0,0,0"/>
                <Button x:Name="LnkZeileDatei" DockPanel.Dock="Right" Style="{StaticResource Link}" Content="Protokoll öffnen" Margin="10,0,0,0" Visibility="Collapsed"/>
                <TextBlock x:Name="MonitorZeileText" Foreground="{StaticResource Leise}" VerticalAlignment="Center" TextTrimming="CharacterEllipsis"/>
              </DockPanel>
            </Border>
            <Border x:Name="Lauf" Visibility="Collapsed" Margin="16,12,16,0" BorderBrush="{StaticResource Linie}" BorderThickness="1" CornerRadius="8" Background="White">
              <StackPanel>
                <Border Background="#F3F5F8" CornerRadius="8,8,0,0" Padding="12,7">
                  <DockPanel>
                    <Button x:Name="LnkLaufZu" DockPanel.Dock="Right" Style="{StaticResource Link}" Content="Ausblenden" Margin="10,0,0,0" ToolTip="Klappt den Vorgangsmonitor zu einer Zeile zusammen; dort holt „Einblenden“ ihn zurück."/>
                    <TextBlock VerticalAlignment="Center" Margin="0,0,12,0"><Run Text="Vorgangsmonitor  ·  " Foreground="#5E6A7A"/><Run x:Name="LaufTitel" FontWeight="SemiBold"/></TextBlock>
                    <ProgressBar x:Name="LaufBalken" Width="220" Height="8" VerticalAlignment="Center" Foreground="#2C5AA0" Background="#D6DCE4" BorderThickness="0" Margin="0,0,10,0"/>
                    <TextBlock x:Name="LaufStatus" Foreground="{StaticResource Leise}" FontSize="12.5" VerticalAlignment="Center" TextTrimming="CharacterEllipsis"/>
                  </DockPanel>
                </Border>
                <Border x:Name="FrageLeiste" Visibility="Collapsed" Background="#FDF1DC" Padding="12,10" BorderBrush="#E8C98F" BorderThickness="0,1">
                  <DockPanel>
                    <StackPanel DockPanel.Dock="Right" Orientation="Horizontal" VerticalAlignment="Center">
                      <Button x:Name="LnkFrageDatei" Style="{StaticResource Link}" Content="Vorschau öffnen" Visibility="Collapsed"/>
                      <Button x:Name="BtnJa" Style="{StaticResource KnopfHaupt}" Content="Ja, ausführen"/>
                      <Button x:Name="BtnNein" Style="{StaticResource Knopf}" Content="Nein" Margin="0"/>
                    </StackPanel>
                    <TextBlock x:Name="FrageText" FontWeight="SemiBold" Foreground="#7A4A00" TextWrapping="Wrap" VerticalAlignment="Center" Margin="0,0,12,0"/>
                  </DockPanel>
                </Border>
                <Border x:Name="EndeLeiste" Visibility="Collapsed" Padding="12,8" BorderBrush="{StaticResource Linie}" BorderThickness="0,1,0,0">
                  <DockPanel>
                    <StackPanel DockPanel.Dock="Right" Orientation="Horizontal">
                      <Button x:Name="LnkEndeDatei" Style="{StaticResource Link}" Content="Protokoll öffnen" Visibility="Collapsed"/>
                    </StackPanel>
                    <TextBlock x:Name="EndeText" FontWeight="SemiBold" VerticalAlignment="Center"/>
                  </DockPanel>
                </Border>
                <!-- 4.1.1 (Befund 7): Frage nach dem Neu-Einlesen, wenn sich im Ziel etwas geaendert hat -->
                <Border x:Name="BibFrage" Visibility="Collapsed" Background="#FDF1DC" Padding="12,10" BorderBrush="#E8C98F" BorderThickness="0,1">
                  <DockPanel>
                    <StackPanel DockPanel.Dock="Right" Orientation="Horizontal" VerticalAlignment="Center">
                      <CheckBox x:Name="ChkBibAuto1" Content="Einlesen künftig automatisch" VerticalAlignment="Center" Margin="0,0,14,0" Foreground="#7A4A00"
                                ToolTip="Nach Sortieren, Import und Duplikate-Entfernen die Bibliothek gleich im Anschluss neu einlesen, ohne zu fragen."/>
                      <Button x:Name="BtnBibJa" Style="{StaticResource KnopfHaupt}" Content="Ja, einlesen"/>
                      <Button x:Name="BtnBibNein" Style="{StaticResource Knopf}" Content="Nein" Margin="0"/>
                    </StackPanel>
                    <TextBlock FontWeight="SemiBold" Foreground="#7A4A00" TextWrapping="Wrap" VerticalAlignment="Center" Margin="0,0,12,0"
                               Text="Im Ziel hat sich etwas geändert. Sample-Bibliothek jetzt neu einlesen?"/>
                  </DockPanel>
                </Border>
                <ListBox x:Name="LaufLog" Height="210" BorderThickness="0" FontFamily="Consolas" FontSize="12" Padding="6,4"
                         ScrollViewer.HorizontalScrollBarVisibility="Auto" VirtualizingStackPanel.IsVirtualizing="True"/>
              </StackPanel>
            </Border>
            <Border Height="16"/>
          </StackPanel>
        </Border>

        <!-- Danach: Sample-Bibliothek -->
        <Grid Margin="0,22,0,8">
          <Grid.ColumnDefinitions><ColumnDefinition Width="*"/><ColumnDefinition Width="Auto"/><ColumnDefinition Width="*"/></Grid.ColumnDefinitions>
          <Rectangle Height="1" Fill="{StaticResource Linie}" VerticalAlignment="Center"/>
          <TextBlock Grid.Column="1" Text="DANACH: DURCHHÖREN UND STÖBERN" Foreground="{StaticResource Leise}" FontSize="12" Margin="12,0"/>
          <Rectangle Grid.Column="2" Height="1" Fill="{StaticResource Linie}" VerticalAlignment="Center"/>
        </Grid>
        <Grid>
          <Grid.ColumnDefinitions><ColumnDefinition Width="1.35*"/><ColumnDefinition Width="14"/><ColumnDefinition Width="*"/></Grid.ColumnDefinitions>
          <Border BorderBrush="{StaticResource Linie}" BorderThickness="1" CornerRadius="8" Padding="18,16">
            <Border.Background>
              <LinearGradientBrush StartPoint="0,0" EndPoint="1,1"><GradientStop Color="#E6EDF8" Offset="0"/><GradientStop Color="White" Offset="1"/></LinearGradientBrush>
            </Border.Background>
            <StackPanel>
              <TextBlock Text="🎧  Sample-Bibliothek" FontSize="19" FontWeight="SemiBold" Foreground="#1F3F74" FontFamily="Segoe UI Emoji, Segoe UI"/>
              <TextBlock Text="Alles im Ziel durchhören, suchen und filtern – nach Instrument, Pack, Tempo und Tonart." Foreground="{StaticResource Leise}" FontSize="13" TextWrapping="Wrap" Margin="0,2,0,12"/>
              <WrapPanel Margin="0,0,0,12">
                <StackPanel Margin="0,0,22,0"><TextBlock x:Name="KpiSamples" FontSize="21" FontWeight="SemiBold" Text="–"/><TextBlock Text="Samples" Foreground="{StaticResource Leise}" FontSize="12"/></StackPanel>
                <StackPanel Margin="0,0,22,0"><TextBlock x:Name="KpiPacks" FontSize="21" FontWeight="SemiBold" Text="–"/><TextBlock Text="Packs" Foreground="{StaticResource Leise}" FontSize="12"/></StackPanel>
                <StackPanel Margin="0,0,22,0"><TextBlock x:Name="KpiGroesse" FontSize="21" FontWeight="SemiBold" Text="–"/><TextBlock Text="Größe" Foreground="{StaticResource Leise}" FontSize="12"/></StackPanel>
              </WrapPanel>
              <TextBlock x:Name="TxtBibStand" FontSize="12.5" TextWrapping="Wrap" Margin="0,0,0,12"/>
              <WrapPanel>
                <Button x:Name="BtnBibliothek" Style="{StaticResource KnopfHaupt}" Content="Bibliothek öffnen" ToolTip="Öffnet die Sample-Bibliothek im Browser: Samples, Packs und Duplikate mit Suche, Gliederung, Filtern und Abspielen. Fragt vorher, ob das Ziel neu eingelesen werden soll."/>
                <Button x:Name="LnkExcel" Style="{StaticResource Link}" Content="Als Excel-Liste" ToolTip="Öffnet den letzten Stand als CSV-Datei (eine Zeile je Sample), z. B. in Excel."/>
              </WrapPanel>
              <CheckBox x:Name="ChkBibAuto2" Content="Bibliothek künftig automatisch einlesen (nach Sortieren, Import, Duplikate-Entfernen)" FontSize="12.5" Margin="0,12,0,0"
                        ToolTip="Liest das Ziel nach jedem Vorgang, der dort etwas kopiert oder entfernt hat, gleich im Anschluss neu ein (im selben Vorgangsmonitor)."/>
            </StackPanel>
          </Border>
          <Border Grid.Column="2" BorderBrush="{StaticResource Linie}" BorderThickness="1" CornerRadius="8" Padding="18,16">
            <StackPanel>
              <TextBlock Text="Beim letzten Einlesen" FontSize="15" FontWeight="SemiBold" Margin="0,0,0,6"/>
              <StackPanel x:Name="BibAenderungen"/>
              <WrapPanel Margin="0,10,0,0">
                <Button x:Name="LnkAenderungen" Style="{StaticResource Link}" Content="Änderungen anzeigen" ToolTip="Öffnet den Vergleich mit dem vorherigen Stand: neu, entfernt, verschoben."/>
                <Button x:Name="LnkPackArten" Style="{StaticResource Link}" Content="Pack-Arten korrigieren" ToolTip="Öffnet Pack-Arten.csv. Dort lässt sich die automatisch bestimmte Pack-Art einzelner Packs überschreiben; gilt ab dem nächsten Einlesen."/>
              </WrapPanel>
            </StackPanel>
          </Border>
        </Grid>
      </StackPanel>
    </ScrollViewer>
  </DockPanel>
</Window>
'@

# Kleiner Dialog: Sample-Bibliothek oeffnen (neu einlesen?)
$xamlBib = @'
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        Title="Sample-Bibliothek öffnen" Width="480" SizeToContent="Height" ResizeMode="NoResize"
        WindowStartupLocation="CenterOwner" Background="White" ShowInTaskbar="False"
        FontFamily="Segoe UI" FontSize="13.5" Foreground="#1D2430" UseLayoutRounding="True" TextOptions.TextFormattingMode="Display">
  <StackPanel Margin="22,18,22,18">
    <TextBlock x:Name="DTitel" FontSize="17" FontWeight="SemiBold" Margin="0,0,0,8"/>
    <TextBlock x:Name="DText" TextWrapping="Wrap" Margin="0,0,0,10"/>
    <Border x:Name="DWarnRahmen" Background="#FDF1DC" CornerRadius="6" Padding="10,8" Margin="0,0,0,10">
      <TextBlock x:Name="DWarn" Foreground="#7A4A00" TextWrapping="Wrap"/>
    </Border>
    <TextBlock Text="Das Einlesen ändert nichts an den Dateien. Bei vielen Samples dauert es einige Minuten; der Fortschritt erscheint im Hauptfenster." Foreground="#5E6A7A" FontSize="12.5" TextWrapping="Wrap" Margin="0,0,0,16"/>
    <StackPanel Orientation="Horizontal" HorizontalAlignment="Right">
      <Button x:Name="DNeu" Padding="14,7" Margin="0,0,10,0" MinWidth="120"/>
      <Button x:Name="DAlt" Padding="14,7" MinWidth="120"/>
    </StackPanel>
  </StackPanel>
</Window>
'@

try {
    $win = [Windows.Markup.XamlReader]::Parse($xaml)
} catch {
    $m = $_.Exception.Message; if ($_.Exception.InnerException) { $m += "`n" + $_.Exception.InnerException.Message }
    Write-FehlerLog "Oberfläche (XAML): $m"
    [void][System.Windows.Forms.MessageBox]::Show("Die Oberfläche konnte nicht aufgebaut werden:`n$m", 'Samples-Werkzeuge', 'OK', 'Error')
    exit 1
}
$ui = @{}
foreach ($n in @('BtnEinstellungen', 'BtnDoku', 'LnkProtokolle', 'LnkProgramm', 'LnkVerknuepfung', 'BtnSchliessen', 'TxtUrheber', 'TxtUrheberName', 'LnkWebseite', 'TxtUnter', 'Logo', 'Haupt', 'Inhalt',
                 'ImportRahmen', 'BtnImport', 'TxtImport1',
                 'Schritt1', 'Schritt2', 'Schritt3', 'Num1', 'Num2', 'Num3', 'NumT1', 'NumT2', 'NumT3', 'Name1', 'Name2', 'Name3',
                 'Stand1', 'Stand2', 'Stand3', 'Pille1', 'Pille2', 'Pille3', 'PilleT1', 'PilleT2', 'PilleT3', 'Spitze',
                 'Feld1', 'Feld2', 'Feld3', 'QuellListe', 'BtnFundorte', 'BtnQuellen', 'Fakten2', 'BtnSortieren', 'BtnZielOeffnen',
                 'LnkSortProt', 'LnkImportProt', 'Fakten3', 'BtnQuelleAuf', 'BtnZielDup', 'LnkPapierkorb',
                 'Lauf', 'MonitorZeile', 'LnkEinblenden', 'MonitorZeileText', 'LnkLaufZu', 'LnkZeileDatei', 'LaufTitel', 'LaufBalken', 'LaufStatus', 'FrageLeiste', 'LnkFrageDatei', 'BtnJa', 'BtnNein',
                 'FrageText', 'EndeLeiste', 'LnkEndeDatei', 'EndeText', 'LaufLog', 'ChkBibAuto1', 'BibFrage', 'BtnBibJa', 'BtnBibNein', 'ChkBibAuto2',
                 'KpiSamples', 'KpiPacks', 'KpiGroesse', 'TxtBibStand', 'BtnBibliothek', 'LnkExcel', 'BibAenderungen', 'LnkAenderungen', 'LnkPackArten')) {
    $ui[$n] = $win.FindName($n)
}
$win.Title = "Samples-Werkzeuge $ProgrammVersion"
$ui.TxtUnter.Text = "Version $ProgrammVersion  ·  Sample-Packs finden, einsortieren, aufräumen – und dann durchhören."
$ui.TxtUrheberName.Text = $UrheberKurz
# 4.1 (QLN-16): Logo oben rechts, Klick oeffnet die Webseite; fehlt die Datei, bleibt es weg
try {
    $logoPfad = Join-Path $skriptOrdner 'make-some-music.png'
    if (Test-Path -LiteralPath $logoPfad) {
        $bild = New-Object System.Windows.Media.Imaging.BitmapImage
        $bild.BeginInit(); $bild.UriSource = New-Object System.Uri($logoPfad); $bild.CacheOption = 'OnLoad'; $bild.EndInit()
        $ui.Logo.Source = $bild; $ui.Logo.Visibility = 'Visible'
        $ui.Logo.Add_MouseLeftButtonUp({ try { Start-Process $WebSeite } catch { } })
    }
} catch { }
$ui.LnkWebseite.Add_RequestNavigate({ param($s, $ev) try { Start-Process $WebSeite } catch { }; $ev.Handled = $true })
$ui.TxtUrheber.ToolTip = $Urheberhinweis
$ui.LnkProgramm.ToolTip = $basis
try {
    $h = [System.Windows.SystemParameters]::WorkArea.Height - 30
    if ($h -gt 400 -and $win.Height -gt $h) { $win.Height = $h }
} catch { }
try { if (Test-Path -LiteralPath $symbolQuelle) { $ic = [System.Drawing.Icon]::ExtractAssociatedIcon($symbolQuelle); $win.Icon = [System.Windows.Interop.Imaging]::CreateBitmapSourceFromHIcon($ic.Handle, [System.Windows.Int32Rect]::Empty, [System.Windows.Media.Imaging.BitmapSizeOptions]::FromEmptyOptions()) } } catch { }

# Farben
$bc = New-Object System.Windows.Media.BrushConverter
function Get-Pinsel([string]$hex) { return $bc.ConvertFromString($hex) }
$SWF = @{
    Akzent = Get-Pinsel '#2C5AA0'; Weiss = Get-Pinsel '#FFFFFF'; Text = Get-Pinsel '#1D2430'; Leise = Get-Pinsel '#5E6A7A'; Linie = Get-Pinsel '#D6DCE4'
    Ok = Get-Pinsel '#2F7D4A'; OkSanft = Get-Pinsel '#E5F3EA'; Warn = Get-Pinsel '#A86400'; WarnSanft = Get-Pinsel '#FDF1DC'
    Rot = Get-Pinsel '#B3261E'; RotSanft = Get-Pinsel '#FBE4E2'; Grau = Get-Pinsel '#9AA4B2'; Hell = Get-Pinsel '#DCE6F5'; Cyan = Get-Pinsel '#1F6F9F'
    ImportAn = Get-Pinsel '#E6EDF8'; ImportAus = Get-Pinsel '#F7F8FA'
}

# Besitzer fuer die WinForms-Dialoge (macht sie modal zum Hauptfenster)
$form = $null
function Set-Wartezeiger([bool]$an) {
    $win.Cursor = $(if ($an) { [System.Windows.Input.Cursors]::Wait } else { $null })
    [System.Windows.Forms.Cursor]::Current = $(if ($an) { [System.Windows.Forms.Cursors]::WaitCursor } else { [System.Windows.Forms.Cursors]::Default })
}

# Fehler in einer Schaltflaeche abfangen: Meldung mit Zeile und Eintrag in Fehler.log
function Invoke-Sicher([scriptblock]$aktion) {
    try { & $aktion }
    catch {
        $ii = $_.InvocationInfo
        $ort = if ($ii) { "Zeile $($ii.ScriptLineNumber) in $([IO.Path]::GetFileName($ii.ScriptName)): $(([string]$ii.Line).Trim())" } else { '' }
        Write-FehlerLog "Oberfläche: $($_.Exception.Message) | $ort | $($_.ScriptStackTrace -replace '\r?\n', ' <- ')"
        Show-Meldung "Es ist ein Fehler aufgetreten:`n$($_.Exception.Message)`n`n$ort`n`nDetails stehen in $fehlerLog." 'Error'
    }
}
function Set-Klick($element, [scriptblock]$aktion) {
    $element.Tag = $aktion
    $element.Add_Click({ param($s, $ev) Invoke-Sicher $s.Tag; Invoke-Sicher { Update-Status } })
}

# ---------------------------------------------------------------------------
# Skript im Fenster ausfuehren (GUI-04)
# ---------------------------------------------------------------------------
$script:lauf = $null
$script:laufNachher = $null
$script:laufDatei = ''
$script:laufFehler = $false
$script:laufEnde = $null
$script:laufSchritt = 0          # 4.0.1: Schritt, zu dem der Vorgangsmonitor gehoert (0 = keiner)
$script:laufZeilen = New-Object System.Collections.Generic.List[string]   # gesamte Ausgabe (fuer die Textdatei)
$script:laufStart = $null
$script:laufErgebnis = ''
$script:laufNein = $false
$script:laufBib = $false         # 4.1 (INV-11): der Vorgang hat im Ziel etwas kopiert oder entfernt
$script:logNeu = 0
$script:monitorOffen = $false
$zeitgeber = New-Object System.Windows.Threading.DispatcherTimer
$zeitgeber.Interval = [TimeSpan]::FromMilliseconds(120)

function Test-LaufAktiv { return ($null -ne $script:lauf) }

function Add-LogZeile([string]$text, $pinsel, [bool]$fett = $false) {
    $script:laufZeilen.Add($text)
    $script:logNeu++
    $tb = New-Object System.Windows.Controls.TextBlock
    $tb.Text = $text
    if ($pinsel) { $tb.Foreground = $pinsel }
    if ($fett) { $tb.FontWeight = 'Bold' }
    [void]$ui.LaufLog.Items.Add($tb)
    while ($ui.LaufLog.Items.Count -gt 4000) { $ui.LaufLog.Items.RemoveAt(0) }
}

# Vorgangsmonitor zeigen: offen, als Zeile zum Einblenden oder gar nicht (4.0.1, Befunde 4 und 9)
function Update-Monitor {
    $da = ($script:laufSchritt -gt 0)
    if (-not $da) { $ui.Lauf.Visibility = 'Collapsed'; $ui.MonitorZeile.Visibility = 'Collapsed'; return }
    # Ein laufender Vorgang bleibt immer sichtbar (eine offene Frage darf nicht verschwinden)
    if (Test-LaufAktiv) { $ui.Lauf.Visibility = 'Visible'; $ui.MonitorZeile.Visibility = 'Collapsed'; return }
    $hier = ($script:laufSchritt -eq $script:aktiverSchritt)
    $ui.Lauf.Visibility = $(if ($hier -and $script:monitorOffen) { 'Visible' } else { 'Collapsed' })
    $ui.MonitorZeile.Visibility = $(if ($hier -and -not $script:monitorOffen) { 'Visible' } else { 'Collapsed' })
    $ui.MonitorZeileText.Text = "Vorgangsmonitor  ·  $($ui.LaufTitel.Text) $([char]0x2013) $($script:laufErgebnis)"
    $ui.LnkZeileDatei.Visibility = $ui.LnkEndeDatei.Visibility
    $ui.LnkZeileDatei.Content = $ui.LnkEndeDatei.Content
}

function Set-Bedienbar([bool]$an) {
    foreach ($n in @('BtnImport', 'BtnFundorte', 'BtnQuellen', 'BtnSortieren', 'BtnQuelleAuf', 'BtnZielDup', 'BtnBibliothek', 'BtnEinstellungen', 'LnkPackArten')) { $ui[$n].IsEnabled = $an }
    $ui.LnkLaufZu.IsEnabled = $an
}

# Startet ein Skript; Ausgabe, Fortschritt und Rueckfragen erscheinen im Ablauf-Bereich.
# $nachher: Skriptblock, der nach erfolgreichem Ende laeuft (z. B. Bericht oeffnen).
function Start-Skript([string]$datei, [string]$argumente = '', [string]$titel = 'Samples-Werkzeuge', [scriptblock]$nachher = $null, [switch]$Anhaengen) {
    if (Test-LaufAktiv) { Show-Meldung 'Es läuft bereits ein Vorgang. Bitte warten, bis er fertig ist.' 'Warning'; return $false }
    $pfad = Join-Path $skriptOrdner $datei
    if (-not (Test-Path -LiteralPath $pfad)) { Show-Meldung "Datei nicht gefunden:`n$pfad" 'Error'; return $false }
    $p = $pfad.Replace("'", "''")
    # 4.0.1: ohne Fortschrittsdaten eingebauter Befehle (die kaemen als CLIXML ueber den Fehlerkanal, Befund 3)
    $befehl = "`$ProgressPreference = 'SilentlyContinue'; try { [Console]::OutputEncoding = New-Object System.Text.UTF8Encoding(`$false) } catch { }; " +
              "try { & '$p' $argumente } catch { [Console]::Out.WriteLine('##T##Red##FEHLER: ' + `$_.Exception.Message); exit 1 }"
    $kodiert = [Convert]::ToBase64String([Text.Encoding]::Unicode.GetBytes($befehl))
    # 4.1 (INV-11): Anhaengen = im selben Vorgangsmonitor weiter (Verlauf bleibt stehen, Trennzeile)
    if ($Anhaengen -and $ui.LaufLog.Items.Count) { $script:laufZeilen.Clear(); Add-LogZeile '' $null; Add-LogZeile "===== $titel =====" $SWF.Akzent $true }
    else { $ui.LaufLog.Items.Clear(); $script:laufZeilen.Clear() }
    $script:laufStart = Get-Date
    # Schritt, zu dem der Vorgang gehoert: Import zaehlt zu Sortieren (Befund 9)
    $script:laufSchritt = switch -Wildcard ($datei) { 'Fundorte*' { 1 } 'Samples-sortieren*' { 2 } 'Download-importieren*' { 2 } 'Quelle-aufraeumen*' { 3 } 'Ziel-Duplikate*' { 3 } default { $script:aktiverSchritt } }
    if ($script:laufSchritt -ne $script:aktiverSchritt) { Set-Schritt $script:laufSchritt }
    $script:monitorOffen = $true
    $ui.LaufTitel.Text = $titel
    $ui.LaufStatus.Text = 'läuft …'
    $ui.LaufBalken.IsIndeterminate = $true
    $ui.LaufBalken.Visibility = 'Visible'
    $ui.FrageLeiste.Visibility = 'Collapsed'
    $ui.EndeLeiste.Visibility = 'Collapsed'
    $ui.LaufLog.Visibility = 'Visible'
    $script:logUnten = $true; $script:laufNein = $false; $script:laufBib = $false
    $ui.BibFrage.Visibility = 'Collapsed'
    $ui.Lauf.Visibility = 'Visible'; $ui.MonitorZeile.Visibility = 'Collapsed'
    $script:laufDatei = ''; $script:laufFehler = $false; $script:laufEnde = $null; $script:laufNachher = $nachher
    try {
        $l = New-Object SamplesWerkzeuge.SkriptLauf400
        $l.Start($psExe, "-NoProfile -NonInteractive -ExecutionPolicy Bypass -EncodedCommand $kodiert", $basis)
        $script:lauf = $l
    } catch {
        $script:laufSchritt = 0; Update-Monitor
        Show-Meldung "Start fehlgeschlagen:`n$($_.Exception.Message)" 'Error'
        return $false
    }
    Set-Bedienbar $false
    Update-LogHoehe
    $ui.Lauf.BringIntoView()
    $zeitgeber.Start()
    return $true
}

function Read-LaufZeilen {
    $script:logNeu = 0
    foreach ($z in $script:lauf.Hole()) {
        if ($z.StartsWith('##T##')) {
            $rest = $z.Substring(5); $i = $rest.IndexOf('##')
            $farbe = if ($i -ge 0) { $rest.Substring(0, $i) } else { '' }
            $text = if ($i -ge 0) { $rest.Substring($i + 2) } else { $rest }
            $pinsel = switch ($farbe) { 'Red' { $SWF.Rot } 'DarkRed' { $SWF.Rot } 'Green' { $SWF.Ok } 'DarkGreen' { $SWF.Ok } 'Yellow' { $SWF.Warn } 'DarkYellow' { $SWF.Warn }
                                        'Cyan' { $SWF.Cyan } 'DarkCyan' { $SWF.Cyan } 'DarkGray' { $SWF.Leise } 'Gray' { $SWF.Leise } default { $null } }
            if ($text -match '^\s*FEHLER') { $pinsel = $SWF.Rot; $script:laufFehler = $true }
            # 4.0.2 (Befund 5): Ueberschriften wie "===== Ergebnis =====" blau und fett statt orange
            # 4.1 (QLN-16): farbige Zeilen fett, grau bleibt normal
            $fett = ($null -ne $pinsel -and $pinsel -ne $SWF.Leise)
            if ($text -match '^\s*={3,}.*={3,}\s*$') { $pinsel = $SWF.Akzent; $fett = $true }
            Add-LogZeile $text $pinsel $fett
            # Zuletzt genannte Datei (Vorschau, Protokoll, Bericht) zum Oeffnen anbieten
            if ($text -match '([A-Za-z]:\\[^<>|"*?]+\.(csv|html))\s*$') { $script:laufDatei = $Matches[1] }
        } elseif ($z.StartsWith('##P##')) {
            $teile = $z.Substring(5) -split '##', 3
            if ($teile[0] -eq '-') { $ui.LaufBalken.IsIndeterminate = $true; $ui.LaufStatus.Text = 'läuft …' }
            else {
                $pz = 0; [void][int]::TryParse($teile[0], [ref]$pz)
                if ($pz -ge 0) { $ui.LaufBalken.IsIndeterminate = $false; $ui.LaufBalken.Value = [Math]::Min(100, $pz) }
                $ui.LaufStatus.Text = $(if ($teile.Count -ge 3 -and $teile[2]) { "$($teile[1]) · $($teile[2])" } else { $teile[1] })
            }
        } elseif ($z -eq '##BIB##') {
            $script:laufBib = $true
        } elseif ($z.StartsWith('##FRAGE##')) {
            $ui.FrageText.Text = $z.Substring(9)
            $ui.LnkFrageDatei.Visibility = $(if ($script:laufDatei -and (Test-Path -LiteralPath $script:laufDatei)) { 'Visible' } else { 'Collapsed' })
            $ui.LnkFrageDatei.Content = $(if ($script:laufDatei -match 'Vorschau') { 'Vorschau öffnen' } else { 'Datei öffnen' })
            $ui.FrageLeiste.Visibility = 'Visible'
            $ui.LaufBalken.IsIndeterminate = $false; $ui.LaufBalken.Value = 0
            $ui.LaufStatus.Text = 'wartet auf deine Antwort'
            $ui.BtnNein.Focus() | Out-Null
            $ui.FrageLeiste.BringIntoView()
        } elseif ($z.StartsWith('##E##')) {
            $t = $z.Substring(5)
            # 4.0.1 (Befund 3): Windows PowerShell schickt ueber den Fehlerkanal CLIXML (u. a. Fortschritt). Nur echte
            # Fehlertexte daraus zeigen; Fortschritt und Kopfzeile "#< CLIXML" uebergehen.
            if ($t.TrimStart().StartsWith('#< CLIXML')) { continue }
            if ($t.TrimStart().StartsWith('<Objs')) {
                foreach ($m in [regex]::Matches($t, '<S S="Error">(.*?)</S>')) {
                    $f = [regex]::Replace($m.Groups[1].Value, '_x([0-9A-Fa-f]{4})_', { param($x) [string][char][Convert]::ToInt32($x.Groups[1].Value, 16) })
                    $f = [Net.WebUtility]::HtmlDecode($f).TrimEnd("`r", "`n")
                    if ($f.Trim()) { foreach ($fz in ($f -split "`r?`n")) { Add-LogZeile $fz $SWF.Rot $true }; $script:laufFehler = $true }
                }
                continue
            }
            if ($t.Trim()) { Add-LogZeile $t $SWF.Rot $true; $script:laufFehler = $true }
        } else {
            Add-LogZeile $z $null
        }
    }
    # 4.0.2 (Befund 1): nur bei neuen Zeilen und nur, wenn man unten steht
    if ($script:logNeu -gt 0 -and $script:logUnten -and $ui.LaufLog.Items.Count) { $ui.LaufLog.ScrollIntoView($ui.LaufLog.Items[$ui.LaufLog.Items.Count - 1]) }
}

function Stop-LaufAnzeige {
    $zeitgeber.Stop()
    $code = $script:lauf.Code
    $script:lauf = $null
    $ok = ($code -eq 0 -and -not $script:laufFehler)
    $ui.FrageLeiste.Visibility = 'Collapsed'
    $ui.LaufBalken.Visibility = 'Collapsed'
    $ui.LaufStatus.Text = ''
    # 4.0.2 (Befund 8): nach "Nein" abgebrochen statt fertig
    $nein = ($ok -and $script:laufNein)
    $ui.EndeText.Text = $(if ($nein) { 'Abgebrochen – es wurde nichts geändert.' } elseif ($ok) { "$([char]0x2714)  Fertig." } else { "$([char]0x26A0)  Beendet mit Fehler – Details im Verlauf." })
    $ui.EndeText.Foreground = $(if ($nein) { $SWF.Leise } elseif ($ok) { $SWF.Ok } else { $SWF.Rot })
    $hatDatei = ($script:laufDatei -and (Test-Path -LiteralPath $script:laufDatei))
    $ui.LnkEndeDatei.Visibility = $(if ($hatDatei) { 'Visible' } else { 'Collapsed' })
    $ui.LnkEndeDatei.Content = $(if ($script:laufDatei -match '\.html$') { 'Bericht öffnen' } elseif ($script:laufDatei -match 'Vorschau') { 'Vorschau öffnen' } else { 'Protokoll öffnen' })
    $ui.EndeLeiste.Visibility = 'Visible'
    $script:laufErgebnis = $(if ($nein) { 'Abgebrochen' } elseif ($ok) { 'Fertig' } else { 'Beendet mit Fehler' }) + " ($((Get-Date).ToString('HH:mm')))"
    # 4.0.1: Ausgabe als Textdatei im Protokollordner (Befund 4)
    try {
        [void][IO.Directory]::CreateDirectory($protokollOrdner)
        $name = ($ui.LaufTitel.Text -replace '[^\w\- ]', '' -replace '\s+', '-')
        $kopf = @("Samples-Werkzeuge $ProgrammVersion - Vorgangsmonitor: $($ui.LaufTitel.Text)", "Start: $($script:laufStart.ToString('dd.MM.yyyy HH:mm:ss'))   Ende: $((Get-Date).ToString('dd.MM.yyyy HH:mm:ss'))   Ergebnis: $($script:laufErgebnis)", '')
        [IO.File]::WriteAllLines((Join-Path $protokollOrdner "Vorgang_$($script:laufStart.ToString('yyyy-MM-dd_HHmmss'))_$name.txt"), [string[]]($kopf + $script:laufZeilen.ToArray()), (New-Object Text.UTF8Encoding($true)))
    } catch { Write-FehlerLog "Vorgangsmonitor (Textdatei): $($_.Exception.Message)" }
    Update-Monitor
    Update-LogHoehe
    Set-Bedienbar $true
    Update-Status
    if ($ok -and -not $nein -and $script:laufNachher) { Invoke-Sicher $script:laufNachher }
    $script:laufNachher = $null
    # 4.1 (INV-11): hat sich im Ziel etwas geaendert, Bibliothek neu einlesen - automatisch oder per Knopf
    if ($script:laufBib -and -not $nein) {
        $script:laufBib = $false
        if ((Get-Einstellungen).BibliothekAutomatisch) {
            $win.Dispatcher.BeginInvoke([Action]{ [void](Start-Skript 'Inventur.ps1' '' 'Sample-Bibliothek einlesen' $null -Anhaengen) }, [System.Windows.Threading.DispatcherPriority]::Background) | Out-Null
        } else {
            $ui.BibFrage.Visibility = 'Visible'; $ui.BtnBibJa.Focus() | Out-Null
            Update-LogHoehe
        }
    }
}

$zeitgeber.Add_Tick({
    try {
        if (-not $script:lauf) { $zeitgeber.Stop(); return }
        Read-LaufZeilen
        if ($script:lauf.Beendet) {
            # Nach dem Ende noch kurz nachlesen (Ausgabe kann nachlaufen), dann abschliessen
            if (-not $script:laufEnde) { $script:laufEnde = Get-Date }
            elseif ($script:lauf.Leer -and ((Get-Date) - $script:laufEnde).TotalMilliseconds -gt 700) { Read-LaufZeilen; Stop-LaufAnzeige }
        }
    } catch {
        Write-FehlerLog "Oberfläche (Ausgabe): $($_.Exception.Message)"
    }
})

Set-Klick $ui.BtnJa {
    if (-not $script:lauf) { return }
    $ui.FrageLeiste.Visibility = 'Collapsed'; $ui.LaufBalken.IsIndeterminate = $true; $ui.LaufStatus.Text = 'läuft …'
    Add-LogZeile "> $($ui.FrageText.Text)  Ja" $SWF.Akzent $true
    $script:lauf.Antwort('J')
}
Set-Klick $ui.BtnNein {
    if (-not $script:lauf) { return }
    $ui.FrageLeiste.Visibility = 'Collapsed'; $ui.LaufBalken.IsIndeterminate = $true; $ui.LaufStatus.Text = 'läuft …'
    Add-LogZeile "> $($ui.FrageText.Text)  Nein" $SWF.Akzent $true
    $script:laufNein = $true
    $script:lauf.Antwort('N')
}
Set-Klick $ui.LnkFrageDatei { Open-Pfad $script:laufDatei }
Set-Klick $ui.LnkEndeDatei {
    if ($script:laufDatei -match '\.html$' -and $script:laufDatei -match 'Inventur') { Open-Bericht } else { Open-Pfad $script:laufDatei }
}
# 4.1 (QLN-16): beim Ein- und Ausblenden bleibt die Kopfzeile des Vorgangsmonitors an ihrer Stelle auf dem Bildschirm
function Set-MonitorOffen([bool]$offen) {
    $vorher = $(if ($ui.Lauf.Visibility -eq 'Visible') { $ui.Lauf } else { $ui.MonitorZeile })
    $y0 = $null; try { $y0 = $vorher.TranslatePoint((New-Object System.Windows.Point(0, 0)), $ui.Haupt).Y } catch { }
    $script:monitorOffen = $offen
    Update-Monitor
    Update-LogHoehe -Sofort
    $nachher = $(if ($ui.Lauf.Visibility -eq 'Visible') { $ui.Lauf } else { $ui.MonitorZeile })
    if ($null -ne $y0) {
        try {
            $win.UpdateLayout()
            $y1 = $nachher.TranslatePoint((New-Object System.Windows.Point(0, 0)), $ui.Haupt).Y
            $ui.Haupt.ScrollToVerticalOffset($ui.Haupt.VerticalOffset + ($y1 - $y0))
        } catch { }
    }
}
Set-Klick $ui.LnkLaufZu { Set-MonitorOffen $false }
Set-Klick $ui.LnkEinblenden { Set-MonitorOffen $true }
Set-Klick $ui.LnkZeileDatei {
    if ($script:laufDatei -match '\.html$' -and $script:laufDatei -match 'Inventur') { Open-Bericht } else { Open-Pfad $script:laufDatei }
}
# 4.0.2 (Befund 1): Verlauf nur nachziehen, wenn man unten steht - sonst bleibt die Stelle, an die man gescrollt hat
$script:logUnten = $true
$ui.LaufLog.AddHandler([System.Windows.Controls.ScrollViewer]::ScrollChangedEvent, [System.Windows.Controls.ScrollChangedEventHandler]{
    param($s, $ev)
    if ($ev.ExtentHeightChange -eq 0) { $script:logUnten = (($ev.VerticalOffset + $ev.ViewportHeight) -ge ($ev.ExtentHeight - 1)) }
})
# 4.1 (QLN-16): Verlauf fuellt genau den freien Platz - im Vollbild passt alles auf eine Seite, im kleinen
# Fenster bleibt er mindestens 210 hoch (dann wird gescrollt)
function Update-LogHoehe([switch]$Sofort) {
    $setzen = {
        try {
            if ($ui.Lauf.Visibility -ne 'Visible' -or $ui.LaufLog.Visibility -ne 'Visible') { return }
            # 4.1.1 (Befund 1): natuerliche Hoehe des Inhalts (VerticalAlignment Top, sonst streckt der ScrollViewer ihn auf die Fensterhoehe)
            $rest = $ui.Inhalt.ActualHeight + $ui.Inhalt.Margin.Top + $ui.Inhalt.Margin.Bottom - $ui.LaufLog.ActualHeight
            $h = [Math]::Floor($ui.Haupt.ViewportHeight - $rest - 2)
            $neu = [Math]::Max(210, $h)
            if ([Math]::Abs($ui.LaufLog.Height - $neu) -ge 1 -or [double]::IsNaN($ui.LaufLog.Height)) { $ui.LaufLog.Height = $neu }
        } catch { }
    }
    if ($Sofort) { $win.UpdateLayout(); & $setzen }
    else { [void]$win.Dispatcher.BeginInvoke([Action]$setzen, [System.Windows.Threading.DispatcherPriority]::Loaded) }
}
$win.Add_SizeChanged({ Update-LogHoehe })

# ---------------------------------------------------------------------------
# Schritte des Ablaufs
# ---------------------------------------------------------------------------
$script:aktiverSchritt = 2
$script:vglCache = @{ Schluessel = ''; Werte = $null }
$script:zipCache = @{}
$script:bibVeraltet = $false
$script:schrittZustand = @{ 1 = 'neutral'; 2 = 'neutral'; 3 = 'neutral' }

function Set-Schritt([int]$n) {
    $alt = $script:aktiverSchritt
    $script:aktiverSchritt = $n
    foreach ($i in 1..3) { $ui["Feld$i"].Visibility = $(if ($i -eq $n) { 'Visible' } else { 'Collapsed' }) }
    [System.Windows.Controls.Grid]::SetColumn($ui.Spitze, ($n - 1) * 2)
    # Abgeschlossener Vorgang: beim Verlassen des Schritts weg, beim Zurueckkehren als Zeile zum Einblenden
    if ($n -ne $alt -and -not (Test-LaufAktiv)) { $script:monitorOffen = $false }
    Update-Monitor
    Update-SchrittAussehen
    Update-LogHoehe
}

function Update-SchrittAussehen {
    foreach ($i in 1..3) {
        $z = $script:schrittZustand[$i]; $aktiv = ($i -eq $script:aktiverSchritt)
        $r = $ui["Schritt$i"]
        if ($aktiv) {
            $r.Background = $SWF.Akzent; $r.BorderBrush = $SWF.Akzent
            $ui["Name$i"].Foreground = $SWF.Weiss; $ui["Stand$i"].Foreground = $SWF.Hell
            $ui["Num$i"].Background = $SWF.Weiss; $ui["NumT$i"].Foreground = $SWF.Akzent
        } else {
            $r.Background = $SWF.Weiss
            $r.BorderBrush = $(if ($z -eq 'ok') { $SWF.Ok } else { $SWF.Linie })
            $ui["Name$i"].Foreground = $SWF.Text; $ui["Stand$i"].Foreground = $SWF.Leise
            $ui["Num$i"].Background = $(if ($z -eq 'ok') { $SWF.Ok } else { $SWF.Linie }); $ui["NumT$i"].Foreground = $(if ($z -eq 'ok') { $SWF.Weiss } else { $SWF.Text })
        }
        $p = $ui["Pille$i"]; $pt = $ui["PilleT$i"]
        switch ($z) {
            'ok'     { $p.Background = $SWF.OkSanft;   $pt.Foreground = $SWF.Ok }
            'warn'   { $p.Background = $SWF.WarnSanft; $pt.Foreground = $SWF.Warn }
            'fehler' { $p.Background = $SWF.RotSanft;  $pt.Foreground = $SWF.Rot }
            default  { $p.Background = $SWF.Linie;     $pt.Foreground = $SWF.Leise }
        }
        $p.Visibility = $(if ($pt.Text) { 'Visible' } else { 'Collapsed' })
    }
}
foreach ($i in 1..3) {
    $ui["Schritt$i"].Tag = $i
    $ui["Schritt$i"].Add_MouseLeftButtonUp({ param($s, $ev) Invoke-Sicher { Set-Schritt ([int]$s.Tag) } })
}

function New-Fakt($eltern, [string]$schluessel, [string]$wert) {
    $sp = New-Object System.Windows.Controls.StackPanel
    $sp.Orientation = 'Horizontal'; $sp.Margin = '0,0,26,4'
    $k = New-Object System.Windows.Controls.TextBlock; $k.Text = $schluessel; $k.Foreground = $SWF.Leise; $k.Margin = '0,0,8,0'
    $w = New-Object System.Windows.Controls.TextBlock; $w.Text = $wert; $w.FontWeight = 'SemiBold'
    [void]$sp.Children.Add($k); [void]$sp.Children.Add($w)
    [void]$eltern.Children.Add($sp)
}
function Format-Zeit($t) { if ($t) { return $t.ToString('dd.MM.yyyy, HH:mm') } else { return '' } }

# ---------------------------------------------------------------------------
# Status (beim Start und immer, wenn das Fenster wieder aktiv wird)
# ---------------------------------------------------------------------------
function Update-Status {
    if (-not $ui) { return }
    $e = Get-Einstellungen
    $strich = [char]0x2013

    # --- Abkuerzung Import: ZIP-Archive mit Audiodateien im Download-Ordner (4.0.1, Befund 7)
    # Gelesen wird nur das Inhaltsverzeichnis; das Ergebnis je ZIP wird gemerkt, bis sich die Datei aendert.
    $nZip = 0
    try {
        if ($e.Downloads -and (Test-Path -LiteralPath $e.Downloads)) {
            foreach ($z in @(Get-ChildItem -LiteralPath $e.Downloads -Filter '*.zip' -File -ErrorAction SilentlyContinue)) {
                $sch = "$($z.Length)|$($z.LastWriteTimeUtc.Ticks)"
                $c = $script:zipCache[$z.FullName]
                if (-not $c -or $c.Schluessel -ne $sch) {
                    $hat = $false
                    try {
                        foreach ($en in [SamplesWerkzeuge.ZipWerkzeug301]::Liste($z.FullName)) {
                            if (-not $en.Ordner -and -not [SamplesWerkzeuge.ZipWerkzeug301]::MacRest($en.Name) -and [SamplesWerkzeuge.ZipWerkzeug301]::AudioExt.Contains([SamplesWerkzeuge.ZipWerkzeug301]::Ext($en.Name))) { $hat = $true; break }
                        }
                    } catch { }
                    $c = @{ Schluessel = $sch; Audio = $hat }; $script:zipCache[$z.FullName] = $c
                }
                if ($c.Audio) { $nZip++ }
            }
        }
    } catch { }
    if ($nZip -gt 0) {
        $ui.TxtImport1.Text = "Neuer Download? $nZip ZIP-Archiv$(if ($nZip -ne 1) { 'e' }) mit Samples im Download-Ordner"
        $ui.ImportRahmen.Fill = $SWF.ImportAn; $ui.ImportRahmen.Stroke = $SWF.Akzent
    } else {
        $ui.TxtImport1.Text = 'Neuer Download? Frisch heruntergeladene Packs direkt einsortieren'
        $ui.ImportRahmen.Fill = $SWF.ImportAus; $ui.ImportRahmen.Stroke = $SWF.Grau
    }

    # --- 1 Quellen
    $alle = @($e.Quellen); $aktiv = @($alle | Where-Object { $_.Aktiv })
    $fehlen = @($aktiv | Where-Object { -not (Test-Path -LiteralPath $_.Pfad) })
    $aus = $alle.Count - $aktiv.Count
    $ui.Stand1.Text = $(if (-not $alle.Count) { 'noch keine Quelle eingetragen' } else { "$($aktiv.Count) Quelle$(if ($aktiv.Count -ne 1) { 'n' }) aktiv" + $(if ($aus) { ", $aus deaktiviert" } else { '' }) })
    if (-not $aktiv.Count) { $script:schrittZustand[1] = 'warn'; $ui.PilleT1.Text = "$([char]0x25CF) Quelle hinzufügen" }
    elseif ($fehlen.Count) { $script:schrittZustand[1] = 'fehler'; $ui.PilleT1.Text = "$([char]0x25CF) $($fehlen.Count) nicht gefunden" }
    else { $script:schrittZustand[1] = 'ok'; $ui.PilleT1.Text = "$([char]0x2713) eingerichtet" }
    $ui.QuellListe.Children.Clear()
    if (-not $alle.Count) {
        $tb = New-Object System.Windows.Controls.TextBlock; $tb.Text = 'Noch keine Quelle. „Fundorte suchen …“ findet Sample-Packs auf deinen Laufwerken.'; $tb.Margin = '10,8'; $tb.Foreground = $SWF.Leise; $tb.TextWrapping = 'Wrap'
        [void]$ui.QuellListe.Children.Add($tb)
    }
    $erste = $true
    foreach ($q in $alle) {
        $g = New-Object System.Windows.Controls.DockPanel
        $g.Margin = '0'
        $rand = New-Object System.Windows.Controls.Border
        $rand.BorderBrush = $SWF.Linie; $rand.BorderThickness = $(if ($erste) { '0' } else { '0,1,0,0' }); $rand.Padding = '10,6'; $erste = $false
        $da = Test-Path -LiteralPath $q.Pfad
        $haken = New-Object System.Windows.Controls.TextBlock; $haken.Text = $(if ($q.Aktiv) { [char]0x2611 } else { [char]0x2610 }); $haken.Margin = '0,0,10,0'; $haken.FontFamily = 'Segoe UI Symbol'
        $zust = New-Object System.Windows.Controls.TextBlock; $zust.FontSize = 12; $zust.Margin = '12,0,0,0'
        if (-not $q.Aktiv) { $zust.Text = 'deaktiviert'; $zust.Foreground = $SWF.Grau }
        elseif (-not $da) { $zust.Text = 'NICHT GEFUNDEN'; $zust.Foreground = $SWF.Rot }
        else { $zust.Text = 'gefunden'; $zust.Foreground = $SWF.Ok }
        $art = New-Object System.Windows.Controls.TextBlock; $art.FontSize = 12; $art.Foreground = $SWF.Leise; $art.Margin = '12,0,0,0'
        $an = Get-QuellArtName $q.Art; $art.Text = $(if ($an -eq 'Sammlung') { 'Sammlung' } else { $QuellArten[$an] })
        $pf = New-Object System.Windows.Controls.TextBlock; $pf.Text = $q.Pfad; $pf.FontFamily = 'Consolas'; $pf.FontSize = 12.5; $pf.TextTrimming = 'CharacterEllipsis'; $pf.ToolTip = $q.Pfad
        if (-not $q.Aktiv) { $pf.Foreground = $SWF.Grau }
        [System.Windows.Controls.DockPanel]::SetDock($haken, 'Left'); [System.Windows.Controls.DockPanel]::SetDock($zust, 'Right'); [System.Windows.Controls.DockPanel]::SetDock($art, 'Right')
        [void]$g.Children.Add($haken); [void]$g.Children.Add($zust); [void]$g.Children.Add($art); [void]$g.Children.Add($pf)
        $rand.Child = $g
        [void]$ui.QuellListe.Children.Add($rand)
    }
    $zs = Get-OrdnerStatus $e.Ziel

    # --- 2 Sortieren
    # 4.0.1 (Befund 2): Stand aus den Protokollen im Ziel (99_Protokolle) - sie gehoeren zum tatsaechlichen Ziel
    $zielProt = @(Get-ZielProtokollOrdner $e.Ziel)
    $p = Get-NeuestesProtokoll 'Protokoll_*.csv' $zielProt
    $tSort = if ($p) { Get-Protokollzeit $p } else { $null }
    $ip = Get-NeuestesProtokoll 'Import-Protokoll_*.csv' $zielProt
    $tImp = if ($ip) { Get-Protokollzeit $ip } else { $null }
    $ui.Stand2.Text = $(if ($tSort) { "Letzter Lauf: $(Format-Zeit $tSort)" } else { 'Noch kein Sortierlauf' })
    # Neues in den Quellen? Aenderungszeit der Quelle und ihrer Unterordner (eine Ebene) gegen den letzten Lauf.
    # 4.0.1 (Befund 7): bei "Nur lose Dateien" nur neue Audiodateien direkt im Ordner (ZIPs, Installer usw. zaehlen nicht)
    $neuer = @()
    if ($tSort) {
        foreach ($q in $aktiv) {
            try {
                if (-not (Test-Path -LiteralPath $q.Pfad)) { continue }
                if ((Get-QuellArtName $q.Art) -eq 'Lose') {
                    $grenze = $tSort.AddMinutes(1)
                    $neu = @(Get-ChildItem -LiteralPath $q.Pfad -File -ErrorAction SilentlyContinue | Where-Object { $_.Name -match $RxAudio -and -not $_.Name.StartsWith('._') -and ($_.CreationTime -gt $grenze -or $_.LastWriteTime -gt $grenze) } | Select-Object -First 1)
                    if ($neu.Count) { $neuer += $q.Pfad }
                    continue
                }
                $d = Get-Item -LiteralPath $q.Pfad -ErrorAction Stop
                $t = $d.LastWriteTime
                foreach ($u in @(Get-ChildItem -LiteralPath $q.Pfad -Directory -ErrorAction SilentlyContinue)) { if ($u.LastWriteTime -gt $t) { $t = $u.LastWriteTime } }
                if ($t -gt $tSort.AddMinutes(1)) { $neuer += $q.Pfad }
            } catch { }
        }
    }
    # 4.1 (GUI-08): Ziel nicht erreichbar (z. B. externe Platte nicht angesteckt) - rot, Sortieren startet nicht
    if ($zs.Fehlt) { $script:schrittZustand[2] = 'fehler'; $ui.PilleT2.Text = "$([char]0x25CF) Ziel $(if ($e.Ziel) { 'nicht gefunden' } else { 'nicht eingestellt' })" }
    elseif ($script:schrittZustand[1] -ne 'ok') { $script:schrittZustand[2] = 'neutral'; $ui.PilleT2.Text = 'erst Quellen einrichten' }
    elseif (-not $tSort) { $script:schrittZustand[2] = 'warn'; $ui.PilleT2.Text = "$([char]0x25CF) noch nicht sortiert" }
    elseif ($neuer.Count) { $script:schrittZustand[2] = 'warn'; $ui.PilleT2.Text = "$([char]0x25CF) Neues in $($neuer.Count) Quelle$(if ($neuer.Count -ne 1) { 'n' })" }
    else { $script:schrittZustand[2] = 'ok'; $ui.PilleT2.Text = "$([char]0x2713) auf dem Stand" }
    $ui.Fakten2.Children.Clear()
    New-Fakt $ui.Fakten2 'Letzter Lauf' $(if ($tSort) { Format-Zeit $tSort } else { 'noch keiner' })
    if ($tImp) { New-Fakt $ui.Fakten2 'Letzter Import' (Format-Zeit $tImp) }
    $frei = ''
    try { $dr = New-Object IO.DriveInfo ([IO.Path]::GetPathRoot($e.Ziel)); if ($dr.IsReady) { $frei = ' · {0:N0} GB frei' -f ($dr.AvailableFreeSpace / 1GB) } } catch { }
    New-Fakt $ui.Fakten2 'Ziel' "$($e.Ziel)$frei"
    $zus = @(@('RX2', 'RX2Beibehalten'), @('MP3', 'MP3Beibehalten'), @('AIFF', 'AIFFBeibehalten') | Where-Object { $e[$_[1]] } | ForEach-Object { $_[0] })
    New-Fakt $ui.Fakten2 'Formate' $(if ($zus.Count -eq 3) { 'alle (WAV, RX2, MP3, AIFF)' } elseif ($zus.Count -eq 0) { 'nur WAV, wenn vorhanden' } else { "WAV, zusätzlich $($zus -join ', ')" })
    if ($neuer.Count) { New-Fakt $ui.Fakten2 'Geändert seit dem letzten Lauf' ($neuer -join ', ') }
    $ui.LnkSortProt.IsEnabled = [bool]$p
    $ui.LnkImportProt.IsEnabled = [bool]$ip

    # --- 3 Aufraeumen
    $dp = Get-NeuestesProtokoll 'Quelle-aufgeraeumt_*.csv' $zielProt
    $zp = Get-NeuestesProtokoll 'Ziel-Duplikate-entfernt_*.csv' $zielProt
    $tAuf = if ($dp) { Get-Protokollzeit $dp } else { $null }
    $tZiel = if ($zp) { Get-Protokollzeit $zp } else { $null }
    $tLetzt = @($tAuf, $tZiel | Where-Object { $_ } | Sort-Object -Descending)[0]
    $tNeuSort = @($tSort, $tImp | Where-Object { $_ } | Sort-Object -Descending)[0]
    $ui.Stand3.Text = $(if ($tLetzt) { "Zuletzt aufgeräumt: $(Format-Zeit $tLetzt)" } else { 'Quellen und Ziel entschlacken' })
    if (-not $tNeuSort) { $script:schrittZustand[3] = 'neutral'; $ui.PilleT3.Text = 'nach dem Sortieren' }
    elseif (-not $tLetzt -or $tLetzt -lt $tNeuSort) { $script:schrittZustand[3] = 'warn'; $ui.PilleT3.Text = "$([char]0x25CF) seit dem Sortieren nicht aufgeräumt" }
    else { $script:schrittZustand[3] = 'ok'; $ui.PilleT3.Text = "$([char]0x2713) aufgeräumt" }
    $ui.Fakten3.Children.Clear()
    New-Fakt $ui.Fakten3 'Quellen zuletzt' $(if ($tAuf) { Format-Zeit $tAuf } else { 'noch nie' })
    New-Fakt $ui.Fakten3 'Ziel zuletzt' $(if ($tZiel) { Format-Zeit $tZiel } else { 'noch nie' })

    # --- Sample-Bibliothek: letzter eingelesener Stand, laut Ziel\99_Protokolle (4.0.1, Befund 2)
    $stand = Get-BibliothekStand
    $j = if ($stand) { $stand.Daten } else { $null }
    $inv = if ($stand) { Get-NeuesteInventur 'Sample' } else { $null }
    $tInv = if ($stand) { $stand.Zeit } else { $null }
    $script:bibVeraltet = $false
    if ($stand) {
        try {
            $ui.KpiSamples.Text = '{0:N0}' -f [int]$j.Samples
            $ui.KpiPacks.Text = '{0:N0}' -f [int]$j.Packs
            $ui.KpiGroesse.Text = $(if ([double]$j.GroesseGB -ge 10) { '{0:N0} GB' -f [double]$j.GroesseGB } else { '{0:N1} GB' -f [double]$j.GroesseGB })
        } catch { $j = $null }
        $danach = @()
        if ($tSort -and $tSort -gt $tInv) { $danach += 'sortiert' }
        if ($tImp -and $tImp -gt $tInv) { $danach += 'importiert' }
        if ($tLetzt -and $tLetzt -gt $tInv) { $danach += 'aufgeräumt' }
        if ($danach.Count) {
            $script:bibVeraltet = $true
            $ui.TxtBibStand.Text = "Stand $(Format-Zeit $tInv) · seitdem $($danach -join ', ') – neu einlesen empfohlen"
            $ui.TxtBibStand.Foreground = $SWF.Warn
        } else {
            $ui.TxtBibStand.Text = "Stand $(Format-Zeit $tInv) · auf dem Stand"
            $ui.TxtBibStand.Foreground = $SWF.Leise
        }
    } else {
        $ui.KpiSamples.Text = $strich; $ui.KpiPacks.Text = $strich; $ui.KpiGroesse.Text = $strich
        $ui.TxtBibStand.Text = 'Noch nicht eingelesen – „Bibliothek öffnen“ liest das Ziel ein.'
        $ui.TxtBibStand.Foreground = $SWF.Leise
    }
    $ui.LnkExcel.IsEnabled = [bool]$inv
    $ui.BtnZielDup.IsEnabled = ([bool]$inv -and -not (Test-LaufAktiv))
    # Aenderungen beim letzten Einlesen (Vergleich mit dem Stand davor)
    $ui.BibAenderungen.Children.Clear()
    $vgl = if ($stand) { Get-NeuesterVergleich } else { $null }
    $zeilen = @()
    if ($vgl) {
        # Zaehlung zwischenspeichern: der Vergleich kann viele tausend Zeilen haben
        $sch = "$($vgl.FullName)|$($vgl.LastWriteTime.Ticks)"
        if ($script:vglCache.Schluessel -ne $sch) {
            $zn = @{ neu = 0; entfernt = 0; verschoben = 0 }
            try { foreach ($r in (Import-Csv -LiteralPath $vgl.FullName -Delimiter ';' -Encoding UTF8)) { if ($zn.ContainsKey([string]$r.Vergleich)) { $zn[[string]$r.Vergleich]++ } } } catch { }
            $script:vglCache = @{ Schluessel = $sch; Werte = $zn }
        }
        $zn = $script:vglCache.Werte
        $zeilen += , @('Neue Samples', $zn.neu)
        $zeilen += , @('Entfernt', $zn.entfernt)
        $zeilen += , @('Verschoben', $zn.verschoben)
    }
    if ($j) { $zeilen += , @('Duplikate (Dateien)', [int]$j.DuplikatDateien) }
    if (-not $zeilen.Count) {
        $tb = New-Object System.Windows.Controls.TextBlock; $tb.Text = 'Der Vergleich entsteht ab dem zweiten Einlesen.'; $tb.Foreground = $SWF.Leise; $tb.TextWrapping = 'Wrap'
        [void]$ui.BibAenderungen.Children.Add($tb)
    }
    $erste = $true
    foreach ($z in $zeilen) {
        $b = New-Object System.Windows.Controls.Border; $b.BorderBrush = $SWF.Linie; $b.BorderThickness = $(if ($erste) { '0' } else { '0,1,0,0' }); $b.Padding = '0,5'; $erste = $false
        $d = New-Object System.Windows.Controls.DockPanel
        $w = New-Object System.Windows.Controls.TextBlock; $w.Text = '{0:N0}' -f [int]$z[1]; $w.FontWeight = 'SemiBold'
        [System.Windows.Controls.DockPanel]::SetDock($w, 'Right')
        $k = New-Object System.Windows.Controls.TextBlock; $k.Text = $z[0]
        [void]$d.Children.Add($w); [void]$d.Children.Add($k); $b.Child = $d
        [void]$ui.BibAenderungen.Children.Add($b)
    }
    $ui.LnkAenderungen.IsEnabled = [bool]$vgl

    # --- Desktop-Verknuepfung
    $lz = ''
    if (Test-Path -LiteralPath $verknuepfung) { try { $lz = (New-Object -ComObject WScript.Shell).CreateShortcut($verknuepfung).Arguments } catch { } }
    if (-not (Test-Path -LiteralPath $verknuepfung)) { $ui.LnkVerknuepfung.Content = 'Desktop-Verknüpfung anlegen'; $ui.LnkVerknuepfung.Visibility = 'Visible' }
    elseif ($lz -like "*$skriptOrdner*") { $ui.LnkVerknuepfung.Visibility = 'Collapsed' }
    else { $ui.LnkVerknuepfung.Content = "Desktop-Verknüpfung auf $ProgrammVersion umstellen"; $ui.LnkVerknuepfung.Visibility = 'Visible' }

    if (Test-LaufAktiv) { Set-Bedienbar $false }
    Update-SchrittAussehen
    Update-LogHoehe
}

# ---------------------------------------------------------------------------
# Sample-Bibliothek oeffnen: vorher fragen, ob das Ziel neu eingelesen werden soll
# ---------------------------------------------------------------------------
function Show-BibliothekOeffnen {
    $zs = Get-OrdnerStatus (Get-Einstellungen).Ziel
    $stand = Get-BibliothekStand
    $inv = if ($stand) { Get-NeuesteInventur 'Sample' } else { $null }
    if (-not $inv -and ($zs.Fehlt -or $zs.Text -ne 'vorhanden')) { Show-Meldung "Der Zielordner ist nicht vorhanden:`n$((Get-Einstellungen).Ziel)`n`nBitte zuerst sortieren oder über $([char]0x2699) Einstellungen den richtigen Ordner wählen." 'Warning'; return }
    $d = [Windows.Markup.XamlReader]::Parse($xamlBib)
    $d.Owner = $win
    $dT = $d.FindName('DTitel'); $dX = $d.FindName('DText'); $dW = $d.FindName('DWarn'); $dWR = $d.FindName('DWarnRahmen')
    $bAlt = $d.FindName('DAlt'); $bNeu = $d.FindName('DNeu')
    $script:bibWahl = ''
    $bAlt.Add_Click({ $script:bibWahl = $(if ($bAlt.Tag) { [string]$bAlt.Tag } else { '' }); $d.Close() })
    $bNeu.Add_Click({ $script:bibWahl = 'neu'; $d.Close() })
    $haupt = { param($b) $b.Background = $SWF.Akzent; $b.Foreground = $SWF.Weiss; $b.BorderBrush = $SWF.Akzent; $b.FontWeight = 'SemiBold'; $b.IsDefault = $true }
    if (-not $inv) {
        $dT.Text = 'Bibliothek einlesen?'
        $dX.Text = 'Die Sample-Bibliothek wurde noch nicht eingelesen. Beim Einlesen werden alle Samples im Ziel erfasst (Audio-Eigenschaften, Tempo, Tonart, Pack-Art, Duplikate); danach öffnet sie sich im Browser.'
        $dWR.Visibility = 'Collapsed'
        $bAlt.Content = 'Abbrechen'; $bAlt.Tag = ''; $bAlt.IsCancel = $true
        $bNeu.Content = 'Einlesen und öffnen'; & $haupt $bNeu
    } else {
        $tInv = $stand.Zeit
        $dT.Text = 'Neu einlesen?'
        $dX.Text = "Der letzte Stand ist vom $(Format-Zeit $tInv)."
        if ($script:bibVeraltet) {
            $dW.Text = 'Seitdem wurde sortiert, importiert oder aufgeräumt. Neue oder entfernte Samples erscheinen erst nach dem Einlesen.'
            $bNeu.Content = 'Neu einlesen und öffnen'; $bAlt.Content = 'Letzten Stand öffnen'; $bAlt.Tag = 'alt'
            & $haupt $bNeu
        } else {
            $dW.Text = 'Seit dem letzten Einlesen wurde nichts sortiert, importiert oder aufgeräumt. Neu einlesen ist nur nötig, wenn du selbst etwas im Ziel geändert hast.'
            $bNeu.Content = 'Neu einlesen und öffnen'; $bAlt.Content = 'Letzten Stand öffnen'; $bAlt.Tag = 'alt'
            & $haupt $bAlt
        }
    }
    [void]$d.ShowDialog()
    switch ($script:bibWahl) {
        'alt' { Open-Bericht }
        'neu' { [void](Start-Skript 'Inventur.ps1' '' 'Sample-Bibliothek einlesen' { Open-Bericht }) }
    }
}

# ---------------------------------------------------------------------------
# Knoepfe
# ---------------------------------------------------------------------------
Set-Klick $ui.BtnImport { Show-DownloadImport }
Set-Klick $ui.BtnFundorte { Show-FundorteSuchen }
Set-Klick $ui.BtnQuellen { Show-Einstellungen }
Set-Klick $ui.BtnSortieren { if (Test-OrdnerBereit) { [void](Start-Skript 'Samples-sortieren.ps1' '' 'Samples sortieren') } }
Set-Klick $ui.BtnZielOeffnen { Open-Pfad (Get-Einstellungen).Ziel }
Set-Klick $ui.LnkSortProt { $p = Get-NeuestesProtokoll 'Protokoll_*.csv' @((Get-ZielProtokollOrdner (Get-Einstellungen).Ziel), $protokollOrdner); if ($p) { Open-Pfad $p.FullName } else { Show-Meldung 'Noch kein Sortierlauf mit dieser Version.' 'Warning' } }
Set-Klick $ui.LnkImportProt { $p = Get-NeuestesProtokoll 'Import-Protokoll_*.csv' @((Get-ZielProtokollOrdner (Get-Einstellungen).Ziel), $protokollOrdner); if ($p) { Open-Pfad $p.FullName } else { Show-Meldung 'Noch kein Import mit dieser Version.' 'Warning' } }
Set-Klick $ui.BtnQuelleAuf { Show-QuelleAufraeumen }
Set-Klick $ui.BtnZielDup { Show-ZielAufraeumen }
Set-Klick $ui.LnkPapierkorb { try { Start-Process explorer.exe 'shell:RecycleBinFolder' } catch { } }
Set-Klick $ui.BtnBibliothek { Show-BibliothekOeffnen }
# 4.1 (INV-11): neu einlesen nach einer Aenderung im Ziel; Haken "automatisch" an zwei Stellen, gemeinsam gespeichert
Set-Klick $ui.BtnBibJa { $ui.BibFrage.Visibility = 'Collapsed'; [void](Start-Skript 'Inventur.ps1' '' 'Sample-Bibliothek einlesen' $null -Anhaengen) }
Set-Klick $ui.BtnBibNein { $ui.BibFrage.Visibility = 'Collapsed'; Update-LogHoehe }
$script:bibAutoSetzen = $false
function Set-BibAuto([bool]$an) {
    if ($script:bibAutoSetzen) { return }
    $script:bibAutoSetzen = $true
    try {
        $ui.ChkBibAuto1.IsChecked = $an; $ui.ChkBibAuto2.IsChecked = $an
        try { Set-Einstellung 'BibliothekAutomatisch' $an }
        catch { $ui.ChkBibAuto1.IsChecked = -not $an; $ui.ChkBibAuto2.IsChecked = -not $an; throw }   # 4.1.1 (Befund 6): Anzeige = gespeicherte Einstellung
    } finally { $script:bibAutoSetzen = $false }
}
foreach ($cb in @($ui.ChkBibAuto1, $ui.ChkBibAuto2)) {
    $cb.Add_Checked({ Invoke-Sicher { Set-BibAuto $true } })
    $cb.Add_Unchecked({ Invoke-Sicher { Set-BibAuto $false } })
}
$script:bibAutoSetzen = $true
$ui.ChkBibAuto1.IsChecked = [bool](Get-Einstellungen).BibliothekAutomatisch; $ui.ChkBibAuto2.IsChecked = $ui.ChkBibAuto1.IsChecked
$script:bibAutoSetzen = $false
Set-Klick $ui.LnkExcel { $c = Get-NeuesteInventur 'Sample'; if ($c) { Open-Pfad $c.FullName } else { Show-Meldung 'Die Bibliothek wurde noch nicht eingelesen.' 'Warning' } }
Set-Klick $ui.LnkAenderungen { $c = Get-NeuesterVergleich; if ($c) { Open-Pfad $c.FullName } else { Show-Meldung 'Noch kein Vergleich vorhanden (entsteht ab dem zweiten Einlesen).' 'Warning' } }
Set-Klick $ui.LnkPackArten {
    if (-not (Test-Path -LiteralPath $packArtenPfad)) { Set-Content -LiteralPath $packArtenPfad -Value 'Pack;Pack-Art' -Encoding UTF8 }
    Show-Meldung ("Eine Zeile je Pack: Name des Packs (wie in der Bibliothek), Semikolon, Pack-Art.`nBeispiel:  Forest Ambience Vol 1;Atmos/Field Recording`n`nMögliche Pack-Arten:`n" + ($PackArten -join ', ') + "`n`nDie Korrektur gilt ab dem nächsten Einlesen.")
    Open-Pfad $packArtenPfad
}
Set-Klick $ui.BtnEinstellungen { Show-Einstellungen }
Set-Klick $ui.BtnDoku { Open-Pfad $dokuPfad }
Set-Klick $ui.LnkProtokolle { Open-Pfad $protokollOrdner }
Set-Klick $ui.LnkProgramm { Open-Pfad $basis }
Set-Klick $ui.LnkVerknuepfung { New-DesktopVerknuepfung }
$ui.BtnSchliessen.Add_Click({ $win.Close() })

# Schliessen waehrend eines Laufs: nur nach Rueckfrage (halb kopierte Dateien vermeiden)
$win.Add_Closing({ param($s, $ev)
    if (Test-LaufAktiv) {
        $j = [System.Windows.MessageBox]::Show('Es läuft noch ein Vorgang. Wird das Programm jetzt geschlossen, bricht er ab; dabei können halb kopierte Dateien zurückbleiben.' + "`n`n" + 'Trotzdem schließen?', 'Samples-Werkzeuge', 'YesNo', 'Warning', 'No')
        if ($j -ne 'Yes') { $ev.Cancel = $true; return }
        try { $script:lauf.Beenden() } catch { }
    }
    $zeitgeber.Stop()
})

$win.Add_SourceInitialized({
    try {
        $script:form = New-Object SamplesWerkzeuge.Besitzer400
        $script:form.Handle = (New-Object System.Windows.Interop.WindowInteropHelper($win)).Handle
    } catch { $script:form = $null }
})
$win.Add_Activated({ if (-not (Test-LaufAktiv)) { Invoke-Sicher { Update-Status } } })

$einst = Get-Einstellungen
$win.Add_ContentRendered({
    # Empfohlener Schritt: der erste, bei dem etwas zu tun ist
    Invoke-Sicher {
        Update-Status
        $n = 2
        foreach ($i in 1..3) { if ($script:schrittZustand[$i] -in 'warn', 'fehler') { $n = $i; break } }
        Set-Schritt $n
        if (-not $einst.ErsterStartErledigt) { Show-Begruessung }
    }
})

# Unerwartete Fehler in der Oberflaeche: melden und weiterarbeiten statt abzustuerzen
$win.Dispatcher.Add_UnhandledException({ param($s, $ev)
    Write-FehlerLog "Oberfläche (unbehandelt): $($ev.Exception.Message)"
    $ev.Handled = $true
    try { Show-Meldung "Es ist ein Fehler aufgetreten:`n$($ev.Exception.Message)`n`nDetails stehen in $fehlerLog." 'Error' } catch { }
})

try {
    Set-Schritt 2
    [void]$win.ShowDialog()
} catch {
    Write-FehlerLog ("FEHLER: " + $_.Exception.Message + ' | ' + ($_.InvocationInfo.PositionMessage -replace "`r?`n", ' '))
    [void][System.Windows.Forms.MessageBox]::Show("Unerwarteter Fehler:`n$($_.Exception.Message)`n`nDetails stehen in:`n$fehlerLog", 'Samples-Werkzeuge', 'OK', 'Error')
} finally {
    $zeitgeber.Stop()
}
