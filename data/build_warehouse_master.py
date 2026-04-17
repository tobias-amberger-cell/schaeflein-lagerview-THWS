"""
================================================================================
WAREHOUSE AI MASTER – Build Pipeline
================================================================================
Ziel    : Fünf Logistik-CSVs → warehouse_ai_master.csv (KI-ready)
Autor   : Senior Data Engineer (Claude)
Erstellt: 2026-04-16
================================================================================

JOIN-PROTOKOLL (Annahmen transparent dokumentiert)
────────────────────────────────────────────────────
1. KERN-ANKER: df_platz  (Stamm aller Lagerplätze, PLATZ_ID = natürlicher PK)

2. platz ← palette via  palette.PLATZ = platz.PLATZ_ID  (str, 9-stellig, 100 % Match)
   → liefert: PALNR, ZUSTAND (Palette), GEWICHT, LHM_TYP, AUFTRAGSNR

3. platz ← fahrpos via  fahrpos.Q_PLATZ = platz.PLATZ_ID  (int→str Mapping, 99.4 % Match)
   → liefert: Bewegungsdaten (BEGINN/ENDE-Timestamps), ARTIKELNR, MENGE_IST, TYP
   ANNAHME: Q_PLATZ (Quell-Platz der Fahrbewegung) entspricht dem Lagerplatz;
            Z_PLATZ (Ziel) ist meistens 'WA0000000' (Warenausgang) → nicht lagerplatz-relevant.

4. fahrpos ← order via  (AUFTRAGSNR, AUFTRAGSPOS, MANDANT) – 3-Part-Key
   → liefert: ARTBEZ1 (Artikelbezeichnung), normierte MENGE_SOLL
   ANNAHME: order ist Positionsebene; LEFT JOIN, da nicht jede Fahrposition
            zwingend einen Auftrag hat (interne Bewegungen / TPA).

5. platz ← tpa via  tpa.Q_PLATZ = platz.PLATZ_ID  (str, direkt)
   ANNAHME: TPA = Transport-Palette-Aufträge; Q_PLATZ = Entnahme-Lagerplatz.
            Zusätzlich: tpa enthält PALNR → kann mit palette verknüpft werden.
   → liefert: TPA-Bewegungsanzahl je Platz (alternative Frequenz-Quelle)

PLATZ_ID-Format
────────────────
 platz.PLATZ_ID  : String '031901200'  (9-stellig, führende 0)
 fahrpos.Q_PLATZ : Integer  31901200   (8-stellig ohne führende 0)
 palette.PLATZ   : String '032006201'  (9-stellig, mit führender 0)
 tpa.Q_PLATZ     : String '03EN00900'  (Mix: numerisch + alphanumerisch)
 → fahrpos.Q_PLATZ wird mit zfill(9) in String umgewandelt für den Join.
 → tpa.Q_PLATZ ist direkt verwendbar (str).
================================================================================
"""

import pandas as pd
import numpy as np
from datetime import datetime, date
import warnings
warnings.filterwarnings('ignore')

SNAPSHOT_TS = datetime.now().strftime('%Y-%m-%dT%H:%M:%S')
DATA_DIR    = '/mnt/user-data/uploads/'
OUTPUT_PATH = '/mnt/user-data/outputs/warehouse_ai_master.csv'

# ══════════════════════════════════════════════════════════════════════════════
# 0. HILFSFUNKTIONEN
# ══════════════════════════════════════════════════════════════════════════════

def combine_date_time(df, date_col, time_col, out_col):
    """Kombiniert getrennte Datum- und Zeit-Spalten zu einem ISO-Timestamp."""
    mask = df[date_col].notna() & df[time_col].notna()
    combined = pd.NaT
    try:
        combined = pd.to_datetime(
            df.loc[mask, date_col].astype(str) + ' ' + df.loc[mask, time_col].astype(str),
            errors='coerce'
        )
    except Exception:
        pass
    result = pd.Series(pd.NaT, index=df.index)
    result[mask] = combined
    df[out_col] = result
    return df

def safe_to_numeric(series):
    return pd.to_numeric(series, errors='coerce')

