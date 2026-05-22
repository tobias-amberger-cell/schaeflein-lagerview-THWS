from __future__ import annotations

import sqlite3
import sys
import threading
import urllib.request
from datetime import datetime
import os
from pathlib import Path
from typing import Any

from fastapi import FastAPI, HTTPException, Query
from fastapi.middleware.cors import CORSMiddleware

# Lokale optionale Python-Dependencies (z. B. pandas/numpy) aus dem Repo laden.
_LOCAL_PYDEPS = Path(__file__).resolve().parents[1] / "_pydeps"
if _LOCAL_PYDEPS.is_dir():
    local_pydeps = str(_LOCAL_PYDEPS)
    if local_pydeps not in sys.path:
        sys.path.insert(0, local_pydeps)

try:
    # Start aus Repo-Root: `python -m uvicorn backend.app.main:app ...`
    from backend.warehouse_project.warehouse_api import app as imported_warehouse_api
except ModuleNotFoundError:
    # Start aus `backend/`: `python -m uvicorn app.main:app ...`
    from warehouse_project.warehouse_api import app as imported_warehouse_api

app = FastAPI(title="Schaeflein LagerView API", version="2.0.0")

app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

# Importierte API aus warehouse-analytics-api ZIP unter eigenem Prefix.
app.mount("/warehouse-analytics-api", imported_warehouse_api)

WAREHOUSE_ID = "schlf-ber03"
WAREHOUSE_NAME = "Schaeflein Lager BER03"
WAREHOUSE_LOCATION = "Standort BER03"

PLATZ_TABLE = "df_platz_ber03_schlg_rti3"
PALETTE_TABLE = "df_palette_08042026_ber03_schlg_rti3"
TPA_TABLE = "df_tpa_6mon_ber03_schlg_rti3"
ORDER_TABLE = "df_order_6mon_schlg_rti3"


def _db_path() -> Path:
    configured = os.getenv("WAREHOUSE_DB_PATH", "").strip()
    if configured:
        configured_path = Path(configured).expanduser()
        if configured_path.is_file():
            return configured_path.resolve()

    root = Path(__file__).resolve().parents[2]
    candidates = [
        root / "data" / "warehouse.db",
        root / "warehouse.db",
    ]
    for candidate in candidates:
        if candidate.is_file():
            return candidate
    raise FileNotFoundError("warehouse.db nicht gefunden")


_DB_DOWNLOAD_LOCK = threading.Lock()


def _download_target() -> Path:
    """Zielpfad, wohin die DB heruntergeladen wird (Render Free: ephemeres /tmp)."""
    configured = os.getenv("WAREHOUSE_DB_PATH", "").strip()
    if configured:
        return Path(configured).expanduser()
    return Path(__file__).resolve().parents[2] / "data" / "warehouse.db"


def _ensure_db() -> Path:
    """DB lokal sicherstellen. Auf Render Free liegt keine DB im Image vor;
    dann einmalig von WAREHOUSE_DB_URL (z. B. GitHub-Release-Asset) laden."""
    try:
        return _db_path()
    except FileNotFoundError:
        pass

    url = os.getenv("WAREHOUSE_DB_URL", "").strip()
    if not url:
        raise FileNotFoundError(
            "warehouse.db nicht gefunden und WAREHOUSE_DB_URL ist nicht gesetzt"
        )

    target = _download_target()
    with _DB_DOWNLOAD_LOCK:
        # Erneut pruefen: ein paralleler Request koennte die DB schon geladen haben.
        if target.is_file() and target.stat().st_size > 0:
            return target.resolve()
        target.parent.mkdir(parents=True, exist_ok=True)
        tmp = target.with_name(target.name + ".part")
        urllib.request.urlretrieve(url, tmp)  # noqa: S310 (feste, eigene Release-URL)
        tmp.replace(target)
    return target.resolve()


def _connect() -> sqlite3.Connection:
    conn = sqlite3.connect(str(_ensure_db()))
    conn.row_factory = sqlite3.Row
    return conn


def _quote_identifier(identifier: str) -> str:
    safe = identifier.replace('"', '""')
    return f'"{safe}"'


def _discover_schema(
    conn: sqlite3.Connection, include_row_counts: bool = True
) -> dict[str, Any]:
    table_rows = conn.execute(
        """
        SELECT name
        FROM sqlite_master
        WHERE type = 'table'
          AND name NOT LIKE 'sqlite_%'
        ORDER BY name
        """
    ).fetchall()

    tables: list[dict[str, Any]] = []
    for table_row in table_rows:
        table_name = str(table_row["name"])
        pragma_rows = conn.execute(
            f"PRAGMA table_info({_quote_identifier(table_name)})"
        ).fetchall()

        columns: list[dict[str, Any]] = []
        id_column: str | None = None
        for col in pragma_rows:
            col_name = str(col["name"])
            pk_pos = _as_int(col["pk"])
            if pk_pos > 0 and id_column is None:
                id_column = col_name
            columns.append(
                {
                    "cid": _as_int(col["cid"]),
                    "name": col_name,
                    "type": str(col["type"] or ""),
                    "notnull": bool(col["notnull"]),
                    "default": col["dflt_value"],
                    "pk": pk_pos,
                }
            )

        if id_column is None:
            lowered = {c["name"].lower(): c["name"] for c in columns}
            id_column = lowered.get("id")

        row_count = None
        if include_row_counts:
            row_count = _as_int(
                conn.execute(
                    f"SELECT COUNT(*) AS cnt FROM {_quote_identifier(table_name)}"
                ).fetchone()["cnt"]
            )

        tables.append(
            {
                "name": table_name,
                "id_column": id_column,
                "row_count": row_count,
                "column_count": len(columns),
                "columns": columns,
            }
        )

    return {
        "database": str(_db_path()),
        "table_count": len(tables),
        "tables": tables,
    }


def _as_int(value: Any) -> int:
    if value is None:
        return 0
    if isinstance(value, bool):
        return int(value)
    if isinstance(value, int):
        return value
    if isinstance(value, float):
        return round(value)
    try:
        return int(str(value).strip())
    except ValueError:
        return 0


def _as_float(value: Any) -> float:
    if value is None:
        return 0.0
    if isinstance(value, bool):
        return float(int(value))
    if isinstance(value, (int, float)):
        return float(value)
    try:
        return float(str(value).strip().replace(",", "."))
    except ValueError:
        return 0.0


