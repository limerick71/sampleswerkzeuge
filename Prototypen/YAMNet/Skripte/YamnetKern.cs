// (c) 2026 Herbert Stoecker. YAMNet-Prototyp fuer die Samples-Werkzeuge.
// Rechnet das YAMNet-Modell (ONNX-Datei von Qualcomm AI Hub, Eingang: Log-Mel-Ausschnitt 96 x 64)
// ohne zusaetzliche Software nach: Audiodatei lesen, auf 16 kHz umrechnen, Log-Mel-Spektrogramm wie
// beim Original-YAMNet (TensorFlow), Faltungsnetz (Conv, Relu, GlobalAveragePool, Reshape, Gemm), Sigmoid.
using System;
using System.Collections.Generic;
using System.IO;
using System.Text;

namespace SamplesWerkzeuge.Yamnet {

    public class Tensor {
        public float[] D; public int[] S;
        public Tensor(float[] d, int[] s) { D = d; S = s; }
    }

    // ---------------------------------------------------------------------------------------------
    // Minimaler Protobuf-Leser fuer ONNX (ModelProto -> GraphProto -> NodeProto/TensorProto)
    // ---------------------------------------------------------------------------------------------
    class PB {
        readonly byte[] b; int p; readonly int end;
        public PB(byte[] buf, int start, int ende) { b = buf; p = start; end = ende; }
        public bool Mehr { get { return p < end; } }
        public ulong Varint() { ulong r = 0; int s = 0; while (true) { byte x = b[p++]; r |= (ulong)(x & 0x7F) << s; if ((x & 0x80) == 0) return r; s += 7; } }
        public void Tag(out int feld, out int typ) { ulong t = Varint(); feld = (int)(t >> 3); typ = (int)(t & 7); }
        public PB Teil() { int n = (int)Varint(); PB r = new PB(b, p, p + n); p += n; return r; }
        public byte[] Bytes() { int n = (int)Varint(); byte[] r = new byte[n]; Buffer.BlockCopy(b, p, r, 0, n); p += n; return r; }
        public string Text() { int n = (int)Varint(); string r = Encoding.UTF8.GetString(b, p, n); p += n; return r; }
        public float Fixed32() { float f = BitConverter.ToSingle(b, p); p += 4; return f; }
        public void Ueberspringen(int typ) {
            if (typ == 0) Varint(); else if (typ == 1) p += 8; else if (typ == 2) { int n = (int)Varint(); p += n; } else if (typ == 5) p += 4;
            else throw new InvalidDataException("Unbekannter Protobuf-Typ " + typ);
        }
        // wiederholte Ganzzahlen: gepackt (Typ 2) oder einzeln (Typ 0)
        public void Ganzzahlen(int typ, List<long> ziel) {
            if (typ == 2) { PB t = Teil(); while (t.Mehr) ziel.Add((long)t.Varint()); } else ziel.Add((long)Varint());
        }
    }

    class Knoten {
        public string Op; public List<string> Ein = new List<string>(); public List<string> Aus = new List<string>();
        public Dictionary<string, List<long>> Ints = new Dictionary<string, List<long>>();
        public Dictionary<string, float> Floats = new Dictionary<string, float>();
        public long Int(string n, long std) { List<long> v; return Ints.TryGetValue(n, out v) && v.Count > 0 ? v[0] : std; }
        public long[] IntListe(string n, long[] std) { List<long> v; return Ints.TryGetValue(n, out v) ? v.ToArray() : std; }
    }

    public class Modell {
        readonly List<Knoten> knoten = new List<Knoten>();
        readonly Dictionary<string, Tensor> werte = new Dictionary<string, Tensor>();
        public string Eingang = "audio", Ausgang = "class_scores";
        public string[] Klassen;

        public Modell(string onnxPfad, string labelsPfad) {
            byte[] buf = File.ReadAllBytes(onnxPfad);
            string ordner = Path.GetDirectoryName(Path.GetFullPath(onnxPfad));
            PB m = new PB(buf, 0, buf.Length);
            int f, t;
            while (m.Mehr) {
                m.Tag(out f, out t);
                if (f == 7 && t == 2) LeseGraph(m.Teil(), ordner); else m.Ueberspringen(t);
            }
            List<string> l = new List<string>();
            foreach (string z in File.ReadAllLines(labelsPfad, Encoding.UTF8)) if (z.Trim().Length > 0) l.Add(z.Trim());
            Klassen = l.ToArray();
        }

