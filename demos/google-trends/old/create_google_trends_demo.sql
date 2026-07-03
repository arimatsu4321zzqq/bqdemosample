-- =============================================================================
-- bqdemosample — Google Trends デモ環境 作成SQL
-- =============================================================================
-- 目的 : bigquery-public-data.google_trends を題材にした自然言語分析デモ用の
--        curated テーブルを作成する。
-- 対象 : プロジェクト = ci-ss4-develop / データセット = demo_google_trends (US)
-- 元データ: bigquery-public-data.google_trends.international_top_terms
--           bigquery-public-data.google_trends.international_top_rising_terms
-- 方針 : 日本(JP)分のみ抽出。google_trends は直近スナップショット(refresh_date)ごとに
--        過去週を再掲するため、(region_name, week, term) 単位で最新 refresh_date の
--        観測値を採用して重複排除する。これで「語彙数」と「時系列の長さ」を両立する。
-- 備考 : 白川町案件(BQ_TEST_shirakawa_tourism)とは別データセットで分離。
--        カラム説明は OPTIONS(description=...) でテーブルに埋め込む。
-- =============================================================================

-- -----------------------------------------------------------------------------
-- 0. データセット作成（SQLではないため bq CLI で。US マルチリージョン必須：
--    元データ bigquery-public-data が US のため）
-- -----------------------------------------------------------------------------
--   bq --location=US mk --dataset \
--     --description "Google Trends デモ用（bqdemosample）" \
--     ci-ss4-develop:demo_google_trends

-- -----------------------------------------------------------------------------
-- 1. 日本の人気検索ワード（都道府県別・週次）
-- -----------------------------------------------------------------------------
CREATE OR REPLACE TABLE `ci-ss4-develop.demo_google_trends.jp_top_terms` (
  country_name STRING  OPTIONS(description="国名（本テーブルは日本のみ。値は Japan）"),
  country_code STRING  OPTIONS(description="ISO 国コード（本テーブルは JP のみ）"),
  region_name  STRING  OPTIONS(description="都道府県名（英語表記。例: Tokyo, Aichi Prefecture, Osaka Prefecture）"),
  region_code  STRING  OPTIONS(description="地域コード（ISO 3166-2 相当。例: JP-13=東京）"),
  term         STRING  OPTIONS(description="検索ワード（日本語。その週・地域で上位にランクインした語）"),
  week         DATE    OPTIONS(description="対象週（週の開始日。時系列トレンド分析の時間軸）"),
  rank         INT64   OPTIONS(description="その週・都道府県内での人気順位（1が最上位。通常1〜25）"),
  score        INT64   OPTIONS(description="人気スコア（Google検索インタレストの相対値。系列内の最大を100とする0〜100）"),
  refresh_date DATE    OPTIONS(description="元データの更新日。同一(都道府県,週,ワード)で最新refresh_dateの観測値を採用済み")
)
OPTIONS(description="日本(JP)の週次・人気検索ワードランキング（都道府県別）。bigquery-public-data.google_trends.international_top_terms のJP分を、全スナップショットから (region_name, week, term) 単位で最新refresh_dateのスコアを採用して重複排除。語彙と時系列の両方を確保したデモ用curatedテーブル。")
AS
SELECT country_name, country_code, region_name, region_code, term, week, rank, score, refresh_date
FROM `bigquery-public-data.google_trends.international_top_terms`
WHERE country_code = "JP"
QUALIFY ROW_NUMBER() OVER (PARTITION BY region_name, week, term ORDER BY refresh_date DESC) = 1;

-- -----------------------------------------------------------------------------
-- 2. 日本の急上昇検索ワード（都道府県別・週次）
-- -----------------------------------------------------------------------------
CREATE OR REPLACE TABLE `ci-ss4-develop.demo_google_trends.jp_top_rising_terms` (
  country_name STRING  OPTIONS(description="国名（本テーブルは日本のみ。値は Japan）"),
  country_code STRING  OPTIONS(description="ISO 国コード（本テーブルは JP のみ）"),
  region_name  STRING  OPTIONS(description="都道府県名（英語表記。例: Tokyo, Aichi Prefecture）"),
  region_code  STRING  OPTIONS(description="地域コード（ISO 3166-2 相当。例: JP-13=東京）"),
  term         STRING  OPTIONS(description="急上昇した検索ワード（日本語）"),
  week         DATE    OPTIONS(description="対象週（週の開始日。時系列トレンド分析の時間軸）"),
  rank         INT64   OPTIONS(description="その週・都道府県内での急上昇順位（1が最上位）"),
  score        INT64   OPTIONS(description="人気スコア（相対値0〜100。急上昇系列では欠損の場合あり）"),
  percent_gain INT64   OPTIONS(description="上昇率(%)。前週比などの伸び。話題性・バズの強さを表す主要指標"),
  refresh_date DATE    OPTIONS(description="元データの更新日。同一(都道府県,週,ワード)で最新refresh_dateの観測値を採用済み")
)
OPTIONS(description="日本(JP)の週次・急上昇検索ワードランキング（都道府県別）。bigquery-public-data.google_trends.international_top_rising_terms のJP分を (region_name, week, term) 単位で最新refresh_dateを採用して重複排除したデモ用curatedテーブル。percent_gain(上昇率)が話題性の指標。")
AS
SELECT country_name, country_code, region_name, region_code, term, week, rank, score, percent_gain, refresh_date
FROM `bigquery-public-data.google_trends.international_top_rising_terms`
WHERE country_code = "JP"
QUALIFY ROW_NUMBER() OVER (PARTITION BY region_name, week, term ORDER BY refresh_date DESC) = 1;
