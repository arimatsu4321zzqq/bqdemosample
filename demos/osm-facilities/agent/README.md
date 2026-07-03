# 地域施設マップ分析エージェント (Conversational Analytics / Gemini Data Analytics)

`ci-ss4-develop.demo_osm_facilities` の2テーブル（`jp_poi_facilities` / `dash_muni_category`）を
対象にした自然言語データエージェント。

- API: `geminidataanalytics.googleapis.com`（有効化済み）
- ロケーション: `global`
- エージェントID: `jp_facilities_demo`
- リソース名: `projects/ci-ss4-develop/locations/global/dataAgents/jp_facilities_demo`
- 定義ペイロード: [`jp_facilities_agent.json`](./jp_facilities_agent.json)（[`build_payload.py`](./build_payload.py) で生成）

## 作成 / 更新

```bash
TOKEN=$(gcloud auth print-access-token)
PROJECT=ci-ss4-develop
AGENT_ID=jp_facilities_demo

# 作成（初回）
curl -X POST \
  "https://geminidataanalytics.googleapis.com/v1beta/projects/$PROJECT/locations/global/dataAgents?data_agent_id=$AGENT_ID" \
  -H "Authorization: Bearer $TOKEN" -H "x-goog-user-project: $PROJECT" \
  -H "Content-Type: application/json" -d @jp_facilities_agent.json

# 更新（build_payload.py で JSON を再生成してから PATCH）
curl -X PATCH \
  "https://geminidataanalytics.googleapis.com/v1beta/projects/$PROJECT/locations/global/dataAgents/$AGENT_ID?update_mask=data_analytics_agent,labels" \
  -H "Authorization: Bearer $TOKEN" -H "x-goog-user-project: $PROJECT" \
  -H "Content-Type: application/json" -d @jp_facilities_agent.json
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
    "messages": [{"userMessage": {"text": "白川町で避難所になりそうな施設を教えて"}}],
    "dataAgentContext": {"dataAgent": "projects/'$PROJECT'/locations/global/dataAgents/jp_facilities_demo"}
  }'
```

レスポンスは NDJSON 風のメッセージ列（`systemMessage.text` = 思考/回答、`systemMessage.data.query` =
生成SQL、`systemMessage.data.result` = 実行結果テーブル）。

## 質問例（動作確認済み）

- 白川町で避難所になりそうな施設を教えて（← 用語集で「学校＋公民館・集会所」に解決）
- 岐阜市の病院を一覧で見せて
- 高山市と飛騨市で学校の数を比べて
- 東京都で公民館・集会所が多い自治体Top10
- 都道府県別の病院数ランキングTop10

## 定義に含まれるもの

- **datasourceReferences**: `jp_poi_facilities`（施設明細）/ `dash_muni_category`（自治体×カテゴリ集計）
- **systemInstruction**（YAML構造）: ペルソナ＋ルール（データ時点2021-11の注記、避難所候補=学校＋公民館、
  政令市は市単位、OSMの登録密度差の注意など）、**tables**（同義語・サンプル値: 47都道府県）、**glossaries**
- **exampleQueries**: BigQuery で実行検証済みの golden query 8本
- **labels**: `app=bqdemosample / theme=osm-facilities / country=jp / env=demo`
