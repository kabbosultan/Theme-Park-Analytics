--CTEs


-- Q1: Daily Performance and Top 3 Peak Days for Ops Staffing
-- A : This query identifies the top 3 busiest days based on visitor count.
-- W: Pinpointing peak traffic days is crucial for operational planning, allowing management to schedule adequate staff and resources to meet demand and ensure a quality guest experience.
-- E : It looks like the top 3 days are random. Mondays, (7th), Wednesday (2nd) and Friday (4th) respectively.
-- S : By understanding our busiest days, we can proactively manage staffing and operations instead of reacting to crowds.

WITH daily_performance AS (
  -- Aggregate visits and spend by day
  SELECT 
    d.date_iso AS visit_date,
    COUNT(v.visit_id) AS daily_visits,
    COALESCE(SUM(v.spend_cents_clean), 0) AS daily_spend_cents
  FROM dim_date d
  LEFT JOIN fact_visits v ON d.date_id = v.date_id
  GROUP BY d.date_iso
),
daily_performance_with_running_totals AS (
  -- Add running totals for visits and spend using a window function
  SELECT
    visit_date,
    daily_visits,
    daily_spend_cents,
    SUM(daily_visits) OVER (ORDER BY visit_date ASC) AS running_total_visits,
    SUM(daily_spend_cents) OVER (ORDER BY visit_date ASC) AS running_total_spend_cents,
    ROW_NUMBER() OVER (ORDER BY daily_visits DESC) AS peak_day_rank -- Using ROW_NUMBER to get exactly 3 days
  FROM daily_performance
)
-- Final selection of top 3 peak days
SELECT 
  visit_date,
  daily_visits,
  ROUND(daily_spend_cents / 100.0, 2) AS daily_spend_dollars,
  running_total_visits,
  ROUND(running_total_spend_cents / 100.0, 2) AS running_total_spend_dollars
FROM daily_performance_with_running_totals
WHERE peak_day_rank <= 3
ORDER BY peak_day_rank;


-- Q2: RFM & CLV for Guest Segmentation
-- A : This query calculates Recency, Frequency, and Monetary value for each guest and ranks them by their total spend (CLV proxy) within their home state.
-- W: This helps identify high-value customers in specific regions, enabling targeted marketing campaigns.
-- E : We can send exclusive offers to our top-spending guests in 'CA' and 'NY' to encourage repeat visits.
-- S : Segmenting guests by value and location allows for more effective and personalized marketing efforts, maximizing ROI.

WITH guest_rfm AS (
  -- Calculate Recency, Frequency, and Monetary value for each guest
  SELECT
    g.guest_id,
    g.home_state,
    (SELECT MAX(d.date_iso) FROM fact_visits v JOIN dim_date d ON v.date_id = d.date_id) - MAX(d.date_iso) AS recency_days,
    COUNT(v.visit_id) AS frequency,
    SUM(v.spend_cents_clean) AS monetary_clv_proxy
  FROM dim_guest g
  JOIN fact_visits v ON g.guest_id = v.guest_id
  JOIN dim_date d ON v.date_id = d.date_id
  GROUP BY g.guest_id, g.home_state
),
ranked_guests AS (
  -- Rank guests by their monetary value within each home state
  SELECT
    guest_id,
    home_state,
    recency_days,
    frequency,
    monetary_clv_proxy,
    DENSE_RANK() OVER (PARTITION BY home_state ORDER BY monetary_clv_proxy DESC) AS clv_rank_in_state
  FROM guest_rfm
)
-- Final selection of ranked guests
SELECT
  guest_id,
  home_state,
  recency_days,
  frequency,
  ROUND(monetary_clv_proxy / 100.0, 2) AS clv_dollars,
  clv_rank_in_state
FROM ranked_guests
ORDER BY home_state, clv_rank_in_state;


-- Q3: Spending Behavior Change Analysis
-- A : This query calculates the change in spending from a guest's previous visit and finds the percentage of visits where spending increased.
-- W: Understanding when and why guests spend more helps identify factors that drive higher revenue.
-- E : If we see that guests who upgrade to a 'Premium' ticket consistently spend more on subsequent visits, we can promote that ticket type more heavily.
-- S : Analyzing visit-over-visit spending changes reveals key drivers of guest value, informing promotional and operational strategies.

WITH visit_spend_delta AS (
  -- Use LAG() to get the spend from the previous visit for each guest
  SELECT
    v.visit_id,
    v.guest_id,
    v.spend_cents_clean,
    LAG(v.spend_cents_clean, 1, 0) OVER (PARTITION BY v.guest_id ORDER BY d.date_iso) AS previous_spend_cents
  FROM fact_visits v
  JOIN dim_date d ON v.date_id = d.date_id
)
-- Calculate the percentage of visits with increased spending
SELECT
  ROUND(
    100.0 * SUM(CASE WHEN spend_cents_clean > previous_spend_cents THEN 1 ELSE 0 END)
    / COUNT(visit_id), 2
  ) AS percentage_of_visits_with_increased_spend
FROM visit_spend_delta
WHERE previous_spend_cents > 0;


-- Q4: Ticket Switching Behavior
-- A : This query identifies guests who have purchased a different ticket type after their first visit.
-- W: This reveals patterns in up-selling or down-selling, providing insight into the perceived value of different ticket packages.
-- E : If many guests switch from a 'Day Pass' to a 'VIP' or "Family Pack' ticket on their second visit, it suggests the premium package is well-priced and offers compelling value.
-- S : Understanding ticket switching behavior is key to optimizing pricing strategy and ticket package design to maximize guest satisfaction and revenue.

WITH guest_first_ticket AS (
  -- Use FIRST_VALUE() to find the first ticket type purchased by each guest
  SELECT
    v.guest_id,
    FIRST_VALUE(t.ticket_type_name) OVER (PARTITION BY v.guest_id ORDER BY d.date_iso) AS first_ticket_type
  FROM fact_visits v
  JOIN dim_ticket t ON v.ticket_type_id = t.ticket_type_id
  JOIN dim_date d ON v.date_id = d.date_id
),
guest_ticket_history AS (
  -- Combine first ticket info with all subsequent ticket purchases
  SELECT DISTINCT
    gft.guest_id,
    gft.first_ticket_type,
    t.ticket_type_name AS subsequent_ticket_type
  FROM guest_first_ticket gft
  JOIN fact_visits v ON gft.guest_id = v.guest_id
  JOIN dim_ticket t ON v.ticket_type_id = t.ticket_type_id
)
-- Flag guests who have switched tickets
SELECT
  guest_id,
  first_ticket_type,
  subsequent_ticket_type,
  CASE
    WHEN first_ticket_type <> subsequent_ticket_type THEN 'Switched'
    ELSE 'No Change'
  END AS switch_status
FROM guest_ticket_history
WHERE first_ticket_type <> subsequent_ticket_type
GROUP BY guest_id, first_ticket_type, subsequent_ticket_type -- Show distinct switches
ORDER BY guest_id;

