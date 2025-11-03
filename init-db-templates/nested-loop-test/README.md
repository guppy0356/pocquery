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
  - `orders.user_id`: **インデックスなし**（パフォーマンス改善の検証用）

## 検証内容

このテストケースでは、以下の現象を段階的に体験できます：

1. **インデックスなし**: Seq Scanでの性能を確認
2. **インデックス追加**: パフォーマンス改善を確認
3. **データの偏り**: 少数/大量データでのクエリプランの違いを確認

## 検証手順

### ステップ1: インデックスなしの状態を確認

まず、インデックスがない状態でクエリを実行します。

#### Aliceのデータを取得（全体の10%）

```sql
EXPLAIN ANALYZE
SELECT u.name, o.order_date, o.amount
FROM users u
INNER JOIN orders o ON u.id = o.user_id
WHERE u.id = 1;
```

**結果:**
- `orders` テーブルに対して **Seq Scan** が使用される
- フィルタ条件で 9,000件を除外（Rows Removed by Filter）
- 少量のデータを取得するのに全件スキャンが発生

#### Bobのデータを取得（全体の80%）

```sql
EXPLAIN ANALYZE
SELECT u.name, o.order_date, o.amount
FROM users u
INNER JOIN orders o ON u.id = o.user_id
WHERE u.id = 2;
```

**結果:**
- こちらも **Seq Scan**
- 大量のデータを取得する場合は、Seq Scanでも比較的効率的

### ステップ2: インデックスを作成

パフォーマンス改善のために、`orders.user_id` にインデックスを作成します：

```sql
CREATE INDEX idx_orders_user_id ON orders(user_id);
```

### ステップ3: インデックス作成後の性能を確認

#### Aliceのデータを再取得

```sql
EXPLAIN ANALYZE
SELECT u.name, o.order_date, o.amount
FROM users u
INNER JOIN orders o ON u.id = o.user_id
WHERE u.id = 1;
```

**期待される改善:**
- `orders` テーブルに対して **Bitmap Index Scan** が使用される
- Seq Scanと比較して大幅に高速化
- 不要な行を読み飛ばすことができる

#### Bobのデータを再取得

```sql
EXPLAIN ANALYZE
SELECT u.name, o.order_date, o.amount
FROM users u
INNER JOIN orders o ON u.id = o.user_id
WHERE u.id = 2;
```

**興味深い結果:**
- インデックスが存在しても **Seq Scan** が選択される可能性が高い
- 全体の80%のデータを取得する場合、インデックスを使うよりSeq Scanの方が効率的
- PostgreSQLのオプティマイザがコストを計算して最適なプランを選択

### ステップ4: 全ユーザーのデータを集計

インデックスがある状態で、全ユーザーの集計クエリを実行します：

```sql
EXPLAIN ANALYZE
SELECT u.name, COUNT(*) as order_count, SUM(o.amount) as total_amount
FROM users u
INNER JOIN orders o ON u.id = o.user_id
GROUP BY u.name
ORDER BY order_count DESC;
```

**確認ポイント:**
- 全件取得する場合の実行計画
- Hash Join や Merge Join が使われる可能性

### ステップ5: インデックスの使用状況を確認

実際にインデックスが使われているか統計情報で確認します：

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

**確認ポイント:**
- `idx_orders_user_id` の `index_scans` が増えているか
- どのクエリでインデックスが使われたか

## さらなる最適化

### カバリングインデックスで高速化

よくアクセスするカラムを含むカバリングインデックスを作成します：

```sql
-- 既存のインデックスを削除
DROP INDEX IF EXISTS idx_orders_user_id;

-- カバリングインデックスを作成
CREATE INDEX idx_orders_user_id_covering ON orders(user_id) INCLUDE (order_date, amount);

-- 効果を確認
EXPLAIN ANALYZE
SELECT u.name, o.order_date, o.amount
FROM users u
INNER JOIN orders o ON u.id = o.user_id
WHERE u.id = 1;
```

**期待される効果:**
- Index-Only Scan が可能になる場合がある
- ヒープアクセスが不要になり、さらに高速化

### インデックスの削除（元に戻す）

検証が終わったら、インデックスを削除して初期状態に戻せます：

```sql
DROP INDEX IF EXISTS idx_orders_user_id;
DROP INDEX IF EXISTS idx_orders_user_id_covering;
```

## 学習ポイント

1. **段階的な改善の重要性**: インデックスなしから始めることで、改善効果を体感できる
2. **インデックスは万能ではない**: 大量のデータを取得する場合、Seq Scanの方が効率的
3. **選択性が重要**: データの偏り（10% vs 80%）がクエリプランに大きく影響する
4. **PostgreSQLのオプティマイザは賢い**: データ分布を考慮して最適なプランを選択
5. **実行計画の確認が重要**: EXPLAIN ANALYZEで実際の動作を確認する
6. **カバリングインデックスの効果**: Index Only Scanでヒープアクセスを削減できる

## カバリングインデックスのトレードオフ

カバリングインデックスは強力ですが、万能ではありません。

### メリット
- **ヒープアクセス不要**: `Heap Fetches: 0` でテーブル本体を読まない
- **読み取り高速化**: 必要なデータが全てインデックスに含まれる
- **I/O削減**: ディスクアクセスが減る

### デメリット
- **インデックスサイズ増大**: 全カラムを含めると数倍のサイズになる
- **書き込み性能低下**: INSERT/UPDATE/DELETEで更新するデータが増える
- **メンテナンスコスト**: スキーマ変更時にインデックス再構築が必要

### 適切な使い所

**✅ 作るべき場面:**
- 頻繁に実行される特定のクエリがある
- 読み取り:書き込み = 9:1 以上
- 含めるカラム数が少ない（2-3カラム程度）

**❌ 避けるべき場面:**
- 「念のため」全カラムをカバー
- 書き込みが多いテーブル
- インデックスサイズがメモリに乗り切らない

### 実践的なアプローチ

1. **まず通常のインデックス**から始める
2. **遅いクエリを特定**する（EXPLAIN ANALYZEで確認）
3. **ピンポイントで最適化**（特定の重要クエリだけカバリング）

```sql
-- 良い例: 特定のクエリ専用
CREATE INDEX idx_dashboard_query ON orders(user_id)
INCLUDE (order_date, amount);

-- 悪い例: やりすぎ
CREATE INDEX idx_everything ON orders(user_id)
INCLUDE (id, order_date, amount, status, created_at, updated_at, ...);
```

## 次のステップ

- データ量を増やして検証（100,000件、1,000,000件など）
- 別の結合方法（Hash Join、Merge Join）との比較
- パーティショニングによる最適化の検証
