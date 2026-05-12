# GreenCoop Data Platform — Forecast 2.0

Pipeline **ELT** pour le projet *Forecast 2.0* de GreenAndCoop.
Ingère des données météo depuis l'API InfoClimat et des fichiers Excel
Weather Underground, les charge dans un warehouse PostgreSQL via Airbyte,
puis les transforme avec DBT en un schéma en étoile exploitable par les
Data Scientists.

## Vue d'ensemble du pipeline

```
┌─────────────────────────────────────────────────────────────────────────┐
│                           Machine locale                                │
│                                                                         │
│   ┌───────────┐   ┌──────────┐   ┌──────────────┐   ┌──────────────┐    │
│   │ Sources   │──▶│ Airbyte  │──▶│ PostgreSQL   │──▶│ DBT          │    │
│   │  (E)      │   │  (L)     │   │  warehouse   │   │  (T)         │    │
│   └───────────┘   └──────────┘   └──────────────┘   └──────────────┘    │
│        │                              │                    │           │
│   GitHub raw                     schémas:              transformations: │
│   URLs (JSON                     raw / staging /       staging →        │
│   + xlsx WU)                     intermediate /        intermediate →   │
│                                  marts                 marts            │
└─────────────────────────────────────────────────────────────────────────┘
```

| Composant | Rôle | Mode de déploiement |
|---|---|---|
| **PostgreSQL 16** | Data warehouse | Docker Compose |
| **Airbyte** | Ingestion (Extract + Load) | `abctl` (cluster kind interne) |
| **DBT** | Transformation | venv Python local |
| **pgAdmin** | Interface d'admin SQL (optionnel) | Docker Compose |

## Arborescence

```
greencoop-data-platform/
├── docker-compose.yml                # PostgreSQL + pgAdmin
├── .env.example                      # Variables d'env (template)
├── .env                              # ⚠️ gitignoré, secrets locaux
├── .gitignore
├── requirements.txt                  # Dépendances Python (dbt + utils)
├── README.md                         # Ce fichier
├── postgres/
│   └── init/
│       └── 01_init_schemas.sql       # Schémas + rôles (raw / staging / intermediate / marts)
├── data/                             # Sources de données (consolidées si besoin)
│   ├── station_infoclimat.json
│   ├── WeatherUndergroundLaMadeleineFR.xlsx       # Source brute (multi-onglets)
│   ├── WeatherUndergroundIchtegemBE.xlsx          # Source brute (multi-onglets)
│   ├── WU_LaMadeleine_consolidated.xlsx           # Source consolidée pour Airbyte
│   └── WU_Ichtegem_consolidated.xlsx              # Source consolidée pour Airbyte
├── scripts/
│   └── consolidate_wu.py             # Pré-traitement format des fichiers WU
└── dbt/                              # Projet DBT (toutes les commandes dbt sont lancées d'ici)
    ├── dbt_project.yml
    ├── profiles.yml                  # Connexion DBT → warehouse (mot de passe via env_var)
    ├── models/
    │   ├── staging/                  # Nettoyage source par source
    │   │   ├── _sources.yml
    │   │   └── stg_wu__la_madeleine.sql
    │   ├── intermediate/             # Unification + conversions vers SI
    │   └── marts/                    # Schéma en étoile : dim + fact
    ├── analyses/
    ├── tests/
    ├── seeds/
    ├── macros/
    └── snapshots/
```

## Prérequis

- **Docker Desktop** (Windows/Mac) ou **Docker Engine** (Linux) — version récente
- **Python 3.10+** (pour DBT et le pré-traitement des sources)
- **8 Go de RAM disponibles** minimum (Airbyte est gourmand)
- **Git** (pour pousser les sources consolidées vers un repo public utilisé par Airbyte)

---

# Étape 0 — Mise en place de l'environnement

## A) PostgreSQL warehouse — Docker Compose

### A.1 — Préparer les variables d'environnement