        void LeseGraph(PB g, string ordner) {
            int f, t;
            while (g.Mehr) {
                g.Tag(out f, out t);
                if (f == 1 && t == 2) knoten.Add(LeseKnoten(g.Teil()));
                else if (f == 5 && t == 2) LeseTensor(g.Teil(), ordner);
                else if (f == 11 && t == 2) { string n = LeseName(g.Teil()); if (n != null) Eingang = n; }
                else if (f == 12 && t == 2) { string n = LeseName(g.Teil()); if (n != null) Ausgang = n; }
                else g.Ueberspringen(t);
            }
        }
        static string LeseName(PB v) { int f, t; while (v.Mehr) { v.Tag(out f, out t); if (f == 1 && t == 2) return v.Text(); v.Ueberspringen(t); } return null; }

        static Knoten LeseKnoten(PB n) {
            Knoten k = new Knoten(); int f, t;
            while (n.Mehr) {
                n.Tag(out f, out t);
                if (f == 1 && t == 2) k.Ein.Add(n.Text());
                else if (f == 2 && t == 2) k.Aus.Add(n.Text());
                else if (f == 4 && t == 2) k.Op = n.Text();
                else if (f == 5 && t == 2) {
                    PB a = n.Teil(); string name = ""; List<long> ints = new List<long>(); float fl = float.NaN; int af, at;
                    while (a.Mehr) {
                        a.Tag(out af, out at);
                        if (af == 1 && at == 2) name = a.Text();
                        else if (af == 2 && at == 5) fl = a.Fixed32();
                        else if (af == 3 && at == 0) ints.Add((long)a.Varint());
                        else if (af == 8) a.Ganzzahlen(at, ints);
                        else a.Ueberspringen(at);
                    }
                    if (ints.Count > 0) k.Ints[name] = ints;
                    if (!float.IsNaN(fl)) k.Floats[name] = fl;
                }
                else n.Ueberspringen(t);
            }
            return k;
        }

        void LeseTensor(PB tp, string ordner) {
            List<long> dims = new List<long>(); List<long> int64 = new List<long>(); List<float> floats = new List<float>();
            int typ = 1; string name = ""; byte[] roh = null; bool extern_ = false; string datei = null; long offset = 0, laenge = -1;
            int f, t;
            while (tp.Mehr) {
                tp.Tag(out f, out t);
                if (f == 1) tp.Ganzzahlen(t, dims);
                else if (f == 2 && t == 0) typ = (int)tp.Varint();
                else if (f == 4 && t == 2) { PB fp = tp.Teil(); while (fp.Mehr) floats.Add(fp.Fixed32()); }
                else if (f == 4 && t == 5) floats.Add(tp.Fixed32());
                else if (f == 7) tp.Ganzzahlen(t, int64);
                else if (f == 8 && t == 2) name = tp.Text();
                else if (f == 9 && t == 2) roh = tp.Bytes();
                else if (f == 13 && t == 2) {
                    PB e = tp.Teil(); string key = null, val = null; int ef, et;
                    while (e.Mehr) { e.Tag(out ef, out et); if (ef == 1 && et == 2) key = e.Text(); else if (ef == 2 && et == 2) val = e.Text(); else e.Ueberspringen(et); }
                    if (key == "location") datei = val; else if (key == "offset") offset = long.Parse(val); else if (key == "length") laenge = long.Parse(val);
                }
                else if (f == 14 && t == 0) extern_ = tp.Varint() == 1;
                else tp.Ueberspringen(t);
            }
            int[] s = new int[dims.Count]; long anz = 1;
            for (int i = 0; i < s.Length; i++) { s[i] = (int)dims[i]; anz *= dims[i]; }
            float[] d = new float[anz];
            if (extern_) {
                int bytesJe = typ == 7 ? 8 : 4;
                if (laenge < 0) laenge = anz * bytesJe;
                roh = new byte[laenge];
                using (FileStream fs = new FileStream(Path.Combine(ordner, datei), FileMode.Open, FileAccess.Read, FileShare.Read)) {
                    fs.Seek(offset, SeekOrigin.Begin); int gelesen = 0;
                    while (gelesen < laenge) { int n = fs.Read(roh, gelesen, (int)laenge - gelesen); if (n <= 0) throw new EndOfStreamException("Modelldaten unvollstaendig: " + datei); gelesen += n; }
                }
            }
            if (typ == 1) {          // FLOAT
                if (roh != null) Buffer.BlockCopy(roh, 0, d, 0, (int)anz * 4); else floats.CopyTo(d);
            } else if (typ == 7) {   // INT64 (z. B. Zielform fuer Reshape)
                for (long i = 0; i < anz; i++) d[i] = roh != null ? BitConverter.ToInt64(roh, (int)(i * 8)) : int64[(int)i];
            } else throw new NotSupportedException("Tensor-Typ " + typ + " (" + name + ") wird nicht unterstuetzt");
            werte[name] = new Tensor(d, s);
        }

