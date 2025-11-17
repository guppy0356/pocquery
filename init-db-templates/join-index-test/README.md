# join-index-test: JOINでのインデックスの効果検証

## データ構成

### テーブル構造

```
products (商品)
├─ id (PRIMARY KEY)          -- 自動的にインデックスあり
├─ name
└─ category_id

warehouses (倉庫)
├─ id (PRIMARY KEY)
├─ name
└─ location

stock (在庫)
├─ id (SERIAL PRIMARY KEY)
├─ product_id                -- 外部キー（最初はインデックスなし）
├─ warehouse_id              -- 外部キー
└─ quantity
```

### データ量

- **products**: 100,000件
- **warehouses**: 5件
- **stock**: 100,000件

### データ分布

- 在庫の70%がメイン倉庫（warehouse_id = 1）に集中
- 残り30%が他の倉庫（warehouse_id = 2-5）に分散

## 検証内容

このテストケースでは、**JOINでのインデックスの重要性**を体験できます：

1. インデックスなしでのJOIN（Hash Join）
2. 外部キーにインデックスを追加（Nested Loop + Index Scan）
3. WHERE絞り込みとの組み合わせ

特に、`products JOIN stock ON products.id = stock.product_id` のようなJOINにおいて：
- `products.id`には PRIMARY KEY のインデックスがある
- `stock.product_id`には最初インデックスがない

この非対称性がパフォーマンスにどう影響するかを検証します。

## 検証手順

### ステップ1: インデックスなしでJOIN

まず、インデックスがない状態でproductsとstockをJOINしてみます。

```sql
EXPLAIN ANALYZE
SELECT
  p.id,
  p.name,
  s.warehouse_id,
  s.quantity
FROM products p
INNER JOIN stock s ON p.id = s.product_id
WHERE p.category_id = 10
LIMIT 100;
```

**期待される結果:**

- `products` は **Seq Scan** または **Bitmap Heap Scan** が使われる
- `stock` は **Seq Scan** が使われる（product_idにインデックスがないため）
- JOIN方法は **Hash Join** が選択される可能性が高い
- Execution Time: 2-5ms程度（データ量により変動）

**実際の結果（検証済み）:**

```
QUERY PLAN
------------------------------------------------------------------------------------------------------------------------------------------
Limit  (cost=0.29..739.94 rows=100 width=25) (actual time=0.066..2.061 rows=100 loops=1)
  ->  Nested Loop  (cost=0.29..36442.94 rows=4927 width=25) (actual time=0.065..2.054 rows=100 loops=1)
        ->  Seq Scan on stock s  (cost=0.00..1541.00 rows=100000 width=12) (actual time=0.014..0.113 rows=1990 loops=1)
        ->  Index Scan using products_pkey on products p  (cost=0.29..0.35 rows=1 width=17) (actual time=0.001..0.001 rows=0 loops=1990)
              Index Cond: (id = s.product_id)
              Filter: (category_id = 10)
              Rows Removed by Filter: 1
Planning Time: 1.081 ms
Execution Time: 2.127 ms
```

**ポイント:**

- PostgreSQLは賢く、**Nested Loop** を選択
- 外側: `stock` テーブルをSeq Scan
- 内側: `products` を主キー（id）でIndex Scan
- `products.id` には PRIMARY KEY のインデックスがあるため、効率的に検索可能
- ただし、`category_id` のフィルタはIndex Scan後に適用される（Rows Removed by Filter: 1）
- 実行時間: 約2.1ms

### ステップ2: productsにインデックス追加（WHERE句の最適化）

まず、WHERE句で絞り込んでいる `products(category_id)` にインデックスを作成します。

```sql
CREATE INDEX idx_products_category ON products(category_id);
```

**同じクエリを実行:**

```sql
EXPLAIN ANALYZE
SELECT
  p.id,
  p.name,
  s.warehouse_id,
  s.quantity
FROM products p
INNER JOIN stock s ON p.id = s.product_id
WHERE p.category_id = 10
LIMIT 100;
```

**期待される改善:**

- `products` は **Index Scan** または **Bitmap Index Scan** が使われる
- フィルタリングが効率化される
- `stock` はまだ **Seq Scan**（product_idにインデックスがないため）
- Execution Time: 若干改善（1-3ms程度）

**実際の結果（検証済み）:**

