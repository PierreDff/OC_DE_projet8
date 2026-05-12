-- ============================================================
-- stg_infoclimat__stations
-- ============================================================
-- Staging des métadonnées des 4 stations InfoClimat (Hauts-de-France).
--
-- La table raw.raw_infoclimat ne contient qu'UNE ligne, dont la colonne
-- 'stations' est un ARRAY JSONB de 4 objets. On utilise jsonb_array_elements
-- pour "exploser" cet array en 4 lignes, puis on extrait les attributs avec
-- l'opérateur ->> (qui renvoie du text).
--
-- Stations attendues en sortie :
--   * 07015      Lille-Lesquin   (type 'synop'   — station professionnelle)
--   * 00052      Armentières     (type 'static'  — station amateur)
--   * 000R5      Bergues         (type 'static')
--   * STATIC0010 Hazebrouck      (type 'static')
--
-- ⚠️ AUCUNE harmonisation avec les stations WU ici. L'unification des
--    référentiels stations (InfoClimat + WU) se fait dans intermediate.

with source as (

    select
        stations,
        _airbyte_raw_id,
        _airbyte_extracted_at
    from {{ source('raw', 'raw_infoclimat') }}

),

exploded as (

    -- jsonb_array_elements explose l'array en 1 ligne par élément.
    -- LATERAL n'est pas obligatoire en Postgres mais explicite l'intention :
    -- on génère des lignes EN FONCTION de la ligne source.
    select
        s.station_json,
        source._airbyte_raw_id,
        source._airbyte_extracted_at
    from source,
         jsonb_array_elements(source.stations) as s(station_json)

),

cleaned as (

    select
        -- ─── Identifiants & nom ──────────────────────────────────────
        station_json ->> 'id'                              as station_id,
        station_json ->> 'name'                            as station_name,

        -- ─── Coordonnées géographiques ───────────────────────────────
        (station_json ->> 'latitude')::numeric             as latitude,
        (station_json ->> 'longitude')::numeric            as longitude,
        (station_json ->> 'elevation')::numeric            as elevation_m,

        -- ─── Type de station ─────────────────────────────────────────
        -- 'synop' = station synoptique professionnelle (réseau MétéoFrance)
        -- 'static' = station amateur fixe
        station_json ->> 'type'                            as station_type,

        -- ─── Licence & traçabilité ───────────────────────────────────
        station_json #>> '{license,license}'               as license_code,
        station_json #>> '{license,source}'                as license_source,
        station_json #>> '{license,url}'                   as license_url,

        -- ─── Lignage Airbyte ─────────────────────────────────────────
        _airbyte_raw_id,
        _airbyte_extracted_at

    from exploded

)

select * from cleaned
