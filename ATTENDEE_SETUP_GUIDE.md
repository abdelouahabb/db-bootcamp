# Attendee Tooling & Day-0 Setup Guide (Windows, macOS & Linux)

> [!IMPORTANT]
> **100% Portable & Self-Contained Bootcamp Package**  
> Everything in this folder is designed to run locally on **Windows 10/11**, **macOS (Intel & Apple Silicon)**, and **Linux (Ubuntu/Debian/RHEL/Fedora)** with zero cloud account dependencies.  
> Follow this guide to understand **which tools to use for reading coursebooks, visualizing spatial/document data, and executing labs across Days 1–5**.

---

## Quick-Start Summary: Which Tool Do I Use for Each Task?

| Task During the Bootcamp | Recommended Primary Tool | Zero-Install / Browser Fallback |
| :--- | :--- | :--- |
| **Reading Coursebooks (`.md`), Reference Cards, Simulators & Quiz** | **Built-In Web Portal** (`python3 start_bootcamp.py` $\rightarrow$ `http://127.0.0.1:8088/bootcamp_portal.html`) | **VS Code** (`Ctrl+Shift+V` / `Cmd+Shift+V` Markdown + Mermaid Preview) |
| **Day 1: SQLite Operational & 250k Telemetry Labs** | **`sqlite3` CLI** + **DBeaver Community Edition** | Python `sqlite3` module (built into Python 3) |
| **Days 2 & 3: PostgreSQL 16 + PostGIS 3.4 Internals & Spatial Maps** | **DBeaver Community** *(Leaflet GIS Map Viewer + `Ctrl+Shift+E` Visual Explain)* + **`psql` CLI** | **Adminer Web SQL UI** (`http://localhost:8080`) + `docker exec -it` |
| **Day 4: MongoDB 7.0 BSON, Time-Series & `2dsphere` Storm Polygons** | **MongoDB Compass GUI** *(Interactive GeoJSON Map + Visual Aggregation Builder)* + **`mongosh` CLI** | `docker exec -it weather-mongo-node1 mongosh` |
| **Day 5: DuckDB, Apache Parquet, NetCDF4 & Polyglot Lakehouse** | **Python 3** + **DuckDB CLI / DBeaver** + **MinIO S3 Console** (`http://localhost:9001`) | Built-In Portal Multi-Engine Scaling Calculator & Architecture Explorer |

---

## 1. Reading Coursebooks, Diagrams & Interactive Simulators (2 Options)

All coursebooks (`day1/` through `day5/`) and the 13 Engineering Reference Cards (`reference_cards/`) are written in **GitHub-Flavored Markdown (`.md`)** with embedded **ASCII architecture diagrams**, **Mermaid flowcharts**, **LaTeX math formulas**, and **copyable SQL/MQL/Python code blocks**.

### Option A — Built-In Web Command Center & Reader (Zero Install, Recommended)

We include a zero-dependency launcher script (`start_bootcamp.py`) that starts a lightweight local HTTP server and opens the **Interactive Bootcamp Command Center (`bootcamp_portal.html`)** in your browser.

1. Open a terminal (`PowerShell`/`cmd` on Windows, `Terminal` on macOS/Linux) inside this bootcamp folder:
   ```bash
   # macOS / Linux:
   python3 start_bootcamp.py

   # Windows (PowerShell or Command Prompt):
   python start_bootcamp.py
   ```
