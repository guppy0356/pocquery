# POC Query - 開発ガイド（Claude向け）

このドキュメントは、Claude（AI）がこのプロジェクトを理解し、継続的に開発するためのガイドです。

## 🚀 クイックスタート（Claude向け指示）

**新しいテストケースを追加する場合:**
1. まず「テストケース追加時の要件定義」セクションを参照
2. **AskUserQuestionツールを使って**選択肢形式でユーザーに必須項目を質問
3. 回答を得てから「新しいテストケースの追加手順」に従って実装
4. **⚠️ 重要**: READMEの全ステップを実際に実行して検証（詳細はステップ5参照）

**質問方法:**
- **必ず**AskUserQuestionツールを使用して選択肢形式で質問する
- 自由記述を求めるプロンプトは避ける
- 段階的に質問していく（1問ずつ、または関連する2-4問をまとめて）
- 具体的な選択肢例は「テストケース追加時の要件定義」セクションを参照

**検証の重要性:**
- 「クエリが実行できた」だけでは不十分
- EXPLAIN ANALYZEで期待したパフォーマンス特性が再現できることを確認
- インデックスが効く/効かない、Rows Removed by Filterの値など、すべて実測値で検証

詳細は「テストケース追加時の要件定義」セクションを参照してください。

## プロジェクト概要

**POC Query** は、PostgreSQLのクエリパフォーマンスを検証・学習するための実験環境です。

### 目的

- SQLクエリのパフォーマンス特性を実践的に学ぶ
- EXPLAIN ANALYZEを使った実行計画の理解
- インデックスの効果や最適化手法の検証
- 段階的な改善を体験できる教材の提供

### 対象ユーザー

- データベースパフォーマンスを学びたいエンジニア
- クエリ最適化の実践経験を積みたい開発者
- PostgreSQLの内部動作を理解したい人

## プロジェクト構成

```
pocquery/
├── .env                          # 環境変数（gitignore済み）
├── .gitignore
├── compose.yml                    # Docker Compose設定
├── README.md                      # ユーザー向けドキュメント
├── CLAUDE.md                      # このファイル（開発ガイド）
├── load-test.sh                   # テストケースロードスクリプト
├── init-db/
│   ├── init.sql                  # 基本設定（常にロード）
│   └── test-data.sql             # 選択されたテストケース（自動生成）
└── init-db-templates/            # テストケーステンプレート
    ├── nested-loop-test/
    │   ├── test-data.sql        # テーブル定義とデータ
    │   └── README.md            # 検証手順と学習内容
    └── (他のテストケース...)
```

## コアコンセプト

### 1. テストケースベースのアーキテクチャ

各テストケースは独立したディレクトリで管理され、以下を含む：

- **test-data.sql**: テーブル定義とデータ投入
- **README.md**: 検証手順、実行計画の解説、学習ポイント

### 2. 段階的な学習体験

テストケースは以下の流れで設計する：

1. **パフォーマンスが悪い状態**から始める
2. **段階的に改善**していく
3. **実行計画を比較**して効果を確認
4. **トレードオフを理解**する

### 3. 実践的な検証

- 実際のデータを使った検証（10万件〜）
- EXPLAIN ANALYZEで実測値を確認
- Rows Removed by Filter などの重要指標に注目

## テストケースの設計原則

### データ設計

1. **データ量は現実的に**
   - 10,000件〜100,000件程度
   - インデックスの効果が見えるサイズ

2. **意図的な偏りを作る**
   - 80%/20%の法則を活用
   - 選択性の違いを際立たせる

3. **シンプルなスキーマ**
   - 2〜3テーブル程度
   - 理解しやすいカラム構成

### README構成

各テストケースのREADMEは以下の構成を推奨：

```markdown
# [テストケース名]

## データ構成
- テーブル構造
- データ量と分布
- インデックスの有無

## 検証内容
- 何を学べるか
- どんな現象を体験できるか

## 検証手順
### ステップ1: [悪い状態]
- クエリ
- 期待される結果（遅い、非効率）

### ステップ2: [改善]
- 改善策（インデックス作成など）
- クエリ
- 期待される改善

### ステップ3-N: [さらなる最適化]
...

## 学習ポイント
- 重要な発見
- トレードオフ
- 実践的なガイドライン

## 次のステップ
- 発展的な学習項目
```

### 実行計画の解説

実行計画を解説する際は：

1. **図や例を使って視覚的に**
   - テキストベースの図解
   - 処理の流れ

2. **数字に注目**
   - actual rows
   - Rows Removed by Filter
   - Execution Time