        // 0.2: ausgewaehlte Stellen (je ein Ausschnitt): Mittelwert und Hoechstwert je Klasse
        public float[][] BewerteStellen(Stellen st) {
            float[] mittel = new float[Klassen.Length], spitze = new float[Klassen.Length]; int anzahl = 0;
            foreach (float[] f in st.Fenster16k) {
                List<float[]> ps = Vorverarbeitung.Ausschnitte(f);
                if (ps.Count == 0) continue;
                float[] s = Bewerte(ps[0]); anzahl++;
                for (int i = 0; i < s.Length && i < mittel.Length; i++) { mittel[i] += s[i]; if (s[i] > spitze[i]) spitze[i] = s[i]; }
            }
            for (int i = 0; i < mittel.Length; i++) mittel[i] /= Math.Max(1, anzahl);
            return new float[][] { mittel, spitze };
        }

        // Ganze Datei (16 kHz): Mittelwert und Hoechstwert je Klasse ueber alle Ausschnitte
        public float[][] BewerteSignal(float[] y16, out int anzahl) {
            List<float[]> ps = Vorverarbeitung.Ausschnitte(y16);
            anzahl = ps.Count;
            float[] mittel = new float[Klassen.Length], spitze = new float[Klassen.Length];
            foreach (float[] p in ps) {
                float[] s = Bewerte(p);
                for (int i = 0; i < s.Length && i < mittel.Length; i++) { mittel[i] += s[i]; if (s[i] > spitze[i]) spitze[i] = s[i]; }
            }
            for (int i = 0; i < mittel.Length; i++) mittel[i] /= Math.Max(1, anzahl);
            return new float[][] { mittel, spitze };
        }

        // Ausschnitt [96 x 64] Log-Mel -> 521 Werte (Sigmoid, 0..1)
        public float[] Bewerte(float[] logMel) {
            Dictionary<string, Tensor> w = new Dictionary<string, Tensor>(werte);
            w[Eingang] = new Tensor(logMel, new int[] { 1, 1, 96, 64 });
            foreach (Knoten k in knoten) {
                Tensor x = w[k.Ein[0]], y;
                switch (k.Op) {
                    case "Conv": y = Conv(x, w[k.Ein[1]], k.Ein.Count > 2 ? w[k.Ein[2]] : null, k); break;
                    case "Relu": y = new Tensor(new float[x.D.Length], x.S); for (int i = 0; i < x.D.Length; i++) y.D[i] = x.D[i] > 0 ? x.D[i] : 0; break;
                    case "GlobalAveragePool": {
                        int c = x.S[1], hw = x.S[2] * x.S[3]; y = new Tensor(new float[c], new int[] { 1, c, 1, 1 });
                        for (int i = 0; i < c; i++) { double s = 0; for (int j = 0; j < hw; j++) s += x.D[i * hw + j]; y.D[i] = (float)(s / hw); }
                        break; }
                    case "Reshape": case "Flatten": y = new Tensor(x.D, new int[] { 1, x.D.Length }); break;
                    case "Gemm": y = Gemm(x, w[k.Ein[1]], k.Ein.Count > 2 ? w[k.Ein[2]] : null, k); break;
                    default: throw new NotSupportedException("ONNX-Operation " + k.Op + " wird nicht unterstuetzt");
                }
                w[k.Aus[0]] = y;
            }
            float[] z = w[Ausgang].D; float[] r = new float[z.Length];
            for (int i = 0; i < z.Length; i++) r[i] = (float)(1.0 / (1.0 + Math.Exp(-z[i])));
            return r;
        }

