# (c) 2026 Herbert Stoecker. Kostenlos nutzbar. Bitte nur als Link auf die offizielle Download-Seite weitergeben; Verkauf und Veroeffentlichung geaenderter Fassungen nur mit Zustimmung.
# Bericht.ps1 - erzeugt den HTML-Bericht zu einer Inventur (Samples-Werkzeuge Version 2)
# Wird von Inventur.ps1 per Dot-Sourcing geladen. Die HTML-Datei ist eigenstaendig
# (keine Internetverbindung noetig) und liegt neben der Inventur-CSV. Aufbau wie der Bericht der Plugin-Werkzeuge.

function New-InventurBericht([string]$csvPfad) {
    $ordner = Split-Path -Parent $csvPfad
    $stempel = [IO.Path]::GetFileNameWithoutExtension($csvPfad) -replace '^Sample-Inventur_', ''
    $samples = @(Import-Csv -LiteralPath $csvPfad -Delimiter ';' -Encoding UTF8)
    $packPfad = Join-Path $ordner "Pack-Inventur_$stempel.csv"
    $packs = if (Test-Path -LiteralPath $packPfad) { @(Import-Csv -LiteralPath $packPfad -Delimiter ';' -Encoding UTF8) } else { @() }
    $lauf = @{}
    $jsonPfad = [IO.Path]::ChangeExtension($csvPfad, '.json')
    if (Test-Path -LiteralPath $jsonPfad) { try { $lauf = Get-Content -LiteralPath $jsonPfad -Raw -Encoding UTF8 | ConvertFrom-Json } catch { } }
    $entfernt = @()
    $vgl = Join-Path (Get-VergleichOrdner) "Inventur-Vergleich_$stempel.csv"
    if (Test-Path -LiteralPath $vgl) {
        $entfernt = @(Import-Csv -LiteralPath $vgl -Delimiter ';' -Encoding UTF8 | Where-Object { $_.Vergleich -eq 'entfernt' } |
            ForEach-Object { [ordered]@{ d = $_.Datei; p = $_.Pack; v = $_.'Pfad vorher' } })
    }

    function Zahl($w) { if ($null -eq $w -or [string]$w -eq '') { return $null }; try { return [double]([string]$w -replace ',', '.') } catch { return $null } }
    $s = foreach ($x in $samples) {
        [ordered]@{
            d = $x.Datei; k = $x.Kategorie; i = $x.Instrument; t = $x.Typ; p = $x.Pack; a = $x.'Pack-Art'; f = $x.Format
            s = (Zahl $x.GroesseBytes); du = (Zahl $x.Dauer); r = (Zahl $x.Abtastrate); b = (Zahl $x.Bittiefe); c = $x.Kanaele
            bpm = (Zahl $x.BPM); key = $x.Tonart; w = $x.Pfad; u = $x.Ursprung; o = $x.'Original in Quelle'
            g = (Zahl $x.'Duplikat-Gruppe'); dr = $x.'Duplikat-Rolle'; n = $x.'Seit letzter Inventur'; h = $x.Hinweis
        }
    }
    $p = foreach ($x in $packs) {
        [ordered]@{
            p = $x.Pack; a = $x.'Pack-Art'; ah = $x.'Pack-Art Herkunft'; n = (Zahl $x.Samples); mb = (Zahl $x.GroesseMB); i = $x.Instrumente
            l = (Zahl $x.'Anteil Loops'); f = $x.Formate; bpm = $x.'BPM-Bereich'; key = $x.Tonarten; lz = $x.Lizenz; o = $x.'Original in Quelle'
            dup = (Zahl $x.Duplikate); neu = $x.'Seit letzter Inventur'
        }
    }
    $meta = [ordered]@{
        Datum = $lauf.Zeit; Rechner = $lauf.Rechner; Version = "Samples-Werkzeuge $ProgrammVersion"; Ziel = $lauf.Ziel
        FreiGB = $lauf.FreiGB; Csv = [IO.Path]::GetFileName($csvPfad); Verglichen = $lauf.VerglichenMit; PackArten = $PackArten
    }
    if (-not $meta.Ziel) { $meta.Ziel = (Get-Einstellungen).Ziel }
    $json = ConvertTo-Json -InputObject @{ meta = $meta; samples = @($s); packs = @($p); entfernt = @($entfernt) } -Depth 5 -Compress
    $json = $json.Replace('</', '<\/')
    $html = $script:BerichtVorlage.Replace('__DATEN__', $json)
    $ziel = [IO.Path]::ChangeExtension($csvPfad, '.html')
    $enc = New-Object System.Text.UTF8Encoding($true)
    [IO.File]::WriteAllText($ziel, $html, $enc)
    # Immer aktuelle Fassung unter festem Namen (REP-03)
    try { [IO.File]::WriteAllText((Join-Path $ordner 'Inventur-aktuell.html'), $html, $enc) } catch { }
    return $ziel
}

