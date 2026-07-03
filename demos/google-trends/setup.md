# セットアップ手順書 — Google トレンド 地域ビューデモ（手動再現用）

このドキュメントだけで、ゼロから以下を**手動で再現**できる。

- BigQuery データセット `demo_google_trends`（地域ビュー用 curated テーブル2本）
- Conversational Analytics データエージェント `jp_trends_demo`（用語集・検証済みクエリ・ラベル付き）

想定環境: `gcloud` / `bq` インストール済み、プロジェクト `ci-ss4-develop`（課金有効）。
別プロジェクトで作る場合は本書中の `ci-ss4-develop` を読み替える。

関連ファイル（すべて本フォルダ `demos/google-trends/` 配下）:
- テーブル作成SQL: [`sql/create_region_view.sql`](./sql/create_region_view.sql) /
  [`sql/create_term_region_weeks.sql`](./sql/create_term_region_weeks.sql)
- データフロー（抽出・加工の設計と根拠）: [`data-flow.md`](./data-flow.md)
- エージェント定義: [`agent/jp_trends_agent.json`](./agent/jp_trends_agent.json)（[`agent/build_payload.py`](./agent/build_payload.py) で生成）
- エージェント操作コマンド集: [`agent/README.md`](./agent/README.md)
- データ辞書: [`data-dictionary.md`](./data-dictionary.md) / ダッシュボードモック: [`mock/`](./mock/)
- 旧設計（curated 2本＋dash 4本の6テーブル構成）: [`old/`](./old/)

> 以下のコマンドはリポジトリのルートから実行する前提でパスを記載している。

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

## 3. テーブル作成（2本）

```bash
# ① 主役: jp_region_weekly（重複排除・NULL除去・順位の最新週限定を済ませた地域ビュー用）
bq query --use_legacy_sql=false --location=US < demos/google-trends/sql/create_region_view.sql

# ② 補助: jp_term_region_weeks（ワード×県のランクイン週数。定番・地元ワード用）
bq query --use_legacy_sql=false --location=US < demos/google-trends/sql/create_term_region_weeks.sql
```

| テーブル | 内容 | 主なカラム |
|---|---|---|
| `jp_region_weekly` | 県×週×ワードの人気検索ワード（本物の観測のみ） | region_name, term, week, score, is_latest_week, latest_rank |
| `jp_term_region_weeks` | ワード×県のランクイン週数（県間・語間比較用） | term, region_name, ranked_weeks, share, is_local_term |

### 作り方のポイント（SQLの意図）
元データには「refresh_date の重複再掲」「81.5%を占めるNULLスコアの複製行」「98.2%が焼き付いた rank」
という3つのクセがあり、これを構築時に一括で潰している。詳細と実測根拠は [`data-flow.md`](./data-flow.md) §3。
**score はワード間・県間の大小比較に使えない**（全系列が自己ピーク=100）ため、比較用の実績指標
（ランクイン週数）を②として事前集計している。

### 確認

```bash
bq query --use_legacy_sql=false \
'SELECT COUNT(*) AS n_rows, COUNT(DISTINCT term) AS terms,
        COUNT(DISTINCT region_name) AS regions, COUNT(DISTINCT week) AS weeks
 FROM `ci-ss4-develop.demo_google_trends.jp_region_weekly`'
# 目安: n_rows≈177.6万 / terms≈779 / regions=47 / weeks≈266（週数は再実行時期により増える）

bq query --use_legacy_sql=false \
'SELECT COUNT(*) AS n_rows, COUNTIF(is_local_term) AS local_terms
 FROM `ci-ss4-develop.demo_google_trends.jp_term_region_weeks`'
# 目安: n_rows≈3.5万 / local_terms≈27
```

> データ更新: 元データは日次更新のため、上記2本のSQLを再実行（冪等）すれば最新週まで取り込める。

---

## 4. データエージェント作成（Conversational Analytics）

gcloud に専用コマンドが無いので **REST API** で作る。ロケーションは `global`。

### 4-1. 定義ファイルを用意

`demos/google-trends/agent/jp_trends_agent.json` をそのまま使う。編集して作り直す場合は
`python3 demos/google-trends/agent/build_payload.py` で再生成する。

定義に含まれるもの:
- **datasourceReferences**: `jp_region_weekly` / `jp_term_region_weeks` の2テーブル
- **systemInstruction**（YAML構造）: ペルソナ＋ルール（score の大小比較禁止、「最新」= is_latest_week、
  順位は latest_rank のみ、急上昇はスコアの伸びで近似して断る、県名の英↔日対応）、
  **tables**（同義語・47都道府県のサンプル値）、**glossaries**（地元ワード・スコア・最新週など）
- **exampleQueries**: BigQuery で**実行検証済みの golden query 9本**
- **labels**: `app=bqdemosample / theme=google-trends / country=jp / env=demo`

### 4-2. 作成（初回）

```bash
TOKEN=$(gcloud auth print-access-token)
PROJECT=ci-ss4-develop
AGENT_ID=jp_trends_demo

curl -X POST \
  "https://geminidataanalytics.googleapis.com/v1beta/projects/$PROJECT/locations/global/dataAgents?data_agent_id=$AGENT_ID" \
  -H "Authorization: Bearer $TOKEN" -H "x-goog-user-project: $PROJECT" \
  -H "Content-Type: application/json" -d @demos/google-trends/agent/jp_trends_agent.json
```

> レスポンスは長時間オペレーション（LRO）。`done:true` になれば作成完了（通常数秒）。
> 既存エージェントを更新する場合の PATCH・確認コマンドは [`agent/README.md`](./agent/README.md)。

---

## 5. 質問する（動作確認）

ステートレス `:chat` に、作成したエージェントを参照させて質問する（コマンドは [`agent/README.md`](./agent/README.md)）。

### 検証済みの質問例
- 直近の週で東京の人気検索ワードTop10を教えて
- 「栗きんとん」の全国平均スコアの月次推移を見せて
- 栗きんとんはどこの県のワード？（← ランクイン週数で回答。愛知・東京・岐阜）
- 大阪の地元ワードを教えて（← is_local_term で回答。大阪府警察・高野線・南海電鉄など）
- 大阪で最近話題になっているワードは？（← 急上昇データが無い旨を断り、4週前比のスコア差で近似）

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

> 旧設計のテーブル（`jp_top_terms` / `jp_top_rising_terms` / `dash_*`）が残っている場合の
> 個別削除は [`old/README.md`](./old/README.md) を参照。

---

## 補足: つまずきポイント

| 症状 | 原因 / 対処 |
|---|---|
| CREATE TABLE でリージョンエラー | データセットが US 以外。手順2を US で作り直す |
| discovery ドキュメントが 403 | discovery はAPIキー必須。実エンドポイント(`/dataAgents`)は access token でOK |
| chat が PERMISSION_DENIED | `x-goog-user-project` ヘッダ（=課金/クォータプロジェクト）を付ける |
| ロケーション us で 403 | データエージェントは `global` を使う |
| 県名で結果が出ない | region_name は英語表記。東京のみ 'Tokyo'、他は '<英名> Prefecture' |
| ワード間・県間の比較結果が変 | score を比較に使っている。順位（最新週）とランクイン週数を使う（[`data-flow.md`](./data-flow.md) §3） |
| 過去の順位が出ない | 仕様（latest_rank は最新週のみ。焼き付き rank の誤用防止のため過去週は NULL） |
