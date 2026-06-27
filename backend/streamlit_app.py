"""Streamlit-Dashboard fuer Schaeflein LagerView.

Visualisiert dieselben Daten wie die Flutter-App direkt aus der warehouse.db
und uebernimmt die Auswertungen aus `warehouse_project/warehouse_analytics.py`
und `warehouse_heatmap.py` (Utilization, Hochfrequenz-Plaetze, Free Capacity, Smart
Relocation, ABC-Analyse).

Lokaler Start:
    streamlit run backend/streamlit_app.py

Deployment auf Streamlit Community Cloud:
    Main file path: backend/streamlit_app.py
    Die volle DB (289 MB) ist zu gross fuer Git -- entweder per `db_url` in
    .streamlit/secrets.toml als Download-URL hinterlegen oder die schlanke
    data/warehouse_sample.db nutzen (wird automatisch gefunden).
"""
from __future__ import annotations

# ===========================================================================
#  AUFBAU DIESER DATEI (zum Erklaeren / Praesentieren)
#  ---------------------------------------------------------------------------
#  1. Konstanten + Tabellennamen   -> welche DB-Tabellen gelesen werden
#  2. Uebersetzungen (TR / t())    -> DE/EN-Umschaltung der Oberflaeche
#  3. DB-Zugriff (get_db_path/...)  -> findet/laedt warehouse.db (read-only)
#  4. Lade-Funktionen (load_*)      -> SQL -> pandas DataFrame, alle @st.cache
#  5. Hilfsfunktionen               -> ABC-Klassifikation, Filter, CSV-Export
#  6. main()                        -> Sidebar-Filter, KPIs und die Tabs/Register
#
#  Roter Faden: alle Auswertungen kommen aus EINER Tabelle (PLATZ) plus den
#  Bewegungsdaten (TPA/FAHRPOS). Es wird NICHTS in die DB zurueckgeschrieben –
#  reine Lese-/Analyse-App. Dieselbe Logik steckt in der Flutter-App.
# ===========================================================================
import os
import sqlite3
import tempfile
from pathlib import Path
from urllib.request import urlretrieve

import numpy as np
import pandas as pd
import plotly.express as px
import streamlit as st
import streamlit.components.v1 as components

st.set_page_config(
    page_title="Schaeflein LagerView v1.123",
    page_icon="📦",
    layout="wide",
)

# HTML/JS-Vorlage fuer den klickbaren three.js-3D-Viewer. Die __PLATZHALTER__
# werden in main() (Tab "3D-Modell") per str.replace gefuellt:
#   __HEIGHT__  Hoehe in px        __GLB__    URL der klickbaren GLB
#   __DATA__    JSON PLATZ_ID->Werte  __LABELS__ JSON uebersetzte Beschriftungen
#   __ROTATE__  "true"/"false"     __COLORMODE__ Faerb-Modus der Plaetze:
#       'abc'   = nach berechneter ABC-Klasse (rot/gelb/gruen)
#       'picks' = Heatmap nach Pick-Haeufigkeit (ANZ_PICKS), Rang/Perzentil
#       'moves' = Heatmap nach Gesamt-Bewegungen (Picks + Nachschub), Rang
#       'none'  = Original-Material der GLB (keine Einfaerbung)
#   __HIDEGREY__ "true"/"false"    (Leistungsmodus: datenlose Plaetze ausblenden)
#   __FOCUS__   gesuchte PLATZ_ID (leer = keine Suche; Kamera springt sonst hin)
# Ablauf im Browser: GLTF laden -> Kamera einpassen -> Klick = Raycasting ->
# getroffenes Mesh hat als Namen die PLATZ_ID -> Kennzahlen aus __DATA__ ins
# Panel. KEINE React/Node-Abhaengigkeit, laeuft komplett in der iframe.
_THREE_VIEWER_HTML = """
<style>
  /* Navigations-Controller unten rechts in der Karte. */
  #nav { position:absolute; bottom:12px; right:12px; display:flex; flex-direction:column; gap:4px; z-index:5; }
  #nav .navrow { display:flex; gap:4px; }
  #nav button { width:34px; height:34px; padding:0; border:none; border-radius:6px;
    background:rgba(38,38,40,.62); color:#fff; font-size:16px; line-height:1; cursor:pointer;
    display:flex; align-items:center; justify-content:center; box-shadow:0 1px 3px rgba(0,0,0,.25);
    touch-action:none; -webkit-user-select:none; user-select:none; }
  #nav button:hover { background:rgba(38,38,40,.85); }
  #nav button:active { background:#1565c0; }
</style>
<div id="wrap" style="display:flex;flex-direction:column;gap:8px;font-family:sans-serif;">
  <div id="view" style="position:relative;height:__HEIGHT__px;background:#2b2b30;border-radius:8px;overflow:hidden;">
    <div id="loading" style="position:absolute;top:10px;left:12px;font-size:13px;color:#555;background:rgba(255,255,255,.7);padding:2px 8px;border-radius:4px;">…</div>
    <div id="legend" style="position:absolute;bottom:10px;left:12px;font-size:12px;color:#333;background:rgba(255,255,255,.88);padding:8px 10px;border-radius:6px;line-height:1.5;box-shadow:0 1px 3px rgba(0,0,0,.15);"></div>
    <div id="nav">
      <div class="navrow">
        <button data-act="rotl" title="Nach links drehen">⟲</button>
        <button data-act="fwd"  title="Vorwärts">▲</button>
        <button data-act="rotr" title="Nach rechts drehen">⟳</button>
      </div>
      <div class="navrow">
        <button data-act="left"  title="Nach links">◄</button>
        <button data-act="home"  title="Ansicht zurücksetzen">⌂</button>
        <button data-act="right" title="Nach rechts">►</button>
      </div>
      <div class="navrow">
        <button data-act="zout" title="Herauszoomen">−</button>
        <button data-act="back" title="Rückwärts">▼</button>
        <button data-act="zin"  title="Hineinzoomen">+</button>
      </div>
    </div>
  </div>
  <div id="panel" style="height:200px;background:#fff;border:1px solid #e0e0e0;border-radius:8px;padding:14px;font-size:14px;overflow:auto;"></div>
</div>
<script type="importmap">
{ "imports": {
    "three": "https://unpkg.com/three@0.160.0/build/three.module.js",
    "three/addons/": "https://unpkg.com/three@0.160.0/examples/jsm/"
}}
</script>
<script type="module">
import * as THREE from 'three';
import { OrbitControls } from 'three/addons/controls/OrbitControls.js';
import { GLTFLoader } from 'three/addons/loaders/GLTFLoader.js';

const DATA = __DATA__;
const L = __LABELS__;
const AUTOROTATE = __ROTATE__;
const COLORMODE = "__COLORMODE__";  // 'abc' | 'picks' | 'moves' | 'none'
const HIDEGREY = __HIDEGREY__;
const FOCUS = "__FOCUS__";  // gesuchte PLATZ_ID (leer = keine Suche)
const SENS = parseFloat("__SENS__") || 1;  // Maus-Empfindlichkeit (Drehen/Zoom/Pan)
const ABC_HEX = { 'A':0xc62828, 'B':0xf9a825, 'C':0x2e7d32, 'grey':0x9e9e9e };
const PID_RE = /^[0-9]{9}$/;

// Geteilte Materialien statt pro-Mesh-Klon (26k Meshes!) -> spart Speicher
// und Ladezeit; jedes Mesh bekommt nur eine Referenz, keinen eigenen Klon.
const SHARED_MAT = {
  'A': new THREE.MeshStandardMaterial({ color: ABC_HEX.A }),
  'B': new THREE.MeshStandardMaterial({ color: ABC_HEX.B }),
  'C': new THREE.MeshStandardMaterial({ color: ABC_HEX.C }),
  'grey': new THREE.MeshStandardMaterial({ color: ABC_HEX.grey }),
};

// --- Heatmap (Pick-/Bewegungs-Haeufigkeit) --------------------------------
// Faerbt Plaetze nach RANG/PERZENTIL der gewaehlten Kennzahl (nicht linear),
// damit wenige Hotspots mit sehr vielen Picks die Skala nicht "wegdruecken".
// Kalt (blau) = selten, heiss (rot) = oft. Plaetze ohne Aktivitaet (Wert 0)
// bekommen ein neutrales Grau, damit "nie bewegt" sichtbar bleibt.
const HEAT_STOPS = [
  [0.0, 0x2c7bb6], [0.25, 0x00a6ca], [0.5, 0x7fbc41],
  [0.75, 0xfdae61], [1.0, 0xd7191c],
];
const HEAT_ZERO_HEX = 0xcfd3d6;
function _lerpHex(a, b, t){
  const ar=(a>>16)&255, ag=(a>>8)&255, ab=a&255;
  const br=(b>>16)&255, bg=(b>>8)&255, bb=b&255;
  return ((Math.round(ar+(br-ar)*t))<<16)
       | ((Math.round(ag+(bg-ag)*t))<<8)
       |  (Math.round(ab+(bb-ab)*t));
}
function heatColor(t){  // t in 0..1 -> Hex
  if(t<=0) return HEAT_STOPS[0][1];
  if(t>=1) return HEAT_STOPS[HEAT_STOPS.length-1][1];
  for(let i=1;i<HEAT_STOPS.length;i++){
    if(t<=HEAT_STOPS[i][0]){
      const a=HEAT_STOPS[i-1], b=HEAT_STOPS[i];
      return _lerpHex(a[1], b[1], (t-a[0])/(b[0]-a[0]));
    }
  }
  return HEAT_STOPS[HEAT_STOPS.length-1][1];
}
// Quantisierte, GETEILTE Materialien (max 12 Stufen + 1x "keine Aktivitaet"),
// damit auch im Heatmap-Modus kein Material pro Mesh entsteht.
const HEAT_NB = 12;
const HEAT_MAT = [];
for(let i=0;i<HEAT_NB;i++){
  HEAT_MAT.push(new THREE.MeshStandardMaterial({ color: heatColor(i/(HEAT_NB-1)) }));
}
const HEAT_ZERO_MAT = new THREE.MeshStandardMaterial({ color: HEAT_ZERO_HEX });

// Kennzahl je Modus: picks = nur Entnahmen, moves = Entnahmen + Nachschub.
function heatMetric(d){
  if(COLORMODE==='picks') return (d.p||0);
  if(COLORMODE==='moves') return (d.p||0)+(d.n||0);
  return 0;
}
// Rang-Funktion: aus allen Plaetzen mit Wert>0 eine sortierte Liste bauen;
// fuer einen Wert v liefert ranker(v) das Perzentil 0..1 (Anteil aktiver
// Plaetze mit kleinerem/gleichem Wert). v<=0 -> -1 (= keine Aktivitaet).
function buildRanker(){
  const vals=[];
  for(const k in DATA){ const v=heatMetric(DATA[k]); if(v>0) vals.push(v); }
  vals.sort((a,b)=>a-b);
  const N=vals.length;
  return function(v){
    if(v<=0 || N===0) return -1;
    let lo=0, hi=N;
    while(lo<hi){ const mid=(lo+hi)>>1; if(vals[mid]<=v) lo=mid+1; else hi=mid; }
    return (lo-1)/Math.max(N-1, 1);
  };
}
// Material fuer ein Mesh im aktiven Heatmap-Modus (ranker vorab gebaut).
function heatMatFor(d, ranker){
  const t = ranker(heatMetric(d));
  if(t < 0) return HEAT_ZERO_MAT;
  return HEAT_MAT[Math.round(t*(HEAT_NB-1))];
}

const host = document.getElementById('view');
const panel = document.getElementById('panel');
const loadingEl = document.getElementById('loading');
panel.innerHTML = '<div style="color:#888;">' + L.hint + '</div>';

let W = host.clientWidth || 600, H = host.clientHeight || 600;
const scene = new THREE.Scene();
scene.background = new THREE.Color(0x2b2b30);  // dunkles Anthrazit (Plaetze heben sich ab)
const camera = new THREE.PerspectiveCamera(50, W / H, 0.1, 100000);
const renderer = new THREE.WebGLRenderer({ antialias: true, powerPreference: 'high-performance' });
renderer.setPixelRatio(Math.min(window.devicePixelRatio || 1, 1.5));
renderer.setSize(W, H);
host.appendChild(renderer.domElement);

// Render-on-Demand: nur neu zeichnen, wenn sich etwas bewegt -> im Stillstand
// keine GPU-Last. controls feuert 'change' bei jeder Kamerabewegung (auch
// waehrend des Damping-Nachlaufs).
let needsRender = true;
function requestRender(){ needsRender = true; }

scene.add(new THREE.HemisphereLight(0xffffff, 0x444444, 1.1));
const dir = new THREE.DirectionalLight(0xffffff, 1.4);
dir.position.set(1, 2, 1);
scene.add(dir);

const controls = new OrbitControls(camera, renderer.domElement);
controls.enableDamping = false;  // kein Nachziehen/Gleiten: stoppt beim Loslassen
controls.autoRotate = AUTOROTATE;
controls.autoRotateSpeed = 0.8;
// Maus-Empfindlichkeit: kleiner = Maus weiter bewegen fuer dieselbe Drehung
// (feineres, ruhigeres Navigieren). 1.0 = Standard.
controls.rotateSpeed = SENS;
controls.zoomSpeed = SENS;
controls.panSpeed = SENS;
controls.addEventListener('change', requestRender);

// --- "Schweben" durch die Regale per WASD ---------------------------------
// OrbitControls bleibt voll erhalten (Drehen per Maus + Klick). Zusaetzlich
// bewegen WASD/QE Kamera UND Orbit-Zielpunkt gemeinsam durch den Raum -> man
// fliegt in die Gaenge und kann dort weiter drehen/klicken. Kein Pointer-Lock,
// damit das Anklicken nicht kaputt geht.
const keys = {};
let moveScale = 1;  // wird nach dem Laden an die Modellgroesse angepasst
let homePos = null, homeTarget = null;  // Standard-Ansicht (Controller "Home")
function onKey(e, down){
  const k = e.key.toLowerCase();
  if(['w','a','s','d','q','e'].includes(k)){ keys[k] = down; e.preventDefault(); }
  if(e.key === 'Shift'){ keys.shift = down; }
}
window.addEventListener('keydown', (e) => onKey(e, true));
window.addEventListener('keyup', (e) => onKey(e, false));
// Canvas fokussierbar machen, damit es Tasten empfaengt.
renderer.domElement.tabIndex = 0;
renderer.domElement.addEventListener('pointerdown', () => renderer.domElement.focus());

const _fwd = new THREE.Vector3(), _right = new THREE.Vector3(), _mv = new THREE.Vector3();
function updateMovement(){
  const speed = moveScale * (keys.shift ? 3 : 1);
  _fwd.subVectors(controls.target, camera.position).normalize();
  _right.crossVectors(_fwd, camera.up).normalize();
  _mv.set(0, 0, 0);
  if(keys.w || keys.navF) _mv.addScaledVector(_fwd, speed);
  if(keys.s || keys.navB) _mv.addScaledVector(_fwd, -speed);
  if(keys.d || keys.navR) _mv.addScaledVector(_right, speed);
  if(keys.a || keys.navL) _mv.addScaledVector(_right, -speed);
  if(keys.e) _mv.y += speed;
  if(keys.q) _mv.y -= speed;
  let acted = false;
  if(_mv.lengthSq() > 0){
    camera.position.add(_mv);
    controls.target.add(_mv);  // Zielpunkt mitnehmen -> man "fliegt", Orbit bleibt
    acted = true;
  }
  // Controller: Drehen links/rechts um den Zielpunkt (Azimut um die Y-Achse).
  if(keys.rotl || keys.rotr){
    const ang = (keys.rotl ? 1 : -1) * 0.025;
    const ox = camera.position.x - controls.target.x;
    const oz = camera.position.z - controls.target.z;
    const cs = Math.cos(ang), sn = Math.sin(ang);
    camera.position.x = controls.target.x + (ox * cs - oz * sn);
    camera.position.z = controls.target.z + (ox * sn + oz * cs);
    acted = true;
  }
  // Controller: Zoom = Dolly zum/vom Zielpunkt (Fokus bleibt erhalten).
  if(keys.zin || keys.zout){
    const f = keys.zin ? 0.95 : 1.05;
    camera.position.set(
      controls.target.x + (camera.position.x - controls.target.x) * f,
      controls.target.y + (camera.position.y - controls.target.y) * f,
      controls.target.z + (camera.position.z - controls.target.z) * f
    );
    acted = true;
  }
  if(acted){ needsRender = true; }
  return acted;
}

// Standard-Ansicht wiederherstellen (Controller-Button "Home").
function homeView(){
  if(!homePos || !homeTarget) return;
  camera.position.copy(homePos);
  controls.target.copy(homeTarget);
  camera.updateProjectionMatrix();
  controls.update();
  requestRender();
}

// On-Screen-Controller unten rechts verdrahten. Halte-Buttons setzen die
// gleichen keys[] wie WASD -> die animate()-Schleife bewegt waehrend des
// Druecks. Loslassen (irgendwo) stoppt alles. "Home" ist ein Einmal-Klick.
const NAV_HOLD = { fwd:'navF', back:'navB', left:'navL', right:'navR',
                   rotl:'rotl', rotr:'rotr', zin:'zin', zout:'zout' };
const navEl = document.getElementById('nav');
if(navEl){
  navEl.querySelectorAll('button').forEach((b) => {
    const act = b.getAttribute('data-act');
    b.addEventListener('pointerdown', (e) => {
      e.preventDefault(); e.stopPropagation();
      if(act === 'home'){ homeView(); return; }
      const k = NAV_HOLD[act]; if(k){ keys[k] = true; }
    });
    // Klick nicht zum Canvas durchreichen (sonst Raycaster-Auswahl).
    b.addEventListener('click', (e) => e.stopPropagation());
  });
  // Loslassen an beliebiger Stelle -> alle Halte-Tasten zuruecksetzen.
  window.addEventListener('pointerup', () => {
    for(const a in NAV_HOLD){ keys[NAV_HOLD[a]] = false; }
  });
}

const raycaster = new THREE.Raycaster();
const pointer = new THREE.Vector2();
let selected = null, selectedOrigMat = null;
const HIGHLIGHT = new THREE.Color(0x1565c0);
const meshIndex = {};   // PLATZ_ID -> Mesh (fuer die Suche/Sprung)
let modelMaxDim = 100;  // Modellgroesse, nach dem Laden gesetzt

function fmt(v){ return (v==null) ? '—' : v; }

// Markiert genau EIN Mesh (blau) und stellt das vorige Material zurueck.
function highlightMesh(meshObj){
  if(selected && selectedOrigMat){ selected.material = selectedOrigMat; }
  selected = meshObj;
  selectedOrigMat = meshObj.material;
  const m = meshObj.material.clone();
  if(m.emissive){ m.emissive = HIGHLIGHT; m.emissiveIntensity = 0.9; }
  else { m.color = HIGHLIGHT; }
  meshObj.material = m;
}

// Springt zu einem Platz: Kamera nah heran, Platz markieren, Daten anzeigen.
const _wp = new THREE.Vector3();
function focusOnId(id){
  const mesh = meshIndex[id];
  if(!mesh){
    panel.innerHTML = '<div style="color:#c62828;">' + L.notfound + ' (' + id + ')</div>';
    return;
  }
  if(mesh.visible === false){ mesh.visible = true; }  // ggf. im Leistungsmodus versteckt
  mesh.getWorldPosition(_wp);
  controls.target.copy(_wp);
  const off = modelMaxDim * 0.05;  // nah genug, um den Platz + Nachbarn zu sehen
  camera.position.set(_wp.x + off, _wp.y + off * 0.6, _wp.z + off);
  camera.updateProjectionMatrix();
  controls.update();
  highlightMesh(mesh);
  showSlot(id);
  requestRender();
}

function showSlot(id){
  const d = DATA[id];
  let h = '<div style="font-weight:600;font-size:15px;margin-bottom:8px;">'
        + L.platz + ': ' + id + '</div>';
  if(!d){
    h += '<div style="color:#c62828;">' + L.notdb + '</div>';
  } else {
    const util = (d.u==null) ? '—' : (d.u + ' %');
    const status = d.b ? L.occupied : L.empty;
    const rows = [
      [L.pos, d.r + ' / ' + d.f + ' / ' + d.e],
      [L.abc_m, d.a],
      [L.abc_c, d.ac],
      [L.picks, d.p],
      [L.nachschub, (d.n==null?0:d.n)],
      [L.util, util],
      [L.status, status],
    ];
    if(d.mx != null) rows.push([L.cap, (d.il==null?0:d.il) + ' / ' + d.mx + ' LHM']);
    if(d.fc != null) rows.push([L.free, d.fc + ' LHM']);
    rows.push([L.locked, d.g ? L.yes : L.no]);
    if(d.lz) rows.push([L.lastacc, d.lz.split('-').reverse().join('.')]);
    if(!d.b && d.dl != null) rows.push([L.daysempty, d.dl]);
    h += '<table style="border-collapse:collapse;width:100%;">';
    for(const r of rows){
      h += '<tr><td style="color:#777;padding:3px 8px 3px 0;vertical-align:top;">'
         + r[0] + '</td><td style="text-align:right;font-weight:500;">'
         + fmt(r[1]) + '</td></tr>';
    }
    h += '</table>';
  }
  panel.innerHTML = h;
}

function pickIdFromObject(obj){
  let o = obj;
  while(o){
    if(o.name && PID_RE.test(o.name)) return o.name;
    o = o.parent;
  }
  return null;
}

function onClick(ev){
  const rect = renderer.domElement.getBoundingClientRect();
  pointer.x = ((ev.clientX - rect.left) / rect.width) * 2 - 1;
  pointer.y = -((ev.clientY - rect.top) / rect.height) * 2 + 1;
  raycaster.setFromCamera(pointer, camera);
  const hits = raycaster.intersectObjects(scene.children, true);
  for(const hit of hits){
    const id = pickIdFromObject(hit.object);
    if(id){
      highlightMesh(hit.object);
      showSlot(id);
      requestRender();
      return;
    }
  }
}
renderer.domElement.addEventListener('click', onClick);

const legendEl = document.getElementById('legend');

function fillLegend(counts){
  const fmtN = (n) => n.toLocaleString('de-DE');
  const row = (hex, label, n) =>
    '<div style="display:flex;align-items:center;gap:6px;">'
    + '<span style="width:12px;height:12px;border-radius:2px;background:' + hex + ';display:inline-block;"></span>'
    + '<span style="flex:1;">' + label + '</span>'
    + '<span style="font-weight:600;margin-left:8px;">' + fmtN(n) + '</span></div>';
  // Modus 'none': Plaetze nicht eingefaerbt -> keine Legende anzeigen.
  if(COLORMODE==='none'){ legendEl.innerHTML = ''; return; }
  // Heatmap-Modi: Farbverlauf-Balken (kalt->heiss) statt ABC-Klassen.
  if(COLORMODE==='picks' || COLORMODE==='moves'){
    const title = (COLORMODE==='moves') ? L.heat_moves : L.heat_picks;
    const stops = HEAT_STOPS.map((s) =>
      '#' + s[1].toString(16).padStart(6,'0') + ' ' + Math.round(s[0]*100) + '%'
    ).join(',');
    legendEl.innerHTML =
      '<div style="font-weight:600;margin-bottom:4px;">' + title + '</div>'
      + '<div style="width:150px;height:10px;border-radius:2px;background:linear-gradient(to right,' + stops + ');"></div>'
      + '<div style="display:flex;justify-content:space-between;width:150px;font-size:11px;color:#555;margin-bottom:4px;">'
      + '<span>' + L.heat_low + '</span><span>' + L.heat_high + '</span></div>'
      + row('#cfd3d6', L.heat_zero, counts.zero);
    return;
  }
  legendEl.innerHTML =
    '<div style="font-weight:600;margin-bottom:4px;">' + L.legend + '</div>'
    + row('#c62828', 'A', counts.A)
    + row('#f9a825', 'B', counts.B)
    + row('#2e7d32', 'C', counts.C)
    + row('#9e9e9e', L.grey, counts.grey);
}

new GLTFLoader().load('__GLB__',
  (gltf) => {
    const root = gltf.scene;
    scene.add(root);

    // Eine Traversierung: Plaetze je Klasse zaehlen und (optional) einfaerben.
    // grau = Mesh hat eine PLATZ_ID, aber keinen Datensatz in der DB.
    const counts = { A:0, B:0, C:0, grey:0, zero:0, active:0 };
    const heatOn = (COLORMODE==='picks' || COLORMODE==='moves');
    // Rang-Skala einmal aus ALLEN Plaetzen bauen (stabil, unabhaengig davon,
    // welche Meshes die GLB enthaelt).
    const ranker = heatOn ? buildRanker() : null;
    root.traverse((o) => {
      if(!o.isMesh || !o.name || !PID_RE.test(o.name)) return;
      meshIndex[o.name] = o;  // fuer die Lagerplatz-Suche
      const d = DATA[o.name];
      const cls = d ? d.ac : null;
      const key = (cls === 'A' || cls === 'B' || cls === 'C') ? cls : 'grey';
      counts[key] += 1;
      // Leistungsmodus: graue (datenlose) Plaetze ausblenden -> weniger
      // Draw-Calls. Kein Datenverlust, da grau ohnehin keine DB-Daten hat.
      if(key === 'grey' && HIDEGREY){ o.visible = false; }
      // Einfaerben ueber GETEILTE Materialien (kein Klon pro Mesh).
      if(COLORMODE==='abc'){
        o.material = SHARED_MAT[key];
      } else if(heatOn){
        if(d){
          if(heatMetric(d) > 0){ counts.active += 1; } else { counts.zero += 1; }
          o.material = heatMatFor(d, ranker);
        } else {
          counts.zero += 1;            // kein DB-Datensatz -> "keine Aktivitaet"
          o.material = HEAT_ZERO_MAT;
        }
      }
      // COLORMODE==='none' -> Original-Material der GLB bleibt unveraendert.
    });
    fillLegend(counts);

    const box = new THREE.Box3().setFromObject(root);
    const size = box.getSize(new THREE.Vector3());
    const center = box.getCenter(new THREE.Vector3());
    controls.target.copy(center);
    const maxDim = Math.max(size.x, size.y, size.z);
    modelMaxDim = maxDim;
    const dist = maxDim / (2 * Math.tan((Math.PI * camera.fov) / 360));
    camera.position.set(center.x + dist * 0.9, center.y + dist * 0.6, center.z + dist * 0.9);
    camera.near = maxDim / 1000; camera.far = maxDim * 10;
    camera.updateProjectionMatrix();
    moveScale = maxDim * 0.004;  // Flug-Geschwindigkeit relativ zur Modellgroesse
    controls.update();
    // Standard-Ansicht fuer den "Home"-Button (Controller) merken.
    homePos = camera.position.clone();
    homeTarget = controls.target.clone();
    loadingEl.style.display = 'none';
    // Gesuchten Platz anfliegen (ueberschreibt die Standard-Ansicht).
    if(FOCUS){ focusOnId(FOCUS); }
    requestRender();
  },
  (p) => {
    if(p && p.total){ loadingEl.textContent = L.loading + ' ' + Math.round(p.loaded / p.total * 100) + '%'; }
  },
  (err) => { loadingEl.textContent = 'Fehler: ' + err; }
);

function animate(){
  requestAnimationFrame(animate);
  // WASD-Flug zuerst (bewegt Kamera + Zielpunkt), dann Orbit-Update.
  const moving = updateMovement();
  // controls.update() liefert true, solange das Damping die Kamera bewegt;
  // 'change' setzt needsRender dabei ohnehin. Nur dann tatsaechlich rendern.
  const moved = controls.update();
  if(needsRender || moved || moving){
    renderer.render(scene, camera);
    needsRender = false;
  }
}
animate();

window.addEventListener('resize', () => {
  W = host.clientWidth; H = host.clientHeight;
  camera.aspect = W / H; camera.updateProjectionMatrix();
  renderer.setSize(W, H);
  requestRender();
});
</script>
"""

