-- ============================================================
-- int_observations_unified
-- ============================================================
-- Modèle d'UNIFICATION : empile les 3 sources intermediate harmonisées
-- en un flux unique d'observations météo, prêt à être projeté dans
-- la table de faits (marts.fact_observation_meteo).
--
-- Sources empilées (dans l'ordre du UNION ALL) :
--   1. int_wu__la_madeleine      (~1 908 lignes, 1 station française)
--   2. int_wu__ichtegem          (~1 899 lignes, 1 station belge)
--   3. int_infoclimat__observations (~1 143 lignes, 4 stations FR)
--   ─────────────────────────────────────────────────────────────
--   TOTAL attendu : ~4 950 lignes pour 6 stations
--
-- Pourquoi UNION ALL et pas UNION ?
--   * UNION ALL empile sans dédupliquer → conserve toutes les lignes
--   * UNION supprimerait les doublons potentiels en faisant un hash global,
--     ce qui est ~10× plus lent ET inutile ici (chaque (station_id,
--     observation_ts_utc) est unique par construction des sources)
--
-- L'unicité de la combinaison (station_id, observation_ts_utc) sera
-- vérifiée par un test DBT à l'étape 4.
--
-- Pourquoi pas une JOIN ? Parce que les 3 sources décrivent les MÊMES
-- types d'événements (des observations météo) à différents endroits.
-- C'est une concaténation verticale, pas un enrichissement horizontal.

with wu_madeleine as (

    select * from {{ ref('int_wu__la_madeleine') }}

),

wu_ichtegem as (

    select * from {{ ref('int_wu__ichtegem') }}

),

infoclimat as (

    select * from {{ ref('int_infoclimat__observations') }}

),

unified as (

    select * from wu_madeleine
    union all
    select * from wu_ichtegem
    union all
    select * from infoclimat

)

select * from unified
