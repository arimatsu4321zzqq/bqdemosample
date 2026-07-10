# お客様アカウントへの共有設定（会話分析エージェント）

BQ の会話分析（Conversational Analytics / Gemini Data Analytics）エージェントを、外部/一般アカウントに
使わせるための IAM 設定手順。**特定のエージェントだけ使わせる**構成にも対応。

- 検証環境: プロジェクト `ci-ss4-develop` / データセット `demo_google_trends` / エージェント `jp_trends_demo`
- 疎通確認: `kk2119nn@gmail.com` で Data ポータル経由チャット成功（2026-07-02 確認済み）

---

## 全体像：権限は「4レイヤ」

会話分析のチャットは **利用者本人の資格情報で BigQuery にクエリを実行する**。そのため
「エージェントを触る権限」だけでは動かず、以下を積む必要がある。

| # | レイヤ | ロール | 粒度 | 症状（無いとき） |
|---|---|---|---|---|
| 1 | エージェント操作 | `roles/geminidataanalytics.dataAgentUser` | **エージェント単位で付与可** | 共有されない |
| 2 | 会話（conversation）作成 | `roles/cloudaicompanion.user` | プロジェクト | 「会話を作成する権限がないため無効」 |
| 3 | クエリ実行 | `roles/bigquery.jobUser` | プロジェクトのみ | 「perform this action」権限エラー |
| 3 | データ読取 | `roles/bigquery.dataViewer` | **データセット単位で付与可** | 「access this data」権限エラー |
| 4 | クォータ/課金PJ利用 | `roles/serviceusage.serviceUsageConsumer` | プロジェクト | `x-goog-user-project` 系で拒否 |

> ⚠ **レイヤ4は「必須ではない」**。`kk2119nn@gmail.com` の Data ポータル経由チャット疎通では
> `serviceUsageConsumer` を付けずに通った（2026-07-02 実測）。利用者本人のクォータPJがクエリ実行PJと
> 一致する経路では不要。`x-goog-user-project` 系のクォータ拒否が出たときにだけ付ければよいフォールバック扱い。

> レイヤ2 `cloudaicompanion.user` は「Gemini チャットを使ってよい」能力のみで、**どのエージェントを使えるかは制御しない**。
> 使えるエージェントはレイヤ1の付与先で決まるため、**「一方だけ使える」分離を保ったまま**付けられる。

---

## 特定のエージェントだけ使わせる（分離）

- レイヤ1 `dataAgentUser` を **使わせたいエージェントのリソースにだけ**付ける。
- **プロジェクト単位では `dataAgentUser` を付けない**（付けると全エージェントに効く）。
- レイヤ2〜4 はプロジェクト単位だが、能力/実行/クォータの権限であってエージェントを開放しないので分離は保たれる。
- さらに堅くするなら、エージェントごとに参照データセットを分け、レイヤ3の `dataViewer` を
  そのデータセットだけに絞る（他エージェントのデータは読めなくなる）。

---

## コンソールでの設定場所（2か所に分かれる）

### ① データセット単位（BigQuery Data Viewer）
`demo_google_trends` だけに絞るのはここ。
1. コンソール → **BigQuery**（BigQuery Studio）
2. エクスプローラで `ci-ss4-develop` → データセット **`demo_google_trends`** をクリック
3. 上部 **「共有」→「権限」**（またはデータセット右の ⋮ →「共有」→「権限」）
4. **「プリンシパルを追加」** → メール入力
5. ロール＝ **「BigQuery データ閲覧者」** → 保存

### ② プロジェクト単位（Job User / Service Usage / Gemini）
1. コンソール → **「IAM と管理」→「IAM」**
2. **「アクセスを許可」**
3. 新しいプリンシパル＝ 対象メール
4. ロールを追加:
   - **「BigQuery ジョブユーザー」**
   - **「Gemini for Google Cloud ユーザー」**（＝会話作成）
   - （必要時のみ）**「Service Usage コンシューマ」** ← 疎通では不要だった。クォータ拒否時のフォールバック
5. 保存

