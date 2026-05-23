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

PLATZ_TABLE = "df_platz_ber03_schlg_rti3"
PALETTE_TABLE = "df_palette_08042026_ber03_schlg_rti3"
TPA_TABLE = "df_tpa_6mon_ber03_schlg_rti3"
FAHRPOS_TABLE = "df_fahrpos_6mon_ber03_schlg_rti3"

_DB_CANDIDATES = [
    Path("data/warehouse.db"),
    Path("backend/data/warehouse.db"),
    Path("data/warehouse_sample.db"),
    Path("backend/data/warehouse_sample.db"),
    Path("warehouse.db"),
]

# --- Zweisprachigkeit (DE/EN) ---------------------------------------------
# Tabellen-Spaltennamen (Datenfelder) bleiben absichtlich unuebersetzt.
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
    "m_overloaded": {"de": "Ueberlastet (>100 %)", "en": "Overloaded (>100%)"},
    # Tab-Titel
    "tab_halls": {"de": "Hallen", "en": "Halls"},
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
        "de": "### 🔄 Umlagern\nDatenbasierte Umlager-Vorschläge (gleiche Logik wie die App).",
        "en": "### 🔄 Relocate\nData-driven relocation suggestions (same logic as the app).",
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
    "sl_reservelevel": {"de": "Reserve-Ebene ab", "en": "Reserve level from"},
    "put_fast_t": {"de": "Fast-Lane (Schnelldreher)", "en": "Fast lane (fast movers)"},
    "put_fast_d": {
        "de": "Freie A-Plätze auf niedriger Ebene – ideal für Schnelldreher.",
        "en": "Free A slots on low level – ideal for fast movers.",
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
}


def t(key: str) -> str:
    entry = TR.get(key)
    if not entry:
        return key
    return entry.get(_LANG, entry.get("de", key))


@st.cache_resource(show_spinner="Lade DB ...")
def get_db_path() -> str:
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
    """Stellplatz-Tabelle mit Utilization, Halle und Pick-Count gemerged."""
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

    platz["UTILIZATION"] = np.where(
        platz["MAX_LHM"] > 0,
        (platz["IST_LHM"] / platz["MAX_LHM"]) * 100,
        np.nan,
    )
    platz["FREE_CAPACITY"] = (platz["MAX_LHM"].fillna(0) - platz["IST_LHM"].fillna(0))
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

    # ABC nach kumulativer Pick-Verteilung (aus warehouse_analytics.py).
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


@st.cache_data(ttl=3600)
def load_throughput_trend(days: int = 30) -> pd.DataFrame:
    con = get_connection()
    df = pd.read_sql_query(
        f"""
        SELECT DATE(ENDE_DATUM) AS day, COUNT(*) AS movements
        FROM "{TPA_TABLE}"
        WHERE TRIM(COALESCE(ENDE_DATUM, '')) <> ''
        GROUP BY DATE(ENDE_DATUM)
        ORDER BY DATE(ENDE_DATUM) DESC
        LIMIT ?
        """,
        con,
        params=[days],
    )
    df["day"] = pd.to_datetime(df["day"], errors="coerce")
    return df.dropna(subset=["day"]).sort_values("day")


@st.cache_data(ttl=3600)
def load_top_articles(limit: int = 25) -> pd.DataFrame:
    con = get_connection()
    return pd.read_sql_query(
        f"""
        SELECT TRIM(ARTIKELNR) AS artikel,
               TRIM(COALESCE(ARTBEZ1, '')) AS bezeichnung,
               COUNT(*) AS bewegungen
        FROM "{TPA_TABLE}"
        WHERE TRIM(COALESCE(ARTIKELNR, '')) <> ''
        GROUP BY artikel
        ORDER BY bewegungen DESC
        LIMIT ?
        """,
        con,
        params=[limit],
    )


@st.cache_data(ttl=3600, show_spinner="Lade Pick-Heatmap ...")
def load_pick_heatmap() -> pd.DataFrame:
    """Picks je Wochentag (0=So..6=Sa) und Stunde aus den TPA-Bewegungen."""
    con = get_connection()
    return pd.read_sql_query(
        f"""
        SELECT CAST(strftime('%w', ENDE_DATUM) AS INTEGER) AS weekday,
               CAST(substr(ENDE_ZEIT, 1, 2) AS INTEGER) AS hour,
               COUNT(*) AS picks
        FROM "{TPA_TABLE}"
        WHERE TRIM(COALESCE(ENDE_DATUM, '')) <> ''
          AND TRIM(COALESCE(ENDE_ZEIT, '')) <> ''
        GROUP BY weekday, hour
        """,
        con,
    )


