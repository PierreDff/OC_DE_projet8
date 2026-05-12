-- ============================================================
-- int_stations_unified
-- ============================================================
-- Référentiel unifié des 6 stations météo du périmètre Forecast 2.0.
--
-- Empile :
--   * Les 4 stations InfoClimat (Hauts-de-France)  → stg_infoclimat__stations
--   * Les 2 stations Weather Underground            → wu_stations_metadata (seed)
--
-- ─── Classification pro / amateur ─────────────────────────────────
-- L'API InfoClimat ne référence que des stations PROFESSIONNELLES :
--   * type='synop'  : station synoptique officielle MétéoFrance
--   * type='static' : station InfoClimat pro, non-synoptique
--   → Les deux types sont PROFESSIONNELS. La différence est un protocole
--     d'instrumentation, pas un niveau de qualité.
--
-- Les seules stations amateurs du périmètre sont les 2 stations Weather
-- Underground (citoyens qui ont enregistré leur station personnelle).

with infoclimat_stations as (

    select
        station_id,
        station_name,
        'infoclimat'::text                                        as source_network,
        latitude,
        longitude,
        elevation_m,
        station_name                                              as city,
        cast(null as varchar)                                     as state,
        'FR'::varchar(2)                                          as country,

        -- Type d'instrumentation : on garde la distinction synop/static
        -- pour les Data Scientists qui voudraient affiner leurs analyses
        station_type,

        -- Classification métier : TOUTES les stations InfoClimat sont pro
        'professional'::text                                      as station_class,

        -- Attributs WU-only mis à NULL
        cast(null as varchar)                                     as hardware,
        cast(null as varchar)                                     as software,

        -- Attributs InfoClimat-only
        license_code,
        license_source

    from {{ ref('stg_infoclimat__stations') }}

),

wu_stations as (

    select
        station_id,
        station_name,
        'weather_underground'::text                               as source_network,
        latitude,
        longitude,
        elevation_m,
        city,
        state,
        country,

        -- WU n'a pas de notion synop/static
        cast(null as varchar)                                     as station_type,

        -- Classification métier : TOUTES les stations WU sont amateurs
        'amateur'::text                                           as station_class,

        hardware,
        software,

        -- Attributs InfoClimat-only mis à NULL
        cast(null as varchar)                                     as license_code,
        cast(null as varchar)                                     as license_source

    from {{ ref('wu_stations_metadata') }}

),

unified as (

    select * from infoclimat_stations
    union all
    select * from wu_stations

)

select * from unified