        static Tensor Conv(Tensor x, Tensor wt, Tensor b, Knoten k) {
            int cin = x.S[1], h = x.S[2], wd = x.S[3];
            int cout = wt.S[0], kcin = wt.S[1], kh = wt.S[2], kw = wt.S[3];
            int grp = (int)k.Int("group", 1);
            long[] st = k.IntListe("strides", new long[] { 1, 1 });
            long[] pd = k.IntListe("pads", new long[] { 0, 0, 0, 0 });
            int sh = (int)st[0], sw = (int)st[1], pt = (int)pd[0], pl = (int)pd[1], pb = (int)pd[2], pr = (int)pd[3];
            int oh = (h + pt + pb - kh) / sh + 1, ow = (wd + pl + pr - kw) / sw + 1;
            float[] o = new float[cout * oh * ow]; float[] xi = x.D, wi = wt.D;
            int P = oh * ow;
            if (kh == 1 && kw == 1 && sh == 1 && sw == 1 && grp == 1 && pt == 0 && pl == 0 && pb == 0 && pr == 0) {
                // 1x1-Faltung = Matrixprodukt; je Bildpunkt alle Eingangskanaele (zusammenhaengend gelesen)
                float[] xt = new float[P * cin];                     // transponiert: [p][ci]
                for (int ci = 0; ci < cin; ci++) { int ib = ci * P; for (int p = 0; p < P; p++) xt[p * cin + ci] = xi[ib + p]; }
                for (int co = 0; co < cout; co++) {
                    int wb = co * cin; float bias = b != null ? b.D[co] : 0f; int ob = co * P;
                    for (int p = 0; p < P; p++) {
                        int xb = p * cin; float s0 = 0f, s1 = 0f, s2 = 0f, s3 = 0f; int ci = 0;
                        for (; ci + 3 < cin; ci += 4) {
                            s0 += wi[wb + ci] * xt[xb + ci]; s1 += wi[wb + ci + 1] * xt[xb + ci + 1];
                            s2 += wi[wb + ci + 2] * xt[xb + ci + 2]; s3 += wi[wb + ci + 3] * xt[xb + ci + 3];
                        }
                        for (; ci < cin; ci++) s0 += wi[wb + ci] * xt[xb + ci];
                        o[ob + p] = bias + ((s0 + s1) + (s2 + s3));
                    }
                }
            } else {
                int coJeGrp = cout / grp;
                for (int co = 0; co < cout; co++) {
                    int gi = co / coJeGrp; float bias = b != null ? b.D[co] : 0f;
                    for (int oy = 0; oy < oh; oy++)
                        for (int ox = 0; ox < ow; ox++) {
                            float s = bias;
                            for (int kc = 0; kc < kcin; kc++) {
                                int ci = gi * kcin + kc;
                                for (int ky = 0; ky < kh; ky++) {
                                    int iy = oy * sh - pt + ky; if (iy < 0 || iy >= h) continue;
                                    for (int kx = 0; kx < kw; kx++) {
                                        int ix = ox * sw - pl + kx; if (ix < 0 || ix >= wd) continue;
                                        s += wi[((co * kcin + kc) * kh + ky) * kw + kx] * xi[(ci * h + iy) * wd + ix];
                                    }
                                }
                            }
                            o[(co * oh + oy) * ow + ox] = s;
                        }
                }
            }
            return new Tensor(o, new int[] { 1, cout, oh, ow });
        }

        static Tensor Gemm(Tensor x, Tensor wt, Tensor b, Knoten k) {
            bool tb = k.Int("transB", 0) == 1; float alpha = k.Floats.ContainsKey("alpha") ? k.Floats["alpha"] : 1f, beta = k.Floats.ContainsKey("beta") ? k.Floats["beta"] : 1f;
            int n = x.D.Length, m = tb ? wt.S[0] : wt.S[1];
            float[] o = new float[m];
            for (int j = 0; j < m; j++) {
                double s = 0;
                for (int i = 0; i < n; i++) s += x.D[i] * (tb ? wt.D[j * n + i] : wt.D[i * m + j]);
                o[j] = (float)(alpha * s + (b != null ? beta * b.D[j] : 0));
            }
            return new Tensor(o, new int[] { 1, m });
        }
    }