dq = {}  # Data-Quality-Report Sammler

# ══════════════════════════════════════════════════════════════════════════════
# 1. DATEN LADEN
# ══════════════════════════════════════════════════════════════════════════════
print("█ [1/7] Lade CSVs ...")

fahrpos = pd.read_csv(DATA_DIR + 'df_fahrpos_6mon_ber03_schlg_rti3.csv',  low_memory=False)
order   = pd.read_csv(DATA_DIR + 'df_order_6mon_schlg_rti3.csv',          low_memory=False)
palette = pd.read_csv(DATA_DIR + 'df_palette_08042026_ber03_schlg_rti3.csv', low_memory=False)
platz   = pd.read_csv(DATA_DIR + 'df_platz_ber03_schlg_rti3.csv',         low_memory=False)
tpa     = pd.read_csv(DATA_DIR + 'df_tpa_6mon_ber03_schlg_rti3.csv',      low_memory=False)

# Initiale Zeilenzählung
dq['initial_rows'] = {
    'fahrpos': len(fahrpos),
    'order'  : len(order),
    'palette': len(palette),
    'platz'  : len(platz),
    'tpa'    : len(tpa),
}
print(f"   fahrpos: {len(fahrpos):>8,} Zeilen | order: {len(order):>9,} | "
      f"palette: {len(palette):>6,} | platz: {len(platz):>6,} | tpa: {len(tpa):>6,}")

# ══════════════════════════════════════════════════════════════════════════════
# 2. CLEANING & NORMALISIERUNG JE TABELLE
# ══════════════════════════════════════════════════════════════════════════════
print("\n█ [2/7] Cleaning & Normalisierung ...")

# ── 2a. PLATZ (Lagerplatz-Stamm) ──────────────────────────────────────────
# PLATZ_ID normalisieren: immer 9-stelliger String
platz['PLATZ_ID'] = platz['PLATZ_ID'].astype(str).str.strip()

# Duplikate nach PLATZ_ID: echten Platz behalten (neueste Änderung)
platz['_ModificationDate'] = pd.to_datetime(platz['_ModificationDate'], errors='coerce')
platz = platz.sort_values('_ModificationDate', ascending=False).drop_duplicates('PLATZ_ID')

# IST_LHM / MAX_LHM bereinigen (negativ → 0)
for col in ['IST_LHM', 'MAX_LHM', 'FREI_LHM', 'KAPA']:
    platz[col] = safe_to_numeric(platz[col]).clip(lower=0)

# Belegungsstatus: IST_LHM > 0 → belegt
platz['aktueller_belegt_status'] = (platz['IST_LHM'] > 0).astype(int)

# Belegungsquote je Platz (0–1)
platz['belegungsquote_platz'] = np.where(
    platz['MAX_LHM'] > 0,
    (platz['IST_LHM'] / platz['MAX_LHM']).clip(0, 1),
    np.nan
)

# Koordinaten aus KO_BEREICH / KO_GANG / KO_FACH ableiten
platz['x_koord'] = safe_to_numeric(platz['KO_BEREICH'])
platz['y_koord'] = safe_to_numeric(platz['KO_GANG'])
platz['z_koord'] = safe_to_numeric(platz['KO_FACH'])

# ZUGRIFF-Timestamp (letzter Zugriff bekannt)
platz = combine_date_time(platz, 'ZUGRIFF_DATUM', 'ZUGRIFF_ZEIT', 'ts_letzter_zugriff')

# SPERR_KNZ: 0 = frei, sonst gesperrt
platz['ist_gesperrt'] = (safe_to_numeric(platz['SPERR_KNZ']) > 0).astype(int)

dq['drops_platz'] = dq['initial_rows']['platz'] - len(platz)
print(f"   platz:   {len(platz):>6,} Zeilen nach Dedup (Drops: {dq['drops_platz']})")

# ── 2b. PALETTE (Aktuell belegte Paletten) ────────────────────────────────
# PLATZ ebenfalls als 9-stelligen String
palette['PLATZ'] = palette['PLATZ'].astype(str).str.strip().str.zfill(9)
palette['PALNR'] = safe_to_numeric(palette['PALNR'])

