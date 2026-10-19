> **Navigation:** [🏠 Master README](../README.md) | [🌐 Interactive Portal](../bootcamp_portal.html) | [📚 Reference Cards](../reference_cards/README.md) | [📘 Day 1 Coursebook](day1_master_coursebook.md) | [⏭️ Day 2 Coursebook](../day2/day2_master_coursebook.md)

# Day 1 Authoritative Reference Card & Cheatsheet: SQLite CLI Directives, Core SQL & Time-Series Telemetry Wrangling

**Companion to:**
- `day1_master_coursebook.md` — Complete Day 1 Master Coursebook & Telemetry Reference
- `day1_hardware_sentinels_and_qc_guide.md` — Deep-Dive on `-9999` In-Band Signaling & 3VL
- `weather_ops_seed.sql` / `weather_ops.db` — WMO Synoptic & NWP Verification Database
- `generate_weather_db.py` / `weather_telemetry.db` — 250,000-Row High-Frequency AWS Telemetry Stream

---

## PART I: SQLite CLI Shell Directives (`.dot-commands`) & Engine `PRAGMA` Reference

### 1. Core Concept: Shell Dot-Commands vs. `PRAGMA` Directives vs. Declarative SQL

When working with SQLite, engineers must distinguish between **three** fundamentally different instruction layers:

1. **Shell Directives ("Dot-Commands" — `.headers`, `.mode`, `.timer`, `.schema`):** Control instructions evaluated **strictly by the `sqlite3` terminal client program**. They configure terminal display formatting, toggle performance timers, and manage CSV import/export streams. They **must start with a dot (`.`) at column 1**, **never end with a semicolon**, and **cannot** be executed inside Python `sqlite3.connect().execute()` or DBeaver SQL editors.
2. **Engine `PRAGMA` Statements (`PRAGMA foreign_keys = ON;`, `PRAGMA journal_mode = WAL;`, `PRAGMA table_info(...)`):** SQLite-specific SQL extensions parsed and executed directly by the **SQLite Storage Core (`libsqlite3`)**. They configure connection-level or database-level engine behavior (foreign key enforcement, Write-Ahead Logging, OS `fsync` durability, RAM page cache size, lock timeouts) and provide SQL-callable schema/integrity introspection. They **end with a semicolon (`;`)** and **work everywhere** (`sqlite3` CLI, Python `sqlite3`, DBeaver, DB Browser for SQLite).
3. **Standard Declarative SQL (`SELECT`, `INSERT`, `CREATE`, `WITH`):** Relational statements sent to the SQLite compiler, translated into Virtual Database Engine (`VDBE`) bytecode, and executed against 4 KB B-Tree pages. They must always end with a semicolon (`;`).

```
┌──────────────────────────────────────────────────────────────────────────────────────────┐
│                           Engineer / Python Driver / GUI Client                          │
└───────────────┬─────────────────────────────────────────┬────────────────────────────────┘
                │                                         │
       Starts with "."?                        Valid SQL / PRAGMA (;)?
       (CLI Shell Only)                        (CLI, Python, DBeaver, JDBC)
                │                                         │
                ▼                                         ▼
┌───────────────────────────────┐         ┌────────────────────────────────────────────────┐
│      SQLite Shell Client      │         │          SQLite Storage Core (libsqlite3)      │
│  • .headers on / .mode box    │         │  1. PRAGMA Engine Control & Introspection      │
│  • .timer on / .nullvalue     │         │     (foreign_keys, journal_mode, cache_size,   │
│  • .tables / .schema / .import│         │      synchronous, busy_timeout, table_info)    │
└───────────────────────────────┘         │  2. Declarative SQL Bytecode (VDBE & B-Trees)  │
                                          │     (SELECT, INSERT, CREATE, JOIN, OVER)       │
                                          └────────────────────────────────────────────────┘
```

### 2. Launching & Building Databases from Terminal

```bash
# Build weather_ops.db from the WMO synoptic seed script:
sqlite3 weather_ops.db < weather_ops_seed.sql

# Generate the 250,000-row AWS telemetry database:
python3 generate_weather_db.py

# Open interactive shell:
sqlite3 weather_ops.db
sqlite3 weather_telemetry.db
```

### 3. Complete `sqlite3` CLI Dot-Commands Reference Table

| Dot-Command | Category | Purpose in Weather Lab | Typical Output / Effect |
| :--- | :--- | :--- | :--- |
| `.help` | Help | List all available `sqlite3` CLI dot-commands | Full command index |
| `.headers on` | Formatting | Render column attribute names above data rows | `station_id \| temperature` displayed at top |
| `.mode box` | Formatting | Draw clean Unicode table borders (SQLite 3.33+) | Box grid with aligned column widths |
| `.mode column` | Formatting | Format query output in aligned plain-text columns | Traditional fixed-width columns |
| `.mode list` | Formatting | Pipe-delimited output (default; ideal for `grep`/`awk`) | `AWS-001\|2026-10-04\|18.4` |
| `.mode csv` | Formatting | Format output as Comma-Separated Values | Exports ready for pandas or Excel |
| `.mode json` | Formatting | Render each row as a JSON object | Useful for API payload inspection |
| `.timer on` | Performance | Display CPU & wall-clock execution time per query | `Run Time: real 0.084 user 0.071 sys 0.012` |
| `.nullvalue NULL` | Formatting | Print `NULL` explicitly instead of an empty blank string | Makes missing sensor values visually obvious |
| `.tables` | Metadata | List all tables and views in the connected database | `forecasts observations stations weather_alerts` |
| `.tables %telemetry%` | Metadata | Filter table list by pattern match | `raw_telemetry` |
| `.schema <table>` | Metadata | Show exact `CREATE TABLE`, `CHECK`, and `CREATE INDEX` DDL | Prints full DDL for `stations` or `raw_telemetry` |
| `.import file.csv tbl` | I/O | Import a raw synoptic CSV file into a table (use with `.mode csv`) | Bulk loads CSV rows |
| `.output results.csv` | I/O | Redirect next query results to a file (reset with `.output stdout`) | Saves query output to disk |
| `.quit` (or `Ctrl+D`) | Session | Exit the `sqlite3` interactive shell | Returns to bash terminal |

---

### 4. Deep-Dive on Essential Directives

#### 4.1 `.headers on`
Controls whether column attribute names are displayed as the top row of a query result set.
* **Default:** Often `off` in script-piping modes to simplify unix-pipe parsing (`awk`, `sed`).
* **Impact on Meteorological Telemetry:** Weather stations output multi-column floating-point series (`temperature`, `dew_point`, `wet_bulb_temp`, `soil_temp_5cm`). Without headers, an analyst viewing raw numeric streams cannot distinguish ambient temperature from dew point.

```text
-- Without .headers on (Unusable & Risky):
AWS-001|2026-10-04 12:00:00|18.4|12.1|1014.2|4.5
AWS-001|2026-10-04 12:10:00|18.6|12.0|1014.1|5.1

-- With .headers on (Unambiguous):
station_id|recorded_at|temperature|dew_point|pressure|wind_speed
AWS-001|2026-10-04 12:00:00|18.4|12.1|1014.2|4.5
AWS-001|2026-10-04 12:10:00|18.6|12.0|1014.1|5.1
```

#### 4.2 `.mode box` vs. `.mode list`
Sets the output presentation layout to use Unicode line-drawing box borders with automatic column width calculation. In exploratory data analysis (EDA), `box` mode immediately reveals alignment shifts caused by negative numbers, long timestamps, or sentinel values (`-999.0`), making visual QC scanning effortless.

```text
-- Default Mode (.mode list):
station_id|recorded_at|temperature|pressure
AWS-013|2026-10-04 12:00:00|-999.0|1012.4
AWS-013|2026-10-04 12:10:00|16.2|1012.3

-- Box Mode (.mode box):
┌────────────┬─────────────────────┬─────────────┬──────────┐
│ station_id │     recorded_at     │ temperature │ pressure │
├────────────┼─────────────────────┼─────────────┼──────────┤
│ AWS-013    │ 2026-10-04 12:00:00 │ -999.0      │ 1012.4   │
│ AWS-013    │ 2026-10-04 12:10:00 │ 16.2        │ 1012.3   │
└────────────┴─────────────────────┴─────────────┴──────────┘
```

