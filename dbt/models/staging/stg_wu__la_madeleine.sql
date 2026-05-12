-- ============================================================
-- stg_wu__la_madeleine
-- ============================================================
-- Staging pour la station Weather Underground ILAMAD25 (La Madeleine, FR).
--
-- Philosophie "staging = nettoyage minimal" :
--   1. Renommer les colonnes en snake_case
--   2. Parser les valeurs string contenant l'unité ("56.2 °F" -> 56.2)
--   3. Combiner Date + Time en un seul timestamp
--   4. Forcer les types numeric pour préparer les calculs
--
-- ⚠️ AUCUNE conversion d'unités ici. Les °F, mph, inHg, in restent tels quels.
--    Les conversions vers le système SI (°C, km/h, hPa, mm) sont faites dans la
--    couche intermediate, où l'on harmonise avec InfoClimat.
--
-- ⚠️ Le timestamp WU est en HEURE LOCALE (Europe/Paris pour cette station).
--    L'alignement vers UTC est fait dans intermediate.
--
-- Note technique : les valeurs raw utilisent un espace INSÉCABLE (U+00A0) entre
-- nombre et unité, pas un espace classique. La regex '[^0-9.\-]+$' supprime
-- tout suffixe non-numérique (chiffre/point/moins) sans s'en soucier.

with source as (

    select * from {{ source('raw', 'raw_madeleine') }}

),

cleaned as (

    select
        -- ─── Identifiants ────────────────────────────────────────────
        -- 1 fichier source = 1 station, on la met en dur
        'ILAMAD25'::text                                                       as station_id,

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
        -- UV est déjà numeric côté raw (Airbyte a inféré le type), pas de regex
        "UV"::numeric                                                          as uv_index,
        nullif(regexp_replace("Solar",          '[^0-9.\-]+$', ''), '')::numeric  as solar_wm2,

        -- ─── Lignage Airbyte (utile en debug & audit) ────────────────
        _airbyte_raw_id,
        _airbyte_extracted_at

    from source

)

select * from cleaned