$script:BerichtVorlage = @'
<!DOCTYPE html>
<html lang="de">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>Sample-Inventur</title>
<style>
:root{
  --bg:#f6f7f9; --karte:#ffffff; --text:#1d2433; --leise:#5f6b7a; --linie:#e2e6ec; --kopf:#eef1f5;
  --akzent:#1f4e79; --rot:#b42318; --rot-bg:#fde8e7; --gelb:#8a5a00; --gelb-bg:#fff4d6;
  --gruen:#1a7f37; --gruen-bg:#e3f5e8; --blau:#1f4e79; --blau-bg:#e4eef8; --grau-bg:#eef0f3;
}
@media (prefers-color-scheme: dark){
  :root{
    --bg:#14171c; --karte:#1c2027; --text:#e6e9ee; --leise:#9aa4b2; --linie:#2c323c; --kopf:#232831;
    --akzent:#8bb8e8; --rot:#ff8a80; --rot-bg:#3a1f1f; --gelb:#ffd27a; --gelb-bg:#3a2f14;
    --gruen:#7ee2a0; --gruen-bg:#163322; --blau:#8bb8e8; --blau-bg:#1b2a3c; --grau-bg:#262b33;
  }
}
*{box-sizing:border-box}
body{margin:0;background:var(--bg);color:var(--text);font:14px/1.45 "Segoe UI",system-ui,sans-serif}
header{padding:22px 28px 6px}
h1{margin:0;font-size:22px;color:var(--akzent)}
.unter{color:var(--leise);font-size:13px;margin-top:2px}
.karten{display:flex;flex-wrap:wrap;gap:10px;padding:14px 28px}
.karte{background:var(--karte);border:1px solid var(--linie);border-radius:8px;padding:10px 14px;min-width:120px}
.karte b{display:block;font-size:20px}
.karte span{color:var(--leise);font-size:12px}
.werkzeuge{display:flex;flex-wrap:wrap;gap:10px;align-items:center;padding:6px 28px 12px;position:sticky;top:0;background:var(--bg);z-index:2;border-bottom:1px solid var(--linie)}
input[type=search],select{font:inherit;color:var(--text);background:var(--karte);border:1px solid var(--linie);border-radius:6px;padding:6px 8px}
input[type=search]{min-width:260px;flex:1 1 260px;max-width:420px}
label.ck{display:flex;gap:6px;align-items:center;color:var(--leise)}
.ansicht{display:flex;border:1px solid var(--linie);border-radius:6px;overflow:hidden}
.ansicht button{font:inherit;border:0;background:var(--karte);color:var(--text);padding:6px 12px;cursor:pointer}
.ansicht button.an{background:var(--akzent);color:var(--karte)}
.chip{display:inline-flex;gap:6px;align-items:center;background:var(--blau-bg);color:var(--blau);border-radius:12px;padding:2px 10px;font-size:12px}
.chip button{border:0;background:none;color:inherit;cursor:pointer;font-size:14px;padding:0}
main{padding:12px 28px 40px}
table{width:100%;border-collapse:collapse;background:var(--karte);border:1px solid var(--linie);border-radius:8px;overflow:hidden;margin-bottom:18px}
th,td{text-align:left;padding:6px 10px;border-bottom:1px solid var(--linie);vertical-align:top}
th{background:var(--kopf);font-size:12px;color:var(--leise);font-weight:600}
td.z{text-align:right;white-space:nowrap}
tr.gruppe td{background:var(--kopf);font-weight:700;color:var(--akzent);font-size:15px;cursor:pointer;user-select:none}
tr.untergruppe td{font-weight:600;color:var(--leise);background:var(--karte);padding-top:9px;cursor:pointer;user-select:none}
tr.gruppe td span.m,tr.untergruppe td span.m{font-weight:400;color:var(--leise);font-size:12px;margin-left:8px}
td.name b{font-weight:600}
td.klein{color:var(--leise);font-size:12px;word-break:break-all}
a{color:var(--akzent)}
a.pk{cursor:pointer;text-decoration:underline}
.marke{display:inline-block;padding:1px 7px;border-radius:10px;font-size:11px;margin:1px 3px 1px 0;white-space:nowrap}
.rot{color:var(--rot);background:var(--rot-bg)} .gelb{color:var(--gelb);background:var(--gelb-bg)}
.gruen{color:var(--gruen);background:var(--gruen-bg)} .blau{color:var(--blau);background:var(--blau-bg)}
.grau{color:var(--leise);background:var(--grau-bg)}
button.play,button.kopie{font:inherit;border:1px solid var(--linie);background:var(--karte);color:var(--akzent);border-radius:50%;width:28px;height:28px;cursor:pointer;padding:0;line-height:26px}
button.kopie{border-radius:6px;width:auto;height:auto;line-height:1.2;padding:1px 6px;font-size:11px;margin-top:2px}
button.play.laeuft{background:var(--akzent);color:var(--karte)}
.leer{color:var(--leise);padding:20px}
h2{font-size:16px;margin:24px 0 8px;color:var(--akzent)}
footer{color:var(--leise);font-size:12px;padding:0 28px 30px}
#meldung{position:fixed;bottom:18px;right:18px;background:var(--akzent);color:var(--karte);padding:8px 14px;border-radius:6px;display:none;z-index:5}
@media print{.werkzeuge{position:static}}
</style>
</head>
<body>
<header>
  <h1>Sample-Inventur</h1>
  <div class="unter" id="unter"></div>
