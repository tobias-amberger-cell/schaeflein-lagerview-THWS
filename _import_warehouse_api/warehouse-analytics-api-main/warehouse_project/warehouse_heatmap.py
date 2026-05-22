import sqlite3
import pandas as pd
import numpy as np

conn = sqlite3.connect("warehouse.db")

platz = pd.read_sql(
    """
    SELECT *
    FROM df_platz_ber03_schlg_rti3
    """,
    conn
)

conn.close()

# convert numeric columns
platz["MAX_LHM"] = pd.to_numeric(
    platz["MAX_LHM"],
    errors="coerce"
)

platz["IST_LHM"] = pd.to_numeric(
    platz["IST_LHM"],
    errors="coerce"
)

# utilization
platz["UTILIZATION"] = np.where(
    platz["MAX_LHM"] > 0,
    (platz["IST_LHM"] / platz["MAX_LHM"]) * 100,
    0
)

# heatmap colors
def heatmap_color(util):

    if util >= 80:
        return "RED"

    elif util >= 40:
        return "YELLOW"

    else:
        return "GREEN"

platz["HEATMAP_COLOR"] = platz["UTILIZATION"].apply(
    heatmap_color
)

# export heatmap file
heatmap = platz[
    [
        "PLATZ_ID",
        "REGAL",
        "FACH",
        "EBENE",
        "UTILIZATION",
        "HEATMAP_COLOR"
    ]
]

heatmap.to_csv(
    "warehouse_heatmap.csv",
    index=False
)

print("\nHEATMAP FILE CREATED\n")

print(heatmap.head(20))