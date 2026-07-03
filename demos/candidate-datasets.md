# 候補データセット詳細（調査・設計メモ）

デモ題材として検討した候補の**詳細資料**（データ辞書・実現性調査・レイアウト案・curated設計案）。
どれを採用しどれを保留したかの一覧・理由は [`candidate-overview.md`](./candidate-overview.md)、
選定の経緯は [`demo-selection-rationale.md`](./demo-selection-rationale.md) を参照。

- 第1部: **地域特化候補の実現性調査**（geo_openstreetmap / ghcn_d）— 実クエリで中身を検証済み（2026-07-03）
- 第2部: **旧候補の設計メモ**（thelook_ecommerce / austin_bikeshare）— スキーマ確認済み・調査は未実施

---
---

# 第1部 地域特化候補の実現性調査（geo_openstreetmap / ghcn_d）

「ある地域（自治体）で絞って、その地域の傾向・特徴を見せる」テーマの候補2件について、
BigQuery 公開データの**実データを実クエリで検証**した結果（調査日: 2026-07-03、プロジェクト `ci-ss4-develop`）。

> 結果、**OSM はデモ②として採用済み**（→ [`osm-facilities/`](./osm-facilities/)。全国版で構築済み）。
> GHCN-D は第3デモ最有力として本調査結果を温存している。

## 比較サマリ

| 観点 | A: geo_openstreetmap（施設POI）✅採用 | B: ghcn_d（NOAA 日別気象）🔶保留 |
|---|---|---|
| 実現可否 | ○（条件付き） | ○（条件付き） |
| 地域の絞り方 | **市区町村単位**（admin_level=7 境界 1,778件で日本の自治体網羅） | 代表観測所単位（日本 202 所、現役約160所。市町村粒度は不可） |
| データ鮮度 | **✗ 2021-11-08 で更新停止**（スナップショット明示が必要） | ○ 日次更新継続（気温2〜3週遅れ。**降水・積雪は3ヶ月超遅れ**） |
| 日本語対応 | `name` タグ自体が日本語（欠損0.3〜2%） | 観測所名はローマ字・都道府県情報なし → 自前dim必須 |
| 構築コスト | 一回 $1〜2 想定（実績は全国版で約$0.25。以後はほぼゼロ） | 一回 40〜60GB スキャン。curated は約0.5GBと極小 |
| 見せ場 | 自治体切替の施設マップ（病院・学校・公民館） | 長期気候トレンド（1951年〜）＋実災害と一致する豪雨・豪雪分析 |
| 最大の弱点 | 避難所タグが全国224件で実用外 → 「避難所候補施設」に読み替え | 東京観測所が2025-08で停止。アメダス非収録 |

## 候補A: geo_openstreetmap（地域の主要施設マップ）✅ デモ②として採用済み

**結論: ○（条件付きで実現可能）。** 病院・学校・公民館の POI 抽出、自治体境界（admin_level=7）での
ST_WITHIN 切り出し、日本語名・緯度経度付き curated テーブル作成はすべて実クエリで確認済み。
ただし (1) スナップショットが 2021-11-08 で更新停止、(2) 避難所タグ（emergency=assembly_point）は
全国 224 件と極端に疎、のため「防災・避難所デモ」の主役には弱い。
「地域の施設マップ + 自治体切替」デモとしては成立する。

### 主要テーブル

| テーブル | 行数 | サイズ | 備考 |
|---|---|---|---|
| planet_features | 9.9億 | 352 GB | 全ジオメトリ統合。geometry でクラスタリング |
| planet_features_points | 1.8億 | 27 GB | ノード（POI）のみ |
| planet_features_multipolygons | 5.6億 | 198 GB | 行政境界・建物ポリゴン |

- `all_tags` は `ARRAY<STRUCT<key,value>>`。タグ取得は `(SELECT value FROM UNNEST(all_tags) WHERE key='amenity')`。
- **鮮度: MAX(osm_timestamp)=2021-11-08 で更新停止。** デモでは「2021年時点」と明示する。

### 実クエリ検証の要点

- **geometry クラスタの枝刈りが劇的**: bbox 付き points クエリは dry_run 見積 22.7GB → **実処理 0.07〜0.5GB**。
  ただしタグのみのフィルタ（境界抽出等）は枝刈り不可で満額（27.5GB 実測）。dry_run はクラスタ枝刈りを反映しない点に注意。
- **岐阜周辺 bbox の施設件数（pointsのみ）**: school 952 / hospital 375 / community_centre 320 / clinic 45。
  name あり 97〜99%超、`name` 自体が日本語（「灯台笹公民館」「市立平中学校」等）。`name:ja` はほぼ欠損だが実害なし。
- **行政境界**: admin_level=7 に日本の市区町村 1,778 件（岐阜市・高山市・大垣市・各務原市・飛騨市の存在確認済み）。
  → 自治体切替は admin_level=7 の name 一致で実現可能。admin_level=6/8 は主に中国の行政区なので使わない。
- **避難所タグは実用外**: `emergency=assembly_point` 全国 224 件（出雲市等タグ付けした自治体に偏在）。
  `amenity=shelter` 2,626 件は大半が東屋。→「避難所候補施設（学校・公民館・病院）」として設計する。
- **points のみでは過小**: 学校・病院は面（way/multipolygon）で描かれているものが多い。
  curated 構築は planet_features（全形状）+ ST_CENTROID で行う（岐阜952校は points のみの数字）。

### 実際の構築結果（デモ②）

