# データ辞書 — OSM 地域施設マップ（geo_openstreetmap）

## 元データ: `bigquery-public-data.geo_openstreetmap`

OpenStreetMap の全世界データを BigQuery 用に加工した Google 公式の一般公開データセット。
**スナップショットは 2021-11-08 時点で更新停止**（MAX(osm_timestamp) で確認済み）。

### テーブル群（16本・実測サイズ）

| グループ | テーブル | 行数 | サイズ | 中身 |
|---|---|---|---|---|
| **features（分析用・本デモで使用）** | `planet_features` | 9.9億 | 352GB | 全地物（点・線・面）の統合。**施設POI抽出の元** |
| | `planet_features_multipolygons` | 5.6億 | 198GB | 面（行政境界・建物等）。**自治体境界抽出の元** |
| | `planet_features_lines` | 2.5億 | 103GB | 線（道路・鉄道・河川） |
| | `planet_features_points` | 1.8億 | 27GB | 点のみ（施設ピン等） |
| | `planet_features_multilinestrings` | 80万 | 9GB | 複合線（ルート系） |
| | `planet_features_other_relations` | 278万 | 3GB | その他リレーション |
| 生データ | `planet_nodes` / `planet_ways` / `planet_relations` / `planet_layers` / `planet_changesets` | 73億〜5千万 | 47〜582GB | features の材料。デモには不要 |
| 履歴 | `history_*`（5本） | 〜112億 | 〜1.3TB | 全編集履歴。不要 |

### features 系のスキーマ（共通）

| カラム | 型 | 意味 |
|---|---|---|
| feature_type | STRING | points / lines / multipolygons / multilinestrings / other_relations |
| osm_id | INTEGER | OSM ID（点=ノードID、リレーション=リレーションID） |
| osm_way_id | INTEGER | ウェイID（面のとき） |
| osm_version | INTEGER | 編集バージョン |
| osm_timestamp | TIMESTAMP | 最終編集日時（データ全体は2021-11-08まで） |
| all_tags | ARRAY<STRUCT<key,value>> | **OSMタグ（key=value の配列）。種類の判別はすべてこれ** |
| geometry | GEOGRAPHY | 地物のジオメトリ。**このカラムでクラスタリング済み**（bbox で絞ると実処理が激減） |

### 本デモで使う OSM タグ

| タグ | 意味 |
|---|---|
| `amenity=hospital / clinic / school / community_centre / library / fire_station` | 病院 / クリニック / 学校 / 公民館・集会所 / 図書館 / 消防署 |
| `emergency=assembly_point` | 避難場所（**全国354件と極端に疎**なため「避難所マップ」の主役にはしない） |
| `boundary=administrative` + `admin_level=4` | 都道府県境界 |
| `boundary=administrative` + `admin_level=7` | 市区町村境界（東京23区含む。政令市の区は含まない） |
| `name` | 名称（**日本の地物は name 自体が日本語**。name:ja はほぼ欠損だが実害なし） |

---

## curated テーブル: `ci-ss4-develop.demo_osm_facilities`

### jp_admin_boundaries（全国の市区町村境界・1,742行）

| カラム | 型 | 意味 |
|---|---|---|
| osm_id | INTEGER | OSM リレーションID |
| muni_name | STRING | 自治体名（日本語。例: 岐阜市, 白川町, 世田谷区） |
| pref_name | STRING | 都道府県名（admin_level=4 と**面積過半の重なり**で付与。重心判定は川沿い境界で誤除外するため不採用） |
| boundary | GEOGRAPHY | 市区町村境界ポリゴン |

### jp_poi_facilities（全国の主要施設・87,745行）★主役

| カラム | 型 | 意味 |
|---|---|---|
| osm_id / osm_way_id | INTEGER | OSM ID |
| feature_type | STRING | 点（points）か面（multipolygons）か |
| category | STRING | 施設カテゴリ（日本語）: 病院 / クリニック / 学校 / 公民館・集会所 / 図書館 / 消防署 / 避難場所 |
| amenity | STRING | 元の OSM amenity タグ値 |
| is_assembly_point | BOOL | 避難場所タグの有無 |
| name | STRING | 施設名（日本語。数%欠損） |
| muni_name / pref_name | STRING | 所在自治体・都道府県（境界と空間結合で付与） |
| latitude / longitude | FLOAT64 | 緯度経度（面は建物重心） |
| latlng | STRING | "緯度,経度"（Looker Studio の緯度経度型にそのまま使える） |
| osm_timestamp | TIMESTAMP | その地物の最終編集日時 |

カテゴリ別件数（2021-11時点）: 学校 45,188 / 公民館・集会所 15,124 / 病院 10,462 /
クリニック 7,454 / 消防署 5,721 / 図書館 3,442 / 避難場所 354

加工内容: 点と面の両方を拾い面は重心を代表点化。同一自治体×カテゴリ×施設名の点/面重複は
**面（建物）を優先して排除**。クラスタ: `pref_name, muni_name`（自治体フィルタが最速・最安）。

### dash_muni_category（自治体×カテゴリ集計・約7,600行）

| カラム | 型 | 意味 |
|---|---|---|
| pref_name / muni_name | STRING | 都道府県・自治体 |
| category | STRING | 施設カテゴリ |
| facility_count | INTEGER | 施設数（比較・ランキングの主指標） |
| named_count | INTEGER | 施設名あり件数（データ品質の参考） |

---

## データの注意点（デモで説明が必要なもの）

1. **鮮度**: 2021-11-08 のスナップショット。以後の開設・閉鎖・統廃合は反映されない。
   ダッシュボード・エージェントとも「データ時点: 2021-11」を明示している。
2. **登録密度の地域差**: OSMは有志作成のため、自治体によって施設の網羅率に差がある。
   件数比較は「OSMに登録されている施設数」であり実数とは限らない。
3. **学校の内訳**: 小中高の区別タグは不安定なため category は「学校」1本。
   name の部分一致（%小学校% 等）で近似可能。
4. **避難場所タグは疎**: 全国354件。防災文脈は「避難所になり得る施設（学校＋公民館）」で見せる。
5. **政令市は市単位**: admin_level=7 のため横浜市などは市で1つ。東京23区は区単位で入っている。
