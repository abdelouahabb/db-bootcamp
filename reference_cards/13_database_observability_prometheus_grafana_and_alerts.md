# Weather Database Observability & Monitoring Cheatsheet (Prometheus, Grafana & Meteorological Health Checks)

**Target Audience:** Weather Forecast & Meteorological Data Engineers  
**Bootcamp Context:** Monitoring **PostgreSQL** and **MongoDB** clusters in a 24/7 Meteorological Operations Center (Database Health + Synoptic Data Freshness)

---

> **Navigation:** [Bootcamp Home](../README.md) | [Reference Cards Index](./README.md) | [Interactive Portal](../bootcamp_portal.html)  
> **Card Sequence:** [⬅ Previous Card](./12_dbeaver_and_mongodb_compass_gui_workflows.md) | **Card 13 of 14** | [Next Card](./14_mysql_and_mariadb_innodb_complete_engineering_guide.md)

## Quick-Jump Table of Contents

- [1. The Two Layers of Monitoring in a Weather Center](#1-the-two-layers-of-monitoring-in-a-weather-center)
- [2. Layer 1: Database Engine Golden Signals & Alert Thresholds](#2-layer-1-database-engine-golden-signals--alert-thresholds)
  - [2.1 PostgreSQL Golden Signals (`postgres_exporter` / SQL)](#21-postgresql-golden-signals-postgres_exporter--sql)
  - [2.2 MongoDB Golden Signals (`mongodb_exporter` / `db.serverStatus()`)](#22-mongodb-golden-signals-mongodb_exporter--dbserverstatus)
- [3. Layer 2: Meteorological Data Freshness & Sensor Health SQL Queries](#3-layer-2-meteorological-data-freshness--sensor-health-sql-queries)
  - [Check 1: Silent / Late Synoptic Station Detector (Station Heartbeat Alert)](#31-check-1-silent--late-synoptic-station-detector-station-heartbeat-alert)
  - [Check 2: NWP Model Run Arrival Monitor (`ECMWF-HRES`, `GFS`, `AROME`)](#32-check-2-nwp-model-run-arrival-monitor-ecmwf-hres-gfs-arome)
  - [Check 3: Sensor Quality Control (`SUSPECT` / `ERRONEOUS`) Anomaly Rate](#33-check-3-sensor-quality-control-suspect--erroneous-anomaly-rate)
- [4. Equivalent MongoDB Telemetry Health Check (`mongosh` / Compass)](#4-equivalent-mongodb-telemetry-health-check-mongosh--compass)

---

## 1. The Two Layers of Monitoring in a Weather Center

In operational meteorology, monitoring CPU and disk space is not enough: a database server can have **10% CPU and 99.9% uptime**, yet the **00Z ECMWF ingestion pipeline failed silently** or **30 automated weather stations stopped transmitting**!

Every weather database dashboard (Grafana) must track **two layers**:
1. **Layer 1: Database Engine Golden Signals** (Connections, Buffer/WiredTiger Cache Hit Ratio, MVCC Dead Tuples, WAL/Oplog Rate, Standby Replication Lag).
2. **Layer 2: Meteorological Data Freshness & Quality Signals** (Station Heartbeat Lag, NWP Run Arrival Delay, and `SUSPECT`/`ERRONEOUS` QC Spike Rate).

---

## 2. Layer 1: Database Engine Golden Signals & Alert Thresholds

### 2.1 PostgreSQL Golden Signals (`postgres_exporter` / SQL)

| Metric | Healthy Target | Warning / Critical Threshold | Root Cause & Action in Weather Ops |
| :--- | :--- | :--- | :--- |
| **Buffer Cache Hit Ratio** | `> 99.0%` | `< 95%` | Hot synoptic tables/indexes don't fit in `shared_buffers`, or a forecaster is running unindexed `Seq Scan`s over multi-year tables. |
| **Dead Tuple Ratio (`n_dead_tup %`)** | `< 5%` | `> 15%` | Frequent QC flag `UPDATE`s or NWP deletes outpacing `autovacuum`. Lower `autovacuum_vacuum_scale_factor` to `0.01`. |
| **Standby Replication Lag** | `< 1 second` (`< 16 MB`) | `> 30 seconds` (`> 500 MB`) | Heavy `00Z`/`12Z` `COPY` load saturating network/disk, or long query blocking WAL replay on Standby. |
| **Inactive Replication Slots** | `0` inactive slots | Any `active = false` slot retaining `> 10 GB` WAL | Dead standby node holding a replication slot; will fill Primary's `$PGDATA/pg_wal` disk 100%! |
| **Active Backend Connections** | `< 70%` of `max_connections` | `> 85%` of `max_connections` | Station connection storm; route stations through `PgBouncer` (`pool_mode = transaction`). |
| **Transaction ID Age (`age(datfrozenxid)`)** | `< 200 Million` | `> 1 Billion` *(Wraparound limit is 2B)* | Long-running abandoned transaction preventing `autovacuum` from freezing old tuple `xmin` IDs! |

### 2.2 MongoDB Golden Signals (`mongodb_exporter` / `db.serverStatus()`)

| Metric | Healthy Target | Warning / Critical Threshold | Root Cause & Action in Weather Ops |
| :--- | :--- | :--- | :--- |
| **WiredTiger Cache Dirty %** | `< 5%` | `> 20%` (`eviction trigger`) | Disk I/O cannot keep up with incoming telemetry writes; check SSD latency or shard across more nodes. |
| **Replica Set Oplog Window** | `> 48 hours` | `< 12 hours` | If a Secondary goes down for maintenance overnight, an Oplog window `< 12h` forces a full multi-TB initial sync! Increase `oplogSizeMB`. |
| **Secondary Replication Lag** | `< 2 seconds` | `> 30 seconds` | Secondary disk bottleneck or unindexed operations. |
| **Query Targeting Ratio (`Examined / Returned`)** | `1 : 1` to `5 : 1` | `> 100 : 1` | Missing compound/multikey index (`COLLSCAN`); inspect `.explain("executionStats")` and apply the **ESR Rule**. |

---

## 3. Layer 2: Meteorological Data Freshness & Sensor Health SQL Queries

Add these 3 SQL queries directly as **Grafana Panels / Prometheus Custom Queries** (or `pg_cron` alerting checks) in your operations room:

### 3.1 Check 1: Silent / Late Synoptic Station Detector (Station Heartbeat Alert)
*Alerts whenever an active WMO station has not reported an observation in the last 2 hours:*

```sql
SELECT
    s.station_id,
    s.station_name,
    s.climate_zone,
    MAX(o.obs_time)                                           AS last_seen_utc,
    ROUND(EXTRACT(EPOCH FROM (NOW() - MAX(o.obs_time))) / 3600.0, 1) AS hours_silent,
    CASE
        WHEN MAX(o.obs_time) IS NULL THEN 'CRITICAL: NEVER REPORTED'
        WHEN NOW() - MAX(o.obs_time) > INTERVAL '3 hours' THEN 'CRITICAL: >3H SILENT'
        WHEN NOW() - MAX(o.obs_time) > INTERVAL '1 hour'  THEN 'WARNING: DELAYED'
        ELSE 'OK'
    END AS heartbeat_status
FROM synoptic.stations s
LEFT JOIN synoptic.observations o ON s.station_id = o.station_id
WHERE s.is_active = TRUE
GROUP BY s.station_id, s.station_name, s.climate_zone
HAVING MAX(o.obs_time) IS NULL OR NOW() - MAX(o.obs_time) > INTERVAL '1 hour'
ORDER BY hours_silent DESC NULLS FIRST;
```

### 3.2 Check 2: NWP Model Run Arrival Monitor (`ECMWF-HRES`, `GFS`, `AROME`)
*Verifies that the latest `00Z` / `12Z` model runs arrived on schedule and loaded the expected number of forecast rows:*

```sql
WITH latest_runs AS (
    SELECT model_name, MAX(init_time) AS latest_init_utc
    FROM nwp.forecasts
    GROUP BY model_name
)
SELECT
    f.model_name,
    l.latest_init_utc,
    COUNT(*)                   AS rows_in_latest_run,
    NOW() - l.latest_init_utc  AS age_of_latest_run
FROM nwp.forecasts f
INNER JOIN latest_runs l
    ON f.model_name = l.model_name
   AND f.init_time  = l.latest_init_utc
GROUP BY f.model_name, l.latest_init_utc
ORDER BY f.model_name;
```

### 3.3 Check 3: Sensor Quality Control (`SUSPECT` / `ERRONEOUS`) Anomaly Rate
*Alerts hardware technicians if a station's error rate exceeds 10% over the last 24 hours:*

```sql
SELECT
    s.station_id,
    s.station_name,
    COUNT(*)                                                  AS obs_last_24h,
    COUNT(*) FILTER (WHERE o.qc_flag != 'VALID')              AS flagged_obs,
    ROUND(
        100.0 * COUNT(*) FILTER (WHERE o.qc_flag != 'VALID') / NULLIF(COUNT(*), 0),
        1
    )                                                         AS anomaly_rate_pct
FROM synoptic.observations o
JOIN synoptic.stations s USING (station_id)
WHERE o.obs_time >= NOW() - INTERVAL '24 hours'
GROUP BY s.station_id, s.station_name
HAVING COUNT(*) FILTER (WHERE o.qc_flag != 'VALID') > 0
ORDER BY anomaly_rate_pct DESC;
```

---

## 4. Equivalent MongoDB Telemetry Health Check (`mongosh` / Compass)

Run this aggregation pipeline in MongoDB to detect stations with low battery voltage (`< 12.2V`), open enclosure doors, or delayed telemetry in `db.synoptic_timeseries`:

```javascript
db.synoptic_timeseries.aggregate([
  {
    $sort: { obs_time: -1 }
  },
  {
    $group: {
      _id: "$station_meta.station_id",
      station_type:    { $first: "$station_meta.station_type" },
      last_obs_utc:    { $first: "$obs_time" },
      latest_battery_v:{ $first: "$diagnostics.battery_v" },
      door_open_alert: { $max: "$diagnostics.door_open" }
    }
  },
  {
    $match: {
      $or: [
        { latest_battery_v: { $lt: 12.2 } },
        { door_open_alert: true }
      ]
    }
  },
  { $sort: { latest_battery_v: 1 } }
]);
```

---

### 4.1 Reference Library Navigation

> **Navigation:** [Bootcamp Home](../README.md) | [Reference Cards Index](./README.md) | [Interactive Portal](../bootcamp_portal.html)  
> **Card Sequence:** [⬅ Previous Card](./12_dbeaver_and_mongodb_compass_gui_workflows.md) | **Card 13 of 14** | [Next Card](./14_mysql_and_mariadb_innodb_complete_engineering_guide.md) | [⬆ Back to Top](#weather-database-observability--monitoring-cheatsheet-prometheus-grafana--meteorological-health-checks)
