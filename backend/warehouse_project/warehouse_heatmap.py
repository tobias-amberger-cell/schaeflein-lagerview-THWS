from pathlib import Path
import sqlite3
import pandas as pd
import numpy as np


def _db_path() -> Path:
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


def heatmap_color(util):
    if util >= 80:
        return "RED"
    if util >= 40:
        return "YELLOW"
    return "GREEN"


platz["HEATMAP_COLOR"] = platz["UTILIZATION"].apply(heatmap_color)

heatmap = platz[["PLATZ_ID", "REGAL", "FACH", "EBENE", "UTILIZATION", "HEATMAP_COLOR"]]

heatmap.to_csv(_heatmap_csv_path(), index=False)

print("\nHEATMAP FILE CREATED\n")
print(heatmap.head(20))
