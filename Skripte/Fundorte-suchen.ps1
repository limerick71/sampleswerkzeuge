# (c) 2026 Herbert Stoecker. Kostenlos nutzbar. Bitte nur als Link auf die offizielle Download-Seite weitergeben; Verkauf und Veroeffentlichung geaenderter Fassungen nur mit Zustimmung.
<#
.SYNOPSIS
  Fundorte suchen (QLN-01 bis QLN-03): findet auf Laufwerken und in Ordnern alle Stellen mit
  Audiodateien, fasst sie zu Fundorten zusammen, schaetzt ein, worum es sich handelt, und zeigt das
  Ergebnis als Bericht im Browser. Dort lassen sich Fundorte als Quellen uebernehmen.

  Es wird nichts veraendert: gelesen werden Ordnernamen, Dateinamen, Groessen und Datum, bei Archiven
  (ZIP, mit Windows 11 auch RAR/7z) zusaetzlich das Inhaltsverzeichnis - entpackt wird nichts.
  Dateien, die nur in der Cloud liegen (OneDrive "bei Bedarf"), werden nicht heruntergeladen,
  sondern gezaehlt. Ordner-Verknuepfungen werden nicht verfolgt.

.BENUTZUNG
    -Orte "C:\Users\HS\Downloads|E:\"   Wo gesucht wird (Trennzeichen |)
    -KeinBrowser                        Bericht nicht oeffnen
    -OhneArchivinhalt                   nicht in Archive hineinschauen (schneller)
    -LetzterBericht                     keinen Suchlauf, den letzten Bericht oeffnen
#>
[CmdletBinding()]
param(
    [string]$Orte,
    [switch]$KeinBrowser,
    [switch]$OhneArchivinhalt,
    [switch]$LetzterBericht
)

$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'Gemeinsam.ps1')
. (Join-Path $PSScriptRoot 'Fundorte-Bericht.ps1')

# 2.3.2: letzten Bericht ohne neuen Suchlauf oeffnen (ueber den Dienst, damit Ordner oeffnen, Abgleich und Uebernehmen gehen)
if ($LetzterBericht) {
    $j = Get-LetzterFundortBericht
    if (-not $j) { throw 'Es gibt noch keinen Fundort-Bericht. Bitte zuerst einen Suchlauf starten.' }
    Write-Host "Oeffne den Bericht vom $($j.LastWriteTime.ToString('dd.MM.yyyy HH:mm')): $($j.FullName)"
    if (-not $KeinBrowser) { [void](Start-FundortBericht $j.FullName) }
    return
}
$Zeitstempel = Get-Date -Format 'yyyy-MM-dd_HHmmss'
$einst = Get-Einstellungen
$start = Get-Date
Write-Host "Fundorte suchen (Samples-Werkzeuge $ProgrammVersion)" -ForegroundColor Cyan

