# GreenCoop Data Platform

Pipeline ELT pour le projet **Forecast 2.0** de GreenAndCoop — fournisseur coopératif
d'électricité d'origine renouvelable dans les Hauts-de-France.

Objectif : ingérer, transformer et fiabiliser des données météorologiques issues de
plusieurs réseaux hétérogènes (InfoClimat, Weather Underground) afin d'enrichir les
modèles de prévision de demande d'électricité de l'équipe Data Science.

## 🎯 État d'avancement

| Étape | Description | Statut |
|---|---|---|
| 0 — Environnement local | Postgres + Airbyte + DBT en local via Docker | ✅ |
| 1 — Ingestion Airbyte | 3 sources → 3 tables raw | ✅ |
| 2 — Transformations DBT | Star schema (staging → intermediate → marts) | ✅ |
| 3 — Optimisation index | 8 index sur la couche marts | ✅ |
| 4 — Tests qualité + doc | Tests DBT + lineage + doc auto-générée | ⏳ |
| 5 — Déploiement AWS | RDS + ECS + CloudWatch | ⏳ |
| 6 — Soutenance | Slides + démo | ⏳ |

## 🏗️ Architecture

```
┌────────────────────────────────────────────────────────────────────┐
│                        Machine locale                              │
│                                                                    │
│  ┌────────────────┐   ┌──────────────────┐   ┌────────────────┐    │
│  │ Sources        │   │  Airbyte         │   │  PostgreSQL    │    │
│  │  • InfoClimat  ├──►│  (abctl / kind)  ├──►│  warehouse     │    │
│  │  • WU Excel    │   │  UI :8000        │   │  port 5432     │    │
│  └────────────────┘   └──────────────────┘   └────────┬───────┘    │
│                                                       │            │
│                              ┌────────────────────────┴───────┐    │
│                              │  Schémas du warehouse :        │    │
│                              │   raw → staging → intermediate │    │
│                              │     → marts (dim + fact)       │    │
│                              └────────────────▲───────────────┘    │
│                                               │                    │
│                              ┌────────────────┴────────────────┐   │
│                              │  DBT (venv Python local)        │   │
│                              │   Transformations + tests + doc │   │
│                              └─────────────────────────────────┘   │
└────────────────────────────────────────────────────────────────────┘
```

Le modèle dimensionnel final dans `marts` :

```
            dim_weather_stations (6 stations)
                       ▲
                       │ station_sk (FK)
                       │
       ┌───────────────┴────────────────┐
       │ fact_observation_meteo (~4950) │
       └───────────────┬────────────────┘
                       │ date_sk (FK)
                       ▼
                  dim_date (731 jours)
```

## 📁 Arborescence

