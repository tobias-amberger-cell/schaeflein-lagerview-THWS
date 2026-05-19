"""Erzeugt eine schlanke Sample-DB fuer Streamlit Cloud.

Die echte warehouse.db ist 289 MB und passt nicht in ein GitHub-Repo
(100 MB Limit pro Datei). Dieses Script samplet jede Tabelle auf eine
Maximalgroesse und schreibt das Resultat als data/warehouse_sample.db.

Aufruf:
    python backend/build_sample_db.py
"""
from __future__ import annotations

import sqlite3
import sys
from pathlib import Path

SRC = Path("data/warehouse.db")
DST = Path("data/warehouse_sample.db")

# Pro Tabelle: max. so viele Zeilen ins Sample. df_platz behalten wir
# komplett, weil die Lager-Topologie sonst Loecher hat.
LIMITS = {
    "df_platz_ber03_schlg_rti3": None,
    "df_palette_08042026_ber03_schlg_rti3": 5000,
    "df_tpa_6mon_ber03_schlg_rti3": 8000,
    "df_fahrpos_6mon_ber03_schlg_rti3": 5000,
    "df_order_6mon_schlg_rti3": 5000,
}


def quote(name: str) -> str:
    return '"' + name.replace('"', '""') + '"'


def copy_table(src: sqlite3.Connection, dst: sqlite3.Connection, table: str, limit: int | None) -> int:
    cols = src.execute(f"PRAGMA table_info({quote(table)})").fetchall()
    col_defs = ", ".join(f"{quote(c[1])} {c[2] or 'TEXT'}" for c in cols)
    dst.execute(f"DROP TABLE IF EXISTS {quote(table)}")
    dst.execute(f"CREATE TABLE {quote(table)} ({col_defs})")

    if limit is None:
        rows = src.execute(f"SELECT * FROM {quote(table)}")
    else:
        # Stratified sample: bei df_platz nach REGAL gruppieren, sonst random.
        rows = src.execute(
            f"SELECT * FROM {quote(table)} ORDER BY RANDOM() LIMIT ?",
            [limit],
        )
    placeholders = ", ".join("?" * len(cols))
    count = 0
    batch: list = []
    for row in rows:
        batch.append(row)
        count += 1
        if len(batch) >= 1000:
            dst.executemany(f"INSERT INTO {quote(table)} VALUES ({placeholders})", batch)
            batch.clear()
    if batch:
        dst.executemany(f"INSERT INTO {quote(table)} VALUES ({placeholders})", batch)
    return count


def main() -> None:
    if not SRC.exists():
        sys.exit(f"Quell-DB nicht gefunden: {SRC.resolve()}")

    if DST.exists():
        DST.unlink()

    print(f"Quelle: {SRC} ({SRC.stat().st_size / 1024 / 1024:.1f} MB)")
    print(f"Ziel:   {DST}")

    src = sqlite3.connect(SRC)
    dst = sqlite3.connect(DST)
    try:
        with dst:
            for table, limit in LIMITS.items():
                n = copy_table(src, dst, table, limit)
                cap = "alle" if limit is None else f"max {limit}"
                print(f"  {table}: {n} Zeilen ({cap})")
        dst.execute("VACUUM")
    finally:
        src.close()
        dst.close()

    print(f"Fertig: {DST} ({DST.stat().st_size / 1024 / 1024:.1f} MB)")


if __name__ == "__main__":
    main()
