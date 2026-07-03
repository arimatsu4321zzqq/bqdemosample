#!/usr/bin/env python3
"""jp_facilities_demo データエージェントの定義ペイロード(jp_facilities_agent.json)を生成する。

構成は google-trends デモの build_payload.py に準拠:
- systemInstruction を公式推奨のYAML構造（system_instruction / tables / glossaries）で記述
- exampleQueries: BigQuery で実行検証済みの golden query
- labels: リソースラベル
"""
import json
import os

DS = "ci-ss4-develop.demo_osm_facilities"

PREFECTURES = [
    "北海道", "青森県", "岩手県", "宮城県", "秋田県", "山形県", "福島県",
    "茨城県", "栃木県", "群馬県", "埼玉県", "千葉県", "東京都", "神奈川県",
    "新潟県", "富山県", "石川県", "福井県", "山梨県", "長野県", "岐阜県",
    "静岡県", "愛知県", "三重県", "滋賀県", "京都府", "大阪府", "兵庫県",
    "奈良県", "和歌山県", "鳥取県", "島根県", "岡山県", "広島県", "山口県",
    "徳島県", "香川県", "愛媛県", "高知県", "福岡県", "佐賀県", "長崎県",
    "熊本県", "大分県", "宮崎県", "鹿児島県", "沖縄県",
]

MUNI_EXAMPLES = [
    "岐阜市", "高山市", "白川町", "横浜市", "京都市", "世田谷区", "那覇市",
    "札幌市", "仙台市", "金沢市", "松本市", "福岡市",
]

CATEGORIES = ["病院", "クリニック", "学校", "公民館・集会所", "図書館", "消防署", "避難場所"]

system_instruction = """system_instruction: >-
  あなたは地域の公共施設・医療施設を分析するデータアナリストです。OpenStreetMap 由来の
  全国の施設データを用い、日本語で分かりやすく回答します。回答には表やグラフを
  積極的に用い、要点を簡潔に補足してください。

  基本ルール:
  1. データは日本全国47都道府県・約1,700市区町村・約8.8万施設。2021年11月時点の
     スナップショットである点を、件数を答えるときに必要に応じて添える。
  2. 都道府県で絞るときは pref_name（例: 岐阜県, 東京都）、市区町村で絞るときは
     muni_name（例: 岐阜市, 白川町, 世田谷区）を使う。
  3. 施設の種類は category 列（日本語値）を使う。値は
     病院 / クリニック / 学校 / 公民館・集会所 / 図書館 / 消防署 / 避難場所 の7種。
  4. 「避難所になり得る施設」と聞かれたら category IN ('学校', '公民館・集会所') を使う
     （OSMの避難場所タグは全国354件と少数のため）。
  5. 自治体・都道府県間の件数比較は dash_muni_category（集計済み）を優先して使う。
  6. 個別施設の一覧・地図系の質問は jp_poi_facilities を使い、name と latitude /
     longitude を返す。
  7. 小学校・中学校・高校は区別できない（すべて category='学校'）。区別を求められたら
     name の部分一致（例: name LIKE '%小学校%'）で近似できるが、その旨を断る。
  8. 政令指定都市は市単位（例: 横浜市）。区単位のデータはない（東京23区は muni_name にある）。
  9. OSMは有志による地図のため、自治体によって施設の登録密度に差がある。件数が実際より
     少なく見える場合がある点を、比較の際に必要に応じて注記する。

tables:
  - table: {ds}.jp_poi_facilities
    description: 全国の主要施設POI（1行=1施設）。施設名・カテゴリ・所在自治体・都道府県・緯度経度を持つ。個別施設の一覧・検索・地図表示に使う。
    synonyms:
      - 施設
      - 施設一覧
      - POI
    fields:
      - field: pref_name
        description: 都道府県名（日本語）。
        synonyms:
          - 都道府県
          - 県
        sample_values:
{pref_samples}
      - field: muni_name
        description: 所在自治体名（日本語）。全国約1,700市区町村。東京23区は区名。
        synonyms:
          - 自治体
          - 市町村
          - 市区町村
        sample_values:
{muni_samples}
      - field: category
        description: 施設カテゴリ（日本語）。
        synonyms:
          - 種類
          - 施設タイプ
        sample_values:
{cat_samples}
      - field: name
        description: 施設名（日本語。例 市立岐阜商業高校, 白川病院）。数%は名称未登録(NULL)。
        synonyms:
          - 施設名
          - 名前
      - field: latitude
        description: 緯度（面で描かれた施設は建物の重心）。
      - field: longitude
        description: 経度。
      - field: is_assembly_point
        description: OSMで避難場所(emergency=assembly_point)タグが付いているか。全国で354件と少数。
  - table: {ds}.dash_muni_category
    description: 自治体×カテゴリの施設数サマリ（都道府県名付き）。自治体間・都道府県間の比較・ランキングに使う。
    synonyms:
      - 施設数
      - 集計
    fields:
      - field: pref_name
        description: 都道府県名（日本語）。
      - field: muni_name
        description: 自治体名（日本語）。
      - field: category
        description: 施設カテゴリ（日本語）。
      - field: facility_count
        description: 施設数。比較・ランキングの主指標。
        synonyms:
          - 件数
          - 数

glossaries:
  - term: 避難所になり得る施設
    description: 学校と公民館・集会所を指す。category IN ('学校', '公民館・集会所') で抽出する。
    synonyms:
      - 避難所候補
      - 避難できる場所
      - 避難施設
  - term: 医療機関
    description: 病院とクリニックの総称。category IN ('病院', 'クリニック')。
    synonyms:
      - 医療施設
      - 病院・診療所
  - term: データ時点
    description: OpenStreetMap の2021年11月8日時点スナップショット。以後の開設・閉鎖は反映されていない。
  - term: 公民館
    description: category は '公民館・集会所'（集会所・コミュニティセンターを含む）。
""".format(
    ds=DS,
    pref_samples="\n".join("          - " + p for p in PREFECTURES),
    muni_samples="\n".join("          - " + m for m in MUNI_EXAMPLES),
    cat_samples="\n".join("          - " + c for c in CATEGORIES),
)

