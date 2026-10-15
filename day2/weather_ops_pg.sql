-- ============================================================================
-- DAY 2 BOOTCAMP: POSTGRESQL ARCHITECTURE & INTERNALS FOR WEATHER ENGINEERS
-- File: weather_ops_pg.sql
-- Usage: psql -U postgres -d weather_ops -f weather_ops_pg.sql
-- ============================================================================

-- 1. MULTI-SCHEMA ARCHITECTURE (Separating domains instead of dumping in 'public')
DROP SCHEMA IF EXISTS alerts CASCADE;
DROP SCHEMA IF EXISTS nwp CASCADE;
DROP SCHEMA IF EXISTS synoptic CASCADE;

CREATE SCHEMA synoptic;
CREATE SCHEMA nwp;
CREATE SCHEMA alerts;

-- Enforce mandatory meteorological UTC timezone & ISO-8601 date formatting
SET timezone = 'UTC';
SET datestyle = 'iso, ymd';

-- Set default search path for convenience
SET search_path TO synoptic, nwp, alerts, public;

-- 2. SYNOPTIC STATIONS TABLE (Strict PostgreSQL Types)
CREATE TABLE synoptic.stations (
    station_id   INTEGER PRIMARY KEY,               -- WMO 5-digit station ID
    station_name VARCHAR(100) NOT NULL UNIQUE,
    latitude     NUMERIC(7,4) NOT NULL CHECK (latitude BETWEEN -90.0 AND 90.0),
    longitude    NUMERIC(7,4) NOT NULL CHECK (longitude BETWEEN -180.0 AND 180.0),
    elevation_m  NUMERIC(6,1) NOT NULL CHECK (elevation_m BETWEEN -500.0 AND 9000.0),
    climate_zone VARCHAR(30)  NOT NULL CHECK (climate_zone IN ('Mediterranean', 'Arid', 'Semi-Arid', 'Highland', 'Maritime')),
    is_active    BOOLEAN      NOT NULL DEFAULT TRUE,
    raw_metadata TEXT                               -- Used to demonstrate TOAST storage for large payloads
);

-- 3. SYNOPTIC OBSERVATIONS TABLE (Using native TIMESTAMPTZ and NUMERIC)
CREATE TABLE synoptic.observations (
    obs_id         BIGSERIAL PRIMARY KEY,
    station_id     INTEGER      NOT NULL REFERENCES synoptic.stations(station_id) ON DELETE CASCADE,
    obs_time       TIMESTAMPTZ  NOT NULL,
    temp_c         NUMERIC(4,1),
    dewpoint_c     NUMERIC(4,1),
    humidity_pct   NUMERIC(4,1) CHECK (humidity_pct IS NULL OR (humidity_pct BETWEEN 0.0 AND 100.0)),
    pressure_hpa   NUMERIC(6,1),
    wind_speed_kt  NUMERIC(4,1) CHECK (wind_speed_kt IS NULL OR wind_speed_kt >= 0.0),
    precip_1h_mm   NUMERIC(5,1) CHECK (precip_1h_mm IS NULL OR precip_1h_mm >= 0.0),
    qc_flag        VARCHAR(15)  NOT NULL DEFAULT 'VALID' CHECK (qc_flag IN ('VALID', 'SUSPECT', 'ERRONEOUS')),
    raw_metar      TEXT,                            -- Optional raw METAR string
    UNIQUE (station_id, obs_time)
);

