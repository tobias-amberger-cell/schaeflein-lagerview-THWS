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
#   __ROTATE__  "true"/"false"     __ABCCOLOR__ "true"/"false" (ABC einfaerben)
#   __HIDEGREY__ "true"/"false"    (Leistungsmodus: datenlose Plaetze ausblenden)
#   __FOCUS__   gesuchte PLATZ_ID (leer = keine Suche; Kamera springt sonst hin)
# Ablauf im Browser: GLTF laden -> Kamera einpassen -> Klick = Raycasting ->
# getroffenes Mesh hat als Namen die PLATZ_ID -> Kennzahlen aus __DATA__ ins
# Panel. KEINE React/Node-Abhaengigkeit, laeuft komplett in der iframe.
_THREE_VIEWER_HTML = """
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
import { GLTFLoader } from 'three/addons/loaders/GLTFLoader.js';

const DATA = __DATA__;
const L = __LABELS__;
const AUTOROTATE = __ROTATE__;
const ABCCOLOR = __ABCCOLOR__;
const HIDEGREY = __HIDEGREY__;
const FOCUS = "__FOCUS__";  // gesuchte PLATZ_ID (leer = keine Suche)
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

const host = document.getElementById('view');
const panel = document.getElementById('panel');
const loadingEl = document.getElementById('loading');
panel.innerHTML = '<div style="color:#888;">' + L.hint + '</div>';

let W = host.clientWidth || 600, H = host.clientHeight || 600;
const scene = new THREE.Scene();
scene.background = new THREE.Color(0xf5f5f7);
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
controls.addEventListener('change', requestRender);

// --- "Schweben" durch die Regale per WASD ---------------------------------
// OrbitControls bleibt voll erhalten (Drehen per Maus + Klick). Zusaetzlich
// bewegen WASD/QE Kamera UND Orbit-Zielpunkt gemeinsam durch den Raum -> man
// fliegt in die Gaenge und kann dort weiter drehen/klicken. Kein Pointer-Lock,
// damit das Anklicken nicht kaputt geht.
const keys = {};
let moveScale = 1;  // wird nach dem Laden an die Modellgroesse angepasst
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
  if(keys.w) _mv.addScaledVector(_fwd, speed);
  if(keys.s) _mv.addScaledVector(_fwd, -speed);
  if(keys.d) _mv.addScaledVector(_right, speed);
  if(keys.a) _mv.addScaledVector(_right, -speed);
  if(keys.e) _mv.y += speed;
  if(keys.q) _mv.y -= speed;
  if(_mv.lengthSq() === 0) return false;
  camera.position.add(_mv);
  controls.target.add(_mv);  // Zielpunkt mitnehmen -> man "fliegt", Orbit bleibt
  needsRender = true;
  return true;
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
    const counts = { A:0, B:0, C:0, grey:0 };
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
      if(ABCCOLOR){ o.material = SHARED_MAT[key]; }
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
        "de": "Filtert auf Stamm-ABC ODER kumulativ berechnete ABC.",
        "en": "Filters on master ABC OR calculated ABC.",
    },
    "util": {"de": "Auslastung (%)", "en": "Utilization (%)"},
    "util_help": {
        "de": "IST_LHM / MAX_LHM × 100. 0 = leer, 100 = voll. Obergrenze 100 = "
              "„100 % und mehr\" (offen) – schließt seltene Überlast-Artefakte "
              "(≥ 200 %, MAX_LHM zu klein gepflegt) mit ein.",
        "en": "IST_LHM / MAX_LHM × 100. 0 = empty, 100 = full. Upper bound 100 = "
              "\"100 % and above\" (open) – includes rare overload artefacts "
              "(≥ 200 %, MAX_LHM set too low).",
    },
    "only_occ": {"de": "Nur belegte Plaetze", "en": "Occupied slots only"},
    "place_filter": {
        "de": "Platz-Filter (Regal/Ebene/Picks/Sperre)",
        "en": "Slot filter (rack/level/picks/lock)",
    },
    "rack": {"de": "Regal", "en": "Rack"},
    "level": {"de": "Ebene", "en": "Level"},
    "level_help": {
        "de": "Regalebene laut Feld EBENE. Obergrenze = höchste real belegte "
              "Ebene (≥ 20 Plätze) – einzelne Ausreißer-Datensätze (EBENE 14–24, "
              "je 1 Platz) blähen die Skala nicht mehr auf.",
        "en": "Rack level from field EBENE. Upper bound = highest substantially "
              "occupied level (≥ 20 slots) – single outlier records (EBENE 14–24, "
              "1 slot each) no longer inflate the scale.",
    },
    "min_picks": {"de": "Min. Picks (ANZ_PICKS)", "en": "Min. picks (ANZ_PICKS)"},
    "lock_status": {"de": "Sperr-Status", "en": "Lock status"},
    "lock_all": {"de": "Alle", "en": "All"},
    "lock_only": {"de": "Nur gesperrte", "en": "Locked only"},
    "lock_without": {"de": "Ohne gesperrte", "en": "Exclude locked"},
    "tp_period": {"de": "Durchsatz-Zeitraum (Tage)", "en": "Throughput period (days)"},
    "top_count": {"de": "Top-Artikel anzeigen", "en": "Show top items"},
    "m_slots": {"de": "Stellplaetze", "en": "Slots"},
    "m_occupied": {"de": "Belegt", "en": "Occupied"},
    "m_avg_util": {"de": "Ø Auslastung", "en": "Avg. utilization"},
    # KPI-Hilfetexte (Tooltip am ?-Symbol der Kacheln)
    "m_slots_help": {
        "de": "Anzahl Stellplaetze in der aktuellen Filter-Auswahl.",
        "en": "Number of slots in the current filter selection.",
    },
    "m_occupied_help": {
        "de": "Plaetze mit Ware (ZUSTAND > 0). Delta = Anteil belegter Plaetze.",
        "en": "Slots with goods (ZUSTAND > 0). Delta = share of occupied slots.",
    },
    "m_avg_util_help": {
        "de": "Mittelwert von IST_LHM / MAX_LHM x 100 ueber alle gefilterten Plaetze.",
        "en": "Average of IST_LHM / MAX_LHM x 100 across all filtered slots.",
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
    "tab_tp": {"de": "Durchsatz", "en": "Throughput"},
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
        "de": "**Lager-Übersicht** — Belegung, Auslastung und ABC-Verteilung für "
              "das gesamte Lager BER03 (eine Halle, keine Trennung).",
        "en": "**Warehouse overview** — occupancy, utilization and ABC "
              "distribution for the whole warehouse BER03 (single hall).",
    },
    "halls_kpis": {"de": "**Kennzahlen Lager gesamt**", "en": "**Metrics (whole warehouse)**"},
    "halls_chart": {
        "de": "Belegung Lager gesamt (gefiltert)",
        "en": "Occupancy whole warehouse (filtered)",
    },
    "pick_chart": {
        "de": "Pick-Aktivität je Wochentag/Stunde",
        "en": "Pick activity per weekday/hour",
    },
    "pick_intro": {
        "de": "**Pick-Heatmap** — Bewegungen je Wochentag und Stunde (aus den "
              "TPA-Daten). Zeigt, wann am meisten gepickt wird.",
        "en": "**Pick heatmap** — movements per weekday and hour (from TPA data). "
              "Shows when picking peaks.",
    },
    "pick_info_t": {
        "de": "ℹ️ Was bedeutet das? (Pick-Heatmap + „ein Pick“ erklärt)",
        "en": "ℹ️ What does this mean? (pick heatmap + “one pick”)",
    },
    "pick_info_b": {
        "de": "Die Heatmap zeigt, **wann** im Lager gepickt wird: **eine Zelle = ein Zeitfenster** (Wochentag × "
              "Stunde), die **Farbe = Anzahl Picks** darin (hell = wenig, rot = viel).\n\n"
              "**Was ist ein Pick / eine Bewegung?** Ein Pick = **ein Datensatz in den TPA-Daten** = **eine "
              "Auftragsposition** (eine Entnahmeposition) – identisch zum Durchsatz-Tab. *Ob eine Position genau "
              "einer Orderzeile oder einem Artikel entspricht, ist im Lagersystem (WMS) definiert.*\n\n"
              "**Was heißt „Picks je Quellplatz“?** Standardmäßig zählt die Heatmap **alle** Picks im Lager. Wenn du "
              "in der Sidebar **Plätze filterst**, werden nur die Bewegungen gezählt, die von diesen **Quellplätzen** "
              "(`Q_PLATZ` = der Platz, aus dem entnommen wird) ausgehen – so siehst du das Pick-Muster gezielt für "
              "die ausgewählten Plätze.\n\n"
              "**Wozu?** Stoßzeiten erkennen → Personal- und Schichtplanung.\n\n"
              "**Wochenende ausblenden** (Standard an): Sa/So haben kaum Picks und würden das Bild verwässern.",
        "en": "The heatmap shows **when** picking happens: **one cell = one time window** (weekday × hour), the "
              "**colour = number of picks** in it (light = few, red = many).\n\n"
              "**What is a pick / a movement?** One pick = **one record in the TPA data** = **one order line** (a "
              "pick line) – same as the Throughput tab. *Whether one line equals exactly one order row or one "
              "article is defined in the warehouse system (WMS).*\n\n"
              "**What does “picks per source slot” mean?** By default the heatmap counts **all** picks in the "
              "warehouse. If you **filter slots** in the sidebar, only movements originating from those **source "
              "slots** (`Q_PLATZ` = the slot picked from) are counted – so you see the pick pattern specifically for "
              "the selected slots.\n\n"
              "**Why?** Spot peak times → staff and shift planning.\n\n"
              "**Hide weekend** (on by default): Sat/Sun have hardly any picks and would dilute the picture.",
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
        "de": "**Hochfrequenz-Plätze** — Plätze mit hoher Pick-Frequenz "
              "(`ANZ_PICKS` + `Q_PLATZ`-Count aus Fahrpos). Diese Plätze werden "
              "am häufigsten angefahren und sind oft hoch ausgelastet.",
        "en": "**High-frequency slots** — slots with high pick frequency "
              "(`ANZ_PICKS` + `Q_PLATZ` count from Fahrpos). These slots are "
              "visited most often and are frequently highly utilized.",
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
        "de": "Dieser Tab zeigt die **meistangefahrenen Plätze** – sortiert nach **Picks gesamt** (absteigend). "
              "Das sind die Hot-Spots im Lager.\n\n"
              "**Warum zwei Pick-Spalten?**\n"
              "- **Picks (Stamm)** = `ANZ_PICKS`, die im Lagersystem hinterlegte Zugriffshäufigkeit des Platzes.\n"
              "- **Picks gesamt** = zusätzlich die Anfahrten aus den Fahrpos-Daten (`Q_PLATZ`).\n"
              "Bei vielen Plätzen sind **beide gleich** – dann gab es **keine** zusätzlichen Fahrpos-Anfahrten. "
              "Das ist **kein Fehler**, sondern heißt: die Stamm-Häufigkeit ist hier die einzige Quelle.\n\n"
              "**Was heißt Auslastung 100 % vs. 0 %?** `Ist-LHM / Kapazität × 100`.\n"
              "- **100 %** = der Platz ist **voll**.\n"
              "- **0 %** = der Platz wird zwar **oft angefahren**, ist aber **gerade leer** → typischer "
              "Nachschub-Kandidat (Pickplatz, der nachgefüllt werden muss).",
        "en": "This tab shows the **most-visited slots** – sorted by **total picks** (descending). These are the "
              "warehouse hot spots.\n\n"
              "**Why two pick columns?**\n"
              "- **Picks (master)** = `ANZ_PICKS`, the access frequency of the slot stored in the warehouse system.\n"
              "- **Total picks** = plus visits from the Fahrpos data (`Q_PLATZ`).\n"
              "For many slots **both are equal** – then there were **no** extra Fahrpos visits. That is **not an "
              "error**; it means the master frequency is the only source here.\n\n"
              "**What does utilization 100 % vs. 0 % mean?** `Ist-LHM / capacity × 100`.\n"
              "- **100 %** = the slot is **full**.\n"
              "- **0 %** = the slot is **visited often** but is **currently empty** → a typical replenishment "
              "candidate (a pick slot to be refilled).",
    },
    "free_intro": {
        "de": "**Free Capacity** — Plätze mit Restkapazität, sortiert nach "
              "`MAX_LHM − IST_LHM`.",
        "en": "**Free capacity** — slots with remaining capacity, sorted by "
              "`MAX_LHM − IST_LHM`.",
    },
    "free_info_t": {
        "de": "ℹ️ Was bedeutet das? (Free Capacity + Spalten)",
        "en": "ℹ️ What does this mean? (free capacity + columns)",
    },
    "free_info_b": {
        "de": "Dieser Tab zeigt **Plätze mit Restkapazität** (`Frei (LHM) > 0`), sortiert nach der **größten Lücke "
              "zuerst** – also wo noch Ware reinpasst.\n\n"
              "**Warum ist „Kapazität (max. LHM)“ manchmal 2 (oder mehr) und nicht 1?** `MAX_LHM` ist die "
              "**maximale Anzahl Ladehilfsmittel (Paletten/Behälter), die der Platz fasst** – ein Platz kann "
              "baulich **mehrere** LHM aufnehmen (z. B. zwei Paletten hinter-/nebeneinander). Das ist **kein "
              "Fehler**, sondern die echte Platzkapazität.\n\n"
              "**Was heißt Auslastung 0 %?** `Ist-LHM / Kapazität × 100`. **0 %** = der Platz ist **ganz leer** "
              "(volle Restkapazität). Ein freier Platz liegt immer **unter 100 %**.\n\n"
              "**Spalten:** **Kapazität** = wie viel max. reinpasst · **Belegt** = wie viel schon drinsteht · "
              "**Frei** = wie viel noch reinpasst · **Auslastung %** = wie voll der Platz schon ist.",
        "en": "This tab shows **slots with remaining capacity** (`Free (LHM) > 0`), sorted by the **largest gap "
              "first** – i.e. where goods still fit.\n\n"
              "**Why is “Capacity (max. LHM)” sometimes 2 (or more) and not 1?** `MAX_LHM` is the **maximum number "
              "of load units (pallets/bins) the slot holds** – a slot can physically take **several** units (e.g. "
              "two pallets). That is **not an error**, it is the real slot capacity.\n\n"
              "**What does utilization 0 % mean?** `Ist-LHM / capacity × 100`. **0 %** = the slot is **completely "
              "empty** (full remaining capacity). A free slot is always **below 100 %**.\n\n"
              "**Columns:** **Capacity** = max that fits · **Occupied** = what is already in · **Free** = what still "
              "fits · **Utilization %** = how full the slot already is.",
    },
    "free_count": {"de": "Plätze mit freier Kapazität", "en": "Slots with free capacity"},
    "free_total": {"de": "Freie LHM gesamt", "en": "Total free LHM"},
    "free_avg": {"de": "Ø freie LHM/Platz", "en": "Avg. free LHM/slot"},
    "free_byhall": {"de": "Freie Kapazität (LHM) je Halle", "en": "Free capacity (LHM) per hall"},
    # Maßnahmen
    "reloc_head": {
        "de": "### 🔄 Umlagern\nDatenbasierte Umlager-Vorschläge.",
        "en": "### 🔄 Relocate\nData-driven relocation suggestions (same logic as the app).",
    },
    "reloc_info_t": {
        "de": "ℹ️ Was bedeutet Umlagern? (Regeln + Spalten)",
        "en": "ℹ️ What is relocation? (rules + columns)",
    },
    "reloc_info_b": {
        "de": "**Umlagern** = einen Artikel von einem **schlechten auf einen besseren Platz** bringen – **ohne** "
              "dass neue Ware reinkommt. Ziel: Premium-Plätze (A, niedrige Ebene) für Schnelldreher frei machen.\n\n"
              "**So entstehen die Listen (Filter-Regeln, alle Kriterien stehen als Spalte):**\n"
              "1. **Premium ungenutzt** – Platz ist **A**, hat aber **0 Picks** → wertvoller Platz steht brach. "
              "→ Inhalt auf einen Reserve-Platz (höhere Ebene) umlagern.\n"
              "2. **Heiße C-Plätze** – Platz ist **C**, hat aber **≥ Regler-Schwelle Picks** → falsch eingestuft / "
              "am falschen Ort. → auf einen guten Pickplatz (niedrige Ebene) holen.\n"
              "3. **A weit oben** – **A**-Platz mit Picks, aber **Ebene ≥ Regler** → ergonomisch ungünstig "
              "(Hochhub). → nach unten holen.\n\n"
              "**Zielplatz-Vorschlag** = ein konkreter freier Platz, der passt (niedrige Ebene für heiße/hohe A, "
              "Reserve oben für ungenutzte A); 1:1 nach freier Kapazität zugeordnet.\n\n"
              "**Spalte „Wert (Bedeutung)“** = `Kapazität × Picks` (MAX_LHM × ANZ_PICKS): grobes Maß, wie viel an "
              "einem Platz „los“ ist.",
        "en": "**Relocation** = move an article from a **worse to a better slot** – **without** new goods coming "
              "in. Goal: free up premium slots (A, low level) for fast movers.\n\n"
              "**How the lists are built (filter rules, every criterion is a column):**\n"
              "1. **Premium unused** – slot is **A** but has **0 picks** → a valuable slot lies idle. → move its "
              "content to a reserve slot (higher level).\n"
              "2. **Hot C slots** – slot is **C** but has **≥ slider threshold picks** → misclassified / wrong "
              "place. → bring to a good pick slot (low level).\n"
              "3. **A high up** – **A** slot with picks but **level ≥ slider** → ergonomically poor (lifting). → "
              "bring down.\n\n"
              "**Suggested target slot** = a concrete free slot that fits (low level for hot/high A, reserve up for "
              "unused A); matched 1:1 by free capacity.\n\n"
              "**Column “Value”** = `capacity × picks` (MAX_LHM × ANZ_PICKS): a rough measure of how much is going "
              "on at a slot.",
    },
    "reloc_abc_help": {
        "de": "Welche Klassen anzeigen: A blendet „Premium ungenutzt“ + „A weit "
              "oben“ ein, C die „Heißen C-Plätze“.",
        "en": "Which classes to show: A reveals ‘premium unused’ + ‘A high up’, "
              "C the ‘hot C slots’.",
    },
    "reloc_pick_abc": {
        "de": "Mindestens eine ABC-Klasse auswählen.",
        "en": "Select at least one ABC class.",
    },
    "col_vorschlag": {"de": "Vorschlag", "en": "Suggestion"},
    "col_ziel": {"de": "Zielplatz-Vorschlag", "en": "Suggested target slot"},
    "ziel_none": {
        "de": "kein freier Zielplatz in Auswahl",
        "en": "no free target slot in selection",
    },
    "reloc_unusedA_v": {
        "de": "Ware auf C-/Reserveplatz umlagern – Premiumplatz freimachen",
        "en": "Move goods to a C/reserve slot – free up the premium spot",
    },
    "reloc_hotC_v": {
        "de": "Auf A-Platz / niedrige Ebene hochlagern + ABC hochstufen",
        "en": "Move up to an A slot / low level + promote ABC",
    },
    "reloc_highA_v": {
        "de": "Auf niedrige Ebene umlagern – kürzere Wege",
        "en": "Move down to a low level – shorter travel",
    },
    "sl_hotc": {"de": "Heiße C-Plätze ab Picks", "en": "Hot C slots from picks"},
    "sl_highlevel": {"de": "Hohe Ebene ab", "en": "High level from"},
    "reloc_unusedA_t": {"de": "Premium-Plätze ungenutzt", "en": "Premium slots unused"},
    "reloc_unusedA_d": {
        "de": "A-Klasse, aber 0 Picks – Premium-Platz nicht genutzt.",
        "en": "A class but 0 picks – premium slot unused.",
    },
    "reloc_hotC_t": {"de": "Heiße C-Plätze", "en": "Hot C slots"},
    "reloc_hotC_d": {
        "de": "C-Klasse mit hoher Pickfrequenz – Klasse anpassen.",
        "en": "C class with high pick frequency – reclassify.",
    },
    "reloc_highA_t": {"de": "A-Plätze auf hoher Ebene", "en": "A slots on high level"},
    "reloc_highA_d": {
        "de": "A-Klasse weit oben & aktiv – nach unten holen.",
        "en": "A class high up & active – bring down.",
    },
    "replen_head": {
        "de": "### ⬆️ Nachschub / Replenishment\n**Welche Pickplätze sind leer und sollten nachgefüllt werden?** "
              "Gelistet werden **ganz leere** Plätze (`IST_LHM = 0`) in der **Pickzone** (niedrige Ebenen), "
              "sortiert nach **Dringlichkeit**.",
        "en": "### ⬆️ Replenishment\n**Which pick slots are empty and should be refilled?** "
              "The lists show **completely empty** slots (`IST_LHM = 0`) in the **pick zone** (low levels), "
              "ranked by **urgency**.",
    },
    "replen_principle": {
        "de": "**Warum dieser Tab?** Ein leerer, aber häufig gepickter Platz bedeutet **Fehlmengen / Suchwege**: "
              "Der Kommissionierer steht vor einem leeren Fach. Je öfter der Platz sonst gepickt wird und je länger "
              "er schon leer ist, desto dringender der Nachschub. Die wichtigen (häufig gepickten) Plätze werden "
              "**nach Aktualität getrennt**: *Dringend (frisch)* = wichtig + kürzlich noch gepickt → akute Nachfrage; "
              "*Überfällig (vernachlässigt)* = wichtig, aber schon länger kein Pick → vor dem Absterben auffüllen; "
              "*Mittlere Frequenz* = leer, aber seltener gepickt. Gesperrte Plätze sind bewusst ausgeschlossen. "
              "**Wichtig:** Über den Regler *„Aktiv …“* werden nur Plätze gezeigt, an denen **kürzlich** gepickt "
              "wurde – seit Monaten unberührte Fächer (hohe HISTORISCHE Picks, aber tot) werden ausgeblendet und "
              "oben als Hinweis gezählt.",
        "en": "**Why this tab?** An empty but frequently picked slot means **shortages / search time**: "
              "the picker faces an empty bin. The more often the slot is otherwise picked and the longer it has "
              "been empty, the more urgent the replenishment. The three lists form an **escalation**: "
              "the important (frequently picked) slots are **split by recency**: *Urgent (fresh)* = important + "
              "picked recently → active demand; *Overdue (neglected)* = important but no pick for a while → refill "
              "before it dies; *Medium frequency* = empty, but picked less often. Locked slots are deliberately excluded. "
              "**Note:** the *‘Active …’* slider shows only slots picked **recently** – locations untouched for "
              "months (high HISTORICAL picks but dead) are hidden and counted as a note above.",
    },
    "replen_overview": {
        "de": "#### 🔎 Überblick (aktuelle Filter & Regler)",
        "en": "#### 🔎 Overview (current filters & sliders)",
    },
    "replen_kpi_total": {
        "de": "Leere Pickplätze (aktiv)",
        "en": "Empty pick slots (active)",
    },
    "replen_glossary_t": {
        "de": "ℹ️ Was bedeuten „leer“, „Pick“ und die Spalten?",
        "en": "ℹ️ What do ‘empty’, ‘pick’ and the columns mean?",
    },
    "replen_glossary_b": {
        "de": "- **Leer** = **ganz leer**: `IST_LHM = 0`, es steht **kein** Ladehilfsmittel (Palette/Behälter) am Platz. "
              "*Teilweise* gefüllte Plätze (noch Restkapazität, aber Ware vorhanden) stehen **nicht** hier, sondern im "
              "Tab **Einlagern / Free Capacity**.\n"
              "- **Pick (Spalte „Picks (Häufigkeit)“)** = `ANZ_PICKS`, die im WMS hinterlegte **Zugriffshäufigkeit "
              "dieses Platzes** (wie oft an diesem Ort entnommen wurde). Es ist ein **Platz-Zähler**, nicht der "
              "aktuelle Bestand. *Hinweis: ob ein Zugriff genau 1 Orderzeile oder 1 Artikel zählt, ist im WMS-Stamm "
              "definiert und sollte beim Betreiber bestätigt werden.*\n"
              "- **ABC (Platz)** = im WMS hinterlegte **Güteklasse des Ortes** (A = wegoptimaler Premiumplatz). "
              "Beschreibt den **Platz**, wird hier **nicht** aus Picks berechnet.\n"
              "- **Soll-LHM** = `MAX_LHM` = auf wie viele Ladehilfsmittel der Platz **aufgefüllt** werden soll.\n"
              "- **Tage leer** = `DAYS_EMPTY`, Tage seit dem Leer-Datum (`LEER_DATUM`). Bei manchen Plätzen leer.\n"
              "- **Tage seit letztem Pick** = `ZUGRIFF_DATUM`, zweites Staleness-Signal (besser gefüllt als das "
              "Leer-Datum): *kürzlich gepickt + leer* = vergessener Nachschub; *lange kein Pick* = evtl. totes Fach.\n"
              "- **Vorschlag** = **abgeleitete** Handlung, kein fester Text: Dringlichkeit aus der Listenregel, "
              "Menge = **Soll-LHM** (Platz leer → auf Soll auffüllen), bei *Überfällig* zusätzlich die Tage leer.\n\n"
              "Eine **Wert-Spalte** (`MAX_LHM × Picks`) gibt es hier bewusst **nicht** – die Dringlichkeit ergibt "
              "sich allein aus **Pickhäufigkeit** und **Tage leer/ohne Pick**. *(`ANZ_NACHSCHUB` aus dem WMS ist in "
              "diesen Daten durchgehend 0 und daher nicht verwertbar.)*",
        "en": "- **Empty** = **completely empty**: `IST_LHM = 0`, **no** load unit (pallet/bin) at the slot. "
              "*Partially* filled slots (spare capacity but goods present) are **not** here but in the "
              "**Put-away / Free Capacity** tab.\n"
              "- **Pick (column ‘Picks (frequency)’)** = `ANZ_PICKS`, the **access frequency of this slot** stored "
              "in the WMS (how often it was picked from this location). It is a **slot counter**, not the current "
              "stock. *Note: whether one access counts as 1 order line or 1 article is defined in the WMS master and "
              "should be confirmed with the operator.*\n"
              "- **ABC (slot)** = the **quality class of the location** stored in the WMS (A = path-optimal premium "
              "slot). Describes the **slot**, **not** computed from picks here.\n"
              "- **Soll-LHM** = `MAX_LHM` = the number of load units the slot should be **refilled** to.\n"
              "- **Days empty** = `DAYS_EMPTY`, days since the empty date (`LEER_DATUM`).\n\n"
              "There is deliberately **no value column** (`MAX_LHM × picks`) here – urgency comes solely from "
              "**pick frequency** and **days empty**.",
    },
    "sl_picklevel": {"de": "Max. Ebene (Pickzone)", "en": "Max. level (pick zone)"},
    "sl_picklevel_h": {
        "de": "Nur Plätze bis zu dieser Ebene gelten als Pickzone. Höher = Reserve, "
              "die nicht zwingend ständig gefüllt sein muss.",
        "en": "Only slots up to this level count as the pick zone. Higher = reserve "
              "that need not always be stocked.",
    },
    "sl_pickthresh": {"de": "Dringend ab Picks", "en": "Urgent from picks"},
    "sl_pickthresh_h": {
        "de": "Ab so vielen Picks (Zugriffshäufigkeit des Platzes) zählt ein leerer "
              "Platz als „dringend“ – ein wichtiger Pickplatz steht leer.",
        "en": "From this many picks (slot access frequency) an empty slot counts as "
              "‘urgent’ – an important pick slot is empty.",
    },
    "sl_overdue": {"de": "Überfällig ab Tagen ohne Pick",
                   "en": "Overdue from days without pick"},
    "sl_overdue_h": {
        "de": "Grenze zwischen „dringend“ und „überfällig“: Ein wichtiger leerer Platz, "
              "an dem seit mehr als so vielen Tagen NICHT gepickt wurde (ZUGRIFF_DATUM), "
              "gilt als überfällig/vernachlässigt; darunter als frisch-dringend.",
        "en": "Threshold between ‘urgent’ and ‘overdue’: an important empty slot not "
              "picked (ZUGRIFF_DATUM) for more than this many days counts as "
              "overdue/neglected; below it as freshly urgent.",
    },
    "sl_active": {"de": "Aktiv: zuletzt gepickt vor max. Tagen",
                  "en": "Active: last picked within days"},
    "sl_active_h": {
        "de": "Nur Plätze berücksichtigen, an denen in diesem Zeitraum zuletzt "
              "gepickt wurde (ZUGRIFF_DATUM). Trennt echte Nachfüll-Kandidaten von "
              "lange ungenutzten/toten Fächern (hohe HISTORISCHE Picks, aber seit "
              "Monaten kein Zugriff).",
        "en": "Only consider slots last picked within this window (ZUGRIFF_DATUM). "
              "Separates genuine refill candidates from long-unused/dead locations "
              "(high HISTORICAL picks but no access for months).",
    },
    "replen_inactive_note": {
        "de": "ℹ️ **{n} leere Plätze ausgeblendet**, weil seit > {d} Tagen kein Pick "
              "(oder kein Zugriffsdatum) – wahrscheinlich **tote Fächer**, kein akuter "
              "Nachschub. Regler „Aktiv …“ erhöhen, um sie einzubeziehen.",
        "en": "ℹ️ **{n} empty slots hidden** because not picked for > {d} days (or no "
              "access date) – likely **dead locations**, not urgent replenishment. "
              "Increase the ‘Active …’ slider to include them.",
    },
    "replen_urgent_t": {"de": "Dringend leer (frisch)", "en": "Urgently empty (fresh)"},
    "replen_urgent_d": {
        "de": "Wichtiger Platz, leer, aber **kürzlich** noch gepickt (≤ {n} T) – "
              "akute Nachfrage, sofort nachfüllen.",
        "en": "Important slot, empty, but picked **recently** (≤ {n} d) – "
              "active demand, refill now.",
    },
    "replen_urgent_v": {
        "de": "Sofort auffüllen (Soll {x} LHM) – wichtiger Pickplatz leer",
        "en": "Refill now (target {x} LU) – important pick slot empty",
    },
    "replen_overdue_t": {"de": "Überfällig (vernachlässigt)",
                         "en": "Overdue (neglected)"},
    "replen_overdue_d": {
        "de": "Wichtiger Platz, leer und seit **> {n} Tagen kein Pick** mehr – "
              "vernachlässigt; auffüllen, bevor das Fach ganz abstirbt.",
        "en": "Important slot, empty and **not picked for > {n} days** – "
              "neglected; refill before the location dies off.",
    },
    "replen_overdue_v": {
        "de": "Priorisiert auffüllen (Soll {x} LHM) – seit {d} T kein Pick, Ursache prüfen",
        "en": "Refill with priority (target {x} LU) – no pick for {d} d, check cause",
    },
    "replen_medium_t": {"de": "Mittlere Frequenz", "en": "Medium frequency"},
    "replen_medium_d": {
        "de": "Leer mit mittlerer Pickhäufigkeit – einplanen, aber weniger dringend.",
        "en": "Empty with medium pick frequency – schedule, but less urgent.",
    },
    "replen_medium_v": {
        "de": "Bei nächster Tour auffüllen (Soll {x} LHM)",
        "en": "Refill on next round (target {x} LU)",
    },
    "put_head": {
        "de": "### 📥 Einlagern / Putaway\n**Wohin mit eingehender Ware?** Die Listen zeigen **freie Plätze** "
              "(`freie Kapazität > 0`), sortiert nach Eignung – Schnelldreher nach vorne/unten, Reserve nach hinten/oben.",
        "en": "### 📥 Put-away\n**Where to store incoming goods?** The lists show **free slots** "
              "(`free capacity > 0`), ranked by suitability – fast movers to the front/low, reserve to the back/high.",
    },
    "put_principle": {
        "de": "**Warum dieser Tab?** Jeder Pick kostet Weg. Schnelldreher gehören deshalb auf wegoptimale "
              "**A-Plätze auf niedriger Ebene** (kurze Greifwege, kein Hochhub); Langsamdreher dürfen weiter oben/hinten "
              "als Reserve stehen. So sinkt die mittlere Wegzeit pro Pick. Gesperrte Plätze werden bewusst ausgeschlossen.",
        "en": "**Why this tab?** Every pick costs travel. Fast movers therefore belong in path-optimal "
              "**A slots on low levels** (short reach, no lifting); slow movers may sit higher/further back as reserve. "
              "This lowers the average travel time per pick. Locked slots are deliberately excluded.",
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
        "de": "**Warum zwei Kriterien (ABC = A *und* niedrige Ebene)?** Das sind zwei **getrennte Wegkosten:**\n"
              "- **ABC = A** = wegoptimaler **Ort** (horizontale Nähe zum I-Punkt/Wareneingang, im WMS gepflegt) → kurzer Fahrweg.\n"
              "- **Niedrige Ebene** = Greifhöhe ohne Hochhub → kein Zeitverlust durch Heben/Stapler.\n"
              "Erst beides zusammen macht einen Platz wirklich schnell.",
        "en": "**Why two criteria (ABC = A *and* low level)?** These are two **separate travel costs:**\n"
              "- **ABC = A** = path-optimal **location** (horizontal proximity to the I-point/goods-in, maintained in the WMS) → short drive.\n"
              "- **Low level** = reach height without lifting → no time lost to a forklift.\n"
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
        "de": "Freie Gesamt-Kapazität: **{n} LHM** (so viele Ladehilfsmittel passen über alle nutzbaren freien Plätze noch rein).",
        "en": "Total free capacity: **{n} LHM** (load units that still fit across all usable free slots).",
    },
    "put_glossary_b": {
        "de": "- **ABC (Platz)** = im WMS hinterlegte **Güteklasse des Ortes** (A = wegoptimaler Premiumplatz). "
              "Beschreibt den **Platz**, wird hier **nicht** aus Picks berechnet.\n"
              "- **Kapazität (max. LHM)** = `MAX_LHM` = maximale Anzahl Ladehilfsmittel (Paletten/Behälter), die der "
              "Platz fasst – kann > 1 sein.\n"
              "- **Belegt (Ist-LHM)** = `IST_LHM` = wie viele Ladehilfsmittel aktuell schon dort stehen.\n"
              "- **Frei (LHM)** = `MAX_LHM − IST_LHM` = wie viele LHM noch reinpassen. Hier zählt **frei = teilweise "
              "ODER ganz frei** (alles mit Restkapazität > 0). **Ganz leere** Plätze (`IST_LHM = 0`) findest du im Tab "
              "**Nachschub**.\n"
              "- **Auslastung %** = `Ist-LHM / Kapazität × 100`. 0 % = ganz leer, 100 % = voll; ein freier Platz liegt < 100 %.",
        "en": "- **ABC (slot)** = the **quality class of the location** stored in the WMS (A = path-optimal premium slot). "
              "Describes the **slot**, **not** computed from picks here.\n"
              "- **Capacity (max. LHM)** = `MAX_LHM` = max number of load units (pallets/bins) the slot holds – can be > 1.\n"
              "- **Occupied (Ist-LHM)** = `IST_LHM` = how many load units are already there.\n"
              "- **Free (LHM)** = `MAX_LHM − IST_LHM` = how many more units fit. Here **free = partially OR fully free** "
              "(anything with spare capacity > 0). **Completely empty** slots (`IST_LHM = 0`) are in the **Replenishment** tab.\n"
              "- **Utilization %** = `Ist-LHM / capacity × 100`. 0 % = empty, 100 % = full; a free slot is < 100 %.",
    },
    "put_rowhint": {
        "de": "Jede Zeile = 1 **freier** Lagerplatz (Kandidat für eingehende Ware), sortiert nach freier Kapazität.",
        "en": "Each row = 1 **free** slot (candidate for incoming goods), sorted by free capacity.",
    },
    "put_blocked_rowhint": {
        "de": "Jede Zeile = 1 Platz, der **frei wäre, aber gesperrt ist** – käme als Ziel infrage, darf aber **nicht** bestückt werden.",
        "en": "Each row = 1 slot that **would be free but is locked** – a possible target, but must **not** be stocked.",
    },
    "sl_fastlevel": {"de": "Fast-Lane bis Ebene", "en": "Fast lane up to level"},
    "sl_fastlevel_h": {
        "de": "Bis zu dieser Ebene gilt ein freier A-Platz als „Fast-Lane“ (kurze Wege). "
              "Höher = mehr Plätze, aber längere Greifwege.",
        "en": "Up to this level a free A slot counts as ‘fast lane’ (short paths). "
              "Higher = more slots but longer reach.",
    },
    "sl_reservelevel": {"de": "Reserve-Ebene ab", "en": "Reserve level from"},
    "sl_reservelevel_h": {
        "de": "Ab dieser Ebene gelten freie Nicht-A-Plätze als Reserve für Langsamdreher.",
        "en": "From this level free non-A slots count as reserve for slow movers.",
    },
    "put_logic_t": {
        "de": "ℹ️ Wie entsteht der Vorschlag?",
        "en": "ℹ️ How is the suggestion derived?",
    },
    "put_logic_b": {
        "de": "Der **Vorschlag** ist keine Einzelfall-Bewertung – er ergibt sich direkt daraus, in **welche "
              "Kategorie** ein Platz fällt. Die Filterregel **ist** die Empfehlung. Alle Kriterien stehen als "
              "Spalte in der Tabelle, der Vorschlag ist also nachprüfbar:\n\n"
              "1. **Schnelldreher-Plätze** → *„Schnelldreher hier einlagern“*\n"
              "   Platz ist **frei** (`Frei > 0`) **und** ABC (Platz) = **A** **und** Ebene **≤** dem Regler "
              "„Fast-Lane bis Ebene“ **und** nicht gesperrt. Sortiert nach **Frei** absteigend (größte Lücke zuerst).\n"
              "2. **Reserve** → *„Langsamdreher/Reserve hier einlagern“*\n"
              "   Platz ist **frei** **und** ABC (Platz) **≠ A** **und** Ebene **≥** dem Regler „Reserve-Ebene ab“ "
              "**und** nicht gesperrt. Sortiert nach **Frei** absteigend.\n"
              "3. **Gesperrt** → *„Nicht einlagern“*\n"
              "   Platz wäre frei, ist aber **gesperrt** (Sperrkennzeichen gesetzt) – darf nicht bestückt werden.\n\n"
              "Die beiden Ebenen-Schwellen stellst du **unten mit den Reglern** ein; die Listen aktualisieren sich sofort.",
        "en": "The **suggestion** is not a case-by-case score – it follows directly from **which category** a slot "
              "falls into. The filter rule **is** the recommendation, and every criterion is shown as a column, so "
              "it is verifiable:\n\n"
              "1. **Fast-mover slots** → *“Store fast movers here”*\n"
              "   Slot is **free** (`Free > 0`) **and** ABC (slot) = **A** **and** level **≤** the “Fast lane up to "
              "level” slider **and** not locked. Sorted by **Free** descending (largest gap first).\n"
              "2. **Reserve** → *“Store slow movers/reserve here”*\n"
              "   Slot is **free** **and** ABC (slot) **≠ A** **and** level **≥** the “Reserve level from” slider "
              "**and** not locked. Sorted by **Free** descending.\n"
              "3. **Locked** → *“Do not put away”*\n"
              "   Slot would be free but is **locked** (lock flag set) – must not be stocked.\n\n"
              "The two level thresholds are set **with the sliders below**; the lists update instantly.",
    },
    "put_fast_t": {"de": "Schnelldreher-Plätze", "en": "Fast-mover slots"},
    "put_fast_d": {
        "de": "Freie **A-Plätze bis Ebene {n}**: wegoptimal und auf Greifhöhe → kürzeste Wege. Hier gehören "
              "**Schnelldreher** hin, weil sie am häufigsten gepickt werden – kurze Wege sparen hier am meisten Zeit.",
        "en": "Free **A slots up to level {n}**: path-optimal and at reach height → shortest paths. **Fast movers** "
              "belong here because they are picked most often – short paths save the most time here.",
    },
    "put_fast_v": {
        "de": "Hier bis zu {x} LHM einlagern (Schnelldreher, kurze Wege)",
        "en": "Store up to {x} LHM here (fast mover, short paths)",
    },
    "put_reserve_t": {"de": "Reserve (hohe Ebenen)", "en": "Reserve (high levels)"},
    "put_reserve_d": {
        "de": "Freie **Nicht-A-Plätze ab Ebene {n}** (weiter oben/hinten): längere Wege, aber für **Langsamdreher / "
              "Reserve** völlig ok – so bleiben die knappen A-Plätze für die Schnelldreher frei.",
        "en": "Free **non-A slots from level {n}** (higher/further back): longer paths, but fine for **slow movers / "
              "reserve** – this keeps the scarce A slots free for fast movers.",
    },
    "put_reserve_v": {
        "de": "Hier bis zu {x} LHM einlagern (Langsamdreher / Reserve)",
        "en": "Store up to {x} LHM here (slow mover / reserve)",
    },
    "put_blocked_t": {"de": "Gesperrt – nicht bestücken", "en": "Locked – do not stock"},
    "put_blocked_d": {
        "de": "Plätze, die **freie Kapazität haben, aber gesperrt sind** (Sperrkennzeichen, z. B. Inventur/Defekt/"
              "reserviert) – sie *kämen als Ziel infrage*, dürfen aber **nicht** bestückt werden. Voll belegte "
              "Sperrplätze sind hier bewusst ausgeblendet (kein Einlager-Ziel).",
        "en": "Slots that **have free capacity but are locked** (lock flag, e.g. stocktake/defect/reserved) – they "
              "*would be candidates* but must **not** be stocked. Fully occupied locked slots are deliberately hidden "
              "(not a put-away target).",
    },
    "put_blocked_v": {
        "de": "Nicht einlagern – Sperre prüfen",
        "en": "Do not store – check lock",
    },
    "retr_head": {
        "de": "### 📤 Auslagern / Retrieval\nLangsamdreher/Ladenhüter, die gute Plätze blockieren und ausgelagert werden sollten.",
        "en": "### 📤 Retrieval\nSlow movers/dead stock blocking good slots that should be retrieved.",
    },
    "retr_info_t": {
        "de": "ℹ️ Was bedeutet Auslagern? (Regeln + Spalten)",
        "en": "ℹ️ What is retrieval? (rules + columns)",
    },
    "retr_info_b": {
        "de": "**Auslagern** = Ware, die einen **guten Platz blockiert, sich aber kaum/nicht bewegt**, aus der "
              "Pickzone entfernen (ins Reserve-/Hochlager oder raus). So werden gute Plätze für Dreher frei.\n\n"
              "Betrachtet werden nur **belegte** Plätze (`Belegt > 0`) in der **Pickzone** (bis zur eingestellten "
              "Ebene).\n\n"
              "**Die drei Listen:**\n"
              "1. **Kritisch** – **A**-Platz belegt, aber **0 Picks** → Premium-Platz von einem Ladenhüter "
              "blockiert. Vorrangig auslagern.\n"
              "2. **Abgestanden** – belegt, **0 Picks**, aber **kein** A-Platz → bewegt sich nicht, Auslagern "
              "prüfen.\n"
              "3. **Beobachten** – belegt, aber **sehr selten** gepickt (1 bis Regler-Wert) → im Auge behalten.\n\n"
              "**Was heißt „belegt“?** `Ist-LHM > 0` (mind. ein Ladehilfsmittel steht drauf). **Was heißt „Wert“?** "
              "`Kapazität × Picks` – bei **0 Picks ist der Wert 0**, genau das Signal für „blockiert ohne Nutzen“.",
        "en": "**Retrieval** = remove goods that **block a good slot but barely move** from the pick zone (to "
              "reserve/high-bay or out). This frees good slots for movers.\n\n"
              "Only **occupied** slots (`Occupied > 0`) in the **pick zone** (up to the set level) are "
              "considered.\n\n"
              "**The three lists:**\n"
              "1. **Critical** – **A** slot occupied but **0 picks** → premium slot blocked by dead stock. Retrieve "
              "first.\n"
              "2. **Stale** – occupied, **0 picks**, but **not** an A slot → not moving, consider retrieval.\n"
              "3. **Observe** – occupied but **very rarely** picked (1 to slider value) → keep an eye on it.\n\n"
              "**What does “occupied” mean?** `Ist-LHM > 0` (at least one load unit present). **What does “value” "
              "mean?** `capacity × picks` – with **0 picks the value is 0**, exactly the signal for “blocked "
              "without use”.",
    },
    "sl_retrzone": {"de": "Pickzone bis Ebene", "en": "Pick zone up to level"},
    "sl_observe": {"de": "„Beobachten“ bis Picks", "en": "‘Observe’ up to picks"},
    "retr_crit_t": {"de": "Kritisch", "en": "Critical"},
    "retr_crit_d": {
        "de": "A-Platz belegt, aber 0 Picks – Premium-Platz von Ladenhüter blockiert.",
        "en": "A slot occupied but 0 picks – premium slot blocked by dead stock.",
    },
    "retr_stale_t": {"de": "Abgestanden", "en": "Stale"},
    "retr_stale_d": {
        "de": "Belegt mit 0 Picks – bewegt sich nicht, Auslagern prüfen.",
        "en": "Occupied with 0 picks – not moving, consider retrieval.",
    },
    "retr_observe_t": {"de": "Beobachten", "en": "Observe"},
    "retr_observe_d": {
        "de": "Belegt mit sehr geringer Frequenz (1–{n} Picks).",
        "en": "Occupied with very low frequency (1–{n} picks).",
    },
    "abc_intro": {
        "de": "**ABC-Analyse** — kumulative Verteilung von `ANZ_PICKS`. "
              "A = Plätze bis {a} % aller Picks, B = bis {b} %, C = Rest "
              "(passt sich den Reglern oben an).",
        "en": "**ABC analysis** — cumulative distribution of `ANZ_PICKS`. "
              "A = slots up to {a}% of all picks, B = up to {b}%, C = rest "
              "(follows the sliders above).",
    },
    "abc_chart": {"de": "ABC-Verteilung (berechnet)", "en": "ABC distribution (calculated)"},
    "abc_cross_intro": {
        "de": "**Stamm-ABC vs. berechnet** — Zeilen = hinterlegte `ABC_KLASSE`, "
              "Spalten = aus Picks berechnete `ABC_CALC`. Werte abseits der "
              "Diagonale sind Kandidaten für eine ABC-Anpassung.",
        "en": "**Master ABC vs. calculated** — rows = stored `ABC_KLASSE`, "
              "columns = `ABC_CALC` from picks. Off-diagonal values are "
              "candidates for an ABC adjustment.",
    },
    "abc_byfreq": {"de": "**📋 Tabelle 2: Alle Einträge nach Pickhäufigkeit**",
                   "en": "**📋 Table 2: All entries by pick frequency**"},
    "abc_byfreq_note": {
        "de": "Die **komplette** Liste, sortiert nach Picks (häufigste oben). "
              "**Stamm** = im Lagersystem hinterlegte Klasse · **Berechnet** = aus "
              "den Picks · **kumul. Pick-%** = Anteil aller Picks bis zu dieser Zeile.",
        "en": "The **full** list, sorted by picks (most-picked on top). "
              "**Master** = class stored in the warehouse system · **Calculated** = "
              "from picks · **cum. pick %** = share of all picks down to this row.",
    },
    "abc_explain_head": {
        "de": "ℹ️ Was bedeutet das? (Wozu ABC, Modi, Klassen)",
        "en": "ℹ️ What does this mean? (purpose, modes, classes)",
    },
    "abc_mode": {"de": "ABC berechnen nach", "en": "Compute ABC by"},
    "abc_by_slots": {"de": "Lagerplätzen", "en": "Storage slots"},
    "abc_by_articles": {"de": "Artikeln", "en": "Articles"},
    "abc_purpose": {
        "de": "**Wozu ABC?** Sortiert nach Wichtigkeit: **A** = Renner (häufig "
              "gepickt) → gehören in gut erreichbare Plätze; **C** = Langsamdreher "
              "→ ab in die Reserve. Ziel: kurze Wege für die wichtigen Artikel.",
        "en": "**Why ABC?** Sorted by importance: **A** = fast movers (picked often) "
              "→ belong in easy-reach slots; **C** = slow movers → into reserve. "
              "Goal: short travel for the important items.",
    },
    "abc_mode_note": {
        "de": "**Nach Artikeln** = klassische ABC (welche *Produkte* sind wichtig). "
              "**Nach Lagerplätzen** = welche *Plätze* werden am häufigsten angefahren.",
        "en": "**By articles** = classic ABC (which *products* matter). "
              "**By storage slots** = which *slots* are visited most often.",
    },
    "abc_c_note": {
        "de": "Hinweis: **C** enthält alle nie/selten gepickten Plätze (inkl. leerer "
              "Reserve) – deshalb ist der C-Anteil bei „nach Lagerplätzen“ so groß.",
        "en": "Note: **C** contains all never/rarely picked slots (incl. empty "
              "reserve) – that's why the C share is so large for ‘by storage slots’.",
    },
    "abc_berech_global": {"de": "Berechnet (Lager gesamt)",
                          "en": "Calculated (whole warehouse)"},
    "abc_berech_sel": {"de": "Berechnet (Auswahl)", "en": "Calculated (selection)"},
    "abc_cum_global": {"de": "kumul. Pick-% (gesamt)", "en": "cum. pick % (whole)"},
    "abc_cum_sel": {"de": "kumul. Pick-% (Auswahl)", "en": "cum. pick % (selection)"},
    "abc_a_thresh": {"de": "A bis % aller Picks", "en": "A up to % of all picks"},
    "abc_b_thresh": {"de": "B bis % aller Picks", "en": "B up to % of all picks"},
    "abc_thresh_note": {
        "de": "A/B/C nach **kumuliertem Pick-Anteil** (Pareto): nach Picks "
              "sortieren, A = die wenigen, die zusammen die ersten **{a} %** aller "
              "Picks ausmachen, B = bis **{b} %**, Rest = C. Verschiebst du die "
              "Regler, ändert sich die Einteilung sofort (Standard 80 / 95 %).",
        "en": "A/B/C by **cumulative pick share** (Pareto): sort by picks, "
              "A = the few accounting for the first **{a}%** of all picks, "
              "B = up to **{b}%**, rest = C. Moving the sliders re-classifies "
              "instantly (default 80 / 95 %).",
    },
    "abc_dist_count": {"de": "Anzahl je Klasse", "en": "Count per class"},
    "abc_dist_share": {"de": "Pick-Anteil je Klasse", "en": "Pick share per class"},
    "abc_bar_title": {"de": "Anteil je Klasse: Plätze vs. Picks",
                      "en": "Share per class: slots vs. picks"},
    "abc_dist_note": {
        "de": "Balkendiagramm: je Klasse der **Anteil der Plätze** (grau) gegen den "
              "**Anteil der Picks** (blau). Genau das ist der ABC-Effekt: wenige "
              "A-Plätze (kleiner grauer Balken) tragen den Großteil der Picks (großer "
              "blauer Balken). Die exakten Zahlen stehen rechts.",
        "en": "Bar chart: per class the **share of slots** (grey) vs. the **share of "
              "picks** (blue). That's the ABC effect: a few A slots (small grey bar) "
              "carry most of the picks (large blue bar). Exact figures on the right.",
    },
    "abc_col_count": {"de": "Anzahl", "en": "Count"},
    "abc_col_share": {"de": "Anteil %", "en": "Share %"},
    "abc_stamm_note": {
        "de": "**Stamm** = die im Lagersystem hinterlegte `ABC_KLASSE`. **Berechnet** = die "
              "**globale** Klasse aus dem kumulierten Pick-Anteil im **ganzen Lager** "
              "(Standard 80 / 95 %, wie in der 3D-Ansicht) – unabhängig von Filter & "
              "Reglern. Der Filter beschränkt nur, welche Zeilen angezeigt werden. "
              "Weichen Stamm und Berechnet ab, ist der Platz ein Kandidat für eine "
              "ABC-Anpassung.",
        "en": "**Master** = the `ABC_KLASSE` stored in the warehouse system. **Calculated** = the "
              "**global** class from the cumulative pick share across the **whole "
              "warehouse** (default 80 / 95 %, like the 3D view) – independent of "
              "filters & sliders. The filter only limits which rows are shown. If "
              "master and calculated differ, the slot is a candidate for an ABC "
              "adjustment.",
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
        "de": "**ABC nach Artikeln** — Artikel nach Bewegungen (TPA). "
              "A = Top-Artikel bis {a} % aller Bewegungen, B = bis {b} %, Rest C "
              "(passt sich den Reglern oben an).",
        "en": "**ABC by articles** — articles by movements (TPA). "
              "A = top articles up to {a}% of all movements, B = up to {b}%, "
              "rest C (follows the sliders above).",
    },
    "abc_dist": {"de": "ABC-Verteilung", "en": "ABC distribution"},
    "abc_count": {"de": "Anzahl je Klasse", "en": "Count per class"},
    "abc_adjust_head": {
        "de": "**🏷️ Tabelle 1: Wo passt die hinterlegte Klasse nicht? (Empfehlungen)**",
        "en": "**🏷️ Table 1: Where doesn't the stored class fit? (recommendations)**",
    },
    "abc_adjust_intro": {
        "de": "**Nur** Plätze, deren **Stamm** (im Lagersystem hinterlegte Klasse) "
              "nicht zur **Berechnet**-Klasse (aus der Pickhäufigkeit) passt. "
              "**⬆️ Hochstufen** = wird öfter gepickt als hinterlegt; "
              "**⬇️ Herabstufen** = seltener.",
        "en": "**Only** slots whose **master** (class stored in the warehouse system) "
              "doesn't match the **calculated** class (from pick frequency). "
              "**⬆️ Promote** = picked more often than recorded; **⬇️ Demote** = "
              "less often.",
    },
    "abc_promote": {"de": "⬆️ Hochstufen", "en": "⬆️ Promote"},
    "abc_demote": {"de": "⬇️ Herabstufen", "en": "⬇️ Demote"},
    "abc_rec": {"de": "Empfehlung", "en": "Recommendation"},
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
        "de": "**Artikel-Detail** — Bewegungen und Quellplätze eines Artikels.",
        "en": "**Article detail** — movements and source slots of an article.",
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
        "de": "**Durchsatz** — Anzahl Lagerbewegungen je Tag (aus den TPA-Daten). "
              "Zeitraum über den Sidebar-Regler einstellbar.",
        "en": "**Throughput** — number of warehouse movements per day (from TPA "
              "data). Period adjustable via the sidebar slider.",
    },
    "tp_info_t": {
        "de": "ℹ️ Was bedeutet das? (Durchsatz + „eine Bewegung“ erklärt)",
        "en": "ℹ️ What does this mean? (throughput + “one movement”)",
    },
    "tp_info_b": {
        "de": "Dieser Tab zählt **Lagerbewegungen je Tag** und zeigt sie als Balken (**ein Balken = ein Tag**).\n\n"
              "**Was zählt als eine Bewegung?** Eine Bewegung = **ein Datensatz in den TPA-Daten** = **eine "
              "Auftragsposition** (eine Position eines Kommissionier-/Transportauftrags, also i. d. R. eine "
              "Entnahme / ein Pick). Mehrere Positionen desselben Auftrags zählen **einzeln**. *Ob eine Position "
              "genau einer Orderzeile oder einem Artikel entspricht, ist im Lagersystem (WMS) definiert und sollte "
              "beim Betreiber bestätigt werden.*\n\n"
              "**Kennzahlen unter dem Diagramm:** **Ø pro Tag** = Durchschnitt über die angezeigten Tage · "
              "**Maximum** = stärkster Einzeltag · **Summe Zeitraum** = alle Bewegungen zusammen.\n\n"
              "**Wochenende ausblenden** (Standard an): Sa/So haben kaum reguläre Bewegungen und würden den Verlauf "
              "mit Tief-/Null-Tagen verzerren – ohne sie ist der Arbeitstag-Verlauf klarer.",
        "en": "This tab counts **warehouse movements per day** and shows them as bars (**one bar = one day**).\n\n"
              "**What counts as one movement?** One movement = **one record in the TPA data** = **one order line** "
              "(a line of a picking/transport order, i.e. usually one pick). Several lines of the same order count "
              "**individually**. *Whether one line equals exactly one order row or one article is defined in the "
              "warehouse system (WMS) and should be confirmed with the operator.*\n\n"
              "**KPIs below the chart:** **Avg. per day** = mean over the shown days · **Maximum** = strongest "
              "single day · **Sum (period)** = all movements together.\n\n"
              "**Hide weekend** (on by default): Sat/Sun have hardly any regular movements and would distort the "
              "trend with low/zero days – without them the working-day trend is clearer.",
    },
    "tp_chart": {"de": "Bewegungen letzte {n} Tage", "en": "Movements last {n} days"},
    "tp_avg": {"de": "Ø pro Tag", "en": "Avg. per day"},
    "tp_max": {"de": "Maximum", "en": "Maximum"},
    "tp_sum": {"de": "Summe Zeitraum", "en": "Sum (period)"},
    "top_intro": {
        "de": "**Top-Artikel** — Artikel mit den meisten Bewegungen (aus den "
              "TPA-Daten). Anzahl über den Sidebar-Regler einstellbar.",
        "en": "**Top items** — items with the most movements (from TPA data). "
              "Count adjustable via the sidebar slider.",
    },
    "top_chart": {"de": "Meistbewegte Artikel", "en": "Most-moved items"},
    "top_info_t": {
        "de": "ℹ️ Was bedeutet das? (Top-Artikel + „eine Bewegung“)",
        "en": "ℹ️ What does this mean? (top items + “one movement”)",
    },
    "top_info_b": {
        "de": "Dieser Tab zeigt die **meistbewegten Artikel** – sortiert nach **Bewegungen** (absteigend); Anzahl "
              "über den Sidebar-Regler einstellbar. So siehst du die echten **Dreher** im Sortiment.\n\n"
              "**Was zählt als eine Bewegung?** Eine Bewegung = **ein Datensatz in den TPA-Daten** = **eine "
              "Auftragsposition** (eine Entnahme / ein Pick) – identisch zum Durchsatz-Tab. *Ob eine Position genau "
              "einer Orderzeile oder einem Artikel entspricht, ist im Lagersystem (WMS) definiert.*\n\n"
              "**Spalten:** **Artikel-Nr** = die Artikelnummer · **Bezeichnung** = Klartext-Name · **Bewegungen** = "
              "wie oft der Artikel im Zeitraum bewegt wurde.\n\n"
              "*Hinweis:* Mit aktivem Sidebar-Platzfilter zählen nur Bewegungen, die von den ausgewählten Plätzen "
              "ausgehen.",
        "en": "This tab shows the **most-moved articles** – sorted by **movements** (descending); count adjustable "
              "via the sidebar slider. This reveals the real **movers** in the assortment.\n\n"
              "**What counts as one movement?** One movement = **one record in the TPA data** = **one order line** "
              "(a pick) – same as the Throughput tab. *Whether one line equals exactly one order row or one article "
              "is defined in the warehouse system (WMS).*\n\n"
              "**Columns:** **Article no.** = the article number · **Description** = plain name · **Movements** = how "
              "often the article was moved in the period.\n\n"
              "*Note:* With an active sidebar slot filter, only movements originating from the selected slots are "
              "counted.",
    },
    "no_data_filters": {
        "de": "Keine Daten mit aktuellen Filtern.",
        "en": "No data with current filters.",
    },
    "mov_filtered": {
        "de": "🔗 Live gefiltert: nur Bewegungen aus den {n} aktuell gewählten Plätzen "
              "(Q_PLATZ). Filter leeren = ganzes Lager.",
        "en": "🔗 Live-filtered: only movements from the {n} currently selected slots "
              "(Q_PLATZ). Clear filters = whole warehouse.",
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
              "runter/hoch, Shift = schneller (erst ins Modell klicken). "
              "Klick auf einen Platz zeigt seine Daten.",
        "en": "Controls: drag = rotate, scroll = zoom, right-drag = pan. "
              "**W A S D = fly through the racks**, Q/E = down/up, Shift = "
              "faster (click into the model first). Click a slot to see its data.",
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
    "d3_click_intro": {
        "de": "**Klickbares 3D-Modell** — auf einen Lagerplatz im Modell klicken, "
              "um seine Kennzahlen rechts zu sehen. Die Plätze sind nach `PLATZ_ID` "
              "benannt und direkt mit der Datenbank verknüpft.",
        "en": "**Clickable 3D model** — click a storage slot in the model to see its "
              "metrics on the right. Slots are named by `PLATZ_ID` and linked "
              "directly to the database.",
    },
    "d3_color_abc": {"de": "Nach ABC einfärben", "en": "Color by ABC"},
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
        "de": "**Daten-Modell** — jeder Lagerplatz der Datenbank als Box, "
              "positioniert nach Regal/Fach/Ebene. Zeigt **alle 22.429 Plätze** "
              "(kein Grau, keine fehlenden Regale), wahlweise eingefärbt nach "
              "Auslastung, Belegung oder ABC.",
        "en": "**Data model** — every database slot as a box, placed by "
              "rack/bin/level. Shows **all 22,429 slots** (no grey, no missing "
              "racks), colored by utilization, occupancy or ABC.",
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
        "de": "9-stellige PLATZ_ID eingeben und Enter – die Karte fliegt zu "
              "diesem Platz und markiert ihn.",
        "en": "Enter a 9-digit PLATZ_ID and press Enter – the map flies to that "
              "slot and highlights it.",
    },
    "d3_notfound": {
        "de": "Platz nicht im Modell gefunden.",
        "en": "Slot not found in the model.",
    },
    "d3_perf": {"de": "Plätze ohne Daten ausblenden", "en": "Hide slots without data"},
    "d3_perf_help": {
        "de": "Blendet die grauen Plätze aus, für die es keinen DB-Datensatz "
              "gibt (Modell-Luftplätze). Standardmäßig an – sauberer und "
              "flüssiger. Es gehen keine Daten verloren.",
        "en": "Hides the grey slots that have no DB record (model-only). On by "
              "default – cleaner and smoother. No data is lost.",
    },
    # --- Erklaerungen/Beschriftungen (Lehrer-Feedback) ---
    "active_filters": {"de": "Aktive Filter", "en": "Active filters"},
    "filter_none": {"de": "keine (ganzes Lager)", "en": "none (whole warehouse)"},
    "hide_weekend": {"de": "Wochenende ausblenden", "en": "Hide weekend"},
    "tab_reloc_retr": {"de": "🔄 Um-/Auslagern", "en": "🔄 Relocate / retrieve"},
    "massn_rowhint": {
        "de": "Jede Zeile = 1 Lagerplatz mit dem aktuell dort liegenden Artikel.",
        "en": "Each row = 1 storage slot with the article currently stored there.",
    },
    "hf_note": {
        "de": "Spalten: **Picks (Stamm)** = `ANZ_PICKS` aus den Platz-Stammdaten, "
              "**Picks gesamt** = zusätzlich die Anfahrten aus den Fahrpos-Daten "
              "(`Q_PLATZ`). Sind beide gleich, gab es keine zusätzlichen Fahrpos-"
              "Anfahrten. **Auslastung 0 %** bedeutet: oft angefahren, aber gerade "
              "leer (Pickplatz, der nachgefüllt werden muss).",
        "en": "Columns: **Picks (master)** = `ANZ_PICKS` from slot master data, "
              "**Picks total** = plus visits from the Fahrpos data (`Q_PLATZ`). If "
              "both are equal there were no extra Fahrpos visits. **Utilization 0 %** "
              "means: visited often but currently empty (pick slot to be refilled).",
    },
    "free_note": {
        "de": "**MAX_LHM** ist die maximale Anzahl Ladehilfsmittel je Platz – kann "
              "> 1 sein (ein Platz fasst mehrere LHM). **Auslastung 0 %** = leerer "
              "Platz mit voller Restkapazität.",
        "en": "**MAX_LHM** is the max number of load units per slot – can be > 1 (a "
              "slot holds several units). **Utilization 0 %** = empty slot with full "
              "remaining capacity.",
    },
    "pick_note": {
        "de": "Jede Zelle zählt die TPA-Bewegungen (Auftragspositionen) in diesem "
              "Wochentag/Stunden-Fenster.",
        "en": "Each cell counts the TPA movements (order lines) in that weekday/hour "
              "window.",
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
    # WERT = Platzkapazitaet (MAX_LHM) x Picks. Ersatz fuer "Gewicht x Picks"
    # (GEWICHT liegt in den Daten nur als 0 vor) -> grober Bedeutungswert je
    # Platz fuer die Massnahmen-Tabellen.
    platz["WERT"] = platz["MAX_LHM"].fillna(0) * platz["ANZ_PICKS"]
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
        f"ENDE_DATUM, ENDE_ZEIT "
        f'FROM "{TPA_TABLE}"',
        con,
    )
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


def agg_articles(tpa: pd.DataFrame, limit: int | None = None) -> pd.DataFrame:
    """Bewegungen je Artikel (ARTIKELNR), absteigend. `limit` schneidet Top-N ab."""
    sub = tpa[tpa["artikel"] != ""]
    if sub.empty:
        return pd.DataFrame(columns=["artikel", "bezeichnung", "bewegungen"])
    g = (
        sub.groupby("artikel")
        .agg(bezeichnung=("bezeichnung", "first"), bewegungen=("artikel", "size"))
        .reset_index().sort_values("bewegungen", ascending=False)
        .reset_index(drop=True)
    )
    g = g[["artikel", "bezeichnung", "bewegungen"]]
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
        "latex": r"\text{Auslastung}\,[\%] = \frac{\mathrm{IST\_LHM}}{\mathrm{MAX\_LHM}} \times 100",
        "plain": {"de": "IST_LHM / MAX_LHM × 100",
                  "en": "IST_LHM / MAX_LHM × 100"},
        "note": {"de": "0 = leer, 100 = voll, ≥ 200 % = Stammdaten-Artefakt (MAX_LHM zu klein).",
                 "en": "0 = empty, 100 = full, ≥ 200 % = master-data artefact (MAX_LHM too low)."},
    },
    {
        "key": "avg_util",
        "title": {"de": "Ø Auslastung", "en": "Avg. utilization"},
        "latex": r"\varnothing\,\text{Auslastung} = \frac{1}{n}\sum_{i=1}^{n} \frac{\mathrm{IST\_LHM}_i}{\mathrm{MAX\_LHM}_i} \times 100",
        "plain": {"de": "Mittelwert von IST_LHM / MAX_LHM × 100 über die Auswahl",
                  "en": "Mean of IST_LHM / MAX_LHM × 100 over the selection"},
    },
    {
        "key": "frei",
        "title": {"de": "Freie Kapazität (LHM)", "en": "Free capacity (LHM)"},
        "latex": r"\mathrm{FREE\_CAPACITY} = \mathrm{MAX\_LHM} - \mathrm{IST\_LHM}",
        "plain": {"de": "MAX_LHM − IST_LHM", "en": "MAX_LHM − IST_LHM"},
    },
    {
        "key": "belegt",
        "title": {"de": "Belegt", "en": "Occupied"},
        "latex": r"\mathrm{BELEGT} = (\mathrm{IST\_LHM} > 0)",
        "plain": {"de": "IST_LHM > 0", "en": "IST_LHM > 0"},
    },
    {
        "key": "gesperrt",
        "title": {"de": "Gesperrt", "en": "Locked"},
        "latex": r"\mathrm{GESPERRT} = \big(\mathrm{SPERR\_KNZ} \notin \{\varnothing, 0\}\big)",
        "plain": {"de": "SPERR_KNZ gesetzt (≠ leer/0)", "en": "SPERR_KNZ set (≠ empty/0)"},
    },
    {
        "key": "tage_leer",
        "title": {"de": "Tage leer", "en": "Days empty"},
        "latex": r"\mathrm{DAYS\_EMPTY} = \text{heute} - \mathrm{LEER\_DATUM}",
        "plain": {"de": "heute − LEER_DATUM (Tage)", "en": "today − LEER_DATUM (days)"},
    },
    {
        "key": "abc_calc",
        "title": {"de": "ABC berechnet (ABC_CALC)", "en": "ABC calculated (ABC_CALC)"},
        "latex": r"\text{kum. Pick-Anteil} \le 80\% \Rightarrow A,\quad \le 95\% \Rightarrow B,\quad \text{sonst } C",
        "plain": {"de": "Sortiert nach Picks; kum. Anteil ≤ 80 %→A, ≤ 95 %→B, sonst C",
                  "en": "Sorted by picks; cum. share ≤ 80 %→A, ≤ 95 %→B, else C"},
        "note": {"de": "Plätze/Artikel nach ANZ_PICKS absteigend, kumulativer Anteil.",
                 "en": "Slots/items by ANZ_PICKS desc., cumulative share."},
    },
    {
        "key": "pick_total",
        "title": {"de": "Pick-Total", "en": "Pick total"},
        "latex": r"\mathrm{PICK\_TOTAL} = \mathrm{ANZ\_PICKS} + \mathrm{Q\_PLATZ\text{-}Count}",
        "plain": {"de": "ANZ_PICKS + Q_PLATZ-Count (Fahrpos)",
                  "en": "ANZ_PICKS + Q_PLATZ count (Fahrpos)"},
    },
    {
        "key": "wert",
        "title": {"de": "Wert je Platz", "en": "Slot value"},
        "latex": r"\mathrm{WERT} = \mathrm{MAX\_LHM} \times \mathrm{ANZ\_PICKS}",
        "plain": {"de": "MAX_LHM × ANZ_PICKS", "en": "MAX_LHM × ANZ_PICKS"},
    },
    {
        "key": "ampel",
        "title": {"de": "Heatmap-Ampel", "en": "Heatmap colour"},
        "latex": r"\text{grün} < 40\,\% \le \text{gelb} < 80\,\% \le \text{rot}",
        "plain": {"de": "grün < 40 %, gelb 40–79 %, rot ≥ 80 %",
                  "en": "green < 40 %, yellow 40–79 %, red ≥ 80 %"},
    },
    {
        "key": "ebene_max",
        "title": {"de": "Ebene-Regler Obergrenze", "en": "Level slider upper bound"},
        "latex": r"\max\{\,e : \#\{\text{Plätze mit EBENE}=e\} \ge 20\,\}",
        "plain": {"de": "höchste Ebene mit ≥ 20 Plätzen",
                  "en": "highest level with ≥ 20 slots"},
        "note": {"de": "Verhindert, dass Einzel-Ausreißer (EBENE 14–24) die Skala aufblähen.",
                 "en": "Prevents single outliers (EBENE 14–24) from inflating the scale."},
    },
]

_FORMULA_BY_KEY = {f["key"]: f for f in FORMULAS}


def fhelp(key: str) -> str:
    """i-Icon-Tooltip-Text (Formel) je Kennzahl – aus der zentralen FORMULAS-Quelle."""
    f = _FORMULA_BY_KEY.get(key)
    if not f:
        return ""
    return f"**{f['title'][_LANG]}**\n\n`{f['plain'][_LANG]}`"


def render_formulas_popover() -> None:
    """ℹ️-Button mit ALLEN exakten Formeln (LaTeX) – komplette Referenz."""
    label = "ℹ️ Formeln" if _LANG == "de" else "ℹ️ Formulas"
    with st.popover(label):
        st.markdown("**Formeln & Definitionen**" if _LANG == "de"
                    else "**Formulas & definitions**")
        for f in FORMULAS:
            st.markdown(f"**{f['title'][_LANG]}**")
            st.latex(f["latex"])
            note = f.get("note")
            if note:
                st.caption(note[_LANG])


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
) -> pd.DataFrame:
    """Wendet die Sidebar-Filter auf das Platz-DataFrame an und gibt die
    Teilmenge zurueck. Wird einmal in main() aufgerufen; ALLE Tabs arbeiten
    danach mit diesem `filtered` – so wirkt jeder Filter ueberall gleich.
    Jeder Block ist ein optionaler Filter (leer/Default = nicht einschraenken).
    """
    out = df
    if abc:
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
    "ANZ_PICKS", "ABC_KLASSE", "MAX_LHM", "IST_LHM", "WERT",
]

# Default-Umbenennung + Tooltips fuer die Standard-Massnahmenspalten
# (greift automatisch bei Umlagern/Auslagern, die keine eigene rename/col_help
# uebergeben). Macht v.a. WERT/ABC verstaendlich (Lehrer-Feedback "was heisst WERT").
_MASSNAHME_RENAME = {
    "PLATZ_ID": "Platz", "REGAL": "Regal", "FACH": "Fach", "EBENE": "Ebene",
    "ANZ_PICKS": "Picks", "ABC_KLASSE": "ABC (Platz)",
    "MAX_LHM": "Kapazität (max. LHM)", "IST_LHM": "Belegt (Ist-LHM)",
    "WERT": "Wert (Bedeutung)",
}
_MASSNAHME_HELP = {
    "Platz": "Eindeutige Platz-Kennung (PLATZ_ID) im Lagersystem.",
    "Regal": "Regalnummer im Lager.",
    "Fach": "Fach innerhalb des Regals.",
    "Ebene": "Höhe/Ebene des Platzes – niedrig = Pickzone (kurze Greifwege).",
    "Picks": "ANZ_PICKS – wie oft an diesem Platz gepickt wird "
             "(Zugriffshäufigkeit im Lagersystem).",
    "ABC (Platz)": "Güteklasse des ORTES aus dem Lagersystem (A = wegoptimaler "
                   "Premiumplatz). Beschreibt den Platz, nicht den Artikel.",
    "Kapazität (max. LHM)": "MAX_LHM – wie viele Ladehilfsmittel der Platz "
                            "maximal fasst (kann > 1 sein).",
    "Belegt (Ist-LHM)": "IST_LHM – wie viele Ladehilfsmittel aktuell dort stehen.",
    "Wert (Bedeutung)": "WERT = Kapazität × Picks (MAX_LHM × ANZ_PICKS). Grobes "
                        "Maß für die „Wichtigkeit“ eines Platzes: viel Kapazität "
                        "UND oft gepickt = hoher Wert. Bei 0 Picks ist der Wert 0 "
                        "(Ersatz für „Gewicht × Picks“; Gewicht fehlt in den Daten).",
    "Vorschlag": "Abgeleitete Handlungsempfehlung für diese Zeile.",
    "Zielplatz-Vorschlag": "Konkreter freier Zielplatz (1:1 nach freier "
                           "Kapazität), wohin der Inhalt umgelagert werden kann.",
}

# Schlanke Spalten fuer den Einlagern-Tab: freie Plaetze haben kaum/keine
# Ist-Ware, darum sind ANZ_PICKS/WERT (= MAX_LHM x ANZ_PICKS) hier ~0 und nur
# verwirrend. Relevant ist nur Ort, Platz-Guete (ABC) und freie Kapazitaet.
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
    "Platz": "Eindeutige Platz-Kennung (PLATZ_ID) im WMS.",
    "Regal": "Regalnummer im Lager.",
    "Fach": "Fach innerhalb des Regals.",
    "Ebene": "Höhe/Ebene – niedrig = wegoptimale Pickzone (kurze Greifwege). "
             "Kriterium für Schnelldreher (≤ Regler) vs. Reserve (≥ Regler).",
    "ABC (Platz)": "Güteklasse des ORTES aus dem WMS (A = wegoptimaler "
                   "Premiumplatz). Beschreibt den Platz, nicht den Artikel; "
                   "entscheidet Schnelldreher-Platz (A) vs. Reserve (kein A).",
    "Kapazität (max. LHM)": "MAX_LHM – wie viele Ladehilfsmittel "
                            "(Paletten/Behälter) der Platz maximal fasst.",
    "Belegt (Ist-LHM)": "IST_LHM – wie viele Ladehilfsmittel aktuell schon "
                        "dort stehen.",
    "Frei (LHM)": "Kapazität − Belegt – wie viele LHM noch reinpassen. "
                  "Sortierkriterium der Liste (größte Lücke zuerst).",
    "Auslastung %": "Belegt / Kapazität × 100. 0 % = ganz leer, < 100 % = "
                    "noch Platz.",
    "Sperrgrund (Kennz.)": "Sperrkennzeichen (SPERR_KNZ) aus dem WMS – warum "
                           "der Platz gesperrt ist (z. B. Inventur/Defekt). "
                           "Gesetzt = hier nicht einlagern.",
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
# GANZ leer (IST_LHM = 0), darum sind IST_LHM (immer 0) und WERT (= MAX_LHM x
# Picks) keine Entscheidungshilfe. Relevant ist: Ort, Platz-Guete (ABC),
# Pickhaeufigkeit (Dringlichkeit) und wie voll der Platz sein SOLL (MAX_LHM).
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
    "Platz": "Eindeutige Platz-Kennung (PLATZ_ID) im WMS.",
    "Regal": "Regalnummer im Lager.",
    "Fach": "Fach innerhalb des Regals.",
    "Ebene": "Höhe/Ebene des Platzes – niedrig = Pickzone (kurze Greifwege).",
    "ABC (Platz)": "Im WMS hinterlegte Güteklasse des ORTES (A = wegoptimaler "
                   "Premiumplatz). Beschreibt den Platz, nicht den Artikel; "
                   "wird hier nicht aus Picks berechnet.",
    "Picks (Häufigkeit)": "ANZ_PICKS – wie oft an diesem Platz gepickt wird "
                          "(WMS-Zugriffszähler). Treiber der Dringlichkeit.",
    "Soll-LHM": "MAX_LHM – auf so viele Ladehilfsmittel (Paletten/Behälter) "
                "sollte der Platz aufgefüllt werden.",
    "Tage leer": "Tage seit dem Leer-Datum (LEER_DATUM) – wie lange der Platz "
                 "schon ohne Ware ist. Bei manchen Plätzen unbekannt (leer).",
    "Tage seit letztem Pick": "Tage seit dem letzten Zugriff (ZUGRIFF_DATUM). "
                              "Zweites Staleness-Signal: kürzlich gepickt + leer "
                              "= vergessener Nachschub; lange kein Pick = evtl. "
                              "totes Fach. Besser gefüllt als „Tage leer“.",
    "Vorschlag": "Abgeleitete Handlung: Dringlichkeit aus der Listenregel "
                 "(Picks/Tage), Menge = Soll-LHM (Platz ist leer → auf Soll "
                 "auffüllen).",
}


def render_massnahme_kategorie(titel: str, beschreibung: str, df: pd.DataFrame,
                               extra_cols: list[str] | None = None,
                               vorschlag: str | None = None,
                               cols: list[str] | None = None,
                               rename: dict[str, str] | None = None,
                               rowhint: str | None = None,
                               col_help: dict[str, str] | None = None) -> None:
    """Rendert eine Massnahmen-Kategorie einheitlich (Titel + Tabelle + CSV).

    `vorschlag`: optionaler Text, der als zusaetzliche Spalte "Vorschlag"
    (konkrete Handlungsempfehlung) in jede Zeile geschrieben wird.
    `cols`: ersetzt die Standard-Spalten (_MASSNAHME_COLS) durch eine
    tab-spezifische Liste (z. B. Einlagern ohne sinnlose Pick-/Wert-Spalten).
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
    # (Umlagern/Auslagern nutzen die Standardspalten -> WERT/ABC werden lesbar).
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
        _csv_download(show, f"massnahme_{key}")
    st.divider()