def _parse_date(raw: str) -> datetime | None:
    value = raw.strip()
    if not value:
        return None
    try:
        return datetime.fromisoformat(value)
    except ValueError:
        pass
    parts = value.split(".")
    if len(parts) == 3:
        try:
            return datetime(int(parts[2]), int(parts[1]), int(parts[0]))
        except ValueError:
            return None
    return None


def _load_zones(
    conn: sqlite3.Connection,
    total_slots: int,
    throughput_total: int,
    inbound_total: int,
    pick_rate_total: int,
) -> list[dict[str, Any]]:
    rows = conn.execute(
        f"""
        SELECT
          CASE
            WHEN CAST(COALESCE(REGAL, '0') AS INTEGER) BETWEEN 1 AND 16 THEN 'Halle 1'
            WHEN CAST(COALESCE(REGAL, '0') AS INTEGER) BETWEEN 17 AND 32 THEN 'Halle 2'
            ELSE 'Halle 3'
          END AS zone_name,
          COUNT(*) AS total_slots,
          SUM(CASE WHEN CAST(COALESCE(IST_LHM, 0) AS INT) > 0 THEN 1 ELSE 0 END) AS occupied_slots,
          SUM(CASE WHEN UPPER(TRIM(COALESCE(ABC_KLASSE, ''))) = 'A' THEN 1 ELSE 0 END) AS a_count,
          SUM(CASE WHEN UPPER(TRIM(COALESCE(ABC_KLASSE, ''))) = 'B' THEN 1 ELSE 0 END) AS b_count
        FROM {PLATZ_TABLE}
        WHERE TRIM(COALESCE(PLATZ_ID,'')) <> ''
        GROUP BY zone_name
        ORDER BY zone_name
        """
    ).fetchall()
    if not rows:
        return []

    safe_total = max(total_slots, 1)

    zones: list[dict[str, Any]] = []
    for idx, row in enumerate(rows):
        z_total = max(0, _as_int(row["total_slots"]))
        z_occupied = max(0, min(_as_int(row["occupied_slots"]), z_total))
        a_count = max(0, min(_as_int(row["a_count"]), z_total))
        b_count = max(0, min(_as_int(row["b_count"]), z_total))
        c_count = max(0, z_total - a_count - b_count)
        share = z_total / safe_total
        zones.append(
            {
                "id": f"{WAREHOUSE_ID}-z{idx + 1}",
                "name": str(row["zone_name"] or f"Zone {idx + 1}"),
                "total_storage_slots": z_total,
                "occupied_storage_slots": z_occupied,
                "article_count": z_total,
                "abc_analysis": {
                    "a_count": a_count,
                    "b_count": b_count,
                    "c_count": c_count,
                },
                # Zone-Aufteilung der echten Warehouse-Totals nach Platzanteil.
                "inbound_per_day": round(inbound_total * share),
                "throughput_per_day": round(throughput_total * share),
                "pick_rate_per_hour": round(pick_rate_total * share),
            }
        )
    return zones


def _load_warehouse(conn: sqlite3.Connection) -> dict[str, Any] | None:
    # Plaetze: total/occupied/ABC kommen aus PLATZ_TABLE.
    # occupied_slots verwendet IST_LHM > 0 (echte Belegung), nicht ZUSTAND>0
    # (das waeren nur die blockierten Plaetze).
    summary = conn.execute(
        f"""
        SELECT
          COUNT(*) AS total_slots,
          SUM(CASE WHEN CAST(COALESCE(IST_LHM, 0) AS INT) > 0 THEN 1 ELSE 0 END) AS occupied_slots,
          SUM(CASE WHEN
                CAST(COALESCE(MAX_LHM, 0) AS REAL) > 0
                AND CAST(COALESCE(IST_LHM, 0) AS REAL) > CAST(COALESCE(MAX_LHM, 0) AS REAL)
              THEN 1 ELSE 0 END) AS overloaded_slots,
          SUM(CASE WHEN UPPER(TRIM(COALESCE(ABC_KLASSE, ''))) = 'A' THEN 1 ELSE 0 END) AS abc_a,
          SUM(CASE WHEN UPPER(TRIM(COALESCE(ABC_KLASSE, ''))) = 'B' THEN 1 ELSE 0 END) AS abc_b
        FROM {PLATZ_TABLE}
        WHERE TRIM(COALESCE(PLATZ_ID,'')) <> ''
        """
    ).fetchone()
    if summary is None:
        return None

    total_slots = _as_int(summary["total_slots"])
    if total_slots <= 0:
        return None
    occupied_slots = _as_int(summary["occupied_slots"])
    overloaded_slots = _as_int(summary["overloaded_slots"])
    abc_a = _as_int(summary["abc_a"])
    abc_b = _as_int(summary["abc_b"])
    abc_c = max(0, total_slots - abc_a - abc_b)

    # Echte Artikel-Anzahl: distinct ARTIKELNR aus df_tpa (Bewegungs-Universum).
    article_row = conn.execute(
        f"""
        SELECT COUNT(DISTINCT TRIM(ARTIKELNR)) AS cnt
        FROM {TPA_TABLE}
        WHERE TRIM(COALESCE(ARTIKELNR,'')) <> ''
        """
    ).fetchone()
    article_count = _as_int(article_row["cnt"]) if article_row else 0

    # Echter Throughput pro Tag: Mittel ueber alle Tage mit Picks in df_tpa.
    throughput_row = conn.execute(
        f"""
        SELECT
          COUNT(*) AS total_picks,
          COUNT(DISTINCT ENDE_DATUM) AS days
        FROM {TPA_TABLE}
        WHERE TRIM(COALESCE(ENDE_DATUM,'')) <> ''
        """
    ).fetchone()
    total_picks = _as_int(throughput_row["total_picks"]) if throughput_row else 0
    pick_days = _as_int(throughput_row["days"]) if throughput_row else 0
    throughput_per_day = round(total_picks / pick_days) if pick_days > 0 else 0
    # 8h-Schicht als gaengige Annahme fuer Pick-Stundenrate.
    pick_rate_per_hour = round(throughput_per_day / 8) if throughput_per_day > 0 else 0

    # Echter Inbound: durchschnittliche Auftragszahl pro Tag aus df_order.
    inbound_row = conn.execute(
        f"""
        SELECT
          COUNT(DISTINCT AUFTRAGSNR) AS orders,
          COUNT(DISTINCT DATE(_CREATIONDATE)) AS days
        FROM {ORDER_TABLE}
        WHERE _CREATIONDATE IS NOT NULL
        """
    ).fetchone()
    order_count = _as_int(inbound_row["orders"]) if inbound_row else 0
    order_days = _as_int(inbound_row["days"]) if inbound_row else 0
    inbound_per_day = round(order_count / order_days) if order_days > 0 else 0
    zones = _load_zones(
        conn,
        total_slots,
        throughput_total=throughput_per_day,
        inbound_total=inbound_per_day,
        pick_rate_total=pick_rate_per_hour,
    )

    return {
        "id": WAREHOUSE_ID,
        "name": WAREHOUSE_NAME,
        "location": WAREHOUSE_LOCATION,
        "status": "online",
        "description": "Aus warehouse.db gelesen",
        "zone_count": len(zones),
        "total_storage_slots": total_slots,
        "occupied_storage_slots": occupied_slots,
        "overloaded_storage_slots": overloaded_slots,
        "article_count": article_count,
        "abc_analysis": {
            "a_count": abc_a,
            "b_count": abc_b,
            "c_count": abc_c,
        },
        "inbound_per_day": inbound_per_day,
        "throughput_per_day": throughput_per_day,
        "pick_rate_per_hour": pick_rate_per_hour,
        "zones": zones,
        "layout": {
            "length_m": 120.0,
            "width_m": 70.0,
            "height_m": 12.0,
            "rack_row_count": 32,
            "rack_length_m": 18.0,
            "rack_width_m": 2.8,
            "rack_levels": 4,
            "aisle_width_m": 3.2,
        },
        "model": None,
    }