3. **なぜそうなるか**を説明
   - PostgreSQLの内部動作
   - オプティマイザの判断理由

4. **トレードオフを明示**
   - メリットとデメリット
   - 適切な使い所

## テストケース追加時の要件定義

ユーザーから「新しいテストケースを追加して」というリクエストがあった場合、**AskUserQuestionツールを使って選択肢形式で**以下の情報をヒアリングしてください。

### 必須項目（必ず質問する）

1. **テーマ・検証内容**
   - 何を検証したいか？
   - どんなパフォーマンス問題を再現したいか？

2. **テーブル構成・ドメイン**
   - どんなドメイン/ビジネスモデルを想定するか？
   - どんなテーブルが必要か？

3. **データ量**
   - 各テーブルの件数は？

4. **検証したいクエリパターン**
   - どんなクエリを実行するか？

### AskUserQuestionツールの使い方

**⚠️ 重要: 必ずAskUserQuestionツールを使用してください。自由記述のプロンプトは避けてください。**

#### ステップ1: 基本情報を質問（2-4問を一度に）

```javascript
AskUserQuestion({
  questions: [
    {
      question: "どのパフォーマンス特性を検証したいですか？",
      header: "テーマ",
      multiSelect: false,
      options: [
        {
          label: "WHERE vs HAVINGのフィルタ効率",
          description: "集計前フィルタ（WHERE）と集計後フィルタ（HAVING）の違いを学ぶ"
        },
        {
          label: "JOINアルゴリズムの比較",
          description: "Nested Loop、Hash Join、Merge Joinの使い分けを学ぶ"
        },
        {
          label: "インデックスの選択性",
          description: "選択性の違いがインデックス利用に与える影響を学ぶ"
        },
        {
          label: "複合インデックスの設計",
          description: "カラムの順序や部分インデックスの効果を学ぶ"
        }
      ]
    },
    {
      question: "どのビジネスドメインでテストしたいですか？",
      header: "ドメイン",
      multiSelect: false,
      options: [
        {
          label: "ECサイト（店舗・注文・商品）",
          description: "shops, orders, items テーブル構成"
        },
        {
          label: "ブログ（ユーザー・投稿・コメント）",
          description: "users, posts, comments テーブル構成"
        },
        {
          label: "在庫管理（商品・倉庫・在庫）",
          description: "products, warehouses, stock テーブル構成"
        },
        {
          label: "SNS（ユーザー・投稿・いいね）",
          description: "users, posts, likes テーブル構成"
        }
      ]
    },
    {
      question: "メインテーブルのデータ量はどのくらいにしますか？",
      header: "データ量",
      multiSelect: false,
      options: [
        {
          label: "小規模（10,000件）",
          description: "軽量で実行が速い。基本的な動作確認向け"
        },
        {
          label: "中規模（50,000件）",
          description: "インデックスの効果が見えやすい。推奨"
        },
        {
          label: "大規模（100,000件）",
          description: "より現実的なパフォーマンス差を体験できる"
        },
        {
          label: "超大規模（500,000件以上）",
          description: "本格的なパフォーマンステスト向け"
        }
      ]
    }
  ]
})
```

#### ステップ2: 詳細を質問（必要に応じて）

最初の回答に基づいて、追加の質問をします。

**例: WHERE vs HAVINGを選択した場合**

```javascript
AskUserQuestion({
  questions: [
    {
      question: "どのようなクエリパターンを検証しますか？",
      header: "クエリ",
      multiSelect: true,  // 複数選択可能
      options: [
        {
          label: "集計前フィルタ（WHERE）",
          description: "期間絞り込み後に集計する効率的なパターン"
        },
        {
          label: "集計後フィルタ（HAVING）",
          description: "全件集計後に結果をフィルタする非効率なパターン"
        },
        {
          label: "インデックス追加での改善",
          description: "WHERE句のカラムにインデックスを追加して高速化"
        },
        {
          label: "集計結果の絞り込み",
          description: "HAVINGで売上額などの集計結果を絞り込み"
        }
      ]
    },
    {
      question: "データの偏りは必要ですか？",
      header: "データ分布",
      multiSelect: false,
      options: [
        {
          label: "均等分散",
          description: "全カテゴリに均等にデータが分布"
        },
        {
          label: "80/20の偏り",
          description: "20%のカテゴリに80%のデータが集中"
        },
        {
          label: "極端な偏り（99/1）",
          description: "特定のカテゴリに大部分が集中。選択性の違いを際立たせる"
        },
        {
          label: "時系列の偏り",
          description: "特定期間にデータが集中（例: 直近1週間に50%）"
        }
      ]
    }
  ]
})
```