# Zweite 3D-Ansicht: SCHEMA, direkt aus den Daten erzeugt (kein CAD-Modell).
# Jeder DB-Platz wird eine Box, positioniert nach Regal (X) / Fach (Z) / Ebene
# (Y). Dadurch sind ALLE Plaetze sichtbar/klickbar (kein Grau, keine fehlenden
# Regale). Per InstancedMesh (1 Draw-Call) auch bei 22k Boxen fluessig.
# Platzhalter: __HEIGHT__, __DATA__ (PLATZ_ID->Werte), __LABELS__, __FOCUS__.
_SCHEMA_VIEWER_HTML = """
<div id="wrap" style="display:flex;gap:8px;height:__HEIGHT__px;font-family:sans-serif;">
  <div id="view" style="flex:3;position:relative;background:#f5f5f7;border-radius:8px;overflow:hidden;">
    <div id="loading" style="position:absolute;top:10px;left:12px;font-size:13px;color:#555;background:rgba(255,255,255,.7);padding:2px 8px;border-radius:4px;">…</div>
    <div id="legend" style="position:absolute;bottom:10px;left:12px;font-size:12px;color:#333;background:rgba(255,255,255,.88);padding:8px 10px;border-radius:6px;line-height:1.5;box-shadow:0 1px 3px rgba(0,0,0,.15);"></div>
  </div>
  <div id="panel" style="flex:1;min-width:230px;max-width:320px;background:#fff;border:1px solid #e0e0e0;border-radius:8px;padding:14px;font-size:14px;overflow:auto;"></div>
</div>
<script type="importmap">
{ "imports": {
    "three": "https://unpkg.com/three@0.160.0/build/three.module.js",
    "three/addons/": "https://unpkg.com/three@0.160.0/examples/jsm/"
}}
</script>
<script type="module">
import * as THREE from 'three';
import { OrbitControls } from 'three/addons/controls/OrbitControls.js';

const DATA = __DATA__;
const L = __LABELS__;
const FOCUS = "__FOCUS__";
const COLORMODE = "__COLORMODE__";    // 'neutral' | 'abc' | 'util' | 'occ'
const ABC_HEX = { 'A':0xc62828, 'B':0xf9a825, 'C':0x2e7d32, 'grey':0x9e9e9e };
const WOOD = 0xc19a6b;                // neutrale Paletten-Farbe
const OCC_HEX = { occ:0xef6c00, empty:0xbdbdbd };
// Auslastung -> Ampelfarbe (gruen 0 % -> gelb 60 % -> rot 120 %+); ohne Wert grau.
function utilColor(u){
  if(u==null) return 0x9e9e9e;
  const x = Math.max(0, Math.min(120, u))/120;
  const r = x<0.5 ? Math.round(2*x*255) : 255;
  const g = x<0.5 ? 205 : Math.round((1-(x-0.5)*2)*205);
  return (r<<16)|(g<<8)|0x22;
}
function colorFor(d){
  if(COLORMODE==='abc'){ const k=(d.ac==='A'||d.ac==='B'||d.ac==='C')?d.ac:'grey'; return ABC_HEX[k]; }
  if(COLORMODE==='util'){ return utilColor(d.u); }
  if(COLORMODE==='occ'){ return d.b ? OCC_HEX.occ : OCC_HEX.empty; }
  return WOOD;
}

const host = document.getElementById('view');
const panel = document.getElementById('panel');
const loadingEl = document.getElementById('loading');
const legendEl = document.getElementById('legend');
panel.innerHTML = '<div style="color:#888;">' + L.hint + '</div>';

let W = host.clientWidth || 600, H = host.clientHeight || 600;
const scene = new THREE.Scene();
scene.background = new THREE.Color(0xf5f5f7);
const camera = new THREE.PerspectiveCamera(50, W / H, 0.1, 100000);
const renderer = new THREE.WebGLRenderer({ antialias: true, powerPreference: 'high-performance' });
renderer.setPixelRatio(Math.min(window.devicePixelRatio || 1, 1.5));
renderer.setSize(W, H);
renderer.toneMapping = THREE.ACESFilmicToneMapping;
renderer.toneMappingExposure = 1.15;
host.appendChild(renderer.domElement);

let needsRender = true;
function requestRender(){ needsRender = true; }

scene.add(new THREE.HemisphereLight(0xffffff, 0x9aa0a6, 1.0));
const dir = new THREE.DirectionalLight(0xffffff, 1.1);
dir.position.set(1, 2, 1); scene.add(dir);
const dir2 = new THREE.DirectionalLight(0xffffff, 0.5);  // Gegenlicht/Fill
dir2.position.set(-1, 1.2, -1); scene.add(dir2);
scene.add(new THREE.AmbientLight(0xffffff, 0.25));

const controls = new OrbitControls(camera, renderer.domElement);
controls.enableDamping = false;
controls.addEventListener('change', requestRender);

// WASD-Flug (wie CAD-Ansicht)
const keys = {};
let moveScale = 1;
function onKey(e, down){
  const k = e.key.toLowerCase();
  if(['w','a','s','d','q','e'].includes(k)){ keys[k] = down; e.preventDefault(); }
  if(e.key === 'Shift'){ keys.shift = down; }
}
window.addEventListener('keydown', (e) => onKey(e, true));
window.addEventListener('keyup', (e) => onKey(e, false));
renderer.domElement.tabIndex = 0;
renderer.domElement.addEventListener('pointerdown', () => renderer.domElement.focus());
const _fwd = new THREE.Vector3(), _right = new THREE.Vector3(), _mv = new THREE.Vector3();
function updateMovement(){
  const speed = moveScale * (keys.shift ? 3 : 1);
  _fwd.subVectors(controls.target, camera.position).normalize();
  _right.crossVectors(_fwd, camera.up).normalize();
  _mv.set(0,0,0);
  if(keys.w) _mv.addScaledVector(_fwd, speed);
  if(keys.s) _mv.addScaledVector(_fwd, -speed);
  if(keys.d) _mv.addScaledVector(_right, speed);
  if(keys.a) _mv.addScaledVector(_right, -speed);
  if(keys.e) _mv.y += speed;
  if(keys.q) _mv.y -= speed;
  if(_mv.lengthSq() === 0) return false;
  camera.position.add(_mv); controls.target.add(_mv); needsRender = true; return true;
}

function fmt(v){ return (v==null) ? '—' : v; }
function showSlot(id){
  const d = DATA[id];
  let h = '<div style="font-weight:600;font-size:15px;margin-bottom:8px;">' + L.platz + ': ' + id + '</div>';
  if(!d){ h += '<div style="color:#c62828;">' + L.notdb + '</div>'; }
  else {
    const util = (d.u==null) ? '—' : (d.u + ' %');
    const status = d.b ? L.occupied : L.empty;
    const rows = [[L.pos, d.r+' / '+d.f+' / '+d.e],[L.abc_m,d.a],[L.abc_c,d.ac],[L.picks,d.p],[L.util,util],[L.status,status]];
    if(d.mx != null) rows.push([L.cap, (d.il==null?0:d.il) + ' / ' + d.mx + ' LHM']);
    if(d.fc != null) rows.push([L.free, d.fc + ' LHM']);
    rows.push([L.locked, d.g ? L.yes : L.no]);
    if(d.lz) rows.push([L.lastacc, d.lz.split('-').reverse().join('.')]);
    if(!d.b && d.dl != null) rows.push([L.daysempty, d.dl]);
    h += '<table style="border-collapse:collapse;width:100%;">';
    for(const r of rows){ h += '<tr><td style="color:#777;padding:3px 8px 3px 0;vertical-align:top;">'+r[0]+'</td><td style="text-align:right;font-weight:500;">'+fmt(r[1])+'</td></tr>'; }
    h += '</table>';
  }
  panel.innerHTML = h;
}
function fillLegend(counts, nOcc, nEmp, total){
  const fmtN = (n) => n.toLocaleString('de-DE');
  const row = (hex, label, n) => '<div style="display:flex;align-items:center;gap:6px;"><span style="width:12px;height:12px;border-radius:2px;background:'+hex+';display:inline-block;"></span><span style="flex:1;">'+label+'</span><span style="font-weight:600;margin-left:8px;">'+fmtN(n)+'</span></div>';
  const head = '<div style="font-weight:600;margin-bottom:4px;">'+L.legend+'</div>';
  if(COLORMODE==='abc'){
    legendEl.innerHTML = head+row('#c62828','A',counts.A)+row('#f9a825','B',counts.B)+row('#2e7d32','C',counts.C);
  } else if(COLORMODE==='occ'){
    legendEl.innerHTML = head+row('#ef6c00',L.occupied,nOcc)+row('#bdbdbd',L.empty,nEmp);
  } else if(COLORMODE==='util'){
    legendEl.innerHTML = head+'<div style="display:flex;align-items:center;gap:6px;"><span style="width:64px;height:12px;border-radius:2px;display:inline-block;background:linear-gradient(90deg,#33cc22,#ffd622,#ff3322);"></span><span style="flex:1;">0–120 %</span></div>';
  } else {
    legendEl.innerHTML = '<div style="font-weight:600;">'+L.legend+': '+fmtN(total)+'</div>';
  }
}

// --- Layout aus den Daten bauen -------------------------------------------
const ids = Object.keys(DATA);
// Sonderplaetze (REGAL 0: VA/EN/VD/GS = Versand/Eingang etc.) haben kein
// echtes Regal-Raster -> als kompakter Block, nicht als Turm.
const specialIds = ids.filter(id => DATA[id].r === 0);
const gridIds = ids.filter(id => DATA[id].r !== 0);
const rackFach = {};
gridIds.forEach(id => { const d = DATA[id]; (rackFach[d.r] = rackFach[d.r] || new Set()).add(d.f); });
const regals = Object.keys(rackFach).map(Number).sort((a,b) => a-b);
// Regale entlang X aufreihen (eine Halle, keine Hallen-Trennung).
const rackX = {}; let _xi = 0;
regals.forEach(r => { rackX[r] = _xi; _xi += 1; });
const fachCol = {};
regals.forEach(r => { const arr=[...rackFach[r]].sort((a,b)=>a-b); const m={}; arr.forEach((f,i)=>m[f]=i); fachCol[r]=m; });
const CELL_ = 1.0;
const SPECIAL_X = -CELL_ * 5;        // Sonderblock links vom ersten Regal
const specialPos = {};               // id -> {c: Spalte, e: Reihe} (4 Reihen)
specialIds.forEach((id,k) => { specialPos[id] = { c: Math.floor(k/4), e: k%4 }; });

const AISLE = __AISLE__;              // Gang-Breiten-Faktor (nur visuell)
const CELL = 1.0, BAY = 3, BAY_GAP = 0.6, RACK_PITCH = 3.6 * AISLE;
const BOX_D = 1.5, BOX_H = 0.78, BOX_W = 0.82;   // Palette: Tiefe(X)/Hoehe(Y)/Breite(Z)
function zForCol(c){ return c*CELL + Math.floor(c/BAY)*BAY_GAP; }  // Bays mit Luecke

const N = ids.length;
const geo = new THREE.BoxGeometry(BOX_D, BOX_H, BOX_W);
const mat = new THREE.MeshStandardMaterial({ roughness: 0.8 });
const inst = new THREE.InstancedMesh(geo, mat, N);
inst.frustumCulled = false;
const dummy = new THREE.Object3D();
const idByInst = new Array(N), instById = {}, pos = new Array(N), baseColor = new Array(N);
const counts = { A:0, B:0, C:0 }; let nOcc=0, nEmp=0;
const col = new THREE.Color();
const rackMaxCol = {}, rackMaxY = {};  // max Spalte/Ebene je Regal (fuer Struktur)
let gMinX=1e9, gMaxX=-1e9, gMinZ=1e9, gMaxZ=-1e9;
for(let i=0; i<N; i++){
  const id = ids[i], d = DATA[id];
  let x, y, z;
  if(d.r === 0){                       // Sonderplatz -> kompakter Block
    const sp = specialPos[id];
    x = SPECIAL_X; z = zForCol(sp.c); y = sp.e * CELL;
  } else {                             // normales Regal
    const cidx = fachCol[d.r][d.f];
    x = rackX[d.r] * RACK_PITCH; z = zForCol(cidx); y = d.e * CELL;
    if(cidx > (rackMaxCol[d.r]||0)) rackMaxCol[d.r] = cidx;
    if(y > (rackMaxY[d.r]||0)) rackMaxY[d.r] = y;
  }
  dummy.position.set(x, y, z); dummy.updateMatrix(); inst.setMatrixAt(i, dummy.matrix);
  const key = (d.ac==='A'||d.ac==='B'||d.ac==='C') ? d.ac : 'grey';
  if(counts[key]!=null) counts[key]++;
  if(d.b) nOcc++; else nEmp++;
  const cval = colorFor(d);
  col.setHex(cval); inst.setColorAt(i, col);
  baseColor[i] = cval; idByInst[i] = id; instById[id] = i; pos[i] = {x,y,z};
  if(x<gMinX) gMinX=x; if(x>gMaxX) gMaxX=x;
  if(z<gMinZ) gMinZ=z; if(z>gMaxZ) gMaxZ=z;
}
inst.instanceMatrix.needsUpdate = true;
if(inst.instanceColor) inst.instanceColor.needsUpdate = true;
scene.add(inst);

// Paletten-Sockel (dunkles Holz) unter jeder Palette -> 3D/Paletten-Look
const baseInst = new THREE.InstancedMesh(
  new THREE.BoxGeometry(BOX_D*1.02, 0.12, BOX_W*1.05),
  new THREE.MeshStandardMaterial({ color: 0x6d4c41, roughness: 0.95 }), N);
baseInst.frustumCulled = false;
for(let i=0; i<N; i++){
  const p = pos[i];
  dummy.position.set(p.x, p.y - BOX_H/2 - 0.07, p.z); dummy.updateMatrix();
  baseInst.setMatrixAt(i, dummy.matrix);
}
baseInst.instanceMatrix.needsUpdate = true;
scene.add(baseInst);
fillLegend(counts, nOcc, nEmp, N);
loadingEl.style.display = 'none';

// --- Lager-Optik: Boden, Regal-Rahmen, Regal-Beschriftung -----------------
const floor = new THREE.Mesh(
  new THREE.PlaneGeometry((gMaxX-gMinX)+8, (gMaxZ-gMinZ)+8),
  new THREE.MeshStandardMaterial({ color: 0xe4e4e7, roughness: 1.0 })
);
floor.rotation.x = -Math.PI/2;
floor.position.set((gMinX+gMaxX)/2, -CELL*0.6, (gMinZ+gMaxZ)/2);
scene.add(floor);
// dezentes Boden-Raster fuer Tiefenwirkung
const gsize = Math.max((gMaxX-gMinX), (gMaxZ-gMinZ)) + 10;
const grid = new THREE.GridHelper(gsize, Math.round(gsize/2), 0xb0bec5, 0xcfd8dc);
grid.position.set((gMinX+gMaxX)/2, -CELL*0.58, (gMinZ+gMaxZ)/2);
scene.add(grid);

// Regalstruktur im Pallet-Racking-Look: vertikale Staender + horizontale
// Querträger (wie im CAD). Beides via InstancedMesh -> performant.
const upM = [], beamM = [];
const _q = new THREE.Quaternion(), _sc = new THREE.Vector3(), _pp = new THREE.Vector3();
function pushBox(arr, px, py, pz, sx, sy, sz){
  const m = new THREE.Matrix4(); _pp.set(px,py,pz); _sc.set(sx,sy,sz);
  m.compose(_pp, _q, _sc); arr.push(m);
}
const frameGroup = new THREE.Group();
function makeLabel(text){
  const c = document.createElement('canvas'); c.width = 128; c.height = 64;
  const ctx = c.getContext('2d');
  ctx.fillStyle = 'rgba(255,255,255,0.9)'; ctx.fillRect(0,0,128,64);
  ctx.strokeStyle = '#9e9e9e'; ctx.strokeRect(1,1,126,62);
  ctx.fillStyle = '#263238'; ctx.font = 'bold 34px sans-serif';
  ctx.textAlign = 'center'; ctx.textBaseline = 'middle'; ctx.fillText(text, 64, 34);
  return new THREE.Sprite(new THREE.SpriteMaterial({ map: new THREE.CanvasTexture(c) }));
}
regals.forEach(r => {
  const x = rackX[r] * RACK_PITCH;
  const ncols = Object.keys(fachCol[r]).length;
  const zmax = zForCol(ncols - 1), ymax = rackMaxY[r] || 0;
  const levels = Math.round(ymax / CELL);
  const postH = ymax + CELL;
  const px = BOX_D/2 + 0.05;
  // Staender an jeder Bay-Grenze, beidseitig
  for(let c = 0; c < ncols; c += BAY){
    const zc = zForCol(c) - CELL*0.5 - BAY_GAP*0.4;
    pushBox(upM, x-px, ymax/2, zc, 0.14, postH, 0.14);
    pushBox(upM, x+px, ymax/2, zc, 0.14, postH, 0.14);
  }
  const zEnd = zmax + CELL*0.5;
  pushBox(upM, x-px, ymax/2, zEnd, 0.14, postH, 0.14);
  pushBox(upM, x+px, ymax/2, zEnd, 0.14, postH, 0.14);
  // Querträger je Ebene (Fachboden, knapp unter den Paletten)
  for(let e = 0; e <= levels; e++){
    const by = e*CELL - BOX_H/2 - 0.08;
    pushBox(beamM, x-px, by, zmax/2, 0.1, 0.1, zmax + CELL);
    pushBox(beamM, x+px, by, zmax/2, 0.1, 0.1, zmax + CELL);
  }
  const lab = makeLabel('R' + r);
  lab.position.set(x, ymax + CELL*2.2, -CELL*1.5);
  lab.scale.set(3, 1.5, 1);
  frameGroup.add(lab);
});
if(specialIds.length){   // Beschriftung fuer den Sonderplatz-Block
  const sl = makeLabel('Sonder');
  sl.position.set(SPECIAL_X, 4*CELL, -CELL*1.5);
  sl.scale.set(3.5, 1.7, 1);
  frameGroup.add(sl);
}
function makeInstanced(mats, hex, metal, rough){
  const im = new THREE.InstancedMesh(new THREE.BoxGeometry(1,1,1),
    new THREE.MeshStandardMaterial({ color: hex, metalness: metal, roughness: rough }),
    mats.length);
  im.frustumCulled = false;
  mats.forEach((m,i) => im.setMatrixAt(i, m));
  im.instanceMatrix.needsUpdate = true;
  return im;
}
scene.add(makeInstanced(upM, 0x455a64, 0.1, 0.7));   // Staender stahlblau
scene.add(makeInstanced(beamM, 0xfb8c00, 0.1, 0.6)); // Träger orange
scene.add(frameGroup);

// Kamera einpassen
const box = new THREE.Box3().setFromObject(inst);
const size = box.getSize(new THREE.Vector3());
const center = box.getCenter(new THREE.Vector3());
controls.target.copy(center);
const maxDim = Math.max(size.x, size.y, size.z);
moveScale = maxDim * 0.004;
const dist = maxDim / (2 * Math.tan((Math.PI * camera.fov) / 360));
// Schraege 3/4-Ansicht von vorne-oben (aehnlich der CAD-Ansicht)
camera.position.set(center.x + dist*0.45, center.y + dist*0.40, center.z - dist*0.85);
camera.near = Math.max(maxDim/1000, 0.1); camera.far = maxDim * 10;
camera.updateProjectionMatrix(); controls.update();

// Auswahl/Markierung per Instanz-Farbe
let selInst = -1;
function selectInstance(i){
  if(selInst >= 0){ col.setHex(baseColor[selInst]); inst.setColorAt(selInst, col); }
  selInst = i; col.setHex(0x1565c0); inst.setColorAt(i, col);
  inst.instanceColor.needsUpdate = true;
  showSlot(idByInst[i]); requestRender();
}
const raycaster = new THREE.Raycaster();
const pointer = new THREE.Vector2();
renderer.domElement.addEventListener('click', (ev) => {
  const rect = renderer.domElement.getBoundingClientRect();
  pointer.x = ((ev.clientX-rect.left)/rect.width)*2 - 1;
  pointer.y = -((ev.clientY-rect.top)/rect.height)*2 + 1;
  raycaster.setFromCamera(pointer, camera);
  const hit = raycaster.intersectObject(inst, false)[0];
  if(hit && hit.instanceId != null){ selectInstance(hit.instanceId); }
});

function focusOnId(id){
  const i = instById[id];
  if(i == null){ panel.innerHTML = '<div style="color:#c62828;">'+L.notfound+' ('+id+')</div>'; return; }
  const p = pos[i]; controls.target.set(p.x, p.y, p.z);
  const off = Math.max(maxDim * 0.04, 4);
  camera.position.set(p.x + off, p.y + off*0.6, p.z + off);
  camera.updateProjectionMatrix(); controls.update();
  selectInstance(i);
}
if(FOCUS){ focusOnId(FOCUS); }
requestRender();

function animate(){
  requestAnimationFrame(animate);
  const moving = updateMovement();
  const moved = controls.update();
  if(needsRender || moved || moving){ renderer.render(scene, camera); needsRender = false; }
}
animate();
window.addEventListener('resize', () => {
  W = host.clientWidth; H = host.clientHeight;
  camera.aspect = W/H; camera.updateProjectionMatrix(); renderer.setSize(W, H); requestRender();
});
</script>
"""

# --- DB-Tabellen (Lager BER03) --------------------------------------------
# PLATZ   = ein Datensatz je Stellplatz (Stammdaten + Auslastung + ABC)
# PALETTE = Palettenbestand (aktuell nicht ausgewertet, nur zur Doku)
# TPA     = Transport-/Pick-Auftragspositionen = die Bewegungen (6 Monate)
# FAHRPOS = Fahrpositionen; Q_PLATZ = Quellplatz -> daraus Pick-Frequenz
PLATZ_TABLE = "df_platz_ber03_schlg_rti3"
PALETTE_TABLE = "df_palette_08042026_ber03_schlg_rti3"
TPA_TABLE = "df_tpa_6mon_ber03_schlg_rti3"
FAHRPOS_TABLE = "df_fahrpos_6mon_ber03_schlg_rti3"

# Such-Reihenfolge fuer die lokale DB. Der erste existierende Pfad gewinnt;
# wird keiner gefunden, faellt get_db_path() auf den Download per URL zurueck.
_DB_CANDIDATES = [
    Path("data/warehouse.db"),
    Path("backend/data/warehouse.db"),
    Path("data/warehouse_sample.db"),
    Path("backend/data/warehouse_sample.db"),
    Path("warehouse.db"),
]

# --- Zweisprachigkeit (DE/EN) ---------------------------------------------
# Muster: TR[schluessel][sprache] = Text. t("schluessel") liest mit dem global
# gesetzten _LANG den passenden Text. Neue UI-Texte hier eintragen, im Code nur
# noch t("...") verwenden. Tabellen-Spaltennamen (Datenfelder) bleiben bewusst
# unuebersetzt, damit sie zur DB passen.
_LANG = "de"
# Menschenlesbare Beschreibung der aktuell aktiven Sidebar-Filter. Wird in
# main() gesetzt und von _csv_download() als Kommentarzeile in jede CSV
# geschrieben -> Downloads sind "unter Angabe der Filter" nachvollziehbar.
_FILTER_LABEL = ""