```bash
cd greencoop-data-platform
cp .env.example .env
# Éditer .env si vous voulez changer les mots de passe par défaut
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

- <http://localhost:5050>
- Login : cf. `.env`
- Connexion : Host = `postgres-warehouse`, Port = `5432`, User/Password = cf. `.env`

---

## B) Airbyte — via abctl

> ℹ️ **Pourquoi pas docker-compose ?** Airbyte a déprécié le déploiement docker-compose
> depuis la version 1.0 (mi-2024). L'outil officiel `abctl` orchestre Airbyte dans un
> cluster Kubernetes léger (kind) qui tourne lui-même dans Docker.

### B.1 — Installer abctl

**Linux / macOS :**
```bash
curl -LsfS https://get.airbyte.com | bash -
abctl version
```

**Windows :** télécharger la release sur <https://github.com/airbytehq/abctl/releases>,
extraire, ajouter au `PATH`.

### B.2 — Lancer Airbyte

```bash
abctl local install                         # standard
abctl local install --low-resource-mode     # si < 4 CPU ou < 8 GB RAM
```

⏱ Première installation : **15–30 min** (téléchargement Helm + images Docker).

### B.3 — Récupérer les credentials d'accès

```bash
abctl local credentials
```

### B.4 — Accéder à l'interface

- <http://localhost:8000> → email/password affichés ci-dessus

### B.5 — Vérifier le statut

```bash
abctl local status
# Doit afficher "Status: deployed" pour le chart airbyte-abctl
```

---

## C) DBT — Environnement Python

### C.1 — Créer le venv et installer dbt-postgres

```bash
cd greencoop-data-platform
python -m venv .venv
.\.venv\Scripts\Activate.ps1     # Windows PowerShell
# source .venv/bin/activate       # Linux/macOS

pip install --upgrade pip
pip install -r requirements.txt
dbt --version                     # doit afficher dbt 1.8.x + plugin postgres 1.8.x
```

### C.2 — Configuration de la connexion DBT

Le fichier `dbt/profiles.yml` est **versionné dans Git** car il ne contient aucun secret :
le mot de passe est lu dynamiquement depuis la variable d'environnement `DBT_PASSWORD`
via la fonction Jinja `env_var()`.

```yaml
# dbt/profiles.yml (extrait)
greencoop:
  target: dev
  outputs:
    dev:
      type: postgres
      host: localhost
      port: 5432
      user: dbt
      password: "{{ env_var('DBT_PASSWORD') }}"
      dbname: greencoop_warehouse
      schema: staging
      threads: 4
```

> **Ordre de recherche DBT pour `profiles.yml`** :
> 1. variable d'env `DBT_PROFILES_DIR`
> 2. dossier courant d'où la commande est lancée *(c'est notre cas)*
> 3. `~/.dbt/profiles.yml` (fallback)
>
> Comme nous avons un `profiles.yml` directement dans `dbt/`, c'est lui qui prime tant
> qu'on lance les commandes depuis ce dossier — aucune configuration globale nécessaire.

### C.3 — À chaque nouvelle session shell

```powershell
# 1. Activer le venv
.\.venv\Scripts\Activate.ps1

# 2. Charger les variables d'environnement depuis .env (PowerShell)
Get-Content .env | ForEach-Object {
  if ($_ -match '^\s*([^#=]+?)\s*=\s*(.*?)\s*$') {
    [System.Environment]::SetEnvironmentVariable($matches[1], $matches[2], 'Process')
  }
}

# 3. Vérifier
echo $env:DBT_PASSWORD       # doit afficher le mot de passe DBT

# 4. Se placer dans le dossier DBT (toutes les commandes dbt se lancent d'ici)
cd dbt
```

### C.4 — Tester la connexion

```bash
dbt debug
```

Sortie attendue :

```
Connection test: [OK connection ok]
All checks passed!
```

---

## ✅ Checklist de validation de l'Étape 0

- [x] `docker compose ps` → `postgres-warehouse` en `healthy`
- [x] `\dn` dans psql affiche `raw`, `staging`, `intermediate`, `marts`
- [x] pgAdmin accessible sur <http://localhost:5050> *(optionnel)*
- [x] `abctl local status` → chart `airbyte-abctl` en `deployed`
- [x] UI Airbyte accessible sur <http://localhost:8000>
- [x] `dbt debug` → `All checks passed!`

---

# Étape 1 — Ingestion Airbyte

Cette étape charge les 3 sources de données dans le schéma `raw` du warehouse,
**sans aucune transformation métier** (philosophie ELT).

## D.1 — Pré-traitement des fichiers Weather Underground

Les fichiers Excel WU encodent la date dans **le nom de chaque onglet** (`011024`,
`021024`, …) au lieu d'une colonne. Comme Airbyte ne lit que la première feuille
d'un classeur, **6 jours sur 7 seraient perdus** sans pré-traitement.

> **Justification soutenance** : ce pré-traitement n'est **pas** une transformation
> métier (interdite avant ingestion), c'est une **adaptation de format** comparable
> à ce qu'un connecteur Airbyte natif ferait. On préserve l'intégralité de l'information
> source, on lui donne juste un format ingérable.

```powershell
# Depuis la racine du projet
python scripts/consolidate_wu.py
```

Sortie attendue : `data/WU_Ichtegem_consolidated.xlsx` et `data/WU_LaMadeleine_consolidated.xlsx`,
chacun contenant un seul onglet avec une nouvelle colonne `Date`.

Une fois consolidés, **pousser ces 2 fichiers sur GitHub** (Airbyte les lira via leur URL
raw HTTPS).

## D.2 — Configuration des 3 sources Airbyte

Sur l'UI Airbyte, créer 3 sources de type **File** pointant vers les URLs raw GitHub :

| Source name | Format | URL | Dataset name |
|---|---|---|---|
| `infoclimat` | json | `https://raw.githubusercontent.com/<user>/<repo>/.../station_infoclimat.json` | `raw_infoclimat` |
| `wu_la_madeleine` | excel | `https://raw.githubusercontent.com/<user>/<repo>/.../WU_LaMadeleine_consolidated.xlsx` | `raw_madeleine` |
| `wu_ichtegem` | excel | `https://raw.githubusercontent.com/<user>/<repo>/.../WU_Ichtegem_consolidated.xlsx` | `raw_ichtegem` |