    // ---------------------------------------------------------------------------------------------
    // Audio lesen (WAV, AIFF/AIFC) -> Mono, Werte -1..1
    // ---------------------------------------------------------------------------------------------
    public class Audio {
        public float[] Mono; public int Rate, Kanaele, Bits; public string Format = ""; public double Dauer;

        public static Audio Lese(string pfad, double maxSek) {
            using (FileStream fs = new FileStream(pfad, FileMode.Open, FileAccess.Read, FileShare.ReadWrite))
            using (BinaryReader br = new BinaryReader(fs)) {
                string id = Encoding.ASCII.GetString(br.ReadBytes(4));
                if (id == "RIFF" || id == "RF64") { br.ReadUInt32(); if (Encoding.ASCII.GetString(br.ReadBytes(4)) != "WAVE") throw new InvalidDataException("keine WAVE-Datei"); return LeseWav(br, fs, maxSek); }
                if (id == "FORM") { br.ReadUInt32(); string art = Encoding.ASCII.GetString(br.ReadBytes(4)); if (art != "AIFF" && art != "AIFC") throw new InvalidDataException("keine AIFF-Datei"); return LeseAiff(br, fs, maxSek, art == "AIFC"); }
                throw new NotSupportedException("Format nicht unterstuetzt (nur WAV und AIFF)");
            }
        }

        static Audio LeseWav(BinaryReader br, FileStream fs, double maxSek) {
            Audio a = new Audio(); int fmt = 0, block = 0; long datenPos = -1, datenLen = 0;
            while (fs.Position + 8 <= fs.Length) {
                string id = Encoding.ASCII.GetString(br.ReadBytes(4)); long len = br.ReadUInt32(); long start = fs.Position;
                if (id == "fmt ") {
                    fmt = br.ReadUInt16(); a.Kanaele = br.ReadUInt16(); a.Rate = (int)br.ReadUInt32(); br.ReadUInt32(); block = br.ReadUInt16(); a.Bits = br.ReadUInt16();
                    if (fmt == 0xFFFE && len >= 40) { br.ReadUInt16(); br.ReadUInt16(); br.ReadUInt32(); fmt = br.ReadUInt16(); }
                } else if (id == "data") { datenPos = start; datenLen = Math.Min(len, fs.Length - start); break; }
                fs.Position = start + len + (len & 1);
            }
            if (datenPos < 0 || a.Rate <= 0 || a.Kanaele <= 0) throw new InvalidDataException("WAV ohne Audiodaten");
            a.Format = fmt == 3 ? "WAV float" : "WAV PCM";
            if (fmt != 1 && fmt != 3) throw new NotSupportedException("WAV-Codierung " + fmt + " (z. B. ADPCM) wird nicht unterstuetzt");
            fs.Position = datenPos;
            a.Mono = Wandle(br, datenLen, a.Kanaele, a.Bits, fmt == 3, false, a.Rate, maxSek, out a.Dauer);
            return a;
        }

        static Audio LeseAiff(BinaryReader br, FileStream fs, double maxSek, bool aifc) {
            Audio a = new Audio(); long datenPos = -1, datenLen = 0; bool le = false, fl = false;
            while (fs.Position + 8 <= fs.Length) {
                string id = Encoding.ASCII.GetString(br.ReadBytes(4)); long len = BE32(br); long start = fs.Position;
                if (id == "COMM") {
                    a.Kanaele = BE16(br); BE32(br); a.Bits = BE16(br); a.Rate = (int)Ext80(br.ReadBytes(10));
                    if (aifc && len >= 22) { string c = Encoding.ASCII.GetString(br.ReadBytes(4)); if (c == "sowt") le = true; else if (c == "fl32" || c == "FL32") { fl = true; a.Bits = 32; } else if (c != "NONE") throw new NotSupportedException("AIFC-Codierung " + c + " wird nicht unterstuetzt"); }
                } else if (id == "SSND") { long off = BE32(br); BE32(br); datenPos = start + 8 + off; datenLen = Math.Min(len - 8 - off, fs.Length - datenPos); break; }
                fs.Position = start + len + (len & 1);
            }
            if (datenPos < 0 || a.Rate <= 0 || a.Kanaele <= 0) throw new InvalidDataException("AIFF ohne Audiodaten");
            a.Format = "AIFF"; fs.Position = datenPos;
            a.Mono = Wandle(br, datenLen, a.Kanaele, a.Bits, fl, !le, a.Rate, maxSek, out a.Dauer);
            return a;
        }