TR: dict[str, dict[str, str]] = {
    "caption": {
        "de": "Lager BER03 — Live-Auswertung aus warehouse.db",
        "en": "Warehouse BER03 — live analysis from warehouse.db",
    },
    "lang_label": {"de": "🌐 Sprache / Language", "en": "🌐 Sprache / Language"},
    "filter": {"de": "Filter", "en": "Filters"},
    "abc": {"de": "ABC-Klasse", "en": "ABC class"},
    "abc_help": {
        "de": "Filtert die ausgewaehlten Klassen je nach gewaehlter Quelle "
              "(Stamm-ABC, berechnete ABC oder beide).",
        "en": "Filters the selected classes by the chosen source "
              "(master ABC, calculated ABC or both).",
    },
    "abc_src": {"de": "ABC-Quelle", "en": "ABC source"},
    "abc_src_help": {
        "de": "Worauf sich die ABC-Auswahl bezieht: **Stamm** = im WMS hinterlegte "
              "Klasse, **Berechnet** = aus tatsaechlichen Picks (Pareto 80/95 %), "
              "**Beide** = Platz zaehlt, wenn Stamm ODER Berechnet passt.",
        "en": "What the ABC selection refers to: **Master** = class stored in the "
              "WMS, **Calculated** = from actual picks (Pareto 80/95 %), "
              "**Both** = slot counts if master OR calculated matches.",
    },
    "abc_src_stamm": {"de": "Stamm", "en": "Master"},
    "abc_src_calc": {"de": "Berechnet", "en": "Calculated"},
    "abc_src_both": {"de": "Beide", "en": "Both"},
    "util": {"de": "Auslastung (%)", "en": "Utilization (%)"},
    "util_help": {
        "de": "Wie voll ein Platz ist: belegte Menge geteilt durch Kapazität, mal 100. "
              "0 = leer, 100 = voll. Der obere Reglerwert 100 meint „100 % und mehr\", "
              "damit auch die wenigen Plätze über 100 % (Kapazität zu niedrig gepflegt) "
              "mit dabei bleiben.",
        "en": "How full a slot is: amount stored divided by capacity, times 100. "
              "0 = empty, 100 = full. The upper slider value 100 means \"100 % and "
              "above\", so the few slots over 100 % (capacity set too low) stay "
              "included.",
    },
    "only_occ": {"de": "Nur belegte Plaetze", "en": "Occupied slots only"},
    "place_filter": {
        "de": "Platz-Filter (Regal/Ebene/Picks/Sperre)",
        "en": "Slot filter (rack/level/picks/lock)",
    },
    "rack": {"de": "Regal", "en": "Rack"},
    "level": {"de": "Ebene", "en": "Level"},
    "level_help": {
        "de": "Die Regalebene. Der Regler endet bei der höchsten Ebene, auf der "
              "wirklich viele Plätze liegen (mindestens 20). Einzelne Ausreißer ganz "
              "oben blähen die Skala so nicht auf.",
        "en": "The rack level. The slider stops at the highest level that actually "
              "holds many slots (at least 20), so single outliers at the very top "
              "don't inflate the scale.",
    },
    "min_picks": {"de": "Min. Picks (ANZ_PICKS)", "en": "Min. picks (ANZ_PICKS)"},
    "lock_status": {"de": "Sperr-Status", "en": "Lock status"},
    "lock_all": {"de": "Alle", "en": "All"},
    "lock_only": {"de": "Nur gesperrte", "en": "Locked only"},
    "lock_without": {"de": "Ohne gesperrte", "en": "Exclude locked"},
    "tp_period": {"de": "Zeitraum (Tage)", "en": "Period (days)"},
    "top_count": {"de": "Top-Artikel anzeigen", "en": "Show top items"},
    "top_show_all": {"de": "Alle Artikel anzeigen", "en": "Show all articles"},
    "top_show_all_h": {
        "de": "Zeigt in der Tabelle ALLE Artikel statt nur der Top-N (Regler). "
              "Das Diagramm bleibt auf die Top-25 begrenzt (mehr Balken wären "
              "unleserlich).",
        "en": "Shows ALL articles in the table instead of just the top N (slider). "
              "The chart stays limited to the top 25 (more bars would be unreadable).",
    },
    "top_dl_all": {
        "de": "Diagramm/Tabelle zeigen die Top-N (Regler). Der **CSV-Download "
              "enthält ALLE {n} Artikel**, unabhängig vom Regler.",
        "en": "Chart/table show the top N (slider). The **CSV download contains ALL "
              "{n} articles**, regardless of the slider.",
    },
    "m_slots": {"de": "Stellplaetze", "en": "Slots"},
    "m_occupied": {"de": "Belegt", "en": "Occupied"},
    "m_avg_util": {"de": "Ø Auslastung", "en": "Avg. utilization"},
    "m_avg_stock": {"de": "Ø Bestand / Platz", "en": "Avg. stock / slot"},
    # KPI-Hilfetexte (Tooltip am ?-Symbol der Kacheln)
    "m_slots_help": {
        "de": "So viele Stellplaetze sind aktuell ausgewaehlt (nach den Filtern).",
        "en": "How many slots are currently selected (after the filters).",
    },
    "m_occupied_help": {
        "de": "Plaetze, auf denen mindestens 1 Ladehilfsmittel steht (auch teilweise "
              "gefuellte zaehlen mit). Der Prozentwert ist ihr Anteil an allen "
              "Plaetzen; die Zeile darunter teilt sie in voll und noch-mit-Platz auf.",
        "en": "Slots holding at least 1 load unit (partially filled ones count too). "
              "The percentage is their share of all slots; the line below splits them "
              "into full and room-left.",
    },
    "m_occupied_split": {
        "de": "davon voll: {full} · noch Platz: {partial}",
        "en": "of which full: {full} · room left: {partial}",
    },
    "m_avg_util_help": {
        "de": "Durchschnittliche Fuellung ueber alle ausgewaehlten Plaetze.",
        "en": "Average fill level across all selected slots.",
    },
    "m_avg_stock_help": {
        "de": "Wie viele Ladehilfsmittel (Paletten/Behaelter) im Schnitt auf einem "
              "Platz stehen – Summe Bestand geteilt durch Anzahl Plaetze. Leere "
              "Plaetze zaehlen mit (ziehen den Schnitt nach unten).",
        "en": "Average number of load units (pallets/bins) per slot – total stock "
              "divided by number of slots. Empty slots are included (they lower the "
              "average).",
    },
    # Tab-Titel
    "tab_halls": {"de": "Übersicht", "en": "Overview"},
    "tab_misc": {"de": "Sonstiges", "en": "Other"},
    "tab_pick": {"de": "Pick-Heatmap", "en": "Pick heatmap"},
    "tab_bottle": {"de": "Hochfrequenz-Plätze", "en": "High-frequency slots"},
    "tab_free": {"de": "Free Capacity", "en": "Free capacity"},
    "tab_relocate": {"de": "🔄 Umlagern", "en": "🔄 Relocate"},
    "tab_replenish": {"de": "⬆️ Nachschub", "en": "⬆️ Replenish"},
    "tab_putaway": {"de": "📥 Einlagern", "en": "📥 Put-away"},
    "tab_retrieve": {"de": "📤 Auslagern", "en": "📤 Retrieve"},
    "tab_abc": {"de": "ABC-Analyse", "en": "ABC analysis"},
    "tab_tp": {"de": "Tagesbewegungen", "en": "Daily movements"},
    "tab_top": {"de": "Top-Artikel", "en": "Top items"},
    "tab_3d": {"de": "3D-Modell", "en": "3D model"},
    # gemeinsame Maßnahmen-Strings
    "cat_slots": {"de": "Plaetze", "en": "Slots"},
    "cat_empty": {
        "de": "Keine Plaetze in dieser Kategorie (mit aktuellen Filtern).",
        "en": "No slots in this category (with current filters).",
    },
    "dl": {"de": "⬇️ Als CSV", "en": "⬇️ As CSV"},
    # Tab-Erklaerungen / Ueberschriften
    "halls_intro": {
        "de": "### 📊 Lager-Übersicht\n**Belegung, Auslastung und ABC-Verteilung** "
              "für das ganze Lager BER03 auf einen Blick (eine Halle, keine Trennung).",
        "en": "### 📊 Warehouse overview\n**Occupancy, utilization and ABC "
              "distribution** for the whole warehouse BER03 at a glance (single hall).",
    },
    "halls_info_t": {
        "de": "ℹ️ Was bedeutet das? — zentrale Begriffe (gelten für ALLE Tabs)",
        "en": "ℹ️ What does this mean? — central terms (apply to ALL tabs)",
    },
    "halls_info_b": {
        "de": "Diese Übersicht fasst das **ganze (gefilterte) Lager** zusammen. Die wichtigsten Begriffe gelten in "
              "**allen Tabs** gleich:\n\n"
              "- **Belegt** = auf dem Platz steht mindestens eine Palette oder ein Behälter. Das zählt schon, wenn "
              "der Platz nur teilweise gefüllt ist – nicht erst, wenn er voll ist.\n"
              "- **Frei / leer** = es passt noch etwas drauf. **Ganz leer** heißt: gar nichts steht drauf.\n"
              "- **Auslastung** = wie voll der Platz ist, in Prozent (0 % = leer, 100 % = voll). Die Ø Auslastung ist "
              "der Durchschnitt über alle Plätze.\n"
              "- **Kapazität** = wie viele Paletten oder Behälter auf einen Platz passen. Das können auch mehrere "
              "sein, nicht nur einer.\n"
              "- **Pick / Bewegung** = eine einzelne Entnahme – also eine Position eines Auftrags. *Ob eine Position "
              "genau einer Orderzeile oder einem Artikel entspricht, legt das Lagersystem fest.*\n"
              "- **ABC eines Platzes** hat zwei Bedeutungen:\n"
              "    - **Stamm-ABC** = die Güteklasse, die im Lagersystem für den **Ort** hinterlegt ist (A = bester, "
              "wegoptimaler Platz).\n"
              "    - **Berechnete ABC** = aus der tatsächlichen Pick-Häufigkeit ermittelt (viel gepickt → A). Zeigt, "
              "wie der Platz wirklich genutzt wird (Details im ABC-Tab).\n"
              "- **ABC eines Artikels** = nach Bewegungen: die meistbewegten Artikel bis ~80 % sind A, bis ~95 % B, "
              "der Rest C.\n\n"
              "**Beispiele:**\n"
              "- *Pick:* Ein Auftrag mit **3 verschiedenen Artikeln** sind **3 Picks**. 10 Stück desselben Artikels "
              "auf **einer** Position sind nur **1 Pick**.\n"
              "- *ABC berechnet:* 5 Plätze mit den Picks **50, 30, 15, 4, 1** (zusammen 100). Aufsummiert ergibt das "
              "50 %, 80 %, 95 %, 99 %, 100 %. Bei den Schwellen 80/95 %: Platz 1+2 sind **A**, Platz 3 ist **B**, "
              "Platz 4+5 sind **C**.\n\n"
              "**Spalten dieser Tabelle:** *Plätze* = Anzahl Stellplätze · *Belegt/Frei* = wie viele davon · "
              "*Belegung %* = Anteil belegter Plätze · *Ø Auslastung %* = mittlere Füllung · *Picks gesamt* = alle "
              "Zugriffe · *A/B/C-Plätze* = Verteilung nach **berechneter** ABC.\n\n"
              "*Jede Tabelle lässt sich als CSV herunterladen – mit allen Treffern (nicht nur den angezeigten) und "
              "den aktuell gesetzten Filtern als Kommentarzeile.*",
        "en": "This overview summarizes the **whole (filtered) warehouse**. The key terms apply the same in "
              "**all tabs**:\n\n"
              "- **Occupied** = the slot holds at least one pallet or bin. This already counts when the slot is only "
              "partly filled, not just when it's full.\n"
              "- **Free / empty** = something still fits on it. **Completely empty** means nothing is on it at all.\n"
              "- **Utilization** = how full the slot is, in percent (0 % = empty, 100 % = full). The average is the "
              "mean across all slots.\n"
              "- **Capacity** = how many pallets or bins fit on a slot. This can be more than one, not just one.\n"
              "- **Pick / movement** = a single retrieval – one line of an order. *Whether one line equals exactly "
              "one order row or one article is defined by the warehouse system.*\n"
              "- **ABC of a slot** has two meanings:\n"
              "    - **Master ABC** = the quality class stored in the warehouse system for the **location** (A = "
              "best, path-optimal slot).\n"
              "    - **Calculated ABC** = derived from the actual pick frequency (picked often → A). Shows how the "
              "slot is really used (details in the ABC tab).\n"
              "- **ABC of an article** = by movements: the most-moved articles up to ~80 % are A, up to ~95 % B, the "
              "rest C.\n\n"
              "**Examples:**\n"
              "- *Pick:* an order with **3 different articles** is **3 picks**. 10 units of the same article on "
              "**one** line is only **1 pick**.\n"
              "- *ABC calculated:* 5 slots with picks **50, 30, 15, 4, 1** (100 in total). Adding them up gives "
              "50 %, 80 %, 95 %, 99 %, 100 %. With thresholds 80/95 %: slots 1+2 are **A**, slot 3 is **B**, slots "
              "4+5 are **C**.\n\n"
              "**Columns of this table:** *Slots* = number of slots · *Occupied/Free* = how many · *Occupancy %* = "
              "share of occupied slots · *Avg. utilization %* = mean fill · *Total picks* = all accesses · *A/B/C "
              "slots* = distribution by **calculated** ABC.\n\n"
              "*Every table can be downloaded as CSV – with all matches (not just the displayed ones) and the "
              "currently set filters as a comment line.*",
    },
    "halls_kpis": {"de": "**Kennzahlen Lager gesamt**", "en": "**Metrics (whole warehouse)**"},
    "halls_chart": {
        "de": "Belegung Lager gesamt (gefiltert)",
        "en": "Occupancy whole warehouse (filtered)",
    },
    "halls_state_legend": {"de": "Zustand", "en": "State"},
    "halls_state_full": {"de": "Voll belegt", "en": "Fully occupied"},
    "halls_state_partial": {
        "de": "Belegt – noch Platz", "en": "Occupied – room left",
    },
    "halls_state_empty": {"de": "Aktuell leer", "en": "Currently empty"},
    "halls_free_now_note": {
        "de": "Drei Zustände: **Voll belegt** (kein Platz mehr) · **Belegt – noch "
              "Platz** (es passt noch etwas drauf) · **Aktuell leer** = eine "
              "Momentaufnahme: gerade gar nichts drauf. „Aktuell leer“ heißt nicht "
              "dauerhaft frei – jeder dieser Plätze kann jederzeit wieder belegt "
              "werden.",
        "en": "Three states: **Fully occupied** (no room left) · **Occupied – room "
              "left** (something still fits) · **Currently empty** = a snapshot: "
              "nothing on it right now. “Currently empty” does not mean permanently "
              "free – any of these slots can be filled again at any time.",
    },
    "pick_chart": {
        "de": "Pick-Aktivität je Wochentag/Stunde",
        "en": "Pick activity per weekday/hour",
    },
    "pick_intro": {
        "de": "**Pick-Heatmap** — wann im Lager gepickt wird, aufgeschlüsselt nach "
              "Wochentag und Stunde. So sieht man die Stoßzeiten.",
        "en": "**Pick heatmap** — when picking happens, broken down by weekday and "
              "hour. Shows the peak times.",
    },
    "pick_info_t": {
        "de": "ℹ️ Was bedeutet das? (Pick-Heatmap + „ein Pick“ erklärt)",
        "en": "ℹ️ What does this mean? (pick heatmap + “one pick”)",
    },
    "pick_info_b": {
        "de": "Die Heatmap zeigt, **wann** im Lager gepickt wird. Jedes Kästchen steht für ein Zeitfenster "
              "(Wochentag und Stunde), und die Farbe sagt, wie viel darin gepickt wurde: hell = wenig, rot = viel.\n\n"
              "**Was ist ein Pick?** Ein Pick ist eine einzelne Entnahme – also eine Position eines Auftrags, genau "
              "wie im Tagesbewegungen-Tab. *Ob eine Position genau einer Orderzeile oder einem Artikel entspricht, legt das "
              "Lagersystem fest.*\n\n"
              "**Was heißt „Picks je Quellplatz“?** Normalerweise zählt die Heatmap alle Picks im Lager. Sobald du "
              "links Plätze filterst, zählen nur noch die Entnahmen, die von genau diesen Plätzen ausgehen – so "
              "siehst du das Pick-Muster gezielt für deine Auswahl.\n\n"
              "**Wozu das Ganze?** Man erkennt die Stoßzeiten und kann Personal und Schichten besser planen.\n\n"
              "**Das Wochenende ist immer ausgeblendet**, weil samstags und sonntags kaum gepickt wird und das Bild "
              "sonst verwässert.",
        "en": "The heatmap shows **when** picking happens. Each cell stands for one time window (weekday and hour), "
              "and the colour tells you how much was picked in it: light = little, red = a lot.\n\n"
              "**What is a pick?** A pick is a single retrieval – one line of an order, just like in the Daily movements "
              "tab. *Whether one line equals exactly one order row or one article is defined by the warehouse "
              "system.*\n\n"
              "**What does “picks per source slot” mean?** By default the heatmap counts all picks in the warehouse. "
              "As soon as you filter slots on the left, only the retrievals from exactly those slots are counted – so "
              "you see the pick pattern specifically for your selection.\n\n"
              "**What's it for?** You can spot the peak times and plan staff and shifts better.\n\n"
              "**The weekend is always hidden**, because there's hardly any picking on Saturdays and Sundays and it "
              "would otherwise dilute the picture.",
    },
    "pick_peak": {
        "de": "Spitze: {wd} {h:02d}:00 Uhr mit {p} Picks.",
        "en": "Peak: {wd} {h:02d}:00 with {p} picks.",
    },
    "pick_by_wd": {"de": "Picks je Wochentag", "en": "Picks per weekday"},
    "pick_by_hour": {"de": "Picks je Stunde", "en": "Picks per hour"},
    "wd_label": {"de": "Wochentag", "en": "Weekday"},
    "hour_label": {"de": "Stunde", "en": "Hour"},
    "picks_label": {"de": "Picks", "en": "Picks"},
    "bottle_intro": {
        "de": "**Hochfrequenz-Plätze** — die Plätze, die am häufigsten angefahren "
              "werden. Das sind die Hot-Spots im Lager; sie sind oft stark ausgelastet.",
        "en": "**High-frequency slots** — the slots that are visited most often. "
              "These are the warehouse hot spots and are often heavily utilized.",
    },
    "bottle_chart": {
        "de": "Top-15 Hochfrequenz-Plätze (Picks gesamt, Farbe = Auslastung %)",
        "en": "Top-15 high-frequency slots (total picks, color = utilization %)",
    },
    "bottle_info_t": {
        "de": "ℹ️ Was bedeutet das? (Hochfrequenz-Plätze + Spalten)",
        "en": "ℹ️ What does this mean? (high-frequency slots + columns)",
    },
    "bottle_info_b": {
        "de": "Dieser Tab zeigt die **meistangefahrenen Plätze**, sortiert nach den gesamten Picks (oben die "
              "stärksten). Das sind die Hot-Spots im Lager.\n\n"
              "**Warum zwei Pick-Spalten?**\n"
              "- **Picks (Stamm)** = die Zugriffshäufigkeit, die im Lagersystem für den Platz hinterlegt ist.\n"
              "- **Picks gesamt** = zusätzlich die tatsächlichen Anfahrten aus den Bewegungsdaten.\n"
              "Bei vielen Plätzen sind beide Werte gleich – dann gab es eben keine zusätzlichen Anfahrten. Das ist "
              "kein Fehler, sondern heißt nur: hier ist der Stamm-Wert die einzige Quelle.\n\n"
              "**Was bedeutet Auslastung 100 % oder 0 %?**\n"
              "- **100 %** = der Platz ist voll.\n"
              "- **0 %** = der Platz wird oft angefahren, ist aber gerade leer. Genau so ein Platz gehört auf die "
              "Nachschub-Liste.",
        "en": "This tab shows the **most-visited slots**, sorted by total picks (the busiest on top). These are the "
              "warehouse hot spots.\n\n"
              "**Why two pick columns?**\n"
              "- **Picks (master)** = the access frequency stored for the slot in the warehouse system.\n"
              "- **Total picks** = plus the actual visits from the movement data.\n"
              "For many slots both values are equal – then there simply were no extra visits. That's not an error, "
              "it just means the master value is the only source here.\n\n"
              "**What does utilization 100 % or 0 % mean?**\n"
              "- **100 %** = the slot is full.\n"
              "- **0 %** = the slot is visited often but is currently empty. Exactly such a slot belongs on the "
              "replenishment list.",
    },
    "free_intro": {
        "de": "**Free Capacity** — Plätze, auf die noch etwas draufpasst. Oben stehen "
              "die mit der größten freien Lücke.",
        "en": "**Free capacity** — slots that still have room. The ones with the "
              "largest free gap are at the top.",
    },
    "free_info_t": {
        "de": "ℹ️ Was bedeutet das? (Free Capacity + Spalten)",
        "en": "ℹ️ What does this mean? (free capacity + columns)",
    },
    "free_info_b": {
        "de": "Dieser Tab zeigt alle Plätze, auf die noch etwas draufpasst – oben die mit der größten freien Lücke. "
              "So findest du schnell Platz für neue Ware.\n\n"
              "**Warum steht bei „Kapazität“ manchmal 2 oder mehr und nicht 1?** Die Kapazität ist, wie viele "
              "Paletten oder Behälter auf den Platz passen. Manche Plätze fassen baulich mehrere (z. B. zwei "
              "Paletten nebeneinander). Das ist kein Fehler, sondern die echte Größe des Platzes.\n\n"
              "**Was heißt Auslastung 0 %?** Der Platz ist ganz leer und komplett frei. Ein freier Platz liegt immer "
              "unter 100 %.\n\n"
              "**Spalten:** *Kapazität* = wie viel maximal draufpasst · *Belegt* = wie viel schon drauf steht · "
              "*Frei* = wie viel noch reinpasst · *Auslastung %* = wie voll der Platz schon ist.",
        "en": "This tab shows every slot that still has room – the ones with the largest free gap on top. So you "
              "quickly find space for new goods.\n\n"
              "**Why does “Capacity” sometimes say 2 or more, not 1?** Capacity is how many pallets or bins fit on "
              "the slot. Some slots physically hold several (e.g. two pallets side by side). That's not an error, "
              "it's the real size of the slot.\n\n"
              "**What does utilization 0 % mean?** The slot is completely empty and fully free. A free slot is always "
              "below 100 %.\n\n"
              "**Columns:** *Capacity* = max that fits · *Occupied* = what's already on it · *Free* = what still "
              "fits · *Utilization %* = how full the slot already is.",
    },
    "free_count": {"de": "Plätze mit freier Kapazität", "en": "Slots with free capacity"},
    "free_total": {"de": "Freie LHM gesamt", "en": "Total free LHM"},
    "free_avg": {"de": "Ø freie LHM/Platz", "en": "Avg. free LHM/slot"},
    "free_byhall": {"de": "Freie Kapazität (LHM) je Halle", "en": "Free capacity (LHM) per hall"},
    # Maßnahmen
    "col_vorschlag": {"de": "Vorschlag", "en": "Suggestion"},
    "col_ziel": {"de": "Zielplatz-Vorschlag", "en": "Suggested target slot"},
    "ziel_none": {
        "de": "kein freier Zielplatz in Auswahl",
        "en": "no free target slot in selection",
    },
    "reloc_hotC_v_to": {
        "de": "Auf Klasse {cls} hochstufen – {picks} Picks, das entspricht der "
              "berechneten Klasse {cls}. Auf einen guten Pickplatz (niedrige "
              "Ebene) umlagern.",
        "en": "Promote to class {cls} – {picks} picks, matching the calculated "
              "class {cls}. Relocate to a good pick slot (low level).",
    },
    "reloc_highA_v": {
        "de": "Ware auf den freien Platz weiter unten umlagern – kürzere Greifwege",
        "en": "Relocate the goods to the free slot lower down – shorter travel",
    },
    "sl_highlevel": {"de": "Hohe Ebene ab", "en": "High level from"},
    "reloc_hotC_t": {"de": "Heiße C-Plätze", "en": "Hot C slots"},
    "reloc_hotC_d": {
        "de": "Stamm-Klasse C, aber nach den Picks berechnet A/B – hochstufen.",
        "en": "Master class C, but computes to A/B by picks – reclassify.",
    },
    "reloc_highA_t": {"de": "A-Ware zu hoch gelagert", "en": "A goods stored too high"},
    "reloc_highA_d": {
        "de": "Aktiver A-Platz weit oben – die Ware auf einen freien Platz weiter "
              "unten umlagern (der Platz bleibt, nur der Inhalt zieht um).",
        "en": "Active A slot high up – relocate the goods to a free slot lower down "
              "(the slot stays, only its contents move).",
    },
    "replen_head": {
        "de": "### ⬆️ Nachschub\n**Welche Pickplätze sind leer und sollten nachgefüllt werden?** "
              "Gelistet werden ganz leere Plätze in der Pickzone (den niedrigen Ebenen), sortiert nach "
              "Dringlichkeit.",
        "en": "### ⬆️ Replenishment\n**Which pick slots are empty and should be refilled?** "
              "The lists show completely empty slots in the pick zone (the low levels), ranked by urgency.",
    },
    "replen_principle": {
        "de": "**Worum geht's hier?** Ist ein Platz leer, an dem sonst oft gepickt wird, steht der Mitarbeiter vor "
              "einem leeren Fach – er muss suchen, oder die Ware fehlt. Je öfter der Platz normalerweise gepickt "
              "wird und je länger er schon leer ist, desto dringender der Nachschub.\n\n"
              "Es gibt zwei Listen:\n"
              "- **Überfällig** – wichtiger Platz, leer und schon länger kein Pick. Auffüllen, bevor "
              "das Fach ganz einschläft.\n"
              "- **Mittlere Frequenz** – leer, aber seltener gebraucht.\n\n"
              "Gesperrte Plätze lassen wir bewusst weg. Über den Regler **„Aktiv …“** zeigen wir außerdem nur Plätze, "
              "an denen kürzlich gepickt wurde. Fächer, die seit Monaten unberührt sind (früher viel gepickt, jetzt "
              "tot), blenden wir aus und zählen sie oben nur als Hinweis.",
        "en": "**What's this about?** If a slot is empty where picking usually happens often, the worker faces an "
              "empty bin – they have to search, or goods are missing. The more often the slot is normally picked and "
              "the longer it has been empty, the more urgent the refill.\n\n"
              "There are two lists:\n"
              "- **Overdue (neglected)** – important slot, empty and no pick for a while. Refill before the location "
              "goes dormant.\n"
              "- **Medium frequency** – empty, but needed less often.\n\n"
              "Locked slots are deliberately left out. The **‘Active …’** slider also shows only slots picked "
              "recently. Bins untouched for months (once busy, now dead) are hidden and only counted as a note "
              "above.",
    },
    "replen_glossary_t": {
        "de": "ℹ️ Was bedeuten „leer“, „Pick“ und die Spalten?",
        "en": "ℹ️ What do ‘empty’, ‘pick’ and the columns mean?",
    },
    "replen_glossary_b": {
        "de": "- **Leer** heißt hier **ganz leer**: gar nichts steht auf dem Platz. Teilweise gefüllte Plätze (noch "
              "Platz frei, aber schon Ware drauf) stehen nicht hier, sondern im Tab **Einlagern / Free Capacity**.\n"
              "- **Picks (Häufigkeit)** = wie oft an diesem Platz normalerweise gepickt wird (im Lagersystem "
              "hinterlegt). Das ist ein Zähler für den Ort, nicht der aktuelle Bestand.\n"
              "- **ABC (Platz)** = die Güteklasse des Ortes aus dem Lagersystem (A = bester Platz). Sie beschreibt "
              "den Platz und wird hier nicht aus den Picks berechnet.\n"
              "- **Soll-LHM** = auf wie viele Paletten/Behälter der Platz aufgefüllt werden soll.\n"
              "- **Tage seit letztem Pick** = wie lange hier nichts mehr entnommen wurde – der eine "
              "Zeit-Wert dieser Tabelle. Kürzlich gepickt und trotzdem leer heißt: Nachschub vergessen. "
              "Lange kein Pick heißt: vielleicht ein totes Fach. (Das reine „leer seit“-Datum ist in den "
              "Daten oft veraltet und wird deshalb nicht extra angezeigt.)\n"
              "- **Vorschlag** = die abgeleitete Handlung. Wie dringend, ergibt sich aus der Liste; die Menge ist das "
              "Soll-LHM (Platz ist leer, also auf Soll auffüllen), bei Überfälligen zusätzlich die Tage ohne Pick.\n\n"
              "Eine **Wert-Spalte** gibt es hier bewusst nicht – die Dringlichkeit ergibt sich allein aus "
              "Pick-Häufigkeit und Tagen ohne Pick.",
        "en": "- **Empty** here means **completely empty**: nothing is on the slot at all. Partly filled slots "
              "(still room, but goods already on them) are not here but in the **Put-away / Free Capacity** tab.\n"
              "- **Picks (frequency)** = how often this slot is normally picked (stored in the warehouse system). "
              "It's a counter for the location, not the current stock.\n"
              "- **ABC (slot)** = the quality class of the location from the warehouse system (A = best slot). It "
              "describes the slot and is not computed from picks here.\n"
              "- **Target LU** = how many pallets/bins the slot should be refilled to.\n"
              "- **Days since last pick** = how long nothing has been taken from here – the single time value of "
              "this table. Picked recently yet empty means a forgotten refill. No pick for a long time may mean a "
              "dead bin. (The plain ‘empty since’ date is often outdated in the data and is therefore not shown "
              "separately.)\n"
              "- **Suggestion** = the derived action. How urgent comes from the list; the amount is the target LU "
              "(the slot is empty, so refill to target), plus the days without a pick for overdue ones.\n\n"
              "There is deliberately **no value column** here – urgency comes solely from pick frequency and days "
              "without a pick.",
    },
    "sl_picklevel": {"de": "Max. Ebene (Pickzone)", "en": "Max. level (pick zone)"},
    "sl_picklevel_h": {
        "de": "Nur Plätze bis zu dieser Ebene zählen als Pickzone. Was höher liegt, "
              "ist Reserve und muss nicht ständig gefüllt sein.",
        "en": "Only slots up to this level count as the pick zone. Anything higher is "
              "reserve and need not always be stocked.",
    },
    "sl_pickthresh": {"de": "Wichtig ab Picks", "en": "Important from picks"},
    "sl_pickthresh_h": {
        "de": "Ab so vielen Picks gilt ein leerer Platz als wichtig. Darunter landet "
              "er in der Liste „Mittlere Frequenz“.",
        "en": "From this many picks an empty slot counts as important. Below that it "
              "goes into the ‘Medium frequency’ list.",
    },
    "sl_overdue": {"de": "Überfällig ab Tagen ohne Pick",
                   "en": "Overdue from days without pick"},
    "sl_overdue_h": {
        "de": "Ab so vielen Tagen ohne Pick gilt ein wichtiger leerer Platz als "
              "überfällig (vernachlässigt).",
        "en": "After this many days without a pick, an important empty slot counts as "
              "overdue (neglected).",
    },
    "sl_active": {"de": "Aktiv: zuletzt gepickt vor max. Tagen",
                  "en": "Active: last picked within days"},
    "sl_active_h": {
        "de": "Nur Plätze zeigen, an denen in diesem Zeitraum zuletzt gepickt wurde. "
              "Das trennt echte Nachfüll-Kandidaten von toten Fächern, die früher viel "
              "gepickt wurden, aber seit Monaten unberührt sind.",
        "en": "Only show slots last picked within this window. This separates real "
              "refill candidates from dead bins that were busy once but haven't been "
              "touched for months.",
    },
    "replen_inactive_note": {
        "de": "ℹ️ **{n} leere Plätze ausgeblendet**, weil seit über {d} Tagen kein Pick "
              "mehr (oder kein Datum bekannt). Die werden zurzeit kaum gebraucht – also "
              "kein akuter Nachschub. Über den Regler „Aktiv …“ kannst du sie einblenden.",
        "en": "ℹ️ **{n} empty slots hidden** because there's been no pick for over {d} "
              "days (or no date known). They're barely in use right now – so not urgent "
              "replenishment. Use the ‘Active …’ slider to include them.",
    },
    "replen_overdue_t": {"de": "Überfällig",
                         "en": "Overdue"},
    "replen_overdue_d": {
        "de": "Wichtiger Platz, leer und seit über {n} Tagen nicht mehr gepickt.",
        "en": "Important slot, empty and not picked for over {n} days.",
    },
    "replen_overdue_v": {
        "de": "Bevorzugt auffüllen (Soll {x} LHM) – seit {d} Tagen kein Pick, Ursache prüfen",
        "en": "Refill first (target {x} LU) – no pick for {d} days, check the cause",
    },
    "replen_medium_t": {"de": "Mittlere Frequenz", "en": "Medium frequency"},
    "replen_medium_d": {
        "de": "Leer und nur mittel oft gepickt – einplanen, aber nicht so dringend.",
        "en": "Empty and only picked moderately often – schedule it, but less urgent.",
    },
    "replen_medium_v": {
        "de": "Bei der nächsten Tour auffüllen (Soll {x} LHM)",
        "en": "Refill on the next round (target {x} LU)",
    },
    "put_head": {
        "de": "### 📥 Einlagern\n**Wohin mit eingehender Ware?** Die Listen zeigen freie Plätze, sortiert danach, "
              "wie gut sie passen – Schnelldreher nach vorne und unten, Reserve nach hinten und oben.",
        "en": "### 📥 Put-away\n**Where to store incoming goods?** The lists show free slots, ranked by how well "
              "they fit – fast movers to the front and low, reserve to the back and high.",
    },
    "put_principle": {
        "de": "**Worum geht's hier?** Jeder Pick kostet Weg. Schnelldreher gehören deshalb auf die besten Plätze "
              "weit unten und nah dran – kurze Greifwege, kein Hochhub. Langsamdreher dürfen weiter oben oder hinten "
              "als Reserve stehen. So wird der mittlere Weg pro Pick kürzer. Gesperrte Plätze lassen wir bewusst weg.",
        "en": "**What's this about?** Every pick costs travel. Fast movers therefore belong in the best slots, low "
              "down and close by – short reach, no lifting. Slow movers may sit higher up or further back as "
              "reserve. That shortens the average travel per pick. Locked slots are deliberately left out.",
    },
    "put_glossary_t": {
        "de": "ℹ️ Was bedeuten die Spalten?",
        "en": "ℹ️ What do the columns mean?",
    },
    "put_info_t": {
        "de": "ℹ️ Was bedeutet das? (Sinn des Tabs + Spalten erklärt)",
        "en": "ℹ️ What does this mean? (purpose of the tab + columns)",
    },
    "put_twocrit": {
        "de": "**Warum gleich zwei Kriterien (A *und* niedrige Ebene)?** Weil das zwei verschiedene Wege sind:\n"
              "- **A-Platz** = liegt nah am Wareneingang → kurzer Fahrweg.\n"
              "- **Niedrige Ebene** = auf Greifhöhe → kein Heben mit dem Stapler.\n"
              "Erst beides zusammen macht einen Platz wirklich schnell.",
        "en": "**Why two criteria (A *and* low level)?** Because they're two different distances:\n"
              "- **A slot** = close to goods-in → short drive.\n"
              "- **Low level** = at reach height → no lifting with a forklift.\n"
              "Only both together make a slot truly fast.",
    },
    "put_cols_head": {
        "de": "**Spalten in den Tabellen:**",
        "en": "**Columns in the tables:**",
    },
    "put_overview": {
        "de": "#### 📊 Überblick: freie Plätze",
        "en": "#### 📊 Overview: free slots",
    },
    "put_kpi_free": {"de": "Freie Plätze (nutzbar)", "en": "Free slots (usable)"},
    "put_kpi_blocked": {"de": "Frei, aber gesperrt", "en": "Free but locked"},
    "put_kpi_capacity": {
        "de": "Freie Gesamt-Kapazität: **{n} LHM** (so viele Paletten/Behälter passen über alle nutzbaren freien Plätze zusammen noch rein).",
        "en": "Total free capacity: **{n} LU** (that many pallets/bins still fit across all usable free slots together).",
    },
    "put_glossary_b": {
        "de": "- **ABC (Platz)** = die Güteklasse des Ortes aus dem Lagersystem (A = bester Platz). Sie beschreibt "
              "den Platz und wird hier nicht aus den Picks berechnet.\n"
              "- **Kapazität (max. LHM)** = wie viele Paletten/Behälter auf den Platz passen – kann auch mehr als "
              "einer sein.\n"
              "- **Belegt (Ist-LHM)** = wie viele davon schon drauf stehen.\n"
              "- **Frei (LHM)** = wie viele noch reinpassen. Hier zählt jeder Platz, auf den noch etwas draufgeht – "
              "egal ob teilweise oder ganz frei. **Ganz leere** Plätze findest du im Tab **Nachschub**.\n"
              "- **Auslastung %** = wie voll der Platz ist (0 % = leer, 100 % = voll). Ein freier Platz liegt immer "
              "unter 100 %.",
        "en": "- **ABC (slot)** = the quality class of the location from the warehouse system (A = best slot). It "
              "describes the slot and is not computed from picks here.\n"
              "- **Capacity (max. LU)** = how many pallets/bins fit on the slot – can be more than one.\n"
              "- **Occupied (actual LU)** = how many are already on it.\n"
              "- **Free (LU)** = how many more fit. Here every slot counts that still has room – whether partly or "
              "fully free. **Completely empty** slots are in the **Replenishment** tab.\n"
              "- **Utilization %** = how full the slot is (0 % = empty, 100 % = full). A free slot is always below "
              "100 %.",
    },
    "put_rowhint": {
        "de": "Jede Zeile ist ein freier Platz, der für neue Ware infrage kommt – sortiert nach freier Kapazität.",
        "en": "Each row is a free slot that could take new goods – sorted by free capacity.",
    },
    "put_blocked_rowhint": {
        "de": "Jede Zeile ist ein Platz, der frei wäre, aber gesperrt ist – er käme als Ziel infrage, darf aber nicht bestückt werden.",
        "en": "Each row is a slot that would be free but is locked – it could be a target, but must not be stocked.",
    },
    "sl_fastlevel": {"de": "Fast-Lane bis Ebene", "en": "Fast lane up to level"},
    "sl_fastlevel_h": {
        "de": "Bis zu dieser Ebene gilt ein freier A-Platz als Fast-Lane (kurze Wege). "
              "Höher = mehr Plätze, aber längere Greifwege.",
        "en": "Up to this level a free A slot counts as a fast lane (short paths). "
              "Higher = more slots, but longer reach.",
    },
    "sl_reservelevel": {"de": "Reserve-Ebene ab", "en": "Reserve level from"},
    "sl_reservelevel_h": {
        "de": "Ab dieser Ebene gelten freie Nicht-A-Plätze als Reserve für die Langsamdreher.",
        "en": "From this level free non-A slots count as reserve for slow movers.",
    },
    "put_logic_t": {
        "de": "ℹ️ Wie entsteht der Vorschlag?",
        "en": "ℹ️ How is the suggestion derived?",
    },
    "put_logic_b": {
        "de": "Der **Vorschlag** ist keine Einzelbewertung – er ergibt sich einfach daraus, in welche Kategorie ein "
              "Platz fällt. Die Regel ist also gleich die Empfehlung, und alle Kriterien stehen als Spalte in der "
              "Tabelle. So kannst du jeden Vorschlag nachprüfen:\n\n"
              "1. **Schnelldreher-Plätze** → *„Schnelldreher hier einlagern“*\n"
              "   Der Platz ist frei, ein A-Platz, liegt bis zur Ebene aus dem Regler „Fast-Lane bis Ebene“ und ist "
              "nicht gesperrt. Oben steht der Platz mit der größten freien Lücke.\n"
              "2. **Reserve** → *„Langsamdreher / Reserve hier einlagern“*\n"
              "   Der Platz ist frei, kein A-Platz, liegt ab der Ebene aus dem Regler „Reserve-Ebene ab“ und ist "
              "nicht gesperrt. Auch hier oben die größte Lücke zuerst.\n"
              "3. **Gesperrt** → *„Nicht einlagern“*\n"
              "   Der Platz wäre frei, ist aber gesperrt – darf nicht bestückt werden.\n\n"
              "Die beiden Ebenen-Grenzen stellst du unten mit den Reglern ein; die Listen passen sich sofort an.",
        "en": "The **suggestion** isn't a case-by-case score – it simply follows from which category a slot falls "
              "into. So the rule is the recommendation, and every criterion is shown as a column. That way you can "
              "check any suggestion:\n\n"
              "1. **Fast-mover slots** → *“Store fast movers here”*\n"
              "   The slot is free, an A slot, sits up to the level from the “Fast lane up to level” slider, and "
              "isn't locked. The slot with the largest free gap is on top.\n"
              "2. **Reserve** → *“Store slow movers / reserve here”*\n"
              "   The slot is free, not an A slot, sits from the level in the “Reserve level from” slider, and isn't "
              "locked. Again the largest gap first.\n"
              "3. **Locked** → *“Do not put away”*\n"
              "   The slot would be free but is locked – it must not be stocked.\n\n"
              "You set the two level limits with the sliders below; the lists update instantly.",
    },
    "put_fast_t": {"de": "Schnelldreher-Plätze", "en": "Fast-mover slots"},
    "put_fast_d": {
        "de": "Freie A-Plätze bis Ebene {n}: nah dran und auf Greifhöhe, also kürzeste Wege. Hier gehören die "
              "Schnelldreher hin – sie werden am häufigsten gepickt, da sparen kurze Wege am meisten Zeit.",
        "en": "Free A slots up to level {n}: close by and at reach height, so the shortest paths. The fast movers "
              "belong here – they're picked most often, so short paths save the most time.",
    },
    "put_fast_v": {
        "de": "Hier bis zu {x} LHM einlagern (Schnelldreher, kurze Wege)",
        "en": "Store up to {x} LU here (fast mover, short paths)",
    },
    "put_reserve_t": {"de": "Reserve (hohe Ebenen)", "en": "Reserve (high levels)"},
    "put_reserve_d": {
        "de": "Freie Nicht-A-Plätze ab Ebene {n} (weiter oben oder hinten): längere Wege, aber für Langsamdreher "
              "und Reserve völlig in Ordnung. So bleiben die knappen A-Plätze für die Schnelldreher frei.",
        "en": "Free non-A slots from level {n} (higher up or further back): longer paths, but perfectly fine for "
              "slow movers and reserve. This keeps the scarce A slots free for the fast movers.",
    },
    "put_reserve_v": {
        "de": "Hier bis zu {x} LHM einlagern (Langsamdreher / Reserve)",
        "en": "Store up to {x} LU here (slow mover / reserve)",
    },
    "put_blocked_t": {"de": "Gesperrt – nicht bestücken", "en": "Locked – do not stock"},
    "put_blocked_d": {
        "de": "Plätze, die zwar Platz frei hätten, aber gesperrt sind (z. B. Inventur, Defekt oder reserviert). Sie "
              "kämen als Ziel infrage, dürfen aber nicht bestückt werden. Voll belegte Sperrplätze blenden wir hier "
              "aus – die sind ohnehin kein Einlager-Ziel.",
        "en": "Slots that would have room but are locked (e.g. stocktake, defect or reserved). They could be a "
              "target, but must not be stocked. Fully occupied locked slots are hidden here – they're not a put-away "
              "target anyway.",
    },
    "put_blocked_v": {
        "de": "Nicht einlagern – Sperre prüfen",
        "en": "Do not store – check the lock",
    },
    "sl_retrzone": {"de": "Pickzone bis Ebene", "en": "Pick zone up to level"},
    # --- Verschmolzener Tab 'Um-/Auslagern' (loest reloc_*/retr_* ab) ---
    "ua_head": {
        "de": "### 🔄 Um- & Auslagern\n**Steht die richtige Ware auf dem richtigen "
              "Platz?** Zwei Stoßrichtungen: gute Plätze von Ladenhütern *freimachen* "
              "und Schnelldreher auf bessere Plätze *umlagern* – direkt aus den "
              "Lagerdaten.",
        "en": "### 🔄 Relocate & retrieve\n**Are the right goods on the right slot?** "
              "Two directions: *free up* good slots from dead stock and *relocate* fast "
              "movers to better slots – straight from the warehouse data.",
    },
    "ua_info_t": {
        "de": "ℹ️ Was heißt um- und auslagern? (Regeln + Spalten)",
        "en": "ℹ️ What do relocate and retrieve mean? (rules + columns)",
    },
    "ua_info_b": {
        "de": "Beide Maßnahmen haben dasselbe Ziel: die guten Pickplätze (A, niedrige Ebene) für die "
              "Schnelldreher frei halten. Sie unterscheiden sich nur in der Richtung:\n\n"
              "**🟥 Platz freimachen (auslagern)** – belegte Plätze, deren Ware sich kaum bewegt:\n"
              "- **Premiumplatz blockiert** – ein A-Platz ist belegt, wird aber gar nicht gepickt. Ein "
              "Ladenhüter sitzt auf einem Premiumplatz → Ware in die Reserve umlagern oder ganz auslagern.\n\n"
              "**🟦 Besser platzieren (umlagern)** – Schnelldreher auf schlechtem Platz:\n"
              "1. **Heißer C-Platz** – ein Platz, der als C geführt wird, aber nach seinen tatsächlichen Picks "
              "rechnerisch in **A oder B** gehört. Falsch eingestuft → auf einen guten Pickplatz unten holen und auf "
              "die **berechnete Klasse (A oder B)** hochstufen. Welche Klasse genau und warum, steht je Zeile im "
              "Vorschlag.\n"
              "2. **A-Ware zu hoch** – ein aktiver A-Platz, der weit oben liegt (ab dem Regler-Wert). Hochhub kostet "
              "Zeit → die **Ware** auf einen freien Platz weiter unten umlagern (der Platz bleibt natürlich, wo er "
              "ist – nur sein Inhalt zieht um, siehe Zielplatz-Vorschlag). *Gilt nur für die echten Ebenen 1–6; "
              "höhere Code-Werte im Feld Ebene sind keine Stockwerke und bleiben außen vor.*\n\n"
              "**Zielplatz-Vorschlag:** ein konkreter freier, passender Platz – für blockierte Premiumplätze oben "
              "in der Reserve, für heiße oder zu hohe Plätze unten in der Pickzone. Zugeordnet wird 1:1 nach freier "
              "Kapazität.\n\n"
              "*Leere A-Plätze tauchen hier bewusst nicht auf – wo nichts steht, gibt es nichts um- oder "
              "auszulagern.*",
        "en": "Both actions share one goal: keep the good pick slots (A, low level) free for the fast movers. They "
              "only differ in direction:\n\n"
              "**🟥 Free up a slot (retrieve)** – occupied slots whose goods barely move:\n"
              "- **Premium slot blocked** – an A slot is occupied but not picked at all. Dead stock on a premium "
              "spot → move the goods to reserve or retrieve them.\n\n"
              "**🟦 Place better (relocate)** – fast movers on a bad slot:\n"
              "1. **Hot C slot** – a slot listed as C that, by its actual picks, computes to **A or B**. "
              "Misclassified → bring it to a good pick slot down low and promote to the **calculated class (A or B)**. "
              "Which class exactly and why is shown per row in the suggestion.\n"
              "2. **A goods too high** – an active A slot sitting high up (from the slider value up). Lifting costs "
              "time → relocate the **goods** to a free slot lower down (the slot itself stays put – only its "
              "contents move, see suggested target slot). *Applies only to real levels 1–6; higher code values in "
              "the Level field are not floors and are excluded.*\n\n"
              "**Suggested target slot:** a concrete free, fitting slot – up in reserve for blocked premium slots, "
              "down in the pick zone for hot or too-high slots. Matched 1:1 by free capacity.\n\n"
              "*Empty A slots deliberately don't appear here – where nothing stands, there's nothing to relocate or "
              "retrieve.*",
    },
    "ua_group_free": {
        "de": "#### 🟥 Platz freimachen (auslagern)",
        "en": "#### 🟥 Free up a slot (retrieve)",
    },
    "ua_group_place": {
        "de": "#### 🟦 Besser platzieren (umlagern)",
        "en": "#### 🟦 Place better (relocate)",
    },
    "ua_kpi_free": {"de": "Plätze freimachen", "en": "Slots to free up"},
    "ua_kpi_free_h": {
        "de": "Belegte A-Plätze ohne Picks – ein Ladenhüter blockiert hier einen "
              "Premiumplatz, ohne bewegt zu werden.",
        "en": "Occupied A slots without picks – dead stock blocks a premium slot "
              "here without ever moving.",
    },
    "ua_kpi_place": {"de": "Besser platzieren", "en": "To place better"},
    "ua_kpi_place_h": {
        "de": "Schnelldreher auf schlechtem Platz (heiße C-Plätze + zu hohe "
              "A-Plätze) – die gehören woanders hin.",
        "en": "Fast movers on a bad slot (hot C slots + too-high A slots) – these "
              "belong elsewhere.",
    },
    "ua_crit_t": {"de": "Premiumplatz blockiert", "en": "Premium slot blocked"},
    "ua_crit_d": {
        "de": "A-Platz belegt, aber 0 Picks – ein Ladenhüter sitzt auf einem "
              "Premiumplatz.",
        "en": "A slot occupied but 0 picks – dead stock sits on a premium spot.",
    },
    "ua_crit_v": {
        "de": "Ware in die Reserve umlagern oder auslagern – Premiumplatz freimachen",
        "en": "Move goods to reserve or retrieve them – free up the premium spot",
    },
    "sl_highlevel_h": {
        "de": "Ab dieser Ebene gilt ein aktiver A-Platz als „zu hoch“ (Hochhub). "
              "Gilt nur für die echten Ebenen 1–6.",
        "en": "From this level an active A slot counts as ‘too high’ (lifting). "
              "Applies only to real levels 1–6.",
    },
    "sl_retrzone_h": {
        "de": "Bis zu dieser Ebene gilt als Pickzone. Sie bestimmt, welche belegten "
              "Plätze auf „blockiert“ geprüft werden – und welche freien Plätze als "
              "Ziel unten (Pickzone) bzw. oben (Reserve) gelten.",
        "en": "Up to this level counts as the pick zone. It sets which occupied slots "
              "are checked for ‘blocked’ – and which free slots count as a target down "
              "low (pick zone) or up high (reserve).",
    },
    "abc_intro": {
        "de": "**ABC nach Lagerplätzen** — die Plätze nach Pick-Häufigkeit sortiert "
              "und aufsummiert. A = Plätze bis {a} % aller Picks, B = bis {b} %, "
              "C = der Rest.",
        "en": "**ABC by storage slots** — slots sorted by pick frequency and added up. "
              "A = slots up to {a}% of all picks, B = up to {b}%, C = the rest.",
    },
    "abc_chart": {"de": "ABC-Verteilung (berechnet)", "en": "ABC distribution (calculated)"},
    "abc_cross_intro": {
        "de": "**Stamm-ABC gegen berechnet** — Zeilen sind die hinterlegte Klasse, "
              "Spalten die aus den Picks berechnete. Alles, was nicht auf der Diagonale "
              "liegt, ist ein Kandidat für eine ABC-Anpassung.",
        "en": "**Master ABC vs. calculated** — rows are the stored class, columns the "
              "one calculated from picks. Anything off the diagonal is a candidate for "
              "an ABC adjustment.",
    },
    "abc_byfreq": {"de": "**📋 Tabelle 2: Alle Einträge nach Pickhäufigkeit**",
                   "en": "**📋 Table 2: All entries by pick frequency**"},
    "abc_byfreq_note": {
        "de": "Die komplette Liste, sortiert nach Picks (die häufigsten oben). "
              "*Stamm* = die im Lagersystem hinterlegte Klasse · *Berechnet* = die aus "
              "den Picks · *kumul. Pick-%* = wie viel Prozent aller Picks bis zu dieser "
              "Zeile zusammenkommen.",
        "en": "The full list, sorted by picks (the most-picked on top). "
              "*Master* = the class stored in the warehouse system · *Calculated* = the "
              "one from picks · *cum. pick %* = what share of all picks adds up down to "
              "this row.",
    },
    "abc_head": {
        "de": "### 🏷️ ABC-Analyse\n**Welche Plätze/Artikel sind die wichtigen?** "
              "A = Renner (Großteil der Picks), C = Langsamdreher – die Grundlage "
              "für kurze Wege und Umlagern.",
        "en": "### 🏷️ ABC analysis\n**Which slots/articles are the important ones?** "
              "A = fast movers (most of the picks), C = slow movers – the basis for "
              "short paths and relocation.",
    },
    "abc_explain_head": {
        "de": "ℹ️ Was bedeutet das? (Wozu ABC, Modi, Klassen)",
        "en": "ℹ️ What does this mean? (purpose, modes, classes)",
    },
    "abc_calc_head": {
        "de": "🧮 Rechenweg: Wie kommt ein Platz auf A / B / C?",
        "en": "🧮 Calculation: how does a slot become A / B / C?",
    },
    "abc_calc_steps": {
        "de": "**So entsteht die Klasse (Pareto-Rechnung):**\n\n"
              "1. Alle {e} nach **Picks absteigend sortieren**.\n"
              "2. Von oben den **kumulierten Pick-Anteil** aufsummieren.\n"
              "3. Kumuliert ≤ **{a} %** → **A**, ≤ **{b} %** → **B**, Rest → **C**.\n\n"
              "Heißt: A bekommt man **nicht** ab einer festen Pick-Zahl, sondern weil "
              "man zu den wenigen Top-{e} gehört, die zusammen die ersten {a} % aller "
              "Picks ausmachen.",
        "en": "**How the class is derived (Pareto):**\n\n"
              "1. Sort all {e} by **picks, descending**.\n"
              "2. From the top, accumulate the **cumulative pick share**.\n"
              "3. Cumulative ≤ **{a} %** → **A**, ≤ **{b} %** → **B**, rest → **C**.\n\n"
              "So A is **not** a fixed pick count – you get A by being among the few "
              "top {e} that together make up the first {a} % of all picks.",
    },
    "abc_calc_concrete": {
        "de": "In der aktuellen Auswahl ergibt das: **A** ab **{amin}** Picks · "
              "**B** **{bmin}–{amin1}** · **C** darunter.",
        "en": "In the current selection: **A** from **{amin}** picks · "
              "**B** **{bmin}–{amin1}** · **C** below.",
    },
    "abc_mode": {"de": "ABC berechnen nach", "en": "Compute ABC by"},
    "abc_by_slots": {"de": "Lagerplätzen", "en": "Storage slots"},
    "abc_by_articles": {"de": "Artikeln", "en": "Articles"},
    "abc_by_menge": {"de": "Menge (Stück)", "en": "Quantity (pcs)"},
    "abc_col_menge": {"de": "Menge (Stück)", "en": "Quantity (pcs)"},
    "abc_col_avgmenge": {"de": "Ø Menge/Bewegung", "en": "avg qty/movement"},
    "abc_csv_all": {
        "de": "Die Tabelle zeigt die ersten 200 Zeilen – der CSV-Download enthält "
              "**alle {n} Artikel**.",
        "en": "The table shows the first 200 rows – the CSV download contains "
              "**all {n} articles**.",
    },
    "abc_byart_head": {
        "de": "**📋 Tabelle 2: Artikel nach Bewegungen**",
        "en": "**📋 Table 2: Articles by movements**"},
    "abc_byart_note": {
        "de": "Sortiert nach **Bewegungen** (häufigste oben). Daneben die "
              "**Menge** (verbrauchte Stück) und die **Ø Menge je Bewegung**. "
              "So sieht man, ob ein häufig bewegter Artikel auch große Mengen "
              "umfasst (echter Renner) oder nur oft in *kleinen* Portionen "
              "entnommen wird. *kumul. %* = Anteil aller Bewegungen bis zu dieser "
              "Zeile · *Berechnet* = ABC-Klasse aus den Bewegungen.",
        "en": "Sorted by **movements** (most frequent on top). Next to it the "
              "**quantity** (pieces consumed) and the **avg quantity per movement**. "
              "This shows whether a frequently moved article also covers large "
              "quantities (a true mover) or is just picked often in *small* "
              "portions. *cum. %* = share of all movements down to this row · "
              "*Calculated* = ABC class from movements.",
    },
    "abc_bymenge_head": {
        "de": "**📋 Tabelle 2: Artikel nach verbrauchter Menge**",
        "en": "**📋 Table 2: Articles by consumed quantity**"},
    "abc_bymenge_note": {
        "de": "Sortiert nach **Gesamtmenge** (meiste Stück oben). Daneben die "
              "**Bewegungen** (wie oft entnommen) und die **Ø Menge je Bewegung**. "
              "So sieht man, ob eine hohe Menge aus *vielen kleinen* Zugriffen kommt "
              "(großer Dreher) oder aus *wenigen großen* Entnahmen (Bulk-Artikel). "
              "*kumul. %* = Anteil der Gesamtmenge bis zu dieser Zeile · *Berechnet* = "
              "ABC-Klasse aus der Menge.",
        "en": "Sorted by **total quantity** (most pieces on top). Next to it the "
              "**movements** (how often picked) and the **avg quantity per movement**. "
              "This shows whether a high quantity comes from *many small* picks "
              "(a true mover) or *few large* withdrawals (bulk article). "
              "*cum. %* = share of total quantity down to this row · *Calculated* = "
              "ABC class from quantity.",
    },
    "abc_purpose": {
        "de": "**Wozu ABC?** Es teilt nach Wichtigkeit ein: **A** sind die Renner, die "
              "oft gepickt werden – die gehören auf gut erreichbare Plätze. **C** sind "
              "die Langsamdreher und können in die Reserve. Ziel: kurze Wege für die "
              "wichtigen Artikel.",
        "en": "**Why ABC?** It groups things by importance: **A** are the fast movers, "
              "picked often – they belong in easy-reach slots. **C** are the slow "
              "movers and can go into reserve. The goal: short travel for the important "
              "items.",
    },
    "abc_mode_note": {
        "de": "**Nach Artikeln** = klassische ABC nach **Anzahl Bewegungen** (wie oft "
              "ein Produkt bewegt wird). **Nach Menge (Stück)** = nach der tatsächlich "
              "bewegten **Stückzahl** (`MENGE_IST`) – wie viel von einem Produkt "
              "wirklich gebraucht wurde. **Nach Lagerplätzen** = welche *Plätze* am "
              "häufigsten angefahren werden.",
        "en": "**By articles** = classic ABC by **number of movements** (how often a "
              "product is moved). **By quantity (pcs)** = by the actual **units moved** "
              "(`MENGE_IST`) – how much of a product was really used. **By storage "
              "slots** = which *slots* are visited most often.",
    },
    "abc_c_note": {
        "de": "Hinweis: Bei „nach Lagerplätzen“ sind die **leeren Plätze (0 Picks)** "
              "im Diagramm als eigene Kategorie **„leer“** ausgewiesen – das ist die "
              "freie Reserve (~88 % der Plätze) und kein echtes „C“. In den Tabellen "
              "unten zählen sie rechnerisch weiter zu C.",
        "en": "Note: for ‘by storage slots’ the **empty slots (0 picks)** are shown as "
              "a separate **‘empty’** category in the chart – that's the free reserve "
              "(~88 % of slots), not real ‘C’. In the tables below they still count "
              "towards C.",
    },
    "abc_berech_global": {"de": "Berechnet (Lager gesamt)",
                          "en": "Calculated (whole warehouse)"},
    "abc_berech_sel": {"de": "Berechnet (Auswahl)", "en": "Calculated (selection)"},
    "abc_cum_global": {"de": "kumul. Pick-% (gesamt)", "en": "cum. pick % (whole)"},
    "abc_cum_sel": {"de": "kumul. Pick-% (Auswahl)", "en": "cum. pick % (selection)"},
    "abc_a_thresh": {"de": "A bis % aller Picks", "en": "A up to % of all picks"},
    "abc_b_thresh": {"de": "B bis % aller Picks", "en": "B up to % of all picks"},
    "abc_thresh_note": {
        "de": "A/B/C nach dem aufsummierten Pick-Anteil (Pareto-Prinzip): erst nach "
              "Picks sortieren, dann ist A die kleine Gruppe, die zusammen schon die "
              "ersten **{a} %** aller Picks ausmacht, B geht bis **{b} %**, der Rest ist "
              "C (Standard-Schwellen {a} / {b} %).",
        "en": "A/B/C by the cumulative pick share (Pareto principle): sort by picks "
              "first, then A is the small group that already makes up the first **{a}%** "
              "of all picks, B goes up to **{b}%**, the rest is C (standard thresholds "
              "{a} / {b} %).",
    },
    "abc_dist_count": {"de": "Anzahl je Klasse", "en": "Count per class"},
    "abc_dist_share": {"de": "Pick-Anteil je Klasse", "en": "Pick share per class"},
    "abc_bar_title": {"de": "Anteil je Klasse: Plätze vs. Picks",
                      "en": "Share per class: slots vs. picks"},
    "abc_dist_note": {
        "de": "Das Balkendiagramm stellt je Klasse den Anteil der Plätze (grau) dem "
              "Anteil der Picks (blau) gegenüber. Genau das ist der ABC-Effekt: wenige "
              "A-Plätze (kleiner grauer Balken) tragen den Großteil der Picks (großer "
              "blauer Balken). Die genauen Zahlen stehen rechts.",
        "en": "The bar chart puts the share of slots (grey) next to the share of picks "
              "(blue) for each class. That's exactly the ABC effect: a few A slots "
              "(small grey bar) carry most of the picks (large blue bar). The exact "
              "figures are on the right.",
    },
    "abc_col_count": {"de": "Anzahl", "en": "Count"},
    "abc_col_share": {"de": "Anteil %", "en": "Share %"},
    "abc_stamm_note": {
        "de": "**Stamm** ist die im Lagersystem hinterlegte Klasse. **Berechnet** ist "
              "die Klasse aus dem aufsummierten Pick-Anteil über das ganze Lager "
              "(Standard 80 / 95 %, wie in der 3D-Ansicht) – unabhängig von Filter und "
              "Reglern. Der Filter bestimmt nur, welche Zeilen angezeigt werden. Weichen "
              "Stamm und Berechnet voneinander ab, ist der Platz ein Kandidat für eine "
              "ABC-Anpassung.",
        "en": "**Master** is the class stored in the warehouse system. **Calculated** "
              "is the class from the cumulative pick share across the whole warehouse "
              "(default 80 / 95 %, like the 3D view) – independent of filters and "
              "sliders. The filter only decides which rows are shown. If master and "
              "calculated differ, the slot is a candidate for an ABC adjustment.",
    },
    "abc_cumcol": {"de": "kumul. Pick-%", "en": "cum. pick %"},
    "abc_pareto": {
        "de": "Pareto-Kurve — kumulativer Anteil der Bewegungen",
        "en": "Pareto curve — cumulative share of movements",
    },
    "abc_px_slots": {"de": "Plätze (nach Picks sortiert)", "en": "Slots (sorted by picks)"},
    "abc_px_articles": {"de": "Artikel (nach Bewegungen sortiert)", "en": "Articles (sorted by movements)"},
    "abc_py": {"de": "kumulativer Anteil %", "en": "cumulative share %"},
    "abc_intro_articles": {
        "de": "**ABC nach Artikeln** — die Artikel nach **Anzahl Bewegungen** sortiert. "
              "A = Top-Artikel bis {a} % aller Bewegungen, B = bis {b} %, der Rest C.",
        "en": "**ABC by articles** — articles sorted by **number of movements**. "
              "A = top articles up to {a}% of all movements, B = up to {b}%, rest C.",
    },
    "abc_intro_menge": {
        "de": "**ABC nach Menge** — die Artikel nach **tatsächlich bewegter Stückzahl** "
              "(`MENGE_IST`) sortiert: wie viel von einem Produkt wirklich gebraucht "
              "wurde. A = Top-Artikel bis {a} % der Gesamtmenge, B = bis {b} %, Rest C.",
        "en": "**ABC by quantity** — articles sorted by **actual units moved** "
              "(`MENGE_IST`): how much of a product was really used. A = top articles "
              "up to {a}% of total quantity, B = up to {b}%, rest C.",
    },
    "abc_dist": {"de": "ABC-Verteilung", "en": "ABC distribution"},
    "abc_count": {"de": "Anzahl je Klasse", "en": "Count per class"},
    "abc_adjust_head": {
        "de": "**🏷️ Tabelle 1: Wo passt die hinterlegte Klasse nicht? (Empfehlungen)**",
        "en": "**🏷️ Table 1: Where doesn't the stored class fit? (recommendations)**",
    },
    "abc_adjust_intro": {
        "de": "Hier stehen nur die Plätze, deren **Ware** öfter oder seltener gepickt "
              "wird, als die hinterlegte Klasse sagt. **⬆️ Hochstufen** = die Ware "
              "wird häufiger gebraucht als hinterlegt. **⬇️ Herabstufen** = seltener.",
        "en": "This shows only the slots whose **goods** are picked more or less often "
              "than the stored class says. **⬆️ Promote** = the goods are needed more "
              "often than recorded. **⬇️ Demote** = less often.",
    },
    "abc_promote": {"de": "⬆️ Hochstufen", "en": "⬆️ Promote"},
    "abc_demote": {"de": "⬇️ Herabstufen", "en": "⬇️ Demote"},
    "abc_rec": {"de": "Empfehlung", "en": "Recommendation"},
    "abc_promote_note": {
        "de": "Die **Ware** auf diesem Platz wird **häufiger** gepickt, als die "
              "hinterlegte ABC-Klasse vermuten lässt → Klasse anheben und die Ware "
              "auf einen besser erreichbaren Platz umlagern (meistgepickte oben).",
        "en": "The **goods** on this slot are picked **more often** than the stored "
              "ABC class suggests → raise the class and relocate the goods to a "
              "better-reachable slot (most-picked on top).",
    },
    "abc_demote_note": {
        "de": "Die **Ware** wird **seltener** gepickt als hinterlegt → Klasse senken "
              "und den gut erreichbaren Platz für einen echten Renner freimachen "
              "(am wenigsten gepickte oben).",
        "en": "The **goods** are picked **less often** than recorded → lower the class "
              "and free up the well-reachable slot for a true mover (least-picked on "
              "top).",
    },
    "abc_none_cat": {
        "de": "Keine Plätze in dieser Kategorie (mit aktuellen Filtern).",
        "en": "No slots in this category (with current filters).",
    },
    "abc_no_dev": {
        "de": "Keine Abweichungen mit aktuellen Filtern – Stamm-ABC passt.",
        "en": "No deviations with current filters – master ABC matches.",
    },
    "tp_use_range": {
        "de": "Datumsbereich statt „letzte N Tage“",
        "en": "Use date range instead of ‘last N days’",
    },
    "tp_range": {"de": "Zeitraum", "en": "Date range"},
    "tab_article": {"de": "🔎 Artikel", "en": "🔎 Article"},
    "art_intro": {
        "de": "### 🔎 Artikel-Detail\n**Wie oft und von welchen Plätzen** ein "
              "einzelner Artikel bewegt wurde.",
        "en": "### 🔎 Article detail\n**How often and from which slots** a single "
              "article was moved.",
    },
    "art_info_t": {
        "de": "ℹ️ Was bedeutet das? (Artikel-Detail + „Picks je Quellplatz“)",
        "en": "ℹ️ What does this mean? (article detail + “picks per source slot”)",
    },
    "art_info_b": {
        "de": "Wähle oben einen Artikel (aus der Liste oder per Nummer). Dann siehst du, wie oft und wo er bewegt "
              "wurde.\n\n"
              "**Kennzahlen:** *Bewegungen gesamt* = alle Picks dieses Artikels im Zeitraum · *Quellplätze* = von wie "
              "vielen verschiedenen Plätzen er entnommen wurde.\n\n"
              "**Was heißt „Picks je Quellplatz“?** Ein Quellplatz ist der Platz, aus dem entnommen wird. Die Tabelle "
              "zeigt je Platz, wie oft dieser Artikel von dort gepickt wurde – so siehst du, ob er über viele Plätze "
              "verstreut ist oder nur von wenigen kommt.\n\n"
              "**Was ist ein Pick?** Eine einzelne Entnahme – eine Position eines Auftrags, wie im Tagesbewegungen-Tab.\n\n"
              "**Bewegungen über Zeit** = die Picks dieses Artikels je Tag (ein Balken = ein Tag). Das Wochenende ist "
              "immer ausgeblendet.",
        "en": "Pick an article above (from the list or by number). You then see how often and where it was "
              "moved.\n\n"
              "**KPIs:** *Total movements* = all picks of this article in the period · *Source slots* = how many "
              "different slots it was retrieved from.\n\n"
              "**What does “picks per source slot” mean?** A source slot is the slot goods are picked from. The table "
              "shows, per slot, how often this article was picked there – so you see whether it's spread over many "
              "slots or comes from just a few.\n\n"
              "**What is a pick?** A single retrieval – one line of an order, like in the Daily movements tab.\n\n"
              "**Movements over time** = the picks of this article per day (one bar = one day). The weekend is always "
              "hidden.",
    },
    "art_select": {"de": "Artikel (Top nach Bewegungen)", "en": "Article (top by movements)"},
    "art_input": {"de": "… oder ARTIKELNR direkt eingeben", "en": "… or enter article no. directly"},
    "art_total": {"de": "Bewegungen gesamt", "en": "Total movements"},
    "art_slotcount": {"de": "Quellplätze", "en": "Source slots"},
    "art_by_slot": {"de": "Picks je Quellplatz", "en": "Picks per source slot"},
    "art_trend": {"de": "Bewegungen über Zeit", "en": "Movements over time"},
    "art_none": {
        "de": "Keine Bewegungen für diesen Artikel gefunden.",
        "en": "No movements found for this article.",
    },
    "tp_intro": {
        "de": "**Tagesbewegungen** — wie viele Lagerbewegungen es pro Tag gab. Den "
              "Zeitraum stellst du links mit dem Regler ein.",
        "en": "**Daily movements** — how many warehouse movements there were per day. "
              "Set the period with the slider on the left.",
    },
    "tp_info_t": {
        "de": "ℹ️ Was bedeutet das? (Tagesbewegungen + „eine Bewegung“ erklärt)",
        "en": "ℹ️ What does this mean? (daily movements + “one movement”)",
    },
    "tp_info_b": {
        "de": "Dieser Tab zählt die Lagerbewegungen pro Tag und zeigt sie als Balken (ein Balken = ein Tag).\n\n"
              "**Was zählt als eine Bewegung?** Eine Bewegung ist eine Position eines Auftrags – also in der Regel "
              "eine Entnahme bzw. ein Pick. Hat ein Auftrag mehrere Positionen, zählt jede einzeln. *Ob eine "
              "Position genau einer Orderzeile oder einem Artikel entspricht, legt das Lagersystem fest.*\n\n"
              "**Kennzahlen unter dem Diagramm:** *Ø pro Tag* = Durchschnitt über die angezeigten Tage · *Maximum* = "
              "der stärkste Einzeltag · *Summe Zeitraum* = alle Bewegungen zusammen.\n\n"
              "**Das Wochenende ist immer ausgeblendet**, weil samstags und sonntags kaum regulär bewegt wird. Die "
              "Null-Tage würden den Verlauf sonst nur verzerren; ohne sie ist der Arbeitstag-Verlauf klarer.",
        "en": "This tab counts the warehouse movements per day and shows them as bars (one bar = one day).\n\n"
              "**What counts as one movement?** A movement is one line of an order – usually one retrieval, i.e. one "
              "pick. If an order has several lines, each one counts. *Whether one line equals exactly one order row "
              "or one article is defined by the warehouse system.*\n\n"
              "**KPIs below the chart:** *Avg. per day* = mean over the shown days · *Maximum* = the strongest single "
              "day · *Sum (period)* = all movements together.\n\n"
              "**The weekend is always hidden**, because there's hardly any regular activity on Saturdays and "
              "Sundays. The zero days would only distort the trend; without them the working-day trend is clearer.",
    },
    "tp_chart": {"de": "Bewegungen letzte {n} Tage", "en": "Movements last {n} days"},
    "tp_avg": {"de": "Ø pro Tag", "en": "Avg. per day"},
    "tp_max": {"de": "Maximum", "en": "Maximum"},
    "tp_sum": {"de": "Summe Zeitraum", "en": "Sum (period)"},
    "top_intro": {
        "de": "**Top-Artikel** — die Artikel mit den meisten Bewegungen. Wie viele "
              "angezeigt werden, stellst du links mit dem Regler ein.",
        "en": "**Top items** — the articles with the most movements. Set how many are "
              "shown with the slider on the left.",
    },
    "top_chart": {"de": "Meistbewegte Artikel", "en": "Most-moved items"},
    "top_info_t": {
        "de": "ℹ️ Was bedeutet das? (Top-Artikel + „eine Bewegung“)",
        "en": "ℹ️ What does this mean? (top items + “one movement”)",
    },
    "top_info_b": {
        "de": "Dieser Tab zeigt die meistbewegten Artikel, sortiert nach Bewegungen (oben die stärksten). So siehst "
              "du die echten Dreher im Sortiment. Wie viele angezeigt werden, stellst du links mit dem Regler ein.\n\n"
              "**Was zählt als eine Bewegung?** Eine Bewegung ist eine Position eines Auftrags – eine Entnahme bzw. "
              "ein Pick, genau wie im Tagesbewegungen-Tab. *Ob eine Position genau einer Orderzeile oder einem Artikel "
              "entspricht, legt das Lagersystem fest.*\n\n"
              "**Spalten:** *Artikel-Nr* = die Artikelnummer · *Bezeichnung* = der Klartext-Name · *Bewegungen* = wie "
              "oft der Artikel im Zeitraum bewegt wurde.\n\n"
              "*Hinweis:* Mit einem aktiven Platzfilter links zählen nur Bewegungen, die von den ausgewählten Plätzen "
              "ausgehen.",
        "en": "This tab shows the most-moved articles, sorted by movements (the busiest on top). This reveals the "
              "real movers in the assortment. Set how many are shown with the slider on the left.\n\n"
              "**What counts as one movement?** A movement is one line of an order – a retrieval, i.e. a pick, just "
              "like in the Daily movements tab. *Whether one line equals exactly one order row or one article is defined "
              "by the warehouse system.*\n\n"
              "**Columns:** *Article no.* = the article number · *Description* = the plain name · *Movements* = how "
              "often the article was moved in the period.\n\n"
              "*Note:* With an active slot filter on the left, only movements originating from the selected slots are "
              "counted.",
    },
    "no_data_filters": {
        "de": "Keine Daten mit aktuellen Filtern.",
        "en": "No data with current filters.",
    },
    "mov_filtered": {
        "de": "🔗 Gefiltert: nur Bewegungen aus den {n} aktuell gewählten Plätzen. "
              "Filter leeren zeigt wieder das ganze Lager.",
        "en": "🔗 Filtered: only movements from the {n} currently selected slots. "
              "Clear the filters to see the whole warehouse again.",
    },
    "d3_autorotate": {"de": "Auto-Rotation", "en": "Auto-rotate"},
    "d3_brightness": {"de": "Helligkeit", "en": "Brightness"},
    "d3_shadow": {"de": "Schatten", "en": "Shadow"},
    "d3_height": {"de": "Anzeigehöhe (px)", "en": "Viewer height (px)"},
    "d3_height_help": {
        "de": "Höhe des Viewer-Fensters in Pixeln – größer = mehr Bildfläche, "
              "kein Zoom. Zoomen per Mausrad im Modell.",
        "en": "Height of the viewer window in pixels – larger = more canvas, "
              "not zoom. Zoom with the mouse wheel inside the model.",
    },
    "d3_sens": {"de": "Maus-Empfindlichkeit", "en": "Mouse sensitivity"},
    "d3_sens_help": {
        "de": "Wie stark die Maus auf Drehen/Zoomen reagiert. Kleiner = du musst "
              "die Maus weiter bewegen, dafür feiner und ruhiger steuerbar. "
              "1.0 = Standard.",
        "en": "How strongly the mouse reacts to rotate/zoom. Lower = you move the "
              "mouse further, but control is finer and steadier. 1.0 = default.",
    },
    "d3_aisle": {"de": "Gang-Breite", "en": "Aisle width"},
    "d3_aisle_help": {
        "de": "Zieht die Regalreihen rein optisch weiter auseinander – breitere "
              "Gänge zum Durchfliegen. Ändert keine Daten, nur die Darstellung.",
        "en": "Spreads the rack rows further apart visually – wider aisles to fly "
              "through. Changes no data, only the rendering.",
    },
    "d3_reset": {"de": "Ansicht zurücksetzen", "en": "Reset view"},
    "d3_caption": {
        "de": "Steuerung: Ziehen = drehen, Scrollen = zoomen, Rechtsklick-Ziehen "
              "= verschieben. **W A S D = durch die Regale fliegen**, Q/E = "
              "runter/hoch, Shift = schneller (erst ins Modell klicken). Oder den "
              "**Controller unten rechts** nutzen (Pfeile = bewegen, ⟲⟳ = drehen, "
              "+/− = zoomen, ⌂ = Ansicht zurücksetzen). "
              "Klick auf einen Platz zeigt seine Daten **unter der Karte**.",
        "en": "Controls: drag = rotate, scroll = zoom, right-drag = pan. "
              "**W A S D = fly through the racks**, Q/E = down/up, Shift = "
              "faster (click into the model first). Or use the **controller at the "
              "bottom right** (arrows = move, ⟲⟳ = rotate, +/− = zoom, ⌂ = reset "
              "view). Click a slot to see its data **below the map**.",
    },
    "abc3d_head": {"de": "### 🏷️ ABC je Lagerplatz", "en": "### 🏷️ ABC per slot"},
    "abc3d_intro": {
        "de": "Welche Plätze welcher ABC-Klasse zugeordnet sind. Reagiert auf die "
              "Sidebar-Filter; zusätzlich nach ABC-Klasse filterbar.",
        "en": "Which slots belong to which ABC class. Reacts to the sidebar "
              "filters; additionally filterable by ABC class.",
    },
    "abc3d_src": {"de": "ABC-Quelle", "en": "ABC source"},
    "abc3d_calc": {"de": "Berechnet", "en": "Calculated"},
    "abc3d_master": {"de": "Stamm-ABC", "en": "Master ABC"},
    "abc3d_classfilter": {"de": "Nur ABC-Klasse", "en": "Only ABC class"},
    "fach_label": {"de": "Fach", "en": "Bin"},
    # --- klickbarer 3D-Viewer ---
    "d3_head": {
        "de": "### 🧊 3D-Modell\n**Das Lager als klickbares 3D-Modell** — die Plätze "
              "im echten CAD-Layout, eingefärbt nach ABC oder Heatmap.",
        "en": "### 🧊 3D model\n**The warehouse as a clickable 3D model** — the slots "
              "in the real CAD layout, colored by ABC or heatmap.",
    },
    "d3_explain_head": {
        "de": "ℹ️ Was bedeutet das? (Bedienung, Einfärbung)",
        "en": "ℹ️ What does this mean? (controls, coloring)",
    },
    "d3_click_intro": {
        "de": "**Klickbares 3D-Modell** — klick einen Lagerplatz im Modell an, dann "
              "siehst du rechts seine Kennzahlen. Jeder Platz ist mit der Datenbank "
              "verknüpft.",
        "en": "**Clickable 3D model** — click a storage slot in the model and you'll "
              "see its metrics on the right. Every slot is linked to the database.",
    },
    "d3_color_abc": {"de": "Nach ABC einfärben", "en": "Color by ABC"},
    # CAD-Viewer: Auswahl der Einfaerbung (ABC / Pick-Heatmap / Bewegungs-Heatmap)
    "d3_cad_cm_abc": {"de": "ABC-Klasse", "en": "ABC class"},
    "d3_cad_cm_picks": {"de": "Heatmap: Picks", "en": "Heatmap: picks"},
    "d3_cad_cm_moves": {"de": "Heatmap: Bewegungen", "en": "Heatmap: movements"},
    "d3_cad_cm_none": {"de": "Keine (Original)", "en": "None (original)"},
    "d3_cad_cm_help": {
        "de": "Wie die Plätze eingefärbt werden. **ABC-Klasse**: rot/gelb/grün nach "
              "berechneter ABC-Klasse. **Heatmap: Picks**: fließend kalt→heiß nach "
              "Pick-Häufigkeit (ANZ_PICKS). **Heatmap: Bewegungen**: nach Picks + "
              "Nachschub zusammen. **Keine**: Original-Optik des Modells. Die "
              "Heatmaps färben nach Rang/Perzentil – wenige Hotspots verzerren die "
              "Skala nicht; graue Plätze = keine Aktivität.",
        "en": "How slots are colored. **ABC class**: red/yellow/green by calculated "
              "ABC class. **Heatmap: picks**: smooth cold→hot by pick frequency "
              "(ANZ_PICKS). **Heatmap: movements**: by picks + replenishment "
              "combined. **None**: model's original look. The heatmaps color by "
              "rank/percentile – a few hotspots don't distort the scale; grey slots "
              "= no activity.",
    },
    "d3_heat_picks": {"de": "Pick-Häufigkeit", "en": "Pick frequency"},
    "d3_heat_moves": {"de": "Bewegungen (Picks + Nachschub)",
                      "en": "Movements (picks + replenishment)"},
    "d3_heat_low": {"de": "selten", "en": "rare"},
    "d3_heat_high": {"de": "oft", "en": "frequent"},
    "d3_heat_zero": {"de": "keine Aktivität", "en": "no activity"},
    "d3_colormode": {"de": "Färben nach", "en": "Color by"},
    "d3_cm_neutral": {"de": "Neutral (Holz)", "en": "Neutral (wood)"},
    "d3_cm_abc": {"de": "ABC-Klasse", "en": "ABC class"},
    "d3_cm_util": {"de": "Auslastung", "en": "Utilization"},
    "d3_cm_occ": {"de": "Belegt / Frei", "en": "Occupied / Free"},
    "d3_panel_hint": {
        "de": "Klicke einen Lagerplatz im Modell an.",
        "en": "Click a storage slot in the model.",
    },
    "d3_f_platz": {"de": "Lagerplatz", "en": "Slot"},
    "d3_f_pos": {"de": "Regal / Fach / Ebene", "en": "Rack / bin / level"},
    "d3_f_abc_m": {"de": "ABC (Stamm)", "en": "ABC (master)"},
    "d3_f_abc_c": {"de": "ABC (berechnet)", "en": "ABC (calculated)"},
    "d3_f_picks": {"de": "Picks", "en": "Picks"},
    "d3_f_nachschub": {"de": "Nachschub", "en": "Replenishment"},
    "d3_f_util": {"de": "Auslastung", "en": "Utilization"},
    "d3_f_status": {"de": "Status", "en": "Status"},
    "d3_f_cap": {"de": "Kapazität (belegt/max)", "en": "Capacity (used/max)"},
    "d3_f_free": {"de": "Frei (LHM)", "en": "Free (LHM)"},
    "d3_f_locked": {"de": "Gesperrt", "en": "Locked"},
    "d3_f_lastacc": {"de": "Letzter Zugriff", "en": "Last access"},
    "d3_f_daysempty": {"de": "Tage leer", "en": "Days empty"},
    "d3_yes": {"de": "Ja", "en": "Yes"},
    "d3_no": {"de": "Nein", "en": "No"},
    "d3_occupied": {"de": "belegt", "en": "occupied"},
    "d3_empty": {"de": "frei", "en": "empty"},
    "d3_not_in_db": {
        "de": "Dieser Platz ist nicht in der Datenbank (nur im Modell).",
        "en": "This slot is not in the database (model only).",
    },
    "d3_legend": {"de": "Plätze im Modell", "en": "Slots in model"},
    "d3_grey": {"de": "ohne Daten", "en": "no data"},
    "d3_view": {"de": "Ansicht", "en": "View"},
    "d3_view_cad": {"de": "CAD-Modell (Teildaten)", "en": "CAD model (partial)"},
    "d3_view_schema": {"de": "Daten-Modell (alle Plätze)", "en": "Data model (all slots)"},
    "d3_schema_intro": {
        "de": "**Daten-Modell** — jeder Lagerplatz aus der Datenbank als Box, "
              "angeordnet nach Regal, Fach und Ebene. Hier sind **alle 22.429 Plätze** "
              "dabei (keine grauen Lücken), wahlweise eingefärbt nach Auslastung, "
              "Belegung oder ABC.",
        "en": "**Data model** — every storage slot from the database as a box, arranged "
              "by rack, bin and level. **All 22,429 slots** are here (no grey gaps), "
              "colored by utilization, occupancy or ABC as you like.",
    },
    "d3_schema_caption": {
        "de": "Steuerung: Ziehen = drehen, Scrollen = zoomen, **WASD = fliegen** "
              "(erst ins Bild klicken), Q/E = runter/hoch. Klick auf eine Box "
              "zeigt die Platz-Daten. Jede Box = 1 Lagerplatz aus der DB.",
        "en": "Controls: drag = rotate, scroll = zoom, **WASD = fly** (click into "
              "the view first), Q/E = down/up. Click a box for slot data. Each "
              "box = 1 slot from the DB.",
    },
    "search_platz": {"de": "🔎 Lagerplatz suchen (PLATZ_ID)", "en": "🔎 Find slot (PLATZ_ID)"},
    "search_platz_help": {
        "de": "Die 9-stellige Platz-Nummer eingeben und Enter drücken – die Ansicht "
              "fliegt zu diesem Platz und markiert ihn.",
        "en": "Enter the 9-digit slot number and press Enter – the view flies to that "
              "slot and highlights it.",
    },
    "d3_notfound": {
        "de": "Platz nicht im Modell gefunden.",
        "en": "Slot not found in the model.",
    },
    "d3_perf": {"de": "Plätze ohne Daten ausblenden", "en": "Hide slots without data"},
    "d3_perf_help": {
        "de": "Blendet die grauen Plätze aus, zu denen es keinen Datensatz gibt (reine "
              "Modell-Plätze). Standardmäßig an – das ist übersichtlicher und läuft "
              "flüssiger. Es gehen keine Daten verloren.",
        "en": "Hides the grey slots that have no data record (model-only). On by "
              "default – cleaner and smoother. No data is lost.",
    },
    # --- Erklaerungen/Beschriftungen (Lehrer-Feedback) ---
    "active_filters": {"de": "Aktive Filter", "en": "Active filters"},
    "filter_none": {"de": "keine (ganzes Lager)", "en": "none (whole warehouse)"},
    "weekend_hidden": {
        "de": "ℹ️ Samstag & Sonntag sind ausgeblendet (am Wochenende kaum Lagerbewegung).",
        "en": "ℹ️ Saturday & Sunday are excluded (hardly any warehouse activity on weekends).",
    },
    "tab_reloc_retr": {"de": "🔄 Um-/Auslagern", "en": "🔄 Relocate / retrieve"},
    "massn_rowhint": {
        "de": "Jede Zeile = 1 Lagerplatz mit dem aktuell dort liegenden Artikel.",
        "en": "Each row = 1 storage slot with the article currently stored there.",
    },
}


