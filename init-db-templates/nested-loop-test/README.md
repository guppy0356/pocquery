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

#### 📚 深掘り: Bitmap Scan の仕組み

Aliceのクエリで使われた **Bitmap Index Scan** と **Bitmap Heap Scan** の動作を理解しましょう。

実際の実行計画：
```
Nested Loop
  ->  Index Scan using users_pkey on users u
  ->  Bitmap Heap Scan on orders o              ← ステップ2
        Recheck Cond: (user_id = 1)
        Heap Blocks: exact=6                    ← 6ページ読んだ
        ->  Bitmap Index Scan on idx_orders_user_id  ← ステップ1
              Index Cond: (user_id = 1)
```

**2つのステップ:**

**ステップ1: Bitmap Index Scan**
- インデックスをスキャンして、条件に合う行の番号を集める
- 「行100, 行101, 行250, 行500, ...」というリストを作成（ビットマップ）
- まだ実際のデータは取得していない

**ステップ2: Bitmap Heap Scan**
- ビットマップの行番号を**ページ単位**でグループ化
- ヒープ（テーブル本体）から効率的にデータを取得
- `Heap Blocks: exact=6` = 6ページを読み取った

**なぜページ単位なのか？**

PostgreSQLは**1ページ = 8KB**のブロック単位でデータを読みます。これはディスクの仕組みによる制約です：

```
❌ できないこと: 「行100の100バイトだけ読む」
✅ 実際の動作: 「ページ1全体（8KB）を読んで、その中から行100を取り出す」
```

**Bitmapの効率化:**

```
非効率な方法（1件ずつ）:
1. ページ1を読む（行100取得）
2. ページ7を読む（行500取得）
3. ページ1を読む（行101取得）← 同じページをまた読む！
→ 同じページを何度も読む無駄が発生

効率的な方法（Bitmap使用）:
1. 必要な行番号を全部集める: [100, 500, 101, 250, ...]
2. ページ単位でグループ化: ページ1=[100,101,...], ページ7=[500,...]
3. 各ページを1回だけ読む
→ ディスクアクセスが大幅に削減！
```

今回のケースでは、1,000件のデータがたった6ページに収まっており、Bitmapを使うことで各ページを1回だけ読めば済みます。

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
    relname as tablename,
    indexrelname as indexname,
    idx_scan as index_scans,
    idx_tup_read as tuples_read,
    idx_tup_fetch as tuples_fetched
FROM pg_stat_user_indexes
WHERE relname IN ('users', 'orders')
ORDER BY idx_scan DESC;
```

**確認ポイント:**
- `idx_orders_user_id` の `index_scans` が増えているか
- どのクエリでインデックスが使われたか

#### 📊 結果の見方

実際の出力例：
```
schemaname | tablename | indexname              | index_scans | tuples_read | tuples_fetched
-----------+-----------+------------------------+-------------+-------------+----------------
public     | users     | users_pkey             | 5           | 5           | 5
public     | orders    | idx_orders_user_id     | 1           | 1000        | 0
public     | orders    | orders_pkey            | 0           | 0           | 0
```

**各カラムの意味:**

| カラム | 意味 | 例の解釈 |
|--------|------|---------|
| **index_scans** | インデックススキャン回数 | `idx_orders_user_id`は1回だけ使われた |
| **tuples_read** | インデックスから読んだエントリ数 | 1,000件読んだ |
| **tuples_fetched** | Index Scanでヒープから取得した行数 | 0 = Bitmap Scanなので別統計 |

**なぜ idx_orders_user_id が1回だけ？**

検証で実行したクエリ：
1. ✅ Alice (user_id=1, 10%): **インデックス使用** → index_scans: 1
2. ❌ Bob (user_id=2, 80%): **Seq Scan** → インデックス使わず
3. ❌ 集計クエリ（全件）: **Hash Join + Seq Scan** → インデックス使わず

**重要な発見:**
- インデックスが存在しても、常に使われるわけではない
- データの選択性（10% vs 80%）がクエリプランを大きく左右する
- オプティマイザは賢くコストを計算している

**tuples_read vs tuples_fetched の違い:**

- **tuples_read**: インデックスから読んだエントリ数（常にカウント）
- **tuples_fetched**: Index Scanで直接ヒープから取得した行数
  - Bitmap Index Scanの場合は0（別の統計でカウント）
  - Index Only Scanの場合も0（ヒープアクセスなし）

今回は `tuples_read=1000, tuples_fetched=0` なので、Bitmap Scanが使われたことが分かります。

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
