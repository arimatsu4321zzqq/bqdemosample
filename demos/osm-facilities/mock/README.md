# mock/ — 地域施設マップ ダッシュボードのレイアウトモック

Looker Studio で構築する「地域施設マップ」（3ページ構成）のレイアウトモックと各画面キャプチャ。
数値は「実測」表記のものは BQ（`demo_osm_facilities`）の実測値、それ以外はモック値。
ページ構成は [`../looker-layout.md`](../looker-layout.md) と各 `looker-page-P*.md` に対応する。

| ファイル | 内容 |
|---|---|
| [`osm-dashboard-mock.html`](./osm-dashboard-mock.html) | モック本体（ブラウザで開く。上部タブでP1〜P3切替、チャートはホバーで値表示、ダークモード対応） |
| [`P1.png`](./P1.png) | **P1 施設マップ** — 都道府県▼→自治体▼の2段絞り込み／KPI×4（岐阜市: 総数247・病院40・学校123・公民館40=実測）／バブルマップ（色=カテゴリ）／カテゴリ内訳／県内比較（自治体▼の適用対象外）／施設一覧 |
| [`P2.png`](./P2.png) | **P2 自治体比較** — KPI（岐阜県42自治体・1,452施設／全国87,745=実測）／県内Top10・全国Top5ランキング（実測）／自治体×カテゴリのピボット・ヒートマップ |
| [`P3.png`](./P3.png) | **P3 施設リスト** — 施設名検索（「小学校」→20,687件=実測）／全国明細テーブル（白川町の小学校5行は実データ）／ページング・CSVエクスポート |

## 設計上の約束（モックに織り込み済み）

- **データ時点 2021-11 を常時表示**（OSM公式データセットは更新停止のため）
- 避難所タグ（全国354件）は主役にせず「避難所になり得る施設（学校・公民館）」で見せる
- 全国ランキングは「OSM登録数＝地図の充実度も反映」という注記ごと見せる（仙台市3位の理由）
- カテゴリ6色はディメンション値に固定（`../looker-setup-common.md` STEP3 の色と一致）

## キャプチャの再生成方法

```bash
cd <リポジトリルート>
SRC=demos/osm-facilities/mock/osm-dashboard-mock.html
chromium-browser --headless=new --disable-gpu --hide-scrollbars \
  --window-size=1280,1760 --screenshot=demos/osm-facilities/mock/P1.png "file://$PWD/$SRC"
# P2/P3 は初期表示タブを差し替えた一時ファイルを撮る（google-trends の mock/README.md と同じ手順）
```

> 注意: snap 版 Chromium は `/tmp` 配下を開けない。一時ファイルはリポジトリ内に置いて撮影後に削除する。