def render_uebersicht(filtered: pd.DataFrame) -> None:
    """Tab 'Übersicht': Belegung/Auslastung/ABC fuer das gesamte Lager."""
    st.markdown(t("halls_intro"))
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

    fig = px.bar(
        zones.melt(
            id_vars="HALLE",
            value_vars=["occupied", "frei"],
            var_name="Status",
            value_name="Plaetze",
        ),
        x="HALLE", y="Plaetze", color="Status", barmode="stack",
        color_discrete_map={"occupied": "#ef6c00", "frei": "#bdbdbd"},
        title=t("halls_chart"),
    )
    st.plotly_chart(fig, use_container_width=True)

    st.markdown(t("halls_kpis"))
    show = zones[[
        "HALLE", "total_slots", "occupied", "frei", "Belegung_%",
        "Ø_Auslastung_%", "picks", "A-Plätze", "B-Plätze", "C-Plätze",
    ]].rename(columns={
        "HALLE": "Lager", "total_slots": "Plätze", "occupied": "Belegt",
        "frei": "Frei", "picks": "Picks gesamt",
    })
    st.dataframe(show, use_container_width=True, hide_index=True)
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
    hide_we = st.checkbox(t("hide_weekend"), value=True, key="pickheat_we")
    ph = agg_pick_heatmap(tpa)
    if ph.empty:
        st.info(t("no_data_filters"))
    else:
        weekday_names = {
            0: "So", 1: "Mo", 2: "Di", 3: "Mi", 4: "Do", 5: "Fr", 6: "Sa",
        }
        ph = ph[(ph["weekday"].between(0, 6)) & (ph["hour"].between(0, 23))]
        if hide_we:
            # Sa (6) und So (0) raus -> klares Mo-Fr-Bild (Lager am WE kaum aktiv)
            ph = ph[~ph["weekday"].isin([0, 6])]
        day_order = range(1, 6) if hide_we else range(7)
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
                ph.groupby("weekday")["picks"].sum().reindex(range(7), fill_value=0)
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
    "Platz": "Eindeutige Platz-Kennung (PLATZ_ID) im Lagersystem.",
    "Regal": "Regalnummer im Lager.",
    "Fach": "Fach innerhalb des Regals.",
    "Ebene": "Höhe/Ebene des Platzes.",
    "Picks (Stamm)": "ANZ_PICKS – die im Lagersystem hinterlegte "
                     "Zugriffshäufigkeit dieses Platzes.",
    "Picks gesamt": "ANZ_PICKS + zusätzliche Anfahrten aus den Fahrpos-Daten "
                    "(Q_PLATZ). Gleich wie „Picks (Stamm)“ = keine zusätzlichen "
                    "Fahrpos-Anfahrten (kein Fehler).",
    "Kapazität (max. LHM)": "MAX_LHM – wie viele Ladehilfsmittel der Platz "
                            "maximal fasst (kann > 1 sein).",
    "Belegt (Ist-LHM)": "IST_LHM – wie viele Ladehilfsmittel aktuell dort stehen.",
    "Auslastung %": "Ist-LHM / Kapazität × 100. 0 % = oft angefahren, aber "
                    "gerade leer (Nachschub nötig); 100 % = voll.",
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


