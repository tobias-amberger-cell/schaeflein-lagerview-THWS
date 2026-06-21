# Schäflein LagerView

Datengetriebene **Lager-Analyse** für das Lager **BER03** der Schäflein-Gruppe –
entwickelt als Hochschulprojekt an der THWS.

Die Anwendung wertet **echte Lagerdaten** (Stellplätze, Paletten, Pick-Bewegungen,
Aufträge) aus und liefert daraus **Kennzahlen und konkrete Handlungsempfehlungen**
fürs Lagermanagement.

> **Kurz erklärt:** Statt nur Zahlen anzuzeigen, sagt die App, *was zu tun ist* –
> welche Plätze umzulagern, nachzufüllen, ein- oder auszulagern sind und welche
> ABC-Klasse nicht zur tatsächlichen Pickfrequenz passt. Alles datenbasiert aus
> den realen Bewegungen.

---

## Aktueller Fokus

- **Aktiv weiterentwickelt:** das **Streamlit-Dashboard** (`backend/streamlit_app.py`).
- **Erhalten, aber sekundär:** die **Flutter-Web-App** + **FastAPI** (Deployment auf
  Render). Bleibt lauffähig und wird nicht gelöscht, steht aber nicht mehr im
  Mittelpunkt.

---

## Architektur (3 Bausteine)

1. **Datenbasis** – eine SQLite-Datenbank `warehouse.db` (~22.500 Stellplätze,
   ~6 Monate Bewegungen). Wegen der Größe (~300 MB) **nicht im Repo**, sondern als
   **GitHub-Release** (`db-v1`); wird zur Laufzeit geladen.
2. **API (FastAPI, `backend/app/main.py`)** – liest die DB und liefert ausgewertete
   Kennzahlen als JSON. Versorgt die Flutter-App. Stellt auch das 3D-Modell
   CORS-fähig unter `/model.glb` bereit.
3. **Oberflächen**
   - **Streamlit-Dashboard** *(primär)* – tiefe Analyse + Steuermaßnahmen.
   - **Flutter-Web-App** *(sekundär)* – Dashboard mit KPIs, ABC, 3D-Modell.

---

## Streamlit-Dashboard – Funktionen

Zweisprachig **DE/EN** (Umschalter in der Sidebar), Schäflein-Logo, globale Filter
(Halle, ABC, Auslastung, Regal/Ebene/Picks, Sperr-Status). Jeder Tab hat
Erklärtext, Tabellen/Diagramme und **CSV-Export**.

| Tab | Inhalt |
|-----|--------|
| **Hallen** | Belegung, Ø Auslastung, ABC-Verteilung je Halle |
| **Auslastungs-Heatmap** | Auslastung je Regal/Ebene + auslastungsstärkste Regale |
| **Pick-Heatmap** | Bewegungen je Wochentag/Stunde |
| **Bottlenecks** | Engpässe (hohe Pickfrequenz + hohe Auslastung) |
| **Free Capacity** | Plätze mit Restkapazität, je Halle |
| **🔄 Umlagern** | Premium ungenutzt · heiße C-Plätze · A auf hoher Ebene |
| **⬆️ Nachschub** | Dringend · überfällig · mittlere Frequenz |
| **📥 Einlagern** | Fast-Lane · Reserve · gesperrt |
| **📤 Auslagern** | Kritisch · abgestanden · beobachten |
| **ABC-Analyse** | nach Plätzen *oder* Artikeln, einstellbare Schwellen, Pareto-Kurve, Stamm-vs-berechnet + **Anpassungs-Empfehlung** |
| **Durchsatz** | Bewegungen/Tag, „letzte N Tage" *oder* Datumsbereich |
| **Top-Artikel** | meistbewegte Artikel |
| **🔎 Artikel** | Detail je Artikel: Bewegungen über Zeit + Picks je Quellplatz |
| **3D-Modell** | GLB-Warehouse-Viewer + Tabelle „ABC je Lagerplatz" |

---

## Lokal starten

### Streamlit (Hauptanwendung)

```powershell
cd C:\Users\tobia\ssi_lagerview
backend\.venv\Scripts\Activate.ps1   # venv mit Abhängigkeiten
streamlit run backend/streamlit_app.py
```

Die DB wird automatisch gefunden, wenn `data/warehouse.db` lokal liegt. Sonst per
Umgebungsvariable `WAREHOUSE_DB_URL` (GitHub-Release-Link) laden lassen.

