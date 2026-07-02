# データ辞書 — google_trends（検索トレンド：地域×時系列）

対象: `bigquery-public-data.google_trends`。実スキーマ（`bq show --schema`）から取得。各カラムに日本語の意味を付与。エージェントの context 作成にも流用する。

> 本デモの curated テーブル（`demo_google_trends.jp_top_terms` / `jp_top_rising_terms`）の作り方は
> [`setup.md`](./setup.md) と [`sql/create_google_trends_demo.sql`](./sql/create_google_trends_demo.sql) を参照。以下は元データの生スキーマ。

Google検索の人気/急上昇ワードの週次ランキング。**US地域別（DMA）**と**国際（国別）**の2系統 ×（人気/急上昇）の4テーブル。

> DMA = Designated Market Area（米国の地域メディア圏。約210区分）。

### top_terms（US地域別・人気検索ワード）
| カラム | 型 | 意味 |
|---|---|---|
| dma_id | INTEGER | 地域ID（DMA） |
| dma_name | STRING | 地域名（例: New York NY） |
| term | STRING | 検索ワード |
| week | DATE | 対象週 |
| rank | INTEGER | 週内の順位（1〜25等） |
| score | INTEGER | 人気スコア（0〜100の相対値） |
| refresh_date | DATE | データ更新日 |

### top_rising_terms（US地域別・急上昇ワード）
| カラム | 型 | 意味 |
|---|---|---|
| dma_id | INTEGER | 地域ID（DMA） |
| dma_name | STRING | 地域名 |
| term | STRING | 検索ワード |
| week | DATE | 対象週 |
| rank | INTEGER | 急上昇順位 |
| score | INTEGER | スコア |
| percent_gain | INTEGER | **上昇率（%）。急上昇の度合い** |
| refresh_date | DATE | 更新日 |

### international_top_terms（国際・人気検索ワード）
| カラム | 型 | 意味 |
|---|---|---|
| country_name | STRING | 国名（例: Japan） |
| country_code | STRING | 国コード（例: JP） |
| region_name | STRING | 地域名（国内の地方） |
| region_code | STRING | 地域コード |
| term | STRING | 検索ワード |
| week | DATE | 対象週 |
| rank | INTEGER | 順位 |
| score | INTEGER | 人気スコア |
| refresh_date | DATE | 更新日 |

### international_top_rising_terms（国際・急上昇ワード）
| カラム | 型 | 意味 |
|---|---|---|
| country_name / country_code | STRING | 国名・国コード |
| region_name / region_code | STRING | 地域名・地域コード |
| term | STRING | 検索ワード |
| week | DATE | 対象週 |
| rank | INTEGER | 急上昇順位 |
| score | INTEGER | スコア |
| percent_gain | INTEGER | 上昇率（%） |
| refresh_date | DATE | 更新日 |
