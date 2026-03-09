{{
  config(
    materialized='table',
    schema='silver',
    tags=['silver', 'fact', 'race_results'],
    partition_by={
      'field': 'season',
      'data_type': 'int'
    }
  )
}}

/*
  fct_race_results
  ----------------
  Race-level fact table — one row per driver per race session.
  Aggregates lap data to compute final race results:
    - total laps completed
    - best lap time
    - average lap time (excl. pit-out laps)
    - total pit stops
    - final finishing position (last recorded position)
*/

with laps as (

    select * from {{ source('bronze', 'openf1_laps') }}

),

pit_stops as (

    select * from {{ source('bronze', 'openf1_pit') }}

),

sessions as (

    select
        session_key,
        meeting_key,
        season,
        session_name,
        session_type,
        location,
        country_code,
        country_name,
        circuit_short_name,
        session_start_utc
    from {{ ref('dim_sessions') }}
    where is_race_session = true

),

drivers as (

    select
        driver_number,
        driver_sk,
        driver_code,
        full_name,
        team_name,
        season
    from {{ ref('dim_drivers') }}

),

-- Aggregate laps per driver per session
lap_aggregates as (

    select
        session_key,
        driver_number,

        count(*)                                                        as total_laps,
        min(lap_duration)                                               as best_lap_time_s,

        -- Average excluding pit-out laps and nulls (dirty laps)
        avg(
            case when is_pit_out_lap = false and lap_duration is not null
                then lap_duration
            end
        )                                                               as avg_clean_lap_time_s,

        -- Sector bests
        min(duration_sector_1)                                          as best_s1_time_s,
        min(duration_sector_2)                                          as best_s2_time_s,
        min(duration_sector_3)                                          as best_s3_time_s,

        -- Top speed
        max(st_speed)                                                   as max_speed_kph,

        -- Last lap number = laps completed
        max(lap_number)                                                 as laps_completed

    from laps
    group by session_key, driver_number

),

-- Aggregate pit stops per driver per session
pit_aggregates as (

    select
        session_key,
        driver_number,
        count(*)                                                        as total_pit_stops,
        sum(stop_duration)                                              as total_stop_duration_s,
        min(stop_duration)                                              as fastest_pit_stop_s
    from pit_stops
    group by session_key, driver_number

),

joined as (

    select
        -- Surrogate key
        {{ dbt_utils.generate_surrogate_key(['l.session_key', 'l.driver_number']) }} as race_result_sk,

        -- FKs
        s.session_key,
        s.meeting_key,
        s.season,
        d.driver_sk,
        l.driver_number,

        -- Session context
        s.session_name,
        s.location,
        s.country_code,
        s.country_name,
        s.circuit_short_name,
        s.session_start_utc                                             as race_date_utc,

        -- Driver context
        d.driver_code,
        d.full_name                                                     as driver_name,
        d.team_name,

        -- Lap metrics
        l.total_laps,
        l.laps_completed,
        round(l.best_lap_time_s, 3)                                     as best_lap_time_s,
        round(l.avg_clean_lap_time_s, 3)                                as avg_clean_lap_time_s,
        round(l.best_s1_time_s, 3)                                      as best_s1_time_s,
        round(l.best_s2_time_s, 3)                                      as best_s2_time_s,
        round(l.best_s3_time_s, 3)                                      as best_s3_time_s,
        l.max_speed_kph,

        -- Pit metrics
        coalesce(p.total_pit_stops, 0)                                  as total_pit_stops,
        round(p.total_stop_duration_s, 3)                               as total_stop_duration_s,
        round(p.fastest_pit_stop_s, 3)                                  as fastest_pit_stop_s,

        -- Metadata
        current_timestamp()                                             as transformed_at

    from lap_aggregates l
    inner join sessions s
        on l.session_key = s.session_key
    inner join drivers d
        on l.driver_number = d.driver_number
        and s.season = d.season
    left join pit_aggregates p
        on l.session_key = p.session_key
        and l.driver_number = p.driver_number

)

select * from joined