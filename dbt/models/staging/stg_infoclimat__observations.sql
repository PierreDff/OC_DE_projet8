-- ============================================================
-- stg_infoclimat__observations
-- ============================================================
-- Staging des ~1 143 observations horaires des 4 stations InfoClimat.
--
-- La colonne 'hourly' de raw.raw_infoclimat est un DICT JSONB :
--   {
--     "07015":      [{obs1}, {obs2}, ...],   ← 60 obs (Lille-Lesquin, synop)
--     "00052":      [{obs1}, {obs2}, ...],   ← 361 obs (Armentières)
--     "000R5":      [{obs1}, {obs2}, ...],   ← 361 obs (Bergues)
--     "STATIC0010": [{obs1}, {obs2}, ...],   ← 361 obs (Hazebrouck)
--     "_params":    {...}                    ← clé parasite à filtrer
--   }
--
-- On déroule ce dict en 2 étapes :
--   1. jsonb_each(hourly)            → 1 ligne par station_id
--   2. jsonb_array_elements(value)   → 1 ligne par observation
--
-- ⚠️ Données déjà en système international (°C, hPa, km/h, mm) — pas comme WU !
--    Mais on garde la philosophie "staging = pas de transformation métier" :
--    on ne fait que parser et caster, l'unification avec WU se fera dans intermediate.

with source as (

    select
        hourly,
        _airbyte_raw_id,
        _airbyte_extracted_at
    from {{ source('raw', 'raw_infoclimat') }}

),

-- Étape 1 : exploser le dict {station_id: [obs, ...]} en (key, value)
station_groups as (

    select
        kv.key                              as station_id,
        kv.value                            as observations_array,
        source._airbyte_raw_id,
        source._airbyte_extracted_at
    from source,
         jsonb_each(source.hourly) as kv

    -- Filtrer les clés "techniques" qui ne sont PAS des station_id.
    -- InfoClimat utilise '_params' pour décrire les paramètres de la requête.
    -- On échappe le '_' (caractère spécial dans LIKE) avec un backslash.
    where kv.key not like '\_%'

),

-- Étape 2 : exploser chaque array d'observations en lignes individuelles
observations_exploded as (

    select
        sg.station_id,
        obs.observation_json,
        sg._airbyte_raw_id,
        sg._airbyte_extracted_at
    from station_groups sg,
         jsonb_array_elements(sg.observations_array) as obs(observation_json)

),

cleaned as (

    select
        -- ─── Identifiants ────────────────────────────────────────────
        station_id,

        -- L'observation a aussi un id_station interne — on le garde pour
        -- vérification (doit être identique à station_id).
        observation_json ->> 'id_station'                                            as id_station_in_obs,

        -- Timestamp de l'observation (déjà en UTC, contrairement à WU !)
        (observation_json ->> 'dh_utc')::timestamp                                   as observation_ts_utc,

        -- ─── Mesures atmosphériques (unités SI : °C, hPa, %) ─────────
        nullif(observation_json ->> 'temperature',    '')::numeric                   as temperature_c,
        nullif(observation_json ->> 'pression',       '')::numeric                   as pressure_hpa,
        nullif(observation_json ->> 'humidite',       '')::numeric                   as humidity_pct,
        nullif(observation_json ->> 'point_de_rosee', '')::numeric                   as dew_point_c,

        -- ─── Visibilité (en mètres, mesurée seulement par 07015 synop) ───
        nullif(observation_json ->> 'visibilite',     '')::numeric                   as visibility_m,

        -- ─── Vent (km/h pour vitesse, degrés pour direction) ─────────
        nullif(observation_json ->> 'vent_moyen',     '')::numeric                   as wind_speed_kmh,
        nullif(observation_json ->> 'vent_rafales',   '')::numeric                   as wind_gust_kmh,
        nullif(observation_json ->> 'vent_direction', '')::numeric                   as wind_direction_deg,

        -- ─── Précipitations (mm cumulés sur 1h ou 3h) ────────────────
        nullif(observation_json ->> 'pluie_1h',       '')::numeric                   as precip_1h_mm,
        nullif(observation_json ->> 'pluie_3h',       '')::numeric                   as precip_3h_mm,

        -- ─── Conditions diverses (souvent NULL hors stations synop) ──
        nullif(observation_json ->> 'neige_au_sol',   '')::numeric                   as snow_depth_cm,
        nullif(observation_json ->> 'nebulosite',     '')                            as cloud_cover,
        nullif(observation_json ->> 'temps_omm',      '')                            as weather_code_omm,

        -- ─── Lignage Airbyte ─────────────────────────────────────────
        _airbyte_raw_id,
        _airbyte_extracted_at

    from observations_exploded

)

select * from cleaned
