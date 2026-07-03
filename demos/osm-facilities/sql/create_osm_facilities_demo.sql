-- =============================================================================
-- bqdemosample — OSM 地域施設マップ デモ環境 作成SQL（全国版）
-- =============================================================================
-- 目的 : bigquery-public-data.geo_openstreetmap から「自治体で絞って地域の
--        主要施設（病院・クリニック・学校・公民館・図書館・消防署）を見る」
--        デモ用 curated テーブルを作成する。
-- 対象 : プロジェクト = ci-ss4-develop / データセット = demo_osm_facilities (US)
-- 範囲 : 全国47都道府県（bbox: lon 122.5〜146.5, lat 24.0〜46.0）。
--        bbox には韓国等も含まれるが、都道府県ポリゴンとの空間結合で日本分のみ残る。
--        ※bbox 外の南鳥島・沖ノ鳥島は対象外（施設なしのため実害なし）。
-- 鮮度 : 元データは 2021-11-08 時点のスナップショット（更新停止）。
--        ダッシュボード・エージェントでは「データ時点: 2021-11」を必ず明示する。
-- コスト: planet_features(352GB) / planet_features_multipolygons(198GB) を参照するが
--        geometry クラスタリングの枝刈りで実処理は大幅に減る（dry_run は満額表示。
--        岐阜県版の実績: 見積184〜344GB → 実処理 約5GB）。構築は一回限り。
-- =============================================================================

-- -----------------------------------------------------------------------------
-- 0. データセット作成（bq CLI で。元データが US のため US 必須）
-- -----------------------------------------------------------------------------
--   bq --location=US mk --dataset \
--     --description "OSM 地域施設マップ デモ用（bqdemosample）" \
--     ci-ss4-develop:demo_osm_facilities

-- -----------------------------------------------------------------------------
-- 1. 自治体境界（全国の市区町村ポリゴン + 都道府県名）
--    admin_level=4（都道府県）と admin_level=7（市区町村）を抽出し、
--    面積の過半が重なる都道府県を市区町村に紐付ける。
--    ※重心判定だと川沿い境界の自治体（例: 笠松町）が漏れることを確認済み。
--    ※都道府県の判定は日本語名の形（〜都/道/府/県）で行い、bbox内の隣国を除外。
-- -----------------------------------------------------------------------------
CREATE OR REPLACE TABLE `ci-ss4-develop.demo_osm_facilities.jp_admin_boundaries`
CLUSTER BY pref_name
OPTIONS(description="日本全国の市区町村境界ポリゴン（都道府県名付き）。OSM の boundary=administrative / admin_level=7 から抽出し、admin_level=4（都道府県）と面積過半の重なりで紐付け。データ時点 2021-11。muni_name / pref_name でのフィルタが地域切替の要。") AS
WITH bbox AS (
  SELECT ST_GEOGFROMTEXT('POLYGON((122.5 24.0, 146.5 24.0, 146.5 46.0, 122.5 46.0, 122.5 24.0))') AS g
),
raw AS (
  SELECT
    f.osm_id,
    (SELECT value FROM UNNEST(f.all_tags) WHERE key = 'name')        AS name,
    (SELECT value FROM UNNEST(f.all_tags) WHERE key = 'admin_level') AS admin_level,
    f.geometry
  FROM `bigquery-public-data.geo_openstreetmap.planet_features_multipolygons` AS f, bbox
  WHERE EXISTS(SELECT 1 FROM UNNEST(f.all_tags) t WHERE t.key = 'boundary' AND t.value = 'administrative')
    AND EXISTS(SELECT 1 FROM UNNEST(f.all_tags) t WHERE t.key = 'admin_level' AND t.value IN ('4', '7'))
    AND ST_INTERSECTS(f.geometry, bbox.g)
),
pref AS (
  -- 日本の都道府県のみ（東京都/北海道/京都府/大阪府/〜県）。bbox内の隣国行政区を除外
  SELECT name AS pref_name, geometry
  FROM raw
  WHERE admin_level = '4'
    AND (name IN ('東京都', '北海道', '京都府', '大阪府') OR ENDS_WITH(name, '県'))
)
SELECT
  r.osm_id,                              -- OSM リレーションID
  r.name        AS muni_name,            -- 自治体名（日本語。例: 岐阜市, 白川町）
  p.pref_name,                           -- 都道府県名（面積過半の重なりで付与）
  r.geometry    AS boundary              -- 市区町村境界ポリゴン（GEOGRAPHY）
FROM raw AS r
JOIN pref AS p
  ON ST_INTERSECTS(r.geometry, p.geometry)
 -- 面積の過半が県域と重なる自治体を採用（重心判定は川沿い境界で誤除外するため不採用）
 AND ST_AREA(ST_INTERSECTION(r.geometry, p.geometry)) > ST_AREA(r.geometry) * 0.5
WHERE r.admin_level = '7';