@app.get("/health")
def health() -> dict[str, Any]:
    # Healthcheck darf NICHT den (grossen) DB-Download ausloesen, sonst
    # schlaegt der Render-Deploy-Healthcheck wegen Timeout fehl.
    try:
        return {"status": "ok", "database": str(_db_path()), "db_ready": True}
    except FileNotFoundError:
        return {
            "status": "ok",
            "database": _download_target().as_posix(),
            "db_ready": False,
            "download_configured": bool(os.getenv("WAREHOUSE_DB_URL", "").strip()),
        }


@app.get("/meta/schema")
def get_meta_schema(
    include_row_counts: bool = Query(default=True),
) -> dict[str, Any]:
    try:
        with _connect() as conn:
            return _discover_schema(conn, include_row_counts=include_row_counts)
    except Exception as exc:
        raise HTTPException(status_code=500, detail=f"DB-Fehler: {exc}") from exc


@app.get("/warehouses")
def get_warehouses() -> list[dict[str, Any]]:
    try:
        with _connect() as conn:
            warehouse = _load_warehouse(conn)
    except Exception as exc:
        raise HTTPException(status_code=500, detail=f"DB-Fehler: {exc}") from exc
    return [] if warehouse is None else [warehouse]


@app.get("/warehouses/{warehouse_id}")
def get_warehouse(warehouse_id: str) -> dict[str, Any]:
    if warehouse_id != WAREHOUSE_ID:
        raise HTTPException(status_code=404, detail="Warehouse not found.")
    try:
        with _connect() as conn:
            warehouse = _load_warehouse(conn)
    except Exception as exc:
        raise HTTPException(status_code=500, detail=f"DB-Fehler: {exc}") from exc
    if warehouse is None:
        raise HTTPException(status_code=404, detail="Warehouse not found.")
    return warehouse


@app.get("/warehouses/{warehouse_id}/operations-profile")
def get_operations_profile(warehouse_id: str) -> dict[str, Any]:
    if warehouse_id != WAREHOUSE_ID:
        raise HTTPException(status_code=404, detail="Warehouse not found.")
    try:
        with _connect() as conn:
            total_slots = _as_int(
                conn.execute(
                    f"SELECT COUNT(*) AS cnt FROM {PLATZ_TABLE} WHERE TRIM(COALESCE(PLATZ_ID,'')) <> ''"
                ).fetchone()["cnt"]
            )
            blocked_slots = _as_int(
                conn.execute(
                    f"SELECT COUNT(*) AS cnt FROM {PLATZ_TABLE} WHERE COALESCE(ZUSTAND, 0) >= 150"
                ).fetchone()["cnt"]
            )
            # SPERR_KNZ='0' bedeutet "nicht gesperrt", echte Sperren sind alle anderen Codes.
            reserved_slots = _as_int(
                conn.execute(
                    f"""
                    SELECT COUNT(*) AS cnt FROM {PLATZ_TABLE}
                    WHERE TRIM(COALESCE(SPERR_KNZ,'')) <> ''
                      AND TRIM(COALESCE(SPERR_KNZ,'')) <> '0'
                    """
                ).fetchone()["cnt"]
            )
            avg_dwell_days = _as_int(
                conn.execute(
                    f"""
                    SELECT ROUND(AVG(diff_days), 0) AS avg_days
                    FROM (
                      SELECT julianday('now') - julianday(LEER_DATUM) AS diff_days
                      FROM {PLATZ_TABLE}
                      WHERE TRIM(COALESCE(LEER_DATUM,'')) <> ''
                    )
                    """
                ).fetchone()["avg_days"]
            )
            pallet_type = _as_int(
                conn.execute(
                    f"SELECT COUNT(*) AS cnt FROM {PLATZ_TABLE} WHERE UPPER(TRIM(COALESCE(PLATZ_TYP,''))) = 'P'"
                ).fetchone()["cnt"]
            )
            floor_type = _as_int(
                conn.execute(
                    f"SELECT COUNT(*) AS cnt FROM {PLATZ_TABLE} WHERE UPPER(TRIM(COALESCE(PLATZ_TYP,''))) = 'F'"
                ).fetchone()["cnt"]
            )
            block_type = _as_int(
                conn.execute(
                    f"SELECT COUNT(*) AS cnt FROM {PLATZ_TABLE} WHERE UPPER(TRIM(COALESCE(PLATZ_TYP,''))) = 'U'"
                ).fetchone()["cnt"]
            )
    except Exception as exc:
        raise HTTPException(status_code=500, detail=f"DB-Fehler: {exc}") from exc

    return {
        "warehouse_id": WAREHOUSE_ID,
        "dock_count": 0,
        "active_docks": 0,
        "blocked_slots": max(0, min(blocked_slots, total_slots)),
        "reserved_slots": max(0, min(reserved_slots, total_slots)),
        "sla_target_percent": 0,
        "sla_current_percent": 0,
        "avg_dwell_minutes": max(0, avg_dwell_days * 60),
        "cold_zone_count": 0,
        "ambient_zone_count": 0,
        "hazardous_zone_count": 0,
        "high_bay_slots": max(0, min(pallet_type, total_slots)),
        "block_storage_slots": max(0, min(block_type, total_slots)),
        "shuttle_slots": max(0, total_slots - pallet_type - floor_type - block_type),
        "floor_storage_slots": max(0, min(floor_type, total_slots)),
        "safety_incidents_month": 0,
        "quality_holds": max(0, blocked_slots),
    }


