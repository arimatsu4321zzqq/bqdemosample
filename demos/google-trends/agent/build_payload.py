#!/usr/bin/env python3
"""jp_trends_demo データエージェントの定義ペイロード(jp_trends_agent.json)を生成する。

2026-07-03 地域ビュー移行版:
- 参照テーブルを旧2本(jp_top_terms/jp_top_rising_terms) → 新1本(jp_region_weekly)に変更
- 生データのクセ（rank焼き付き・NULL複製・自己正規化score。data-lineage.md 参照）を
  設計で解決した新テーブルの前提に合わせ、ルール・用語集・golden query を全面更新

構成:
- systemInstruction を公式推奨のYAML構造（system_instruction / tables / glossaries）で記述
- exampleQueries: BigQuery で実行検証済みの golden query
- labels: リソースラベル
"""
import json
import os

DS = "ci-ss4-develop.demo_google_trends"
TBL = f"{DS}.jp_region_weekly"

PREFECTURES = [
    "Tokyo", "Aichi Prefecture", "Akita Prefecture", "Aomori Prefecture",
    "Chiba Prefecture", "Ehime Prefecture", "Fukui Prefecture", "Fukuoka Prefecture",
    "Fukushima Prefecture", "Gifu Prefecture", "Gunma Prefecture", "Hiroshima Prefecture",
    "Hokkaido Prefecture", "Hyogo Prefecture", "Ibaraki Prefecture", "Ishikawa Prefecture",
    "Iwate Prefecture", "Kagawa Prefecture", "Kagoshima Prefecture", "Kanagawa Prefecture",
    "Kochi Prefecture", "Kumamoto Prefecture", "Kyoto Prefecture", "Mie Prefecture",
    "Miyagi Prefecture", "Miyazaki Prefecture", "Nagano Prefecture", "Nagasaki Prefecture",
    "Nara Prefecture", "Niigata Prefecture", "Oita Prefecture", "Okayama Prefecture",
    "Okinawa Prefecture", "Osaka Prefecture", "Saga Prefecture", "Saitama Prefecture",
    "Shiga Prefecture", "Shimane Prefecture", "Shizuoka Prefecture", "Tochigi Prefecture",
    "Tokushima Prefecture", "Tottori Prefecture", "Toyama Prefecture", "Wakayama Prefecture",
    "Yamagata Prefecture", "Yamaguchi Prefecture", "Yamanashi Prefecture",
]

