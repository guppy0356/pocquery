# 複合インデックステスト: Sort Aggregate vs Hash Aggregate

## データ構成

### テーブル構造

**shops（店舗マスター）**
- `id`: 店舗ID（主キー）
- `name`: 店舗名
- `region`: 地域（North/South/East/West）
- データ件数: **100店舗**

**orders（注文テーブル）**
- `id`: 注文ID（主キー）
- `shop_id`: 店舗ID
- `shipped_date`: 出荷日
- `customer_id`: 顧客ID
- `total_amount`: 注文金額
- データ件数: **5,000,000件**

### データ分布

**shipped_dateの分布:**
- 直近1日（今日）: 約20,000件（**0.4%**）← WHEREで絞り込む対象
- 2日以降: 約4,980,000件（99.6%）

**shop_idの分布:**
- 100店舗に均等に分散（各店舗約50,000件）

この分布により、WHERE句で今日のデータを絞り込むと約2万件（0.4%）に絞られ、その中でshop_id（100店舗）でGROUP BYする構造になっています。データ量が非常に多く、絞り込み率が極めて低いため、複合インデックスを使ったIndex Scan + GroupAggregateが効果的です。

## 検証内容

複合インデックスが**Sort Aggregate**を引き起こし、単一インデックスやインデックスなしの**Hash Aggregate**よりも高速になることを体験します。

### 学べること

1. **Hash Aggregate vs Sort Aggregate**
   - Hash Aggregateはグルーピング前に全行をメモリ上のハッシュテーブルに格納
   - Sort Aggregateはソート済みデータを順次読み取りながら集計（メモリ効率が良い）

2. **複合インデックスのカラム順序の重要性**
   - `(shipped_date, shop_id)` の順序が重要
   - WHEREで使うカラムを先頭に、GROUP BYで使うカラムを2番目に配置

3. **オプティマイザの判断**
   - インデックスの選択性とクエリパターンによって実行計画が変わる

## 検証手順

接続コマンド:
```bash
docker exec -it pocquery_postgres psql -U postgres -d pocquery
```

### ステップ1: インデックスなしの状態（Hash Aggregate）

まず、インデックスが存在しない状態で店舗ごとの今日の売上を集計します。

```sql
EXPLAIN ANALYZE
SELECT
  shop_id,
  COUNT(*) as order_count,
  SUM(total_amount) as total_sales,
  AVG(total_amount)::INT as avg_sales
FROM orders
WHERE shipped_date = CURRENT_DATE
GROUP BY shop_id
ORDER BY shop_id;
```

**期待される結果:**

```
Sort  (cost=... rows=100 ...)
  Sort Key: shop_id
  ->  HashAggregate  (cost=... rows=100 ...)
        Group Key: shop_id
        ->  Seq Scan on orders  (cost=... rows=約20000 ...)
              Filter: (shipped_date >= ...)
              Rows Removed by Filter: 約4980000
```

**ポイント:**
- ✅ **Seq Scan**: 全行スキャンが発生（5,000,000件）
- ✅ **Rows Removed by Filter**: 約450,000件がフィルタで除外される（90%が無駄）
- ✅ **HashAggregate**: メモリ上でハッシュテーブルを使って集計
- ✅ **Sort**: 最後にORDER BY用のソートが別途必要
- 実行時間: 100-200ms程度

### ステップ2: shipped_dateのみのインデックス（まだHash Aggregate）

WHERE句で使うカラムにインデックスを作成します。

```sql
CREATE INDEX idx_orders_shipped_date ON orders(shipped_date);
ANALYZE orders;
```

同じクエリを実行:

```sql
EXPLAIN ANALYZE
SELECT
  shop_id,
  COUNT(*) as order_count,
  SUM(total_amount) as total_sales,
  AVG(total_amount)::INT as avg_sales
FROM orders
WHERE shipped_date = CURRENT_DATE
GROUP BY shop_id
ORDER BY shop_id;
```

**期待される改善:**

```
Sort  (cost=... rows=100 ...)
  Sort Key: shop_id
  ->  HashAggregate  (cost=... rows=100 ...)
        Group Key: shop_id
        ->  Bitmap Heap Scan on orders  (cost=... rows=約20000 ...)
              Recheck Cond: (shipped_date >= ...)
              ->  Bitmap Index Scan on idx_orders_shipped_date
                    Index Cond: (shipped_date >= ...)
```

**改善されたポイント:**
- ✅ **Bitmap Index Scan**: インデックスを使って効率的に絞り込み
- ✅ Rows Removed by Filterがなくなる（必要な行だけ読む）
- ❌ **まだHashAggregate**: GROUP BYはハッシュテーブルを使用
- ❌ **まだSort**: ORDER BY用のソートが別途必要
- 実行時間: 50-100ms程度（やや改善）

