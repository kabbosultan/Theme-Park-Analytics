---- EDA ----

-- Q0 (style example): Row counts by table
SELECT 'dim_guest' AS table_name, COUNT(*) AS n FROM dim_guest
UNION ALL SELECT 'dim_ticket', COUNT(*) FROM dim_ticket
UNION ALL SELECT 'dim_attraction', COUNT(*) FROM dim_attraction
UNION ALL SELECT 'dim_date', COUNT(*) FROM dim_date
UNION ALL SELECT 'fact_visits', COUNT(*) FROM fact_visits
UNION ALL SELECT 'fact_ride_events', COUNT(*) FROM fact_ride_events
UNION ALL SELECT 'fact_purchases', COUNT(*) FROM fact_purchases;

-- Q1: 
SELECT MIN(visit_date) AS min_visit_date,
       MAX(visit_date) AS max_visit_date,
       COUNT(DISTINCT visit_date) AS distinct_dates
FROM fact_visits;

SELECT visit_date, COUNT(*) AS visits
FROM fact_visits
GROUP BY visit_date
ORDER BY visit_date;

-- Q2: 
SELECT t.ticket_type_name, COUNT(*) AS visits
FROM fact_visits v
JOIN dim_ticket t ON v.ticket_type_id = t.ticket_type_id
GROUP BY t.ticket_type_name
ORDER BY visits DESC;

-- Q3: 

SELECT COUNT(*) AS null_waits
FROM fact_ride_events
WHERE wait_minutes IS NULL;

SELECT
  COUNT(*) AS rows_total,
  SUM(CASE WHEN wait_minutes IS NULL THEN 1 ELSE 0 END) AS wait_nulls,
  AVG(wait_minutes) AS avg_wait,
  MIN(wait_minutes) AS min_wait,
  MAX(wait_minutes) AS max_wait
FROM fact_ride_events;

-- Q4: 
--by attraction_name
SELECT a.attraction_name, AVG(satisfaction_rating) AS avg_sat, COUNT(*) AS n
FROM fact_ride_events e
JOIN dim_attraction a ON e.attraction_id = a.attraction_id
GROUP BY a.attraction_name
HAVING COUNT(*) >= 5
ORDER BY avg_sat ASC;
--by category
SELECT a.category, AVG(satisfaction_rating) AS avg_sat, COUNT(*) AS n
FROM fact_ride_events e
JOIN dim_attraction a ON e.attraction_id = a.attraction_id
GROUP BY a.category
ORDER BY avg_sat ASC;

-- Query to correlate average wait times with average satisfaction scores
WITH waits AS (
  -- Calculate the average wait time for each attraction
  SELECT
    e.attraction_id,
    AVG(e.wait_minutes) AS avg_wait
  FROM fact_ride_events e
  WHERE e.wait_minutes IS NOT NULL
  GROUP BY e.attraction_id
),
satisfaction AS (
  -- Calculate the average satisfaction for each attraction
  SELECT
    e.attraction_id,
    AVG(e.satisfaction_rating) AS avg_satisfaction
  FROM fact_ride_events e
  WHERE e.satisfaction_rating IS NOT NULL
  GROUP BY e.attraction_id
)
-- Join the two metrics together
SELECT
  a.attraction_name,
  ROUND(w.avg_wait, 1) AS average_wait_minutes,
  ROUND(s.avg_satisfaction, 2) AS average_satisfaction_rating
FROM dim_attraction a
JOIN waits w ON a.attraction_id = w.attraction_id
JOIN satisfaction s ON a.attraction_id = s.attraction_id
ORDER BY average_wait_minutes DESC; -- Order by longest wait time

-- Q5: 
SELECT
  attraction_id, visit_id, ride_time, wait_minutes, satisfaction_rating, photo_purchase,
  COUNT(*) AS dup_count
FROM fact_ride_events
GROUP BY attraction_id, visit_id, ride_time, wait_minutes, satisfaction_rating, photo_purchase
HAVING COUNT(*) > 1
ORDER BY dup_count DESC;

-- Q6: 
--Checking null counts of columns from fact_visits and fact_ride_events
SELECT
  SUM(CASE WHEN guest_id IS NULL THEN 1 ELSE 0 END) AS null_guest_id,
  SUM(CASE WHEN ticket_type_id IS NULL THEN 1 ELSE 0 END) AS null_ticket_type_id,
  SUM(CASE WHEN visit_date IS NULL THEN 1 ELSE 0 END) AS null_visit_date,
  SUM(CASE WHEN total_spend_cents IS NULL THEN 1 ELSE 0 END) AS null_total_spend_cents,
  SUM(CASE WHEN spend_cents_clean IS NULL THEN 1 ELSE 0 END) AS null_spend_cents_clean
FROM fact_visits;

SELECT
  SUM(CASE WHEN attraction_id IS NULL THEN 1 ELSE 0 END) AS null_attraction_id,
  SUM(CASE WHEN wait_minutes IS NULL THEN 1 ELSE 0 END) AS null_wait_minutes,
  SUM(CASE WHEN satisfaction_rating IS NULL THEN 1 ELSE 0 END) AS null_satisfaction
FROM fact_ride_events;

-- Q7: 
SELECT d.day_name, ROUND(AVG(v.party_size), 2) AS avg_party_size
FROM fact_visits v
JOIN dim_date d ON v.date_id = d.date_id
GROUP BY d.day_name
ORDER BY CASE d.day_name
  WHEN 'Monday' THEN 1 WHEN 'Tuesday' THEN 2 WHEN 'Wednesday' THEN 3
  WHEN 'Thursday' THEN 4 WHEN 'Friday' THEN 5 WHEN 'Saturday' THEN 6
  WHEN 'Sunday' THEN 7 END;

--Additional EDA 
  --Top 3 bottleneck attractions by sustained wait
-- Why: identify targets for virtual queue/load balancing pilots
WITH waits AS (
  SELECT e.attraction_id,
         AVG(e.wait_minutes) AS avg_wait,
         COUNT(*) AS n_events
  FROM fact_ride_events e
  WHERE e.wait_minutes IS NOT NULL
  GROUP BY e.attraction_id
),
sats AS (
  SELECT e.attraction_id,
         AVG(e.satisfaction_rating) AS avg_sat
  FROM fact_ride_events e
  WHERE e.satisfaction_rating IS NOT NULL
  GROUP BY e.attraction_id
)
SELECT a.attraction_name,
       w.avg_wait,
       s.avg_sat,
       w.n_events
FROM waits w
JOIN dim_attraction a ON a.attraction_id = w.attraction_id
LEFT JOIN sats s ON s.attraction_id = w.attraction_id
WHERE w.n_events >= 5  -- small-sample guardrail
ORDER BY w.avg_wait DESC
LIMIT 3;



