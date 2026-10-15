-- ============================================================================
-- DAY 1 BOOTCAMP: SQL FUNDAMENTALS FOR WEATHER FORECAST ENGINEERS (SQLite)
-- File: weather_ops_seed.sql
-- Usage: sqlite3 weather_ops.db < weather_ops_seed.sql
-- ============================================================================

PRAGMA foreign_keys = ON;

DROP TABLE IF EXISTS weather_alerts;
DROP TABLE IF EXISTS forecasts;
DROP TABLE IF EXISTS observations;
DROP TABLE IF EXISTS stations;

-- 1. STATIONS TABLE (WMO Surface Synoptic Stations)
CREATE TABLE stations (
    station_id   INTEGER PRIMARY KEY,               -- WMO 5-digit station identifier
    station_name TEXT    NOT NULL UNIQUE,           -- Official station name
    latitude     REAL    NOT NULL CHECK (latitude BETWEEN -90.0 AND 90.0),
    longitude    REAL    NOT NULL CHECK (longitude BETWEEN -180.0 AND 180.0),
    elevation_m  REAL    NOT NULL CHECK (elevation_m >= -500.0 AND elevation_m <= 9000.0),
    climate_zone TEXT    NOT NULL CHECK (climate_zone IN ('Mediterranean', 'Arid', 'Semi-Arid', 'Highland', 'Maritime')),
    is_active    INTEGER NOT NULL DEFAULT 1 CHECK (is_active IN (0, 1))
);

-- 2. OBSERVATIONS TABLE (Hourly Synoptic Surface Readings)
CREATE TABLE observations (
    obs_id         INTEGER PRIMARY KEY AUTOINCREMENT,
    station_id     INTEGER NOT NULL,
    obs_time       TEXT    NOT NULL,                -- ISO-8601 UTC: YYYY-MM-DD HH:MM:SS
    temp_c         REAL,                            -- 2m Air Temperature (°C); NULL if sensor offline
    dewpoint_c     REAL,                            -- 2m Dewpoint Temperature (°C)
    humidity_pct   REAL    CHECK (humidity_pct IS NULL OR (humidity_pct >= 0.0 AND humidity_pct <= 100.0)),
    pressure_hpa   REAL,                            -- Mean Sea Level Pressure (hPa)
    wind_speed_kt  REAL    CHECK (wind_speed_kt IS NULL OR wind_speed_kt >= 0.0),
    precip_1h_mm   REAL,                            -- 1h Precipitation (mm) - includes legacy -9999.0 in raw rows for cleaning lab!
    qc_flag        TEXT    NOT NULL DEFAULT 'VALID' CHECK (qc_flag IN ('VALID', 'SUSPECT', 'ERRONEOUS')),
    FOREIGN KEY (station_id) REFERENCES stations(station_id) ON DELETE CASCADE,
    UNIQUE (station_id, obs_time)
);

-- 3. FORECASTS TABLE (Numerical Weather Prediction - NWP Model Output)
CREATE TABLE forecasts (
    forecast_id    INTEGER PRIMARY KEY AUTOINCREMENT,
    station_id     INTEGER NOT NULL,
    model_name     TEXT    NOT NULL CHECK (model_name IN ('ECMWF-HRES', 'GFS', 'AROME')),
    init_time      TEXT    NOT NULL,                -- Model initialization UTC (e.g., 2026-10-05 00:00:00)
    valid_time     TEXT    NOT NULL,                -- Forecast target valid UTC
    lead_hours     INTEGER NOT NULL CHECK (lead_hours >= 0),
    pred_temp_c    REAL    NOT NULL,
    pred_wind_kt   REAL    NOT NULL CHECK (pred_wind_kt >= 0.0),
    pred_precip_mm REAL    NOT NULL CHECK (pred_precip_mm >= 0.0),
    FOREIGN KEY (station_id) REFERENCES stations(station_id) ON DELETE CASCADE
);

