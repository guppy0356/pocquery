# Nested Loop テストケース

Nested Loop結合のパフォーマンス特性を検証するためのテストケースです。

## データ構成

- **users テーブル**: 3件
  - Alice (id=1)
  - Bob (id=2)
  - Charlie (id=3)

- **orders テーブル**: 10,000件
  - Alice: 1,000件 (10%)
  - **Bob: 8,000件 (80%)** ← 意図的に偏らせたデータ
  - Charlie: 1,000件 (10%)

- **インデックス**:
  - `users.id`: PRIMARY KEY
  - `orders.id`: PRIMARY KEY
  - `orders.user_id`: INDEX (`idx_orders_user_id`)

## 検証内容

このテストケースでは、以下の現象を確認できます：

1. **少数のデータを取得する場合**: インデックスが使用される
2. **大量のデータを取得する場合**: Seq Scanが選択される（インデックスよりも効率的）
3. データの偏りがクエリプランに与える影響

## 検証クエリ

### 1. Bobのデータを取得（全体の80%）

```sql
EXPLAIN ANALYZE
SELECT u.name, o.order_date, o.amount
FROM users u
INNER JOIN orders o ON u.id = o.user_id
WHERE u.id = 2;
```

**期待される結果:**
- `orders` テーブルに対して **Seq Scan** が使用される
- インデックスが存在しても、大量データの場合はSeq Scanの方が効率的

### 2. Aliceのデータを取得（全体の10%）

```sql
EXPLAIN ANALYZE
SELECT u.name, o.order_date, o.amount
FROM users u
INNER JOIN orders o ON u.id = o.user_id
WHERE u.id = 1;
```

**期待される結果:**
- `orders` テーブルに対して **Bitmap Index Scan** が使用される
- 少量データの場合はインデックスが効率的

### 3. 全ユーザーのデータを取得

```sql
EXPLAIN ANALYZE
SELECT u.name, COUNT(*) as order_count, SUM(o.amount) as total_amount
FROM users u
INNER JOIN orders o ON u.id = o.user_id
GROUP BY u.name
ORDER BY order_count DESC;
```

### 4. インデックスの使用状況を確認

```sql
SELECT
    schemaname,
    tablename,
    indexname,
    idx_scan as index_scans,
    idx_tup_read as tuples_read,
    idx_tup_fetch as tuples_fetched
FROM pg_stat_user_indexes
WHERE tablename IN ('users', 'orders')
ORDER BY idx_scan DESC;
```

## パフォーマンス改善の検証

### インデックスなしの場合との比較

インデックスを削除して比較してみましょう：

```sql
-- インデックスを削除
DROP INDEX IF EXISTS idx_orders_user_id;

-- Aliceのデータを取得（インデックスなし）
EXPLAIN ANALYZE
SELECT u.name, o.order_date, o.amount
FROM users u
INNER JOIN orders o ON u.id = o.user_id
WHERE u.id = 1;

-- インデックスを再作成
CREATE INDEX idx_orders_user_id ON orders(user_id);

-- 同じクエリを再実行（インデックスあり）
EXPLAIN ANALYZE
SELECT u.name, o.order_date, o.amount
FROM users u
INNER JOIN orders o ON u.id = o.user_id
WHERE u.id = 1;
```

### カバリングインデックスでさらに最適化

よくアクセスするカラムを含むカバリングインデックスを作成：

```sql
-- 複合インデックス（カバリングインデックス）
CREATE INDEX idx_orders_user_id_covering ON orders(user_id) INCLUDE (order_date, amount);

-- 効果を確認
EXPLAIN ANALYZE
SELECT u.name, o.order_date, o.amount
FROM users u
INNER JOIN orders o ON u.id = o.user_id
WHERE u.id = 1;
```

**期待される効果:**
- Index-Only Scan が可能になり、ヒープアクセスが不要になる場合がある

## 学習ポイント

1. **インデックスは万能ではない**: 大量のデータを取得する場合、Seq Scanの方が効率的
2. **選択性が重要**: データの偏りがクエリプランに大きく影響する
3. **PostgreSQLのオプティマイザは賢い**: データ分布を考慮して最適なプランを選択
4. **実行計画の確認が重要**: EXPLAIN ANALYZEで実際の動作を確認する

## 次のステップ

- データ量を増やして検証（100,000件、1,000,000件など）
- 別の結合方法（Hash Join、Merge Join）との比較
- パーティショニングによる最適化の検証