#### 4.3 `.timer on`
Instructs the SQLite shell to measure and print the precise CPU and elapsed wall-clock execution time for every SQL statement executed:
```text
Run Time: real 0.084 user 0.071230 sys 0.012410
```
* **`real` (Wall-Clock Time):** Total elapsed human time from query dispatch to final row delivery (includes disk I/O, OS scheduling).
* **`user` (User-Space CPU Time):** CPU time spent actively executing instructions inside SQLite code (math expressions, hashing groups, sorting arrays).
* **`sys` (Kernel-Space CPU Time):** CPU time spent handling OS system calls on behalf of SQLite (allocating memory pages, reading physical file blocks via `read()`).
* **The Pedagogical Bridge to Day 2:** On 250,000 rows, SQLite takes $\approx 0.08\text{ seconds}$ because the entire $20\text{ MB}$ database resides in OS RAM cache. On Day 2, running an unindexed table scan across 50 million records in PostgreSQL jumps from $80\text{ ms}$ to $45\text{ seconds}$ due to disk head read amplification.

#### 4.4 `.tables` and `.schema <table>` Under the Hood
Both commands are syntactic sugar querying SQLite's internal system catalog (`sqlite_schema`, formerly `sqlite_master`):

```sql
-- What .tables actually runs:
SELECT name 
FROM sqlite_schema 
WHERE type IN ('table', 'view') 
  AND name NOT LIKE 'sqlite_%'
ORDER BY 1;

-- What .schema raw_telemetry actually runs:
SELECT sql 
FROM sqlite_schema 
WHERE tbl_name = 'raw_telemetry' 
  AND type IN ('table', 'index', 'trigger')
ORDER BY type = 'table' DESC, name;
```
**Why Weather Engineers Must Run `.schema` First:**
1. **Index Verification:** Immediately reveals whether composite indexes exist on temporal columns (`station_id`, `recorded_at`).
2. **Constraint Auditing:** Confirms whether sensor metrics allow `NULL` or enforce physical `CHECK` constraints.
3. **Type Affinity Inspection:** Ensures sensor timestamps are stored consistently as ISO-8601 `TEXT` strings (`YYYY-MM-DD HH:MM:SS`).

#### 4.5 Permanent Shell Automation (`~/.sqliterc`)
Persist both `PRAGMA` engine rules and CLI display directives so every `sqlite3` session opens pre-configured:

```bash
# Linux / macOS:
cat << 'EOF' > ~/.sqliterc
PRAGMA foreign_keys = ON;
PRAGMA busy_timeout = 5000;
.headers on
.mode box
.timer on
.nullvalue NULL
EOF
```