def t(key: str) -> str:
    entry = TR.get(key)
    if not entry:
        return key
    return entry.get(_LANG, entry.get("de", key))


@st.cache_resource(show_spinner="Lade DB ...")
def get_db_path() -> str:
    """Liefert den Pfad zur warehouse.db.

    Reihenfolge: (1) lokale Datei aus _DB_CANDIDATES, (2) sonst Download von
    `db_url` (Streamlit-Secret) bzw. WAREHOUSE_DB_URL (Env). Die ~300 MB grosse
    DB liegt NICHT im Git-Repo, sondern als GitHub-Release-Asset; daher der
    Download-Fallback. @st.cache_resource = nur einmal pro Session ausfuehren.
    """
    for p in _DB_CANDIDATES:
        if p.exists():
            return str(p)

    db_url = st.secrets.get("db_url") if hasattr(st, "secrets") else None
    if not db_url:
        db_url = os.environ.get("WAREHOUSE_DB_URL")
    if db_url:
        cache_dir = Path(tempfile.gettempdir()) / "schaeflein_lagerview"
        cache_dir.mkdir(parents=True, exist_ok=True)
        target = cache_dir / "warehouse.db"
        if not target.exists():
            urlretrieve(db_url, target)
        return str(target)

    st.error(
        "Keine warehouse.db gefunden. Lokal: Datei nach `data/warehouse.db` legen. "
        "Auf Streamlit Cloud: `db_url` in den App-Secrets setzen."
    )
    st.stop()


