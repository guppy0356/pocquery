# POC Query - 開発ガイド（Claude向け）

このドキュメントは、Claude（AI）がこのプロジェクトを理解し、継続的に開発するためのガイドです。

## 🚀 クイックスタート（Claude向け指示）

**新しいテストケースを追加する場合:**
1. まず「テストケース追加時の要件定義」セクションを参照
2. ユーザーに必須項目（テーマ、テーブル構成、データ量、検証クエリ）を質問
3. 回答を得てから「新しいテストケースの追加手順」に従って実装

**プロンプト例:**
```
新しいテストケースを作成します。以下の情報を教えてください：

【必須】
1. テーマ: どんなパフォーマンス特性を検証したいですか？
2. テーブル構成: どんなテーブルが必要ですか？
3. データ量: 各テーブルの件数は？
4. 検証クエリ: どんなクエリを実行しますか？
...
```

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

ユーザーから「新しいテストケースを追加して」というリクエストがあった場合、以下の情報をヒアリングしてください。

### 必須項目（必ず質問する）

1. **テーマ・検証内容**
   - 何を検証したいか？（例: WHERE vs HAVING、Nested Loop vs Hash Join）
   - どんなパフォーマンス問題を再現したいか？

2. **テーブル構成**
   - どんなテーブルが必要か？（例: orders, items, shops）
   - 各テーブルの主要カラムは？
   - テーブル間のリレーションは？

3. **データ量と分布**
   - 各テーブルの件数は？（推奨: 10,000〜100,000件）
   - データの偏りは必要か？（例: 80%/20%）

4. **検証したいクエリ**
   - どんなクエリを実行するか？
   - 集計？結合？検索？

### 任意項目（必要に応じて質問）

5. **段階的な改善の流れ**
   - ステップ1で何をするか？（通常: パフォーマンスが悪い状態）
   - ステップ2以降の改善策は？（インデックス追加など）

6. **学習のゴール**
   - ユーザーに何を学んでほしいか？
   - どんな「aha!」体験を提供するか？

### 質問テンプレート例

```
新しいテストケースを作成します。以下の情報を教えてください：

【必須】
1. テーマ: どんなパフォーマンス特性を検証したいですか？
   例:
   - WHERE vs HAVINGの効率比較
   - Nested LoopとHash Joinの使い分け
   - インデックスの選択性による実行計画の変化

2. テーブル構成: どんなテーブルが必要ですか？
   例:
   - ECサイト: shops, orders, items
   - ブログ: users, posts, comments
   - 在庫管理: products, warehouses, stock

3. データ量: 各テーブルの件数は？
   - 推奨: 10,000〜100,000件程度
   - データの偏りは必要ですか？（80%/20%など）

4. 検証クエリ: どんなクエリを実行しますか？
   例:
   - 店舗ごとの日別売上集計
   - ユーザーの投稿数ランキング
   - 在庫の少ない商品検索

【任意】
5. 改善の流れ: どう段階的に改善しますか？
   - ステップ1: インデックスなしで実行（遅い）
   - ステップ2: WHEREで絞り込み（改善）
   - ステップ3: インデックス追加（更に改善）

6. 学習ゴール: ユーザーに何を学んでほしいですか？
```

### ユーザー入力例

```
テーマ: ECサイトの売上集計でのWHERE vs HAVING比較

テーブル構成:
- shops (id, name)
- orders (id, shop_id, shipped_day, customer_id)
- items (id, order_id, product_name, price)

データ量:
- shops: 100店舗
- orders: 100,000件（shipped_dayは1年分、特定期間に偏らせる）
- items: 500,000件（1注文あたり平均5アイテム）

検証クエリ:
店舗ごとの日別売上を計算
- WHEREで期間絞り込み（直近1週間）vs 全期間集計
- Rows Removed by Filterの確認

改善の流れ:
1. 全期間で集計（非効率）
2. WHEREで期間絞り込み（効率的）
3. shipped_dayにインデックス追加（更に改善）
4. HAVINGで売上額絞り込み（集計後フィルタ）

学習ゴール:
- WHERE（集計前）とHAVING（集計後）のフィルタタイミングの違い
- Rows Removed by Filterの意味
- インデックスが効くタイミング
```

## 新しいテストケースの追加手順

### 1. テーマを決める（要件定義完了後）

既存のテストケース：
- **nested-loop-test**: Nested Loop結合、データの偏り、Bitmap Scan
- (将来追加されるもの)

新しいテーマの例：
- Hash Join vs Nested Loop vs Merge Join
- パーティショニング
- 複合インデックスの設計
- サブクエリ vs JOIN
- UNION vs UNION ALL

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

### 5. テスト

```bash
# テストケースをロード
./load-test.sh [test-name]

# データベース再起動
docker compose down -v
docker compose up -d

# READMEの手順を実際に実行して確認
docker exec -it pocquery_postgres psql -U postgres -d pocquery
```

### 6. README.mdを更新

メインのREADME.mdの「利用可能なテストケース」セクションに追加：

```markdown
- **[test-name](init-db-templates/test-name/README.md)**: 説明
  - 学習ポイント1
  - 学習ポイント2
```

### 7. コミット

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

**このドキュメントは、Claudeがプロジェクトを理解し、一貫性のある開発を継続するための指針です。**