```
greencoop-data-platform/
├── docker-compose.yml          # PostgreSQL + pgAdmin
├── .env.example                # Variables d'env (template)
├── .gitignore
├── requirements.txt            # Dépendances Python (dbt + utils + openpyxl)
├── README.md
│
├── data/                       # Sources brutes versionnées
│   ├── station_infoclimat.json
│   ├── WeatherUndergroundIchtegemBE.xlsx       # Original WU (multi-onglets)
│   ├── WeatherUndergroundLaMadeleineFR.xlsx    # Original WU (multi-onglets)
│   ├── WU_Ichtegem_consolidated.xlsx           # Pré-traité pour Airbyte
│   └── WU_LaMadeleine_consolidated.xlsx        # Pré-traité pour Airbyte
│
├── scripts/
│   └── consolidate_wu.py       # Pré-traitement Excel multi-onglets → mono-onglet
│
├── postgres/
│   └── init/
│       └── 01_init_schemas.sql # Schémas raw/staging/intermediate/marts + rôles
│
└── dbt/
    ├── dbt_project.yml         # Config du projet DBT
    ├── profiles.yml            # Connexion DBT → warehouse local
    ├── packages.yml            # Dépendance dbt_utils
    ├── package-lock.yml
    │
    ├── models/
    │   ├── staging/            # 4 modèles : 1 source = 1 modèle, nettoyage minimal
    │   │   ├── _sources.yml
    │   │   ├── stg_infoclimat__observations.sql
    │   │   ├── stg_infoclimat__stations.sql
    │   │   ├── stg_wu__ichtegem.sql
    │   │   └── stg_wu__la_madeleine.sql
    │   │
    │   ├── intermediate/       # 5 modèles : conversions, UTC, UNION ALL
    │   │   ├── int_infoclimat__observations.sql
    │   │   ├── int_observations_unified.sql
    │   │   ├── int_stations_unified.sql
    │   │   ├── int_wu__ichtegem.sql
    │   │   └── int_wu__la_madeleine.sql
    │   │
    │   └── marts/              # 3 tables : star schema final
    │       ├── dim_date.sql
    │       ├── dim_weather_stations.sql
    │       └── fact_observation_meteo.sql
    │
    ├── seeds/
    │   ├── _seeds.yml
    │   └── wu_stations_metadata.csv     # Métadonnées des 2 stations WU
    │
    └── macros/
        ├── cardinal_to_degrees.sql      # Conversion 'NNW' → 337.5°
        └── generate_schema_name.sql     # Override DBT : noms de schémas propres
```

## 📦 Prérequis

- **Docker Desktop** (Windows/Mac) ou **Docker Engine** (Linux) — version récente
- **Python 3.10+** (pour DBT et le pré-traitement Excel)
- **8 Go de RAM disponibles** minimum (Airbyte est gourmand)
- **Git** (pour cloner le repo et pour Airbyte qui consomme nos sources via GitHub raw URLs)

---

# Étape 0 — Mise en place de l'environnement

## A) PostgreSQL warehouse — Docker Compose

### A.1 — Préparer les variables d'environnement

```bash
cd greencoop-data-platform
cp .env.example .env
# Optionnel : éditer .env pour changer les mots de passe
```

### A.2 — Démarrer le warehouse

```bash
docker compose up -d
```

### A.3 — Vérifier la santé du conteneur

```bash
docker compose ps
# postgres-warehouse doit être "Up (healthy)"

docker compose logs postgres-warehouse | tail -20
# Cherche "database system is ready to accept connections"
# et "Initialisation OK : schémas créés -> raw, staging, intermediate, marts"
```

### A.4 — Tester la connexion

```bash
docker compose exec postgres-warehouse \
  psql -U greencoop -d greencoop_warehouse -c "\dn"
```

Sortie attendue :

```
     Name      |  Owner
---------------+----------
 intermediate  | greencoop
 marts         | greencoop
 public        | greencoop
 raw           | greencoop
 staging       | greencoop
```

### A.5 — Interface graphique pgAdmin (optionnel)

- Aller sur <http://localhost:5050>
- Login : `admin@greencoop.local` / `admin` (cf. `.env`)
- Créer une connexion :
  - Host : `postgres-warehouse` (nom du service Docker)
  - Port : `5432`
  - User : `greencoop` (ou `dbt` pour ne voir que les schémas DBT)
  - Password : (cf. `.env`)

---

## B) Airbyte — via abctl

> ℹ️ **Pourquoi pas docker-compose ?** Airbyte a déprécié le déploiement docker-compose
> depuis la version 1.0 (mi-2024). L'outil officiel `abctl` orchestre Airbyte dans un
> cluster Kubernetes léger (kind) qui tourne lui-même dans Docker.

### B.1 — Installer abctl

