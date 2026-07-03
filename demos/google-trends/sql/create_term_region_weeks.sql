-- =============================================================================
-- bqdemosample — 地域ビュー補助テーブル: ワード×県のランクイン週数
-- =============================================================================
-- 目的 : score は系列ごとの自己ピーク比のため、ワード間・県間の大小比較に使えない。
--        県間・ワード間の比較に使える「ランクイン週数」（その県のTop25に入った週の数
--        ＝検索量ベースの実績）を term×県 で事前集計し、Looker Studio と
--        データエージェントから窓関数なしで使えるようにする。
-- 用途 : ①定番ワード（県内で週数が多い順） ②地元ワード（週数シェアが特定県に偏る語）
-- 元   : ci-ss4-develop.demo_google_trends.jp_region_weekly（177万行）
-- 規模 : 約3.5万行（term×県の組合せ）。再実行は冪等（CREATE OR REPLACE）。
-- =============================================================================
CREATE OR REPLACE TABLE `ci-ss4-develop.demo_google_trends.jp_term_region_weeks`
OPTIONS(description="ワード×都道府県のランクイン週数（Top25入りした週の数）。score と違い県間・ワード間の比較に使える実績指標。share=そのワードの全国ランクイン週数に占める当該県の割合（均等なら約2%）。is_local_term=計20週以上かつトップ県シェア30%以上の『地元ワード』判定（全779語中27語）。") AS
WITH per AS (
  SELECT term, region_name, region_code, COUNT(*) AS ranked_weeks
  FROM `ci-ss4-develop.demo_google_trends.jp_region_weekly`
  GROUP BY term, region_name, region_code
),
tot AS (
  SELECT term, SUM(ranked_weeks) AS total_weeks, MAX(ranked_weeks) AS top_pref_weeks
  FROM per GROUP BY term
)
SELECT
  p.term,                                       -- 検索ワード
  p.region_name,                                -- 都道府県名（英語表記）
  p.region_code,                                -- 地域コード（JP-xx）
  p.ranked_weeks,                               -- この県でTop25に入った週の数（定番度）
  t.total_weeks,                                -- 全国合計のランクイン週数
  ROUND(p.ranked_weeks / t.total_weeks, 3) AS share,  -- この県のシェア（均等なら≈0.02）
  (t.total_weeks >= 20
   AND t.top_pref_weeks / t.total_weeks >= 0.3
   AND p.ranked_weeks = t.top_pref_weeks) AS is_local_term  -- この県の「地元ワード」か
FROM per AS p
JOIN tot AS t USING (term);
