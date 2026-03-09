# F1 Data Warehouse — dbt Project

Formula 1 Data Warehouse built on Databricks + Delta Lake, following Medallion Architecture.
Transformations managed with **dbt Core** and deployed via **Azure DevOps CI/CD**.

---

## Project Structure

```
f1_data_warehouse/
├── models/
│   ├── bronze/
│   │   └── sources.yml          # Source declarations pointing to Delta Bronze tables
│   ├── silver/
│   │   ├── dim_drivers.sql      # Driver dimension (deduplicated, cleaned)
│   │   ├── dim_sessions.sql     # Session dimension (all session types)
│   │   ├── fct_race_results.sql # Race-level fact table (aggregated per driver per race)
│   │   ├── fct_lap_times.sql    # Granular lap-level fact table
│   │   └── schema.yml           # Column docs + tests
│   └── marts/                   # (upcoming) analytics-ready aggregations
├── macros/
│   └── seconds_to_laptime.sql   # Helper macro: seconds → M:SS.mmm
├── dbt_project.yml
├── profiles.yml                  # Databricks connection config
├── packages.yml
└── azure-pipelines.yml           # CI/CD pipeline (3 stages)
```

---

## Data Sources (OpenF1 API)

| Bronze Table           | OpenF1 Endpoint       | Description                     |
|------------------------|-----------------------|---------------------------------|
| `openf1_drivers`       | `/v1/drivers`         | Driver info + team affiliation  |
| `openf1_sessions`      | `/v1/sessions`        | Race weekend sessions metadata  |
| `openf1_laps`          | `/v1/laps`            | Per-lap timing + sector splits  |
| `openf1_pit`           | `/v1/pit`             | Pit stop durations              |
| `openf1_stints`        | `/v1/stints`          | Tyre stint + compound data      |

---

## Silver Layer Models

### Dimensions
- **`dim_drivers`** — One row per driver per season. Cleaned names, team, country.
- **`dim_sessions`** — One row per session. Flags for race / qualifying sessions.

### Facts
- **`fct_race_results`** — One row per driver per race. Aggregated lap metrics, pit stop counts, speed.
- **`fct_lap_times`** — One row per lap per driver. Granular timing, sector splits, tyre compound, clean lap flag.

---

## Setup

### 1. Install dbt

```bash
pip install dbt-databricks==1.8.0
```

### 2. Configure environment variables

```bash
export DATABRICKS_HOST="<your-workspace>.azuredatabricks.net"
export DATABRICKS_HTTP_PATH="/sql/1.0/warehouses/<warehouse-id>"
export DATABRICKS_TOKEN="<personal-access-token>"
```

### 3. Install dbt packages

```bash
dbt deps
```

### 4. Run models

```bash
# Full run
dbt run

# Silver layer only
dbt run --select silver

# Single model
dbt run --select dim_drivers
```

### 5. Run tests

```bash
dbt test
```

---

## CI/CD (Azure DevOps)

| Stage         | Trigger                  | Actions                                      |
|---------------|--------------------------|----------------------------------------------|
| **CI**        | PR → `main`              | Lint (SQLFluff) + slim run (modified models) |
| **Deploy Dev**| Merge → `develop`        | Full `dbt run` + `dbt test` on Dev           |
| **Deploy Prod**| Merge → `main`          | Full run + test + docs generation (with manual approval gate) |

### Required Azure DevOps Pipeline Variables

| Variable                    | Description                          |
|-----------------------------|--------------------------------------|
| `DATABRICKS_HOST`           | Dev workspace hostname               |
| `DATABRICKS_HTTP_PATH`      | Dev SQL warehouse HTTP path          |
| `DATABRICKS_TOKEN_DEV`      | Dev personal access token (secret)   |
| `DATABRICKS_HOST_PROD`      | Prod workspace hostname              |
| `DATABRICKS_HTTP_PATH_PROD` | Prod SQL warehouse HTTP path         |
| `DATABRICKS_TOKEN_PROD`     | Prod personal access token (secret)  |

---

## What's Next (Marts Layer)

- `mart_driver_championship` — Rolling points standings per race
- `mart_team_performance` — Constructor-level aggregations
- `mart_race_pace_analysis` — Tyre strategy + pace degradation analytics