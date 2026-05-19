"""Streamlit-Dashboard fuer Schaeflein LagerView.

Visualisiert dieselben Daten wie die Flutter-App direkt aus der warehouse.db.

Lokaler Start:
    streamlit run backend/streamlit_app.py

Deployment auf Streamlit Community Cloud:
    Main file path: backend/streamlit_app.py
    Die DB (289 MB) ist zu gross fuer Git -- entweder per `db_url` in
    .streamlit/secrets.toml als Download-URL hinterlegen oder eine
    Sample-DB ins Repo legen (siehe `_DB_CANDIDATES`).
"""
from __future__ import annotations

import os
import sqlite3
import tempfile
from pathlib import Path
from urllib.request import urlretrieve

import pandas as pd
import plotly.express as px
import streamlit as st

st.set_page_config(
    page_title="Schaeflein LagerView",
    page_icon="📦",
    layout="wide",
)

PLATZ_TABLE = "df_platz_ber03_schlg_rti3"
PALETTE_TABLE = "df_palette_08042026_ber03_schlg_rti3"
TPA_TABLE = "df_tpa_6mon_ber03_schlg_rti3"
FAHRPOS_TABLE = "df_fahrpos_6mon_ber03_schlg_rti3"

# Repo-relative Pfade in Reihenfolge der Bevorzugung. Lokal greift zuerst die
# vollstaendige DB, online (Streamlit Cloud) bleibt nur die Sample-DB im Repo.
_DB_CANDIDATES = [
    Path("data/warehouse.db"),
    Path("backend/data/warehouse.db"),
    Path("data/warehouse_sample.db"),
    Path("backend/data/warehouse_sample.db"),
    Path("warehouse.db"),
]


@st.cache_resource(show_spinner="Lade DB ...")
def get_db_path() -> str:
    """Sucht die warehouse.db lokal oder laedt sie von einer URL herunter."""
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
    # check_same_thread=False, weil Streamlit pro Request andere Threads nutzen kann.
    return sqlite3.connect(path, check_same_thread=False)


@st.cache_data(ttl=3600)
def load_platz_overview() -> dict:
    con = get_connection()
    row = con.execute(
        f"""
        SELECT
            COUNT(*) AS total_slots,
            SUM(CASE WHEN COALESCE(ZUSTAND, 0) > 0 THEN 1 ELSE 0 END) AS occupied,
            SUM(CASE WHEN UPPER(TRIM(COALESCE(ABC_KLASSE, ''))) = 'A' THEN 1 ELSE 0 END) AS abc_a,
            SUM(CASE WHEN UPPER(TRIM(COALESCE(ABC_KLASSE, ''))) = 'B' THEN 1 ELSE 0 END) AS abc_b,
            SUM(CASE WHEN UPPER(TRIM(COALESCE(ABC_KLASSE, ''))) = 'C' THEN 1 ELSE 0 END) AS abc_c,
            SUM(CASE WHEN COALESCE(ZUSTAND, 0) >= 150 THEN 1 ELSE 0 END) AS blocked
        FROM {PLATZ_TABLE}
        WHERE TRIM(COALESCE(PLATZ_ID, '')) <> ''
        """
    ).fetchone()
    keys = ["total_slots", "occupied", "abc_a", "abc_b", "abc_c", "blocked"]
    return dict(zip(keys, [v or 0 for v in row]))


@st.cache_data(ttl=3600)
def load_zone_distribution() -> pd.DataFrame:
    con = get_connection()
    return pd.read_sql_query(
        f"""
        SELECT
            CASE
                WHEN CAST(COALESCE(REGAL, '0') AS INTEGER) BETWEEN 1 AND 16 THEN 'Halle 1'
                WHEN CAST(COALESCE(REGAL, '0') AS INTEGER) BETWEEN 17 AND 32 THEN 'Halle 2'
                ELSE 'Halle 3'
            END AS zone,
            COUNT(*) AS total_slots,
            SUM(CASE WHEN COALESCE(ZUSTAND, 0) > 0 THEN 1 ELSE 0 END) AS occupied
        FROM {PLATZ_TABLE}
        WHERE TRIM(COALESCE(PLATZ_ID, '')) <> ''
        GROUP BY zone
        ORDER BY zone
        """,
        con,
    )


@st.cache_data(ttl=3600)
def load_rack_heatmap() -> pd.DataFrame:
    con = get_connection()
    df = pd.read_sql_query(
        f"""
        SELECT
            CAST(COALESCE(REGAL, '0') AS INTEGER) AS regal,
            CAST(COALESCE(EBENE, 0) AS INTEGER) AS ebene,
            COUNT(*) AS total_slots,
            SUM(CASE WHEN COALESCE(ZUSTAND, 0) > 0 THEN 1 ELSE 0 END) AS occupied
        FROM {PLATZ_TABLE}
        WHERE TRIM(COALESCE(PLATZ_ID, '')) <> ''
        GROUP BY REGAL, EBENE
        """,
        con,
    )
    # Verschiedene Roh-Strings wie "5" und "05" kollabieren auf denselben
    # CAST-Wert. Nach dem CAST nochmal aggregieren, damit das Pivot eindeutig
    # bleibt.
    df = (
        df.groupby(["regal", "ebene"], as_index=False)[["total_slots", "occupied"]]
        .sum()
        .sort_values(["regal", "ebene"])
    )
    return df


