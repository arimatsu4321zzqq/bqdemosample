-- =============================================================================
-- bqdemosample — Looker Studio ダッシュボード用 集計テーブル 作成SQL
-- =============================================================================
-- 目的 : Looker Studio から直結する「見るたびのスキャン量が小さい」集計済み
--        物理テーブルを用意する。ビューではなく CREATE TABLE で実体化し、
--        表示時のBQスキャンを数MB以下に抑える（＝実質無料＆高速）。
-- 元データ: ci-ss4-develop.demo_google_trends.jp_top_terms       (人気・約958万行)
--           ci-ss4-develop.demo_google_trends.jp_top_rising_terms(急上昇・約638万行)
-- 更新 : 今回はスケジュール更新なし。データ更新時は本スクリプトを再実行すればよい
--        （CREATE OR REPLACE なので冪等）。
-- =============================================================================

-- -----------------------------------------------------------------------------
-- 1. 週 × ワード（全国集計）: 時系列トレンド・人気ランキング用
--    都道府県を跨いで集計し行数を大幅圧縮（元958万行 → 週×ワードの組合せのみ）。
-- -----------------------------------------------------------------------------
CREATE OR REPLACE TABLE `ci-ss4-develop.demo_google_trends.dash_jp_terms_weekly`
OPTIONS(description="日本の人気検索ワードを週×ワード単位に全国集計したダッシュボード用テーブル。jp_top_terms を都道府県横断で集約。時系列トレンド・人気ランキング表示に使用。") AS
SELECT
  week,                                              -- 対象週（週の開始日。時間軸）
  term,                                              -- 検索ワード（日本語）
  AVG(score)                  AS avg_score,          -- 全国平均スコア（※各語の自分比ピーク=100。語間比較には不向き）
  MAX(score)                  AS max_score,          -- 全国最大スコア（その語の自分比ピーク）
  AVG(rank)                   AS avg_rank,           -- 全国平均順位（★語間比較の主指標。小さいほど人気）
  MIN(rank)                   AS best_rank,          -- 全国最高順位（1が最上位）
  COUNT(DISTINCT region_name) AS region_count        -- ランクインした都道府県数（常に47＝使用非推奨）
FROM `ci-ss4-develop.demo_google_trends.jp_top_terms`
WHERE score IS NOT NULL   -- ★現在語を過去週へ複製したNULLスコアのゴミ行(全体の81.5%)を除外。これが本物の週次データ
GROUP BY week, term;

-- -----------------------------------------------------------------------------
-- 2. 都道府県 × ワード（最新週スナップショット）: 日本地図・地域比較用
--    全国の最新週のみを抽出。地図は region_name を地域型にして AVG(score) を塗り分け。
-- -----------------------------------------------------------------------------
CREATE OR REPLACE TABLE `ci-ss4-develop.demo_google_trends.dash_jp_region_latest`
OPTIONS(description="日本の人気検索ワードの最新週スナップショット（都道府県×ワード）。日本地図の塗り分け・都道府県間の比較ランキングに使用。") AS
WITH latest AS (
  SELECT MAX(week) AS max_week
  FROM `ci-ss4-develop.demo_google_trends.jp_top_terms`
  WHERE score IS NOT NULL   -- ★複製ゴミを除いた本物の最新週
),
geo AS (  -- 都道府県の代表座標（県庁所在地相当）。塗り分けが不安定な環境向けのバブルマップ用フォールバック
  SELECT * FROM UNNEST([
    STRUCT('JP-01' AS region_code, 43.06 AS lat, 141.35 AS lng),
    ('JP-02',40.82,140.74),('JP-03',39.70,141.15),('JP-04',38.27,140.87),('JP-05',39.72,140.10),
    ('JP-06',38.24,140.36),('JP-07',37.75,140.47),('JP-08',36.34,140.45),('JP-09',36.57,139.88),
    ('JP-10',36.39,139.06),('JP-11',35.86,139.65),('JP-12',35.61,140.12),('JP-13',35.69,139.69),
    ('JP-14',35.45,139.64),('JP-15',37.90,139.02),('JP-16',36.70,137.21),('JP-17',36.59,136.63),
    ('JP-18',36.07,136.22),('JP-19',35.66,138.57),('JP-20',36.65,138.18),('JP-21',35.39,136.72),
    ('JP-22',34.98,138.38),('JP-23',35.18,136.91),('JP-24',34.73,136.51),('JP-25',35.00,135.87),
    ('JP-26',35.02,135.76),('JP-27',34.69,135.52),('JP-28',34.69,135.18),('JP-29',34.69,135.83),
    ('JP-30',34.23,135.17),('JP-31',35.50,134.24),('JP-32',35.47,133.05),('JP-33',34.66,133.93),
    ('JP-34',34.40,132.46),('JP-35',34.19,131.47),('JP-36',34.07,134.56),('JP-37',34.34,134.04),
    ('JP-38',33.84,132.77),('JP-39',33.56,133.53),('JP-40',33.61,130.42),('JP-41',33.25,130.30),
    ('JP-42',32.74,129.87),('JP-43',32.79,130.74),('JP-44',33.24,131.61),('JP-45',31.91,131.42),
    ('JP-46',31.56,130.56),('JP-47',26.21,127.68)
  ])
)
SELECT
  t.region_name,   -- 都道府県名（英語表記。Looker Studioで地域型にしジオコーディング）
  t.region_code,   -- 地域コード（ISO 3166-2 相当。例: JP-13=東京）
  t.week,          -- 対象週（=全国最新週）
  t.term,          -- 検索ワード
  t.rank,          -- 都道府県内順位（1が最上位）
  t.score,         -- 人気スコア（0〜100）
  g.lat AS latitude,   -- 都道府県代表緯度（バブルマップ用フォールバック）
  g.lng AS longitude,  -- 都道府県代表経度（バブルマップ用フォールバック）
  CONCAT(CAST(g.lat AS STRING), ',', CAST(g.lng AS STRING)) AS latlng  -- "緯度,経度" 形式（Looker Geo緯度経度型に直接使える）
