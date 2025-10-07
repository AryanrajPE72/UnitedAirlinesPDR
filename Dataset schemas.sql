CREATE TABLE flight_level_data (
    company_id VARCHAR(10),
    flight_number VARCHAR(20),
    scheduled_departure_date_local DATE,
    scheduled_departure_station_code VARCHAR(10),
    scheduled_arrival_station_code VARCHAR(10),
    scheduled_departure_datetime_local TIMESTAMP,
    scheduled_arrival_datetime_local TIMESTAMP,
    actual_departure_datetime_local TIMESTAMP,
    actual_arrival_datetime_local TIMESTAMP,
    total_seats INTEGER,
    fleet_type VARCHAR(50),
    carrier VARCHAR(20),
    scheduled_ground_time_minutes INTEGER,
    actual_ground_time_minutes INTEGER,
    minimum_turn_minutes INTEGER
);


CREATE TABLE pnr_flight_level_data (
    company_id VARCHAR(10),
    flight_number VARCHAR(20),
    scheduled_departure_date_local DATE,
    scheduled_departure_station_code VARCHAR(10),
    scheduled_arrival_station_code VARCHAR(10),
    record_locator VARCHAR(20),
    pnr_creation_date DATE,
    total_pax INTEGER,
	is_child BOOLEAN,
	basic_economy_pax INTEGER,
	is_stroller_user BOOLEAN,
	lap_child_count INTEGER
);


CREATE TABLE pnr_remark_level_data (
    record_locator VARCHAR(20),
    pnr_creation_date DATE,
    flight_number VARCHAR(20),
    special_service_request VARCHAR(100)
);

CREATE TABLE airports_data (
    airport_iata_code VARCHAR(10),
    iso_country_code VARCHAR(5)
);

CREATE TABLE bag_level_data (
    company_id VARCHAR(10),
    flight_number VARCHAR(20),
    scheduled_departure_date_local DATE,
    scheduled_departure_station_code VARCHAR(10),
    scheduled_arrival_station_code VARCHAR(10),
    bag_tag_unique_number VARCHAR(30),
    bag_tag_issue_date DATE,
    bag_type VARCHAR(20)
);

--DATA CLEANING
WITH duplicates AS (
    SELECT *,
           ROW_NUMBER() OVER (PARTITION BY bag_tag_unique_number ORDER BY bag_tag_unique_number) AS rn
    FROM bag_level_data
)
DELETE FROM bag_level_data
WHERE bag_tag_unique_number IN (
    SELECT bag_tag_unique_number FROM duplicates WHERE rn > 1
);



DELETE FROM flight_level_data
WHERE scheduled_ground_time_minutes <=0 ;



