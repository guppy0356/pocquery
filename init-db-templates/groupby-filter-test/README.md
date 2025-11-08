# GROUP BY Filter Test: WHERE vs HAVING

このテストケースでは、GROUP BYを使った集計クエリにおいて、**WHERE（集計前フィルタ）** と **HAVING（集計後フィルタ）** のパフォーマンス差を検証します。

## データ構成

このテストケースには3つのテーブルがあります：

- **shops**: 1,000店舗
  - `id`, `name`

- **orders**: 500,000件の注文データ
  - `id`, `shop_id`, `customer_id`, `order_day`（注文日）, `ship_day`（発送日）
  - データ分布: **11-12月に60%** (300,000件)、**1-10月に40%** (200,000件)
  - `ship_day` は `order_day` の 1-7日後
  - 初期状態: **インデックスなし**

- **items**: 2,000,000件の注文明細
  - `id`, `order_id`, `product_name`, `price`（1,000円〜50,000円）
  - 平均4件/注文

## 検証内容

このテストケースで学べること：

- **WHERE vs HAVING**: フィルタのタイミングによるパフォーマンス差
- **GROUP BYとインデックス**: なぜGROUP BY結果にインデックスが効かないのか
- **複合インデックスの効果**: WHERE + GROUP BYの両方に効くインデックス設計
- **実行計画の読み方**: Rows Removed by Filterから処理効率を判断

## ユースケース

ECサイトで「**店舗ごと、日ごとの売上**」を集計する場面を想定します：
- `GROUP BY shop_id, order_day`
- 発送日（`ship_day`）で期間絞り込み

## 検証手順

### 事前準備: データ確認

まず、データがどのように分布しているか確認しましょう：

```sql
-- orders テーブルの件数確認
SELECT COUNT(*) FROM orders;

-- 月別の注文件数（偏りを確認）
SELECT
  TO_CHAR(order_day, 'YYYY-MM') as month,
  COUNT(*) as order_count,
  ROUND(COUNT(*) * 100.0 / SUM(COUNT(*)) OVER (), 2) as percentage
FROM orders
GROUP BY TO_CHAR(order_day, 'YYYY-MM')
ORDER BY month;
```

**期待される結果:**
- 1-10月: 各月約20,000件（合計40%）
- 11-12月: 各月約150,000件（合計60%）

---

### ステップ1: HAVING での期間絞り込み（非効率な方法）

まず、**HAVING** を使って集計後にフィルタする方法を試します。これは **非効率** です。

```sql
-- 店舗ごと、日ごとの売上集計（12月のみ対象）
-- HAVING で ship_day を絞り込む（悪い例）
EXPLAIN ANALYZE
SELECT
  o.shop_id,
  o.order_day,
  COUNT(*) as order_count,
  SUM(i.price) as total_sales
FROM orders o
JOIN items i ON o.id = i.order_id
GROUP BY o.shop_id, o.order_day
HAVING MIN(o.ship_day) >= DATE '2024-12-01'
   AND MAX(o.ship_day) <= DATE '2024-12-31'
ORDER BY total_sales DESC
LIMIT 10;
```

**結果:**

```
Execution Time: 686.8ms
```

**実行計画のポイント:**
- **Parallel Seq Scan** on orders: 全500,000件をスキャン
- **Parallel Hash Join**: 全データ（2,000,000件のitems）を結合してから集計
- **Filter**: GROUP BY **後** にHAVINGで絞り込み
- **Rows Removed by Filter: 73,405グループ**（大部分のグループが破棄される！）
  - 約10万グループを生成 → 25,595グループだけが条件に合致

**なぜ遅いのか:**
1. 全注文データ（500,000件）をスキャン
2. 全明細データ（2,000,000件）と結合
3. shop_id × order_day でGROUP BY（数万グループ）
4. **最後に** HAVINGでフィルタ（大部分が不要だったのに！）

**HAVINGの問題点:**
- `MIN(o.ship_day)` や `MAX(o.ship_day)` は集計後に計算される
- 集計前にフィルタできないため、無駄な処理が多い