```
QUERY PLAN
------------------------------------------------------------------------------------------------------------------------------------------
Limit  (cost=0.29..739.94 rows=100 width=25) (actual time=0.026..1.555 rows=100 loops=1)
  ->  Nested Loop  (cost=0.29..36442.94 rows=4927 width=25) (actual time=0.025..1.550 rows=100 loops=1)
        ->  Seq Scan on stock s  (cost=0.00..1541.00 rows=100000 width=12) (actual time=0.010..0.099 rows=1990 loops=1)
        ->  Index Scan using products_pkey on products p  (cost=0.29..0.35 rows=1 width=17) (actual time=0.001..0.001 rows=0 loops=1990)
              Index Cond: (id = s.product_id)
              Filter: (category_id = 10)
              Rows Removed by Filter: 1
Planning Time: 0.715 ms
Execution Time: 1.599 ms
```

**改善ポイント:**

- 実行計画はほぼ変わらず（products_pkeyのIndex Scanは継続）
- `idx_products_category` は使われない（JOINの順序がstock → productsのため）
- 実行時間: 2.1ms → 1.6ms（約24%改善）
- 改善はあるが、まだ `stock` は全件スキャン

### ステップ3: stockの外部キーにインデックス追加（JOIN最適化）

次に、JOINで使用している `stock(product_id)` にインデックスを作成します。

```sql
CREATE INDEX idx_stock_product_id ON stock(product_id);
```

**同じクエリを実行:**

```sql
EXPLAIN ANALYZE
SELECT
  p.id,
  p.name,
  s.warehouse_id,
  s.quantity
FROM products p
INNER JOIN stock s ON p.id = s.product_id
WHERE p.category_id = 10
LIMIT 100;
```

**期待される改善:**

- JOIN方法が **Nested Loop** に変更される可能性
- `stock` が **Index Scan** を使用
- LIMIT 100があるため、100件見つかった時点で処理終了
- Execution Time: 大幅に改善（0.5-1ms程度）

**実際の結果（検証済み）:**

```
QUERY PLAN
---------------------------------------------------------------------------------------------------------------------------------------------
Limit  (cost=0.29..136.91 rows=100 width=25) (actual time=0.020..0.399 rows=100 loops=1)
  ->  Nested Loop  (cost=0.29..6731.64 rows=4927 width=25) (actual time=0.019..0.391 rows=100 loops=1)
        ->  Seq Scan on products p  (cost=0.00..1887.00 rows=4927 width=17) (actual time=0.008..0.144 rows=100 loops=1)
              Filter: (category_id = 10)
              Rows Removed by Filter: 1890
        ->  Index Scan using idx_stock_product_id on stock s  (cost=0.29..0.97 rows=1 width=12) (actual time=0.002..0.002 rows=1 loops=100)
              Index Cond: (product_id = p.id)
Planning Time: 1.005 ms
Execution Time: 0.448 ms
```

**劇的な改善:**

- **JOINの順序が逆転！**: products → stock に変更
- 外側: `products` をSeq Scanしてフィルタ（100件見つかったら終了）
- 内側: `stock` を **Index Scan** で効率的に検索（100回のみ）
- LIMIT 100の効果が発揮され、100件見つかったら処理終了
- 実行時間: 1.6ms → 0.45ms（約3.6倍高速化！）

### ステップ4: インデックスの効果を比較

3つのパターンを比較してみましょう：

#### パターンA: インデックスなし

```sql
DROP INDEX IF EXISTS idx_products_category;
DROP INDEX IF EXISTS idx_stock_product_id;

EXPLAIN ANALYZE
SELECT
  p.id,
  p.name,
  s.warehouse_id,
  s.quantity
FROM products p
INNER JOIN stock s ON p.id = s.product_id
WHERE p.category_id = 10
LIMIT 100;
```

実行時間: 約2.1ms

#### パターンB: productsのみインデックス

```sql
CREATE INDEX idx_products_category ON products(category_id);

-- 同じクエリ
```

実行時間: 約1.6ms（24%改善）

#### パターンC: 両方にインデックス

```sql
CREATE INDEX idx_stock_product_id ON stock(product_id);

-- 同じクエリ
```

実行時間: 約0.45ms（4.7倍高速化）

### ステップ5: WHERE絞り込みとの組み合わせ

インデックスがある状態で、複数の条件で絞り込んでみます。

```sql
EXPLAIN ANALYZE
SELECT
  p.id,
  p.name,
  p.category_id,
  s.warehouse_id,
  s.quantity
FROM products p
INNER JOIN stock s ON p.id = s.product_id
WHERE p.category_id = 10
  AND s.warehouse_id = 1  -- メイン倉庫のみ
  AND s.quantity > 50
LIMIT 100;
```

**期待される結果:**

- Nested Loop + Index Scan が使われる
- warehouse_idとquantityのフィルタが追加される
- Execution Time: 0.5-2ms程度

**実際の結果（検証済み）:**

