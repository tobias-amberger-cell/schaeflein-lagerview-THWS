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


def _csv_download(df: pd.DataFrame, key: str, label: str = "⬇️ Als CSV") -> None:
    """Einheitlicher CSV-Export-Button (utf-8-sig fuer Excel-Umlaute)."""
    st.download_button(
        label,
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
        with st.expander("Platz-Filter (Regal/Ebene/Picks/Sperre)"):
            regal_max = max(int(platz["REGAL"].max()), 1)
            ebene_max = max(int(platz["EBENE"].max()), 1)
            picks_max = max(int(platz["ANZ_PICKS"].max()), 1)
            regal_range = st.slider("Regal", 0, regal_max, (0, regal_max))
            ebene_range = st.slider("Ebene", 0, ebene_max, (0, ebene_max))
            min_picks = st.slider("Min. Picks (ANZ_PICKS)", 0, picks_max, 0)
            sperr_mode = st.radio(
                "Sperr-Status",
                options=["Alle", "Nur gesperrte", "Ohne gesperrte"],
                horizontal=True,
            )
        st.divider()
        days = st.slider("Durchsatz-Zeitraum (Tage)", 7, 180, 30, step=7)
        article_limit = st.slider("Top-Artikel anzeigen", 5, 100, 25, step=5)
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
    c1.metric("Stellplaetze", f"{len(filtered):,}".replace(",", "."))
    c2.metric("Belegt", f"{occupied:,}".replace(",", "."),
              f"{occupied/total*100:.1f}%")
    c3.metric("Ø Auslastung",
              f"{avg_util:.1f} %" if not pd.isna(avg_util) else "—")
    c4.metric("Ueberlastet (>100 %)", f"{overloaded:,}".replace(",", "."))

    (tab_hallen, tab_heat, tab_pickheat, tab_bottle, tab_free, tab_umlagern,
     tab_nachschub, tab_einlagern, tab_auslagern, tab_abc, tab_trend, tab_top,
     tab_3d) = st.tabs([
        "Hallen",
        "Auslastungs-Heatmap",
        "Pick-Heatmap",
        "Bottlenecks",
        "Free Capacity",
        "🔄 Umlagern",
        "⬆️ Nachschub",
        "📥 Einlagern",
        "📤 Auslagern",
        "ABC-Analyse",
        "Durchsatz",
        "Top-Artikel",
        "3D-Modell",
    ])

    with tab_hallen:
        st.markdown(
            "**Hallen-Übersicht** — Belegung, Auslastung und ABC-Verteilung je "
            "Halle (Regal 1–16 = Halle 1, 17–32 = Halle 2, Rest = Halle 3)."
        )
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
            title="Belegung pro Halle (gefiltert)",
        )
        st.plotly_chart(fig, use_container_width=True)

        st.markdown("**Kennzahlen je Halle**")
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
        st.markdown(
            "**Auslastungs-Heatmap** — durchschnittliche Auslastung "
            "(`IST_LHM / MAX_LHM × 100`) je Regal und Ebene. Rot = voll/überlastet, "
            "grün = viel Luft. Darunter die am stärksten ausgelasteten Regale."
        )
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

            st.markdown("**Regale nach Ø Auslastung**")
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
        st.markdown(
            "**Pick-Heatmap** — Bewegungen je Wochentag und Stunde "
            "(aus den TPA-Daten). Zeigt, wann am meisten gepickt wird."
        )
        ph = load_pick_heatmap()
        if ph.empty:
            st.info("Keine Bewegungsdaten mit Datum/Uhrzeit gefunden.")
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
                title="Pick-Aktivitaet je Wochentag/Stunde",
            )
            st.plotly_chart(fig, use_container_width=True)
            busiest = ph.sort_values("picks", ascending=False).head(1)
            if not busiest.empty:
                row = busiest.iloc[0]
                st.caption(
                    f"Spitze: {weekday_names[int(row['weekday'])]} "
                    f"{int(row['hour']):02d}:00 Uhr mit {int(row['picks']):,} Picks."
                    .replace(",", ".")
                )

            c1, c2 = st.columns(2)
            with c1:
                per_wd = (
                    ph.groupby("weekday")["picks"].sum().reindex(range(7), fill_value=0)
                )
                per_wd.index = [weekday_names[i] for i in per_wd.index]
                st.plotly_chart(
                    px.bar(per_wd, title="Picks je Wochentag",
                           labels=dict(value="Picks", index="Wochentag")),
                    use_container_width=True,
                )
            with c2:
                per_hour = (
                    ph.groupby("hour")["picks"].sum().reindex(range(24), fill_value=0)
                )
                st.plotly_chart(
                    px.bar(per_hour, title="Picks je Stunde",
                           labels=dict(value="Picks", index="Stunde")),
                    use_container_width=True,
                )
            tbl = ph.copy()
            tbl["Wochentag"] = tbl["weekday"].map(weekday_names)
            tbl = tbl.rename(columns={"hour": "Stunde", "picks": "Picks"})
            _csv_download(tbl[["Wochentag", "Stunde", "Picks"]], "pick_heatmap")

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
        if bottlenecks.empty:
            st.info("Keine Daten mit aktuellen Filtern.")
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
                        title="Top-15 Engpässe (Picks gesamt, Farbe = Auslastung %)",
                        labels=dict(PICK_TOTAL="Picks gesamt", PLATZ_ID="Platz"),
                    ),
                    use_container_width=True,
                )
            except Exception as exc:  # Diagramm ist optional, Tabelle zaehlt.
                st.caption(f"(Diagramm konnte nicht gezeichnet werden: {exc})")

    with tab_free:
        st.markdown(
            "**Free Capacity** — Plaetze mit Restkapazitaet sortiert nach "
            "`MAX_LHM − IST_LHM`."
        )
        free_all = filtered[filtered["FREE_CAPACITY"] > 0]
        c1, c2, c3 = st.columns(3)
        c1.metric("Plätze mit freier Kapazität",
                  f"{len(free_all):,}".replace(",", "."))
        c2.metric("Freie LHM gesamt",
                  f"{int(free_all['FREE_CAPACITY'].sum()):,}".replace(",", "."))
        c3.metric("Ø freie LHM/Platz",
                  f"{free_all['FREE_CAPACITY'].mean():.1f}"
                  if not free_all.empty else "—")

        if not free_all.empty:
            by_hall = (
                free_all.groupby("HALLE")["FREE_CAPACITY"].sum().reset_index()
            )
            st.plotly_chart(
                px.bar(by_hall, x="HALLE", y="FREE_CAPACITY",
                       title="Freie Kapazität (LHM) je Halle",
                       labels=dict(FREE_CAPACITY="Freie LHM", HALLE="Halle")),
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
        st.metric("Plaetze", f"{len(df):,}".replace(",", "."))
        if df.empty:
            st.info("Keine Plaetze in dieser Kategorie (mit aktuellen Filtern).")
        else:
            st.dataframe(
                df.head(200)[cols], use_container_width=True, hide_index=True
            )
            key = "".join(c if c.isalnum() else "_" for c in titel.lower())
            _csv_download(df[cols], f"massnahme_{key}")
        st.divider()

    with tab_umlagern:
        st.markdown(
            "### 🔄 Umlagern\n"
            "Datenbasierte Umlager-Vorschlaege (gleiche Logik wie die App)."
        )
        c1, c2 = st.columns(2)
        with c1:
            hot_c_threshold = st.slider("Heiße C-Plätze ab Picks", 10, 300, 100, step=10)
        with c2:
            high_level = st.slider("Hohe Ebene ab", 2, 6, 4)

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
            "Premium-Plätze ungenutzt",
            "A-Klasse, aber 0 Picks – Premium-Platz nicht genutzt.", unused_a)
        _massnahme_kategorie(
            "Heiße C-Plätze",
            "C-Klasse mit hoher Pickfrequenz – Klasse anpassen.", hot_c)
        _massnahme_kategorie(
            "A-Plätze auf hoher Ebene",
            "A-Klasse weit oben & aktiv – nach unten holen.", high_level_a)

    with tab_nachschub:
        st.markdown(
            "### ⬆️ Nachschub / Replenishment\n"
            "Leere Pickplaetze (`IST_LHM = 0`), die nachgefuellt werden sollten."
        )
        c1, c2, c3 = st.columns(3)
        with c1:
            pick_level = st.slider("Max. Ebene (Pickzone)", 1, 6, 2)
        with c2:
            pick_threshold = st.slider("Dringend ab Picks", 10, 300, 50, step=10)
        with c3:
            overdue_days = st.slider("Überfällig ab Tagen", 3, 60, 14)
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
            "Dringend leer",
            "Aktiver Pickplatz leer – dringend nachfuellen.", urgent,
            extra_cols=["DAYS_EMPTY"])
        _massnahme_kategorie(
            "Überfällig",
            f"Bereits ≥ {overdue_days} Tage leer – Replenishment vergessen?",
            overdue, extra_cols=["DAYS_EMPTY"])
        _massnahme_kategorie(
            "Mittlere Frequenz",
            "Pickplatz leer mit mittlerer Pickfrequenz.", medium)

    with tab_einlagern:
        st.markdown(
            "### 📥 Einlagern / Putaway\n"
            "Wohin eingehende Ware gestellt werden sollte (freie Kapazitaet)."
        )
        reserve_level = st.slider("Reserve-Ebene ab", 2, 6, 3)
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
            "Fast-Lane (Schnelldreher)",
            "Freie A-Plätze auf niedriger Ebene – ideal für Schnelldreher.",
            fast_lane, extra_cols=["FREE_CAPACITY"])
        _massnahme_kategorie(
            "Reserve (hohe Ebenen)",
            f"Freie Plätze ab Ebene {reserve_level} – für Langsamdreher/Reserve.",
            reserve, extra_cols=["FREE_CAPACITY"])
        _massnahme_kategorie(
            "Gesperrt – nicht bestücken",
            "Gesperrte Plätze (ZUSTAND ≥ 150) – nicht einlagern.", blocked)

    with tab_auslagern:
        st.markdown(
            "### 📤 Auslagern / Retrieval\n"
            "Langsamdreher/Ladenhueter, die (gute) Plaetze blockieren und "
            "ausgelagert oder umgelagert werden sollten."
        )
        observe_max = st.slider("„Beobachten“ bis Picks", 1, 50, 5)
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
            "Kritisch",
            "A-Platz belegt, aber 0 Picks – Premium-Platz von Ladenhueter blockiert.",
            critical)
        _massnahme_kategorie(
            "Abgestanden",
            "Belegt mit 0 Picks – bewegt sich nicht, Auslagern pruefen.", stale)
        _massnahme_kategorie(
            "Beobachten",
            f"Belegt mit sehr geringer Frequenz (1–{observe_max} Picks).", observe)

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

        st.markdown(
            "**Stamm-ABC vs. berechnet** — Zeilen = hinterlegte `ABC_KLASSE`, "
            "Spalten = aus Picks berechnete `ABC_CALC`. Werte abseits der Diagonale "
            "sind Kandidaten für eine ABC-Anpassung."
        )
        cross = pd.crosstab(
            filtered["ABC_KLASSE"].replace("", "—"),
            filtered["ABC_CALC"].fillna("—"),
        )
        st.dataframe(cross, use_container_width=True)

        st.markdown("**Plätze nach Pickfrequenz**")
        abc_table = filtered.sort_values("ANZ_PICKS", ascending=False).head(100)[
            ["PLATZ_ID", "HALLE", "REGAL", "FACH", "EBENE",
             "ANZ_PICKS", "CUMULATIVE_%", "ABC_KLASSE", "ABC_CALC"]
        ]
        st.dataframe(abc_table, use_container_width=True, hide_index=True)
        _csv_download(abc_table, "abc_analyse")

    with tab_trend:
        st.markdown(
            "**Durchsatz** — Anzahl Lagerbewegungen je Tag (aus den TPA-Daten). "
            "Zeitraum über den Sidebar-Regler „Durchsatz-Zeitraum“ einstellbar."
        )
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

            c1, c2, c3 = st.columns(3)
            c1.metric("Ø pro Tag", f"{trend['movements'].mean():.0f}")
            c2.metric("Maximum", f"{int(trend['movements'].max()):,}".replace(",", "."))
            c3.metric("Summe Zeitraum",
                      f"{int(trend['movements'].sum()):,}".replace(",", "."))

            tbl = trend.copy()
            tbl["day"] = tbl["day"].dt.strftime("%Y-%m-%d")
            tbl = tbl.rename(columns={"day": "Datum", "movements": "Bewegungen"})
            tbl = tbl.sort_values("Datum", ascending=False)
            st.dataframe(tbl, use_container_width=True, hide_index=True)
            _csv_download(tbl, "durchsatz")

    with tab_top:
        st.markdown(
            "**Top-Artikel** — Artikel mit den meisten Bewegungen (aus den "
            "TPA-Daten). Anzahl über den Sidebar-Regler „Top-Artikel anzeigen“."
        )
        top = load_top_articles(article_limit)
        if top.empty:
            st.info("Keine Artikelbewegungen gefunden.")
        else:
            chart_df = top.head(min(article_limit, 25)).sort_values("bewegungen")
            st.plotly_chart(
                px.bar(
                    chart_df, x="bewegungen", y="artikel", orientation="h",
                    title="Meistbewegte Artikel",
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
            auto_rotate = st.checkbox("Auto-Rotation", value=False)
        with ctrl2:
            exposure = st.slider("Helligkeit", 0.2, 2.0, 1.0, step=0.1)
        with ctrl3:
            shadow = st.slider("Schatten", 0.0, 2.0, 0.8, step=0.1)
        with ctrl4:
            viewer_height = st.slider("Höhe (px)", 360, 900, 640, step=20)
        bg = "#f5f5f7"
        if st.button("Ansicht zuruecksetzen"):
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
        st.caption(
            "Steuerung: Ziehen = drehen, Scrollen = zoomen, Rechtsklick-Ziehen = "
            "verschieben. Regler oben ändern Helligkeit/Schatten/Höhe; "
            "„Ansicht zurücksetzen“ zentriert neu."
        )


if __name__ == "__main__":
    main()
