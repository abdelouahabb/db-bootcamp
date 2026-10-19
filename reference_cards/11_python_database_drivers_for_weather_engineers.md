# Python Database Drivers, PEP 249 (`DB-API 2.0`) Internals & Engine Integration Guide (`sqlite3` vs. `APSW`, `psycopg3`, `DuckDB`, `GeoPandas`, `PyMongo`)

**Target Audience:** Weather Forecast Engineers, Meteorological Data Engineers & Backend Python Architects  
**Bootcamp Context:** Deep-dive architectural guide to how Python communicates with database engines: **PEP 249 (`DB-API 2.0`)** internals, transaction state machines (`autocommit` vs. `isolation_level`), the **`with conn:` context manager trap**, standard library **`sqlite3` vs. `APSW`**, **`psycopg` v3** binary pipelines & server-side cursors, **DuckDB** zero-copy Apache Arrow bridges, and **PyMongo** replica-set driver topology.

---

> **Navigation:** [🏠 Bootcamp Home](../README.md) | [📚 Reference Cards Index](./README.md) | [🌐 Interactive Portal](../bootcamp_portal.html)  
> **Card Sequence:** [⬅️ Previous Card](./10_query_execution_plan_forensics_and_explain.md) | **Card 11 of 14** | [Next Card ➡️](./12_dbeaver_and_mongodb_compass_gui_workflows.md)

## 🧭 Quick-Jump Table of Contents