---

### ステップ2: ship_day にインデックス作成

HAVINGで使っている `ship_day` にインデックスを作成してみます：

```sql
CREATE INDEX idx_orders_ship_day ON orders(ship_day);
ANALYZE orders;
```

同じクエリを再実行：

```sql
EXPLAIN ANALYZE
SELECT
  o.shop_id,
  o.order_day,
  COUNT(*) as order_count,
  SUM(i.price) as total_sales
FROM orders o
JOIN items i ON o.id = i.order_id
GROUP BY o.shop_id, o.order_day
HAVING MIN(o.ship_day) >= DATE '2024-12-01'
   AND MAX(o.ship_day) <= DATE '2024-12-31'
ORDER BY total_sales DESC
LIMIT 10;
```

**結果:**

```
Execution Time: 684.3ms（ほぼ変わらず！）
```

**驚きの事実: インデックスが効かない！**

実行計画も全く同じで、`ship_day` のインデックスは完全に無視されています。

**なぜインデックスが効かないのか:**

HAVINGは **GROUP BY の後** に実行されます。実行順序を見てみましょう：

```
1. FROM orders o
2. JOIN items i ...
3. GROUP BY o.shop_id, o.order_day    ← ここで集計
4. HAVING MIN(o.ship_day) ...          ← ここでフィルタ（集計後！）
```

**問題点:**
- `MIN(o.ship_day)` は集計結果から計算される
- 集計結果は **メモリ上の一時データ** であり、インデックスは効かない
- インデックスはテーブルの物理データに対してのみ有効

**図解:**

```
[ordersテーブル]  ← インデックスが効く範囲
  ↓
[全件スキャン + JOIN]
  ↓
[GROUP BY で集計]
  ↓
[集計結果（メモリ上）] ← ここにはインデックスが効かない
  ↓
[HAVING でフィルタ]
```

**例えで理解:**
- 図書館（テーブル）には索引（インデックス）がある
- でも、本を借りて自宅（メモリ）で整理した後の本には、図書館の索引は使えない
- HAVINGは「自宅で整理した後」のフィルタなので、索引が使えない

---

### ステップ3: WHERE での期間絞り込み（正しい方法）

**WHERE** を使って、集計 **前** にフィルタしましょう：

```sql
EXPLAIN ANALYZE
SELECT
  o.shop_id,
  o.order_day,
  COUNT(*) as order_count,
  SUM(i.price) as total_sales
FROM orders o
JOIN items i ON o.id = i.order_id
WHERE o.ship_day BETWEEN DATE '2024-12-01' AND DATE '2024-12-31'
GROUP BY o.shop_id, o.order_day
ORDER BY total_sales DESC
LIMIT 10;
```

**結果:**

```
Execution Time: 295.5ms（2.3倍高速化！）
```

**実行計画のポイント:**
- **Parallel Seq Scan** on orders
  - **注意**: インデックスが存在しない場合でも、WHEREで絞り込みが行われます
- **Filter**: `ship_day BETWEEN '2024-12-01' AND '2024-12-31'`
- **Rows Removed by Filter: 115,847行/worker** （各ワーカーごとに絞り込み）
- 処理対象が約152,458件に削減（元の500,000件から）

**なぜ速いのか:**

```
1. FROM orders o
2. WHERE o.ship_day BETWEEN ...   ← ここでフィルタ（集計前に絞り込み！）
3. JOIN items i ...               ← 絞り込まれた15万件だけを処理
4. GROUP BY o.shop_id, o.order_day
```

**図解:**

```
[ordersテーブル: 500,000件]
  ↓
[WHERE でフィルタ] ← 集計前に絞り込み！
  ↓ (500,000件 → 152,458件)
[絞り込まれたデータ + JOIN]
  ↓ (約610,000件のitems)
[GROUP BY で集計] ← 処理量が大幅削減！
```

**重要なポイント: 選択率とインデックス**

このケースでは12月のデータが全体の約30%（152,458件 / 500,000件）を占めます。
PostgreSQLのプランナーは、**選択率が高い場合（約20-30%以上）、Seq Scanの方が効率的**と判断します。