**なぜSort Aggregateにならないのか？**

インデックスは`shipped_date`の順序でデータを返しますが、GROUP BYに必要な`shop_id`の順序ではありません。したがって、PostgreSQLはハッシュテーブルを使う方が効率的と判断します。

### ステップ3: 複合インデックス作成（GroupAggregateに変化！）

WHERE句とGROUP BY句の両方を考慮した複合インデックスを作成します。

```sql
-- 既存のインデックスを削除
DROP INDEX idx_orders_shipped_date;

-- 複合インデックス作成（shipped_date, shop_id の順序）
CREATE INDEX idx_orders_shipped_shop ON orders(shipped_date, shop_id);
ANALYZE orders;
```

**重要**: 複合インデックスの効果を最大限に引き出すため、GROUP BYの順序をインデックスと一致させ、LIMITを追加します。

```sql
EXPLAIN ANALYZE
SELECT
  shipped_date,
  shop_id,
  COUNT(*) as order_count,
  SUM(total_amount) as total_sales
FROM orders
WHERE shipped_date = CURRENT_DATE
GROUP BY shipped_date, shop_id  -- インデックスの順序と一致
ORDER BY shipped_date, shop_id
LIMIT 10;  -- トップ10店舗を取得
```

**期待される劇的な改善:**

```
Limit  (cost=0.43..40.42 rows=10 width=24) (actual time=0.478..0.846 rows=10 loops=1)
  ->  GroupAggregate  (cost=0.43..61661.06 rows=15421 width=24) (actual time=0.478..0.845 rows=10 loops=1)
        Group Key: shipped_date, shop_id
        ->  Index Scan using idx_orders_shipped_shop on orders  (cost=0.43..61306.85 rows=20000 width=12) (actual time=0.040..0.701 rows=2001 loops=1)
              Index Cond: (shipped_date = CURRENT_DATE)
Planning Time: 0.952 ms
Execution Time: 1.098 ms
```

**劇的に改善されたポイント:**
- ✅ **Index Scan**: 複合インデックスを使った効率的なスキャン
- ✅ **GroupAggregate**: ソート済みデータを順次集計
  - メモリ上のハッシュテーブルが不要
  - インデックスの順序で既にソート済み
- ✅ **LIMIT早期終了**: 10グループ取得後、即座に終了（残り90グループをスキャンしない）
- ✅ **Sortが消えた**: インデックスの順序がGROUP BY/ORDER BYと一致
- 実行時間: 約1.1ms

**なぜGroupAggregateになったのか？**

LIMITがあることで、PostgreSQLは以下を判断しました：
1. Index Scanで順次データを読み取り、GroupAggregateで集計
2. 10グループに達したら即座に終了（早期終了）
3. 全データをスキャンするBitmap Scan + HashAggregateより効率的

複合インデックス`(shipped_date, shop_id)`は、以下の順序でデータを保持しています：

```
(2025-11-10, shop_id=1)  <- 1番目のグループ
(2025-11-10, shop_id=2)  <- 2番目のグループ
...
(2025-11-10, shop_id=10) <- 10番目のグループ、ここでLIMIT達成
(2025-11-10, shop_id=11) <- スキャンされない
...
(2025-11-10, shop_id=100)
```

GROUP BY句が`(shipped_date, shop_id)`とインデックスの順序と完全に一致しているため、PostgreSQLはIndex Scanで取得したデータをそのまま（ソートなしで）GroupAggregateできます。さらに、LIMITにより必要なグループ数だけ処理して終了できます。

### ステップ4: LIMITなしの全データ集計（HashAggregateに戻る）

LIMITを削除して、全100店舗のデータを集計してみます。

```sql
EXPLAIN ANALYZE
SELECT
  shipped_date,
  shop_id,
  COUNT(*) as order_count,
  SUM(total_amount) as total_sales
FROM orders
WHERE shipped_date = CURRENT_DATE
GROUP BY shipped_date, shop_id
ORDER BY shipped_date, shop_id;
```

**期待される結果:**

```
Sort  (cost=31274.53..31313.08 rows=15421 width=24) (actual time=6.960..6.964 rows=100 loops=1)
  Sort Key: shop_id
  Sort Method: quicksort  Memory: 31kB
  ->  HashAggregate  (cost=30047.59..30201.80 rows=15421 width=24) (actual time=6.820..6.918 rows=100 loops=1)
        Group Key: shipped_date, shop_id
        Batches: 1  Memory Usage: 801kB
        ->  Bitmap Heap Scan on orders  (cost=231.44..29847.59 rows=20000 width=12) (actual time=0.957..4.474 rows=20000 loops=1)
              Recheck Cond: (shipped_date = CURRENT_DATE)
              Heap Blocks: exact=128
              ->  Bitmap Index Scan on idx_orders_shipped_shop  (cost=0.00..226.44 rows=20000 width=0) (actual time=0.928..0.928 rows=20000 loops=1)
                    Index Cond: (shipped_date = CURRENT_DATE)
Planning Time: 1.467 ms
Execution Time: 7.398 ms
```

