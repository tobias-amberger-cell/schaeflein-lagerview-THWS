from pathlib import Path
import sqlite3
import pandas as pd


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


conn = sqlite3.connect(str(_db_path()))

tables = pd.read_sql(
    "SELECT name FROM sqlite_master WHERE type='table';",
    conn,
)

print(tables)
