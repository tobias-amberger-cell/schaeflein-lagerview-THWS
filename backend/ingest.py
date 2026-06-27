"""CSV-nach-SQLite-Ladepipeline fuer Schaeflein LagerView.

Laedt alle df_*.csv aus einem Quellordner in die warehouse.db.
Schluessel-ID-Spalten (PLATZ_ID, Q_PLATZ usw.) werden als Text
eingelesen, um fuehrende Nullen zu erhalten – z. B. "032306700"
darf NICHT als int64 (32306700) abgelegt werden, da sonst der
Join zwischen PLATZ und FAHRPOS keine Treffer liefert.

Aufruf:
    python backend/ingest.py                         # liest aus data/incoming/
    python backend/ingest.py <Ordner_mit_CSV>        # expliziter Pfad
    python backend/ingest.py <Ordner_mit_CSV> --db data/meine.db
"""
from __future__ import annotations

import argparse
import sqlite3
import sys
from pathlib import Path

import pandas as pd

# ---------------------------------------------------------------------------
# Konstanten
# ---------------------------------------------------------------------------

# Spalten, die IMMER als str gelesen werden muessen (fuehrende Nullen!).
# Neue Spalten einfach ergaenzen – kein anderer Code-Teil muss geaendert werden.
ID_COLUMNS: frozenset[str] = frozenset({
    "PLATZ_ID",
    "Q_PLATZ",
    "Z_PLATZ",
    "U_PLATZ",
    "PALNR",
    "PLATZ",
    "AUFTRAGSNR",
    "BESTNR",
})

# Regex fuer Platzhalter-Werte (z. B. "__________") -> werden zu NULL.
_STUB_RE = r"^_+$"

# Zeilen pro Ladechunk; niedrig genug fuer 2-Mio-Zeilen-Dateien im RAM.
CHUNKSIZE = 50_000

# Kodierungsreihenfolge fuer automatische Erkennung (deutsches SAP-CSV
# ist haeufig cp1252 oder utf-8 mit BOM).
_ENCODINGS = ("utf-8-sig", "utf-8", "cp1252", "latin-1")


# ---------------------------------------------------------------------------
# Hilfsfunktionen
# ---------------------------------------------------------------------------

def _open_encoding(path: Path) -> str:
    """Gibt die erste Kodierung zurueck, mit der die CSV-Datei fehlerfrei lesbar ist."""
    for enc in _ENCODINGS:
        try:
            with path.open(encoding=enc) as fh:
                fh.readline()
            return enc
        except UnicodeDecodeError:
            continue
    return "utf-8"


def _detect_separator(path: Path, encoding: str) -> str:
    """Erkennt automatisch den Feldtrenner der CSV (Semikolon oder Komma)."""
    with path.open(encoding=encoding, errors="replace") as fh:
        first_line = fh.readline()
    return ";" if first_line.count(";") >= first_line.count(",") else ","


def _id_cols_present(columns: list[str]) -> list[str]:
    """Gibt die Schnittmenge der Tabellenspalten mit ID_COLUMNS zurueck."""
    return [c for c in columns if c in ID_COLUMNS]


def _clean_chunk(df: pd.DataFrame, id_cols: list[str]) -> pd.DataFrame:
    """Bereinigt einen gelesenen Datenchunk.

    - ID-Spalten: fuehrende/abschliessende Leerzeichen entfernen,
      Leerstrings -> pd.NA
    - Alle Textspalten: Platzhalter-Unterstriche (z. B. "__________")
      -> pd.NA
    """
    df = df.copy()
    for col in id_cols:
        s = df[col].str.strip()
        df[col] = s.mask(s == "", pd.NA)
    obj_cols = df.select_dtypes(include="object").columns
    for c in obj_cols:
        s = df[c]
        # Stub-Werte (nur Unterstriche, z.B. "____") -> NULL,
        # ohne dtype-Downcasting (kein .replace -> kein FutureWarning).
        mask = s.notna() & s.astype(str).str.fullmatch(r"_+")
        df[c] = s.mask(mask, pd.NA)
    return df


def _log_id_lengths(con: sqlite3.Connection, table: str, id_cols: list[str]) -> None:
    """Gibt fuer jede ID-Spalte den Anteil 9-stelliger Werte aus (Laengenerhalt-Pruefung)."""
    for col in id_cols:
        row = con.execute(
            f'SELECT COUNT(*), '
            f'SUM(CASE WHEN LENGTH(TRIM("{col}")) = 9 THEN 1 ELSE 0 END) '
            f'FROM "{table}" WHERE "{col}" IS NOT NULL'
        ).fetchone()
        total = row[0] or 0
        correct = row[1] or 0
        if total == 0:
            print(f"    {col}: (keine Werte vorhanden)")
            continue
        pct = correct / total * 100
        sample_row = con.execute(
            f'SELECT "{col}" FROM "{table}" WHERE "{col}" IS NOT NULL LIMIT 1'
        ).fetchone()
        sample_val = sample_row[0] if sample_row else "–"
        print(f"    {col}: {pct:.0f}% Laenge=9  (Beispiel: {sample_val!r})")


# ---------------------------------------------------------------------------
# Kern-Ladefunktion
# ---------------------------------------------------------------------------

