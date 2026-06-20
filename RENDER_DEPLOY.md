# Render Deployment (kostenlos, Team-Zugriff)

Diese Anleitung stellt die App fuer dein Team online bereit – komplett auf dem
**kostenlosen** Render-Plan.

## Wie "kostenlos" funktioniert

- Beide Services laufen auf `plan: free`.
- Free hat **keine Persistent Disk**. Die 303-MB-`warehouse.db` passt auch nicht
  ins GitHub-Repo (100-MB-Limit pro Datei).
- Loesung: Die DB liegt als **GitHub-Release-Asset** und wird vom Backend beim
  **ersten Zugriff** automatisch nach `/tmp/warehouse.db` heruntergeladen.
- Hinweis Free-Tier: Der Service schlaeft nach ~15 min Inaktivitaet ein. Beim
  Aufwachen (Cold Start) wird die DB neu geladen -> erste Anfrage dauert laenger.

## Was bereits vorbereitet ist

- `render.yaml` fuer 2 Free-Services:
  - `ssi-lagerview-api` (FastAPI, Python)
  - `ssi-lagerview-web` (Flutter Web via Docker)
- Backend laedt die DB bei Bedarf aus `WAREHOUSE_DB_URL` nach `WAREHOUSE_DB_PATH`.
- `/health` antwortet sofort `status: ok` (loest den Download NICHT aus), damit
  der Render-Deploy-Healthcheck nicht in ein Timeout laeuft.

## Schritt 1: DB als GitHub-Release hochladen

1. Auf GitHub ins Repo `tobias-amberger-cell/schaeflein-lagerview-THWS`.
2. Rechts auf **Releases** -> **Draft a new release**.
3. **Tag** exakt `db-v1` setzen (Target-Branch egal).
4. Unter **Attach binaries** die lokale `data/warehouse.db` hochladen
   (Dateiname muss `warehouse.db` bleiben).
5. **Publish release**.
6. Die Download-URL ist dann exakt:
   `https://github.com/tobias-amberger-cell/schaeflein-lagerview-THWS/releases/download/db-v1/warehouse.db`
   (genau diese URL steht schon in `render.yaml`).

> Anderer Tag/Name? Dann in `render.yaml` den Wert von `WAREHOUSE_DB_URL`
> entsprechend anpassen.

## Schritt 2: Blueprint in Render deployen

1. In Render oben rechts: **+ New** -> **Blueprint**.
2. Repo `tobias-amberger-cell/schaeflein-lagerview-THWS` waehlen.
3. Branch `chore-render-team-deploy` waehlen.
4. Render liest `render.yaml` und zeigt 2 Services -> **Apply / Create**.
5. Web-Service pruefen: `API_BASE_URL` muss auf die echte API-URL zeigen.
   Falls Render einen anderen Hostnamen vergibt, `API_BASE_URL` anpassen und
   den Web-Service neu deployen.

## Schritt 3: Verifikation

1. API-Health: `https://ssi-lagerview-api.onrender.com/health`
   - muss `status: ok` liefern.
   - `db_ready: false` direkt nach Deploy ist normal (DB noch nicht geladen).
2. Eine Datenanfrage ausloesen, z. B.
   `https://ssi-lagerview-api.onrender.com/warehouses`
   - Erster Aufruf laedt die DB (kann dauern), danach kommen die Lagerdaten.
3. Web-App: `https://ssi-lagerview-web.onrender.com` oeffnen und pruefen, ob
   Lagerdaten erscheinen.

## DB aktualisieren

- Neue `warehouse.db` als Asset an dasselbe Release `db-v1` haengen (altes Asset
  loeschen/ersetzen) – URL bleibt gleich. API-Service neu starten, damit beim
  naechsten Zugriff frisch geladen wird.

## Upgrade-Pfad (optional, falls Free zu langsam)

- `plan: free` -> `plan: starter` und eine Persistent Disk ergaenzen; dann liegt
  die DB dauerhaft auf der Disk (kein Cold-Start-Download mehr). Kostenpflichtig.
- Vollstaendige Migration auf Render Postgres ist ein separater Schritt
  (mehrere Abfragen sind aktuell SQLite-spezifisch).
