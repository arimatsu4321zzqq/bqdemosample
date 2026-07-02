#!/usr/bin/env python3
"""jp_trends_demo データエージェントの定義ペイロード(jp_trends_agent.json)を生成する。

強化内容:
- systemInstruction を公式推奨のYAML構造（system_instruction / tables / glossaries）で記述
  - tables: 各カラムの説明・同義語(synonyms)・サンプル値(sample_values)
  - glossaries: 業務用語→テーブル/カラムの対応（人気/急上昇/スコア/上昇率/県名の対応など）
- exampleQueries: BigQuery で実行検証済みの golden query 8本
- labels: リソースラベル
"""
import json

DS = "ci-ss4-develop.demo_google_trends"

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

# YAML はインデントが意味を持つため、慎重に組み立てる。
system_instruction = """system_instruction: >-
  あなたは日本の検索トレンドを分析するデータアナリストです。Google トレンド由来の
  週次・都道府県別データを用い、日本語で分かりやすく回答します。回答には表やグラフを
  積極的に用い、要点を日本語で簡潔に補足してください。

  基本ルール:
  1. 「人気・定番」は jp_top_terms、「急上昇・話題・バズ」は jp_top_rising_terms を使う。
  2. データは日本(country_code='JP')のみ。国の絞り込みは不要。
  3. 都道府県は region_name の英語表記で指定する。ユーザーが日本語県名で聞いたら英語名に変換する
     （用語集参照。東京だけは 'Tokyo'、それ以外は '<英名> Prefecture'）。
  4. 「最新」「直近」は各テーブルの MAX(week) を基準にする。
  5. 全国集計は都道府県をまたぐため term・week 単位で AVG(score) や MAX(percent_gain) を取る。
  6. 時系列は week 昇順で並べる。rank は同一週・地域内で同順位(タイ)が存在しうる点に注意。

tables:
  - table: {ds}.jp_top_terms
    description: 日本の週次・都道府県別「人気」検索ワードランキング。定番・よく検索される語の把握に使う。
    synonyms:
      - 人気ワード
      - 人気検索ワード
      - トップワード
    fields:
      - field: region_name
        description: 都道府県名（英語表記）。東京のみ 'Tokyo'、他は '<英名> Prefecture'。
        synonyms:
          - 都道府県
          - 県
          - 地域
        sample_values:
{pref_samples}
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
      - field: rank
        description: その週・都道府県内での人気順位（1が最上位、通常1〜25）。タイあり。
        synonyms:
          - 順位
          - ランキング
      - field: score
        description: 人気スコア（相対値0〜100、系列内最大を100）。
        synonyms:
          - スコア
          - 人気度
          - 検索インタレスト
  - table: {ds}.jp_top_rising_terms
    description: 日本の週次・都道府県別「急上昇」検索ワード。話題性・バズの把握に使う。
    synonyms:
      - 急上昇ワード
      - 話題のワード
      - バズワード
    fields:
      - field: percent_gain
        description: 上昇率(%)。伸びの大きさ＝話題性の主指標。急上昇分析ではこの列で並べ替える。
        synonyms:
          - 上昇率
          - 伸び率
          - 話題性
      - field: term
        description: 急上昇した検索ワード（日本語）。
      - field: score
        description: 人気スコア（相対値0〜100）。急上昇系列では欠損の場合あり。

glossaries:
  - term: 人気（定番）
    description: よく検索される定番ワード。jp_top_terms を参照し score / rank で評価する。
    synonyms:
      - 定番
      - よく検索される
      - 人気
  - term: 急上昇（話題・バズ）
    description: 短期間に検索が伸びたワード。jp_top_rising_terms を参照し percent_gain で評価する。
    synonyms:
      - 話題
      - バズ
      - 急上昇
      - 伸びている
      - トレンド
  - term: スコア
    description: score 列。0〜100の相対的な検索インタレスト。系列内の最大を100とする。
  - term: 上昇率
    description: percent_gain 列。急上昇の度合い(%)。jp_top_rising_terms のみに存在。
  - term: 東京
    description: region_name では 'Tokyo'（47都道府県で唯一 'Prefecture' が付かない）。
  - term: 都道府県名の対応
    description: 東京以外は「<英名> Prefecture」。例 大阪='Osaka Prefecture'、京都='Kyoto Prefecture'、北海道='Hokkaido Prefecture'、愛知='Aichi Prefecture'、福岡='Fukuoka Prefecture'。
""".format(
    ds=DS,
    pref_samples="\n".join("          - " + p for p in PREFECTURES),
)

