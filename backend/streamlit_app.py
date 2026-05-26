"""Streamlit-Dashboard fuer Schaeflein LagerView.

Visualisiert dieselben Daten wie die Flutter-App direkt aus der warehouse.db
und uebernimmt die Auswertungen aus `warehouse_project/warehouse_analytics.py`
und `warehouse_heatmap.py` (Utilization, Bottlenecks, Free Capacity, Smart
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
controls.enableDamping = true;
controls.autoRotate = AUTOROTATE;
controls.autoRotateSpeed = 0.8;
controls.addEventListener('change', requestRender);

const raycaster = new THREE.Raycaster();
const pointer = new THREE.Vector2();
let selected = null, selectedOrigMat = null;
const HIGHLIGHT = new THREE.Color(0x1565c0);

function fmt(v){ return (v==null) ? '—' : v; }

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
      [L.halle, d.h],
      [L.abc_m, d.a],
      [L.abc_c, d.ac],
      [L.picks, d.p],
      [L.util, util],
      [L.status, status],
    ];
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
      if(selected && selectedOrigMat){ selected.material = selectedOrigMat; }
      selected = hit.object;
      selectedOrigMat = selected.material;
      const m = selected.material.clone();  // nur das EINE markierte Mesh klont
      if(m.emissive){ m.emissive = HIGHLIGHT; m.emissiveIntensity = 0.9; }
      else { m.color = HIGHLIGHT; }
      selected.material = m;
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
    const dist = maxDim / (2 * Math.tan((Math.PI * camera.fov) / 360));
    camera.position.set(center.x + dist * 0.9, center.y + dist * 0.6, center.z + dist * 0.9);
    camera.near = maxDim / 1000; camera.far = maxDim * 10;
    camera.updateProjectionMatrix();
    controls.update();
    loadingEl.style.display = 'none';
    requestRender();
  },
  (p) => {
    if(p && p.total){ loadingEl.textContent = L.loading + ' ' + Math.round(p.loaded / p.total * 100) + '%'; }
  },
  (err) => { loadingEl.textContent = 'Fehler: ' + err; }
);

function animate(){
  requestAnimationFrame(animate);
  // controls.update() liefert true, solange das Damping die Kamera bewegt;
  // 'change' setzt needsRender dabei ohnehin. Nur dann tatsaechlich rendern.
  const moved = controls.update();
  if(needsRender || moved){
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

TR: dict[str, dict[str, str]] = {
    "caption": {
        "de": "Lager BER03 — Live-Auswertung aus warehouse.db",
        "en": "Warehouse BER03 — live analysis from warehouse.db",
    },
    "lang_label": {"de": "🌐 Sprache / Language", "en": "🌐 Sprache / Language"},
    "filter": {"de": "Filter", "en": "Filters"},
    "hall": {"de": "Halle", "en": "Hall"},
    "hall_help": {"de": "Leer = alle Hallen.", "en": "Empty = all halls."},
    "abc": {"de": "ABC-Klasse", "en": "ABC class"},
    "abc_help": {
        "de": "Filtert auf Stamm-ABC ODER kumulativ berechnete ABC.",
        "en": "Filters on master ABC OR calculated ABC.",
    },
    "util": {"de": "Auslastung (%)", "en": "Utilization (%)"},
    "util_help": {
        "de": "MAX_LHM vs. IST_LHM. 0 = leer, 100 = voll, >100 = ueberlastet.",
        "en": "MAX_LHM vs. IST_LHM. 0 = empty, 100 = full, >100 = overloaded.",
    },
    "only_occ": {"de": "Nur belegte Plaetze", "en": "Occupied slots only"},
    "place_filter": {
        "de": "Platz-Filter (Regal/Ebene/Picks/Sperre)",
        "en": "Slot filter (rack/level/picks/lock)",
    },
    "rack": {"de": "Regal", "en": "Rack"},
    "level": {"de": "Ebene", "en": "Level"},
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
    "tab_halls": {"de": "Hallen", "en": "Halls"},
    "tab_misc": {"de": "Sonstiges", "en": "Other"},
    "tab_util": {"de": "Auslastungs-Heatmap", "en": "Utilization heatmap"},
    "tab_pick": {"de": "Pick-Heatmap", "en": "Pick heatmap"},
    "tab_bottle": {"de": "Bottlenecks", "en": "Bottlenecks"},
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
        "de": "**Hallen-Übersicht** — Belegung, Auslastung und ABC-Verteilung je "
              "Halle (Regal 1–16 = Halle 1, 17–32 = Halle 2, Rest = Halle 3).",
        "en": "**Hall overview** — occupancy, utilization and ABC distribution per "
              "hall (rack 1–16 = Hall 1, 17–32 = Hall 2, rest = Hall 3).",
    },
    "halls_kpis": {"de": "**Kennzahlen je Halle**", "en": "**Metrics per hall**"},
    "halls_chart": {
        "de": "Belegung pro Halle (gefiltert)",
        "en": "Occupancy per hall (filtered)",
    },
    "heat_chart": {
        "de": "Auslastung je Regal/Ebene (IST/MAX × 100)",
        "en": "Utilization per rack/level (actual/max × 100)",
    },
    "pick_chart": {
        "de": "Pick-Aktivität je Wochentag/Stunde",
        "en": "Pick activity per weekday/hour",
    },
    "heat_intro": {
        "de": "**Auslastungs-Heatmap** — durchschnittliche Auslastung "
              "(`IST_LHM / MAX_LHM × 100`) je Regal und Ebene. Rot = voll, "
              "grün = viel Luft. Darunter die am stärksten ausgelasteten Regale.",
        "en": "**Utilization heatmap** — average utilization "
              "(`IST_LHM / MAX_LHM × 100`) per rack and level. Red = full, "
              "green = lots of space. Below: the most-utilized racks.",
    },
    "heat_racks": {"de": "**Regale nach Ø Auslastung**", "en": "**Racks by avg. utilization**"},
    "pick_intro": {
        "de": "**Pick-Heatmap** — Bewegungen je Wochentag und Stunde (aus den "
              "TPA-Daten). Zeigt, wann am meisten gepickt wird.",
        "en": "**Pick heatmap** — movements per weekday and hour (from TPA data). "
              "Shows when picking peaks.",
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
        "de": "**Bottleneck-Analyse** — Plätze mit hoher Pick-Frequenz "
              "(`ANZ_PICKS` + `Q_PLATZ`-Count aus Fahrpos). Engpässe werden oft "
              "angefahren und sind gleichzeitig hoch ausgelastet.",
        "en": "**Bottleneck analysis** — slots with high pick frequency "
              "(`ANZ_PICKS` + `Q_PLATZ` count from Fahrpos). Bottlenecks are "
              "visited often and are highly utilized at the same time.",
    },
    "bottle_chart": {
        "de": "Top-15 Engpässe (Picks gesamt, Farbe = Auslastung %)",
        "en": "Top-15 bottlenecks (total picks, color = utilization %)",
    },
    "free_intro": {
        "de": "**Free Capacity** — Plätze mit Restkapazität, sortiert nach "
              "`MAX_LHM − IST_LHM`.",
        "en": "**Free capacity** — slots with remaining capacity, sorted by "
              "`MAX_LHM − IST_LHM`.",
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
        "de": "### ⬆️ Nachschub / Replenishment\nLeere Pickplätze (`IST_LHM = 0`), die nachgefüllt werden sollten.",
        "en": "### ⬆️ Replenishment\nEmpty pick slots (`IST_LHM = 0`) that should be refilled.",
    },
    "sl_picklevel": {"de": "Max. Ebene (Pickzone)", "en": "Max. level (pick zone)"},
    "sl_pickthresh": {"de": "Dringend ab Picks", "en": "Urgent from picks"},
    "sl_overdue": {"de": "Überfällig ab Tagen", "en": "Overdue from days"},
    "replen_urgent_t": {"de": "Dringend leer", "en": "Urgently empty"},
    "replen_urgent_d": {
        "de": "Aktiver Pickplatz leer – dringend nachfüllen.",
        "en": "Active pick slot empty – replenish urgently.",
    },
    "replen_overdue_t": {"de": "Überfällig", "en": "Overdue"},
    "replen_overdue_d": {
        "de": "Bereits ≥ {n} Tage leer – Replenishment vergessen?",
        "en": "Empty for ≥ {n} days – replenishment forgotten?",
    },
    "replen_medium_t": {"de": "Mittlere Frequenz", "en": "Medium frequency"},
    "replen_medium_d": {
        "de": "Pickplatz leer mit mittlerer Pickfrequenz.",
        "en": "Pick slot empty with medium pick frequency.",
    },
    "put_head": {
        "de": "### 📥 Einlagern / Putaway\nWohin eingehende Ware gestellt werden sollte (freie Kapazität).",
        "en": "### 📥 Put-away\nWhere incoming goods should be stored (free capacity).",
    },
    "sl_fastlevel": {"de": "Fast-Lane bis Ebene", "en": "Fast lane up to level"},
    "sl_reservelevel": {"de": "Reserve-Ebene ab", "en": "Reserve level from"},
    "put_fast_t": {"de": "Schnelldreher-Plätze", "en": "Fast-mover slots"},
    "put_fast_d": {
        "de": "Freie A-Plätze bis Ebene {n} – ideal für Schnelldreher.",
        "en": "Free A slots up to level {n} – ideal for fast movers.",
    },
    "put_reserve_t": {"de": "Reserve (hohe Ebenen)", "en": "Reserve (high levels)"},
    "put_reserve_d": {
        "de": "Freie Plätze ab Ebene {n} – für Langsamdreher/Reserve.",
        "en": "Free slots from level {n} – for slow movers/reserve.",
    },
    "put_blocked_t": {"de": "Gesperrt – nicht bestücken", "en": "Locked – do not stock"},
    "put_blocked_d": {
        "de": "Gesperrte Plätze (ZUSTAND ≥ 150) – nicht einlagern.",
        "en": "Locked slots (ZUSTAND ≥ 150) – do not put away.",
    },
    "retr_head": {
        "de": "### 📤 Auslagern / Retrieval\nLangsamdreher/Ladenhüter, die gute Plätze blockieren und ausgelagert werden sollten.",
        "en": "### 📤 Retrieval\nSlow movers/dead stock blocking good slots that should be retrieved.",
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
              "A = Top 80 % Picks, B = nächste 15 %, C = Rest.",
        "en": "**ABC analysis** — cumulative distribution of `ANZ_PICKS`. "
              "A = top 80% of picks, B = next 15%, C = rest.",
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
    "abc_byfreq": {"de": "**Plätze nach Pickfrequenz**", "en": "**Slots by pick frequency**"},
    "abc_mode": {"de": "ABC berechnen nach", "en": "Compute ABC by"},
    "abc_by_slots": {"de": "Lagerplätzen", "en": "Storage slots"},
    "abc_by_articles": {"de": "Artikeln", "en": "Articles"},
    "abc_a_thresh": {"de": "A bis kumul. %", "en": "A up to cum. %"},
    "abc_b_thresh": {"de": "B bis kumul. %", "en": "B up to cum. %"},
    "abc_pareto": {
        "de": "Pareto-Kurve — kumulativer Anteil der Bewegungen",
        "en": "Pareto curve — cumulative share of movements",
    },
    "abc_px_slots": {"de": "Plätze (nach Picks sortiert)", "en": "Slots (sorted by picks)"},
    "abc_px_articles": {"de": "Artikel (nach Bewegungen sortiert)", "en": "Articles (sorted by movements)"},
    "abc_py": {"de": "kumulativer Anteil %", "en": "cumulative share %"},
    "abc_intro_articles": {
        "de": "**ABC nach Artikeln** — Artikel nach Bewegungen (TPA). "
              "A = Top-Artikel bis zur A-Schwelle, dann B, Rest C.",
        "en": "**ABC by articles** — articles by movements (TPA). "
              "A = top articles up to the A threshold, then B, rest C.",
    },
    "abc_dist": {"de": "ABC-Verteilung", "en": "ABC distribution"},
    "abc_count": {"de": "Anzahl je Klasse", "en": "Count per class"},
    "abc_adjust_head": {
        "de": "**🏷️ ABC-Anpassung — Empfehlungen**",
        "en": "**🏷️ ABC adjustment — recommendations**",
    },
    "abc_adjust_intro": {
        "de": "Plätze, deren Stamm-ABC nicht zur berechneten Klasse passt. "
              "„Hochstufen“ = wird stärker bewegt als hinterlegt, „Herabstufen“ = umgekehrt.",
        "en": "Slots whose master ABC differs from the calculated class. "
              "“Promote” = busier than recorded, “Demote” = the opposite.",
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
    "d3_height": {"de": "Höhe (px)", "en": "Height (px)"},
    "d3_reset": {"de": "Ansicht zurücksetzen", "en": "Reset view"},
    "d3_caption": {
        "de": "Steuerung: Ziehen = drehen, Scrollen = zoomen, Rechtsklick-Ziehen "
              "= verschieben. Regler oben ändern Helligkeit/Schatten/Höhe.",
        "en": "Controls: drag = rotate, scroll = zoom, right-drag = pan. Sliders "
              "above change brightness/shadow/height.",
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
    "d3_occupied": {"de": "belegt", "en": "occupied"},
    "d3_empty": {"de": "frei", "en": "empty"},
    "d3_not_in_db": {
        "de": "Dieser Platz ist nicht in der Datenbank (nur im Modell).",
        "en": "This slot is not in the database (model only).",
    },
    "d3_legend": {"de": "Plätze im Modell", "en": "Slots in model"},
    "d3_grey": {"de": "ohne Daten", "en": "no data"},
    "d3_perf": {"de": "Leistungsmodus", "en": "Performance mode"},
    "d3_perf_help": {
        "de": "Blendet Plätze ohne DB-Daten (grau) aus → flüssiger. "
              "Es gehen keine Daten verloren, graue Plätze haben ohnehin keine.",
        "en": "Hides slots without DB data (grey) → smoother. No data is lost; "
              "grey slots have none anyway.",
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


def _hall_for_regal(regal: int) -> str:
    if 1 <= regal <= 16:
        return "Halle 1"
    if 17 <= regal <= 32:
        return "Halle 2"
    return "Halle 3"


@st.cache_data(ttl=3600, show_spinner="Lade Stellplaetze ...")
def load_platz_full() -> pd.DataFrame:
    """Zentrale Tabelle der App: ein Datensatz je Stellplatz, angereichert um
    abgeleitete Kennzahlen. Fast alle Tabs/Filter bauen darauf auf.

    Schritte:
      1. Stammdaten je Platz aus der PLATZ-Tabelle lesen
      2. Spalten in Zahlen wandeln (DB liefert teils Strings)
      3. Kennzahlen ableiten: UTILIZATION (%), FREE_CAPACITY, HALLE, BELEGT,
         DAYS_EMPTY (Tage seit LEER_DATUM)
      4. Pick-Frequenz aus FAHRPOS dazumergen (PICK_COUNT_FAHR)
      5. ABC_CALC: ABC-Klasse aus der kumulativen Pick-Verteilung berechnen
    @st.cache_data(ttl=3600) = Ergebnis 1 h zwischenspeichern (teurer Query).
    """
    con = get_connection()
    platz = pd.read_sql_query(
        f'SELECT PLATZ_ID, REGAL, FACH, EBENE, ABC_KLASSE, MAX_LHM, IST_LHM, '
        f'ANZ_PICKS, ANZ_NACHSCHUB, ZUSTAND, SPERR_KNZ, LEER_DATUM '
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
    platz["HALLE"] = platz["REGAL"].apply(_hall_for_regal)
    platz["BELEGT"] = platz["ZUSTAND"] > 0
    platz["DAYS_EMPTY"] = (
        pd.Timestamp.now().normalize()
        - pd.to_datetime(platz["LEER_DATUM"], errors="coerce")
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
        out[pid] = {
            "r": int(row.REGAL),
            "f": int(row.FACH),
            "e": int(row.EBENE),
            "h": row.HALLE,
            "a": (row.ABC_KLASSE or "—"),
            "ac": (row.ABC_CALC if isinstance(row.ABC_CALC, str) else "—"),
            "p": int(row.ANZ_PICKS),
            "u": (None if pd.isna(util) else round(float(util), 1)),
            "b": bool(row.BELEGT),
        }
    return json.dumps(out, ensure_ascii=False, separators=(",", ":"))


def heatmap_color(util: float) -> str:
    """Aus warehouse_heatmap.py."""
    if pd.isna(util):
        return "GREY"
    if util >= 80:
        return "RED"
    if util >= 40:
        return "YELLOW"
    return "GREEN"


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
    """Einheitlicher CSV-Export-Button (utf-8-sig fuer Excel-Umlaute)."""
    st.download_button(
        label or t("dl"),
        df.to_csv(index=False).encode("utf-8-sig"),
        file_name=f"{key}.csv",
        mime="text/csv",
        key=f"dl_{key}",
    )


def apply_filters(
    df: pd.DataFrame,
    hallen: list[str],
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
    if hallen:
        out = out[out["HALLE"].isin(hallen)]
    if abc:
        out = out[out["ABC_KLASSE"].isin(abc) | out["ABC_CALC"].isin(abc)]
    lo, hi = util_range
    if lo > 0 or hi < 150:
        util_filled = out["UTILIZATION"].fillna(-1)
        out = out[(util_filled >= lo) & (util_filled <= hi)]
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


def main() -> None:
    """Baut die komplette Oberflaeche auf (Streamlit rendert top-down und fuehrt
    diese Funktion bei jeder Interaktion komplett neu aus).

    Ablauf: Sprache -> Logo/Titel -> Daten laden -> Sidebar-Filter -> KPIs ->
    Tabs. Die teuren Lade-Funktionen sind gecacht, daher ist das Neu-Ausfuehren
    guenstig.
    """
    # Sprachumschalter ganz oben in der Sidebar; setzt das globale _LANG, das
    # t() fuer alle folgenden Texte auswertet.
    global _LANG
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
            st.title("Schaeflein LagerView v1.133")
            st.caption(t("caption"))
    else:
        st.title("📦 Schaeflein LagerView v1.133")
        st.caption(t("caption"))

    try:
        platz = load_platz_full()
    except Exception as exc:
        st.error(f"Konnte Stellplatz-Daten nicht laden: {exc}")
        st.exception(exc)
        st.stop()

    with st.sidebar:
        st.header(t("filter"))
        hallen = st.multiselect(
            t("hall"),
            options=["Halle 1", "Halle 2", "Halle 3"],
            default=[],
            help=t("hall_help"),
        )
        abc = st.multiselect(
            t("abc"),
            options=["A", "B", "C"],
            default=[],
            help=t("abc_help"),
        )
        util_range = st.slider(
            t("util"), 0, 150, (0, 150), step=5, help=t("util_help"),
        )
        only_occupied = st.checkbox(t("only_occ"), value=False)
        with st.expander(t("place_filter")):
            regal_max = max(int(platz["REGAL"].max()), 1)
            ebene_max = max(int(platz["EBENE"].max()), 1)
            picks_max = max(int(platz["ANZ_PICKS"].max()), 1)
            regal_range = st.slider(t("rack"), 0, regal_max, (0, regal_max))
            ebene_range = st.slider(t("level"), 0, ebene_max, (0, ebene_max))
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
        platz, hallen, abc, util_range, only_occupied,
        regal_range=regal_range,
        ebene_range=ebene_range,
        min_picks=min_picks,
        sperr_mode=sperr_mode,
    )

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

    def _mov_filter_note() -> None:
        """Hinweis in bewegungsbasierten Tabs, wenn die Platz-Filter greifen."""
        if movements_filtered:
            st.caption(t("mov_filtered").format(
                n=f"{len(filtered):,}".replace(",", ".")))

    # --- KPI-Kacheln oben (beziehen sich auf die gefilterte Auswahl) ---
    total = len(filtered) or 1
    occupied = int(filtered["BELEGT"].sum())
    avg_util = filtered["UTILIZATION"].mean()

    c1, c2, c3 = st.columns(3)
    c1.metric(t("m_slots"), f"{len(filtered):,}".replace(",", "."),
              help=t("m_slots_help"))
    c2.metric(t("m_occupied"), f"{occupied:,}".replace(",", "."),
              f"{occupied/total*100:.1f}%", help=t("m_occupied_help"))
    c3.metric(t("m_avg_util"),
              f"{avg_util:.1f} %" if not pd.isna(avg_util) else "—",
              help=t("m_avg_util_help"))

    # --- Register/Tabs ---------------------------------------------------
    # Reihenfolge der Variablen MUSS zur Reihenfolge der Titel-Liste passen.
    # ACHTUNG: Die Anzeige-Reihenfolge der Reiter bestimmt allein diese Liste –
    # die `with tab_*`-Bloecke weiter unten duerfen in beliebiger Code-Reihen-
    # folge stehen. Reihenfolge: Hallen, 3D, ABC, Steuermassnahmen (Umlagern/
    # Nachschub/Einlagern/Auslagern), Artikel, und ganz am Ende "Sonstiges".
    # "Sonstiges" buendelt Auslastungs-/Pick-Heatmap, Bottlenecks, Free
    # Capacity, Durchsatz und Top-Artikel (siehe unten).
    (tab_hallen, tab_3d, tab_abc, tab_umlagern, tab_nachschub,
     tab_einlagern, tab_auslagern, tab_article, tab_sonstiges) = st.tabs([
        t("tab_halls"),
        t("tab_3d"),
        t("tab_abc"),
        t("tab_relocate"),
        t("tab_replenish"),
        t("tab_putaway"),
        t("tab_retrieve"),
        t("tab_article"),
        t("tab_misc"),
    ])

    # "Sonstiges": Unter-Tabs fuer die Analyse-Heatmaps + Durchsatz + Top-
    # Artikel. Die Unter-Tab-Objekte werden hier (im Kontext von tab_sonstiges)
    # erzeugt; ihre Inhalte folgen weiter unten als `with sub_*` und landen
    # dadurch verschachtelt unter "Sonstiges".
    with tab_sonstiges:
        (sub_heat, sub_bottle, sub_free, sub_trend, sub_top,
         sub_pickheat) = st.tabs([
            t("tab_util"), t("tab_bottle"), t("tab_free"),
            t("tab_tp"), t("tab_top"), t("tab_pick"),
        ])

    with tab_hallen:
        st.markdown(t("halls_intro"))
        zones = (
            filtered.groupby("HALLE")
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
        # ABC-Verteilung je Halle.
        abc_pivot = (
            filtered.pivot_table(
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
            "HALLE": "Halle", "total_slots": "Plätze", "occupied": "Belegt",
            "frei": "Frei", "picks": "Picks gesamt",
        })
        st.dataframe(show, use_container_width=True, hide_index=True)
        _csv_download(show, "hallen_kennzahlen")

    with sub_heat:
        st.markdown(t("heat_intro"))
        if filtered.empty:
            st.info(t("no_data_filters"))
        else:
            pivot = filtered.pivot_table(
                index="EBENE", columns="REGAL",
                values="UTILIZATION", aggfunc="mean",
            )
            fig = px.imshow(
                pivot,
                color_continuous_scale="RdYlGn_r",
                range_color=[0, 120],
                aspect="auto",
                labels=dict(x="Regal", y="Ebene", color="Auslastung %"),
                title=t("heat_chart"),
            )
            st.plotly_chart(fig, use_container_width=True)

            color_counts = (
                filtered["UTILIZATION"].apply(heatmap_color)
                .value_counts()
                .reindex(["GREEN", "YELLOW", "RED", "GREY"]).fillna(0)
            )
            col1, col2, col3, col4 = st.columns(4)
            col1.metric("🟢 < 40 %", int(color_counts["GREEN"]))
            col2.metric("🟡 40–79 %", int(color_counts["YELLOW"]))
            col3.metric("🔴 ≥ 80 %", int(color_counts["RED"]))
            col4.metric("⚪ unbekannt", int(color_counts["GREY"]))

            st.markdown(t("heat_racks"))
            rack_util = (
                filtered.groupby(["HALLE", "REGAL"])
                .agg(
                    Plätze=("PLATZ_ID", "count"),
                    Ø_Auslastung_=("UTILIZATION", "mean"),
                    Überlastet=("UTILIZATION", lambda s: int((s > 100).sum())),
                )
                .reset_index()
                .rename(columns={"HALLE": "Halle", "REGAL": "Regal",
                                 "Ø_Auslastung_": "Ø Auslastung %"})
            )
            rack_util["Ø Auslastung %"] = rack_util["Ø Auslastung %"].round(1)
            rack_util = rack_util.sort_values("Ø Auslastung %", ascending=False)
            st.dataframe(rack_util, use_container_width=True, hide_index=True)
            _csv_download(rack_util, "regal_auslastung")

    with sub_pickheat:
        st.markdown(t("pick_intro"))
        _mov_filter_note()
        ph = agg_pick_heatmap(tpa)
        if ph.empty:
            st.info(t("no_data_filters"))
        else:
            weekday_names = {
                0: "So", 1: "Mo", 2: "Di", 3: "Mi", 4: "Do", 5: "Fr", 6: "Sa",
            }
            ph = ph[(ph["weekday"].between(0, 6)) & (ph["hour"].between(0, 23))]
            pivot = (
                ph.pivot_table(
                    index="weekday", columns="hour", values="picks", aggfunc="sum"
                )
                .reindex(range(7))
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
                        p=f"{int(row['picks']):,}".replace(",", "."),
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

    with sub_bottle:
        st.markdown(t("bottle_intro"))
        bottlenecks = (
            filtered.assign(
                PICK_TOTAL=lambda d: d["ANZ_PICKS"] + d["PICK_COUNT_FAHR"]
            )
            .sort_values(["PICK_TOTAL", "UTILIZATION"], ascending=[False, False])
            .head(50)[
                ["PLATZ_ID", "HALLE", "REGAL", "FACH", "EBENE",
                 "ANZ_PICKS", "PICK_TOTAL", "MAX_LHM", "IST_LHM", "UTILIZATION"]
            ]
        )
        if bottlenecks.empty:
            st.info(t("no_data_filters"))
        else:
            st.dataframe(bottlenecks, use_container_width=True, hide_index=True)
            _csv_download(bottlenecks, "bottlenecks")

    with sub_free:
        st.markdown(t("free_intro"))
        free_all = filtered[filtered["FREE_CAPACITY"] > 0]
        c1, c2, c3 = st.columns(3)
        c1.metric(t("free_count"), f"{len(free_all):,}".replace(",", "."))
        c2.metric(t("free_total"),
                  f"{int(free_all['FREE_CAPACITY'].sum()):,}".replace(",", "."))
        c3.metric(t("free_avg"),
                  f"{free_all['FREE_CAPACITY'].mean():.1f}"
                  if not free_all.empty else "—")

        if not free_all.empty:
            by_hall = (
                free_all.groupby("HALLE")["FREE_CAPACITY"].sum().reset_index()
            )
            st.plotly_chart(
                px.bar(by_hall, x="HALLE", y="FREE_CAPACITY",
                       title=t("free_byhall"),
                       labels=dict(FREE_CAPACITY=t("free_total"), HALLE=t("hall"))),
                use_container_width=True,
            )
        free = (
            free_all.sort_values("FREE_CAPACITY", ascending=False)
            .head(100)[
                ["PLATZ_ID", "HALLE", "REGAL", "FACH", "EBENE",
                 "MAX_LHM", "IST_LHM", "FREE_CAPACITY", "UTILIZATION"]
            ]
        )
        st.dataframe(free, use_container_width=True, hide_index=True)
        _csv_download(free, "free_capacity")

    # ----- Steuermassnahmen (Umlagern/Nachschub/Einlagern/Auslagern) -----
    # Jeder dieser vier Tabs zeigt mehrere "Kategorien" (z. B. dringend/
    # ueberfaellig). Eine Kategorie = eine nach Regeln gefilterte Teilmenge von
    # `filtered`. _massnahme_kategorie() rendert jede einheitlich: Titel,
    # Anzahl-Kennzahl, Tabelle und CSV-Download. Die Regeln (welche Plaetze in
    # welche Kategorie fallen) entsprechen der Logik der Flutter-App.
    _MASSNAHME_COLS = [
        "PLATZ_ID", "HALLE", "REGAL", "FACH", "EBENE",
        "ANZ_PICKS", "ABC_KLASSE", "MAX_LHM", "IST_LHM", "WERT",
    ]

    def _massnahme_kategorie(titel: str, beschreibung: str, df: pd.DataFrame,
                             extra_cols: list[str] | None = None,
                             vorschlag: str | None = None) -> None:
        """Rendert eine Massnahmen-Kategorie einheitlich (Titel + Tabelle + CSV).

        `vorschlag`: optionaler Text, der als zusaetzliche Spalte "Vorschlag"
        (konkrete Handlungsempfehlung) in jede Zeile geschrieben wird.
        """
        cols = _MASSNAHME_COLS + (extra_cols or [])
        cols = [c for c in cols if c in df.columns]
        st.markdown(f"**{titel}** — {beschreibung}")
        st.metric(t("cat_slots"), f"{len(df):,}".replace(",", "."))
        if df.empty:
            st.info(t("cat_empty"))
        else:
            show = df[cols].copy()
            if vorschlag:
                show[t("col_vorschlag")] = vorschlag
            st.dataframe(
                show.head(200), use_container_width=True, hide_index=True
            )
            key = "".join(c if c.isalnum() else "_" for c in titel.lower())
            _csv_download(show, f"massnahme_{key}")
        st.divider()

    with tab_umlagern:
        st.markdown(t("reloc_head"))
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
        # ZUSTAND < 150 = nicht gesperrt.
        unused_a = filtered[
            (filtered["ABC_KLASSE"] == "A")
            & (filtered["ANZ_PICKS"] == 0)
            & (filtered["ZUSTAND"] < 150)
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
            (filtered["FREE_CAPACITY"] > 0) & (filtered["ZUSTAND"] < 150)
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
                f"{r.PLATZ_ID} · {r.HALLE} R{int(r.REGAL)}/E{int(r.EBENE)} "
                f"(frei {int(r.FREE_CAPACITY)})"
                for r in tgt.itertuples(index=False)
            ]
            col = [labels[i] if i < len(labels) else t("ziel_none")
                   for i in range(len(src))]
            return src.assign(**{t("col_ziel"): col})

        if "A" in reloc_abc:
            _massnahme_kategorie(
                t("reloc_unusedA_t"), t("reloc_unusedA_d"),
                _add_ziel(unused_a, free_high),
                extra_cols=[t("col_ziel")], vorschlag=t("reloc_unusedA_v"))
        if "C" in reloc_abc:
            _massnahme_kategorie(
                t("reloc_hotC_t"), t("reloc_hotC_d"),
                _add_ziel(hot_c, free_low),
                extra_cols=[t("col_ziel")], vorschlag=t("reloc_hotC_v"))
        if "A" in reloc_abc:
            _massnahme_kategorie(
                t("reloc_highA_t"), t("reloc_highA_d"),
                _add_ziel(high_level_a, free_low),
                extra_cols=[t("col_ziel")], vorschlag=t("reloc_highA_v"))
        if not reloc_abc:
            st.info(t("reloc_pick_abc"))

    with tab_nachschub:
        st.markdown(t("replen_head"))
        c1, c2, c3 = st.columns(3)
        with c1:
            pick_level = st.slider(t("sl_picklevel"), 1, 6, 2)
        with c2:
            pick_threshold = st.slider(t("sl_pickthresh"), 10, 300, 50, step=10)
        with c3:
            overdue_days = st.slider(t("sl_overdue"), 3, 60, 14)

        # Basis: leere Pickplaetze (IST_LHM=0) in der Pickzone (niedrige Ebene),
        # nicht gesperrt. Daraus drei Dringlichkeitsstufen:
        empty_pick = filtered[
            (filtered["IST_LHM"].fillna(0) == 0)
            & (filtered["EBENE"] <= pick_level)
            & (filtered["ZUSTAND"] < 150)
        ]
        # dringend = leer + hohe Pickfrequenz
        urgent = empty_pick[empty_pick["ANZ_PICKS"] >= pick_threshold] \
            .sort_values("ANZ_PICKS", ascending=False)
        # ueberfaellig = dringend + schon zu lange leer (DAYS_EMPTY)
        overdue = urgent[urgent["DAYS_EMPTY"] >= overdue_days] \
            .sort_values("DAYS_EMPTY", ascending=False)

        _massnahme_kategorie(
            t("replen_urgent_t"), t("replen_urgent_d"), urgent,
            extra_cols=["DAYS_EMPTY"])
        _massnahme_kategorie(
            t("replen_overdue_t"),
            t("replen_overdue_d").format(n=overdue_days),
            overdue, extra_cols=["DAYS_EMPTY"])

    with tab_einlagern:
        st.markdown(t("put_head"))
        fast_level = st.slider(t("sl_fastlevel"), 1, 6, 2)
        free_slots = filtered[filtered["FREE_CAPACITY"] > 0]

        # Schnelldreher-Plaetze: freie A-Plaetze auf niedriger Ebene -> kurze
        # Wege. Schwelle ueber den Slider fast_level einstellbar.
        fast_lane = free_slots[
            (free_slots["ABC_KLASSE"] == "A")
            & (free_slots["EBENE"] <= fast_level)
            & (free_slots["ZUSTAND"] < 150)
        ].sort_values("FREE_CAPACITY", ascending=False)

        _massnahme_kategorie(
            t("put_fast_t"), t("put_fast_d").format(n=fast_level),
            fast_lane, extra_cols=["FREE_CAPACITY"])

    with tab_auslagern:
        st.markdown(t("retr_head"))
        c1, c2 = st.columns(2)
        with c1:
            # Pickzone: nur niedrige Ebenen betrachten. 88% aller Plaetze haben
            # 0 Picks (v.a. Reserve weit oben) -> ohne diese Grenze waeren die
            # 0-Pick-Listen unbrauchbar gross. Standard: bis Ebene 2.
            retr_zone = st.slider(t("sl_retrzone"), 1, 6, 2)
        with c2:
            observe_max = st.slider(t("sl_observe"), 1, 50, 5)
        belegt = filtered[
            (filtered["BELEGT"])
            & (filtered["ZUSTAND"] < 150)
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

        _massnahme_kategorie(
            t("retr_crit_t"), t("retr_crit_d"), critical)
        _massnahme_kategorie(
            t("retr_stale_t"), t("retr_stale_d"), stale)
        _massnahme_kategorie(
            t("retr_observe_t"),
            t("retr_observe_d").format(n=observe_max), observe)

    with tab_abc:
        abc_mode = st.radio(
            t("abc_mode"),
            options=[t("abc_by_slots"), t("abc_by_articles")],
            horizontal=True,
        )
        by_articles = abc_mode == t("abc_by_articles")

        cc1, cc2 = st.columns(2)
        with cc1:
            a_thr = st.slider(t("abc_a_thresh"), 50, 95, 80, step=1)
        with cc2:
            b_thr = st.slider(t("abc_b_thresh"), a_thr + 1, 99, max(a_thr + 1, 95),
                              step=1)

        abc_color = {"A": "#c62828", "B": "#f9a825", "C": "#2e7d32"}

        if by_articles:
            st.markdown(t("abc_intro_articles"))
            _mov_filter_note()
            base = agg_articles(tpa)
            data = classify_abc(base, "bewegungen", a_thr, b_thr) \
                if not base.empty else base
            table_cols = ["artikel", "bezeichnung", "bewegungen", "CUM_%", "ABC"]
        else:
            st.markdown(t("abc_intro"))
            data = classify_abc(filtered, "ANZ_PICKS", a_thr, b_thr)
            table_cols = ["PLATZ_ID", "HALLE", "REGAL", "FACH", "EBENE",
                          "ANZ_PICKS", "CUM_%", "ABC_KLASSE", "ABC"]

        if data.empty:
            st.info(t("no_data_filters"))
        else:
            # Verteilung (Pie + Anzahl je Klasse)
            counts = data["ABC"].value_counts().reindex(["A", "B", "C"]).fillna(0)
            d1, d2 = st.columns([2, 1])
            with d1:
                st.plotly_chart(
                    px.pie(names=counts.index, values=counts.values,
                           color=counts.index, color_discrete_map=abc_color,
                           title=t("abc_dist")),
                    use_container_width=True,
                )
            with d2:
                st.markdown(f"**{t('abc_count')}**")
                for klasse in ["A", "B", "C"]:
                    st.metric(klasse, f"{int(counts[klasse]):,}".replace(",", "."))

            # Stamm vs. berechnet — nur bei Platz-Sicht (Artikel haben kein Stamm-ABC)
            if not by_articles:
                # ABC-Anpassung: Abweichungen Stamm vs. berechnet + Empfehlung.
                # Trick: A/B/C als Rang 3/2/1. Ist die berechnete Klasse hoeher
                # als die hinterlegte (_c > _m), wird der Platz mehr bewegt als
                # gedacht -> "Hochstufen"; umgekehrt -> "Herabstufen".
                st.markdown(t("abc_adjust_head"))
                st.markdown(t("abc_adjust_intro"))
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
                    mcols[0].metric(t("abc_promote"), f"{n_prom:,}".replace(",", "."))
                    mcols[1].metric(t("abc_demote"), f"{n_dem:,}".replace(",", "."))
                    dev_tbl = dev.sort_values("ANZ_PICKS", ascending=False)[
                        ["PLATZ_ID", "HALLE", "REGAL", "FACH", "EBENE",
                         "ANZ_PICKS", "ABC_KLASSE", "ABC", t("abc_rec")]
                    ].rename(columns={"ABC_KLASSE": "Stamm", "ABC": "Berechnet"}).head(200)
                    st.dataframe(dev_tbl, use_container_width=True, hide_index=True)
                    _csv_download(dev_tbl, "abc_anpassung")

            st.markdown(t("abc_byfreq"))
            table = data[[c for c in table_cols if c in data.columns]].head(200)
            st.dataframe(table, use_container_width=True, hide_index=True)
            _csv_download(table, "abc_articles" if by_articles else "abc_slots")

    with sub_trend:
        st.markdown(t("tp_intro"))
        _mov_filter_note()
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
        if trend.empty:
            st.info(t("no_data_filters"))
        else:
            fig = px.line(
                trend, x="day", y="movements", markers=True,
                title=t("tp_chart").format(n=len(trend)),
            )
            fig.update_layout(
                yaxis_title=t("picks_label"),
                xaxis_title="Date" if _LANG == "en" else "Datum",
            )
            st.plotly_chart(fig, use_container_width=True)

            c1, c2, c3 = st.columns(3)
            c1.metric(t("tp_avg"), f"{trend['movements'].mean():.0f}")
            c2.metric(t("tp_max"), f"{int(trend['movements'].max()):,}".replace(",", "."))
            c3.metric(t("tp_sum"),
                      f"{int(trend['movements'].sum()):,}".replace(",", "."))

            tbl = trend.copy()
            tbl["day"] = tbl["day"].dt.strftime("%Y-%m-%d")
            tbl = tbl.rename(columns={"day": "Datum", "movements": "Bewegungen"})
            tbl = tbl.sort_values("Datum", ascending=False)
            st.dataframe(tbl, use_container_width=True, hide_index=True)
            _csv_download(tbl, "durchsatz")

    with sub_top:
        st.markdown(t("top_intro"))
        _mov_filter_note()
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
            st.dataframe(top, use_container_width=True, hide_index=True)
            _csv_download(top, "top_artikel")

    with tab_article:
        st.markdown(t("art_intro"))
        _mov_filter_note()
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
                m1.metric(t("art_total"), f"{total:,}".replace(",", "."))
                m2.metric(t("art_slotcount"),
                          f"{len(slots):,}".replace(",", "."))
                if not day_df.empty:
                    st.markdown(f"**{t('art_trend')}**")
                    st.plotly_chart(
                        px.line(day_df, x="day", y="picks", markers=True,
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

    with tab_3d:
        import json as _json

        st.markdown(t("d3_click_intro"))

        # Klickbares Modell: SampleScene_clickable.glb hat eine intakte
        # Hierarchie, deren Blatt-Meshes nach PLATZ_ID benannt sind. Der
        # three.js-Viewer (eingebettet via components.html) wirft beim Klick
        # einen Strahl ins Modell (Raycasting), liest den getroffenen
        # PLATZ_ID-Namen und schlaegt seine Kennzahlen in der unten injizierten
        # JSON-Map nach. GLB wird CORS-faehig ueber die API geliefert.
        glb_url = "https://ssi-lagerview-api.onrender.com/model-clickable.glb"

        # Modell dreht sich bewusst NICHT von allein (auf Wunsch). Drehen geht
        # weiterhin manuell per Ziehen mit der Maus.
        ctrl1, ctrl2, ctrl3 = st.columns([1, 1, 1])
        with ctrl1:
            color_abc = st.checkbox(t("d3_color_abc"), value=True)
        with ctrl2:
            perf_mode = st.checkbox(t("d3_perf"), value=False, help=t("d3_perf_help"))
        with ctrl3:
            viewer_height = st.slider(t("d3_height"), 360, 900, 640, step=20)

        slot_json = load_slot_3d_map()
        labels = {
            "hint": t("d3_panel_hint"),
            "platz": t("d3_f_platz"),
            "pos": t("d3_f_pos"),
            "halle": t("hall"),
            "abc_m": t("d3_f_abc_m"),
            "abc_c": t("d3_f_abc_c"),
            "picks": t("d3_f_picks"),
            "util": t("d3_f_util"),
            "status": t("d3_f_status"),
            "occupied": t("d3_occupied"),
            "empty": t("d3_empty"),
            "notdb": t("d3_not_in_db"),
            "legend": t("d3_legend"),
            "grey": t("d3_grey"),
            "loading": "Lade Modell" if _LANG == "de" else "Loading model",
        }

        html = (
            _THREE_VIEWER_HTML
            .replace("__HEIGHT__", str(viewer_height))
            .replace("__GLB__", glb_url)
            .replace("__DATA__", slot_json)
            .replace("__LABELS__", _json.dumps(labels, ensure_ascii=False))
            .replace("__ROTATE__", "false")
            .replace("__ABCCOLOR__", "true" if color_abc else "false")
            .replace("__HIDEGREY__", "true" if perf_mode else "false")
        )
        components.html(html, height=viewer_height + 16)
        st.caption(t("d3_caption"))

        st.divider()
        st.markdown(t("abc3d_head"))
        st.markdown(t("abc3d_intro"))

        a1, a2 = st.columns([1, 1])
        with a1:
            src_opts = [t("abc3d_calc"), t("abc3d_master")]
            src_choice = st.radio(t("abc3d_src"), src_opts, horizontal=True)
            abc_col = "ABC_KLASSE" if src_choice == t("abc3d_master") else "ABC_CALC"
        with a2:
            sel_classes = st.multiselect(
                t("abc3d_classfilter"), options=["A", "B", "C"], default=["A", "B", "C"],
            )

        if filtered.empty:
            st.info(t("no_data_filters"))
        else:
            df_abc = filtered.copy()
            df_abc["ABC"] = df_abc[abc_col].where(
                df_abc[abc_col].isin(["A", "B", "C"]), "—"
            )
            if sel_classes:
                df_abc = df_abc[df_abc["ABC"].isin(sel_classes)]

            counts = df_abc["ABC"].value_counts().reindex(["A", "B", "C"]).fillna(0)
            mc = st.columns(3)
            mc[0].metric("A", f"{int(counts['A']):,}".replace(",", "."))
            mc[1].metric("B", f"{int(counts['B']):,}".replace(",", "."))
            mc[2].metric("C", f"{int(counts['C']):,}".replace(",", "."))

            abc_tbl = (
                df_abc.sort_values(["ABC", "ANZ_PICKS"], ascending=[True, False])[
                    ["PLATZ_ID", "HALLE", "REGAL", "FACH", "EBENE",
                     "ANZ_PICKS", "ABC"]
                ]
            )
            st.dataframe(abc_tbl, use_container_width=True, hide_index=True)
            _csv_download(abc_tbl, "abc_je_platz")


if __name__ == "__main__":
    main()