### 質問の段階的な進め方

1. **最初の質問（必須）**: テーマ、ドメイン、データ量を一度に質問
2. **詳細の質問（必須）**: 最初の回答に基づいて、クエリパターンやデータ分布を質問
3. **オプション質問（任意）**: 必要に応じて、学習ゴールや段階的改善の流れを質問

### よくある質問パターン集

#### テーマ別の選択肢

**JOIN アルゴリズム:**
- Nested Loop（小規模結合）
- Hash Join（大規模等結合）
- Merge Join（ソート済み結合）

**インデックス関連:**
- 単一カラムインデックス vs 複合インデックス
- 部分インデックス（WHERE付き）
- カバリングインデックス
- インデックスの選択性による実行計画の変化

**集計・グルーピング:**
- WHERE vs HAVING
- GROUP BY の最適化
- DISTINCT vs GROUP BY

**サブクエリ:**
- EXISTS vs IN
- サブクエリ vs JOIN
- CTEのマテリアライズ

#### データ量の選択肢

- **10,000件**: 軽量テスト
- **50,000件**: 推奨（インデックスの効果が見えやすい）
- **100,000件**: 現実的なサイズ
- **500,000件**: 大規模テスト

#### データ分布の選択肢

- **均等分散**: 全カテゴリに均等
- **80/20**: 一般的な偏り
- **99/1**: 極端な偏り（選択性の検証向け）
- **時系列偏り**: 特定期間に集中

### 回答例（ユーザーがツールで選択した場合）

```javascript
// ステップ1の回答
{
  "テーマ": "WHERE vs HAVINGのフィルタ効率",
  "ドメイン": "ECサイト（店舗・注文・商品）",
  "データ量": "中規模（50,000件）"
}

// ステップ2の回答
{
  "クエリ": ["集計前フィルタ（WHERE）", "集計後フィルタ（HAVING）", "インデックス追加での改善"],
  "データ分布": "時系列の偏り"
}
```

この情報を基に、テストケースを実装します。

## 新しいテストケースの追加手順

### 0. 要件定義（最初に必ず実行）

**⚠️ 重要: 実装を開始する前に、必ずAskUserQuestionツールで要件をヒアリングしてください。**

「テストケース追加時の要件定義」セクションの指示に従って：
1. ステップ1の質問（テーマ、ドメイン、データ量）を実行
2. ステップ2の詳細質問（クエリパターン、データ分布）を実行
3. 回答を確認してから実装に進む

### 1. テーマを決める（要件定義完了後）

既存のテストケース：
- **nested-loop-test**: Nested Loop結合、データの偏り、Bitmap Scan
- **blob-column-test**: BLOBカラムのパフォーマンス影響
- **composite-index-test**: 複合インデックスのカラム順序
- **groupby-filter-test**: GROUP BY と WHERE/HAVING の組み合わせ
- (将来追加されるもの)

新しいテーマの例：
- Hash Join vs Nested Loop vs Merge Join
- パーティショニング
- サブクエリ vs JOIN (EXISTS vs IN)
- UNION vs UNION ALL
- CTEのマテリアライズ

### 2. ディレクトリとファイルを作成

```bash
# ディレクトリ作成
mkdir -p init-db-templates/[test-name]/

# test-data.sql 作成
# - テーブル定義
# - データ投入（generate_series活用）
# - インデックスは「なし」から始める

# README.md 作成
# - データ構成説明
# - 検証手順（ステップバイステップ）
# - 実行計画の解説
# - 学習ポイント
```

### 3. データ設計のポイント

```sql
-- 良い例: generate_seriesで大量データ生成
INSERT INTO table_name (id, category, value)
SELECT
    i as id,
    ((i - 1) % 100) + 1 as category,  -- 均等分散
    CASE
        WHEN i % 5 = 0 THEN 'active'   -- 20%
        ELSE 'inactive'                 -- 80%
    END as value
FROM generate_series(1, 100000) as i;
```

### 4. 検証手順の作成

```markdown
### ステップ1: インデックスなしの状態

[クエリ]

**結果:**
- Seq Scan が使われる
- Rows Removed by Filter: X件
- 実行時間: Xms

### ステップ2: インデックス作成

```sql
CREATE INDEX idx_xxx ON table(column);
```

### ステップ3: 改善を確認

[同じクエリ]

**期待される改善:**
- Index Scan が使われる
- 実行時間: Xms → Yms（Z倍高速化）
```

### 5. 徹底的なテストと検証（重要！）