2. Your browser will automatically open **`http://127.0.0.1:8088/bootcamp_portal.html`**.
3. **Built-In Document & Code Reader:** Clicking **any** `.md` coursebook, `.md` reference card, `.sql` script, `.js` MongoDB script, `.py` pipeline, or `.yml` Docker file inside the **Curriculum & File Explorer** tab opens it directly inside the portal's **Built-In Dark-Mode Reader Modal** — complete with formatted tables, callout boxes, line-numbered code views, and **1-click Copy buttons**!
4. **Interactive Simulators & Certification Quiz:** Use the top navigation tabs in `bootcamp_portal.html` to run:
   - **Lab 1: PostgreSQL Tuple Tetris & 8-Byte Alignment Visualizer** (drag-and-drop columns to eliminate CPU padding waste).
   - **Lab 2: `-9999.0` Hardware Sentinel & Three-Valued Logic (`3VL`) Simulator** (see live mean/std-dev corruption vs. `NULLIF` hygiene).
   - **Lab 3: Multi-Engine Workload & Storage Scaling Calculator** (`SQLite` vs. `PostgreSQL` vs. `MongoDB` vs. `DuckDB + Parquet`).
   - **Polyglot Architecture Explorer** & **15-Question Final Certification Quiz**.

---

### Option B — Visual Studio Code (IDE Workflow)

If you prefer working inside an IDE with an integrated terminal right below your reading pane:

