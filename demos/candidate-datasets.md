# 候補データセット（採用保留・横展の予備メモ）

google-trends に続く**第2・第3デモの候補**。採用するか未定のため、フォルダ化はまだしない。
採用が決まったら、この内容を雛形に `demos/<名前>/`（google-trends と同じ構成）を作る。

BQ public データで実スキーマ確認済み。データ辞書と Looker レイアウト案まで検討は済んでいる。

---

## 候補A：thelook_ecommerce（EC売上BI）

- 元データ: `bigquery-public-data.thelook_ecommerce`（US マルチリージョン）
- テーマ: 業務BI（売上・顧客・商品）。経営者向けの王道。
- 主なテーブル: `order_items`（売上の主役）/ `orders` / `products` / `users`

### データ辞書（主要テーブル）

#### orders（注文ヘッダ）
| カラム | 型 | 意味 |
|---|---|---|
| order_id | INTEGER | 注文ID（主キー） |
| user_id | INTEGER | 注文した顧客ID（→ users.id） |
| status | STRING | 注文状態（Complete / Shipped / Processing / Cancelled / Returned） |
| gender | STRING | 注文者の性別 |
| created_at | TIMESTAMP | 注文日時 |
| returned_at | TIMESTAMP | 返品日時（なければNULL） |
| shipped_at / delivered_at | TIMESTAMP | 出荷/配達完了日時 |
| num_of_item | INTEGER | 注文内の商品点数 |

#### order_items（注文明細：1商品=1行。売上分析の主役）
| カラム | 型 | 意味 |
|---|---|---|
| id | INTEGER | 明細ID（主キー） |
| order_id | INTEGER | 注文ID（→ orders.order_id） |
| user_id | INTEGER | 顧客ID（→ users.id） |
| product_id | INTEGER | 商品ID（→ products.id） |
| status | STRING | 明細状態（注文と同様） |
| created_at / shipped_at / delivered_at / returned_at | TIMESTAMP | 各種日時 |
| sale_price | FLOAT | **販売価格（売上金額）。集計の中心** |

#### products（商品マスタ）
| カラム | 型 | 意味 |
|---|---|---|
| id | INTEGER | 商品ID（主キー） |
| cost | FLOAT | 原価 |
| category | STRING | 商品カテゴリ（Jeans, Tops…） |
| name | STRING | 商品名 |
| brand | STRING | ブランド |
| retail_price | FLOAT | 定価 |
| department | STRING | 部門（Men / Women） |
| sku | STRING | SKUコード |

#### users（顧客マスタ）
| カラム | 型 | 意味 |
|---|---|---|
| id | INTEGER | 顧客ID（主キー） |
| age / gender | INTEGER/STRING | 年齢・性別 |
| country / state / city | STRING | 国・州・市 |
| traffic_source | STRING | 流入元（Organic / Facebook / Search…） |
| created_at | TIMESTAMP | 登録日時 |

> 他に inventory_items（在庫個体）/ events（Webアクセスログ）/ distribution_centers（物流拠点）あり。

### Looker レイアウト案（1ページ）
| # | チャート | ディメンション | 指標 | 元データ |
|---|---|---|---|---|
| 1 | スコアカード×4 | — | 総売上=SUM(sale_price) / 注文数=CD(order_id) / 顧客数=CD(user_id) / 平均単価 | order_items |
| 2 | 時系列 | created_at（月） | SUM(sale_price) | order_items |
| 3 | 横棒 | products.category | SUM(sale_price) | order_items×products |
| 4 | 地域別マップ | users.country | SUM(sale_price) | order_items×users |
| 5 | ドーナツ | products.department | SUM(sale_price) | order_items×products |
| 6 | 横棒 | products.brand（Top10） | SUM(sale_price) | order_items×products |
| 7 | テーブル | products.name | 売上・注文数・返品率 | order_items×products |

> 計算フィールド例：返品率 = COUNT(returned_at)/COUNT(order_id)、粗利 = sale_price − cost
> 多ページ案: P1サマリー / P2売上トレンド / P3商品分析 / P4顧客分析 / P5地域分析 / P6明細ドリル

---

## 候補B：austin_bikeshare（人流・移動）

- 元データ: `bigquery-public-data.austin_bikeshare`（US マルチリージョン）
- テーマ: 人流・移動（ドコモ親和性が高い）。時間帯ヒートマップ・移動動線が見せ場。
- 主なテーブル: `bikeshare_trips`（人流の主役）/ `bikeshare_stations`

### データ辞書（主要テーブル）

#### bikeshare_trips（移動ログ：1乗車=1行）
| カラム | 型 | 意味 |
|---|---|---|
| trip_id | STRING | 乗車ID |
| subscriber_type | STRING | 会員種別（年間/月間/単発/Walk Up 等） |
| bike_id | STRING | 自転車ID |
| bike_type | STRING | 自転車種別（electric / classic 等） |
| start_time | TIMESTAMP | **乗車開始日時（時間帯・曜日分析の軸）** |
| start_station_id / start_station_name | INTEGER/STRING | 出発ステーション |
| end_station_id / end_station_name | STRING | 到着ステーション |
| duration_minutes | INTEGER | 乗車時間（分） |

#### bikeshare_stations（ステーションマスタ）
| カラム | 型 | 意味 |
|---|---|---|
| station_id | INTEGER | ステーションID（主キー） |
| name | STRING | ステーション名 |
| status | STRING | 稼働状態（active / closed 等） |
| location | STRING | 位置（緯度経度の文字列。マップ用に分解が必要） |
| number_of_docks | INTEGER | ドック数 |
| council_district | INTEGER | 行政区 |

> 派生の日次集計テーブル（daily系）は内容が重複。デモでは生ログ trips を主に使い集計は自前が綺麗。

### Looker レイアウト案（1ページ）
| # | チャート | ディメンション | 指標 | 元データ |
|---|---|---|---|---|
| 1 | スコアカード×4 | — | 総乗車=COUNT / 平均=AVG(duration_minutes) / 稼働駅数 / 電動比率 | bikeshare_trips |
| 2 | 時系列 | start_time（日） | COUNT(trip_id) | bikeshare_trips |
| 3 | ヒートマップ（ピボット＋条件付き書式） | 時(HOUR) × 曜日 | COUNT(trip_id) | bikeshare_trips |
| 4 | バブルマップ | station 緯度経度 | COUNT(trip_id) | trips×stations |
| 5 | 横棒 | start_station_name（Top10） | COUNT(trip_id) | bikeshare_trips |
| 6 | 円×2 | subscriber_type / bike_type | COUNT(trip_id) | bikeshare_trips |
| 7 | テーブル | 出発→到着（連結） | COUNT(trip_id) | bikeshare_trips |

> 計算フィールド例：時間帯=HOUR(start_time)、曜日=WEEKDAY(start_time)、電動比率=COUNTIF(bike_type='electric')/COUNT()
> 多ページ案: P1概況 / P2時間分析 / P3ステーション分析 / P4移動動線 / P5利用者属性
