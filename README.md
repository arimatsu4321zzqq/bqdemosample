# bqdemosample — BigQuery 自然言語分析デモ

ドコモ向け横展用の「売れるツール」デモ環境。BigQuery のオープンデータ（public datasets）を題材に、
**複数のレポート**と、**自然言語で質問 → 回答（表・グラフ・SQL）が返るデータエージェント**を構築する。

> 白川町（観光DB / Looker Studio 移行）とは別案件。リポジトリ・GCPリソースとも分離する。

## ゴール

1. BQ public データで「似たレポート」を複数（地域・テーマ違いで横展の説得力を出す）
2. 自然言語で質問できるデモ環境（チャットUI）
3. ドコモと共同提案できる、再現性のある“プロダクトの種”にする

## 技術方針（調査結果に基づく本命）

中核は **BigQuery Conversational Analytics（Gemini Data Analytics API）** の **データエージェント**。

- `geminidataanalytics.googleapis.com` 経由でデータエージェントを作成
- NL2Query エンジンが自然言語 → BigQuery 用 SQL に変換、スキーマにグラウンディング
- Python コードインタープリタで高度な集計・統計も実行
- 回答は **テキスト / 表 / グラフ**で返る。ステートフル会話（フォローアップ質問）対応
- 配信先: **Data Studio（Preview）/ Gemini Enterprise（Preview）/ API（GA）でカスタムUIに組込**

公式チュートリアルが `google_trends`（国際トレンド）/ `austin_bikeshare` など **BQ public データで
データエージェントを作る手順**を提供しており、本デモの「BQサンプルデータ＋自然言語回答」と完全に一致する。

### 想定アーキテクチャ

```
[ BQ public datasets ]
        │
        ▼
[ Conversational Analytics / Data Agent ]  ← NL2Query + Pythonコードインタープリタ
        │
        ├─►  カスタムUI（API GA / React チャット）   ← デモの“自社ツール”面
        └─►  Looker Studio レポート（複数）          ← 横展の説得力
```

> カスタムUIを作り込む場合は既存スタック（ADK / FastAPI / React）と一致させられる。
> 第一弾はまず純正データエージェント＋少数の固定レポートで「動くデモ」を最短で出す。

## デモ一覧（`demos/` 配下・1テーマ1フォルダで自己完結）

採用したデモだけフォルダ化し、そのデモ単体で再現・受け渡しできる標準構成
（README / setup / data-flow / data-dictionary / sql / agent / mock / looker手順書）を持つ。
**構成の詳細は [`demos/README.md`](demos/README.md)**。
Looker Studio 共通ノウハウは [`docs/looker-common.md`](docs/looker-common.md)。
お客様アカウントへの会話分析エージェント共有（IAM）手順は [`docs/access-sharing-setup.md`](docs/access-sharing-setup.md)。

| # | デモ | テーマ | 元データ | ステータス |
|---|---|---|---|---|
| ① | [google-trends](demos/google-trends/) | 検索トレンド地域ビュー（県で絞る×時系列） | `google_trends` | ✅ BQ・エージェント構築済み／Looker は手順書・モックまで |
| ② | [osm-facilities](demos/osm-facilities/) | 地域施設マップ（市区町村で絞る×分布) | `geo_openstreetmap` | ✅ BQ・エージェント構築済み／Looker は手順書・モックまで |

> 題材を「地域で絞って傾向・特徴を見る」観点でどう選んだかの経緯は
> [`demos/demo-selection-rationale.md`](demos/demo-selection-rationale.md) に記録。

### 候補一覧（採用状況つき）

検討した全候補と採用/保留の理由は [`demos/candidate-overview.md`](demos/candidate-overview.md) に集約。

- 🔶 `ghcn_d` — 日本の日別気象（長期気候トレンド・豪雨/豪雪分析）: 第3デモ最有力（実データ検証済み）
- ⬜ `thelook_ecommerce` / `austin_bikeshare` — 保留

各候補の調査詳細・データ辞書・設計案は [`demos/candidate-datasets.md`](demos/candidate-datasets.md) に集約。

## データ（第一弾は BQ public のみ・ロード作業なし）

候補（公式チュートリアル実績あり / 即利用可）:

- `bigquery-public-data.google_trends` — 検索トレンド（地域・時系列の比較が映える）
- `bigquery-public-data.austin_bikeshare` — 移動・利用ログ（人流デモの代替になりやすい）
- `bigquery-public-data.noaa_gsod` — 気象（地域×気象の掛け合わせ）
- `bigquery-public-data.geo_openstreetmap` — POI

将来: 日本の観光統計（観光庁 宿泊旅行統計 / e-Stat）等を BQ にロードし「地域観光×人流」テーマへ寄せる。

## スコープ（段階）

- **Phase 0 — 環境準備**: GCPプロジェクト/課金、API有効化（BigQuery, Gemini Data Analytics / Conversational Analytics）、認証
- **Phase 1 — 最短デモ**: public データ1〜2本でデータエージェント作成、質問テンプレ5〜10個で確実に答える状態に
- **Phase 2 — 複数レポート**: テーマ違いで Looker Studio レポートを2〜3本（白川町の構築知見を流用）
- **Phase 3 — カスタムUI（任意）**: API(GA) を React チャットUIに組込み“自社ツール”として見せる
- **Phase 4 — 日本データ化（任意）**: 観光・人流系データをロードしドコモ提案テーマに最適化

> デモは自由質問を全開にせず「半レール式（質問テンプレ中心）」で事故を防ぐ。

## 前提・必要なもの（ユーザー側で要確認）

- [ ] 利用する **GCPプロジェクトID**（課金有効）
- [ ] `gcloud` 認証（このマシンで `gcloud auth login` 済みか）
- [ ] Conversational Analytics / Gemini Data Analytics API の有効化可否（組織ポリシー）
- [ ] デモを見せる相手・刺さる業種（将来テーマ最適化用）

## 参考リンク

- Conversational analytics overview — https://docs.cloud.google.com/bigquery/docs/conversational-analytics
- Build data agents with Conversational Analytics API — https://cloud.google.com/blog/products/data-analytics/build-data-agents-with-conversational-analytics-api
- Create data agents — https://docs.cloud.google.com/bigquery/docs/create-data-agents
- Codelab: Intro to Conversational Analytics in BigQuery — https://codelabs.developers.google.com/ca-in-bigquery
- Codelab: Intro to the Conversational Analytics API — https://codelabs.developers.google.com/ca-api-bigquery