```powershell
# Windows (PowerShell):
Set-Content -Path "$HOME\.sqliterc" -Value "PRAGMA foreign_keys = ON;`nPRAGMA busy_timeout = 5000;`n.headers on`n.mode box`n.timer on`n.nullvalue NULL"
```

---

### 5. Complete SQLite `PRAGMA` Options Reference & Production Tuning Guide

#### 5.1 How `PRAGMA` Syntax Works & Scope Rules (Per-Connection vs. Persistent)
Unlike standard SQL statements, a `PRAGMA` can be called in three ways:
- **Query current setting:** `PRAGMA foreign_keys;` or `PRAGMA journal_mode;`
- **Assign a new setting:** `PRAGMA foreign_keys = ON;` or `PRAGMA cache_size = -64000;`
- **Call with an argument (or as a Table-Valued Function in SQLite 3.16+):** `PRAGMA table_info('stations');` or `SELECT * FROM pragma_table_info('stations') WHERE notnull = 1;`

> [!IMPORTANT]
> **The Golden Scope Rule — Per-Connection vs. Persistent Database Header Pragmas:**
> - **Per-Connection (Session) Pragmas:** Reset to compile-time defaults on **every** new `sqlite3` CLI launch, Python `sqlite3.connect()`, or DBeaver connection! Examples: `foreign_keys`, `synchronous`, `busy_timeout`, `cache_size`, `temp_store`, `mmap_size`.
> - **Persistent (Database File Header) Pragmas:** Recorded permanently inside the first 100 bytes of the `.db` file header and persist across all future connections! Examples: `journal_mode = WAL` (persists until explicitly changed back to `DELETE`), `page_size` (when set before table creation or followed by `VACUUM;`), `auto_vacuum`, `application_id`, `user_version`.

---

#### 5.2 Category A: Data Integrity, Foreign Keys & Corruption Auditing Pragmas

| `PRAGMA` Option | Default | Scope | Values / Syntax | Purpose & Meteorological Engineering Impact |
| :--- | :---: | :---: | :--- | :--- |
| **`PRAGMA foreign_keys`** | `0` (`OFF`) | **Per-Connection** | `ON` (`1`) \| `OFF` (`0`) | **Critical:** Enables runtime enforcement of `FOREIGN KEY` constraints and `ON DELETE CASCADE` (used in [`weather_ops_seed.sql`](./weather_ops_seed.sql)). Without this, SQLite silently allows orphaned `station_id` rows! |
| **`PRAGMA foreign_key_check`** | — | Action | `PRAGMA foreign_key_check;` or `PRAGMA foreign_key_check(observations);` | Scans existing tables for orphaned rows that were inserted while `foreign_keys = OFF`. Returns 4 columns (`table`, `rowid`, `parent`, `fkid`); empty result = 100% valid. |
| **`PRAGMA integrity_check`** | — | Action | `PRAGMA integrity_check;` or `PRAGMA integrity_check(10);` | Full physical B-Tree page audit: verifies page pointers, index entries, `UNIQUE`, and `NOT NULL` constraints. Returns `ok` if clean. Run after power outages on remote field loggers! |
| **`PRAGMA quick_check`** | — | Action | `PRAGMA quick_check;` | Fast variant of `integrity_check` ($\approx 5\text{--}10\times$ faster) that verifies B-Tree pages and constraints but skips cross-checking index sort order against table rows. |
| **`PRAGMA ignore_check_constraints`** | `0` (`OFF`) | **Per-Connection** | `OFF` (`0`) \| `ON` (`1`) | Temporarily bypasses `CHECK (...)` constraints during emergency raw recovery (never enable in normal operations). |
| **`PRAGMA trusted_schema`** | `1` (`ON`) | **Per-Connection** | `OFF` (`0`) \| `ON` (`1`) | Set to `OFF` when opening untrusted external `.db` files so SQLite refuses to execute potentially malicious SQL functions hidden inside views or triggers. |

---

#### 5.3 Category B: Journaling, Crash Recovery (`WAL`) & Lock Concurrency Pragmas

*(For cross-engine architectural diagrams comparing SQLite WAL vs. PostgreSQL `XLogRecord` vs. MySQL InnoDB Redo Log, see [Reference Card 07: WAL & Crash Recovery](../reference_cards/07_wal_crash_recovery_sqlite_postgres_mysql.md)).*

| `PRAGMA` Option | Default | Scope | Options & Mechanics | When to Use in Weather Telemetry |
| :--- | :---: | :---: | :--- | :--- |
| **`PRAGMA journal_mode`** | `DELETE` | **Persistent** (for `WAL`) / Connection | • `DELETE`: Creates & deletes `.db-journal` on every commit (blocks readers during writes).<br>• `TRUNCATE`: Truncates journal to `0` bytes.<br>• `PERSIST`: Zeroes journal header.<br>• `MEMORY`: Keeps rollback journal in RAM (**corrupts on power loss**).<br>• **`WAL`**: **Write-Ahead Logging** (`.db-wal` + `.db-shm`). Readers never block the writer; writer never blocks readers!<br>• `OFF`: Disables rollback journal (**corrupts on crash/rollback**). | • **Live AWS Station Daemon + Dashboard:** Always set `PRAGMA journal_mode = WAL;` so 1-minute ingestion doesn't throw `database is locked` while forecasters run queries.<br>• **Scratch Bulk Generator ([`generate_weather_db.py`](./generate_weather_db.py)):** Uses `OFF` to synthesize 250,000 rows in ~2s because the file can be regenerated from scratch if interrupted. |
| **`PRAGMA synchronous`** | `FULL` (`2`) | **Per-Connection** | • `EXTRA` (`3`): Extra `fsync` of parent directory in `DELETE` mode.<br>• `FULL` (`2`): OS `fsync()` after every transaction commit.<br>• **`NORMAL` (`1`)**: In `WAL` mode, guarantees B-Tree corruption safety while skipping `fsync()` on individual WAL commits (syncs only at checkpoints!).<br>• `OFF` (`0`): Hands bytes to OS buffer cache without `fsync()` (**fast, but OS crash can lose data**). | • **Production (`WAL` mode):** Use `PRAGMA synchronous = NORMAL;` ($5\text{--}20\times$ faster writes than `FULL` with full B-Tree crash safety in `WAL` mode).<br>• **Disposable Bulk Load:** `generate_weather_db.py` uses `OFF` to avoid 250k disk barrier stalls. |
| **`PRAGMA busy_timeout`** | `0` ms | **Per-Connection** | `PRAGMA busy_timeout = 5000;` (milliseconds) | By default (`0 ms`), if Process A holds a write lock, Process B fails *instantly* with `OperationalError: database is locked` (`SQLITE_BUSY`). Setting `5000` instructs SQLite to sleep and retry for up to 5 seconds until the writer finishes. |
| **`PRAGMA wal_autocheckpoint`** | `1000` pages | **Per-Connection** | `PRAGMA wal_autocheckpoint = 1000;` ($\approx 4\text{ MB}$ at 4 KB pages; `<= 0` disables auto-checkpoint) | Automatically triggers a `PASSIVE` checkpoint once `.db-wal` accumulates $N$ frames (default `1000` pages = `4 MB`). |
| **`PRAGMA wal_checkpoint`** | — | Action | `PASSIVE` \| `FULL` \| `RESTART` \| `TRUNCATE` | Manually triggers a WAL checkpoint and returns the 3-column diagnostic row `(busy, log, checkpointed)`. |
| **`PRAGMA journal_size_limit`** | `-1` (Unlimited) | **Per-Connection** | Bytes (e.g., `PRAGMA journal_size_limit = 67108864;` for `64 MiB`; `0` truncates to minimum) | Caps the on-disk size of `.db-wal` (and `PERSIST` journals). Whenever a WAL checkpoint rewinds to frame 1, SQLite automatically truncates `.db-wal` if it exceeded this byte limit! |
| **`PRAGMA locking_mode`** | `NORMAL` | **Per-Connection** | `NORMAL` \| `EXCLUSIVE` | In `EXCLUSIVE` + `WAL` mode, a single-process edge logger keeps locks permanently and never creates or maps the `.db-shm` shared-memory file (reducing flash I/O, but forbidding any second process from connecting). |

##### 5.3a. Deep-Dive: The 4 `PRAGMA wal_checkpoint` Modes & Return Tuple `(busy, log, checkpointed)`

When SQLite runs in `WAL` mode, every `INSERT`/`UPDATE`/`DELETE` appends modified 4 KB pages ("frames") sequentially to `weather_ops.db-wal`. Checkpointing copies those committed frames back into the main `weather_ops.db` file so `.db-wal` can be rewound to the beginning and reused.

Every execution of `PRAGMA wal_checkpoint(<MODE>);` returns a single diagnostic row with **three integers**:

```text
┌──────┬──────┬──────────────┐
│ busy │ log  │ checkpointed │
├──────┼──────┼──────────────┤
│ 0    │ 1420 │ 1420         │
└──────┴──────┴──────────────┘
```
1. **`busy` (`0` or `1`):** `0` means the checkpoint completed without being blocked; `1` means an active concurrent reader or writer prevented the checkpoint from finishing or rewinding.
2. **`log` (Integer):** Total number of modified 4 KB frames currently residing inside the `.db-wal` file.
3. **`checkpointed` (Integer):** Total number of frames successfully copied from `.db-wal` back into the main `.db` file. *(If `checkpointed < log`, an active reader is holding a read lock ("Read-Mark") on an older snapshot in the WAL!)*

| Checkpoint Mode | SQL Command | Waits for Active Writers/Readers? | Rewinds WAL Write Pointer to Frame 1? | Truncates `.db-wal` File to `0` Bytes on Disk? | When to Use |
| :--- | :--- | :---: | :---: | :---: | :--- |
| **1. `PASSIVE`** *(Default)* | `PRAGMA wal_checkpoint(PASSIVE);` | ❌ **Never blocks** (stops at first active reader snapshot) | Only if `checkpointed == log` and no readers remain | ❌ No (keeps allocated file size unless `journal_size_limit` set) | Used automatically by `wal_autocheckpoint = 1000` and non-intrusive background cron jobs. |
| **2. `FULL`** | `PRAGMA wal_checkpoint(FULL);` | ⏳ **Waits** (up to `busy_timeout`) for current writers & existing readers to finish | Only if no new reader started during the flush | ❌ No | Scheduled maintenance window when you want all committed WAL frames flushed to `.db`. |
| **3. `RESTART`** | `PRAGMA wal_checkpoint(RESTART);` | ⏳ **Waits** for all readers to finish **after** flushing so next writer **must** start at byte 0 | ✅ **Guaranteed** (blocks new writers until WAL rewinds to frame 1) | ❌ No (reuses existing file allocation for speed) | High-throughput ingestion daemons that want to bound `.db-wal` growth without filesystem `ftruncate()` metadata stalls. |
| **4. `TRUNCATE`** | `PRAGMA wal_checkpoint(TRUNCATE);` | ⏳ **Waits** for all writers & readers, flushes all frames, and rewinds | ✅ **Guaranteed** | ✅ **Yes (`0` bytes)** | Pre-backup / pre-archival hook (`compact_hot_to_cold.py`) to fold everything into a clean single `.db` file. |

##### 5.3b. Deep-Dive: The `journal_mode` $\times$ `synchronous` Durability & `fsync()` Matrix

A common misconception is that `PRAGMA synchronous = NORMAL;` is "unsafe." In reality, its safety depends entirely on whether you are in legacy `DELETE` mode or `WAL` mode:

| Configuration Pair | OS `fsync()` Calls per `COMMIT` | Process Crash (`kill -9`) | Sudden Power Loss / OS Kernel Panic | Relative Write Speed | Verdict for Meteorological Engineering |
| :--- | :---: | :--- | :--- | :---: | :--- |
| `journal_mode = DELETE` + `synchronous = FULL` *(SQLite Default)* | **2 `fsync`s** per commit (journal + `.db`) | ✅ Safe | ✅ Safe (Zero data loss, zero corruption) | $1\times$ (Slowest; blocks readers) | Legacy default; safe but suffers `database is locked` under concurrent load. |
| `journal_mode = DELETE` + `synchronous = NORMAL` | 1–2 `fsync`s (skips barrier before deleting journal) | ✅ Safe | ⚠️ **Small Corruption Risk** if power dies mid-commit | $\approx 2\times$ | Avoid in `DELETE` mode; switch to `WAL` instead. |
| **`journal_mode = WAL` + `synchronous = NORMAL`** *(Recommended Production)* | **0 `fsync`s on commit!** (`fsync` only during WAL checkpoint) | ✅ Safe (OS flushes buffers) | ✅ **100% Corruption-Safe!** *(Last ~1–2s of un-fsynced commits may roll back cleanly, but `.db` never corrupts)* | **$10\text{--}25\times$ faster** | **Gold Standard for Edge AWS Loggers & Telemetry Daemons.** Preserves SSD/SD-card lifespan and eliminates commit stalls. |
| **`journal_mode = WAL` + `synchronous = FULL`** | **1 `fsync`** per commit (on `.db-wal` append) | ✅ Safe | ✅ **100% Safe + Zero Lost Commits** | $\approx 3\text{--}5\times$ faster than `DELETE+FULL` | Use for critical operational alert tables (`weather_alerts`) where even 1 second of power-cut rollback is unacceptable. |
| `journal_mode = OFF` + `synchronous = OFF` | **0 `fsync`s** | ❌ **DB Corrupts** | ❌ **DB Corrupts** | **$50\times$ faster** | **Only** for disposable scratch generators ([`generate_weather_db.py`](./generate_weather_db.py)) where the file is rebuilt from scratch on failure. |

##### 5.3c. Two Production WAL Pitfalls Every Engineer Must Know

> [!WARNING]
> **Pitfall 1 — "WAL Starvation" (Why `.db-wal` Can Grow to Gigabytes Despite `wal_autocheckpoint = 1000`):**  
> In `WAL` mode, SQLite can only rewind `.db-wal` back to byte `0` when **every** frame in `.db-wal` has been copied to `.db` **and** no active reader is referencing an older snapshot.  
> If a forecaster opens a query in a GUI or a Python script runs `cur.execute("SELECT * FROM raw_telemetry")` and fetches only 10 rows **without closing the cursor or finishing the transaction**, that connection holds a permanent "Read-Mark" on the old snapshot!  
> - **Symptom:** Subsequent checkpoints copy frames up to the Read-Mark (`checkpointed < log`), cannot rewind `.db-wal`, and `.db-wal` grows indefinitely to 10+ GB!  
> - **Fix:** Always close read cursors / wrap reads in short context managers, set `PRAGMA journal_size_limit = 67108864;` (`64 MiB`), and run periodic `PRAGMA wal_checkpoint(RESTART);`.

> [!CAUTION]
> **Pitfall 2 — Why `PRAGMA busy_timeout = 5000;` Fails Instantly on Read-to-Write Upgrades (`SQLITE_BUSY_SNAPSHOT`):**  
> Suppose Connection A starts a default deferred transaction (`BEGIN;`), runs a `SELECT` (acquiring a read snapshot at WAL frame 500), and then tries to run an `INSERT`. If Connection B committed frame 501 in the meantime, Connection A's snapshot is now stale.  
> SQLite **cannot** let Connection A wait and overwrite frame 501 without violating Serializable Snapshot Isolation—so SQLite **completely ignores `PRAGMA busy_timeout = 5000;`** and throws `OperationalError: database is locked` (`SQLITE_BUSY_SNAPSHOT`) at `0 ms`!  
> - **The Golden Rule for Concurrent Writers:** Whenever a transaction intends to write (`INSERT`/`UPDATE`/`DELETE`), **always start it with `BEGIN IMMEDIATE;`** instead of `BEGIN;`. `BEGIN IMMEDIATE;` acquires the write lock up front and **always honors `PRAGMA busy_timeout = 5000;`**!

---

#### 5.4 Category C: Memory Cache, I/O Performance & Storage Layout Pragmas

| `PRAGMA` Option | Default | Scope | Values / Syntax | Purpose & Meteorological Engineering Impact |
| :--- | :---: | :---: | :--- | :--- |
| **`PRAGMA cache_size`** | `-2000` ($\approx 2\text{ MiB}$) | **Per-Connection** | • **Negative (`-N`):** Allocates $N\text{ KiB}$ of RAM (e.g., `-64000` $\approx 64\text{ MiB}$).<br>• **Positive (`+N`):** Allocates $N$ B-Tree pages (e.g., `100000` pages $\times 4\text{ KB} \approx 400\text{ MB}$, used in [`generate_weather_db.py`](./generate_weather_db.py)). | Prevents SQLite from thrashing disk when building composite B-Tree indexes (`idx_telemetry_station_time`) or computing window functions across 250,000+ rows. |
| **`PRAGMA temp_store`** | `0` (`DEFAULT`) | **Per-Connection** | `0` (`DEFAULT`) \| `1` (`FILE`) \| `2` (`MEMORY`) | Setting `PRAGMA temp_store = MEMORY;` forces temporary B-Trees created by `ORDER BY`, `GROUP BY`, `DISTINCT`, `WITH RECURSIVE`, and window functions (`OVER`) to live purely in RAM instead of spilling to `/tmp`. |
| **`PRAGMA mmap_size`** | `0` (Disabled) | **Per-Connection** | Bytes (e.g., `PRAGMA mmap_size = 268435456;` for `256 MiB`) | Maps the `.db` file directly into the process virtual address space via OS `mmap()`, bypassing kernel `read()` system calls on analytical table scans. |
| **`PRAGMA page_size`** | `4096` bytes | **Persistent** (before DDL or `VACUUM`) | `512`, `1024`, `2048`, **`4096`**, `8192`, `16384`, `32768`, `65536` | Size of each physical B-Tree page on disk. `4096` matches modern SSD/OS 4 KB blocks; increasing to `8192` or `16384` speeds up sequential telemetry scans (`VACUUM;` required to apply to an existing DB). |
| **`PRAGMA auto_vacuum`** | `0` (`NONE`) | **Persistent** | `0` (`NONE`) \| `1` (`FULL`) \| `2` (`INCREMENTAL`) | By default (`NONE`), deleting old telemetry rows marks pages as reusable inside the file (`freelist_count`) without shrinking the `.db` file size on disk until `VACUUM;` is run. |

---

#### 5.5 Category D: Schema Introspection, System Metadata & Optimizer Pragmas

Unlike CLI dot-commands (`.tables`, `.schema`) which fail outside the `sqlite3` terminal, **Introspection Pragmas are valid SQL statements** that return tabular rows in Python (`cur.fetchall()`), DBeaver, and SQL queries (via `pragma_*` table-valued functions):

| `PRAGMA` Statement | Table-Valued SQL Equivalent | Output Columns Returned | Practical Use in `weather_ops.db` & `weather_telemetry.db` |
| :--- | :--- | :--- | :--- |
| **`PRAGMA table_info('stations');`** | `SELECT * FROM pragma_table_info('stations');` | `cid`, `name`, `type`, `notnull`, `dflt_value`, `pk` | Inspect column names, affinities (`INTEGER`, `REAL`, `TEXT`), `NOT NULL` flags (`1`/`0`), defaults, and Primary Key ordinal (`pk`). |
| **`PRAGMA table_xinfo('observations');`** | `SELECT * FROM pragma_table_xinfo('observations');` | Same as `table_info` + `hidden` | Also reveals virtual/generated columns and internal `rowid` hidden columns. |
| **`PRAGMA index_list('observations');`** | `SELECT * FROM pragma_index_list('observations');` | `seq`, `name`, `unique`, `origin`, `partial` | Lists all indexes on a table, including `sqlite_autoindex_observations_1` (`origin = 'u'` for `UNIQUE (station_id, obs_time)`). |
| **`PRAGMA index_info('idx_name');`** | `SELECT * FROM pragma_index_info('idx_name');` | `seqno`, `cid`, `name` | Shows the exact left-to-right column order inside a composite index (`station_id`, then `obs_time`). |
| **`PRAGMA foreign_key_list('observations');`** | `SELECT * FROM pragma_foreign_key_list('observations');` | `id`, `seq`, `table`, `from`, `to`, `on_update`, `on_delete`, `match` | Verifies that `observations.station_id` references `stations.station_id` with `on_delete = 'CASCADE'`. |
| **`PRAGMA database_list;`** | `SELECT * FROM pragma_database_list;` | `seq`, `name`, `file` | Displays the exact filesystem path of the `main` `.db` file and any `ATTACH`ed databases. |
| **`PRAGMA page_count;`** & **`PRAGMA freelist_count;`** | `SELECT * FROM pragma_page_count;` | Single integer | Total 4 KB pages in the database file vs. unused pages available for reuse before growing the file. |
| **`PRAGMA optimize;`** | — | Action (run before closing connection) | Inspects query planner usage and automatically runs `ANALYZE` (`sqlite_stat1`) **only** on tables/indexes whose row counts changed significantly during the session. |

#### 5.6 Side-by-Side Comparison: Three Real-World SQLite `PRAGMA` Profiles

```sql
-- ============================================================================
-- PROFILE 1: Interactive Day 1 Lab & GUI Session (weather_ops.db)
-- Prioritizes strict referential integrity, lock resilience, and inspection
-- ============================================================================
PRAGMA foreign_keys = ON;            -- Enforce FOREIGN KEY & ON DELETE CASCADE
PRAGMA busy_timeout = 5000;          -- Wait up to 5s if another terminal is writing
PRAGMA foreign_key_check;            -- Audit existing rows for FK violations
SELECT * FROM pragma_table_info('observations');

