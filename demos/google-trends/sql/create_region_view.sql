-- =============================================================================
-- bqdemosample — Google Trends 地域ビュー（新設計・単一テーブル）
-- =============================================================================
-- 目的 : Looker Studio の「地域ビュー」1画面を、たった1テーブルで賄う。
--        既存の集計テーブル(dash_* / jp_top_*)は使わない。元データから作り直す。
-- 元データ: bigquery-public-data.google_trends.international_top_terms（JP分）
-- 出力 : ci-ss4-develop.demo_google_trends.jp_region_weekly
--
-- 設計方針（実データ検証済みの結論に基づく）:
--   1. refresh_date の重複再掲は (region,week,term) 単位で最新を採用して排除。
--   2. score が NULL の行（現在語を過去週へ複製したゴミ＝全体の約81.5%）を除外。
--      → 残った約178万行が「本物の週次観測」。
--   3. score は各(県×語)を自分のピーク=100に正規化した相対値。語間比較は不可。
--      時系列（③）と定番判定にのみ使い、絶対量としては扱わない。
--   4. rank は (県×語) で週をまたいで98.2%が一定＝過去週には最新順位が焼き付いている。
--      → 履歴の rank は信用しない。rank は「最新週」だけ有効な latest_rank として持つ
--        （最新週では順位が現行で正当）。それ以外の週は NULL にして誤用を物理的に防ぐ。
--
-- このテーブル1本で:
--   ① KPI      : COUNT_DISTINCT(term) / COUNT_DISTINCT(week) / MAX(week)
--   ② 左 定番  : term × COUNT_DISTINCT(week)（＝出現週数）降順。rank不使用。
--   ② 右 今週  : WHERE is_latest_week=true, term × latest_rank 昇順（同点あり）。
--   ③ 時系列  : X=week, 指標=score（選択語）。rank不使用。
--   県ドロップダウン : region_name（単一データソースなので全チャートに一括で効く）
-- =============================================================================

CREATE OR REPLACE TABLE `ci-ss4-develop.demo_google_trends.jp_region_weekly`
OPTIONS(description="日本(JP)の週次・人気検索ワード（都道府県×週×ワード）。international_top_terms のJP分を、(region,week,term)単位で最新refresh_dateを採用して重複排除し、複製NULLスコア(約81.5%)を除いた本物の観測のみ。is_latest_week=最新週フラグ、latest_rank=最新週のみ有効な順位(履歴はNULL)。Looker Studioの地域ビュー1画面をこの1本で賄う。") AS
WITH dedup AS (
  SELECT region_name, region_code, week, term, score, rank,
         ROW_NUMBER() OVER (PARTITION BY region_name, week, term
                            ORDER BY refresh_date DESC) AS rn
  FROM `bigquery-public-data.google_trends.international_top_terms`
  WHERE country_code = "JP"
),
base AS (
  SELECT region_name, region_code, week, term, score, rank
  FROM dedup
  WHERE rn = 1              -- refresh_date重複を最新で排除
    AND score IS NOT NULL   -- 複製ゴミ(約81.5%)を除外＝本物の週次観測のみ
),
mx AS ( SELECT MAX(week) AS max_week FROM base )
SELECT
  b.region_name,                                   -- 都道府県名（英語表記。Looker地域型/ドロップダウン用）
  b.region_code,                                   -- 地域コード（ISO 3166-2 相当。例 JP-27=大阪。地図用）
  b.week,                                           -- 対象週（週の開始日。時系列の時間軸）
  b.term,                                           -- 検索ワード（日本語）
  b.score,                                          -- 人気スコア（各語の自分比ピーク=100の相対値。語間比較不可）
  (b.week = mx.max_week)                 AS is_latest_week,  -- 最新週フラグ（②右のフィルタ用）
  IF(b.week = mx.max_week, b.rank, NULL) AS latest_rank      -- 最新週のみ有効な順位（同点あり。履歴はNULL）
FROM base b CROSS JOIN mx;

-- -----------------------------------------------------------------------------
-- 参考: Looker Studio 各チャートの参照（すべて上記1テーブル・計算フィールド0本）
-- -----------------------------------------------------------------------------
-- ① KPI       : スコアカード。COUNT_DISTINCT(term) / COUNT_DISTINCT(week) / MAX(week)
-- ② 左 定番   : 棒付き表。ディメンション=term、指標=COUNT_DISTINCT(week)、降順、行数10-15
-- ② 右 今週   : 表。チャートフィルタ is_latest_week=true、ディメンション=term、
--               指標/並べ替え=latest_rank(最小・昇順)、補助列 score
-- ③ 時系列   : 時系列。X=week、指標=score、語はクロスフィルタ/ドロップダウンで選択
-- 県選択      : ドロップダウンコントロール region_name（ページ/レポートレベル）
-- 地図(任意)  : 地域別マップ region_code（塗り分けは値でなく選択状態のみ。要実機検証、
--               不安定なら緯度経度バブルにフォールバック）
-- 注意        : 全体に効く単一の期間コントロールは置かない（時間スコープがゾーンで異なるため）
-- =============================================================================