-- -----------------------------------------------------------------------------
-- 2. 施設POI（全国の主要施設）
--    点（ノード）と面（建物ポリゴン）の両方を planet_features から拾い、
--    面は重心を代表点にする。同一自治体×同一施設名の点/面重複は面を優先して排除。
-- -----------------------------------------------------------------------------
CREATE OR REPLACE TABLE `ci-ss4-develop.demo_osm_facilities.jp_poi_facilities`
CLUSTER BY pref_name, muni_name
OPTIONS(description="日本全国の主要施設POI（1行=1施設）。OSM の amenity タグ（hospital/clinic/school/community_centre/library/fire_station）＋emergency=assembly_point を抽出し、市区町村境界と空間結合して muni_name / pref_name を付与。同一自治体×同一施設名は面（建物）を優先して重複排除。データ時点 2021-11。Looker Studio バブルマップは latlng 列を使用。") AS
WITH bbox AS (
  SELECT ST_GEOGFROMTEXT('POLYGON((122.5 24.0, 146.5 24.0, 146.5 46.0, 122.5 46.0, 122.5 24.0))') AS g
),
poi AS (
  SELECT
    f.osm_id,
    f.osm_way_id,
    f.feature_type,
    f.osm_timestamp,
    (SELECT value FROM UNNEST(f.all_tags) WHERE key = 'name')    AS name,
    (SELECT value FROM UNNEST(f.all_tags) WHERE key = 'amenity') AS amenity,
    EXISTS(SELECT 1 FROM UNNEST(f.all_tags) t
           WHERE t.key = 'emergency' AND t.value = 'assembly_point') AS is_assembly_point,
    ST_CENTROID(f.geometry) AS pt
  FROM `bigquery-public-data.geo_openstreetmap.planet_features` AS f, bbox
  WHERE ST_INTERSECTS(f.geometry, bbox.g)
    AND (
      EXISTS(SELECT 1 FROM UNNEST(f.all_tags) t
             WHERE t.key = 'amenity'
               AND t.value IN ('hospital','clinic','school','community_centre','library','fire_station'))
      OR EXISTS(SELECT 1 FROM UNNEST(f.all_tags) t
                WHERE t.key = 'emergency' AND t.value = 'assembly_point')
    )
),
joined AS (
  SELECT
    p.*,
    b.muni_name,
    b.pref_name
  FROM poi AS p
  JOIN `ci-ss4-develop.demo_osm_facilities.jp_admin_boundaries` AS b
    ON ST_WITHIN(p.pt, b.boundary)   -- 日本の自治体に落ちない地物（隣国分等）はここで除外される
)
SELECT
  osm_id,                                -- OSM ID（点はノードID）
  osm_way_id,                            -- OSM ウェイID（面のとき）
  feature_type,                          -- points / multipolygons 等（点か面か）
  CASE amenity
    WHEN 'hospital'         THEN '病院'
    WHEN 'clinic'           THEN 'クリニック'
    WHEN 'school'           THEN '学校'
    WHEN 'community_centre' THEN '公民館・集会所'
    WHEN 'library'          THEN '図書館'
    WHEN 'fire_station'     THEN '消防署'
    ELSE '避難場所'                       -- amenity なしで emergency=assembly_point のみの地物
  END AS category,                       -- 施設カテゴリ（日本語。分析・色分けの主軸）
  amenity,                               -- 元の OSM amenity タグ値
  is_assembly_point,                     -- 避難場所タグ（emergency=assembly_point）の有無
  name,                                  -- 施設名（日本語。OSM の name タグ。数%欠損）
  muni_name,                             -- 所在自治体名（境界ポリゴンとの空間結合で付与）
  pref_name,                             -- 都道府県名
  ST_Y(pt) AS latitude,                  -- 緯度（面は重心）
  ST_X(pt) AS longitude,                 -- 経度（面は重心）
  CONCAT(CAST(ROUND(ST_Y(pt), 6) AS STRING), ',',
         CAST(ROUND(ST_X(pt), 6) AS STRING)) AS latlng,  -- "緯度,経度"（Looker Geo型に直接使える）
  osm_timestamp                          -- この地物の最終編集日時（元データは2021-11時点）
FROM joined
QUALIFY ROW_NUMBER() OVER (
  PARTITION BY muni_name, category, COALESCE(name, CAST(osm_id AS STRING), CAST(osm_way_id AS STRING))
  ORDER BY CASE feature_type WHEN 'multipolygons' THEN 0 ELSE 1 END
) = 1;

-- -----------------------------------------------------------------------------
-- 3. ダッシュボード用サマリ（自治体 × カテゴリの施設数）
--    Looker Studio の「自治体間比較」「カテゴリ内訳」用の極小テーブル。
-- -----------------------------------------------------------------------------
CREATE OR REPLACE TABLE `ci-ss4-develop.demo_osm_facilities.dash_muni_category`
OPTIONS(description="自治体×カテゴリの施設数サマリ（全国）。Looker Studio の自治体間比較・カテゴリ内訳チャート用。jp_poi_facilities を集計。") AS
SELECT
  pref_name,                             -- 都道府県名
  muni_name,                             -- 自治体名
  category,                              -- 施設カテゴリ
  COUNT(*)                    AS facility_count,   -- 施設数
  COUNTIF(name IS NOT NULL)   AS named_count       -- 施設名あり件数（データ品質の参考）
FROM `ci-ss4-develop.demo_osm_facilities.jp_poi_facilities`
GROUP BY pref_name, muni_name, category;