# 実行検証済み golden queries（BigQuery で成功を確認してから登録する）
example_queries = [
    ("岐阜市の病院を一覧で見せて",
     f"SELECT name, latitude, longitude\nFROM `{DS}.jp_poi_facilities`\nWHERE muni_name = '岐阜市' AND category = '病院' AND name IS NOT NULL\nORDER BY name;"),
    ("高山市と飛騨市で学校の数を比べて",
     f"SELECT muni_name, facility_count\nFROM `{DS}.dash_muni_category`\nWHERE muni_name IN ('高山市', '飛騨市') AND category = '学校'\nORDER BY facility_count DESC;"),
    ("東京都で公民館・集会所が多い自治体Top10を教えて",
     f"SELECT muni_name, facility_count\nFROM `{DS}.dash_muni_category`\nWHERE pref_name = '東京都' AND category = '公民館・集会所'\nORDER BY facility_count DESC\nLIMIT 10;"),
    ("白川町にはどんな施設がある？カテゴリ別に数えて",
     f"SELECT category, facility_count\nFROM `{DS}.dash_muni_category`\nWHERE muni_name = '白川町' AND pref_name = '岐阜県'\nORDER BY facility_count DESC;"),
    ("岐阜県で図書館がない自治体はどこ？",
     f"SELECT DISTINCT muni_name\nFROM `{DS}.jp_poi_facilities`\nWHERE pref_name = '岐阜県'\n  AND muni_name NOT IN (\n    SELECT muni_name FROM `{DS}.jp_poi_facilities`\n    WHERE pref_name = '岐阜県' AND category = '図書館'\n  )\nORDER BY muni_name;"),
    ("避難所になり得る施設（学校・公民館）が多い自治体Top10（全国）",
     f"SELECT pref_name, muni_name, SUM(facility_count) AS shelter_candidates\nFROM `{DS}.dash_muni_category`\nWHERE category IN ('学校', '公民館・集会所')\nGROUP BY pref_name, muni_name\nORDER BY shelter_candidates DESC\nLIMIT 10;"),
    ("都道府県別の病院数ランキングTop10",
     f"SELECT pref_name, SUM(facility_count) AS hospitals\nFROM `{DS}.dash_muni_category`\nWHERE category = '病院'\nGROUP BY pref_name\nORDER BY hospitals DESC\nLIMIT 10;"),
    ("郡上市の小学校を一覧で（名前に小学校を含む学校）",
     f"SELECT name, latitude, longitude\nFROM `{DS}.jp_poi_facilities`\nWHERE muni_name = '郡上市' AND category = '学校' AND name LIKE '%小学校%'\nORDER BY name;"),
]

payload = {
    "displayName": "地域施設マップ分析エージェント (bqdemosample)",
    "description": (
        "OpenStreetMap 由来の全国の主要施設データ（病院・クリニック・学校・公民館・図書館・"
        "消防署、約8.8万件）を自然言語で分析するデータエージェント。都道府県・市区町村で"
        "絞った施設一覧、自治体間の施設数比較、避難所候補の抽出に回答する。"
        "データ時点は2021年11月。\n\n質問例:\n"
        "1. 岐阜市の病院を一覧で見せて\n"
        "2. 高山市と飛騨市で学校の数を比べて\n"
        "3. 避難所になり得る施設が多い自治体Top10"
    ),
    "labels": {
        "app": "bqdemosample",
        "theme": "osm-facilities",
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
                        {"projectId": "ci-ss4-develop", "datasetId": "demo_osm_facilities", "tableId": "jp_poi_facilities"},
                        {"projectId": "ci-ss4-develop", "datasetId": "demo_osm_facilities", "tableId": "dash_muni_category"},
                    ]
                }
            },
        }
    },
}

out = os.path.join(os.path.dirname(os.path.abspath(__file__)), "jp_facilities_agent.json")
with open(out, "w", encoding="utf-8") as f:
    json.dump(payload, f, ensure_ascii=False, indent=2)
print("wrote", out)
print("labels:", payload["labels"])
print("exampleQueries:", len(payload["dataAnalyticsAgent"]["publishedContext"]["exampleQueries"]))
