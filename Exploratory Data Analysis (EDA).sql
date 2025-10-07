

/**
A. Calculate Average Departure Delay and Percentage of Late Departures
**/
/**i) Add a Delay Column (in Minutes)**/

SELECT
  flight_number,
  scheduled_departure_datetime_local,
  actual_departure_datetime_local,
  EXTRACT(EPOCH FROM (actual_departure_datetime_local - scheduled_departure_datetime_local))/60 AS departure_delay_mins
FROM
  flight_level_data order by scheduled_departure_datetime_local;

/**ii) Calculate Average Delay of flights(without considering flights with preponed departure)**/

  SELECT
  AVG(EXTRACT(EPOCH FROM (actual_departure_datetime_local - scheduled_departure_datetime_local))/60) AS avg_departure_delay_mins
FROM
  flight_level_data where actual_departure_datetime_local>scheduled_departure_datetime_local;

/**iii) Calculate Percentage of Late Departures**/

  SELECT
  100.0 * SUM(CASE WHEN actual_departure_datetime_local > scheduled_departure_datetime_local THEN 1 ELSE 0 END) / COUNT(*) AS pct_late_departures
FROM
  flight_level_data where scheduled_ground_time_minutes>0;

/** B. Flights with Scheduled Ground Time Close to or Below Minimum Turn Minutes**/
SELECT
  flight_number,
  scheduled_departure_date_local,
  scheduled_ground_time_minutes,
  minimum_turn_minutes
FROM
  flight_level_data
WHERE
  scheduled_ground_time_minutes <= minimum_turn_minutes;

/**To get the total count of such flights:**/

SELECT
  COUNT(*) AS num_flights_with_tight_turnaround
FROM
  flight_level_data
WHERE
  scheduled_ground_time_minutes <= minimum_turn_minutes;

/** C. Average ratio of transfer bags vs. checked bags across flights?**/

/**Step 1: Calculate the ratio for each flight**/
SELECT
  flight_number,
  scheduled_departure_date_local,
  SUM(CASE WHEN bag_type IN ('Transfer', 'Hot ransfer') THEN 1 ELSE 0 END) AS transfer_bags,
  SUM(CASE WHEN bag_type = 'origin' THEN 1 ELSE 0 END) AS origin_bags,
  CASE
    WHEN SUM(CASE WHEN bag_type = 'origin' THEN 1 ELSE 0 END) = 0 THEN NULL
    ELSE SUM(CASE WHEN bag_type IN ('transfer', 'hot transfer') THEN 1 ELSE 0 END)::DECIMAL
         / SUM(CASE WHEN bag_type = 'origin' THEN 1 ELSE 0 END)
  END AS transfer_to_origin_ratio
FROM
  bag_level_data
GROUP BY
  flight_number,
  scheduled_departure_date_local;


/**Step 2: Calculate the average ratio across all flights**/
WITH flight_bag_ratios AS (
  SELECT
    flight_number,
    scheduled_departure_date_local,
    SUM(CASE WHEN bag_type = 'Transfer' THEN 1 ELSE 0 END) AS transfer_bags,
    SUM(CASE WHEN bag_type = 'Checked' THEN 1 ELSE 0 END) AS checked_bags,
    CASE
      WHEN SUM(CASE WHEN bag_type = 'Checked' THEN 1 ELSE 0 END) = 0 THEN NULL
      ELSE SUM(CASE WHEN bag_type = 'Transfer' THEN 1 ELSE 0 END)::DECIMAL
           / SUM(CASE WHEN bag_type = 'Checked' THEN 1 ELSE 0 END)
    END AS transfer_to_checked_ratio
  FROM
    bag_level_data
  GROUP BY
    flight_number,
    scheduled_departure_date_local
)
SELECT
  AVG(transfer_to_checked_ratio) AS avg_transfer_to_checked_ratio
FROM
  flight_bag_ratios
WHERE
  transfer_to_checked_ratio IS NOT NULL;

/**D. passenger loads and their correlation with operational difficulty**/
 /**Step 1: Calculate Passenger Load Factor
 Aggregate total passengers per flight**/
 
 -- First, sum total passengers per flight from PNR data
SELECT
  flight_number,
  scheduled_departure_date_local,
  SUM(total_pax) AS total_passengers
FROM
  pnr_flight_level_data
GROUP BY
  flight_number,
  scheduled_departure_date_local;

/**Join with flight data to get load factor**/
-- Join with flight_level_data to get total seats and calculate load factor
SELECT
  f.flight_number,
  f.scheduled_departure_date_local,
  f.total_seats,
  p.total_passengers,
  (p.total_passengers::DECIMAL / f.total_seats) AS load_factor
FROM
  flight_level_data f
JOIN (
  SELECT
    flight_number,
    scheduled_departure_date_local,
    SUM(total_pax) AS total_passengers
  FROM
    pnr_flight_level_data
  GROUP BY
    flight_number,
    scheduled_departure_date_local
) p
ON f.flight_number = p.flight_number
AND f.scheduled_departure_date_local = p.scheduled_departure_date_local;

