# Architecture Decision Record (ADR)
## CineData Analytics — Databricks Lakehouse Pipeline

This document consolidates the architectural decisions, data modeling justifications, business rules, and data contracts applied across the Lakehouse pipeline (Bronze, Silver, and Gold layers).

---

## 1. silver.tb_info_filmes (Source: `bronze.tb_movies_info`)

### Decision 1.1: Canonical Deduplication by Motion Picture Work (`tconst`) vs. Technical Identifier (`id`)
* **Context**: 
  - The raw source dataset (`movies_info_TMDB_IMDB.csv`) exhibits severe catalog duplicate anomalies resulting from duplicate entries in TMDB. A total of **321 IMDb codes (`tconst`) were associated with multiple numeric TMDB `id`s**, totaling **986 distinct IDs** (665 redundant instances).
  - The most critical example is the movie *Die Hart 2: Die Harter* (`tt32094375`), which appeared in **1,716 duplicated rows across 61 distinct numeric TMDB IDs** (`1300214`, `1362673`, `1611488`, `1476515`, etc.), all with the same release date (`2024-05-30`).
* **Engineering & Business Decision**:
  - **Primacy of Real Intellectual Work over Technical Keys**: The analytical integrity of the actual cinematic work (represented by the universal IMDb industry identifier `tconst`) takes precedence over the local TMDB technical key (`id`).
  - **Resolution Mechanism**: Deduplication in the Silver layer was implemented by partitioning primarily on the universal key `coalesce(tconst, id)`, sorting by `ingestion_datetime DESC NULLS LAST`, and breaking ties with `id ASC`.
  - **Schema Preservation & Dropping of `tconst`**: Once uniqueness of the work is resolved and the latest canonical record is selected, `tconst` is dropped, and the chosen technical `id_filme` is preserved to strictly satisfy the Silver layer data contract and enable downstream joins.
* **Analytical and Metric Impact**:
  - **Cast Appearances**: Neutralized Kevin Hart's artificial distortion (from 64 nominal appearances due to *Die Hart 2* duplicates down to his 2 legitimate releases in the period), revealing the true ranking led by Suhas (4 appearances).
  - **Genre Distribution**: Expunged hundreds of phantom genre counts in replicated movies (e.g., Action at 5,935 real movies vs. 6,049 inflated).
  - **Financial Integrity**: Eliminated **US$ 489,329.00** in duplicate revenue and **US$ 2,054,749.00** in phantom budget spread across multiple IDs for the same work.

### Decision 1.2: Status Normalization and Declarative Mapping with Fallback
* **Context**: Status records contain casing discrepancies, redundant hyphens (`"Post-Production"`, `"in-production"`), and unknown values.
* **Decision**: Applied regex normalization and a `create_map` construct with an explicit fallback to `"Não Informado"`.

---

## 2. silver.tb_financeiro_filmes (Source: `bronze.tb_movies_financials`)

### Decision 2.1: Deduplication with Tie-Breaking by Highest Non-Null Value
* **Context**: The source exhibits duplicate rows for the same `id` with conflicting data (e.g., one row with valid box office coexisting with another row containing zeros or the sentinel string `Unknown`).
* **Decision**: 
  - Revenue and budget columns are sanitized and typed prior to windowing.
  - The deduplication window explicitly prioritizes the highest populated value: `orderBy(col("receita_usd").desc_nulls_last(), col("orcamento_usd").desc_nulls_last(), col("ingestion_datetime").desc())`.
  - Ensures the most complete financial data is retained without loss from blind deterministic deduplication.

### Decision 2.2: Monetary Metric Sanitization and Scale Parsing
* **Context**: The `budget` and `revenue` columns contain noisy artifacts: sentinel strings (`"Unknown"`, `"Não Informado"`), currency symbols (`$`, `USD`), whitespace, scale abbreviations (`10.0M`, `18.0K`), zeros, and negative values (e.g., `-800526015`).
* **Decision**:
  1. **Sentinels $\rightarrow$ `NULL`**: Any textual indicator of missing data is converted to `NULL` before calculations.
  2. **Symbol Sanitization**: Regex removal of `$`, `USD`, and redundant whitespace.
  3. **Scale Multipliers**: Parsing suffixes `K` ($\times 10^3$), `M` ($\times 10^6$), and `B` ($\times 10^9$) to multiply against the numeric base.
  4. **Invalid Values ($\le 0$) $\rightarrow$ `NULL`**: Zero and negative amounts are invalidated to `NULL` in accordance with data contract rules.
  5. **Typing and Precision**: Cast to `DECIMAL(18, 2)` for accounting-grade precision.
  6. **Safe Profit & Margin Calculations**: Built-in division-by-zero protection and controlled null propagation for `margem_lucro_percentual`.

---

## 3. silver.tb_metricas_engajamento (Source: `bronze.tb_movies_metrics`)

### Decision 3.1: Safe Casting Against Column Shift and Range Validation
* **Context**: The raw file suffers from structural column shift, causing textual fragments from overviews and titles to bleed into numeric rating and vote columns, along with comma-decimal numbers (`154,34`) and out-of-scale ratings (e.g., `79.97`).
* **Decision**:
  1. Pre-substitution of commas with standard periods.
  2. Utilization of `try_cast` to prevent Spark job crashes on invalid literal strings.
  3. Application of business domain constraints: `nota_media_tmdb` and `nota_media_imdb` restricted to the range $[0.0, 10.0]$; `popularidade`, `qtd_votos_tmdb`, and `qtd_votos_imdb` constrained to $\ge 0$. Anomalous values are converted to `NULL`.