**⚠️ 重要: テストケースを作成したら、必ずREADMEの全ステップを実際に実行して検証してください。**

#### 5.1 データ投入の確認

```bash
# テストケースをロード
./load-test.sh [test-name]

# データベース再起動
docker compose down -v
docker compose up -d

# データが正しく投入されたか確認
docker exec pocquery_postgres psql -U postgres -d pocquery -c "
SELECT
    schemaname,
    tablename,
    n_live_tup as row_count
FROM pg_stat_user_tables
ORDER BY tablename;
"

# データ分布を確認（例: カテゴリ別の件数）
docker exec pocquery_postgres psql -U postgres -d pocquery -c "
SELECT
    category_id,
    COUNT(*)
FROM your_table
GROUP BY category_id
ORDER BY category_id
LIMIT 10;
"
```

#### 5.2 READMEの各ステップを実行

**READMEに記載した全てのクエリを実行し、以下を確認:**

1. **実行計画が期待通りか**
   ```bash
   docker exec pocquery_postgres psql -U postgres -d pocquery -c "
   EXPLAIN ANALYZE
   [READMEのクエリ]
   "
   ```

2. **確認すべきポイント:**
   - ✅ 正しいスキャン方法が使われているか（Seq Scan, Index Scan, Bitmap Scanなど）
   - ✅ `Rows Removed by Filter` の値は期待通りか
   - ✅ `actual rows` の値は正しいか
   - ✅ 実行時間は妥当か
   - ✅ インデックスが効いているか（作成後）

3. **よくある問題:**
   - ❌ インデックスを作成したのに使われていない
     → データ量や選択性を見直す
   - ❌ 期待したフィルタが発生していない
     → クエリやデータ設計を修正
   - ❌ 実行時間の改善が見られない
     → インデックスの設計やデータ分布を見直す

#### 5.3 期待と現実のギャップを記録

実際の実行結果をREADMEに反映：

```markdown
**期待される結果:**
- Seq Scan が使われる
- Rows Removed by Filter: 約80,000件
- 実行時間: 10-20ms程度

**実際の結果（検証済み）:**
```
[実際のEXPLAIN ANALYZEの出力を貼る]
```
```

#### 5.4 全ステップの動作確認

READMEに記載した全てのステップを順番に実行：

```bash
# ステップ1: インデックスなし
[クエリ実行]
→ 結果を記録

# ステップ2: インデックス作成
docker exec pocquery_postgres psql -U postgres -d pocquery -c "
CREATE INDEX idx_xxx ON table(column);
"

# ステップ3: 改善を確認
[同じクエリ実行]
→ 改善されたか確認

# ステップ4以降も同様に...
```

#### 5.5 失敗したケースの対処

期待通りの結果が得られない場合：

1. **データ設計を見直す**
   - データ量が少なすぎる/多すぎる
   - データの偏りが不十分

2. **クエリを調整**
   - WHERE句の条件を変える
   - JOINの順序を見直す

3. **READMEの説明を修正**
   - 「期待される結果」を実際の結果に合わせる
   - なぜそうなるかの説明を追加

4. **test-data.sqlを修正**
   - データ量を調整
   - 分布を変更

**⚠️ 注意: 「動作確認」は「クエリが実行できた」ではなく、「期待したパフォーマンス特性が再現できた」ことを意味します。**

### 6. TodoListで進捗管理（推奨）

テストケース追加時は、TodoWriteツールでタスクを管理すると漏れがありません：

```
[
  {"content": "テーブル定義とデータ投入SQL作成", "status": "completed"},
  {"content": "README.md作成", "status": "completed"},
  {"content": "データ投入確認", "status": "completed"},
  {"content": "ステップ1検証（インデックスなし）", "status": "in_progress"},
  {"content": "ステップ2検証（WHERE絞り込み）", "status": "pending"},
  {"content": "ステップ3検証（インデックス追加）", "status": "pending"},
  {"content": "全ステップ完了確認", "status": "pending"}
]
```

### 7. メインREADME.mdを更新

メインのREADME.mdの「利用可能なテストケース」セクションに追加：

```markdown
- **[test-name](init-db-templates/test-name/README.md)**: 説明
  - 学習ポイント1
  - 学習ポイント2
```

### 8. コミット

```bash
git add init-db-templates/[test-name]/
git add README.md
git commit -m "Add [test-name] test case

[簡潔な説明]

🤖 Generated with [Claude Code](https://claude.com/claude-code)

Co-Authored-By: Claude <noreply@anthropic.com>"
```

## コミットメッセージ規約