# 実行検証済み golden queries（BigQuery で成功を確認済み）
example_queries = [
    ("直近の週で東京の人気検索ワードTop10を教えて",
     f"SELECT term, rank, score\nFROM `{DS}.jp_top_terms`\nWHERE region_name = 'Tokyo'\n  AND week = (SELECT MAX(week) FROM `{DS}.jp_top_terms`)\nORDER BY rank\nLIMIT 10;"),
    ("直近の週に全国で人気の高かった検索ワードTop10（都道府県横断の平均スコア順）",
     f"SELECT term, AVG(score) AS avg_score, COUNT(DISTINCT region_name) AS regions\nFROM `{DS}.jp_top_terms`\nWHERE week = (SELECT MAX(week) FROM `{DS}.jp_top_terms`)\nGROUP BY term\nORDER BY avg_score DESC, regions DESC\nLIMIT 10;"),
    ("「栗きんとん」の全国平均スコアの週次推移を見せて",
     f"SELECT week, AVG(score) AS avg_score\nFROM `{DS}.jp_top_terms`\nWHERE term = '栗きんとん'\nGROUP BY week\nORDER BY week;"),
    ("「栗きんとん」の全国平均スコアの月次推移を見せて",
     f"SELECT DATE_TRUNC(week, MONTH) AS month, AVG(score) AS avg_score\nFROM `{DS}.jp_top_terms`\nWHERE term = '栗きんとん'\nGROUP BY month\nORDER BY month;"),
    ("直近の週で「栗きんとん」を最も検索している都道府県Top5",
     f"SELECT region_name, score\nFROM `{DS}.jp_top_terms`\nWHERE term = '栗きんとん'\n  AND week = (SELECT MAX(week) FROM `{DS}.jp_top_terms`)\nORDER BY score DESC\nLIMIT 5;"),
    ("直近週で最も急上昇したワードを上昇率順に10件",
     f"SELECT region_name, term, percent_gain, rank\nFROM `{DS}.jp_top_rising_terms`\nWHERE week = (SELECT MAX(week) FROM `{DS}.jp_top_rising_terms`)\nORDER BY percent_gain DESC\nLIMIT 10;"),
    ("直近の週の東京と大阪の人気ワードTop5を比較して",
     f"SELECT region_name, term, rank, score\nFROM `{DS}.jp_top_terms`\nWHERE region_name IN ('Tokyo', 'Osaka Prefecture')\n  AND week = (SELECT MAX(week) FROM `{DS}.jp_top_terms`)\n  AND rank <= 5\nORDER BY region_name, rank;"),
    ("「栗きんとん」と「田中みな実」の全国平均スコアの週次推移を比較して",
     f"SELECT week, term, AVG(score) AS avg_score\nFROM `{DS}.jp_top_terms`\nWHERE term IN ('栗きんとん', '田中みな実')\nGROUP BY week, term\nORDER BY week, term;"),
]

payload = {
    "displayName": "日本 検索トレンド分析エージェント (bqdemosample)",
    "description": (
        "Google トレンド(日本)の週次・都道府県別データを自然言語で分析するデータエージェント。"
        "人気ワード(jp_top_terms)と急上昇ワード(jp_top_rising_terms)の2テーブルを対象に、"
        "トレンド推移・地域比較・話題ワード抽出に回答する。\n\n質問例:\n"
        "1. 直近の週で東京の人気検索ワードTop10を教えて\n"
        "2. 「栗きんとん」の全国スコア推移を月別に見せて\n"
        "3. 直近週で最も急上昇したワードを都道府県別に教えて"
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
                        {"projectId": "ci-ss4-develop", "datasetId": "demo_google_trends", "tableId": "jp_top_terms"},
                        {"projectId": "ci-ss4-develop", "datasetId": "demo_google_trends", "tableId": "jp_top_rising_terms"},
                    ]
                }
            },
        }
    },
}

out = "/home/dskarimatsu/aistudy/bqdemosample/agent/jp_trends_agent.json"
with open(out, "w", encoding="utf-8") as f:
    json.dump(payload, f, ensure_ascii=False, indent=2)
print("wrote", out)
print("labels:", payload["labels"])
print("exampleQueries:", len(payload["dataAnalyticsAgent"]["publishedContext"]["exampleQueries"]))