実行時間: 約7.4ms

**なぜGroupAggregateにならないのか？**

LIMITがない場合、PostgreSQLは以下のコスト比較を行います：

1. **Index Scan + GroupAggregate**: 全20,000行を順次スキャン → コスト約61,661
2. **Bitmap Scan + HashAggregate**: ランダムアクセスで取得してメモリで集計 → コスト約31,313

全データをスキャンする必要がある場合、Bitmap Scanの方がランダムアクセスを効率的に処理できるため、HashAggregateが選ばれます。

**LIMITあり（ステップ3）との比較:**

| 項目 | ステップ3（LIMIT 10） | ステップ4（LIMITなし） |
|------|---------------------|---------------------|
| スキャン方法 | Index Scan | Bitmap Heap Scan |
| 集計方法 | GroupAggregate | HashAggregate |
| 実行時間 | 約1.1ms | 約7.4ms |
| 処理行数 | 約2,001行（早期終了） | 20,000行（全行） |

**重要な原則:**
- LIMITが小さい場合、Index Scan + GroupAggregateで早期終了が有利
- 全データを処理する場合、Bitmap Scan + HashAggregateの方が効率的
- クエリの目的（一部取得 vs 全件集計）によって最適な実行計画が変わる

### ステップ5: カラム順序の重要性（逆順だと効果なし）

複合インデックスのカラム順序を逆にすると、WHERE句での絞り込みが非効率になります。

```sql
-- 逆順の複合インデックスを作成
DROP INDEX idx_orders_shipped_shop;
CREATE INDEX idx_orders_shop_shipped ON orders(shop_id, shipped_date);
ANALYZE orders;
```

ステップ3のクエリ（`GROUP BY shipped_date, shop_id`）を実行:

```sql
EXPLAIN ANALYZE
SELECT
  shipped_date,
  shop_id,
  COUNT(*) as order_count,
  SUM(total_amount) as total_sales
FROM orders
WHERE shipped_date = CURRENT_DATE
GROUP BY shipped_date, shop_id
ORDER BY shipped_date, shop_id;
```

**期待される結果:**

```
Sort  (cost=... rows=... ...)
  Sort Key: shipped_date, shop_id
  ->  HashAggregate  (cost=... rows=... ...)
        Group Key: shipped_date, shop_id
        ->  Seq Scan on orders  (cost=... rows=約20000 ...)
              Filter: (shipped_date >= ...)
              Rows Removed by Filter: 約4980000
```

**なぜ逆戻りしたのか？**

インデックス`(shop_id, shipped_date)`は以下の順序でデータを保持しています：

```
(shop_id=1, 2025-01-01)
(shop_id=1, 2025-01-15)
(shop_id=1, 2025-02-10)
...
(shop_id=2, 2025-01-01)
...
```

この順序では、WHERE句`shipped_date >= '2025-01-15'`で効率的に絞り込めません。各shop_idごとに全期間をスキャンする必要があり、インデックスの効果が薄れます。そのため、PostgreSQLはSeq Scanを選択します。

### ステップ6: 正しいインデックスに戻す

検証後、正しいインデックスに戻しておきます。

```sql
-- 正しい順序の複合インデックスを再作成
DROP INDEX idx_orders_shop_shipped;
CREATE INDEX idx_orders_shipped_shop ON orders(shipped_date, shop_id);
ANALYZE orders;
```

## 実行計画の比較まとめ

| ステップ | クエリパターン | スキャン方法 | 集計方法 | ソート | 実行時間 | 処理行数 |
|---------|---------------|-------------|---------|--------|---------|---------|
| 1 | インデックスなし | Seq Scan | HashAggregate | Sort必要 | 約150ms | 5,000,000行 |
| 2 | shipped_dateのみ | Bitmap Scan | HashAggregate | Sort必要 | 約13ms | 20,000行 |
| 3 | **(shipped_date, shop_id) + LIMIT 10** | **Index Scan** | **GroupAggregate** | **不要** | **約1.1ms** | **約2,001行** |
| 4 | (shipped_date, shop_id) + LIMITなし | Bitmap Scan | HashAggregate | Sort必要 | 約7.4ms | 20,000行 |
| 5 | (shop_id, shipped_date) + GROUP BY shipped_date, shop_id | Seq Scan | HashAggregate | Sort必要 | 約150ms | 5,000,000行 |

