# 成果物仕様書：地域施設マップ デモ（osm-facilities）

> **納品パッケージの一部（テーブル定義・データ定義・エージェント定義）。**
> BigQuery 公開データ（OpenStreetMap）を使い「自治体で絞って地域の施設を見る／聞く」を再現した汎用デモの技術仕様。
> この1冊で、データの出どころ・加工・テーブル・AIエージェントまで把握できる（ダッシュボードは公開URL＋別途PDFで提供）。
> 出典は本デモリポジトリ `bqdemosample/demos/osm-facilities/`。数値は 2026-07 に実データで裏取り済み。

---

## 0. デモの概要

**「病院・学校・公民館などの主要施設を、自治体を選ぶだけで地図・比較・一覧で見られ、しかも日本語で聞いて分析できる」** 地域データ活用のサンプル。

- 構成は **BigQuery（データ基盤）× AI会話型分析（Conversational Analytics）× Looker Studio（ダッシュボード）** の3点セット。
- 題材は OpenStreetMap 由来の全国 **約8.8万施設**。顧客データに依存しない**汎用デモケース**なので、どの自治体・業種にも「同じ形でできます」と提示できる。
- 対になる時系列デモ（検索トレンド）とは違い、こちらは **分布・比較型**（地図・ランキング）。

| 項目 | 値 |
|---|---|
| GCP プロジェクト | `ci-ss4-develop`（課金有効・BQ 利用可能プラン） |
| 元データ | `bigquery-public-data.geo_openstreetmap`（US マルチリージョン・**2021-11-08 スナップショット**） |
| curated データセット | `ci-ss4-develop.demo_osm_facilities`（US） |
| テーブル | `jp_poi_facilities`（施設8.8万件）／ `jp_admin_boundaries`（1,742市区町村境界）／ `dash_muni_category`（自治体×カテゴリ集計） |
| データエージェント | `jp_facilities_demo`（location: `global`） |
| ステータス | **BQ・エージェント構築済み（動作検証済み）** ／ ダッシュボードは別途（URL＋PDF） |

---

## 1. データソース（元データ）

### `bigquery-public-data.geo_openstreetmap`

OpenStreetMap（有志が作る世界地図）の全世界データを BigQuery 用に加工した **Google 公式の一般公開データセット**。

- スナップショットは **2021-11-08 時点で更新停止**（`MAX(osm_timestamp)` で確認済み）。以後の開設・閉鎖・統廃合は反映されない。
- OSM には「病院テーブル」のような**種類別テーブルは存在しない**。全地物が `all_tags`（`key=value` の配列）で種類を表し、**何を抽出するかはタグの選び方で決まる**。

### テーブル群（16本）と本デモでの使用

| グループ | テーブル | サイズ | 本デモ |
|---|---|---|---|
| features（分析用） | `planet_features`（全地物統合） | 352GB | **施設POI の抽出元** |
| | `planet_features_multipolygons`（面） | 198GB | **行政境界の抽出元** |
| | `planet_features_lines`（線：道路・鉄道・河川） | 103GB | 使わない |
| | `planet_features_points`（点のみ） | 27GB | 使わない（features に含まれる） |
| | `planet_features_multilinestrings` / `_other_relations` | 9 / 3GB | 使わない |
| 生データ | `planet_nodes` / `planet_ways` / `planet_relations` / `planet_layers` / `planet_changesets` | 47〜582GB | 使わない（features の材料） |
| 編集履歴 | `history_*`（5本） | 〜1.3TB | 使わない |

→ **使うのは features 系 2本だけ**（残り14本はデモには不要）。

### features 系の共通スキーマ

| カラム | 型 | 意味 |
|---|---|---|
| feature_type | STRING | points / lines / multipolygons / multilinestrings / other_relations |
| osm_id | INTEGER | OSM ID（点=ノードID、リレーション=リレーションID） |
| osm_way_id | INTEGER | ウェイID（面のとき） |
| osm_version | INTEGER | 編集バージョン |
| osm_timestamp | TIMESTAMP | 最終編集日時（データ全体は 2021-11-08 まで） |
| all_tags | ARRAY&lt;STRUCT&lt;key, value&gt;&gt; | **OSM タグ（key=value の配列）。種類の判別はすべてこれ** |
| geometry | GEOGRAPHY | 地物のジオメトリ。**このカラムでクラスタリング済み**（bbox で絞ると実処理が激減） |

### 本デモで使う OSM タグ