@app.get("/warehouses/{warehouse_id}/storage-locations")
def get_storage_locations(
    warehouse_id: str,
    limit: int = Query(default=120, ge=1, le=2000),
) -> list[dict[str, Any]]:
    if warehouse_id != WAREHOUSE_ID:
        raise HTTPException(status_code=404, detail="Warehouse not found.")
    try:
        with _connect() as conn:
            rows = conn.execute(
                f"""
                SELECT
                  TRIM(p.PLATZ_ID) AS place_id,
                  CAST(COALESCE(p.BEREICH, 0) AS TEXT) AS area,
                  CAST(COALESCE(p.REGAL, '0') AS INTEGER) AS rack_number,
                  CAST(COALESCE(p.EBENE, 0) AS INTEGER) AS level_number,
                  CAST(COALESCE(p.FACH, 0) AS INTEGER) AS slot_number,
                  UPPER(TRIM(COALESCE(p.ABC_KLASSE, ''))) AS abc_class,
                  CAST(COALESCE(p.ZUSTAND, 0) AS INTEGER) AS status_code,
                  '' AS article_id,
                  COALESCE(p.LEER_DATUM, '') AS last_move_day,
                  CAST(COALESCE(p.ANZ_PICKS, 0) AS INTEGER) AS movements_30d
                FROM {PLATZ_TABLE} p
                WHERE TRIM(COALESCE(p.PLATZ_ID,'')) <> ''
                ORDER BY CAST(COALESCE(p.REGAL, '0') AS INTEGER), CAST(COALESCE(p.EBENE, 0) AS INTEGER), CAST(COALESCE(p.FACH, 0) AS INTEGER)
                LIMIT ?
                """,
                (limit,),
            ).fetchall()
    except Exception as exc:
        raise HTTPException(status_code=500, detail=f"DB-Fehler: {exc}") from exc

    now = datetime.now()
    result: list[dict[str, Any]] = []
    seen: set[str] = set()
    for row in rows:
        place_id = str(row["place_id"] or "").strip()
        if not place_id or place_id in seen:
            continue
        seen.add(place_id)
        last_move = _parse_date(str(row["last_move_day"] or ""))
        days_since = None
        if last_move is not None:
            days_since = (now.date() - last_move.date()).days
        status_code = _as_int(row["status_code"])
        if status_code >= 150:
            status = "Gesperrt"
        elif status_code > 0:
            status = "Belegt"
        else:
            status = "Frei"
        abc = str(row["abc_class"] or "").strip().upper()
        if abc not in {"A", "B", "C"}:
            abc = "C"
        result.append(
            {
                "place_id": place_id,
                "area": str(row["area"] or ""),
                "rack_number": _as_int(row["rack_number"]),
                "level_number": _as_int(row["level_number"]),
                "slot_number": _as_int(row["slot_number"]),
                "abc_class": abc,
                "status": status,
                "article_id": str(row["article_id"] or "").strip(),
                "days_since_movement": days_since,
                "movements_30d": _as_int(row["movements_30d"]),
            }
        )
    return result


@app.get("/warehouses/{warehouse_id}/throughput-trend")
def get_throughput_trend(
    warehouse_id: str,
    days: int = Query(default=14, ge=1, le=365),
) -> list[dict[str, Any]]:
    if warehouse_id != WAREHOUSE_ID:
        raise HTTPException(status_code=404, detail="Warehouse not found.")
    try:
        with _connect() as conn:
            rows = conn.execute(
                f"""
                SELECT ENDE_DATUM AS day, COUNT(*) AS count
                FROM {TPA_TABLE}
                WHERE TRIM(COALESCE(ENDE_DATUM,'')) <> ''
                GROUP BY ENDE_DATUM
                ORDER BY ENDE_DATUM DESC
                LIMIT ?
                """,
                (days,),
            ).fetchall()
    except Exception as exc:
        raise HTTPException(status_code=500, detail=f"DB-Fehler: {exc}") from exc

    points: list[dict[str, Any]] = []
    for row in rows:
        day = str(row["day"] or "").strip()
        parsed = _parse_date(day)
        if parsed is None:
            continue
        points.append({"date": parsed.date().isoformat(), "value": _as_int(row["count"])})
    points.sort(key=lambda item: item["date"])
    return points


