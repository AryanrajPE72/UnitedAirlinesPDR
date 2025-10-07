/**3. Post-Analysis & Operational Insights**/
--i)Summarize which destinations consistently show more difficulty.

SELECT 
    fld.scheduled_arrival_station_code AS destination,
    COUNT(*) AS flight_count,
    AVG(fd.difficulty_score) AS avg_difficulty_score,
    CASE
        WHEN AVG(fd.difficulty_score) >= 0.5 THEN 'Difficult'
        WHEN AVG(fd.difficulty_score) >= 0.3 THEN 'Medium'
        ELSE 'Easy'
    END AS representative_difficulty_category
FROM 
    flight_level_data fld
JOIN 
    flight_difficulty fd
ON 
    fld.flight_number = fd.flight_number
    AND fld.scheduled_departure_date_local = fd.scheduled_departure_date_local
GROUP BY 
    fld.scheduled_arrival_station_code
HAVING 
    AVG(fd.difficulty_score) > (
        SELECT AVG(difficulty_score)
        FROM flight_difficulty
    )
ORDER BY 
    avg_difficulty_score DESC;


--ii)destinations consistently show more difficulty(more than 50% difficult flights)

SELECT
    fld.scheduled_arrival_station_code AS destination,
    COUNT(*) AS flight_count,
    AVG(fd.difficulty_score) AS avg_difficulty_score,
    SUM(CASE
            WHEN fd.difficulty_category = 'Difficult' THEN 1
            ELSE 0
        END) AS difficult_flights_count,
    ROUND(
        100.0 * SUM(CASE
            WHEN fd.difficulty_category = 'Difficult' THEN 1
            ELSE 0
        END) / COUNT(*),
        2
    ) AS percent_difficult_flights
FROM
    flight_level_data fld
JOIN
    flight_difficulty fd
ON
    fld.flight_number = fd.flight_number
    AND fld.scheduled_departure_date_local = fd.scheduled_departure_date_local
GROUP BY
    fld.scheduled_arrival_station_code
HAVING
    SUM(CASE
            WHEN fd.difficulty_category = 'Difficult' THEN 1
            ELSE 0
        END)::float / COUNT(*) > 0.5
ORDER BY
    percent_difficult_flights DESC,
    avg_difficulty_score DESC;


	

	

	



