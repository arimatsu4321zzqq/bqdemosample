# デモ①：Google 検索トレンド分析（google_trends）

**ステータス：構築済み（sql + agent 実装、動作検証済み）**

日本の週次・都道府県別の検索トレンド（人気/急上昇ワード）を題材に、自然言語で質問 → 表・グラフ・SQL が返るデータエージェント。

| 項目 | 値 |
|---|---|
| 元データ | `bigquery-public-data.google_trends`（US マルチリージョン） |
| curated データセット | `ci-ss4-develop.demo_google_trends` |
| テーブル | `jp_top_terms`（人気） / `jp_top_rising_terms`（急上昇） |
| データエージェント | `jp_trends_demo`（location: `global`） |
| テーマ | 地域×時系列のトレンド |

## このフォルダの中身
| ファイル | 役割 |
|---|---|
| [`setup.md`](./setup.md) | ゼロから手動再現する全手順（認証〜作成〜質問〜片付け） |
| [`sql/create_google_trends_demo.sql`](./sql/create_google_trends_demo.sql) | curated テーブル2本の作成SQL |
| [`sql/create_dashboard_tables.sql`](./sql/create_dashboard_tables.sql) | Looker Studio 用の集計テーブル |
| [`agent/`](./agent/) | エージェント定義JSON・生成スクリプト・操作コマンド集 |
| [`data-dictionary.md`](./data-dictionary.md) | 元データのスキーマ辞書 |
| [`looker-layout.md`](./looker-layout.md) | Looker Studio レポートのレイアウト案 |
| [`looker-setup-common.md`](./looker-setup-common.md) | Looker ダッシュボード手動構築の共通セットアップ（P1〜P4の土台） |
| [`looker-studio-capabilities.md`](../../docs/looker-studio-capabilities.md) | Looker Studio 機能リファレンス（全デモ共通・`docs/`） |
| `looker-page-P1〜P4-*.md` | Looker 各ページ手順書（P1概況 / P2地域 / P3ワード / P4急上昇） |

## クイックスタート
[`setup.md`](./setup.md) を上から実行。動作確認の質問例は setup.md の「5. 質問する」を参照。
