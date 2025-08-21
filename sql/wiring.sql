-- 1) Create dim_date
CREATE TABLE IF NOT EXISTS dim_date (
  date_id    INTEGER PRIMARY KEY,   -- e.g., 20250701
  date_iso   TEXT NOT NULL,         -- 'YYYY-MM-DD'
  day_name   TEXT,                  -- 'Monday', ...
  is_weekend INTEGER,               -- 0/1
  season     TEXT                   -- e.g., 'Summer'
);

-- 2) Insert provided rows
INSERT OR IGNORE INTO dim_date (date_id, date_iso, day_name, is_weekend, season) VALUES
(20250701, '2025-07-01', 'Tuesday',   0, 'Summer'),
(20250702, '2025-07-02', 'Wednesday', 0, 'Summer'),
(20250703, '2025-07-03', 'Thursday',  0, 'Summer'),
(20250704, '2025-07-04', 'Friday',    0, 'Summer'),
(20250705, '2025-07-05', 'Saturday',  1, 'Summer'),
(20250706, '2025-07-06', 'Sunday',    1, 'Summer'),
(20250707, '2025-07-07', 'Monday',    0, 'Summer'),
(20250708, '2025-07-08', 'Tuesday',   0, 'Summer');

-- 3) Wire fact_visits to dim_date via YYYYMMDD integer
UPDATE fact_visits
SET date_id = CAST(STRFTIME('%Y%m%d', visit_date) AS INTEGER);

-- 4) Index for joins
CREATE INDEX IF NOT EXISTS idx_fact_visits_date_id ON fact_visits(date_id);

-- 5) Check: any visits without a matching date row? (should be zero)
SELECT COUNT(*) AS visits_without_date
FROM fact_visits v
LEFT JOIN dim_date d ON d.date_id = v.date_id
WHERE d.date_id IS NULL;

-- 6) Sanity check: daily visit counts
SELECT d.date_iso, d.day_name, d.is_weekend, COUNT(DISTINCT v.visit_id) AS daily_visits
FROM dim_date d
LEFT JOIN fact_visits v ON v.date_id = d.date_id
GROUP BY d.date_iso, d.day_name, d.is_weekend
ORDER BY d.date_iso;