FROM `ci-ss4-develop.demo_google_trends.jp_top_terms` AS t
CROSS JOIN latest
LEFT JOIN geo AS g ON g.region_code = t.region_code
WHERE t.week = latest.max_week
  AND t.score IS NOT NULL;   -- ★複製ゴミ除外

-- -----------------------------------------------------------------------------
-- 3. 都道府県 × 週 × ワード（急上昇・直近52週・rank<=10）: 急上昇ウォッチ用
--    急上昇はバズ検知が主目的なので直近1年・上位10位に絞りサイズを抑える。
-- -----------------------------------------------------------------------------
CREATE OR REPLACE TABLE `ci-ss4-develop.demo_google_trends.dash_jp_rising_recent`
OPTIONS(description="日本の急上昇検索ワード（都道府県×週×ワード、直近52週・rank<=10）。percent_gain(上昇率)を主指標にしたバズ検知・急上昇ランキングに使用。") AS
WITH bounds AS (
  SELECT DATE_SUB(MAX(week), INTERVAL 52 WEEK) AS from_week
  FROM `ci-ss4-develop.demo_google_trends.jp_top_rising_terms`
  WHERE percent_gain IS NOT NULL   -- ★複製ゴミ除外
)
SELECT
  r.region_name,    -- 都道府県名（英語表記）
  r.region_code,    -- 地域コード
  r.week,           -- 対象週
  r.term,           -- 急上昇した検索ワード
  r.rank,           -- 急上昇順位（1が最上位）
  r.score,          -- 人気スコア（欠損の場合あり）
  r.percent_gain    -- 上昇率(%)。話題性・バズの強さの主指標
FROM `ci-ss4-develop.demo_google_trends.jp_top_rising_terms` AS r
CROSS JOIN bounds
WHERE r.week >= bounds.from_week
  AND r.rank <= 10;

-- -----------------------------------------------------------------------------
-- 4. 週 × ワード（急上昇・全国集計・直近52週）: 急上昇ウォッチ(P4)用【推奨】
--    注意: 元データは JP の急上昇 percent_gain が47都道府県すべて同値（＝全国一律）。
--    そのため県次元は無意味。県次元を廃し週×ワードで全国集計したものが正しい見せ方。
--    dash_jp_rising_recent（県×週×ワード）は残すが、P4はこの全国版を使うこと。
-- -----------------------------------------------------------------------------
CREATE OR REPLACE TABLE `ci-ss4-develop.demo_google_trends.dash_jp_rising_weekly`
OPTIONS(description="日本の急上昇検索ワード（週×ワード・全国）。元データは47都道府県で percent_gain が同値のため県次元を廃し、直近52週で全国集計。P4急上昇ウォッチ用の正しいデータソース。") AS
WITH ded AS (
  SELECT week, term, rank, score, percent_gain
  FROM `bigquery-public-data.google_trends.international_top_rising_terms`
  WHERE country_code = "JP"
    AND percent_gain IS NOT NULL   -- ★複製ゴミ除外
  QUALIFY ROW_NUMBER() OVER (PARTITION BY region_name, week, term ORDER BY refresh_date DESC) = 1
),
bounds AS (
  SELECT DATE_SUB(MAX(week), INTERVAL 52 WEEK) AS from_week FROM ded
)
SELECT
  week,                             -- 対象週
  term,                             -- 急上昇した検索ワード
  MAX(percent_gain) AS percent_gain,-- 上昇率(%)。全国一律値
  AVG(score)        AS avg_score,   -- 人気スコア平均（欠損あり）
  MIN(rank)         AS best_rank    -- 全国最高の急上昇順位
FROM ded, bounds
WHERE week >= bounds.from_week
GROUP BY week, term;
