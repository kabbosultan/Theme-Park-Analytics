--Feature Engineering

-- Feature 1: stay_minutes (entry_time to exit_time)
-- Why: Longer stays often mean higher spend and more ride events; short stays may signal dissatisfaction or operational issues.
ALTER TABLE fact_visits ADD COLUMN stay_minutes INTEGER;

UPDATE fact_visits
SET stay_minutes =
  CASE
    WHEN entry_time IS NOT NULL AND exit_time IS NOT NULL
    THEN
      (strftime('%s', exit_time) - strftime('%s', entry_time)) / 60
    ELSE NULL
  END;
  
  --Verifying
  SELECT stay_minutes FROM fact_visits; 
  
  -- Feature 2: wait_bucket (categorize wait_minutes for staffing/ops)
-- Why: Bucketing wait times helps identify when/where lines are too long, guiding queue management and staffing.
ALTER TABLE fact_ride_events ADD COLUMN wait_bucket TEXT;

UPDATE fact_ride_events
SET wait_bucket = CASE
  WHEN wait_minutes IS NULL THEN 'NULL'
  WHEN wait_minutes < 16 THEN '0-15'
  WHEN wait_minutes < 31 THEN '16-30'
  WHEN wait_minutes < 61 THEN '31-60'
  ELSE '60+' END;
  
  --Verifying
 SELECT wait_bucket FROM fact_ride_events;
 
 --(I know we are only supposed to choose 2 from the list but I ended up making this one so decided to keep it)
-- Feature 3 : is_repeat_guest (flag guests with >1 visit) 
-- Why: Repeat guests are more valuable; tracking them helps target loyalty campaigns and measure retention.
ALTER TABLE dim_guest ADD COLUMN is_repeat_guest INTEGER;

UPDATE dim_guest
SET is_repeat_guest = CASE
  WHEN guest_id IN (
    SELECT guest_id FROM fact_visits GROUP BY guest_id HAVING COUNT(*) > 1
  ) THEN 1 ELSE 0 END;
  
--Verifying
SELECT is_repeat_guest from dim_guest;

-- Feature 4: spend_per_person (normalized spend for Marketing)
-- Why: Spend per person (vs. raw spend) reveals which segments/ticket types drive the most value, regardless of party size.
ALTER TABLE fact_visits ADD COLUMN spend_per_person REAL;

UPDATE fact_visits
SET spend_per_person =
  CASE
    WHEN spend_cents_clean IS NOT NULL AND party_size IS NOT NULL AND party_size > 0
    THEN ROUND(spend_cents_clean * 1.0 / party_size, 2)
    ELSE NULL
  END;
  
SELECT spend_per_person from fact_visits;


-- Feature 5: high_wait_flag (flag visits where guest experienced a high wait on any top bottleneck ride)
-- Why: This helps identify guests most affected by long waits, so we can target satisfaction surveys, 
--compensation, or special offers, and measure if operational changes reduce the number of guests with high-wait experiences.
ALTER TABLE fact_visits ADD COLUMN high_wait_flag INTEGER;


-- Query to identify top 3 bottleneck attraction IDs
-- This will provide the attraction_id numbers to use in the high_wait_flag feature
--Result Top 3 IDs: 3,2,6
SELECT 
  e.attraction_id,
  a.attraction_name,
  AVG(e.wait_minutes) AS avg_wait,
  COUNT(*) AS n_events
FROM fact_ride_events e
JOIN dim_attraction a ON a.attraction_id = e.attraction_id
WHERE e.wait_minutes IS NOT NULL
GROUP BY e.attraction_id, a.attraction_name
HAVING COUNT(*) >= 5  -- only attractions with enough data
ORDER BY avg_wait DESC
LIMIT 3;


-- After identifying top 3 attractions
-- Here, we flag any visit where the guest waited over 30 minutes on any of those rides
UPDATE fact_visits
SET high_wait_flag = CASE
  WHEN EXISTS (
    SELECT 1
    FROM fact_ride_events e
    WHERE e.visit_id = fact_visits.visit_id
      AND e.attraction_id IN (3, 2, 6) 
      AND e.wait_minutes >= 30
  ) THEN 1 ELSE 0 END;
  
  --Verifying
  SELECT high_wait_flag FROM fact_visits;
 
 --Why normalize promotion codes before analysis?
-- Normalize promotion_code before analysis to ensure accurate grouping, reporting, and filtering—so you and your stakeholders can trust the results.
--I chose to not standardize SUMMER-25 and SUMMER25 promotion codes because 
--it is perfectly reasonable to assume that they are 2 different codes. Since I cannot verify, I have kept them seperate.
SELECT DISTINCT promotion_code
FROM fact_visits
ORDER BY promotion_code;