@app.get("/warehouses/{warehouse_id}/abc-articles")
def get_abc_articles(
    warehouse_id: str,
    limit: int = Query(default=10000, ge=1, le=200000),
) -> list[dict[str, Any]]:
    if warehouse_id != WAREHOUSE_ID:
        raise HTTPException(status_code=404, detail="Warehouse not found.")
    try:
        with _connect() as conn:
            rows = conn.execute(
                f"""
                SELECT
                  TRIM(COALESCE(t.ARTIKELNR, '')) AS article_id,
                  COUNT(*) AS movements_30d,
                  COUNT(DISTINCT TRIM(COALESCE(t.Z_PLATZ, ''))) AS slot_count,
                  CAST(
                    julianday('now') - julianday(MAX(DATE(t.ENDE_DATUM)))
                    AS INTEGER
                  ) AS max_idle_days
                FROM {TPA_TABLE} t
                WHERE TRIM(COALESCE(t.ARTIKELNR, '')) <> ''
                  AND TRIM(COALESCE(t.ENDE_DATUM, '')) <> ''
                GROUP BY TRIM(COALESCE(t.ARTIKELNR, ''))
                ORDER BY movements_30d DESC, article_id ASC
                LIMIT ?
                """,
                (limit,),
            ).fetchall()
    except Exception as exc:
        raise HTTPException(status_code=500, detail=f"DB-Fehler: {exc}") from exc

    # Pareto-/Lorenz-Klassifizierung: kumulativer Anteil der Bewegungen.
    # A = top, bis 80 % der Bewegungen, B = bis 95 %, C = Rest.
    # Rows sind bereits nach movements_30d DESC sortiert.
    total_moves = sum(_as_int(r["movements_30d"]) for r in rows)
    result: list[dict[str, Any]] = []
    cum = 0
    for row in rows:
        article_id = str(row["article_id"] or "").strip()
        if not article_id:
            continue
        movements = _as_int(row["movements_30d"])
        cum += movements
        cum_pct = (cum / total_moves * 100) if total_moves > 0 else 0.0
        if cum_pct <= 80:
            abc_class = "A"
        elif cum_pct <= 95:
            abc_class = "B"
        else:
            abc_class = "C"
        result.append(
            {
                "article_id": article_id,
                "abc_class": abc_class,
                "slot_count": _as_int(row["slot_count"]),
                "movements_30d": movements,
                "max_idle_days": _as_int(row["max_idle_days"]),
            }
        )
    return result


@app.get("/warehouses/{warehouse_id}/abc-slots")
def get_abc_slots(
    warehouse_id: str,
    limit: int = Query(default=10000, ge=1, le=100000),
) -> list[dict[str, Any]]:
    """Per-Platz ABC: PLATZ_ID, Halle, Regal, Fach, Ebene, ANZ_PICKS,
    Cumulative %, ABC_CALC (aus Picks), ABC_KLASSE (Master) + Top-Artikel."""
    if warehouse_id != WAREHOUSE_ID:
        raise HTTPException(status_code=404, detail="Warehouse not found.")
    try:
        with _connect() as conn:
            rows = conn.execute(
                f"""
                WITH top_article AS (
                    SELECT
                      TRIM(COALESCE(t.Q_PLATZ, '')) AS place_id,
                      TRIM(COALESCE(t.ARTIKELNR, '')) AS article_id,
                      TRIM(COALESCE(t.ARTBEZ1, '')) AS article_description,
                      COUNT(*) AS picks_for_article,
                      ROW_NUMBER() OVER (
                        PARTITION BY TRIM(COALESCE(t.Q_PLATZ, ''))
                        ORDER BY COUNT(*) DESC, TRIM(COALESCE(t.ARTIKELNR, '')) ASC
                      ) AS rn
                    FROM {TPA_TABLE} t
                    WHERE TRIM(COALESCE(t.Q_PLATZ, '')) <> ''
                    GROUP BY
                      TRIM(COALESCE(t.Q_PLATZ, '')),
                      TRIM(COALESCE(t.ARTIKELNR, '')),
                      TRIM(COALESCE(t.ARTBEZ1, ''))
                )
                SELECT
                  TRIM(COALESCE(p.PLATZ_ID, '')) AS place_id,
                  TRIM(COALESCE(p.HAUSNR, '')) AS halle,
                  TRIM(COALESCE(p.BEREICH, '')) AS bereich,
                  TRIM(COALESCE(p.REGAL, '')) AS regal,
                  TRIM(COALESCE(p.FACH, '')) AS fach,
                  TRIM(COALESCE(p.EBENE, '')) AS ebene,
                  CAST(COALESCE(p.ANZ_PICKS, 0) AS INTEGER) AS anz_picks,
                  UPPER(TRIM(COALESCE(p.ABC_KLASSE, ''))) AS abc_klasse,
                  CAST(COALESCE(p.MAX_LHM, 0) AS REAL) AS max_lhm,
                  CAST(COALESCE(p.IST_LHM, 0) AS REAL) AS ist_lhm,
                  COALESCE(a.article_id, '') AS article_id,
                  COALESCE(a.article_description, '') AS article_description
                FROM {PLATZ_TABLE} p
                LEFT JOIN top_article a
                  ON a.place_id = TRIM(COALESCE(p.PLATZ_ID, ''))
                 AND a.rn = 1
                WHERE TRIM(COALESCE(p.PLATZ_ID, '')) <> ''
                ORDER BY anz_picks DESC, place_id ASC
                LIMIT ?
                """,
                (limit,),
            ).fetchall()
    except Exception as exc:
        raise HTTPException(status_code=500, detail=f"DB-Fehler: {exc}") from exc

    total_picks = sum(_as_int(row["anz_picks"]) for row in rows)
    cum = 0
    result: list[dict[str, Any]] = []
    for row in rows:
        picks = _as_int(row["anz_picks"])
        cum += picks
        if total_picks > 0:
            cum_pct = round(cum / total_picks * 100, 2)
        else:
            cum_pct = 0.0
        if cum_pct <= 80:
            abc_calc = "A"
        elif cum_pct <= 95:
            abc_calc = "B"
        else:
            abc_calc = "C"
        master = str(row["abc_klasse"] or "").strip().upper()
        if master not in {"A", "B", "C"}:
            master = ""
        max_lhm = float(row["max_lhm"] or 0)
        ist_lhm = float(row["ist_lhm"] or 0)
        free_cap = max_lhm - ist_lhm
        util = round((ist_lhm / max_lhm) * 100, 2) if max_lhm > 0 else 0.0
        result.append(
            {
                "place_id": str(row["place_id"] or ""),
                "halle": str(row["halle"] or ""),
                "bereich": str(row["bereich"] or ""),
                "regal": str(row["regal"] or ""),
                "fach": str(row["fach"] or ""),
                "ebene": str(row["ebene"] or ""),
                "anz_picks": picks,
                "cumulative_pct": cum_pct,
                "abc_calc": abc_calc,
                "abc_class": master,
                "article_id": str(row["article_id"] or ""),
                "article_description": str(row["article_description"] or ""),
                "max_lhm": max_lhm,
                "ist_lhm": ist_lhm,
                "free_capacity": free_cap,
                "utilization_pct": util,
            }
        )
    return result


