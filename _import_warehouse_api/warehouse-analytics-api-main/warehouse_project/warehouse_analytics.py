import sqlite3
from pathlib import Path
import pandas as pd
import numpy as np

# repo-root/data/warehouse.db (verlässlich, egal wo das Script läuft)
DB_PATH = Path(__file__).resolve().parents[3] / "data" / "warehouse.db"

# connect database
conn = sqlite3.connect(DB_PATH)

# load platz table
platz = pd.read_sql(
    'SELECT * FROM "df_platz_ber03_schlg_rti3"',
    conn
)
fahrpos = pd.read_sql(
    'SELECT * FROM "df_fahrpos_6mon_ber03_schlg_rti3"',
    conn
)

# convert columns to numeric
platz["MAX_LHM"] = pd.to_numeric(
    platz["MAX_LHM"],
    errors="coerce"
)

platz["IST_LHM"] = pd.to_numeric(
    platz["IST_LHM"],
    errors="coerce"
)

# calculate utilization
platz["UTILIZATION"] = np.where(
    platz["MAX_LHM"] > 0,
    (platz["IST_LHM"] / platz["MAX_LHM"]) * 100,
    np.nan
)

# show results
print("\nSTORAGE UTILIZATION\n")

print(
    platz[
        [
            "PLATZ_ID",
            "REGAL",
            "FACH",
            "EBENE",
            "MAX_LHM",
            "IST_LHM",
            "UTILIZATION"
        ]
    ].head(20)
)

# basic statistics
print("\nUTILIZATION STATISTICS\n")

print(
    platz["UTILIZATION"].describe()
)

# overloaded zones
print("\nOVERLOADED ZONES\n")

overloaded = platz[
    platz["UTILIZATION"] > 100
]

print(
    overloaded[
        [
            "PLATZ_ID",
            "REGAL",
            "FACH",
            "EBENE",
            "UTILIZATION"
        ]
    ].head(20)
)

# close connection
conn.close()
# free capacity analysis

platz["FREE_CAPACITY"] = (
    platz["MAX_LHM"] - platz["IST_LHM"]
)

print("\nFREE CAPACITY ANALYSIS\n")

print(
    platz[
        [
            "PLATZ_ID",
            "REGAL",
            "FACH",
            "EBENE",
            "MAX_LHM",
            "IST_LHM",
            "FREE_CAPACITY"
        ]
    ]
    .sort_values(
        by="FREE_CAPACITY",
        ascending=False
    )
    .head(20)
)
# bottleneck detection
platz["PLATZ_ID"] = platz["PLATZ_ID"].astype(str)
fahrpos["Q_PLATZ"] = fahrpos["Q_PLATZ"].astype(str)
pick_frequency = (
    fahrpos.groupby("Q_PLATZ")
    .size()
    .reset_index(name="PICK_COUNT")
)

bottlenecks = platz.merge(
    pick_frequency,
    left_on="PLATZ_ID",
    right_on="Q_PLATZ",
    how="left"
)

bottlenecks["PICK_COUNT"] = (
    bottlenecks["PICK_COUNT"]
    .fillna(0)
)

print("\nBOTTLENECK ANALYSIS\n")

print(
    bottlenecks[
        [
            "PLATZ_ID",
            "REGAL",
            "FACH",
            "EBENE",
            "UTILIZATION",
            "PICK_COUNT"
        ]
    ]
    .sort_values(
        by=["PICK_COUNT", "UTILIZATION"],
        ascending=False
    )
    .head(20)
)
# smart relocation recommendations

recommendations = platz[
    (platz["UTILIZATION"] > 100)
]

free_places = platz[
    platz["FREE_CAPACITY"] > 0
]

print("\nSMART RECOMMENDATIONS\n")

for index, overloaded in recommendations.head(10).iterrows():

    target = free_places.sample(1).iloc[0]

    print(
        f"""
MOVE STOCK:

FROM:
REGAL {overloaded['REGAL']}
FACH {overloaded['FACH']}
EBENE {overloaded['EBENE']}

TO:
REGAL {target['REGAL']}
FACH {target['FACH']}
EBENE {target['EBENE']}

FREE CAPACITY: {target['FREE_CAPACITY']}
----------------------------------------
"""
    )
