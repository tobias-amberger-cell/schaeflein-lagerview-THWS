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
        f'ANZ_PICKS, ANZ_NACHSCHUB, ZUSTAND, SPERR_KNZ '
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


def heatmap_color(util: float) -> str:
    """Aus warehouse_heatmap.py."""
    if pd.isna(util):
        return "GREY"
    if util >= 80:
        return "RED"
    if util >= 40:
        return "YELLOW"
    return "GREEN"


def apply_filters(
    df: pd.DataFrame,
    hallen: list[str],
    abc: list[str],
    util_range: tuple[float, float],
    only_occupied: bool,
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
    return out


def main() -> None:
    st.title("📦 Schaeflein LagerView v1.133")
    st.caption("Lager BER03 — Live-Auswertung aus warehouse.db")

    try:
        platz = load_platz_full()
    except Exception as exc:
        st.error(f"Konnte Stellplatz-Daten nicht laden: {exc}")
        st.exception(exc)
        st.stop()

    with st.sidebar:
        st.header("Filter")
        hallen = st.multiselect(
            "Halle",
            options=["Halle 1", "Halle 2", "Halle 3"],
            default=[],
            help="Leer = alle Hallen.",
        )
        abc = st.multiselect(
            "ABC-Klasse",
            options=["A", "B", "C"],
            default=[],
            help="Filtert auf Stamm-ABC ODER auf die kumulativ berechnete ABC.",
        )
        util_range = st.slider(
            "Auslastung (%)", 0, 150, (0, 150), step=5,
            help="MAX_LHM vs. IST_LHM. 0 = leer, 100 = voll, >100 = ueberlastet.",
        )
        only_occupied = st.checkbox("Nur belegte Plaetze", value=False)
        st.divider()
        days = st.slider("Durchsatz-Zeitraum (Tage)", 7, 180, 30, step=7)
        article_limit = st.slider("Top-Artikel anzeigen", 5, 100, 25, step=5)
        st.divider()
        st.caption(f"DB: `{get_db_path()}`")

    filtered = apply_filters(platz, hallen, abc, util_range, only_occupied)

    total = len(filtered) or 1
    occupied = int(filtered["BELEGT"].sum())
    overloaded = int((filtered["UTILIZATION"] > 100).sum())
    avg_util = filtered["UTILIZATION"].mean()

    c1, c2, c3, c4 = st.columns(4)
    c1.metric("Stellplaetze", f"{len(filtered):,}".replace(",", "."))
    c2.metric("Belegt", f"{occupied:,}".replace(",", "."),
              f"{occupied/total*100:.1f}%")
    c3.metric("Ø Auslastung",
              f"{avg_util:.1f} %" if not pd.isna(avg_util) else "—")
    c4.metric("Ueberlastet (>100 %)", f"{overloaded:,}".replace(",", "."))

    (tab_hallen, tab_heat, tab_bottle, tab_free, tab_reloc, tab_abc,
     tab_trend, tab_top, tab_3d) = st.tabs([
        "Hallen",
        "Auslastungs-Heatmap",
        "Bottlenecks",
        "Free Capacity",
        "Smart Relocation",
        "ABC-Analyse",
        "Durchsatz",
        "Top-Artikel",
        "3D-Modell",
    ])

    with tab_hallen:
        zones = (
            filtered.groupby("HALLE")
            .agg(total_slots=("PLATZ_ID", "count"),
                 occupied=("BELEGT", "sum"))
            .reset_index()
        )
        zones["frei"] = zones["total_slots"] - zones["occupied"]
        fig = px.bar(
            zones.melt(
                id_vars="HALLE",
                value_vars=["occupied", "frei"],
                var_name="Status",
                value_name="Plaetze",
            ),
            x="HALLE", y="Plaetze", color="Status", barmode="stack",
            color_discrete_map={"occupied": "#ef6c00", "frei": "#bdbdbd"},
            title="Belegung pro Halle (gefiltert)",
        )
        st.plotly_chart(fig, use_container_width=True)
        st.dataframe(zones, use_container_width=True, hide_index=True)

    with tab_heat:
        if filtered.empty:
            st.info("Keine Daten mit aktuellen Filtern.")
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
                title="Auslastung je Regal/Ebene (IST/MAX × 100)",
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

    with tab_bottle:
        st.markdown(
            "**Bottleneck-Analyse** — Plaetze mit hoher Pick-Frequenz "
            "(`ANZ_PICKS` aus Platz + `Q_PLATZ`-Count aus Fahrpos). "
            "Engpaesse sind Plaetze, die oft angefahren werden und gleichzeitig "
            "hoch ausgelastet sind."
        )
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
        st.dataframe(bottlenecks, use_container_width=True, hide_index=True)

    with tab_free:
        st.markdown(
            "**Free Capacity** — Plaetze mit Restkapazitaet sortiert nach "
            "`MAX_LHM − IST_LHM`."
        )
        free = (
            filtered[filtered["FREE_CAPACITY"] > 0]
            .sort_values("FREE_CAPACITY", ascending=False)
            .head(100)[
                ["PLATZ_ID", "HALLE", "REGAL", "FACH", "EBENE",
                 "MAX_LHM", "IST_LHM", "FREE_CAPACITY", "UTILIZATION"]
            ]
        )
        st.dataframe(free, use_container_width=True, hide_index=True)

    with tab_reloc:
        st.markdown(
            "**Smart Relocation** — fuer jeden ueberlasteten Platz "
            "(UTILIZATION > 100 %) ein Vorschlag, wohin ausgelagert werden "
            "kann (`FREE_CAPACITY > 0`)."
        )
        overloaded_df = filtered[filtered["UTILIZATION"] > 100]
        free_df = filtered[filtered["FREE_CAPACITY"] > 0]
        if overloaded_df.empty or free_df.empty:
            st.info("Keine ueberlasteten oder keine freien Plaetze mit aktuellen Filtern.")
        else:
            n = st.slider("Anzahl Vorschlaege", 5, 50, 15, step=5)
            rng = np.random.default_rng(seed=42)
            free_pool = free_df.sample(
                n=min(n, len(free_df)), random_state=rng.integers(1, 2**32 - 1)
            ).reset_index(drop=True)
            picks = overloaded_df.sort_values("UTILIZATION", ascending=False).head(n).reset_index(drop=True)
            rows = []
            for i in range(min(len(picks), len(free_pool))):
                src = picks.iloc[i]
                tgt = free_pool.iloc[i]
                rows.append({
                    "von_PLATZ": src["PLATZ_ID"],
                    "von (R/F/E)": f'{src["REGAL"]}/{src["FACH"]}/{src["EBENE"]}',
                    "von_Auslastung_%": round(src["UTILIZATION"], 1),
                    "nach_PLATZ": tgt["PLATZ_ID"],
                    "nach (R/F/E)": f'{tgt["REGAL"]}/{tgt["FACH"]}/{tgt["EBENE"]}',
                    "nach_freie_LHM": tgt["FREE_CAPACITY"],
                })
            st.dataframe(pd.DataFrame(rows), use_container_width=True, hide_index=True)

    with tab_abc:
        st.markdown(
            "**ABC-Analyse** — kumulative Verteilung von `ANZ_PICKS`. "
            "A = Top 80 % Picks, B = naechste 15 %, C = Rest."
        )
        abc_counts = (
            filtered["ABC_CALC"].value_counts().reindex(["A", "B", "C"]).fillna(0)
        )
        fig = px.pie(
            names=abc_counts.index,
            values=abc_counts.values,
            color=abc_counts.index,
            color_discrete_map={"A": "#c62828", "B": "#f9a825", "C": "#2e7d32"},
            title="ABC-Verteilung (berechnet)",
        )
        st.plotly_chart(fig, use_container_width=True)
        st.dataframe(
            filtered.sort_values("ANZ_PICKS", ascending=False).head(50)[
                ["PLATZ_ID", "HALLE", "REGAL", "FACH", "EBENE",
                 "ANZ_PICKS", "CUMULATIVE_%", "ABC_KLASSE", "ABC_CALC"]
            ],
            use_container_width=True,
            hide_index=True,
        )

    with tab_trend:
        trend = load_throughput_trend(days)
        if trend.empty:
            st.info("Keine Bewegungsdaten gefunden.")
        else:
            fig = px.line(
                trend, x="day", y="movements", markers=True,
                title=f"Bewegungen letzte {days} Tage",
            )
            fig.update_layout(yaxis_title="Bewegungen", xaxis_title="Datum")
            st.plotly_chart(fig, use_container_width=True)

    with tab_top:
        top = load_top_articles(article_limit)
        st.dataframe(top, use_container_width=True, hide_index=True)

    with tab_3d:
        # GitHub-Release-Assets senden kein CORS -> der Browser wuerde das
        # Modell blocken. Daher ueber den CORS-faehigen API-Proxy laden
        # (gleiche Quelle wie die Flutter-App).
        glb_url = "https://ssi-lagerview-api.onrender.com/model.glb"
        components.html(
            f"""
<script type="module"
    src="https://unpkg.com/@google/model-viewer/dist/model-viewer.min.js">
</script>
<div style="width:100%;height:640px;background:#f5f5f7;border-radius:8px;">
  <model-viewer
      src="{glb_url}"
      alt="Schaeflein BER03 Lager"
      camera-controls
      touch-action="pan-y"
      shadow-intensity="0.8"
      exposure="1"
      style="width:100%;height:100%;background-color:#f5f5f7;">
  </model-viewer>
</div>
            """,
            height=660,
        )
        st.caption(
            f"GLB-Quelle: [{glb_url}]({glb_url}) — GitHub-Release `model-v1`."
        )


if __name__ == "__main__":
    main()
