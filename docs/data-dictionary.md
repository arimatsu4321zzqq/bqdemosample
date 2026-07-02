# データ辞書 — デモ第一弾の3データセット

対象: `bigquery-public-data` の `thelook_ecommerce` / `google_trends` / `austin_bikeshare`。
実スキーマ（`bq show --schema`）から取得。各カラムに日本語の意味を付与。エージェントの context 作成にも流用する。

---

## 1. thelook_ecommerce（合成EC：売上・顧客・商品）

ECサイトを模した**業務系リレーショナルデータ**。`orders`/`order_items` を軸に `products`・`users` を結合して使う。

### orders（注文ヘッダ）
| カラム | 型 | 意味 |
|---|---|---|
| order_id | INTEGER | 注文ID（主キー） |
| user_id | INTEGER | 注文した顧客ID（→ users.id） |
| status | STRING | 注文状態（Complete / Shipped / Processing / Cancelled / Returned） |
| gender | STRING | 注文者の性別 |
| created_at | TIMESTAMP | 注文日時 |
| returned_at | TIMESTAMP | 返品日時（なければNULL） |
| shipped_at | TIMESTAMP | 出荷日時 |
| delivered_at | TIMESTAMP | 配達完了日時 |
| num_of_item | INTEGER | 注文内の商品点数 |

### order_items（注文明細：1商品=1行。売上分析の主役）
| カラム | 型 | 意味 |
|---|---|---|
| id | INTEGER | 明細ID（主キー） |
| order_id | INTEGER | 注文ID（→ orders.order_id） |
| user_id | INTEGER | 顧客ID（→ users.id） |
| product_id | INTEGER | 商品ID（→ products.id） |
| inventory_item_id | INTEGER | 在庫アイテムID（→ inventory_items.id） |
| status | STRING | 明細状態（注文と同様） |
| created_at | TIMESTAMP | 注文日時 |
| shipped_at | TIMESTAMP | 出荷日時 |
| delivered_at | TIMESTAMP | 配達日時 |
| returned_at | TIMESTAMP | 返品日時 |
| sale_price | FLOAT | **販売価格（売上金額）。集計の中心** |

### products（商品マスタ）
| カラム | 型 | 意味 |
|---|---|---|
| id | INTEGER | 商品ID（主キー） |
| cost | FLOAT | 原価 |
| category | STRING | 商品カテゴリ（例: Jeans, Tops…） |
| name | STRING | 商品名 |
| brand | STRING | ブランド |
| retail_price | FLOAT | 定価（小売価格） |
| department | STRING | 部門（Men / Women） |
| sku | STRING | SKUコード |
| distribution_center_id | INTEGER | 物流拠点ID（→ distribution_centers.id） |

### users（顧客マスタ）
| カラム | 型 | 意味 |
|---|---|---|
| id | INTEGER | 顧客ID（主キー） |
| first_name / last_name | STRING | 氏名 |
| email | STRING | メール |
| age | INTEGER | 年齢 |
| gender | STRING | 性別 |
| state | STRING | 州/都道府県 |
| street_address | STRING | 住所 |
| postal_code | STRING | 郵便番号 |
| city | STRING | 市区町村 |
| country | STRING | 国 |
| latitude / longitude | FLOAT | 緯度・経度 |
| traffic_source | STRING | 流入元（Organic / Facebook / Search…） |
| created_at | TIMESTAMP | 登録日時 |
| user_geom | GEOGRAPHY | 位置情報（地理型） |

### inventory_items（在庫アイテム：商品の個体）
| カラム | 型 | 意味 |
|---|---|---|
| id | INTEGER | 在庫アイテムID（主キー） |
| product_id | INTEGER | 商品ID（→ products.id） |
| created_at | TIMESTAMP | 入庫日時 |
| sold_at | TIMESTAMP | 販売日時（未販売はNULL） |
| cost | FLOAT | 原価 |
| product_category | STRING | 商品カテゴリ（非正規化） |
| product_name | STRING | 商品名（非正規化） |
| product_brand | STRING | ブランド（非正規化） |
| product_retail_price | FLOAT | 定価（非正規化） |
| product_department | STRING | 部門（非正規化） |
| product_sku | STRING | SKU（非正規化） |
| product_distribution_center_id | INTEGER | 物流拠点ID |