@app.get("/warehouses/{warehouse_id}/order-volume-trend")
def get_order_volume_trend(
    warehouse_id: str,
    days: int = Query(default=30, ge=1, le=365),
) -> list[dict[str, Any]]:
    if warehouse_id != WAREHOUSE_ID:
        raise HTTPException(status_code=404, detail="Warehouse not found.")
    try:
        with _connect() as conn:
            rows = conn.execute(
                f"""
                SELECT
                  DATE(_CREATIONDATE) AS day,
                  COUNT(DISTINCT AUFTRAGSNR) AS orders,
                  COUNT(*) AS positions,
                  SUM(CAST(REPLACE(COALESCE(MENGE_SOLL, '0'), ',', '.') AS REAL)) AS qty
                FROM {ORDER_TABLE}
                WHERE _CREATIONDATE IS NOT NULL
                GROUP BY DATE(_CREATIONDATE)
                ORDER BY day DESC
                LIMIT ?
                """,
                (days,),
            ).fetchall()
    except Exception as exc:
        raise HTTPException(status_code=500, detail=f"DB-Fehler: {exc}") from exc

    points: list[dict[str, Any]] = []
    for row in rows:
        day = str(row["day"] or "").strip()
        if not day:
            continue
        parsed = _parse_date(day)
        if parsed is None:
            continue
        points.append(
            {
                "date": parsed.date().isoformat(),
                "orders": _as_int(row["orders"]),
                "positions": _as_int(row["positions"]),
                "quantity": _as_int(row["qty"]),
            }
        )
    points.sort(key=lambda item: item["date"])
    return points


@app.get("/warehouses/{warehouse_id}/pick-activity-heatmap")
def get_pick_activity_heatmap(warehouse_id: str) -> dict[str, Any]:
    if warehouse_id != WAREHOUSE_ID:
        raise HTTPException(status_code=404, detail="Warehouse not found.")
    try:
        with _connect() as conn:
            rows = conn.execute(
                f"""
                SELECT
                  CAST(strftime('%w', ENDE_DATUM) AS INTEGER) AS weekday,
                  CAST(substr(ENDE_ZEIT, 1, 2) AS INTEGER) AS hour,
                  COUNT(*) AS picks
                FROM {TPA_TABLE}
                WHERE TRIM(COALESCE(ENDE_DATUM,'')) <> ''
                  AND TRIM(COALESCE(ENDE_ZEIT,'')) <> ''
                GROUP BY weekday, hour
                """
            ).fetchall()
            range_row = conn.execute(
                f"""
                SELECT MIN(ENDE_DATUM) AS min_date, MAX(ENDE_DATUM) AS max_date
                FROM {TPA_TABLE}
                WHERE TRIM(COALESCE(ENDE_DATUM,'')) <> ''
                """
            ).fetchone()
    except Exception as exc:
        raise HTTPException(status_code=500, detail=f"DB-Fehler: {exc}") from exc

    cells: list[dict[str, Any]] = []
    max_picks = 0
    for row in rows:
        weekday = _as_int(row["weekday"])
        hour = _as_int(row["hour"])
        if weekday < 0 or weekday > 6 or hour < 0 or hour > 23:
            continue
        picks = _as_int(row["picks"])
        if picks > max_picks:
            max_picks = picks
        cells.append({"weekday": weekday, "hour": hour, "picks": picks})

    return {
        "warehouse_id": warehouse_id,
        "min_date": str(range_row["min_date"] or "") if range_row else "",
        "max_date": str(range_row["max_date"] or "") if range_row else "",
        "max_picks": max_picks,
        "cells": cells,
    }