# Duplikate: neueste Palette pro Lagerplatz (eine Palette pro Platz → Snapshot)
palette['_ModificationDate'] = pd.to_datetime(palette['_ModificationDate'], errors='coerce')
palette = palette.sort_values('_ModificationDate', ascending=False).drop_duplicates('PLATZ')

# Zustand-Mapping (WMS-typisch): 401 = eingelagert, andere = in Bewegung etc.
palette['palette_zustand'] = safe_to_numeric(palette['ZUSTAND'])

dq['drops_palette'] = dq['initial_rows']['palette'] - len(palette)
print(f"   palette: {len(palette):>6,} Zeilen nach Dedup (Drops: {dq['drops_palette']})")

# ── 2c. FAHRPOS (Fahrbewegungen der letzten 6 Monate) ────────────────────
# Q_PLATZ → 9-stelliger String (führende Null ergänzen)
fahrpos['Q_PLATZ_str'] = safe_to_numeric(fahrpos['Q_PLATZ']).dropna().astype(int).astype(str).str.zfill(9)
fahrpos['Q_PLATZ_str'] = fahrpos.get('Q_PLATZ', pd.Series(dtype=str))
fahrpos['Q_PLATZ_str'] = safe_to_numeric(fahrpos['Q_PLATZ']).apply(
    lambda x: str(int(x)).zfill(9) if pd.notna(x) else np.nan
)

# Timestamps zusammenbauen
fahrpos = combine_date_time(fahrpos, 'BEGINN_DATUM', 'BEGINN_ZEIT', 'ts_beginn')
fahrpos = combine_date_time(fahrpos, 'ENDE_DATUM',   'ENDE_ZEIT',   'ts_ende')

# Duplikate entfernen (Primärschlüssel: LFDNR)
pre = len(fahrpos)
fahrpos = fahrpos.drop_duplicates('LFDNR')
dq['drops_fahrpos'] = pre - len(fahrpos)
print(f"   fahrpos: {len(fahrpos):>8,} Zeilen nach Dedup (Drops: {dq['drops_fahrpos']})")

# Durchlaufzeit in Minuten (Ende – Beginn)
fahrpos['durchlaufzeit_min'] = (
    (fahrpos['ts_ende'] - fahrpos['ts_beginn']).dt.total_seconds() / 60
).clip(lower=0)  # negative Werte (Datenfehler) auf 0

# Bewegungszeitpunkt (Ende-Datum zuverlässiger als Beginn)
fahrpos['ts_bewegung'] = fahrpos['ts_ende'].fillna(fahrpos['ts_beginn'])

# ── 2d. ORDER (Auftrags-Positionen) ───────────────────────────────────────
order['AUFTRAGSNR']  = safe_to_numeric(order['AUFTRAGSNR'])
order['AUFTRAGSPOS'] = safe_to_numeric(order['AUFTRAGSPOS'])
order['MANDANT']     = safe_to_numeric(order['MANDANT'])

# Dedup auf Positionsebene
pre = len(order)
order = order.drop_duplicates(['AUFTRAGSNR', 'AUFTRAGSPOS', 'MANDANT'])
dq['drops_order'] = pre - len(order)
print(f"   order:   {len(order):>9,} Zeilen nach Dedup (Drops: {dq['drops_order']})")

# ── 2e. TPA (Transport-Palette-Aufträge) ──────────────────────────────────
tpa['Q_PLATZ'] = tpa['Q_PLATZ'].astype(str).str.strip()

# Timestamps
tpa = combine_date_time(tpa, 'ENDE_DATUM', 'ENDE_ZEIT', 'ts_tpa_ende')

pre = len(tpa)
tpa = tpa.drop_duplicates('LFDNR')
dq['drops_tpa'] = pre - len(tpa)
print(f"   tpa:     {len(tpa):>6,} Zeilen nach Dedup (Drops: {dq['drops_tpa']})")

# ══════════════════════════════════════════════════════════════════════════════
# 3. BEWEGUNGS-AGGREGATION (vor dem Haupt-Join)
# ══════════════════════════════════════════════════════════════════════════════
print("\n█ [3/7] Aggregiere Bewegungsdaten je Platz ...")

