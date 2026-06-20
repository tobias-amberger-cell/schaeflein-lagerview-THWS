from pathlib import Path
import sys
import os
from typing import Annotated
import csv

from fastapi import FastAPI, Query
import sqlite3

app = FastAPI()

_LOCAL_PYDEPS = Path(__file__).resolve().parents[1] / "_pydeps"
if _LOCAL_PYDEPS.is_dir():
    local_pydeps = str(_LOCAL_PYDEPS)
    if local_pydeps not in sys.path:
        sys.path.insert(0, local_pydeps)


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
        Path.cwd() / "warehouse.db",
    ]
    for candidate in candidates:
        if candidate.is_file():
            return candidate.resolve()
    raise FileNotFoundError("warehouse.db nicht gefunden")


def _heatmap_csv_path() -> Path:
    return Path(__file__).resolve().with_name("warehouse_heatmap.csv")


@app.get("/")
def home():
    return {"message": "Warehouse API laeuft"}


@app.get("/analytics")
def analytics():
    import numpy as np
    import pandas as pd

    conn = sqlite3.connect(str(_db_path()))

    platz = pd.read_sql(
        """
        SELECT *
        FROM df_platz_ber03_schlg_rti3
        """,
        conn,
    )

    conn.close()

    platz["MAX_LHM"] = pd.to_numeric(platz["MAX_LHM"], errors="coerce")
    platz["IST_LHM"] = pd.to_numeric(platz["IST_LHM"], errors="coerce")

    platz["UTILIZATION"] = np.where(
        platz["MAX_LHM"] > 0,
        (platz["IST_LHM"] / platz["MAX_LHM"]) * 100,
        0,
    )

    return {
        "total_locations": int(len(platz)),
        "avg_utilization": float(round(platz["UTILIZATION"].mean(), 2)),
        "max_utilization": float(round(platz["UTILIZATION"].max(), 2)),
        "free_locations": int((platz["IST_LHM"] == 0).sum()),
    }


@app.get("/heatmap")
def heatmap():
    def _to_int(raw: object) -> int:
        text = str(raw or "").strip().replace(",", ".")
        if not text:
            return 0
        try:
            value = float(text)
            if value != value:  # NaN
                return 0
            return int(value)
        except ValueError:
            return 0

    def _to_float(raw: object) -> float:
        text = str(raw or "").strip().replace(",", ".")
        if not text:
            return 0.0
        try:
            value = float(text)
            return 0.0 if value != value else value
        except ValueError:
            return 0.0

    path = _heatmap_csv_path()
    if not path.is_file():
        return []
    result: list[dict[str, object]] = []
    with path.open("r", encoding="utf-8", newline="") as handle:
        reader = csv.DictReader(handle)
        for row in reader:
            result.append(
                {
                    "PLATZ_ID": str(row.get("PLATZ_ID", "")).strip(),
                    "REGAL": _to_int(row.get("REGAL")),
                    "FACH": _to_int(row.get("FACH")),
                    "EBENE": _to_int(row.get("EBENE")),
                    "UTILIZATION": _to_float(row.get("UTILIZATION")),
                    "HEATMAP_COLOR": str(row.get("HEATMAP_COLOR", "")).strip().upper(),
                }
            )
            if len(result) >= 500:
                break
    return result


@app.get("/critical-locations")
def critical_locations(limit: Annotated[int, Query(ge=1, le=200)] = 10):
    import numpy as np
    import pandas as pd

    conn = sqlite3.connect(str(_db_path()))
    platz = pd.read_sql(
        """
        SELECT PLATZ_ID, REGAL, FACH, EBENE, MAX_LHM, IST_LHM
        FROM df_platz_ber03_schlg_rti3
        """,
        conn,
    )
    conn.close()

    platz["MAX_LHM"] = pd.to_numeric(platz["MAX_LHM"], errors="coerce")
    platz["IST_LHM"] = pd.to_numeric(platz["IST_LHM"], errors="coerce")
    platz["UTILIZATION"] = np.where(
        platz["MAX_LHM"] > 0,
        (platz["IST_LHM"] / platz["MAX_LHM"]) * 100,
        0,
    )

    def _risk_color(util: float) -> str:
        if util >= 80:
            return "RED"
        if util >= 40:
            return "YELLOW"
        return "GREEN"

    ranked = (
        platz.sort_values(by=["UTILIZATION", "IST_LHM"], ascending=False)
        .head(limit)
        .copy()
    )
    ranked["HEATMAP_COLOR"] = ranked["UTILIZATION"].apply(_risk_color)

    result = []
    for _, row in ranked.iterrows():
        result.append(
            {
                "platz_id": str(row["PLATZ_ID"]) if pd.notna(row["PLATZ_ID"]) else "",
                "regal": int(row["REGAL"]) if pd.notna(row["REGAL"]) else 0,
                "fach": int(row["FACH"]) if pd.notna(row["FACH"]) else 0,
                "ebene": int(row["EBENE"]) if pd.notna(row["EBENE"]) else 0,
                "max_lhm": float(row["MAX_LHM"]) if pd.notna(row["MAX_LHM"]) else 0.0,
                "ist_lhm": float(row["IST_LHM"]) if pd.notna(row["IST_LHM"]) else 0.0,
                "utilization": float(round(row["UTILIZATION"], 2)),
                "heatmap_color": str(row["HEATMAP_COLOR"]),
            }
        )

    return {
        "limit": limit,
        "count": len(result),
        "critical_locations": result,
    }


