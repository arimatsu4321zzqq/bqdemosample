# Looker Studio 共通ノウハウ（全デモ共通）

各デモの具体レイアウトは `<demo>/looker-layout.md` を参照。ここには3レポートで共通して使える
参考情報（サンプル入手先・チャート一覧・作り込みポイント）をまとめる。

---

## 実サンプルの入手先（実在・流用可）

| サンプル | 内容 | URL |
|---|---|---|
| 公式 Report Gallery | Google/コミュニティの優秀レポート集。コピーしてデータ差し替え可 | https://lookerstudio.google.com/gallery |
| 公式 BQ→Looker チュートリアル | `austin_bikeshare` をLooker Studioで可視化する公式手順 | https://cloud.google.com/bigquery/docs/visualize-looker-studio |
| Coupler.io 64事例集 | 業種別ダッシュボードの実例カタログ | https://blog.coupler.io/looker-studio-dashboard-examples/ |

> 使い方: ギャラリーで気に入ったレポートを開き「コピーを作成」→データソースを今回のBQに差し替え。

---

## 試せるチャート一覧（各ページで差し替えて見比べる）
- 基本: スコアカード / 表 / ピボット表 / 折れ線(時系列) / 棒・積み上げ棒 / 円・ドーナツ
- 応用: コンボ(棒＋線) / 面グラフ / 散布図・バブル / ツリーマップ / ゲージ / ヒートマップ(ピボット＋条件付き書式)
- 地図: 地域別マップ(塗り分け) / バブルマップ / ヒートマップレイヤー(Googleマップ)
- コミュニティビジュアル: サンキー / ファネル / ワードクラウド 等（追加導入）

---

## 共通の作り込みポイント
- **配色・ロゴ**を統一して「自社プロダクト」感を出す（公開データ感を消す）
- 各ページに**自然言語Q&Aへの導線**（「AIに質問」ボタン/埋め込み）を置き、Conversational Analyticsと一体で見せる
- Looker StudioのデータソースはBQ直結。整形済みデモデータセット（自PJ）を指すとコスト・速度が安定