@st.cache_resource
def get_connection() -> sqlite3.Connection:
    path = get_db_path()
    # Read-only via URI: auf Streamlit Cloud ist das DB-File read-only
    # gemountet, ein RW-Open scheitert beim ersten Journal-Schreiben mit
    # "attempt to write a readonly database".
    uri = f"file:{Path(path).absolute().as_posix()}?mode=ro"
    return sqlite3.connect(uri, uri=True, check_same_thread=False)


@st.cache_data(ttl=3600, show_spinner="Lade Stellplaetze ...")
def load_platz_full() -> pd.DataFrame:
    """Zentrale Tabelle der App: ein Datensatz je Stellplatz, angereichert um
    abgeleitete Kennzahlen. Fast alle Tabs/Filter bauen darauf auf.

    Schritte:
      1. Stammdaten je Platz aus der PLATZ-Tabelle lesen
      2. Spalten in Zahlen wandeln (DB liefert teils Strings)
      3. Kennzahlen ableiten: UTILIZATION (%), FREE_CAPACITY, BELEGT,
         DAYS_EMPTY (Tage seit LEER_DATUM)
      4. Pick-Frequenz aus FAHRPOS dazumergen (PICK_COUNT_FAHR)
      5. ABC_CALC: ABC-Klasse aus der kumulativen Pick-Verteilung berechnen
    @st.cache_data(ttl=3600) = Ergebnis 1 h zwischenspeichern (teurer Query).
    """
    con = get_connection()
    platz = pd.read_sql_query(
        f'SELECT PLATZ_ID, REGAL, FACH, EBENE, ABC_KLASSE, MAX_LHM, IST_LHM, '
        f'ANZ_PICKS, ANZ_NACHSCHUB, ZUSTAND, SPERR_KNZ, LEER_DATUM, ZUGRIFF_DATUM '
        f'FROM "{PLATZ_TABLE}" '
        f"WHERE TRIM(COALESCE(PLATZ_ID, '')) <> ''",
        con,
    )

    platz["REGAL"] = pd.to_numeric(platz["REGAL"], errors="coerce").fillna(0).astype(int)
    platz["FACH"] = pd.to_numeric(platz["FACH"], errors="coerce").fillna(0).astype(int)
    platz["EBENE"] = pd.to_numeric(platz["EBENE"], errors="coerce").fillna(0).astype(int)
    platz["MAX_LHM"] = pd.to_numeric(platz["MAX_LHM"], errors="coerce")
    platz["IST_LHM"] = pd.to_numeric(platz["IST_LHM"], errors="coerce")
    platz["ANZ_PICKS"] = pd.to_numeric(platz["ANZ_PICKS"], errors="coerce").fillna(0).astype(int)
    platz["ANZ_NACHSCHUB"] = pd.to_numeric(platz["ANZ_NACHSCHUB"], errors="coerce").fillna(0).astype(int)
    platz["ZUSTAND"] = pd.to_numeric(platz["ZUSTAND"], errors="coerce").fillna(0).astype(int)
    platz["ABC_KLASSE"] = platz["ABC_KLASSE"].astype(str).str.strip().str.upper()

    # Auslastung in %: IST-Ladehilfsmittel / Maximum. 0 = leer, 100 = voll,
    # >100 = ueberbelegt. Ohne MAX_LHM (=0) ist die Auslastung undefiniert (NaN).
    platz["UTILIZATION"] = np.where(
        platz["MAX_LHM"] > 0,
        (platz["IST_LHM"] / platz["MAX_LHM"]) * 100,
        np.nan,
    )
    platz["FREE_CAPACITY"] = (platz["MAX_LHM"].fillna(0) - platz["IST_LHM"].fillna(0))
    # Belegt = physisch Ware vorhanden (IST_LHM > 0). ZUSTAND ist hier KEIN
    # verlaesslicher Indikator (nur Werte 0/150; nur ~19% der 150er haben
    # IST_LHM>0). Konsistent mit UTILIZATION/FREE_CAPACITY, die ebenfalls auf
    # IST_LHM beruhen.
    platz["BELEGT"] = platz["IST_LHM"].fillna(0) > 0
    # Gesperrt = SPERR_KNZ gesetzt (alles ausser leer/0). Das ist der echte
    # Sperr-Indikator (NICHT ZUSTAND); gleiche Definition wie der Sidebar-Filter.
    _sperr = platz["SPERR_KNZ"].astype(str).str.strip().str.lower()
    platz["GESPERRT"] = ~_sperr.isin(["", "0", "nan", "none"])
    platz["DAYS_EMPTY"] = (
        pd.Timestamp.now().normalize()
        - pd.to_datetime(platz["LEER_DATUM"], errors="coerce")
    ).dt.days
    # Tage seit letztem Pick (ZUGRIFF_DATUM). Eigenstaendiges Staleness-Signal
    # neben DAYS_EMPTY: besser gefuellt (auch Plaetze OHNE Leer-Datum haben ein
    # Zugriffsdatum) und unterscheidet "kuerzlich aktiv, Nachschub vergessen" von
    # "totes Fach". 'None'-Strings in den Rohdaten als fehlend behandeln.
    platz["DAYS_SINCE_PICK"] = (
        pd.Timestamp.now().normalize()
        - pd.to_datetime(
            platz["ZUGRIFF_DATUM"].replace(
                {"None": np.nan, "none": np.nan, "": np.nan}),
            errors="coerce",
        )
    ).dt.days

    # Pick-Count aus Fahrpos zusaetzlich mergen (Q_PLATZ = Quellplatz).
    try:
        fahrpos = pd.read_sql_query(
            f'SELECT Q_PLATZ FROM "{FAHRPOS_TABLE}" '
            f"WHERE TRIM(COALESCE(Q_PLATZ, '')) <> ''",
            con,
        )
        fahrpos["Q_PLATZ"] = fahrpos["Q_PLATZ"].astype(str).str.strip()
        pick_freq = (
            fahrpos.groupby("Q_PLATZ").size().reset_index(name="PICK_COUNT_FAHR")
        )
        platz["PLATZ_ID_STR"] = platz["PLATZ_ID"].astype(str).str.strip()
        platz = platz.merge(
            pick_freq, left_on="PLATZ_ID_STR", right_on="Q_PLATZ", how="left"
        )
        platz["PICK_COUNT_FAHR"] = platz["PICK_COUNT_FAHR"].fillna(0).astype(int)
        platz.drop(columns=["Q_PLATZ", "PLATZ_ID_STR"], inplace=True)
    except Exception:
        platz["PICK_COUNT_FAHR"] = 0

    # ABC nach kumulativer Pick-Verteilung (Pareto, aus warehouse_analytics.py):
    # Plaetze absteigend nach Picks sortieren, kumulierten Anteil bilden und
    # klassifizieren -> A = Plaetze, die zusammen die ersten 80 % aller Picks
    # ausmachen, B = bis 95 %, C = der lange Rest. Das ist die *berechnete*
    # Klasse (ABC_CALC) und kann von der hinterlegten ABC_KLASSE abweichen.
    abc_basis = platz.sort_values("ANZ_PICKS", ascending=False).copy()
    total = abc_basis["ANZ_PICKS"].sum()
    if total > 0:
        abc_basis["CUMULATIVE_%"] = (
            abc_basis["ANZ_PICKS"].cumsum() / total * 100
        )
        abc_basis["ABC_CALC"] = np.where(
            abc_basis["CUMULATIVE_%"] <= 80,
            "A",
            np.where(abc_basis["CUMULATIVE_%"] <= 95, "B", "C"),
        )
    else:
        abc_basis["CUMULATIVE_%"] = 0.0
        abc_basis["ABC_CALC"] = "C"
    platz = platz.merge(
        abc_basis[["PLATZ_ID", "CUMULATIVE_%", "ABC_CALC"]],
        on="PLATZ_ID",
        how="left",
    )
    return platz


# --- Bewegungsdaten (TPA/FAHRPOS) -----------------------------------------
# Diese load_*-Funktionen liefern jeweils ein fertiges DataFrame fuer genau
# einen Tab. Trennung von Datenbeschaffung (hier) und Darstellung (in main()).


@st.cache_data(ttl=3600, show_spinner="Lade Bewegungen ...")
def load_tpa_raw() -> pd.DataFrame:
    """Rohe TPA-Bewegungen (nur ~74k Zeilen) als EINE Quelle fuer alle
    bewegungsbasierten Tabs (Pick-Heatmap, Durchsatz, Top-Artikel, Artikel,
    ABC-nach-Artikeln).

    Frueher hatte jeder dieser Tabs sein eigenes GROUP-BY-SQL und ignorierte
    dadurch die Sidebar-Filter. Jetzt laden wir die Bewegungen einmal roh und
    aggregieren in Pandas – so kann ueber Q_PLATZ -> PLATZ_ID dieselbe
    Platz-Auswahl angewandt werden wie ueberall sonst. @st.cache_data cacht den
    Roh-Frame pro Session; die Aggregationen darauf sind bei der Datenmenge
    vernachlaessigbar guenstig.
    """
    con = get_connection()
    df = pd.read_sql_query(
        f"SELECT TRIM(COALESCE(Q_PLATZ, '')) AS q_platz, "
        f"TRIM(COALESCE(ARTIKELNR, '')) AS artikel, "
        f"TRIM(COALESCE(ARTBEZ1, '')) AS bezeichnung, "
        f"MENGE_IST, ENDE_DATUM, ENDE_ZEIT "
        f'FROM "{TPA_TABLE}"',
        con,
    )
    # MENGE_IST = tatsaechlich bewegte Stueckzahl (fuer ABC nach Verbrauch).
    df["menge"] = pd.to_numeric(df["MENGE_IST"], errors="coerce").fillna(0)
    df["day"] = pd.to_datetime(df["ENDE_DATUM"], errors="coerce")
    # Wochentag wie SQLite strftime('%w'): 0=So..6=Sa (Pandas: Mo=0..So=6).
    df["weekday"] = (df["day"].dt.dayofweek + 1) % 7
    df["hour"] = pd.to_numeric(
        df["ENDE_ZEIT"].astype(str).str.slice(0, 2), errors="coerce"
    )
    return df


def filter_tpa(tpa: pd.DataFrame, allowed_pids: set[str] | None) -> pd.DataFrame:
    """Bewegungen auf erlaubte Quellplaetze einschraenken (None = alle Plaetze)."""
    if allowed_pids is None:
        return tpa
    return tpa[tpa["q_platz"].isin(allowed_pids)]


def drop_weekend(df: pd.DataFrame, day_col: str = "day") -> pd.DataFrame:
    """Entfernt Samstag/Sonntag aus einem Tages-DataFrame (Mo=0..So=6).

    Wird in den Zeitreihen (Durchsatz, Artikel) genutzt, da das Lager am
    Wochenende kaum/keine regulaeren Bewegungen hat und die Tage die Diagramme
    sonst optisch verzerren.
    """
    if df.empty or day_col not in df.columns:
        return df
    return df[pd.to_datetime(df[day_col]).dt.dayofweek < 5]


def agg_pick_heatmap(tpa: pd.DataFrame) -> pd.DataFrame:
    """Picks je Wochentag (0=So..6=Sa) und Stunde."""
    sub = tpa.dropna(subset=["day", "hour"])
    if sub.empty:
        return pd.DataFrame(columns=["weekday", "hour", "picks"])
    return (
        sub.assign(weekday=sub["weekday"].astype(int), hour=sub["hour"].astype(int))
        .groupby(["weekday", "hour"]).size().reset_index(name="picks")
    )


def agg_movements_by_day(tpa: pd.DataFrame) -> pd.DataFrame:
    """Bewegungen je Kalendertag (chronologisch)."""
    sub = tpa.dropna(subset=["day"])
    if sub.empty:
        return pd.DataFrame(columns=["day", "movements"])
    return (
        sub.assign(d=sub["day"].dt.normalize())
        .groupby("d").size().reset_index(name="movements")
        .rename(columns={"d": "day"}).sort_values("day")
    )


def agg_throughput_trend(tpa: pd.DataFrame, days: int = 30) -> pd.DataFrame:
    """Bewegungen je Tag der letzten `days` Tage mit Bewegung."""
    daily = agg_movements_by_day(tpa)
    return daily.tail(days).reset_index(drop=True)


def agg_articles(tpa: pd.DataFrame, limit: int | None = None,
                 with_menge: bool = False) -> pd.DataFrame:
    """Bewegungen je Artikel (ARTIKELNR), absteigend. `limit` schneidet Top-N ab.

    with_menge=True ergaenzt die Spalte `menge` = Summe MENGE_IST (tatsaechlich
    bewegte Stueckzahl) – fuer die ABC-Sicht nach Verbrauch.
    """
    cols = ["artikel", "bezeichnung", "bewegungen"] + (["menge"] if with_menge else [])
    sub = tpa[tpa["artikel"] != ""]
    if sub.empty:
        return pd.DataFrame(columns=cols)
    aggs = {"bezeichnung": ("bezeichnung", "first"),
            "bewegungen": ("artikel", "size")}
    if with_menge:
        aggs["menge"] = ("menge", "sum")
    g = (
        sub.groupby("artikel").agg(**aggs)
        .reset_index().sort_values("bewegungen", ascending=False)
        .reset_index(drop=True)
    )
    if with_menge:
        g["menge"] = g["menge"].astype(int)
    g = g[cols]
    return g.head(limit) if limit else g


def agg_article_detail(
    tpa: pd.DataFrame, artikelnr: str
) -> tuple[pd.DataFrame, pd.DataFrame]:
    """Fuer einen Artikel: Picks je Quellplatz und Bewegungen je Tag."""
    sub = tpa[tpa["artikel"] == artikelnr]
    slots = (
        sub[sub["q_platz"] != ""].groupby("q_platz").size()
        .reset_index(name="picks").rename(columns={"q_platz": "platz"})
        .sort_values("picks", ascending=False)
    )
    dated = sub.dropna(subset=["day"])
    days = (
        dated.assign(d=dated["day"].dt.normalize())
        .groupby("d").size().reset_index(name="picks")
        .rename(columns={"d": "day"}).sort_values("day")
    )
    return slots, days


def classify_abc(
    df: pd.DataFrame, value_col: str, a_pct: float, b_pct: float
) -> pd.DataFrame:
    """ABC-Klassifikation nach kumulativem Anteil von `value_col`.

    Generische Variante der ABC-Logik aus load_platz_full(), aber mit *frei
    einstellbaren* Schwellen (Slider im ABC-Tab) und fuer beliebige Wertespalte
    – `ANZ_PICKS` (je Platz) oder `bewegungen` (je Artikel). Liefert zusaetzlich
    die Spalten CUM_% (kumulierter Anteil) und ABC (A/B/C).
    """
    out = df.sort_values(value_col, ascending=False).copy().reset_index(drop=True)
    total = out[value_col].sum()
    if total > 0:
        out["CUM_%"] = (out[value_col].cumsum() / total * 100).round(2)
        out["ABC"] = np.where(
            out["CUM_%"] <= a_pct, "A",
            np.where(out["CUM_%"] <= b_pct, "B", "C"),
        )
    else:
        out["CUM_%"] = 0.0
        out["ABC"] = "C"
    return out


@st.cache_data(ttl=3600, show_spinner="Baue 3D-Platzdaten ...")
def load_slot_3d_map() -> str:
    """Kompakte JSON-Map PLATZ_ID -> Kennzahlen fuer den klickbaren 3D-Viewer.

    Die Meshes in SampleScene_clickable.glb sind nach PLATZ_ID benannt. Beim
    Klick liest das three.js-Frontend hier nach, welche Werte zu dem Platz
    gehoeren (ABC, Picks, Auslastung, belegt). Als JSON-String gecacht, damit
    er pro Session nur einmal gebaut wird.
    """
    import json

    df = load_platz_full()
    out: dict[str, dict] = {}
    for row in df.itertuples(index=False):
        pid = str(row.PLATZ_ID).strip()
        if not pid:
            continue
        util = getattr(row, "UTILIZATION")
        mx = getattr(row, "MAX_LHM")
        il = getattr(row, "IST_LHM")
        fc = getattr(row, "FREE_CAPACITY")
        de = getattr(row, "DAYS_EMPTY")
        zd = str(getattr(row, "ZUGRIFF_DATUM") or "").strip()[:10]
        out[pid] = {
            "r": int(row.REGAL),
            "f": int(row.FACH),
            "e": int(row.EBENE),
            "a": (row.ABC_KLASSE or "—"),
            "ac": (row.ABC_CALC if isinstance(row.ABC_CALC, str) else "—"),
            "p": int(row.ANZ_PICKS),
            "n": int(getattr(row, "ANZ_NACHSCHUB", 0)),
            "u": (None if pd.isna(util) else round(float(util), 1)),
            "b": bool(row.BELEGT),
            # Kapazitaet in Ladehilfsmitteln (belegt/max), freie Kapazitaet,
            # Sperr-Status, letzter Zugriff (Datum) und Tage seit Leerstand.
            "mx": (None if pd.isna(mx) else round(float(mx), 1)),
            "il": (None if pd.isna(il) else round(float(il), 1)),
            "fc": (None if pd.isna(fc) else round(float(fc), 1)),
            "g": bool(getattr(row, "GESPERRT")),
            "lz": (zd if len(zd) == 10 and zd[4] == "-" else None),
            "dl": (None if pd.isna(de) else int(de)),
        }
    return json.dumps(out, ensure_ascii=False, separators=(",", ":"))