ref_date = pd.Timestamp('2026-04-08')  # Snapshot-Datum (Palette-Datei)

# ── 3a. Fahrpos-Aggregation je Q_PLATZ ────────────────────────────────────
fahrpos_agg = (
    fahrpos
    .dropna(subset=['Q_PLATZ_str'])
    .groupby('Q_PLATZ_str')
    .agg(
        bewegungen_gesamt   = ('LFDNR',              'count'),
        letzter_bewegung_fp = ('ts_bewegung',        'max'),
        durchlaufzeit_avg   = ('durchlaufzeit_min',  'mean'),
        artikelnr_haupt     = ('ARTIKELNR',          lambda x: x.mode().iloc[0] if len(x) > 0 else np.nan),
        picks_total         = ('ANZ_PICK',           'sum'),
        menge_ist_sum       = ('MENGE_IST',          'sum'),
    )
    .reset_index()
    .rename(columns={'Q_PLATZ_str': 'PLATZ_ID'})
)

# 30-Tage & 90-Tage Fenster
cutoff_30  = ref_date - pd.Timedelta(days=30)
cutoff_90  = ref_date - pd.Timedelta(days=90)

fp_30 = (fahrpos[fahrpos['ts_bewegung'] >= cutoff_30]
         .dropna(subset=['Q_PLATZ_str'])
         .groupby('Q_PLATZ_str').size()
         .reset_index(name='bewegungen_30d')
         .rename(columns={'Q_PLATZ_str': 'PLATZ_ID'}))

fp_90 = (fahrpos[fahrpos['ts_bewegung'] >= cutoff_90]
         .dropna(subset=['Q_PLATZ_str'])
         .groupby('Q_PLATZ_str').size()
         .reset_index(name='bewegungen_90d')
         .rename(columns={'Q_PLATZ_str': 'PLATZ_ID'}))

# Picks in 30d
picks_30 = (fahrpos[fahrpos['ts_bewegung'] >= cutoff_30]
            .dropna(subset=['Q_PLATZ_str'])
            .groupby('Q_PLATZ_str')['ANZ_PICK'].sum()
            .reset_index(name='picks_30d')
            .rename(columns={'Q_PLATZ_str': 'PLATZ_ID'}))

# ── 3b. TPA-Aggregation je Q_PLATZ ────────────────────────────────────────
tpa_agg = (
    tpa
    .dropna(subset=['Q_PLATZ'])
    .groupby('Q_PLATZ')
    .agg(
        tpa_bewegungen_gesamt = ('LFDNR', 'count'),
        letzter_bewegung_tpa  = ('ts_tpa_ende', 'max'),
    )
    .reset_index()
    .rename(columns={'Q_PLATZ': 'PLATZ_ID'})
)

# ══════════════════════════════════════════════════════════════════════════════
# 4. HAUPT-JOIN: AUFBAU DES MASTERS
# ══════════════════════════════════════════════════════════════════════════════
print("\n█ [4/7] Baue Master per Join-Kaskade ...")

# Basis: Lagerplatz-Stamm
master = platz.copy()

# ── Join 1: palette → platz (aktuell belegte Paletten)
pal_slim = palette[[
    'PLATZ', 'PALNR', 'palette_zustand', 'GEWICHT', 'AUFTRAGSNR',
    'ANZ_KOLLI', 'MANDANT'
]].rename(columns={
    'PLATZ'          : 'PLATZ_ID',
    'GEWICHT'        : 'palette_gewicht',
    'AUFTRAGSNR'     : 'auftragsnr_palette',
    'MANDANT'        : 'mandant_palette',
})
master = master.merge(pal_slim, on='PLATZ_ID', how='left')

# Palette vorhanden?
master['PALNR'] = safe_to_numeric(master['PALNR'])

# ── Join 2: fahrpos-Aggregat → platz
master = master.merge(fahrpos_agg, on='PLATZ_ID', how='left')
master = master.merge(fp_30,       on='PLATZ_ID', how='left')
master = master.merge(fp_90,       on='PLATZ_ID', how='left')
master = master.merge(picks_30,    on='PLATZ_ID', how='left')