</header>
<div class="karten" id="karten"></div>
<div class="werkzeuge">
  <div class="ansicht" id="ansicht">
    <button data-v="samples" class="an">Samples</button><button data-v="packs">Packs</button><button data-v="dups">Duplikate</button>
  </div>
  <input type="search" id="suche" placeholder="Suchen (Datei, Pack, Instrument, Pfad) &#x2026;">
  <label>Gliedern nach <select id="gliederung"></select></label>
  <select id="fKat"><option value="">alle Kategorien</option></select>
  <select id="fArt"><option value="">alle Pack-Arten</option></select>
  <select id="fTyp"><option value="">One-Shots und Loops</option><option>One-Shot</option><option>Loop</option><option>Kit</option></select>
  <select id="fKey"><option value="">alle Tonarten</option></select>
  <select id="fFmt"><option value="">alle Formate</option></select>
  <label class="ck"><input type="checkbox" id="fProblem"> nur Auff&#xE4;lligkeiten</label>
  <span id="packChip"></span>
  <span id="anzahl" class="unter"></span>
</div>
<main id="inhalt"></main>
<footer id="fuss"></footer>
<div id="meldung"></div>
<audio id="player" preload="none"></audio>
<script id="daten" type="application/json">__DATEN__</script>
<script>
(function(){
  var D = JSON.parse(document.getElementById('daten').textContent);
  var S = D.samples || [], P = D.packs || [], M = D.meta || {}, W = D.entfernt || [];
  var ansicht = 'samples', packFilter = '', offen = {}, zeit = null;
  function $(id){ return document.getElementById(id); }
  function esc(s){ return String(s == null ? '' : s).replace(/[&<>"]/g, function(c){ return {'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;'}[c]; }); }
  function uniq(a){ var o = {}, r = []; a.forEach(function(x){ if (x && !o[x]) { o[x] = 1; r.push(x); } }); return r.sort(function(a,b){ return String(a).localeCompare(String(b),'de',{numeric:true}); }); }
  function mb(b){ b = b || 0; if (b >= 1073741824) return (b/1073741824).toLocaleString('de-DE',{maximumFractionDigits:2}) + ' GB'; if (b >= 1048576) return (b/1048576).toLocaleString('de-DE',{maximumFractionDigits:1}) + ' MB'; return Math.max(1, Math.round(b/1024)).toLocaleString('de-DE') + ' KB'; }
  function gb(b){ return (b/1073741824).toLocaleString('de-DE',{maximumFractionDigits:2}); }
  function sum(a,f){ var s = 0; a.forEach(function(x){ s += (f(x) || 0); }); return s; }
  function zahl(v,st){ return v == null ? '' : Number(v).toLocaleString('de-DE',{maximumFractionDigits:st||0}); }
  function meldung(t){ var m = $('meldung'); m.textContent = t; m.style.display = 'block'; clearTimeout(m._t); m._t = setTimeout(function(){ m.style.display = 'none'; }, 2500); }

  var neu = S.filter(function(s){ return s.n === 'neu'; }).length;
  var dupE = S.filter(function(s){ return s.dr === 'entfernbar'; });
  $('unter').textContent = 'Stand ' + (M.Datum || '') + (M.Rechner ? ' · ' + M.Rechner : '') + ' · ' + (M.Ziel || '');
  $('fuss').textContent = (M.Version || '') + ' · Datei ' + (M.Csv || '') + (M.Verglichen ? ' · verglichen mit ' + M.Verglichen : '');

  // Kennzahlen
  function karte(w,t){ return '<div class="karte"><b>' + esc(w) + '</b><span>' + esc(t) + '</span></div>'; }
  var k = karte(S.length.toLocaleString('de-DE'), 'Samples') + karte(P.filter(function(p){ return p.a !== 'ausgespart'; }).length, 'Packs');
  k += karte(mb(sum(S,function(s){ return s.s; })), 'belegt' + (M.FreiGB != null ? ' · ' + Number(M.FreiGB).toLocaleString('de-DE') + ' GB frei' : ''));
  uniq(S.map(function(s){ return s.k; })).forEach(function(kat){ var L = S.filter(function(s){ return s.k === kat; }); k += karte(L.length, kat + ' · ' + mb(sum(L,function(s){ return s.s; }))); });
  if (dupE.length) k += karte(dupE.length, 'Duplikate entfernbar · ' + mb(sum(dupE,function(s){ return s.s; })));
  if (neu || W.length) k += karte(neu + ' / ' + W.length, 'neu / entfernt');
  $('karten').innerHTML = k;

  // Auswahllisten
  function fuelle(id, werte){ werte.forEach(function(v){ $(id).insertAdjacentHTML('beforeend', '<option>' + esc(v) + '</option>'); }); }
  fuelle('fKat', uniq(S.map(function(s){ return s.k; })));
  fuelle('fArt', uniq(P.map(function(p){ return p.a; })));
  fuelle('fKey', uniq(S.map(function(s){ return s.key; })));
  fuelle('fFmt', uniq(S.map(function(s){ return s.f; })));
  var GL = {
    samples: [['kat','Kategorie → Instrument'],['pack','Pack'],['art','Pack-Art'],['bpm','BPM (10er-Bereiche)'],['key','Tonart'],['keine','nicht gliedern']],
    packs:   [['art','Pack-Art'],['keine','nicht gliedern']],
    dups:    [['gruppe','Duplikat-Gruppe']]
  };
  function setzeGliederung(){ $('gliederung').innerHTML = GL[ansicht].map(function(x){ return '<option value="' + x[0] + '">' + esc(x[1]) + '</option>'; }).join(''); }
  setzeGliederung();

  // Markierungen
  function markenS(s, ohneDup){
    var m = [], h = s.h || '';
    if (h.indexOf('defekt') >= 0 || h.indexOf('0 Byte') >= 0) m.push(['rot','defekt',h]);
    if (ohneDup) {} else if (s.dr === 'entfernbar') m.push(['gelb','Duplikat','gleicher Inhalt liegt noch an anderer Stelle (Gruppe ' + s.g + ') – entfernbar']);
    else if (s.g) m.push(['grau','Duplikat behalten','Gruppe ' + s.g + ': ' + s.dr]);
    if (h.indexOf('unsortiert') >= 0) m.push(['gelb','unsortiert','keinem Instrument zugeordnet']);
    if (s.n === 'neu') m.push(['gruen','neu','seit der letzten Inventur neu']);
    else if (s.n && s.n.indexOf('verschoben') === 0) m.push(['blau','verschoben',s.n]);
    return m;
  }
  function markenP(p){
    var m = [];
    if (p.a === 'ausgespart') m.push(['grau','ausgespart','nicht in die Bibliothek kopiert']);
    if (p.dup) m.push(['gelb', p.dup + ' Duplikat' + (p.dup > 1 ? 'e' : ''), 'entfernbare Duplikate in diesem Pack']);
    if (p.lz === 'nein') m.push(['grau','ohne Lizenztext','keine Lizenz- oder Infodatei gefunden']);
    if (p.neu === 'neu') m.push(['gruen','neu','seit der letzten Inventur neu']);
    if (p.ah === 'manuell') m.push(['blau','Art manuell','Pack-Art aus Pack-Arten.csv']);
    return m;
  }
  function problem(m){ return m.some(function(x){ return x[0] === 'rot' || x[0] === 'gelb'; }); }
  function markenHtml(m){ return m.map(function(x){ return '<span class="marke ' + x[0] + '" title="' + esc(x[2]) + '">' + esc(x[1]) + '</span>'; }).join(''); }

  // Abspielen im Browser (WAV, MP3, OGG, FLAC, M4A; nicht AIFF und RX2)
  var spielbar = {WAV:1,MP3:1,OGG:1,FLAC:1,M4A:1};
  var player = $('player'), aktuell = null;
  function dateiUrl(rel){ var p = (M.Ziel || '').replace(/[\\\/]+$/,'') + '\\' + rel; return 'file:///' + p.split(/[\\\/]/).map(encodeURIComponent).join('/').replace(/^([A-Za-z])%3A/, '$1:'); }
  function vollerPfad(rel){ return (M.Ziel || '').replace(/[\\\/]+$/,'') + '\\' + rel; }
  document.addEventListener('click', function(e){
    var b = e.target.closest('button.play');
    if (b) {
      if (aktuell === b && !player.paused) { player.pause(); b.classList.remove('laeuft'); b.textContent = '▶'; return; }
      if (aktuell) { aktuell.classList.remove('laeuft'); aktuell.textContent = '▶'; }
      aktuell = b; player.src = dateiUrl(b.getAttribute('data-w'));
      player.play().then(function(){ b.classList.add('laeuft'); b.textContent = '■'; }).catch(function(){ meldung('Abspielen nicht möglich (Browser erlaubt keinen Zugriff oder Format nicht unterstützt).'); });
      return;
    }
    var c = e.target.closest('button.kopie');
    if (c) { kopiere(vollerPfad(c.getAttribute('data-w'))); return; }
    var pk = e.target.closest('a.pk');
    if (pk) { packFilter = pk.getAttribute('data-p'); waehle('samples'); return; }
    var g = e.target.closest('tr[data-g]');
    if (g) { var id = g.getAttribute('data-g'); offen[id] = !offen[id]; zeichnen(); }
  });
  player.addEventListener('ended', function(){ if (aktuell) { aktuell.classList.remove('laeuft'); aktuell.textContent = '▶'; } });
  function kopiere(t){
    function alt(){ var x = document.createElement('textarea'); x.value = t; document.body.appendChild(x); x.select(); try { document.execCommand('copy'); meldung('Pfad kopiert'); } catch(e) { prompt('Pfad:', t); } x.remove(); }
    if (navigator.clipboard && navigator.clipboard.writeText) navigator.clipboard.writeText(t).then(function(){ meldung('Pfad kopiert – im Explorer in die Adresszeile einfügen'); }, alt); else alt();
  }

  // Filtern
  function filterS(){
    var q = $('suche').value.trim().toLowerCase(), fk = $('fKat').value, fa = $('fArt').value, ft = $('fTyp').value, fkey = $('fKey').value, ff = $('fFmt').value, fp = $('fProblem').checked;
    return S.filter(function(s){
      if (packFilter && s.p !== packFilter) return false;
      if (fk && s.k !== fk) return false;
      if (fa && s.a !== fa) return false;
      if (ft && s.t !== ft) return false;
      if (fkey && s.key !== fkey) return false;
      if (ff && s.f !== ff) return false;
      if (fp && !problem(markenS(s))) return false;
      if (q && [s.d, s.p, s.i, s.k, s.w, s.key, s.a].join(' ').toLowerCase().indexOf(q) < 0) return false;
      return true;
    });
  }
  function filterP(){
    var q = $('suche').value.trim().toLowerCase(), fa = $('fArt').value, fp = $('fProblem').checked, fk = $('fKat').value;
    return P.filter(function(p){
      if (fa && p.a !== fa) return false;
      if (fp && !problem(markenP(p))) return false;
      if (fk && !S.some(function(s){ return s.p === p.p && s.k === fk; })) return false;
      if (q && [p.p, p.a, p.i, p.key].join(' ').toLowerCase().indexOf(q) < 0) return false;
      return true;
    });
  }

  // Tabellen
  var KOPF_S = '<tr><th></th><th>Sample</th><th>Pack</th><th>Instrument / Typ</th><th>BPM</th><th>Tonart</th><th>Dauer</th><th>Format</th><th>Größe</th><th>Pfad</th></tr>';
  function zeileS(s, ohneDup){
    var play = spielbar[s.f] ? '<button class="play" data-w="' + esc(s.w) + '" title="Im Browser anhören">▶</button>' : '';
    var fmt = esc(s.f) + (s.r ? '<br><span class="klein">' + zahl(s.r/1000,1) + ' kHz · ' + esc(s.b) + ' Bit · ' + esc(s.c) + '</span>' : '');
    return '<tr><td>' + play + '</td><td class="name"><b>' + esc(s.d) + '</b><br>' + markenHtml(markenS(s, ohneDup)) + '</td>' +
      '<td><a class="pk" data-p="' + esc(s.p) + '" title="Nur dieses Pack zeigen">' + esc(s.p) + '</a><br><span class="marke grau">' + esc(s.a) + '</span></td>' +
      '<td>' + esc(s.i) + (s.t ? '<br><span class="klein">' + esc(s.t) + '</span>' : '') + '</td>' +
      '<td class="z">' + zahl(s.bpm,1) + '</td><td>' + esc(s.key) + '</td><td class="z">' + (s.du != null ? zahl(s.du,2) + ' s' : '') + '</td>' +
      '<td>' + fmt + '</td><td class="z">' + mb(s.s || 0) + '</td>' +
      '<td class="klein">' + esc(s.w) + '<br><button class="kopie" data-w="' + esc(s.w) + '" title="Vollständigen Pfad in die Zwischenablage kopieren">Pfad kopieren</button></td></tr>';
  }
  var KOPF_P = '<tr><th>Pack</th><th>Pack-Art</th><th>Samples</th><th>Größe</th><th>Instrumente</th><th>Loops</th><th>BPM</th><th>Tonarten</th><th>Formate</th><th>Original in Quelle</th></tr>';
  function zeileP(p){
    var name = p.a === 'ausgespart' ? '<b>' + esc(p.p) + '</b>' : '<a class="pk" data-p="' + esc(p.p) + '" title="Samples dieses Packs zeigen"><b>' + esc(p.p) + '</b></a>';
    return '<tr><td class="name">' + name + '<br>' + markenHtml(markenP(p)) + '</td><td>' + esc(p.a) + '</td><td class="z">' + zahl(p.n) + '</td><td class="z">' + mb((p.mb || 0) * 1048576) + '</td>' +
      '<td class="klein">' + esc(p.i) + '</td><td class="z">' + zahl(p.l) + ' %</td><td>' + esc(p.bpm) + '</td><td class="klein">' + esc(p.key) + '</td><td>' + esc(p.f) + '</td><td>' + esc(p.o) + '</td></tr>';
  }

  function gruppenKopf(id, text, L, unter, spalten){
    var zu = !offen[id];
    return '<tr class="' + (unter ? 'untergruppe' : 'gruppe') + '" data-g="' + esc(id) + '"><td colspan="' + spalten + '">' + (zu ? '▸ ' : '▾ ') + esc(text) +
      '<span class="m">' + L.length.toLocaleString('de-DE') + ' · ' + mb(sum(L,function(s){ return s.s; })) + '</span></td></tr>';
  }
  function schluessel(s, g){
    if (g === 'pack') return s.p; if (g === 'art') return s.a || '(ohne)'; if (g === 'key') return s.key || '(ohne Tonart)';
    if (g === 'bpm') { if (s.bpm == null) return '(ohne BPM)'; var b = Math.floor(s.bpm/10)*10; return b + '–' + (b+9) + ' BPM'; }
    return s.k;
  }
  function sortSchl(a,b){ var x = /^\(/.test(a), y = /^\(/.test(b); if (x !== y) return x ? 1 : -1; return String(a).localeCompare(String(b),'de',{numeric:true}); }

  function zeichneSamples(){
    var L = filterS(), g = $('gliederung').value, h = '<table>' + KOPF_S, MAX = 1500;
    $('anzahl').textContent = L.length.toLocaleString('de-DE') + ' von ' + S.length.toLocaleString('de-DE') + ' Samples';
    if (!L.length) return '<div class="leer">Keine Samples für diese Auswahl.</div>';
    var alleOffen = L.length <= 200;
    if (g === 'keine') { L.slice(0, MAX).forEach(function(s){ h += zeileS(s); }); if (L.length > MAX) h += '<tr><td colspan="10" class="leer">… und ' + (L.length - MAX) + ' weitere. Bitte Suche oder Filter verwenden.</td></tr>'; return h + '</table>'; }
    var grp = {}; L.forEach(function(s){ var k = schluessel(s,g); (grp[k] = grp[k] || []).push(s); });
    Object.keys(grp).sort(sortSchl).forEach(function(k){
      var id = g + '|' + k; if (alleOffen && offen[id] === undefined) offen[id] = true;
      h += gruppenKopf(id, k, grp[k], false, 10);
      if (!offen[id]) return;
      if (g === 'kat') {
        var u = {}; grp[k].forEach(function(s){ (u[s.i] = u[s.i] || []).push(s); });
        Object.keys(u).sort(sortSchl).forEach(function(i){
          var uid = id + '|' + i; if (alleOffen && offen[uid] === undefined) offen[uid] = true;
          if (Object.keys(u).length > 1 || i !== k) h += gruppenKopf(uid, i, u[i], true, 10); else offen[uid] = true;
          if (offen[uid]) u[i].slice(0, MAX).forEach(function(s){ h += zeileS(s); });
        });
      } else grp[k].slice(0, MAX).forEach(function(s){ h += zeileS(s); });
    });
    h += '</table>';
    if (W.length && !packFilter && !$('suche').value && !$('fProblem').checked) {
      h += '<h2>Seit der letzten Inventur entfernt (' + W.length + ')</h2><table><tr><th>Sample</th><th>Pack</th><th>früherer Pfad</th></tr>';
      W.slice(0, 500).forEach(function(w){ h += '<tr><td><b>' + esc(w.d) + '</b></td><td>' + esc(w.p) + '</td><td class="klein">' + esc(w.v) + '</td></tr>'; });
      h += '</table>';
    }
    return h;
  }
  function zeichnePacks(){
    var L = filterP().sort(function(a,b){ return a.p.localeCompare(b.p,'de',{numeric:true}); }), g = $('gliederung').value, h = '<table>' + KOPF_P;
    $('anzahl').textContent = L.length + ' von ' + P.length + ' Packs';
    if (!L.length) return '<div class="leer">Keine Packs für diese Auswahl.</div>';
    if (g === 'keine') { L.forEach(function(p){ h += zeileP(p); }); return h + '</table>'; }
    var grp = {}; L.forEach(function(p){ (grp[p.a] = grp[p.a] || []).push(p); });
    Object.keys(grp).sort(sortSchl).forEach(function(a){
      h += '<tr class="gruppe"><td colspan="10">' + esc(a) + '<span class="m">' + grp[a].length + ' Packs</span></td></tr>';
      grp[a].forEach(function(p){ h += zeileP(p); });
    });
    return h + '</table>';
  }
  function zeichneDups(){
    var L = filterS().filter(function(s){ return s.g; }), h = '';
    var grp = {}; L.forEach(function(s){ (grp[s.g] = grp[s.g] || []).push(s); });
    var ids = Object.keys(grp).sort(function(a,b){ return a-b; });
    var E = L.filter(function(s){ return s.dr === 'entfernbar'; });
    $('anzahl').textContent = ids.length + ' Gruppen · ' + E.length + ' entfernbar · ' + mb(sum(E,function(s){ return s.s; }));
    if (!ids.length) return '<div class="leer">Keine Duplikate in der Bibliothek' + (S.some(function(s){ return s.g; }) ? ' für diese Auswahl' : '') + '.</div>';
    h += '<div class="unter" style="margin-bottom:10px">Gleicher Inhalt (Größe und Prüfsumme) an mehreren Stellen. Entfernen über „Duplikate im Ziel entfernen …“ in der Oberfläche: „entfernbar“ geht in den Papierkorb, „behalten“ bleibt.</div><table>' + KOPF_S;
    var viele = ids.length > 60;
    if (viele) h = h.replace('</div><table>', ' Bei vielen Gruppen sind diese zugeklappt \u2013 zum \u00d6ffnen anklicken.</div><table>');
    ids.forEach(function(id){
      var G = grp[id];
      var gid = 'dup|' + id, zu = viele && !offen[gid];
      h += '<tr class="gruppe" data-g="' + gid + '"><td colspan="10">' + (viele ? (zu ? '\u25B8 ' : '\u25BE ') : '') + 'Gruppe ' + id + ': ' + esc(G[0].d) + '<span class="m">' + G.length + ' Exemplare \u00b7 je ' + mb(G[0].s) + '</span></td></tr>';
      if (zu) return;
      G.sort(function(a,b){ return (a.dr === 'entfernbar') - (b.dr === 'entfernbar'); }).forEach(function(s){ h += zeileS(s, true).replace('<td class="name"><b>', '<td class="name"><span class="marke ' + (s.dr === 'entfernbar' ? 'gelb' : 'gruen') + '">' + esc(s.dr) + '</span><br><b>'); });
    });
    return h + '</table>';
  }
  function zeichnen(){
    $('packChip').innerHTML = packFilter ? '<span class="chip">Pack: ' + esc(packFilter) + ' <button id="chipZu" title="Pack-Filter aufheben">×</button></span>' : '';
    if (packFilter) $('chipZu').onclick = function(){ packFilter = ''; zeichnen(); };
    ['fTyp','fKey','fFmt'].forEach(function(id){ $(id).style.display = ansicht === 'packs' ? 'none' : ''; });
    $('inhalt').innerHTML = ansicht === 'packs' ? zeichnePacks() : ansicht === 'dups' ? zeichneDups() : zeichneSamples();
  }
  function waehle(v){
    ansicht = v; setzeGliederung();
    Array.prototype.forEach.call(document.querySelectorAll('#ansicht button'), function(b){ b.classList.toggle('an', b.getAttribute('data-v') === v); });
    zeichnen();
  }
  Array.prototype.forEach.call(document.querySelectorAll('#ansicht button'), function(b){ b.addEventListener('click', function(){ waehle(b.getAttribute('data-v')); }); });
  $('suche').addEventListener('input', function(){ clearTimeout(zeit); zeit = setTimeout(zeichnen, 250); });
  ['gliederung','fKat','fArt','fTyp','fKey','fFmt','fProblem'].forEach(function(id){ $(id).addEventListener('change', zeichnen); });
  zeichnen();
})();
</script>
</body>
</html>
'@
