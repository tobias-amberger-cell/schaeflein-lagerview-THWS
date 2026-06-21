"""Goldene Invarianten-Tests fuer warehouse.db.

Prueft nach dem Ingest, ob die wichtigsten Bedingungen erfuellt sind:
  - 100 % der PLATZ_ID-Werte haben Laenge 9
  - 100 % der Q_PLATZ-Werte (nicht NULL) in FAHRPOS haben Laenge 9
  - Join platz x fahrpos ergibt >= 99 % Treffer (kein Schluesselverlust)
  - UTILIZATION ist berechnet (nicht NaN) und nicht negativ fuer MAX_LHM > 0
  - ID-Spalten sind nicht als INTEGER gespeichert (fuehrende Null vorhanden)

Aufruf:
    pytest backend/test_golden.py
    python backend/test_golden.py
    python backend/test_golden.py --db anderer/pfad.db
    WAREHOUSE_DB=data/warehouse.db pytest backend/test_golden.py
"""
from __future__ import annotations

import argparse
import os
import sqlite3
import sys
from pathlib import Path

import pandas as pd

# ---------------------------------------------------------------------------
# Konfiguration
# ---------------------------------------------------------------------------

PLATZ_TABLE = "df_platz_ber03_schlg_rti3"
FAHRPOS_TABLE = "df_fahrpos_6mon_ber03_schlg_rti3"

# ID-Spalten, bei denen der INTEGER-Typ ein Fehler waere
_ID_COLS_CHECK = {
    PLATZ_TABLE: ["PLATZ_ID"],
    FAHRPOS_TABLE: ["Q_PLATZ"],
}

# Datenbankpfad: Umgebungsvariable WAREHOUSE_DB hat Vorrang, sonst Default.
_DB_PATH: Path = Path(os.environ.get("WAREHOUSE_DB", "data/warehouse.db"))


# ---------------------------------------------------------------------------
# Interne Hilfsfunktion
# ---------------------------------------------------------------------------

def _con() -> sqlite3.Connection:
    """Oeffnet die Datenbank; ueberspringt den Test bei fehlender DB."""
    if not _DB_PATH.exists():
        # Im pytest-Kontext: Test ueberspringen statt Fehler.
        try:
            import pytest  # type: ignore[import]
            pytest.skip(f"Datenbank nicht gefunden: {_DB_PATH.resolve()}")
        except ImportError:
            raise FileNotFoundError(
                f"Datenbank nicht gefunden: {_DB_PATH.resolve()}"
            )
    return sqlite3.connect(_DB_PATH)


# ---------------------------------------------------------------------------
# Test-Funktionen (pytest-kompatibel: Praefix test_, keine Pflicht-Parameter)
# ---------------------------------------------------------------------------

def test_platz_id_length_100pct() -> None:
    """100 % der PLATZ_ID-Werte muessen genau 9 Zeichen lang sein."""
    con = _con()
    df = pd.read_sql_query(
        f'SELECT PLATZ_ID FROM "{PLATZ_TABLE}" WHERE PLATZ_ID IS NOT NULL',
        con,
    )
    con.close()

    assert not df.empty, f"Tabelle {PLATZ_TABLE} enthaelt keine PLATZ_ID-Werte"

    lengths = df["PLATZ_ID"].astype(str).str.len()
    wrong = int((lengths != 9).sum())
    assert wrong == 0, (
        f"{wrong} von {len(df)} PLATZ_ID-Werten haben NICHT Laenge 9. "
        f"Beispiele: {df.loc[lengths != 9, 'PLATZ_ID'].head(5).tolist()}"
    )


def test_q_platz_length_100pct() -> None:
    """Alle nicht-NULL Q_PLATZ-Werte in FAHRPOS muessen Laenge 9 haben."""
    con = _con()
    try:
        df = pd.read_sql_query(
            f'SELECT Q_PLATZ FROM "{FAHRPOS_TABLE}" WHERE Q_PLATZ IS NOT NULL',
            con,
        )
    except Exception as exc:
        con.close()
        raise AssertionError(
            f"Tabelle {FAHRPOS_TABLE} nicht lesbar: {exc}"
        ) from exc
    con.close()

    if df.empty:
        return  # Leere Tabelle -> Bedingung trivial erfuellt

    lengths = df["Q_PLATZ"].astype(str).str.len()
    wrong = int((lengths != 9).sum())
    assert wrong == 0, (
        f"{wrong} von {len(df)} Q_PLATZ-Werten haben NICHT Laenge 9. "
        f"Beispiele: {df.loc[lengths != 9, 'Q_PLATZ'].head(5).tolist()}"
    )


def test_join_platz_fahrpos_match_rate() -> None:
    """Join platz x fahrpos muss >= 99 % Trefferrate ergeben (kein Schluesselverlust)."""
    con = _con()
    try:
        platz_ids = pd.read_sql_query(
            f"SELECT TRIM(PLATZ_ID) AS pid FROM \"{PLATZ_TABLE}\" "
            f"WHERE TRIM(COALESCE(PLATZ_ID, '')) <> ''",
            con,
        )["pid"]
        fahrpos_keys = pd.read_sql_query(
            f"SELECT TRIM(Q_PLATZ) AS qp FROM \"{FAHRPOS_TABLE}\" "
            f"WHERE TRIM(COALESCE(Q_PLATZ, '')) <> ''",
            con,
        )["qp"]
    finally:
        con.close()

    total = len(fahrpos_keys)
    if total == 0:
        return  # Keine Fahrpositionen -> trivial OK

    platz_set = set(platz_ids)
    matched = int(fahrpos_keys.isin(platz_set).sum())
    rate = matched / total * 100

    assert rate >= 99.0, (
        f"Join-Trefferrate zu gering: {rate:.1f} % "
        f"({matched}/{total} FAHRPOS-Zeilen matchen eine PLATZ_ID). "
        "Moegliche Ursache: fuehrende Nullen in ID-Spalten verloren."
    )


