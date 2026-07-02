# 日本 検索トレンド分析エージェント (Conversational Analytics / Gemini Data Analytics)

`ci-ss4-develop.demo_google_trends` の2テーブル（`jp_top_terms` / `jp_top_rising_terms`）を
対象にした自然言語データエージェント。

- API: `geminidataanalytics.googleapis.com`（有効化済み）
- ロケーション: `global`
- エージェントID: `jp_trends_demo`
- リソース名: `projects/ci-ss4-develop/locations/global/dataAgents/jp_trends_demo`
- 定義ペイロード: [`jp_trends_agent.json`](./jp_trends_agent.json)

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

# 更新（PATCH。jp_trends_agent.json を編集後）
curl -X PATCH \
  "https://geminidataanalytics.googleapis.com/v1beta/projects/$PROJECT/locations/global/dataAgents/$AGENT_ID?update_mask=data_analytics_agent" \
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

レスポンスは NDJSON 風のメッセージ列（`systemMessage.text` = 思考/回答、`systemMessage.data.query.sql` =
生成SQL、`systemMessage.data.result` = 実行結果テーブル）。

## 質問例（動作確認済み）

- 直近の週で東京の人気検索ワードTop10を教えて
- 「栗きんとん」の全国平均スコアの週次推移を見せて
- 直近週で最も急上昇したワードを上昇率順に10件
```
