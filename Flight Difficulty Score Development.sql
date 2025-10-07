--Flight Difficulty Score Development
/**step 1.)Calculate Min/Max for Normalization**/

-- Scheduled ground time
SELECT MIN(scheduled_ground_time_minutes) AS min_ground, MAX(scheduled_ground_time_minutes) AS max_ground FROM flight_level_data WHERE scheduled_ground_time_minutes > 0
;

-- Transfer-to-checked bag ratio
SELECT MIN(transfer_to_checked_ratio) AS min_tr, MAX(transfer_to_checked_ratio) AS max_tr FROM (
  SELECT
    flight_number,
    scheduled_departure_date_local,
    SUM(CASE WHEN bag_type IN ('Transfer','Hot Transfer') THEN 1 ELSE 0 END)::DECIMAL /
    NULLIF(SUM(CASE WHEN bag_type = 'Origin' THEN 1 ELSE 0 END),0) AS transfer_to_checked_ratio
  FROM bag_level_data
  GROUP BY flight_number, scheduled_departure_date_local
) t WHERE transfer_to_checked_ratio IS NOT NULL;

-- SSR count
WITH deduped_pnrs AS (
  SELECT *
  FROM (
    SELECT
      flight_number,
      scheduled_departure_date_local,
      record_locator,
      ROW_NUMBER() OVER (
        PARTITION BY flight_number, scheduled_departure_date_local, record_locator
        ORDER BY record_locator
      ) AS rn
    FROM pnr_flight_level_data
  ) t
  WHERE rn = 1
)
SELECT MIN(num_special_service_requests) AS min_ssr, MAX(num_special_service_requests) AS max_ssr FROM (
  SELECT
    pr.flight_number,
    pf.scheduled_departure_date_local,
    COUNT(*) AS num_special_service_requests
  FROM pnr_remark_level_data pr
  JOIN deduped_pnrs pf
    ON pr.record_locator = pf.record_locator
   AND pr.flight_number = pf.flight_number
  GROUP BY pr.flight_number, pf.scheduled_departure_date_local
) t;


-- Load factor
WITH deduped_pnrs AS (
  SELECT *
  FROM (
    SELECT
      flight_number,
      scheduled_departure_date_local,
      record_locator,
      total_pax,
      lap_child_count,
      ROW_NUMBER() OVER (
        PARTITION BY flight_number, scheduled_departure_date_local, record_locator
        ORDER BY record_locator
      ) AS rn
    FROM pnr_flight_level_data
  ) t
  WHERE rn = 1
)
SELECT MIN(load_factor) AS min_lf, MAX(load_factor) AS max_lf FROM (
  SELECT
    f.flight_number,
    f.scheduled_departure_date_local,
    (p.seat_occupying_passengers::DECIMAL / f.total_seats) AS load_factor
  FROM flight_level_data f
  JOIN (
    SELECT
      flight_number,
      scheduled_departure_date_local,
      SUM(total_pax - lap_child_count) AS seat_occupying_passengers
    FROM deduped_pnrs
    GROUP BY flight_number, scheduled_departure_date_local
  ) p ON f.flight_number = p.flight_number AND f.scheduled_departure_date_local = p.scheduled_departure_date_local
) t;