def render_umlagern(filtered: pd.DataFrame) -> None:
    """Tab 'Umlagern': datenbasierte Umlager-Vorschlaege (3 Regeln)."""
    st.markdown(t("reloc_head"))
    with st.expander(t("reloc_info_t")):
        st.markdown(t("reloc_info_b"))
    c1, c2, c3 = st.columns(3)
    with c1:
        # A/B/C-Auswahl: blendet die Kategorien nach ihrer Ziel-Klasse ein.
        # A -> "Premium ungenutzt" + "A weit oben", C -> "Heisse C-Plaetze".
        reloc_abc = st.multiselect(
            t("abc"), ["A", "B", "C"], default=["A", "B", "C"],
            key="reloc_abc", help=t("reloc_abc_help"))
    with c2:
        hot_c_threshold = st.slider(t("sl_hotc"), 10, 300, 100, step=10)
    with c3:
        high_level = st.slider(t("sl_highlevel"), 2, 6, 4)

    # Regel 1: A-Platz (Premium) ohne Picks -> Premiumplatz verschwendet.
    unused_a = filtered[
        (filtered["ABC_KLASSE"] == "A")
        & (filtered["ANZ_PICKS"] == 0)
        & (~filtered["GESPERRT"])
    ].sort_values(["REGAL", "EBENE", "FACH"])
    # Regel 2: C-Platz mit vielen Picks -> falsch klassifiziert, hochstufen.
    hot_c = filtered[
        (filtered["ABC_KLASSE"] == "C")
        & (filtered["ANZ_PICKS"] >= hot_c_threshold)
    ].sort_values("ANZ_PICKS", ascending=False)
    # Regel 3: aktiver A-Artikel weit oben -> ergonomisch nach unten holen.
    high_level_a = filtered[
        (filtered["ABC_KLASSE"] == "A")
        & (filtered["EBENE"] >= high_level)
        & (filtered["ANZ_PICKS"] > 0)
    ].sort_values("ANZ_PICKS", ascending=False)

    # Konkrete Zielplatz-Vorschlaege aus den freien (nicht gesperrten)
    # Plaetzen der aktuellen Auswahl. Niedrige Ebenen (<=2) = gute Pick-
    # plaetze -> Ziel fuer heisse C-Plaetze und A-Plaetze von oben; hohe
    # Ebenen (>=3) = Reserve -> Ziel fuer ungenutzte Premiumplaetze.
    free_pool = filtered[
        (filtered["FREE_CAPACITY"] > 0) & (~filtered["GESPERRT"])
    ]
    free_low = free_pool[free_pool["EBENE"] <= 2] \
        .sort_values("FREE_CAPACITY", ascending=False)
    free_high = free_pool[free_pool["EBENE"] >= 3] \
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

    if "A" in reloc_abc:
        render_massnahme_kategorie(
            t("reloc_unusedA_t"), t("reloc_unusedA_d"),
            _add_ziel(unused_a, free_high),
            extra_cols=[t("col_ziel")], vorschlag=t("reloc_unusedA_v"))
    if "C" in reloc_abc:
        render_massnahme_kategorie(
            t("reloc_hotC_t"), t("reloc_hotC_d"),
            _add_ziel(hot_c, free_low),
            extra_cols=[t("col_ziel")], vorschlag=t("reloc_hotC_v"))
    if "A" in reloc_abc:
        render_massnahme_kategorie(
            t("reloc_highA_t"), t("reloc_highA_d"),
            _add_ziel(high_level_a, free_low),
            extra_cols=[t("col_ziel")], vorschlag=t("reloc_highA_v"))
    if not reloc_abc:
        st.info(t("reloc_pick_abc"))