-- ============================================================================
-- PROFILE 2: Live Production Edge Weather Logger / Daemon + Dashboard Reader
-- Prioritizes concurrent reader/writer throughput + crash safety on flash/SSD
-- ============================================================================
PRAGMA journal_mode = WAL;           -- Persistent: concurrent readers + 1 writer
PRAGMA synchronous = NORMAL;         -- 100% corruption-safe in WAL mode without per-commit fsync stall
PRAGMA wal_autocheckpoint = 1000;    -- Auto-checkpoint every 1000 pages (~4 MB)
PRAGMA journal_size_limit = 67108864;-- Cap .db-wal file size on disk at 64 MiB after rewind
PRAGMA foreign_keys = ON;            -- Block invalid station_id inserts
PRAGMA busy_timeout = 5000;          -- Retry automatically on transient write contention
PRAGMA cache_size = -64000;          -- 64 MiB page cache in RAM
PRAGMA temp_store = MEMORY;          -- Keep sorting/window temp B-Trees in RAM
-- Always start write transactions with: BEGIN IMMEDIATE;
-- Before closing long-lived connection:
PRAGMA optimize;                     -- Refresh planner stats if table sizes grew
PRAGMA wal_checkpoint(TRUNCATE);     -- Optional: flush & truncate .db-wal on clean daemon shutdown