/**step2). Feature Engineering and Normalization**/
WITH
params AS (
  SELECT
    1.0 AS min_ground, 33327 AS max_ground,
    0.0 AS min_tr, 134.0 AS max_tr,
    1 AS min_ssr, 27 AS max_ssr,
    0.06 AS min_lf, 1.02 AS max_lf
),
bag_ratios AS (
  SELECT
    flight_number,
    scheduled_departure_date_local,
    SUM(CASE WHEN bag_type IN ('Transfer','Hot Transfer') THEN 1 ELSE 0 END)::DECIMAL /
    NULLIF(SUM(CASE WHEN bag_type = 'Origin' THEN 1 ELSE 0 END),0) AS transfer_to_checked_ratio
  FROM bag_level_data
  GROUP BY flight_number, scheduled_departure_date_local
),
deduped_pnrs AS (
  SELECT *
  FROM (
    SELECT
      flight_number,
      scheduled_departure_date_local,
      record_locator,
      total_pax,
      lap_child_count,
      ROW_NUMBER() OVER (
        PARTITION BY flight_number, scheduled_departure_date_local, record_locator
        ORDER BY record_locator
      ) AS rn
    FROM pnr_flight_level_data
  ) t
  WHERE rn = 1
),
ssr_counts AS (
  SELECT
    pr.flight_number,
    pf.scheduled_departure_date_local,
    COUNT(*) AS num_special_service_requests
  FROM pnr_remark_level_data pr
  JOIN deduped_pnrs pf
    ON pr.record_locator = pf.record_locator
   AND pr.flight_number = pf.flight_number
  GROUP BY pr.flight_number, pf.scheduled_departure_date_local
),
passenger_loads AS (
  SELECT
    flight_number,
    scheduled_departure_date_local,
    SUM(total_pax - lap_child_count) AS seat_occupying_passengers
  FROM deduped_pnrs
  GROUP BY flight_number, scheduled_departure_date_local
),
features AS (
  SELECT
    f.flight_number,
    f.scheduled_departure_date_local,
    (params.max_ground - f.scheduled_ground_time_minutes)::DECIMAL / NULLIF((params.max_ground - params.min_ground),0) AS ground_time_score,
    (COALESCE(b.transfer_to_checked_ratio,0) - params.min_tr) / NULLIF((params.max_tr - params.min_tr),0) AS transfer_score,
    (COALESCE(s.num_special_service_requests,0) - params.min_ssr) / NULLIF((params.max_ssr - params.min_ssr),0) AS ssr_score,
    (COALESCE(p.seat_occupying_passengers,0)::DECIMAL / f.total_seats - params.min_lf) / NULLIF((params.max_lf - params.min_lf),0) AS load_factor_score
  FROM flight_level_data f
  LEFT JOIN bag_ratios b ON f.flight_number = b.flight_number AND f.scheduled_departure_date_local = b.scheduled_departure_date_local
  LEFT JOIN ssr_counts s ON f.flight_number = s.flight_number AND f.scheduled_departure_date_local = s.scheduled_departure_date_local
  LEFT JOIN passenger_loads p ON f.flight_number = p.flight_number AND f.scheduled_departure_date_local = p.scheduled_departure_date_local
  CROSS JOIN params
)



/**step3.)Final Difficulty Score Calculation**/
WITH
params AS (
  SELECT
    1.0 AS min_ground, 33327 AS max_ground,
    0.0 AS min_tr, 134.0 AS max_tr,
    0 AS min_ssr, 27 AS max_ssr,
    0.06 AS min_lf, 1.02 AS max_lf
),
bag_ratios AS (
  SELECT
    flight_number,
    scheduled_departure_date_local,
    SUM(CASE WHEN bag_type IN ('Transfer','Hot Transfer') THEN 1 ELSE 0 END)::DECIMAL /
    NULLIF(SUM(CASE WHEN bag_type = 'Origin' THEN 1 ELSE 0 END),0) AS transfer_to_checked_ratio
  FROM bag_level_data
  GROUP BY flight_number, scheduled_departure_date_local
),
deduped_pnrs AS (
  SELECT *
  FROM (
    SELECT
      flight_number,
      scheduled_departure_date_local,
      record_locator,
      total_pax,
      lap_child_count,
      ROW_NUMBER() OVER (
        PARTITION BY flight_number, scheduled_departure_date_local, record_locator
        ORDER BY record_locator
      ) AS rn
    FROM pnr_flight_level_data
  ) t
  WHERE rn = 1
),
ssr_counts AS (
  SELECT
    pr.flight_number,
    pf.scheduled_departure_date_local,
    COUNT(*) AS num_special_service_requests
  FROM pnr_remark_level_data pr
  JOIN deduped_pnrs pf
    ON pr.record_locator = pf.record_locator
   AND pr.flight_number = pf.flight_number
  GROUP BY pr.flight_number, pf.scheduled_departure_date_local
),
passenger_loads AS (
  SELECT
    flight_number,
    scheduled_departure_date_local,
    SUM(total_pax - lap_child_count) AS seat_occupying_passengers
  FROM deduped_pnrs
  GROUP BY flight_number, scheduled_departure_date_local
),
features AS (
  SELECT
    f.flight_number,
    f.scheduled_departure_date_local,
    (params.max_ground - f.scheduled_ground_time_minutes)::DECIMAL / NULLIF((params.max_ground - params.min_ground),0) AS ground_time_score,
    (COALESCE(b.transfer_to_checked_ratio,0) - params.min_tr) / NULLIF((params.max_tr - params.min_tr),0) AS transfer_score,
    (COALESCE(s.num_special_service_requests,0) - params.min_ssr) / NULLIF((params.max_ssr - params.min_ssr),0) AS ssr_score,
    (COALESCE(p.seat_occupying_passengers,0)::DECIMAL / f.total_seats - params.min_lf) / NULLIF((params.max_lf - params.min_lf),0) AS load_factor_score
  FROM flight_level_data f
  LEFT JOIN bag_ratios b ON f.flight_number = b.flight_number AND f.scheduled_departure_date_local = b.scheduled_departure_date_local
  LEFT JOIN ssr_counts s ON f.flight_number = s.flight_number AND f.scheduled_departure_date_local = s.scheduled_departure_date_local
  LEFT JOIN passenger_loads p ON f.flight_number = p.flight_number AND f.scheduled_departure_date_local = p.scheduled_departure_date_local
  CROSS JOIN params
)

