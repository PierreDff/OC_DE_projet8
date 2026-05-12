-- ============================================================
-- int_wu__ichtegem
-- ============================================================
-- Couche intermediate pour la station belge IICHTE19 (WeerstationBS).
--
-- Strictement identique à int_wu__la_madeleine en logique : mêmes
-- conversions impérial → SI, même fuseau horaire (Europe/Brussels =
-- Europe/Paris pour notre fenêtre temporelle), même structure de sortie.
--
-- La SEULE différence est la source : ref('stg_wu__ichtegem').

with stg_observations as (

    select * from {{ ref('stg_wu__ichtegem') }}

),

stations_metadata as (

    select * from {{ ref('wu_stations_metadata') }}

),

converted as (

    select
        -- ─── Identifiants ────────────────────────────────────────────
        obs.station_id,
        'weather_underground'::text                                          as source_network,

        -- ─── Timestamp local → UTC ───────────────────────────────────
        -- Europe/Brussels = Europe/Paris (même fuseau horaire CEST/CET)
        (obs.observation_ts_local at time zone 'Europe/Paris')::timestamp    as observation_ts_utc,

        -- ─── Conversions impérial → SI ───────────────────────────────
        round(((obs.temperature_f - 32) * 5.0 / 9.0)::numeric, 2)            as temperature_c,
        round(((obs.dew_point_f   - 32) * 5.0 / 9.0)::numeric, 2)            as dew_point_c,
        obs.humidity_pct                                                     as humidity_pct,
        round((obs.pressure_inhg * 33.8639)::numeric, 2)                     as pressure_hpa,
        round((obs.wind_speed_mph * 1.609344)::numeric, 2)                   as wind_speed_kmh,
        round((obs.wind_gust_mph  * 1.609344)::numeric, 2)                   as wind_gust_kmh,
        {{ cardinal_to_degrees('obs.wind_direction_cardinal') }}             as wind_direction_deg,
        round((obs.precip_rate_inh   * 25.4)::numeric, 2)                    as precip_rate_mmh,
        round((obs.precip_accum_in   * 25.4)::numeric, 2)                    as precip_accum_mm,

        -- ─── Mesures gardées telles quelles ──────────────────────────
        obs.uv_index                                                         as uv_index,
        obs.solar_wm2                                                        as solar_wm2,

        -- ─── Mesures InfoClimat-only mises à NULL (préparation UNION) ───
        cast(null as numeric)                                                as visibility_m,
        cast(null as numeric)                                                as precip_1h_mm,
        cast(null as numeric)                                                as precip_3h_mm,
        cast(null as numeric)                                                as snow_depth_cm,
        cast(null as varchar)                                                as cloud_cover,
        cast(null as varchar)                                                as weather_code_omm,

        -- ─── Lignage Airbyte ─────────────────────────────────────────
        obs._airbyte_raw_id,
        obs._airbyte_extracted_at

    from stg_observations as obs

    inner join stations_metadata as meta
        on obs.station_id = meta.station_id

)

select * from converted
