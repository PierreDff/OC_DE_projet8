-- ============================================================
-- dim_date
-- ============================================================
-- Dimension calendaire : 1 ligne par jour calendaire.
-- Couvre 2024 + 2025 → 731 jours (assez pour les analyses actuelles +
-- une marge pour les futurs chargements).
--
-- Justification de cette dim (point soutenance) :
--   Sans elle, un Data Scientist qui veut "moyenne de température le
--   weekend" doit écrire EXTRACT(DOW FROM observation_ts_utc) IN (0, 6)
--   à chaque requête, pour chaque colonne dérivée. C'est verbeux et lent.
--
--   Avec dim_date, c'est juste WHERE d.is_weekend = true.
--
-- Génération :
--   1. dbt_utils.date_spine produit 1 ligne par jour entre 2024-01-01
--      et 2026-01-01 (exclusive).
--   2. On extrait les attributs calendaires standards (year, month, etc.).
--   3. On dérive les attributs métier (is_weekend, season, jour férié FR).
--
-- Note : la PK date_sk est un entier de la forme YYYYMMDD (genre 20241002),
-- humainement lisible. C'est plus pratique en debug qu'un MD5 hash.
--
-- ─── Index (Étape 3 : optimisation) ───────────────────────────────
--   * date_sk (UNIQUE) → PK technique, accélère les jointures FK
--     depuis fact_observation_meteo
--   * date → pattern star schema typique : un DS filtre par date côté
--     dim (WHERE d.date BETWEEN ...) avant la jointure vers la fact
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
      "CREATE UNIQUE INDEX IF NOT EXISTS dim_date_date_sk_uk ON {{ this }} (date_sk)",
      "CREATE INDEX IF NOT EXISTS dim_date_date_idx ON {{ this }} (date)"
    ]
) }}

with date_spine as (

    -- date_spine génère une série de dates entre start et end (exclusive).
    -- 'datepart=day' = pas de 1 jour. Autres options : 'week', 'month', etc.
    {{ dbt_utils.date_spine(
        datepart="day",
        start_date="cast('2024-01-01' as date)",
        end_date="cast('2026-01-01' as date)"
    ) }}

),

enriched as (

    select
        -- ─── Clé primaire au format YYYYMMDD (humainement lisible) ───
        cast(to_char(date_day, 'YYYYMMDD') as integer)              as date_sk,

        -- ─── La date elle-même ───────────────────────────────────────
        cast(date_day as date)                                      as date,

        -- ─── Décomposition standard ──────────────────────────────────
        extract(year     from date_day)::integer                    as year,
        extract(quarter  from date_day)::integer                    as quarter,
        extract(month    from date_day)::integer                    as month,
        extract(day      from date_day)::integer                    as day,
        extract(week     from date_day)::integer                    as iso_week,
        extract(doy      from date_day)::integer                    as day_of_year,

        -- ─── Jour de la semaine ──────────────────────────────────────
        -- Postgres : 0 = dimanche, 1 = lundi, ..., 6 = samedi
        -- On normalise en ISO : 1 = lundi, ..., 7 = dimanche
        case extract(dow from date_day)::integer
            when 0 then 7
            else extract(dow from date_day)::integer
        end                                                         as day_of_week_iso,

        to_char(date_day, 'Day')                                    as day_name,
        to_char(date_day, 'Month')                                  as month_name,

        -- ─── Drapeau weekend ─────────────────────────────────────────
        case
            when extract(dow from date_day) in (0, 6) then true
            else false
        end                                                         as is_weekend,

        -- ─── Saison météorologique ──────────────────────────────────
        -- Convention météo (différente de la convention astronomique) :
        --   * Hiver : déc, jan, fév  → idéal pour les analyses météo
        --   * Printemps : mar, avr, mai
        --   * Été : juin, juil, août
        --   * Automne : sep, oct, nov
        case extract(month from date_day)::integer
            when 12 then 'winter'
            when  1 then 'winter'
            when  2 then 'winter'
            when  3 then 'spring'
            when  4 then 'spring'
            when  5 then 'spring'
            when  6 then 'summer'
            when  7 then 'summer'
            when  8 then 'summer'
            when  9 then 'autumn'
            when 10 then 'autumn'
            when 11 then 'autumn'
        end                                                         as season,

        -- ─── Jour férié français ─────────────────────────────────────
        -- Liste hardcodée des jours fériés non-mobiles (les 9 fixes) +
        -- les fériés mobiles 2024-2025 (calculés selon la date de Pâques).
        -- Pour un projet réel à plus long terme, on chargerait un seed CSV
        -- de fériés générés via Python + workalendar.
        case
            when to_char(date_day, 'MM-DD') in (
                '01-01',  -- Jour de l'An
                '05-01',  -- Fête du Travail
                '05-08',  -- Victoire 1945
                '07-14',  -- Fête nationale
                '08-15',  -- Assomption
                '11-01',  -- Toussaint
                '11-11',  -- Armistice
                '12-25'   -- Noël
            ) then true
            -- Pâques + jours mobiles 2024 (Pâques = 2024-03-31)
            when date_day in (
                cast('2024-04-01' as date),  -- Lundi de Pâques 2024
                cast('2024-05-09' as date),  -- Ascension 2024
                cast('2024-05-20' as date)   -- Lundi de Pentecôte 2024
            ) then true
            -- Pâques + jours mobiles 2025 (Pâques = 2025-04-20)
            when date_day in (
                cast('2025-04-21' as date),  -- Lundi de Pâques 2025
                cast('2025-05-29' as date),  -- Ascension 2025
                cast('2025-06-09' as date)   -- Lundi de Pentecôte 2025
            ) then true
            else false
        end                                                         as is_holiday_fr,

        -- ─── Métadonnées de chargement ───────────────────────────────
        current_timestamp                                           as dbt_loaded_at

    from date_spine

)

select * from enriched
