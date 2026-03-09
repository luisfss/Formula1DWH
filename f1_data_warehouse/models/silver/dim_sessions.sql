{{
  config(
    materialized='table',
    schema='silver',
    tags=['silver', 'dimension', 'sessions']
  )
}}

/*
  dim_sessions
  ------------
  Cleaned session dimension — one row per session_key.
  Covers all session types (Race, Qualifying, Sprint, FP1-3).
*/

with source as (

    select * from {{ source('bronze', 'openf1_sessions') }}

),

final as (

    select
        -- Surrogate key
        {{ dbt_utils.generate_surrogate_key(['session_key']) }} as session_sk,

        -- Natural keys
        cast(session_key as int)    as session_key,
        cast(meeting_key as int)    as meeting_key,
        cast(year as int)           as season,

        -- Session details
        trim(session_name)          as session_name,
        trim(session_type)          as session_type,

        -- Timing
        cast(date_start as timestamp) as session_start_utc,
        cast(date_end as timestamp)   as session_end_utc,
        trim(gmt_offset)              as gmt_offset,

        -- Location
        trim(location)              as location,
        upper(trim(country_code))   as country_code,
        trim(country_name)          as country_name,
        cast(circuit_key as int)    as circuit_key,
        trim(circuit_short_name)    as circuit_short_name,
        cast(country_key as int)    as country_key,

        -- Derived flags
        case
            when lower(trim(session_type)) = 'race' then true
            else false
        end as is_race_session,

        case
            when lower(trim(session_type)) in ('qualifying', 'sprint qualifying') then true
            else false
        end as is_qualifying_session,

        -- Metadata
        ingest_timestamp

    from source

)

select * from final