| タグ | 意味 |
|---|---|
| `amenity=hospital / clinic / school / community_centre / library / fire_station` | 病院 / クリニック / 学校 / 公民館・集会所 / 図書館 / 消防署 |
| `emergency=assembly_point` | 避難場所（**全国354件と極端に疎**なため主役にはしない） |
| `boundary=administrative` + `admin_level=4` | 都道府県境界 |
| `boundary=administrative` + `admin_level=7` | 市区町村境界（東京23区含む。政令市の区＝level 8 は対象外） |
| `name` | 名称（**日本の地物は name 自体が日本語**。name:ja はほぼ欠損だが実害なし） |

---

## 2. データフロー（何を抽出し、どう加工したか）

```
【BQ公式】bigquery-public-data.geo_openstreetmap（全16テーブル・2021-11時点）
│  使うのは features 系 2本だけ
│
├─ planet_features_multipolygons（198GB：面＝行政境界・建物）
│      抽出: boundary=administrative + 日本周辺bbox
│        ├ admin_level=4 → 都道府県ポリゴン（名前が 都/道/府/県 で終わる＝日本のみ）
│        └ admin_level=7 → 市区町村ポリゴン
│      加工: 市区町村を「面積の過半が重なる都道府県」に紐付け（pref_name 付与）
│      ▼
│  ① jp_admin_boundaries（1,742市区町村・境界ポリゴン）──┐
│                                                        │
└─ planet_features（352GB：点・線・面すべて）             │
       抽出: 日本周辺bbox + amenity 6種 + emergency=assembly_point
       加工: ・面（建物）は重心を代表点にして緯度経度化
             ・①と空間結合（ST_WITHIN）→ 所在自治体・県名を付与 ◄┘
               ※bbox内の隣国分はここで自動的に落ちる
             ・点と面の二重登録は 面 を優先して重複排除
             ・amenity を日本語カテゴリに変換（hospital→病院 等）
             ・Looker用の "緯度,経度" 文字列列（latlng）を生成
       ▼
   ② jp_poi_facilities（87,745施設・主テーブル）
       集計: 自治体 × カテゴリで COUNT
       ▼
   ③ dash_muni_category（約7,600行）
```

作成先はすべて `ci-ss4-develop.demo_osm_facilities`（US）。

### 抽出条件（タグと範囲）

| 対象 | 条件 |
|---|---|
| 都道府県境界 | `boundary=administrative` + `admin_level=4`、名前が 東京都/北海道/京都府/大阪府/〜県 |
| 市区町村境界 | `boundary=administrative` + `admin_level=7`（東京23区含む。政令市の区＝level 8 は対象外） |
| 施設POI | `amenity` ∈ {hospital, clinic, school, community_centre, library, fire_station}、補助的に `emergency=assembly_point` |
| 空間範囲 | 日本周辺 bbox（lon 122.5〜146.5, lat 24.0〜46.0）。bbox 内の隣国分は自治体境界との空間結合で除外 |

---

## 3. テーブル定義（curated 3テーブル）

作成SQL の実体は `demos/osm-facilities/sql/create_osm_facilities_demo.sql`（`CREATE OR REPLACE TABLE` で境界→施設→集計の順に3本）。

### ① `jp_admin_boundaries` — 市区町村境界（1,742行）

`CLUSTER BY pref_name`。中間マスタ（②を作るための空間結合先。地図の塗り分けにも転用可）。

| カラム | 型 | 意味 |
|---|---|---|
| osm_id | INTEGER | OSM リレーションID |
| muni_name | STRING | 自治体名（日本語。例: 岐阜市, 白川町, 世田谷区） |
| pref_name | STRING | 都道府県名（admin_level=4 と**面積過半の重なり**で付与。重心判定は川沿い境界で誤除外するため不採用） |
| boundary | GEOGRAPHY | 市区町村境界ポリゴン |

### ② `jp_poi_facilities` — 主要施設POI（87,745行・主テーブル）

`CLUSTER BY pref_name, muni_name`（自治体フィルタが最速・最安）。地図・明細、エージェントの明細回答に使う。