@app.get("/warehouses/{warehouse_id}/relocation-candidates")
def get_relocation_candidates(
    warehouse_id: str,
    limit: int = Query(default=12, ge=1, le=200),
    high_pick_threshold: int = Query(default=100, ge=1),
    high_level: int = Query(default=4, ge=1),
) -> dict[str, Any]:
    """Drei datenbasierte Umlager-Kategorien:

    1. Premium-Plaetze ungenutzt: ABC='A', 0 Picks, nicht gesperrt.
    2. Hochfrequente C-Plaetze: ABC='C' mit Picks >= Schwellwert.
    3. A-Plaetze auf hohen Ebenen aktiv: ABC='A', EBENE >= Schwelle, Picks > 0.
    """
    if warehouse_id != WAREHOUSE_ID:
        raise HTTPException(status_code=404, detail="Warehouse not found.")
    try:
        with _connect() as conn:
            summary_row = conn.execute(
                f"""
                SELECT
                  SUM(CASE
                    WHEN UPPER(TRIM(COALESCE(ABC_KLASSE,''))) = 'A'
                      AND CAST(COALESCE(ANZ_PICKS,0) AS INT) = 0
                      AND COALESCE(ZUSTAND, 0) < 150
                    THEN 1 ELSE 0 END) AS unused_a,
                  SUM(CASE
                    WHEN UPPER(TRIM(COALESCE(ABC_KLASSE,''))) = 'C'
                      AND CAST(COALESCE(ANZ_PICKS,0) AS INT) >= ?
                    THEN 1 ELSE 0 END) AS hot_c,
                  SUM(CASE
                    WHEN UPPER(TRIM(COALESCE(ABC_KLASSE,''))) = 'A'
                      AND CAST(COALESCE(EBENE,0) AS INT) >= ?
                      AND CAST(COALESCE(ANZ_PICKS,0) AS INT) > 0
                    THEN 1 ELSE 0 END) AS high_level_a
                FROM {PLATZ_TABLE}
                WHERE TRIM(COALESCE(PLATZ_ID,'')) <> ''
                """,
                (high_pick_threshold, high_level),
            ).fetchone()

            unused_a_rows = conn.execute(
                f"""
                SELECT
                  TRIM(PLATZ_ID) AS place_id,
                  CAST(COALESCE(REGAL,'0') AS INTEGER) AS rack_number,
                  CAST(COALESCE(EBENE,0) AS INTEGER) AS level_number,
                  CAST(COALESCE(FACH,0) AS INTEGER) AS slot_number,
                  CAST(COALESCE(ANZ_PICKS,0) AS INTEGER) AS picks
                FROM {PLATZ_TABLE}
                WHERE UPPER(TRIM(COALESCE(ABC_KLASSE,''))) = 'A'
                  AND CAST(COALESCE(ANZ_PICKS,0) AS INT) = 0
                  AND COALESCE(ZUSTAND, 0) < 150
                  AND TRIM(COALESCE(PLATZ_ID,'')) <> ''
                ORDER BY rack_number, level_number, slot_number
                LIMIT ?
                """,
                (limit,),
            ).fetchall()

            hot_c_rows = conn.execute(
                f"""
                SELECT
                  TRIM(PLATZ_ID) AS place_id,
                  CAST(COALESCE(REGAL,'0') AS INTEGER) AS rack_number,
                  CAST(COALESCE(EBENE,0) AS INTEGER) AS level_number,
                  CAST(COALESCE(FACH,0) AS INTEGER) AS slot_number,
                  CAST(COALESCE(ANZ_PICKS,0) AS INTEGER) AS picks
                FROM {PLATZ_TABLE}
                WHERE UPPER(TRIM(COALESCE(ABC_KLASSE,''))) = 'C'
                  AND CAST(COALESCE(ANZ_PICKS,0) AS INT) >= ?
                  AND TRIM(COALESCE(PLATZ_ID,'')) <> ''
                ORDER BY picks DESC
                LIMIT ?
                """,
                (high_pick_threshold, limit),
            ).fetchall()

            high_level_a_rows = conn.execute(
                f"""
                SELECT
                  TRIM(PLATZ_ID) AS place_id,
                  CAST(COALESCE(REGAL,'0') AS INTEGER) AS rack_number,
                  CAST(COALESCE(EBENE,0) AS INTEGER) AS level_number,
                  CAST(COALESCE(FACH,0) AS INTEGER) AS slot_number,
                  CAST(COALESCE(ANZ_PICKS,0) AS INTEGER) AS picks
                FROM {PLATZ_TABLE}
                WHERE UPPER(TRIM(COALESCE(ABC_KLASSE,''))) = 'A'
                  AND CAST(COALESCE(EBENE,0) AS INT) >= ?
                  AND CAST(COALESCE(ANZ_PICKS,0) AS INT) > 0
                  AND TRIM(COALESCE(PLATZ_ID,'')) <> ''
                ORDER BY picks DESC
                LIMIT ?
                """,
                (high_level, limit),
            ).fetchall()
    except Exception as exc:
        raise HTTPException(status_code=500, detail=f"DB-Fehler: {exc}") from exc

    def _serialize(row, abc: str, reason: str) -> dict[str, Any]:
        return {
            "place_id": str(row["place_id"]),
            "rack_number": _as_int(row["rack_number"]),
            "level_number": _as_int(row["level_number"]),
            "slot_number": _as_int(row["slot_number"]),
            "picks": _as_int(row["picks"]),
            "abc_class": abc,
            "reason": reason,
        }

    return {
        "warehouse_id": warehouse_id,
        "high_pick_threshold": high_pick_threshold,
        "high_level": high_level,
        "summary": {
            "unused_a": _as_int(summary_row["unused_a"]) if summary_row else 0,
            "hot_c": _as_int(summary_row["hot_c"]) if summary_row else 0,
            "high_level_a": _as_int(summary_row["high_level_a"])
            if summary_row
            else 0,
        },
        "unused_a_places": [
            _serialize(row, "A", "A-Klasse, aber 0 Picks - Premium-Platz nicht genutzt")
            for row in unused_a_rows
        ],
        "hot_c_places": [
            _serialize(row, "C", "C-Klasse, aber hohe Pickfrequenz - Klasse anpassen")
            for row in hot_c_rows
        ],
        "high_level_a_places": [
            _serialize(row, "A", "A-Klasse auf hoher Ebene - nach unten holen")
            for row in high_level_a_rows
        ],
    }


