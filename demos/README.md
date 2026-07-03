# demos/ — フォルダ構成ガイド

1テーマ = 1フォルダで自己完結させる。このファイルは**構成の説明のみ**（各デモの状態は各フォルダの README を参照）。

## 直下のファイル（デモ横断ドキュメント）

| ファイル | 内容 |
|---|---|
| [`candidate-overview.md`](./candidate-overview.md) | 検討した全候補データセットの一覧（採用/保留とその理由） |
| [`candidate-datasets.md`](./candidate-datasets.md) | 候補の詳細資料（実現性調査・データ辞書・レイアウト案・curated設計案） |
| [`demo-selection-rationale.md`](./demo-selection-rationale.md) | 題材選定の経緯（要件の変遷・比較の考え方・レビュアー提案への対応） |

## デモフォルダ

| フォルダ | テーマ | 元データ（BQ公式） |
|---|---|---|
| [`google-trends/`](./google-trends/) | 検索トレンド地域ビュー（県で絞る×時系列。いつ何が盛り上がったか） | `google_trends` |
| [`osm-facilities/`](./osm-facilities/) | 地域施設マップ（市区町村で絞る×分布。何がどこにあるか） | `geo_openstreetmap` |

2つのデモは「時間の動き（トレンド）」と「空間の分布（施設）」の役割分担で補完し合う設計。

## 各デモフォルダの標準構成

```
demos/<デモ名>/
├── README.md            … デモの概要・テーブル/エージェントの識別子・ファイル案内
├── setup.md             … ゼロから手動再現する全手順（認証〜BQ〜エージェント〜片付け）
├── data-flow.md         … データフロー全体図（公式データセットの何を抽出し、どう加工・集計したか）
├── data-dictionary.md   … スキーマ辞書（元データのテーブル群・クセ → curated テーブルのカラム定義）
├── sql/                 … curated テーブル作成SQL（CREATE OR REPLACE・冪等）
├── agent/               … Conversational Analytics データエージェント
│   ├── build_payload.py       … 定義ペイロード生成スクリプト（用語集・検証済みクエリを一元管理）
│   ├── <agent>.json           … 生成された定義ペイロード（REST API で登録）
│   └── README.md              … 作成/更新/質問の操作コマンド集
├── mock/                … Looker Studio ダッシュボードのレイアウトモック
│   ├── *.html                 … モック本体（タブでページ切替・ホバーで値表示）
│   ├── P1.png 〜 P3.png       … 各ページの画面キャプチャ
│   └── README.md              … キャプチャの説明・再生成コマンド
├── looker-setup-common.md     … Looker 手動構築の共通セットアップ（データソース・型・色・ページ）
├── looker-layout.md           … レイアウト案（チャート/ディメンション/指標の定義）
├── looker-page-P*.md          … ページ別の構築手順書（設定表・手順・ハマりどころ・期待値）
└── old/                 … 旧設計の退避場所（再設計時のみ存在。中身は old/README.md 参照）
```

- Looker 手順書（`looker-*.md`）は**モック確定後に書く**ため、再設計中のデモには無いことがある。
- Looker Studio の機能可否・共通ノウハウはデモ横断のため `../docs/`
  （[`looker-studio-capabilities.md`](../docs/looker-studio-capabilities.md) /
  [`looker-common.md`](../docs/looker-common.md)）に置く。