1. Download and install **[Visual Studio Code](https://code.visualstudio.com/)** (Free for Windows, macOS, Linux).
2. Open Visual Studio Code and select **File $\rightarrow$ Open Folder...** to open this bootcamp directory.
3. **Open the Side-by-Side Markdown Preview:**
   - Click any `.md` file in the left Explorer sidebar (e.g., `day1/day1_master_coursebook.md`).
   - Press **`Ctrl+Shift+V`** (Windows/Linux) or **`Cmd+Shift+V`** (macOS) — or click the **"Open Preview to the Side"** icon in the top-right corner of the editor.
4. **Open the Integrated Terminal:**
   - Press **`Ctrl+\``** (Control + Backtick) or select **Terminal $\rightarrow$ New Terminal** to run `sqlite3`, `psql`, `mongosh`, `duckdb`, and `python3` commands right below the coursebook!
5. **Recommended Free VS Code Extensions** (Search in the Extensions sidebar `Ctrl+Shift+X`):
   - **Markdown Preview Mermaid Support** (`bierner.markdown-mermaid`) — Renders Mermaid state & sequence diagrams inside VS Code's Markdown preview.
   - **Markdown All in One** (`yzhang.markdown-all-in-one`) — Renders math formulas and table of contents navigation.
   - **SQLite Viewer** (`qwtel.sqlite-viewer`) — Quick 1-click inspection of `day1/weather_ops.db` and `day1/weather_telemetry.db`.
   - **MongoDB for VS Code** (`mongodb.mongodb-vscode`) — Connect directly to `mongodb://localhost:27017` and run playgrounds.

---

## 2. Database GUI Clients (Visual Maps, ER Diagrams & Explain Plans)

While every lab in this bootcamp can be executed 100% from the terminal CLI, meteorological data engineers rely on **two free visual GUI applications** to inspect PostGIS geodesic maps, `2dsphere` storm polygons, Entity-Relationship (ER) diagrams, and visual query execution plans.

*(For advanced GUI pro-tips, see [reference_cards/12_dbeaver_and_mongodb_compass_gui_workflows.md](./reference_cards/12_dbeaver_and_mongodb_compass_gui_workflows.md)).*

### A. DBeaver Community Edition (Days 1, 2, 3 & 5)
- **Download:** [https://dbeaver.io/download/](https://dbeaver.io/download/) *(Free & Open-Source — Windows, macOS, Linux)*
- **What You Use It For:**
  - **Day 1 (SQLite):** Open `./day1/weather_ops.db` and `./day1/weather_telemetry.db`, inspect ER diagrams, and test `PRAGMA foreign_keys = ON`.
  - **Days 2 & 3 (PostgreSQL 16 + PostGIS 3.4):**
    - **Visual Spatial Map Viewer:** Click any `GEOGRAPHY(Point, 4326)` column or `ST_Buffer` / `ST_DWithin` query result to plot WMO weather stations and storm radii directly on an interactive **OpenStreetMap / Leaflet GIS panel** inside DBeaver!
    - **Visual Execution Plan (`Ctrl+Shift+E`):** Highlight any slow query and press `Ctrl+Shift+E` (`Cmd+Shift+E` on Mac) to visualize `Seq Scan` vs. `Bitmap Heap Scan` vs. `Partition Pruning` cost trees.
  - **Day 5 (DuckDB & Parquet):** Connect DBeaver's DuckDB driver to `:memory:` or `./day5/weather.duckdb` to query `SELECT * FROM read_parquet('day5/lakehouse_parquet/**/*.parquet')` visually.

#### Exact DBeaver Connection Parameters

| Bootcamp Day | Engine Driver | Host / File Path | Port | Database | Username | Password |
| :--- | :--- | :--- | :---: | :--- | :--- | :--- |
| **Day 1** | **SQLite** | Browse to `./day1/weather_ops.db` or `./day1/weather_telemetry.db` | *N/A* | *N/A* | *N/A* | *N/A* |
| **Days 2 & 3** *(HA Stack)* | **PostgreSQL** | `localhost` | `5432` | `weather_ops` | `postgres` | `meteo_password` |
| **Day 5** *(Polyglot Stack)* | **PostgreSQL** | `localhost` | `5432` | `weather_ops_db` | `postgres` | `postgres` |
| **Day 5** *(Lakehouse)* | **DuckDB** | Enter `:memory:` *(or `./day5/weather.duckdb`)* | *N/A* | *N/A* | *N/A* | *N/A* |

---

### B. MongoDB Compass (Day 4 & Day 5)
- **Download:** [https://www.mongodb.com/try/download/compass](https://www.mongodb.com/try/download/compass) *(Free GUI Edition — Windows, macOS, Linux)*
- **Connection URI:**
  ```text
  mongodb://localhost:27017
  ```
- **What You Use It For on Day 4:**
  - **Schema Tab & GeoJSON Maps:** Click the **Schema** tab on `weather_nosql.stations` or `weather_nosql.storm_polygons` and click **"Analyze Schema"** — Compass automatically renders an interactive **2dsphere Map** of your Algerian & Mediterranean weather stations and convective storm polygons!
  - **Visual Aggregation Pipeline Builder:** Build `$match` $\rightarrow$ `$unwind` $\rightarrow$ `$group` radiosonde and ultrasonic anemometer pipelines stage-by-stage with live 10-document previews at every step.
  - **Visual Explain Plan Tab:** Compare `COLLSCAN` (red warning) vs. `IXSCAN` (green checkmark) when testing the **ESR (`Equality -> Sort -> Range`)** indexing rule.

---

## 3. Running the Database Servers (Docker Compose vs. Native CLI)

### Option A — Turnkey Docker Compose Stacks (Recommended for All OS)

Installing PostgreSQL 16, PostGIS 3.4, a 3-node MongoDB 7.0 Replica Set, Mosquitto MQTT, Redpanda Kafka, and MinIO S3 natively across Windows, macOS, and Linux can take hours. Instead, use **[Docker Desktop](https://www.docker.com/products/docker-desktop/)** (Windows/macOS) or **Docker Engine + Compose v2** (Linux) to spin up the pre-tuned environments in **1 command**:

#### Stack 1: Days 2, 3 & 4 — PostgreSQL 16 / PostGIS 3.4 + 3-Node MongoDB 7.0 Replica Set (`rs_meteo`)
```bash
# Start PostgreSQL 16 + PostGIS 3.4 (Port 5432) and 3-Node MongoDB Replica Set (Ports 27017, 27018, 27019)
docker compose -f docker/docker-compose.ha-replicaset.yml up -d

# Open interactive PostgreSQL psql shell inside the container (Zero host psql install required!)
docker exec -it weather-pg-primary psql -U postgres -d weather_ops

# Execute a Day 2 or Day 3 SQL script mounted automatically at /workspace:
docker exec -it weather-pg-primary psql -U postgres -d weather_ops -f /workspace/day2/weather_ops_pg.sql

# Open interactive MongoDB mongosh shell inside Node 1:
docker exec -it weather-mongo-node1 mongosh
```

#### Stack 2: Day 5 — Enterprise Polyglot Streaming & Lakehouse Stack
```bash
# Stop Stack 1 first (so ports 5432 and 27017 are free), then launch Stack 2:
docker compose -f docker/docker-compose.ha-replicaset.yml down
docker compose -f docker/docker-compose.polyglot-lakehouse.yml up -d
```
Stack 2 also includes two built-in browser UIs:
- **Adminer Web SQL UI:** Open `http://localhost:8080` *(System: `PostgreSQL`, Server: `postgres`, Username: `postgres`, Password: `postgres`, Database: `weather_ops_db`)*.
- **MinIO S3 Object Storage Console:** Open `http://localhost:9001` *(Username: `minioadmin`, Password: `minioadmin123`)*.

*(See [docker/docker_lab_guide.md](./docker/docker_lab_guide.md) for the complete Docker & Chaos Engineering failover walkthrough).*

---

### Option B — Python Environment Setup (Days 1 & 5)

- **Day 1 (`day1/generate_weather_db.py`)** and **`start_bootcamp.py`** use **100% Python 3 Standard Library** (`sqlite3`, `http.server`, `math`, `random`) — **zero `pip install` needed!**
- **Day 5 Benchmarks & Polyglot Capstone (`day5/*.py`)** use `duckdb`, `pyarrow`, `pandas`, `numpy`, `netCDF4`, `psycopg`, `pymongo`, `paho-mqtt`, `fastapi`, and `uvicorn`. Install them inside a virtual environment:

```bash
# macOS / Linux:
python3 -m venv .venv
source .venv/bin/activate
pip install duckdb pyarrow pandas numpy netCDF4 "psycopg[binary]" pymongo paho-mqtt fastapi uvicorn

# Windows (PowerShell):
python -m venv .venv
.\.venv\Scripts\Activate.ps1
pip install duckdb pyarrow pandas numpy netCDF4 "psycopg[binary]" pymongo paho-mqtt fastapi uvicorn
```

---

## 4. Complete CLI & Tooling Reference Matrix

| Tool / Binary | Used On | Purpose | How to Run via Docker (Zero Local Install) or Native CLI |
| :--- | :---: | :--- | :--- |
| **`python3 start_bootcamp.py`** | **All Days** | Serves `bootcamp_portal.html` + Built-In Markdown/Code Reader on port `8088` | `python3 start_bootcamp.py` *(macOS/Linux)*<br>`python start_bootcamp.py` *(Windows)* |
| **`sqlite3`** | **Day 1** | Embedded single-file relational engine (`weather_ops.db`, `weather_telemetry.db`) | `sqlite3 -header -box day1/weather_ops.db`<br>*(Pre-installed on macOS/Linux; download `sqlite-tools` on Windows or open in DBeaver)* |
| **`psql`** | **Days 2–3** | Interactive PostgreSQL CLI (`\d+`, `\timing`, `EXPLAIN (ANALYZE, BUFFERS)`) | **Docker:** `docker exec -it weather-pg-primary psql -U postgres -d weather_ops`<br>**Native:** `psql -h localhost -U postgres -d weather_ops` |
| **`mongosh`** | **Day 4** | Interactive MongoDB JavaScript shell (`db.stations.find()`, `rs.status()`) | **Docker:** `docker exec -it weather-mongo-node1 mongosh`<br>**Native:** `mongosh "mongodb://localhost:27017/weather_nosql"` |
| **`duckdb`** | **Day 5** | In-process vectorized columnar OLAP engine over Apache Parquet & CSV | **Python:** `python3 -c "import duckdb; ..."`<br>**CLI:** `duckdb` *(or connect via DBeaver DuckDB driver)* |
| **`./verify_bootcamp.sh`** | **Day 0** | Runs 65+ automated integrity, SQLite, 250k telemetry, Python AST & Docker checks | `./verify_bootcamp.sh` *(Linux/macOS/WSL2/Git Bash)* |
