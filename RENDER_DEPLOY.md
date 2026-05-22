# Render Deployment (Team Access)

Diese Anleitung stellt die App fuer dein Team online bereit, ohne lokale Daten zu verlieren.

## Was bereits vorbereitet ist

- `render.yaml` fuer 2 Services:
  - `ssi-lagerview-api` (FastAPI, Python, mit Persistent Disk)
  - `ssi-lagerview-web` (Flutter Web via Docker)
- Backend liest DB jetzt auch aus `WAREHOUSE_DB_PATH` (Render-Disk-Pfad).
- Docker-Build nimmt `API_BASE_URL` als `--dart-define`.

## Wichtige Vorbedingung

- Render `Starter` (oder hoeher), weil Persistent Disk nicht auf Free Web Services verfuegbar ist.
- Deine `warehouse.db` liegt lokal als Backup vor (hast du schon).

## Deployment-Schritte

1. Repo nach GitHub pushen (inkl. `render.yaml` und Code-Aenderungen).
2. In Render: `New +` -> `Blueprint` -> Repo waehlen.
3. Blueprint erzeugt 2 Services.
4. API-Service pruefen:
   - Name: `ssi-lagerview-api`
   - Disk: `/opt/render/project/src/data` (2 GB)
5. Web-Service pruefen:
   - Name: `ssi-lagerview-web`
   - Env: `API_BASE_URL=https://ssi-lagerview-api.onrender.com`
   - Falls Render einen anderen Hostnamen vergibt: `API_BASE_URL` auf die echte API-URL setzen und Web-Service neu deployen.

## Datenbank auf Render-Disk legen

Die Datei muss auf der API-Disk unter exakt diesem Pfad liegen:

- `/opt/render/project/src/data/warehouse.db`

Optionen:

- Render Shell/SSH + Upload (SCP/SFTP) auf die Disk.
- Danach API-Service neu starten.

## Verifikation

1. API-Health aufrufen:
   - `https://ssi-lagerview-api.onrender.com/health`
2. Muss `status: ok` liefern und den DB-Pfad zeigen.
3. Dann Web-App aufrufen:
   - `https://ssi-lagerview-web.onrender.com`
4. In der App pruefen, ob Lagerdaten sichtbar sind.

## Rollback

- Lokales Backup unveraendert behalten.
- Wenn etwas schiefgeht:
  - API stoppen
  - alte `warehouse.db` wieder auf `/opt/render/project/src/data/warehouse.db` ersetzen
  - API neu starten

## Hinweis zu Postgres (Phase 2)

Aktuell ist das sichere Ziel: Team-Zugriff ohne Datenverlust.
Die vollstaendige Migration auf Render Postgres ist ein separater Schritt, weil mehrere SQL-Abfragen aktuell SQLite-spezifisch sind.