-- ============================================================================
-- PROFILE 3: Disposable Scratch Bulk-Seed Script (generate_weather_db.py)
-- Prioritizes raw 250,000-row generation speed (~2s); regenerate file on crash
-- ============================================================================
PRAGMA journal_mode = OFF;           -- Skip rollback journal I/O during initial seed
PRAGMA synchronous = OFF;            -- Skip OS fsync() barriers during batch load
PRAGMA cache_size = 100000;          -- 100,000 pages (~400 MB RAM) for fast index build
```

---


## PART II: Declarative SQL Execution Order, DDL & Three-Valued Logic (3VL)

### 1. Declarative Execution Order (The 8 Logical Phases)

SQL is not executed top-to-bottom. The query planner evaluates statements in eight distinct logical phases:

```
┌────────────────────────────────────────────────────────────────────────┐
│ 1. FROM & JOIN     Identify candidate relations & compute cross/joins  │
│ 2. WHERE           Filter raw rows from disk BEFORE memory allocation   │
│ 3. GROUP BY        Partition remaining rows into aggregated buckets    │
│ 4. HAVING          Filter aggregated buckets based on aggregate results │
│ 5. SELECT          Evaluate scalar expressions & assign column aliases  │
│ 6. DISTINCT        Sort/hash to remove duplicate row states             │
│ 7. ORDER BY        Sort output stream (can spill to disk/temp files)    │
│ 8. LIMIT / OFFSET  Slice row window returned to the client application  │
└────────────────────────────────────────────────────────────────────────┘
```

> **The Alias Trap:** You **cannot** use a `SELECT` column alias in `WHERE` or `GROUP BY` because Step 2 and Step 3 execute **before** Step 5 allocates the alias.
> ```sql
> -- FAILS (Step 2 doesn't know temp_f):
> SELECT station_id, (temperature * 1.8 + 32.0) AS temp_f
> FROM raw_telemetry
> WHERE temp_f > 85.0;
> 
> -- CORRECT (Repeat expression or wrap in a CTE):
> SELECT station_id, (temperature * 1.8 + 32.0) AS temp_f
> FROM raw_telemetry
> WHERE (temperature * 1.8 + 32.0) > 85.0;
> ```

---

### 2. DDL & Physical Meteorology Constraints (`NOT NULL` vs. `CHECK` vs. `NOT NULL CHECK`)

```sql
-- CRITICAL: SQLite disables Foreign Keys by default on every new connection!
-- Always run this first:
PRAGMA foreign_keys = ON;

CREATE TABLE stations (
    station_id   INTEGER PRIMARY KEY,               -- Natural key (5-digit WMO ID)
    station_name TEXT    NOT NULL UNIQUE,           -- Pattern 1: Mandatory presence + unique
    latitude     REAL    NOT NULL CHECK (latitude BETWEEN -90.0 AND 90.0),          -- Pattern 2: Mandatory + range
    longitude    REAL    NOT NULL CHECK (longitude BETWEEN -180.0 AND 180.0),       -- Pattern 2: Mandatory + range
    elevation_m  REAL    NOT NULL CHECK (elevation_m BETWEEN -500.0 AND 9000.0),
    climate_zone TEXT    NOT NULL CHECK (climate_zone IN ('Mediterranean', 'Arid', 'Semi-Arid', 'Highland', 'Maritime')),
    is_active    INTEGER NOT NULL DEFAULT 1 CHECK (is_active IN (0, 1))
);
```

#### The 4 Column Constraint Patterns (`NOT NULL` vs. `CHECK`)
* **`NOT NULL` enforces Presence (Existence):** Rejects `NULL`, but allows *any* value of that type (`-9999.0`, `145.0`, or empty string `''`).
* **`CHECK (expr)` enforces Domain Validity (Physics/Enums):** Rejects `FALSE`, **but silently allows `NULL`** because `NULL` evaluates to `UNKNOWN`, and `CHECK` only blocks `FALSE`!

| Pattern | SQL Syntax | Allows `NULL`? | Enforces Range / Enum? | When to Use | Example in `weather_ops.db` |
| :--- | :--- | :---: | :---: | :--- | :--- |
| **1. `NOT NULL` only** | `col TYPE NOT NULL` | ❌ No | ❌ No | Mandatory timestamp, ID, or unbounded metric where `NULL` is forbidden. | `obs_time TEXT NOT NULL`, `pred_temp_c REAL NOT NULL` |
| **2. `NOT NULL CHECK (...)`** | `col TYPE NOT NULL CHECK (...)` | ❌ No | ✅ Yes | Mandatory attribute that **must exist** AND **must obey physical bounds or an enum**. (`CHECK` alone is NOT enough to block `NULL`!) | `latitude`, `elevation_m`, `pred_wind_kt`, `qc_flag` |
| **3. Nullable + `CHECK`** | `col TYPE CHECK (col IS NULL OR (...))` | ✅ Yes | ✅ Yes (if not `NULL`) | Field sensor reading that can be `NULL` when offline, **but if reported**, must obey physics. (`IS NULL OR` makes nullability explicit and safe for `WHERE` clauses). | `humidity_pct` (`0–100%`), `wind_speed_kt` (`>= 0.0`) |
| **4. Raw Nullable (No `CHECK`)** | `col TYPE` | ✅ Yes | ❌ No | Raw/Bronze staging column that must ingest in-band hardware sentinels (`-9999.0`) or raw spikes (`68.5°C`) for downstream `NULLIF` / QC auditing. | `precip_1h_mm` (Day 1 raw `-9999.0`), `temp_c` |

> **The Empty-String Trap (`''` $\neq$ `NULL`):** `station_name TEXT NOT NULL` blocks `NULL` but allows `''`. To block both `NULL` and blank strings: `station_name TEXT NOT NULL CHECK (LENGTH(TRIM(station_name)) > 0)`.

---

### 3. Three-Valued Logic (3VL) & `NULL` Truth Tables

SQL implements Three-Valued Logic: `TRUE`, `FALSE`, and `UNKNOWN` (represented by `NULL`).

#### Logical Truth Matrix

| Condition $A$ | Condition $B$ | $A \text{ AND } B$ | $A \text{ OR } B$ | $\text{NOT } A$ |
| :--- | :--- | :--- | :--- | :--- |
| `TRUE` | `NULL` | `UNKNOWN` | `TRUE` | `FALSE` |
| `FALSE` | `NULL` | `FALSE` | `UNKNOWN` | `TRUE` |
| `NULL` | `NULL` | `UNKNOWN` | `UNKNOWN` | `UNKNOWN` |

#### Comparison Propagation & The `WHERE` vs. `CHECK` Asymmetry Gate
* `val = NULL` $\implies$ `UNKNOWN` (never evaluates to `TRUE`).
* `val != NULL` $\implies$ `UNKNOWN` (never evaluates to `TRUE`).
* `NULL = NULL` $\implies$ `UNKNOWN` (never evaluates to `TRUE`).
* **Always use** `IS NULL` or `IS NOT NULL`.

| 3VL Evaluation Result | `WHERE` / `HAVING` / `JOIN ON` Gate | `CHECK (...)` Constraint Gate | Why It Matters |
| :--- | :--- | :--- | :--- |
| **`TRUE`** | ✅ **Row Kept** | ✅ **Insert Allowed** | Valid data passes both filters and constraints |
| **`FALSE`** | ❌ **Row Discarded** | ❌ **Insert Rejected** | Violating data is blocked by both |
| **`UNKNOWN` (`NULL`)** | ❌ **Row Discarded** | ✅ **Insert ALLOWED!** | `CHECK (col >= 0)` **allows `NULL`!** Add `NOT NULL` if `NULL` must be rejected |

---

### 4. Aggregate Hygiene & Hardware Sentinel Handling (`NULL` vs. `-999.0` / `-9999.0`)

In SQL, **`NULL` means "missing/unknown"** and is **ignored** by `AVG()`, `MIN()`, `MAX()`, `SUM()`, and `COUNT(column)`. Legacy Fortran/WMO/datalogger codes like `-9999.0`, `-999.0`, or `9999.0` are treated as real numbers and corrupt averages!

#### Aggregate Function Behavior Matrix

| Aggregate | Behavior on `NULL` | Behavior on Sentinel (`-999.0` / `-9999.0`) |
| :--- | :--- | :--- |
| `COUNT(*)` | Counts the row regardless of column content | Counts the row |
| `COUNT(column)` | **Silently ignores `NULL`** | Counts the sentinel as a valid reading |
| `AVG(column)` | **Silently ignores `NULL`** | **Corrupts mean:** sums $-999.0$ / $-9999.0$ into accumulator |
| `MIN(column)` | **Silently ignores `NULL`** | **Returns** $-999.0$ / $-9999.0$ as absolute network minimum |
| `MAX(column)` | **Silently ignores `NULL`** | Returns sentinel if ADC shorts to `9999.0` |

#### Essential Null & Cleaning Functions

| SQL Function / Operator | Meteorological Example | What It Does |
| :--- | :--- | :--- |
| `IS NULL` / `IS NOT NULL` | `WHERE temp_c IS NOT NULL` | Correct way to filter missing sensor values (`= NULL` never works!) |
| `NULLIF(col, sentinel)` | `AVG(NULLIF(precip_1h_mm, -9999.0))` | Converts `-9999.0` to `NULL` on the fly so `AVG()` ignores it! |
| `COALESCE(col, fallback)` | `SUM(COALESCE(precip_1h_mm, 0.0))` | Replaces `NULL` with `0.0` when summing rainfall |
| `ROUND(expr, decimals)` | `ROUND(temp_c + 273.15, 2) AS temp_k` | Rounds floating-point calculations |

#### In-Flight & Permanent Sanitization Patterns

```sql
-- 1. Exact sentinel replacement in-flight with NULLIF
SELECT
    AVG(NULLIF(temperature, -999.0))    AS clean_aws_temp,
    AVG(NULLIF(precip_1h_mm, -9999.0))  AS clean_synoptic_rain
FROM raw_telemetry;

-- 2. Range-bound clamping with CASE WHEN (Handles sensor drift like -998.2 or 9999.0)
SELECT
    AVG(CASE 
        WHEN temperature BETWEEN -60.0 AND 60.0 THEN temperature 
        ELSE NULL 
    END) AS physical_mean_temp
FROM raw_telemetry;

-- 3. ANSI SQL / PostgreSQL Native FILTER clause (Supported in SQLite 3.30+ & PostgreSQL)
SELECT
    AVG(temperature) FILTER (WHERE temperature BETWEEN -60.0 AND 60.0) AS filtered_mean_temp
FROM raw_telemetry;

-- 4. Permanently clean sentinel values in a table via UPDATE:
UPDATE observations
SET precip_1h_mm = NULL
WHERE precip_1h_mm = -9999.0;
```

---

## PART III: Filtering, Classification, Temporal Bucketing & `JOIN` Verification

### 1. Operational Classification (`CASE WHEN`) & Climatological Rollups (`GROUP BY` / `HAVING`)

```sql
-- 1. Operational Wind Classification (Beaufort Categories via CASE WHEN)
SELECT
    station_id,
    obs_time,
    wind_speed_kt,
    CASE
        WHEN wind_speed_kt >= 34.0 THEN 'Gale Warning'
        WHEN wind_speed_kt >= 22.0 THEN 'Strong Wind'
        WHEN wind_speed_kt >= 10.0 THEN 'Moderate Wind'
        ELSE 'Light Breeze'
    END AS wind_category
FROM observations
WHERE wind_speed_kt IS NOT NULL
ORDER BY wind_speed_kt DESC;

-- 2. Daily Climatology Rollup + Sensor Uptime % (GROUP BY & HAVING)
SELECT
    station_id,
    DATE(obs_time)                                 AS obs_date,
    COUNT(*)                                       AS total_hours,
    COUNT(temp_c)                                  AS valid_temp_hours,
    ROUND(100.0 * COUNT(temp_c) / COUNT(*), 1)     AS sensor_uptime_pct,
    ROUND(MIN(temp_c), 1)                          AS tmin_c,
    ROUND(MAX(temp_c), 1)                          AS tmax_c,
    ROUND(AVG(temp_c), 1)                          AS tmean_c,
    ROUND(SUM(COALESCE(precip_1h_mm, 0.0)), 1)     AS daily_rain_mm
FROM observations
WHERE qc_flag = 'VALID'                            -- Filters rows BEFORE grouping (Step 2)
GROUP BY station_id, DATE(obs_time)                -- Partitions buckets (Step 3)
HAVING SUM(COALESCE(precip_1h_mm, 0.0)) > 10.0     -- Filters groups AFTER aggregation (Step 4)
ORDER BY daily_rain_mm DESC;
```

---

### 2. Synoptic Bucketing & Temporal Intervals (SQLite vs. PostgreSQL)

Raw pings arrive asynchronously. Telemetry must be aggregated into regular synoptic hours ($00:00, 01:00, \dots$).

| Task | SQLite Syntax | PostgreSQL Syntax (Day 2+) |
| :--- | :--- | :--- |
| **Hourly Bucket** | `strftime('%Y-%m-%d %H:00:00', recorded_at)` | `date_trunc('hour', recorded_at)` |
| **Daily Bucket** | `DATE(recorded_at)` or `strftime('%Y-%m-%d 00:00:00', recorded_at)` | `date_trunc('day', recorded_at)` |
| **Extract Hour** | `strftime('%H', obs_time)` | `EXTRACT(HOUR FROM obs_time)` |
| **Time Arithmetic** | `datetime(recorded_at, '+1 hour')` | `recorded_at + INTERVAL '1 hour'` |
| **Past 24 Hours** | `recorded_at >= datetime('now', '-24 hours')` | `recorded_at >= NOW() - INTERVAL '24 hours'` |
| **UTC Force** | `datetime(recorded_at, 'utc')` | `recorded_at AT TIME ZONE 'UTC'` |

---

### 3. Normalization (`1NF`–`3NF`) vs. Denormalization Quick Reference

| Pattern | Rule / Structure | Where We Use It in the Bootcamp | Key Trade-Off |
| :--- | :--- | :--- | :--- |
| **`1NF` (First Normal Form)** | Atomic scalar columns; no CSV strings (`'19.4,27.8'`) or repeating columns (`temp_00z`, `temp_06z`). | All SQL tables (`stations`, `observations`, `forecasts`). | Enables SQL indexing, `AVG()`, and `WHERE` filtering. |
| **`2NF` (Second Normal Form)** | `1NF` + no partial dependency on a composite key `(station_id, obs_time)`. | Splitting `stations` (depends only on `station_id`) from `observations` (depends on `station_id + obs_time`). | Eliminates **Insertion**, **Update**, and **Deletion** anomalies; saves `~68 bytes/row`. |
| **`3NF` (Third Normal Form)** | `2NF` + no transitive dependency (`non_key_A -> non_key_B`). | `day1/weather_ops.db` & `day2/weather_ops_pg.sql` (`synoptic.stations`, `synoptic.observations`). | Gold standard for **Row-Store OLTP** (`SQLite`, `PostgreSQL`). Requires `JOIN` on reads. |
| **Deliberate Denormalization (Pre-Joined / Embedded / Columnar)** | Intentionally duplicating attributes or pre-joining tables for read performance. | • **Day 3 PG:** `MATERIALIZED VIEW nwp.mv_daily_model_verification` + Covering Index `INCLUDE (temp_c)`<br>• **Day 4 Mongo:** Embedded `vertical_levels: [...]` array in `radiosonde_soundings`<br>• **Day 5 Parquet/DuckDB:** Wide flat Parquet files | • **Row Store (`SQLite`/`PG`):** Bloats disk if done on raw tables; safe via Materialized Views.<br>• **Columnar (`Parquet`):** **Dictionary Encoding + RLE** compresses repeated strings (`'Mediterranean'`) to near-zero bytes while eliminating `JOIN`s! |

---

### 4. SQL `JOIN` Compatibility Matrix (`SQLite < 3.39` vs. `3.39+` vs. `MySQL 8.0/8.4` vs. `PostgreSQL` vs. `DuckDB`)

> [!IMPORTANT]
> **Cross-Engine `JOIN` Boundaries (`SQLite < 3.39` & `MySQL 8.0/8.4`):**
> - **SQLite `< 3.39.0` (prior to July 2022):** Throws `Parse error: RIGHT and FULL OUTER JOINs are not currently supported`. Modern **SQLite `3.39.0+`** (Ubuntu 24.04 ships `3.45.x`) supports both natively, but embedded Linux dataloggers often run older SQLite versions.
> - **MySQL `8.0` / `8.4` (`InnoDB`):** Supports `RIGHT JOIN`, `LATERAL` (`8.0.14+`), and `Hash Join` (`8.0.18+`), **but still does NOT support native `FULL OUTER JOIN`**! The `LEFT JOIN ... UNION ALL ... LEFT JOIN WHERE IS NULL` rewrite below works identically on both **SQLite `< 3.39`** and **MySQL `8.0/8.4`** (see **[Reference Card 14: MySQL 8.0/8.4 & MariaDB Complete Engineering Guide](../reference_cards/14_mysql_and_mariadb_innodb_complete_engineering_guide.md)**).

| `JOIN` Type | SQLite `< 3.39` | SQLite `3.39+` | MySQL `8.0 / 8.4` | PostgreSQL 16 | DuckDB | Portable Emulation / Engine Note |
| :--- | :---: | :---: | :---: | :---: | :---: | :--- |
| **`INNER JOIN`** | ✅ | ✅ | ✅ | ✅ | ✅ | Returns only matching rows ($A \cap B$). |
| **`LEFT [OUTER] JOIN`** | ✅ | ✅ | ✅ | ✅ | ✅ | All left rows + matching right rows ($A \cup (A \cap B)$). |
| **`LEFT ANTI-JOIN`** | ✅ | ✅ | ✅ | ✅ | ✅ | `A LEFT JOIN B ON ... WHERE B.id IS NULL` ($A \setminus B$). |
| **`RIGHT [OUTER] JOIN`** | ❌ | ✅ | ✅ | ✅ | ✅ | **Portable `< 3.39` Rewrite:** Flip table order to `B LEFT JOIN A`. |
| **`FULL [OUTER] JOIN`** | ❌ | ✅ | ❌ | ✅ | ✅ | **Portable `< 3.39` & MySQL Rewrite:** `A LEFT JOIN B UNION ALL B LEFT JOIN A WHERE A.id IS NULL`. |
| **`CROSS JOIN`** | ✅ | ✅ | ✅ | ✅ | ✅ | Cartesian product ($M \times N$ rows; no `ON` clause). |
| **`SELF JOIN`** | ✅ | ✅ | ✅ | ✅ | ✅ | `FROM stations s1 JOIN stations s2 ON s1.climate_zone = s2.climate_zone AND s1.station_id < s2.station_id`. |
| **`LATERAL` Join** | ❌ | ❌ | ✅ *(8.0.14+)* | ✅ | ✅ | Correlated subquery per left row. In SQLite, use `ROW_NUMBER() OVER (PARTITION BY ...)` in a CTE. |
| **`ASOF JOIN`** | ❌ | ❌ | ❌ *(use `LATERAL`)* | ❌ *(use `LATERAL`)* | ✅ | Time-series nearest-timestamp match (`ON a.id = b.id AND a.ts >= b.ts`). |
| **Join Algorithms** | Nested Loop only | Nested Loop only | Nested Loop & Hash Join *(8.0.18+; no Merge Join)* | Nested Loop, Parallel Hash, Merge Join | Vectorized Hash & Merge Join | SQLite has no `Hash`/`Merge Join`; MySQL lacks `Sort-Merge Join`. |

---

### 5. All 7 Relational `JOIN` Recipes on `weather_ops.db`

```sql
-- 1. LEFT ANTI-JOIN (LEFT JOIN + IS NULL): Find silent/offline stations with 0 observations!
SELECT s.station_id, s.station_name, s.climate_zone, s.is_active
FROM stations s
LEFT JOIN observations o ON s.station_id = o.station_id
WHERE o.obs_id IS NULL;

-- 2. Multi-Column INNER JOIN + CTE: NWP Forecast Verification (Bias & MAE across ECMWF, GFS, AROME)
--    CRITICAL: Must join on BOTH station_id AND valid_time = obs_time to avoid a Cartesian product!
WITH pairs AS (
    SELECT
        f.model_name,
        (f.pred_temp_c - o.temp_c)     AS err_c,
        ABS(f.pred_temp_c - o.temp_c)  AS abs_err_c,
        (f.pred_wind_kt - o.wind_speed_kt)    AS wind_err_kt,
        ABS(f.pred_wind_kt - o.wind_speed_kt) AS wind_abs_err_kt
    FROM forecasts f
    INNER JOIN observations o
        ON f.station_id = o.station_id
       AND f.valid_time = o.obs_time
    WHERE o.temp_c IS NOT NULL
      AND o.wind_speed_kt IS NOT NULL
)
SELECT
    model_name,
    COUNT(*)                       AS n_verified,
    ROUND(AVG(err_c), 2)           AS mean_temp_bias_c,
    ROUND(AVG(abs_err_c), 2)       AS temp_mae_c,
    ROUND(AVG(wind_err_kt), 2)     AS mean_wind_bias_kt,
    ROUND(AVG(wind_abs_err_kt), 2) AS wind_mae_kt
FROM pairs
GROUP BY model_name
ORDER BY temp_mae_c ASC;

-- 3. RIGHT JOIN (SQLite 3.39+) & Portable < 3.39 LEFT JOIN Flip:
-- Native 3.39+: FROM weather_alerts a RIGHT JOIN stations s ON a.station_id = s.station_id
-- Portable:     FROM stations s LEFT JOIN weather_alerts a ON s.station_id = a.station_id

-- 4. FULL OUTER JOIN (SQLite 3.39+) vs Portable < 3.39 UNION ALL Emulation:
SELECT s.station_id, s.station_name, a.phenomenon, a.severity
FROM stations s
LEFT JOIN weather_alerts a ON s.station_id = a.station_id
UNION ALL
SELECT a.station_id, s.station_name, a.phenomenon, a.severity
FROM weather_alerts a
LEFT JOIN stations s ON a.station_id = s.station_id
WHERE s.station_id IS NULL;

-- 5. CROSS JOIN: Generate Expected (7 Stations x 3 NWP Models = 21 Pairs) Audit Grid
WITH models AS (SELECT 'ECMWF-HRES' AS model_name UNION ALL SELECT 'GFS' UNION ALL SELECT 'AROME')
SELECT s.station_id, s.station_name, m.model_name, COUNT(f.forecast_id) AS forecast_count
FROM stations s
CROSS JOIN models m
LEFT JOIN forecasts f ON f.station_id = s.station_id AND f.model_name = m.model_name
GROUP BY s.station_id, s.station_name, m.model_name
ORDER BY s.station_id, m.model_name;

-- 6. SELF JOIN: Compare Distinct Stations in the Same Climate Zone (s1.station_id < s2.station_id)
SELECT s1.climate_zone, s1.station_name AS station_a, s2.station_name AS station_b,
       ROUND(ABS(s1.elevation_m - s2.elevation_m), 1) AS elev_diff_m
FROM stations s1
INNER JOIN stations s2
    ON s1.climate_zone = s2.climate_zone
   AND s1.station_id < s2.station_id;
```

---

## PART IV: Common Table Expressions (CTEs), Recursive Grids & Window Functions

### 1. Multi-Stage CTE Pipeline Blueprint

Use CTEs (`WITH` clauses) to organize transformations as a linear Directed Acyclic Graph (DAG) instead of deeply nested subqueries:

```sql
WITH stage1_cleansed AS (
    -- Strip impossible hardware voltages and wire sentinels
    SELECT 
        station_id,
        recorded_at,
        temperature,
        pressure,
        wind_speed
    FROM raw_telemetry
    WHERE (temperature BETWEEN -60.0 AND 60.0 OR temperature IS NULL)
      AND (pressure BETWEEN 870.0 AND 1085.0 OR pressure IS NULL)
),
stage2_synoptic_hourly AS (
    -- Downsample high-frequency pings into 1-hour reporting bins
    SELECT 
        station_id,
        strftime('%Y-%m-%d %H:00:00', recorded_at) AS obs_hour,
        ROUND(AVG(temperature), 2) AS mean_temp,
        ROUND(AVG(pressure), 2) AS mean_pressure,
        ROUND(MAX(wind_speed), 2) AS peak_gust
    FROM stage1_cleansed
    GROUP BY station_id, obs_hour
)
SELECT * 
FROM stage2_synoptic_hourly
WHERE peak_gust >= 20.0
ORDER BY peak_gust DESC;
```

### 2. Gap Detection via Recursive Time Grid (`WITH RECURSIVE`)

A simple `GROUP BY` cannot report on hours where a station sent zero packets. Generate a continuous reference grid to spot communication blackouts:

```sql
WITH RECURSIVE timeline(slot) AS (
    SELECT datetime('2026-10-01 00:00:00')
    UNION ALL
    SELECT datetime(slot, '+1 hour')
    FROM timeline
    WHERE slot < datetime('2026-10-02 23:00:00')
)
SELECT 
    t.slot AS expected_timestamp,
    s.station_id,
    COUNT(r.recorded_at) AS packets_received,
    CASE 
        WHEN COUNT(r.recorded_at) = 0 THEN 'COMPLETE_BLACKOUT'
        WHEN COUNT(r.recorded_at) < 30 THEN 'PACKET_LOSS'
        ELSE 'NOMINAL'
    END AS telemetry_status
FROM timeline t
CROSS JOIN stations s
LEFT JOIN raw_telemetry r 
       ON strftime('%Y-%m-%d %H:00:00', r.recorded_at) = t.slot 
      AND r.station_id = s.station_id
GROUP BY t.slot, s.station_id;
```

---

### 3. Window Functions for Sensor Streams

Unlike `GROUP BY`, which collapses rows, **window functions preserve individual observation rows** while computing context across partitions.

#### Syntax Layout

$$
\text{FUNCTION}(\dots)\ \mathbf{OVER}\ (\mathbf{PARTITION\ BY}\ \text{station}\ \mathbf{ORDER\ BY}\ \text{time}\ [\mathbf{FRAME}])
$$

```
 ┌──────────────────────┬─────────────────────────────────────────────────┐
 │ Window Function      │ Telemetry Engineering Use Case                  │
 ├──────────────────────┼─────────────────────────────────────────────────┤
 │ LAG(col, n)          │ Fetch reading from n steps prior (tendency, ΔP) │
 │ LEAD(col, n)         │ Lookahead n steps for forward anomaly audits    │
 │ ROW_NUMBER()         │ Rank rows per partition to deduplicate latest   │
 │ RANK() / DENSE_RANK()│ Rank extreme weather records with tie handling  │
 │ AVG(col) OVER(...)   │ Moving average across physical/temporal frames  │
 └──────────────────────┴─────────────────────────────────────────────────┘
```

#### Sliding Frames: `ROWS` vs. `RANGE`

```sql
-- ROWS: Exact physical count of preceding rows
ROWS BETWEEN 4 PRECEDING AND CURRENT ROW

-- RANGE: Logical temporal offset (PostgreSQL)
RANGE BETWEEN INTERVAL '1 hour' PRECEDING AND CURRENT ROW

-- Centered Rolling Window (Microburst / spike baseline)
ROWS BETWEEN 2 PRECEDING AND 2 FOLLOWING
```

> **Warning:** If an instrument drops offline for 6 hours, `ROWS BETWEEN 4 PRECEDING` will traverse across the 6-hour gap and blend physically unrelated data. For irregular streams, use `RANGE` (PostgreSQL) or bucket into uniform intervals first.

---

### 4. Field-Ready Telemetry Window Recipes

#### Recipe 1: 3-Hour Barometric Tendency ($\Delta P$)
Detect approaching squall lines or frontal passages:
```sql
SELECT 
    station_id,
    recorded_at,
    pressure,
    LAG(pressure, 3) OVER (
        PARTITION BY station_id 
        ORDER BY recorded_at
    ) AS pressure_3step_prior,
    ROUND(pressure - LAG(pressure, 3) OVER (
        PARTITION BY station_id 
        ORDER BY recorded_at
    ), 2) AS barometric_tendency
FROM raw_telemetry
WHERE pressure > -900.0;
```

#### Recipe 2: Latest State Deduplication (`ROW_NUMBER()`)
Retrieve the single latest observation per station without correlated subqueries:
```sql
WITH indexed_stream AS (
    SELECT 
        station_id,
        recorded_at,
        temperature,
        pressure,
        wind_speed,
        ROW_NUMBER() OVER (
            PARTITION BY station_id 
            ORDER BY recorded_at DESC
        ) AS recency_rank
    FROM raw_telemetry
    WHERE temperature > -900.0
)
SELECT * 
FROM indexed_stream 
WHERE recency_rank = 1;
```

#### Recipe 3: Rolling 5-Point Wind Gust Smoother
Filter out single-ping turbulent noise:
```sql
SELECT 
    station_id,
    recorded_at,
    wind_speed,
    ROUND(AVG(wind_speed) OVER (
        PARTITION BY station_id 
        ORDER BY recorded_at 
        ROWS BETWEEN 4 PRECEDING AND CURRENT ROW
    ), 2) AS wind_sma5,
    MAX(wind_speed) OVER (
        PARTITION BY station_id 
        ORDER BY recorded_at 
        ROWS BETWEEN 4 PRECEDING AND CURRENT ROW
    ) AS peak_gust_5step
FROM raw_telemetry
WHERE wind_speed >= 0.0;
```

#### Recipe 4: Thermal Spike / Inversion Detector
Flag measurements deviating by $>6.0^\circ\text{C}$ from a centered moving window:
```sql
WITH baseline AS (
    SELECT 
        station_id,
        recorded_at,
        temperature,
        ROUND(AVG(temperature) OVER (
            PARTITION BY station_id 
            ORDER BY recorded_at 
            ROWS BETWEEN 2 PRECEDING AND 2 FOLLOWING
        ), 2) AS centered_mean
    FROM raw_telemetry
    WHERE temperature > -900.0
)
SELECT 
    station_id,
    recorded_at,
    temperature,
    centered_mean,
    ROUND(ABS(temperature - centered_mean), 2) AS anomaly_magnitude
FROM baseline
WHERE ABS(temperature - centered_mean) > 6.0
ORDER BY anomaly_magnitude DESC;
```

---

> **Navigation:** [🏠 Master README](../README.md) | [🌐 Interactive Portal](../bootcamp_portal.html) | [📚 Reference Cards](../reference_cards/README.md) | [📘 Day 1 Coursebook](day1_master_coursebook.md) | [⏭️ Day 2 Coursebook](../day2/day2_master_coursebook.md)