SELECT
  *,
  0.3*ssr_score + 0.3*ground_time_score + 0.2*transfer_score + 0.2*load_factor_score AS difficulty_score
FROM features
ORDER BY difficulty_score DESC;

/**step4.)Daily Ranking and Classification**/
WITH
params AS (
  SELECT
    1.0 AS min_ground, 33327 AS max_ground,
    0.0 AS min_tr, 134.0 AS max_tr,
    0 AS min_ssr, 27 AS max_ssr,
    0.06 AS min_lf, 1.02 AS max_lf
),
bag_ratios AS (
  SELECT
    flight_number,
    scheduled_departure_date_local,
    SUM(CASE WHEN bag_type IN ('Transfer','Hot Transfer') THEN 1 ELSE 0 END)::DECIMAL /
    NULLIF(SUM(CASE WHEN bag_type = 'Origin' THEN 1 ELSE 0 END),0) AS transfer_to_checked_ratio
  FROM bag_level_data
  GROUP BY flight_number, scheduled_departure_date_local
),
deduped_pnrs AS (
  SELECT *
  FROM (
    SELECT
      flight_number,
      scheduled_departure_date_local,
      record_locator,
      total_pax,
      lap_child_count,
      ROW_NUMBER() OVER (
        PARTITION BY flight_number, scheduled_departure_date_local, record_locator
        ORDER BY record_locator
      ) AS rn
    FROM pnr_flight_level_data
  ) t
  WHERE rn = 1
),
ssr_counts AS (
  SELECT
    pr.flight_number,
    pf.scheduled_departure_date_local,
    COUNT(*) AS num_special_service_requests
  FROM pnr_remark_level_data pr
  JOIN deduped_pnrs pf
    ON pr.record_locator = pf.record_locator
   AND pr.flight_number = pf.flight_number
  GROUP BY pr.flight_number, pf.scheduled_departure_date_local
),
passenger_loads AS (
  SELECT
    flight_number,
    scheduled_departure_date_local,
    SUM(total_pax - lap_child_count) AS seat_occupying_passengers
  FROM deduped_pnrs
  GROUP BY flight_number, scheduled_departure_date_local
),
features AS (
  SELECT
    f.flight_number,
    f.scheduled_departure_date_local,
    (params.max_ground - f.scheduled_ground_time_minutes)::DECIMAL / NULLIF((params.max_ground - params.min_ground),0) AS ground_time_score,
    (COALESCE(b.transfer_to_checked_ratio,0) - params.min_tr) / NULLIF((params.max_tr - params.min_tr),0) AS transfer_score,
    (COALESCE(s.num_special_service_requests,0) - params.min_ssr) / NULLIF((params.max_ssr - params.min_ssr),0) AS ssr_score,
    (COALESCE(p.seat_occupying_passengers,0)::DECIMAL / f.total_seats - params.min_lf) / NULLIF((params.max_lf - params.min_lf),0) AS load_factor_score
  FROM flight_level_data f
  LEFT JOIN bag_ratios b ON f.flight_number = b.flight_number AND f.scheduled_departure_date_local = b.scheduled_departure_date_local
  LEFT JOIN ssr_counts s ON f.flight_number = s.flight_number AND f.scheduled_departure_date_local = s.scheduled_departure_date_local
  LEFT JOIN passenger_loads p ON f.flight_number = p.flight_number AND f.scheduled_departure_date_local = p.scheduled_departure_date_local
  CROSS JOIN params
),
ranked AS (
  SELECT
    *,
    ROW_NUMBER() OVER (PARTITION BY scheduled_departure_date_local ORDER BY
      0.3*ssr_score + 0.3*ground_time_score + 0.2*transfer_score + 0.2*load_factor_score DESC) AS daily_rank,
    COUNT(*) OVER (PARTITION BY scheduled_departure_date_local) AS total_flights,
    0.3*ssr_score + 0.3*ground_time_score + 0.2*transfer_score + 0.2*load_factor_score AS difficulty_score
  FROM features
)
SELECT
  flight_number,
  scheduled_departure_date_local,
  difficulty_score,
  ground_time_score,
  transfer_score,
  ssr_score,
  load_factor_score,
  daily_rank,
  CASE
    WHEN daily_rank <= total_flights/3 THEN 'Difficult'
    WHEN daily_rank <= 2*total_flights/3 THEN 'Medium'
    ELSE 'Easy'
  END AS difficulty_category
FROM ranked
ORDER BY scheduled_departure_date_local, daily_rank;