**重要な発見:**
- ステップ3が最も効率的（Index Scan + GroupAggregate + 早期終了）
- **LIMITがあると早期終了が可能**で、GroupAggregateが選ばれる
- **GROUP BYの順序がインデックスと一致**していることが必須
- LIMITなし（ステップ4）ではBitmap Scan + HashAggregateの方が効率的
- カラム順序が逆だと、WHERE句での絞り込みが非効率（ステップ5）

## 学習ポイント

### 1. Hash Aggregate vs Sort Aggregate（Group Aggregate）

**Hash Aggregate:**
- グルーピング前に全行をメモリ上のハッシュテーブルに格納
- ランダムアクセスが多い
- work_memを超えるとディスクを使う（遅くなる）
- データが既にソート済みでなくても使える

**Sort Aggregate (Group Aggregate):**
- ソート済みデータを順次読み取りながら集計
- メモリ使用量が少ない（現在のグループの集計値だけ保持）
- インデックスの順序を活用できる
- 大量データでもメモリ効率が良い

### 2. 複合インデックスのカラム順序の原則

複合インデックスは**左から順に**機能します：

1. **WHERE句で絞り込むカラムを先頭に**
   - 最初の条件で大量のデータを絞り込む
   - 例: `shipped_date >= ...` で90%削減

2. **GROUP BYで使うカラムを2番目以降に**
   - 絞り込まれたデータがGROUP BYのカラムでソート済みになる
   - Sort Aggregateが使える

3. **逆順は機能しない**
   - `(shop_id, shipped_date)`ではWHERE句で効率的に絞り込めない

### 3. インデックスの順序とクエリの関係

複合インデックス`(A, B)`は以下のクエリで有効：
- ✅ `WHERE A = ? AND B = ?`
- ✅ `WHERE A = ?`
- ✅ `WHERE A >= ? GROUP BY B`（Sort Aggregateが使える）
- ❌ `WHERE B = ?`（Aがないと使えない）
- ❌ `WHERE B >= ? GROUP BY A`（順序が逆）

### 4. LIMITとGroupAggregateの相性

**LIMIT付きクエリでGroupAggregateが有利になる理由:**

1. **早期終了が可能**
   - Index Scan + GroupAggregateは必要なグループ数に達したら即座に終了
   - 例: LIMIT 10の場合、10グループ取得後に残りのデータをスキャンしない

2. **コスト比較**
   - LIMIT小: Index Scan + GroupAggregate（早期終了で有利）
   - LIMITなし: Bitmap Scan + HashAggregate（全データ処理で効率的）

3. **実務での応用例**
   - トップNランキング: `SELECT ... GROUP BY ... ORDER BY ... LIMIT N`
   - ページネーション: `LIMIT 20 OFFSET 0`
   - ダッシュボード: 最新N件の集計表示

**実測例（本テストケースの場合）:**

| LIMIT値 | 実行計画 | 実行時間 |
|---------|---------|---------|
| 10 | Index Scan + GroupAggregate | 約1.1ms（早期終了） |
| なし（100行） | Bitmap Scan + HashAggregate | 約7.4ms（全行処理） |

**重要:** LIMITの有無で最適な実行計画が変わることを理解し、クエリの目的に応じた設計が重要。

### 5. 実務での応用

**典型的なパターン:**
```sql
-- 日次/月次レポート
SELECT date, category, SUM(amount)
FROM sales
WHERE date >= '2025-01-01'  -- 期間絞り込み
GROUP BY date, category      -- 集計
ORDER BY date, category;

-- 最適な複合インデックス
CREATE INDEX idx_sales ON sales(date, category);
```

**トレードオフ:**
- 複合インデックスはディスクスペースを消費
- 書き込み（INSERT/UPDATE）が若干遅くなる
- 読み取りクエリが大幅に高速化される場合は導入する価値がある

## 次のステップ

1. **INCLUDE句を使った複合インデックス**
   - `CREATE INDEX idx ON orders(shipped_date, shop_id) INCLUDE (total_amount);`
   - Index-Only Scanが可能に

2. **パーティショニングとの組み合わせ**
   - shipped_dateでパーティション分割
   - 各パーティション内で複合インデックス

3. **他の集計関数での検証**
   - COUNT, SUM以外の関数（MIN, MAX, PERCENTILE）
   - HAVING句を追加した場合の挙動

4. **work_memの影響**
   - Hash Aggregateがディスクを使う場合の性能劣化
   - Sort Aggregateの優位性

## まとめ

複合インデックスは単なる「複数カラムのインデックス」ではなく、**カラムの順序が実行計画に大きく影響**します。

特に、`WHERE + GROUP BY + ORDER BY`のパターンでは、複合インデックスによってSort Aggregateを引き出し、ハッシュテーブルやソート処理を削減できます。これにより、**メモリ効率**と**実行速度**の両方が改善されます。

実務では、頻繁に実行されるレポートクエリや集計クエリに対して、複合インデックスを適切に設計することで大幅なパフォーマンス改善が期待できます。