def test_utilization_computed_and_nonneg() -> None:
    """Fuer Plaetze mit MAX_LHM>0 muss UTILIZATION berechnet (kein NaN) und >= 0 sein.

    Werte >100 % sind zulaessig: Blocklagerung (PLATZ_ART R/DK/K) erlaubt
    Ueberbelegung bis IST_LHM >> MAX_LHM. Diese werden als INFO ausgegeben,
    gelten aber nicht als Fehler.
    """
    con = _con()
    df = pd.read_sql_query(
        f'SELECT IST_LHM, MAX_LHM FROM "{PLATZ_TABLE}" WHERE MAX_LHM > 0',
        con,
    )
    con.close()

    if df.empty:
        return

    df["IST_LHM"] = pd.to_numeric(df["IST_LHM"], errors="coerce")
    df["MAX_LHM"] = pd.to_numeric(df["MAX_LHM"], errors="coerce")
    util = df["IST_LHM"] / df["MAX_LHM"] * 100

    nan_count = int(util.isna().sum())
    assert nan_count == 0, (
        f"{nan_count} UTILIZATION-Werte konnten nicht berechnet werden (NaN). "
        "Pruefe IST_LHM / MAX_LHM auf nicht-numerische Eintraege."
    )

    neg_count = int((util < 0).sum())
    assert neg_count == 0, (
        f"{neg_count} UTILIZATION-Werte sind negativ "
        f"(min={util.min():.1f} %). Pruefe auf negative IST_LHM-Werte."
    )

    ueber_count = int((util > 100).sum())
    if ueber_count:
        print(
            f"INFO: {ueber_count} Plaetze mit Ueberbelegung >100% "
            "(Blocklagerung/Datenpruefung)"
        )


def test_id_columns_not_integer() -> None:
    """ID-Spalten duerfen nicht als INTEGER-Werte gespeichert sein (fuehrende Null!).

    SQLite speichert Werte typlos; typeof() gibt die tatsaechliche Storage-Class
    zurueck. Wird 'integer' gefunden, ist der fuehrende Null verloren gegangen.
    """
    con = _con()
    failures: list[str] = []

    for table, cols in _ID_COLS_CHECK.items():
        # Pruefen, ob die Tabelle ueberhaupt existiert
        exists = con.execute(
            "SELECT name FROM sqlite_master WHERE type='table' AND name=?",
            [table],
        ).fetchone()
        if not exists:
            continue

        for col in cols:
            # Tatsaechliche Storage-Class des ersten nicht-NULL-Wertes pruefen
            row = con.execute(
                f'SELECT typeof("{col}") FROM "{table}" '
                f'WHERE "{col}" IS NOT NULL LIMIT 1'
            ).fetchone()
            if row and row[0] == "integer":
                sample = con.execute(
                    f'SELECT "{col}" FROM "{table}" WHERE "{col}" IS NOT NULL LIMIT 1'
                ).fetchone()
                failures.append(
                    f"{table}.{col} typeof=integer "
                    f"(Beispiel-Wert: {sample[0] if sample else '?'})"
                )

    con.close()
    assert not failures, (
        "ID-Spalten als INTEGER gespeichert – fuehrende Nullen verloren:\n"
        + "\n".join(failures)
    )


# ---------------------------------------------------------------------------
# Standalone-Runner (python test_golden.py)
# ---------------------------------------------------------------------------

def run_all() -> bool:
    """Fuehrt alle Tests aus; gibt True zurueck wenn alle bestehen."""
    tests = [
        test_platz_id_length_100pct,
        test_q_platz_length_100pct,
        test_join_platz_fahrpos_match_rate,
        test_utilization_computed_and_nonneg,
        test_id_columns_not_integer,
    ]
    passed = failed = 0
    for fn in tests:
        try:
            fn()
            print(f"  OK   {fn.__name__}")
            passed += 1
        except (AssertionError, FileNotFoundError, Exception) as exc:
            print(f"  FAIL {fn.__name__}: {exc}")
            failed += 1
    print(f"\nErgebnis: {passed} bestanden, {failed} fehlgeschlagen")
    return failed == 0


if __name__ == "__main__":
    parser = argparse.ArgumentParser(
        description="Goldene Invarianten-Tests fuer warehouse.db"
    )
    parser.add_argument(
        "--db",
        type=Path,
        default=_DB_PATH,
        metavar="PFAD",
        help=f"Pfad zur SQLite-Datenbank (Standard: {_DB_PATH})",
    )
    cli_args = parser.parse_args()

    # Modul-Variable ueberschreiben, damit alle Test-Funktionen den neuen Pfad nutzen
    _DB_PATH = cli_args.db  # noqa: PLW0603

    print(f"Datenbank: {_DB_PATH.resolve()}")
    print("-" * 50)
    success = run_all()
    sys.exit(0 if success else 1)
