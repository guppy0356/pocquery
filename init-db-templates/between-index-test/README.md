# BETWEEN Index Test - BETWEEN句とインデックス

## データ構成

### テーブル構造

```sql
CREATE TABLE orders (
  id SERIAL PRIMARY KEY,
  user_id INT NOT NULL,
  product_id INT NOT NULL,
  amount INT NOT NULL,
  status TEXT NOT NULL,
  created_at TIMESTAMP NOT NULL
);
```

### データ量と分布

- **総件数**: 500,000件の注文データ
- **期間**: 過去1年間
- **時系列の偏り**:
  - 直近1ヶ月: 250,000件（50%）
  - 1-3ヶ月前: 125,000件（25%）
  - 3-6ヶ月前: 75,000件（15%）
  - 6-12ヶ月前: 50,000件（10%）
- **ステータス分布**:
  - completed: 70%
  - pending: 20%
  - cancelled: 10%

### インデックス

- 初期状態: PRIMARY KEY (id) のみ
- 検証中に created_at や複合インデックスを追加

## 検証内容

このテストケースでは、以下を学べます：

1. **BETWEEN句でのインデックスの効果**
   - 日時範囲検索でインデックスが有効に働くか
   - Seq Scan vs Index Scan / Bitmap Index Scan

2. **範囲の広さによるパフォーマンス変化**
   - 狭い範囲（1週間）: Index Scanが効率的
   - 広い範囲（6ヶ月）: Seq Scanの方が速い場合も

3. **複合インデックスでの最適化**
   - WHERE created_at BETWEEN ... AND status = '...'
   - インデックスのカラム順序の重要性

4. **時系列データの特性**
   - データの偏りが実行計画に与える影響
   - 最新データへのアクセスが多い場合の最適化

## 検証手順

### 事前確認: データの分布を確認

```sql
-- データの総件数
SELECT COUNT(*) FROM orders;

-- 期間ごとのデータ分布
SELECT
  CASE
    WHEN created_at >= NOW() - INTERVAL '30 days' THEN '直近1ヶ月'
    WHEN created_at >= NOW() - INTERVAL '90 days' THEN '1-3ヶ月前'
    WHEN created_at >= NOW() - INTERVAL '180 days' THEN '3-6ヶ月前'
    ELSE '6-12ヶ月前'
  END as period,
  COUNT(*) as count,
  ROUND(COUNT(*) * 100.0 / 500000, 1) as percentage
FROM orders
GROUP BY period
ORDER BY MIN(created_at) DESC;

-- ステータス別の分布
SELECT
  status,
  COUNT(*) as count,
  ROUND(COUNT(*) * 100.0 / 500000, 1) as percentage
FROM orders
GROUP BY status
ORDER BY count DESC;
```

**期待される結果:**
- 総件数: 500,000件
- 直近1ヶ月: 約250,000件（50%）
- completed: 約350,000件（70%）

---

### ステップ1: インデックスなしでBETWEEN検索

まず、インデックスがない状態で直近1週間のデータを検索します。

```sql
EXPLAIN ANALYZE
SELECT
  id,
  user_id,
  amount,
  status,
  created_at
FROM orders
WHERE created_at BETWEEN NOW() - INTERVAL '7 days' AND NOW()
ORDER BY created_at DESC
LIMIT 100;
```

**期待される結果:**
- **Seq Scan** が使われる
- 500,000件すべてをスキャン
- `Rows Removed by Filter`: 約465,000件（直近1週間以外のデータ）
- 実行時間: 100-200ms程度（データ量が多いため）

**実行計画のポイント:**
```
Limit
  -> Sort
       -> Seq Scan on orders
            Filter: (created_at >= ... AND created_at <= ...)
            Rows Removed by Filter: ~465000
```

インデックスがないため、PostgreSQLは全行をスキャンして条件に合う行だけを抽出します。

---

### ステップ2: created_atにインデックスを追加

```sql
CREATE INDEX idx_orders_created_at ON orders(created_at);
```

インデックス作成後、統計情報を更新：

```sql
ANALYZE orders;
```

---

### ステップ3: BETWEEN検索が高速化されることを確認