### events（Webアクセスログ）
| カラム | 型 | 意味 |
|---|---|---|
| id | INTEGER | イベントID（主キー） |
| user_id | INTEGER | 顧客ID（匿名はNULL） |
| sequence_number | INTEGER | セッション内の順番 |
| session_id | STRING | セッションID |
| created_at | TIMESTAMP | 発生日時 |
| ip_address | STRING | IPアドレス |
| city / state / postal_code | STRING | アクセス地域 |
| browser | STRING | ブラウザ |
| traffic_source | STRING | 流入元 |
| uri | STRING | アクセスURL |
| event_type | STRING | イベント種別（cart / purchase / product…） |

### distribution_centers（物流拠点マスタ）
| カラム | 型 | 意味 |
|---|---|---|
| id | INTEGER | 拠点ID（主キー） |
| name | STRING | 拠点名（都市名） |
| latitude / longitude | FLOAT | 緯度・経度 |
| distribution_center_geom | GEOGRAPHY | 位置情報（地理型） |

---

## 2. google_trends（検索トレンド：地域×時系列）

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

---

## 3. austin_bikeshare（シェアサイクル：人流・移動）

米テキサス州オースティンの公共シェアサイクル。**移動ログ（trips）＋ステーション（stations）**が本体。残りは日次集計の派生テーブル。

### bikeshare_trips（移動ログ：1乗車=1行。人流分析の主役）
| カラム | 型 | 意味 |
|---|---|---|
| trip_id | STRING | 乗車ID |
| subscriber_type | STRING | 会員種別（年間/月間/単発/Walk Up 等） |
| bike_id | STRING | 使用した自転車ID |
| bike_type | STRING | 自転車種別（electric / classic 等） |
| start_time | TIMESTAMP | **乗車開始日時（時間帯・曜日分析の軸）** |
| start_station_id | INTEGER | 出発ステーションID |
| start_station_name | STRING | 出発ステーション名 |
| end_station_id | STRING | 到着ステーションID |
| end_station_name | STRING | 到着ステーション名 |
| duration_minutes | INTEGER | 乗車時間（分） |

### bikeshare_stations（ステーションマスタ）
| カラム | 型 | 意味 |
|---|---|---|
| station_id | INTEGER | ステーションID（主キー） |
| name | STRING | ステーション名 |
| status | STRING | 稼働状態（active / closed 等） |
| location | STRING | 位置（緯度経度の文字列） |
| address | STRING | 住所 |
| alternate_name | STRING | 別名 |
| city_asset_number | INTEGER | 市の資産番号 |
| property_type | STRING | 設置区分 |
| number_of_docks | INTEGER | ドック数（駐輪可能台数） |
| power_type | STRING | 電源種別 |
| footprint_length / footprint_width | INTEGER/FLOAT | 設置区画の長さ・幅 |
| notes | STRING | 備考 |
| council_district | INTEGER | 行政区 |
| image | STRING | 画像URL |
| modified_date | TIMESTAMP | 更新日時 |

### 派生（日次集計）テーブル ※同じ「日別乗車数」の別バージョン
| テーブル | カラム | 意味 |
|---|---|---|
| bikeshare_trips_daily_counts | trip_date(DATE), trip_count(INT) | 日別乗車数 |
| daily_bikeshare_trips | trip_date(DATE), num_trips(INT) | 日別乗車数（別名版） |
| daily_ride_counts | ride_date(DATE), daily_rides(INT) | 日別乗車数（別名版） |
| daily_trip_counts | trip_date(DATE), trip_count(INT) | 日別乗車数（別名版） |

> 日次集計は内容が重複しているので、デモでは `bikeshare_trips`（生ログ）を主に使い、必要なら集計は自前で行うのがきれい。