$wurzeln = @($Orte -split '\|' | Where-Object { $_.Trim() } | ForEach-Object { $_.Trim() })
if (-not $wurzeln.Count) { throw 'Es ist kein Ort zum Durchsuchen angegeben.' }
$wurzeln = @(foreach ($w in $wurzeln) {
    if (Test-Path -LiteralPath $w) { $v = (Resolve-Path -LiteralPath $w).ProviderPath; if ($v.Length -gt 3) { $v.TrimEnd('\', '/') } else { $v } }
    else { Write-Host "  nicht gefunden, wird ausgelassen: $w" -ForegroundColor Yellow }
})
if (-not $wurzeln.Count) { throw 'Keiner der angegebenen Orte wurde gefunden.' }
# Orte, die in einem anderen gewaehlten Ort liegen, nicht doppelt durchsuchen
$wurzeln = @($wurzeln | Where-Object { $w = $_.TrimEnd('\', '/') + [IO.Path]::DirectorySeparatorChar
    -not @($wurzeln | Where-Object { $a = $_.TrimEnd('\', '/') + [IO.Path]::DirectorySeparatorChar; $a -ne $w -and $w.StartsWith($a, [StringComparison]::OrdinalIgnoreCase) }).Count } | Select-Object -Unique)
foreach ($w in $wurzeln) { Write-Host "  durchsuche: $w" }
Write-Host ""

# ---------------------------------------------------------------------------
# Ausgeschlossen: System- und Programmordner, Anwendungsdaten, Ziel, Programmordner
# ---------------------------------------------------------------------------
$aus = New-Object System.Collections.Generic.List[string]
foreach ($v in @($env:windir, $env:ProgramFiles, ${env:ProgramFiles(x86)}, $env:ProgramData, $env:APPDATA, $env:LOCALAPPDATA)) { if ($v) { $aus.Add($v.TrimEnd('\')) } }
foreach ($lw in [IO.DriveInfo]::GetDrives()) {
    foreach ($n in '$Recycle.Bin', 'System Volume Information', 'Recovery', 'PerfLogs', 'Config.Msi', 'MSOCache', 'Windows', 'Program Files', 'Program Files (x86)', 'ProgramData') {
        $aus.Add((Join-Path $lw.RootDirectory.FullName $n))
    }
}
if ($env:USERPROFILE) { $aus.Add((Join-Path $env:USERPROFILE 'AppData')) }
$aus.Add($einst.Ziel.TrimEnd('\', '/'))
$aus.Add($wurzel.TrimEnd('\', '/'))
# Ausschluesse, die selbst Suchort sind, gelten nicht (wer C:\Program Files ausdruecklich waehlt, bekommt es)
$aus = @($aus | Where-Object { $a = $_; -not @($wurzeln | Where-Object { $_ -ieq $a }).Count } | Select-Object -Unique)

# ---------------------------------------------------------------------------
# Schneller Suchlauf (C#): je Ordner Zahl und Groesse der Audiodateien, Formate, Datum,
# Merkmale fuer Projekte und Instrument-Bibliotheken, Archive, Cloud-Dateien
# ---------------------------------------------------------------------------
# Typname mit Versionsnummer: eine geaenderte Fassung laesst sich in derselben Sitzung neu laden
Add-Type -AssemblyName System.IO.Compression
# Verweise: Windows PowerShell 5.1 braucht System.IO.Compression ausdruecklich; dann alle benoetigten
# angeben (System, System.Core). PowerShell 7 hat alle Standardverweise schon.
$verweise = @()
if ($PSVersionTable.PSEdition -ne 'Core') {
    $verweise = @([System.IO.Compression.ZipArchive], [System.Diagnostics.Process], [System.Collections.Generic.HashSet[string]] |
        ForEach-Object { $_.Assembly.Location } | Where-Object { $_ } | Select-Object -Unique)
}
if (-not ('SamplesWerkzeuge.FundortScanner235' -as [type])) {
    $atArg = @{ Language = 'CSharp' }; if ($verweise.Count) { $atArg.ReferencedAssemblies = $verweise }
    Add-Type @atArg -TypeDefinition @'
using System;
using System.IO;
using System.IO.Compression;
using System.Diagnostics;
using System.Text.RegularExpressions;
using System.Collections.Generic;
namespace SamplesWerkzeuge {
    public class OrdnerInfo235 {
        public string Pfad; public int Audio; public long Bytes; public int Archive; public int Projekt; public int Instrument;
        public int Cloud; public DateTime Neu; public string Formate; public string Beispiele;
        // 2.3.4: Ableton-Presets (.adg/.adv/.alc) sind Zeichen fuer ein Sample-Pack; DawAudio setzt das Skript
        public int AbletonPreset; public int DawAudio;
        // Archive (2.3.2): nur Archive mit Audiodateien, nicht lesbare und verschachtelte zaehlen in "Archive"
        public int ZAudio; public long ZBytes; public int ZCloud; public int ZOffen; public int ZVerschachtelt; public int ZOhneAudio;
        public string ZFormate; public string ZListe;
    }
    public class ArchivInhalt { public bool Gelesen; public string Grund = ""; public int Audio; public long Bytes; public int Archive; public SortedSet<string> Formate = new SortedSet<string>(); }
    public static class FundortScanner235 {
        public static int Ordner; public static int NichtLesbar; public static int ArchiveGelesen;
        public static bool ArchiveLesen = true; public static bool TarLesen = false;
        public static readonly HashSet<string> AudioExt = new HashSet<string>(new string[] { ".wav", ".aif", ".aiff", ".mp3", ".flac", ".ogg", ".rx2", ".rex", ".m4a" }, StringComparer.OrdinalIgnoreCase);
        static readonly HashSet<string> ProjektExt = new HashSet<string>(new string[] { ".als", ".flp", ".cpr", ".ptx", ".ptf", ".song", ".rpp", ".bwproject", ".aup", ".aup3", ".npr", ".reason", ".logicx" }, StringComparer.OrdinalIgnoreCase);
        static readonly HashSet<string> InstrExt = new HashSet<string>(new string[] { ".nki", ".nkx", ".nkc", ".nkr", ".nicnt", ".ncw", ".nkm", ".nkb", ".ens", ".exs", ".gig", ".sf2", ".ufs", ".zmulti", ".nksn", ".hsb", ".vstpreset" }, StringComparer.OrdinalIgnoreCase);
        static readonly HashSet<string> ArchivExt = new HashSet<string>(new string[] { ".zip", ".rar", ".7z" }, StringComparer.OrdinalIgnoreCase);
        static readonly HashSet<string> AbletonPresetExt = new HashSet<string>(new string[] { ".adg", ".adv", ".alc", ".alp", ".ask" }, StringComparer.OrdinalIgnoreCase);
        const FileAttributes CloudBits = (FileAttributes)0x400000 | (FileAttributes)0x40000 | FileAttributes.Offline;
        static readonly Regex TarZeile = new Regex(@"^(\S)\S*\s+\d+\s+\S+\s+\S+\s+(\d+)\s+\S+\s+\d+\s+\S+\s+(.+)$");

        // Lange Pfade (2.3.3): Windows PowerShell 5.1 braucht den Vorsatz \\?\ ab etwa 260 Zeichen
        static string L(string p) {
            if (Path.DirectorySeparatorChar != '\\' || p.Length < 240 || p.StartsWith(@"\\?\")) return p;
            return p.StartsWith(@"\\") ? @"\\?\UNC\" + p.Substring(2) : @"\\?\" + p;
        }
        static string K(string p) {
            if (p.StartsWith(@"\\?\UNC\")) return @"\\" + p.Substring(8);
            if (p.StartsWith(@"\\?\")) return p.Substring(4);
            return p;
        }
        static bool Ausgeschlossen(string pfad, string[] aus) {
            foreach (string a in aus) {
                if (string.Equals(pfad, a, StringComparison.OrdinalIgnoreCase)) return true;
            }
            return false;
        }

        // 2.3.4: Endung und Dateiname ohne Path.GetExtension - das bricht unter Windows PowerShell 5.1 bei
        // Zeichen ab, die in Archiven vorkommen duerfen (z. B. " < > | oder Steuerzeichen)
        static string Ext(string name) {
            int s = Math.Max(name.LastIndexOf('/'), name.LastIndexOf('\\'));
            int d = name.LastIndexOf('.');
            if (d <= s || d >= name.Length - 1) return "";
            return name.Substring(d);
        }
        static string DateiName(string name) {
            string n = name.TrimEnd('/', '\\');
            int s = Math.Max(n.LastIndexOf('/'), n.LastIndexOf('\\'));
            return s >= 0 ? n.Substring(s + 1) : n;
        }
        static bool MacRest(string name) { return name.StartsWith("._") || string.Equals(name, ".DS_Store", StringComparison.OrdinalIgnoreCase); }
        static string Kurz(string t) { t = (t ?? "").Replace("|", "/").Replace("\r", " ").Replace("\n", " ").Trim(); return t.Length > 120 ? t.Substring(0, 120) + " ..." : t; }

        static void Zaehle(ArchivInhalt r, string name, long laenge) {
            string ext = Ext(name);
            if (string.IsNullOrEmpty(ext)) return;
            string datei = DateiName(name);
            if (name.IndexOf("__MACOSX", StringComparison.OrdinalIgnoreCase) >= 0 || MacRest(datei)) return;
            if (AudioExt.Contains(ext)) { r.Audio++; r.Bytes += laenge; r.Formate.Add(ext.TrimStart('.').ToUpperInvariant()); }
            else if (ArchivExt.Contains(ext)) r.Archive++;
        }

        // Liest nur das Inhaltsverzeichnis; es wird nichts entpackt und nichts veraendert.
        public static ArchivInhalt LeseArchiv(string pfad) {
            ArchivInhalt r = new ArchivInhalt();
            string ext = Ext(pfad);
            try {
                if (string.Equals(ext, ".zip", StringComparison.OrdinalIgnoreCase)) {
                    using (FileStream fs = new FileStream(L(pfad), FileMode.Open, FileAccess.Read, FileShare.ReadWrite))
                    using (ZipArchive z = new ZipArchive(fs, ZipArchiveMode.Read)) {
                        // 2.3.4: ein ungewoehnlicher Eintrag bricht nicht mehr das ganze Archiv ab
                        foreach (ZipArchiveEntry e in z.Entries) { try { Zaehle(r, e.FullName, e.Length); } catch (Exception) { } }
                    }
                    r.Gelesen = true;
                } else if (!TarLesen) {
                    r.Grund = "RAR/7z: kein passendes Windows-Werkzeug (erst ab Windows 11 eingebaut)";
                } else {
                    ProcessStartInfo si = new ProcessStartInfo("tar", "-tvf \"" + pfad + "\"");
                    si.UseShellExecute = false; si.RedirectStandardOutput = true; si.RedirectStandardError = true; si.CreateNoWindow = true;
                    si.StandardOutputEncoding = System.Text.Encoding.UTF8;
                    System.Text.StringBuilder fehler = new System.Text.StringBuilder();
                    using (Process p = Process.Start(si)) {
                        p.ErrorDataReceived += delegate(object o, DataReceivedEventArgs a) { if (a.Data != null && fehler.Length < 2000) fehler.AppendLine(a.Data); };
                        p.BeginErrorReadLine();
                        string zeile;
                        while ((zeile = p.StandardOutput.ReadLine()) != null) {
                            Match m = TarZeile.Match(zeile);
                            if (m.Success) { if (m.Groups[1].Value != "d") Zaehle(r, m.Groups[3].Value, long.Parse(m.Groups[2].Value)); }
                            else Zaehle(r, zeile.Trim(), 0);
                        }
                        if (!p.WaitForExit(60000)) { try { p.Kill(); } catch (Exception) { } r.Grund = "Zeitüberschreitung beim Lesen"; return r; }
                        p.WaitForExit();
                        r.Gelesen = (p.ExitCode == 0);
                        if (!r.Gelesen) {
                            string f = fehler.ToString().ToLowerInvariant();
                            if (f.Contains("encrypt") || f.Contains("passphrase") || f.Contains("password")) r.Grund = "verschlüsselt (Kennwort nötig)";
                            else if (f.Contains("truncated") || f.Contains("unexpected end") || f.Contains("damaged") || f.Contains("premature")) r.Grund = "unvollständig oder beschädigt (Download abgebrochen?)";
                            else if (f.Contains("unrecognized") || f.Contains("not supported") || f.Contains("unsupported")) r.Grund = "Format wird vom Windows-Werkzeug nicht unterstützt";
                            else r.Grund = "nicht lesbar: " + Kurz(fehler.ToString());
                        }
                    }
                }
            } catch (InvalidDataException) { r.Gelesen = false; r.Grund = "keine gültige ZIP-Datei (Download unvollständig oder beschädigt?)"; }
            catch (ArgumentException ex) {
                // 2.3.5: Windows PowerShell 5.1 bricht beim Inhaltsverzeichnis ab, wenn ein Eintrag Zeichen wie " < > | enthaelt
                // ("Illegales Zeichen im Pfad") - dann das Verzeichnis der ZIP-Datei selbst lesen
                ArchivInhalt r2 = new ArchivInhalt();
                bool ok = false; try { ok = LeseZipVerzeichnis(pfad, r2); } catch (Exception) { ok = false; }
                if (ok) { r2.Gelesen = true; return r2; }
                r.Gelesen = false; r.Grund = "nicht lesbar: " + Kurz(ex.Message);
            }
            catch (UnauthorizedAccessException) { r.Gelesen = false; r.Grund = "kein Zugriff"; }
            catch (IOException ex) { r.Gelesen = false; r.Grund = "gesperrt oder nicht lesbar: " + Kurz(ex.Message); }
            catch (Exception ex) { r.Gelesen = false; r.Grund = "nicht lesbar: " + Kurz(ex.Message); }
            return r;
        }

        static uint U16(byte[] b, long i) { return (uint)(b[i] | (b[i + 1] << 8)); }
        static uint U32(byte[] b, long i) { return (uint)(b[i] | (b[i + 1] << 8) | (b[i + 2] << 16) | (b[i + 3] << 24)); }
        static ulong U64(byte[] b, long i) { return (ulong)U32(b, i) | ((ulong)U32(b, i + 4) << 32); }
        static void Lies(FileStream fs, long pos, byte[] b) {
            fs.Seek(pos, SeekOrigin.Begin); int n = 0;
            while (n < b.Length) { int k = fs.Read(b, n, b.Length - n); if (k <= 0) throw new EndOfStreamException(); n += k; }
        }
        // 2.3.5: zentrales Verzeichnis einer ZIP-Datei selbst lesen (Namen und Groessen, auch ZIP64); nichts wird entpackt
        public static bool LeseZipVerzeichnis(string pfad, ArchivInhalt r) {
            using (FileStream fs = new FileStream(L(pfad), FileMode.Open, FileAccess.Read, FileShare.ReadWrite)) {
                long len = fs.Length; if (len < 22) return false;
                int max = (int)Math.Min(len, 65557L); byte[] e = new byte[max]; Lies(fs, len - max, e);
                long i = -1;
                for (long k = max - 22; k >= 0; k--) { if (U32(e, k) == 0x06054b50) { i = k; break; } }
                if (i < 0) return false;
                ulong anzahl = U16(e, i + 10), groesse = U32(e, i + 12), start = U32(e, i + 16);
                if (anzahl == 0xFFFF || groesse == 0xFFFFFFFF || start == 0xFFFFFFFF) {
                    if (i < 20 || U32(e, i - 20) != 0x07064b50) return false;
                    byte[] z = new byte[56]; Lies(fs, (long)U64(e, i - 20 + 8), z);
                    if (U32(z, 0) != 0x06064b50) return false;
                    anzahl = U64(z, 32); groesse = U64(z, 40); start = U64(z, 48);
                }
                if (groesse > 256UL * 1024 * 1024 || start + groesse > (ulong)len) return false;
                byte[] v = new byte[(int)groesse]; Lies(fs, (long)start, v);
                System.Text.Encoding alt;
                try { alt = System.Text.Encoding.GetEncoding(437); } catch (Exception) { alt = System.Text.Encoding.GetEncoding("ISO-8859-1"); }
                long p = 0; ulong gelesen = 0;
                while (p + 46 <= v.Length && U32(v, p) == 0x02014b50) {
                    uint flags = U16(v, p + 8); ulong groesseE = U32(v, p + 24);
                    int nl = (int)U16(v, p + 28), xl = (int)U16(v, p + 30), kl = (int)U16(v, p + 32);
                    if (p + 46 + nl + xl > v.Length) break;
                    string name = ((flags & 0x800) != 0 ? System.Text.Encoding.UTF8 : alt).GetString(v, (int)(p + 46), nl);
                    if (groesseE == 0xFFFFFFFF) {
                        long x = p + 46 + nl, xe = x + xl;
                        while (x + 4 <= xe) { uint id = U16(v, x), dl = U16(v, x + 2); if (id == 1 && dl >= 8) { groesseE = U64(v, x + 4); break; } x += 4 + dl; }
                    }
                    try { Zaehle(r, name, (long)groesseE); } catch (Exception) { }
                    gelesen++;
                    p += 46 + nl + xl + kl;
                }
                return gelesen > 0 || anzahl == 0;
            }
        }

        public static List<OrdnerInfo235> Suche(string[] wurzeln, string[] aus) {
            List<OrdnerInfo235> erg = new List<OrdnerInfo235>();
            Ordner = 0; NichtLesbar = 0; ArchiveGelesen = 0;
            Stack<string> stapel = new Stack<string>();
            foreach (string w in wurzeln) stapel.Push(w);
            DateTime letzte = DateTime.Now;
            while (stapel.Count > 0) {
                string d = stapel.Pop();
                Ordner++;
                if ((DateTime.Now - letzte).TotalSeconds >= 5) { Console.WriteLine("  ... " + Ordner.ToString("N0") + " Ordner durchsucht" + (ArchiveGelesen > 0 ? ", " + ArchiveGelesen.ToString("N0") + " Archive angesehen" : "")); letzte = DateTime.Now; }
                OrdnerInfo235 oi = new OrdnerInfo235(); oi.Pfad = d; oi.Neu = DateTime.MinValue;
                SortedSet<string> formate = new SortedSet<string>();
                SortedSet<string> zformate = new SortedSet<string>();
                List<string> beisp = new List<string>();
                List<string> zliste = new List<string>();
                try {
                    foreach (FileSystemInfo e in new DirectoryInfo(L(d)).EnumerateFileSystemInfos()) {
                        FileAttributes at = e.Attributes;
                        if ((at & FileAttributes.Directory) != 0) {
                            if ((at & FileAttributes.ReparsePoint) != 0) continue;
                            // 2.3.4: "Ableton Project Info" allein ist kein Projekt (liegt auch in Packs); es zaehlt nur die .als.
                            // Mac-Reste (__MACOSX) werden nicht durchsucht.
                            if (string.Equals(e.Name, "Ableton Project Info", StringComparison.OrdinalIgnoreCase)) continue;
                            if (string.Equals(e.Name, "__MACOSX", StringComparison.OrdinalIgnoreCase)) continue;
                            if (Ausgeschlossen(K(e.FullName), aus)) continue;
                            stapel.Push(K(e.FullName));
                            continue;
                        }
                        string ext = Ext(e.Name);
                        if (string.IsNullOrEmpty(ext) || MacRest(e.Name)) continue;
                        bool audio = AudioExt.Contains(ext);
                        if (audio) {
                            oi.Audio++;
                            oi.Bytes += ((FileInfo)e).Length;
                            formate.Add(ext.TrimStart('.').ToUpperInvariant());
                            if (beisp.Count < 5) beisp.Add(e.Name);
                            if ((at & CloudBits) != 0) oi.Cloud++;
                            if (e.LastWriteTime > oi.Neu) oi.Neu = e.LastWriteTime;
                        } else if (ProjektExt.Contains(ext)) oi.Projekt++;
                        else if (InstrExt.Contains(ext)) oi.Instrument++;
                        else if (AbletonPresetExt.Contains(ext)) oi.AbletonPreset++;
                        else if (ArchivExt.Contains(ext)) {
                            string zeile = null;
                            if ((at & CloudBits) != 0) { oi.ZCloud++; oi.Archive++; zeile = e.Name + "|c|0|0"; }
                            else if (!ArchiveLesen) { oi.ZOffen++; oi.Archive++; zeile = e.Name + "|o|0|0"; }
                            else {
                                ArchiveGelesen++;
                                ArchivInhalt r = LeseArchiv(K(e.FullName));
                                if (!r.Gelesen) { oi.ZOffen++; oi.Archive++; zeile = e.Name + "|o|0|0|" + r.Grund; }
                                else if (r.Audio == 0 && r.Archive == 0) { oi.ZOhneAudio++; }
                                else {
                                    oi.Archive++; oi.ZAudio += r.Audio; oi.ZBytes += r.Bytes;
                                    if (r.Archive > 0) oi.ZVerschachtelt++;
                                    foreach (string f in r.Formate) zformate.Add(f);
                                    zeile = e.Name + "|" + (r.Archive > 0 ? "v" : "a") + "|" + r.Audio + "|" + r.Bytes;
                                }
                            }
                            if (zeile != null) {
                                if (e.LastWriteTime > oi.Neu) oi.Neu = e.LastWriteTime;
                                if (zliste.Count < 20) zliste.Add(zeile);
                            }
                        }
                    }
                } catch (Exception) { NichtLesbar++; }
                if (oi.Audio > 0 || oi.Projekt > 0 || oi.Instrument > 0 || oi.Archive > 0 || oi.AbletonPreset > 0) {
                    oi.Formate = string.Join(",", formate); oi.Beispiele = string.Join("|", beisp);
                    oi.ZFormate = string.Join(",", zformate); oi.ZListe = string.Join("\n", zliste);
                    erg.Add(oi);
                }
            }
            return erg;
        }
    }
}
'@
}
# RAR und 7z: nur mit dem in Windows 11 eingebauten tar (bsdtar/libarchive); sonst "Inhalt nicht geprueft"
[SamplesWerkzeuge.FundortScanner235]::ArchiveLesen = -not $OhneArchivinhalt
$tarOk = $false
if (-not $OhneArchivinhalt -and (Get-Command tar -ErrorAction SilentlyContinue)) { try { $tarOk = [bool]((& tar --version 2>$null | Out-String) -match 'bsdtar|libarchive') } catch { } }
[SamplesWerkzeuge.FundortScanner235]::TarLesen = $tarOk
Write-Host ("Durchsuche Ordner (es werden nur Namen und Groessen gelesen{0}) ..." -f $(if ($OhneArchivinhalt) { "" } elseif ($tarOk) { ", bei ZIP/RAR/7z das Inhaltsverzeichnis" } else { ", bei ZIP das Inhaltsverzeichnis" })) -ForegroundColor Cyan
$treffer = [SamplesWerkzeuge.FundortScanner235]::Suche([string[]]$wurzeln, [string[]]$aus)
$ordnerZahl = [SamplesWerkzeuge.FundortScanner235]::Ordner
$nichtLesbar = [SamplesWerkzeuge.FundortScanner235]::NichtLesbar
Write-Host ("  {0:N0} Ordner durchsucht, {1:N0} mit Audiodateien, Projekten oder Archiven" -f $ordnerZahl, $treffer.Count)
$archivZahl = [SamplesWerkzeuge.FundortScanner235]::ArchiveGelesen
if ($archivZahl) { Write-Host ("  {0:N0} Archive angesehen (nur Inhaltsverzeichnis)" -f $archivZahl) }
if ($nichtLesbar) { Write-Host "  $nichtLesbar Ordner waren nicht lesbar und wurden ausgelassen." -ForegroundColor DarkGray }

# ---------------------------------------------------------------------------
# Zusammenfassen: Summen fuer jeden Ordner und alle Elternordner bis zum Suchort
# ---------------------------------------------------------------------------
$sep = [IO.Path]::DirectorySeparatorChar
function Get-Eltern([string]$p) { $e = [IO.Path]::GetDirectoryName($p); if ($e -and $e -ne $p) { return $e } else { return '' } }
function Get-Suchwurzel([string]$p) {
    $t = ''
    foreach ($w in $wurzeln) { $wn = $w.TrimEnd('\', '/'); if (($p -ieq $wn -or $p -ieq $w -or $p.StartsWith($wn + $sep, [StringComparison]::OrdinalIgnoreCase)) -and $w.Length -gt $t.Length) { $t = $w } }
    return $t
}
$SummenFelder = 'Audio', 'Bytes', 'Archive', 'Projekt', 'Instrument', 'Cloud', 'ZAudio', 'ZBytes', 'ZCloud', 'ZOffen', 'ZVerschachtelt', 'AbletonPreset', 'DawAudio'
$knoten = @{}
function Get-Knoten([string]$p) {
    $k = $p.ToLowerInvariant()
    if (-not $knoten.ContainsKey($k)) {
        $n = @{ Pfad = $p; Neu = [DateTime]::MinValue; Formate = @{}; ZFormate = @{}; Kinder = @{}
                Beispiele = New-Object System.Collections.Generic.List[string]; ZListe = New-Object System.Collections.Generic.List[string]; Eigen = @{} }
        foreach ($s in $SummenFelder) { $n[$s] = [long]0; $n.Eigen[$s] = [long]0 }
        $knoten[$k] = $n
    }
    return $knoten[$k]
}
# Audiodateien, die zu einem DAW-Projekt gehoeren (2.3.4, erweitert 2.3.5): neben der Projektdatei, in Aufnahme-/
# Import-Ordnern (Ableton) oder in den typischen Projektordnern unterhalb einer Projektdatei (Cubase: Audio, Edits,
# Mixdown, Freeze; Ableton: Samples; Studio One/Reaper: Media, Mixdown, Bounces)
$DawPfade = '[\\/](Samples[\\/](Recorded|Imported|Processed|Combined|Consolidated)|Live Recordings|Audio Files|Bounces?|Freeze Files)([\\/]|$)'
$DawUnterordner = '^(Audio|Audio Files|Edits|Mixdown|Freeze|Freeze Files|Images|Samples|Media|Bounces?|Recorded|Recordings|Live Recordings|Auto Saves|Backup|Stems)$'
$projektOrdner = @{}
foreach ($t in $treffer) { if ($t.Projekt -gt 0) { $projektOrdner[$t.Pfad.TrimEnd('\', '/').ToLowerInvariant()] = $true } }
# Liegt der Ordner (hoechstens 4 Ebenen) unter einem Ordner mit Projektdatei? Liefert den ersten Ordner darunter (sonst $null)
function Get-ProjektRest([string]$p) {
    $e = $p.TrimEnd('\', '/'); $rest = @()
    for ($i = 0; $i -lt 4; $i++) {
        $rest = @([IO.Path]::GetFileName($e)) + $rest
        $e = [IO.Path]::GetDirectoryName($e)
        if (-not $e) { return $null }
        if ($projektOrdner.ContainsKey($e.TrimEnd('\', '/').ToLowerInvariant())) { return [string]$rest[0] }
    }
    return $null
}
foreach ($t in $treffer) {
    $dw = ($t.Projekt -gt 0 -or $t.Pfad -match $DawPfade)
    if (-not $dw) { $r = Get-ProjektRest $t.Pfad; if ($r -and $r -match $DawUnterordner) { $dw = $true } }
    $t.DawAudio = $(if ($dw) { $t.Audio } else { 0 })
}
foreach ($t in $treffer) {
    $sw = Get-Suchwurzel $t.Pfad
    $n = Get-Knoten $t.Pfad
    foreach ($s in $SummenFelder) { $n.Eigen[$s] += $t.$s }
    if ($t.Beispiele) { $n.EigeneBeispiele = @($t.Beispiele -split '\|') }
    $p = $t.Pfad; $kind = ''
    while ($p) {
        $n = Get-Knoten $p
        foreach ($s in $SummenFelder) { $n[$s] += $t.$s }
        if ($t.Neu -gt $n.Neu) { $n.Neu = $t.Neu }
        foreach ($f in ($t.Formate -split ',')) { if ($f) { $n.Formate[$f] = $true } }
        foreach ($f in ($t.ZFormate -split ',')) { if ($f) { $n.ZFormate[$f] = $true } }
        if ($t.Beispiele -and $n.Beispiele.Count -lt 5) { foreach ($b in ($t.Beispiele -split '\|')) { if ($n.Beispiele.Count -lt 5) { $n.Beispiele.Add($b) } } }
        if ($t.ZListe -and $n.ZListe.Count -lt 20) { foreach ($z in ($t.ZListe -split "`n")) { if ($n.ZListe.Count -lt 20) { $n.ZListe.Add($t.Pfad + $sep + $z) } } }
        if ($kind) { $n.Kinder[$kind.ToLowerInvariant()] = $kind }
        if (-not $sw -or $p -ieq $sw -or $p -ieq $sw.TrimEnd('\', '/')) { break }
        $kind = $p; $p = Get-Eltern $p
    }
}

# ---------------------------------------------------------------------------
# Einschaetzen (QLN-02)
# ---------------------------------------------------------------------------
$InstrNamen = 'Native Instruments|Kontakt|Spitfire|Sonokinetic|Muse ?Hub|Arturia|\bUVI\b|Vienna|\bVSL\b|EastWest|East West|Toontrack|Superior Drummer|EZdrummer|Steinberg|HALion|Komplete|Heavyocity|8Dio|Orchestral Tools|Cinesamples|XLN Audio|Addictive|Spectrasonics|Omnisphere|Keyscape|Trilian|Factory Packs|Core Library|Output Arcade|Soundiron|Impact Soundworks|Best Service|Garritan|Embertone'
# Ableton (2.3.2): eigene und mitgelieferte Klaenge der Ableton-Library; Projektordner mit ihren Unterordnern
$AbletonLibrary = '[\\/](User Library|ABL Assets)([\\/]|$)'
$SystemPfade = @($env:windir, $env:ProgramFiles, ${env:ProgramFiles(x86)}, $env:ProgramData) | Where-Object { $_ }
function Get-Einschaetzung($n) {
    $p = $n.Pfad
    foreach ($s in $SystemPfade) { if ($p.StartsWith($s, [StringComparison]::OrdinalIgnoreCase)) { return 'System/Programm' } }
    if ($p -match $AbletonLibrary) { return 'Ableton-Library' }
    if ($n.Instrument -gt 0 -or $p -match $InstrNamen) { return 'Instrument-Bibliothek' }
    # 2.3.4: DAW-Projekt nur mit Projektdatei (.als, .flp ...) und wenn die Audiodateien ueberwiegend zum Projekt
    # gehoeren; ein Pack mit Demo-Projekt oder Ableton-Presets bleibt ein Sample-Pack
    # 2.3.5: auch ein Ordner innerhalb eines Projekts (z. B. "<Projekt>\Samples" oder "<Projekt>\Audio")
    if (($n.Projekt -gt 0 -or $null -ne (Get-ProjektRest $p)) -and $n.DawAudio * 2 -ge $n.Audio) { return 'DAW-Projekt' }
    if ($n.Audio -eq 0 -and $n.Archive -gt 0) { if ($n.ZAudio -gt 0) { return 'Archive mit Samples' } else { return 'Archive (Inhalt offen)' } }
    return 'Sample-Packs'
}
# Ordner, die nur Behaelter sind (Laufwerk, Benutzerordner, Dokumente ...): nie selbst Fundort
$behaelter = @{}
$benutzerEltern = if ($env:USERPROFILE) { Split-Path -Parent $env:USERPROFILE } else { '' }
foreach ($v in @($env:USERPROFILE, [Environment]::GetFolderPath('MyDocuments'), [Environment]::GetFolderPath('Desktop'), [Environment]::GetFolderPath('MyMusic'), (Get-StandardDownloads), $env:OneDrive, $env:OneDriveConsumer, $env:OneDriveCommercial, $benutzerEltern)) {
    if ($v) { $behaelter[$v.TrimEnd('\', '/').ToLowerInvariant()] = $true }
}
function Test-Behaelter([string]$p) {
    if ([IO.Path]::GetPathRoot($p) -ieq $p -or $p.Length -le 3) { return $true }
    # Gewaehlte Suchorte sind nie selbst Fundort ("dort suchen" heisst nicht "das ist eine Quelle")
    foreach ($w in $wurzeln) { if ($w.TrimEnd('\', '/') -ieq $p.TrimEnd('\', '/')) { return $true } }
    return $behaelter.ContainsKey($p.TrimEnd('\', '/').ToLowerInvariant())
}

# Fundorte von oben nach unten bestimmen
$fundorte = New-Object System.Collections.Generic.List[object]
# 2.3.3: Ebene, auf der die Packs liegen. Hat ein Fundort nur einen Unterordner mit Inhalt (und selbst keine
# Audiodateien), wird bis zur Verzweigung hinabgegangen (z. B. Splice -> Samples -> packs). Sind die Ordner dort
# eigenstaendige Pack-Namen, ist diese Ebene der Fundort (Sammlung); sonst bleibt es beim Ordner selbst
# (ein Pack mit Innenordnern wie "...-WAV", "Loops", "One Shots").
function Get-PackKnoten($n) {
    $w = $n
    for ($i = 0; $i -lt 6; $i++) {
        $k = @($w.Kinder.Values | ForEach-Object { $knoten[$_.ToLowerInvariant()] } | Where-Object { $_ -and $_.Audio -gt 0 })
        if ($w.Eigen.Audio -gt 0 -or $k.Count -ne 1) { break }
        $w = $k[0]
    }
    if ($w -eq $n) { return $n }
    $namen = @($w.Kinder.Values | ForEach-Object { [IO.Path]::GetFileName($_) })
    if ($namen.Count -ge 2 -and (Get-QuellArtVorschlag $namen $w.Eigen.Audio ([IO.Path]::GetFileName($w.Pfad))) -eq 'Sammlung') { return $w }
    return $n
}
function Add-Fundort($n) { $fundorte.Add((Get-PackKnoten $n)) }
function Find-Fundorte([string]$p, [bool]$unterBehaelter = $false) {
    $n = $knoten[$p.ToLowerInvariant()]
    if (-not $n) { return }
    $kinder = @($n.Kinder.Values | ForEach-Object { $knoten[$_.ToLowerInvariant()] } | Where-Object { $_ })
    if (Test-Behaelter $p) {
        # Behaelter (Laufwerk, Downloads, Dokumente ...) ist nie als Ganzes Fundort. Lose Audiodateien und Archive
        # direkt darin erscheinen als eigene Zeile mit der Art "Nur lose Dateien" (ohne Unterordner).
        # Version 3 (QLN-11): Archive direkt darin bekommen je eine eigene Zeile - sonst liest sich die Zeile der
        # losen Dateien wie ein Pack aus dem ZIP
        $eigeneZ = @($n.ZListe | Where-Object { $d = [IO.Path]::GetDirectoryName(($_ -split '\|')[0]); $d -ieq $p.TrimEnd('\', '/') -or $d -ieq $p })
        if ($n.Eigen.Audio -gt 0) {
            $z = @{ Pfad = $p; Neu = $n.Neu; Formate = $n.Formate; ZFormate = @{}; Kinder = @{}; Beispiele = @($n.EigeneBeispiele | Where-Object { $_ }); Lose = $true; Eigen = $n.Eigen; ZListe = @() }
            foreach ($s in $SummenFelder) { $z[$s] = $n.Eigen[$s] }
            foreach ($s in 'Archive', 'ZAudio', 'ZBytes', 'ZCloud', 'ZOffen', 'ZVerschachtelt') { $z[$s] = 0 }
            $z.Projekt = 0; $z.Instrument = 0
            $fundorte.Add($z)
        }
        foreach ($zl in $eigeneZ) {
            $t = $zl -split '\|'
            $z = @{ Pfad = $t[0]; Neu = $n.Neu; Formate = @{}; ZFormate = @{}; Kinder = @{}; Beispiele = @(); Lose = $false; Eigen = @{ Audio = 0 }; ZListe = @($zl); Archivzeile = $true }
            foreach ($s in $SummenFelder) { $z[$s] = 0 }
            $z.Archive = 1
            switch ($t[1]) { 'a' { $z.ZAudio = [long]$t[2]; $z.ZBytes = [long]$t[3] } 'v' { $z.ZAudio = [long]$t[2]; $z.ZBytes = [long]$t[3]; $z.ZVerschachtelt = 1 } 'c' { $z.ZCloud = 1 } default { $z.ZOffen = 1 } }
            $fundorte.Add($z)
        }
        foreach ($k in $kinder) { Find-Fundorte $k.Pfad $true }
        return
    }
    # Direkt unter einem Behaelter ist jeder Ordner ein Fundort (z. B. Downloads\BSH092_...), auch wenn er
    # nur einen Unterordner hat - sonst wuerde ein innerer Ordner zum Pack-Namen.
    if ($unterBehaelter -and @($kinder | ForEach-Object { Get-Einschaetzung $_ } | Select-Object -Unique).Count -le 1) { Add-Fundort $n; return }
    # Nur ein Unterordner mit Inhalt und hier selbst nichts (auch keine Projekt-, Instrument- oder Archivdateien): tiefer gehen
    # 2.3.4: nicht in einen typischen Innenordner (Loops, Kicks, "<Pack> - Drums" ...) hinabgehen - dann ist dieser Ordner das Pack
    if ($n.Eigen.Audio -eq 0 -and $kinder.Count -eq 1 -and $n.Archive -eq $kinder[0].Archive -and $n.Projekt -eq $kinder[0].Projekt -and $n.Instrument -eq $kinder[0].Instrument -and
        $n.AbletonPreset -eq $kinder[0].AbletonPreset -and -not (Test-PackInnenName ([IO.Path]::GetFileName($kinder[0].Pfad)) ([IO.Path]::GetFileName($p)))) { Find-Fundorte $kinder[0].Pfad; return }
    $arten = @($kinder | ForEach-Object { Get-Einschaetzung $_ } | Select-Object -Unique)
    if ($n.Eigen.Audio -eq 0 -and $arten.Count -gt 1) { foreach ($k in $kinder) { Find-Fundorte $k.Pfad }; return }
    Add-Fundort $n
}
foreach ($w in $wurzeln) { Find-Fundorte $w.TrimEnd('\', '/'); if ($w.Length -le 3) { Find-Fundorte $w } }

# Bereits eingetragene Quellen (aktiv oder ohne Haken)
$quellen = @($einst.Quellen)
function Get-QuellStatus([string]$p, [string]$art = 'Sammlung') {
    $pn = $p.TrimEnd('\') + '\'
    foreach ($q in $quellen) {
        $qn = ([string]$q.Pfad).TrimEnd('\') + '\'
        $qArt = Get-QuellArtName ([string]$q.Art)
        if ($qn -ieq $pn) { if ($q.Aktiv) { return 'schon Quelle' } else { return 'schon Quelle (deaktiviert)' } }
        $zu = if ($q.Aktiv) { "$($q.Pfad)" } else { "$($q.Pfad) (deaktiviert)" }
        if ($pn.StartsWith($qn, [StringComparison]::OrdinalIgnoreCase) -and $qArt -ne 'Lose') { return "liegt in der Quelle $zu" }
        if ($qn.StartsWith($pn, [StringComparison]::OrdinalIgnoreCase) -and $art -ne 'Lose') { return "enthält die Quelle $zu" }
    }
    return ''
}

$liste = @(foreach ($n in $fundorte) {
    $art = Get-Einschaetzung $n
    $kinder = @($n.Kinder.Values | ForEach-Object { $knoten[$_.ToLowerInvariant()] } | Where-Object { $_ } | Sort-Object { $_.Audio + $_.ZAudio } -Descending)
    $packs = @($kinder | Where-Object { $_.Audio -gt 0 }).Count
    $qArt = if ($n.Lose) { 'Lose' } else { Get-QuellArtVorschlag @($kinder | ForEach-Object { [IO.Path]::GetFileName($_.Pfad) }) $n.Eigen.Audio ([IO.Path]::GetFileName($n.Pfad.TrimEnd('\', '/'))) }
    $status = Get-QuellStatus $n.Pfad $qArt
    $basisPfad = $n.Pfad.TrimEnd('\', '/')
    [pscustomobject][ordered]@{
        p   = $n.Pfad
        art = $art
        a   = $n.Audio
        b   = $n.Bytes
        f   = (@($n.Formate.Keys | Sort-Object) -join ', ')
        neu = $(if ($n.Neu -gt [DateTime]::MinValue) { $n.Neu.ToString('yyyy-MM-dd') } else { '' })
        zip = $n.Archive
        za  = $n.ZAudio
        zb  = $n.ZBytes
        zf  = (@($n.ZFormate.Keys | Sort-Object) -join ', ')
        zc  = $n.ZCloud
        zo  = $n.ZOffen
        zv  = $n.ZVerschachtelt
        cl  = $n.Cloud
        pk  = $packs
        lose = $n.Eigen.Audio
        pj  = $n.Projekt
        ap  = $n.AbletonPreset
        nl  = [bool]$n.Lose
        ar  = [bool]$n.Archivzeile
        qa  = $qArt
        st  = $status
        vor = ($art -eq 'Sample-Packs' -and -not $n.Lose -and -not $status -and $n.Audio -ge 5 -and $n.Cloud -eq 0)
        u   = @($kinder | Select-Object -First 30 | ForEach-Object { [pscustomobject]@{ n = [IO.Path]::GetFileName($_.Pfad); a = $_.Audio; b = $_.Bytes; za = $_.ZAudio; art = (Get-Einschaetzung $_) } })
        bsp = @($n.Beispiele)
        zl  = @($n.ZListe | ForEach-Object { $t = $_ -split '\|'; $r = $t[0]; if ($n.Archivzeile) { $r = [IO.Path]::GetFileName($r) } elseif ($r.StartsWith($basisPfad + $sep, [StringComparison]::OrdinalIgnoreCase)) { $r = $r.Substring($basisPfad.Length + 1) }
                 [pscustomobject]@{ n = $r; s = $t[1]; a = [int]$t[2]; b = [long]$t[3]; g = $(if ($t.Count -gt 4) { $t[4] } else { '' }) } })
    }
}) | Sort-Object @{ e = { $_.art -ne 'Sample-Packs' } }, @{ e = { $_.b + $_.zb }; Descending = $true }

# ---------------------------------------------------------------------------
# Ergebnis: JSON, CSV, HTML
# ---------------------------------------------------------------------------
$ablage = Join-Path $einst.Berichtsordner 'Fundorte'
if (-not (Test-Path -LiteralPath $ablage)) { New-Item -ItemType Directory -Path $ablage -Force | Out-Null }
$basisName = Join-Path $ablage "Fundorte_$Zeitstempel"
$meta = [ordered]@{
    Version = $ProgrammVersion; Erstellt = (Get-Date).ToString('dd.MM.yyyy HH:mm'); Orte = @($wurzeln); Ordner = $ordnerZahl
    NichtLesbar = $nichtLesbar; ArchivInhalt = (-not $OhneArchivinhalt); Dauer = [math]::Round(((Get-Date) - $start).TotalSeconds); Ziel = $einst.Ziel
}
$daten = [ordered]@{ meta = $meta; f = @($liste) }
$json = ConvertTo-Json -InputObject $daten -Depth 6 -Compress
[IO.File]::WriteAllText("$basisName.json", $json, (New-Object System.Text.UTF8Encoding($false)))
$liste | Select-Object @{ n = 'Fundort'; e = { $_.p } }, @{ n = 'Einschaetzung'; e = { $_.art } }, @{ n = 'Audiodateien'; e = { $_.a } },
    @{ n = 'GroesseMB'; e = { [math]::Round($_.b / 1MB, 1) } }, @{ n = 'Formate'; e = { $_.f } }, @{ n = 'Letzte Aenderung'; e = { $_.neu } },
    @{ n = 'Archive'; e = { $_.zip } }, @{ n = 'Nur in der Cloud'; e = { $_.cl } }, @{ n = 'Unterordner mit Audio'; e = { $_.pk } }, @{ n = 'Status'; e = { $_.st } } |
    Export-Csv -LiteralPath "$basisName.csv" -NoTypeInformation -Delimiter ';' -Encoding UTF8

$html = New-FundortHtml $json
[IO.File]::WriteAllText("$basisName.html", $html, (New-Object System.Text.UTF8Encoding($false)))

# ---------------------------------------------------------------------------
# Zusammenfassung und Bericht oeffnen
# ---------------------------------------------------------------------------
Write-Host ""
Write-Host "==================== Zusammenfassung ====================" -ForegroundColor Yellow
Write-Host ("Fundorte:            {0,6}" -f $liste.Count)
$liste | Group-Object art | Sort-Object Name | ForEach-Object { Write-Host ("  {0,-22} {1,6}" -f $_.Name, $_.Count) }
Write-Host ("Dauer: {0} s" -f $meta.Dauer)
Write-Host ""
Write-Host "Bericht: $basisName.html"
Write-Host "Liste (Excel): $basisName.csv"
if (-not $KeinBrowser) {
    Write-Host ""
    Write-Host "Der Bericht wird im Browser geoeffnet. Dort Fundorte anhaken und 'In Quellenliste uebernehmen'." -ForegroundColor Green
    if (-not (Start-FundortBericht "$basisName.json")) { try { Invoke-Item -LiteralPath "$basisName.html" } catch { } }
}
