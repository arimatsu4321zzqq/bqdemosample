# セットアップ手順書 — Google トレンド 自然言語分析デモ（手動再現用）

このドキュメントだけで、ゼロから以下を**手動で再現**できる。

- BigQuery データセット `demo_google_trends`（日本の検索トレンド curated テーブル2本）
- Conversational Analytics データエージェント `jp_trends_demo`（用語集・検証済みクエリ・ラベル付き）

想定環境: `gcloud` / `bq` インストール済み、プロジェクト `ci-ss4-develop`（課金有効）。
別プロジェクトで作る場合は本書中の `ci-ss4-develop` を読み替える。

関連ファイル:
- テーブル作成SQL: [`../sql/create_google_trends_demo.sql`](../sql/create_google_trends_demo.sql)
- エージェント定義: [`../agent/jp_trends_agent.json`](../agent/jp_trends_agent.json)（[`build_payload.py`](../agent/build_payload.py) で生成）
- エージェント操作コマンド集: [`../agent/README.md`](../agent/README.md)
- データ辞書: [`data-dictionary.md`](./data-dictionary.md)

---

## 0. 前提・認証

```bash
# ログイン（ブラウザが開く。このマシンで未認証なら実行）
gcloud auth login
gcloud auth application-default login   # ADC（ライブラリ/一部APIで使用）

# プロジェクト設定
gcloud config set project ci-ss4-develop

# 確認
gcloud auth list
gcloud config get-value project
```

## 1. API 有効化

```bash
gcloud services enable \
  bigquery.googleapis.com \
  geminidataanalytics.googleapis.com \
  --project=ci-ss4-develop

# 確認
gcloud services list --enabled --project=ci-ss4-develop \
  | grep -E "bigquery|geminidataanalytics"
```

> `geminidataanalytics.googleapis.com` = Conversational Analytics（Gemini Data Analytics）本体。

---

## 2. データセット作成

元データ `bigquery-public-data.google_trends` は **US マルチリージョン**のため、
データセットも **US** で作る（別リージョンだと CREATE 時にエラー）。

```bash
bq --location=US mk --dataset \
  --description "Google Trends デモ用（bqdemosample）" \
  ci-ss4-develop:demo_google_trends
```

> 白川町案件（`BQ_TEST_shirakawa_tourism`）とは**別データセット**にして分離する。

## 3. テーブル作成（人気・急上昇の2本）

`sql/create_google_trends_demo.sql` を実行するだけ。カラム説明も `OPTIONS(description=...)` で内包済み。

```bash
bq query --use_legacy_sql=false --location=US < sql/create_google_trends_demo.sql
```

作られるもの:

| テーブル | 内容 | 主なカラム |
|---|---|---|
| `jp_top_terms` | 日本の週次・都道府県別**人気**検索ワード | region_name, term, week, rank, score |
| `jp_top_rising_terms` | 日本の週次・都道府県別**急上昇**ワード | 上記 + percent_gain（上昇率） |

### 作り方のポイント（SQLの意図）
- 日本のみ（`country_code='JP'`）を抽出。
- google_trends は refresh_date スナップショットごとに過去週を再掲するため、
  `(region_name, week, term)` 単位で**最新 refresh_date のスコアを採用して重複排除**。
  → これで「語彙数」と「時系列の長さ（約5年・266週）」を両立。

### 確認

```bash
bq ls ci-ss4-develop:demo_google_trends
bq query --use_legacy_sql=false \
'SELECT COUNT(*) AS rows, COUNT(DISTINCT term) AS terms,
        COUNT(DISTINCT region_name) AS regions, COUNT(DISTINCT week) AS weeks
 FROM `ci-ss4-develop.demo_google_trends.jp_top_terms`'
# 目安: rows≈958万 / terms≈779 / regions=47 / weeks≈266
```

---

## 4. データエージェント作成（Conversational Analytics）

gcloud に専用コマンドが無いので **REST API** で作る。ロケーションは `global`。

### 4-1. 定義ファイルを用意

`agent/jp_trends_agent.json` をそのまま使う。編集して作り直す場合は
`python3 agent/build_payload.py` で再生成する（用語集・県名・検証済みクエリを一元管理）。

定義に含まれるもの:
- **datasourceReferences**: 上記2テーブルへの紐付け
- **systemInstruction**（YAML構造）: ペルソナ＋ルール、**tables**（各カラムの同義語・サンプル値）、
  **glossaries**（用語集: 人気/急上昇/スコア/上昇率、県名の英↔日対応・東京の特例など）