-- 4. NWP FORECASTS TABLE (In 'nwp' schema, using INTERVAL for lead time)
CREATE TABLE nwp.forecasts (
    forecast_id    BIGSERIAL PRIMARY KEY,
    station_id     INTEGER      NOT NULL REFERENCES synoptic.stations(station_id) ON DELETE CASCADE,
    model_name     VARCHAR(20)  NOT NULL CHECK (model_name IN ('ECMWF-HRES', 'GFS', 'AROME')),
    init_time      TIMESTAMPTZ  NOT NULL,
    lead_interval  INTERVAL     NOT NULL,
    valid_time     TIMESTAMPTZ  GENERATED ALWAYS AS (((init_time AT TIME ZONE 'UTC') + lead_interval) AT TIME ZONE 'UTC') STORED,
    pred_temp_c    NUMERIC(4,1) NOT NULL,
    pred_wind_kt   NUMERIC(4,1) NOT NULL CHECK (pred_wind_kt >= 0.0),
    pred_precip_mm NUMERIC(5,1) NOT NULL CHECK (pred_precip_mm >= 0.0)
);

-- 5. WEATHER ALERTS TABLE (In 'alerts' schema)
CREATE TABLE alerts.weather_alerts (
    alert_id    BIGSERIAL PRIMARY KEY,
    station_id  INTEGER     NOT NULL REFERENCES synoptic.stations(station_id) ON DELETE CASCADE,
    issued_at   TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    phenomenon  VARCHAR(30) NOT NULL CHECK (phenomenon IN ('HEATWAVE', 'HIGH_WIND', 'FLASH_FLOOD', 'SANDSTORM', 'FROST')),
    severity    VARCHAR(15) NOT NULL CHECK (severity IN ('YELLOW', 'ORANGE', 'RED')),
    message     TEXT        NOT NULL
);

-- ============================================================================
-- SEED DATA: WMO STATIONS
-- ============================================================================
INSERT INTO synoptic.stations (station_id, station_name, latitude, longitude, elevation_m, climate_zone, is_active, raw_metadata) VALUES
(60390, 'Algiers - Dar El Beida',  36.6910,  3.2154,   25.0, 'Mediterranean', TRUE,  REPEAT('WMO_CALIBRATION_HEADER_60390;', 200)),
(60490, 'Oran - Es Senia',         35.6239, -0.6212,   90.0, 'Mediterranean', TRUE,  'Standard synoptic AWS'),
(60419, 'Constantine - El Khroub', 36.2760,  6.6203,  694.0, 'Highland',      TRUE,  'Highland synoptic AWS'),
(60571, 'Bechar - Ouakda',         31.6457, -2.2699,  811.0, 'Arid',          TRUE,  'Desert synoptic AWS'),
(60680, 'Tamanrasset - Aguenar',   22.8115,  5.4510, 1377.0, 'Arid',          TRUE,  'High altitude desert AWS'),
(60531, 'Tlemcen - Zenata',        35.0167, -1.4500,  247.0, 'Semi-Arid',     TRUE,  'Semi-arid AWS'),
(60402, 'Bejaia - Soummam',        36.7120,  5.0699,    6.0, 'Mediterranean', FALSE, 'Coastal AWS under maintenance');

-- ============================================================================
-- SEED DATA: WEATHER ALERTS
-- ============================================================================
INSERT INTO alerts.weather_alerts (station_id, issued_at, phenomenon, severity, message) VALUES
(60390, '2026-10-05 21:00:00+00', 'FLASH_FLOOD', 'ORANGE', 'Heavy convective rainfall exceeding 15mm/h expected overnight.'),
(60419, '2026-10-05 20:30:00+00', 'FLASH_FLOOD', 'RED',    'Severe thunderstorm cell approaching Constantine; >20mm/h and 30kt+ gusts.'),
(60571, '2026-10-05 15:00:00+00', 'SANDSTORM',   'ORANGE', 'Strong SW winds (35-40 kt) reducing visibility below 500m.'),
(60680, '2026-10-05 10:00:00+00', 'HEATWAVE',    'YELLOW', 'Afternoon temperatures exceeding 36°C at high elevation.');

