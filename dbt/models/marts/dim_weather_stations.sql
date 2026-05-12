-- ============================================================
-- dim_weather_stations
-- ============================================================
-- Table de dimension des 6 stations météo du périmètre Forecast 2.0.
-- Réponse directe à l'exigence Mission :
--   « Intégrer explicitement les métadonnées des stations amateurs dans
--     une table de dimension dédiée (ex : dim_weather_stations). »
--
-- ─── Différences clés avec la couche intermediate ─────────────────
--
-- 1. MATÉRIALISÉE EN TABLE (et pas en vue)
--    Configurée via {{ config(materialized='table') }}.
--    DBT exécute un CREATE TABLE AS SELECT au lieu d'un CREATE VIEW.
--    Ça stocke physiquement les 6 lignes sur disque → les Data Scientists
--    n'ont plus à recalculer le UNION + filtres à chaque requête.
--
-- 2. SURROGATE KEY (station_sk)
--    On ajoute une clé technique générée par DBT via la macro
--    dbt_utils.generate_surrogate_key. Elle hashe (md5) la combinaison
--    (station_id, source_network) en un identifiant stable.
--    C'est elle qui sera utilisée comme FK dans fact_observation_meteo.
--
--    Pourquoi pas un simple ROW_NUMBER() ? Parce qu'un ROW_NUMBER change
--    si l'ordre du SELECT change, ce qui casserait les FK. Le hash est
--    déterministe : tant que (station_id, source_network) ne change pas,
--    station_sk ne change pas non plus.
--
-- 3. ORDRE DES COLONNES SOIGNÉ
--    PK en premier, puis attributs métier (ce que les DS regarderont
--    en premier), puis attributs techniques en fin.
--
-- ─── Index (Étape 3 : optimisation) ───────────────────────────────
--   * station_sk (UNIQUE) → PK technique, accélère les jointures FK
--     depuis fact_observation_meteo
--   * (station_id, source_network) → clé naturelle, utile pour les
--     lookups par identifiant métier et pour les futurs MERGE en mode
--     incrémental. station_id en première position car plus discriminant
--     (6 valeurs distinctes vs 2 pour source_network).
--
-- Les index sont créés via post_hook (et non via la syntaxe `indexes` de
-- dbt-postgres) pour pouvoir leur donner des noms explicites — la syntaxe
-- `indexes` ne supporte pas la clé `name` et génère des noms hashés MD5.
--
-- Convention de nommage des index :
--   <table>_<colonnes>_uk   pour les index UNIQUE
--   <table>_<colonnes>_idx  pour les index standards

{{ config(
    materialized='table',
    schema='marts',
    post_hook=[
      "CREATE UNIQUE INDEX IF NOT EXISTS dim_weather_stations_station_sk_uk ON {{ this }} (station_sk)",
      "CREATE INDEX IF NOT EXISTS dim_weather_stations_station_id_source_network_idx ON {{ this }} (station_id, source_network)"
    ]
) }}

with stations_unified as (

    select * from {{ ref('int_stations_unified') }}

),

with_surrogate_key as (

    select
        -- ─── Clé primaire technique (surrogate key) ──────────────────
        -- Hash MD5 de la clé naturelle. Stable tant que (station_id,
        -- source_network) reste identique. Permet une jointure par un
        -- entier-comme-string court et indexable.
        {{ dbt_utils.generate_surrogate_key(['station_id', 'source_network']) }} as station_sk,

        -- ─── Clé naturelle (gardée pour traçabilité & debug) ─────────
        station_id,
        source_network,

        -- ─── Identité de la station ──────────────────────────────────
        station_name,
        station_class,                  -- 'professional' / 'amateur'
        station_type,                   -- InfoClimat-only : 'synop' / 'static'

        -- ─── Géolocalisation ─────────────────────────────────────────
        latitude,
        longitude,
        elevation_m,
        city,
        state,
        country,

        -- ─── Instrumentation (WU-only) ───────────────────────────────
        hardware,
        software,

        -- ─── Licence / source (InfoClimat-only) ──────────────────────
        license_code,
        license_source,

        -- ─── Métadonnées de chargement ───────────────────────────────
        current_timestamp                                                    as dbt_loaded_at

    from stations_unified

)

select * from with_surrogate_key