def _replen_vorschlag_col(df: pd.DataFrame, kind: str) -> pd.DataFrame:
    """Fuegt eine ABGELEITETE Vorschlag-Spalte hinzu (1 Zeile = 1 konkrete
    Handlung). Die Empfehlung ist nicht fix, sondern entsteht aus:
      - der Listenregel (kind: urgent/overdue/medium) -> Dringlichkeit/Wortlaut,
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
        tmpl = t("replen_urgent_v") if kind == "urgent" else t("replen_medium_v")
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
    # Wichtige (hochfrequente) leere Plaetze, aufgeteilt nach Aktualitaet des
    # letzten Picks (DAYS_SINCE_PICK). DAYS_EMPTY taugt hier NICHT zur Trennung
    # (Leer-Datum oft Jahre alt), DAYS_SINCE_PICK schon -> disjunkte Listen:
    #   dringend    = wichtig + GERADE ERST ohne Pick (<= Schwelle) -> jetzt fuellen
    #   ueberfaellig= wichtig + schon LAENGER ohne Pick (> Schwelle) -> vernachlaessigt
    important = empty_pick[empty_pick["ANZ_PICKS"] >= pick_threshold]
    days_since = important["DAYS_SINCE_PICK"].fillna(10**9)
    urgent = important[days_since <= overdue_days] \
        .sort_values("ANZ_PICKS", ascending=False)
    overdue = important[days_since > overdue_days] \
        .sort_values("DAYS_SINCE_PICK", ascending=False)
    # mittlere Frequenz = aktiv leer mit Picks unterhalb der Dringend-Schwelle (>0)
    medium = empty_pick[
        (empty_pick["ANZ_PICKS"] > 0)
        & (empty_pick["ANZ_PICKS"] < pick_threshold)
    ].sort_values("ANZ_PICKS", ascending=False)

    # Überblick zuerst: wie viele leere Pickplaetze insgesamt und je Stufe?
    # (Dringend + Überfällig = disjunkte Aufteilung der wichtigen Plaetze.)
    st.markdown(t("replen_overview"))
    k1, k2, k3, k4 = st.columns(4)
    k1.metric(t("replen_kpi_total"), de_num(len(empty_pick)))
    k2.metric(t("replen_urgent_t"), de_num(len(urgent)))
    k3.metric(t("replen_overdue_t"), de_num(len(overdue)))
    k4.metric(t("replen_medium_t"), de_num(len(medium)))
    st.divider()

    # Spaltenende je Liste: zwei Staleness-Signale + abgeleiteter Vorschlag.
    replen_extra = ["DAYS_EMPTY", "DAYS_SINCE_PICK", t("col_vorschlag")]
    render_massnahme_kategorie(
        t("replen_urgent_t"), t("replen_urgent_d").format(n=overdue_days),
        _replen_vorschlag_col(urgent, "urgent"),
        cols=_REPLEN_COLS, extra_cols=replen_extra,
        rename=_REPLEN_RENAME, col_help=_REPLEN_HELP)
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


def render_auslagern(filtered: pd.DataFrame) -> None:
    """Tab 'Auslagern': Langsamdreher/Ladenhueter in der Pickzone."""
    st.markdown(t("retr_head"))
    with st.expander(t("retr_info_t")):
        st.markdown(t("retr_info_b"))
    c1, c2 = st.columns(2)
    with c1:
        # Pickzone: nur niedrige Ebenen betrachten. 88% aller Plaetze haben
        # 0 Picks (v.a. Reserve weit oben) -> ohne diese Grenze waeren die
        # 0-Pick-Listen unbrauchbar gross. Standard: bis Ebene 2.
        retr_zone = st.slider(t("sl_retrzone"), 1, 6, 2)
    with c2:
        observe_max = st.slider(t("sl_observe"), 1, 50, 5)
    # belegt = physisch Ware vorhanden (IST_LHM>0, siehe BELEGT) in der
    # Pickzone. KEIN ZUSTAND<150-Filter mehr (ZUSTAND ist hier nur 0/150 und
    # kein Sperr-Indikator -> hat zuvor alle belegten Plaetze ausgeschlossen,
    # darum war der Tab leer). Gesperrte ueber den Sidebar-Filter ausblenden.
    belegt = filtered[
        (filtered["BELEGT"])
        & (filtered["EBENE"] <= retr_zone)
    ]

    # kritisch: belegter A-Platz mit 0 Picks -> Premiumplatz von Ladenhueter
    # blockiert, vorrangig auslagern.
    critical = belegt[
        (belegt["ABC_KLASSE"] == "A") & (belegt["ANZ_PICKS"] == 0)
    ].sort_values(["REGAL", "EBENE", "FACH"])
    # abgestanden: belegt, 0 Picks, aber kein A-Platz.
    stale = belegt[
        (belegt["ABC_KLASSE"] != "A") & (belegt["ANZ_PICKS"] == 0)
    ].sort_values(["REGAL", "EBENE", "FACH"])
    # beobachten: laeuft, aber nur sehr selten (1..observe_max Picks).
    observe = belegt[
        (belegt["ANZ_PICKS"] > 0) & (belegt["ANZ_PICKS"] <= observe_max)
    ].sort_values("ANZ_PICKS")

    render_massnahme_kategorie(
        t("retr_crit_t"), t("retr_crit_d"), critical)
    render_massnahme_kategorie(
        t("retr_stale_t"), t("retr_stale_d"), stale)
    render_massnahme_kategorie(
        t("retr_observe_t"),
        t("retr_observe_d").format(n=observe_max), observe)


def render_abc(filtered: pd.DataFrame, tpa: pd.DataFrame,
               movements_filtered: bool) -> None:
    """Tab 'ABC-Analyse': Verteilung, Stamm-vs-berechnet, Anpassungs-Tipps."""
    abc_mode = st.radio(
        t("abc_mode"),
        options=[t("abc_by_slots"), t("abc_by_articles")],
        horizontal=True,
    )
    by_articles = abc_mode == t("abc_by_articles")

    cc1, cc2 = st.columns(2)
    with cc1:
        a_thr = st.slider(t("abc_a_thresh"), 50, 95, 80, step=1,
                          help=fhelp("abc_calc"))
    with cc2:
        b_thr = st.slider(t("abc_b_thresh"), a_thr + 1, 99, max(a_thr + 1, 95),
                          step=1, help=fhelp("abc_calc"))

    # Alle Erklaerungen gebuendelt in EINEM eingeklappten Block (wie in den
    # anderen Tabs) -> oben keine Textwand. Reagiert auf Modus + Reglerwerte.
    with st.expander(t("abc_explain_head")):
        st.markdown(t("abc_purpose"))
        st.markdown(t("abc_mode_note"))
        st.markdown(t("abc_thresh_note").format(a=a_thr, b=b_thr))
        st.markdown(t("abc_intro_articles").format(a=a_thr, b=b_thr)
                    if by_articles else t("abc_intro").format(a=a_thr, b=b_thr))
        st.markdown(t("abc_dist_note"))
        if not by_articles:
            st.markdown(t("abc_c_note"))

    if by_articles:
        mov_filter_note(movements_filtered, filtered)
        base = agg_articles(tpa)
        data = classify_abc(base, "bewegungen", a_thr, b_thr) \
            if not base.empty else base
        table_cols = ["artikel", "bezeichnung", "bewegungen", "CUM_%", "ABC"]
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
        "bewegungen": "Bewegungen",
    }

    # Wertespalte je Sicht (Artikel = Bewegungen, Plaetze = ANZ_PICKS).
    val_col = "bewegungen" if by_articles else "ANZ_PICKS"
    val_label = (("Bewegungen" if _LANG == "de" else "Movements")
                 if by_articles else t("picks_label"))
    ent_label = (("Artikel" if _LANG == "de" else "Articles") if by_articles
                 else ("Plätze" if _LANG == "de" else "Slots"))
    # Verteilung: Balkendiagramm Anteil PLAETZE vs. Anteil PICKS je Klasse
    # (Erklaerung dazu steht im eingeklappten Block oben).
    counts = data["ABC"].value_counts().reindex(["A", "B", "C"]).fillna(0)
    picks_sum = (data.groupby("ABC")[val_col].sum()
                 .reindex(["A", "B", "C"]).fillna(0))
    total_picks = picks_sum.sum() or 1
    total_count = counts.sum() or 1
    share = (picks_sum / total_picks * 100).round(1)
    count_share = (counts / total_count * 100).round(1)
    summary = pd.DataFrame({
        t("abc_col_count"): counts.astype(int).values,
        val_label: picks_sum.astype(int).values,
        t("abc_col_share"): share.values,
    }, index=["A", "B", "C"])
    summary.index.name = t("abc")
    lbl_c, lbl_p = f"% {ent_label}", f"% {val_label}"
    bar_df = pd.DataFrame({
        t("abc"): ["A", "B", "C", "A", "B", "C"],
        "Kennzahl": [lbl_c] * 3 + [lbl_p] * 3,
        "Prozent": list(count_share.values) + list(share.values),
    })
    d1, d2 = st.columns([2, 1])
    with d1:
        st.plotly_chart(
            px.bar(bar_df, x=t("abc"), y="Prozent", color="Kennzahl",
                   barmode="group", title=t("abc_bar_title"),
                   color_discrete_map={lbl_c: "#90a4ae", lbl_p: "#1565c0"}),
            use_container_width=True,
        )
    with d2:
        st.markdown(f"**{t('abc_count')}**")
        st.dataframe(summary, use_container_width=True)

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
            dev[t("abc_rec")] = dev.apply(
                lambda r: t("abc_promote") if r["_c"] > r["_m"]
                else t("abc_demote"), axis=1,
            )
            n_prom = int((dev["_c"] > dev["_m"]).sum())
            n_dem = int((dev["_c"] < dev["_m"]).sum())
            mcols = st.columns(2)
            mcols[0].metric(t("abc_promote"), de_num(n_prom))
            mcols[1].metric(t("abc_demote"), de_num(n_dem))
            dev_tbl = dev.sort_values("ANZ_PICKS", ascending=False)[
                ["PLATZ_ID", "REGAL", "FACH", "EBENE", "ANZ_PICKS",
                 "CUM_%", "ABC_KLASSE", "ABC", t("abc_rec")]
            ].rename(columns=colmap)
            st.dataframe(dev_tbl.head(200), use_container_width=True,
                         hide_index=True)
            _csv_download(dev_tbl, "abc_anpassung")

    # --- Tabelle 2: ALLE Eintraege, sortiert nach Pickhaeufigkeit ----------
    st.markdown(t("abc_byfreq"))
    st.caption(t("abc_byfreq_note"))
    table = data[[c for c in table_cols if c in data.columns]].rename(columns=colmap)
    st.dataframe(table.head(200), use_container_width=True, hide_index=True)
    _csv_download(table, "abc_articles" if by_articles else "abc_slots")


def render_trend(tpa: pd.DataFrame, days: int, movements_filtered: bool,
                 filtered: pd.DataFrame) -> None:
    """Unter-Tab 'Durchsatz': Bewegungen je Tag (letzte N Tage o. Bereich)."""
    st.markdown(t("tp_intro"))
    # Was bedeutet das? — beantwortet v.a. "was zaehlt als EINE Bewegung?"
    # (Lehrer-Feedback), plus Kennzahlen + Grund fuer den Wochenende-Filter.
    with st.expander(t("tp_info_t")):
        st.markdown(t("tp_info_b"))
    mov_filter_note(movements_filtered, filtered)
    copt1, copt2 = st.columns(2)
    with copt1:
        use_range = st.checkbox(t("tp_use_range"), value=False)
    with copt2:
        hide_we = st.checkbox(t("hide_weekend"), value=True)
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
    if hide_we:
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
    "Artikel-Nr": "Artikelnummer (ARTIKELNR) aus den TPA-Daten.",
    "Bezeichnung": "Klartext-Name des Artikels.",
    "Bewegungen": "Anzahl TPA-Datensätze (Auftragspositionen) für diesen "
                  "Artikel im Zeitraum – wie oft er bewegt/gepickt wurde. "
                  "Mehr = wichtigerer Dreher.",
}


def render_top(tpa: pd.DataFrame, article_limit: int,
               movements_filtered: bool, filtered: pd.DataFrame) -> None:
    """Unter-Tab 'Top-Artikel': meistbewegte Artikel aus TPA."""
    st.markdown(t("top_intro"))
    with st.expander(t("top_info_t")):
        st.markdown(t("top_info_b"))
    mov_filter_note(movements_filtered, filtered)
    top = agg_articles(tpa, article_limit)
    if top.empty:
        st.info(t("no_data_filters"))
    else:
        chart_df = top.head(min(article_limit, 25)).sort_values("bewegungen")
        st.plotly_chart(
            px.bar(
                chart_df, x="bewegungen", y="artikel", orientation="h",
                title=t("top_chart"),
                labels=dict(bewegungen="Bewegungen", artikel="Artikel"),
            ),
            use_container_width=True,
        )
        show = top.rename(columns=_TOP_RENAME)
        col_cfg = {c: st.column_config.Column(help=h)
                   for c, h in _TOP_HELP.items() if c in show.columns}
        st.dataframe(show, use_container_width=True, hide_index=True,
                     column_config=col_cfg)
        _csv_download(show, "top_artikel")


def render_article(tpa: pd.DataFrame, movements_filtered: bool,
                   filtered: pd.DataFrame) -> None:
    """Tab 'Artikel': Bewegungen und Quellplaetze eines Artikels."""
    st.markdown(t("art_intro"))
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
                hide_we = st.checkbox(t("hide_weekend"), value=True,
                                      key="art_hide_we")
                day_plot = drop_weekend(day_df, "day") if hide_we else day_df
                st.plotly_chart(
                    px.line(day_plot, x="day", y="picks", markers=True,
                            labels={"day": "Datum" if _LANG == "de" else "Date",
                                    "picks": t("picks_label")}),
                    use_container_width=True,
                )
            if not slots.empty:
                st.markdown(f"**{t('art_by_slot')}**")
                slot_tbl = slots.rename(columns={"platz": "PLATZ_ID",
                                                 "picks": "Picks"})
                st.dataframe(slot_tbl, use_container_width=True, hide_index=True)
                _csv_download(slot_tbl, "artikel_plaetze")


def render_3d(filtered: pd.DataFrame) -> None:
    """Tab '3D-Modell': CAD-Viewer ODER Daten-Schema + ABC-je-Platz-Tabelle."""
    import json as _json

    # Umschalter: CAD-Modell (echte Optik, ~66% Deckung) ODER Schema aus
    # den Daten (alle 22.429 Plaetze, kein Grau, klotzig).
    view_opts = [t("d3_view_cad"), t("d3_view_schema")]
    view_choice = st.radio(t("d3_view"), view_opts, horizontal=True)
    schema_mode = view_choice == t("d3_view_schema")

    st.markdown(t("d3_schema_intro") if schema_mode else t("d3_click_intro"))

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
    }
    labels_json = _json.dumps(labels, ensure_ascii=False)
    # Nur 9-stellige PLATZ_ID ins Modell durchreichen.
    focus_id = search_platz if search_platz.isdigit() else ""

    if schema_mode:
        sc1, sc2 = st.columns([1, 1])
        with sc1:
            # Färben nach Auslastung (Default = 3D-Heatmap), Belegung, ABC
            # oder neutral. Alle Modi nutzen dieselben DB-Daten je Box.
            cm_opts = [t("d3_cm_util"), t("d3_cm_occ"), t("d3_cm_abc"),
                       t("d3_cm_neutral")]
            cm_choice = st.selectbox(t("d3_colormode"), cm_opts, index=0,
                                     key="d3_cm_schema")
            colormode = {
                t("d3_cm_util"): "util", t("d3_cm_occ"): "occ",
                t("d3_cm_abc"): "abc", t("d3_cm_neutral"): "neutral",
            }[cm_choice]
        with sc2:
            viewer_height = st.slider(t("d3_height"), 360, 900, 640, step=20,
                                      key="d3_height_schema",
                                      help=t("d3_height_help"))
            aisle = st.slider(t("d3_aisle"), 1.0, 3.0, 1.0, step=0.1,
                              key="d3_aisle_schema", help=t("d3_aisle_help"))
        html = (
            _SCHEMA_VIEWER_HTML
            .replace("__HEIGHT__", str(viewer_height))
            .replace("__AISLE__", str(aisle))
            .replace("__DATA__", slot_json)
            .replace("__LABELS__", labels_json)
            .replace("__FOCUS__", focus_id)
            .replace("__COLORMODE__", colormode)
        )
        components.html(html, height=viewer_height + 16)
        st.caption(t("d3_schema_caption"))
    else:
        # CAD-Modell: SampleScene_clickable.glb (Meshes nach PLATZ_ID benannt),
        # CORS-faehig ueber die API geliefert.
        glb_url = "https://ssi-lagerview-api.onrender.com/model-clickable.glb"
        ctrl1, ctrl2, ctrl3 = st.columns([1, 1, 1])
        with ctrl1:
            color_abc = st.checkbox(t("d3_color_abc"), value=True)
        with ctrl2:
            perf_mode = st.checkbox(t("d3_perf"), value=True, help=t("d3_perf_help"))
        with ctrl3:
            viewer_height = st.slider(t("d3_height"), 360, 900, 640, step=20,
                                      help=t("d3_height_help"))
        html = (
            _THREE_VIEWER_HTML
            .replace("__HEIGHT__", str(viewer_height))
            .replace("__GLB__", glb_url)
            .replace("__DATA__", slot_json)
            .replace("__LABELS__", labels_json)
            .replace("__ROTATE__", "false")
            .replace("__ABCCOLOR__", "true" if color_abc else "false")
            .replace("__HIDEGREY__", "true" if perf_mode else "false")
            .replace("__FOCUS__", focus_id)
        )
        components.html(html, height=viewer_height + 16)
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
        util_range = st.slider(
            t("util"), 0, 100, (0, 100), step=5, help=t("util_help"),
        )
        only_occupied = st.checkbox(t("only_occ"), value=False)
        with st.expander(t("place_filter")):
            regal_max = max(int(platz["REGAL"].max()), 1)
            # EBENE enthaelt vereinzelte Ausreisser-Datensaetze bis 24 (je 1 Platz),
            # waehrend echte Ebenen substanziell belegt sind (0-6 sowie Cluster 10-13).
            # Obergrenze = hoechste Ebene mit nennenswerter Belegung (>= 20 Plaetze),
            # damit Einzel-Ausreisser die Skala nicht aufblaehen.
            _ebene_counts = platz["EBENE"].value_counts()
            _ebene_real = _ebene_counts[_ebene_counts >= 20].index
            ebene_max = (max(int(_ebene_real.max()), 1) if len(_ebene_real)
                         else max(int(platz["EBENE"].max()), 1))
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
        article_limit = st.slider(t("top_count"), 5, 100, 25, step=5)
        st.divider()
        st.caption(f"DB: `{get_db_path()}`")

    # Einmal filtern -> alle Tabs nutzen dasselbe gefilterte DataFrame.
    filtered = apply_filters(
        platz, abc, util_range, only_occupied,
        regal_range=regal_range,
        ebene_range=ebene_range,
        min_picks=min_picks,
        sperr_mode=sperr_mode,
    )

    # Menschenlesbare Zusammenfassung der aktiven Filter -> Caption unter den KPIs
    # und Kommentarzeile in jedem CSV-Download (Nachvollziehbarkeit).
    _af: list[str] = []
    if abc:
        _af.append(f"{t('abc')}: {', '.join(abc)}")
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
    avg_util = filtered["UTILIZATION"].mean()

    c1, c2, c3 = st.columns(3)
    c1.metric(t("m_slots"), de_num(len(filtered)),
              help=t("m_slots_help"))
    c2.metric(t("m_occupied"), de_num(occupied),
              f"{occupied/total*100:.1f}%", help=t("m_occupied_help"))
    c3.metric(t("m_avg_util"),
              f"{avg_util:.1f} %" if not pd.isna(avg_util) else "—",
              help=fhelp("avg_util"))

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
        render_umlagern(filtered)
        st.divider()
        render_auslagern(filtered)

    with tab_nachschub:
        render_nachschub(filtered)

    with tab_einlagern:
        render_einlagern(filtered)

    with tab_abc:
        render_abc(filtered, tpa, movements_filtered)

    with sub_trend:
        render_trend(tpa, days, movements_filtered, filtered)

    with sub_top:
        render_top(tpa, article_limit, movements_filtered, filtered)

    with tab_article:
        render_article(tpa, movements_filtered, filtered)

    with tab_3d:
        render_3d(filtered)


if __name__ == "__main__":
    main()