| カラム | 型 | 意味 |
|---|---|---|
| osm_id / osm_way_id | INTEGER | OSM ID |
| feature_type | STRING | 点（points）か面（multipolygons）か |
| category | STRING | 施設カテゴリ（日本語）: 病院 / クリニック / 学校 / 公民館・集会所 / 図書館 / 消防署 / 避難場所 |
| amenity | STRING | 元の OSM amenity タグ値 |
| is_assembly_point | BOOL | 避難場所タグ（emergency=assembly_point）の有無 |
| name | STRING | 施設名（日本語。数%欠損） |
| muni_name / pref_name | STRING | 所在自治体・都道府県（境界と空間結合で付与） |
| latitude / longitude | FLOAT64 | 緯度経度（面は建物重心） |
| latlng | STRING | "緯度,経度"（Looker Studio の緯度経度型にそのまま使える） |
| osm_timestamp | TIMESTAMP | その地物の最終編集日時 |

**加工の要点**：点と面の両方を拾い、面は重心を代表点化。同一自治体×カテゴリ×施設名の点/面重複は**面（建物）を優先して排除**。

### ③ `dash_muni_category` — 自治体×カテゴリ集計（約7,600行）

②を `GROUP BY pref_name, muni_name, category` で集計した極小テーブル。比較・ランキングの主データ。

| カラム | 型 | 意味 |
|---|---|---|
| pref_name / muni_name | STRING | 都道府県・自治体 |
| category | STRING | 施設カテゴリ |
| facility_count | INTEGER | 施設数（比較・ランキングの主指標） |
| named_count | INTEGER | 施設名あり件数（データ品質の参考） |

### カテゴリ別件数（②の内訳・2021-11時点）

| カテゴリ | 件数 |
|---|---|
| 学校 | 45,188 |
| 公民館・集会所 | 15,124 |
| 病院 | 10,462 |
| クリニック | 7,454 |
| 消防署 | 5,721 |
| 図書館 | 3,442 |
| 避難場所 | 354 |
| **合計** | **87,745** |

（都道府県 47・POI に出現する自治体 約1,684）

---

## 4. データエージェント定義（`jp_facilities_demo`）

Conversational Analytics（Gemini Data Analytics）。SQL やテーブル名を知らなくても日本語で聞ける。

| 項目 | 値 |
|---|---|
| API | `geminidataanalytics.googleapis.com` |
| ロケーション | `global` |
| リソース名 | `projects/ci-ss4-develop/locations/global/dataAgents/jp_facilities_demo` |
| 参照データソース | `jp_poi_facilities`（施設明細）／ `dash_muni_category`（自治体×カテゴリ集計） |
| 定義ファイル | `agent/jp_facilities_agent.json`（`agent/build_payload.py` で生成） |
| ラベル | `app=bqdemosample / theme=osm-facilities / country=jp / env=demo` |

> **参照テーブルは2本に限定**（境界テーブル `jp_admin_boundaries` は渡さない）。参照データを絞ることが、予期せぬ高額クエリ（クロス結合等）の防止と回答の安定に直結する。

### システムインストラクション（ペルソナ＋ルール）

「地域の公共施設・医療施設を分析するデータアナリスト」。表・グラフを積極利用し日本語で簡潔に回答。主要ルール：

1. データは全国47都道府県・約1,700市区町村・約8.8万施設。**2021年11月時点**である旨を件数回答時に添える。
2. 都道府県で絞るときは `pref_name`、市区町村で絞るときは `muni_name`。
3. 施設種類は `category`（7値：病院 / クリニック / 学校 / 公民館・集会所 / 図書館 / 消防署 / 避難場所）。
4. **「避難所になり得る施設」＝ `category IN ('学校','公民館・集会所')`**（避難場所タグは全国354件と少数のため）。
5. 件数比較・ランキングは集計済みの `dash_muni_category` を優先。
6. 個別施設の一覧・地図は `jp_poi_facilities` を使い name・緯度経度を返す。
7. 小中高は区別できない（すべて `category='学校'`）。求められたら `name` 部分一致（例 `LIKE '%小学校%'`）で**近似する旨を断って**回答。
8. 政令市は市単位（東京23区のみ区単位）。
9. OSM は登録密度に地域差があり、件数が実際より少なく見える場合がある旨を必要に応じて注記。

### 用語集（glossary）

| 用語 | 定義 |
|---|---|
| 避難所になり得る施設（避難所候補／避難施設） | 学校と公民館・集会所。`category IN ('学校','公民館・集会所')` |
| 医療機関（医療施設／病院・診療所） | 病院とクリニック。`category IN ('病院','クリニック')` |
| データ時点 | OpenStreetMap の 2021-11-08 スナップショット（以後の開閉は未反映） |
| 公民館 | `category = '公民館・集会所'`（集会所・コミュニティセンターを含む） |

