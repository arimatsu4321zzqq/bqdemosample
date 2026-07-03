# old/ — 旧設計（4ページ・dash_* テーブル前提）の退避場所

google-trends デモは「地域ビュー」への再設計（[`../data-flow.md`](../data-flow.md) /
`../sql/create_region_view.sql` / 新テーブル `jp_region_weekly`）に移行中。
ここには**旧設計を前提にした成果物**を退避してある（2026-07-03移動）。

| ファイル | 内容 | 旧前提 |
|---|---|---|
| `looker-setup-common.md` | 旧・共通セットアップ | データソース3本（dash_* 3テーブル） |
| `looker-layout.md` | 旧・レイアウト案 | 4ページ構成 |
| `looker-page-P1〜P4-*.md` | 旧・ページ別手順書 | dash_jp_terms_weekly / dash_jp_region_latest / dash_jp_rising_recent |
| `create_dashboard_tables.sql` | 旧・ダッシュボード集計テーブル作成SQL | dash_* 4テーブル（rank焼き付き・NULL複製の問題を内包） |
| `create_google_trends_demo.sql` | 旧・curated テーブル2本の作成SQL | jp_top_terms / jp_top_rising_terms（NULL複製行が残存する旧仕様） |
| `tmp20260702/` | 旧・一時作業物 | looker-quickbuild-3h.md（**内容に誤りあり・参照非推奨**）/ 構築時のスクショ / 作業レポート |

## 注意（BQ側の旧テーブルはまだ生きている）

- 旧テーブル `jp_top_terms` / `jp_top_rising_terms` / `dash_*` は BQ に**残存**（データ系譜ドキュメントで DROP 候補）。
- データエージェント `jp_trends_demo` は **2026-07-03 に `jp_region_weekly` へ移行済み**。
  エージェント起因の DROP 制約は解消した。
- 残る制約は1つ: **旧テーブル（dash_*）で構築済みの Looker レポートがある場合、DROP するとそのレポートが壊れる**。
  旧レポートを捨てる判断をしたら `bq rm -f -t` で6本（jp_top_terms / jp_top_rising_terms /
  dash_jp_terms_weekly / dash_jp_region_latest / dash_jp_rising_recent / dash_jp_rising_weekly）を削除してよい。