同じクエリを再実行します。

```sql
EXPLAIN ANALYZE
SELECT
  id,
  user_id,
  amount,
  status,
  created_at
FROM orders
WHERE created_at BETWEEN NOW() - INTERVAL '7 days' AND NOW()
ORDER BY created_at DESC
LIMIT 100;
```

**期待される改善:**
- **Index Scan** または **Bitmap Index Scan** が使われる
- スキャンする行数が大幅に減少（~35,000件 → 実際にマッチする件数のみ）
- 実行時間: 10-30ms程度（5-10倍高速化）

**実行計画のポイント:**
```
Limit
  -> Index Scan Backward using idx_orders_created_at on orders
       Index Cond: (created_at >= ... AND created_at <= ...)
```

ORDER BY created_at DESC と BETWEEN の条件が同じカラムなので、PostgreSQLはインデックスを逆順にスキャンするだけで結果を得られます。

---

### ステップ4: 範囲の広さによる実行計画の変化

#### 4-1. 狭い範囲（1週間）- Index Scanが効率的

```sql
EXPLAIN ANALYZE
SELECT COUNT(*)
FROM orders
WHERE created_at BETWEEN NOW() - INTERVAL '7 days' AND NOW();
```

**期待される結果:**
- Index Scan または Bitmap Index Scan
- 約35,000件をスキャン（7%程度）
- 実行時間: 10-20ms

#### 4-2. 広い範囲（6ヶ月）- Seq Scanになる可能性

```sql
EXPLAIN ANALYZE
SELECT COUNT(*)
FROM orders
WHERE created_at BETWEEN NOW() - INTERVAL '180 days' AND NOW();
```

**期待される結果:**
- 場合によっては **Seq Scan** に戻る
- 約450,000件をスキャン（90%）
- PostgreSQLのオプティマイザは「大部分の行を読む場合、インデックスより全表スキャンの方が速い」と判断

**なぜSeq Scanになるのか:**
- インデックススキャンは「インデックスを読む」→「テーブルを読む」の2段階
- 大量の行を読む場合、ランダムアクセスのコストが高い
- 全表を順次読む方が効率的になる

#### 4-3. 中程度の範囲（1ヶ月）

```sql
EXPLAIN ANALYZE
SELECT COUNT(*)
FROM orders
WHERE created_at BETWEEN NOW() - INTERVAL '30 days' AND NOW();
```

**期待される結果:**
- **Bitmap Index Scan** が使われる可能性が高い
- 約250,000件（50%）
- Bitmap Scanは「インデックスで対象行を特定」→「効率的にテーブルを読む」の中間的手法

---

### ステップ5: 複合条件での最適化

#### 5-1. status条件を追加

```sql
EXPLAIN ANALYZE
SELECT
  id,
  user_id,
  amount,
  created_at
FROM orders
WHERE created_at BETWEEN NOW() - INTERVAL '7 days' AND NOW()
  AND status = 'completed'
ORDER BY created_at DESC
LIMIT 100;
```

**期待される結果:**
- Index Scanでcreated_atを絞り込み
- その後、statusでフィルタ（Rows Removed by Filter: 約10,500件）
- 実行時間: やや遅くなる（フィルタのコスト）

**実行計画のポイント:**
```
Limit
  -> Index Scan Backward using idx_orders_created_at on orders
       Index Cond: (created_at >= ... AND created_at <= ...)
       Filter: (status = 'completed')
       Rows Removed by Filter: ~10500
```

#### 5-2. 複合インデックスを追加

```sql
CREATE INDEX idx_orders_created_at_status ON orders(created_at, status);
```

再度クエリを実行：

```sql
EXPLAIN ANALYZE
SELECT
  id,
  user_id,
  amount,
  created_at
FROM orders
WHERE created_at BETWEEN NOW() - INTERVAL '7 days' AND NOW()
  AND status = 'completed'
ORDER BY created_at DESC
LIMIT 100;
```

**期待される改善:**
- 複合インデックスを使用（idx_orders_created_at_status）
- statusのフィルタがインデックス内で完結（Rows Removed by Filter: 0）
- 実行時間: さらに高速化