- [1. How Python Talks to Databases: PEP 249 (`DB-API 2.0`) Architecture](#1-how-python-talks-to-databases-pep-249-db-api-20-architecture)
  - [1.1 The Two-Tier Object Model: `Connection` vs. `Cursor`](#11-the-two-tier-object-model-connection-vs-cursor)
  - [1.2 The PEP 249 Exception Hierarchy (Catching the Right Error)](#12-the-pep-249-exception-hierarchy-catching-the-right-error)
  - [1.3 Parameter Binding (`paramstyle`) vs. The Python `f-string` Anti-Pattern](#13-parameter-binding-paramstyle-vs-the-python-f-string-anti-pattern)
  - [1.4 Why `PyObject` Boxing Is Slow (Row Tuples vs. Zero-Copy Arrow)](#14-why-pyobject-boxing-is-slow-row-tuples-vs-zero-copy-arrow)
- [2. The Transaction, `autocommit`, and `with` Statement Minefield](#2-the-transaction-autocommit-and-with-statement-minefield)
  - [2.1 Why PEP 249 Defaults to `autocommit = False` (Implicit `BEGIN`)](#21-why-pep-249-defaults-to-autocommit--false-implicit-begin)
  - [2.2 The Infamous `sqlite3` `isolation_level` Quirk vs. Python 3.12+ `autocommit`](#22-the-infamous-sqlite3-isolation_level-quirk-vs-python-312-autocommit)
  - [2.3 CRITICAL TRAP: What `with conn:` Actually Does in `sqlite3` vs. `psycopg3`!](#23-critical-trap-what-with-conn-actually-does-in-sqlite3-vs-psycopg3)
- [3. Day 1: Python SQLite Drivers — Standard Library `sqlite3` vs. `APSW`](#3-day-1-python-sqlite-drivers--standard-library-sqlite3-vs-apsw)
  - [3.1 Architectural Comparison: `sqlite3` (PEP 249) vs. `APSW` (1:1 C API Wrapper)](#31-architectural-comparison-sqlite3-pep-249-vs-apsw-11-c-api-wrapper)
  - [3.2 Production `sqlite3` Pattern: WAL Pragmas, `Row` Factory & `contextlib.closing`](#32-production-sqlite3-pattern-wal-pragmas-row-factory--contextlibclosing)
  - [3.3 Production `APSW` Pattern: `wal_hook`, Incremental BLOB I/O & Online Backup API](#33-production-apsw-pattern-wal_hook-incremental-blob-io--online-backup-api)
- [4. Days 1 & 5: Python + `DuckDB` (Zero-Copy Arrow & DataFrame Replacement Scans)](#4-days-1--5-python--duckdb-zero-copy-arrow--dataframe-replacement-scans)
  - [4.1 How DuckDB Queries In-Memory Pandas/Polars DataFrames Without Copying RAM](#41-how-duckdb-queries-in-memory-pandaspolars-dataframes-without-copying-ram)
  - [4.2 Multi-Thread Concurrency in DuckDB (`conn.cursor()`)](#42-multi-thread-concurrency-in-duckdb-conncursor)
- [5. Days 2 & 3: Python + PostgreSQL (`psycopg` v3 vs. Legacy `psycopg2`)](#5-days-2--3-python--postgresql-psycopg-v3-vs-legacy-psycopg2)
  - [5.1 Why `psycopg` v3 Replaces `psycopg2` (Server-Side Binding & Pipeline Mode)](#51-why-psycopg-v3-replaces-psycopg2-server-side-binding--pipeline-mode)
  - [5.2 Client-Side vs. Named Server-Side Cursors (Preventing 10M-Row `MemoryError`)](#52-client-side-vs-named-server-side-cursors-preventing-10m-row-memoryerror)
  - [5.3 High-Speed Ingestion: `executemany()` Pipeline vs. Binary `COPY`](#53-high-speed-ingestion-executemany-pipeline-vs-binary-copy)
  - [5.4 Loading `PostGIS` Spatial Data into `GeoPandas` (`read_postgis` & `ADBC`)](#54-loading-postgis-spatial-data-into-geopandas-read_postgis--adbc)
- [6. Days 4 & 5: Python + MongoDB (`PyMongo` Replica-Set Driver Internals)](#6-days-4--5-python--mongodb-pymongo-replica-set-driver-internals)
  - [6.1 How `MongoClient` Discovers Replica Sets & Routes Reads/Writes](#61-how-mongoclient-discovers-replica-sets--routes-readswrites)
  - [6.2 Production `PyMongo` Pattern: Unordered Bulk Upserts, `WriteConcern` & Aggregation Cursors](#62-production-pymongo-pattern-unordered-bulk-upserts-writeconcern--aggregation-cursors)
- [7. Cross-Driver Engineering Summary Matrix](#7-cross-driver-engineering-summary-matrix)

---

## 1. How Python Talks to Databases: PEP 249 (`DB-API 2.0`) Architecture

To prevent every relational database vendor from inventing incompatible Python methods, the Python community standardized **PEP 249 — Python Database API Specification v2.0** (`DB-API 2.0`). Standard library `sqlite3`, PostgreSQL `psycopg` (v2 and v3), `duckdb`, and MySQL `mysqlclient`/`PyMySQL` all implement PEP 249. *(Notably, `APSW` for SQLite and `PyMongo` for MongoDB deliberately do **not** follow PEP 249, for reasons explained in §3 and §6).*

```
┌────────────────────────────────────────────────────────────────────────────────────────┐
│                              Your Python Weather Application                           │
│     conn = driver.connect(...)   ───►   cur = conn.cursor()   ───►   cur.execute(...)  │
└───────────────────┬──────────────────────────────────────────────────────┬─────────────┘
                    │ PEP 249 (DB-API 2.0) C-Extension / Cython Layer      │
                    ▼                                                      ▼
┌───────────────────────────────────────────┐  ┌─────────────────────────────────────────┐
│    In-Process Embedded C Library          │  │    Client-Server Wire Protocol          │
│  • sqlite3 / APSW  ──► libsqlite3.so      │  │  • psycopg3 ──► libpq (TCP :5432)       │
│  • duckdb          ──► libduckdb.so       │  │  • PyMongo  ──► OP_MSG BSON (TCP :27017)│
│  (Zero network hop; direct disk/RAM I/O)  │  │  (Socket pool, TLS, auth, wire packets) │
└───────────────────────────────────────────┘  └─────────────────────────────────────────┘
```

### 1.1 The Two-Tier Object Model: `Connection` vs. `Cursor`

PEP 249 separates database interaction into two distinct objects:

| Object | What It Represents Physically | Primary Responsibilities & Methods | Thread-Safety Rule |
| :--- | :--- | :--- | :--- |
| **`Connection`** (`conn`) | A physical database session: an open OS file descriptor + page cache (`sqlite3`), or an authenticated TCP socket connected to a backend `postgres` process (`psycopg3`). | • **Transaction boundary control:** `conn.commit()`, `conn.rollback()`<br>• **Session lifecycle:** `conn.close()`<br>• **Spawning cursors:** `conn.cursor()`<br>• *(Shortcut in `sqlite3` & `psycopg3`)*: `conn.execute(...)` creates a cursor internally and returns it. | **Never share a single `Connection` across concurrent threads without synchronization** (use a `ConnectionPool` in PostgreSQL, or one connection per thread in SQLite WAL mode). |
| **`Cursor`** (`cur`) | A query execution context and result-set iterator bound to a `Connection`. | • **Executing SQL:** `cur.execute(sql, params)`, `cur.executemany(sql, seq_of_params)`<br>• **Fetching rows:** `cur.fetchone()`, `cur.fetchmany(size)`, `cur.fetchall()`, or `for row in cur:`<br>• **Metadata:** `cur.description` (column names/types), `cur.rowcount` (affected rows). | **Strictly single-threaded.** Always close cursors (`cur.close()` or `with conn.cursor() as cur:`) when finished iterating. |

> [!WARNING]
> **The `cur.fetchone()` / `cur.fetchall()` Exhaustion Rule:**  
> A `Cursor` is a **forward-only iterator** (stateful generator). Once you call `rows = cur.fetchall()` or iterate `for row in cur:`, the cursor is exhausted—calling `cur.fetchall()` a second time returns an empty list `[]`!

---

### 1.2 The PEP 249 Exception Hierarchy (Catching the Right Error)

Every PEP 249 driver (`sqlite3`, `psycopg`, `duckdb`) exposes the exact same standard exception tree so your error-handling code is structured identically across engines:

```
Exception
 └── StandardError / Warning
      └── Error (Base DB-API Error: sqlite3.Error / psycopg.Error)
           ├── InterfaceError      (Driver misuse: using a closed connection/cursor, wrong param count)
           └── DatabaseError       (Error raised by the database engine itself)
                ├── DataError          (Division by zero, numeric overflow, invalid timestamp string)
                ├── OperationalError   (Disk full, 'database is locked', lost TCP connection, deadlock)
                ├── IntegrityError     (PRIMARY KEY duplicate, FOREIGN KEY failure, NOT NULL / CHECK failed)
                ├── InternalError      (Corrupted B-Tree page, out-of-sync transaction state)
                ├── ProgrammingError   (SQL syntax error, table/column does not exist)
                └── NotSupportedError  (Feature not supported by engine/driver)
```

- **Production Rule for Weather Ingestion Daemons:**
  - Catch **`IntegrityError`** when a station packet violates a physical `CHECK` constraint (`humidity_pct = 145.0`) or `UNIQUE (station_id, obs_time)`—log the bad packet to a Dead-Letter Queue (DLQ) without crashing the daemon.
  - Catch **`OperationalError`** for transient lock/network failures (`database is locked`, PostgreSQL failover)—sleep with exponential backoff and retry the batch!

---

### 1.3 Parameter Binding (`paramstyle`) vs. The Python `f-string` Anti-Pattern

**Never** interpolate variables into SQL using Python `f-strings`, `.format()`, or `%`:

```python
# ❌ CATASTROPHIC ANTI-PATTERN (SQL Injection + Syntax Crash + Plan Cache Pollution):
station_name = "M'Sila"
cur.execute(f"SELECT * FROM stations WHERE station_name = '{station_name}';")
# Crashes immediately: near "Sila": syntax error (unbalanced single quote!)
```

When you pass parameters as a **separate second argument** (`cur.execute(sql, params)`), the driver never concatenates strings into the SQL text. Instead:
1. **The SQL structure is compiled first:** The database parses the SQL AST (`SELECT * FROM stations WHERE station_name = ?`) before looking at the parameter bytes. A quote or `; DROP TABLE stations;` inside `station_name` is treated strictly as literal data bytes—making SQL injection mathematically impossible.
2. **Prepared Statement Reuse:** Because the SQL string stays identical across 100,000 station pings, the engine can reuse the compiled bytecode (`sqlite3_stmt` in SQLite / Prepared Plan in `psycopg3`).

#### Cross-Driver Parameter Placeholder Styles (`paramstyle`)

| Driver | PEP 249 `paramstyle` | Positional Syntax (Tuple) | Named Syntax (Dict) | Single-Parameter Tuple Gotcha! |
| :--- | :---: | :--- | :--- | :--- |
| **`sqlite3` / `APSW`** | `qmark` & `named` | `WHERE id = ? AND temp > ?`<br>`(60390, 20.0)` | `WHERE id = :id AND temp > :t`<br>`{"id": 60390, "t": 20.0}` | Must include trailing comma for 1 item: **`(60390,)`** — writing `(60390)` passes an `int`, raising `ValueError: parameters are of unsupported type`! |
| **`duckdb`** | `qmark`, `numeric`, `named` | `WHERE id = ?` or `WHERE id = $1`<br>`(60390,)` | `WHERE id = $id`<br>`{"id": 60390}` | Same tuple rule: `(60390,)` or `[60390]`. |
| **`psycopg` (v2 & v3)** | `format` & `pyformat` | `WHERE id = %s AND temp > %s`<br>`(60390, 20.0)` | `WHERE id = %(id)s AND temp > %(t)s`<br>`{"id": 60390, "t": 20.0}` | Note: Even though `psycopg` uses `%s`, **do not use the Python `%` operator**! Pass `(60390, 20.0)` as the 2nd argument to `cur.execute(sql, params)`! |

---

### 1.4 Why `PyObject` Boxing Is Slow (Row Tuples vs. Zero-Copy Arrow)

When you run `cur.fetchall()` in a PEP 249 driver (`sqlite3` or `psycopg3`) over 1,000,000 rows of 8 columns:
- The C driver must allocate **1,000,000 Python `tuple` objects** and **8,000,000 individual boxed `PyFloatObject` / `PyUnicodeObject` structs** on the Python heap (each Python `float` takes **24 bytes** in CPython instead of 8 bytes!).
- **Rule of Thumb:**
  - Use `cur.fetchone()` / `cur.fetchall()` for **OLTP lookups and small result sets** ($< 50,000$ rows).
  - For **million-row analytical transfers** into Pandas, Polars, or Parquet, bypass PEP 249 tuple boxing entirely using **DuckDB `.arrow()` / `.pl()`** (§4) or PostgreSQL **`COPY ... TO STDOUT (FORMAT BINARY)` / `ADBC`** (§5.4).

---

## 2. The Transaction, `autocommit`, and `with` Statement Minefield

The #1 source of bugs when engineers move from interactive SQL shells (`sqlite3`, `psql`) to Python scripts is **how PEP 249 handles transactions and `with` blocks**.

### 2.1 Why PEP 249 Defaults to `autocommit = False` (Implicit `BEGIN`)

- **In the `sqlite3` or `psql` CLI terminal:** The shell runs in **autocommit mode** by default. Every `INSERT` or `UPDATE` you type is immediately committed to disk when it finishes, unless you explicitly type `BEGIN;`.
- **In Python PEP 249 (`sqlite3`, `psycopg2`, `psycopg3`):** The specification **forbids** autocommit by default (`autocommit = False`)!
  - The moment you execute a write statement, the Python driver implicitly opens a transaction (`BEGIN`).
  - **If your Python script finishes and exits without calling `conn.commit()`, the driver issues an implicit `ROLLBACK` on disconnect and every single row you inserted disappears!**

---

### 2.2 The Infamous `sqlite3` `isolation_level` Quirk vs. Python 3.12+ `autocommit`

In Python's standard library `sqlite3`, the default connection behavior (`sqlite3.connect("weather_ops.db")`) has a quirky historical implementation controlled by the `isolation_level` parameter:

| Mode | How to Configure | What Python's `_sqlite3` C Wrapper Actually Does | Pros & Pitfalls in Weather Telemetry |
| :--- | :--- | :--- | :--- |
| **1. Legacy Default Mode** | `sqlite3.connect("db")` *(where default `isolation_level = ""`)* | Python inspects the first word of every SQL string you pass to `execute()`. It **only** sends an implicit `BEGIN` before DML (`INSERT`, `UPDATE`, `DELETE`, `REPLACE`). Statements like `SELECT` or `PRAGMA` do not start a transaction! | ⚠️ **Pitfall:** Because Python automatically injects `BEGIN` before `INSERT`, if you try to run `conn.execute("BEGIN IMMEDIATE;")` yourself after a DML statement, SQLite throws `OperationalError: cannot start a transaction within a transaction`! Also, `PRAGMA` settings that cannot run inside a transaction behave unpredictably if mixed with uncommitted DML. |
| **2. Explicit Lock-Acquisition Mode** | `sqlite3.connect("db", isolation_level="IMMEDIATE")` *(or `"DEFERRED"` / `"EXCLUSIVE"`)* | Whenever Python implicitly starts a DML transaction, it issues `BEGIN IMMEDIATE` (acquiring the write lock immediately and honoring `PRAGMA busy_timeout`) instead of a deferred `BEGIN`. | ✅ Prevents the `SQLITE_BUSY_SNAPSHOT` read-to-write upgrade failure on concurrent writers! |
| **3. Native SQLite Autocommit / Manual Control** | `sqlite3.connect("db", isolation_level=None)` *(Python 3.x)*<br>**OR**<br>`sqlite3.connect("db", autocommit=True)` *(Python 3.12+)* | **Disables Python's magic SQL-string sniffing completely!** `libsqlite3` runs in its native C autocommit mode (just like the `sqlite3` CLI shell). Every statement auto-commits unless you explicitly execute `conn.execute("BEGIN IMMEDIATE;")` ... `conn.execute("COMMIT;")`. | ✅ **Preferred by Database Architects** who want 100% deterministic control over `BEGIN IMMEDIATE;`, `COMMIT;`, `ROLLBACK;`, and `PRAGMA` execution without Python secretly injecting `BEGIN` statements behind the scenes. |
| **4. Strict PEP 249 Mode (Python 3.12+)** | `sqlite3.connect("db", autocommit=False)` *(Python 3.12+, PEP 249 v2)* | Uses SQLite's native C `sqlite3_get_autocommit()` state machine instead of string-parsing SQL statements, keeping a transaction open at all times until `conn.commit()` or `conn.rollback()`. | ✅ Clean modern PEP 249 semantics on Python 3.12+. |

---

### 2.3 CRITICAL TRAP: What `with conn:` Actually Does in `sqlite3` vs. `psycopg3`!

> [!CAUTION]
> **The #1 Python `sqlite3` Bug — `with sqlite3.connect(...) as conn:` DOES NOT CLOSE THE CONNECTION!**  
> Most Python engineers assume `with sqlite3.connect("weather_ops.db") as conn:` works like `with open("file.txt") as f:` and closes the database file when exiting the `with` block. **It does NOT!**

Look at the exact implementation difference between `sqlite3` and `psycopg3`:

| Action Inside `with` Block | `sqlite3.connect("weather_ops.db")` (`with conn:`) | `psycopg.connect(PG_DSN)` (`psycopg` v3 `with conn:`) | `psycopg` v3 `with conn.transaction():` |
| :--- | :--- | :--- | :--- |
| **Block exits normally (no exception)** | Calls `conn.commit()` | Calls `conn.commit()` **AND `conn.close()`** | Calls `COMMIT` (or `RELEASE SAVEPOINT`) |
| **Exception raised inside block** | Calls `conn.rollback()` and re-raises exception | Calls `conn.rollback()` **AND `conn.close()`** | Calls `ROLLBACK` (or `ROLLBACK TO SAVEPOINT`) |
| **Is the database connection closed after the `with` block?** | ❌ **NO! Connection stays OPEN!** (Holds `.db-wal` / `.db-shm` file handles open until Python garbage collection runs!) | ✅ **YES! Socket is closed deterministically.** | Connection stays open (only the transaction block ends). |

#### How to Write Leak-Free `sqlite3` Context Managers (`contextlib.closing`)

In `sqlite3`, always combine **`contextlib.closing()`** (which guarantees `conn.close()` on exit) with **`with conn:`** (which guarantees `conn.commit()` on success or `conn.rollback()` on exception):

```python
import sqlite3
from contextlib import closing

# ❌ WRONG: Connection stays open after the 'with' block exits!
with sqlite3.connect("weather_ops.db") as conn:
    conn.execute("INSERT INTO stations VALUES (60602, 'In Salah', 27.25, 2.51, 269.0, 'Arid', 1);")
# Here, the transaction is committed, but `conn` is STILL OPEN!
# On Windows or in WAL mode, trying to delete/move weather_ops.db or checkpoint .db-wal may fail!

# ✅ CORRECT: Outer `closing()` guarantees conn.close(); inner `with conn:` guarantees commit/rollback!
with closing(sqlite3.connect("weather_ops.db", timeout=5.0)) as conn:
    conn.execute("PRAGMA foreign_keys = ON;")
    with conn:  # <-- Transaction context manager: auto-commits on exit, auto-rollbacks on exception!
        conn.execute(
            "INSERT OR IGNORE INTO stations VALUES (?, ?, ?, ?, ?, ?, ?);",
            (60602, "In Salah", 27.25, 2.51, 269.0, "Arid", 1),
        )
# Here, the transaction is committed AND the file descriptor is 100% closed!
```

---

## 3. Day 1: Python SQLite Drivers — Standard Library `sqlite3` vs. `APSW`

Python has **two** mature C-extension drivers for SQLite:
1. **`sqlite3` (Standard Library `_sqlite3`):** Written originally by Gerhard Häring (`pysqlite`), bundled inside Python's standard library since Python 2.5. Designed to make SQLite look like a generic **PEP 249 (`DB-API 2.0`)** relational database.
2. **`APSW` (Another Python SQLite Wrapper, `pip install apsw`):** Written by Roger Binns and maintained in lockstep with every upstream SQLite release. Designed from the ground up to provide **100% access to the native SQLite C API (`libsqlite3`)** with zero DB-API translation overhead.

### 3.1 Architectural Comparison: `sqlite3` (PEP 249) vs. `APSW` (1:1 C API Wrapper)

| Architectural Dimension | Standard Library `sqlite3` (`import sqlite3`) | `APSW` — Another Python SQLite Wrapper (`import apsw`) |
| :--- | :--- | :--- |
| **Installation & Footprint** | **Built into Python standard library** (zero external dependencies; ideal for air-gapped VMs & portable scripts). | External C-extension wheel (`pip install apsw`); bundles the latest upstream SQLite amalgamation (often newer than the OS `libsqlite3.so`!). |
| **API Standard** | **PEP 249 (`DB-API 2.0`)** compliant (`conn.commit()`, `cur.fetchall()`, `isolation_level`). | **Deliberately NOT PEP 249!** Mirrors the exact C `sqlite3_*` semantics (`cursor.execute()` is a direct generator; no hidden `BEGIN` injection). |
| **Transaction Behavior** | Intercepts DML strings to inject `BEGIN` (`isolation_level=""`) unless `isolation_level=None` or `autocommit=True` is set. | **100% Native SQLite:** Starts in autocommit mode (just like the `sqlite3` CLI). Use `with conn:` in APSW for clean, nestable `BEGIN` / `SAVEPOINT` transactions! |
| **`with conn:` Context Manager** | Commits or rolls back top-level transaction only (**cannot** nest `with conn:` blocks in `sqlite3`!). | **Supports arbitrarily nested `with conn:` blocks!** Outer `with conn:` issues `BEGIN`/`COMMIT`; inner `with conn:` blocks automatically use SQLite **`SAVEPOINT`**s! |
| **Multi-Statement Strings in `execute()`** | ❌ `cur.execute("SELECT 1; SELECT 2;")` raises `ProgrammingError: You can only execute one statement at a time` (requires `executescript()`). | ✅ **`cur.execute("PRAGMA foreign_keys=ON; INSERT ...; SELECT ...;")` natively executes multiple semicolon-separated statements** with parameter bindings and yields rows from all of them! |
| **Prepared Statement Caching** | Caches compiled `sqlite3_stmt` handles per connection (default `cached_statements=128`). | Transparent high-speed statement cache with explicit `apsw.ext.query_info()` bytecode/index inspection. |
| **Incremental BLOB Streaming (`sqlite3_blob_open`)** | *(Added basic `conn.blobopen()` in Python 3.11+)* | Full native **`conn.blob_open(db, table, col, rowid, writeable)`** streaming I/O for reading/writing multi-MB binary radar tiles without loading into RAM. |
| **Custom WAL Checkpoint Hook (`sqlite3_wal_hook`)** | ❌ Not exposed. | ✅ **`conn.set_wal_hook(callable)`**: Python callback invoked after every commit with the exact count of pages currently in `.db-wal`! |
| **Virtual Tables & Custom VFS (`sqlite3_vfs`)** | ❌ Not exposed. | ✅ Full Python **Virtual Table (`VTModule`)** and **Custom VFS (`apsw.VFS`)** support (e.g., querying raw WMO BUFR/CSV directories as SQL tables or encrypting page I/O). |
| **Execution Speed (Micro-queries & Iteration)** | Baseline ($1\times$) | **$\approx 2\text{--}3.5\times$ faster** on high-frequency cursor loops due to zero DB-API layer overhead. |

#### When to Choose `sqlite3` vs. `APSW` in Meteorological Engineering
- **Use Standard Library `sqlite3` when:** You want zero `pip` dependencies (like our [`day1/generate_weather_db.py`](../day1/generate_weather_db.py)), you are passing the connection to `pandas.read_sql_query()` or `SQLAlchemy`, or you are writing standard SQL scripts.
- **Use `APSW` when:** You are building a high-frequency **edge weather station data logger**, need a newer SQLite engine than the host OS provides, need **nestable `with conn:` savepoints**, need **`set_wal_hook()`** to schedule custom WAL checkpoints between 20Hz ultrasonic sensor bursts, or want to expose raw binary telemetry files as SQLite Virtual Tables.

---

### 3.2 Production `sqlite3` Pattern: WAL Pragmas, `Row` Factory & `contextlib.closing`

By default, `sqlite3` returns rows as plain positional tuples `(60390, 'Algiers', 25.0)`, forcing you to write fragile index numbers like `row[2]`. Setting **`conn.row_factory = sqlite3.Row`** returns lightweight C-backed row objects that support **both** dictionary-style column-name lookup (`row["temp_c"]`) and positional lookup (`row[2]`) with near-zero memory overhead!

```python
import sqlite3
from contextlib import closing, contextmanager
from typing import Iterator
import pandas as pd

@contextmanager
def get_weather_sqlite_conn(db_path: str) -> Iterator[sqlite3.Connection]:
    """
    Production SQLite connection factory:
    1. Guarantees conn.close() on exit via contextlib.closing
    2. Uses isolation_level=None (native SQLite mode; no magic BEGIN injection)
    3. Configures WAL, NORMAL fsync, 5s busy_timeout, 64MiB journal cap, and foreign_keys
    4. Enables sqlite3.Row for dict-like column access (row['temp_c'])
    """
    with closing(sqlite3.connect(db_path, timeout=5.0, isolation_level=None)) as conn:
        conn.row_factory = sqlite3.Row
        conn.execute("PRAGMA foreign_keys = ON;")            # Enforce FK & ON DELETE CASCADE
        conn.execute("PRAGMA journal_mode = WAL;")           # Persistent: concurrent readers + 1 writer
        conn.execute("PRAGMA synchronous = NORMAL;")         # 100% corruption-safe in WAL mode
        conn.execute("PRAGMA busy_timeout = 5000;")          # Sleep/retry up to 5s on SQLITE_BUSY
        conn.execute("PRAGMA journal_size_limit = 67108864;")# Cap .db-wal at 64 MiB after rewind
        conn.execute("PRAGMA cache_size = -64000;")          # 64 MiB RAM page cache
        conn.execute("PRAGMA temp_store = MEMORY;")          # Keep sort/window temp B-Trees in RAM
        try:
            yield conn
        finally:
            # Refresh sqlite_stat1 planner statistics if table row counts shifted
            conn.execute("PRAGMA optimize;")


# Usage Example: Safe Read + Concurrent Write with BEGIN IMMEDIATE
with get_weather_sqlite_conn("weather_ops.db") as conn:
    # 1. Read Query using sqlite3.Row (access columns by name!)
    with closing(conn.cursor()) as cur:
        cur.execute(
            """
            SELECT station_id, obs_time, temp_c, wind_speed_kt
            FROM observations
            WHERE station_id = :sid AND qc_flag = :flag
            ORDER BY obs_time DESC
            LIMIT 5;
            """,
            {"sid": 60390, "flag": "VALID"},
        )
        for row in cur:
            print(f"Station {row['station_id']} @ {row['obs_time']}: {row['temp_c']}°C")

    # 2. Concurrent Write Transaction: Explicit BEGIN IMMEDIATE honors busy_timeout!
    try:
        conn.execute("BEGIN IMMEDIATE;")
        conn.executemany(
            """
            INSERT OR IGNORE INTO observations (station_id, obs_time, temp_c, qc_flag)
            VALUES (?, ?, ?, ?);
            """,
            [
                (60390, "2026-10-06 18:00:00", 22.4, "VALID"),
                (60419, "2026-10-06 18:00:00", 16.8, "VALID"),
            ],
        )
        conn.execute("COMMIT;")
    except sqlite3.Error:
        conn.execute("ROLLBACK;")
        raise
```

---

### 3.3 Production `APSW` Pattern: `wal_hook`, Incremental BLOB I/O & Online Backup API

If `apsw` is installed (`pip install apsw`), notice how much cleaner multi-statement pragmas, nested `with conn:` savepoints, and WAL checkpoint hooks become:

```python
import apsw
import apsw.bestpractice

# Apply APSW's built-in production best practices (WAL, NORMAL sync, busy_timeout, foreign_keys, temp_store=MEMORY)
apsw.bestpractice.apply(apsw.bestpractice.recommended)

conn = apsw.Connection("weather_ops.db")

# 1. Custom WAL Hook: Monitor .db-wal frame count after every commit!
def telemetry_wal_monitor(db_conn: apsw.Connection, db_name: str, num_pages_in_wal: int) -> int:
    if num_pages_in_wal > 2500:  # > 10 MB at 4 KB pages
        print(f"[WAL Monitor] {db_name} WAL reached {num_pages_in_wal} pages")
    return apsw.SQLITE_OK

conn.set_wal_hook(telemetry_wal_monitor)

# 2. Nestable `with conn:` Transactions (Outer = BEGIN IMMEDIATE, Inner = SAVEPOINT!)
with conn:  # Issues BEGIN
    conn.execute(
        "INSERT OR IGNORE INTO stations VALUES (?, ?, ?, ?, ?, ?, ?);",
        (60602, "In Salah", 27.25, 2.51, 269.0, "Arid", 1),
    )
    try:
        with conn:  # Automatically issues SAVEPOINT!
            # Violates CHECK (humidity_pct <= 100.0):
            conn.execute(
                "INSERT INTO observations (station_id, obs_time, humidity_pct) VALUES (?, ?, ?);",
                (60602, "2026-10-06 19:00:00", 145.0),
            )
    except apsw.ConstraintError as exc:
        # Inner SAVEPOINT rolled back cleanly; outer station 60602 insert is preserved!
        print(f"Caught sensor spike in savepoint: {exc}")

# 3. Online Hot Backup API (Copies live WAL database page-by-page without blocking writers!)
dest_conn = apsw.Connection("weather_ops_hot_backup.db")
with dest_conn.backup("main", conn, "main") as backup:
    while not backup.done:
        backup.step(100)  # Copy 100 pages (400 KB) per step, yielding locks between steps
dest_conn.close()
conn.close()
```

---

## 4. Days 1 & 5: Python + `DuckDB` (Zero-Copy Arrow & DataFrame Replacement Scans)

While `sqlite3` is a row-oriented OLTP library, **`duckdb`** (`pip install duckdb pyarrow polars`) is an in-process **vectorized columnar OLAP engine** (covered in [Reference Card 02](./02_duckdb_vectorized_olap_vs_sqlite.md) and [Day 5 Part 1](../day5/day5_part1_olap_duckdb_parquet_and_gridded_data_coursebook.md)).

### 4.1 How DuckDB Queries In-Memory Pandas/Polars DataFrames Without Copying RAM

When you execute a SQL query in `duckdb.sql(...)` and reference a table name that does not exist inside DuckDB's catalog (such as `station_df` below), DuckDB triggers a **Python Replacement Scan**:
1. It inspects your current Python stack frame's local and global variables (`locals()` / `globals()`) for a Pandas DataFrame, Polars DataFrame, or PyArrow Table named `station_df`.
2. Using the **Apache Arrow C Data Interface**, DuckDB reads the raw C memory pointers of the Polars/Arrow column buffers directly—**zero serialization, zero data copying, and zero `PyObject` boxing**!

```python
import duckdb
import polars as pl

# 1. Create an in-memory Polars DataFrame in Python RAM:
station_df = pl.DataFrame({
    "station_id": [60390, 60419, 60680],
    "region":     ["North Coast", "East Highland", "Deep South"],
})

# 2. DuckDB Replacement Scan: JOIN the Python variable `station_df` directly with a Parquet file on disk!
result_pl = duckdb.sql("""
    SELECT
        s.region,
        COUNT(*)                                     AS valid_obs,
        ROUND(AVG(NULLIF(o.temp_c, -9999.0)), 2)     AS mean_temp_c
    FROM 'synoptic_observations_2026.parquet' o
    INNER JOIN station_df s USING (station_id)
    GROUP BY s.region
    ORDER BY mean_temp_c DESC;
""").pl()  # Zero-copy output: .pl() -> Polars, .arrow() -> PyArrow Table, .df() -> Pandas!
           # NEVER use .fetchall() on large analytical results in DuckDB!
```

### 4.2 Multi-Thread Concurrency in DuckDB (`conn.cursor()`)

If you use DuckDB inside a multi-threaded FastAPI server (like [`day5/serving_api.py`](../day5/serving_api.py)):
- Open a single shared read-only `duckdb.connect()` at process startup, and in each worker thread call **`local_con = shared_conn.cursor()`** (which in DuckDB creates a lightweight thread-local client context sharing the same buffer pool).

---

## 5. Days 2 & 3: Python + PostgreSQL (`psycopg` v3 vs. Legacy `psycopg2`)

Install modern `psycopg` (v3) and its connection pool:
```bash
pip install "psycopg[binary,pool]" geopandas sqlalchemy pyarrow
```

### 5.1 Why `psycopg` v3 Replaces `psycopg2` (Server-Side Binding & Pipeline Mode)

For over a decade, `psycopg2` was the standard Python PostgreSQL driver, but its architecture had three major limitations that **`psycopg` v3 (`import psycopg`)** solved completely:

| Architectural Feature | Legacy `psycopg2` (`import psycopg2`) | Modern `psycopg` v3 (`import psycopg`) | Impact on Weather Telemetry |
| :--- | :--- | :--- | :--- |
| **Parameter Binding Protocol** | **Client-Side String Interpolation (`mogrify`):** Formats Python values into SQL strings in client RAM and sends a single giant SQL text string via `PQexec`. | **True Server-Side Binding (`PQexecParams`):** Sends the SQL template and binary/text parameters **separately** over the PostgreSQL wire protocol! | Enables automatic **Server-Side Prepared Statements** (`prepare_threshold=5`) and eliminates string-quoting CPU overhead. |
| **`cur.executemany()` Performance** | **Slow 1-by-1 Network Loop:** Sends each row as a separate TCP round-trip (`INSERT` $\rightarrow$ wait $\rightarrow$ `INSERT` $\rightarrow$ wait). | **Automatic Libpq Pipeline Mode:** Batches thousands of parameterized `INSERT`s into a single asynchronous TCP stream without waiting for individual replies! | `cur.executemany()` in `psycopg3` is **$10\text{--}30\times$ faster** out of the box without needing `psycopg2.extras.execute_values` hacks! |
| **`COPY` API (`COPY ... FROM STDIN`)** | Requires awkward file-like `StringIO`/`BytesIO` wrappers (`copy_from` / `copy_expert`). | Native Python context manager **`with cur.copy("COPY ... FROM STDIN (FORMAT BINARY)") as copy:`** with typed `copy.write_row(tuple)`! | Streams **100,000+ rows/sec** directly into PostgreSQL 8 KB heap pages in binary format. |
| **`with conn:` & Nested Transactions** | `with conn:` only commits/rolls back; **does not close** the connection! No nested transaction support. | `with psycopg.connect(...) as conn:` **commits/rolls back AND closes** the connection! Plus **`with conn.transaction():`** supports nested `SAVEPOINT`s! | Eliminates leaked `idle in transaction` backends on PostgreSQL. |

---

### 5.2 Client-Side vs. Named Server-Side Cursors (Preventing 10M-Row `MemoryError`)

> [!WARNING]
> **Why `cur.execute("SELECT * FROM synoptic.observations")` Crashes Python Before `fetchone()` Even Runs:**  
> By default, PostgreSQL's C library (`libpq`) uses **Client-Side Cursors**: when you call `cur.execute(sql)`, PostgreSQL streams the **entire 10,000,000-row result set** over the network into your Python process's RAM *before* `cur.execute()` even returns! Calling `cur.fetchone()` or `cur.fetchmany(1000)` on a default cursor does **not** save RAM because all 10M rows were already downloaded into `libpq` memory!

To stream millions of rows in constant RAM (e.g., when exporting a PostgreSQL partition to Parquet in [`day5/export_pg_to_parquet.py`](../day5/export_pg_to_parquet.py)), pass a **`name`** to `conn.cursor(name="...")` to create a **Named Server-Side Cursor** (`DECLARE <name> NO SCROLL CURSOR FOR ...` in PostgreSQL):

```python
import psycopg

PG_DSN = "postgresql://postgres:meteo_password@localhost:5432/weather_ops"

# ✅ Constant-Memory Streaming of 10,000,000 Rows via Named Server-Side Cursor:
with psycopg.connect(PG_DSN) as conn:
    # Passing `name="stream_obs"` creates a PostgreSQL Server-Side Cursor!
    with conn.cursor(name="stream_obs") as cur:
        cur.itersize = 10_000  # Fetch 10,000 rows per network round-trip (`FETCH FORWARD 10000`)
        cur.execute("""
            SELECT station_id, obs_time, temp_c, pressure_hpa
            FROM synoptic.observations
            WHERE obs_time >= '2026-01-01 00:00:00+00';
        """)
        for row in cur:  # Streams seamlessly in ~15 MB of constant Python RAM!
            pass
```

---

### 5.3 High-Speed Ingestion: `executemany()` Pipeline vs. Binary `COPY`

Use a **`ConnectionPool`** (`psycopg_pool`) so worker threads reuse open TCP connections instead of paying a 15–30 ms TLS/fork handshake on every batch:

```python
from datetime import datetime, timezone
import psycopg
from psycopg.rows import dict_row
from psycopg_pool import ConnectionPool

PG_DSN = "postgresql://postgres:meteo_password@localhost:5432/weather_ops"

# Thread-safe pool: keeps 2 to 10 persistent PostgreSQL backends open
pool = ConnectionPool(conninfo=PG_DSN, min_size=2, max_size=10)

# PATTERN A: Idempotent UPSERT Batching via `executemany()` (Automatic Pipeline Mode)
def upsert_synoptic_batch(readings: list[tuple]) -> None:
    upsert_sql = """
        INSERT INTO synoptic.observations (
            station_id, obs_time, temp_c, pressure_hpa, wind_speed_kt, precip_1h_mm, qc_flag
        )
        VALUES (%s, %s, %s, %s, %s, %s, %s)
        ON CONFLICT (station_id, obs_time) DO UPDATE SET
            temp_c        = EXCLUDED.temp_c,
            pressure_hpa  = EXCLUDED.pressure_hpa,
            wind_speed_kt = EXCLUDED.wind_speed_kt,
            precip_1h_mm  = EXCLUDED.precip_1h_mm,
            qc_flag       = EXCLUDED.qc_flag
        WHERE (
            observations.temp_c, observations.pressure_hpa, observations.wind_speed_kt,
            observations.precip_1h_mm, observations.qc_flag
        ) IS DISTINCT FROM (
            EXCLUDED.temp_c, EXCLUDED.pressure_hpa, EXCLUDED.wind_speed_kt,
            EXCLUDED.precip_1h_mm, EXCLUDED.qc_flag
        );
    """
    # Note: `with pool.connection() as conn:` commits and returns `conn` to the pool on exit!
    with pool.connection() as conn:
        with conn.cursor() as cur:
            cur.executemany(upsert_sql, readings)


# PATTERN B: Ultra-Fast Raw Bulk Append via Binary `COPY` (100,000+ rows/sec)
def bulk_copy_raw_observations(readings: list[tuple]) -> None:
    copy_sql = """
        COPY synoptic.observations (
            station_id, obs_time, temp_c, pressure_hpa, wind_speed_kt, precip_1h_mm, qc_flag
        ) FROM STDIN WITH (FORMAT BINARY);
    """
    with pool.connection() as conn:
        with conn.cursor() as cur:
            with cur.copy(copy_sql) as copy:
                # Explicitly set PostgreSQL column types for binary serialization safety
                copy.set_types(["int4", "timestamptz", "numeric", "numeric", "numeric", "numeric", "text"])
                for row in readings:
                    copy.write_row(row)
```

---

### 5.4 Loading `PostGIS` Spatial Data into `GeoPandas` (`read_postgis` & `ADBC`)

```python
import geopandas as gpd
from sqlalchemy import create_engine

# SQLAlchemy 2.0 URL using the modern `psycopg` (v3) dialect (`postgresql+psycopg://`)
engine = create_engine("postgresql+psycopg://postgres:meteo_password@localhost:5432/weather_ops")

# Read PostGIS GEOGRAPHY/GEOMETRY query directly into a spatial GeoDataFrame!
gdf = gpd.read_postgis(
    sql="""
        SELECT
            s.station_id,
            s.station_name,
            s.geog::geometry AS geom,
            ROUND(AVG(o.temp_c), 1) AS mean_temp_c
        FROM synoptic.stations s
        JOIN synoptic.observations o USING (station_id)
        GROUP BY s.station_id, s.station_name, s.geog;
    """,
    con=engine,
    geom_col="geom",
    crs="EPSG:4326",
)

# Export to Cloud-Native GeoParquet for Day 5 Lakehouse analytics:
gdf.to_parquet("stations_climatology_geoparquet.parquet")
```

---

### 5.5 Generating & Binding Time-Ordered `UUIDv7` (RFC 9562) in Python (`psycopg3` vs. `sqlite3`)

When remote Saharan automatic weather stations (`AWS`) or mobile radiosonde units record observations while offline, they cannot ask a central PostgreSQL server for the next `BIGINT IDENTITY` sequence value. However, generating random **`uuid.uuid4()`** values on the edge and inserting them into PostgreSQL destroys B-Tree page locality, causes 50/50 index page splits, and triggers **$500\times$ `pg_wal` Full-Page Write (`FPW`) amplification** (see [Day 2 Coursebook — Black Box 2D](../day2/day2_master_coursebook.md)).

Instead, edge Python daemons should generate **IETF RFC 9562 `UUIDv7`** (`48-bit` big-endian Unix millisecond timestamp + `4-bit` version `7` + `12-bit` sub-millisecond counter/random + `2-bit` variant + `62-bit` random payload):
- **Python 3.14+** includes `uuid.uuid7()` in the standard library; on **Python 3.10–3.13**, you can either install `uuid6` (`from uuid6 import uuid7`) or use the **10-line zero-dependency standard-library `uuid7()` generator** below.
- **How Drivers Adapt `uuid.UUID` Under the Hood:**
  - **`psycopg` v3:** Natively adapts Python `uuid.UUID` objects to PostgreSQL's `16-byte` binary `UUID` type (and decodes PostgreSQL `UUID` columns back into `uuid.UUID` objects automatically!). In binary `COPY`, specify `"uuid"` in `copy.set_types([...])`.
  - **`sqlite3` / `APSW`:** SQLite has no dedicated `UUID` storage class. Calling `cur.execute("INSERT ... VALUES (?)", (u,))` with a raw `uuid.UUID` object raises `ProgrammingError: Error binding parameter 1: type 'UUID' is not supported`! You must explicitly pass either:
    1. **`u.bytes` (`16-byte BLOB`)** — **Fastest & smallest** (`16 bytes` on disk vs. `36 bytes` for text; preserves big-endian chronological byte sorting in SQLite B-Trees!).
    2. **`str(u)` (`36-byte TEXT`)** — Human-readable in `sqlite3` CLI (`'01925a6b-9c00-7e42-...'`) and also sorts chronologically because big-endian hex strings are lexicographically ordered!

```python
import os
import sqlite3
import time
import uuid
from contextlib import closing
from datetime import datetime, timezone


# 1. Zero-Dependency RFC 9562 UUIDv7 Generator (Works in Python 3.8–3.14+ with Stdlib Only!)
def generate_uuidv7() -> uuid.UUID:
    """
    Constructs a 128-bit RFC 9562 time-ordered UUIDv7:
    - Bits  0..47 : 48-bit big-endian Unix Epoch timestamp in milliseconds
    - Bits 48..51 : 4-bit version = 0b0111 (7)
    - Bits 52..63 : 12-bit sub-ms / random_a
    - Bits 64..65 : 2-bit RFC 9562 variant = 0b10
    - Bits 66..127: 62-bit cryptographic randomness (random_b)
    """
    unix_ts_ms = time.time_ns() // 1_000_000
    rand_bytes = int.from_bytes(os.urandom(10), byteorder="big")
    rand_a = (rand_bytes >> 62) & 0x0FFF
    rand_b = rand_bytes & ((1 << 62) - 1)

    uuid_int = (
        ((unix_ts_ms & 0xFFFFFFFFFFFF) << 80)
        | (0x7 << 76)
        | (rand_a << 64)
        | (0x2 << 62)
        | rand_b
    )
    return uuid.UUID(int=uuid_int)


def extract_uuidv7_utc_datetime(u: uuid.UUID) -> datetime:
    """Extracts the exact millisecond UTC creation timestamp embedded in a UUIDv7's top 48 bits."""
    unix_ts_ms = u.int >> 80
    return datetime.fromtimestamp(unix_ts_ms / 1000.0, tz=timezone.utc)


# 2. Verify Monotonic B-Tree Sorting & Timestamp Extraction:
batch_ids = [generate_uuidv7() for _ in range(3)]
assert batch_ids == sorted(batch_ids), "UUIDv7s are strictly time-ordered!"
print(f"Sample UUIDv7 : {batch_ids[0]} (ver={batch_ids[0].version})")
print(f"Embedded Time : {extract_uuidv7_utc_datetime(batch_ids[0]).isoformat()}")

# 3. Binding UUIDv7 as Compact 16-Byte BLOB in SQLite (Saves 20 Bytes/Row vs. 36-Char TEXT!):
with closing(sqlite3.connect(":memory:", isolation_level=None)) as sqlite_conn:
    sqlite_conn.execute("""
        CREATE TABLE edge_packet_buffer (
            packet_id  BLOB PRIMARY KEY CHECK (length(packet_id) = 16),
            station_id INTEGER NOT NULL,
            temp_c     REAL    NOT NULL
        ) STRICT;
    """)
    with sqlite_conn:
        for pkt_uuid in batch_ids:
            # Bind `pkt_uuid.bytes` (16-byte big-endian BLOB) -> B-Tree appends strictly to rightmost leaf!
            sqlite_conn.execute(
                "INSERT INTO edge_packet_buffer VALUES (?, ?, ?);",
                (pkt_uuid.bytes, 60680, 38.4),
            )
    # Read back and reconstruct `uuid.UUID(bytes=row[0])`:
    for raw_blob, stn_id, temp_c in sqlite_conn.execute("SELECT * FROM edge_packet_buffer ORDER BY packet_id;"):
        recovered_uuid = uuid.UUID(bytes=raw_blob)
        assert recovered_uuid in batch_ids

# 4. Binding UUIDv7 Natively in PostgreSQL (`psycopg3` adapts `uuid.UUID` -> 16-Byte PG `UUID` directly!):
# with psycopg.connect(PG_DSN) as pg_conn:
#     pg_conn.execute(
#         "INSERT INTO synoptic.edge_packets (packet_id, station_id, temp_c) VALUES (%s, %s, %s);",
#         (generate_uuidv7(), 60680, 38.4),  # <-- Pass `uuid.UUID` object directly!
#     )
```

---

## 6. Days 4 & 5: Python + MongoDB (`PyMongo` Replica-Set Driver Internals)

Unlike relational engines, MongoDB uses a binary BSON wire protocol (`OP_MSG` over TCP `:27017`), so **`PyMongo`** (`pip install pymongo`) does **not** use PEP 249 `Connection`/`Cursor` semantics.

### 6.1 How `MongoClient` Discovers Replica Sets & Routes Reads/Writes

1. **`MongoClient` Is Already a Thread-Safe Connection Pool:**
   - **Never create a new `MongoClient()` per request!** Instantiate **one** global `MongoClient` per process. Internally, `MongoClient` spawns background topology-monitoring threads (`hello` heartbeats) and maintains a socket pool (`maxPoolSize=100` by default) to every node in the Replica Set.
2. **Automatic Failover & Topology Discovery:**
   - When you pass `replicaSet=rs_meteo` in the URI, `MongoClient` automatically discovers all Primary and Secondary nodes. If the Primary steps down during a storm, `retryWrites=true` instructs `PyMongo` to wait for the Raft election (1–3 seconds) and transparently retry your write against the new Primary!
3. **Critical Timezone Rule (`tz_aware=True`):**
   - MongoDB stores BSON `Date` as a 64-bit UTC millisecond integer, but by default `PyMongo` decodes BSON dates into **naive** Python `datetime` objects (`tzinfo=None`)! Always obtain your database handle with **`CodecOptions(tz_aware=True)`** so Python receives timezone-aware UTC `datetime` objects.

### 6.2 Production `PyMongo` Pattern: Unordered Bulk Upserts, `WriteConcern` & Aggregation Cursors

```python
from datetime import datetime, timezone
from bson.codec_options import CodecOptions
from pymongo import MongoClient, UpdateOne, ReadPreference
from pymongo.errors import BulkWriteError
from pymongo.write_concern import WriteConcern

# 1. Single process-wide MongoClient with Replica Set discovery, majority durability & timeouts
client = MongoClient(
    "mongodb://localhost:27017,localhost:27018,localhost:27019/"
    "?replicaSet=rs_meteo&retryWrites=true&w=majority&readPreference=primaryPreferred",
    serverSelectionTimeoutMS=5000,
)

# Enforce timezone-aware UTC datetime objects when reading BSON Date fields!
db = client.get_database(
    "weather_nosql",
    codec_options=CodecOptions(tz_aware=True, tzinfo=timezone.utc),
    write_concern=WriteConcern(w="majority", j=True, wtimeout=5000),
)

# 2. High-Throughput Idempotent Upserts with `bulk_write(..., ordered=False)`
# ordered=False lets WiredTiger process valid station packets even if 1 packet fails $jsonSchema!
ops = [
    UpdateOne(
        {"_id": "DZ-ONM-2026-10-07-001"},
        {
            "$setOnInsert": {
                "issued_at": datetime.now(timezone.utc),
                "phenomenon": "HIGH_WIND",
                "severity": "ORANGE",
            },
            "$max": {"max_observed_gust_kt": 46.0},
            "$addToSet": {"affected_stations": {"$each": [60390, 60901]}},
        },
        upsert=True,
    )
]

try:
    result = db.cap_alerts.bulk_write(ops, ordered=False)
    print(f"Upserted: {result.upserted_count}, Modified: {result.modified_count}")
except BulkWriteError as bwe:
    # Inspect individual document validation errors without losing valid writes:
    for err in bwe.details.get("writeErrors", []):
        print(f"Rejected document index {err['index']}: {err['errmsg']}")

# 3. Offload Heavy Analytical Aggregations to Secondary Nodes (`SECONDARY_PREFERRED`)
analytics_coll = db.radiosonde_soundings.with_options(
    read_preference=ReadPreference.SECONDARY_PREFERRED
)

pipeline = [
    {"$unwind": {"path": "$vertical_levels", "preserveNullAndEmptyArrays": False}},
    {"$match": {"vertical_levels.pressure_hpa": 500}},
    {
        "$project": {
            "_id": 0,
            "station_id": 1,
            "launch_time": 1,
            "temp_500hpa_c": "$vertical_levels.temp_c",
            "wind_500hpa_kt": "$vertical_levels.wind_speed_kt",
        }
    },
]

# Iterate over the CommandCursor in batches (`batch_size=1000`) instead of `list(cursor)` on large results
with analytics_coll.aggregate(pipeline, batch_size=1000) as cursor:
    for doc in cursor:
        pass
```

---

## 7. Cross-Driver Engineering Summary Matrix

| Feature / Trap | `sqlite3` (Stdlib) | `APSW` (SQLite C Wrapper) | `psycopg` v3 (PostgreSQL) | `duckdb` (Columnar OLAP) | `PyMongo` (MongoDB) |
| :--- | :--- | :--- | :--- | :--- | :--- |
| **Implements PEP 249 (`DB-API 2.0`)?** | ✅ Yes | ❌ No (Direct 1:1 SQLite C API) | ✅ Yes | ✅ Yes (+ Relational/Arrow API) | ❌ No (BSON Document API) |
| **Parameter Placeholder** | `?` or `:name` | `?` or `:name` | `%s` or `%(name)s` | `?`, `$1`, or `$name` | Native Python `dict` |
| **Default Transaction Mode** | Quirky DML-only implicit `BEGIN` (`isolation_level=""`); use `isolation_level=None` or Python 3.12 `autocommit=True` | Native SQLite autocommit (no hidden `BEGIN`) | Strict PEP 249 (`autocommit=False`, starts transaction on first statement) | Autocommit unless `BEGIN` executed | Single-document atomic (`w="majority"`); multi-doc via `with client.start_session() as s:` |
| **Does `with conn:` close the connection?** | ❌ **NO!** (Only commits/rolls back; wrap in `contextlib.closing()`) | ❌ **NO!** (Manages nestable `BEGIN` / `SAVEPOINT`s) | ✅ **YES!** (Commits/rolls back **and** closes socket; `with conn.transaction():` for savepoints) | ✅ **YES!** (`with duckdb.connect() as con:` closes on exit) | ✅ **YES!** (`with MongoClient() as client:` closes pools on exit) |
| **UUID (`UUIDv7` RFC 9562) Binding** | Pass `u.bytes` (`16B BLOB`) or `str(u)` (`36B TEXT`) | Pass `u.bytes` (`16B BLOB`) or `str(u)` (`36B TEXT`) | Pass `uuid.UUID` directly (`16B` native PG `UUID`) | Pass `uuid.UUID` or `str(u)` (`16B` `UUID` type) | Native `bson.ObjectId` (`12B`) or `Binary.from_uuid(u)` (`16B`) |
| **Fastest Bulk Write Method** | `BEGIN IMMEDIATE;` + `cur.executemany()` | `with conn:` + `cur.executemany()` | `with cur.copy("COPY ... FROM STDIN (FORMAT BINARY)")` | `INSERT INTO tbl SELECT * FROM arrow_or_polars_df` | `coll.bulk_write(ops, ordered=False)` |
| **Fastest Million-Row Read Method** | `pd.read_sql_query()` or `APSW` | `cur.execute()` generator | Named Server-Side Cursor (`conn.cursor(name="...")`) or `COPY TO STDOUT` | **Zero-Copy `.pl()` / `.arrow()`** (Never `.fetchall()`!) | `coll.find(..., batch_size=5000)` |

---

### 🔗 Reference Library Navigation

> **Navigation:** [🏠 Bootcamp Home](../README.md) | [📚 Reference Cards Index](./README.md) | [🌐 Interactive Portal](../bootcamp_portal.html)  
> **Card Sequence:** [⬅️ Previous Card](./10_query_execution_plan_forensics_and_explain.md) | **Card 11 of 14** | [Next Card ➡️](./12_dbeaver_and_mongodb_compass_gui_workflows.md) | [⬆️ Back to Top](#python-database-drivers-pep-249-db-api-20-internals--engine-integration-guide-sqlite3-vs-apsw-psycopg3-duckdb-geopandas-pymongo)