# Zentrale, einzige Quelle aller in der App verwendeten Formeln/Definitionen.
# Speist sowohl die komplette Formel-Referenz (render_formulas_popover) als auch
# die i-Icon-Tooltips je Kennzahl (fhelp). Aenderungen NUR hier pflegen.
FORMULAS: list[dict] = [
    {
        "key": "auslastung",
        "title": {"de": "Auslastung (%)", "en": "Utilization (%)"},
        "latex": r"\text{Auslastung}\,[\%] = \frac{\text{Belegt}}{\text{Kapazität}} \times 100",
        "plain": {"de": "Belegt ÷ Kapazität × 100",
                  "en": "Occupied ÷ capacity × 100"},
        "note": {"de": "Wie voll ein Platz ist: belegte Menge geteilt durch Kapazität. "
                       "0 % = leer, 100 % = voll. Werte über 100 % heißen nur, dass die "
                       "Kapazität zu niedrig gepflegt ist.",
                 "en": "How full a slot is: amount stored divided by capacity. 0 % = "
                       "empty, 100 % = full. Values above 100 % just mean the capacity "
                       "is set too low."},
    },
    {
        "key": "avg_util",
        "title": {"de": "Ø Auslastung", "en": "Avg. utilization"},
        "latex": r"\varnothing\,\text{Auslastung} = \frac{1}{n}\sum_{i=1}^{n} \frac{\text{Belegt}_i}{\text{Kapazität}_i} \times 100",
        "plain": {"de": "Durchschnitt der Auslastung über alle Plätze",
                  "en": "Average utilization across all slots"},
        "note": {"de": "Der Durchschnitt der Auslastung über alle Plätze in der "
                       "aktuellen Auswahl.",
                 "en": "The average utilization across all slots in the current "
                       "selection."},
    },
    {
        "key": "frei",
        "title": {"de": "Freie Kapazität", "en": "Free capacity"},
        "latex": r"\text{Frei} = \text{Kapazität} - \text{Belegt}",
        "plain": {"de": "Kapazität − Belegt", "en": "Capacity − occupied"},
        "note": {"de": "Wie viele Paletten/Behälter noch auf den Platz passen: "
                       "Kapazität minus Belegt.",
                 "en": "How many pallets/bins still fit on the slot: capacity minus "
                       "occupied."},
    },
    {
        "key": "belegt",
        "title": {"de": "Belegt", "en": "Occupied"},
        "latex": r"\text{Belegt} = (\text{Ist-Menge} > 0)",
        "plain": {"de": "mindestens eine Palette/ein Behälter steht drauf",
                  "en": "at least one pallet/bin is on it"},
        "note": {"de": "Ein Platz gilt als belegt, sobald mindestens eine Palette oder "
                       "ein Behälter darauf steht – auch bei nur teilweiser Füllung.",
                 "en": "A slot counts as occupied as soon as at least one pallet or bin "
                       "is on it – even when only partly filled."},
    },
    {
        "key": "gesperrt",
        "title": {"de": "Gesperrt", "en": "Locked"},
        "latex": r"\text{Gesperrt} = \text{Sperrkennzeichen ist gesetzt}",
        "plain": {"de": "Sperrkennzeichen ist gesetzt",
                  "en": "a lock flag is set"},
        "note": {"de": "Ein Platz ist gesperrt, wenn ein Sperrkennzeichen gesetzt ist "
                       "(z. B. Inventur oder Defekt). Dann nicht einlagern.",
                 "en": "A slot is locked when a lock flag is set (e.g. stocktake or "
                       "defect). Don't store there."},
    },
    {
        "key": "tage_leer",
        "title": {"de": "Tage leer", "en": "Days empty"},
        "latex": r"\text{Tage leer} = \text{heute} - \text{Leer-Datum}",
        "plain": {"de": "heute − Leer-Datum (in Tagen)",
                  "en": "today − empty date (in days)"},
        "note": {"de": "Wie viele Tage der Platz schon leer ist – von heute zurück bis "
                       "zum Leer-Datum.",
                 "en": "How many days the slot has been empty – from today back to the "
                       "empty date."},
    },
    {
        "key": "abc_calc",
        "title": {"de": "ABC (berechnet)", "en": "ABC (calculated)"},
        "latex": r"\text{kumulierter Pick-Anteil} \le 80\% \Rightarrow A,\quad \le 95\% \Rightarrow B,\quad \text{sonst } C",
        "plain": {"de": "kumulierter Pick-Anteil ≤ 80 % → A, ≤ 95 % → B, sonst C",
                  "en": "cumulative pick share ≤ 80 % → A, ≤ 95 % → B, else C"},
        "note": {"de": "Erst nach Picks sortieren, dann aufsummieren: bis 80 % = A, bis "
                       "95 % = B, der Rest = C.",
                 "en": "Sort by picks first, then add up: up to 80 % = A, up to 95 % = "
                       "B, the rest = C."},
    },
    {
        "key": "pick_total",
        "title": {"de": "Picks gesamt", "en": "Total picks"},
        "latex": r"\text{Picks gesamt} = \text{Picks (Stamm)} + \text{Anfahrten (Bewegungsdaten)}",
        "plain": {"de": "Picks (Stamm) + zusätzliche Anfahrten",
                  "en": "Picks (master) + extra visits"},
        "note": {"de": "Die im Lagersystem hinterlegten Picks plus die zusätzlichen "
                       "Anfahrten aus den Bewegungsdaten.",
                 "en": "The picks stored in the warehouse system plus the extra visits "
                       "from the movement data."},
    },
    {
        "key": "ebene_max",
        "title": {"de": "Obergrenze Ebenen-Regler", "en": "Level slider upper bound"},
        "latex": r"\text{höchste Ebene mit mindestens 20 Plätzen}",
        "plain": {"de": "höchste Ebene mit mindestens 20 Plätzen",
                  "en": "highest level with at least 20 slots"},
        "note": {"de": "Der Ebenen-Regler endet bei der höchsten Ebene mit mindestens "
                       "20 Plätzen, damit einzelne Ausreißer ganz oben die Skala nicht "
                       "aufblähen.",
                 "en": "The level slider stops at the highest level with at least 20 "
                       "slots, so single outliers at the very top don't inflate the "
                       "scale."},
    },
]

_FORMULA_BY_KEY = {f["key"]: f for f in FORMULAS}


def fhelp(key: str) -> str:
    """i-Icon-Tooltip-Text (Formel) je Kennzahl – aus der zentralen FORMULAS-Quelle.

    Formel als normaler Text (keine Backticks/Code-Box) – sonst faerbt Streamlit
    sie ein und stellt sie in einem Kasten dar.
    """
    f = _FORMULA_BY_KEY.get(key)
    if not f:
        return ""
    return f"**{f['title'][_LANG]}**\n\n{f['plain'][_LANG]}"


def render_formulas_popover() -> None:
    """ℹ️-Button mit ALLEN Formeln + Klartext-Erklaerung je Kennzahl.

    Pro Eintrag: Titel, die Formel als gerenderte Mathematik (st.latex) und eine
    Erklaerung in einem Satz – getrennt durch eine duenne Linie.
    """
    label = "ℹ️ Formeln" if _LANG == "de" else "ℹ️ Formulas"
    with st.popover(label):
        st.markdown("**Formeln & Erklärungen**" if _LANG == "de"
                    else "**Formulas & explanations**")
        for i, f in enumerate(FORMULAS):
            if i:
                st.divider()
            st.markdown(f"**{f['title'][_LANG]}**")
            st.latex(f["latex"])
            note = f.get("note")
            if note:
                st.write(note[_LANG])


def render_formel_popover(keys: list[str], label: str | None = None) -> None:
    """Kleiner ℹ️-Button, der gezielt NUR die Formel(n) zu bestimmten Kennzahlen
    zeigt (Titel, gerenderte Formel via st.latex, Klartext-Erklaerung) – aus
    derselben zentralen FORMULAS-Quelle wie die volle Referenz. Gedacht direkt
    neben einer Tabelle/CSV, wo eine berechnete Spalte erklaert werden soll."""
    items = [_FORMULA_BY_KEY[k] for k in keys if k in _FORMULA_BY_KEY]
    if not items:
        return
    lbl = label or ("ℹ️ Formel" if _LANG == "de" else "ℹ️ Formula")
    with st.popover(lbl):
        for i, f in enumerate(items):
            if i:
                st.divider()
            st.markdown(f"**{f['title'][_LANG]}**")
            st.latex(f["latex"])
            note = f.get("note")
            if note:
                st.write(note[_LANG])


def _logo_path() -> Path | None:
    """Sucht das Schaeflein-Logo unabhaengig vom Arbeitsverzeichnis."""
    candidates = [
        Path(__file__).resolve().parents[1] / "assets" / "branding" / "schaeflein_logo.jpg",
        Path("assets/branding/schaeflein_logo.jpg"),
        Path("../assets/branding/schaeflein_logo.jpg"),
    ]
    for c in candidates:
        if c.is_file():
            return c
    return None


def _csv_download(df: pd.DataFrame, key: str, label: str | None = None) -> None:
    """Einheitlicher CSV-Export-Button (utf-8-sig fuer Excel-Umlaute).

    Exportiert IMMER den vollstaendigen uebergebenen DataFrame (alle Treffer der
    aktuellen Filter, nicht nur die in der Tabelle angezeigten Zeilen). Die
    aktiven Filter werden als fuehrende Kommentarzeile in die CSV geschrieben,
    damit der Download nachvollziehbar "unter Angabe der Filter" ist.
    """
    csv = df.to_csv(index=False)
    if _FILTER_LABEL:
        csv = f"# {t('active_filters')}: {_FILTER_LABEL}\n" + csv
    st.download_button(
        label or t("dl"),
        csv.encode("utf-8-sig"),
        file_name=f"{key}.csv",
        mime="text/csv",
        key=f"dl_{key}",
    )


def apply_filters(
    df: pd.DataFrame,
    abc: list[str],
    util_range: tuple[float, float],
    only_occupied: bool,
    regal_range: tuple[int, int] | None = None,
    ebene_range: tuple[int, int] | None = None,
    min_picks: int = 0,
    sperr_mode: str = "Alle",
    abc_src: str = "Beide",
) -> pd.DataFrame:
    """Wendet die Sidebar-Filter auf das Platz-DataFrame an und gibt die
    Teilmenge zurueck. Wird einmal in main() aufgerufen; ALLE Tabs arbeiten
    danach mit diesem `filtered` – so wirkt jeder Filter ueberall gleich.
    Jeder Block ist ein optionaler Filter (leer/Default = nicht einschraenken).
    `abc_src` bestimmt, worauf die ABC-Auswahl wirkt: 'Stamm' (ABC_KLASSE),
    'Berechnet' (ABC_CALC) oder 'Beide' (ODER, Default).
    """
    out = df
    if abc:
        if abc_src == "Stamm":
            out = out[out["ABC_KLASSE"].isin(abc)]
        elif abc_src == "Berechnet":
            out = out[out["ABC_CALC"].isin(abc)]
        else:  # "Beide"
            out = out[out["ABC_KLASSE"].isin(abc) | out["ABC_CALC"].isin(abc)]
    lo, hi = util_range
    # Slider-Obergrenze 100 bedeutet "100 % und mehr" (nach oben offen), damit
    # seltene Ueberlast-Artefakte (>=200 %) und Plaetze ohne MAX_LHM im Default
    # nicht ausgeblendet werden. Nur einschraenken, wenn der Nutzer den Bereich
    # tatsaechlich verengt hat.
    if lo > 0 or hi < 100:
        util_filled = out["UTILIZATION"].fillna(-1)
        upper = float("inf") if hi >= 100 else hi
        out = out[(util_filled >= lo) & (util_filled <= upper)]
    if only_occupied:
        out = out[out["BELEGT"]]
    if regal_range is not None:
        rlo, rhi = regal_range
        out = out[(out["REGAL"] >= rlo) & (out["REGAL"] <= rhi)]
    if ebene_range is not None:
        elo, ehi = ebene_range
        out = out[(out["EBENE"] >= elo) & (out["EBENE"] <= ehi)]
    if min_picks > 0:
        out = out[out["ANZ_PICKS"] >= min_picks]
    if sperr_mode != "Alle":
        sperr = out["SPERR_KNZ"].astype(str).str.strip().str.lower()
        is_locked = ~sperr.isin(["", "0", "nan", "none"])
        out = out[is_locked] if sperr_mode == "Nur gesperrte" else out[~is_locked]
    return out


def de_num(n) -> str:
    """Deutsche Tausendertrennung fuer ganze Zahlen: 12345 -> '12.345'."""
    return f"{int(n):,}".replace(",", ".")


def mov_filter_note(movements_filtered: bool, filtered: pd.DataFrame) -> None:
    """Hinweis in bewegungsbasierten Tabs, wenn die Platz-Filter greifen."""
    if movements_filtered:
        st.caption(t("mov_filtered").format(n=de_num(len(filtered))))


# Spalten, die jede Massnahmen-Tabelle (Umlagern/Nachschub/Einlagern/Auslagern)
# zeigt; tab-spezifische Zusatzspalten kommen ueber `extra_cols` dazu.
_MASSNAHME_COLS = [
    "PLATZ_ID", "REGAL", "FACH", "EBENE",
    "ANZ_PICKS", "ABC_KLASSE", "MAX_LHM", "IST_LHM",
]

# Default-Umbenennung + Tooltips fuer die Standard-Massnahmenspalten
# (greift automatisch bei Umlagern/Auslagern, die keine eigene rename/col_help
# uebergeben). Macht v.a. ABC/Kapazitaet ohne Vorwissen verstaendlich.
_MASSNAHME_RENAME = {
    "PLATZ_ID": "Platz", "REGAL": "Regal", "FACH": "Fach", "EBENE": "Ebene",
    "ANZ_PICKS": "Picks", "ABC_KLASSE": "ABC (Platz)",
    "MAX_LHM": "Kapazität (max. LHM)", "IST_LHM": "Belegt (Ist-LHM)",
}
_MASSNAHME_HELP = {
    "Platz": "Die eindeutige Nummer des Lagerplatzes.",
    "Regal": "Regalnummer im Lager.",
    "Fach": "Fach innerhalb des Regals.",
    "Ebene": "Wie hoch der Platz liegt – niedrig heißt Pickzone mit kurzen "
             "Greifwegen.",
    "Picks": "Wie oft an diesem Platz gepickt wird (Häufigkeit aus dem "
             "Lagersystem).",
    "ABC (Platz)": "Die Güteklasse des Ortes aus dem Lagersystem (A = bester "
                   "Platz). Beschreibt den Platz, nicht den Artikel.",
    "Kapazität (max. LHM)": "Wie viele Paletten/Behälter auf den Platz passen "
                            "(kann auch mehr als einer sein).",
    "Belegt (Ist-LHM)": "Wie viele Paletten/Behälter aktuell drauf stehen.",
    "Vorschlag": "Die empfohlene Handlung für diese Zeile.",
    "Zielplatz-Vorschlag": "Ein konkreter freier Platz, auf den der Inhalt "
                           "umgelagert werden kann (nach freier Kapazität zugeordnet).",
}

# Schlanke Spalten fuer den Einlagern-Tab: freie Plaetze haben kaum/keine
# Ist-Ware, darum ist ANZ_PICKS hier ~0 und nur verwirrend. Relevant ist nur
# Ort, Platz-Guete (ABC) und freie Kapazitaet.
_PUTAWAY_COLS = [
    "PLATZ_ID", "REGAL", "FACH", "EBENE",
    "ABC_KLASSE", "MAX_LHM", "IST_LHM", "FREE_CAPACITY", "UTILIZATION",
]

# Sprechende Spaltenkoepfe fuer die Einlagern-Tabellen (technisch -> Klartext).
# Kapazitaet/Belegt/Frei machen MAX_LHM/IST_LHM/FREE_CAPACITY ohne Vorwissen klar.
_PUTAWAY_RENAME = {
    "PLATZ_ID": "Platz",
    "REGAL": "Regal",
    "FACH": "Fach",
    "EBENE": "Ebene",
    "ABC_KLASSE": "ABC (Platz)",
    "MAX_LHM": "Kapazität (max. LHM)",
    "IST_LHM": "Belegt (Ist-LHM)",
    "FREE_CAPACITY": "Frei (LHM)",
    "UTILIZATION": "Auslastung %",
}

# Hilfetexte je (umbenannter) Spalte – als ℹ️ am Tabellenkopf (col_help).
_PUTAWAY_HELP = {
    "Platz": "Die eindeutige Nummer des Lagerplatzes.",
    "Regal": "Regalnummer im Lager.",
    "Fach": "Fach innerhalb des Regals.",
    "Ebene": "Wie hoch der Platz liegt – niedrig ist die Pickzone mit kurzen "
             "Wegen. Entscheidet, ob ein Platz Schnelldreher oder Reserve ist.",
    "ABC (Platz)": "Die Güteklasse des Ortes aus dem Lagersystem (A = bester "
                   "Platz). Beschreibt den Platz, nicht den Artikel; A wird zum "
                   "Schnelldreher-Platz, alles andere zur Reserve.",
    "Kapazität (max. LHM)": "Wie viele Paletten/Behälter auf den Platz passen.",
    "Belegt (Ist-LHM)": "Wie viele davon schon drauf stehen.",
    "Frei (LHM)": "Wie viele noch reinpassen. Danach ist die Liste sortiert "
                  "(größte Lücke zuerst).",
    "Auslastung %": "Wie voll der Platz ist. 0 % = ganz leer, unter 100 % = noch "
                    "Platz.",
    "Sperrgrund (Kennz.)": "Warum der Platz gesperrt ist (z. B. Inventur oder "
                           "Defekt). Ist er gesetzt, hier nicht einlagern.",
}

# Gesperrt-Liste: Kapazitaet/Frei sind hier irrelevant (egal ob frei, der Platz
# darf nicht bestueckt werden). Stattdessen zeigt diese Liste den SPERRGRUND.
_PUTAWAY_BLOCKED_COLS = [
    "PLATZ_ID", "REGAL", "FACH", "EBENE", "ABC_KLASSE", "SPERR_KNZ",
]
_PUTAWAY_BLOCKED_RENAME = {
    "PLATZ_ID": "Platz",
    "REGAL": "Regal",
    "FACH": "Fach",
    "EBENE": "Ebene",
    "ABC_KLASSE": "ABC (Platz)",
    "SPERR_KNZ": "Sperrgrund (Kennz.)",
}

# Schlanke Spalten fuer den Nachschub-Tab: jeder Platz ist hier per Definition
# GANZ leer (IST_LHM = 0), darum ist IST_LHM (immer 0) keine Entscheidungshilfe.
# Relevant ist: Ort, Platz-Guete (ABC), Pickhaeufigkeit (Dringlichkeit) und wie
# voll der Platz sein SOLL (MAX_LHM).
_REPLEN_COLS = [
    "PLATZ_ID", "REGAL", "FACH", "EBENE",
    "ABC_KLASSE", "ANZ_PICKS", "MAX_LHM",
]

# Sprechende Spaltenkoepfe fuer die Nachschub-Tabellen (technisch -> Klartext).
_REPLEN_RENAME = {
    "PLATZ_ID": "Platz",
    "REGAL": "Regal",
    "FACH": "Fach",
    "EBENE": "Ebene",
    "ABC_KLASSE": "ABC (Platz)",
    "ANZ_PICKS": "Picks (Häufigkeit)",
    "MAX_LHM": "Soll-LHM",
    "DAYS_EMPTY": "Tage leer",
    "DAYS_SINCE_PICK": "Tage seit letztem Pick",
}

# Hilfetexte je (umbenannter) Spalte – als ℹ️ am Tabellenkopf (col_help).
_REPLEN_HELP = {
    "Platz": "Die eindeutige Nummer des Lagerplatzes.",
    "Regal": "Regalnummer im Lager.",
    "Fach": "Fach innerhalb des Regals.",
    "Ebene": "Wie hoch der Platz liegt – niedrig heißt Pickzone mit kurzen "
             "Greifwegen.",
    "ABC (Platz)": "Die Güteklasse des Ortes aus dem Lagersystem (A = bester "
                   "Platz). Beschreibt den Platz, nicht den Artikel, und wird hier "
                   "nicht aus den Picks berechnet.",
    "Picks (Häufigkeit)": "Wie oft an diesem Platz gepickt wird. Je mehr, desto "
                          "dringender der Nachschub.",
    "Soll-LHM": "Auf so viele Paletten/Behälter sollte der Platz aufgefüllt "
                "werden.",
    "Tage leer": "Wie lange der Platz schon ohne Ware ist. Bei manchen Plätzen "
                 "nicht bekannt.",
    "Tage seit letztem Pick": "Wie lange hier nichts mehr entnommen wurde. "
                              "Kürzlich gepickt und trotzdem leer heißt: Nachschub "
                              "vergessen. Lange kein Pick: vielleicht ein totes Fach.",
    "Vorschlag": "Die empfohlene Handlung: wie dringend kommt aus der Liste, die "
                 "Menge ist das Soll (Platz ist leer, also auffüllen).",
}


def render_massnahme_kategorie(titel: str, beschreibung: str, df: pd.DataFrame,
                               extra_cols: list[str] | None = None,
                               vorschlag: str | None = None,
                               cols: list[str] | None = None,
                               rename: dict[str, str] | None = None,
                               rowhint: str | None = None,
                               col_help: dict[str, str] | None = None,
                               formel_keys: list[str] | None = None) -> None:
    """Rendert eine Massnahmen-Kategorie einheitlich (Titel + Tabelle + CSV).

    `vorschlag`: optionaler Text, der als zusaetzliche Spalte "Vorschlag"
    (konkrete Handlungsempfehlung) in jede Zeile geschrieben wird.
    `cols`: ersetzt die Standard-Spalten (_MASSNAHME_COLS) durch eine
    tab-spezifische Liste (z. B. Einlagern ohne sinnlose Pick-Spalten).
    `rename`: optionale Zuordnung technischer Spaltennamen -> sprechende
    Anzeige-Namen (z. B. ANZ_PICKS -> "Picks"); wirkt auf Tabelle UND CSV.
    `rowhint`: ueberschreibt den Standard-Zeilenhinweis (z. B. Einlagern zeigt
    FREIE Plaetze, nicht belegte) – sonst gilt massn_rowhint.
    `col_help`: Anzeige-Spaltenname -> Hilfetext; gibt jeder Spaltenueberschrift
    ein ℹ️ zum Hovern (beantwortet "was bedeutet diese Spalte?" direkt am Kopf).

    Anzeige ist auf 200 Zeilen begrenzt (Performance), der CSV-Download enthaelt
    jedoch ALLE Treffer.
    """
    base = cols if cols is not None else _MASSNAHME_COLS
    cols = base + (extra_cols or [])
    cols = [c for c in cols if c in df.columns]
    # Default-Klartextspalten + Tooltips, wenn der Aufrufer nichts uebergibt
    # (Umlagern/Auslagern nutzen die Standardspalten -> ABC/Kapazitaet lesbar).
    if rename is None:
        rename = _MASSNAHME_RENAME
    if col_help is None:
        col_help = _MASSNAHME_HELP
    st.markdown(f"**{titel}** — {beschreibung}")
    st.metric(t("cat_slots"), de_num(len(df)))
    st.caption(rowhint or t("massn_rowhint"))
    if df.empty:
        st.info(t("cat_empty"))
    else:
        show = df[cols].copy()
        # Auslastung lesbar runden (sonst 33.33333…); nur wenn die Spalte
        # ueberhaupt mitgefuehrt wird (aktuell nur Einlagern).
        if "UTILIZATION" in show.columns:
            show["UTILIZATION"] = show["UTILIZATION"].round(1)
        if rename:
            show = show.rename(columns=rename)
        if vorschlag:
            show[t("col_vorschlag")] = vorschlag
        col_cfg = None
        if col_help:
            col_cfg = {
                c: st.column_config.Column(help=h)
                for c, h in col_help.items() if c in show.columns
            }
        st.dataframe(
            show.head(200), use_container_width=True, hide_index=True,
            column_config=col_cfg,
        )
        key = "".join(c if c.isalnum() else "_" for c in titel.lower())
        # CSV-Download; optional direkt daneben ein ℹ️-Button mit der/den
        # Formel(n) zu berechneten Spalten dieser Liste (z. B. berechnete ABC).
        if formel_keys:
            dl_col, info_col, _sp = st.columns([2, 2, 6])
            with dl_col:
                _csv_download(show, f"massnahme_{key}")
            with info_col:
                render_formel_popover(formel_keys)
        else:
            _csv_download(show, f"massnahme_{key}")
    st.divider()


def render_uebersicht(filtered: pd.DataFrame) -> None:
    """Tab 'Übersicht': Belegung/Auslastung/ABC fuer das gesamte Lager."""
    st.markdown(t("halls_intro"))
    # Zentrale Legende: beantwortet die generellen Begriffe (belegt/leer/
    # Auslastung/Pick/ABC) EINMAL fuer alle Tabs (Lehrer-Feedback).
    with st.expander(t("halls_info_t")):
        st.markdown(t("halls_info_b"))
    # Eine Halle: das gesamte (gefilterte) Lager als EIN Block zusammenfassen.
    # Kein Regal->Halle-Split mehr; HALLE ist hier nur ein konstantes Label.
    df_h = filtered.assign(HALLE="Lager BER03")
    zones = (
        df_h.groupby("HALLE")
        .agg(
            total_slots=("PLATZ_ID", "count"),
            occupied=("BELEGT", "sum"),
            avg_util=("UTILIZATION", "mean"),
            picks=("ANZ_PICKS", "sum"),
        )
        .reset_index()
    )
    zones["frei"] = zones["total_slots"] - zones["occupied"]
    zones["Belegung_%"] = (zones["occupied"] / zones["total_slots"] * 100).round(1)
    zones["Ø_Auslastung_%"] = zones["avg_util"].round(1)
    abc_pivot = (
        df_h.pivot_table(
            index="HALLE", columns="ABC_CALC", values="PLATZ_ID",
            aggfunc="count", fill_value=0,
        )
        .reindex(columns=["A", "B", "C"], fill_value=0)
        .reset_index()
        .rename(columns={"A": "A-Plätze", "B": "B-Plätze", "C": "C-Plätze"})
    )
    zones = zones.merge(abc_pivot, on="HALLE", how="left")

    # Drei Zustaende statt nur Belegt/Frei, damit "frei" nicht ueberschaetzt
    # wird (User-Feedback: man denkt sonst, die sind immer/dauerhaft frei):
    #   - voll        = belegt, keine Restkapazitaet
    #   - noch Platz  = belegt, aber es passt noch etwas drauf
    #   - aktuell leer= gerade gar nichts drauf (Momentaufnahme, kann jederzeit
    #                   wieder belegt werden)
    s_full, s_part, s_empty = (
        t("halls_state_full"), t("halls_state_partial"), t("halls_state_empty"),
    )
    belegt = df_h["BELEGT"].astype(bool)
    df_h["_state"] = np.select(
        [~belegt, df_h["FREE_CAPACITY"].gt(0)],
        [s_empty, s_part],
        default=s_full,
    )
    state_counts = (
        df_h.groupby(["HALLE", "_state"]).size().rename("Plaetze").reset_index()
    )
    # Voll/Teilbelegt je Halle fuer die Kennzahlen-Tabelle (voll + noch Platz +
    # leer = alle Plaetze, konsistent zum Diagramm und zur KPI-Kachel oben).
    state_pivot = (
        state_counts.pivot(index="HALLE", columns="_state", values="Plaetze")
        .reindex(columns=[s_full, s_part], fill_value=0)
        .reset_index()
        .rename(columns={s_full: "voll", s_part: "teil"})
    )
    zones = zones.merge(state_pivot, on="HALLE", how="left")
    fig = px.bar(
        state_counts,
        x="HALLE", y="Plaetze", color="_state", barmode="stack",
        category_orders={"_state": [s_full, s_part, s_empty]},
        color_discrete_map={
            s_full: "#ef6c00", s_part: "#ffb74d", s_empty: "#bdbdbd",
        },
        labels={"_state": t("halls_state_legend")},
        title=t("halls_chart"),
        text="Plaetze",
    )
    fig.update_traces(textposition="inside", textfont_size=13)
    st.plotly_chart(fig, use_container_width=True)
    st.caption(t("halls_free_now_note"))

    st.markdown(t("halls_kpis"))
    show = zones[[
        "HALLE", "total_slots", "voll", "teil", "frei", "Belegung_%",
        "Ø_Auslastung_%", "picks", "A-Plätze", "B-Plätze", "C-Plätze",
    ]].rename(columns={
        "HALLE": "Lager", "total_slots": "Plätze",
        "voll": "Voll belegt", "teil": "Belegt – noch Platz",
        "frei": "Aktuell leer", "Belegung_%": "Belegung %",
        "Ø_Auslastung_%": "Ø Auslastung %", "picks": "Picks gesamt",
    })
    halls_help = {
        "Plätze": "Anzahl Stellplätze im (gefilterten) Lager.",
        "Voll belegt": "Plätze, die belegt sind und keine Restkapazität mehr "
                       "haben – da passt nichts mehr drauf.",
        "Belegt – noch Platz": "Plätze, auf denen schon Ware steht, aber noch "
                               "etwas draufpasst (teilweise gefüllt).",
        "Aktuell leer": "Plätze, auf denen gerade gar nichts steht – eine "
                        "Momentaufnahme aus den Daten. Das ist keine dauerhaft "
                        "freie Reserve: jeder dieser Plätze kann jederzeit wieder "
                        "belegt werden.",
        "Belegung %": "Anteil der belegten Plätze.",
        "Ø Auslastung %": "Wie voll die Plätze im Schnitt sind.",
        "Picks gesamt": "Alle Zugriffe im gefilterten Lager zusammen.",
        "A-Plätze": "Plätze mit berechneter Klasse A (viel gepickt).",
        "B-Plätze": "Plätze mit berechneter Klasse B.",
        "C-Plätze": "Plätze mit berechneter Klasse C (wenig oder gar nicht gepickt).",
    }
    col_cfg = {c: st.column_config.Column(help=h)
               for c, h in halls_help.items() if c in show.columns}
    st.dataframe(show, use_container_width=True, hide_index=True,
                 column_config=col_cfg)
    _csv_download(show, "lager_kennzahlen")


