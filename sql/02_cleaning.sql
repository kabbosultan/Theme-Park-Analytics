--Cleaning
--A
--SELECT * FROM fact_visits; (Confirming if total_spend_cents has been created)
--SELECT * FROM fact_purchases; (Confirming if amount_cents_clean has been created)

-- Visits: compute cleaned once, join by rowid, update when cleaned is non-empty
WITH c AS (
  SELECT
    rowid AS rid,
    REPLACE(REPLACE(REPLACE(REPLACE(UPPER(COALESCE(total_spend_cents,'')),
      'USD',''), '$',''), ',', ''), ' ', '') AS cleaned
  FROM fact_visits
)
UPDATE fact_visits
SET spend_cents_clean = CAST((SELECT cleaned FROM c WHERE c.rid = fact_visits.rowid) AS INTEGER)
WHERE LENGTH((SELECT cleaned FROM c WHERE c.rid = fact_visits.rowid)) > 0;

-- Purchases: same pattern for the fact_purchases table
WITH c AS (
  SELECT
    rowid AS rid,
    REPLACE(REPLACE(REPLACE(REPLACE(UPPER(COALESCE(amount_cents,'')),
      'USD',''), '$',''), ',', ''), ' ', '') AS cleaned
  FROM fact_purchases
)
UPDATE fact_purchases
SET amount_cents_clean = CAST((SELECT cleaned FROM c WHERE c.rid = fact_purchases.rowid) AS INTEGER)
WHERE LENGTH((SELECT cleaned FROM c WHERE c.rid = fact_purchases.rowid)) > 0;

-- Convert cents to dollars for reporting (since both tables store amounts in cents)
SELECT 
  visit_id,
  spend_cents_clean,
  ROUND(spend_cents_clean / 100.0, 2) AS spend_dollars
FROM fact_visits 
WHERE spend_cents_clean IS NOT NULL
LIMIT 5;

SELECT 
  purchase_id,
  amount_cents_clean,
  ROUND(amount_cents_clean / 100.0, 2) AS amount_dollars
FROM fact_purchases 
WHERE amount_cents_clean IS NOT NULL
LIMIT 5;

-- Standardize Pirate Splash variants
UPDATE dim_attraction
SET attraction_name = 'Pirate Splash'
WHERE UPPER(TRIM(attraction_name)) IN ('PIRATE SPLASH', 'PIRATE SPLASH!', 'PIRATE SPLASH !!');

-- Standardize Galaxy Coaster variants by capitalizing it properly
UPDATE dim_attraction
SET attraction_name = 'Galaxy Coaster'
WHERE UPPER(TRIM(attraction_name)) = 'GALAXY COASTER';

--B
WITH d AS (
  SELECT
    attraction_id, visit_id, ride_time, wait_minutes, satisfaction_rating, photo_purchase,
    COUNT(*) AS cnt
  FROM fact_ride_events
  GROUP BY attraction_id, visit_id, ride_time, wait_minutes, satisfaction_rating, photo_purchase
  HAVING COUNT(*) > 1
)
SELECT
  COUNT(*) AS duplicate_groups,
  COALESCE(SUM(cnt - 1), 0) AS duplicate_rows_to_remove
FROM d;


--Number of Duplicate groups: 8
SELECT
  attraction_id, visit_id, ride_time, wait_minutes, satisfaction_rating, photo_purchase,
  COUNT(*) AS dup_count
FROM fact_ride_events
GROUP BY attraction_id, visit_id, ride_time, wait_minutes, satisfaction_rating, photo_purchase
HAVING COUNT(*) > 1
ORDER BY dup_count DESC, attraction_id, visit_id, ride_time;

-- Rationale:
--   We keep exactly one row per duplicate group. Since ride_event_id is a monotonically increasing surrogate key,
--   the row with the smallest rowid (or smallest ride_event_id) is treated as the canonical/original record.
--   This is reproducible, simple, and avoids bias because the records are otherwise identical by definition.

-- Merge duplicate attraction_ids for 'Pirate Splash'
-- We keep attraction_id = 2 and merge attraction_id = 7 into it

-- Update all fact tables to use attraction_id = 2 for Pirate Splash
UPDATE fact_ride_events
SET attraction_id = 2
WHERE attraction_id = 7;


-- Delete the duplicate from dim_attraction (keep only one Pirate Splash)
DELETE FROM dim_attraction
WHERE attraction_id = 7
  AND attraction_name = 'Pirate Splash';
