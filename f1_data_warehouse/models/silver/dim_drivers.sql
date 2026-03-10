{{
  config(
    materialized='table',
    schema='silver',
    tags=['silver', 'dimension', 'drivers']
  )
}}

/*
  dim_drivers
  -----------
  Cleaned and deduplicated driver dimension from the Bronze layer.
  One row per unique driver per season.
  Deduplication keeps the most recent record per driver_number + season.
*/

with source as (

    select * from {{ source('bronze', 'openf1_drivers') }}

),

deduplicated as (

    select *
    from source
    qualify row_number() over (
        partition by driver_number, season
        order by ingest_timestamp desc
    ) = 1

),

final as (

    select
        -- Surrogate key
        {{ dbt_utils.generate_surrogate_key(['driver_number', 'season']) }} as driver_sk,

        -- Natural key
        cast(driver_number as int)    as driver_number,
        cast(season as int)           as season,

        -- Driver identity
        upper(trim(name_acronym))     as driver_code,
        trim(full_name)               as full_name,
        trim(first_name)              as first_name,
        trim(last_name)               as last_name,
        trim(broadcast_name)          as broadcast_name,

        -- Team info
        trim(team_name)               as team_name,
        upper(trim(team_colour))      as team_colour_hex,

        -- Nationality
        upper(trim(country_code))     as country_code,

        -- Media
        headshot_url,

        -- Metadata
        ingest_timestamp

    from deduplicated

)

select * from final