> **Pourquoi GitHub raw URLs ?** On a essayé d'autres approches (`abctl --volume`,
> serveur HTTP local) qui ont buté sur des bugs Windows ou de réseau interne kind.
> GitHub raw est fiable, public, versionné, et fonctionne immédiatement.

## D.3 — Configuration de la destination Airbyte

| Champ | Valeur |
|---|---|
| Host | `host.docker.internal` *(et **pas** `localhost`)* |
| Port | `5432` |
| Database name | `greencoop_warehouse` |
| Default schema | `raw` |
| Username | `airbyte` |
| Password | (cf. `.env`) |
| SSL | `disable` |

## D.4 — Création des connections

Pour chacune des 3 sources, créer une connection vers la destination Postgres :
- **Sync mode** : `Full refresh | Overwrite`
- **Frequency** : `Manual` (déclenchement à la demande pendant le dev)
- **Destination namespace** : `raw`

## D.5 — Vérifier les tables ingérées

```bash
docker compose exec postgres-warehouse \
  psql -U greencoop -d greencoop_warehouse -c "\dt raw.*"
```

Sortie attendue :

```
 Schema |      Name      | Type  |  Owner
--------+----------------+-------+---------
 raw    | raw_ichtegem   | table | airbyte    (~1 900 lignes)
 raw    | raw_infoclimat | table | airbyte    (1 ligne, JSONB)
 raw    | raw_madeleine  | table | airbyte    (~1 900 lignes)
```

---

# Étape 2 — Modélisation DBT

Transformation des données brutes en un **schéma en étoile** exploitable par les
Data Scientists, avec une architecture en 3 couches :

| Couche | Matérialisation | Responsabilité |
|---|---|---|
| `staging` | view | Nettoyage source par source (rename, cast, parsing) |
| `intermediate` | view | Harmonisation : conversions °F→°C, mph→km/h, UTC, UNION des sources |
| `marts` | table | Schéma en étoile final : `dim_weather_station`, `dim_date`, `fact_observation_meteo` |

## E.1 — Sources DBT

Le fichier `dbt/models/staging/_sources.yml` déclare les 3 tables raw alimentées par
Airbyte. Cela permet à DBT de tracer le lineage et d'utiliser `{{ source('raw', '...') }}`
dans les modèles.

## E.2 — Modèles staging

Un modèle staging par source (1 source = 1 modèle), responsabilité minimale :
- renommage en snake_case
- parsing des unités (`'56.2 °F'` → `56.2`)
- cast string → numeric / timestamp
- gestion des chaînes vides → NULL

**Aucune conversion d'unités** à ce stade : staging reste fidèle à la source.

## E.3 — Modèles intermediate (à venir)

- conversions vers le système international (°C, km/h, hPa, mm)
- alignement des fuseaux horaires (heure locale → UTC)
- conversion des cardinaux WU en degrés
- `UNION ALL` des sources pour produire un flux unifié d'observations

## E.4 — Modèles marts (à venir)

