# 日本 検索トレンド分析エージェント (Conversational Analytics / Gemini Data Analytics)

`ci-ss4-develop.demo_google_trends.jp_region_weekly`（地域ビュー用・単一テーブル）を
対象にした自然言語データエージェント。**2026-07-03 に旧2テーブル（jp_top_terms /
jp_top_rising_terms）から移行済み**（経緯・テーブル設計は [`../data-flow.md`](../data-flow.md)）。

- API: `geminidataanalytics.googleapis.com`（有効化済み）
- ロケーション: `global`
- エージェントID: `jp_trends_demo`
- リソース名: `projects/ci-ss4-develop/locations/global/dataAgents/jp_trends_demo`
- 定義ペイロード: [`jp_trends_agent.json`](./jp_trends_agent.json)（[`build_payload.py`](./build_payload.py) で生成）

## 作成 / 更新

```bash
TOKEN=$(gcloud auth print-access-token)
PROJECT=ci-ss4-develop
AGENT_ID=jp_trends_demo

# 作成（初回）
curl -X POST \
  "https://geminidataanalytics.googleapis.com/v1beta/projects/$PROJECT/locations/global/dataAgents?data_agent_id=$AGENT_ID" \
  -H "Authorization: Bearer $TOKEN" -H "x-goog-user-project: $PROJECT" \
  -H "Content-Type: application/json" -d @jp_trends_agent.json

# 更新（build_payload.py で JSON を再生成してから PATCH）
curl -X PATCH \
  "https://geminidataanalytics.googleapis.com/v1beta/projects/$PROJECT/locations/global/dataAgents/$AGENT_ID?update_mask=data_analytics_agent,labels,description" \
  -H "Authorization: Bearer $TOKEN" -H "x-goog-user-project: $PROJECT" \
  -H "Content-Type: application/json" -d @jp_trends_agent.json
```

## 質問する（ステートレス chat）

```bash
TOKEN=$(gcloud auth print-access-token)
PROJECT=ci-ss4-develop
curl -X POST \
  "https://geminidataanalytics.googleapis.com/v1beta/projects/$PROJECT/locations/global:chat" \
  -H "Authorization: Bearer $TOKEN" -H "x-goog-user-project: $PROJECT" \
  -H "Content-Type: application/json" -d '{
    "parent": "projects/'$PROJECT'/locations/global",
    "messages": [{"userMessage": {"text": "直近の週で東京の人気検索ワードTop5を教えて"}}],
    "dataAgentContext": {"dataAgent": "projects/'$PROJECT'/locations/global/dataAgents/jp_trends_demo"}
  }'
```

レスポンスは NDJSON 風のメッセージ列（`systemMessage.text` = 思考/回答、`systemMessage.data.query` =
生成SQL、`systemMessage.data.result` = 実行結果テーブル）。

## 質問例（動作確認済み）

- 直近の週で東京の人気検索ワードTop10を教えて（← is_latest_week + latest_rank）
- 「栗きんとん」の全国平均スコアの週次推移を見せて（← 毎年秋だけ跳ねる季節ワード）
- 栗きんとんはどこの県のワード？（← score の県間比較は不可のため、ランクイン週数で回答。
  愛知251週・東京238週・岐阜190週=中京圏の地元ワード）
- 大阪で最近話題になっているワードを教えて
  （← 急上昇データが無いことを自分で説明し、4週前比の score 増分で近似する。移行時に検証済み）

## 定義に含まれるもの（地域ビュー移行版のポイント）

- **datasourceReferences**: `jp_region_weekly` 1本のみ
- **systemInstruction**: 新テーブルの設計仕様をルール化
  - 「最新・直近」= `is_latest_week`／順位は最新週のみ（`latest_rank`。過去週はNULL＝焼き付きrank対策）
  - score は自己ピーク=100 の相対値（ワード間の絶対比較・実数扱いを禁止）
  - 急上昇の専用データなし → score の伸びで近似し、その旨を断る
  - 県名の英日対応（東京のみ 'Tokyo'、他は '<英名> Prefecture'）
- **exampleQueries**: BigQuery で実行検証済みの golden query 8本（伸び近似のCTE例を含む）
- **labels**: `app=bqdemosample / theme=google-trends / country=jp / env=demo`