-- 4. WEATHER ALERTS TABLE (Operational Warnings)
CREATE TABLE weather_alerts (
    alert_id    INTEGER PRIMARY KEY AUTOINCREMENT,
    station_id  INTEGER NOT NULL,
    issued_at   TEXT    NOT NULL,
    phenomenon  TEXT    NOT NULL CHECK (phenomenon IN ('HEATWAVE', 'HIGH_WIND', 'FLASH_FLOOD', 'SANDSTORM', 'FROST')),
    severity    TEXT    NOT NULL CHECK (severity IN ('YELLOW', 'ORANGE', 'RED')),
    message     TEXT    NOT NULL,
    FOREIGN KEY (station_id) REFERENCES stations(station_id) ON DELETE CASCADE
);

-- ============================================================================
-- SEED DATA: WMO STATIONS
-- ============================================================================
INSERT INTO stations (station_id, station_name, latitude, longitude, elevation_m, climate_zone, is_active) VALUES
(60390, 'Algiers - Dar El Beida', 36.6910,  3.2154,   25.0, 'Mediterranean', 1),
(60490, 'Oran - Es Senia',        35.6239, -0.6212,   90.0, 'Mediterranean', 1),
(60419, 'Constantine - El Khroub',36.2760,  6.6203,  694.0, 'Highland',      1),
(60571, 'Bechar - Ouakda',        31.6457, -2.2699,  811.0, 'Arid',          1),
(60680, 'Tamanrasset - Aguenar',  22.8115,  5.4510, 1377.0, 'Arid',          1),
(60531, 'Tlemcen - Zenata',       35.0167, -1.4500,  247.0, 'Semi-Arid',     1),
(60402, 'Bejaia - Soummam',       36.7120,  5.0699,    6.0, 'Mediterranean', 0); -- Station under maintenance (0 observations)

-- ============================================================================
-- SEED DATA: SYNOPTIC OBSERVATIONS (2026-10-05 & 2026-10-06)
-- Includes realistic meteorology, a NULL sensor dropout, and a legacy -9999.0 sentinel value
-- ============================================================================
INSERT INTO observations (station_id, obs_time, temp_c, dewpoint_c, humidity_pct, pressure_hpa, wind_speed_kt, precip_1h_mm, qc_flag) VALUES
-- Algiers (60390)
(60390, '2026-10-05 06:00:00', 19.4, 15.2, 77.0, 1016.2,  8.0,  0.0, 'VALID'),
(60390, '2026-10-05 12:00:00', 27.8, 16.0, 48.0, 1015.0, 14.0,  0.0, 'VALID'),
(60390, '2026-10-05 18:00:00', 23.1, 17.5, 71.0, 1013.8, 19.0,  2.4, 'VALID'),
(60390, '2026-10-06 00:00:00', 18.5, 16.8, 90.0, 1011.5, 28.0, 18.6, 'VALID'),
(60390, '2026-10-06 06:00:00', 17.9, 16.1, 89.0, 1012.0, 22.0,  6.2, 'VALID'),
(60390, '2026-10-06 12:00:00', 24.6, 15.0, 55.0, 1014.4, 11.0,  0.0, 'VALID'),

-- Oran (60490)
(60490, '2026-10-05 06:00:00', 20.1, 16.0, 77.0, 1015.8, 10.0,  0.0, 'VALID'),
(60490, '2026-10-05 12:00:00', 29.5, 14.2, 39.0, 1014.1, 16.0,  0.0, 'VALID'),
(60490, '2026-10-05 18:00:00', 24.8, 16.5, 60.0, 1013.0, 21.0,  0.4, 'VALID'),
(60490, '2026-10-06 00:00:00', 20.2, 15.9, 76.0, 1013.5, 15.0,  1.2, 'VALID'),
(60490, '2026-10-06 06:00:00', NULL, NULL, NULL, 1014.2, 12.0,  0.0, 'SUSPECT'),   -- Thermohygrometer dropout (NULL)
(60490, '2026-10-06 12:00:00', 26.3, 14.8, 49.0, 1015.6, 13.0,  0.0, 'VALID'),