# picking efficiency analysis

pick_frequency = (
    fahrpos.groupby("Q_PLATZ")
    .size()
    .reset_index(name="PICK_COUNT")
)

pick_frequency.columns = ["PLATZ_ID", "PICK_COUNT"]

pick_frequency["PLATZ_ID"] = (
    pick_frequency["PLATZ_ID"]
    .astype(str)
)

platz["PLATZ_ID"] = (
    platz["PLATZ_ID"]
    .astype(str)
)

picking_analysis = platz.merge(
    pick_frequency,
    on="PLATZ_ID",
    how="left"
)

picking_analysis["PICK_COUNT"] = (
    picking_analysis["PICK_COUNT"]
    .fillna(0)
)

print("\nPICKING EFFICIENCY ANALYSIS\n")

print(
    picking_analysis[
        [
            "PLATZ_ID",
            "REGAL",
            "FACH",
            "EBENE",
            "PICK_COUNT"
        ]
    ]
    .sort_values(
        by="PICK_COUNT",
        ascending=False
    )
    .head(20)
)
# storage optimization score

picking_analysis["OPTIMIZATION_SCORE"] = (
    (100 - picking_analysis["UTILIZATION"].fillna(0))
    +
    picking_analysis["PICK_COUNT"]
)

print("\nSTORAGE OPTIMIZATION SCORE\n")

print(
    picking_analysis[
        [
            "PLATZ_ID",
            "REGAL",
            "FACH",
            "EBENE",
            "UTILIZATION",
            "PICK_COUNT",
            "OPTIMIZATION_SCORE"
        ]
    ]
    .sort_values(
        by="OPTIMIZATION_SCORE",
        ascending=False
    )
    .head(20)
)
print("\nABC ANALYSIS\n")

# top-Artikel je Platz (aus tpa, da dort ARTBEZ1 steht)
conn = sqlite3.connect(DB_PATH)
tpa = pd.read_sql(
    'SELECT Q_PLATZ, ARTIKELNR, ARTBEZ1 FROM "df_tpa_6mon_ber03_schlg_rti3"',
    conn
)
conn.close()

tpa["Q_PLATZ"] = tpa["Q_PLATZ"].astype(str)

top_article = (
    tpa.groupby(["Q_PLATZ", "ARTIKELNR", "ARTBEZ1"])
    .size()
    .reset_index(name="PICKS_AUF_ARTIKEL")
    .sort_values(["Q_PLATZ", "PICKS_AUF_ARTIKEL"], ascending=[True, False])
    .drop_duplicates(subset="Q_PLATZ", keep="first")
    .rename(columns={"Q_PLATZ": "PLATZ_ID"})
    [["PLATZ_ID", "ARTIKELNR", "ARTBEZ1"]]
)

abc = platz.copy()
abc["ANZ_PICKS"] = pd.to_numeric(abc["ANZ_PICKS"], errors="coerce").fillna(0)

abc = abc.sort_values(by="ANZ_PICKS", ascending=False)

total_picks = abc["ANZ_PICKS"].sum()

abc["CUMULATIVE_%"] = (
    abc["ANZ_PICKS"].cumsum() / total_picks * 100
    if total_picks > 0 else 0
)

abc["ABC_CALC"] = np.where(
    abc["CUMULATIVE_%"] <= 80,
    "A",
    np.where(abc["CUMULATIVE_%"] <= 95, "B", "C")
)

abc = abc.merge(top_article, on="PLATZ_ID", how="left")

abc_table = abc[
    [
        "PLATZ_ID",
        "HAUSNR",     # Halle
        "REGAL",
        "FACH",
        "EBENE",
        "ANZ_PICKS",
        "CUMULATIVE_%",
        "ABC_CALC",
        "ABC_KLASSE",
        "ARTIKELNR",
        "ARTBEZ1",
    ]
].rename(columns={"HAUSNR": "HALLE"})

print(abc_table.head(30))

abc_table.to_csv("abc_analysis.csv", index=False)
print("\nGespeichert: abc_analysis.csv")