# ── Join 3: TPA-Aggregat → platz
master = master.merge(tpa_agg, on='PLATZ_ID', how='left')

# ── Join 4: order (Artikelbezeichnung via fahrpos.artikelnr_haupt)
order_slim = order[['AUFTRAGSNR', 'AUFTRAGSPOS', 'MANDANT', 'ARTIKELNR', 'ARTBEZ1']].copy()
order_slim = order_slim.drop_duplicates('ARTIKELNR')  # Artikel-Bezeichnung

art_slim = order_slim[['ARTIKELNR', 'ARTBEZ1']].drop_duplicates('ARTIKELNR')
master = master.merge(
    art_slim.rename(columns={'ARTIKELNR': 'artikelnr_haupt', 'ARTBEZ1': 'artikel_bezeichnung'}),
    on='artikelnr_haupt',
    how='left'
)

print(f"   Master nach Join-Kaskade: {len(master):>6,} Zeilen, {master.shape[1]} Spalten")

# ══════════════════════════════════════════════════════════════════════════════
# 5. FEATURE ENGINEERING
# ══════════════════════════════════════════════════════════════════════════════
print("\n█ [5/7] Feature Engineering (ABC, Kritikalität, Timestamps) ...")

# ── 5a. Null-Werte auffüllen ───────────────────────────────────────────────
for col in ['bewegungen_30d', 'bewegungen_90d', 'picks_30d',
            'bewegungen_gesamt', 'tpa_bewegungen_gesamt', 'picks_total']:
    master[col] = master[col].fillna(0).astype(int)

master['durchlaufzeit_avg']    = master['durchlaufzeit_avg'].fillna(0).round(2)
master['belegungsquote_platz'] = master['belegungsquote_platz'].fillna(0).round(4)

# ── 5b. Letzter Bewegungszeitpunkt (bestes verfügbares Signal) ─────────────
master['letzter_bewegungszeitpunkt'] = master[['letzter_bewegung_fp', 'letzter_bewegung_tpa']].max(axis=1)
master['letzter_bewegungszeitpunkt'] = master['letzter_bewegungszeitpunkt'].fillna(master['ts_letzter_zugriff'])

# ── 5c. Tage seit letzter Bewegung ────────────────────────────────────────
master['tage_seit_bewegung'] = (
    (ref_date - master['letzter_bewegungszeitpunkt']).dt.days
).clip(lower=0)

# ── 5d. ABC-Klasse (Bewegungsbasiert) ─────────────────────────────────────
"""
ABC-Klassifizierung nach kumuliertem Bewegungsanteil (Pareto-Prinzip):
  A: Top 20 % der Plätze nach Bewegungen (akkumuliert ~80 % Volumen)
  B: Nächste 30 % (akkumuliert ~95 %)
  C: Restliche 50 %
Wenn der Platz bereits eine ABC_KLASSE aus dem Platz-Stamm hat, wird diese
BEVORZUGT (da sie vom WMS gepflegt ist). Eigene Berechnung dient als Fallback
und Validierung.
"""
# Eigene Berechnung (normiert auf alle Plätze mit Bewegungen)
bewegungs_rank = master['bewegungen_gesamt'].rank(method='first', ascending=False, na_option='bottom')
total_plätze   = len(master)

master['abc_klasse_berechnet'] = pd.cut(
    bewegungs_rank,
    bins=[0, total_plätze * 0.20, total_plätze * 0.50, total_plätze],
    labels=['A', 'B', 'C'],
    include_lowest=True
).astype(str)

# WMS-Klasse (aus Platz-Stamm) bevorzugen, wenn vorhanden
master['ABC_KLASSE'] = master['ABC_KLASSE'].astype(str).str.strip().str.upper()
valid_abc = master['ABC_KLASSE'].isin(['A', 'B', 'C'])
master['abc_klasse'] = np.where(valid_abc, master['ABC_KLASSE'], master['abc_klasse_berechnet'])