@st.cache_data(ttl=3600)
def load_throughput_trend(days: int = 30) -> pd.DataFrame:
    con = get_connection()
    df = pd.read_sql_query(
        f"""
        SELECT
            DATE(ENDE_DATUM) AS day,
            COUNT(*) AS movements
        FROM {TPA_TABLE}
        WHERE TRIM(COALESCE(ENDE_DATUM, '')) <> ''
        GROUP BY DATE(ENDE_DATUM)
        ORDER BY DATE(ENDE_DATUM) DESC
        LIMIT ?
        """,
        con,
        params=[days],
    )
    df["day"] = pd.to_datetime(df["day"], errors="coerce")
    df = df.dropna(subset=["day"]).sort_values("day")
    return df


@st.cache_data(ttl=3600)
def load_top_articles(limit: int = 25) -> pd.DataFrame:
    con = get_connection()
    return pd.read_sql_query(
        f"""
        SELECT
            TRIM(ARTIKELNR) AS artikel,
            TRIM(COALESCE(ARTBEZ1, '')) AS bezeichnung,
            COUNT(*) AS bewegungen
        FROM {TPA_TABLE}
        WHERE TRIM(COALESCE(ARTIKELNR, '')) <> ''
        GROUP BY artikel
        ORDER BY bewegungen DESC
        LIMIT ?
        """,
        con,
        params=[limit],
    )


def main() -> None:
    st.title("📦 Schaeflein LagerView")
    st.caption("Lager BER03 — Live-Auswertung aus warehouse.db")

    with st.sidebar:
        st.header("Filter")
        days = st.slider("Durchsatz-Zeitraum (Tage)", 7, 180, 30, step=7)
        article_limit = st.slider("Top-Artikel anzeigen", 5, 100, 25, step=5)
        st.divider()
        st.caption(f"DB: `{get_db_path()}`")

    overview = load_platz_overview()
    total = overview["total_slots"] or 1
    occupied = overview["occupied"]

    c1, c2, c3, c4 = st.columns(4)
    c1.metric("Stellplaetze", f"{total:,}".replace(",", "."))
    c2.metric("Belegt", f"{occupied:,}".replace(",", "."),
              f"{occupied/total*100:.1f}%")
    c3.metric("Gesperrt", f"{overview['blocked']:,}".replace(",", "."))
    c4.metric(
        "ABC A/B/C",
        f"{overview['abc_a']} / {overview['abc_b']} / {overview['abc_c']}",
    )

    tab1, tab2, tab3, tab4 = st.tabs(
        ["Hallen", "Belegungs-Heatmap", "Durchsatz", "Top-Artikel"]
    )

    with tab1:
        zones = load_zone_distribution()
        zones["frei"] = zones["total_slots"] - zones["occupied"]
        fig = px.bar(
            zones.melt(
                id_vars="zone",
                value_vars=["occupied", "frei"],
                var_name="Status",
                value_name="Plaetze",
            ),
            x="zone",
            y="Plaetze",
            color="Status",
            barmode="stack",
            color_discrete_map={"occupied": "#ef6c00", "frei": "#bdbdbd"},
            title="Belegung pro Halle",
        )
        st.plotly_chart(fig, use_container_width=True)
        st.dataframe(zones, use_container_width=True, hide_index=True)

    with tab2:
        heat = load_rack_heatmap()
        heat["auslastung_%"] = (heat["occupied"] / heat["total_slots"] * 100).round(1)
        pivot = heat.pivot_table(
            index="ebene",
            columns="regal",
            values="auslastung_%",
            aggfunc="mean",
        )
        fig = px.imshow(
            pivot,
            color_continuous_scale="RdYlGn_r",
            aspect="auto",
            labels=dict(x="Regal", y="Ebene", color="Auslastung %"),
            title="Auslastung je Regal/Ebene",
        )
        st.plotly_chart(fig, use_container_width=True)

    with tab3:
        trend = load_throughput_trend(days)
        if trend.empty:
            st.info("Keine Bewegungsdaten gefunden.")
        else:
            fig = px.line(
                trend,
                x="day",
                y="movements",
                markers=True,
                title=f"Bewegungen letzte {days} Tage",
            )
            fig.update_layout(yaxis_title="Bewegungen", xaxis_title="Datum")
            st.plotly_chart(fig, use_container_width=True)

    with tab4:
        top = load_top_articles(article_limit)
        st.dataframe(top, use_container_width=True, hide_index=True)


if __name__ == "__main__":
    main()