- **exampleQueries**: BigQuery で**実行検証済みの golden query 8本**
- **labels**: `app=bqdemosample / theme=google-trends / country=jp / env=demo`

### 4-2. 作成（初回）

```bash
TOKEN=$(gcloud auth print-access-token)
PROJECT=ci-ss4-develop
AGENT_ID=jp_trends_demo

curl -X POST \
  "https://geminidataanalytics.googleapis.com/v1beta/projects/$PROJECT/locations/global/dataAgents?data_agent_id=$AGENT_ID" \
  -H "Authorization: Bearer $TOKEN" -H "x-goog-user-project: $PROJECT" \
  -H "Content-Type: application/json" -d @agent/jp_trends_agent.json
```

> レスポンスは長時間オペレーション（LRO）。`done:true` になれば作成完了（通常数秒）。

### 4-3. 更新（用語集やクエリを直したとき）

`update_mask` に更新対象を指定して PATCH。

```bash
curl -X PATCH \
  "https://geminidataanalytics.googleapis.com/v1beta/projects/$PROJECT/locations/global/dataAgents/$AGENT_ID?update_mask=data_analytics_agent,labels" \
  -H "Authorization: Bearer $TOKEN" -H "x-goog-user-project: $PROJECT" \
  -H "Content-Type: application/json" -d @agent/jp_trends_agent.json
```

### 4-4. 確認

```bash
# 一覧
curl -s "https://geminidataanalytics.googleapis.com/v1beta/projects/$PROJECT/locations/global/dataAgents" \
  -H "Authorization: Bearer $TOKEN" -H "x-goog-user-project: $PROJECT"

# 単体（ラベル・用語集・クエリの反映確認）
curl -s "https://geminidataanalytics.googleapis.com/v1beta/projects/$PROJECT/locations/global/dataAgents/$AGENT_ID" \
  -H "Authorization: Bearer $TOKEN" -H "x-goog-user-project: $PROJECT"
```

---

## 5. 質問する（動作確認）

ステートレス `:chat` に、作成したエージェントを参照させて質問する。

```bash
TOKEN=$(gcloud auth print-access-token)
PROJECT=ci-ss4-develop
curl -s -X POST \
  "https://geminidataanalytics.googleapis.com/v1beta/projects/$PROJECT/locations/global:chat" \
  -H "Authorization: Bearer $TOKEN" -H "x-goog-user-project: $PROJECT" \
  -H "Content-Type: application/json" -d '{
    "parent": "projects/'$PROJECT'/locations/global",
    "messages": [{"userMessage": {"text": "直近の週で東京の人気検索ワードTop5を教えて"}}],
    "dataAgentContext": {"dataAgent": "projects/'$PROJECT'/locations/global/dataAgents/jp_trends_demo"}
  }'
```

レスポンスは NDJSON 風のメッセージ列:
- `systemMessage.text`（`textType:THOUGHT` は思考、その他は回答本文）
- `systemMessage.data.query.sql` = 生成された SQL
- `systemMessage.data.result` = 実行結果テーブル（schema + data）

### 検証済みの質問例
- 直近の週で東京の人気検索ワードTop10を教えて
- 「栗きんとん」の全国平均スコアの月次推移を見せて
- 直近週で最も急上昇したワードを上昇率順に10件
- 大阪で直近に話題になった（急上昇した）ワードをTop5で（← 日本語県名・「話題」を用語集で解決）

---

## 6. 後片付け（作り直したいとき）

```bash
TOKEN=$(gcloud auth print-access-token); PROJECT=ci-ss4-develop
# エージェント削除
curl -X DELETE \
  "https://geminidataanalytics.googleapis.com/v1beta/projects/$PROJECT/locations/global/dataAgents/jp_trends_demo" \
  -H "Authorization: Bearer $TOKEN" -H "x-goog-user-project: $PROJECT"
# データセットごと削除（テーブル含む）
bq rm -r -f -d ci-ss4-develop:demo_google_trends
```

---

## 補足: つまずきポイント

| 症状 | 原因 / 対処 |
|---|---|
| CREATE TABLE でリージョンエラー | データセットが US 以外。手順2を US で作り直す |
| discovery ドキュメントが 403 | discovery はAPIキー必須。実エンドポイント(`/dataAgents`)は access token でOK |
| chat が PERMISSION_DENIED | `x-goog-user-project` ヘッダ（=課金/クォータプロジェクト）を付ける |
| ロケーション us で 403 | データエージェントは `global` を使う |
| 県名で結果が出ない | region_name は英語表記。東京のみ 'Tokyo'、他は '<英名> Prefecture' |
