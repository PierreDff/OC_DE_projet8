-- ============================================================
-- int_infoclimat__observations
-- ============================================================
-- Couche intermediate pour les observations InfoClimat.
--
-- Contrairement aux WU, AUCUNE conversion d'unités n'est nécessaire :
--   * Températures : déjà en °C
--   * Pressions    : déjà en hPa
--   * Vitesses vent: déjà en km/h
--   * Direction    : déjà en degrés (0-360)
--   * Précips      : déjà en mm
--   * Timestamps   : déjà en UTC (champ 'dh_utc' dans le JSON source)
--
-- Le seul rôle de ce modèle est d'ALIGNER LE SCHÉMA sur celui des modèles
-- int_wu__* pour préparer le UNION ALL dans int_observations_unified :
--   1. Ajouter source_network = 'infoclimat'
--   2. Mettre à NULL les colonnes WU-only (solar_wm2, uv_index, precip_rate,
--      precip_accum) pour avoir le même nombre de colonnes dans le même ordre
--   3. Garder les colonnes InfoClimat-only (visibility_m, snow_depth_cm,
--      cloud_cover, weather_code_omm, precip_1h_mm, precip_3h_mm) qui
--      étaient déjà à NULL dans int_wu__*

with stg_observations as (

    select * from {{ ref('stg_infoclimat__observations') }}

),

aligned as (

    select
        -- ─── Identifiants ────────────────────────────────────────────
        station_id,
        'infoclimat'::text                          as source_network,

        -- ─── Timestamp (déjà en UTC, pas de conversion) ──────────────
        observation_ts_utc,

        -- ─── Mesures atmosphériques (déjà en SI) ─────────────────────
        temperature_c,
        dew_point_c,
        humidity_pct,
        pressure_hpa,

        -- ─── Vent (déjà en SI + déjà en degrés) ──────────────────────
        wind_speed_kmh,
        wind_gust_kmh,
        wind_direction_deg,

        -- ─── Précipitations WU-only mises à NULL ─────────────────────
        -- WU mesure un "rate" instantané et un "accum" cumulé sur la journée.
        -- InfoClimat ne fournit pas ces grandeurs (il fournit pluie_1h et
        -- pluie_3h à la place).
        cast(null as numeric)                       as precip_rate_mmh,
        cast(null as numeric)                       as precip_accum_mm,

        -- ─── Mesures WU-only mises à NULL ────────────────────────────
        cast(null as numeric)                       as uv_index,
        cast(null as numeric)                       as solar_wm2,

        -- ─── Mesures InfoClimat-only (gardées) ───────────────────────
        visibility_m,
        precip_1h_mm,
        precip_3h_mm,
        snow_depth_cm,
        cloud_cover,
        weather_code_omm,

        -- ─── Lignage Airbyte ─────────────────────────────────────────
        _airbyte_raw_id,
        _airbyte_extracted_at

    from stg_observations

)

select * from aligned