        static float[] Wandle(BinaryReader br, long len, int ch, int bits, bool fl, bool bigEndian, int rate, double maxSek, out double dauer) {
            int bps = (bits + 7) / 8; long frames = len / (bps * ch);
            dauer = (double)frames / rate;
            long nutz = Math.Min(frames, (long)(maxSek * rate));
            byte[] roh = br.ReadBytes((int)(nutz * bps * ch));
            nutz = roh.Length / (bps * ch);
            float[] m = new float[nutz];
            for (long i = 0; i < nutz; i++) {
                double s = 0;
                for (int c = 0; c < ch; c++) {
                    int o = (int)((i * ch + c) * bps); double v;
                    if (fl && bps == 4) { if (bigEndian) { byte[] t = { roh[o + 3], roh[o + 2], roh[o + 1], roh[o] }; v = BitConverter.ToSingle(t, 0); } else v = BitConverter.ToSingle(roh, o); }
                    else if (fl && bps == 8) v = BitConverter.ToDouble(roh, o);
                    else if (bps == 1) v = bigEndian ? (sbyte)roh[o] / 128.0 : (roh[o] - 128) / 128.0;
                    else {
                        long x = 0;
                        for (int k = 0; k < bps; k++) { int idx = bigEndian ? o + k : o + bps - 1 - k; x = (x << 8) | roh[idx]; }
                        int shift = 64 - 8 * bps; x = (x << shift) >> shift;   // Vorzeichen
                        v = x / Math.Pow(2, 8 * bps - 1);
                    }
                    s += v;
                }
                m[i] = (float)(s / ch);
            }
            return m;
        }
        static int BE16(BinaryReader br) { byte[] b = br.ReadBytes(2); return (short)((b[0] << 8) | b[1]); }
        static long BE32(BinaryReader br) { byte[] b = br.ReadBytes(4); return ((long)b[0] << 24) | ((long)b[1] << 16) | ((long)b[2] << 8) | b[3]; }
        static double Ext80(byte[] b) {
            int exp = ((b[0] & 0x7F) << 8) | b[1]; ulong man = 0; for (int i = 2; i < 10; i++) man = (man << 8) | b[i];
            if (exp == 0 && man == 0) return 0; return man * Math.Pow(2, exp - 16383 - 63);
        }
    }

    // ---------------------------------------------------------------------------------------------
    // 0.2: Auswahl der lautesten Stellen, Lautstaerke angleichen, Grundton
    // ---------------------------------------------------------------------------------------------
    public class Stellen {
        public List<float[]> Fenster16k = new List<float[]>();   // je 0,975 s bei 16 kHz (= ein Ausschnitt)
        public List<double> Beginn = new List<double>();          // Sekunden
        public double VerstaerkungDb, LautesteRmsDb;
    }

