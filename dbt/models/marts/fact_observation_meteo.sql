-- ============================================================
-- fact_observation_meteo
-- ============================================================
-- TABLE DE FAITS centrale du modèle dimensionnel.
-- Une ligne = une observation météo prise par une station à un instant t.
--
-- Volume attendu : ~4 950 lignes (4 sources unifiées dans intermediate).
--
-- ─── Rôle Kimball ────────────────────────────────────────────────
-- Cette table contient :
--   * Les MESURES (faits numériques additifs ou semi-additifs) :
--     temperature_c, humidity_pct, pressure_hpa, wind_speed_kmh, ...
--   * Les CLÉS ÉTRANGÈRES vers les dimensions :
--     station_sk → dim_weather_stations
--     date_sk    → dim_date
--   * Les DEGENERATE DIMENSIONS (attributs descriptifs sans dim dédiée) :
--     observation_ts_utc, source_network
--
-- ─── Clé naturelle composite ────────────────────────────────────
-- (station_sk, observation_ts_utc) est UNIQUE par construction. On l'a
-- vérifié dans int_observations_unified avec un HAVING COUNT(*) > 1
-- qui retournait 0 lignes. Cette clé est matérialisée en INDEX UNIQUE
-- ci-dessous (Étape 3).
--
-- ─── Pourquoi pas une surrogate key supplémentaire ? ────────────
-- Pour ce volume (~5k lignes), la clé composite naturelle est suffisante.
-- Si on passait à des milliards de lignes, on ajouterait observation_sk
-- (entier auto-incrément) pour des FK plus rapides à joindre. Pas le cas
-- ici.
--
-- ─── Index (Étape 3 : optimisation) ───────────────────────────────
-- 4 index pour couvrir les patterns d'usage attendus côté Data Science :
--
--   * (station_sk, observation_ts_utc) UNIQUE
--       → Triple rôle : (1) garde-fou anti-doublons,
--                       (2) accélère le pattern "historique d'une station
--                           sur une période" (cas le plus courant),
--                       (3) documente la granularité de la table.
--
--   * station_sk
--       → FK vers dim_weather_stations. Redondance partielle avec
--         l'index composite (la première colonne d'un composite est
--         utilisable seule), gardé pour la lisibilité du schéma et le
--         pattern recommandé "1 index par FK".
--
--   * date_sk
--       → FK vers dim_date. NON couvert par l'index composite, donc
--         strictement nécessaire pour les jointures et filtres calendaires.
--
--   * observation_ts_utc
--       → Filtres temporels CROSS-STATION ("entre 6h et 8h sur toutes
--         les stations"). NON couvert par le composite parce qu'il y
--         figure en 2e position (un index B-tree n'est utilisable que
--         si on filtre sur ses premières colonnes).
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
      "CREATE UNIQUE INDEX IF NOT EXISTS fact_observation_meteo_station_sk_observation_ts_utc_uk ON {{ this }} (station_sk, observation_ts_utc)",
      "CREATE INDEX IF NOT EXISTS fact_observation_meteo_station_sk_idx ON {{ this }} (station_sk)",
      "CREATE INDEX IF NOT EXISTS fact_observation_meteo_date_sk_idx ON {{ this }} (date_sk)",
      "CREATE INDEX IF NOT EXISTS fact_observation_meteo_observation_ts_utc_idx ON {{ this }} (observation_ts_utc)"
    ]
) }}

with observations_unified as (

    select * from {{ ref('int_observations_unified') }}

),

dim_stations as (

    select
        station_sk,
        station_id,
        source_network
    from {{ ref('dim_weather_stations') }}

),

dim_date_lookup as (

    select
        date_sk,
        date
    from {{ ref('dim_date') }}

),

with_foreign_keys as (

    select
        -- ─── Foreign keys vers les dimensions ────────────────────────
        ds.station_sk,
        dd.date_sk,

        -- ─── Clé naturelle (degenerate dimension : pas de dim dédiée) ──
        obs.observation_ts_utc,

        -- ─── Discriminant de provenance (degenerate dimension) ───────
        -- Aurait pu être promu en dim_source mais peu de variabilité
        -- (juste 2 valeurs) — on le garde dans la fact.
        obs.source_network,

        -- ─── MESURES atmosphériques (faits) ──────────────────────────
        obs.temperature_c,
        obs.dew_point_c,
        obs.humidity_pct,
        obs.pressure_hpa,

        -- ─── MESURES vent (faits) ────────────────────────────────────
        obs.wind_speed_kmh,
        obs.wind_gust_kmh,
        obs.wind_direction_deg,

        -- ─── MESURES précipitations (faits) ──────────────────────────
        -- Note : WU mesure rate/accum, InfoClimat mesure 1h/3h.
        -- Les colonnes manquantes par source sont à NULL (vu en intermediate).
        obs.precip_rate_mmh,
        obs.precip_accum_mm,
        obs.precip_1h_mm,
        obs.precip_3h_mm,

        -- ─── MESURES rayonnement (WU-only) ───────────────────────────
        obs.uv_index,
        obs.solar_wm2,

        -- ─── MESURES InfoClimat-only ─────────────────────────────────
        obs.visibility_m,
        obs.snow_depth_cm,
        obs.cloud_cover,
        obs.weather_code_omm,

        -- ─── Métadonnées de chargement ───────────────────────────────
        current_timestamp                                            as dbt_loaded_at

    from observations_unified obs

    -- Jointure dim stations : on utilise (station_id, source_network)
    -- comme clé naturelle composite. Une station_id seule ne suffit pas
    -- si jamais une autre source utilisait le même ID demain.
    inner join dim_stations ds
        on obs.station_id     = ds.station_id
       and obs.source_network = ds.source_network

    -- Jointure dim date : on cast le timestamp en date pour matcher.
    inner join dim_date_lookup dd
        on cast(obs.observation_ts_utc as date) = dd.date

)

select * from with_foreign_keys