-- ============================================================================
-- SEED DATA: GENERATE 15,000+ REALISTIC HOURLY SYNOPTIC OBSERVATIONS
-- Uses PostgreSQL generate_series() to populate enough 8KB pages for
-- MVCC, VACUUM, WAL, and EXPLAIN (ANALYZE, BUFFERS) architecture labs!
-- ============================================================================
INSERT INTO synoptic.observations (
    station_id, obs_time, temp_c, dewpoint_c, humidity_pct,
    pressure_hpa, wind_speed_kt, precip_1h_mm, qc_flag, raw_metar
)
SELECT
    s.station_id,
    ts AS obs_time,
    ROUND((22.0 + (s.latitude - 30.0) * -0.5 + 6.0 * SIN(EXTRACT(EPOCH FROM ts) / 86400.0 * 2 * PI()) + (RANDOM() * 2.0 - 1.0))::NUMERIC, 1) AS temp_c,
    ROUND((12.0 + (RANDOM() * 3.0 - 1.5))::NUMERIC, 1) AS dewpoint_c,
    ROUND((45.0 + (RANDOM() * 40.0))::NUMERIC, 1)      AS humidity_pct,
    ROUND((1013.2 + 5.0 * COS(EXTRACT(EPOCH FROM ts) / 259200.0) + (RANDOM() * 1.5))::NUMERIC, 1) AS pressure_hpa,
    ROUND((8.0 + (RANDOM() * 20.0))::NUMERIC, 1)       AS wind_speed_kt,
    CASE WHEN RANDOM() > 0.88 THEN ROUND((RANDOM() * 12.0)::NUMERIC, 1) ELSE 0.0 END AS precip_1h_mm,
    CASE WHEN RANDOM() > 0.96 THEN 'SUSPECT' ELSE 'VALID' END AS qc_flag,
    'METAR DAAG ' || TO_CHAR(ts, 'DDHH24MI') || 'Z AUTO 28012KT 9999 FEW030'
FROM synoptic.stations s
CROSS JOIN generate_series(
    '2026-06-01 00:00:00+00'::TIMESTAMPTZ,
    '2026-10-06 23:00:00+00'::TIMESTAMPTZ,
    INTERVAL '1 hour'
) AS ts
WHERE s.is_active = TRUE;

-- ============================================================================
-- SEED DATA: GENERATE NWP FORECASTS FOR VERIFICATION & PLANNER LABS
-- ============================================================================
INSERT INTO nwp.forecasts (
    station_id, model_name, init_time, lead_interval,
    pred_temp_c, pred_wind_kt, pred_precip_mm
)
SELECT
    o.station_id,
    m.model_name,
    o.obs_time - INTERVAL '12 hours' AS init_time,
    INTERVAL '12 hours'              AS lead_interval,
    ROUND((o.temp_c + (RANDOM() * 2.4 - 1.0))::NUMERIC, 1)       AS pred_temp_c,
    ROUND(GREATEST(0.0, o.wind_speed_kt + (RANDOM() * 4.0 - 2.0))::NUMERIC, 1) AS pred_wind_kt,
    o.precip_1h_mm                                               AS pred_precip_mm
FROM synoptic.observations o
CROSS JOIN (VALUES ('ECMWF-HRES'), ('GFS'), ('AROME')) AS m(model_name)
WHERE EXTRACT(HOUR FROM o.obs_time) IN (0, 12);

-- ============================================================================
-- TABLE-LEVEL AUTOVACUUM TUNING FOR HIGH-CHURN METEOROLOGICAL TABLES
-- Prevents dead tuple bloat from frequent QC updates & rolling NWP purges
-- ============================================================================
ALTER TABLE synoptic.observations SET (
    autovacuum_vacuum_scale_factor  = 0.01,
    autovacuum_vacuum_threshold     = 1000,
    autovacuum_analyze_scale_factor = 0.005
);

ALTER TABLE nwp.forecasts SET (
    autovacuum_vacuum_scale_factor  = 0.02,
    autovacuum_vacuum_threshold     = 1000,
    autovacuum_analyze_scale_factor = 0.01
);

-- Refresh planner statistics
ANALYZE;
