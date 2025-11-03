# POC Query - SQL パフォーマンス検証環境

PostgreSQL を使用した SQL パフォーマンス検証用の Docker 環境です。

## 構成

- PostgreSQL 15（安定版）
- pgAdmin 4（Web ベースの管理ツール）

## セットアップ

### 1. 環境変数の設定

```bash
cp .env.example .env
```

必要に応じて `.env` ファイルを編集してください。

### 2. コンテナの起動

```bash
docker compose up -d
```

### 3. 起動確認

```bash
docker compose ps
```

両方のサービスが `Up` 状態であることを確認してください。

## アクセス方法

### PostgreSQL

- **ホスト**: localhost
- **ポート**: 5432
- **ユーザー**: postgres（デフォルト）
- **パスワード**: postgres（デフォルト）
- **データベース**: pocquery

#### psql での接続例

```bash
docker compose exec postgres psql -U postgres -d pocquery
```

または、ローカルの psql から：

```bash
psql -h localhost -U postgres -d pocquery
```

### pgAdmin

ブラウザで http://localhost:5050 にアクセス

- **メールアドレス**: admin@example.com（デフォルト）
- **パスワード**: admin（デフォルト）

#### pgAdmin での PostgreSQL サーバー登録

1. pgAdmin にログイン後、「Add New Server」をクリック
2. 以下の情報を入力：
   - **Name**: POC Query（任意の名前）
   - **Host**: postgres（Docker ネットワーク内のサービス名）
   - **Port**: 5432
   - **Username**: postgres
   - **Password**: postgres

## パフォーマンス検証機能

初期化スクリプトで以下が自動的にセットアップされます：

### 有効化された拡張機能

- `pg_stat_statements`: クエリ統計の記録
- `pg_trgm`: テキスト検索の高速化

### performance スキーマ

パフォーマンス分析用のツールが用意されています：

#### query_stats テーブル

クエリの実行時間とパフォーマンスを記録

```sql
SELECT * FROM performance.query_stats;
```

#### query_summary ビュー

クエリ名ごとの統計サマリー

```sql
SELECT * FROM performance.query_summary;
```

#### log_query_execution 関数

クエリ実行結果を記録

```sql
SELECT performance.log_query_execution(
    'sample_query',  -- クエリ名
    123.45,          -- 実行時間（ミリ秒）
    1000,            -- 返却行数
    'test note'      -- メモ（オプション）
);
```

## テストケース管理

複数のテストケースを用意して、検証したい内容に応じて切り替えることができます。

### テストケースの構成

- `init-db/`: 自動的にロードされるディレクトリ
  - `init.sql`: 基本的なパフォーマンス検証機能（常にロード）
  - `test-data.sql`: 選択されたテストケース（自動生成、gitignore済み）
- `init-db-templates/`: テストケースのテンプレート
  - `nested-loop-test/`: Nested Loop検証用
    - `test-data.sql`: テーブル定義とデータ（users: 3件, orders: 10,000件）
    - `README.md`: 検証手順とクエリ例

### 利用可能なテストケースの確認

```bash
./load-test.sh
```

### テストケースのロード

```bash
# 1. テストケースを選択してロード
./load-test.sh nested-loop-test

# 2. データベースをリセットして再起動
docker compose down -v
docker compose up -d

# 3. テストケースのREADMEで検証手順を確認
cat init-db-templates/nested-loop-test/README.md
```

**注意**: テストケースを切り替える際は必ず `-v` フラグを使用してボリュームを削除してください。これにより古いデータが削除され、新しいテストデータで初期化されます。

### 利用可能なテストケース

- **[nested-loop-test](init-db-templates/nested-loop-test/README.md)**: Nested Loop結合のパフォーマンス検証
  - データの偏りがクエリプランに与える影響
  - インデックスの選択性による実行計画の違い

### 新しいテストケースの追加

`init-db-templates/` ディレクトリに新しいディレクトリを作成します：

```bash
# 1. テストケースディレクトリを作成
mkdir -p init-db-templates/hash-join-test

# 2. test-data.sql を作成
cat > init-db-templates/hash-join-test/test-data.sql << 'EOF'
-- Hash Join 検証用テストデータ
CREATE TABLE ...
EOF

# 3. README.md を作成（検証手順とクエリ例）
cat > init-db-templates/hash-join-test/README.md << 'EOF'
# Hash Join テストケース
...
EOF

# 4. ロード
./load-test.sh hash-join-test
```

## パフォーマンス検証のヒント

### EXPLAIN ANALYZE の使用

```sql
EXPLAIN ANALYZE
SELECT * FROM your_table WHERE condition;
```

### クエリ統計の確認

```sql
SELECT * FROM pg_stat_statements
ORDER BY total_exec_time DESC
LIMIT 10;
```

### インデックスの使用状況確認

```sql
SELECT schemaname, tablename, indexname, idx_scan, idx_tup_read, idx_tup_fetch
FROM pg_stat_user_indexes
ORDER BY idx_scan DESC;
```

### テーブルサイズの確認

```sql
SELECT
    schemaname,
    tablename,
    pg_size_pretty(pg_total_relation_size(schemaname||'.'||tablename)) AS size
FROM pg_tables
WHERE schemaname NOT IN ('pg_catalog', 'information_schema')
ORDER BY pg_total_relation_size(schemaname||'.'||tablename) DESC;
```

## コマンド

### コンテナの起動

```bash
docker compose up -d
```

### コンテナの停止

```bash
docker compose down
```

### ログの確認

```bash
# すべてのログ
docker compose logs -f

# PostgreSQL のみ
docker compose logs -f postgres

# pgAdmin のみ
docker compose logs -f pgadmin
```

### データベースのリセット

```bash
# コンテナとボリュームを削除
docker compose down -v

# 再起動
docker compose up -d
```

## トラブルシューティング

### ポートが既に使用されている

`.env` ファイルでポート番号を変更してください。

### コンテナが起動しない

```bash
# ログを確認
docker compose logs

# コンテナの状態を確認
docker compose ps -a
```

### データベースに接続できない

```bash
# PostgreSQL のヘルスチェック
docker compose exec postgres pg_isready -U postgres
```

## ライセンス

MIT
