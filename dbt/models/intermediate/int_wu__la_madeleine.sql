-- ============================================================
-- int_wu__la_madeleine
-- ============================================================
-- Couche intermediate : on prend la vue staging brute (toujours en unités
-- impériales et timestamp local) et on l'harmonise vers le standard SI/UTC
-- qui sera celui de la table de faits finale.
--
-- 4 transformations principales :
--   1. Conversions d'unités : °F → °C, mph → km/h, inHg → hPa, in → mm
--   2. Direction du vent : cardinal ('NNW') → degrés (337.5) via macro
--   3. Timestamp : heure locale Europe/Paris → UTC
--   4. Enrichissement : jointure avec le seed wu_stations_metadata pour
--      ajouter le nom, la ville, le pays, le hardware/software
--
-- ⚠️ Schéma de sortie aligné avec InfoClimat pour préparer le UNION ALL :
--    station_id, observation_ts_utc, temperature_c, pressure_hpa, etc.
--
-- ⚠️ source_network = 'weather_underground' (utile dans le UNION pour
--    distinguer l'origine de chaque ligne).

with stg_observations as (

    select * from {{ ref('stg_wu__la_madeleine') }}

),

stations_metadata as (

    -- Le seed contient les métadonnées des 2 stations WU. Ici on ne joint
    -- que celle de Madeleine (filtre sur station_id), mais on garde la
    -- structure de jointure en cas d'évolution.
    select * from {{ ref('wu_stations_metadata') }}

),

converted as (

    select
        -- ─── Identifiants ────────────────────────────────────────────
        obs.station_id,
        'weather_underground'::text                                          as source_network,

        -- ─── Timestamp local → UTC ───────────────────────────────────
        -- AT TIME ZONE 'Europe/Paris' interprète le timestamp naïf comme
        -- heure locale, puis le convertit en UTC. Pendant CEST (heure d'été
        -- en oct 2024), Europe/Paris = UTC+2, donc 00:04 local → 22:04 UTC
        -- la veille.
        (obs.observation_ts_local at time zone 'Europe/Paris')::timestamp    as observation_ts_utc,

        -- ─── Conversions impérial → SI ───────────────────────────────
        -- Température : (°F − 32) × 5/9
        round(((obs.temperature_f - 32) * 5.0 / 9.0)::numeric, 2)            as temperature_c,
        round(((obs.dew_point_f   - 32) * 5.0 / 9.0)::numeric, 2)            as dew_point_c,

        -- Humidité : déjà en % côté WU, pas de conversion
        obs.humidity_pct                                                     as humidity_pct,

        -- Pression : inHg × 33.8639 = hPa
        round((obs.pressure_inhg * 33.8639)::numeric, 2)                     as pressure_hpa,

        -- Vitesse vent : mph × 1.609344 = km/h
        round((obs.wind_speed_mph * 1.609344)::numeric, 2)                   as wind_speed_kmh,
        round((obs.wind_gust_mph  * 1.609344)::numeric, 2)                   as wind_gust_kmh,

        -- Direction vent : cardinal → degrés via macro réutilisable
        {{ cardinal_to_degrees('obs.wind_direction_cardinal') }}             as wind_direction_deg,

        -- Précipitations : in × 25.4 = mm
        -- Note : précip_rate est en in/h, devient mm/h. On le préfixe pour
        -- éviter la confusion avec un cumul.
        round((obs.precip_rate_inh   * 25.4)::numeric, 2)                    as precip_rate_mmh,
        round((obs.precip_accum_in   * 25.4)::numeric, 2)                    as precip_accum_mm,

        -- ─── Mesures gardées telles quelles (déjà en SI) ─────────────
        obs.uv_index                                                         as uv_index,
        obs.solar_wm2                                                        as solar_wm2,

        -- ─── Mesures InfoClimat-only mises à NULL (préparation UNION) ───
        -- Ces grandeurs ne sont PAS mesurées par WU. On les déclare ici à
        -- NULL pour que le schéma soit identique à celui d'InfoClimat et
        -- qu'on puisse faire un UNION ALL sans tordre la structure.
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

    -- Jointure avec le seed sur station_id (= 'ILAMAD25').
    -- Pas strictement nécessaire ici puisqu'on n'utilise pas les colonnes
    -- du seed dans le SELECT (les métadonnées seront utilisées dans la
    -- dimension marts). Mais on valide la cohérence : si station_id n'a
    -- pas de match dans le seed, INNER JOIN supprimera les lignes —
    -- garde-fou utile.
    inner join stations_metadata as meta
        on obs.station_id = meta.station_id

)

select * from converted