def load_csv_to_db(csv_path: Path, con: sqlite3.Connection) -> int:
    """Laedt eine einzelne CSV-Datei chunk-weise in die SQLite-Datenbank.

    Tabellenname = Dateiname ohne .csv (unveraendert, damit er mit den
    Konstanten PLATZ_TABLE / FAHRPOS_TABLE / TPA_TABLE in streamlit_app.py
    uebereinstimmt).

    Gibt die Gesamtzahl geladener Zeilen zurueck.
    """
    table = csv_path.stem
    enc = _open_encoding(csv_path)
    sep = _detect_separator(csv_path, enc)

    # Spaltennamen vorab bestimmen (ohne Daten in den Speicher zu laden)
    header = pd.read_csv(csv_path, sep=sep, nrows=0, encoding=enc)
    id_cols = _id_cols_present(list(header.columns))
    dtype_map: dict[str, type] = {c: str for c in id_cols}

    print(f"\n  Tabelle : {table}")
    print(f"  Trenner : {sep!r}  |  Kodierung : {enc}")
    if id_cols:
        print(f"  ID-Spalten als TEXT : {id_cols}")

    total = 0
    first_chunk = True

    for chunk in pd.read_csv(
        csv_path,
        sep=sep,
        encoding=enc,
        dtype=dtype_map,
        chunksize=CHUNKSIZE,
        low_memory=False,
    ):
        chunk = _clean_chunk(chunk, id_cols)
        # Beim ersten Chunk: Tabelle neu anlegen (replace), danach anhaengen.
        chunk.to_sql(
            table,
            con,
            if_exists="replace" if first_chunk else "append",
            index=False,
        )
        total += len(chunk)
        first_chunk = False
        # Fortschritts-Ausgabe nur bei sehr grossen Dateien (> 500k Zeilen)
        if total % 500_000 == 0:
            print(f"    ... {total:,} Zeilen geladen")

    print(f"  Zeilen gesamt : {total:,}")

    # Laengenerhalt-Bestaetigung fuer alle ID-Spalten
    if id_cols:
        _log_id_lengths(con, table, id_cols)

    return total


# ---------------------------------------------------------------------------
# Ingest-Orchestrierung
# ---------------------------------------------------------------------------

def ingest(csv_dir: Path, db_path: Path) -> None:
    """Laedt alle df_*.csv aus csv_dir in die SQLite-Datenbank unter db_path.

    Ueberschreibt bestehende Tabellen (if_exists='replace') – es entsteht
    eine frische DB fuer den neuen Datenstand.
    """
    csv_files = sorted(csv_dir.glob("df_*.csv"))
    if not csv_files:
        print(f"Keine df_*.csv-Dateien in: {csv_dir.resolve()}")
        return

    db_path.parent.mkdir(parents=True, exist_ok=True)
    print(f"Ziel-Datenbank : {db_path.resolve()}")
    print(f"CSV-Dateien    : {len(csv_files)}")
    for p in csv_files:
        size_mb = p.stat().st_size / 1024 / 1024
        print(f"  {p.name}  ({size_mb:.1f} MB)")

    con = sqlite3.connect(db_path)
    # WAL-Modus und reduzierte Sync-Haeufigkeit beschleunigen den Batch-Write.
    con.execute("PRAGMA journal_mode=WAL")
    con.execute("PRAGMA synchronous=NORMAL")

    try:
        for csv_path in csv_files:
            load_csv_to_db(csv_path, con)
        # VACUUM: freien Speicherplatz zurueckgeben und Index neu aufbauen.
        print("\nVACUUM ...")
        con.execute("VACUUM")
        print("Fertig.")
    finally:
        con.close()


# ---------------------------------------------------------------------------
# CLI-Einstiegspunkt
# ---------------------------------------------------------------------------

def main() -> None:
    """Kommandozeilenschnittstelle fuer den Ingest-Lauf."""
    parser = argparse.ArgumentParser(
        description=(
            "CSV-nach-SQLite-Ladepipeline fuer warehouse.db. "
            "Liest alle df_*.csv aus dem angegebenen Ordner und "
            "schreibt sie in die Zieldatenbank."
        )
    )
    parser.add_argument(
        "csv_dir",
        type=Path,
        nargs="?",
        default=Path("data/incoming"),
        help="Ordner mit den df_*.csv-Quelldateien (Standard: data/incoming/)",
    )
    parser.add_argument(
        "--db",
        type=Path,
        default=Path("data/warehouse.db"),
        metavar="PFAD",
        help="Pfad zur SQLite-Zieldatenbank (Standard: data/warehouse.db)",
    )
    args = parser.parse_args()
    csv_dir: Path = args.csv_dir

    if not csv_dir.exists():
        csv_dir.mkdir(parents=True, exist_ok=True)
        print(
            f"Ordner {csv_dir}/ angelegt. "
            "Bitte die Data_exchange-CSVs hineinlegen und erneut ausfuehren."
        )
        sys.exit(0)

    if not csv_dir.is_dir():
        print(f"Fehler: {csv_dir} ist kein Ordner.")
        sys.exit(1)

    csv_files = list(csv_dir.glob("df_*.csv"))
    if not csv_files:
        print(f"Keine df_*.csv-Dateien in {csv_dir}/ gefunden. Bitte CSVs hineinlegen.")
        sys.exit(0)

    ingest(csv_dir, args.db)


if __name__ == "__main__":
    main()