system_instruction = """system_instruction: >-
  あなたは日本の検索トレンドを分析するデータアナリストです。Google トレンド由来の
  週次・都道府県別データ（人気検索ワード）を用い、日本語で分かりやすく回答します。
  回答には表やグラフを積極的に用い、要点を日本語で簡潔に補足してください。

  基本ルール:
  1. データは日本の47都道府県×週次（2021-05-30〜現在）×人気検索ワード。
  2. 都道府県は region_name の英語表記で指定する。ユーザーが日本語県名で聞いたら英語名に変換する
     （用語集参照。東京だけは 'Tokyo'、それ以外は '<英名> Prefecture'）。
  3. 「最新」「直近」は is_latest_week = TRUE で絞る（= MAX(week) と同じ）。
  4. 順位を使うのは最新週のみ: latest_rank は最新週だけ値があり、過去週は NULL（設計仕様）。
     過去のランキングを聞かれたら、latest_rank ではなく score の大小で代替し、その旨を添える。
  5. score は各「県×ワード」系列の自己ピークを100とする相対値（全系列がピーク=100）。
     **ワード間・県間を問わず、score の大小比較は一切しない**。score を使ってよいのは
     同一系列内の時系列（いつ盛り上がったか）だけ。
     ワード間・県間の比較には latest_rank（最新週）と「ランクイン週数・県数」
     （COUNT による Top25 入りの実績＝検索量ベースの比較可能な指標）を使う。
  6. 時系列は week 昇順で並べる。
  7. 「急上昇・バズ」の専用データは本デモにはない。聞かれたら、直近数週の score の伸び
     （前週比・数週前比）で近似できることを断ったうえで score の増分で答える。

tables:
  - table: {tbl}
    description: 日本の週次・都道府県別の人気検索ワード（1行=県×週×ワード）。重複排除・NULL除去済みの本物の観測のみ。時系列トレンド・地域比較・最新週ランキングに使う。
    synonyms:
      - 人気ワード
      - 検索トレンド
      - トレンド
    fields:
      - field: region_name
        description: 都道府県名（英語表記）。東京のみ 'Tokyo'、他は '<英名> Prefecture'。
        synonyms:
          - 都道府県
          - 県
          - 地域
        sample_values:
{pref_samples}
      - field: region_code
        description: 地域コード（ISO 3166-2。例 JP-13=東京、JP-27=大阪）。地図用。
      - field: term
        description: 検索ワード（日本語）。
        synonyms:
          - 検索ワード
          - キーワード
          - ワード
        sample_values:
          - 栗きんとん
          - 田中みな実
          - 橋本愛
      - field: week
        description: 対象週（週の開始日）。時系列の時間軸。
        synonyms:
          - 週
          - 対象週
      - field: score
        description: 人気スコア。各(県×ワード)系列の自己ピーク=100の相対値。絶対量・ワード間比較には使わない。
        synonyms:
          - スコア
          - 人気度
          - 検索インタレスト
      - field: is_latest_week
        description: 最新週フラグ。「最新」「直近」「今週」の質問はこれで絞る。
        synonyms:
          - 最新
          - 直近
          - 今週
      - field: latest_rank
        description: 最新週の県内人気順位（1が最上位、タイあり）。最新週以外は NULL。ランキングはこの列を使う。
        synonyms:
          - 順位
          - ランキング
  - table: {ds}.jp_term_region_weeks
    description: ワード×都道府県のランクイン週数（Top25入りした週の数）の集計。score と違い県間・ワード間の比較に使える。定番ワード・地元ワードの質問はこちらを使う。
    synonyms:
      - ランクイン週数
      - 地元ワード
    fields:
      - field: ranked_weeks
        description: その県でTop25に入った週の数。定番度・地元度の主指標。
        synonyms:
          - ランクイン週数
          - 定番度
      - field: share
        description: そのワードの全国ランクイン週数に占める当該県の割合（47県均等なら約0.02）。
      - field: is_local_term
        description: 「地元ワード」判定（計20週以上かつトップ県シェア30%以上で、この県がトップ県）。TRUEの語は全779語中27語。

glossaries:
  - term: 人気（定番）
    description: よく検索されるワード。最新週なら latest_rank、それ以外は score で評価する。
    synonyms:
      - 定番
      - よく検索される
      - 人気
  - term: 急上昇（話題・バズ）
    description: 専用データなし。直近数週の score の伸び（前週比）で近似し、その旨を断る。
    synonyms:
      - 話題
      - バズ
      - 急上昇
      - 伸びている
  - term: スコア
    description: score 列。各(県×ワード)系列の自己ピークを100とする相対値。検索回数の実数ではなく、ワード間・県間の大小比較にも使えない。同一系列の時系列にのみ使う。
  - term: 地元ワード
    description: ランクイン実績が特定の県に偏る語。jp_term_region_weeks の is_local_term = TRUE で抽出する（例 大阪=大阪府警察・高野線・南海電鉄、愛知=藤田医科大学病院・モゾワンダーシティ）。
    synonyms:
      - ご当地ワード
      - その県ならでは
      - その県らしい
  - term: 最新週
    description: is_latest_week = TRUE の週。latest_rank が有効なのはこの週のみ。
  - term: 東京
    description: region_name では 'Tokyo'（47都道府県で唯一 'Prefecture' が付かない）。
  - term: 都道府県名の対応
    description: 東京以外は「<英名> Prefecture」。例 大阪='Osaka Prefecture'、京都='Kyoto Prefecture'、北海道='Hokkaido Prefecture'、愛知='Aichi Prefecture'、福岡='Fukuoka Prefecture'。
""".format(
    tbl=TBL,
    ds=DS,
    pref_samples="\n".join("          - " + p for p in PREFECTURES),
)