    public static class Auswahl {
        // Bis zu "anzahl" nicht ueberlappende Fenster mit dem hoechsten Pegel; Fenster unter -40 dB
        // gegenueber dem lautesten werden ausgelassen. Danach Pegel angleichen (RMS -20 dBFS, hoechstens +30 dB).
        public static Stellen Waehle(float[] x, int rate, int anzahl) {
            Stellen st = new Stellen();
            int win = (int)Math.Round(0.975 * rate), hop = Math.Max(1, (int)Math.Round(0.24 * rate));
            List<int> starts = new List<int>(); List<double> rms = new List<double>();
            if (x.Length <= win) { starts.Add(0); rms.Add(Rms(x, 0, x.Length)); }
            else for (int s = 0; s + win <= x.Length; s += hop) { starts.Add(s); rms.Add(Rms(x, s, win)); }
            int[] ord = new int[starts.Count]; for (int i = 0; i < ord.Length; i++) ord[i] = i;
            double[] r = rms.ToArray(); Array.Sort(r, ord); Array.Reverse(ord);
            double maxRms = rms[ord[0]];
            List<int> gew = new List<int>();
            foreach (int i in ord) {
                if (gew.Count >= anzahl) break;
                if (gew.Count > 0 && rms[i] < maxRms * 0.01) break;
                bool frei = true; foreach (int g in gew) if (Math.Abs(starts[g] - starts[i]) < win) { frei = false; break; }
                if (frei) gew.Add(i);
            }
            gew.Sort((a, b) => starts[a].CompareTo(starts[b]));
            double gain = maxRms > 1e-9 ? Math.Min(0.1 / maxRms, Math.Pow(10, 30 / 20.0)) : 1.0;
            st.VerstaerkungDb = 20 * Math.Log10(gain); st.LautesteRmsDb = maxRms > 0 ? 20 * Math.Log10(maxRms) : -120;
            foreach (int g in gew) {
                int s0 = starts[g], n = Math.Min(win, x.Length - s0);
                float[] f = new float[n]; for (int k = 0; k < n; k++) f[k] = (float)(x[s0 + k] * gain);
                st.Fenster16k.Add(Vorverarbeitung.Resample(f, rate));
                st.Beginn.Add((double)s0 / rate);
            }
            return st;
        }
        static double Rms(float[] x, int s, int n) { double q = 0; for (int k = s; k < s + n; k++) q += x[k] * x[k]; return n > 0 ? Math.Sqrt(q / n) : 0; }

        // Grundton per Autokorrelation (30-1000 Hz) in einem 16-kHz-Fenster; Klarheit 0..1
        public static double[] Grundton(float[] y) {
            int n = Math.Min(y.Length, 8000), lo = 16, hi = 533;
            if (n < hi * 2) return new double[] { 0, 0 };
            double e0 = 0; for (int i = 0; i < n - hi; i++) e0 += y[i] * y[i];
            if (e0 <= 1e-9) return new double[] { 0, 0 };
            double[] ac = new double[hi + 1];
            for (int lag = lo; lag <= hi; lag++) {
                double s = 0, e1 = 0; for (int i = 0; i < n - hi; i++) { s += y[i] * y[i + lag]; e1 += y[i + lag] * y[i + lag]; }
                ac[lag] = e1 > 0 ? s / Math.Sqrt(e0 * e1) : 0;
            }
            int best = -1; double bv = 0;
            for (int lag = lo + 1; lag < hi; lag++) if (ac[lag] > ac[lag - 1] && ac[lag] >= ac[lag + 1] && ac[lag] > bv) { bv = ac[lag]; best = lag; }
            if (best < 0) return new double[] { 0, 0 };
            // kuerzeste Periode mit fast gleich guter Korrelation (gegen Oktavfehler)
            for (int lag = lo + 1; lag < best; lag++) if (ac[lag] > ac[lag - 1] && ac[lag] >= ac[lag + 1] && ac[lag] > 0.9 * bv) { best = lag; bv = ac[lag]; break; }
            return new double[] { 16000.0 / best, bv };
        }
    }

    // ---------------------------------------------------------------------------------------------
    // Vorverarbeitung wie YAMNet: 16 kHz, Fenster 25 ms, Schritt 10 ms, 64 Mel-Baender 125-7500 Hz,
    // log(mel + 0.001), Ausschnitte 96 Frames (0,96 s) mit Schritt 48 Frames (0,48 s)
    // ---------------------------------------------------------------------------------------------
    public static class Vorverarbeitung {
        static double[] melMatrix, fenster, cosT, sinT; static int[] umkehr;
        static double mel(double h) { return 1127.0 * Math.Log(1 + h / 700.0); }

        // Pegel: [RMS dBFS, Spitze dBFS]
        public static double[] Pegel(float[] x) {
            double q = 0, sp = 0; foreach (float v in x) { q += v * v; double a = Math.Abs(v); if (a > sp) sp = a; }
            double rms = x.Length > 0 ? Math.Sqrt(q / x.Length) : 0;
            return new double[] { rms > 0 ? 20 * Math.Log10(rms) : -120, sp > 0 ? 20 * Math.Log10(sp) : -120 };
        }