**Linux / macOS (script d'install) :**

```bash
curl -LsfS https://get.airbyte.com | bash -
abctl version
```

**macOS (Homebrew) :**

```bash
brew tap airbytehq/tap
brew install abctl
abctl version
```

**Windows :** télécharger la release depuis <https://github.com/airbytehq/abctl/releases>,
extraire le zip, ajouter le dossier au `PATH`.

### B.2 — Lancer Airbyte

```bash
abctl local install
# Sur machine modeste (< 4 CPU ou < 8 GB RAM) : abctl local install --low-resource-mode
```

⏱ La première installation peut prendre **15-30 min**. C'est normal.

### B.3 — Accéder à l'interface

```bash
abctl local credentials    # Affiche email/password générés
```

- Ouvrir <http://localhost:8000>
- Saisir les credentials affichés
- Renseigner email + nom d'organisation au premier login → "Get Started"

### B.4 — Configurer la destination PostgreSQL

Sur l'UI Airbyte, créer la destination qui sera réutilisée par les 3 connections :

| Champ | Valeur |
|---|---|
| Host | `host.docker.internal` *(et **pas** `localhost`)* |
| Port | `5432` |
| DB Name | `greencoop_warehouse` |
| Default Schema | `raw` |
| User | `airbyte` |
| Password | `airbyte_dev_pwd` *(cf. `.env`)* |

Cliquer sur **Test** → "All connection tests passed!" ✅

> 🐧 **Linux uniquement** : `host.docker.internal` n'est pas résolu par défaut. Récupérer
> l'IP de l'hôte vue depuis le conteneur kind avec :
> `docker network inspect bridge | grep Gateway` → utiliser cette IP.

---

## C) DBT — Environnement Python

### C.1 — Créer le venv et installer dbt-postgres

```bash
cd greencoop-data-platform
python3 -m venv .venv
source .venv/bin/activate          # Linux/macOS
# .venv\Scripts\activate            # Windows PowerShell

pip install --upgrade pip
pip install -r requirements.txt
dbt --version
```

Sortie attendue :

```
Core:
  - installed: 1.8.x
Plugins:
  - postgres: 1.8.x
```

### C.2 — Configurer DBT pour utiliser le `profiles.yml` du repo

Par défaut DBT cherche `profiles.yml` dans `~/.dbt/`. On préfère le garder dans le repo
(versionné, sans secret car le mot de passe est lu depuis `DBT_PASSWORD`). Deux options :

```bash
# Option A : précier le dossier à chaque commande
cd dbt
dbt debug --profiles-dir .

# Option B (recommandée) : exporter la variable d'env une fois par session
export DBT_PROFILES_DIR=./dbt    # Linux/macOS
# $env:DBT_PROFILES_DIR="./dbt"  # Windows PowerShell
cd dbt
dbt debug
```

### C.3 — Charger le mot de passe DBT depuis `.env`

DBT lit le mot de passe via `env_var('DBT_PASSWORD')` dans `profiles.yml`. Il faut donc
exporter cette variable avant de lancer `dbt` :

```powershell
# Windows PowerShell — à faire à chaque nouvelle session
Get-Content .env | ForEach-Object {
    if ($_ -match '^([^=]+)=(.*)$') {
        [Environment]::SetEnvironmentVariable($matches[1], $matches[2], 'Process')
    }
}
```

```bash
# Linux/macOS — équivalent
export $(grep -v '^#' .env | xargs)
```

### C.4 — Installer les packages DBT et tester la connexion

```bash
cd dbt
dbt deps              # Installe dbt_utils dans dbt_packages/
dbt debug             # Tout doit être "OK"
```

Sortie attendue :

```
Connection test: [OK connection ok]
All checks passed!
```

---

# Étape 1 — Ingestion Airbyte

Trois sources de données arrivent dans le schéma `raw` du warehouse :

| Source | Format | Volume | Table cible |
|---|---|---|---|
| InfoClimat (4 stations Hauts-de-France) | JSON | 1 ligne (JSONB) contenant ~1 143 observations | `raw.raw_infoclimat` |
| Weather Underground - La Madeleine (FR) | Excel | ~1 908 lignes | `raw.raw_madeleine` |
| Weather Underground - Ichtegem (BE) | Excel | ~1 899 lignes | `raw.raw_ichtegem` |

## D.1 — Pré-traitement des fichiers Excel Weather Underground

Les fichiers WU originaux ont une structure tordue : **chaque journée est sur un onglet
séparé**, et le nom de l'onglet (`011024`, `021024`, ...) encode la date sous forme
`ddmmyy`. Le connecteur Airbyte File Source ne lit que le **premier onglet**, ce qui
perdrait 99 % des données.

Le script `scripts/consolidate_wu.py` règle le problème en amont (adaptateur de format,
**pas** une transformation métier) :

1. Lit chaque onglet du `.xlsx`
2. Convertit le nom de l'onglet en date (`011024` → `2024-10-01`)
3. Injecte cette date comme première colonne `Date` de chaque ligne
4. Écrit le tout dans un fichier mono-onglet `WU_<nom>_consolidated.xlsx`

```bash
# Exécuter le pré-traitement (à refaire si les fichiers sources changent)
python scripts/consolidate_wu.py
```

Sortie attendue :

```
=== Consolidation de WeatherUndergroundLaMadeleineFR.xlsx ===
   ✓ Onglet '011024' (2024-10-01) traité
   ✓ Onglet '021024' (2024-10-02) traité
   ...
   → 1908 lignes consolidées dans WU_LaMadeleine_consolidated.xlsx
```

## D.2 — Pousser les fichiers consolidés sur GitHub

Airbyte File Source ne peut pas lire des fichiers locaux sur Windows (le flag
`abctl --volume` est incompatible avec les chemins Windows). On contourne en exposant
les fichiers via **GitHub raw URLs** :

```bash
git add data/WU_*_consolidated.xlsx data/station_infoclimat.json
git commit -m "data: add WU consolidated files and InfoClimat snapshot"
git push
```

Les URLs deviennent (à adapter à ton fork) :

- `https://raw.githubusercontent.com/<user>/<repo>/main/data/WU_LaMadeleine_consolidated.xlsx`
- `https://raw.githubusercontent.com/<user>/<repo>/main/data/WU_Ichtegem_consolidated.xlsx`
- `https://raw.githubusercontent.com/<user>/<repo>/main/data/station_infoclimat.json`

## D.3 — Configurer les 3 sources Airbyte

Pour chaque source, sur l'UI Airbyte → **Sources** → **+ New source** → "File" :

### Source 1 : InfoClimat (JSON)

| Champ | Valeur |
|---|---|
| Source name | `InfoClimat` |
| Dataset name | `raw_infoclimat` |
| File format | `json` |
| Storage provider | `HTTPS` |
| URL | URL raw du `station_infoclimat.json` |

### Source 2 : WU La Madeleine (Excel)

| Champ | Valeur |
|---|---|
| Source name | `WU La Madeleine` |
| Dataset name | `raw_madeleine` |
| File format | `excel` |
| URL | URL raw du `WU_LaMadeleine_consolidated.xlsx` |

### Source 3 : WU Ichtegem (Excel)

| Champ | Valeur |
|---|---|
| Source name | `WU Ichtegem` |
| Dataset name | `raw_ichtegem` |
| File format | `excel` |
| URL | URL raw du `WU_Ichtegem_consolidated.xlsx` |

## D.4 — Créer les 3 connections et lancer la première sync

Pour chaque source, créer une **Connection** vers la destination PostgreSQL :

- **Replication frequency** : `Manual` (en production : toutes les 30 min)
- **Sync mode** : `Full Refresh - Overwrite` (les fichiers ne changent pas, c'est suffisant)
- **Destination namespace** : `raw`

Lancer la sync (**Sync now**) sur chaque connection → 3 tables apparaissent dans
`raw.*`.

## D.5 — Vérifier les tables raw

```sql
-- Dans pgAdmin ou via psql
\dt raw.*

SELECT count(*) FROM raw.raw_infoclimat;   -- 1 (JSONB)
SELECT count(*) FROM raw.raw_madeleine;    -- ~1908
SELECT count(*) FROM raw.raw_ichtegem;     -- ~1899
```

---

# Étape 2 — Transformations DBT (star schema)

Le projet DBT suit l'architecture en 3 couches standard. **Toute la logique métier
réside dans les couches staging et intermediate** ; les tables `marts` sont les
livrables consommables par les Data Scientists.

```
raw (Airbyte)
   │
   ▼ stg_*  (4 vues, nettoyage minimal, 1 source = 1 modèle)
staging
   │
   ▼ int_*  (5 vues, conversions, jointures, UNION ALL)
intermediate
   │
   ▼ dim_*, fact_*  (3 tables matérialisées avec index)
marts
```

## E.1 — Couche staging (4 vues)

| Modèle | Rôle |
|---|---|
| `stg_infoclimat__stations` | Explose le JSONB `stations` → 4 lignes |
| `stg_infoclimat__observations` | Double explosion (`jsonb_each` + `jsonb_array_elements`) → ~1 143 lignes |
| `stg_wu__la_madeleine` | Parse les valeurs string avec unité (`"56.2 °F"` → `56.2`) via regex |
| `stg_wu__ichtegem` | Idem pour Ichtegem |

⚠️ **Aucune conversion d'unités à ce stade** — on parse et on cast seulement.

## E.2 — Couche intermediate (5 vues)

| Modèle | Rôle |
|---|---|
| `int_wu__la_madeleine` | °F → °C, mph → km/h, inHg → hPa, in → mm. Heure locale → UTC. Cardinal → degrés via macro |
| `int_wu__ichtegem` | Idem |
| `int_infoclimat__observations` | Pas de conversion (déjà en SI/UTC), juste alignement de schéma pour le UNION |
| `int_stations_unified` | UNION ALL des 6 stations + classification `professional` / `amateur` |
| `int_observations_unified` | UNION ALL → ~4 950 observations alignées |

## E.3 — Couche marts (3 tables)

| Modèle | Rôle | Volume |
|---|---|---|
| `dim_weather_stations` | Dim stations avec surrogate key `station_sk` (MD5 hash) | 6 lignes |
| `dim_date` | Dim calendrier avec `is_weekend`, `season`, `is_holiday_fr` | 731 lignes |
| `fact_observation_meteo` | Table de faits avec FK `station_sk` + `date_sk` | ~4 950 lignes |

## E.4 — Seeds et macros

- **Seed `wu_stations_metadata.csv`** : métadonnées des 2 stations WU (latitude,
  longitude, hardware, software, etc.) extraites du brief de mission Ouly. Versionné
  avec le code.
- **Macro `cardinal_to_degrees`** : conversion des directions de vent cardinales
  (`'NNW'` → `337.5°`) — réutilisable sur les 2 stations WU.
- **Macro `generate_schema_name`** (override DBT) : force les noms de schémas à
  `staging`, `intermediate`, `marts` (sans préfixage du profil).

## E.5 — Exécution complète

```bash
cd dbt
dbt deps                # Installe dbt_utils
dbt seed                # Charge wu_stations_metadata
dbt run                 # Exécute les 12 modèles dans le bon ordre

# Vérification : compter les lignes dans la fact
psql -U dbt -d greencoop_warehouse -c \
  "SELECT count(*) FROM marts.fact_observation_meteo;"
# → 4950
```

---

# Étape 3 — Optimisation des index

Les 3 tables marts sont indexées via un `post_hook` DBT qui exécute des `CREATE INDEX`
après le `CREATE TABLE AS`. On utilise `post_hook` plutôt que la syntaxe `indexes` de
`dbt-postgres` pour pouvoir nommer explicitement les index (la syntaxe `indexes` génère
des hashs MD5 illisibles).

## F.1 — Liste des 8 index

| Table | Colonnes | Type | Rôle |
|---|---|---|---|
| `dim_weather_stations` | `station_sk` | UNIQUE | PK technique |
| `dim_weather_stations` | `(station_id, source_network)` | INDEX | Lookup par clé naturelle |
| `dim_date` | `date_sk` | UNIQUE | PK technique |
| `dim_date` | `date` | INDEX | Filtre temporel côté dim |
| `fact_observation_meteo` | `(station_sk, observation_ts_utc)` | UNIQUE | Garde-fou anti-doublons + filtre station+période |
| `fact_observation_meteo` | `station_sk` | INDEX | FK vers dim_weather_stations |
| `fact_observation_meteo` | `date_sk` | INDEX | FK vers dim_date |
| `fact_observation_meteo` | `observation_ts_utc` | INDEX | Filtre temporel cross-station |

Convention de nommage : `<table>_<colonnes>_uk` pour UNIQUE, `<table>_<colonnes>_idx`
pour les autres.

## F.2 — Application

```bash
cd dbt
dbt run --select marts --full-refresh
# Le full-refresh est nécessaire : DBT doit recréer les tables pour appliquer
# le nouveau post_hook.

# Vérification : 8 index créés
psql -U dbt -d greencoop_warehouse -c \
  "SELECT tablename, indexname FROM pg_indexes
   WHERE schemaname = 'marts' ORDER BY tablename, indexname;"
```

## F.3 — Benchmark avant / après

Mesures réelles avec `EXPLAIN (ANALYZE, BUFFERS)` sur 3 exécutions, meilleur temps gardé :

| Pattern de requête | Sans index | Avec index | Gain |
|---|---|---|---|
| Historique d'une station sur 3 jours | 1.17 ms | 0.38 ms | **× 3** |
| Fenêtre temporelle 2h, toutes stations | 0.72 ms | 0.13 ms | **× 5** |
| Agrégation globale par station (Hash Join préservé) | 4.80 ms | 3.57 ms | × 1.4 |

À noter : Postgres choisit intelligemment d'utiliser ou non un index selon la
sélectivité de la requête. Sur les agrégations globales, il préfère un `Hash Join` (qui
n'utilise pas les index FK) — c'est mathématiquement optimal à ce volume.

---

## ✅ Checklist de validation globale

**Étape 0**
- [ ] `docker compose ps` → `postgres-warehouse` en `healthy`
- [ ] `\dn` dans psql affiche `raw`, `staging`, `intermediate`, `marts`
- [ ] pgAdmin accessible sur <http://localhost:5050> *(optionnel)*
- [ ] `abctl local status` → chart `airbyte-abctl` en `deployed`
- [ ] UI Airbyte accessible sur <http://localhost:8000>
- [ ] Test de connexion Airbyte → `host.docker.internal:5432` ✅
- [ ] `dbt debug` → `All checks passed!`

**Étape 1**
- [ ] `python scripts/consolidate_wu.py` exécuté sans erreur
- [ ] 3 sources Airbyte configurées, test de connexion ✅ sur chacune
- [ ] 3 syncs lancées avec succès
- [ ] `raw.raw_infoclimat`, `raw.raw_madeleine`, `raw.raw_ichtegem` peuplées

**Étape 2**
- [ ] `dbt deps` + `dbt seed` + `dbt run` passent sans erreur
- [ ] 4 vues dans `staging`, 5 dans `intermediate`, 3 tables dans `marts`
- [ ] `SELECT count(*) FROM marts.fact_observation_meteo` → 4950
- [ ] `SELECT count(*) FROM marts.dim_weather_stations` → 6

**Étape 3**
- [ ] `dbt run --select marts --full-refresh` recrée les tables avec leurs index
- [ ] `SELECT count(*) FROM pg_indexes WHERE schemaname = 'marts'` → 8

---

## 🛠 Pièges fréquents rencontrés

| Symptôme | Cause | Correction |
|---|---|---|
| `port 5432 already in use` au `docker compose up` | Un service `postgresql-x64-XX` Windows tourne et occupe le port | `services.msc` → arrêter le service, le passer en démarrage manuel |
| `abctl local install --volume <path>` échoue sur Windows | Le flag `--volume` n'accepte pas les chemins avec lettre de lecteur | Ne pas utiliser `--volume`. Passer par GitHub raw URLs pour les fichiers |
| Airbyte ne se connecte pas à `localhost:5432` | `localhost` côté Airbyte = le pod kind, pas l'hôte | Utiliser `host.docker.internal` (Win/Mac) ou IP du host (Linux) |
| Airbyte écrit mais DBT ne voit aucune table dans `raw` | Le rôle `airbyte` n'a pas `CREATE`/`TEMPORARY` sur la database | `GRANT CREATE, TEMPORARY ON DATABASE greencoop_warehouse TO airbyte;` |
| `dbt run` → `permission denied for schema staging` | Le rôle `dbt` n'a pas `USAGE, CREATE` sur le schéma | Voir `01_init_schemas.sql` — relancer le `down -v && up -d` si volume préexistant |
| `dbt debug` → `Could not find profile` | Lancé depuis le mauvais dossier OU `DBT_PROFILES_DIR` non défini | Se placer dans `dbt/` et utiliser `--profiles-dir .` ou exporter `DBT_PROFILES_DIR=./dbt` |
| Erreurs SQL avec `column "Date" does not exist` | Airbyte préserve la casse mixte des colonnes Excel | Citer les colonnes avec `"..."` dans le SQL staging |
| Excel WU pré-traité a 1 onglet mais 0 ligne | Le script lit le premier onglet uniquement et écrase | Vérifier que `wb_dst.active` est bien renommé/vide avant d'écrire |

---

## 🧹 Commandes utiles

```bash
# --- Docker / Postgres
docker compose stop                    # garde les données
docker compose down                    # supprime les conteneurs (garde le volume)
docker compose down -v                 # ⚠️ supprime aussi les données
docker compose logs -f postgres-warehouse

# --- Airbyte
abctl local status
abctl local credentials
abctl local uninstall                  # désinstalle (garde les données)

# --- DBT (depuis le dossier dbt/, profiles-dir exporté)
dbt deps                               # installe les packages
dbt seed                               # charge les CSV des seeds
dbt run                                # exécute tous les modèles
dbt run --select stg_wu__la_madeleine  # un seul modèle
dbt run --select staging               # toute une couche (staging/intermediate/marts)
dbt run --select +marts                # marts ET tout ce dont elle dépend
dbt run --full-refresh                 # force le DROP + CREATE des tables
dbt docs generate && dbt docs serve    # doc + lineage interactif (port 8080)
dbt clean                              # supprime target/ et dbt_packages/
```

---

## ➡️ Prochaines étapes

**Étape 4 — Tests qualité + documentation**
Tests génériques DBT (`unique`, `not_null`, `relationships`, `accepted_values`) déclarés
en YAML sur chaque modèle marts. Ajout de tests métier custom (températures dans une
plage réaliste, timestamps non futurs, etc.). Génération de la doc DBT et du lineage
graphique avec `dbt docs generate && dbt docs serve`.

**Étape 5 — Déploiement AWS**
Migration de la base PostgreSQL vers Amazon RDS, déploiement d'Airbyte sur EC2/ECS,
orchestration des transformations DBT via des tâches ECS planifiées, monitoring et logs
centralisés dans CloudWatch.

**Étape 6 — Soutenance**
Support de présentation (15 min + questions), schéma dimensionnel, lineage DBT,
benchmark de qualité et performance, démonstration live du pipeline.
