# デモ②：地域施設マップ（osm-facilities）

**ステータス：BQ・エージェント構築済み（動作検証済み）／ Looker ダッシュボードは手順書のみ（未構築）**

OpenStreetMap 由来の全国の主要施設（病院・クリニック・学校・公民館・図書館・消防署）を題材に、
**自治体で絞って地域の特徴を見る**デモ。自然言語で「白川町で避難所になりそうな施設は？」と聞ける。

| 項目 | 値 |
|---|---|
| 元データ | `bigquery-public-data.geo_openstreetmap`（US マルチリージョン・**2021-11時点のスナップショット**） |
| curated データセット | `ci-ss4-develop.demo_osm_facilities` |
| テーブル | `jp_poi_facilities`（施設8.8万件） / `jp_admin_boundaries`（1,742市区町村） / `dash_muni_category`（集計） |
| データエージェント | `jp_facilities_demo`（location: `global`） |
| テーマ | 自治体切替×施設分布（地図）。google-trends（時系列）と対照的な「分布・比較」型 |

## このフォルダの中身

| ファイル | 役割 |
|---|---|
| [`setup.md`](./setup.md) | ゼロから手動再現する全手順（認証〜作成〜質問〜片付け・コスト実測値付き） |
| [`sql/create_osm_facilities_demo.sql`](./sql/create_osm_facilities_demo.sql) | curated テーブル3本の作成SQL（全国版） |
| [`agent/`](./agent/) | エージェント定義JSON・生成スクリプト・操作コマンド集 |
| [`data-flow.md`](./data-flow.md) | **データフロー全体図**（公式データセットの何を抽出し、どう加工・集計して3テーブルを作ったか） |
| [`data-dictionary.md`](./data-dictionary.md) | 元データ（OSM 16テーブル・タグ方式）と curated テーブルのスキーマ辞書 |
| [`looker-layout.md`](./looker-layout.md) | Looker Studio 3ページ構成のレイアウト案（再現可否は公式Docで検証済み） |
| [`looker-setup-common.md`](./looker-setup-common.md) | Looker 手動構築の共通セットアップ（データソース・型・カテゴリ7色・ページ構成） |
| [`looker-page-P1-map.md`](./looker-page-P1-map.md) | P1 施設マップ 手順書（バブルマップ・グループ化・期待値付き） |
| [`looker-page-P2-compare.md`](./looker-page-P2-compare.md) | P2 自治体比較 手順書（ランキング・ピボット） |
| [`looker-page-P3-list.md`](./looker-page-P3-list.md) | P3 施設リスト 手順書（検索・明細） |
| [`mock/`](./mock/) | ダッシュボードの**レイアウトモック**（HTML＋P1〜P3画面キャプチャ） |

## クイックスタート

[`setup.md`](./setup.md) を上から実行。動作確認の質問例は setup.md の「4. データエージェント」を参照。

## このデモの見せ場

1. **自治体ドロップダウン1つで全部が切り替わる**地図ダッシュボード（都道府県→自治体の2段絞り込み）
2. 「避難所になりそうな施設は？」→ 用語集が「学校＋公民館・集会所」に解釈して回答（防災文脈）
3. 自治体間比較（「高山市と飛騨市で学校の数を比べて」「東京都で公民館が多い自治体Top10」）

## 制約（デモで正直に言うこと）

- データ時点は **2021年11月**（OSM公式データセットの更新が停止しているため）。時点を明示して使う。
- OSMは有志作成のため**自治体により登録密度に差**がある（件数=実数ではない）。
- 時系列なし（推移グラフは作れない）。トレンドは google-trends デモが担当。
