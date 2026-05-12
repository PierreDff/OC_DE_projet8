-- ============================================================
-- Initialisation du data warehouse GreenCoop
-- ============================================================
-- Exécuté UNE SEULE FOIS à la première création du volume Postgres.
-- Pour réappliquer après modification : docker compose down -v && docker compose up -d
--
-- Les mots de passe sont passés via des variables psql (jamais en clair ici).
-- Lancer avec :
--   psql -U greencoop -d greencoop_warehouse \
--     -v AIRBYTE_PASSWORD="$AIRBYTE_PASSWORD" \
--     -v DBT_PASSWORD="$DBT_PASSWORD" \
--     -v DS_PASSWORD="$DS_PASSWORD" \
--     -f 01_init_schemas.sql

-- ----------------------------------------------------------------
-- Schémas - on suit l'organisation classique d'un projet ELT/DBT
-- ----------------------------------------------------------------

-- Couche RAW : données brutes telles qu'écrites par Airbyte
CREATE SCHEMA IF NOT EXISTS raw;
COMMENT ON SCHEMA raw IS 'Données brutes ingérées par Airbyte, sans transformation';

-- Couche STAGING : nettoyage / cast / parsing par DBT (1 source = 1 modèle)
CREATE SCHEMA IF NOT EXISTS staging;
COMMENT ON SCHEMA staging IS 'Données nettoyées et typées (modèles DBT staging)';

-- Couche INTERMEDIATE : jointures et logique métier par DBT
CREATE SCHEMA IF NOT EXISTS intermediate;
COMMENT ON SCHEMA intermediate IS 'Modèles de travail DBT : jointures, agrégations, logique métier';

-- Couche MARTS : modèle métier unifié (dim/fact) prêt pour la Data Science
CREATE SCHEMA IF NOT EXISTS marts;
COMMENT ON SCHEMA marts IS 'Modèle métier (dim_station, fact_observation_meteo) pour la Data Science';

-- ----------------------------------------------------------------
-- Utilisateurs / rôles
-- ----------------------------------------------------------------

-- Utilisateur dédié pour Airbyte (écriture sur raw uniquement)
DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'airbyte') THEN
    CREATE ROLE airbyte WITH LOGIN PASSWORD :'AIRBYTE_PASSWORD';
  END IF;
END
$$;

GRANT CONNECT ON DATABASE greencoop_warehouse TO airbyte;
GRANT CREATE, TEMPORARY ON DATABASE greencoop_warehouse TO airbyte;
GRANT USAGE, CREATE ON SCHEMA raw TO airbyte;
ALTER DEFAULT PRIVILEGES IN SCHEMA raw GRANT ALL ON TABLES TO airbyte;
ALTER DEFAULT PRIVILEGES IN SCHEMA raw GRANT ALL ON SEQUENCES TO airbyte;

-- Utilisateur dédié pour DBT (lecture sur raw, écriture sur staging/intermediate/marts)
DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'dbt') THEN
    CREATE ROLE dbt WITH LOGIN PASSWORD :'DBT_PASSWORD';
  END IF;
END
$$;

GRANT CONNECT ON DATABASE greencoop_warehouse TO dbt;
GRANT CREATE, TEMPORARY ON DATABASE greencoop_warehouse TO dbt;
GRANT USAGE ON SCHEMA raw TO dbt;
GRANT SELECT ON ALL TABLES IN SCHEMA raw TO dbt;
ALTER DEFAULT PRIVILEGES IN SCHEMA raw GRANT SELECT ON TABLES TO dbt;
GRANT USAGE, CREATE ON SCHEMA staging TO dbt;
GRANT USAGE, CREATE ON SCHEMA intermediate TO dbt;
GRANT USAGE, CREATE ON SCHEMA marts TO dbt;

-- Utilisateur en lecture seule pour la Data Science (SageMaker)
DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'data_science_ro') THEN
    CREATE ROLE data_science_ro WITH LOGIN PASSWORD :'DS_PASSWORD';
  END IF;
END
$$;

GRANT CONNECT ON DATABASE greencoop_warehouse TO data_science_ro;
GRANT USAGE ON SCHEMA marts TO data_science_ro;
GRANT SELECT ON ALL TABLES IN SCHEMA marts TO data_science_ro;
ALTER DEFAULT PRIVILEGES IN SCHEMA marts GRANT SELECT ON TABLES TO data_science_ro;

-- ----------------------------------------------------------------
-- Vérification
-- ----------------------------------------------------------------
SELECT 'Initialisation OK : schémas créés -> ' ||
       string_agg(schema_name, ', ') AS message
FROM information_schema.schemata
WHERE schema_name IN ('raw', 'staging', 'intermediate', 'marts');