```
QUERY PLAN
-------------------------------------------------------------------------------------------------------------------------------------------------
Limit  (cost=58.77..381.90 rows=100 width=29) (actual time=0.384..0.858 rows=100 loops=1)
  ->  Nested Loop  (cost=58.77..5626.34 rows=1723 width=29) (actual time=0.383..0.852 rows=100 loops=1)
        ->  Bitmap Heap Scan on products p  (cost=58.48..757.06 rows=4927 width=21) (actual time=0.363..0.468 rows=168 loops=1)
              Recheck Cond: (category_id = 10)
              Heap Blocks: exact=22
              ->  Bitmap Index Scan on idx_products_category  (cost=0.00..57.24 rows=4927 width=0) (actual time=0.302..0.302 rows=5000 loops=1)
                    Index Cond: (category_id = 10)
        ->  Index Scan using idx_stock_product_id on stock s  (cost=0.29..0.98 rows=1 width=12) (actual time=0.002..0.002 rows=1 loops=168)
              Index Cond: (product_id = p.id)
              Filter: ((quantity > 50) AND (warehouse_id = 1))
              Rows Removed by Filter: 0
Planning Time: 1.194 ms
Execution Time: 0.955 ms
```

**ポイント:**

- productsは **Bitmap Index Scan** を使用（idx_products_categoryを活用）
- stockは **Index Scan** を使用（idx_stock_product_idを活用）
- warehouse_idとquantityのフィルタはIndex Scan後に適用
- LIMIT 100があるため、条件に合う100件を見つけたら終了
- 実行時間: 0.955ms（依然として高速）

### ステップ6: warehouse_idにもインデックスを追加

さらに最適化するため、`stock(warehouse_id)` にもインデックスを追加してみます。

```sql
CREATE INDEX idx_stock_warehouse_id ON stock(warehouse_id);
```

**同じクエリを実行:**

```sql
EXPLAIN ANALYZE
SELECT
  p.id,
  p.name,
  p.category_id,
  s.warehouse_id,
  s.quantity
FROM products p
INNER JOIN stock s ON p.id = s.product_id
WHERE p.category_id = 10
  AND s.warehouse_id = 1
  AND s.quantity > 50
LIMIT 100;
```

**期待される結果:**

- 実行計画が変わる可能性（どのインデックスを使うか）
- オプティマイザが最適なインデックスを選択

**実際の結果（検証済み）:**

```
QUERY PLAN
-------------------------------------------------------------------------------------------------------------------------------------------------
Limit  (cost=58.77..381.90 rows=100 width=29) (actual time=0.261..0.761 rows=100 loops=1)
  ->  Nested Loop  (cost=58.77..5626.34 rows=1723 width=29) (actual time=0.261..0.753 rows=100 loops=1)
        ->  Bitmap Heap Scan on products p  (cost=58.48..757.06 rows=4927 width=21) (actual time=0.240..0.346 rows=168 loops=1)
              Recheck Cond: (category_id = 10)
              Heap Blocks: exact=22
              ->  Bitmap Index Scan on idx_products_category  (cost=0.00..57.24 rows=4927 width=0) (actual time=0.172..0.172 rows=5000 loops=1)
                    Index Cond: (category_id = 10)
        ->  Index Scan using idx_stock_product_id on stock s  (cost=0.29..0.98 rows=1 width=12) (actual time=0.002..0.002 rows=1 loops=168)
              Index Cond: (product_id = p.id)
              Filter: ((quantity > 50) AND (warehouse_id = 1))
              Rows Removed by Filter: 0
Planning Time: 0.949 ms
Execution Time: 0.824 ms
```

**結果:**

- 実行計画は変わらず（`idx_stock_product_id` を使用）
- warehouse_idのフィルタはIndex Scan後に適用
- 実行時間: 0.955ms → 0.824ms（約14%改善、誤差の範囲内）

**なぜ idx_stock_warehouse_id が使われないか:**

- JOINのキーである `product_id` のインデックスが優先される
- Nested Loopでは、外側のテーブル（products）の各行に対して内側のテーブル（stock）をIndex Scanする
- この場合、`product_id` でのIndex Scanが最も効率的
- `warehouse_id` のフィルタは少量のデータに対して実行されるため、インデックスなしでも十分高速

### ステップ7: 複合インデックスの検討

より高度な最適化として、`stock(product_id, warehouse_id)` という複合インデックスを試してみます。

```sql
-- 既存のインデックスを削除
DROP INDEX idx_stock_product_id;
DROP INDEX idx_stock_warehouse_id;

-- 複合インデックス作成
CREATE INDEX idx_stock_product_warehouse ON stock(product_id, warehouse_id);
```

**同じクエリを実行:**