        public static float[] Resample(float[] x, int von) {
            const int nach = 16000;
            if (von == nach) return (float[])x.Clone();
            double fc = Math.Min(1.0, (double)nach / von); int R = (int)Math.Ceiling(16 / fc);
            int n = (int)Math.Floor((double)x.Length * nach / von); float[] y = new float[n];
            for (int i = 0; i < n; i++) {
                double t = (double)i * von / nach; int k0 = (int)Math.Floor(t); double s = 0;
                for (int k = k0 - R + 1; k <= k0 + R; k++) {
                    if (k < 0 || k >= x.Length) continue;
                    double d = t - k; if (Math.Abs(d) >= R) continue;
                    double z = fc * d; double sinc = Math.Abs(z) < 1e-12 ? 1.0 : Math.Sin(Math.PI * z) / (Math.PI * z);
                    s += x[k] * fc * sinc * (0.5 + 0.5 * Math.Cos(Math.PI * d / R));
                }
                y[i] = (float)s;
            }
            return y;
        }

        static void Init() {
            if (melMatrix != null) return;
            melMatrix = new double[257 * 64];
            double lo = mel(125), hi = mel(7500);
            for (int i = 0; i < 64; i++) {
                double l = lo + (hi - lo) * i / 65, c = lo + (hi - lo) * (i + 1) / 65, u = lo + (hi - lo) * (i + 2) / 65;
                for (int k = 1; k < 257; k++) {
                    double m = mel(8000.0 * k / 256);
                    melMatrix[k * 64 + i] = Math.Max(0, Math.Min((m - l) / (c - l), (u - m) / (u - c)));
                }
            }
            fenster = new double[400]; for (int i = 0; i < 400; i++) fenster[i] = 0.5 - 0.5 * Math.Cos(2 * Math.PI * i / 400);
            cosT = new double[256]; sinT = new double[256];
            for (int i = 0; i < 256; i++) { cosT[i] = Math.Cos(2 * Math.PI * i / 512); sinT[i] = -Math.Sin(2 * Math.PI * i / 512); }
            umkehr = new int[512]; for (int i = 0; i < 512; i++) { int r = 0, v = i; for (int b = 0; b < 9; b++) { r = (r << 1) | (v & 1); v >>= 1; } umkehr[i] = r; }
        }

        static void Fft(double[] re, double[] im) {
            for (int i = 0; i < 512; i++) { int j = umkehr[i]; if (j > i) { double t = re[i]; re[i] = re[j]; re[j] = t; t = im[i]; im[i] = im[j]; im[j] = t; } }
            for (int len = 2; len <= 512; len <<= 1) {
                int half = len >> 1, schritt = 512 / len;
                for (int s = 0; s < 512; s += len)
                    for (int k = 0; k < half; k++) {
                        double wr = cosT[k * schritt], wi = sinT[k * schritt];
                        int a = s + k, b = a + half;
                        double tr = re[b] * wr - im[b] * wi, ti = re[b] * wi + im[b] * wr;
                        re[b] = re[a] - tr; im[b] = im[a] - ti; re[a] += tr; im[a] += ti;
                    }
            }
        }

        // 16-kHz-Signal -> Liste von Ausschnitten [96*64]
        public static List<float[]> Ausschnitte(float[] y) {
            Init();
            const int win = 400, hop = 160, minLen = win + 95 * hop, ph = 48 * hop;
            int len = y.Length < minLen ? minLen : minLen + (int)Math.Ceiling((double)(y.Length - minLen) / ph) * ph;
            float[] z = new float[len]; Array.Copy(y, z, y.Length);
            int nf = 1 + (len - win) / hop;
            float[] lm = new float[nf * 64];
            double[] re = new double[512], im = new double[512], mag = new double[257];
            for (int f = 0; f < nf; f++) {
                for (int i = 0; i < 512; i++) { re[i] = i < win ? z[f * hop + i] * fenster[i] : 0; im[i] = 0; }
                Fft(re, im);
                for (int k = 0; k < 257; k++) mag[k] = Math.Sqrt(re[k] * re[k] + im[k] * im[k]);
                for (int b = 0; b < 64; b++) { double s = 0; for (int k = 1; k < 257; k++) s += mag[k] * melMatrix[k * 64 + b]; lm[f * 64 + b] = (float)Math.Log(s + 0.001); }
            }
            List<float[]> r = new List<float[]>();
            for (int p = 0; p + 96 <= nf; p += 48) { float[] a = new float[96 * 64]; Array.Copy(lm, p * 64, a, 0, 96 * 64); r.Add(a); }
            return r;
        }
    }
}
