from fastapi import FastAPI
import sqlite3
import pandas as pd
import numpy as np

app = FastAPI()


@app.get("/")
def home():
    return {
        "message": "Warehouse API работает"
    }


@app.get("/analytics")
def analytics():

    conn = sqlite3.connect("warehouse.db")

    platz = pd.read_sql(
        """
        SELECT *
        FROM df_platz_ber03_schlg_rti3
        """,
        conn
    )

    conn.close()

    platz["MAX_LHM"] = pd.to_numeric(
        platz["MAX_LHM"],
        errors="coerce"
    )

    platz["IST_LHM"] = pd.to_numeric(
        platz["IST_LHM"],
        errors="coerce"
    )

    platz["UTILIZATION"] = np.where(
        platz["MAX_LHM"] > 0,
        (platz["IST_LHM"] / platz["MAX_LHM"]) * 100,
        0
    )

    return {
        "total_locations": int(len(platz)),
        "avg_utilization": float(
            round(platz["UTILIZATION"].mean(), 2)
        ),
        "max_utilization": float(
            round(platz["UTILIZATION"].max(), 2)
        ),
        "free_locations": int(
            (platz["IST_LHM"] == 0).sum()
        )
    }
@app.get("/heatmap")
def heatmap():

    heatmap = pd.read_csv("warehouse_heatmap.csv")

    return heatmap.head(500).to_dict(
        orient="records"
    )