### フォーマット

```
<type>: <subject>

<body>

🤖 Generated with [Claude Code](https://claude.com/claude-code)

Co-Authored-By: Claude <noreply@anthropic.com>
```

### Type

- `Add`: 新しいテストケース、機能追加
- `Update`: 既存コンテンツの更新
- `Fix`: バグ修正、SQL修正
- `Restructure`: ディレクトリ構造の変更
- `Docs`: ドキュメントのみの変更

### 例

```
Add hash-join-test test case

Hash JoinとNested Loopのパフォーマンス比較テストケースを追加。
大量データでの結合パフォーマンスの違いを検証可能。

Changes:
- Create hash-join-test directory with test data
- Add README with step-by-step verification
- Update main README with new test case

🤖 Generated with [Claude Code](https://claude.com/claude-code)

Co-Authored-By: Claude <noreply@anthropic.com>
```

## コーディング規約

### SQL

- **インデント**: 2スペース
- **キーワード**: 大文字（SELECT, FROM, WHERE）
- **コメント**: `--` で説明を追加
- **generate_series**: 大量データ生成に活用

```sql
-- 良い例
SELECT
    category_id,
    COUNT(*) as product_count,
    AVG(price)::INT as avg_price
FROM products
WHERE is_active = true  -- アクティブな商品のみ
GROUP BY category_id
ORDER BY category_id;
```

### シェルスクリプト

- **エラーハンドリング**: `set -e` を使用
- **変数**: UPPER_CASE
- **コメント**: 各セクションに説明

### Markdown

- **見出し**: 階層構造を明確に
- **コードブロック**: 言語指定（```sql, ```bash）
- **絵文字**: 控えめに使用（📚, ✅, ❌など）

## トラブルシューティング

### データが投入されない

```bash
# ボリュームを完全削除
docker compose down -v
docker compose up -d

# ログ確認
docker logs pocquery_postgres
```

### クエリが遅い

- データ量を確認: `SELECT COUNT(*) FROM table;`
- 統計情報を更新: `ANALYZE table;`
- インデックスを確認: `\di`

### 実行計画が期待と違う

- `random_page_cost` などのパラメータ確認
- データ分布を確認
- VACUUM ANALYZEを実行

## 参考リソース

- PostgreSQL公式ドキュメント: https://www.postgresql.org/docs/
- EXPLAIN解説: https://www.postgresql.org/docs/current/using-explain.html
- パフォーマンスチューニング: https://www.postgresql.org/docs/current/performance-tips.html

## メンテナンスガイドライン

### 定期的な見直し

- PostgreSQLのバージョンアップに対応
- 実行計画の結果を最新化
- 新しい最適化手法を追加

### ユーザーフィードバック

- GitHubのIssuesで受け付け
- 分かりにくい部分を改善
- 新しいテストケースのリクエスト

### コミュニティ貢献

- Pull Requestを歓迎
- テストケースの追加
- ドキュメントの改善

---

## 重要事項まとめ（必読）

### テストケース追加時の鉄則

1. **質問は必ず選択肢形式で**: AskUserQuestionツールを使用。自由記述プロンプトは禁止
2. **段階的に質問する**:
   - ステップ1: テーマ、ドメイン、データ量（2-4問）
   - ステップ2: クエリパターン、データ分布（1-2問）
3. **実装前に要件確定**: 全ての回答を得てから実装開始
4. **必ず検証する**: READMEの全ステップを実行して動作確認
5. **TodoWriteで管理**: 進捗を可視化してタスク漏れを防ぐ

### よくある間違い

❌ **間違い**: 「どんなテストケースを作りますか？」と自由記述を促す
✅ **正しい**: AskUserQuestionで選択肢を提示

❌ **間違い**: ユーザーの説明だけでテーブルを設計
✅ **正しい**: ドメイン、データ量、分布を選択肢で確認

❌ **間違い**: クエリが実行できたら完了
✅ **正しい**: EXPLAIN ANALYZEで期待したパフォーマンス特性を確認

### 質問の選択肢テンプレート（再掲）

```javascript
// 必ず「テストケース追加時の要件定義」セクションの
// 詳細な選択肢例を参照してください

AskUserQuestion({
  questions: [
    { question: "どのパフォーマンス特性を検証したいですか？", ... },
    { question: "どのビジネスドメインでテストしたいですか？", ... },
    { question: "メインテーブルのデータ量はどのくらいにしますか？", ... }
  ]
})
```

---

**このドキュメントは、Claudeがプロジェクトを理解し、一貫性のある開発を継続するための指針です。**