**実行計画のポイント:**
```
Limit
  -> Index Scan Backward using idx_orders_created_at_status on orders
       Index Cond: (created_at >= ... AND created_at <= ... AND status = 'completed')
```

---

### ステップ6: インデックスの使い分け

インデックスが複数ある場合、PostgreSQLはどちらを選ぶか確認します。

```sql
-- 現在のインデックスを確認
\di orders*

-- created_atのみの条件
EXPLAIN ANALYZE
SELECT COUNT(*)
FROM orders
WHERE created_at BETWEEN NOW() - INTERVAL '7 days' AND NOW();

-- created_at + statusの条件
EXPLAIN ANALYZE
SELECT COUNT(*)
FROM orders
WHERE created_at BETWEEN NOW() - INTERVAL '7 days' AND NOW()
  AND status = 'completed';
```

**期待される結果:**
- created_atのみ: どちらのインデックスも使える（オプティマイザが選択）
- created_at + status: 複合インデックスが選ばれる（より効率的）

---

## 学習ポイント

### 1. BETWEENはインデックスフレンドリー

BETWEENは範囲検索ですが、インデックスを効率的に使えます。特にB-treeインデックスは範囲検索に最適化されています。

### 2. ORDER BYとBETWEENの組み合わせ

```sql
WHERE created_at BETWEEN ... ORDER BY created_at DESC
```

このパターンでは、インデックスを逆順にスキャンするだけで結果が得られるため、非常に効率的です。

### 3. 範囲の広さによる実行計画の変化

- **狭い範囲（<10%）**: Index Scanが効率的
- **中程度の範囲（10-50%）**: Bitmap Index Scanが選ばれやすい
- **広い範囲（>50%）**: Seq Scanの方が速い場合も

これはPostgreSQLのコストベースオプティマイザの賢さを示しています。

### 4. 複合インデックスの効果

```sql
CREATE INDEX idx ON orders(created_at, status);
```

このインデックスは：
- `WHERE created_at BETWEEN ... AND status = '...'` で最適
- カラムの順序が重要: (created_at, status) の順が正しい
- `WHERE status = '...'` だけでは使えない（先頭カラムが必要）

### 5. 時系列データの特性

直近のデータに偏りがある場合：
- 直近期間の検索が多い → インデックスが非常に有効
- 部分インデックスも検討できる:
  ```sql
  CREATE INDEX idx_recent ON orders(created_at)
  WHERE created_at >= NOW() - INTERVAL '90 days';
  ```

### 6. トレードオフ

**インデックスのメリット:**
- 範囲検索が高速化
- ORDER BYと組み合わせると効率的

**デメリット:**
- インデックスのサイズ（ディスク容量）
- INSERT/UPDATE時のオーバーヘッド
- 広範囲の検索では逆効果の場合も

---

## 次のステップ

### さらなる最適化

1. **パーティショニング**
   - created_atで月次パーティション
   - 古いデータへのアクセスが少ない場合に有効

2. **カバリングインデックス**
   ```sql
   CREATE INDEX idx_covering ON orders(created_at, status, user_id, amount);
   ```
   - Index Only Scanが可能になる
   - テーブルアクセスが不要

3. **部分インデックス**
   ```sql
   CREATE INDEX idx_completed ON orders(created_at)
   WHERE status = 'completed';
   ```
   - 特定の条件でのみインデックスを作成
   - インデックスサイズの削減

### 関連するテストケース

- **composite-index-test**: 複合インデックスのカラム順序
- **nested-loop-test**: JOINでのインデックス活用

---

## まとめ

BETWEENは一見「範囲検索で遅そう」に見えますが、適切なインデックスがあれば非常に効率的です。特に時系列データでは、インデックスを活用した範囲検索が頻繁に使われます。

重要なのは：
- 検索範囲の広さを考慮する
- ORDER BYとの組み合わせを意識する
- 複合条件では複合インデックスを検討する
- PostgreSQLのオプティマイザを信頼する

実際のアプリケーションでは、アクセスパターンを分析して最適なインデックス戦略を立てましょう。