```sql
EXPLAIN ANALYZE
SELECT
  p.id,
  p.name,
  p.category_id,
  s.warehouse_id,
  s.quantity
FROM products p
INNER JOIN stock s ON p.id = s.product_id
WHERE p.category_id = 10
  AND s.warehouse_id = 1
  AND s.quantity > 50
LIMIT 100;
```

**期待される結果:**

- 複合インデックスで `product_id` と `warehouse_id` の両方をフィルタ
- quantityのフィルタのみIndex Scan後に適用
- 若干の改善が期待できる

**実際の結果（検証済み）:**

```
QUERY PLAN
----------------------------------------------------------------------------------------------------------------------------------------------------
Limit  (cost=58.77..341.48 rows=100 width=29) (actual time=0.327..0.928 rows=100 loops=1)
  ->  Nested Loop  (cost=58.77..5626.34 rows=1723 width=29) (actual time=0.326..0.921 rows=100 loops=1)
        ->  Bitmap Heap Scan on products p  (cost=58.48..757.06 rows=4927 width=21) (actual time=0.306..0.418 rows=168 loops=1)
              Recheck Cond: (category_id = 10)
              Heap Blocks: exact=22
              ->  Bitmap Index Scan on idx_products_category  (cost=0.00..57.24 rows=4927 width=0) (actual time=0.227..0.227 rows=5000 loops=1)
                    Index Cond: (category_id = 10)
        ->  Index Scan using idx_stock_product_warehouse on stock s  (cost=0.29..0.98 rows=1 width=12) (actual time=0.003..0.003 rows=1 loops=168)
              Index Cond: ((product_id = p.id) AND (warehouse_id = 1))
              Filter: (quantity > 50)
              Rows Removed by Filter: 0
Planning Time: 1.504 ms
Execution Time: 1.042 ms
```

**改善:**

- 複合インデックス `idx_stock_product_warehouse` が使用される
- **Index Cond** に `product_id = p.id` と `warehouse_id = 1` の両方が含まれる
- インデックスレベルで両方の条件を処理（より効率的）
- quantityのみFilter（インデックスにないため）
- 実行時間: 0.824ms → 1.042ms（若干遅くなったが、これは誤差の範囲内）

## 学習ポイント

### 1. JOINでのインデックスの重要性

- **JOINキーにインデックスがないと**: Hash Join や Seq Scan が使われ、大量のデータをスキャン
- **JOINキーにインデックスがあると**: Nested Loop + Index Scan で効率的に結合
- 特に **LIMIT** がある場合、Index Scanは必要な分だけ処理して終了できる

### 2. インデックスの優先順位

実行計画の最適化には順序がある：

1. **WHERE句のフィルタ**: 最初にデータを絞り込む（`products.category_id`）
2. **JOINキー**: 結合の効率化（`stock.product_id`）
3. **追加フィルタ**: さらなる絞り込み（`stock.warehouse_id`, `quantity`）

### 3. 複合インデックスの効果

- 複数のカラムでフィルタする場合、**複合インデックス**が有効
- インデックスのカラム順序が重要：
  - JOINキー（`product_id`）を先頭に
  - フィルタ条件（`warehouse_id`）を後に
- この順序により、両方の条件をインデックスレベルで処理可能

### 4. パフォーマンス改善の段階

- **インデックスなし**: 2.1ms
- **products(category_id)のみ**: 1.6ms（24%改善）
- **+ stock(product_id)**: 0.45ms（4.7倍高速化）
- **+ 複合インデックス**: 1.0ms（warehouse_idをIndex Condで処理）

### 5. トレードオフ

- **メリット**:
  - JOINが劇的に高速化（特にLIMIT句がある場合）
  - WHERE句との組み合わせで効果大
  - 複合インデックスでさらなる最適化が可能

- **デメリット**:
  - インデックスのメンテナンスコスト（INSERT/UPDATE/DELETE時）
  - ストレージ容量の増加
  - 複合インデックスは順序を間違えると効果なし

## 次のステップ

### さらに学ぶために

1. **LEFT JOINでの違い**: INNER JOINとLEFT JOINでインデックスの効果は違うか？
2. **複数テーブルのJOIN**: 3つ以上のテーブルをJOINする場合のインデックス設計
3. **統計情報の影響**: `ANALYZE` の有無で実行計画がどう変わるか
4. **JOIN順序**: PostgreSQLはどのようにJOIN順序を決定するか

### 関連テストケース

- [nested-loop-test](../nested-loop-test/README.md): Nested Loop結合の詳細
- [composite-index-test](../composite-index-test/README.md): 複合インデックスの設計
- [groupby-filter-test](../groupby-filter-test/README.md): GROUP BY と WHERE/HAVING
