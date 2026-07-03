# セットアップ手順書 — OSM 地域施設マップデモ（手動再現用）

このドキュメントだけで、ゼロから以下を**手動で再現**できる。

- BigQuery データセット `demo_osm_facilities`（全国の施設POI・自治体境界・集計の3テーブル）
- Conversational Analytics データエージェント `jp_facilities_demo`（用語集・検証済みクエリ・ラベル付き）

想定環境: `gcloud` / `bq` インストール済み、プロジェクト `ci-ss4-develop`（課金有効）。
別プロジェクトで作る場合は本書中の `ci-ss4-develop` を読み替える。

関連ファイル（すべて本フォルダ `demos/osm-facilities/` 配下）:
- テーブル作成SQL: [`sql/create_osm_facilities_demo.sql`](./sql/create_osm_facilities_demo.sql)
- エージェント定義: [`agent/jp_facilities_agent.json`](./agent/jp_facilities_agent.json)（[`agent/build_payload.py`](./agent/build_payload.py) で生成）
- エージェント操作コマンド集: [`agent/README.md`](./agent/README.md)
- データ辞書: [`data-dictionary.md`](./data-dictionary.md) / Looker案: [`looker-layout.md`](./looker-layout.md)

> 以下のコマンドはリポジトリのルートから実行する前提でパスを記載している。

---

## 0. 前提・認証

```bash
gcloud auth login
gcloud auth application-default login   # ADC（ライブラリ/一部APIで使用）
gcloud config set project ci-ss4-develop
```

## 1. API 有効化

```bash
gcloud services enable \
  bigquery.googleapis.com \
  geminidataanalytics.googleapis.com \
  --project=ci-ss4-develop
```

---

## 2. データセット作成

元データ `bigquery-public-data.geo_openstreetmap` は **US マルチリージョン**のため US で作る。

```bash
bq --location=US mk --dataset \
  --description "OSM 地域施設マップ デモ用（bqdemosample）" \
  ci-ss4-develop:demo_osm_facilities
```

## 3. テーブル作成（境界 → 施設POI → 集計の3本）

`sql/create_osm_facilities_demo.sql` を上から実行する。**文の順番に依存**
（施設POIが境界テーブルを参照）するため、1文ずつ実行するのが安全。

```bash
bq query --use_legacy_sql=false --location=US < demos/osm-facilities/sql/create_osm_facilities_demo.sql
```

作られるもの:

| テーブル | 内容 | 行数目安 |
|---|---|---|
| `jp_admin_boundaries` | 全国の市区町村境界ポリゴン（都道府県名付き） | 1,742 |
| `jp_poi_facilities` | 全国の主要施設POI（7カテゴリ・緯度経度・自治体名付き） | 87,745 |
| `dash_muni_category` | 自治体×カテゴリの施設数サマリ | 約7,600 |

### コストの注意（重要）
- dry_run の見積もりは**クラスタ枝刈りを反映しないため満額表示**される
  （境界: 見積184GB → 実処理16.4GB / POI: 見積344GB → 実処理17.1GB。2026-07実測）。
- 構築一回の実処理は**合計 約35GB ≒ $0.25 以下**。作り直しても安い。
- タグのみのフィルタ（bbox なし）は枝刈りが効かず満額になるので、必ず bbox を付ける。

### 確認

```bash
bq query --use_legacy_sql=false '
SELECT COUNT(DISTINCT pref_name) AS prefs, COUNT(DISTINCT muni_name) AS munis, COUNT(*) AS pois
FROM `ci-ss4-develop.demo_osm_facilities.jp_poi_facilities`'
# 目安: prefs=47 / munis≈1,684 / pois≈87,745

bq query --use_legacy_sql=false '
SELECT category, COUNT(*) AS n
FROM `ci-ss4-develop.demo_osm_facilities.jp_poi_facilities`
GROUP BY category ORDER BY n DESC'
# 目安: 学校45,188 / 公民館・集会所15,124 / 病院10,462 / クリニック7,454 / 消防署5,721 / 図書館3,442 / 避難場所354
```

---

## 4. データエージェント作成（Conversational Analytics）

gcloud に専用コマンドが無いので **REST API** で作る。ロケーションは `global`。

### 4-1. 定義ファイルを用意

`demos/osm-facilities/agent/jp_facilities_agent.json` をそのまま使う。編集する場合は
`python3 demos/osm-facilities/agent/build_payload.py` で再生成する
（用語集・47都道府県サンプル値・検証済みクエリを一元管理）。

### 4-2. 作成（初回）

```bash
TOKEN=$(gcloud auth print-access-token)
PROJECT=ci-ss4-develop
AGENT_ID=jp_facilities_demo

curl -X POST \
  "https://geminidataanalytics.googleapis.com/v1beta/projects/$PROJECT/locations/global/dataAgents?data_agent_id=$AGENT_ID" \
  -H "Authorization: Bearer $TOKEN" -H "x-goog-user-project: $PROJECT" \
  -H "Content-Type: application/json" -d @demos/osm-facilities/agent/jp_facilities_agent.json
```

> レスポンスは長時間オペレーション（LRO）。通常数秒で作成完了。

### 4-3. 更新 / 確認 / 質問

[`agent/README.md`](./agent/README.md) のコマンド集を参照（PATCH・一覧・:chat の例あり）。

### 検証済みの質問例

- 白川町で避難所になりそうな施設を教えて（用語集で「学校＋公民館・集会所」に解決されることを確認済み）
- 岐阜市の病院を一覧で見せて
- 高山市と飛騨市で学校の数を比べて
- 東京都で公民館・集会所が多い自治体Top10

---

## 5. Looker Studio ダッシュボード

[`looker-layout.md`](./looker-layout.md) の3ページ構成を手動構築する。
データソースは `jp_poi_facilities`（マップ・明細）と `dash_muni_category`（比較）の直結で足りる
（8.8万行・十数MBのため Extract 不要）。

---

## 6. 後片付け（作り直したいとき）

```bash
TOKEN=$(gcloud auth print-access-token); PROJECT=ci-ss4-develop
# エージェント削除
curl -X DELETE \
  "https://geminidataanalytics.googleapis.com/v1beta/projects/$PROJECT/locations/global/dataAgents/jp_facilities_demo" \
  -H "Authorization: Bearer $TOKEN" -H "x-goog-user-project: $PROJECT"
# データセットごと削除（テーブル含む）
bq rm -r -f -d ci-ss4-develop:demo_osm_facilities
```

---

## 補足: つまずきポイント

| 症状 | 原因 / 対処 |
|---|---|
| dry_run が200GB超と出て怖い | クラスタ枝刈り未反映の満額表示。bbox 付きなら実処理は数〜20GB（実測済み） |
| CREATE OR REPLACE でクラスタ指定エラー | 既存テーブルとクラスタ列が違うと置換不可。`bq rm -f -t` で消してから再実行 |
| 特定の自治体が境界から漏れる | 重心判定だと川沿い境界（例: 笠松町）が漏れる。本SQLは**面積過半の重なり**判定にしてあるので変更しないこと |
| bbox に隣国が入るのが心配 | 都道府県（admin_level=4 の 都/道/府/県 名）との空間結合で日本分のみ残る設計 |
| 避難所が全然出てこない | OSMの避難場所タグは全国354件と疎。「避難所になり得る施設（学校＋公民館）」で見せる（エージェントの用語集に設定済み） |
| 政令市の区で絞れない | admin_level=7 は市単位（東京23区のみ区単位で存在） |