| Table | Type | Description |
|---|---|---|
| `dim_weather_station` | dimension | 6 stations (4 InfoClimat + 2 WU). Métadonnées des stations WU injectées via un seed CSV. |
| `dim_date` | dimension | Une ligne par jour : year, month, day_of_week, is_weekend, etc. |
| `fact_observation_meteo` | faits | Une ligne par mesure. Colonnes harmonisées entre sources, NULL si la source ne mesure pas une grandeur. |

## E.5 — Commandes DBT courantes

| Commande | Effet |
|---|---|
| `dbt debug` | Vérifie config + connexion |
| `dbt parse` | Parse les fichiers, sans exécuter |
| `dbt compile --select <model>` | Génère le SQL final dans `target/` |
| `dbt run` | Exécute tous les modèles |
| `dbt run --select staging` | Exécute uniquement la couche staging |
| `dbt run --select stg_wu__la_madeleine` | Exécute un modèle précis |
| `dbt test` | Lance les tests de qualité |
| `dbt seed` | Charge les CSV de référence (métadonnées WU) |
| `dbt docs generate && dbt docs serve` | Doc HTML interactive avec lineage |
| `dbt clean` | Supprime `target/` et `dbt_packages/` |

---

## 🛠 Pièges fréquents (rencontrés sur le projet)

| Symptôme | Cause | Correction |
|---|---|---|
| `port 5432 already in use` au `docker compose up` | Un PostgreSQL natif Windows occupe le port | `Stop-Service postgresql-x64-XX` et `Set-Service ... -StartupType Manual` (PowerShell admin) |
| Airbyte → "password authentication failed" sur la destination | Même cause : Airbyte tape sur le PostgreSQL Windows fantôme via `host.docker.internal:5432`, pas sur le container | Idem ci-dessus, vérifier avec `Get-NetTCPConnection -LocalPort 5432 -State Listen` |
| `abctl local install --volume` échoue sur Windows | Bug du parseur d'`abctl` qui ne gère pas les `:` des chemins Windows (`C:\...`) | Solution de contournement : héberger les sources sur GitHub raw URLs |
| Schémas `raw/staging/intermediate/marts` absents | Volume Docker préexistant : le script SQL d'init n'est rejoué qu'à la création du volume | `docker compose down -v` (⚠️ supprime les données) puis `docker compose up -d` |
| Airbyte n'arrive pas à `localhost:5432` | `localhost` côté pod Airbyte = le pod, pas l'hôte | Utiliser `host.docker.internal` (Mac/Win) |
| `raw.raw_madeleine` ingérée avec ~270 lignes au lieu de ~1900 | Airbyte n'a lu que la première feuille du classeur multi-onglets | Pré-consolider avec `scripts/consolidate_wu.py` |
| Les colonnes raw sont en `MixedCase` (`"Temperature"`, `"Dew_Point"`) | Comportement Airbyte : il préserve la casse d'origine et quote les identifiants | Requêter avec des doubles guillemets : `SELECT "Temperature" FROM raw.raw_madeleine;` |
| Airbyte rôle Postgres : `permission denied for database` | Manque d'un `GRANT CREATE, TEMPORARY ON DATABASE` | Vérifier que la ligne est bien dans `01_init_schemas.sql` |
| `dbt debug` → `dbt_project.yml file [ERROR not found]` | Commande lancée depuis la racine du repo au lieu du dossier `dbt/` | `cd dbt` avant la commande |
| `dbt debug` → `password authentication failed for user "dbt"` | Variable `DBT_PASSWORD` non chargée dans le shell | Recharger le `.env` (cf. C.3) |

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

# --- DBT (depuis le dossier dbt/)
dbt clean                              # supprime target/ et dbt_packages/
dbt run --select stg_wu__la_madeleine  # un modèle
dbt run --select staging               # toute une couche
dbt run --full-refresh                 # recrée tout
dbt docs generate && dbt docs serve    # doc avec lineage interactif (port 8080)
```

---

## ➡️ Prochaines étapes

| Étape | Description | Statut |
|---|---|---|
| 0 — Environnement | Postgres + Airbyte + DBT en local | ✅ |
| 1 — Ingestion Airbyte | 3 tables raw alimentées | ✅ |
| 2 — Modélisation DBT | staging → intermediate → marts (étoile) | 🚧 en cours |
| 3 — Tests qualité | tests DBT unitaires + tests métier | ⏳ |
| 4 — Documentation | `dbt docs` + lineage exporté | ⏳ |
| 5 — Déploiement AWS | Postgres RDS + Airbyte EC2 + DBT ECS | ⏳ |