### 検証済み golden query（8本・BigQuery で実行確認済み）

エージェント定義に例示クエリとして埋め込み。NL→SQL の精度を担保する要。

| 自然文 | 生成SQL の要点 |
|---|---|
| 岐阜市の病院を一覧で見せて | `jp_poi_facilities` WHERE muni_name AND category='病院' AND name IS NOT NULL |
| 高山市と飛騨市で学校の数を比べて | `dash_muni_category` WHERE muni_name IN(...) AND category='学校' |
| 東京都で公民館・集会所が多い自治体Top10 | `dash_muni_category` WHERE pref_name AND category ORDER BY facility_count LIMIT 10 |
| 白川町にはどんな施設がある？カテゴリ別に | `dash_muni_category` WHERE muni/pref ORDER BY facility_count |
| 岐阜県で図書館がない自治体はどこ？ | `jp_poi_facilities` の NOT IN サブクエリ（欠落抽出） |
| 避難所になり得る施設が多い自治体Top10（全国） | `dash_muni_category` WHERE category IN('学校','公民館・集会所') GROUP BY muni SUM |
| 都道府県別の病院数ランキングTop10 | `dash_muni_category` WHERE category='病院' GROUP BY pref SUM |
| 郡上市の小学校を一覧で | `jp_poi_facilities` WHERE category='学校' AND name LIKE '%小学校%' |

---

## 5. ダッシュボード（Looker Studio）

施設マップのダッシュボード本体は、この仕様書とは**別に提供**する。

- **限定公開URL**：https://datastudio.google.com/reporting/3e8bbacd-785f-466e-b9f3-806fc4b9dbed
- **画面・レイアウト詳細**：別途PDF [`dashboard.pdf`](./dashboard.pdf)（本フォルダ同梱）

データソースは `jp_poi_facilities`（地図・明細）と `dash_muni_category`（比較）の直結で足りる（8.8万行・十数MBのため Extract 不要）。

---

## 6. 制約（正直に伝えること）

1. **鮮度**：2021-11-08 スナップショット。以後の開設・閉鎖・統廃合は未反映。ダッシュボード・エージェントとも「データ時点: 2021-11」を明示。
2. **登録密度の地域差**：OSM は有志作成のため自治体により網羅率に差。件数は「OSM に登録されている数」で実数とは限らない。
3. **学校の内訳**：小中高の区別タグは不安定なため `category` は「学校」1本。`name` 部分一致で近似。
4. **避難場所タグは疎**：全国354件。防災文脈は「避難所になり得る施設（学校＋公民館）」で見せる。
5. **政令市は市単位**：admin_level=7 のため横浜市などは市で1つ。東京23区は区単位で存在。
6. 時系列なし（推移グラフは作れない）。トレンドは検索トレンドデモが担当。

---

## 7. コストと構築

- **課金は BigQuery のみ**（Looker Studio・AIエージェントはそれ自体無料）。
- 構築は**一回限り**。dry_run は クラスタ枝刈り未反映で満額表示されるが、bbox 付きで実処理は激減：
  - 境界：見積184GB → 実処理16.4GB／POI：見積344GB → 実処理17.1GB（2026-07 実測）。
  - **構築一回の実処理 合計 約35GB ≒ $0.25 以下**。作り直しても安い。
- 運用時：`jp_poi_facilities` は 8.8万行・十数MB のため Looker 直結で問題なし（Extract 不要）。
- 構築手順の全体は `demos/osm-facilities/setup.md`（認証 → API有効化 → データセット → SQL3本 → エージェント → 片付け）。

---

## 8. 成果物ファイル一覧（`demos/osm-facilities/`）

| ファイル | 役割 |
|---|---|
| `setup.md` | ゼロから手動再現する全手順（コスト実測値付き） |
| `sql/create_osm_facilities_demo.sql` | curated テーブル3本の作成SQL（DDL） |
| `agent/jp_facilities_agent.json` | エージェント定義（systemInstruction・用語集・golden query 8本） |
| `agent/build_payload.py` | 上記 JSON の生成スクリプト |
| `agent/README.md` | エージェント作成/更新/質問（REST API）コマンド集 |
| `data-flow.md` | データフロー全体図（抽出・加工の設計判断） |
| `data-dictionary.md` | 元データ・curated テーブルのスキーマ辞書 |