def render_pickheat(tpa: pd.DataFrame, movements_filtered: bool,
                    filtered: pd.DataFrame) -> None:
    """Unter-Tab 'Pick-Heatmap': Picks je Wochentag/Stunde aus TPA."""
    st.markdown(t("pick_intro"))
    # Was bedeutet das? — was ist ein Pick, was heisst "Picks je Quellplatz",
    # wozu die Heatmap (Lehrer-Feedback).
    with st.expander(t("pick_info_t")):
        st.markdown(t("pick_info_b"))
    mov_filter_note(movements_filtered, filtered)
    st.caption(t("weekend_hidden"))
    ph = agg_pick_heatmap(tpa)
    if ph.empty:
        st.info(t("no_data_filters"))
    else:
        weekday_names = {
            1: "Mo", 2: "Di", 3: "Mi", 4: "Do", 5: "Fr",
        }
        ph = ph[(ph["weekday"].between(0, 6)) & (ph["hour"].between(0, 23))]
        # Wochenende IMMER ausblenden (Sa=6, So=0) -> klares Mo-Fr-Bild.
        ph = ph[~ph["weekday"].isin([0, 6])]
        day_order = range(1, 6)
        pivot = (
            ph.pivot_table(
                index="weekday", columns="hour", values="picks", aggfunc="sum"
            )
            .reindex(day_order)
            .reindex(columns=range(24))
        )
        pivot.index = [weekday_names[i] for i in pivot.index]
        fig = px.imshow(
            pivot,
            color_continuous_scale="YlOrRd",
            aspect="auto",
            labels=dict(x="Stunde", y="Wochentag", color="Picks"),
            title=t("pick_chart"),
        )
        st.plotly_chart(fig, use_container_width=True)
        busiest = ph.sort_values("picks", ascending=False).head(1)
        if not busiest.empty:
            row = busiest.iloc[0]
            st.caption(
                t("pick_peak").format(
                    wd=weekday_names[int(row["weekday"])],
                    h=int(row["hour"]),
                    p=de_num(int(row['picks'])),
                )
            )

        c1, c2 = st.columns(2)
        with c1:
            per_wd = (
                ph.groupby("weekday")["picks"].sum()
                .reindex(range(1, 6), fill_value=0)
            )
            per_wd.index = [weekday_names[i] for i in per_wd.index]
            st.plotly_chart(
                px.bar(per_wd, title=t("pick_by_wd"),
                       labels=dict(value=t("picks_label"), index=t("wd_label"))),
                use_container_width=True,
            )
        with c2:
            per_hour = (
                ph.groupby("hour")["picks"].sum().reindex(range(24), fill_value=0)
            )
            st.plotly_chart(
                px.bar(per_hour, title=t("pick_by_hour"),
                       labels=dict(value=t("picks_label"), index=t("hour_label"))),
                use_container_width=True,
            )
        tbl = ph.copy()
        tbl["weekday"] = tbl["weekday"].map(weekday_names)
        tbl = tbl.rename(columns={"weekday": "Wochentag", "hour": "Stunde",
                                  "picks": "Picks"})
        _csv_download(tbl[["Wochentag", "Stunde", "Picks"]], "pick_heatmap")


# Hochfrequenz-Tabelle: technische -> sprechende Spalten + Tooltips.
_HF_RENAME = {
    "PLATZ_ID": "Platz", "REGAL": "Regal", "FACH": "Fach", "EBENE": "Ebene",
    "ANZ_PICKS": "Picks (Stamm)", "PICK_TOTAL": "Picks gesamt",
    "MAX_LHM": "Kapazität (max. LHM)", "IST_LHM": "Belegt (Ist-LHM)",
    "UTILIZATION": "Auslastung %",
}
_HF_HELP = {
    "Platz": "Die eindeutige Nummer des Lagerplatzes.",
    "Regal": "Regalnummer im Lager.",
    "Fach": "Fach innerhalb des Regals.",
    "Ebene": "Wie hoch der Platz liegt.",
    "Picks (Stamm)": "Die im Lagersystem hinterlegte Zugriffshäufigkeit dieses "
                     "Platzes.",
    "Picks gesamt": "Stamm-Picks plus die tatsächlichen Anfahrten aus den "
                    "Bewegungsdaten. Gleich wie „Picks (Stamm)“ heißt: keine "
                    "zusätzlichen Anfahrten (kein Fehler).",
    "Kapazität (max. LHM)": "Wie viele Paletten/Behälter auf den Platz passen "
                            "(kann auch mehr als einer sein).",
    "Belegt (Ist-LHM)": "Wie viele davon aktuell drauf stehen.",
    "Auslastung %": "Wie voll der Platz ist. 0 % = oft angefahren, aber gerade "
                    "leer (Nachschub nötig); 100 % = voll.",
}


def render_high_frequency_slots(filtered: pd.DataFrame) -> None:
    """Unter-Tab 'Hochfrequenz-Plaetze': Plaetze mit hoher Pick-Frequenz."""
    st.markdown(t("bottle_intro"))
    with st.expander(t("bottle_info_t")):
        st.markdown(t("bottle_info_b"))
    # Voller, sortierter Satz fuer den Export; Anzeige auf Top 50 begrenzt.
    high_freq_full = (
        filtered.assign(
            PICK_TOTAL=lambda d: d["ANZ_PICKS"] + d["PICK_COUNT_FAHR"]
        )
        .sort_values(["PICK_TOTAL", "UTILIZATION"], ascending=[False, False])[
            ["PLATZ_ID", "REGAL", "FACH", "EBENE",
             "ANZ_PICKS", "PICK_TOTAL", "MAX_LHM", "IST_LHM", "UTILIZATION"]
        ].copy()
    )
    high_freq_full["UTILIZATION"] = high_freq_full["UTILIZATION"].round(1)
    high_freq_full = high_freq_full.rename(columns=_HF_RENAME)
    if high_freq_full.empty:
        st.info(t("no_data_filters"))
    else:
        col_cfg = {c: st.column_config.Column(help=h)
                   for c, h in _HF_HELP.items() if c in high_freq_full.columns}
        st.dataframe(high_freq_full.head(50), use_container_width=True,
                     hide_index=True, column_config=col_cfg)
        _csv_download(high_freq_full, "hochfrequenz_plaetze")


def render_free(filtered: pd.DataFrame) -> None:
    """Unter-Tab 'Free Capacity': Plaetze mit Restkapazitaet."""
    st.markdown(t("free_intro"))
    with st.expander(t("free_info_t")):
        st.markdown(t("free_info_b"))
    free_all = filtered[filtered["FREE_CAPACITY"] > 0]
    c1, c2, c3 = st.columns(3)
    c1.metric(t("free_count"), de_num(len(free_all)))
    c2.metric(t("free_total"),
              de_num(int(free_all['FREE_CAPACITY'].sum())))
    c3.metric(t("free_avg"),
              f"{free_all['FREE_CAPACITY'].mean():.1f}"
              if not free_all.empty else "—")

    # Voller, sortierter Satz fuer den Export; Anzeige auf Top 100 begrenzt.
    free_full = (
        free_all.sort_values("FREE_CAPACITY", ascending=False)[
            ["PLATZ_ID", "REGAL", "FACH", "EBENE",
             "MAX_LHM", "IST_LHM", "FREE_CAPACITY", "UTILIZATION"]
        ].copy()
    )
    free_full["UTILIZATION"] = free_full["UTILIZATION"].round(1)
    free_full = free_full.rename(columns=_PUTAWAY_RENAME)
    col_cfg = {c: st.column_config.Column(help=h)
               for c, h in _PUTAWAY_HELP.items() if c in free_full.columns}
    st.dataframe(free_full.head(100), use_container_width=True,
                 hide_index=True, column_config=col_cfg)
    _csv_download(free_full, "free_capacity")


def render_umlagern_auslagern(filtered: pd.DataFrame) -> None:
    """Tab 'Um-/Auslagern': EIN Diagnose-Modell 'richtige Ware auf richtigem
    Platz', verschmolzen aus den frueheren getrennten render_umlagern() und
    render_auslagern(). Zwei Absichten mit ueberschneidungsfreien Kategorien:
      - Platz freimachen (auslagern): belegte Plaetze, deren Ware kaum bewegt;
      - besser platzieren (umlagern): Schnelldreher auf schlechtem Platz.
    Der frueher DOPPELTE Fall 'A-Platz mit 0 Picks' (steckte sowohl in
    'Premium ungenutzt' als auch in 'Kritisch') liegt jetzt nur noch in
    'Premiumplatz blockiert'. Leere A-Plaetze entfallen ganz (kein Inhalt ->
    nichts um-/auszulagern)."""
    st.markdown(t("ua_head"))
    with st.expander(t("ua_info_t")):
        st.markdown(t("ua_info_b"))

    # Gemeinsame Regler statt zwei getrennter Bloecke. Die Pickzonen-Ebene
    # steuert sowohl die "blockiert"-Pruefung als auch die Trennung der freien
    # Zielplaetze in unten (Pickzone) / oben (Reserve).
    c1, c2 = st.columns(2)
    with c1:
        pick_zone = st.slider(t("sl_retrzone"), 1, 6, 2, key="ua_zone",
                              help=t("sl_retrzone_h"))
    with c2:
        high_level = st.slider(t("sl_highlevel"), 2, 6, 4, key="ua_high",
                               help=t("sl_highlevel_h"))

    notgesperrt = ~filtered["GESPERRT"]
    # Gruppe 1: Premiumplatz blockiert – A-Platz, belegt, 0 Picks, in der
    # Pickzone, nicht gesperrt (Ladenhueter sitzt auf einem Premiumplatz).
    critical = filtered[
        filtered["BELEGT"] & (filtered["EBENE"] <= pick_zone) & notgesperrt
        & (filtered["ABC_KLASSE"] == "A") & (filtered["ANZ_PICKS"] == 0)
    ].sort_values(["REGAL", "EBENE", "FACH"])

    # Gruppe 2: Schnelldreher auf schlechtem Platz (ueber das ganze Lager).
    # Heisser C-Platz: als C gefuehrt, aber nach den tatsaechlichen Picks
    # rechnerisch A oder B (ABC_CALC). Diese Fehlklassifikation IST das Signal -
    # kein willkuerlicher Pick-Schwellen-Regler mehr noetig.
    hot_c = filtered[
        (filtered["ABC_KLASSE"] == "C")
        & (filtered["ABC_CALC"].isin(["A", "B"]))
        & notgesperrt
    ].sort_values("ANZ_PICKS", ascending=False)
    # A-Ware zu hoch: A-Klasse, aktiv, weit oben -> Ware ergonomisch auf einen
    # freien Platz weiter unten umlagern (Platz bleibt, nur Inhalt zieht um).
    # BELEGT ist Pflicht: ANZ_PICKS>0 zaehlt HISTORISCHE Picks (6 Mon) - ein Platz
    # kann viel gepickt worden, inzwischen aber leer sein. Ohne BELEGT landen leere
    # A-Plaetze in der Liste (~3/4 der Treffer), obwohl es da nichts umzulagern gibt
    # - genau der Fall, den der Info-Text ausschliesst.
    # WICHTIG: EBENE ist KEIN sauberer 1-6-Level. Das Feld enthaelt codierte
    # Cluster (0-6 = echte Ebenen, 10-13 = eigener Block mit ~2200 Plaetzen,
    # 14-24 Ausreisser). Die "zu hoch"-Logik gilt nur fuer die echten
    # physischen Ebenen (<=6) - sonst landen ~1600 codierte "Ebene 10"-Plaetze
    # faelschlich in der Liste.
    high_a = filtered[
        (filtered["ABC_KLASSE"] == "A")
        & (filtered["EBENE"] >= high_level)
        & (filtered["EBENE"] <= 6)
        & (filtered["ANZ_PICKS"] > 0)
        & filtered["BELEGT"]
        & notgesperrt
    ].sort_values("ANZ_PICKS", ascending=False)

    # Zielplatz-Pool: freie, nicht gesperrte Plaetze. Unten (<= Pickzone) sind
    # gute Pickplaetze (Ziel fuer heisse/zu hohe Ware), oben (> Pickzone) ist
    # Reserve (Ziel fuer Ladenhueter vom Premiumplatz).
    free_pool = filtered[(filtered["FREE_CAPACITY"] > 0) & notgesperrt]
    free_low = free_pool[free_pool["EBENE"] <= pick_zone] \
        .sort_values("FREE_CAPACITY", ascending=False)
    free_high = free_pool[free_pool["EBENE"] > pick_zone] \
        .sort_values("FREE_CAPACITY", ascending=False)

    def _add_ziel(src: pd.DataFrame, targets: pd.DataFrame) -> pd.DataFrame:
        """Greedy 1:1 – jedem Quellplatz genau einen freien Zielplatz (nach
        freier Kapazitaet) zuordnen; Quellplaetze selbst sind nie Ziel."""
        tgt = targets[~targets["PLATZ_ID"].isin(src["PLATZ_ID"])]
        labels = [
            f"{r.PLATZ_ID} · R{int(r.REGAL)}/E{int(r.EBENE)} "
            f"(frei {int(r.FREE_CAPACITY)})"
            for r in tgt.itertuples(index=False)
        ]
        col = [labels[i] if i < len(labels) else t("ziel_none")
               for i in range(len(src))]
        return src.assign(**{t("col_ziel"): col})

    def _hotc_vorschlag(df: pd.DataFrame) -> list:
        """Konkrete Ziel-Klasse je heissem C-Platz statt nur 'hochstufen': die
        berechnete ABC-Klasse (ABC_CALC) aus der tatsaechlichen Pick-Haeufigkeit,
        mit Picks als Begruendung. ABC_CALC ist hier per Filter immer A oder B."""
        return [
            t("reloc_hotC_v_to").format(
                cls=str(getattr(r, "ABC_CALC", "") or "").upper(),
                picks=de_num(int(getattr(r, "ANZ_PICKS", 0))))
            for r in df.itertuples(index=False)
        ]

    # KPI-Zeile: Zusammenfassung nach Absicht (statt der Zahlen erst weit unten).
    k1, k2 = st.columns(2)
    k1.metric(t("ua_kpi_free"), de_num(len(critical)),
              help=t("ua_kpi_free_h"))
    k2.metric(t("ua_kpi_place"), de_num(len(hot_c) + len(high_a)),
              help=t("ua_kpi_place_h"))

    # --- Gruppe 1: Platz freimachen (auslagern) ---
    st.markdown(t("ua_group_free"))
    render_massnahme_kategorie(
        t("ua_crit_t"), t("ua_crit_d"),
        _add_ziel(critical, free_high),
        # ABC-Spalte weglassen: per Filter ist jede Zeile "A" -> redundant.
        cols=[c for c in _MASSNAHME_COLS if c != "ABC_KLASSE"],
        extra_cols=[t("col_ziel")], vorschlag=t("ua_crit_v"))

    # --- Gruppe 2: besser platzieren (umlagern) ---
    st.markdown(t("ua_group_place"))
    render_massnahme_kategorie(
        t("reloc_hotC_t"), t("reloc_hotC_d"),
        _add_ziel(hot_c, free_low),
        # ABC-Spalte weglassen: per Filter immer "C"; das C->A/B-Hochstufen steht
        # ohnehin im Titel und in der Vorschlag-Spalte.
        cols=[c for c in _MASSNAHME_COLS if c != "ABC_KLASSE"],
        extra_cols=[t("col_ziel")], vorschlag=_hotc_vorschlag(hot_c),
        formel_keys=["abc_calc"])
    render_massnahme_kategorie(
        t("reloc_highA_t"), t("reloc_highA_d"),
        _add_ziel(high_a, free_low),
        # ABC-Spalte hier weglassen: per Filter ist jede Zeile "A" -> redundant.
        cols=[c for c in _MASSNAHME_COLS if c != "ABC_KLASSE"],
        extra_cols=[t("col_ziel")], vorschlag=t("reloc_highA_v"))


def _replen_vorschlag_col(df: pd.DataFrame, kind: str) -> pd.DataFrame:
    """Fuegt eine ABGELEITETE Vorschlag-Spalte hinzu (1 Zeile = 1 konkrete
    Handlung). Die Empfehlung ist nicht fix, sondern entsteht aus:
      - der Listenregel (kind: overdue/medium) -> Dringlichkeit/Wortlaut,
      - x = Soll-LHM (MAX_LHM; Platz ist leer -> auf Soll auffuellen),
      - bei 'overdue' zusaetzlich d = Tage seit letztem Pick (DAYS_SINCE_PICK).
    So ist im Tab nachvollziehbar, WIE der Vorschlag zustande kommt."""
    out = df.copy()
    lhm = (pd.to_numeric(out["MAX_LHM"], errors="coerce")
           .fillna(0).astype(int).clip(lower=1))
    if kind == "overdue":
        days = (pd.to_numeric(out["DAYS_SINCE_PICK"], errors="coerce")
                .fillna(0).astype(int))
        tmpl = t("replen_overdue_v")
        col = [tmpl.format(x=x, d=d) for x, d in zip(lhm, days)]
    else:
        tmpl = t("replen_medium_v")
        col = [tmpl.format(x=x) for x in lhm]
    out[t("col_vorschlag")] = col
    return out


def render_nachschub(filtered: pd.DataFrame) -> None:
    """Tab 'Nachschub': leere Pickplaetze nach Dringlichkeit."""
    st.markdown(t("replen_head"))
    # WARUM dieser Tab existiert + Eskalations-Logik der drei Listen.
    st.caption(t("replen_principle"))
    # Kurz-Glossar: beantwortet "was heisst leer / was zaehlt als Pick / Spalten".
    with st.expander(t("replen_glossary_t")):
        st.markdown(t("replen_glossary_b"))
    c1, c2, c3, c4 = st.columns(4)
    with c1:
        pick_level = st.slider(t("sl_picklevel"), 1, 6, 2,
                               help=t("sl_picklevel_h"))
    with c2:
        active_days = st.slider(t("sl_active"), 7, 365, 90, step=7,
                                help=t("sl_active_h"))
    with c3:
        pick_threshold = st.slider(t("sl_pickthresh"), 10, 300, 50, step=10,
                                   help=t("sl_pickthresh_h"))
    with c4:
        overdue_days = st.slider(t("sl_overdue"), 3, 60, 14,
                                 help=t("sl_overdue_h"))

    # Basis: leere Pickplaetze (IST_LHM=0) in der Pickzone (niedrige Ebene),
    # nicht gesperrt.
    empty_pick = filtered[
        (filtered["IST_LHM"].fillna(0) == 0)
        & (filtered["EBENE"] <= pick_level)
        & (~filtered["GESPERRT"])
    ]
    # AKTIV-Filter: nur Plaetze, an denen zuletzt innerhalb `active_days` gepickt
    # wurde. Trennt echte Nachfuell-Kandidaten von toten Faechern (hohe HISTORISCHE
    # Picks, aber seit Monaten leer & kein Zugriff). NaN (kein Zugriffsdatum) zaehlt
    # als inaktiv. Ausgeblendete Anzahl wird transparent gemeldet (kein stilles Cap).
    is_active = empty_pick["DAYS_SINCE_PICK"].fillna(10**9) <= active_days
    inactive_n = int((~is_active).sum())
    active_pick = empty_pick[is_active]
    if inactive_n:
        st.warning(t("replen_inactive_note").format(n=de_num(inactive_n),
                                                     d=active_days))
    empty_pick = active_pick
    # Wichtige (hochfrequente) leere Plaetze. DAYS_EMPTY taugt hier NICHT zur
    # Trennung (Leer-Datum oft Jahre alt), DAYS_SINCE_PICK schon:
    #   ueberfaellig = wichtig + schon LAENGER ohne Pick (> Schwelle) -> vernachlaessigt
    important = empty_pick[empty_pick["ANZ_PICKS"] >= pick_threshold]
    days_since = important["DAYS_SINCE_PICK"].fillna(10**9)
    overdue = important[days_since > overdue_days] \
        .sort_values("DAYS_SINCE_PICK", ascending=False)
    # mittlere Frequenz = aktiv leer mit Picks unterhalb der Dringend-Schwelle (>0)
    medium = empty_pick[
        (empty_pick["ANZ_PICKS"] > 0)
        & (empty_pick["ANZ_PICKS"] < pick_threshold)
    ].sort_values("ANZ_PICKS", ascending=False)

    # Spaltenende je Liste: EIN Staleness-Wert (Tage seit letztem Pick – das
    # genutzte, verlaessliche Signal; "Tage leer" waere doppelt + unzuverlaessig)
    # + abgeleiteter Vorschlag.
    replen_extra = ["DAYS_SINCE_PICK", t("col_vorschlag")]
    render_massnahme_kategorie(
        t("replen_overdue_t"),
        t("replen_overdue_d").format(n=overdue_days),
        _replen_vorschlag_col(overdue, "overdue"),
        cols=_REPLEN_COLS, extra_cols=replen_extra,
        rename=_REPLEN_RENAME, col_help=_REPLEN_HELP)
    render_massnahme_kategorie(
        t("replen_medium_t"), t("replen_medium_d"),
        _replen_vorschlag_col(medium, "medium"),
        cols=_REPLEN_COLS, extra_cols=replen_extra,
        rename=_REPLEN_RENAME, col_help=_REPLEN_HELP)


def _putaway_vorschlag_col(df: pd.DataFrame, kind: str) -> pd.DataFrame:
    """Abgeleitete Vorschlag-Spalte (1 Zeile = 1 konkrete Handlung).
    'fast'/'reserve': x = freie Kapazitaet der Zeile (so viele LHM passen rein).
    'blocked': fixer Hinweis (Platz ist gesperrt)."""
    out = df.copy()
    if kind == "blocked":
        out[t("col_vorschlag")] = t("put_blocked_v")
        return out
    frei = (pd.to_numeric(out["FREE_CAPACITY"], errors="coerce")
            .fillna(0).astype(int).clip(lower=1))
    tmpl = t("put_fast_v") if kind == "fast" else t("put_reserve_v")
    out[t("col_vorschlag")] = [tmpl.format(x=x) for x in frei]
    return out


def render_einlagern(filtered: pd.DataFrame) -> None:
    """Tab 'Einlagern': wohin eingehende Ware (freie A-Plaetze + Reserve)."""
    st.markdown(t("put_head"))
    # Klare, gestapelte Reihenfolge (Lehrer-Feedback "uebersichtlicher"):
    # 1) WAS BEDEUTET DAS? — Prinzip (Warum) + Spalten-Glossar, eingeklappt,
    #    damit oben kein Textblock dauerhaft zustellt.
    with st.expander(t("put_info_t")):
        st.markdown(t("put_principle"))
        st.markdown(t("put_twocrit"))
        st.markdown(t("put_cols_head"))
        st.markdown(t("put_glossary_b"))
    # 2) WIE ENTSTEHT DER VORSCHLAG? Die Kategorie-Filterregel IST die Empfehlung.
    #    Steht VOR den Reglern -> Text generisch (verweist auf die Regler unten),
    #    keine Live-Reglerwerte (die gibt es hier noch nicht).
    with st.expander(t("put_logic_t")):
        st.markdown(t("put_logic_b"))
    # 3) SCHIEBEREGLER
    c1, c2 = st.columns(2)
    with c1:
        fast_level = st.slider(t("sl_fastlevel"), 1, 6, 2,
                               help=t("sl_fastlevel_h"))
    with c2:
        reserve_level = st.slider(t("sl_reservelevel"), 1, 6, 3,
                                  help=t("sl_reservelevel_h"))

    # Freie Plaetze = Restkapazitaet > 0. Nutzbar = nicht gesperrt.
    free_slots = filtered[filtered["FREE_CAPACITY"] > 0]
    free_usable = free_slots[~free_slots["GESPERRT"]]

    # Schnelldreher-Plaetze: freie A-Plaetze auf niedriger Ebene -> kurze Wege.
    fast_lane = free_usable[
        (free_usable["ABC_KLASSE"] == "A")
        & (free_usable["EBENE"] <= fast_level)
    ].sort_values("FREE_CAPACITY", ascending=False)

    # Reserve fuer Langsamdreher / Nicht-A: freie Nicht-A-Plaetze hoeher oben.
    reserve = free_usable[
        (free_usable["ABC_KLASSE"] != "A")
        & (free_usable["EBENE"] >= reserve_level)
    ].sort_values("FREE_CAPACITY", ascending=False)

    # Gesperrt: nur Plaetze, die FREI waeren, aber gesperrt sind (waeren sonst
    # Einlager-Ziele). Voll belegte Sperrplaetze sind hier irrelevant -> raus.
    blocked = free_slots[free_slots["GESPERRT"]].sort_values(
        ["REGAL", "EBENE", "FACH"])

    # Ueberblick: wie viel freier Platz ueberhaupt (gesamt + je Kategorie)?
    st.markdown(t("put_overview"))
    k1, k2, k3, k4 = st.columns(4)
    k1.metric(t("put_kpi_free"), de_num(len(free_usable)))
    k2.metric(t("put_fast_t"), de_num(len(fast_lane)))
    k3.metric(t("put_reserve_t"), de_num(len(reserve)))
    k4.metric(t("put_kpi_blocked"), de_num(len(blocked)))
    st.caption(t("put_kpi_capacity").format(
        n=de_num(int(free_usable["FREE_CAPACITY"].fillna(0).sum()))))
    st.divider()

    put_extra = [t("col_vorschlag")]
    render_massnahme_kategorie(
        t("put_fast_t"), t("put_fast_d").format(n=fast_level),
        _putaway_vorschlag_col(fast_lane, "fast"),
        cols=_PUTAWAY_COLS, extra_cols=put_extra, rename=_PUTAWAY_RENAME,
        rowhint=t("put_rowhint"), col_help=_PUTAWAY_HELP)
    render_massnahme_kategorie(
        t("put_reserve_t"), t("put_reserve_d").format(n=reserve_level),
        _putaway_vorschlag_col(reserve, "reserve"),
        cols=_PUTAWAY_COLS, extra_cols=put_extra, rename=_PUTAWAY_RENAME,
        rowhint=t("put_rowhint"), col_help=_PUTAWAY_HELP)
    render_massnahme_kategorie(
        t("put_blocked_t"), t("put_blocked_d"),
        _putaway_vorschlag_col(blocked, "blocked"),
        cols=_PUTAWAY_BLOCKED_COLS, extra_cols=put_extra,
        rename=_PUTAWAY_BLOCKED_RENAME,
        rowhint=t("put_blocked_rowhint"), col_help=_PUTAWAY_HELP)


