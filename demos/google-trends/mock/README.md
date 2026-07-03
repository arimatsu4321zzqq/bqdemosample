# mock/ — 地域ビュー ダッシュボードのレイアウトモック

Looker Studio で構築する「検索トレンド 地域ビュー」（3ページ構成）のレイアウトモックと各画面キャプチャ。
数値は「実測」表記のもの以外はモック値。データ設計の前提は [`../data-flow.md`](../data-flow.md) を参照。

| ファイル | 内容 |
|---|---|
| [`region-view-mockup.html`](./region-view-mockup.html) | モック本体（ブラウザで開く。上部タブでP1〜P3切替、チャートはホバーで値表示、ダークモード対応） |
| [`P1.png`](./P1.png) | **P1 地域ビュー** — 今週の顔ぶれTop10（順位=latest_rank、バー=ランクイン週数、NEWバッジ）／時系列（52週）／**地元ワード**（大阪の実測: 大阪府警察68%・高野線62%・大阪 警報41%・南海電鉄30%）＋急浮上／今週Top25明細 |
| [`P2.png`](./P2.png) | **P2 ワード深掘り**（栗きんとん）— KPI（261週ランクイン・最長は愛知251週=実測）／5年推移（毎年秋だけ跳ねる型）／月別の季節性／県別ランクイン週数 |
| [`P3.png`](./P3.png) | **P3 全国サマリ** — KPI（779語・47県・266週・最新週=実測）／全国Top10（ランクイン県数順）／県ごとの1位ワード |

## 設計上の約束（モックに織り込み済み）

- **score の大小はワード間・県間とも比較しない**（全35,489系列が自己ピーク=100。実測確認済み）。
  比較はすべて「順位（最新週のみ有効）」と「ランクイン週数・県数」（`jp_term_region_weeks`）で行う。
- score は同一系列の時系列（いつ盛り上がったか）にのみ使う。
- 「急上昇」の専用データは無いため、4週前比のスコア差で近似（P1右下）。

## キャプチャの再生成方法

```bash
cd <リポジトリルート>
SRC=demos/google-trends/mock/region-view-mockup.html
# P1（初期表示）
chromium-browser --headless=new --disable-gpu --hide-scrollbars \
  --window-size=1280,2450 --screenshot=demos/google-trends/mock/P1.png "file://$PWD/$SRC"
# P2/P3 は初期表示タブを差し替えた一時ファイルを撮る（撮影後に削除）
sed 's/class="tab on" data-pane="p1"/class="tab" data-pane="p1"/; s/class="tab" data-pane="p2"/class="tab on" data-pane="p2"/; s/class="pane on" id="p1"/class="pane" id="p1"/; s/class="pane" id="p2"/class="pane on" id="p2"/' \
  $SRC > demos/google-trends/mock/_tmp.html
chromium-browser --headless=new --disable-gpu --hide-scrollbars \
  --window-size=1280,1900 --screenshot=demos/google-trends/mock/P2.png "file://$PWD/demos/google-trends/mock/_tmp.html"
rm demos/google-trends/mock/_tmp.html
```

> 注意: snap 版 Chromium は `/tmp` 配下のファイルを開けない（ERR_FILE_NOT_FOUND）。
> 一時ファイルはホームディレクトリ配下（リポジトリ内）に置くこと。