---

## 4. silver.tb_avaliacoes_usuarios (Source: `bronze.tb_movies_reviews`)

### Decision 4.1: Full Deduplication and Review Normalization
* **Context**: The user reviews table contains 194,472 raw records with high duplicate volume resulting from unconstrained append executions.
* **Decision**:
  1. **Full Deduplication**: Executed `dropDuplicates(["id", "nome", "nota", "comentario"])`, retaining 32,412 unique user reviews.
  2. **Rating Validation**: Ratings outside $[0.0, 10.0]$ converted to `NULL`.
  3. **Missing Comments**: Empty or `NULL` comments receive the default text `"Sem comentário"`.

---

## 5. silver.tb_generos (Source: `bronze.tb_credits_and_tags`)

### Decision 5.1: Atomic Unnesting and Canonical Domain Filtering
* **Context**: The `genres` column contains delimited lists using mixed separators (`,`, `;`, `|`), along with column shift residue (image URLs `.jpg`, decimal floats `0.6`, country codes).
* **Decision**:
  1. **Separator Standardization**: Replaced `[,;|]+` with commas and applied `explode(split(...))`.
  2. **Canonical TMDB Domain Filtering**: Strict filtering against the 19 official TMDB genres (`Action`, `Adventure`, `Animation`, `Comedy`, `Crime`, `Documentary`, `Drama`, `Family`, `Fantasy`, `History`, `Horror`, `Music`, `Mystery`, `Romance`, `Science Fiction`, `TV Movie`, `Thriller`, `War`, `Western`).
  3. **Relationship Deduplication**: Executed `dropDuplicates(["id_filme", "nome_genero"])`.

---

## 6. silver.tb_pessoas_empresas (Source: `bronze.tb_credits_and_tags`)

### Decision 6.1: Consolidation into Unified Entity Dimension
* **Context**: Industry contributors are distributed across 4 distinct columns (`cast`, `directors`, `writers`, `production_companies`) in varied formats.
* **Decision**:
  1. **Entity Role Mapping**:
     - `cast` $\rightarrow$ `'Ator'`
     - `directors` $\rightarrow$ `'Diretor'`
     - `writers` $\rightarrow$ `'Roteirista'`
     - `production_companies` $\rightarrow$ `'Produtora'`
  2. **Text Cleaning**: Stripped quotation marks, brackets `[]`, and standardized casing with `initcap`.
  3. **Column Shift Purging**: Excluded image extensions (`.jpg`, `.png`), URLs (`http`, `www`), numeric strings, and sentinel markers (`N/A`, `Unknown`).
  4. **Union & Deduplication**: Unified via `unionByName` and deduplicated by the tuple `(id_filme, nome_entidade, tipo_entidade)`.

---

## 7. silver.tb_cotacao_dolar (Source: `bronze.tb_cotacao_dolar`)

### Decision 7.1: Continuous Time Series and Forward Fill
* **Context**: The Central Bank of Brazil (BACEN PTAX) API reports quotes solely on business days, creating gaps on weekends and holidays.
* **Decision**:
  1. **Daily Deduplication**: Selected the final quote registered per business day.
  2. **Calendar Generation**: Created an unbroken date interval using `sequence(min_date, max_date, interval 1 day)`.
  3. **Forward Fill**: Implemented forward filling (`last(cotacao_compra_bruta, ignorenulls=True).over(Window.orderBy("data_cotacao").rowsBetween(Window.unboundedPreceding, Window.currentRow))`) to guarantee complete temporal coverage.
  4. **Precision**: Stored as `DECIMAL(18, 4)` for exchange rate accuracy.

---

## 8. Dimensional Modeling (Gold Layer - Star Schema)

### Decision 8.1: Deterministic Surrogate Keys
* **Context**: Establish robust relationships between facts and dimensions independent of upstream source natural keys.
* **Decision**:
  - Generated `BIGINT` surrogate keys (`sk_movie_id`, `sk_genre_id`, `sk_person_id`, `sk_company_id`, `sk_review_id`) using `row_number().over(Window.orderBy(...))`.

### Decision 8.2: N:N Decoupling via Bridge Tables
* **Context**: Films exhibit M:N relationships with genres, cast/crew, and production companies.
* **Decision**:
  - Implemented `gold.bridge_movie_genre`, `gold.bridge_movie_person`, and `gold.bridge_movie_company`.
  - Prevents row explosion and metric distortion in `fact_movies_performance`, preserving its strict 1:1 movie grain.

### Decision 8.3: Catalog Completeness in Fact Table
* **Context**: Movies may lack financial data or engagement metrics.
* **Decision**:
  - Executed a `LEFT JOIN` starting from `dim_movies` toward `silver.tb_financeiro_filmes` and `silver.tb_metricas_engajamento`, ensuring that every movie in the catalog is preserved in the analytical fact table.

---

## 9. GenAI Context Data Mart (`gold.gold_genai_movies_context`)

### Decision 9.1: NULL-Safety and Declarative Context Engineering
* **Context**: String concatenation functions return `NULL` if any input component is null, leading to silent drops of movie records in downstream vector stores.
* **Decision**:
  - Implemented explicit fallback handling via `coalesce` and conditional expressions for all metadata fields (title, year, formatted revenue, formatted budget, aggregated top actors, aggregated directors, overview).
  - Guarantees 100% text population for the `llm_context_document` column.