def render_abc(filtered: pd.DataFrame, tpa: pd.DataFrame,
               movements_filtered: bool) -> None:
    """Tab 'ABC-Analyse': Verteilung, Stamm-vs-berechnet, Anpassungs-Tipps."""
    # Einheitliches Layout wie die anderen Tabs: Ueberschrift + Text -> Info ->
    # Steuerung -> Inhalt.
    a_thr, b_thr = 80, 95  # feste Standard-Schwellen (Pareto)
    st.markdown(t("abc_head"))
    with st.expander(t("abc_explain_head")):
        st.markdown(t("abc_purpose"))
        st.markdown(t("abc_mode_note"))
        st.markdown(t("abc_thresh_note").format(a=a_thr, b=b_thr))
        st.markdown(t("abc_dist_note"))
        st.markdown(t("abc_c_note"))

    abc_mode = st.radio(
        t("abc_mode"),
        options=[t("abc_by_slots"), t("abc_by_articles"), t("abc_by_menge")],
        horizontal=True,
    )
    by_articles = abc_mode != t("abc_by_slots")   # beide Artikel-Sichten
    by_menge = abc_mode == t("abc_by_menge")
    art_value = "menge" if by_menge else "bewegungen"
    _intro = (t("abc_intro_menge") if by_menge
              else t("abc_intro_articles") if by_articles else t("abc_intro"))
    st.caption(_intro.format(a=a_thr, b=b_thr))

    if by_articles:
        mov_filter_note(movements_filtered, filtered)
        # Menge IMMER mitladen -> beide Artikel-Sichten koennen Bewegungen UND
        # Menge nebeneinander zeigen (gegenseitige Ergaenzung).
        base = agg_articles(tpa, with_menge=True)
        data = classify_abc(base, art_value, a_thr, b_thr) \
            if not base.empty else base
        table_cols = ["artikel", "bezeichnung", art_value, "CUM_%", "ABC"]
    else:
        # Klassifikation IMMER ueber das GANZE Lager (mit den Reglern) -> jeder
        # Platz hat EINE Klasse, konsistent in beiden Tabellen unten und mit
        # 3D/Uebersicht. Der Sidebar-Filter beschraenkt nur die ANGEZEIGTEN
        # Zeilen, NICHT die Klassifikation.
        full = classify_abc(load_platz_full(), "ANZ_PICKS", a_thr, b_thr)
        _sel = set(filtered["PLATZ_ID"].astype(str))
        data = full[full["PLATZ_ID"].astype(str).isin(_sel)]
        table_cols = ["PLATZ_ID", "REGAL", "FACH", "EBENE",
                      "ANZ_PICKS", "CUM_%", "ABC_KLASSE", "ABC"]

    if data.empty:
        st.info(t("no_data_filters"))
        return

    # Klartext-Spaltennamen fuer beide Tabellen unten.
    colmap = {
        "PLATZ_ID": t("d3_f_platz"), "REGAL": t("rack"), "FACH": t("fach_label"),
        "EBENE": t("level"), "ANZ_PICKS": t("picks_label"),
        "CUM_%": t("abc_cumcol"), "ABC_KLASSE": "Stamm", "ABC": "Berechnet",
        "artikel": "Artikel", "bezeichnung": "Bezeichnung",
        "bewegungen": "Bewegungen", "menge": t("abc_col_menge"),
    }

    # Wertespalte + Labels je Sicht.
    _artikel_lbl = "Artikel" if _LANG == "de" else "Articles"
    if by_menge:
        val_col, val_label, ent_label = "menge", t("abc_col_menge"), _artikel_lbl
    elif by_articles:
        val_col = "bewegungen"
        val_label = "Bewegungen" if _LANG == "de" else "Movements"
        ent_label = _artikel_lbl
    else:
        val_col, val_label = "ANZ_PICKS", t("picks_label")
        ent_label = "Plätze" if _LANG == "de" else "Slots"
    # Verteilung: Balkendiagramm Anteil PLAETZE vs. Anteil PICKS je Klasse
    # (Erklaerung dazu steht im eingeklappten Block oben). Bei Plaetzen werden
    # die LEEREN (0 Picks) als eigene Kategorie ausgewiesen, statt sie unsichtbar
    # in C zu stecken -> sonst wirkt C kuenstlich riesig (freie Reserve).
    if by_articles:
        cats = ["A", "B", "C"]
        cat_series = data["ABC"]
    else:
        empty_label = "leer (0 Picks)" if _LANG == "de" else "empty (0 picks)"
        cats = ["A", "B", "C", empty_label]
        cat_series = pd.Series(
            np.where(data[val_col] == 0, empty_label, data["ABC"]),
            index=data.index)
    counts = cat_series.value_counts().reindex(cats).fillna(0)
    picks_sum = (data.groupby(cat_series)[val_col].sum()
                 .reindex(cats).fillna(0))
    total_picks = picks_sum.sum() or 1
    total_count = counts.sum() or 1
    share = (picks_sum / total_picks * 100).round(1)
    count_share = (counts / total_count * 100).round(1)
    summary = pd.DataFrame({
        t("abc_col_count"): counts.astype(int).values,
        val_label: picks_sum.astype(int).values,
        t("abc_col_share"): share.values,
    }, index=cats)
    summary.index.name = t("abc")
    lbl_c, lbl_p = f"% {ent_label}", f"% {val_label}"
    # Diagramm OHNE die 'leer'-Kategorie (nur A/B/C) -> sonst dominiert der
    # 88%-Leer-Balken alles. Die Tabelle daneben zeigt 'leer' weiterhin.
    # %-Werte bleiben auf ALLE Plaetze bezogen (zeigt den ABC-Effekt).
    bar_cats = ["A", "B", "C"]
    nb = len(bar_cats)
    bar_df = pd.DataFrame({
        t("abc"): bar_cats * 2,
        "Kennzahl": [lbl_c] * nb + [lbl_p] * nb,
        "Prozent": list(count_share.reindex(bar_cats).values)
        + list(share.reindex(bar_cats).values),
    })
    d1, d2 = st.columns([2, 1])
    with d1:
        st.plotly_chart(
            px.bar(bar_df, x=t("abc"), y="Prozent", color="Kennzahl",
                   barmode="group", title=t("abc_bar_title"),
                   category_orders={t("abc"): bar_cats},
                   color_discrete_map={lbl_c: "#90a4ae", lbl_p: "#1565c0"}),
            use_container_width=True,
        )
    with d2:
        st.markdown(f"**{t('abc_count')}**")
        st.dataframe(summary, use_container_width=True)

    # Rechenweg-Button: Schritt-fuer-Schritt, wie die Klasse entsteht, plus die
    # konkreten Pick-Grenzen aus der aktuellen Auswahl (macht "warum A" greifbar).
    with st.expander(t("abc_calc_head")):
        st.markdown(t("abc_calc_steps").format(a=a_thr, b=b_thr, e=ent_label))
        a_vals = data[data["ABC"] == "A"][val_col]
        b_vals = data[data["ABC"] == "B"][val_col]
        if not a_vals.empty and not b_vals.empty:
            st.markdown(t("abc_calc_concrete").format(
                amin=de_num(int(a_vals.min())),
                bmin=de_num(int(b_vals.min())),
                amin1=de_num(int(a_vals.min()) - 1)))

    # --- Tabelle 1: nur Abweichungen Stamm vs. Berechnet + Empfehlung -------
    # (nur Platz-Sicht; Artikel haben kein Stamm-ABC). Gleiche Klasse wie unten.
    if not by_articles:
        st.markdown(t("abc_adjust_head"))
        st.caption(t("abc_adjust_intro"))
        rank = {"A": 3, "B": 2, "C": 1}
        dev = data[data["ABC_KLASSE"].isin(["A", "B", "C"])].copy()
        dev = dev[dev["ABC_KLASSE"] != dev["ABC"]]  # nur Abweichungen
        if dev.empty:
            st.info(t("abc_no_dev"))
        else:
            dev["_m"] = dev["ABC_KLASSE"].map(rank)
            dev["_c"] = dev["ABC"].map(rank)
            # Zwei getrennte Listen: hochstufen (mehr Picks als hinterlegt,
            # meiste oben) und herabstufen (kaum Picks, wenigste oben).
            promote = dev[dev["_c"] > dev["_m"]].sort_values(
                "ANZ_PICKS", ascending=False)
            demote = dev[dev["_c"] < dev["_m"]].sort_values(
                "ANZ_PICKS", ascending=True)
            mcols = st.columns(2)
            mcols[0].metric(t("abc_promote"), de_num(len(promote)))
            mcols[1].metric(t("abc_demote"), de_num(len(demote)))
            _dev_cols = ["PLATZ_ID", "REGAL", "FACH", "EBENE", "ANZ_PICKS",
                         "CUM_%", "ABC_KLASSE", "ABC"]

            def _dev_table(sub: pd.DataFrame, key: str) -> None:
                if sub.empty:
                    st.info(t("abc_none_cat"))
                    return
                tbl = sub[_dev_cols].rename(columns=colmap)
                st.dataframe(tbl.head(200), use_container_width=True,
                             hide_index=True)
                _csv_download(tbl, key)

            st.markdown(f"**{t('abc_promote')}**")
            st.caption(t("abc_promote_note"))
            _dev_table(promote, "abc_hochstufen")
            st.markdown(f"**{t('abc_demote')}**")
            st.caption(t("abc_demote_note"))
            _dev_table(demote, "abc_herabstufen")

    # --- Tabelle 2: Detailliste je Sicht -----------------------------------
    if by_articles:
        # Beide Artikel-Sichten stellen Bewegungen UND Menge gegenueber + Ø Menge
        # je Bewegung -> Renner mit grossen Mengen vs. nur oft in kleinen
        # Portionen entnommene Artikel werden unterscheidbar. Reihenfolge der
        # Spalten je nach Sortier-/Klassifikationsgroesse (Menge bzw. Bewegungen).
        atab = data.copy()
        atab["_avg"] = np.where(
            atab["bewegungen"] > 0,
            (atab["menge"] / atab["bewegungen"]).round(1), 0.0)
        amap = dict(colmap)
        amap["_avg"] = t("abc_col_avgmenge")
        if by_menge:
            st.markdown(t("abc_bymenge_head"))
            st.caption(t("abc_bymenge_note"))
            acols = ["artikel", "bezeichnung", "menge", "bewegungen", "_avg",
                     "CUM_%", "ABC"]
            dl_key = "abc_menge"
        else:
            st.markdown(t("abc_byart_head"))
            st.caption(t("abc_byart_note"))
            acols = ["artikel", "bezeichnung", "bewegungen", "menge", "_avg",
                     "CUM_%", "ABC"]
            dl_key = "abc_articles"
        table = atab[[c for c in acols if c in atab.columns]].rename(columns=amap)
        st.dataframe(table.head(200), use_container_width=True, hide_index=True)
        if len(table) > 200:
            st.caption(t("abc_csv_all").format(n=de_num(len(table))))
        _csv_download(table, dl_key)
    else:
        st.markdown(t("abc_byfreq"))
        st.caption(t("abc_byfreq_note"))
        table = data[[c for c in table_cols if c in data.columns]].rename(columns=colmap)
        st.dataframe(table.head(200), use_container_width=True, hide_index=True)
        _csv_download(table, "abc_slots")


def render_trend(tpa: pd.DataFrame, days: int, movements_filtered: bool,
                 filtered: pd.DataFrame) -> None:
    """Unter-Tab 'Durchsatz': Bewegungen je Tag (letzte N Tage o. Bereich)."""
    st.markdown(t("tp_intro"))
    # Was bedeutet das? — beantwortet v.a. "was zaehlt als EINE Bewegung?"
    # (Lehrer-Feedback), plus Kennzahlen + Grund fuer den Wochenende-Filter.
    with st.expander(t("tp_info_t")):
        st.markdown(t("tp_info_b"))
    mov_filter_note(movements_filtered, filtered)
    st.caption(t("weekend_hidden"))
    use_range = st.checkbox(t("tp_use_range"), value=False)
    if use_range:
        all_days = agg_movements_by_day(tpa)
        if all_days.empty:
            trend = all_days
        else:
            dmin = all_days["day"].min().date()
            dmax = all_days["day"].max().date()
            picked = st.date_input(t("tp_range"), (dmin, dmax),
                                   min_value=dmin, max_value=dmax)
            if isinstance(picked, (tuple, list)) and len(picked) == 2:
                lo, hi = picked
                trend = all_days[
                    (all_days["day"].dt.date >= lo)
                    & (all_days["day"].dt.date <= hi)
                ].copy()
            else:
                trend = all_days.copy()
            trend = trend.sort_values("day")
    else:
        trend = agg_throughput_trend(tpa, days)
    # Wochenende IMMER ausblenden (kein Toggle mehr).
    trend = drop_weekend(trend, "day")
    if trend.empty:
        st.info(t("no_data_filters"))
    else:
        fig = px.bar(
            trend, x="day", y="movements",
            title=t("tp_chart").format(n=len(trend)),
        )
        fig.update_layout(
            yaxis_title=t("picks_label"),
            xaxis_title="Date" if _LANG == "en" else "Datum",
        )
        st.plotly_chart(fig, use_container_width=True)

        c1, c2, c3 = st.columns(3)
        c1.metric(t("tp_avg"), f"{trend['movements'].mean():.0f}")
        c2.metric(t("tp_max"), de_num(int(trend['movements'].max())))
        c3.metric(t("tp_sum"),
                  de_num(int(trend['movements'].sum())))

        tbl = trend.copy()
        tbl["day"] = tbl["day"].dt.strftime("%Y-%m-%d")
        tbl = tbl.rename(columns={"day": "Datum", "movements": "Bewegungen"})
        tbl = tbl.sort_values("Datum", ascending=False)
        st.dataframe(tbl, use_container_width=True, hide_index=True)
        _csv_download(tbl, "durchsatz")


# Top-Artikel-Tabelle: technische -> sprechende Spalten + Tooltips.
_TOP_RENAME = {
    "artikel": "Artikel-Nr", "bezeichnung": "Bezeichnung",
    "bewegungen": "Bewegungen",
}
_TOP_HELP = {
    "Artikel-Nr": "Die Artikelnummer.",
    "Bezeichnung": "Der Klartext-Name des Artikels.",
    "Bewegungen": "Wie oft der Artikel im Zeitraum bewegt bzw. gepickt wurde. "
                  "Mehr Bewegungen = wichtigerer Dreher.",
}


def render_top(tpa: pd.DataFrame, article_limit: int,
               movements_filtered: bool, filtered: pd.DataFrame,
               show_all: bool = False) -> None:
    """Unter-Tab 'Top-Artikel': meistbewegte Artikel aus TPA.

    show_all=True -> Tabelle zeigt ALLE Artikel (Checkbox in der Sidebar);
    sonst nur die Top-N laut Regler. Das Diagramm bleibt immer auf Top-25
    begrenzt (mehr Balken waeren unleserlich), der CSV-Export immer komplett.
    """
    st.markdown(t("top_intro"))
    with st.expander(t("top_info_t")):
        st.markdown(t("top_info_b"))
    mov_filter_note(movements_filtered, filtered)
    # ALLE Artikel laden (fuer den CSV-Export); Diagramm/Tabelle zeigen nur Top-N.
    top_all = agg_articles(tpa)
    if top_all.empty:
        st.info(t("no_data_filters"))
    else:
        top = top_all if show_all else top_all.head(article_limit)
        chart_df = top.head(min(article_limit, 25)).sort_values("bewegungen")
        fig_top = px.bar(
            chart_df, x="bewegungen", y="artikel", orientation="h",
            title=t("top_chart"), text="artikel",
            color="bewegungen", color_continuous_scale=["#5b9bd5", "#1f4e79"],
            labels=dict(bewegungen="Bewegungen", artikel="Artikel"),
        )
        # Artikelnummer VORNE in jeden Balken (linker Anfang), weiss; Balken im
        # Blau-Verlauf nach Haeufigkeit, ohne Rand.
        fig_top.update_traces(
            textposition="inside", insidetextanchor="start",
            textfont=dict(color="white", size=13),
            marker_line_width=0, cliponaxis=False,
        )
        # Aufgeraeumter Look: keine Farbleiste, transparenter Hintergrund,
        # dezentes X-Raster, mehr Luft zwischen den Balken, Hoehe nach Anzahl.
        fig_top.update_yaxes(showticklabels=False, title_text="")
        fig_top.update_xaxes(showgrid=True, gridcolor="rgba(0,0,0,0.07)")
        fig_top.update_layout(
            height=max(450, len(chart_df) * 34),
            coloraxis_showscale=False,
            plot_bgcolor="rgba(0,0,0,0)", paper_bgcolor="rgba(0,0,0,0)",
            bargap=0.3, title_font_size=16,
            margin=dict(l=10, r=30, t=50, b=10),
        )
        st.plotly_chart(fig_top, use_container_width=True)
        show = top.rename(columns=_TOP_RENAME)
        col_cfg = {c: st.column_config.Column(help=h)
                   for c, h in _TOP_HELP.items() if c in show.columns}
        st.dataframe(show, use_container_width=True, hide_index=True,
                     column_config=col_cfg)
        st.caption(t("top_dl_all").format(n=de_num(len(top_all))))
        # Download enthaelt ALLE Artikel, nicht nur die angezeigten Top-N.
        _csv_download(top_all.rename(columns=_TOP_RENAME), "top_artikel")


def render_article(tpa: pd.DataFrame, movements_filtered: bool,
                   filtered: pd.DataFrame) -> None:
    """Tab 'Artikel': Bewegungen und Quellplaetze eines Artikels."""
    st.markdown(t("art_intro"))
    with st.expander(t("art_info_t")):
        st.markdown(t("art_info_b"))
    mov_filter_note(movements_filtered, filtered)
    opts = agg_articles(tpa, limit=500)
    labels = (
        (opts["artikel"] + " — " + opts["bezeichnung"]).tolist()
        if not opts.empty else []
    )
    col_s, col_i = st.columns(2)
    with col_s:
        chosen = st.selectbox(t("art_select"), options=labels) if labels else None
    with col_i:
        manual = st.text_input(t("art_input"), value="").strip()

    artikelnr = manual or (chosen.split(" — ")[0] if chosen else "")
    if not artikelnr:
        st.info(t("art_none"))
    else:
        slots, day_df = agg_article_detail(tpa, artikelnr)
        total = int(slots["picks"].sum()) if not slots.empty else 0
        if total == 0 and day_df.empty:
            st.info(t("art_none"))
        else:
            m1, m2 = st.columns(2)
            m1.metric(t("art_total"), de_num(total))
            m2.metric(t("art_slotcount"),
                      de_num(len(slots)))
            if not day_df.empty:
                st.markdown(f"**{t('art_trend')}**")
                st.caption(t("weekend_hidden"))
                # Wochenende IMMER ausblenden (kein Toggle mehr).
                day_plot = drop_weekend(day_df, "day")
                # Balken (konsistent mit Durchsatz-Tab) statt Linie.
                st.plotly_chart(
                    px.bar(day_plot, x="day", y="picks",
                           labels={"day": "Datum" if _LANG == "de" else "Date",
                                   "picks": t("picks_label")}),
                    use_container_width=True,
                )
            if not slots.empty:
                st.markdown(f"**{t('art_by_slot')}**")
                slot_tbl = slots.rename(columns={"platz": "Quellplatz",
                                                 "picks": "Picks (von hier)"})
                slot_help = {
                    "Quellplatz": "Der Lagerplatz, aus dem dieser Artikel "
                                  "entnommen wurde.",
                    "Picks (von hier)": "Wie oft der Artikel im Zeitraum von "
                                        "genau diesem Platz gepickt wurde.",
                }
                col_cfg = {c: st.column_config.Column(help=h)
                           for c, h in slot_help.items() if c in slot_tbl.columns}
                st.dataframe(slot_tbl, use_container_width=True,
                             hide_index=True, column_config=col_cfg)
                _csv_download(slot_tbl, "artikel_plaetze")


def render_3d(filtered: pd.DataFrame) -> None:
    """Tab '3D-Modell': klickbarer CAD-Viewer (Meshes nach PLATZ_ID)."""
    import json as _json

    # Einheitliches Tab-Layout wie die anderen Reiter: Ueberschrift + Info-
    # Expander. Es gibt nur noch EINE Ansicht (CAD), daher kein Umschalter mehr.
    st.markdown(t("d3_head"))
    with st.expander(t("d3_explain_head")):
        st.markdown(t("d3_click_intro"))

    # Lagerplatz-Suche direkt an der Karte: ID eingeben -> Ansicht fliegt hin.
    search_platz = st.text_input(
        t("search_platz"), value="", help=t("search_platz_help"),
        key="d3_search",
    ).strip()

    slot_json = load_slot_3d_map()
    labels = {
        "hint": t("d3_panel_hint"),
        "platz": t("d3_f_platz"),
        "pos": t("d3_f_pos"),
        "abc_m": t("d3_f_abc_m"),
        "abc_c": t("d3_f_abc_c"),
        "picks": t("d3_f_picks"),
        "nachschub": t("d3_f_nachschub"),
        "util": t("d3_f_util"),
        "status": t("d3_f_status"),
        "cap": t("d3_f_cap"),
        "free": t("d3_f_free"),
        "locked": t("d3_f_locked"),
        "lastacc": t("d3_f_lastacc"),
        "daysempty": t("d3_f_daysempty"),
        "yes": t("d3_yes"),
        "no": t("d3_no"),
        "occupied": t("d3_occupied"),
        "empty": t("d3_empty"),
        "notdb": t("d3_not_in_db"),
        "legend": t("d3_legend"),
        "grey": t("d3_grey"),
        "notfound": t("d3_notfound"),
        "loading": "Lade Modell" if _LANG == "de" else "Loading model",
        # Heatmap-Legende (CAD-Viewer, Modi 'picks'/'moves')
        "heat_picks": t("d3_heat_picks"),
        "heat_moves": t("d3_heat_moves"),
        "heat_low": t("d3_heat_low"),
        "heat_high": t("d3_heat_high"),
        "heat_zero": t("d3_heat_zero"),
    }
    labels_json = _json.dumps(labels, ensure_ascii=False)
    # Nur 9-stellige PLATZ_ID ins Modell durchreichen.
    focus_id = search_platz if search_platz.isdigit() else ""

    # CAD-Modell: SampleScene_clickable.glb (Meshes nach PLATZ_ID benannt),
    # CORS-faehig ueber die API geliefert. Der ?v=-Parameter ist ein
    # Cache-Buster: bei jedem Modell-Wechsel hochzaehlen, damit Browser die
    # neue GLB laden statt der alten aus dem Cache.
    glb_url = "https://ssi-lagerview-api.onrender.com/model-clickable.glb?v=20260624"
    ctrl1, ctrl2, ctrl3, ctrl4 = st.columns([1, 1, 1, 1])
    with ctrl1:
        # Faerb-Modus: ABC-Klassen, Pick-Heatmap, Bewegungs-Heatmap oder
        # gar nicht (Original-Optik der GLB).
        cad_cm_opts = [t("d3_cad_cm_abc"), t("d3_cad_cm_picks"),
                       t("d3_cad_cm_moves"), t("d3_cad_cm_none")]
        cad_cm_choice = st.selectbox(t("d3_colormode"), cad_cm_opts, index=0,
                                     key="d3_cm_cad", help=t("d3_cad_cm_help"))
        colormode_cad = {
            t("d3_cad_cm_abc"): "abc", t("d3_cad_cm_picks"): "picks",
            t("d3_cad_cm_moves"): "moves", t("d3_cad_cm_none"): "none",
        }[cad_cm_choice]
    with ctrl2:
        perf_mode = st.checkbox(t("d3_perf"), value=True, help=t("d3_perf_help"))
    with ctrl3:
        viewer_height = st.slider(t("d3_height"), 360, 900, 640, step=20,
                                  help=t("d3_height_help"))
    with ctrl4:
        # Maus-Empfindlichkeit fuer Drehen/Zoom/Pan; kleiner = feiner steuerbar.
        sens = st.slider(t("d3_sens"), 0.2, 1.5, 1.0, step=0.1,
                         key="d3_sens_cad", help=t("d3_sens_help"))
    html = (
        _THREE_VIEWER_HTML
        .replace("__HEIGHT__", str(viewer_height))
        .replace("__GLB__", glb_url)
        .replace("__DATA__", slot_json)
        .replace("__LABELS__", labels_json)
        .replace("__ROTATE__", "false")
        .replace("__COLORMODE__", colormode_cad)
        .replace("__HIDEGREY__", "true" if perf_mode else "false")
        .replace("__FOCUS__", focus_id)
        .replace("__SENS__", str(sens))
    )
    # +230: Detail-Panel liegt jetzt UNTER der Karte (200px) + Abstand.
    components.html(html, height=viewer_height + 230)
    st.caption(t("d3_caption"))


def main() -> None:
    """Baut die komplette Oberflaeche auf (Streamlit rendert top-down und fuehrt
    diese Funktion bei jeder Interaktion komplett neu aus).

    Ablauf: Sprache -> Logo/Titel -> Daten laden -> Sidebar-Filter -> KPIs ->
    Tabs. Die teuren Lade-Funktionen sind gecacht, daher ist das Neu-Ausfuehren
    guenstig.
    """
    # Sprachumschalter ganz oben in der Sidebar; setzt das globale _LANG, das
    # t() fuer alle folgenden Texte auswertet.
    global _LANG, _FILTER_LABEL
    _LANG = "en" if st.sidebar.radio(
        TR["lang_label"]["de"], ["Deutsch", "English"], horizontal=True,
    ) == "English" else "de"

    logo = _logo_path()
    if logo is not None:
        try:
            st.logo(str(logo))  # oben links + Sidebar-Kopf
        except Exception:
            pass

    if logo is not None:
        col_logo, col_title = st.columns([1, 6], vertical_alignment="center")
        with col_logo:
            st.image(str(logo), width=110)
        with col_title:
            st.title("Schaeflein LagerView v1.4")
            st.caption(t("caption"))
    else:
        st.title("📦 Schaeflein LagerView v1.4")
        st.caption(t("caption"))

    render_formulas_popover()

    try:
        platz = load_platz_full()
    except Exception as exc:
        st.error(f"Konnte Stellplatz-Daten nicht laden: {exc}")
        st.exception(exc)
        st.stop()

    with st.sidebar:
        st.header(t("filter"))
        abc = st.multiselect(
            t("abc"),
            options=["A", "B", "C"],
            default=[],
            help=t("abc_help"),
        )
        # Quelle der ABC-Auswahl: Stamm (WMS), Berechnet (Picks) oder Beide.
        # Greift nur, wenn oben Klassen gewaehlt sind; Default 'Beide' = altes
        # ODER-Verhalten. -> auf kanonische (deutsche) Schluessel zurueckmappen.
        abc_src_opts = [t("abc_src_stamm"), t("abc_src_calc"), t("abc_src_both")]
        abc_src_choice = st.radio(
            t("abc_src"), options=abc_src_opts, index=2, horizontal=True,
            help=t("abc_src_help"), disabled=not abc,
        )
        abc_src = ["Stamm", "Berechnet", "Beide"][abc_src_opts.index(abc_src_choice)]
        util_range = st.slider(
            t("util"), 0, 100, (0, 100), step=5, help=t("util_help"),
        )
        only_occupied = st.checkbox(t("only_occ"), value=False)
        with st.expander(t("place_filter")):
            regal_max = max(int(platz["REGAL"].max()), 1)
            # EBENE enthaelt vereinzelte Ausreisser-Datensaetze bis 24 (je 1 Platz),
            # waehrend echte Ebenen substanziell belegt sind (0-6 sowie Cluster 10-13).
            # Obergrenze = hoechste Ebene mit nennenswerter Belegung (>= 20 Plaetze),
            # damit Einzel-Ausreisser die Skala nicht aufblaehen. Zusaetzlich hart
            # auf 9 gedeckelt -> die Cluster-Codes 10-13 sind fuer den Bediener
            # nicht als echte Ebenen lesbar und wuerden die Skala verwirren.
            _ebene_counts = platz["EBENE"].value_counts()
            _ebene_real = _ebene_counts[_ebene_counts >= 20].index
            ebene_max = (max(int(_ebene_real.max()), 1) if len(_ebene_real)
                         else max(int(platz["EBENE"].max()), 1))
            ebene_max = min(ebene_max, 9)
            picks_max = max(int(platz["ANZ_PICKS"].max()), 1)
            regal_range = st.slider(t("rack"), 0, regal_max, (0, regal_max))
            ebene_range = st.slider(t("level"), 0, ebene_max, (0, ebene_max),
                                    help=t("level_help"))
            min_picks = st.slider(t("min_picks"), 0, picks_max, 0)
            sperr_opts = [t("lock_all"), t("lock_only"), t("lock_without")]
            sperr_choice = st.radio(
                t("lock_status"), options=sperr_opts, horizontal=True,
            )
            # auf kanonische (deutsche) Schluessel zurueckmappen
            sperr_mode = ["Alle", "Nur gesperrte", "Ohne gesperrte"][
                sperr_opts.index(sperr_choice)
            ]
        st.divider()
        days = st.slider(t("tp_period"), 7, 180, 30, step=7)
        article_limit = st.slider(t("top_count"), 5, 500, 25, step=5)
        show_all_top = st.checkbox(t("top_show_all"), value=False,
                                   help=t("top_show_all_h"))
        st.divider()
        st.caption(f"DB: `{get_db_path()}`")

    # Einmal filtern -> alle Tabs nutzen dasselbe gefilterte DataFrame.
    filtered = apply_filters(
        platz, abc, util_range, only_occupied,
        regal_range=regal_range,
        ebene_range=ebene_range,
        min_picks=min_picks,
        sperr_mode=sperr_mode,
        abc_src=abc_src,
    )

    # Menschenlesbare Zusammenfassung der aktiven Filter -> Caption unter den KPIs
    # und Kommentarzeile in jedem CSV-Download (Nachvollziehbarkeit).
    _af: list[str] = []
    if abc:
        _af.append(f"{t('abc')}: {', '.join(abc)} ({abc_src_choice})")
    if util_range != (0, 100):
        _af.append(f"{t('util')}: {util_range[0]}–{util_range[1]}")
    if only_occupied:
        _af.append(t("only_occ"))
    if regal_range != (0, regal_max):
        _af.append(f"{t('rack')}: {regal_range[0]}–{regal_range[1]}")
    if ebene_range != (0, ebene_max):
        _af.append(f"{t('level')}: {ebene_range[0]}–{ebene_range[1]}")
    if min_picks > 0:
        _af.append(f"{t('min_picks')}: ≥ {min_picks}")
    if sperr_mode != "Alle":
        _af.append(f"{t('lock_status')}: {sperr_choice}")
    _FILTER_LABEL = "; ".join(_af) if _af else t("filter_none")
    st.caption(f"{t('active_filters')}: {_FILTER_LABEL}")

    # Bewegungsdaten (TPA) einmal roh laden und auf die gefilterten Plaetze
    # einschraenken (ueber Q_PLATZ -> PLATZ_ID). So wirken die Sidebar-Filter
    # jetzt LIVE auch in den bewegungsbasierten Tabs (Pick-Heatmap, Durchsatz,
    # Top-Artikel, Artikel, ABC-nach-Artikeln). Ist kein Filter aktiv (gleiche
    # Zeilenzahl wie das volle Platz-DF), bleibt der schnelle Voll-Datensatz.
    tpa_all = load_tpa_raw()
    movements_filtered = len(filtered) != len(platz)
    allowed_pids = (
        set(filtered["PLATZ_ID"].astype(str).str.strip())
        if movements_filtered else None
    )
    tpa = filter_tpa(tpa_all, allowed_pids)

    # --- KPI-Kacheln oben (beziehen sich auf die gefilterte Auswahl) ---
    total = len(filtered) or 1
    occupied = int(filtered["BELEGT"].sum())
    # "Belegt" = mind. 1 LHM drauf. Aufschluesseln in voll (keine Restkapazitaet)
    # und teilbelegt (noch Platz), damit teilweise gefuellte Plaetze nicht als
    # "voll belegt" missverstanden werden (User-Feedback) - konsistent zum
    # Uebersichts-Diagramm.
    full_occ = int((filtered["BELEGT"] & filtered["FREE_CAPACITY"].le(0)).sum())
    partial_occ = occupied - full_occ
    avg_util = filtered["UTILIZATION"].mean()
    # Durchschnittlicher Bestand je Platz = mittlere belegte Ladehilfsmittel
    # (IST_LHM) ueber alle Plaetze. Konkreter/greifbarer als die Ø Auslastung %
    # (User-Wunsch). Ø Auslastung bleibt als Zusatzinfo im Tooltip erhalten.
    avg_stock = filtered["IST_LHM"].mean()

    c1, c2, c3 = st.columns(3)
    c1.metric(t("m_slots"), de_num(len(filtered)),
              help=t("m_slots_help"))
    c2.metric(t("m_occupied"), de_num(occupied),
              f"{occupied/total*100:.1f}%", help=t("m_occupied_help"))
    c2.caption(t("m_occupied_split").format(
        full=de_num(full_occ), partial=de_num(partial_occ)))
    util_hint = (f" · Ø Auslastung {avg_util:.1f} %"
                 if not pd.isna(avg_util) else "")
    c3.metric(t("m_avg_stock"),
              f"{avg_stock:.1f}".replace(".", ",") + " LHM"
              if not pd.isna(avg_stock) else "—",
              help=t("m_avg_stock_help") + util_hint)

    # --- Register/Tabs ---------------------------------------------------
    # Reihenfolge der Variablen MUSS zur Reihenfolge der Titel-Liste passen.
    # ACHTUNG: Die Anzeige-Reihenfolge der Reiter bestimmt allein diese Liste –
    # die `with tab_*`-Bloecke weiter unten duerfen in beliebiger Code-Reihen-
    # folge stehen. Reihenfolge: Übersicht, 3D, ABC, Steuermassnahmen (Um-/Auslagern
    # zusammengefasst / Nachschub / Einlagern), Artikel, und ganz am Ende "Sonstiges".
    # "Sonstiges" buendelt Auslastungs-/Pick-Heatmap, Hochfrequenz-Plaetze, Free
    # Capacity, Durchsatz und Top-Artikel (siehe unten).
    # Umlagern + Auslagern liegen jetzt in EINEM Reiter (beide arbeiten auf
    # denselben Plaetzen mit gegenlaeufiger Logik).
    (tab_uebersicht, tab_3d, tab_abc, tab_umlagern, tab_nachschub,
     tab_einlagern, tab_article, tab_sonstiges) = st.tabs([
        t("tab_halls"),
        t("tab_3d"),
        t("tab_abc"),
        t("tab_reloc_retr"),
        t("tab_replenish"),
        t("tab_putaway"),
        t("tab_article"),
        t("tab_misc"),
    ])

    # "Sonstiges": Unter-Tabs fuer die Analyse-Heatmaps + Durchsatz + Top-
    # Artikel. Die Unter-Tab-Objekte werden hier (im Kontext von tab_sonstiges)
    # erzeugt; ihre Inhalte folgen weiter unten als `with sub_*` und landen
    # dadurch verschachtelt unter "Sonstiges".
    with tab_sonstiges:
        (sub_bottle, sub_free, sub_trend, sub_top,
         sub_pickheat) = st.tabs([
            t("tab_bottle"), t("tab_free"),
            t("tab_tp"), t("tab_top"), t("tab_pick"),
        ])

    with tab_uebersicht:
        render_uebersicht(filtered)

    with sub_pickheat:
        render_pickheat(tpa, movements_filtered, filtered)

    with sub_bottle:
        render_high_frequency_slots(filtered)

    with sub_free:
        render_free(filtered)

    # ----- Steuermassnahmen (Umlagern/Nachschub/Einlagern/Auslagern) -----
    # Jeder dieser vier Tabs zeigt mehrere "Kategorien" (z. B. dringend/
    # ueberfaellig). Eine Kategorie = eine nach Regeln gefilterte Teilmenge von
    # `filtered`. render_massnahme_kategorie() (oben) rendert jede einheitlich:
    # Titel, Anzahl-Kennzahl, Tabelle und CSV-Download. Die Regeln (welche
    # Plaetze in welche Kategorie fallen) entsprechen der Logik der Flutter-App.
    with tab_umlagern:
        render_umlagern_auslagern(filtered)

    with tab_nachschub:
        render_nachschub(filtered)

    with tab_einlagern:
        render_einlagern(filtered)

    with tab_abc:
        render_abc(filtered, tpa, movements_filtered)

    with sub_trend:
        render_trend(tpa, days, movements_filtered, filtered)

    with sub_top:
        render_top(tpa, article_limit, movements_filtered, filtered,
                   show_all_top)

    with tab_article:
        render_article(tpa, movements_filtered, filtered)

    with tab_3d:
        render_3d(filtered)


if __name__ == "__main__":
    main()