def heatmap_color(util: float) -> str:
    """Aus warehouse_heatmap.py."""
    if pd.isna(util):
        return "GREY"
    if util >= 80:
        return "RED"
    if util >= 40:
        return "YELLOW"
    return "GREEN"


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
    global _LANG
    _LANG = "en" if st.sidebar.radio(
        TR["lang_label"]["de"], ["Deutsch", "English"], horizontal=True,
    ) == "English" else "de"

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

    filtered = apply_filters(
        platz, hallen, abc, util_range, only_occupied,
        regal_range=regal_range,
        ebene_range=ebene_range,
        min_picks=min_picks,
        sperr_mode=sperr_mode,
    )

    total = len(filtered) or 1
    occupied = int(filtered["BELEGT"].sum())
    overloaded = int((filtered["UTILIZATION"] > 100).sum())
    avg_util = filtered["UTILIZATION"].mean()

    c1, c2, c3, c4 = st.columns(4)
    c1.metric(t("m_slots"), f"{len(filtered):,}".replace(",", "."))
    c2.metric(t("m_occupied"), f"{occupied:,}".replace(",", "."),
              f"{occupied/total*100:.1f}%")
    c3.metric(t("m_avg_util"),
              f"{avg_util:.1f} %" if not pd.isna(avg_util) else "—")
    c4.metric(t("m_overloaded"), f"{overloaded:,}".replace(",", "."))

    (tab_hallen, tab_heat, tab_pickheat, tab_bottle, tab_free, tab_umlagern,
     tab_nachschub, tab_einlagern, tab_auslagern, tab_abc, tab_trend, tab_top,
     tab_3d) = st.tabs([
        t("tab_halls"),
        t("tab_util"),
        t("tab_pick"),
        t("tab_bottle"),
        t("tab_free"),
        t("tab_relocate"),
        t("tab_replenish"),
        t("tab_putaway"),
        t("tab_retrieve"),
        t("tab_abc"),
        t("tab_tp"),
        t("tab_top"),
        t("tab_3d"),
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

    with tab_heat:
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

    with tab_pickheat:
        st.markdown(t("pick_intro"))
        ph = load_pick_heatmap()
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

    with tab_bottle:
        st.markdown(t("bottle_intro"))
        bottlenecks = (
            filtered.assign(
                PICK_TOTAL=lambda d: d["ANZ_PICKS"] + d["PICK_COUNT_FAHR"]
            )
            .sort_values(["PICK_TOTAL", "UTILIZATION"], ascending=[False, False])
            .head(50)[
                ["PLATZ_ID", "HALLE", "REGAL", "FACH", "EBENE",
                 "ANZ_PICKS", "PICK_COUNT_FAHR", "PICK_TOTAL", "UTILIZATION"]
            ]
        )
        if bottlenecks.empty:
            st.info(t("no_data_filters"))
        else:
            # Tabelle zuerst, damit sie auch erscheint, falls das Diagramm hakt.
            st.dataframe(bottlenecks, use_container_width=True, hide_index=True)
            _csv_download(bottlenecks, "bottlenecks")
            try:
                top15 = bottlenecks.head(15).copy()
                top15["UTILIZATION"] = top15["UTILIZATION"].fillna(0)
                top15 = top15.sort_values("PICK_TOTAL")
                st.plotly_chart(
                    px.bar(
                        top15, x="PICK_TOTAL", y="PLATZ_ID", orientation="h",
                        color="UTILIZATION", color_continuous_scale="RdYlGn_r",
                        range_color=[0, 120],
                        title=t("bottle_chart"),
                        labels=dict(PICK_TOTAL="Picks gesamt", PLATZ_ID="Platz"),
                    ),
                    use_container_width=True,
                )
            except Exception as exc:  # Diagramm ist optional, Tabelle zaehlt.
                st.caption(f"(Diagramm konnte nicht gezeichnet werden: {exc})")

    with tab_free:
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

    _MASSNAHME_COLS = [
        "PLATZ_ID", "HALLE", "REGAL", "FACH", "EBENE",
        "ANZ_PICKS", "ABC_KLASSE", "MAX_LHM", "IST_LHM",
    ]

    def _massnahme_kategorie(titel: str, beschreibung: str, df: pd.DataFrame,
                             extra_cols: list[str] | None = None) -> None:
        cols = _MASSNAHME_COLS + (extra_cols or [])
        cols = [c for c in cols if c in df.columns]
        st.markdown(f"**{titel}** — {beschreibung}")
        st.metric(t("cat_slots"), f"{len(df):,}".replace(",", "."))
        if df.empty:
            st.info(t("cat_empty"))
        else:
            st.dataframe(
                df.head(200)[cols], use_container_width=True, hide_index=True
            )
            key = "".join(c if c.isalnum() else "_" for c in titel.lower())
            _csv_download(df[cols], f"massnahme_{key}")
        st.divider()

    with tab_umlagern:
        st.markdown(t("reloc_head"))
        c1, c2 = st.columns(2)
        with c1:
            hot_c_threshold = st.slider(t("sl_hotc"), 10, 300, 100, step=10)
        with c2:
            high_level = st.slider(t("sl_highlevel"), 2, 6, 4)

        unused_a = filtered[
            (filtered["ABC_KLASSE"] == "A")
            & (filtered["ANZ_PICKS"] == 0)
            & (filtered["ZUSTAND"] < 150)
        ].sort_values(["REGAL", "EBENE", "FACH"])
        hot_c = filtered[
            (filtered["ABC_KLASSE"] == "C")
            & (filtered["ANZ_PICKS"] >= hot_c_threshold)
        ].sort_values("ANZ_PICKS", ascending=False)
        high_level_a = filtered[
            (filtered["ABC_KLASSE"] == "A")
            & (filtered["EBENE"] >= high_level)
            & (filtered["ANZ_PICKS"] > 0)
        ].sort_values("ANZ_PICKS", ascending=False)

        _massnahme_kategorie(
            t("reloc_unusedA_t"), t("reloc_unusedA_d"), unused_a)
        _massnahme_kategorie(
            t("reloc_hotC_t"), t("reloc_hotC_d"), hot_c)
        _massnahme_kategorie(
            t("reloc_highA_t"), t("reloc_highA_d"), high_level_a)

    with tab_nachschub:
        st.markdown(t("replen_head"))
        c1, c2, c3 = st.columns(3)
        with c1:
            pick_level = st.slider(t("sl_picklevel"), 1, 6, 2)
        with c2:
            pick_threshold = st.slider(t("sl_pickthresh"), 10, 300, 50, step=10)
        with c3:
            overdue_days = st.slider(t("sl_overdue"), 3, 60, 14)
        medium_threshold = max(1, pick_threshold // 2)

        empty_pick = filtered[
            (filtered["IST_LHM"].fillna(0) == 0)
            & (filtered["EBENE"] <= pick_level)
            & (filtered["ZUSTAND"] < 150)
        ]
        urgent = empty_pick[empty_pick["ANZ_PICKS"] >= pick_threshold] \
            .sort_values("ANZ_PICKS", ascending=False)
        overdue = urgent[urgent["DAYS_EMPTY"] >= overdue_days] \
            .sort_values("DAYS_EMPTY", ascending=False)
        medium = empty_pick[
            (empty_pick["ANZ_PICKS"] >= medium_threshold)
            & (empty_pick["ANZ_PICKS"] < pick_threshold)
        ].sort_values("ANZ_PICKS", ascending=False)

        _massnahme_kategorie(
            t("replen_urgent_t"), t("replen_urgent_d"), urgent,
            extra_cols=["DAYS_EMPTY"])
        _massnahme_kategorie(
            t("replen_overdue_t"),
            t("replen_overdue_d").format(n=overdue_days),
            overdue, extra_cols=["DAYS_EMPTY"])
        _massnahme_kategorie(
            t("replen_medium_t"), t("replen_medium_d"), medium)

    with tab_einlagern:
        st.markdown(t("put_head"))
        reserve_level = st.slider(t("sl_reservelevel"), 2, 6, 3)
        free_slots = filtered[filtered["FREE_CAPACITY"] > 0]

        fast_lane = free_slots[
            (free_slots["ABC_KLASSE"] == "A")
            & (free_slots["EBENE"] <= 2)
            & (free_slots["ZUSTAND"] < 150)
        ].sort_values("FREE_CAPACITY", ascending=False)
        reserve = free_slots[
            (free_slots["EBENE"] >= reserve_level)
            & (free_slots["ZUSTAND"] < 150)
        ].sort_values("FREE_CAPACITY", ascending=False)
        blocked = filtered[filtered["ZUSTAND"] >= 150] \
            .sort_values("REGAL")

        _massnahme_kategorie(
            t("put_fast_t"), t("put_fast_d"),
            fast_lane, extra_cols=["FREE_CAPACITY"])
        _massnahme_kategorie(
            t("put_reserve_t"),
            t("put_reserve_d").format(n=reserve_level),
            reserve, extra_cols=["FREE_CAPACITY"])
        _massnahme_kategorie(
            t("put_blocked_t"), t("put_blocked_d"), blocked)

    with tab_auslagern:
        st.markdown(t("retr_head"))
        observe_max = st.slider(t("sl_observe"), 1, 50, 5)
        belegt = filtered[
            (filtered["BELEGT"]) & (filtered["ZUSTAND"] < 150)
        ]

        critical = belegt[
            (belegt["ABC_KLASSE"] == "A") & (belegt["ANZ_PICKS"] == 0)
        ].sort_values(["REGAL", "EBENE", "FACH"])
        stale = belegt[
            (belegt["ABC_KLASSE"] != "A") & (belegt["ANZ_PICKS"] == 0)
        ].sort_values(["REGAL", "EBENE", "FACH"])
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
        st.markdown(t("abc_intro"))
        abc_counts = (
            filtered["ABC_CALC"].value_counts().reindex(["A", "B", "C"]).fillna(0)
        )
        fig = px.pie(
            names=abc_counts.index,
            values=abc_counts.values,
            color=abc_counts.index,
            color_discrete_map={"A": "#c62828", "B": "#f9a825", "C": "#2e7d32"},
            title=t("abc_chart"),
        )
        st.plotly_chart(fig, use_container_width=True)

        st.markdown(t("abc_cross_intro"))
        cross = pd.crosstab(
            filtered["ABC_KLASSE"].replace("", "—"),
            filtered["ABC_CALC"].fillna("—"),
        )
        st.dataframe(cross, use_container_width=True)

        st.markdown(t("abc_byfreq"))
        abc_table = filtered.sort_values("ANZ_PICKS", ascending=False).head(100)[
            ["PLATZ_ID", "HALLE", "REGAL", "FACH", "EBENE",
             "ANZ_PICKS", "CUMULATIVE_%", "ABC_KLASSE", "ABC_CALC"]
        ]
        st.dataframe(abc_table, use_container_width=True, hide_index=True)
        _csv_download(abc_table, "abc_analyse")

    with tab_trend:
        st.markdown(t("tp_intro"))
        trend = load_throughput_trend(days)
        if trend.empty:
            st.info(t("no_data_filters"))
        else:
            fig = px.line(
                trend, x="day", y="movements", markers=True,
                title=t("tp_chart").format(n=days),
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

    with tab_top:
        st.markdown(t("top_intro"))
        top = load_top_articles(article_limit)
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

    with tab_3d:
        # GitHub-Release-Assets senden kein CORS -> der Browser wuerde das
        # Modell blocken. Daher ueber den CORS-faehigen API-Proxy laden
        # (gleiche Quelle wie die Flutter-App).
        glb_url = "https://ssi-lagerview-api.onrender.com/model.glb"

        # --- 3D-Steuerelemente ---
        ctrl1, ctrl2, ctrl3, ctrl4 = st.columns([1, 1, 1, 1])
        with ctrl1:
            auto_rotate = st.checkbox(t("d3_autorotate"), value=False)
        with ctrl2:
            exposure = st.slider(t("d3_brightness"), 0.2, 2.0, 1.0, step=0.1)
        with ctrl3:
            shadow = st.slider(t("d3_shadow"), 0.0, 2.0, 0.8, step=0.1)
        with ctrl4:
            viewer_height = st.slider(t("d3_height"), 360, 900, 640, step=20)
        bg = "#f5f5f7"
        if st.button(t("d3_reset")):
            st.rerun()

        rotate_attr = 'auto-rotate auto-rotate-delay="0"' if auto_rotate else ""
        components.html(
            f"""
<script type="module"
    src="https://unpkg.com/@google/model-viewer/dist/model-viewer.min.js">
</script>
<div style="width:100%;height:{viewer_height}px;background:{bg};border-radius:8px;">
  <model-viewer
      src="{glb_url}"
      alt="Schaeflein BER03 Lager"
      camera-controls
      {rotate_attr}
      touch-action="pan-y"
      shadow-intensity="{shadow}"
      exposure="{exposure}"
      style="width:100%;height:100%;background-color:{bg};">
  </model-viewer>
</div>
            """,
            height=viewer_height + 20,
        )
        st.caption(t("d3_caption"))


if __name__ == "__main__":
    main()