調査時の設計案から変更した点も含め、最終形は [`osm-facilities/`](./osm-facilities/) を参照:
- 範囲は岐阜県先行 → **全国47都道府県・1,742市区町村・87,745施設**に拡大（行数・コストとも問題なし）
- 都道府県の紐付けは重心判定 → **面積過半の重なり**判定に変更（川沿い境界の笠松町が漏れたため）
- 地域切替は bbox パラメータ入力ではなく **muni_name ドロップダウン**方式を採用
- データフローの全体図は [`osm-facilities/data-flow.md`](./osm-facilities/data-flow.md)

### リスク

鮮度2021年（閉院・統廃合が未反映。最新が必要なら Overture Maps や国土数値情報の取込みを検討）／
自治体によるデータ密度差が大きい（デモ対象自治体は事前に件数確認して選ぶ）。

## 候補B: ghcn_d（NOAA GHCN-D 日別気象・日本観測所）🔶 第3デモ最有力・保留

**結論: ○（実現可能・条件付き）。** 気温（TMAX/TMIN/TAVG）は約140〜155観測所で 1951年〜2026年6月まで
途切れなく取れ、長期気候変動の可視化は十分成立。ただし降水・積雪は直近3〜4ヶ月未反映、
東京観測所が2025-08で停止、都道府県情報なし。**「防災×リアルタイム」ではなく
「長期気候トレンド＋過去イベント分析」に寄せる。**

### 主要テーブル・鮮度

- `ghcnd_1763`〜`ghcnd_2026`（年別・縦持ち: id, date, element, value, qflag…。近年 ~3,700万行/4.2GB/年）、
  `ghcnd_stations`（13.2万所）、`ghcnd_inventory`（要素×期間）。
- 鮮度: ghcnd_2026 の MAX(date)=2026-06-29（日本分は 2026-06-14 まで）。etl は日次更新継続。
  **PRCP/SNWD は2026年3月で停止（気温は速報系、降水は後追い反映）。**

### 日本の観測所・カバレッジ（実測）

- `JA%` 202 所（名前ローマ字、緯度経度・標高あり、**state は全件空**。wmoid=気象庁地点番号が168件）。
- 要素別（現役=2025年以降も活動）: TMAX/TMIN 155所・30年以上167所 / PRCP 147所 / SNWD 103所 /
  **SNOW（日降雪量）は2005年で終了し使えない → 雪は SNWD（積雪深）を使う**。
- 実用的な分析起点は 1951年（年間15〜21万行・150〜175所で安定）。

### 実クエリ検証の要点

- 単位確定: 気温・降水は **1/10単位**（value/10）、SNWD は mm。岐阜2026年6月で TMAX 21.1〜30.1℃と妥当。
- 名古屋 PRCP 歴代1位 = 2011-09-21 135.4mm（台風15号東海直撃）、2位 = 2023-06-03 118.6mm。
  青森 SNWD トップ = 2025年1〜2月の124cm（記録的豪雪）。**実災害と一致し防災ストーリー成立。**
- 品質: 2024年日本分 142,228 行中 qflag 付き2行のみ。`qflag=''` フィルタで十分。
- **東京(JA000047662)は 2025-08-24 で全要素停止**。代表地点は札幌・名古屋・岐阜等（2026年まで継続）を使う。

### curated テーブル設計案（採用時はここから着手）

1. **`jp_weather_daily`（主役・ワイド型）**: date × station で `tmax_c, tmin_c, tavg_c, prcp_mm, snwd_cm` に
   単位変換済みピボット。約440万行・~0.5GB。NL→SQL も Looker も縦持ちより圧倒的に扱いやすい。
2. `jp_ghcn_daily_long`（縦持ち保全用。DATEパーティション + id/element クラスタ）。
3. `jp_stations_dim`: 観測所マスタに **prefecture / region 列を自前付加**（約160所なら手動マッピング現実的。
   wmoid から機械対応付け可、または都道府県ポリゴンと ST_CONTAINS）。→ Looker のドロップダウンで地域切替。
- 構築一回 40〜60GB スキャン。以後は日次スケジュールクエリで ghcnd_2026 のみ MERGE（~2GB/日）。

### 見せ場・質問例

- 1951年からの年平均気温・真夏日/猛暑日日数の長期トレンド（温暖化の可視化）、
  地点別「観測史上の大雨トップ10」×実災害の突合、豪雪地帯の積雪深推移、lat/lon による地図表示。
- 「札幌の1950年代と2010年代で真冬日はどれだけ減った？」「岐阜で日降水量100mm超の日を年代別に数えて」
  「青森の積雪深が過去最大だったのはいつ？」「猛暑日が最も増えた観測所は？」

### リスク

PRCP/SNWD の反映ラグ（「先週の大雨」は見えない）／観測所の廃止・欠測（inventory の lastyear と
実行数の両方で「使える観測所」を絞る前処理が必須）／**アメダス非収録**（市区町村粒度は出ない）／
JMA公表値と丸め・品質処理で微差あり（「気象庁の公式値」として提示しない注記を推奨）。

---
---

# 第2部 旧候補の設計メモ（thelook_ecommerce / austin_bikeshare）

「地域で絞る」への方針転換前に検討していた候補。BQ public データで実スキーマ確認済み。
データ辞書と Looker レイアウト案まで検討は済んでいる。採用する場合は google-trends を雛形に
`demos/<名前>/` を作成する。

## 候補C: thelook_ecommerce（EC売上BI）⬜ 保留

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

## 候補D: austin_bikeshare（人流・移動）⬜ 保留

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