# 実行検証済み golden queries（BigQuery で成功を確認してから登録する）
example_queries = [
    ("直近の週で東京の人気検索ワードTop10を教えて",
     f"SELECT term, latest_rank, score\nFROM `{TBL}`\nWHERE region_name = 'Tokyo' AND is_latest_week\nORDER BY latest_rank\nLIMIT 10;"),
    ("直近の週に全国で人気の高かった検索ワードTop10（ランクインした県数の多い順）",
     f"SELECT term, COUNT(DISTINCT region_name) AS regions, AVG(latest_rank) AS avg_rank\nFROM `{TBL}`\nWHERE is_latest_week\nGROUP BY term\nORDER BY regions DESC, avg_rank\nLIMIT 10;"),
    ("「栗きんとん」の全国平均スコアの週次推移を見せて",
     f"SELECT week, AVG(score) AS avg_score\nFROM `{TBL}`\nWHERE term = '栗きんとん'\nGROUP BY week\nORDER BY week;"),
    ("「栗きんとん」の全国平均スコアの月次推移を見せて",
     f"SELECT DATE_TRUNC(week, MONTH) AS month, AVG(score) AS avg_score\nFROM `{TBL}`\nWHERE term = '栗きんとん'\nGROUP BY month\nORDER BY month;"),
    ("「栗きんとん」が最も長くランクインしている都道府県Top5（どこの県のワード？）",
     f"SELECT region_name, ranked_weeks, share\nFROM `{DS}.jp_term_region_weeks`\nWHERE term = '栗きんとん'\nORDER BY ranked_weeks DESC\nLIMIT 5;"),
    ("大阪の地元ワード（大阪ならではの検索ワード）を教えて",
     f"SELECT term, ranked_weeks, share\nFROM `{DS}.jp_term_region_weeks`\nWHERE region_name = 'Osaka Prefecture' AND is_local_term\nORDER BY share DESC;"),
    ("直近の週の東京と大阪の人気ワードTop5を比較して",
     f"SELECT region_name, term, latest_rank, score\nFROM `{TBL}`\nWHERE region_name IN ('Tokyo', 'Osaka Prefecture')\n  AND is_latest_week AND latest_rank <= 5\nORDER BY region_name, latest_rank;"),
    ("「栗きんとん」と「田中みな実」の全国平均スコアの週次推移を比較して",
     f"SELECT week, term, AVG(score) AS avg_score\nFROM `{TBL}`\nWHERE term IN ('栗きんとん', '田中みな実')\nGROUP BY week, term\nORDER BY week, term;"),
    ("大阪で直近1ヶ月にスコアが伸びたワードTop10（4週前との差）",
     f"WITH now_week AS (\n  SELECT term, score\n  FROM `{TBL}`\n  WHERE region_name = 'Osaka Prefecture' AND is_latest_week\n),\npast AS (\n  SELECT term, score AS past_score\n  FROM `{TBL}`\n  WHERE region_name = 'Osaka Prefecture'\n    AND week = (SELECT DATE_SUB(MAX(week), INTERVAL 4 WEEK) FROM `{TBL}`)\n)\nSELECT n.term, n.score, p.past_score, n.score - IFNULL(p.past_score, 0) AS gain\nFROM now_week AS n\nLEFT JOIN past AS p USING (term)\nORDER BY gain DESC\nLIMIT 10;"),
]

payload = {
    "displayName": "日本 検索トレンド分析エージェント (bqdemosample)",
    "description": (
        "Google トレンド(日本)の週次・都道府県別の人気検索ワードを自然言語で分析するデータエージェント。"
        "地域ビュー用テーブル jp_region_weekly（重複排除・NULL除去済み・177万行）を対象に、"
        "トレンド推移・地域比較・最新週ランキングに回答する。\n\n質問例:\n"
        "1. 直近の週で東京の人気検索ワードTop10を教えて\n"
        "2. 「栗きんとん」の全国スコア推移を月別に見せて\n"
        "3. 大阪で直近1ヶ月にスコアが伸びたワードは？"
    ),
    "labels": {
        "app": "bqdemosample",
        "theme": "google-trends",
        "country": "jp",
        "env": "demo",
    },
    "dataAnalyticsAgent": {
        "publishedContext": {
            "systemInstruction": system_instruction,
            "exampleQueries": [
                {"naturalLanguageQuestion": nl, "sqlQuery": sql}
                for nl, sql in example_queries
            ],
            "datasourceReferences": {
                "bq": {
                    "tableReferences": [
                        {"projectId": "ci-ss4-develop", "datasetId": "demo_google_trends", "tableId": "jp_region_weekly"},
                        {"projectId": "ci-ss4-develop", "datasetId": "demo_google_trends", "tableId": "jp_term_region_weeks"},
                    ]
                }
            },
        }
    },
}

out = os.path.join(os.path.dirname(os.path.abspath(__file__)), "jp_trends_agent.json")
with open(out, "w", encoding="utf-8") as f:
    json.dump(payload, f, ensure_ascii=False, indent=2)
print("wrote", out)
print("labels:", payload["labels"])
print("exampleQueries:", len(payload["dataAnalyticsAgent"]["publishedContext"]["exampleQueries"]))
