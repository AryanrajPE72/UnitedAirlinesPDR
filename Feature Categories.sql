/**1. Ground Time Constraints**/
--Feature: Ground Time Margin (how scheduled ground time compares to minimum requirement)
SELECT
  flight_number,
  scheduled_departure_date_local,
  scheduled_departure_station_code,
  scheduled_arrival_station_code,
  scheduled_ground_time_minutes,
  minimum_turn_minutes,
  (scheduled_ground_time_minutes - minimum_turn_minutes) AS ground_time_margin
FROM
  flight_level_data;

/**2. Bag Volume/Transfer Complexity**/
--Feature: Bags per Pax and Transfer Bag Ratio
-- Bags per passenger
SELECT
  b.flight_number,
  b.scheduled_departure_date_local,
  COUNT(b.bag_tag_unique_number) AS total_bags,
  SUM(p.total_pax) AS total_pax,
  COUNT(b.bag_tag_unique_number)::DECIMAL / NULLIF(SUM(p.total_pax), 0) AS bags_per_pax
FROM
  bag_level_data b
JOIN
  pnr_flight_level_data p
ON
  b.flight_number = p.flight_number
  AND b.scheduled_departure_date_local = p.scheduled_departure_date_local
GROUP BY
  b.flight_number, b.scheduled_departure_date_local order by bags_per_pax desc;

-- Transfer to Checked Bag ratio
SELECT
  flight_number,
  scheduled_departure_date_local,
  SUM(CASE WHEN bag_type IN ('Transfer', 'Hot Transfer') THEN 1 ELSE 0 END) AS transfer_bags,
  SUM(CASE WHEN bag_type = 'Origin' THEN 1 ELSE 0 END) AS checked_bags,
  CASE
    WHEN SUM(CASE WHEN bag_type = 'Origin' THEN 1 ELSE 0 END) = 0 THEN NULL
    ELSE SUM(CASE WHEN bag_type IN ('Transfer', 'Hot Transfer') THEN 1 ELSE 0 END)::DECIMAL
        / SUM(CASE WHEN bag_type = 'Origin' THEN 1 ELSE 0 END)
  END AS transfer_to_checked_ratio
FROM
  bag_level_data
GROUP BY
  flight_number, scheduled_departure_date_local;

/**3. Children Proportion**/
--Feature: Ratio of lap children to total passengers
SELECT
  flight_number,
  scheduled_departure_date_local,
  SUM(lap_child_count) AS lap_children,
  SUM(total_pax) AS total_passengers,
  SUM(lap_child_count)::DECIMAL / NULLIF(SUM(total_pax),0) AS lap_children_ratio
FROM
  pnr_flight_level_data
GROUP BY
  flight_number, scheduled_departure_date_local
  order by lap_children_ratio desc;

/**4. Haul Category**/
--Feature: Haul tag (short/medium/long), EXAMPLE using scheduled time difference
SELECT
  flight_number,
  scheduled_departure_date_local,
  scheduled_departure_station_code,
  scheduled_arrival_station_code,
  (EXTRACT(EPOCH FROM (scheduled_arrival_datetime_local - scheduled_departure_datetime_local))/3600) AS scheduled_haul_hours,
  CASE 
    WHEN (EXTRACT(EPOCH FROM (scheduled_arrival_datetime_local - scheduled_departure_datetime_local))/3600) < 2 THEN 'Short Haul'
    WHEN (EXTRACT(EPOCH FROM (scheduled_arrival_datetime_local - scheduled_departure_datetime_local))/3600) BETWEEN 2 AND 5 THEN 'Medium Haul'
    ELSE 'Long Haul'
  END AS haul_category
FROM
  flight_level_data; 

/**5. Aircraft and Fleet Type Flag**/
--Feature: Aircraft type, carrier, and “rare”/“common” flag
WITH fleet_counts AS (
  SELECT
    fleet_type,
    carrier,
    COUNT(*) AS n_flights
  FROM
    flight_level_data
  GROUP BY
    fleet_type, carrier
),
fleet_summary AS (
  SELECT
    fleet_type,
    carrier,
    n_flights,
    (SELECT SUM(n_flights) FROM fleet_counts) AS total_flights
  FROM fleet_counts
)
SELECT
  fleet_type,
  carrier,
  n_flights,
  total_flights,
  100.0 * n_flights / total_flights AS pct_of_flights,
  CASE
    WHEN 100.0 * n_flights / total_flights < 5 THEN 'Rare'
    ELSE 'Common'
  END AS rarity_flag
FROM fleet_summary
ORDER BY pct_of_flights ASC, carrier, fleet_type;

/**6. SSR Cluster Analysis**/
--Feature: SSRs per flight; SSR per Pax
-- SSRs per flight
SELECT
  pr.flight_number,
  pf.scheduled_departure_date_local,
  COUNT(*) AS num_special_service_requests
FROM
  pnr_remark_level_data pr
JOIN
  pnr_flight_level_data pf
    ON pr.record_locator = pf.record_locator AND pr.flight_number = pf.flight_number
GROUP BY
  pr.flight_number, pf.scheduled_departure_date_local;

-- SSR per passenger
SELECT
  ssr.flight_number,
  ssr.scheduled_departure_date_local,
  ssr.num_special_service_requests,
  pax.total_pax,
  ssr.num_special_service_requests::DECIMAL / NULLIF(pax.total_pax, 0) AS ssr_per_pax
FROM
  (SELECT
     pr.flight_number,
     pf.scheduled_departure_date_local,
     COUNT(*) AS num_special_service_requests
   FROM
     pnr_remark_level_data pr
   JOIN
     pnr_flight_level_data pf
     ON pr.record_locator = pf.record_locator AND pr.flight_number = pf.flight_number
   GROUP BY pr.flight_number, pf.scheduled_departure_date_local
  ) ssr
JOIN
  (SELECT
     flight_number,
     scheduled_departure_date_local,
     SUM(total_pax) AS total_pax
   FROM
     pnr_flight_level_data
   GROUP BY flight_number, scheduled_departure_date_local
  ) pax
ON
  ssr.flight_number = pax.flight_number AND ssr.scheduled_departure_date_local = pax.scheduled_departure_date_local;


/**7. Temporal Features**/
--Feature: Departure bank classification (hour of day), day-of-week patterns
SELECT
  flight_number,
  scheduled_departure_date_local,
  EXTRACT(HOUR FROM scheduled_departure_datetime_local) AS departure_hour,
  CASE
    WHEN EXTRACT(HOUR FROM scheduled_departure_datetime_local) < 7 THEN 'Early Morning'
    WHEN EXTRACT(HOUR FROM scheduled_departure_datetime_local) BETWEEN 7 AND 12 THEN 'Morning'
    WHEN EXTRACT(HOUR FROM scheduled_departure_datetime_local) BETWEEN 13 AND 18 THEN 'Afternoon'
    ELSE 'Evening/Night'
  END AS departure_bank,
  TO_CHAR(scheduled_departure_date_local, 'Day') AS day_of_week
FROM
  flight_level_data;