DELETE FROM fact_ride_events
WHERE rowid NOT IN (
  SELECT MIN(rowid)
  FROM fact_ride_events
  GROUP BY attraction_id, visit_id, ride_time, wait_minutes, satisfaction_rating, photo_purchase
);

-- Post-delete verification (returns 0)
SELECT COUNT(*) AS duplicate_groups_after
FROM (
  SELECT attraction_id, visit_id, ride_time, wait_minutes, satisfaction_rating, photo_purchase,
         COUNT(*) AS cnt
  FROM fact_ride_events
  GROUP BY attraction_id, visit_id, ride_time, wait_minutes, satisfaction_rating, photo_purchase
  HAVING COUNT(*) > 1
);

--Finding the Galaxy Coaster IDs
SELECT attraction_id, attraction_name FROM dim_attraction WHERE attraction_name = 'Galaxy Coaster';

-- Update all fact tables to use attraction_id = 1 for Galaxy Coaster
UPDATE fact_ride_events
SET attraction_id = 1  
WHERE attraction_id = 6;

-- Delete the duplicate from dim_attraction (keep only one Galaxy Coaster)
DELETE FROM dim_attraction
WHERE attraction_id = 6;

--C
-- Orphan visits: guest_id not in dim_guest (should be zero)
--The query returns 0 so no orphans were found and no action needs to be taken
SELECT COUNT(v.visit_id), COUNT(v.guest_id)
FROM fact_visits v
LEFT JOIN dim_guest g ON g.guest_id = v.guest_id
WHERE g.guest_id IS NULL;

--No orphans found. No action required.
SELECT COUNT(v.visit_id), COUNT(v.ticket_type_id)
FROM fact_visits v
LEFT JOIN dim_ticket t ON t.ticket_type_id = v.ticket_type_id
WHERE t.ticket_type_id IS NULL;

--No orphans found. No action required.
SELECT COUNT(v.visit_id), COUNT(v.date_id)
FROM fact_visits v
LEFT JOIN dim_date d ON d.date_id = v.date_id
WHERE v.date_id IS NOT NULL AND d.date_id IS NULL;

--No orphans found. No action required.
SELECT COUNT(e.ride_event_id), COUNT(e.visit_id)
FROM fact_ride_events e
LEFT JOIN fact_visits v ON v.visit_id = e.visit_id
WHERE v.visit_id IS NULL;

--No orphans found. No action required.
SELECT COUNT(e.ride_event_id), COUNT(e.attraction_id)
FROM fact_ride_events e
LEFT JOIN dim_attraction a ON a.attraction_id = e.attraction_id
WHERE a.attraction_id IS NULL;

--No orphans found. No action required.
SELECT COUNT(p.purchase_id), COUNT(p.visit_id)
FROM fact_purchases p
LEFT JOIN fact_visits v ON v.visit_id = p.visit_id
WHERE v.visit_id IS NULL;

--D
UPDATE fact_visits
SET promotion_code = NULLIF(UPPER(TRIM(promotion_code)), '');

UPDATE dim_guest
SET home_state = NULLIF(UPPER(TRIM(home_state)), '');

--null_spend: 10, null_promo: 14
SELECT
  SUM(CASE WHEN spend_cents_clean IS NULL THEN 1 ELSE 0 END) AS null_spend,
  SUM(CASE WHEN promotion_code IS NULL THEN 1 ELSE 0 END) AS null_promo
FROM fact_visits;

--null_waits: 67
SELECT
  SUM(CASE WHEN wait_minutes IS NULL THEN 1 ELSE 0 END) AS null_waits
FROM fact_ride_events;

--null_home_state: 0
SELECT
  SUM(CASE WHEN home_state IS NULL THEN 1 ELSE 0 END) AS null_home_state
FROM dim_guest;

-- Standardize all state names to two-letter, uppercase abbreviations
UPDATE dim_guest
SET home_state =
  CASE
    WHEN UPPER(TRIM(home_state)) IN ('CA', 'CALIFORNIA') THEN 'CA'
    WHEN UPPER(TRIM(home_state)) IN ('NY', 'NEW YORK') THEN 'NY'
    WHEN UPPER(TRIM(home_state)) IN ('FL', 'FLORIDA') THEN 'FL' 
    WHEN UPPER(TRIM(home_state)) IN ('TX', 'TEXAS') THEN 'TX'   
    ELSE UPPER(TRIM(home_state)) -- Capitalize any others just in case
  END;

-- Verifying
SELECT
  home_state,
  COUNT(guest_id) AS number_of_guests
FROM dim_guest
GROUP BY home_state
ORDER BY home_state;
