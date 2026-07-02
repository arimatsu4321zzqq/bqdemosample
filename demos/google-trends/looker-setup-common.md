# Looker Studio ダッシュボード共通セットアップ手順（P1〜P4 共通の土台）

「日本 検索トレンド ダッシュボード」を手動構築するための**最初に1回だけ行う共通設定**。
各ページ手順書（`looker-page-P1〜P4`）はこのファイルを前提にする。機能の詳細は
[`looker-studio-capabilities.md`](../../docs/looker-studio-capabilities.md) を参照。

- 対象プロジェクト: `ci-ss4-develop` / データセット: `demo_google_trends`（ロケーション **US**）
- 使う集計テーブル（[`sql/create_dashboard_tables.sql`](./sql/create_dashboard_tables.sql) で作成済み）:
  - `dash_jp_terms_weekly` … 週×ワード（全国）。時系列・人気ランキング。
  - `dash_jp_region_latest` … 都道府県×ワード（最新週）。日本地図・地域比較。
  - `dash_jp_rising_recent` … 都道府県×週×ワード（急上昇・直近52週）。急上昇ウォッチ。

---

## STEP 0. レポート作成
1. https://lookerstudio.google.com → 「空のレポート」を作成。
2. レポート名を **「日本 検索トレンド ダッシュボード」** に変更。

## STEP 1. データソースを3本追加（テーブル選択方式）
「リソース → 追加済みのデータソースの管理 → データを追加 → BigQuery」から、以下を**3回**繰り返す。
1. 認証 → プロジェクト `ci-ss4-develop` → データセット `demo_google_trends` → テーブル選択。
2. 対象テーブル: `dash_jp_terms_weekly` / `dash_jp_region_latest` / `dash_jp_rising_recent`。
3. 各データソースの名前を分かりやすく（例: `週×ワード(全国)` / `都道府県×ワード(最新)` / `急上昇(直近52週)`）。

> テーブル選択方式を使う（カスタムクエリ不要）。集計は BQ 側で済ませてあるので Looker からのスキャンは軽い。

## STEP 2. フィールドの型・既定集計を設定（★最重要）
集計テーブルは **すでに (週×ワード) 等の粒度で集計済み**。Looker はフィールドの「既定の集計」で
再集計するため、放置すると `avg_score` を SUM してしまう。**必ず下表の既定集計に直す**こと。

### 共通（地理・日付）
| フィールド | 設定する型 | 備考 |
|---|---|---|
| `region_code` | **地理 → 地域(Country subdivision / 国内地域第1レベル)** | `JP-13` 形式。**地図はこれを使うのが最も確実** |
| `region_name` | テキスト（表示用ラベル） | "Tokyo","Osaka Prefecture" 等。ラベル・表に使用 |
| `week` | 日付（YYYYMMDD/週） | 期間コントロール・時系列の軸 |

### 既定の集計（各データソースの数値フィールド）
| データソース | フィールド | 既定の集計 |
|---|---|---|
| dash_jp_terms_weekly | `avg_score` | **平均 (AVG)** |
| dash_jp_terms_weekly | `max_score` | **最大値 (MAX)** |
| dash_jp_terms_weekly | `best_rank` | **最小値 (MIN)** ＝最高順位 |
| dash_jp_terms_weekly | `region_count` | **平均 (AVG)**（または最大値）|
| dash_jp_region_latest | `score` | **平均 (AVG)** |
| dash_jp_region_latest | `rank` | **最小値 (MIN)** |
| dash_jp_rising_recent | `percent_gain` | **最大値 (MAX)** ＝最も伸びた瞬間 |
| dash_jp_rising_recent | `score` | **平均 (AVG)** |
| dash_jp_rising_recent | `rank` | **最小値 (MIN)** |

> `rank`/`best_rank` は「1が最上位」なので、必ず **最小値** に。SUM/AVG のままだと順位が壊れる。

## STEP 3. テーマ・キャンバス（全ページ共通の見た目）
- 「テーマとレイアウト → テーマ」でカスタムテーマを作成。
- **配色（推奨・ブランド中立）**:
  - アクセント（1色系グラフ）: `#2563EB`（青）
  - 補助: `#0EA5E9`(水) / `#F59E0B`(橙・急上昇/注意) / `#10B981`(緑)
  - 背景: `#FFFFFF` / パネル: `#F8FAFC` / 文字: `#0F172A`
  - 地図の濃淡: 淡 `#DBEAFE` → 濃 `#1E3A8A`
- **キャンバスサイズ**: 幅 1366 × 高さ 768（横長・プレゼン向け。「テーマとレイアウト → レイアウト → キャンバスサイズ」）。
- チャートヘッダー: 「ホバー時に表示」。グリッドスナップ ON（10px）。

## STEP 4. ページ構成とナビゲーション
1. ページを4枚用意し、名前を設定:
   - **P1 概況** / **P2 地域比較** / **P3 ワード深掘り** / **P4 急上昇ウォッチ**
2. 「テーマとレイアウト → レイアウト → ナビゲーションタイプ」を **左（またはタブ）** に設定 → 閲覧者がページを切替可能に。
3. 各ページ上部に共通ヘッダー帯（長方形＋タイトルテキスト）を置く。1ページ目で作って全ページにコピペし統一。

## STEP 5. レポートレベルの共通コントロール
- **期間コントロール**を1つ、レポートレベルに配置（右クリック →「レポートレベルにする」）。日付ディメンション＝`week`。既定の期間＝「過去12か月」など。
- これで全ページに期間フィルタが効く（`dash_jp_region_latest` は最新週スナップショットのため期間の影響は受けない点に留意）。

## 命名・ファイル規約
- 各ページ手順書: `looker-page-P1-overview.md` / `-P2-region.md` / `-P3-term.md` / `-P4-rising.md`（本フォルダ内）
- チャートには分かる名前を付ける（例: 「KPI_対象ワード数」「地図_都道府県別スコア」）。

---

## 補足: よく使う計算フィールド（共通）
- **都道府県名(日本語ラベル)**: 必要なら `CASE WHEN region_code="JP-13" THEN "東京都" … END`（表示を日本語化したい時のみ。地図のジオコーディングには使わず `region_code` を使う）。
- **急上昇バッジ**: `CASE WHEN percent_gain>=200 THEN "🔥" WHEN percent_gain>=100 THEN "▲" ELSE "" END`（非集計フィールド。`percent_gain` を集計せずそのまま参照する行レベルで作る点に注意）。
