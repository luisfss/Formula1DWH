{{
  config(
    materialized='table',
    schema='silver',
    tags=['silver', 'fact', 'laps'],
    partition_by={
      'field': 'session_key',
      'data_type': 'int'
    }
  )
}}

/*
  fct_lap_times
  -------------
  Granular lap-level fact table — one row per driver per lap per session.
  Enriched with driver and session context for analytics-ready queries.
*/

with laps as (

    select * from {{ source('bronze', 'openf1_laps') }}

),

sessions as (

    select
        session_key,
        meeting_key,
        season,
        location,
        country_name,
        circuit_short_name,
        session_type,
        session_start_utc
    from {{ ref('dim_sessions') }}

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

stints as (

    select * from {{ source('bronze', 'openf1_stints') }}

),

enriched as (

    select
        -- Surrogate key
        {{ dbt_utils.generate_surrogate_key(['l.session_key', 'l.driver_number', 'l.lap_number']) }} as lap_sk,

        -- FKs
        l.session_key,
        s.meeting_key,
        s.season,
        d.driver_sk,
        l.driver_number,

        -- Race context
        s.location,
        s.country_name,
        s.circuit_short_name,
        s.session_type,
        s.session_start_utc                                    as race_date_utc,

        -- Driver context
        d.driver_code,
        d.full_name                                             as driver_name,
        d.team_name,

        -- Lap details
        l.lap_number,
        cast(l.date_start as timestamp)                         as lap_start_utc,
        l.is_pit_out_lap,

        -- Lap timing (seconds, rounded)
        round(l.lap_duration, 3)                               as lap_time_s,
        round(l.duration_sector_1, 3)                          as sector_1_s,
        round(l.duration_sector_2, 3)                          as sector_2_s,
        round(l.duration_sector_3, 3)                          as sector_3_s,

        -- Speed traps (km/h)
        l.i1_speed,
        l.i2_speed,
        l.st_speed                                              as finish_straight_speed_kph,

        -- Tyre context from stints
        st.compound                                             as tyre_compound,
        st.stint_number,
        (l.lap_number - st.lap_start + 1)                      as tyre_age_laps,

        -- Flag: is this a representative clean lap?
        case
            when l.is_pit_out_lap = false
             and l.lap_duration is not null
             and l.lap_duration < (
                 avg(l.lap_duration) over (
                     partition by l.session_key, l.driver_number
                 ) * 1.10   -- within 110% of driver's own average
             )
            then true
            else false
        end                                                     as is_clean_lap,

        -- Metadata
        current_timestamp()                                     as transformed_at

    from laps l
    inner join sessions s
        on l.session_key = s.session_key
    inner join drivers d
        on l.driver_number = d.driver_number
        and s.season = d.season
    left join stints st
        on l.session_key = st.session_key
        and l.driver_number = st.driver_number
        and l.lap_number between st.lap_start and st.lap_end

)

select * from enriched