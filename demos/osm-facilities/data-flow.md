# データフロー — BQ公式データセットから何を抽出し、どう加工したか

デモ②（地域施設マップ）のデータの出どころと加工の全体像。
カラム単位の詳細スキーマは [`data-dictionary.md`](./data-dictionary.md)、作成SQLの実体は
[`sql/create_osm_facilities_demo.sql`](./sql/create_osm_facilities_demo.sql) を参照。

---

## 全体図

```
【BQ公式データセット】bigquery-public-data.geo_openstreetmap（全16テーブル・2021-11時点）
│
│  使うのは features 系 2本だけ（残り14本はデモには不要）
│
├─ planet_features_multipolygons（5.6億行 / 198GB: 面＝行政境界・建物など）
│      │ 抽出: boundary=administrative タグ + 日本周辺bbox
│      │       ├ admin_level=4 → 都道府県ポリゴン（名前が 都/道/府/県 で終わるもの＝日本のみ）
│      │       └ admin_level=7 → 市区町村ポリゴン
│      │ 加工: 市区町村を「面積の過半が重なる都道府県」に紐付け（pref_name 付与）
│      ▼
│  ① jp_admin_boundaries（1,742市区町村・境界ポリゴン）─────────┐
│                                                                │
└─ planet_features（9.9億行 / 352GB: 点・線・面すべての地物）      │
       │ 抽出: 日本周辺bbox + amenity タグ 6種                     │
       │       (hospital / clinic / school / community_centre /   │
       │        library / fire_station) + emergency=assembly_point│
       │ 加工: ・面（建物）は重心を代表点にして緯度経度化           │
       │       ・①と空間結合（ST_WITHIN）→ 所在自治体・県名を付与 ◄┘
       │         ※bbox内の隣国分はここで自動的に落ちる
       │       ・点と面の二重登録は 面 を優先して重複排除
       │       ・amenity を日本語カテゴリに変換（hospital→病院 等）
       │       ・Looker用の "緯度,経度" 文字列列（latlng）を生成
       ▼
   ② jp_poi_facilities（87,745施設）★ダッシュボード・エージェントの主役
       │
       │ 集計: 自治体 × カテゴリで件数を GROUP BY
       ▼
   ③ dash_muni_category（約7,600行）
```

作成先はすべて `ci-ss4-develop.demo_osm_facilities`（US）。

---

## 1. 元データ: 公式データセットにあるテーブル（16本）

| グループ | テーブル | サイズ | 今回 |
|---|---|---|---|
| features（分析用） | `planet_features`（全地物統合） | 352GB | **✅ 施設POIの抽出元** |
| | `planet_features_multipolygons`（面） | 198GB | **✅ 行政境界の抽出元** |
| | `planet_features_lines`（線: 道路・川） | 103GB | 使わない |
| | `planet_features_points`（点のみ） | 27GB | 使わない（features に含まれるため） |
| | `planet_features_multilinestrings` / `_other_relations` | 9 / 3GB | 使わない |
| 生データ | `planet_nodes` / `planet_ways` / `planet_relations` / `planet_layers` / `planet_changesets` | 47〜582GB | 使わない（features の材料） |
| 編集履歴 | `history_*`（5本） | 〜1.3TB | 使わない |

- OSMには「病院テーブル」のような種類別テーブルは無く、全地物が `all_tags`（key=value の配列）で
  種類を表す。**何を抽出するかはタグの選び方で決まる**。
- features 系は geometry（位置）でクラスタリングされており、bbox で絞ると
  実処理が激減する（dry_run 見積344GB → 実処理17GB を実測）。
- スナップショットは **2021-11-08 で更新停止**。

## 2. 抽出したもの（タグと範囲）

| 対象 | 抽出条件 |
|---|---|
| 都道府県境界 | `boundary=administrative` + `admin_level=4`、名前が 東京都/北海道/京都府/大阪府/〜県 |
| 市区町村境界 | `boundary=administrative` + `admin_level=7`（東京23区含む。政令市の区=level 8 は対象外） |
| 施設POI | `amenity` ∈ {hospital, clinic, school, community_centre, library, fire_station}、補助的に `emergency=assembly_point`（避難場所） |
| 空間範囲 | 日本周辺bbox（lon 122.5〜146.5, lat 24.0〜46.0）。bbox内の隣国分は自治体境界との空間結合で除外 |

## 3. 作ったテーブル（3本）と加工内容

| # | テーブル | 行数 | 加工・集計 | ダッシュボードでの用途 |
|---|---|---|---|---|
| ① | `jp_admin_boundaries` | 1,742 | 市区町村ポリゴンに、**面積の過半が重なる**都道府県名を付与（重心判定は川沿い境界の自治体が漏れるため不採用） | 直接は使わない（②を作るための中間マスタ。地図の塗り分けに転用可） |
| ② | `jp_poi_facilities` | 87,745 | 面→重心の代表点化 / ①との空間結合で muni_name・pref_name 付与 / 点・面の重複排除（面優先）/ カテゴリ日本語化 / `latlng` 列生成。クラスタ: pref_name, muni_name | **P1 施設マップ**（バブルマップ・KPI・施設一覧）、**P3 施設リスト**、エージェントの明細回答 |
| ③ | `dash_muni_category` | 約7,600 | ②を自治体×カテゴリで COUNT 集計 | **P2 自治体比較**（ランキング・ピボット）、エージェントの比較回答 |

カテゴリ別の中身（②の内訳）: 学校 45,188 / 公民館・集会所 15,124 / 病院 10,462 /
クリニック 7,454 / 消防署 5,721 / 図書館 3,442 / 避難場所 354。

## 4. なぜこの形にしたか（設計判断のメモ）

- **巨大な元データに Looker を直結しない**: 352GBのテーブルに毎回クエリすると遅く高い。
  一回の構築（実測 合計約35GB ≒ $0.25以下）で 8.8万行の小テーブルに落とし、以後のスキャンを実質ゼロにする。
- **自治体名を列に持たせる**: 空間結合を構築時に済ませておくことで、ダッシュボードもエージェントも
  `WHERE muni_name = '岐阜市'` の1条件で地域切替できる（クラスタリングとも一致）。
- **集計テーブル（③）を分ける**: 比較・ランキングは集計済みを参照させると、
  エージェントの NL→SQL が単純になり事故が減る（google-trends デモの dash_* と同じ方針）。
- **避難場所タグは補助扱い**: 全国354件しか無いため主役にせず、「避難所になり得る施設＝学校＋公民館」
  という見せ方をエージェントの用語集とダッシュボード設計の両方に織り込んだ。