# ── 5e. Kritikalitäts-Score (0–100) ───────────────────────────────────────
"""
Kritikalitäts-Score = gewichteter Index aus 4 Komponenten:

  1. Frequenz-Score (30 %):
     Normiert auf max. Bewegungen_30d aller Plätze.
     Hohe Bewegungsfrequenz = hohe Kritikalität.

  2. Auslastungs-Score (25 %):
     belegungsquote_platz (0–1). Volle Plätze sind kritischer (Engpass).

  3. Engpass-Score (25 %):
     Plätze mit IST_LHM ≥ MAX_LHM (100 % belegt UND viele Bewegungen) = Engpass.
     Kombiniert belegungsquote * frequenz_norm.

  4. Stillstand-Penalty (20 %):
     Plätze ohne Bewegung in 90d erhalten Penalty (belegter Platz + keine Bewegung
     = mögliches Phantom-Bestand-Risiko).
     tage_seit_bewegung normiert, invertiert (je länger kein Zugriff = höher).
     Nur aktive (belegte) Plätze bekommen Penalty.
"""
max_bew30   = master['bewegungen_30d'].max() or 1
max_tage    = master['tage_seit_bewegung'].replace(0, np.nan).quantile(0.99) or 1

freq_score      = (master['bewegungen_30d'] / max_bew30).clip(0, 1)
auslast_score   = master['belegungsquote_platz'].clip(0, 1)
engpass_score   = (auslast_score * freq_score).clip(0, 1)
stillstand_norm = (master['tage_seit_bewegung'] / max_tage).clip(0, 1)
# Stillstand kritisch nur wenn Platz belegt
stillstand_score = np.where(master['aktueller_belegt_status'] == 1, stillstand_norm, 0)

master['kritikalitaet_score'] = (
    (freq_score      * 0.30 +
     auslast_score   * 0.25 +
     engpass_score   * 0.25 +
     pd.Series(stillstand_score, index=master.index) * 0.20) * 100
).round(1).clip(0, 100)

# ── 5f. Standort / Lager-ID ───────────────────────────────────────────────
master['lager_id']  = master['_Location'].fillna('schlg_rti3')
master['standort']  = master['BEREICH'].astype(str).str.zfill(2)

# ── 5g. Snapshot-Timestamp ────────────────────────────────────────────────
master['quelle_timestamp'] = SNAPSHOT_TS

# ══════════════════════════════════════════════════════════════════════════════
# 6. AUSGABE-SELEKTION & UMBENENNUNG
# ══════════════════════════════════════════════════════════════════════════════
print("\n█ [6/7] Selektion & Umbenennung der Ausgabespalten ...")

OUTPUT_COLS = {
    # Lager / Standort
    'lager_id'                  : 'lager_id',
    'standort'                  : 'standort',
    # Platz-Identifikation
    'PLATZ_ID'                  : 'platz_id',
    'BEREICH'                   : 'zone',
    'REGAL'                     : 'regal',
    'FACH'                      : 'fach',
    'EBENE'                     : 'ebene',
    # Artikel
    'artikelnr_haupt'           : 'artikel_id',
    'artikel_bezeichnung'       : 'artikelgruppe',
    # Palette
    'PALNR'                     : 'palette_id',
    # Belegung
    'aktueller_belegt_status'   : 'aktueller_belegt_status',
    'belegungsquote_platz'      : 'belegungsquote_platz',
    'ist_gesperrt'              : 'ist_gesperrt',
    # Bewegungsdaten
    'letzter_bewegungszeitpunkt': 'letzter_bewegungszeitpunkt',
    'bewegungen_30d'            : 'bewegungen_30d',
    'bewegungen_90d'            : 'bewegungen_90d',
    'bewegungen_gesamt'         : 'bewegungen_6mon',
    'durchlaufzeit_avg'         : 'durchlaufzeit_avg_min',
    'picks_30d'                 : 'picks_30d',
    # KPI
    'abc_klasse'                : 'abc_klasse',
    'kritikalitaet_score'       : 'kritikalitaet_score',
    # Koordinaten
    'x_koord'                   : 'x_koord',
    'y_koord'                   : 'y_koord',
    'z_koord'                   : 'z_koord',
    # Tage ohne Bewegung (Zusatz für Heatmap)
    'tage_seit_bewegung'        : 'tage_seit_bewegung',
    # Physische Platz-Attribute
    'MAX_LHM'                   : 'kapazitaet_lhm',
    'IST_LHM'                   : 'belegt_lhm',
    'PLATZ_TYP'                 : 'platz_typ',
    'ABC_KLASSE'                : 'abc_klasse_wms',
    # Snapshot
    'quelle_timestamp'          : 'quelle_timestamp',
}

