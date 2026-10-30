# (c) 2026 Herbert Stoecker. Kostenlos nutzbar. Bitte nur als Link auf die offizielle Download-Seite weitergeben; Verkauf und Veroeffentlichung geaenderter Fassungen nur mit Zustimmung.
<#
.SYNOPSIS
  Gemeinsame Teile fuer "Download importieren" (Version 3, IMP-01 bis IMP-10): ZIP-Archive lesen und
  sicher entpacken (ohne Zusatzsoftware), neue Sample-Packs im Download-Ordner finden.
  Wird von der Oberflaeche und von Download-importieren.ps1 eingebunden (nach Gemeinsam.ps1).

  ZIP wird selbst gelesen und entpackt (zentrales Verzeichnis, Stored/Deflate, Pruefsumme CRC32):
  so stoeren auch ungewoehnliche Namen im Archiv nicht ("Illegales Zeichen im Pfad").
#>

if (-not ('SamplesWerkzeuge.ZipWerkzeug300' -as [type])) {
    Add-Type -Language CSharp -TypeDefinition @'
using System;
using System.IO;
using System.IO.Compression;
using System.Text;
using System.Collections.Generic;
namespace SamplesWerkzeuge {
    public class ZipEintrag300 {
        public string Name; public long Groesse; public long Gepackt; public long Offset;
        public int Methode; public bool Verschluesselt; public uint Crc; public bool Ordner;
    }
    public class ZipErgebnis300 {
        public int Dateien; public long Bytes; public string Fehler = "";
        public List<string> Uebersprungen = new List<string>();
        public List<string> Archive = new List<string>();
    }
    public class OrdnerAudio300 { public int Audio; public long Bytes; public long AudioBytes; public DateTime Neu = DateTime.MinValue; public List<long> Groessen = new List<long>(); }
    public static class ZipWerkzeug300 {
        public static readonly HashSet<string> AudioExt = new HashSet<string>(new string[] { ".wav", ".aif", ".aiff", ".mp3", ".flac", ".ogg", ".rx2", ".rex", ".m4a" }, StringComparer.OrdinalIgnoreCase);
        // Programme und Skripte werden nie entpackt (IMP-05)
        public static readonly HashSet<string> ProgrammExt = new HashSet<string>(new string[] { ".exe", ".msi", ".bat", ".cmd", ".com", ".scr", ".ps1", ".psm1", ".vbs", ".vbe", ".js", ".jse", ".wsf", ".hta", ".jar", ".dll", ".sys", ".lnk", ".reg", ".app", ".dmg", ".pkg", ".sh", ".apk", ".msix", ".appx", ".iso" }, StringComparer.OrdinalIgnoreCase);
        static readonly string[] Reserviert = new string[] { "CON", "PRN", "AUX", "NUL", "COM1", "COM2", "COM3", "COM4", "COM5", "COM6", "COM7", "COM8", "COM9", "LPT1", "LPT2", "LPT3", "LPT4", "LPT5", "LPT6", "LPT7", "LPT8", "LPT9" };

        public static string L(string p) {
            if (Path.DirectorySeparatorChar != '\\' || p.Length < 240 || p.StartsWith(@"\\?\")) return p;
            return p.StartsWith(@"\\") ? @"\\?\UNC\" + p.Substring(2) : @"\\?\" + p;
        }
        public static string Ext(string name) {
            int s = Math.Max(name.LastIndexOf('/'), name.LastIndexOf('\\'));
            int d = name.LastIndexOf('.');
            if (d <= s || d >= name.Length - 1) return "";
            return name.Substring(d);
        }
        static uint U16(byte[] b, long i) { return (uint)(b[i] | (b[i + 1] << 8)); }
        static uint U32(byte[] b, long i) { return (uint)(b[i] | (b[i + 1] << 8) | (b[i + 2] << 16) | (b[i + 3] << 24)); }
        static ulong U64(byte[] b, long i) { return (ulong)U32(b, i) | ((ulong)U32(b, i + 4) << 32); }
        static void Lies(Stream fs, long pos, byte[] b) {
            fs.Seek(pos, SeekOrigin.Begin); int n = 0;
            while (n < b.Length) { int k = fs.Read(b, n, b.Length - n); if (k <= 0) throw new EndOfStreamException(); n += k; }
        }

        // Inhaltsverzeichnis lesen (zentrales Verzeichnis, auch ZIP64); entpackt nichts
        public static List<ZipEintrag300> Liste(string pfad) {
            List<ZipEintrag300> liste = new List<ZipEintrag300>();
            using (FileStream fs = new FileStream(L(pfad), FileMode.Open, FileAccess.Read, FileShare.ReadWrite)) {
                long len = fs.Length;
                if (len < 22) throw new InvalidDataException("keine gültige ZIP-Datei (Download unvollständig oder beschädigt?)");
                int max = (int)Math.Min(len, 65557L); byte[] e = new byte[max]; Lies(fs, len - max, e);
                long i = -1;
                for (long k = max - 22; k >= 0; k--) { if (U32(e, k) == 0x06054b50) { i = k; break; } }
                if (i < 0) throw new InvalidDataException("keine gültige ZIP-Datei (Download unvollständig oder beschädigt?)");
                ulong groesse = U32(e, i + 12), start = U32(e, i + 16);
                if (U16(e, i + 10) == 0xFFFF || groesse == 0xFFFFFFFF || start == 0xFFFFFFFF) {
                    if (i < 20 || U32(e, i - 20) != 0x07064b50) throw new InvalidDataException("ZIP64-Verzeichnis fehlt");
                    byte[] z = new byte[56]; Lies(fs, (long)U64(e, i - 20 + 8), z);
                    if (U32(z, 0) != 0x06064b50) throw new InvalidDataException("ZIP64-Verzeichnis beschädigt");
                    groesse = U64(z, 40); start = U64(z, 48);
                }
                if (groesse > 512UL * 1024 * 1024 || start + groesse > (ulong)len) throw new InvalidDataException("Inhaltsverzeichnis unplausibel (Datei beschädigt?)");
                byte[] v = new byte[(int)groesse]; Lies(fs, (long)start, v);
                Encoding alt;
                try { alt = Encoding.GetEncoding(437); } catch (Exception) { alt = Encoding.GetEncoding("ISO-8859-1"); }
                long p = 0;
                while (p + 46 <= v.Length && U32(v, p) == 0x02014b50) {
                    ZipEintrag300 en = new ZipEintrag300();
                    uint flags = U16(v, p + 8);
                    en.Methode = (int)U16(v, p + 10); en.Crc = U32(v, p + 16);
                    ulong gepackt = U32(v, p + 20), roh = U32(v, p + 24), off = U32(v, p + 42);
                    int nl = (int)U16(v, p + 28), xl = (int)U16(v, p + 30), kl = (int)U16(v, p + 32);
                    if (p + 46 + nl + xl > v.Length) break;
                    en.Name = ((flags & 0x800) != 0 ? Encoding.UTF8 : alt).GetString(v, (int)(p + 46), nl);
                    en.Verschluesselt = (flags & 1) != 0;
                    long x = p + 46 + nl, xe = x + xl;
                    while (x + 4 <= xe) {
                        uint id = U16(v, x), dl = U16(v, x + 2);
                        if (id == 1) {
                            long q = x + 4;
                            if (roh == 0xFFFFFFFF && q + 8 <= x + 4 + dl) { roh = U64(v, q); q += 8; }
                            if (gepackt == 0xFFFFFFFF && q + 8 <= x + 4 + dl) { gepackt = U64(v, q); q += 8; }
                            if (off == 0xFFFFFFFF && q + 8 <= x + 4 + dl) { off = U64(v, q); q += 8; }
                            break;
                        }
                        x += 4 + dl;
                    }
                    en.Groesse = (long)roh; en.Gepackt = (long)gepackt; en.Offset = (long)off;
                    en.Ordner = en.Name.EndsWith("/") || en.Name.EndsWith("\\");
                    liste.Add(en);
                    p += 46 + nl + xl + kl;
                }
            }
            return liste;
        }

        public static bool MacRest(string name) {
            string n = name.Replace('\\', '/');
            if (n.IndexOf("__MACOSX/", StringComparison.OrdinalIgnoreCase) >= 0 || n.StartsWith("__MACOSX", StringComparison.OrdinalIgnoreCase)) return true;
            string d = n.TrimEnd('/'); int s = d.LastIndexOf('/'); if (s >= 0) d = d.Substring(s + 1);
            return d.StartsWith("._") || string.Equals(d, ".DS_Store", StringComparison.OrdinalIgnoreCase);
        }

        // Sicherer Teilpfad (mit \): null bei ".." oder absoluten Pfaden (IMP-05); unzulaessige Zeichen werden ersetzt
        public static string SichererName(string name) {
            string n = name.Replace('\\', '/');
            if (n.StartsWith("/") || (n.Length > 1 && n[1] == ':')) return null;
            List<string> teile = new List<string>();
            foreach (string t0 in n.Split('/')) {
                if (t0.Length == 0 || t0 == ".") continue;
                if (t0 == "..") return null;
                StringBuilder sb = new StringBuilder();
                foreach (char c in t0) { if (c < 32 || "<>:\"|?*".IndexOf(c) >= 0) sb.Append('_'); else sb.Append(c); }
                string t = sb.ToString().TrimEnd('.', ' ').TrimStart(' ');
                if (t.Length == 0) t = "_";
                string basis = t; int pkt = t.IndexOf('.'); if (pkt > 0) basis = t.Substring(0, pkt);
                foreach (string r in Reserviert) { if (string.Equals(basis, r, StringComparison.OrdinalIgnoreCase)) { t = "_" + t; break; } }
                if (t.Length > 150) { string ex = Ext(t); t = t.Substring(0, 140 - Math.Min(ex.Length, 10)) + (ex.Length <= 10 ? ex : ""); }
                teile.Add(t);
            }
            if (teile.Count == 0) return null;
            return string.Join(Path.DirectorySeparatorChar.ToString(), teile.ToArray());
        }

        static uint[] crcTab;
        static uint Crc(uint crc, byte[] b, int n) {
            if (crcTab == null) {
                uint[] t = new uint[256];
                for (uint i = 0; i < 256; i++) { uint c = i; for (int k = 0; k < 8; k++) c = (c & 1) != 0 ? 0xEDB88320 ^ (c >> 1) : c >> 1; t[i] = c; }
                crcTab = t;
            }
            crc = ~crc;
            for (int i = 0; i < n; i++) crc = crcTab[(crc ^ b[i]) & 0xFF] ^ (crc >> 8);
            return ~crc;
        }

        // Entpackt ein ZIP in den Ordner ziel. Prueft jede Datei per CRC32. Programme, macOS-Reste und unsichere
        // Pfade werden nicht entpackt. maxBytes: Obergrenze fuer die entpackte Groesse (Schutz vor "ZIP-Bomben").
        public static ZipErgebnis300 Entpacken(string zip, string ziel, long maxBytes) {
            ZipErgebnis300 r = new ZipErgebnis300();
            List<ZipEintrag300> liste;
            try { liste = Liste(zip); } catch (Exception ex) { r.Fehler = ex.Message; return r; }
            long summe = 0;
            foreach (ZipEintrag300 en in liste) {
                if (en.Ordner) continue;
                if (en.Verschluesselt) { r.Fehler = "verschlüsselt (Kennwort nötig) – nicht unterstützt"; return r; }
                if (en.Methode != 0 && en.Methode != 8) { r.Fehler = "Komprimierungsart " + en.Methode + " wird nicht unterstützt"; return r; }
                if (en.Groesse > 100L * 1024 * 1024 && en.Gepackt > 0 && en.Groesse / en.Gepackt > 1000) { r.Fehler = "unplausibel stark gepackt (" + en.Name + ") – nicht entpackt"; return r; }
                summe += en.Groesse;
            }
            if (summe > maxBytes) { r.Fehler = "entpackt zu groß (" + (summe / 1048576) + " MB)"; return r; }
            Directory.CreateDirectory(L(ziel));
            byte[] puffer = new byte[1 << 16];
            using (FileStream fs = new FileStream(L(zip), FileMode.Open, FileAccess.Read, FileShare.ReadWrite)) {
                foreach (ZipEintrag300 en in liste) {
                    if (en.Ordner) continue;
                    if (MacRest(en.Name)) continue;
                    string rel = SichererName(en.Name);
                    if (rel == null) { r.Uebersprungen.Add(en.Name + " (unsicherer Pfad)"); continue; }
                    if (ProgrammExt.Contains(Ext(rel))) { r.Uebersprungen.Add(en.Name + " (Programm oder Skript)"); continue; }
                    string datei = Path.Combine(ziel, rel);
                    if (File.Exists(L(datei))) {
                        string b = Path.Combine(Path.GetDirectoryName(datei), Path.GetFileNameWithoutExtension(datei)); string ex = Path.GetExtension(datei); int z = 2;
                        while (File.Exists(L(b + " (" + z + ")" + ex))) z++;
                        datei = b + " (" + z + ")" + ex;
                    }
                    Directory.CreateDirectory(L(Path.GetDirectoryName(datei)));
                    byte[] kopf = new byte[30]; Lies(fs, en.Offset, kopf);
                    if (U32(kopf, 0) != 0x04034b50) { r.Fehler = "beschädigt bei " + en.Name; return r; }
                    long daten = en.Offset + 30 + U16(kopf, 26) + U16(kopf, 28);
                    fs.Seek(daten, SeekOrigin.Begin);
                    uint crc = 0; long geschrieben = 0;
                    using (FileStream aus = new FileStream(L(datei), FileMode.CreateNew, FileAccess.Write)) {
                        if (en.Methode == 0) {
                            long rest = en.Gepackt;
                            while (rest > 0) {
                                int k = fs.Read(puffer, 0, (int)Math.Min(puffer.Length, rest));
                                if (k <= 0) break;
                                aus.Write(puffer, 0, k); crc = Crc(crc, puffer, k); rest -= k; geschrieben += k;
                            }
                        } else {
                            using (DeflateStream ds = new DeflateStream(fs, CompressionMode.Decompress, true)) {
                                int k;
                                while ((k = ds.Read(puffer, 0, puffer.Length)) > 0) {
                                    geschrieben += k;
                                    if (geschrieben > en.Groesse) break;
                                    aus.Write(puffer, 0, k); crc = Crc(crc, puffer, k);
                                }
                            }
                        }
                    }
                    if (geschrieben != en.Groesse || crc != en.Crc) {
                        try { File.Delete(L(datei)); } catch (Exception) { }
                        r.Fehler = "Prüfsumme stimmt nicht bei " + en.Name + " (Archiv beschädigt?)"; return r;
                    }
                    r.Dateien++; r.Bytes += geschrieben;
                    if (string.Equals(Ext(rel), ".zip", StringComparison.OrdinalIgnoreCase)) r.Archive.Add(datei);
                }
            }
            return r;
        }

        // Groessen aller Audiodateien in einem Ordner (fuer "schon vollstaendig im Ziel")
        public static OrdnerAudio300 Ordner(string pfad) {
            OrdnerAudio300 o = new OrdnerAudio300();
            Stack<string> st = new Stack<string>(); st.Push(pfad);
            while (st.Count > 0) {
                string d = st.Pop();
                try {
                    foreach (FileSystemInfo e in new DirectoryInfo(L(d)).EnumerateFileSystemInfos()) {
                        if ((e.Attributes & FileAttributes.Directory) != 0) {
                            if ((e.Attributes & FileAttributes.ReparsePoint) == 0) st.Push(e.FullName.StartsWith(@"\\?\") ? e.FullName.Substring(4) : e.FullName);
                            continue;
                        }
                        long n = ((FileInfo)e).Length; o.Bytes += n;
                        if (e.LastWriteTime > o.Neu) o.Neu = e.LastWriteTime;
                        if (AudioExt.Contains(Ext(e.Name)) && !e.Name.StartsWith("._")) { o.Audio++; o.AudioBytes += n; o.Groessen.Add(n); }
                    }
                } catch (Exception) { }
            }
            return o;
        }
        public static HashSet<long> GroessenIndex(string pfad) {
            HashSet<long> h = new HashSet<long>();
            if (!Directory.Exists(L(pfad))) return h;
            foreach (long g in Ordner(pfad).Groessen) h.Add(g);
            return h;
        }
    }
}
'@
}

# ---------------------------------------------------------------------------
# Neue Sample-Packs im Download-Ordner (IMP-02): ZIP-Archive und Ordner mit Audiodateien.
# Liefert je Kandidat: Name, Pfad, Art (ZIP/Ordner/RAR/7z), Bytes (entpackt), Audio, Datum, Anhakbar, Hinweis.
# "Schon vollstaendig im Ziel": alle Audiodateien haben eine gleich grosse Datei im Ziel (ab 3 Dateien;
# der Import selbst prueft ohnehin per Pruefsumme).
# ---------------------------------------------------------------------------
function Get-ImportKandidaten {
    $e = Get-Einstellungen
    $dl = [string]$e.Downloads
    $erg = New-Object System.Collections.Generic.List[object]
    if (-not $dl -or -not (Test-Path -LiteralPath $dl -PathType Container)) { return $erg }
    $zielGroessen = [SamplesWerkzeuge.ZipWerkzeug300]::GroessenIndex([string]$e.Ziel)
    $aus = @([string]$e.DownloadArchiv, [string]$e.Ziel, $wurzel, (Split-Path -Parent $wurzel)) | Where-Object { $_ } | ForEach-Object { $_.TrimEnd('\', '/') }
    $quellen = @($e.Quellen | ForEach-Object { ([string]$_.Pfad).TrimEnd('\', '/') })
    $neu = { param($name, $pfad, $art, $bytes, $audio, $datum, $an, $hinweis, $voll)
        [pscustomobject]@{ Name = $name; Pfad = $pfad; Art = $art; Bytes = [long]$bytes; Audio = [int]$audio; Datum = $datum; Anhakbar = [bool]$an; Hinweis = $hinweis; Vollstaendig = [bool]$voll } }
    $alleIm = { param($groessen) $n = 0; foreach ($g in $groessen) { if ($zielGroessen.Contains([long]$g)) { $n++ } }; return $n }
    foreach ($x in @(Get-ChildItem -LiteralPath $dl -Force -ErrorAction SilentlyContinue | Sort-Object LastWriteTime -Descending)) {
        $voll = $x.FullName.TrimEnd('\', '/')
        if ($aus -contains $voll -or $x.Name -like '_Samples-Werkzeuge*') { continue }
        if ($x.PSIsContainer) {
            if ($x.Attributes -band [IO.FileAttributes]::ReparsePoint) { continue }
            $o = [SamplesWerkzeuge.ZipWerkzeug300]::Ordner($voll)
            if ($o.Audio -eq 0) { continue }
            $im = & $alleIm $o.Groessen
            $v = ($o.Audio -ge 3 -and $im -eq $o.Audio)
            $h = @(); if ($v) { $h += 'schon vollständig im Ziel – nicht importierbar' } elseif ($im) { $h += "$im von $($o.Audio) schon im Ziel" }
            if ($quellen -contains $voll) { $h += 'auch als Quelle eingetragen' }
            $erg.Add((& $neu $x.Name $voll 'Ordner' $o.Bytes $o.Audio $x.LastWriteTime (-not $v) ($h -join '; ') $v))
        } elseif ($x.Extension -ieq '.zip') {
            try { $l = [SamplesWerkzeuge.ZipWerkzeug300]::Liste($voll) }
            catch { $m = if ($_.Exception.InnerException) { $_.Exception.InnerException.Message } else { $_.Exception.Message }; $erg.Add((& $neu $x.Name $voll 'ZIP' 0 0 $x.LastWriteTime $false "nicht lesbar: $m" $false)); continue }
            $dateien = @($l | Where-Object { -not $_.Ordner -and -not [SamplesWerkzeuge.ZipWerkzeug300]::MacRest($_.Name) })
            $audio = @($dateien | Where-Object { [SamplesWerkzeuge.ZipWerkzeug300]::AudioExt.Contains([SamplesWerkzeuge.ZipWerkzeug300]::Ext($_.Name)) })
            $innen = @($dateien | Where-Object { [SamplesWerkzeuge.ZipWerkzeug300]::Ext($_.Name) -ieq '.zip' }).Count
            if (-not $audio.Count -and -not $innen) { continue }   # kein Sample-Pack (z. B. Installer, Dokumente)
            $bytes = [long](($dateien | Measure-Object Groesse -Sum).Sum)
            $h = @(); $an = $true
            if (@($dateien | Where-Object { $_.Verschluesselt }).Count) { $an = $false; $h += 'verschlüsselt – nicht unterstützt' }
            elseif (@($dateien | Where-Object { $_.Methode -ne 0 -and $_.Methode -ne 8 }).Count) { $an = $false; $h += 'Komprimierungsart nicht unterstützt' }
            $im = & $alleIm @($audio | ForEach-Object { $_.Groesse })
            $v = ($audio.Count -ge 3 -and -not $innen -and $im -eq $audio.Count)
            if ($v) { $an = $false; $h = @('schon vollständig im Ziel – nicht importierbar') + $h } elseif ($im) { $h += "$im von $($audio.Count) schon im Ziel" }
            if ($innen) { $h += "enthält $innen weitere(s) ZIP (wird mit entpackt)" }
            $erg.Add((& $neu $x.Name $voll 'ZIP' $bytes $audio.Count $x.LastWriteTime $an ($h -join '; ') $v))
        } elseif ($x.Extension -in '.rar', '.7z') {
            $erg.Add((& $neu $x.Name $voll ($x.Extension.TrimStart('.').ToUpperInvariant()) $x.Length 0 $x.LastWriteTime $false 'RAR/7z – nicht unterstützt (bitte selbst entpacken)' $false))
        }
    }
    return $erg
}

# Pack-Name aus dem Namen des Downloads (ohne .zip, ohne unzulaessige Zeichen)
function Get-ImportPackName([string]$name) {
    $n = $name; if ($n -match '\.zip$') { $n = $n.Substring(0, $n.Length - 4) }
    $n = ($n -replace '[<>:"/\\|?*\x00-\x1f]', '_').Trim().TrimEnd('.')
    if (-not $n) { $n = 'Pack' }
    return $n
}
