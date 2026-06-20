from __future__ import annotations

import os
import sqlite3
from pathlib import Path
from typing import Any

from fastapi import FastAPI, HTTPException

app = FastAPI(
    title="Warehouse SQLite Auto API",
    version="1.0.0",
    description=(
        "Automatisch generierte Read-Only API aus einer SQLite-Datenbank. "
        "Tabellen und Spalten werden zur Laufzeit aus sqlite_master/PRAGMA gelesen."
    ),
)


def _resolve_db_path() -> Path:
    configured = os.getenv("WAREHOUSE_DB_PATH", "").strip()
    if configured:
        candidate = Path(configured).expanduser().resolve()
        if candidate.is_file():
            return candidate

    repo_root = Path(__file__).resolve().parents[2]
    candidates = [
        repo_root / "data" / "warehouse.db",
        repo_root / "warehouse.db",
        Path.cwd() / "data" / "warehouse.db",
        Path.cwd() / "warehouse.db",
    ]
    for candidate in candidates:
        if candidate.is_file():
            return candidate.resolve()

    raise FileNotFoundError(
        "Keine warehouse.db gefunden. Setze WAREHOUSE_DB_PATH oder lege die Datei in data/warehouse.db ab."
    )


DB_PATH = _resolve_db_path()


def _connect() -> sqlite3.Connection:
    conn = sqlite3.connect(str(DB_PATH))
    conn.row_factory = sqlite3.Row
    return conn


def _quote_identifier(identifier: str) -> str:
    # SQLite-Identifier sicher quoten (verhindert SQL Injection auf Tabellen/Spaltennamen).
    safe = identifier.replace('"', '""')
    return f'"{safe}"'


def _discover_tables(conn: sqlite3.Connection) -> dict[str, dict[str, Any]]:
    rows = conn.execute(
        """
        SELECT name
        FROM sqlite_master
        WHERE type = 'table'
          AND name NOT LIKE 'sqlite_%'
        ORDER BY name
        """
    ).fetchall()

    tables: dict[str, dict[str, Any]] = {}
    for row in rows:
        table_name = str(row["name"])
        pragma_rows = conn.execute(
            f"PRAGMA table_info({_quote_identifier(table_name)})"
        ).fetchall()

        columns: list[dict[str, Any]] = []
        pk_column: str | None = None
        for col in pragma_rows:
            name = str(col["name"])
            col_info = {
                "cid": int(col["cid"]),
                "name": name,
                "type": str(col["type"] or ""),
                "notnull": bool(col["notnull"]),
                "default": col["dflt_value"],
                "pk": int(col["pk"]),
            }
            columns.append(col_info)
            if int(col["pk"]) > 0 and pk_column is None:
                pk_column = name

        if pk_column is None:
            lower_names = {c["name"].lower(): c["name"] for c in columns}
            pk_column = lower_names.get("id")

        tables[table_name] = {
            "columns": columns,
            "id_column": pk_column,  # None => rowid wird genutzt
        }

    return tables


SCHEMA_CACHE: dict[str, dict[str, Any]] = {}


@app.on_event("startup")
def _startup() -> None:
    global SCHEMA_CACHE
    with _connect() as conn:
        SCHEMA_CACHE = _discover_tables(conn)


@app.get("/health")
def health() -> dict[str, Any]:
    return {
        "status": "ok",
        "database": str(DB_PATH),
        "table_count": len(SCHEMA_CACHE),
    }


@app.get("/tables")
def list_tables() -> dict[str, Any]:
    # Liefert alle Tabellen inkl. Spaltenstruktur.
    return {"database": str(DB_PATH), "tables": SCHEMA_CACHE}


@app.get("/{table_name}")
def get_all_rows(table_name: str) -> list[dict[str, Any]]:
    table = SCHEMA_CACHE.get(table_name)
    if table is None:
        raise HTTPException(status_code=404, detail=f"Tabelle '{table_name}' nicht gefunden.")

    sql = f"SELECT * FROM {_quote_identifier(table_name)}"
    with _connect() as conn:
        rows = conn.execute(sql).fetchall()
    return [dict(row) for row in rows]


@app.get("/{table_name}/{item_id}")
def get_one_row(table_name: str, item_id: str) -> dict[str, Any]:
    table = SCHEMA_CACHE.get(table_name)
    if table is None:
        raise HTTPException(status_code=404, detail=f"Tabelle '{table_name}' nicht gefunden.")

    id_column = table.get("id_column")
    if id_column:
        sql = (
            f"SELECT * FROM {_quote_identifier(table_name)} "
            f"WHERE {_quote_identifier(id_column)} = ? LIMIT 1"
        )
        params = (item_id,)
    else:
        try:
            row_id = int(item_id)
        except ValueError as exc:
            raise HTTPException(
                status_code=400,
                detail=(
                    f"Tabelle '{table_name}' hat keine PK/ID-Spalte. "
                    "Bitte rowid als Zahl verwenden."
                ),
            ) from exc
        sql = f"SELECT rowid, * FROM {_quote_identifier(table_name)} WHERE rowid = ? LIMIT 1"
        params = (row_id,)

    with _connect() as conn:
        row = conn.execute(sql, params).fetchone()

    if row is None:
        raise HTTPException(status_code=404, detail="Eintrag nicht gefunden.")
    return dict(row)