# Nur vorhandene Spalten selektieren
avail_cols = {k: v for k, v in OUTPUT_COLS.items() if k in master.columns}
final = master[list(avail_cols.keys())].rename(columns=avail_cols)

# ISO-Format für alle Timestamp-Spalten
ts_cols = final.select_dtypes(include=['datetime64[ns]', 'datetimetz']).columns
for col in ts_cols:
    final[col] = final[col].dt.strftime('%Y-%m-%dT%H:%M:%S')

# Finale Duplikat-Prüfung auf platz_id
pre_final = len(final)
final = final.drop_duplicates('platz_id')
dq['drops_final_dedup'] = pre_final - len(final)

print(f"   Finale Tabelle: {len(final):>6,} Zeilen, {final.shape[1]} Spalten")

# ══════════════════════════════════════════════════════════════════════════════
# 7. SPEICHERN & DATA-QUALITY-REPORT
# ══════════════════════════════════════════════════════════════════════════════
print("\n█ [7/7] Speichere warehouse_ai_master.csv ...")

final.to_csv(OUTPUT_PATH, index=False, encoding='utf-8-sig')
print(f"   ✓ Gespeichert: {OUTPUT_PATH}")

# ── DATA-QUALITY-REPORT ───────────────────────────────────────────────────
print("\n" + "═" * 70)
print("DATA-QUALITY-REPORT")
print("═" * 70)

print("\n① ZEILENZAHL JE QUELLDATEI")
print(f"   {'Datei':<12} {'Initial':>10} {'Nach Dedup':>12} {'Drop-Rate':>10}")
print("   " + "─" * 48)
for name in ['fahrpos', 'order', 'palette', 'platz', 'tpa']:
    init  = dq['initial_rows'][name]
    drops = dq.get(f'drops_{name}', 0)
    after = init - drops
    rate  = drops / init * 100 if init > 0 else 0
    print(f"   {name:<12} {init:>10,} {after:>12,} {rate:>9.2f}%")

print(f"\n② FINALE MASTER-TABELLE: {len(final):,} Zeilen × {final.shape[1]} Spalten")
print(f"   Zusatz-Drops (Final-Dedup): {dq['drops_final_dedup']}")

print("\n③ NULL-WERTE PRO SPALTE (finale Tabelle, nur Spalten mit Nulls)")
null_info = final.isnull().sum()
null_info = null_info[null_info > 0].sort_values(ascending=False)
for col, cnt in null_info.items():
    pct = cnt / len(final) * 100
    print(f"   {col:<35} {cnt:>6,} ({pct:5.1f}%)")

print("\n④ ABC-KLASSEN-VERTEILUNG (berechnete Klasse)")
abc_dist = final['abc_klasse'].value_counts().sort_index()
for k, v in abc_dist.items():
    print(f"   Klasse {k}: {v:>5,} Plätze ({v/len(final)*100:4.1f}%)")

print("\n⑤ BELEGTE / FREIE PLÄTZE")
belegt = final['aktueller_belegt_status'].sum()
frei   = len(final) - belegt
print(f"   Belegt: {belegt:,} ({belegt/len(final)*100:.1f}%)  |  Frei: {frei:,} ({frei/len(final)*100:.1f}%)")

print("\n⑥ KRITIKALITÄTS-SCORE (Verteilung)")
print(final['kritikalitaet_score'].describe().round(2).to_string())

print("\n" + "═" * 70)
print(f"Fertig! Snapshot: {SNAPSHOT_TS}")
print("═" * 70)