/**Step 2: Correlate Load Factor with Operational Difficulty**/
SELECT
  f.flight_number,
  f.scheduled_departure_date_local,
  (p.total_passengers::DECIMAL / f.total_seats) AS load_factor,
  EXTRACT(EPOCH FROM (f.actual_departure_datetime_local - f.scheduled_departure_datetime_local))/60 AS departure_delay_mins
FROM
  flight_level_data f
JOIN (
  SELECT
    flight_number,
    scheduled_departure_date_local,
    SUM(total_pax) AS total_passengers
  FROM
    pnr_flight_level_data
  GROUP BY
    flight_number,
    scheduled_departure_date_local
) p
ON f.flight_number = p.flight_number
AND f.scheduled_departure_date_local = p.scheduled_departure_date_local;

/** E. Are high special service requests flights also high-delay after controlling for load?**/
/**Step 1: Aggregate Special Service Requests Per Flight & Date**/
SELECT
  pr.flight_number,
  pf.scheduled_departure_date_local,
  COUNT(*) AS num_special_service_requests
FROM
  pnr_remark_level_data pr
JOIN
  pnr_flight_level_data pf
    ON pr.record_locator = pf.record_locator
    AND pr.flight_number = pf.flight_number
GROUP BY
  pr.flight_number,
  pf.scheduled_departure_date_local


/**Step 2: Aggregate Passenger Load Per Flight & Date**/

SELECT
  flight_number,
  scheduled_departure_date_local,
  SUM(total_pax) AS total_passengers
FROM
  pnr_flight_level_data
GROUP BY
  flight_number,
  scheduled_departure_date_local


/**Step 3: Combine Data with Flight Delay**/

SELECT
  f.flight_number,
  f.scheduled_departure_date_local,
  f.total_seats,
  COALESCE(pl.total_passengers, 0) AS total_passengers,
  COALESCE(ss.num_special_service_requests, 0) AS num_special_service_requests,
  EXTRACT(EPOCH FROM (f.actual_departure_datetime_local - f.scheduled_departure_datetime_local))/60 AS departure_delay_mins
FROM
  flight_level_data f
LEFT JOIN
  (
    SELECT
      flight_number,
      scheduled_departure_date_local,
      SUM(total_pax) AS total_passengers
    FROM
      pnr_flight_level_data
    GROUP BY
      flight_number,
      scheduled_departure_date_local
  ) pl
  ON f.flight_number = pl.flight_number
  AND f.scheduled_departure_date_local = pl.scheduled_departure_date_local
LEFT JOIN
  (
    SELECT
      pr.flight_number,
      pf.scheduled_departure_date_local,
      COUNT(*) AS num_special_service_requests
    FROM
      pnr_remark_level_data pr
    JOIN
      pnr_flight_level_data pf
        ON pr.record_locator = pf.record_locator
        AND pr.flight_number = pf.flight_number
    GROUP BY
      pr.flight_number,
      pf.scheduled_departure_date_local
  ) ss
  ON f.flight_number = ss.flight_number
  AND f.scheduled_departure_date_local = ss.scheduled_departure_date_local
  where f.actual_departure_datetime_local > f.scheduled_departure_datetime_local

/**Step 4: Combine Data with Flight Delay**/
SELECT
  CASE
    WHEN num_special_service_requests >= 5 THEN 'High SSR'
    ELSE 'Low SSR'
  END AS ssr_group,
  AVG(departure_delay_mins) AS avg_departure_delay_mins
FROM
  (
    SELECT
  f.flight_number,
  f.scheduled_departure_date_local,
  f.total_seats,
  COALESCE(pl.total_passengers, 0) AS total_passengers,
  COALESCE(ss.num_special_service_requests, 0) AS num_special_service_requests,
  EXTRACT(EPOCH FROM (f.actual_departure_datetime_local - f.scheduled_departure_datetime_local))/60 AS departure_delay_mins
FROM
  flight_level_data f
LEFT JOIN
  (
    SELECT
      flight_number,
      scheduled_departure_date_local,
      SUM(total_pax) AS total_passengers
    FROM
      pnr_flight_level_data
    GROUP BY
      flight_number,
      scheduled_departure_date_local
  ) pl
  ON f.flight_number = pl.flight_number
  AND f.scheduled_departure_date_local = pl.scheduled_departure_date_local
LEFT JOIN
  (
    SELECT
      pr.flight_number,
      pf.scheduled_departure_date_local,
      COUNT(*) AS num_special_service_requests
    FROM
      pnr_remark_level_data pr
    JOIN
      pnr_flight_level_data pf
        ON pr.record_locator = pf.record_locator
        AND pr.flight_number = pf.flight_number
    GROUP BY
      pr.flight_number,
      pf.scheduled_departure_date_local
  ) ss
  ON f.flight_number = ss.flight_number
  AND f.scheduled_departure_date_local = ss.scheduled_departure_date_local
  where f.actual_departure_datetime_local > f.scheduled_departure_datetime_local
  ) t
GROUP BY
  ssr_group;

