-- ============================================================
-- stg_wu__ichtegem
-- ============================================================
-- Staging pour la station Weather Underground IICHTE19 (WeerstationBS, BE).
--
-- Structure strictement identique à stg_wu__la_madeleine :
--   * Mêmes colonnes raw (Airbyte a créé les 2 tables avec le même schéma)
--   * Mêmes unités impériales (°F, mph, inHg, in)
--   * Même fuseau horaire (Europe/Brussels = Europe/Paris pour notre fenêtre)
--
-- La SEULE différence est l'ID de station injecté en dur ('IICHTE19').
--
-- ⚠️ AUCUNE conversion d'unités ici. Les conversions vers SI sont faites dans
--    la couche intermediate, après UNION avec les autres sources.

with source as (

    select * from {{ source('raw', 'raw_ichtegem') }}

),

cleaned as (

    select
        -- ─── Identifiants ────────────────────────────────────────────
        'IICHTE19'::text                                                       as station_id,

        -- Timestamp local (sera converti en UTC dans intermediate)
        ("Date" || ' ' || "Time")::timestamp                                   as observation_ts_local,

        -- ─── Mesures atmosphériques (unités IMPÉRIALES) ──────────────
        nullif(regexp_replace("Temperature",    '[^0-9.\-]+$', ''), '')::numeric  as temperature_f,
        nullif(regexp_replace("Dew_Point",      '[^0-9.\-]+$', ''), '')::numeric  as dew_point_f,
        nullif(regexp_replace("Humidity",       '[^0-9.\-]+$', ''), '')::numeric  as humidity_pct,
        nullif(regexp_replace("Pressure",       '[^0-9.\-]+$', ''), '')::numeric  as pressure_inhg,

        -- ─── Vent ─────────────────────────────────────────────────────
        nullif("Wind", '')                                                     as wind_direction_cardinal,
        nullif(regexp_replace("Speed",          '[^0-9.\-]+$', ''), '')::numeric  as wind_speed_mph,
        nullif(regexp_replace("Gust",           '[^0-9.\-]+$', ''), '')::numeric  as wind_gust_mph,

        -- ─── Précipitations ──────────────────────────────────────────
        nullif(regexp_replace("Precip__Rate_",  '[^0-9.\-]+$', ''), '')::numeric  as precip_rate_inh,
        nullif(regexp_replace("Precip__Accum_", '[^0-9.\-]+$', ''), '')::numeric  as precip_accum_in,

        -- ─── Rayonnement ─────────────────────────────────────────────
        "UV"::numeric                                                          as uv_index,
        nullif(regexp_replace("Solar",          '[^0-9.\-]+$', ''), '')::numeric  as solar_wm2,

        -- ─── Lignage Airbyte ─────────────────────────────────────────
        _airbyte_raw_id,
        _airbyte_extracted_at

    from source

)

select * from cleaned
