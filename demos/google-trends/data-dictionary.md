# データ辞書 — 検索トレンド地域ビュー（google_trends）

## 元データ: `bigquery-public-data.google_trends`

Google検索の人気/急上昇ワード週次ランキングの公式一般公開データセット。**日次更新が継続中**。
「元データの何をどう加工したか」の全体像は [`data-flow.md`](./data-flow.md) を参照。

### テーブル群（4本・実測サイズ）

| テーブル | 行数 | サイズ | 中身 | 本デモ |
|---|---|---|---|---|
| `international_top_terms` | 2.05億 | 16.5GB | 国別→国内地域の週次**人気**ワードTop25 | **✅ 抽出元** |
| `international_top_rising_terms` | 1.94億 | 17.6GB | 同・**急上昇**（percent_gain 付き） | ❌ 不使用（JPは percent_gain が47県一律のため） |
| `top_terms` | 4,400万 | 3.2GB | 米国DMA別・人気 | 使わない |
| `top_rising_terms` | 4,400万 | 3.4GB | 米国DMA別・急上昇 | 使わない |

> DMA = Designated Market Area（米国の地域メディア圏。約210区分）。

### 使用テーブルのスキーマ（international_top_terms）

| カラム | 型 | 意味 |
|---|---|---|
| country_name / country_code | STRING | 国名・国コード（日本 = Japan / JP） |
| region_name | STRING | 国内地域名（日本は都道府県。**英語表記**。東京のみ 'Tokyo'、他は '<英名> Prefecture'） |
| region_code | STRING | 地域コード（ISO 3166-2。例 JP-13=東京） |
| term | STRING | 検索ワード（日本語） |
| week | DATE | 対象週（週の開始日） |
| rank | INTEGER | 週内順位（1〜25）。**※98.2%が最新順位の焼き付きで履歴として信用できない** |
| score | INTEGER | 人気スコア。**※各(地域×語)系列の自己ピーク=100の相対値**（語間比較・実数不可） |
| refresh_date | DATE | データ更新日。**※同一(地域,週,語)が複数 refresh_date で再掲される** |

（急上昇テーブルは上記＋ `percent_gain` INTEGER。米国DMA系は region が dma_id/dma_name になる）

※印の3点が生データの主要な「クセ」。実測値と対応は [`data-flow.md`](./data-flow.md) §3 参照。

---

## curated テーブル: `ci-ss4-develop.demo_google_trends`

### jp_region_weekly（177.6万行・約100MB）★主役（1本のみ）

日本分を抽出し、重複排除・NULL除去・順位の最新週限定を済ませた地域ビュー用テーブル。
SQL: [`sql/create_region_view.sql`](./sql/create_region_view.sql)（CREATE OR REPLACE・冪等。再実行で最新週まで更新）。

| カラム | 型 | 由来 | 意味 |
|---|---|---|---|
| region_name | STRING | 元データそのまま | 都道府県名（英語。例 Osaka Prefecture）。県ドロップダウン・表示用 |
| region_code | STRING | 元データそのまま | 地域コード（ISO 3166-2。例 JP-27=大阪）。地図用 |
| week | DATE | 元データそのまま | 対象週（週の開始日）。時系列の時間軸。2021-05-30〜最新週 |
| term | STRING | 元データそのまま | 検索ワード（日本語） |
| score | INT64 | 元データそのまま | 人気スコア（自己ピーク=100の相対値。**同一系列の時系列にのみ使う。語間・県間の大小比較は不可**） |
| is_latest_week | BOOL | **加工で付与** | 最新週フラグ。「最新・直近・今週」の絞り込みはこれ |
| latest_rank | INT64 | **加工で付与** | 県内人気順位（1が最上位・タイあり）。**最新週のみ値あり、過去週は NULL**（焼き付きrank対策） |

規模感: 47都道府県 × 266週 × 779語（重複排除・NULL除去後の本物の観測のみ）。
最新週の行数は約3,171（47県 × Top25前後）。

### jp_term_region_weeks（3.5万行）— 定番・地元ワード用の補助テーブル

ワード×都道府県の**ランクイン週数**（Top25入りした週の数＝検索量ベースで県間・語間比較が成立する実績指標）。
SQL: [`sql/create_term_region_weeks.sql`](./sql/create_term_region_weeks.sql)。

| カラム | 型 | 意味 |
|---|---|---|
| term / region_name / region_code | STRING | ワード・都道府県 |
| ranked_weeks | INT64 | その県でTop25に入った週の数（定番度・地元度の主指標） |
| total_weeks | INT64 | そのワードの全国合計ランクイン週数 |
| share | FLOAT64 | 当該県のシェア（47県均等なら≈0.02） |
| is_local_term | BOOL | **地元ワード判定**（計20週以上＋トップ県シェア30%以上でこの県がトップ。全779語中27語。例: 大阪=大阪府警察・高野線・南海電鉄、愛知=藤田医科大学病院・モゾワンダーシティ） |

### 旧テーブル（残存・廃止予定）

`jp_top_terms` / `jp_top_rising_terms` / `dash_*` 4本。エージェントは新テーブルへ移行済みで未参照。
旧Lookerレポートを捨てる判断をしたらDROP可（[`old/README.md`](./old/README.md) 参照）。

---

## データの注意点（デモで説明が必要なもの）

1. **score の大小比較は一切できない**: 各「県×ワード」系列の自己ピークを100とする相対値
   （全35,489系列がピーク=100と実測確認済み）。語間はもちろん、**同一ワードの県間比較も不可**。
   読むのは山の位置（時期）のみ。ワード間・県間の比較は latest_rank（最新週）と
   「ランクイン週数・県数」で行う（例: 栗きんとん=愛知251週・東京238週・岐阜190週で中京圏の地元ワード）。
2. **順位は最新週のみ**: 過去週の latest_rank は設計上 NULL。「去年のランキング」は出せない
   （元データの rank が信頼できないため。代替は score の大小）。
3. **急上昇の専用データなし**: 急上昇テーブルは県別に差が出ないため不採用。
   「話題・バズ」は score の4週前比で近似する（エージェントは近似であることを自分で説明する）。
4. **鮮度**: 元データは日次更新だが、最新週の反映は2〜3週遅れ程度。curated の更新は SQL 再実行。
5. **県名は英語表記**: region_name は 'Tokyo' / '<英名> Prefecture'。日本語対応はエージェントの
   用語集で吸収済み。Looker では region_code（JP-xx）を地域型に使うのが確実。