- **選択率が低い場合**（5%未満など）: Index Scan が使われる
- **選択率が高い場合**（30%など）: Seq Scan が使われる（今回のケース）

**WHEREの本質は「フィルタのタイミング」であり、「インデックスを使うこと」ではありません。**
集計前に絞り込むことで、無駄な処理を削減できるのが重要です。

**改善点の比較:**

| ステップ | フィルタ方法 | インデックス | フィルタ対象 | 実行時間 | 改善率 |
|---------|------------|------------|-------------|---------|--------|
| ステップ1 | HAVING | なし | 73,405グループ破棄 | 686.8ms | ベースライン |
| ステップ2 | HAVING | ship_day | 73,405グループ破棄 | 684.3ms | 0.4%（誤差） |
| **ステップ3** | **WHERE** | **なし** | **347,542行除外** | **295.5ms** | **2.3倍高速** |

**重要な発見:**
1. **WHERE vs HAVING**: フィルタのタイミングが決定的に重要（2.3倍の差）
2. **HAVINGにインデックスは効かない**: 集計結果はメモリ上の一時データ
3. **WHEREはインデックスなしでも高速**: 集計前に絞り込むことが本質

---

## 学習ポイント

### 1. WHERE vs HAVING の使い分け

| | WHERE | HAVING |
|---|-------|--------|
| **実行タイミング** | 集計前（行レベル） | 集計後（グループレベル） |
| **インデックス** | 効く場合がある ⚠️ | 効かない ❌ |
| **用途** | 行をフィルタ | 集計結果をフィルタ |
| **パフォーマンス** | 高速（早期に絞り込み） | 低速（全データ処理後フィルタ） |

**注**: WHEREでもインデックスが使われるかは選択率に依存します（詳細は後述）。

### 2. GROUP BY とインデックスの関係

- **GROUP BY自体** にはインデックスが効く（ソート効率化）
- **GROUP BYの結果**（集計値）にはインデックスが効かない
- HAVINGは集計結果を見るので、インデックスが使えない

### 3. クエリ最適化の原則

1. **可能な限りWHEREで絞り込む**: 早い段階でデータを減らす
2. **HAVINGは集計結果のフィルタにのみ使う**: 例: `HAVING COUNT(*) > 10`, `HAVING SUM(price) > 100000`
3. **フィルタのタイミングが最重要**: インデックスの有無より、WHERE/HAVINGの使い分けが決定的
4. **実測で判断する**: EXPLAIN ANALYZEで実行計画を確認し、推測ではなく実測で最適化

### 4. 実行計画から見抜くポイント

- **Seq Scan vs Index Scan**:
  - Seq Scanは必ずしも悪くない（選択率が高い場合は効率的）
  - 選択率30%の場合、Seq Scanが正しい選択
- **Rows Removed by Filter**: フィルタの効率を示す重要指標
  - **WHERE**: 行レベルで除外（例: 347,542行除外）
  - **HAVING**: グループレベルで除外（例: 73,405グループ破棄）
  - この値が大きい場合、フィルタのタイミングを見直す
- **Filter条件の位置**:
  - WHERE: 集計前のフィルタ（効率的）
  - HAVING: 集計後のフィルタ（非効率）

### 5. よくある間違い

```sql
-- ❌ 悪い例: HAVINGで行レベルの条件を書く
SELECT shop_id, order_day, COUNT(*), SUM(price)
FROM orders o
JOIN items i ON o.id = i.order_id
GROUP BY shop_id, order_day
HAVING o.ship_day >= DATE '2024-12-01';  -- ←これはエラー！（集計後にo.ship_dayは存在しない）

-- ❌ 悪い例: HAVINGでMIN/MAXを使って行レベル条件を書く
SELECT shop_id, order_day, COUNT(*), SUM(price)
FROM orders o
JOIN items i ON o.id = i.order_id
GROUP BY shop_id, order_day
HAVING MIN(o.ship_day) >= DATE '2024-12-01';  -- 動くが非効率！

-- ✅ 良い例: WHEREで行レベルの条件を書く
SELECT shop_id, order_day, COUNT(*), SUM(price)
FROM orders o
JOIN items i ON o.id = i.order_id
WHERE o.ship_day >= DATE '2024-12-01'  -- ←これが正しい！
GROUP BY shop_id, order_day;
```