### FastAPI + Flutter (sekundär)

```powershell
# API
python -m uvicorn backend.app.main:app --reload --port 8000
# Flutter-Web (separates Terminal)
flutter run -d chrome --dart-define=API_BASE_URL=http://localhost:8000
```

---

## Neue CSV-Daten laden

Einfachster Weg: CSVs in `data/incoming/` legen, dann:

```powershell
python backend/ingest.py                              # liest aus data/incoming/
# oder mit explizitem Pfad:
python backend/ingest.py C:\Pfad\zu\den\CSVs\

# Integritaet pruefen (Schluessellaengen, Join-Rate, Auslastung):
pytest backend/test_golden.py
```

Danach `streamlit run backend/streamlit_app.py` – die App liest `data/warehouse.db`.

---

## Deployment

- **Streamlit Cloud** (kostenlos): Main file `backend/streamlit_app.py`, Branch
  `main`. **DB-Zugriff** über App-Secret:
  ```toml
  db_url = "https://github.com/tobias-amberger-cell/schaeflein-lagerview-THWS/releases/download/db-v1/warehouse.db"
  ```
- **Render** (kostenlos) für API + Flutter-Web: siehe **[RENDER_DEPLOY.md](RENDER_DEPLOY.md)**.
  DB und 3D-Modell liegen als GitHub-Releases (`db-v1`, `model-v1`) und werden zur
  Laufzeit geladen.

---

## Daten (wichtigste Tabellen in `warehouse.db`)

| Tabelle | Inhalt |
|---------|--------|
| `df_platz_…` | Stellplätze (Regal/Fach/Ebene, ABC, Picks, Belegung, Sperre) |
| `df_palette_…` | Paletten |
| `df_tpa_…` | Pick-/Lagerbewegungen (Artikel, Quell-/Zielplatz, Datum/Zeit) |
| `df_order_…` | Aufträge |

ABC-Logik: kumulativer Anteil der Picks/Bewegungen – A bis ~80 %, B bis ~95 %,
Rest C (Schwellen im Dashboard einstellbar).

---

## Präsentations-Spickzettel

1. **Problem:** Lagerdaten sind da, aber niemand sieht auf einen Blick, *wo*
   etwas im Argen liegt und *was* zu tun ist.
2. **Lösung:** ein Dashboard, das aus den realen Bewegungen Kennzahlen **und**
   Maßnahmen ableitet (Umlagern/Nachschub/Einlagern/Auslagern).
3. **Demo-Reihenfolge:**
   Hallen-Überblick → Auslastungs-Heatmap (wo ist es eng?) →
   Pick-Heatmap (wann ist viel los?) → **Steuermaßnahmen** (konkrete To-dos) →
   **ABC-Analyse** (Pareto, Stamm vs. berechnet, Anpassungs-Empfehlung) →
   **Artikel-Detail** (Einzelartikel verfolgen) → 3D-Modell.
4. **Technik in einem Satz:** SQLite-Daten → FastAPI/Streamlit → Auswertung mit
   pandas → Diagramme (Plotly) und Tabellen, zweisprachig, kostenlos gehostet.
5. **Datenschutz/Skalierung:** DB liegt extern (Release), Hosting kostenlos
   (Streamlit Cloud / Render Free), erweiterbar auf Postgres.

---

## Technologien

- **Streamlit**, **pandas**, **NumPy**, **Plotly** (Dashboard & Analyse)
- **FastAPI** + **Uvicorn** (API)
- **Flutter / Dart** (sekundäre Web-App)
- **SQLite** (Datenhaltung), **Git/GitHub** (inkl. Releases für große Dateien)
- **Docker** (Flutter-Web-Build), **Render** & **Streamlit Cloud** (Hosting)

---

## Repository-Struktur (Überblick)

| Pfad | Zweck | Status |
|------|-------|--------|
| `backend/streamlit_app.py` | Streamlit-Dashboard | **aktiv** |
| `backend/app/` | FastAPI-Backend | sekundär |
| `backend/warehouse_project/` | Zusatz-Analytik / Heatmap-CSV | sekundär |
| `lib/` | Flutter-Web-App | sekundär |
| `data/` | lokale Daten (DB nicht im Repo) | – |
| `RENDER_DEPLOY.md` | Render-Deployment-Anleitung | – |
