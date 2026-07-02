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
  AVG(score)                  AS avg_score,          -- 全国平均スコア（0〜100の相対値の平均）
  MAX(score)                  AS max_score,          -- 全国最大スコア（最も強く出た都道府県の値）
  MIN(rank)                   AS best_rank,          -- 全国最高順位（1が最上位）
  COUNT(DISTINCT region_name) AS region_count        -- ランクインした都道府県数（＝浸透度）
FROM `ci-ss4-develop.demo_google_trends.jp_top_terms`
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
)
SELECT
  t.region_name,   -- 都道府県名（英語表記。Looker Studioで地域型にしジオコーディング）
  t.region_code,   -- 地域コード（ISO 3166-2 相当。例: JP-13=東京）
  t.week,          -- 対象週（=全国最新週）
  t.term,          -- 検索ワード
  t.rank,          -- 都道府県内順位（1が最上位）
  t.score          -- 人気スコア（0〜100）
FROM `ci-ss4-develop.demo_google_trends.jp_top_terms` AS t
CROSS JOIN latest
WHERE t.week = latest.max_week;

-- -----------------------------------------------------------------------------
-- 3. 都道府県 × 週 × ワード（急上昇・直近52週・rank<=10）: 急上昇ウォッチ用
--    急上昇はバズ検知が主目的なので直近1年・上位10位に絞りサイズを抑える。
-- -----------------------------------------------------------------------------
CREATE OR REPLACE TABLE `ci-ss4-develop.demo_google_trends.dash_jp_rising_recent`
OPTIONS(description="日本の急上昇検索ワード（都道府県×週×ワード、直近52週・rank<=10）。percent_gain(上昇率)を主指標にしたバズ検知・急上昇ランキングに使用。") AS
WITH bounds AS (
  SELECT DATE_SUB(MAX(week), INTERVAL 52 WEEK) AS from_week
  FROM `ci-ss4-develop.demo_google_trends.jp_top_rising_terms`
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
