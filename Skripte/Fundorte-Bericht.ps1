# (c) 2026 Herbert Stoecker. Kostenlos nutzbar. Bitte nur als Link auf die offizielle Download-Seite weitergeben; Verkauf und Veroeffentlichung geaenderter Fassungen nur mit Zustimmung.
<#
.SYNOPSIS
  HTML-Vorlage des Fundort-Berichts (QLN-03). Wird von "Fundorte suchen" und vom Bericht-Dienst
  genutzt; der Dienst baut die Seite bei jedem Oeffnen aus den gespeicherten Daten (JSON) neu,
  so zeigt auch ein aelterer Bericht die aktuelle Fassung der Seite.
#>

function Get-LetzterFundortBericht {
    # Neuester Fundort-Bericht im Berichtsordner, sonst in den Programmordnern der Vorversionen
    $e = Get-Einstellungen
    $orte = @((Join-Path $e.Berichtsordner 'Fundorte'))
    try {
        $orte += @(Get-ChildItem -LiteralPath (Split-Path -Parent $wurzel) -Directory -ErrorAction SilentlyContinue | ForEach-Object { Join-Path $_.FullName 'Fundorte' })
    } catch { }
    $j = @($orte | Select-Object -Unique | Where-Object { Test-Path -LiteralPath $_ } |
        ForEach-Object { Get-ChildItem -LiteralPath $_ -Filter 'Fundorte_*.json' -File -ErrorAction SilentlyContinue } |
        Sort-Object LastWriteTime -Descending) | Select-Object -First 1
    return $j
}