```sql
-- ✅ HAVINGの正しい使い方: 集計結果のフィルタ
SELECT shop_id, order_day, COUNT(*) as order_count, SUM(price) as total_sales
FROM orders o
JOIN items i ON o.id = i.order_id
WHERE o.ship_day >= DATE '2024-12-01'  -- 行フィルタ
GROUP BY shop_id, order_day
HAVING COUNT(*) >= 10;  -- 集計結果フィルタ（10件以上の注文がある日のみ）
```

### 6. パフォーマンスチューニングの思考法

1. **EXPLAIN ANALYZEを必ず実行**: 推測ではなく実測で判断
2. **フィルタのタイミングを確認**: WHERE（集計前）とHAVING（集計後）の使い分けが最重要
3. **Rows Removed by Filterに注目**:
   - HAVINGで大量のグループが破棄されている → WHEREに移行できないか検討
   - WHEREで大量の行が除外されている → 正常（早期フィルタの証拠）
4. **Seq Scanは文脈で判断**: 選択率が高い場合はSeq Scanが効率的
5. **インデックスを追加したら**: ANALYZEを実行して統計情報を更新

### 7. MIN/MAX in HAVING の落とし穴

このテストケースの重要なポイント：

```sql
-- これは動くが、非効率！
HAVING MIN(ship_day) >= '2024-12-01' AND MAX(ship_day) <= '2024-12-31'
```

**なぜ非効率なのか:**
1. 全データをGROUP BYして、各グループの `MIN(ship_day)` と `MAX(ship_day)` を計算
2. その後、条件に合わないグループを破棄
3. 結果的に、大部分の処理が無駄になる

**正しいアプローチ:**
```sql
-- ship_day自体で絞り込む
WHERE ship_day BETWEEN '2024-12-01' AND '2024-12-31'
```

**なぜ効率的なのか:**
1. 最初にship_dayでフィルタ（インデックスが効く）
2. 絞り込まれたデータだけをGROUP BY
3. 無駄な処理がない

---

## 次のステップ

このテストケースをマスターしたら、次のトピックに進みましょう：

### より高度なトピック

1. **HashAggregate vs GroupAggregate**: 集計方式の違いと最適化
2. **パーティショニング**: 大量データを期間で分割して検索を高速化
3. **ウィンドウ関数**: ROW_NUMBER() や RANK() とインデックスの関係
4. **CTEとMaterialization**: WITH句の最適化
5. **UNION vs UNION ALL**: 重複排除のコスト

### 実践的な課題

1. **選択率の違いを検証**: WHERE条件を1週間（選択率1%未満）に変えて、インデックスの効果を確認
   - `WHERE ship_day BETWEEN '2024-12-01' AND '2024-12-07'`
   - 選択率が低い場合、Index Scanが使われるか？

2. **別の期間で検証**: WHERE条件を11月に変えて、選択率30%の場合と比較

3. **店舗IDでの絞り込み**: `WHERE shop_id = 100` のような選択率の低い条件でインデックスの効果を確認

4. **複合条件**: `WHERE shop_id < 100 AND ship_day >= ...` で選択率を調整し、プランナーの判断を観察

---

## 参考リソース

- [PostgreSQL公式: EXPLAIN](https://www.postgresql.org/docs/current/using-explain.html)
- [PostgreSQL公式: Indexes](https://www.postgresql.org/docs/current/indexes.html)
- [PostgreSQL公式: Query Planning](https://www.postgresql.org/docs/current/runtime-config-query.html)
- [PostgreSQL公式: GROUP BY](https://www.postgresql.org/docs/current/queries-table-expressions.html#QUERIES-GROUP)
