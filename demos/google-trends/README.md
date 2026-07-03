# デモ①：Google 検索トレンド分析（google_trends）

**ステータス：BQ・エージェント構築済み（動作検証済み）／ダッシュボードは「地域ビュー」に再設計中**

日本の週次・都道府県別の検索トレンド（人気ワード）を題材に、自然言語で質問 → 表・グラフ・SQL が返るデータエージェント。
ダッシュボードは旧4ページ構成から、**地域（県）で絞る「地域ビュー」**（osm-facilities と同じ発想）へ再設計中。

| 項目 | 値 |
|---|---|
| 元データ | `bigquery-public-data.google_trends`（US マルチリージョン） |
| curated データセット | `ci-ss4-develop.demo_google_trends` |
| テーブル（新設計） | `jp_region_weekly`（県×週×ワード・176万行。[`data-flow.md`](./data-flow.md) 参照） |
| テーブル（旧・残存） | `jp_top_terms` / `jp_top_rising_terms` / `dash_*`（未参照。旧Lookerレポートが dash_* を使っていなければ DROP 可） |
| データエージェント | `jp_trends_demo`（location: `global`。**2026-07-03 に jp_region_weekly へ移行済み・動作検証済み**） |
| テーマ | 地域×時系列のトレンド |

## このフォルダの中身
| ファイル | 役割 |
|---|---|
| [`data-flow.md`](./data-flow.md) | **データ系譜**（出所→抽出→加工→成果テーブル。生データのクセと対応も） |
| [`sql/create_region_view.sql`](./sql/create_region_view.sql) | **新設計** curated テーブル `jp_region_weekly` の作成SQL |
| [`sql/create_term_region_weeks.sql`](./sql/create_term_region_weeks.sql) | 補助テーブル（ランクイン週数・**地元ワード判定**）の作成SQL |
| [`setup.md`](./setup.md) | ゼロから手動再現する全手順（新設計ベース。認証〜BQ〜エージェント〜片付け） |
| [`agent/`](./agent/) | エージェント定義JSON・生成スクリプト・操作コマンド集（jp_region_weekly 移行済み） |
| [`data-dictionary.md`](./data-dictionary.md) | 元データのスキーマ辞書 |
| [`mock/`](./mock/) | 地域ビュー ダッシュボードの**レイアウトモック**（HTML＋P1〜P3画面キャプチャ） |
| [`looker-layout.md`](./looker-layout.md) | Looker Studio 3ページ構成のレイアウト案（設計原則・チャート定義） |
| [`looker-setup-common.md`](./looker-setup-common.md) | Looker 手動構築の共通セットアップ（データソース2本・型/既定集計・県名/month計算フィールド） |
| [`looker-page-P1-region.md`](./looker-page-P1-region.md) | P1 地域ビュー 手順書（顔ぶれ・時系列・地元ワード。期待値付き） |
| [`looker-page-P2-term.md`](./looker-page-P2-term.md) | P2 ワード深掘り 手順書（5年推移・季節性・県別週数） |
| [`looker-page-P3-national.md`](./looker-page-P3-national.md) | P3 全国サマリ 手順書（KPI・全国Top10・県ごとの1位） |
| [`old/`](./old/) | **旧設計の退避場所**（4ページ構成の Looker 手順書・dash_* 集計SQL・旧作業物） |
| [`looker-studio-capabilities.md`](../../docs/looker-studio-capabilities.md) | Looker Studio 機能リファレンス（全デモ共通・`docs/`） |

## クイックスタート
[`setup.md`](./setup.md) を上から実行。動作確認の質問例は setup.md の「5. 質問する」を参照。