function Start-FundortBericht([string]$jsonPfad) {
    # Startet den Bericht-Dienst unsichtbar; er oeffnet den Bericht im Browser
    $psExe = Join-Path $PSHOME 'powershell.exe'; if (-not (Test-Path -LiteralPath $psExe)) { $psExe = 'powershell.exe' }
    $dienst = Join-Path $PSScriptRoot 'Bericht-Dienst.ps1'
    try { Start-Process -FilePath $psExe -ArgumentList "-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File `"$dienst`" -Fundorte `"$jsonPfad`"" -WindowStyle Hidden -ErrorAction Stop; return $true }
    catch { Write-FehlerLog "Fundort-Bericht nicht startbar: $($_.Exception.Message)"; return $false }
}

function New-FundortHtml([string]$json) {
    $vorlage = @'
<!DOCTYPE html>
<html lang="de"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width, initial-scale=1">
<title>Fundorte – Samples-Werkzeuge</title>
<style>
:root{--bg:#f6f7f9;--karte:#fff;--text:#1d2433;--leise:#5f6b7a;--linie:#e2e6ec;--kopf:#eef1f5;--akzent:#1f4e79;--rot:#b42318;--rot-bg:#fde8e7;--gelb:#8a5a00;--gelb-bg:#fff4d6;--gruen:#1a7f37;--gruen-bg:#e3f5e8;--blau:#1f4e79;--blau-bg:#e4eef8;--grau-bg:#eef0f3;--lila:#6b3fa0;--lila-bg:#f1e9fa}
@media (prefers-color-scheme: dark){:root{--bg:#14171c;--karte:#1c2027;--text:#e6e9ee;--leise:#9aa4b2;--linie:#2c323c;--kopf:#232831;--akzent:#8bb8e8;--rot:#ff8a80;--rot-bg:#3a1f1f;--gelb:#ffd27a;--gelb-bg:#3a2f14;--gruen:#7ee2a0;--gruen-bg:#163322;--blau:#8bb8e8;--blau-bg:#1b2a3c;--grau-bg:#262b33;--lila:#d0b0f5;--lila-bg:#2e2340}}
*{box-sizing:border-box}body{margin:0;background:var(--bg);color:var(--text);font:14px/1.45 "Segoe UI",system-ui,sans-serif}
header{padding:22px 28px 6px}h1{margin:0;font-size:22px;color:var(--akzent)}.unter{color:var(--leise);font-size:13px;margin-top:2px}
.karten{display:flex;flex-wrap:wrap;gap:10px;padding:14px 28px}.karte{background:var(--karte);border:1px solid var(--linie);border-radius:8px;padding:10px 14px;min-width:120px}
.karte b{display:block;font-size:20px}.karte span{color:var(--leise);font-size:12px}
.werkzeuge{display:flex;flex-wrap:wrap;gap:10px;align-items:center;padding:8px 28px 12px;position:sticky;top:0;background:var(--bg);z-index:2;border-bottom:1px solid var(--linie)}
label.ck{display:flex;gap:6px;align-items:center;color:var(--leise)}
button.k{font:inherit;border:1px solid var(--linie);background:var(--karte);color:var(--text);border-radius:6px;padding:6px 12px;cursor:pointer}
button.haupt{background:var(--akzent);color:var(--karte);border-color:var(--akzent)}button:disabled{opacity:.5;cursor:default}
.erkl{flex-basis:100%;font-size:12px;color:var(--leise);margin-top:-4px}
main{padding:12px 28px 40px}table{width:100%;border-collapse:collapse;background:var(--karte);border:1px solid var(--linie)}
th,td{text-align:left;padding:7px 10px;border-bottom:1px solid var(--linie);vertical-align:top}th{background:var(--kopf);font-size:12px;color:var(--leise);font-weight:600}
td.z,th.z{text-align:right;white-space:nowrap}tr.f{cursor:pointer}button.oe{white-space:nowrap}tr.f:hover td{background:var(--kopf)}td.pfad{word-break:break-all;font-weight:600}
.art{display:inline-block;border-radius:10px;padding:1px 8px;font-size:12px;white-space:nowrap}
.a-sp{background:var(--gruen-bg);color:var(--gruen)}.a-za{background:var(--gruen-bg);color:var(--gruen);outline:1px dashed var(--gruen)}.a-ib{background:var(--gelb-bg);color:var(--gelb)}.a-al{background:var(--lila-bg);color:var(--lila)}.a-dp{background:var(--blau-bg);color:var(--blau)}.a-sy,.a-ar{background:var(--grau-bg);color:var(--leise)}
.hw{display:block;font-size:12px;color:var(--leise);font-weight:400}.hw.rot{color:var(--rot)}.hw.gruen{color:var(--gruen)}.hw.gelb{color:var(--gelb)}
.zus{display:block;font-size:11px;color:var(--leise)}
tr.detail td{background:var(--bg);font-size:13px}tr.detail table{margin:4px 0 6px;border:0}tr.detail td,tr.detail th{padding:3px 8px}
tr.weg td{opacity:.55}
.leise{color:var(--leise)}#meldung{position:fixed;bottom:18px;left:50%;transform:translateX(-50%);background:var(--akzent);color:var(--karte);padding:8px 16px;border-radius:6px;display:none;z-index:9}
.hinweis{margin:0 28px 10px;padding:8px 12px;border-radius:6px;background:var(--gelb-bg);color:var(--gelb);font-size:13px}
</style></head><body>
<header><h1>Fundorte</h1><div class="unter" id="unter"></div></header>
<div class="karten" id="karten"></div>
<div class="hinweis" id="ohneDienst" style="display:none">Dieser Bericht wurde direkt geöffnet. Zum Übernehmen als Quelle, „Ordner öffnen“ und Abgleich bitte in den Samples-Werkzeugen über „Fundorte suchen …“ → „Letzten Bericht öffnen“ öffnen.</div>
<div class="werkzeuge">
 <button class="k haupt" id="uebernehmen">In Quellenliste übernehmen (0)</button>
 <button class="k" id="abgleich">Angehakte mit Ziel-Ordner abgleichen (0)</button>
 <label class="ck"><input type="checkbox" id="klein" checked> auch kleine Fundorte zeigen (unter 5 Audiodateien)</label>
 <span class="leise" id="ausgeblendet" style="font-size:12px"></span>
 <label class="ck"><input type="checkbox" id="andere" checked> Instrument-Bibliotheken, Ableton-Library, Projekte, System zeigen</label>
 <div class="erkl">Abgleich: prüft für die angehakten Fundorte über Größe und Prüfsumme, wie viele Audiodateien schon im Ziel-Ordner liegen (<span id="zielname"></span>). Es wird nichts verändert; bei großen Fundorten dauert es etwas.</div>
</div>
<main><table><thead><tr><th><input type="checkbox" id="alle" title="Alle sichtbaren Fundorte an- oder abhaken"></th><th>Fundort</th><th>Einschätzung</th><th class="z">Audiodateien</th><th class="z">Größe</th><th>Formate</th><th>Letzte Änderung</th><th></th></tr></thead><tbody id="liste"></tbody></table>
<p class="leise" style="font-size:12px">Ein Klick auf eine Zeile zeigt Unterordner, Archive und Beispieldateien. Vorausgewählt sind Sample-Packs, die noch keine Quelle sind. Instrument-Bibliotheken gehören zu Plugins (z. B. Kontakt, Spitfire), die Ableton-Library zu Ableton – beides besser dort lassen; DAW-Projekte enthalten eigene Aufnahmen. Archive werden nur angesehen (Inhaltsverzeichnis), nicht entpackt. Gezählt werden nur Audiodateien: Programme, Installer, Plugin-Inhalte und Archive bleiben beim Sortieren liegen; bei „Nur lose Dateien“ werden nur Audio- und MIDI-Dateien übernommen.</p></main>
<div id="meldung"></div>
<script id="daten" type="application/json">__DATEN__</script>
<script>
(function(){
  var D = JSON.parse(document.getElementById('daten').textContent), F = D.f, M = D.meta, DIENST = window.SW_DIENST;
  var $ = function(id){ return document.getElementById(id); };
  var wahl = {}, offen = {}, abgl = {}, getrennt = false, sichtbar = [];
  F.forEach(function(f, i){ f.i = i; f.za = f.za || 0; f.zb = f.zb || 0; f.zo = f.zo || 0; f.zc = f.zc || 0; f.zv = f.zv || 0; if (f.vor) wahl[i] = true; });
  function esc(s){ return String(s == null ? '' : s).replace(/[&<>"]/g, function(c){ return {'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;'}[c]; }); }
  function mb(b){ b = b / 1048576; return b >= 1024 ? (b/1024).toFixed(1).replace('.', ',') + ' GB' : (b >= 10 ? Math.round(b) : b.toFixed(1).replace('.', ',')) + ' MB'; }
  function n(z){ return Number(z).toLocaleString('de-DE'); }
  function meldung(t){ var m = $('meldung'); m.textContent = t; m.style.display = 'block'; clearTimeout(m._t); m._t = setTimeout(function(){ m.style.display = 'none'; }, 3500); }
  var KL = {'Sample-Packs':'a-sp','Archive mit Samples':'a-za','Instrument-Bibliothek':'a-ib','Ableton-Library':'a-al','DAW-Projekt':'a-dp','System/Programm':'a-sy','Archive (Inhalt offen)':'a-ar','Nur Archive (ZIP)':'a-ar'};
  var IMMER = {'Sample-Packs':1,'Archive mit Samples':1,'Archive (Inhalt offen)':1,'Nur Archive (ZIP)':1};
  // anhakbar (fuer Abgleich): hat lesbare Audiodateien, Ordner gibt es noch
  function waehlbar(f){ return !f.weg && f.a > 0 && f.cl < f.a; }
  // uebernehmbar: anhakbar und noch keine (aktive) Quelle; eine deaktivierte Quelle wird wieder aktiviert
  function uebernehmbar(f){ return waehlbar(f) && (!f.st || f.st === 'schon Quelle (deaktiviert)'); }
  // klein: weniger als 5 bekannte Audiodateien (auch in Archiven) - gilt fuer alle Zeilen gleich (auch lose Dateien);
  // nur Archive mit unbekanntem Inhalt bleiben sichtbar, weil ihre Zahl nicht bekannt ist
  function klein(f){ return (f.a + f.za) < 5 && !f.zo && !f.zc && !f.zv && !(f.zip && M.ArchivInhalt === undefined); }
  var ARTEN = [['Sammlung','Sammlung'],['Pack','Ein Pack'],['Lose','Nur lose Dateien']], ARTNAME = {}; ARTEN.forEach(function(a){ ARTNAME[a[0]] = a[1]; });
  $('unter').textContent = 'Stand des Suchlaufs vom ' + M.Erstellt + ' · durchsucht: ' + M.Orte.join(', ') + ' · ' + n(M.Ordner) + ' Ordner in ' + M.Dauer + ' s' + (M.NichtLesbar ? ' · ' + M.NichtLesbar + ' Ordner nicht lesbar' : '');
  $('zielname').textContent = M.Ziel || 'eingestellter Ziel-Ordner';
  function karten(){
    var sp = F.filter(function(f){ return f.art === 'Sample-Packs'; }), a = 0, b = 0, za = 0; sp.forEach(function(f){ a += f.a; b += f.b; });
    F.forEach(function(f){ za += f.za; });
    $('karten').innerHTML = '<div class="karte"><b>' + F.length + '</b><span>Fundorte</span></div><div class="karte"><b>' + sp.length + '</b><span>davon Sample-Packs</span></div>' +
      '<div class="karte"><b>' + n(a) + '</b><span>Audiodateien in Sample-Packs</span></div><div class="karte"><b>' + mb(b) + '</b><span>Größe Sample-Packs</span></div>' +
      (za ? '<div class="karte"><b>' + n(za) + '</b><span>Audiodateien in Archiven (nicht entpackt)</span></div>' : '');
  }
  function stKlasse(st){ return st.indexOf('jetzt') === 0 || st.indexOf('wieder') === 0 || st === 'schon Quelle' ? ' gruen' : (st.indexOf('deaktiviert') >= 0 ? ' gelb' : ''); }
  var ZST = { a: '', v: 'enthält weitere Archive', c: 'nur in der Cloud – nicht geprüft', o: 'Inhalt nicht geprüft' };
  function zeichnen(){
    var zKlein = $('klein').checked, andere = $('andere').checked, h = [], aus = 0; sichtbar = [];
    F.forEach(function(f){
      if (!andere && !IMMER[f.art]) return;
      if (!zKlein && klein(f)) { aus++; return; }
      var w = waehlbar(f), hw = []; if (w) sichtbar.push(f.i);
      if (f.weg) hw.push('<span class="hw rot">Ordner gibt es nicht mehr</span>');
      if (f.st) hw.push('<span class="hw' + stKlasse(f.st) + '">' + esc(f.st) + '</span>');
      if (f.pk > 1 && f.qa === 'Sammlung') { var pn = (f.u || []).filter(function(x){ return x.a > 0; }).map(function(x){ return x.n; });
        hw.push('<span class="hw">Sammlung mit ' + f.pk + ' Packs: ' + esc(pn.slice(0, 3).join(', ')) + (f.pk > 3 ? ' und ' + (f.pk - 3) + ' weitere' : '') + '</span>'); }
      if (f.lose && f.pk) hw.push('<span class="hw">' + n(f.lose) + ' Dateien direkt im Ordner</span>');
      if (f.nl && f.a) hw.push('<span class="hw">nur die Dateien direkt in diesem Ordner, ohne Unterordner</span>');
      if (f.za) hw.push('<span class="hw rot">' + n(f.za) + ' Audiodateien in Archiven (' + mb(f.zb) + ' entpackt' + (f.zf ? ', ' + esc(f.zf) : '') + ') – liegt es im Download-Ordner: mit „Download importieren …“ übernehmen, sonst vorher entpacken</span>');
      if (f.zv) hw.push('<span class="hw rot">' + f.zv + ' Archiv(e) enthalten weitere Archive</span>');
      if (f.zc) hw.push('<span class="hw rot">' + f.zc + ' Archiv(e) nur in der Cloud – Inhalt nicht geprüft</span>');
      if (f.zo) { var gr = {}; (f.zl || []).forEach(function(x){ if (x.s === 'o' && x.g) gr[x.g] = 1; }); gr = Object.keys(gr);
        hw.push('<span class="hw rot">' + f.zo + ' Archiv(e): Inhalt nicht geprüft' + (M.ArchivInhalt === false ? ' (Hineinschauen war abgeschaltet)' : (gr.length ? ' – ' + esc(gr.join('; ')) : ' (RAR/7z ohne passendes Windows-Werkzeug, beschädigt oder verschlüsselt)')) + '</span>'); }
      if (f.zip && f.za === 0 && !f.zo && !f.zc && !f.zv) hw.push('<span class="hw rot">' + f.zip + ' Archiv(e) nicht entpackt</span>');
      if (f.cl) hw.push('<span class="hw rot">' + n(f.cl) + ' Dateien nur in der Cloud (werden nicht heruntergeladen)</span>');
      if (f.art === 'Sample-Packs' && f.pj) hw.push('<span class="hw">enthält ' + f.pj + ' Projektdatei(en), z. B. ein Demo-Projekt – die Audiodateien liegen aber überwiegend außerhalb, daher Sample-Pack</span>');
      if (f.art === 'Sample-Packs' && f.ap) hw.push('<span class="hw">enthält Ableton-Presets (.adg/.adv/.alc) – gehören zum Pack, werden beim Sortieren nicht übernommen</span>');
      if (abgl[f.i]) hw.push('<span class="hw">' + abgl[f.i] + '</span>');
      var ue = uebernehmbar(f);
      h.push('<tr class="f' + (f.weg ? ' weg' : '') + '" data-i="' + f.i + '"><td><input type="checkbox" class="w" data-i="' + f.i + '"' + (wahl[f.i] && w ? ' checked' : '') + (w ? '' : ' disabled') + '></td>' +
        '<td class="pfad">' + esc(f.p) + hw.join('') + '</td><td><span class="art ' + (KL[f.art] || '') + '">' + esc(f.art) + '</span>' +
        (!ue && f.qq ? '<br><span class="hw">' + esc(ARTNAME[f.qq] || f.qq) + '</span>' : '') +
        (ue ? '<br><select class="qa" data-i="' + f.i + '" title="Art als Quelle: Sammlung = jeder Unterordner ist ein Pack; Ein Pack = alles darin unter dem Ordnernamen; Nur lose Dateien = ohne Unterordner">' +
          ARTEN.map(function(a){ return '<option value="' + a[0] + '"' + (f.qa === a[0] ? ' selected' : '') + '>' + a[1] + '</option>'; }).join('') + '</select>' : '') + '</td>' +
        '<td class="z">' + n(f.a) + (f.za ? '<span class="zus">+ ' + n(f.za) + ' in Archiven</span>' : '') + '</td><td class="z">' + mb(f.b) + (f.zb ? '<span class="zus">+ ' + mb(f.zb) + ' entpackt</span>' : '') + '</td>' +
        '<td>' + esc(f.f) + '</td><td>' + esc(f.neu) + '</td>' +
        '<td><button class="k oe" data-i="' + f.i + '"' + (DIENST && !getrennt && !f.weg ? '' : ' disabled') + '>Ordner öffnen</button></td></tr>');
      if (offen[f.i]) {
        var u = (f.u || []).map(function(x){ return '<tr><td>' + esc(x.n) + '</td><td class="z">' + n(x.a) + (x.za ? ' + ' + n(x.za) + ' in Archiven' : '') + '</td><td class="z">' + mb(x.b) + '</td><td>' + esc(x.art) + '</td></tr>'; }).join('');
        var z = (f.zl || []).map(function(x){ return '<tr><td>' + esc(x.n) + '</td><td class="z">' + (x.s === 'a' || x.s === 'v' ? n(x.a) : '–') + '</td><td class="z">' + (x.s === 'a' || x.s === 'v' ? mb(x.b) : '–') + '</td><td>' + esc(x.s === 'o' && x.g ? 'Inhalt nicht geprüft: ' + x.g : (ZST[x.s] || '')) + '</td></tr>'; }).join('');
        h.push('<tr class="detail"><td></td><td colspan="7">' + (u ? '<table><tr><th>Unterordner</th><th class="z">Audiodateien</th><th class="z">Größe</th><th>Einschätzung</th></tr>' + u + '</table>' : '') +
          (z ? '<table><tr><th>Archiv</th><th class="z">Audiodateien darin</th><th class="z">Größe entpackt</th><th></th></tr>' + z + '</table>' : '') +
          '<span class="leise">Beispiele: ' + esc((f.bsp || []).join(' · ') || '–') + '</span></td></tr>');
      }
    });
    $('liste').innerHTML = h.join('') || '<tr><td colspan="8" class="leise">Keine Fundorte für diese Auswahl.</td></tr>';
    $('ausgeblendet').textContent = aus ? '(' + aus + ' kleine' + (aus === 1 ? 'r Fundort' : ' Fundorte') + ' ausgeblendet)' : '';
    var cU = Object.keys(wahl).filter(function(i){ return wahl[i] && uebernehmbar(F[i]); }).length;
    var cA = Object.keys(wahl).filter(function(i){ return wahl[i] && waehlbar(F[i]); }).length;
    $('uebernehmen').textContent = 'In Quellenliste übernehmen (' + cU + ')';
    $('abgleich').textContent = 'Angehakte mit Ziel-Ordner abgleichen (' + cA + ')';
    $('uebernehmen').disabled = !DIENST || getrennt || !cU; $('abgleich').disabled = !DIENST || getrennt || !cA;
    // 2.3.5: Haken in der Kopfzeile - an, wenn alle sichtbaren anhakbaren Zeilen angehakt sind
    var nA = sichtbar.filter(function(i){ return wahl[i]; }).length;
    $('alle').checked = sichtbar.length > 0 && nA === sichtbar.length; $('alle').indeterminate = nA > 0 && nA < sichtbar.length; $('alle').disabled = !sichtbar.length;
  }
  document.addEventListener('click', function(e){
    var cb = e.target.closest('input.w'); if (cb) { wahl[cb.getAttribute('data-i')] = cb.checked; zeichnen(); return; }
    if (e.target.closest('select.qa')) return;
    var oe = e.target.closest('button.oe'); if (oe) { post('/oeffnen-ort', { pfad: F[oe.getAttribute('data-i')].p }).then(function(){ meldung('Explorer wird geöffnet …'); }).catch(function(){}); return; }
    var tr = e.target.closest('tr.f'); if (tr) { var i = tr.getAttribute('data-i'); offen[i] = !offen[i]; zeichnen(); }
  });
  $('alle').addEventListener('change', function(){ var an = $('alle').checked; sichtbar.forEach(function(i){ wahl[i] = an; }); zeichnen(); });
  $('klein').addEventListener('change', zeichnen); $('andere').addEventListener('change', zeichnen);
  document.addEventListener('change', function(e){ var s = e.target.closest('select.qa'); if (!s) return; var f = F[s.getAttribute('data-i')];
    // 2.3.3: Sammelordner (Downloads, Dokumente ...) nur als "Nur lose Dateien" - sonst wird alles darin als Pack gelesen
    if (f.nl && s.value !== 'Lose' && !confirm(f.p + ' ist ein Sammelordner (z. B. Downloads). Als „' + s.options[s.selectedIndex].text + '“ würde das Sortieren alles darin lesen – auch Programme, Dokumente und fremde Unterordner – und unter einem Namen einsortieren.\n\nRichtig ist „Nur lose Dateien“; Packs darin bitte einzeln übernehmen.\n\nTrotzdem ändern?')) { s.value = f.qa; return; }
    f.qa = s.value; });
  document.addEventListener('sw-getrennt', function(){ getrennt = true; zeichnen(); });
  function post(pfad, daten){
    return fetch(pfad + '?t=' + DIENST.token, { method: 'POST', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify(daten) })
      .catch(function(err){ if (window.SW_FEHLER) window.SW_FEHLER(); throw err; })
      .then(function(r){ return r.text().then(function(t){ if (!r.ok) { meldung(t); throw new Error(t); } return t ? JSON.parse(t) : {}; }); });
  }
  $('uebernehmen').addEventListener('click', function(){
    var wa = Object.keys(wahl).filter(function(i){ return wahl[i] && uebernehmbar(F[i]); }).map(function(i){ return F[i]; });
    if (!wa.length) return;
    var NAME = {}; ARTEN.forEach(function(a){ NAME[a[0]] = a[1]; });
    if (!confirm(wa.length + ' Fundort(e) als Quelle übernehmen?\n\n' + wa.map(function(f){ return f.p + '  (' + (f.st ? 'wieder aktivieren' : NAME[f.qa]) + ')'; }).join('\n') + '\n\nEs wird nichts kopiert oder verändert; die Quellen erscheinen unter ⚙ Einstellungen.')) return;
    post('/uebernehmen', { pfade: wa.map(function(f){ return { pfad: f.p, art: f.qa }; }) }).then(function(r){
      var ok = 0, akt = 0, schon = 0, nein = [];
      (r.ergebnisse || []).forEach(function(x){ F.forEach(function(f){ if (f.p === x.pfad) {
        if (x.ok && x.aktiviert) { f.st = 'wieder aktiviert'; akt++; } else if (x.ok) { f.st = 'jetzt Quelle'; ok++; }
        else if (x.schon) { f.st = 'schon Quelle'; schon++; } else { nein.push(x.pfad + ': ' + x.grund); } } }); });
      zeichnen();
      var t = []; if (ok || (!akt && !schon)) t.push(ok + ' übernommen'); if (akt) t.push(akt + ' wieder aktiviert'); if (schon) t.push(schon + ' war(en) schon Quelle'); meldung(t.join(', ') + '.');
      if (nein.length) alert('Nicht übernommen:\n\n' + nein.join('\n'));
    }).catch(function(){});
  });
  $('abgleich').addEventListener('click', function(){
    var ix = Object.keys(wahl).filter(function(i){ return wahl[i] && waehlbar(F[i]); });
    var lauf = function(k){
      if (k >= ix.length) { meldung('Abgleich fertig.'); return; }
      var f = F[ix[k]]; abgl[f.i] = 'Abgleich läuft …'; zeichnen();
      post('/abgleich', { pfad: f.p, lose: !!f.nl }).then(function(r){
        abgl[f.i] = 'Schon im Ziel-Ordner: ' + n(r.vorhanden) + ' von ' + n(r.geprueft) + ' Audiodateien (' + (r.geprueft ? Math.round(100 * r.vorhanden / r.geprueft) : 0) + ' %)' + (r.cloud ? ', ' + n(r.cloud) + ' nur in der Cloud nicht geprüft' : '');
        zeichnen(); lauf(k + 1);
      }).catch(function(){ abgl[f.i] = 'Abgleich nicht möglich'; zeichnen(); if (!getrennt) lauf(k + 1); });
    };
    lauf(0);
  });
  if (DIENST) {
    // Status gegen die aktuelle Quellenliste neu bestimmen (Bericht kann älter sein); nicht mehr vorhandene Ordner kennzeichnen
    post('/quellen', {}).then(function(r){
      var Q = (r.quellen || []).map(function(q){ return { p: String(q.pfad).replace(/[\\\/]+$/, '').replace(/\//g, '\\').toLowerCase() + '\\', o: String(q.pfad), art: q.art, lose: q.art === 'Lose', aktiv: q.aktiv !== false }; });
      var weg = {}; (r.fehlt || []).forEach(function(p){ weg[String(p).toLowerCase()] = true; });
      F.forEach(function(f){
        f.weg = !!weg[f.p.toLowerCase()]; f.qq = '';
        var p = f.p.replace(/[\\\/]+$/, '').replace(/\//g, '\\').toLowerCase() + '\\', st = '';
        // 2.3.5: mit Pfad der Quelle und Hinweis, ob sie deaktiviert ist
        var zu = function(q){ return q.o + (q.aktiv ? '' : ' (deaktiviert)'); };
        Q.forEach(function(q){ if (st) return; if (q.p === p) { st = q.aktiv ? 'schon Quelle' : 'schon Quelle (deaktiviert)'; f.qq = q.art; } else if (p.indexOf(q.p) === 0 && !q.lose) st = 'liegt in der Quelle ' + zu(q); else if (q.p.indexOf(p) === 0 && f.qa !== 'Lose') st = 'enthält die Quelle ' + zu(q); });
        f.st = st;
      });
      zeichnen();
    }).catch(function(){});
  } else { $('ohneDienst').style.display = 'block'; }
  karten(); zeichnen();
})();
</script><footer style="color:#5E6A7A;font-size:12px;padding:8px 28px 30px">© 2026 Herbert Stöcker · <a href="https://make-some-music.de" target="_blank" rel="noopener">make-some-music.de</a></footer></body></html>
'@
    return $vorlage.Replace('__DATEN__', $json.Replace('</', '<\/'))
}