-- Constantine (60419)
(60419, '2026-10-05 06:00:00', 14.2,  9.8, 75.0, 1017.1,  6.0,  0.0, 'VALID'),
(60419, '2026-10-05 12:00:00', 25.0, 10.5, 40.0, 1015.4, 12.0,  0.0, 'VALID'),
(60419, '2026-10-05 18:00:00', 19.6, 12.0, 61.0, 1014.0, 25.0,  8.5, 'VALID'),
(60419, '2026-10-06 00:00:00', 15.1, 13.5, 90.0, 1012.2, 34.0, 24.0, 'VALID'),
(60419, '2026-10-06 06:00:00', 13.8, 12.1, 89.0, 1013.1, 18.0,  4.1, 'VALID'),
(60419, '2026-10-06 12:00:00', 21.4, 11.2, 52.0, 1015.0, 10.0, -9999.0, 'SUSPECT'), -- Legacy -9999.0 rain gauge code!

-- Bechar (60571)
(60571, '2026-10-05 06:00:00', 22.0,  4.5, 32.0, 1013.0, 15.0,  0.0, 'VALID'),
(60571, '2026-10-05 12:00:00', 35.8,  5.2, 15.0, 1011.2, 28.0,  0.0, 'VALID'),
(60571, '2026-10-05 18:00:00', 31.4,  6.0, 20.0, 1010.5, 38.0,  0.0, 'VALID'),
(60571, '2026-10-06 00:00:00', 25.2,  6.8, 31.0, 1011.8, 22.0,  0.0, 'VALID'),
(60571, '2026-10-06 06:00:00', 21.5,  7.1, 39.0, 1012.9, 14.0,  0.0, 'VALID'),
(60571, '2026-10-06 12:00:00', 68.5,  5.0, 10.0, 1012.0, 16.0,  0.0, 'ERRONEOUS'), -- Corrupted temperature spike!

-- Tamanrasset (60680)
(60680, '2026-10-05 06:00:00', 23.5,  2.1, 24.0, 1014.5,  9.0,  0.0, 'VALID'),
(60680, '2026-10-05 12:00:00', 36.9,  3.0, 12.0, 1012.8, 18.0,  0.0, 'VALID'),
(60680, '2026-10-05 18:00:00', 32.1,  3.5, 16.0, 1012.1, 14.0,  0.0, 'VALID'),
(60680, '2026-10-06 00:00:00', 26.0,  4.0, 24.0, 1013.4,  8.0,  0.0, 'VALID'),
(60680, '2026-10-06 06:00:00', 24.1,  3.8, 26.0, 1014.8, 11.0,  0.0, 'VALID'),
(60680, '2026-10-06 12:00:00', 37.4,  2.9, 11.0, 1013.0, 17.0,  0.0, 'VALID'),

-- Tlemcen (60531)
(60531, '2026-10-05 06:00:00', 17.5, 13.0, 75.0, 1016.0,  7.0,  0.0, 'VALID'),
(60531, '2026-10-05 12:00:00', 28.2, 13.5, 40.0, 1014.5, 13.0,  0.0, 'VALID'),
(60531, '2026-10-05 18:00:00', 22.9, 14.8, 60.0, 1013.9, 15.0,  0.0, 'VALID'),
(60531, '2026-10-06 00:00:00', 18.0, 14.2, 78.0, 1014.1, 10.0,  0.5, 'VALID'),
(60531, '2026-10-06 06:00:00', 16.8, 13.6, 81.0, 1014.9,  8.0,  0.0, 'VALID'),
(60531, '2026-10-06 12:00:00', 25.9, 13.0, 45.0, 1015.8, 12.0,  0.0, 'VALID');