@app.get("/warehouses/{warehouse_id}/replenishment-candidates")
def get_replenishment_candidates(
    warehouse_id: str,
    limit: int = Query(default=12, ge=1, le=200),
    pick_threshold: int = Query(default=50, ge=1),
    medium_pick_threshold: int = Query(default=20, ge=1),
    overdue_days: int = Query(default=14, ge=1),
    pick_level: int = Query(default=2, ge=0),
) -> dict[str, Any]:
    """Drei datenbasierte Replenishment-Kategorien:

    1. Dringend leer: aktiver Pickplatz (EBENE<=pick_level, Picks>=pick_threshold),
       IST_LHM=0, nicht gesperrt.
    2. Ueberfaellig: dringend leer und LEER_DATUM aelter als overdue_days.
    3. Mittel: leer mit medium_pick_threshold<=Picks<pick_threshold.
    """
    if warehouse_id != WAREHOUSE_ID:
        raise HTTPException(status_code=404, detail="Warehouse not found.")
    try:
        with _connect() as conn:
            summary_row = conn.execute(
                f"""
                SELECT
                  SUM(CASE
                    WHEN CAST(COALESCE(IST_LHM,0) AS INT) = 0
                      AND CAST(COALESCE(EBENE,0) AS INT) <= ?
                      AND CAST(COALESCE(ANZ_PICKS,0) AS INT) >= ?
                      AND COALESCE(ZUSTAND, 0) < 150
                    THEN 1 ELSE 0 END) AS urgent,
                  SUM(CASE
                    WHEN CAST(COALESCE(IST_LHM,0) AS INT) = 0
                      AND CAST(COALESCE(EBENE,0) AS INT) <= ?
                      AND CAST(COALESCE(ANZ_PICKS,0) AS INT) >= ?
                      AND COALESCE(ZUSTAND, 0) < 150
                      AND TRIM(COALESCE(LEER_DATUM,'')) <> ''
                      AND CAST(julianday('now') - julianday(LEER_DATUM) AS INT) >= ?
                    THEN 1 ELSE 0 END) AS overdue,
                  SUM(CASE
                    WHEN CAST(COALESCE(IST_LHM,0) AS INT) = 0
                      AND CAST(COALESCE(EBENE,0) AS INT) <= ?
                      AND CAST(COALESCE(ANZ_PICKS,0) AS INT) >= ?
                      AND CAST(COALESCE(ANZ_PICKS,0) AS INT) < ?
                      AND COALESCE(ZUSTAND, 0) < 150
                    THEN 1 ELSE 0 END) AS medium
                FROM {PLATZ_TABLE}
                WHERE TRIM(COALESCE(PLATZ_ID,'')) <> ''
                """,
                (
                    pick_level,
                    pick_threshold,
                    pick_level,
                    pick_threshold,
                    overdue_days,
                    pick_level,
                    medium_pick_threshold,
                    pick_threshold,
                ),
            ).fetchone()

            urgent_rows = conn.execute(
                f"""
                SELECT
                  TRIM(PLATZ_ID) AS place_id,
                  CAST(COALESCE(REGAL,'0') AS INTEGER) AS rack_number,
                  CAST(COALESCE(EBENE,0) AS INTEGER) AS level_number,
                  CAST(COALESCE(FACH,0) AS INTEGER) AS slot_number,
                  CAST(COALESCE(ANZ_PICKS,0) AS INTEGER) AS picks,
                  COALESCE(LEER_DATUM,'') AS leer_datum,
                  CAST(julianday('now') - julianday(LEER_DATUM) AS INTEGER) AS days_empty
                FROM {PLATZ_TABLE}
                WHERE CAST(COALESCE(IST_LHM,0) AS INT) = 0
                  AND CAST(COALESCE(EBENE,0) AS INT) <= ?
                  AND CAST(COALESCE(ANZ_PICKS,0) AS INT) >= ?
                  AND COALESCE(ZUSTAND, 0) < 150
                  AND TRIM(COALESCE(PLATZ_ID,'')) <> ''
                ORDER BY picks DESC
                LIMIT ?
                """,
                (pick_level, pick_threshold, limit),
            ).fetchall()

            overdue_rows = conn.execute(
                f"""
                SELECT
                  TRIM(PLATZ_ID) AS place_id,
                  CAST(COALESCE(REGAL,'0') AS INTEGER) AS rack_number,
                  CAST(COALESCE(EBENE,0) AS INTEGER) AS level_number,
                  CAST(COALESCE(FACH,0) AS INTEGER) AS slot_number,
                  CAST(COALESCE(ANZ_PICKS,0) AS INTEGER) AS picks,
                  COALESCE(LEER_DATUM,'') AS leer_datum,
                  CAST(julianday('now') - julianday(LEER_DATUM) AS INTEGER) AS days_empty
                FROM {PLATZ_TABLE}
                WHERE CAST(COALESCE(IST_LHM,0) AS INT) = 0
                  AND CAST(COALESCE(EBENE,0) AS INT) <= ?
                  AND CAST(COALESCE(ANZ_PICKS,0) AS INT) >= ?
                  AND COALESCE(ZUSTAND, 0) < 150
                  AND TRIM(COALESCE(LEER_DATUM,'')) <> ''
                  AND CAST(julianday('now') - julianday(LEER_DATUM) AS INT) >= ?
                  AND TRIM(COALESCE(PLATZ_ID,'')) <> ''
                ORDER BY days_empty DESC
                LIMIT ?
                """,
                (pick_level, pick_threshold, overdue_days, limit),
            ).fetchall()

            medium_rows = conn.execute(
                f"""
                SELECT
                  TRIM(PLATZ_ID) AS place_id,
                  CAST(COALESCE(REGAL,'0') AS INTEGER) AS rack_number,
                  CAST(COALESCE(EBENE,0) AS INTEGER) AS level_number,
                  CAST(COALESCE(FACH,0) AS INTEGER) AS slot_number,
                  CAST(COALESCE(ANZ_PICKS,0) AS INTEGER) AS picks,
                  COALESCE(LEER_DATUM,'') AS leer_datum,
                  CAST(julianday('now') - julianday(LEER_DATUM) AS INTEGER) AS days_empty
                FROM {PLATZ_TABLE}
                WHERE CAST(COALESCE(IST_LHM,0) AS INT) = 0
                  AND CAST(COALESCE(EBENE,0) AS INT) <= ?
                  AND CAST(COALESCE(ANZ_PICKS,0) AS INT) >= ?
                  AND CAST(COALESCE(ANZ_PICKS,0) AS INT) < ?
                  AND COALESCE(ZUSTAND, 0) < 150
                  AND TRIM(COALESCE(PLATZ_ID,'')) <> ''
                ORDER BY picks DESC
                LIMIT ?
                """,
                (pick_level, medium_pick_threshold, pick_threshold, limit),
            ).fetchall()
    except Exception as exc:
        raise HTTPException(status_code=500, detail=f"DB-Fehler: {exc}") from exc

    def _serialize(row, reason: str) -> dict[str, Any]:
        return {
            "place_id": str(row["place_id"]),
            "rack_number": _as_int(row["rack_number"]),
            "level_number": _as_int(row["level_number"]),
            "slot_number": _as_int(row["slot_number"]),
            "picks": _as_int(row["picks"]),
            "days_empty": _as_int(row["days_empty"]) if row["days_empty"] is not None else 0,
            "leer_datum": str(row["leer_datum"] or ""),
            "reason": reason,
        }

    return {
        "warehouse_id": warehouse_id,
        "pick_threshold": pick_threshold,
        "medium_pick_threshold": medium_pick_threshold,
        "overdue_days": overdue_days,
        "pick_level": pick_level,
        "summary": {
            "urgent": _as_int(summary_row["urgent"]) if summary_row else 0,
            "overdue": _as_int(summary_row["overdue"]) if summary_row else 0,
            "medium": _as_int(summary_row["medium"]) if summary_row else 0,
        },
        "urgent_places": [
            _serialize(row, "Aktiver Pickplatz leer - dringend nachfuellen")
            for row in urgent_rows
        ],
        "overdue_places": [
            _serialize(row, "Bereits laenger leer - Replenishment vergessen?")
            for row in overdue_rows
        ],
        "medium_places": [
            _serialize(row, "Pickplatz leer mit mittlerer Frequenz")
            for row in medium_rows
        ],
    }


@app.get("/warehouses/{warehouse_id}/model")
def get_generated_model(warehouse_id: str) -> dict[str, Any]:
    if warehouse_id != WAREHOUSE_ID:
        raise HTTPException(status_code=404, detail="Warehouse not found.")
    return {"warehouse_id": warehouse_id, "model": None}