> ⚠ 「BigQuery データ閲覧者」を IAM 画面（②）で付けると**プロジェクト全体（全データセット）**に効く。
> データセット限定にしたいなら必ず①の BigQuery 側で付ける。ジョブユーザーは①に出てこない（②専用）。

---

## CLI での設定（`EMAIL` を差し替え）

```bash
PROJECT=ci-ss4-develop
EMAIL=customer@example.com
AGENT_ID=jp_trends_demo      # 使わせたいエージェント

# --- レイヤ2/3：プロジェクト単位（この2つは必須） ---
gcloud projects add-iam-policy-binding $PROJECT \
  --member="user:$EMAIL" --role="roles/cloudaicompanion.user"
gcloud projects add-iam-policy-binding $PROJECT \
  --member="user:$EMAIL" --role="roles/bigquery.jobUser"

# --- レイヤ4：クォータ拒否が出たときだけ（疎通では不要だった） ---
# gcloud projects add-iam-policy-binding $PROJECT \
#   --member="user:$EMAIL" --role="roles/serviceusage.serviceUsageConsumer"

# --- レイヤ3：データ読取をデータセット限定で ---
bq add-iam-policy-binding \
  --member="user:$EMAIL" --role="roles/bigquery.dataViewer" \
  $PROJECT:demo_google_trends

# --- レイヤ1：エージェント単位（gcloud に専用コマンドが無いので REST・read-modify-write） ---
TOKEN=$(gcloud auth print-access-token)
# 1) 現ポリシー取得
curl -s -X POST \
  "https://geminidataanalytics.googleapis.com/v1beta/projects/$PROJECT/locations/global/dataAgents/$AGENT_ID:getIamPolicy" \
  -H "Authorization: Bearer $TOKEN" -H "x-goog-user-project: $PROJECT" \
  -H "Content-Type: application/json" -d '{}'
# 2) 既存 bindings に下記を足して setIamPolicy で書き戻す（空ポリシー時の最小例）
curl -s -X POST \
  "https://geminidataanalytics.googleapis.com/v1beta/projects/$PROJECT/locations/global/dataAgents/$AGENT_ID:setIamPolicy" \
  -H "Authorization: Bearer $TOKEN" -H "x-goog-user-project: $PROJECT" \
  -H "Content-Type: application/json" -d '{
    "policy": { "bindings": [
      { "role": "roles/geminidataanalytics.dataAgentUser",
        "members": ["user:'"$EMAIL"'"] }
    ] }
  }'
```

> `setIamPolicy` は既存ポリシーを上書きする。必ず `getIamPolicy` の結果に追記して丸ごと送る。
> `v1beta` で 404 なら `v1` に読み替え。API 無効エラーなら `gcloud services enable cloudaicompanion.googleapis.com`。

---

## つまずき対応表

| 症状 | 不足している権限 |
|---|---|
| 「エージェントが共有されましたが…会話を作成する権限がないため無効」 | `roles/cloudaicompanion.user`（レイヤ2） |
| チャットで「perform this action」権限エラー | `roles/bigquery.jobUser`（レイヤ3） |
| チャットで「access this data」権限エラー | `roles/bigquery.dataViewer`（レイヤ3・対象データセット） |
| `x-goog-user-project` / クォータ拒否 | `roles/serviceusage.serviceUsageConsumer`（レイヤ4・疎通では不要。出たときだけ付ける） |
| 外部ドメインのメールが追加できない | 組織ポリシー `iam.allowedPolicyMemberDomains` の制約 |

---

## 検証運用メモ

- レポート（Looker Studio）: ユーザー/グループ共有でお客様メールを招待。
- 会話分析: 上記 IAM をお客様メールに付与。
- **注意**: 社内アカウント（DSK）で検証しても「お客様アカウントで使えるか」は別問題。
  外部相当アカウントで一度実地確認すること（CIF 等のアカウント種別で Data ポータル経由が
  制限される事象の可能性があるため）。
- 本番配布時は共有 dev プロジェクト（`ci-ss4-develop`）ではなく**会話分析用の専用プロジェクト**を推奨
  （`jobUser`（＋付けるなら `serviceUsageConsumer`）がプロジェクト全体に効くため）。