-- ============================================================================
-- SEED DATA: NWP FORECASTS (Initialized 2026-10-05 00:00:00 UTC)
-- Models: ECMWF-HRES, GFS, AROME
-- ============================================================================
INSERT INTO forecasts (station_id, model_name, init_time, valid_time, lead_hours, pred_temp_c, pred_wind_kt, pred_precip_mm) VALUES
-- Algiers (60390) forecasts
(60390, 'ECMWF-HRES', '2026-10-05 00:00:00', '2026-10-05 12:00:00', 12, 27.5, 15.0,  0.0),
(60390, 'ECMWF-HRES', '2026-10-05 00:00:00', '2026-10-06 00:00:00', 24, 18.8, 26.0, 16.5),
(60390, 'ECMWF-HRES', '2026-10-05 00:00:00', '2026-10-06 12:00:00', 36, 24.2, 12.0,  0.2),
(60390, 'GFS',        '2026-10-05 00:00:00', '2026-10-05 12:00:00', 12, 29.1, 17.0,  0.0),
(60390, 'GFS',        '2026-10-05 00:00:00', '2026-10-06 00:00:00', 24, 19.9, 22.0, 11.0),
(60390, 'GFS',        '2026-10-05 00:00:00', '2026-10-06 12:00:00', 36, 25.8, 14.0,  0.0),
(60390, 'AROME',      '2026-10-05 00:00:00', '2026-10-05 12:00:00', 12, 27.9, 14.0,  0.0),
(60390, 'AROME',      '2026-10-05 00:00:00', '2026-10-06 00:00:00', 24, 18.4, 29.0, 19.2),
(60390, 'AROME',      '2026-10-05 00:00:00', '2026-10-06 12:00:00', 36, 24.5, 11.0,  0.0),

-- Constantine (60419) forecasts
(60419, 'ECMWF-HRES', '2026-10-05 00:00:00', '2026-10-05 12:00:00', 12, 24.8, 13.0,  0.0),
(60419, 'ECMWF-HRES', '2026-10-05 00:00:00', '2026-10-06 00:00:00', 24, 15.5, 31.0, 21.0),
(60419, 'ECMWF-HRES', '2026-10-05 00:00:00', '2026-10-06 12:00:00', 36, 21.0, 11.0,  0.5),
(60419, 'GFS',        '2026-10-05 00:00:00', '2026-10-05 12:00:00', 12, 26.4, 15.0,  0.0),
(60419, 'GFS',        '2026-10-05 00:00:00', '2026-10-06 00:00:00', 24, 16.8, 25.0, 14.5),
(60419, 'GFS',        '2026-10-05 00:00:00', '2026-10-06 12:00:00', 36, 22.9, 13.0,  0.0),
(60419, 'AROME',      '2026-10-05 00:00:00', '2026-10-05 12:00:00', 12, 25.1, 12.0,  0.0),
(60419, 'AROME',      '2026-10-05 00:00:00', '2026-10-06 00:00:00', 24, 15.0, 35.0, 25.4),
(60419, 'AROME',      '2026-10-05 00:00:00', '2026-10-06 12:00:00', 36, 21.3, 10.0,  0.0),

-- Bechar (60571) forecasts
(60571, 'ECMWF-HRES', '2026-10-05 00:00:00', '2026-10-05 12:00:00', 12, 35.5, 27.0,  0.0),
(60571, 'ECMWF-HRES', '2026-10-05 00:00:00', '2026-10-06 00:00:00', 24, 25.0, 21.0,  0.0),
(60571, 'GFS',        '2026-10-05 00:00:00', '2026-10-05 12:00:00', 12, 37.2, 30.0,  0.0),
(60571, 'GFS',        '2026-10-05 00:00:00', '2026-10-06 00:00:00', 24, 26.8, 24.0,  0.0);

-- ============================================================================
-- SEED DATA: WEATHER ALERTS
-- ============================================================================
INSERT INTO weather_alerts (station_id, issued_at, phenomenon, severity, message) VALUES
(60390, '2026-10-05 21:00:00', 'FLASH_FLOOD', 'ORANGE', 'Heavy convective rainfall exceeding 15mm/h expected overnight.'),
(60419, '2026-10-05 20:30:00', 'FLASH_FLOOD', 'RED',    'Severe thunderstorm cell approaching Constantine; >20mm/h and 30kt+ gusts.'),
(60571, '2026-10-05 15:00:00', 'SANDSTORM',   'ORANGE', 'Strong SW winds (35-40 kt) reducing visibility below 500m.'),
(60680, '2026-10-05 10:00:00', 'HEATWAVE',    'YELLOW', 'Afternoon temperatures exceeding 36°C at high elevation.');
